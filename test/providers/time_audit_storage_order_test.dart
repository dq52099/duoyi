// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/oauth_calendar_storage.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _entriesKey = 'flutter.duoyi_time_entries';
const _tombstonesKey = 'flutter.sync_deleted_items';
const _timeout = Duration(seconds: 3);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ControlledStore store;
  final providers = <TimeAuditProvider>[];
  final manualGates = <Completer<void>>[];

  TimeAuditProvider createProvider() {
    final provider = TimeAuditProvider();
    providers.add(provider);
    return provider;
  }

  Future<TimeAuditProvider> reloadProvider() async {
    // Legacy SharedPreferences changes its cache before the platform replies.
    // Always refresh that cache from the store before testing hydration.
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final provider = createProvider();
    await provider.loadFromStorage();
    return provider;
  }

  setUp(() {
    providers.clear();
    manualGates.clear();
    store = _installStore();
  });

  tearDown(() async {
    for (final gate in manualGates) {
      if (!gate.isCompleted) gate.complete();
    }
    store.releaseAll();
    await AccountPreferenceWrites.drain().timeout(_timeout);
    for (final provider in providers) {
      if (!provider.isDisposed) provider.dispose();
    }
  });

  test(
    'each queued add waits for its own acknowledgement and rejection retains the preceding commit',
    () async {
      final provider = createProvider();
      final firstEntry = _entry('acknowledged');
      final secondEntry = _entry('rejected-follower');
      final firstWrite = store.planSet(key: _entriesKey, hold: true);
      final secondWrite = store.planSet(
        key: _entriesKey,
        hold: true,
        reject: true,
      );
      var notifications = 0;
      var callbacks = 0;
      var firstCompleted = false;
      provider.addListener(() => notifications++);
      provider.onLocalMutationPersisted = () => callbacks++;

      final first = provider.add(firstEntry).then((_) {
        firstCompleted = true;
      });
      await firstWrite.entered.future.timeout(_timeout);
      final second = expectLater(provider.add(secondEntry), throwsStateError);
      await _nextTurn();

      expect(firstCompleted, isFalse);
      expect(provider.entries, isEmpty);
      expect(await store.readEntries(), isEmpty);
      expect(store.entrySetCalls, 1);
      expect(notifications, 0);
      expect(callbacks, 0);

      firstWrite.release.complete();
      await first;
      await secondWrite.entered.future.timeout(_timeout);
      _expectEntries(provider.entries, [firstEntry]);
      _expectEntries(await store.readEntries(), [firstEntry]);
      expect(firstCompleted, isTrue);
      expect(notifications, 1);
      expect(callbacks, 1);

      secondWrite.release.complete();
      await second;
      _expectEntries(provider.entries, [firstEntry]);
      _expectEntries(await store.readEntries(), [firstEntry]);
      _expectEntries((await reloadProvider()).entries, [firstEntry]);
      expect(store.maxActiveSets, 1);
      expect(notifications, 1);
      expect(callbacks, 1);
    },
  );

  test(
    'false and exception leave no published draft and retry the same ID exactly once',
    () async {
      final provider = createProvider();
      final accepted = <TimeEntry>[_entry('prior')];
      await provider.add(accepted.single);
      var notifications = 0;
      var callbacks = 0;
      provider.addListener(() => notifications++);
      provider.onLocalMutationPersisted = () => callbacks++;

      for (final throwError in [false, true]) {
        final draft = _entry('retry-${throwError ? 'exception' : 'false'}');
        final write = store.planSet(
          key: _entriesKey,
          hold: true,
          reject: !throwError,
          throwError: throwError,
        );
        final rejected = expectLater(provider.add(draft), throwsStateError);
        await write.entered.future.timeout(_timeout);
        _expectEntries(provider.entries, accepted);
        _expectEntries(await store.readEntries(), accepted);
        final beforeNotifications = notifications;
        final beforeCallbacks = callbacks;
        write.release.complete();
        await rejected;

        _expectEntries(provider.entries, accepted);
        _expectEntries(await store.readEntries(), accepted);
        _expectEntries((await reloadProvider()).entries, accepted);
        expect(notifications, beforeNotifications);
        expect(callbacks, beforeCallbacks);

        final retry = draft.copyWith(title: 'accepted retry');
        await provider.add(retry);
        accepted.add(retry);
        _expectEntries(provider.entries, accepted);
        _expectEntries(await store.readEntries(), accepted);
        _expectEntries((await reloadProvider()).entries, accepted);
        expect(
          provider.entries.where((entry) => entry.id == draft.id),
          hasLength(1),
        );
        expect(notifications, beforeNotifications + 1);
        expect(callbacks, beforeCallbacks + 1);

        final setsBeforeDuplicate = store.entrySetCalls;
        await expectLater(provider.add(retry), throwsStateError);
        expect(store.entrySetCalls, setsBeforeDuplicate);
        _expectEntries(provider.entries, accepted);
      }
    },
  );

  test(
    'cleanup waits for an issued deletion and rollback then cancels its queued follower',
    () async {
      final original = _entry('outgoing-account');
      store = _installStore(
        entries: [original],
        tombstones: _existingTombstones,
      );
      final provider = createProvider();
      await provider.loadFromStorage();
      final issuedWrite = store.planSet(hold: true);
      // Both deletion keys already exist, so cancellation must issue a real
      // restoring set rather than merely remove an absent original value.
      final rollbackWrite = store.planSet(hold: true);
      var callbacks = 0;
      provider.onLocalMutationPersisted = () => callbacks++;
      final deletion = provider.delete(original.id);
      await issuedWrite.entered.future.timeout(_timeout);
      final follower = provider.add(_entry('queued-old-account'));
      var cleaned = false;
      final cleanup = AccountLocalDataCleaner.clearSharedPreferences().then((
        _,
      ) {
        cleaned = true;
      });
      provider.resetLocalState();
      await _nextTurn();

      expect(cleaned, isFalse);
      expect(store.setKeys, hasLength(1));
      issuedWrite.release.complete();
      await rollbackWrite.entered.future.timeout(_timeout);
      expect(cleaned, isFalse);
      expect(store.setKeys, hasLength(2));
      rollbackWrite.release.complete();
      await Future.wait([deletion, follower, cleanup]);

      final disk = await store.readDisk();
      expect(disk[_entriesKey], isNull);
      expect(disk[_tombstonesKey], isNull);
      expect(provider.entries, isEmpty);
      expect((await reloadProvider()).entries, isEmpty);
      expect(callbacks, 0);
      expect(store.maxActiveSets, 1);
      expect(store.setKeys, [
        _entriesKey,
        _entriesKey,
        'flutter.${OAuthCalendarStorage.retirementFenceKey}',
      ]);
    },
  );

  test(
    'reset queues a new generation behind the old issued write and its rollback',
    () async {
      final provider = createProvider();
      final write = store.planSet(key: _entriesKey, hold: true);
      var notifications = 0;
      var callbacks = 0;
      provider.addListener(() => notifications++);
      provider.onLocalMutationPersisted = () => callbacks++;
      final oldWrite = provider.add(_entry('before-reset'));
      await write.entered.future.timeout(_timeout);

      provider.resetLocalState();
      final fresh = _entry('after-reset');
      final newWrite = provider.add(fresh);
      await _nextTurn();
      expect(provider.entries, isEmpty);
      expect(store.entrySetCalls, 1);
      write.release.complete();
      await Future.wait([oldWrite, newWrite]);

      _expectEntries(provider.entries, [fresh]);
      _expectEntries(await store.readEntries(), [fresh]);
      _expectEntries((await reloadProvider()).entries, [fresh]);
      expect(store.maxActiveSets, 1);
      expect(callbacks, 1);
      expect(notifications, 2); // Reset and the new acknowledged mutation.
    },
  );

  test(
    'a replacement provider waits for a disposed provider to finish rollback',
    () async {
      final oldProvider = createProvider();
      final write = store.planSet(key: _entriesKey, hold: true);
      var oldCallbacks = 0;
      var oldNotifications = 0;
      oldProvider.onLocalMutationPersisted = () => oldCallbacks++;
      oldProvider.addListener(() => oldNotifications++);
      final oldWrite = oldProvider.add(_entry('disposed-owner'));
      await write.entered.future.timeout(_timeout);
      oldProvider.dispose();

      final replacement = createProvider();
      var loaded = false;
      final load = replacement.loadFromStorage().then((_) => loaded = true);
      final fresh = _entry('replacement-owner');
      final newWrite = replacement.add(fresh);
      await _nextTurn();
      expect(loaded, isFalse);
      expect(store.entrySetCalls, 1);
      expect(replacement.entries, isEmpty);
      write.release.complete();
      await Future.wait([oldWrite, load, newWrite]);

      _expectEntries(replacement.entries, [fresh]);
      _expectEntries(await store.readEntries(), [fresh]);
      _expectEntries((await reloadProvider()).entries, [fresh]);
      expect(store.maxActiveSets, 1);
      expect(oldCallbacks, 0);
      expect(oldNotifications, 0);
    },
  );

  test(
    'load participates in storage order between two mutations across instances',
    () async {
      final original = _entry('ordered-load');
      store = _installStore(entries: [original]);
      final writer = createProvider();
      await writer.loadFromStorage();
      final reader = createProvider();
      final firstWrite = store.planSet(key: _entriesKey, hold: true);
      final followingWrite = store.planSet(key: _entriesKey, hold: true);
      final changed = original.copyWith(title: 'acknowledged before load');
      final update = writer.update(changed);
      await firstWrite.entered.future.timeout(_timeout);
      var loaded = false;
      final load = reader.loadFromStorage().then((_) => loaded = true);
      final following = _entry('following-load');
      final add = writer.add(following);
      await _nextTurn();
      expect(loaded, isFalse);
      expect(reader.entries, isEmpty);
      expect(store.entrySetCalls, 1);

      firstWrite.release.complete();
      await Future.wait([update, load]);
      await followingWrite.entered.future.timeout(_timeout);
      _expectEntries(reader.entries, [changed]);
      _expectEntries(await store.readEntries(), [changed]);
      followingWrite.release.complete();
      await add;

      _expectEntries(writer.entries, [changed, following]);
      _expectEntries(await store.readEntries(), [changed, following]);
      _expectEntries((await reloadProvider()).entries, [changed, following]);
      expect(store.maxActiveSets, 1);
    },
  );

  for (final rejectedKey in [_entriesKey, _tombstonesKey]) {
    test(
      'delete rejection at $rejectedKey restores both keys and preserves another collection writer',
      () async {
        final original = _entry('failed-delete');
        final retained = _entry('retained');
        store = _installStore(
          entries: [original, retained],
          tombstones: _existingTombstones,
        );
        final provider = createProvider();
        await provider.loadFromStorage();
        var notifications = 0;
        var callbacks = 0;
        provider.addListener(() => notifications++);
        provider.onLocalMutationPersisted = () => callbacks++;
        final rejectedWrite = store.planSet(
          key: rejectedKey,
          hold: true,
          reject: true,
        );
        final deletion = expectLater(
          provider.delete(original.id),
          throwsStateError,
        );
        await rejectedWrite.entered.future.timeout(_timeout);
        final concurrent = CloudSyncProvider.recordDeletedItem(
          'habits',
          'other-collection',
        );
        await _nextTurn();
        _expectEntries(provider.entries, [original, retained]);
        expect(notifications, 0);
        expect(callbacks, 0);
        rejectedWrite.release.complete();
        await Future.wait([deletion, concurrent]);

        _expectEntries(provider.entries, [original, retained]);
        _expectEntries(await store.readEntries(), [original, retained]);
        _expectEntries((await reloadProvider()).entries, [original, retained]);
        final tombstones = await store.readTombstones();
        expect(tombstones['time_entries'], isNull);
        expect(tombstones['todos'], _existingTombstones['todos']);
        expect(tombstones['habits'], contains('other-collection'));
        expect(notifications, 0);
        expect(callbacks, 0);
        expect(store.maxActiveSets, 1);
      },
    );
  }

  test(
    'a boundary cancels writes with an unchanged owner instead of reporting success',
    () async {
      final original = _entry('same-owner');
      store = _installStore(entries: [original]);
      final provider = createProvider();
      await provider.loadFromStorage();
      final storageGeneration = provider.storageGeneration;
      final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
      var notifications = 0;
      var callbacks = 0;
      provider.addListener(() => notifications++);
      provider.onLocalMutationPersisted = () => callbacks++;
      final write = store.planSet(key: _entriesKey, hold: true);
      final update = expectLater(
        provider.update(original.copyWith(title: 'canceled by boundary')),
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      await write.entered.future.timeout(_timeout);
      final boundaryEntered = Completer<void>();
      final releaseBoundary = Completer<void>();
      manualGates.add(releaseBoundary);
      final boundary = AccountLocalDataCleaner.runPreferenceBoundary(() async {
        boundaryEntered.complete();
        await releaseBoundary.future;
      });
      await _nextTurn();
      expect(boundaryEntered.isCompleted, isFalse);
      write.release.complete();
      await update;
      await boundaryEntered.future.timeout(_timeout);
      await expectLater(
        provider.add(_entry('during-boundary')),
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );

      expect(provider.storageGeneration, storageGeneration);
      expect(AccountLocalDataCleaner.accountDataGeneration, accountGeneration);
      _expectEntries(provider.entries, [original]);
      _expectEntries(await store.readEntries(), [original]);
      expect(notifications, 0);
      expect(callbacks, 0);
      releaseBoundary.complete();
      await boundary;
      _expectEntries((await reloadProvider()).entries, [original]);
      final fresh = _entry('after-boundary');
      await provider.add(fresh);
      _expectEntries(await store.readEntries(), [original, fresh]);
    },
  );

  test(
    'an update queued after deletion fails instead of recreating its ID',
    () async {
      final original = _entry('deleted-before-update');
      store = _installStore(entries: [original]);
      final provider = createProvider();
      await provider.loadFromStorage();
      var notifications = 0;
      var callbacks = 0;
      provider.addListener(() => notifications++);
      provider.onLocalMutationPersisted = () => callbacks++;
      final write = store.planSet(hold: true);
      final deletion = provider.delete(original.id);
      await write.entered.future.timeout(_timeout);
      final update = expectLater(
        provider.update(original.copyWith(title: 'must not resurrect')),
        throwsStateError,
      );
      write.release.complete();
      await Future.wait([deletion, update]);

      expect(provider.entries, isEmpty);
      expect(await store.readEntries(), isEmpty);
      expect((await reloadProvider()).entries, isEmpty);
      expect(
        (await store.readTombstones())['time_entries'],
        contains(original.id),
      );
      expect(store.setKeys, hasLength(2));
      expect(notifications, 1);
      expect(callbacks, 1);
    },
  );

  for (final interruption in ['reset', 'dispose']) {
    test(
      '$interruption in the commit callback prevents an old generation notification',
      () async {
        final provider = createProvider();
        final entry = _entry('committed-before-$interruption');
        final originalGeneration = provider.storageGeneration;
        final notificationGenerations = <int>[];
        var callbacks = 0;
        provider.addListener(() {
          notificationGenerations.add(provider.storageGeneration);
        });
        provider.onLocalMutationPersisted = () {
          callbacks++;
          if (interruption == 'reset') {
            provider.resetLocalState();
          } else {
            provider.dispose();
          }
        };

        await provider.add(entry);

        expect(callbacks, 1);
        expect(notificationGenerations, isNot(contains(originalGeneration)));
        expect(
          notificationGenerations,
          hasLength(interruption == 'reset' ? 1 : 0),
        );
        if (interruption == 'reset') expect(provider.entries, isEmpty);
        _expectEntries(await store.readEntries(), [entry]);
        _expectEntries((await reloadProvider()).entries, [entry]);
      },
    );
  }
}

