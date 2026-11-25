// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/domain_event_bus.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Store store;
  late TodoProvider provider;
  late SharedPreferences prefs;
  final created = <String>[];
  StreamSubscription<DomainEvent>? events;
  var persisted = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    prefs = await SharedPreferences.getInstance();
    provider = TodoProvider();
    await provider.loadFromStorage();
    persisted = 0;
    created.clear();
    provider.onLocalMutationPersisted = () => persisted++;
    events = DomainEventBus.instance.events.listen((event) {
      if (event.type == DomainEventType.todoCreated) {
        created.add(event.objectId);
      }
    });
  });
  tearDown(() async {
    await AccountPreferenceWrites.drain();
    await events?.cancel();
    provider.dispose();
  });

  for (final failure in ['false', 'throw', 'writeThenThrow']) {
    test('create $failure cannot publish; retry inserts once', () async {
      store.failure = failure;
      await expectLater(
        provider.addTodoWithResult(_todo('A')),
        throwsA(anything),
      );
      expect(provider.todos, isEmpty);
      expect(_stored(prefs), isEmpty);
      expect(created, isEmpty);
      expect(persisted, 0);
      expect(provider.lastReminderSyncAttemptAt, isNull);
      final retry = await provider.addTodoWithResult(_todo('A'));
      expect(retry, isNotNull);
      expect(provider.todos.map((todo) => todo.id), ['A']);
      expect(_stored(prefs).map((raw) => raw['id']), ['A']);
      expect(created, ['A']);
      expect(persisted, 1);
    });
  }

  test('held create publishes only after acknowledged storage', () async {
    store.holdNext = true;
    final pending = provider.addTodoWithResult(_todo('A'));
    await store.started.future;
    expect(provider.todos, isEmpty);
    expect(created, isEmpty);
    expect(persisted, 0);
    store.release.complete();
    expect(await pending, isNotNull);
    expect(created, ['A']);
    expect(persisted, 1);
    expect(provider.todos.single.id, 'A');
  });

  test('held create invalidated by origin lease rolls disk back', () async {
    var current = true;
    store.holdNext = true;
    final pending = provider.addTodoWithResult(
      _todo('A'),
      canWrite: () => current,
    );
    await store.started.future;
    current = false;
    store.release.complete();
    expect(await pending, isNull);
    expect(provider.todos, isEmpty);
    expect(_stored(prefs), isEmpty);
    expect(created, isEmpty);
    expect(persisted, 0);
    expect(provider.lastReminderSyncAttemptAt, isNull);
  });

  test(
    'account cleanup drains a held create and rollback before clearing',
    () async {
      store.holdNext = true;
      final pending = provider.addTodoWithResult(_todo('A'));
      await store.started.future;
      var cleared = false;
      final cleanup = AccountLocalDataCleaner.clearSharedPreferences().then(
        (_) => cleared = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(cleared, isFalse);
      store.release.complete();
      expect(await pending, isNull);
      await cleanup;
      expect(cleared, isTrue);
      expect(provider.todos, isEmpty);
      await prefs.reload();
      expect(prefs.containsKey('todos'), isFalse);
      expect(created, isEmpty);
    },
  );

  test('held create preserves concurrent edits and queued inserts', () async {
    await provider.addTodo(_todo('existing'));
    store.holdNext = true;
    final pending = provider.addTodoWithResult(_todo('A'));
    await store.started.future;
    final edited = provider.updateTodo(
      'existing',
      provider.todos.single.copyWith(title: 'edited'),
    );
    final added = provider.addTodo(_todo('B'));
    store.release.complete();
    await Future.wait([pending, edited, added]);
    expect(provider.todos.map((todo) => todo.id).toSet(), {
      'existing',
      'A',
      'B',
    });
    expect(
      provider.todos.firstWhere((todo) => todo.id == 'existing').title,
      'edited',
    );
    final stored = _stored(prefs);
    expect(stored.map((raw) => raw['id']).toSet(), {'existing', 'A', 'B'});
    expect(
      stored.singleWhere((raw) => raw['id'] == 'existing')['title'],
      'edited',
    );
  });
}

TodoItem _todo(String id) =>
    TodoItem(id: id, title: '$id task', date: DateTime(2100, 1, 1));
List<Map<String, dynamic>> _stored(SharedPreferences prefs) =>
    (jsonDecode(prefs.getString('todos') ?? '[]') as List)
        .cast<Map<String, dynamic>>();

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData({});
  String? failure;
  bool holdNext = false;
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.todos') {
      final nextFailure = failure;
      failure = null;
      if (nextFailure == 'false') return false;
      if (nextFailure == 'throw') {
        throw StateError('private storage diagnostic');
      }
      if (nextFailure == 'writeThenThrow') {
        await super.setValue(type, key, value);
        throw StateError('private storage diagnostic after disk write');
      }
      if (holdNext) {
        holdNext = false;
        started.complete();
        await release.future;
      }
    }
    return super.setValue(type, key, value);
  }
}
