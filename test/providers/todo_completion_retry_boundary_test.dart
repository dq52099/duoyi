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

const _timeout = Duration(seconds: 3);
const _todoId = 'completion-retry-boundary';
const _auditKey = 'flutter.${TimeAuditProvider.storageKey}';

// Public contracts used here: completeTodos/reopenTodos/deleteTodos return
// Future<int>; retryPendingCompletionTimeRecords returns Future<bool>, where
// false retains an eligible pending record. TodoProvider.timeAudit binds a
// TimeAuditProvider with resetLocalState(), dispose(), isDisposed,
// storageGeneration, entries, and loadFromStorage(). No private hooks or
// overridden recording methods stand in for the real audit transaction.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final action in ['reopen', 'delete']) {
    for (final rejection in ['false', 'throw']) {
      test(
        '$rejection $action acknowledgement preserves pending completion recovery',
        () async {
          final fixture = await _Fixture.seed();
          addTearDown(fixture.close);
          await fixture.leaveRecordPending();

          fixture.store.nextTodoFailure = rejection;
          final mutation = action == 'reopen'
              ? fixture.todos.reopenTodos([_todoId])
              : fixture.todos.deleteTodos([_todoId]);
          await expectLater(mutation, throwsStateError);

          // The platform actually stored the rejected candidate. Refresh the
          // legacy cache to prove rollback restored disk, then require the live
          // Todo to agree before retry decides whether to discard its tuple.
          expect(fixture.store.todoFailures, 1);
          await fixture.expectCompletionUnchanged();
          expect(fixture.audit.entries, isEmpty);
          expect(await fixture.store.readAuditEntries(), isEmpty);
          final todoWrites = fixture.store.todoWriteAttempts;
          final auditWrites = fixture.store.auditWriteAttempts;

          expect(
            await fixture.todos.retryPendingCompletionTimeRecords(),
            isTrue,
          );
          expect(fixture.store.auditWriteAttempts, auditWrites + 1);
          expect(fixture.store.todoWriteAttempts, todoWrites);
          await fixture.expectRecoveredRecord();
          await fixture.expectCompletionUnchanged();

          // Recovery consumes the original tuple once, without requiring
          // completion or the failed reopen/delete to be submitted again.
          expect(
            await fixture.todos.retryPendingCompletionTimeRecords(),
            isTrue,
          );
          expect(fixture.store.auditWriteAttempts, auditWrites + 1);
          expect(fixture.store.todoWriteAttempts, todoWrites);
          expect(fixture.auditMarkers, 1);
          await fixture.expectCompletionUnchanged();
        },
      );
    }
  }

  for (final cancellation in ['reset', 'dispose']) {
    test(
      'audit-only $cancellation during retry retains recovery for a replacement audit',
      () async {
        final fixture = await _Fixture.seed();
        addTearDown(fixture.close);
        await fixture.leaveRecordPending();
        final oldAudit = fixture.audit;
        final oldGeneration = oldAudit.storageGeneration;
        final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
        final todoWrites = fixture.store.todoWriteAttempts;
        final gate = fixture.store.holdNextAuditWrite();
        var settled = false;
        final retry = fixture.todos.retryPendingCompletionTimeRecords().then((
          result,
        ) {
          settled = true;
          return result;
        });
        await gate.entered.future.timeout(_timeout);
        expect(settled, isFalse);
        expect(oldAudit.entries, isEmpty);

        // Keep the Todo and account owner current. Cancel only the collaborator
        // whose real preference write is already awaiting acknowledgement.
        if (cancellation == 'reset') {
          oldAudit.resetLocalState();
        } else {
          oldAudit.dispose();
        }
        expect(oldAudit.storageGeneration, greaterThan(oldGeneration));
        expect(
          AccountLocalDataCleaner.accountDataGeneration,
          accountGeneration,
        );
        gate.release.complete();

        expect(await retry.timeout(_timeout), isFalse);
        expect(oldAudit.entries, isEmpty);
        expect(await fixture.store.readAuditEntries(), isEmpty);
        expect(fixture.auditMarkers, 0);
        await fixture.expectCompletionUnchanged();
        expect(fixture.store.todoWriteAttempts, todoWrites);

        await fixture.bindReplacementAudit();
        final auditWrites = fixture.store.auditWriteAttempts;
        expect(await fixture.todos.retryPendingCompletionTimeRecords(), isTrue);
        expect(fixture.store.auditWriteAttempts, auditWrites + 1);
        expect(fixture.store.todoWriteAttempts, todoWrites);
        await fixture.expectRecoveredRecord();
        await fixture.expectCompletionUnchanged();

        expect(await fixture.todos.retryPendingCompletionTimeRecords(), isTrue);
        expect(fixture.store.auditWriteAttempts, auditWrites + 1);
        expect(fixture.store.todoWriteAttempts, todoWrites);
        expect(fixture.auditMarkers, 1);
        await fixture.expectCompletionUnchanged();
      },
    );
  }
}

