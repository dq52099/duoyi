// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/domain_event_bus.dart';
import 'package:duoyi/models/recurrence.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../test_support/recording_reminder_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'notification account reset stops reminders when automatic recording is disabled',
    () async {
      final todo = TodoItem(
        id: 'post-commit-account-reset',
        title: 'Complete before the account changes',
        date: DateTime(2026, 10, 1),
        timeTargetSeconds: 1800,
      );
      final fixture = await _Fixture.seed(todo);
      addTearDown(fixture.close);
      var invalidated = false;
      fixture.todos.addListener(() {
        if (invalidated ||
            !fixture.todos.todos.any(
              (item) => item.id == todo.id && item.isCompleted,
            )) {
          return;
        }
        // This runs synchronously from completion's _notify(), after its
        // durable write and event. The same provider now belongs to new data.
        invalidated = true;
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        fixture.todos.resetLocalState();
      });

      final changed = await fixture.todos.completeTodos([
        todo.id,
      ], recordCompletionTime: false);

      expect(invalidated, isTrue);
      expect(changed, 0, reason: 'the originating account was invalidated');
      expect(fixture.todos.todos, isEmpty);
      expect(fixture.todoMarkers, 1);
      expect(fixture.completionEvents, hasLength(1));
      expect(fixture.completionEvents.single.objectId, todo.id);
      final stored = fixture.storedTodos.single;
      expect(stored.id, todo.id);
      expect(stored.isCompleted, isTrue);
      expect(stored.completedAt, isNotNull);
      expect(fixture.store.todoWrites, 1);
      expect(
        fixture.scheduler.todoSyncs,
        isEmpty,
        reason: 'the old action must not schedule the replacement account',
      );
      expect(fixture.audit.entries, isEmpty);
      expect(fixture.store.auditWriteAttempts, 0);
    },
  );

  test(
    'rejected time recording preserves completion success and retries only the record once',
    () async {
      final todo = TodoItem(
        id: 'post-commit-record-retry',
        title: 'Recurring task with an automatic duration',
        date: DateTime(2026, 10, 1, 9),
        dueDate: DateTime(2026, 10, 1, 18),
        timeTargetSeconds: 1800,
        recurrence: const RecurrenceRule(
          frequency: RecurrenceFrequency.daily,
          maxOccurrences: 2,
        ),
      );
      final fixture = await _Fixture.seed(todo);
      addTearDown(fixture.close);
      fixture.store.rejectNextAuditWrite = true;

      // Use the real TimeAuditProvider transaction, rejecting its platform
      // acknowledgement after the Todo's own durable commit has succeeded.
      expect(await fixture.todos.completeTodos([todo.id]), 1);
      expect(fixture.store.auditWriteAttempts, 1);
      expect(fixture.audit.entries, isEmpty);
      expect(fixture.auditMarkers, 0);
      expect(fixture.prefs.getStringList(TimeAuditProvider.storageKey), isNull);
      expect(fixture.todos.todos, hasLength(2));
      final completed = fixture.todos.todos.singleWhere(
        (item) => item.id == todo.id,
      );
      final successor = fixture.todos.todos.singleWhere(
        (item) => item.id != todo.id,
      );
      expect(completed.isCompleted, isTrue);
      expect(completed.completedAt, isNotNull);
      expect(successor.isCompleted, isFalse);
      expect(successor.date, DateTime(2026, 10, 2, 9));
      expect(successor.dueDate, DateTime(2026, 10, 2, 18));
      expect(successor.recurrence.maxOccurrences, 1);
      expect(fixture.completionEvents, hasLength(1));
      expect(fixture.todoMarkers, 1);
      expect(fixture.store.todoWrites, 1);
      expect(fixture.scheduler.todoSyncs, hasLength(1));

      final completionAt = completed.completedAt!;
      final todoDiskAfterCompletion = fixture.prefs.getString('todos');
      final todoMemoryAfterCompletion = fixture.todos.todos
          .map((item) => item.toJson())
          .toList();
      expect(
        fixture.storedTodos.map((item) => item.toJson()).toList(),
        todoMemoryAfterCompletion,
      );

      // A second completion request stays a no-op. Recovery is the separate
      // instance API; its bool means no eligible recording remains pending.
      expect(await fixture.todos.completeTodos([todo.id]), 0);
      expect(fixture.store.auditWriteAttempts, 1);
      expect(await fixture.todos.retryPendingCompletionTimeRecords(), isTrue);
      expect(fixture.store.auditWriteAttempts, 2);
      expect(fixture.auditMarkers, 1);
      expect(fixture.audit.entries, hasLength(1));
      final record = fixture.audit.entries.single;
      expect(record.source, TimeEntrySource.todo);
      expect(record.sourceId, todo.id);
      expect(record.endAt, completionAt);
      expect(
        record.startAt,
        completionAt.subtract(const Duration(seconds: 1800)),
      );
      expect(record.durationSeconds, 1800);
      expect(
        record.dedupeKey,
        TimeAuditProvider.todoCompletionDedupeKey(todo.id, completionAt),
      );
      expect(
        jsonDecode(
          fixture.prefs.getStringList(TimeAuditProvider.storageKey)!.single,
        ),
        record.toJson(),
      );

      // Retrying an empty queue must issue no platform write or Todo effects.
      expect(await fixture.todos.retryPendingCompletionTimeRecords(), isTrue);
      expect(fixture.store.auditWriteAttempts, 2);
      expect(fixture.audit.entries, hasLength(1));
      expect(fixture.auditMarkers, 1);
      expect(fixture.completionEvents, hasLength(1));
      expect(fixture.todoMarkers, 1);
      expect(fixture.store.todoWrites, 1);
      expect(fixture.scheduler.todoSyncs, hasLength(1));
      expect(fixture.prefs.getString('todos'), todoDiskAfterCompletion);
      expect(
        fixture.todos.todos.map((item) => item.toJson()).toList(),
        todoMemoryAfterCompletion,
      );
    },
  );
}

