// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/models/location_reminder.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _key = 'duoyi_location_reminders_v1';
const _platformKey = 'flutter.$_key';
const _wait = Duration(seconds: 2);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _LocationStore store;
  late SharedPreferences prefs;
  late LocationReminderProvider provider;
  var disposed = false;

  setUp(() async {
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = _LocationStore();
    SharedPreferencesStorePlatform.instance = store;
    prefs = await SharedPreferences.getInstance();
    await AccountLocalDataCleaner.clearSharedPreferences();
    provider = LocationReminderProvider();
    disposed = false;
  });

  tearDown(() async {
    store.releaseAll();
    await AccountPreferenceWrites.drain();
    if (!disposed) provider.dispose();
  });

  Future<String> seedExisting({bool load = true}) async {
    // Preserve whitespace as well as records when a transaction rolls back.
    final raw = '[\n  ${jsonEncode(_reminder('existing').toJson())}\n]\n';
    await prefs.setString(_key, raw);
    store.resetTracking();
    if (load) await provider.loadFromStorage();
    return raw;
  }

  Future<void> expectStorage(String? raw) async {
    expect(prefs.getString(_key), raw, reason: 'SharedPreferences cache');
    expect(await store.diskRaw(), raw, reason: 'platform backing storage');
    await prefs.reload();
    expect(prefs.getString(_key), raw, reason: 'freshly reloaded storage');
  }

  test(
    'loaded add stages its snapshot until durable acknowledgement',
    () async {
      final originalRaw = await seedExisting();
      final effects = _Effects(provider);
      final originalMemory = _snapshot(provider);
      final gate = store.holdNext();
      var completed = false;

      final saving = provider
          .add(_reminder('new'))
          .then((_) => completed = true);
      await gate.started.future.timeout(_wait);

      expect(_snapshot(provider), originalMemory);
      expect(await store.diskRaw(), originalRaw);
      expect(completed, isFalse);
      expect(effects.notifications, 0);
      expect(effects.persisted, 0);

      gate.release.complete();
      await saving;

      expect(completed, isTrue);
      expect(_ids(provider), ['existing', 'new']);
      expect(_storedIds(prefs), ['existing', 'new']);
      expect(await store.diskRaw(), prefs.getString(_key));
      expect(effects.notifications, 1);
      expect(effects.persisted, 1);
    },
  );

  test(
    'cold add preserves durable records without publishing its draft',
    () async {
      await seedExisting(load: false);
      final effects = _Effects(provider);
      final gate = store.holdNext();

      final saving = provider.add(_reminder('cold-new'));
      await gate.started.future.timeout(_wait);
      expect(_ids(provider), isNot(contains('cold-new')));
      expect(effects.notifications, 0);
      expect(effects.persisted, 0);

      gate.release.complete();
      await saving;

      expect(_ids(provider), ['existing', 'cold-new']);
      expect(_storedIds(prefs), ['existing', 'cold-new']);
      expect(provider.isLoaded, isTrue);
      expect(effects.notifications, 1);
      expect(effects.persisted, 1);
    },
  );

  for (final failure in _Failure.values) {
    for (final existingKey in [false, true]) {
      test(
        'add ${failure.name}, existing key=$existingKey restores exactly and retries the stable ID',
        () async {
          final originalRaw = existingKey ? await seedExisting() : null;
          if (!existingKey) await provider.loadFromStorage();
          final originalMemory = _snapshot(provider);
          final effects = _Effects(provider);
          final reminder = _reminder('retry-same-id');
          store.failure = failure;

          await expectLater(provider.add(reminder), throwsStateError);

          expect(_snapshot(provider), originalMemory);
          await expectStorage(originalRaw);
          expect(effects.notifications, 0);
          expect(effects.persisted, 0);

          await provider.add(reminder);
          await provider.add(LocationReminder.fromJson(reminder.toJson()));

          final expectedIds = [if (existingKey) 'existing', reminder.id];
          expect(_ids(provider), expectedIds);
          expect(_storedIds(prefs), expectedIds);
          expect(effects.notifications, 1);
          expect(effects.persisted, 1);
        },
      );
    }
  }

  test(
    'cold rejected add leaves the durable records intact for retry',
    () async {
      final originalRaw = await seedExisting(load: false);
      final effects = _Effects(provider);
      final reminder = _reminder('cold-retry');
      store.failure = _Failure.writeThenThrow;

      await expectLater(provider.add(reminder), throwsStateError);

      expect(_ids(provider), isNot(contains(reminder.id)));
      await expectStorage(originalRaw);
      expect(effects.notifications, 0);
      expect(effects.persisted, 0);

      await provider.add(reminder);
      expect(_ids(provider), ['existing', 'cold-retry']);
      expect(_storedIds(prefs), ['existing', 'cold-retry']);
      expect(effects.notifications, 1);
      expect(effects.persisted, 1);
    },
  );

  test('two queued adds read the preceding acknowledged snapshot', () async {
    await seedExisting();
    final effects = _Effects(provider);
    final firstGate = store.holdNext();
    final secondGate = store.holdNext();

    final first = provider.add(_reminder('first'));
    await firstGate.started.future.timeout(_wait);
    final second = provider.add(_reminder('second'));
    await Future<void>.delayed(Duration.zero);
    expect(store.setAttempts, 1);
    expect(_ids(provider), ['existing']);

    firstGate.release.complete();
    await first;
    await secondGate.started.future.timeout(_wait);
    expect(store.setAttempts, 2);
    expect(_ids(provider), ['existing', 'first']);
    expect(
      (jsonDecode((await store.diskRaw())!) as List).map(
        (item) => (item as Map)['id'],
      ),
      ['existing', 'first'],
      reason: 'backing storage still contains only the first acknowledged add',
    );
    expect(effects.notifications, 1);
    expect(effects.persisted, 1);

    secondGate.release.complete();
    await second;
    expect(_ids(provider), ['existing', 'first', 'second']);
    expect(_storedIds(prefs), ['existing', 'first', 'second']);
    expect(effects.notifications, 2);
    expect(effects.persisted, 2);
  });

  test(
    'a rejected first add cannot leak into its successful queued follower',
    () async {
      await seedExisting();
      final effects = _Effects(provider);
      final gate = store.holdNext();
      store.failure = _Failure.writeThenFalse;
      final firstRejected = expectLater(
        provider.add(_reminder('rejected')),
        throwsStateError,
      );
      await gate.started.future.timeout(_wait);
      final follower = provider.add(_reminder('accepted'));

      gate.release.complete();
      await Future.wait([firstRejected, follower]);

      expect(_ids(provider), ['existing', 'accepted']);
      expect(_storedIds(prefs), ['existing', 'accepted']);
      expect(effects.notifications, 1);
      expect(effects.persisted, 1);
      await provider.add(_reminder('rejected'));
      expect(_storedIds(prefs), ['existing', 'accepted', 'rejected']);
    },
  );

  for (final invalidation in ['reset', 'dispose', 'account', 'authority']) {
    test('$invalidation cancels a held add and its queued follower', () async {
      final originalRaw = await seedExisting();
      final originalMemory = _snapshot(provider);
      final generation = provider.storageGeneration;
      final effects = _Effects(provider);
      var current = true;
      final gate = store.holdNext();
      final firstRejected = expectLater(
        provider.add(_reminder('departing'), isCurrent: () => current),
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      await gate.started.future.timeout(_wait);
      final followerRejected = expectLater(
        provider.add(_reminder('queued-old'), isCurrent: () => current),
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );

      switch (invalidation) {
        case 'reset':
          provider.resetLocalState();
        case 'dispose':
          provider.dispose();
          disposed = true;
        case 'account':
          AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        case 'authority':
          current = false;
      }
      gate.release.complete();
      await Future.wait([firstRejected, followerRejected]);

      await expectStorage(originalRaw);
      expect(
        _snapshot(provider),
        invalidation == 'reset' ? [] : originalMemory,
      );
      expect(effects.notifications, invalidation == 'reset' ? 1 : 0);
      expect(effects.persisted, 0);
      expect(store.setAttempts, 2, reason: 'issued draft plus exact rollback');
      expect(
        provider.storageGeneration,
        generation +
            (invalidation == 'reset' || invalidation == 'dispose' ? 1 : 0),
      );
    });
  }

  for (final invalidation in ['reset', 'dispose', 'account', 'authority']) {
    test(
      '$invalidation before the queued add starts issues no write',
      () async {
        final originalRaw = await seedExisting();
        final effects = _Effects(provider);
        var current = true;
        final rejected = expectLater(
          provider.add(_reminder('never-started'), isCurrent: () => current),
          throwsA(isA<AccountPreferenceWriteCanceled>()),
        );
        switch (invalidation) {
          case 'reset':
            provider.resetLocalState();
          case 'dispose':
            provider.dispose();
            disposed = true;
          case 'account':
            AccountLocalDataCleaner.invalidateInFlightAccountWrites();
          case 'authority':
            current = false;
        }
        await rejected;

        await expectStorage(originalRaw);
        expect(store.setAttempts, 0);
        expect(_ids(provider), invalidation == 'reset' ? [] : ['existing']);
        expect(effects.notifications, invalidation == 'reset' ? 1 : 0);
        expect(effects.persisted, 0);
      },
    );
  }

  test(
    'account cleanup drains the issued add before clearing account storage',
    () async {
      await seedExisting();
      final effects = _Effects(provider);
      final gate = store.holdNext();
      final firstRejected = expectLater(
        provider.add(_reminder('departing')),
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      await gate.started.future.timeout(_wait);
      final followerRejected = expectLater(
        provider.add(_reminder('queued-old')),
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      var cleaned = false;
      final cleanup = AccountLocalDataCleaner.runPreferenceBoundary(() async {
        provider.resetLocalState();
        await AccountLocalDataCleaner.clearSharedPreferences();
        cleaned = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(cleaned, isFalse);

      gate.release.complete();
      await Future.wait([firstRejected, followerRejected, cleanup]);

      expect(cleaned, isTrue);
      await expectStorage(null);
      expect(provider.reminders, isEmpty);
      expect(effects.notifications, 1);
      expect(effects.persisted, 0);

      await provider.add(_reminder('new-account'));
      expect(_ids(provider), ['new-account']);
      expect(_storedIds(prefs), ['new-account']);
    },
  );

  test(
    'expired authority rejects an add before changing cache or disk',
    () async {
      final originalRaw = await seedExisting();
      final originalMemory = _snapshot(provider);
      final effects = _Effects(provider);

      await expectLater(
        provider.add(_reminder('blocked'), isCurrent: () => false),
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );

      expect(_snapshot(provider), originalMemory);
      await expectStorage(originalRaw);
      expect(store.setAttempts, 0);
      expect(effects.notifications, 0);
      expect(effects.persisted, 0);
    },
  );

  test(
    'same-generation provider replacement cancels only the departing lease',
    () async {
      await seedExisting();
      final originalMemory = _snapshot(provider);
      final oldEffects = _Effects(provider);
      final replacement = LocationReminderProvider();
      addTearDown(replacement.dispose);
      final newEffects = _Effects(replacement);
      LocationReminderProvider currentProvider = provider;
      final oldProvider = provider;
      expect(oldProvider.storageGeneration, replacement.storageGeneration);
      final gate = store.holdNext();
      final oldRejected = expectLater(
        oldProvider.add(
          _reminder('departing'),
          isCurrent: () => identical(currentProvider, oldProvider),
        ),
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      await gate.started.future.timeout(_wait);

      currentProvider = replacement;
      final replacementSaving = replacement.add(
        _reminder('replacement-new'),
        isCurrent: () => identical(currentProvider, replacement),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        store.setAttempts,
        1,
        reason: 'replacement shares the storage queue',
      );

      gate.release.complete();
      await Future.wait([oldRejected, replacementSaving]);

      expect(_snapshot(oldProvider), originalMemory);
      expect(_ids(replacement), ['existing', 'replacement-new']);
      expect(_storedIds(prefs), ['existing', 'replacement-new']);
      expect(oldEffects.notifications, 0);
      expect(oldEffects.persisted, 0);
      expect(newEffects.notifications, 1);
      expect(newEffects.persisted, 1);
    },
  );

  test(
    'two live providers serialize adds without losing either durable record',
    () async {
      await seedExisting();
      final replacement = LocationReminderProvider();
      addTearDown(replacement.dispose);
      await replacement.loadFromStorage();
      final firstGate = store.holdNext();
      final first = provider.add(_reminder('first-provider'));
      await firstGate.started.future.timeout(_wait);
      final second = replacement.add(_reminder('second-provider'));
      await Future<void>.delayed(Duration.zero);
      expect(store.setAttempts, 1);

      firstGate.release.complete();
      await Future.wait([first, second]);

      expect(_storedIds(prefs), [
        'existing',
        'first-provider',
        'second-provider',
      ]);
      expect(_ids(replacement), [
        'existing',
        'first-provider',
        'second-provider',
      ]);
    },
  );

  test(
    'a throwing origin guard cancels before changing cache or disk',
    () async {
      final originalRaw = await seedExisting();
      final originalMemory = _snapshot(provider);
      final effects = _Effects(provider);

      await expectLater(
        provider.add(
          _reminder('blocked'),
          isCurrent: () => throw StateError('origin lease is unavailable'),
        ),
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );

      expect(_snapshot(provider), originalMemory);
      await expectStorage(originalRaw);
      expect(store.setAttempts, 0);
      expect(effects.notifications, 0);
      expect(effects.persisted, 0);
    },
  );

  test(
    'identical stable-ID retry is a no-op after acknowledged insertion',
    () async {
      final reminder = _reminder('stable');
      await provider.add(reminder);
      final originalRaw = prefs.getString(_key);
      final originalMemory = _snapshot(provider);
      store.resetTracking();
      final effects = _Effects(provider);

      await provider.add(LocationReminder.fromJson(reminder.toJson()));

      expect(_snapshot(provider), originalMemory);
      await expectStorage(originalRaw);
      expect(store.setAttempts, 0);
      expect(effects.notifications, 0);
      expect(effects.persisted, 0);
    },
  );

  test(
    'queued identical stable-ID adds publish exactly one insertion',
    () async {
      await provider.loadFromStorage();
      final effects = _Effects(provider);
      final reminder = _reminder('stable');
      final gate = store.holdNext();
      final first = provider.add(reminder);
      await gate.started.future.timeout(_wait);
      final retry = provider.add(LocationReminder.fromJson(reminder.toJson()));

      gate.release.complete();
      await Future.wait([first, retry]);

      expect(_ids(provider), ['stable']);
      expect(_storedIds(prefs), ['stable']);
      expect(store.setAttempts, 1);
      expect(effects.notifications, 1);
      expect(effects.persisted, 1);
    },
  );

  for (final existingKey in [false, true]) {
    test(
      'failed compensation, existing key=$existingKey blocks blind retry until explicit reconciliation',
      () async {
        final originalRaw = existingKey ? await seedExisting() : null;
        if (!existingKey) await provider.loadFromStorage();
        final originalMemory = _snapshot(provider);
        final effects = _Effects(provider);
        final reminder = _reminder('uncertain');
        store.failure = _Failure.writeThenFalse;
        if (existingKey) {
          store.followingFailures.add(_Failure.returnsFalse);
        } else {
          store.rejectNextRemove = true;
        }

        await expectLater(
          provider.add(reminder),
          throwsA(isA<LocationReminderStorageIndeterminate>()),
        );
        expect(provider.storageNeedsReconciliation, isTrue);
        expect(_snapshot(provider), originalMemory);
        final issuedRaw = await store.diskRaw();
        expect(issuedRaw, isNot(originalRaw));
        expect(effects.notifications, 0);
        expect(effects.persisted, 0);
        final attemptsBeforeRetry = store.setAttempts;

        final replacement = LocationReminderProvider();
        addTearDown(replacement.dispose);
        expect(replacement.storageNeedsReconciliation, isTrue);
        final blockedOperations = <Future<dynamic> Function()>[
          () => provider.add(reminder),
          () => replacement.add(reminder),
          provider.loadFromStorage,
          () => provider.update(_reminder('existing')),
          () => provider.remove('existing'),
          () => provider.ingestFix(
            LocationFix(
              latitude: 39.9042,
              longitude: 116.4074,
              at: DateTime.utc(2026, 11, 9, 11),
            ),
          ),
        ];
        for (final operation in blockedOperations) {
          await expectLater(
            operation(),
            throwsA(isA<LocationReminderStorageIndeterminate>()),
          );
        }
        expect(store.setAttempts, attemptsBeforeRetry);
        expect(await store.diskRaw(), issuedRaw);
        expect(_snapshot(provider), originalMemory);
        expect(effects.notifications, 0);
        expect(effects.persisted, 0);

        await provider.reconcileStorage();

        expect(provider.storageNeedsReconciliation, isFalse);
        expect(replacement.storageNeedsReconciliation, isFalse);
        expect(_snapshot(provider), originalMemory);
        await expectStorage(originalRaw);
        expect(effects.notifications, 1);
        expect(effects.persisted, 0);

        await provider.add(reminder);
        expect(_ids(provider), [if (existingKey) 'existing', 'uncertain']);
        expect(_storedIds(prefs), [if (existingKey) 'existing', 'uncertain']);
        expect(effects.notifications, 2);
        expect(effects.persisted, 1);
      },
    );
  }

  test(
    'a failed explicit restoration stays blocked and can be reconciled again',
    () async {
      final originalRaw = await seedExisting();
      final originalMemory = _snapshot(provider);
      final effects = _Effects(provider);
      store.failure = _Failure.writeThenThrow;
      store.followingFailures.add(_Failure.returnsFalse);
      await expectLater(
        provider.add(_reminder('uncertain')),
        throwsA(isA<LocationReminderStorageIndeterminate>()),
      );
      final issuedRaw = await store.diskRaw();
      store.failure = _Failure.returnsFalse;

      await expectLater(
        provider.reconcileStorage(),
        throwsA(isA<LocationReminderStorageIndeterminate>()),
      );

      expect(provider.storageNeedsReconciliation, isTrue);
      expect(await store.diskRaw(), issuedRaw);
      expect(_snapshot(provider), originalMemory);
      expect(effects.notifications, 0);
      expect(effects.persisted, 0);
      await expectLater(
        provider.add(_reminder('different-draft')),
        throwsA(isA<LocationReminderStorageIndeterminate>()),
      );

      await provider.reconcileStorage();

      await expectStorage(originalRaw);
      expect(provider.storageNeedsReconciliation, isFalse);
      expect(_snapshot(provider), originalMemory);
      expect(effects.notifications, 1);
      expect(effects.persisted, 0);
    },
  );

  test(
    'reconciliation refuses an independent writer and preserves its data',
    () async {
      final originalRaw = await seedExisting();
      final originalMemory = _snapshot(provider);
      final effects = _Effects(provider);
      store.failure = _Failure.writeThenFalse;
      store.followingFailures.add(_Failure.returnsFalse);
      await expectLater(
        provider.add(_reminder('uncertain')),
        throwsA(isA<LocationReminderStorageIndeterminate>()),
      );
      final independentRaw = jsonEncode([
        _reminder('existing').toJson(),
        _reminder('independent').toJson(),
      ]);
      await store.writeIndependentRaw(independentRaw);
      final attemptsBeforeReconcile = store.setAttempts;

      await expectLater(
        provider.reconcileStorage(),
        throwsA(isA<LocationReminderStorageIndeterminate>()),
      );

      await expectStorage(independentRaw);
      expect(store.setAttempts, attemptsBeforeReconcile);
      expect(provider.storageNeedsReconciliation, isTrue);
      expect(_snapshot(provider), originalMemory);
      expect(effects.notifications, 0);
      expect(effects.persisted, 0);

      // Simulate the independent writer restoring the agreed baseline.
      await store.writeIndependentRaw(originalRaw);
      await provider.reconcileStorage();
      expect(provider.storageNeedsReconciliation, isFalse);
      await expectStorage(originalRaw);
    },
  );

  for (final changedField in ['title', 'latitude', 'linkedId', 'updatedAt']) {
    test(
      'stable-ID collision in $changedField preserves the original record',
      () async {
        final original = _reminder('collision');
        await provider.add(original);
        final originalRaw = prefs.getString(_key);
        final originalMemory = _snapshot(provider);
        final changedJson = original.toJson();
        switch (changedField) {
          case 'title':
            changedJson['title'] = 'A different reminder';
          case 'latitude':
            changedJson['latitude'] = 1.25;
          case 'linkedId':
            changedJson['linkedId'] = 'different-todo';
          case 'updatedAt':
            changedJson['updatedAt'] = DateTime.utc(
              2026,
              11,
              10,
            ).toIso8601String();
        }
        store.resetTracking();
        final effects = _Effects(provider);

        await expectLater(
          provider.add(LocationReminder.fromJson(changedJson)),
          throwsStateError,
        );

        expect(_snapshot(provider), originalMemory);
        await expectStorage(originalRaw);
        expect(store.setAttempts, 0);
        expect(effects.notifications, 0);
        expect(effects.persisted, 0);
      },
    );
  }
}

LocationReminder _reminder(String id) => LocationReminder(
  id: id,
  title: '到公司提醒 $id',
  note: '保留原文 / $id',
  latitude: 39.9042,
  longitude: 116.4074,
  radiusMeters: 250,
  trigger: LocationTrigger.enter,
  oneShot: false,
  linkedType: 'todo',
  linkedId: 'todo-$id',
  createdAt: DateTime.utc(2026, 11, 9, 10),
  updatedAt: DateTime.utc(2026, 11, 9, 10),
);

List<String> _ids(LocationReminderProvider provider) =>
    provider.reminders.map((reminder) => reminder.id).toList();

List<Map<String, dynamic>> _snapshot(LocationReminderProvider provider) =>
    provider.reminders.map((reminder) => reminder.toJson()).toList();

List<String> _storedIds(SharedPreferences prefs) =>
    ((jsonDecode(prefs.getString(_key) ?? '[]')) as List)
        .map((item) => (item as Map)['id'] as String)
        .toList();

class _Effects {
  _Effects(LocationReminderProvider provider) {
    provider.addListener(() => notifications++);
    provider.onLocalMutationPersisted = () => persisted++;
  }

  int notifications = 0;
  int persisted = 0;
}

enum _Failure {
  returnsFalse,
  throwsBeforeWrite,
  writeThenFalse,
  writeThenThrow,
}

class _HeldWrite {
  final started = Completer<void>();
  final release = Completer<void>();
}

class _LocationStore extends InMemorySharedPreferencesStore {
  _LocationStore() : super.withData(<String, Object>{});

  _Failure? failure;
  final followingFailures = <_Failure>[];
  bool rejectNextRemove = false;
  int setAttempts = 0;
  final _queuedHolds = <_HeldWrite>[];
  final _allHolds = <_HeldWrite>[];

  _HeldWrite holdNext() {
    final gate = _HeldWrite();
    _queuedHolds.add(gate);
    _allHolds.add(gate);
    return gate;
  }

  void releaseAll() {
    for (final gate in _allHolds) {
      if (!gate.release.isCompleted) gate.release.complete();
    }
  }

  void resetTracking() => setAttempts = 0;

  Future<String?> diskRaw() async => (await getAll())[_platformKey] as String?;

  Future<void> writeIndependentRaw(String raw) async {
    await super.setValue('String', _platformKey, raw);
  }

  @override
  Future<bool> remove(String key) async {
    if (key == _platformKey && rejectNextRemove) {
      rejectNextRemove = false;
      return false;
    }
    return super.remove(key);
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key != _platformKey) return super.setValue(type, key, value);
    setAttempts++;
    final thisFailure =
        failure ??
        (followingFailures.isEmpty ? null : followingFailures.removeAt(0));
    failure = null;
    if (_queuedHolds.isNotEmpty) {
      final gate = _queuedHolds.removeAt(0);
      gate.started.complete();
      await gate.release.future;
    }
    if (thisFailure == _Failure.returnsFalse) return false;
    if (thisFailure == _Failure.throwsBeforeWrite) {
      throw StateError('synthetic location write failure before disk change');
    }
    await super.setValue(type, key, value);
    if (thisFailure == _Failure.writeThenFalse) return false;
    if (thisFailure == _Failure.writeThenThrow) {
      throw StateError('synthetic location write failure after disk change');
    }
    return true;
  }
}