class _Fixture {
  _Fixture(this.todos, this.audit, this.scheduler, this.store, this.prefs) {
    _audits.add(audit);
    todos.onLocalMutationPersisted = () => todoMarkers++;
    audit.onLocalMutationPersisted = () => auditMarkers++;
    _subscription = DomainEventBus.instance.events.listen((event) {
      if (event.type == DomainEventType.todoCompleted &&
          event.objectId == _todoId) {
        completionEvents.add(event);
      }
    });
  }

  final TodoProvider todos;
  TimeAuditProvider audit;
  final RecordingReminderScheduler scheduler;
  final _Store store;
  final SharedPreferences prefs;
  final _audits = <TimeAuditProvider>[];
  final completionEvents = <DomainEvent>[];
  late final StreamSubscription<DomainEvent> _subscription;
  late final String _completedPayload;
  late final DateTime _completedAt;
  late final int _completionSyncs;
  int todoMarkers = 0;
  int auditMarkers = 0;

  static Future<_Fixture> seed() async {
    final todo = TodoItem(
      id: _todoId,
      title: 'Pending duration across a rejected mutation',
      date: DateTime(2026, 10, 1, 9),
      dueDate: DateTime(2026, 10, 1, 18),
      timeTargetSeconds: 1800,
      recurrence: const RecurrenceRule(
        frequency: RecurrenceFrequency.daily,
        maxOccurrences: 2,
      ),
    );
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
    await audit.loadFromStorage();
    await todos.loadFromStorage();
    return _Fixture(todos, audit, scheduler, store, prefs);
  }

  Future<void> leaveRecordPending() async {
    store.rejectNextAuditWrite = true;
    expect(await todos.completeTodos([_todoId]), 1);
    expect(store.auditWriteAttempts, 1);
    expect(audit.entries, isEmpty);
    expect(await store.readAuditEntries(), isEmpty);
    expect(auditMarkers, 0);
    expect(todos.todos, hasLength(2));
    final completed = todos.todos.singleWhere((todo) => todo.id == _todoId);
    expect(completed.isCompleted, isTrue);
    expect(completed.completedAt, isNotNull);
    _completedAt = completed.completedAt!;
    _completedPayload = jsonEncode(
      todos.todos.map((todo) => todo.toJson()).toList(),
    );
    _completionSyncs = scheduler.todoSyncs.length;
    expect(_completionSyncs, 1);
    await expectCompletionUnchanged();
  }

  Future<void> expectCompletionUnchanged() async {
    final disk = await store.getAll();
    expect(
      jsonDecode(disk['flutter.todos']! as String),
      jsonDecode(_completedPayload),
    );
    await prefs.reload();
    expect(
      jsonDecode(prefs.getString('todos')!),
      jsonDecode(_completedPayload),
    );
    expect(
      todos.todos.map((todo) => todo.toJson()).toList(),
      jsonDecode(_completedPayload),
    );
    expect(completionEvents.map((event) => event.objectId).toList(), [_todoId]);
    expect(todoMarkers, 1);
    expect(scheduler.todoSyncs, hasLength(_completionSyncs));
  }

