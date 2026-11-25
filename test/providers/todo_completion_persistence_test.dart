// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/domain_event_bus.dart';
import 'package:duoyi/models/recurrence.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Store store;
  late TodoProvider provider;
  late _Audit audit;
  late SharedPreferences prefs;
  late StreamSubscription<DomainEvent> subscription;
  late List<DomainEvent> events;
  var markers = 0;
  var notifications = 0;

  Future<void> seed(List<TodoItem> items) async {
    final data = jsonEncode(items.map((item) => item.toJson()).toList());
    SharedPreferences.setMockInitialValues({'todos': data});
    store = _Store({'flutter.todos': data});
    SharedPreferencesStorePlatform.instance = store;
    prefs = await SharedPreferences.getInstance();
    audit = _Audit();
    provider = TodoProvider()..timeAudit = audit;
    await provider.loadFromStorage();
    markers = 0;
    notifications = 0;
    provider.onLocalMutationPersisted = () => markers++;
    provider.addListener(() => notifications++);
    events = [];
    subscription = DomainEventBus.instance.events.listen(events.add);
  }

  setUp(() => seed([_recurring(), TodoItem(id: 'other', title: 'unrelated')]));
  tearDown(() async {
    await AccountPreferenceWrites.drain();
    await subscription.cancel();
    provider.dispose();
    audit.dispose();
    SharedPreferences.setMockInitialValues({});
  });

  for (final failure in ['false', 'throw']) {
    test(
      '$failure completion write leaves no events or successor and retries once',
      () async {
        final original = prefs.getString('todos');
        store.failure = failure;
        await expectLater(
          provider.completeTodos(['recurring']),
          throwsStateError,
        );
        expect(provider.todos.first.isCompleted, isFalse);
        expect(provider.todos, hasLength(2));
        expect(prefs.getString('todos'), original);
        expect(events, isEmpty);
        expect(markers, 0);
        expect(notifications, 0);
        expect(audit.calls, 0);

        expect(await provider.completeTodos(['recurring']), 1);
        expect(provider.todos.first.isCompleted, isTrue);
        expect(provider.todos, hasLength(3));
        expect(_stored(prefs).where((item) => item.isCompleted), hasLength(1));
        expect(events.map((event) => event.objectId), ['recurring']);
        expect(markers, 1);
        expect(audit.calls, 1);
        final writes = store.writes;
        expect(await provider.completeTodos(['recurring']), 0);
        expect(store.writes, writes);
        expect(provider.todos, hasLength(3));
        expect(audit.calls, 1);
      },
    );
  }

  test('real shared viewer cannot complete; private owner still can', () async {
    await subscription.cancel();
    provider.dispose();
    audit.dispose();
    await seed([
      TodoItem(id: 'viewer', title: 'shared', workspaceId: 'unknown-shared'),
      TodoItem(id: 'owner', title: 'private'),
    ]);
    final shares = ShareProvider();
    addTearDown(shares.dispose);
    provider.canEditWorkspace = shares.canEdit;
    await expectLater(provider.completeTodos(['viewer']), throwsStateError);
    expect(store.writes, 0);
    expect(events, isEmpty);
    expect(provider.todos.first.isCompleted, isFalse);
    expect(await provider.completeTodos(['owner']), 1);
    expect(provider.todos.first.isCompleted, isFalse);
    expect(provider.todos.last.isCompleted, isTrue);
    expect(events.map((event) => event.objectId), ['owner']);
  });

  test(
    'permission revoked during platform write rolls back and can retry after grant',
    () async {
      var allowed = true;
      provider.canEditWorkspace = (_) => allowed;
      final original = prefs.getString('todos');
      store.block = true;
      final pending = provider.completeTodos(['recurring']);
      await store.entered.future;
      expect(provider.todos.first.isCompleted, isFalse);
      allowed = false;
      store.release.complete();
      expect(await pending, 0);
      expect(prefs.getString('todos'), original);
      expect(provider.todos, hasLength(2));
      expect(events, isEmpty);
      expect(markers, 0);
      expect(audit.calls, 0);
      allowed = true;
      expect(await provider.completeTodos(['recurring']), 1);
    },
  );

  test(
    'account invalidation during completion does not publish the old account',
    () async {
      final original = prefs.getString('todos');
      store.block = true;
      final pending = provider.completeTodos(['recurring']);
      await store.entered.future;
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      store.release.complete();
      expect(await pending, 0);
      expect(prefs.getString('todos'), original);
      expect(provider.todos.first.isCompleted, isFalse);
      expect(provider.todos, hasLength(2));
      expect(events, isEmpty);
      expect(markers, 0);
      expect(audit.calls, 0);
    },
  );

  test(
    'unrelated edit during staged completion survives in memory and storage',
    () async {
      store.block = true;
      final pending = provider.completeTodos(['recurring']);
      await store.entered.future;
      final other = provider.todos.firstWhere((todo) => todo.id == 'other');
      final edit = provider.updateTodo(
        'other',
        other.copyWith(title: 'edited while saving'),
      );
      await Future<void>.delayed(Duration.zero);
      store.release.complete();
      expect(await pending, 1);
      await edit;
      expect(
        provider.todos.firstWhere((todo) => todo.id == 'other').title,
        'edited while saving',
      );
      expect(
        _stored(prefs).firstWhere((todo) => todo.id == 'other').title,
        'edited while saving',
      );
      expect(
        _stored(prefs).firstWhere((todo) => todo.id == 'recurring').isCompleted,
        isTrue,
      );
      expect(provider.todos, hasLength(3));
      expect(
        events.where((event) => event.type == DomainEventType.todoCompleted),
        hasLength(1),
      );
    },
  );

  test('repeated tap while saving cannot create a second successor', () async {
    store.block = true;
    final pending = provider.completeTodos(['recurring']);
    await store.entered.future;
    expect(await provider.completeTodos(['recurring']), 0);
    expect(events, isEmpty);
    expect(provider.todos, hasLength(2));
    store.release.complete();
    expect(await pending, 1);
    expect(provider.todos, hasLength(3));
    expect(events, hasLength(1));
    expect(store.writes, 1);
  });

  for (final action in ['reopen', 'delete']) {
    test('$action invalidates a pending secondary time record', () async {
      audit.rejectNext = true;
      expect(await provider.completeTodos(['recurring']), 1);
      expect(audit.calls, 1);
      if (action == 'reopen') {
        expect(await provider.reopenTodos(['recurring']), 1);
      } else {
        expect(await provider.deleteTodos(['recurring']), 1);
      }
      expect(await provider.retryPendingCompletionTimeRecords(), isTrue);
      expect(audit.calls, 1);
      expect(await provider.retryPendingCompletionTimeRecords(), isTrue);
      expect(audit.calls, 1);
    });
  }
}