class _Fixture {
  _Fixture(this.todos, this.audit, this.scheduler, this.store, this.prefs);

  final TodoProvider todos;
  final TimeAuditProvider audit;
  final RecordingReminderScheduler scheduler;
  final _Store store;
  final SharedPreferences prefs;
  final completionEvents = <DomainEvent>[];
  late final StreamSubscription<DomainEvent> _subscription;
  int todoMarkers = 0;
  int auditMarkers = 0;

  static Future<_Fixture> seed(TodoItem todo) async {
    final payload = jsonEncode([todo.toJson()]);
    SharedPreferences.setMockInitialValues({'todos': payload});
    final store = _Store({'flutter.todos': payload});
    SharedPreferencesStorePlatform.instance = store;
    final prefs = await SharedPreferences.getInstance();
    final audit = TimeAuditProvider();
    final scheduler = RecordingReminderScheduler();
    final todos = TodoProvider()
      ..timeAudit = audit
      ..scheduler = scheduler;
    await todos.loadFromStorage();
    final fixture = _Fixture(todos, audit, scheduler, store, prefs);
    todos.onLocalMutationPersisted = () => fixture.todoMarkers++;
    audit.onLocalMutationPersisted = () => fixture.auditMarkers++;
    fixture._subscription = DomainEventBus.instance.events.listen((event) {
      if (event.type == DomainEventType.todoCompleted &&
          event.objectId == todo.id) {
        fixture.completionEvents.add(event);
      }
    });
    return fixture;
  }

  List<TodoItem> get storedTodos =>
      (jsonDecode(prefs.getString('todos')!) as List)
          .map(
            (raw) => TodoItem.fromJson(Map<String, dynamic>.from(raw as Map)),
          )
          .toList();

  Future<void> close() async {
    await AccountPreferenceWrites.drain();
    await _subscription.cancel();
    todos.dispose();
    audit.dispose();
    SharedPreferences.setMockInitialValues({});
  }
}

class _Store extends InMemorySharedPreferencesStore {
  _Store(super.data) : super.withData();

  bool rejectNextAuditWrite = false;
  int todoWrites = 0;
  int auditWriteAttempts = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.todos') todoWrites++;
    if (key == 'flutter.${TimeAuditProvider.storageKey}') {
      auditWriteAttempts++;
      if (rejectNextAuditWrite) {
        rejectNextAuditWrite = false;
        return false;
      }
    }
    return super.setValue(valueType, key, value);
  }
}
