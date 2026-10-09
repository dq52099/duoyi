// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'dispose during storage load suppresses hydration and notification',
    () async {
      final stored = _entry('load-old', 'stored before disposal');
      final store = _installStore(entries: [stored])..blockNextGetAll = true;
      final provider = TimeAuditProvider();
      var notifications = 0;
      provider.addListener(() => notifications++);

      final pendingLoad = provider.loadFromStorage();
      await store.getAllEntered.future.timeout(const Duration(seconds: 1));
      provider.dispose();
      store.releaseGetAll.complete();
      await pendingLoad;

      expect(provider.entries, isEmpty);
      expect(notifications, 0);
      expect(store.getAllCalls, 1);
      expect(store.timeEntrySetAttempts, 0);
    },
  );

  test(
    'dispose during save initialization prevents a later storage write',
    () async {
      final store = _installStore()..blockNextGetAll = true;
      final provider = TimeAuditProvider();
      var notifications = 0;
      var callbacks = 0;
      provider.addListener(() => notifications++);
      provider.onLocalMutationPersisted = () => callbacks++;

      final pendingAdd = provider.add(_entry('init-add', 'awaiting prefs'));
      await store.getAllEntered.future.timeout(const Duration(seconds: 1));
      final entriesAtDispose = _entryFingerprints(provider);
      provider.dispose();
      store.releaseGetAll.complete();
      await pendingAdd;

      expect(_entryFingerprints(provider), entriesAtDispose);
      expect(notifications, 0);
      expect(callbacks, 0);
      expect(store.timeEntrySetAttempts, 0);
    },
  );

  for (final operation in ['add', 'update', 'import', 'upsert']) {
    test(
      'dispose during $operation write suppresses later effects',
      () async => _disposeDuringStartedWrite(operation),
    );
  }

  test(
    'dispose during tombstone write prevents the subsequent entry save',
    () async {
      final existing = _entry(
        'delete-during-tombstone',
        'delete while tombstone is pending',
        dedupeKey: 'delete-during-tombstone-key',
      );
      final store = _installStore(entries: [existing]);
      final provider = TimeAuditProvider();
      await provider.loadFromStorage();
      var notifications = 0;
      var callbacks = 0;
      provider.addListener(() => notifications++);
      provider.onLocalMutationPersisted = () => callbacks++;
      store.blockNextTombstoneSet = true;

      final pendingDelete = provider.deleteByDedupeKey(
        'delete-during-tombstone-key',
      );
      await store.tombstoneSetEntered.future.timeout(
        const Duration(seconds: 1),
      );
      expect(provider.entries, isEmpty);

      provider.dispose();
      store.releaseTombstoneSet.complete();
      await pendingDelete;

      expect(notifications, 0);
      expect(callbacks, 0);
      expect(store.writes, ['flutter.sync_deleted_items']);
      expect(store.timeEntrySetAttempts, 0);
    },
  );

  test(
    'direct mutations after disposal do not change state or use storage',
    () async {
      final existing = _entry(
        'already-disposed-entry',
        'existing entry',
        dedupeKey: 'already-disposed-key',
      );
      final store = _installStore(entries: [existing]);
      final provider = TimeAuditProvider();
      await provider.loadFromStorage();
      final entriesBeforeDispose = _entryFingerprints(provider);
      var notifications = 0;
      var callbacks = 0;
      provider.addListener(() => notifications++);
      provider.onLocalMutationPersisted = () => callbacks++;
      provider.dispose();

      final readsBefore = store.getAllCalls;
      final writesBefore = List<String>.of(store.writes);
      await provider.add(_entry('after-dispose-add', 'ignored add'));
      await provider.update(existing.copyWith(title: 'ignored update'));
      final summary = await provider.importTimeEntries([
        _entry('after-dispose-import', 'ignored import'),
      ]);
      await provider.upsertAuto(existing.copyWith(title: 'ignored upsert'));
      await provider.delete(existing.id);
      await provider.deleteByDedupeKey('already-disposed-key');
      await provider.deleteWhere((_) => true);
      await provider.deleteBySource(existing.source, existing.sourceId ?? '');
      await provider.deleteGoalEntries('already-disposed-entry');
      provider.resetLocalState();
      await provider.loadFromStorage();

      expect(summary.inserted, 0);
      expect(summary.skippedDuplicates, 0);
      expect(_entryFingerprints(provider), entriesBeforeDispose);
      expect(notifications, 0);
      expect(callbacks, 0);
      expect(store.getAllCalls, readsBefore);
      expect(store.writes, writesBefore);
    },
  );

  test(
    'reset during load keeps newer entries and rejects the stale load',
    () async {
      await _expectFreshEntryAfterLoadInvalidation(resetProvider: true);
    },
  );

  test(
    'account invalidation during load keeps newer entries and rejects stale data',
    () async {
      await _expectFreshEntryAfterLoadInvalidation(invalidateAccount: true);
    },
  );

  test('a fresh provider lifetime still saves and notifies', () async {
    final store = _installStore();
    final provider = TimeAuditProvider();
    var notifications = 0;
    var callbacks = 0;
    provider.addListener(() => notifications++);
    provider.onLocalMutationPersisted = () => callbacks++;

    final entry = _entry('fresh-lifetime', 'still persists');
    await provider.add(entry);

    expect(provider.entries, hasLength(1));
    expect(notifications, 1);
    expect(callbacks, 1);
    expect(store.timeEntrySetAttempts, 1);
    expect(await _storedEntries(store), [jsonEncode(entry.toJson())]);
    provider.dispose();
  });
}

