// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/domain_event_bus.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../test_support/recording_reminder_scheduler.dart';

const _timeout = Duration(seconds: 3);
const _todoId = 'completion-cleanup-todo';
const _retainedEntryId = 'completion-cleanup-retained';
const _auditKey = 'flutter.${TimeAuditProvider.storageKey}';
const _tombstoneKey = 'flutter.${CloudSyncProvider.deletedItemsStorageKey}';
const _priorTombstones = <String, Map<String, String>>{
  'todos': {'previous-todo': '2026-10-01T08:00:00.000'},
  'time_entries': {'previous-time-entry': '2026-10-01T08:00:00.000'},
};

// Reopen/delete retain their Future<int> committed count after failed secondary
// cleanup. The existing Future<bool> retryPendingCompletionTimeRecords() also
// drains that cleanup using the original record identity, even when the Todo
// is uncompleted or absent. Intent stays in this TodoProvider instance; only
// the TimeAudit provider is replaced, and no restart recovery is assumed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final action in ['reopen', 'delete']) {
    for (final stage in ['entries', 'tombstones']) {
      for (final rejection in ['false', 'throw']) {
        test(
          '$action commits despite $rejection cleanup $stage acknowledgement and retries removal once',
          () async {
            final fixture = await _Fixture.seedCompleted();
            addTearDown(fixture.close);
            fixture.store.armCleanupFailure(stage, rejection);

            expect(await fixture.mutate(action), 1);
            expect(fixture.store.cleanupFailures, 1);
            expect(fixture.store.failedCleanupStage, stage);
            await fixture.expectPrimaryCommitted(action);
            await fixture.expectAuditUnchanged();

            // Recovery is the explicit API on the same Todo owner, without
            // repeating completion or submitting reopen/delete a second time.
            await fixture.recoverCleanupOnce(action);
          },
        );
      }
    }

    for (final cancellation in ['reset', 'dispose']) {
      test(
        '$action keeps cleanup intent across audit-only $cancellation and replacement',
        () async {
          final fixture = await _Fixture.seedCompleted();
          addTearDown(fixture.close);
          final oldAudit = fixture.audit;
          final oldGeneration = oldAudit.storageGeneration;
          final accountGeneration =
              AccountLocalDataCleaner.accountDataGeneration;
          final gate = fixture.store.holdNextAuditWrite();
          final mutation = fixture.mutate(action);
          await gate.entered.future.timeout(_timeout);

          // The held platform operation belongs to secondary cleanup. Primary
          // Todo persistence is already acknowledged before that call begins.
          await fixture.expectPrimaryCommitted(action, checkReminders: false);
          expect(_entryPayloads(oldAudit.entries), fixture.auditBeforeCleanup);
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

          expect(await mutation.timeout(_timeout), 1);
          if (cancellation == 'reset') {
            expect(oldAudit.entries, isEmpty);
          } else {
            // Disposal preserves the last committed snapshot while preventing
            // the canceled cleanup from publishing its candidate.
            expect(_entryPayloads(oldAudit.entries), fixture.auditBeforeCleanup);
          }
          expect(
            await fixture.store.readAuditEntries(),
            fixture.auditBeforeCleanup,
          );
          expect(fixture.auditMarkers, fixture.auditMarkersBeforeCleanup);
          await fixture.expectPrimaryCommitted(action);

          // Hydration reads the rolled-back durable entries into a new audit;
          // pending removal is still owned by the same TodoProvider instance.
          await fixture.bindReplacementAudit();
          await fixture.expectAuditUnchanged();
          await fixture.recoverCleanupOnce(action);
        },
      );
    }
  }
}

List<Map<String, dynamic>> _entryPayloads(Iterable<TimeEntry> entries) {
  final payloads = entries.map((entry) => entry.toJson()).toList();
  payloads.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
  return payloads;
}