TodoItem _recurring() => TodoItem(
  id: 'recurring',
  title: 'repeat',
  date: DateTime(2026, 10, 1),
  recurrence: const RecurrenceRule(frequency: RecurrenceFrequency.daily),
);

List<TodoItem> _stored(SharedPreferences prefs) =>
    (jsonDecode(prefs.getString('todos')!) as List)
        .map(
          (item) => TodoItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();

class _Audit extends TimeAuditProvider {
  int calls = 0;
  bool rejectNext = false;
  @override
  Future<void> recordTodoCompletion(
    TodoItem todo, {
    DateTime? completedAt,
  }) async {
    calls++;
    if (rejectNext) {
      rejectNext = false;
      throw StateError('secondary time record rejected');
    }
  }
}

class _Store extends InMemorySharedPreferencesStore {
  _Store(super.data) : super.withData();
  String? failure;
  bool block = false;
  int writes = 0;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key != 'flutter.todos') return super.setValue(valueType, key, value);
    writes++;
    if (block) {
      block = false;
      entered.complete();
      await release.future;
    }
    final mode = failure;
    failure = null;
    final result = await super.setValue(valueType, key, value);
    if (mode == 'false') return false;
    if (mode == 'throw') throw StateError('synthetic failed completion write');
    return result;
  }
}