  Future<void> bindReplacementAudit() async {
    final replacement = TimeAuditProvider();
    _audits.add(replacement);
    await prefs.reload();
    await replacement.loadFromStorage();
    replacement.onLocalMutationPersisted = () => auditMarkers++;
    audit = replacement;
    todos.timeAudit = replacement;
  }

  Future<void> expectRecoveredRecord() async {
    expect(audit.entries, hasLength(1));
    final record = audit.entries.single;
    expect(record.source, TimeEntrySource.todo);
    expect(record.sourceId, _todoId);
    expect(record.endAt, _completedAt);
    expect(
      record.startAt,
      _completedAt.subtract(const Duration(seconds: 1800)),
    );
    expect(record.durationSeconds, 1800);
    expect(
      record.dedupeKey,
      TimeAuditProvider.todoCompletionDedupeKey(_todoId, _completedAt),
    );
    expect(await store.readAuditEntries(), [record.toJson()]);
    expect(auditMarkers, 1);

    // Hydrate another real provider only after refreshing the preferences
    // cache, proving recovery was acknowledged by the underlying store.
    await prefs.reload();
    final reloaded = TimeAuditProvider();
    _audits.add(reloaded);
    await reloaded.loadFromStorage();
    expect(reloaded.entries.map((entry) => entry.toJson()).toList(), [
      record.toJson(),
    ]);
  }

  Future<void> close() async {
    store.releaseAll();
    await AccountPreferenceWrites.drain().timeout(_timeout);
    await _subscription.cancel();
    todos.dispose();
    for (final provider in _audits) {
      if (!provider.isDisposed) provider.dispose();
    }
    SharedPreferences.setMockInitialValues({});
  }
}

class _AuditWriteGate {
  final entered = Completer<void>();
  final release = Completer<void>();
}

class _Store extends InMemorySharedPreferencesStore {
  _Store(super.data) : super.withData();

  bool rejectNextAuditWrite = false;
  String? nextTodoFailure;
  int todoWriteAttempts = 0;
  int todoFailures = 0;
  int auditWriteAttempts = 0;
  _AuditWriteGate? _nextAuditGate;
  final _gates = <_AuditWriteGate>[];

  _AuditWriteGate holdNextAuditWrite() {
    final gate = _AuditWriteGate();
    _gates.add(gate);
    _nextAuditGate = gate;
    return gate;
  }

  void releaseAll() {
    for (final gate in _gates) {
      if (!gate.release.isCompleted) gate.release.complete();
    }
  }

  Future<List<Map<String, dynamic>>> readAuditEntries() async {
    final disk = await getAll();
    final raw = disk[_auditKey] as List<String>? ?? const <String>[];
    return raw
        .map((entry) => Map<String, dynamic>.from(jsonDecode(entry) as Map))
        .toList();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == _auditKey) {
      auditWriteAttempts++;
      if (rejectNextAuditWrite) {
        rejectNextAuditWrite = false;
        return false;
      }
      final gate = _nextAuditGate;
      _nextAuditGate = null;
      if (gate != null) {
        gate.entered.complete();
        await gate.release.future;
      }
    }
    if (key == 'flutter.todos') {
      todoWriteAttempts++;
      final failure = nextTodoFailure;
      nextTodoFailure = null;
      final saved = await super.setValue(valueType, key, value);
      if (failure != null) {
        todoFailures++;
        if (failure == 'false') return false;
        throw StateError('Todo write stored its candidate, then threw');
      }
      return saved;
    }
    return super.setValue(valueType, key, value);
  }
}