const _existingTombstones = <String, Map<String, String>>{
  'todos': {'already-deleted': '2026-10-18T09:00:00.000'},
};

_ControlledStore _installStore({
  List<TimeEntry> entries = const [],
  Map<String, Map<String, String>>? tombstones,
}) {
  final values = <String, Object>{
    if (entries.isNotEmpty)
      TimeAuditProvider.storageKey: entries
          .map((entry) => jsonEncode(entry.toJson()))
          .toList(),
    if (tombstones != null) 'sync_deleted_items': jsonEncode(tombstones),
  };
  SharedPreferences.setMockInitialValues(values);
  final store = _ControlledStore({
    for (final entry in values.entries) 'flutter.${entry.key}': entry.value,
  });
  SharedPreferencesStorePlatform.instance = store;
  return store;
}

TimeEntry _entry(String id) => TimeEntry(
  id: id,
  title: id,
  startAt: DateTime(2026, 10, 19, 9),
  endAt: DateTime(2026, 10, 19, 9, 30),
  category: TimeEntryCategory.study,
  createdAt: DateTime(2026, 10, 19, 8),
  updatedAt: DateTime(2026, 10, 19, 8),
);

void _expectEntries(Iterable<TimeEntry> actual, Iterable<TimeEntry> expected) {
  expect(
    {for (final entry in actual) entry.id: jsonEncode(entry.toJson())},
    {for (final entry in expected) entry.id: jsonEncode(entry.toJson())},
  );
  expect(actual.length, expected.length, reason: 'IDs must remain unique');
}