class _Fixture {
  _Fixture(this.todos, this.audit, this.scheduler, this.store, this.prefs) {
    _audits.add(audit);
    todos.onLocalMutationPersisted = () => todoMarkers++;
    audit.onLocalMutationPersisted = () => auditMarkers++;
    _subscription = DomainEventBus.instance.events.listen((event) {
      if (event.type == DomainEventType.todoCompleted) {
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
  late final TimeEntry completionRecord;
  late final Map<String, dynamic> retainedEntryPayload;
  late final List<Map<String, dynamic>> auditBeforeCleanup;
  late final int auditMarkersBeforeCleanup;
  late final int _todoWritesBeforeMutation;
  late final int _todoMarkersBeforeMutation;
  late final int _reminderSyncsBeforeMutation;
  String? _primaryPayload;
  Map<String, dynamic>? _primaryTodoTombstones;
  int todoMarkers = 0;
  int auditMarkers = 0;

  static Future<_Fixture> seedCompleted() async {
    final todo = TodoItem(
      id: _todoId,
      title: 'A completed Todo with cleanup still to acknowledge',
      date: DateTime(2026, 10, 1, 9),
      timeTargetSeconds: 1800,
    );
    final retained = TimeEntry(
      id: _retainedEntryId,
      title: 'Unrelated manual record stays intact',
      startAt: DateTime(2026, 10, 1, 8),
      endAt: DateTime(2026, 10, 1, 8, 10),
      source: TimeEntrySource.manual,
    );
    final initial = <String, Object>{
      'todos': jsonEncode([todo.toJson()]),
      TimeAuditProvider.storageKey: [jsonEncode(retained.toJson())],
      CloudSyncProvider.deletedItemsStorageKey: jsonEncode(_priorTombstones),
    };
    SharedPreferences.setMockInitialValues(initial);
    final store = _Store({
      for (final entry in initial.entries) 'flutter.${entry.key}': entry.value,
    });
    SharedPreferencesStorePlatform.instance = store;
    final prefs = await SharedPreferences.getInstance();
    final audit = TimeAuditProvider();
    final scheduler = RecordingReminderScheduler();
    final todos = TodoProvider()
      ..timeAudit = audit
      ..scheduler = scheduler;
    await audit.loadFromStorage();
    await todos.loadFromStorage();
    final fixture = _Fixture(todos, audit, scheduler, store, prefs);
    expect(await todos.completeTodos([_todoId]), 1);
    fixture.completionRecord = audit.entries.singleWhere(
      (entry) =>
          entry.source == TimeEntrySource.todo && entry.sourceId == _todoId,
    );
    fixture.retainedEntryPayload = retained.toJson();
    fixture.auditBeforeCleanup = _entryPayloads(audit.entries);
    fixture.auditMarkersBeforeCleanup = fixture.auditMarkers;
    fixture._todoWritesBeforeMutation = store.todoWriteAttempts;
    fixture._todoMarkersBeforeMutation = fixture.todoMarkers;
    fixture._reminderSyncsBeforeMutation = scheduler.todoSyncs.length;
    expect(fixture.auditBeforeCleanup, hasLength(2));
    expect(await store.readAuditEntries(), fixture.auditBeforeCleanup);
    expect(fixture.completionRecord.endAt, todos.todos.single.completedAt);
    return fixture;
  }

  Future<int> mutate(String action) => action == 'reopen'
      ? todos.reopenTodos([_todoId])
      : todos.deleteTodos([_todoId]);

  Future<void> expectPrimaryCommitted(
    String action, {
    bool checkReminders = true,
  }) async {
    final live = todos.todos.map((todo) => todo.toJson()).toList();
    if (action == 'reopen') {
      expect(todos.todos, hasLength(1));
      expect(todos.todos.single.id, _todoId);
      expect(todos.todos.single.isCompleted, isFalse);
      expect(todos.todos.single.completedAt, isNull);
    } else {
      expect(todos.todos, isEmpty);
    }
    final disk = await store.getAll();
    expect(jsonDecode(disk['flutter.todos']! as String), live);
    await prefs.reload();
    expect(jsonDecode(prefs.getString('todos')!), live);
    _primaryPayload ??= jsonEncode(live);
    expect(live, jsonDecode(_primaryPayload!));
    expect(store.todoWriteAttempts, _todoWritesBeforeMutation + 1);
    expect(todoMarkers, _todoMarkersBeforeMutation + 1);
    expect(completionEvents.map((event) => event.objectId).toList(), [_todoId]);

    final tombstones = await store.readTombstones();
    final todoTombstones = Map<String, dynamic>.from(
      tombstones['todos'] as Map,
    );
    expect(
      todoTombstones['previous-todo'],
      _priorTombstones['todos']!['previous-todo'],
    );
    if (action == 'delete') {
      expect(todoTombstones, contains(_todoId));
      expect(todoTombstones[_todoId], isA<String>());
    } else {
      expect(todoTombstones, isNot(contains(_todoId)));
    }
    _primaryTodoTombstones ??= Map<String, dynamic>.of(todoTombstones);
    expect(todoTombstones, _primaryTodoTombstones);
    if (checkReminders) {
      expect(
        scheduler.todoSyncs.length,
        greaterThan(_reminderSyncsBeforeMutation),
      );
      if (action == 'reopen') {
        expect(scheduler.todoSyncs.last, [_todoId]);
      } else {
        expect(scheduler.todoSyncs.last, isEmpty);
      }
    }
  }

  Future<void> expectAuditUnchanged() async {
    expect(_entryPayloads(audit.entries), auditBeforeCleanup);
    expect(await store.readAuditEntries(), auditBeforeCleanup);
    expect(auditMarkers, auditMarkersBeforeCleanup);
    final tombstones = await store.readTombstones();
    expect(tombstones['time_entries'], _priorTombstones['time_entries']);
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

  Future<void> recoverCleanupOnce(String action) async {
    final auditWrites = store.auditWriteAttempts;
    final tombstoneWrites = store.tombstoneWriteAttempts;
    expect(await todos.retryPendingCompletionTimeRecords(), isTrue);
    expect(store.auditWriteAttempts, auditWrites + 1);
    expect(store.tombstoneWriteAttempts, tombstoneWrites + 1);
    expect(_entryPayloads(audit.entries), [retainedEntryPayload]);
    expect(await store.readAuditEntries(), [retainedEntryPayload]);
    expect(auditMarkers, auditMarkersBeforeCleanup + 1);
    final tombstones = await store.readTombstones();
    final timeTombstones = Map<String, dynamic>.from(
      tombstones['time_entries'] as Map,
    );
    expect(timeTombstones, contains(completionRecord.id));
    expect(
      timeTombstones['previous-time-entry'],
      _priorTombstones['time_entries']!['previous-time-entry'],
    );
    expect(timeTombstones, isNot(contains(_retainedEntryId)));
    await expectPrimaryCommitted(action);

    // Refresh the cache before a new real provider proves the acknowledged
    // entry deletion. The Todo owner and its in-memory intent were never reset.
    await prefs.reload();
    final reloaded = TimeAuditProvider();
    _audits.add(reloaded);
    await reloaded.loadFromStorage();
    expect(_entryPayloads(reloaded.entries), [retainedEntryPayload]);

    final tombstonesAfterRecovery = await store.readTombstones();
    expect(await todos.retryPendingCompletionTimeRecords(), isTrue);
    expect(store.auditWriteAttempts, auditWrites + 1);
    expect(store.tombstoneWriteAttempts, tombstoneWrites + 1);
    expect(auditMarkers, auditMarkersBeforeCleanup + 1);
    expect(_entryPayloads(audit.entries), [retainedEntryPayload]);
    expect(await store.readTombstones(), tombstonesAfterRecovery);
    await expectPrimaryCommitted(action);
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

  int todoWriteAttempts = 0;
  int auditWriteAttempts = 0;
  int tombstoneWriteAttempts = 0;
  int cleanupFailures = 0;
  String? failedCleanupStage;
  String? _failureStage;
  String? _failureMode;
  bool _auditCandidateIssued = false;
  _AuditWriteGate? _nextAuditGate;
  final _gates = <_AuditWriteGate>[];

  void armCleanupFailure(String stage, String mode) {
    _failureStage = stage;
    _failureMode = mode;
    _auditCandidateIssued = false;
  }

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
    final payloads = raw
        .map((entry) => Map<String, dynamic>.from(jsonDecode(entry) as Map))
        .toList();
    payloads.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    return payloads;
  }

  Future<Map<String, dynamic>> readTombstones() async {
    final disk = await getAll();
    return Map<String, dynamic>.from(
      jsonDecode(disk[_tombstoneKey]! as String) as Map,
    );
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.todos') todoWriteAttempts++;
    if (key == _tombstoneKey) tombstoneWriteAttempts++;
    if (key == _auditKey) {
      auditWriteAttempts++;
      _auditCandidateIssued = true;
      final gate = _nextAuditGate;
      _nextAuditGate = null;
      if (gate != null) {
        gate.entered.complete();
        await gate.release.future;
      }
    }
    final shouldFail =
        (_failureStage == 'entries' && key == _auditKey) ||
        (_failureStage == 'tombstones' &&
            _auditCandidateIssued &&
            key == _tombstoneKey);
    final mode = shouldFail ? _failureMode : null;
    if (shouldFail) {
      failedCleanupStage = _failureStage;
      _failureStage = null;
      _failureMode = null;
      cleanupFailures++;
    }
    // Every rejected acknowledgement follows a real platform-store mutation.
    // The one-shot fault is consumed before transaction rollback issues writes.
    final saved = await super.setValue(valueType, key, value);
    if (mode == 'false') return false;
    if (mode == 'throw') {
      throw StateError('Cleanup stored its candidate, then threw');
    }
    return saved;
  }
}
