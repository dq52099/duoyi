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
const _todoId = 'cleanup-audit-hydration-todo';
const _retainedId = 'cleanup-audit-hydration-retained';
const _todoKey = 'flutter.todos';
const _auditKey = 'flutter.${TimeAuditProvider.storageKey}';
const _tombstoneKey = 'flutter.${CloudSyncProvider.deletedItemsStorageKey}';
const _priorTombstones = <String, Map<String, String>>{
  'todos': {'previous-todo': '2026-10-01T08:00:00.000'},
  'time_entries': {'previous-time-entry': '2026-10-01T08:00:00.000'},
};

// Public contract: retryPendingCompletionTimeRecords() performs owned audit
// hydration before consuming pending cleanup. Reopen/delete keep their durable
// committed count; only the bound audit is reset/replaced here. No Todo owner
// reset, primary action replay, or restart-durable intent is assumed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final action in ['reopen', 'delete']) {
    test(
      '$action captures durable cleanup targets from an initially unhydrated audit',
      () async {
        final fixture = await _Fixture.seedCompleted();
        addTearDown(fixture.close);
        fixture.bindUnhydratedReplacement();
        expect(fixture.audit.entries, isEmpty);
        expect(
          await fixture.store.readAuditEntries(),
          fixture.auditBeforeCleanup,
        );
        final auditWrites = fixture.store.auditWriteAttempts;
        final tombstoneWrites = fixture.store.tombstoneWriteAttempts;

        // The caller never hydrates this audit. Primary admission must capture
        // stored targets before deciding that an empty live cache has no work.
        expect(await fixture.mutate(action), 1);
        await fixture.expectPrimaryCommitted(action);
        await fixture.recoverAndExpectOnce(
          action,
          expectedAuditWrites: auditWrites + 1,
          expectedTombstoneWrites:
              tombstoneWrites + (action == 'delete' ? 2 : 1),
        );
      },
    );

    test(
      '$action retains cleanup targets when audit resets during the primary write',
      () async {
        final fixture = await _Fixture.seedCompleted();
        addTearDown(fixture.close);
        final auditWrites = fixture.store.auditWriteAttempts;
        final tombstoneWrites = fixture.store.tombstoneWriteAttempts;
        final account = AccountLocalDataCleaner.accountDataGeneration;
        final generation = fixture.audit.storageGeneration;
        final gate = fixture.store.holdNextTodoWrite();
        final mutation = fixture.mutate(action);
        await gate.entered.future.timeout(_timeout);

        // Gate the actual primary Todo platform call, before its candidate is
        // stored. The audit reset happens before cleanup intent is committed.
        expect(fixture.todos.todos.single.isCompleted, isTrue);
        expect(await fixture.store.readTodoPayload(), fixture.completedPayload);
        fixture.audit.resetLocalState();
        expect(fixture.audit.entries, isEmpty);
        expect(fixture.audit.storageGeneration, greaterThan(generation));
        expect(AccountLocalDataCleaner.accountDataGeneration, account);
        expect(
          await fixture.store.readAuditEntries(),
          fixture.auditBeforeCleanup,
        );
        gate.release.complete();

        expect(await mutation.timeout(_timeout), 1);
        await fixture.expectPrimaryCommitted(action);
        // The primary action may already attempt its retained cleanup. An
        // explicit retry must finish any remaining intent without extra writes.
        await fixture.recoverAndExpectOnce(
          action,
          expectedAuditWrites: auditWrites + 1,
          expectedTombstoneWrites:
              tombstoneWrites + (action == 'delete' ? 2 : 1),
        );
      },
    );

    for (final auditChange in ['same audit reset', 'unhydrated replacement']) {
      test(
        '$action retries failed cleanup after $auditChange without caller hydration',
        () async {
          final fixture = await _Fixture.seedCompleted();
          addTearDown(fixture.close);
          await fixture.leaveCleanupPending(action);
          final auditWrites = fixture.store.auditWriteAttempts;
          final tombstoneWrites = fixture.store.tombstoneWriteAttempts;
          final account = AccountLocalDataCleaner.accountDataGeneration;

          if (auditChange == 'same audit reset') {
            fixture.audit.resetLocalState();
          } else {
            fixture.bindUnhydratedReplacement();
          }
          expect(fixture.audit.entries, isEmpty);
          expect(AccountLocalDataCleaner.accountDataGeneration, account);
          expect(
            await fixture.store.readAuditEntries(),
            fixture.auditBeforeCleanup,
          );
          // No loadFromStorage or preferences reload is performed between the
          // audit change and the public retry that must own that hydration.
          await fixture.recoverAndExpectOnce(
            action,
            expectedAuditWrites: auditWrites + 1,
            expectedTombstoneWrites: tombstoneWrites + 1,
          );
        },
      );
    }

    test(
      '$action cleanup preserves a reused entry ID with a new completion identity',
      () async {
        final fixture = await _Fixture.seedCompleted();
        addTearDown(fixture.close);
        await fixture.leaveCleanupPending(action);
        final newCompletionAt = fixture.completionRecord.endAt.add(
          const Duration(days: 1),
        );
        final replacement = fixture.completionRecord.copyWith(
          title: 'A new completion reuses the durable entry ID',
          startAt: newCompletionAt.subtract(const Duration(minutes: 15)),
          endAt: newCompletionAt,
          dedupeKey: TimeAuditProvider.todoCompletionDedupeKey(
            _todoId,
            newCompletionAt,
          ),
        );
        expect(replacement.id, fixture.completionRecord.id);
        expect(replacement.sourceId, _todoId);
        expect(
          replacement.dedupeKey,
          isNot(fixture.completionRecord.dedupeKey),
        );
        await fixture.audit.upsertAuto(replacement);
        final acknowledgedReplacement = fixture.audit.entries.singleWhere(
          (entry) => entry.id == replacement.id,
        );
        expect(acknowledgedReplacement.endAt, newCompletionAt);
        expect(acknowledgedReplacement.dedupeKey, replacement.dedupeKey);
        final expected = _entryPayloads([
          fixture.retainedEntry,
          acknowledgedReplacement,
        ]);
        expect(await fixture.store.readAuditEntries(), expected);
        final auditWrites = fixture.store.auditWriteAttempts;
        final tombstoneWrites = fixture.store.tombstoneWriteAttempts;
        final auditMarkers = fixture.auditMarkers;
        final tombstones = await fixture.store.readTombstones();

        // Captured completion identity is superseded. ID/source equality alone
        // must not authorize removal of this newly acknowledged record.
        expect(await fixture.todos.retryPendingCompletionTimeRecords(), isTrue);
        expect(_entryPayloads(fixture.audit.entries), expected);
        expect(await fixture.store.readAuditEntries(), expected);
        expect(fixture.store.auditWriteAttempts, auditWrites);
        expect(fixture.store.tombstoneWriteAttempts, tombstoneWrites);
        expect(fixture.auditMarkers, auditMarkers);
        expect(await fixture.store.readTombstones(), tombstones);
        await fixture.expectPrimaryCommitted(action);

        expect(await fixture.todos.retryPendingCompletionTimeRecords(), isTrue);
        expect(_entryPayloads(fixture.audit.entries), expected);
        expect(await fixture.store.readAuditEntries(), expected);
        expect(fixture.store.auditWriteAttempts, auditWrites);
        expect(fixture.store.tombstoneWriteAttempts, tombstoneWrites);
        expect(fixture.auditMarkers, auditMarkers);
        await fixture.expectPrimaryCommitted(action);
      },
    );
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
  late final TimeEntry retainedEntry;
  late final List<Map<String, dynamic>> completedPayload;
  late final List<Map<String, dynamic>> auditBeforeCleanup;
  late final int _auditMarkersBeforeMutation;
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
      title: 'Cleanup targets must survive an empty audit cache',
      date: DateTime(2026, 10, 1, 9),
      timeTargetSeconds: 1800,
    );
    final retained = TimeEntry(
      id: _retainedId,
      title: 'An unrelated persisted entry is preserved',
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
    fixture.retainedEntry = retained;
    fixture.completedPayload = todos.todos
        .map((item) => item.toJson())
        .toList();
    fixture.auditBeforeCleanup = _entryPayloads(audit.entries);
    fixture._auditMarkersBeforeMutation = fixture.auditMarkers;
    fixture._todoWritesBeforeMutation = store.todoWriteAttempts;
    fixture._todoMarkersBeforeMutation = fixture.todoMarkers;
    fixture._reminderSyncsBeforeMutation = scheduler.todoSyncs.length;
    expect(fixture.auditBeforeCleanup, hasLength(2));
    expect(await store.readAuditEntries(), fixture.auditBeforeCleanup);
    return fixture;
  }

  Future<int> mutate(String action) => action == 'reopen'
      ? todos.reopenTodos([_todoId])
      : todos.deleteTodos([_todoId]);

  Future<void> leaveCleanupPending(String action) async {
    store.rejectNextAuditWrite = true;
    expect(await mutate(action), 1);
    expect(store.cleanupFailures, 1);
    expect(_entryPayloads(audit.entries), auditBeforeCleanup);
    expect(await store.readAuditEntries(), auditBeforeCleanup);
    expect(auditMarkers, _auditMarkersBeforeMutation);
    await expectPrimaryCommitted(action);
  }

  void bindUnhydratedReplacement() {
    final replacement = TimeAuditProvider();
    _audits.add(replacement);
    replacement.onLocalMutationPersisted = () => auditMarkers++;
    audit = replacement;
    todos.timeAudit = replacement;
  }

  Future<void> expectPrimaryCommitted(String action) async {
    final live = todos.todos.map((todo) => todo.toJson()).toList();
    if (action == 'reopen') {
      expect(todos.todos, hasLength(1));
      expect(todos.todos.single.id, _todoId);
      expect(todos.todos.single.isCompleted, isFalse);
      expect(todos.todos.single.completedAt, isNull);
    } else {
      expect(todos.todos, isEmpty);
    }
    expect(await store.readTodoPayload(), live);
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
    } else {
      expect(todoTombstones, isNot(contains(_todoId)));
    }
    _primaryTodoTombstones ??= Map<String, dynamic>.of(todoTombstones);
    expect(todoTombstones, _primaryTodoTombstones);
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

  Future<void> recoverAndExpectOnce(
    String action, {
    required int expectedAuditWrites,
    required int expectedTombstoneWrites,
  }) async {
    // Invoke public retry before any caller-triggered audit hydration.
    expect(await todos.retryPendingCompletionTimeRecords(), isTrue);
    expect(store.auditWriteAttempts, expectedAuditWrites);
    expect(store.tombstoneWriteAttempts, expectedTombstoneWrites);
    expect(auditMarkers, _auditMarkersBeforeMutation + 1);
    final retained = [retainedEntry.toJson()];
    expect(_entryPayloads(audit.entries), retained);
    expect(await store.readAuditEntries(), retained);
    final tombstones = await store.readTombstones();
    final timeTombstones = Map<String, dynamic>.from(
      tombstones['time_entries'] as Map,
    );
    expect(timeTombstones, contains(completionRecord.id));
    expect(timeTombstones, isNot(contains(_retainedId)));
    expect(
      timeTombstones['previous-time-entry'],
      _priorTombstones['time_entries']!['previous-time-entry'],
    );
    await expectPrimaryCommitted(action);

    await prefs.reload();
    final reloaded = TimeAuditProvider();
    _audits.add(reloaded);
    await reloaded.loadFromStorage();
    expect(_entryPayloads(reloaded.entries), retained);

    expect(await todos.retryPendingCompletionTimeRecords(), isTrue);
    expect(store.auditWriteAttempts, expectedAuditWrites);
    expect(store.tombstoneWriteAttempts, expectedTombstoneWrites);
    expect(auditMarkers, _auditMarkersBeforeMutation + 1);
    expect(_entryPayloads(audit.entries), retained);
    expect(await store.readTombstones(), tombstones);
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

class _TodoWriteGate {
  final entered = Completer<void>();
  final release = Completer<void>();
}

class _Store extends InMemorySharedPreferencesStore {
  _Store(super.data) : super.withData();

  int todoWriteAttempts = 0;
  int auditWriteAttempts = 0;
  int tombstoneWriteAttempts = 0;
  int cleanupFailures = 0;
  bool rejectNextAuditWrite = false;
  _TodoWriteGate? _nextTodoGate;
  final _gates = <_TodoWriteGate>[];

  _TodoWriteGate holdNextTodoWrite() {
    final gate = _TodoWriteGate();
    _gates.add(gate);
    _nextTodoGate = gate;
    return gate;
  }

  void releaseAll() {
    for (final gate in _gates) {
      if (!gate.release.isCompleted) gate.release.complete();
    }
  }

  Future<List<dynamic>> readTodoPayload() async {
    final disk = await getAll();
    return jsonDecode(disk[_todoKey]! as String) as List;
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
    if (key == _todoKey) {
      todoWriteAttempts++;
      final gate = _nextTodoGate;
      _nextTodoGate = null;
      if (gate != null) {
        gate.entered.complete();
        await gate.release.future;
      }
    }
    if (key == _tombstoneKey) tombstoneWriteAttempts++;
    var reject = false;
    if (key == _auditKey) {
      auditWriteAttempts++;
      reject = rejectNextAuditWrite;
      rejectNextAuditWrite = false;
    }
    final saved = await super.setValue(valueType, key, value);
    if (reject) {
      cleanupFailures++;
      return false;
    }
    return saved;
  }
}