Future<void> _nextTurn() => Future<void>.delayed(Duration.zero);

class _ControlledStore extends InMemorySharedPreferencesStore {
  _ControlledStore(super.values) : super.withData();

  final _planned = <_WriteStep>[];
  final _allSteps = <_WriteStep>[];
  final setKeys = <String>[];
  int _activeSets = 0;
  int maxActiveSets = 0;

  int get entrySetCalls => setKeys.where((key) => key == _entriesKey).length;

  _WriteStep planSet({
    String? key,
    bool hold = false,
    bool reject = false,
    bool throwError = false,
  }) {
    final step = _WriteStep(
      key: key,
      hold: hold,
      reject: reject,
      throwError: throwError,
    );
    _planned.add(step);
    _allSteps.add(step);
    return step;
  }

  void releaseAll() {
    for (final step in _allSteps) {
      if (!step.release.isCompleted) step.release.complete();
    }
  }

  // Read the platform store itself, bypassing SharedPreferences' eager cache.
  Future<Map<String, Object>> readDisk() => super.getAll();

  Future<List<TimeEntry>> readEntries() async {
    final raw = (await readDisk())[_entriesKey];
    if (raw == null) return [];
    return (raw as List).cast<String>().map((encoded) {
      return TimeEntry.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
    }).toList();
  }

  Future<Map<String, dynamic>> readTombstones() async {
    final raw = (await readDisk())[_tombstonesKey] as String?;
    return raw == null ? {} : jsonDecode(raw) as Map<String, dynamic>;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    setKeys.add(key);
    _activeSets++;
    if (_activeSets > maxActiveSets) maxActiveSets = _activeSets;
    try {
      final index = _planned.indexWhere(
        (step) => step.key == null || step.key == key,
      );
      if (index >= 0) {
        final step = _planned.removeAt(index);
        step.entered.complete();
        if (step.hold) await step.release.future;
        if (step.throwError) {
          throw StateError('Injected platform write failure');
        }
        if (step.reject) return false;
      }
      return await super.setValue(valueType, key, value);
    } finally {
      _activeSets--;
    }
  }
}

class _WriteStep {
  _WriteStep({
    required this.key,
    required this.hold,
    required this.reject,
    required this.throwError,
  });

  final String? key;
  final bool hold;
  final bool reject;
  final bool throwError;
  final entered = Completer<void>();
  final release = Completer<void>();
}