Future<void> _disposeDuringStartedWrite(String operation) async {
  final existing = _entry(
    'write-existing',
    'existing before write',
    dedupeKey: 'write-existing-auto-key',
  );
  final store = _installStore(entries: [existing]);
  final provider = TimeAuditProvider();
  await provider.loadFromStorage();
  var notifications = 0;
  var callbacks = 0;
  provider.addListener(() => notifications++);
  provider.onLocalMutationPersisted = () => callbacks++;
  store.blockNextTimeEntrySet = true;

  late final Future<void> pending;
  switch (operation) {
    case 'add':
      pending = provider.add(_entry('write-added', 'new entry'));
      break;
    case 'update':
      pending = provider.update(existing.copyWith(title: 'updated entry'));
      break;
    case 'import':
      pending = provider
          .importTimeEntries([_entry('write-imported', 'imported entry')])
          .then<void>((summary) {
            expect(summary.inserted, 1);
            expect(summary.skippedDuplicates, 0);
          });
      break;
    case 'upsert':
      pending = provider.upsertAuto(existing.copyWith(title: 'upserted entry'));
      break;
    default:
      throw StateError('Unknown disposal fixture operation: $operation');
  }

  await store.timeEntrySetEntered.future.timeout(const Duration(seconds: 1));
  expect(store.timeEntrySetAttempts, 1);
  final entriesAtDispose = _entryFingerprints(provider);
  provider.dispose();
  store.releaseTimeEntrySet.complete();
  await pending;

  expect(_entryFingerprints(provider), entriesAtDispose);
  expect(notifications, 0);
  expect(callbacks, 0);
  // This set call began before dispose and cannot be rolled back. The fence
  // suppresses later effects and prevents any additional storage operation.
  expect(store.writes, ['flutter.duoyi_time_entries']);
}

Future<void> _expectFreshEntryAfterLoadInvalidation({
  bool resetProvider = false,
  bool invalidateAccount = false,
}) async {
  final stored = _entry('stale-stored-entry', 'old data');
  final store = _installStore(entries: [stored])..blockNextGetAll = true;
  final provider = TimeAuditProvider();
  var notifications = 0;
  var callbacks = 0;
  provider.addListener(() => notifications++);
  provider.onLocalMutationPersisted = () => callbacks++;

  final pendingLoad = provider.loadFromStorage();
  await store.getAllEntered.future.timeout(const Duration(seconds: 1));
  if (invalidateAccount) {
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
  }
  if (resetProvider) provider.resetLocalState();
  final fresh = _entry('new-after-invalidation', 'new data');
  final pendingAdd = provider.add(fresh);
  store.releaseGetAll.complete();
  await Future.wait([pendingLoad, pendingAdd]);

  expect(provider.entries.map((entry) => entry.id).toList(), [fresh.id]);
  expect(notifications, resetProvider ? 2 : 1);
  expect(callbacks, 1);
  expect(await _storedEntries(store), [jsonEncode(fresh.toJson())]);
  provider.dispose();
}

_ControlledPreferencesStore _installStore({
  List<TimeEntry> entries = const [],
}) {
  final values = <String, Object>{
    if (entries.isNotEmpty)
      TimeAuditProvider.storageKey: entries.map(jsonEncode).toList(),
  };
  SharedPreferences.setMockInitialValues(values);
  final store = _ControlledPreferencesStore({
    for (final entry in values.entries) 'flutter.${entry.key}': entry.value,
  });
  SharedPreferencesStorePlatform.instance = store;
  return store;
}

TimeEntry _entry(String id, String title, {String? dedupeKey}) => TimeEntry(
  id: id,
  title: title,
  startAt: DateTime(2026, 10, 9, 9),
  endAt: DateTime(2026, 10, 9, 9, 30),
  category: TimeEntryCategory.study,
  dedupeKey: dedupeKey,
  createdAt: DateTime(2026, 10, 9, 8),
  updatedAt: DateTime(2026, 10, 9, 8),
);

List<String> _entryFingerprints(TimeAuditProvider provider) => provider.entries
    .map((entry) => jsonEncode(entry.toJson()))
    .toList(growable: false);

Future<List<String>> _storedEntries(_ControlledPreferencesStore store) async {
  final values = await store.getAll();
  final raw = values['flutter.${TimeAuditProvider.storageKey}'];
  return raw is List ? raw.cast<String>() : <String>[];
}

class _ControlledPreferencesStore extends InMemorySharedPreferencesStore {
  _ControlledPreferencesStore(super.data) : super.withData();

  bool blockNextGetAll = false;
  bool blockNextTimeEntrySet = false;
  bool blockNextTombstoneSet = false;
  int getAllCalls = 0;
  int timeEntrySetAttempts = 0;
  final writes = <String>[];
  final getAllEntered = Completer<void>();
  final releaseGetAll = Completer<void>();
  final timeEntrySetEntered = Completer<void>();
  final releaseTimeEntrySet = Completer<void>();
  final tombstoneSetEntered = Completer<void>();
  final releaseTombstoneSet = Completer<void>();

  @override
  Future<Map<String, Object>> getAll() async {
    getAllCalls++;
    if (blockNextGetAll) {
      blockNextGetAll = false;
      getAllEntered.complete();
      await releaseGetAll.future;
    }
    return super.getAll();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writes.add(key);
    if (key == 'flutter.${TimeAuditProvider.storageKey}') {
      timeEntrySetAttempts++;
      if (blockNextTimeEntrySet) {
        blockNextTimeEntrySet = false;
        timeEntrySetEntered.complete();
        await releaseTimeEntrySet.future;
      }
    }
    if (key == 'flutter.sync_deleted_items' && blockNextTombstoneSet) {
      blockNextTombstoneSet = false;
      tombstoneSetEntered.complete();
      await releaseTombstoneSet.future;
    }
    return super.setValue(valueType, key, value);
  }
}
