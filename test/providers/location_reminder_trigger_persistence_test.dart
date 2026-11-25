// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/models/location_reminder.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _remindersKey = 'duoyi_location_reminders_v1';
const _deletedKey = CloudSyncProvider.deletedItemsStorageKey;
const _wait = Duration(seconds: 2);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _TriggerStore store;
  late SharedPreferences prefs;
  late LocationReminderProvider provider;
  var disposed = false;

  setUp(() async {
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = _TriggerStore();
    SharedPreferencesStorePlatform.instance = store;
    prefs = await SharedPreferences.getInstance();
    provider = LocationReminderProvider();
    disposed = false;
  });

  tearDown(() async {
    store.releaseAll();
    await AccountPreferenceWrites.drain();
    if (!disposed) provider.dispose();
  });

  Future<Map<String, String>> seed(List<LocationReminder> reminders) async {
    final raws = <String, String>{
      _remindersKey:
          '${const JsonEncoder.withIndent('  ').convert(reminders.map((r) => r.toJson()).toList())}\n',
      _deletedKey: '{\n  "todos": {"keep": "2026-11-01T12:00:00.000Z"}\n}\n',
    };
    for (final entry in raws.entries) {
      await prefs.setString(entry.key, entry.value);
    }
    await provider.loadFromStorage();
    store.writes.clear();
    return raws;
  }

  Future<void> expectRawStorage(Map<String, String> raws) async {
    for (final entry in raws.entries) {
      expect(
        prefs.getString(entry.key),
        entry.value,
        reason: 'cached ${entry.key}',
      );
      expect(
        await store.diskRaw(entry.key),
        entry.value,
        reason: 'durable ${entry.key}',
      );
    }
    await prefs.reload();
    for (final entry in raws.entries) {
      expect(
        prefs.getString(entry.key),
        entry.value,
        reason: 'reloaded ${entry.key}',
      );
    }
  }

  for (final oneShot in [false, true]) {
    test(
      'trigger oneShot=$oneShot publishes hits only after acknowledgement',
      () async {
        final reminder = _reminder(oneShot: oneShot);
        final raws = await seed([reminder]);
        final originalMemory = _snapshot(provider);
        final effects = _Effects(provider);
        final gate = store.holdNext(_remindersKey);
        var completed = false;
        final triggering = provider.ingestFix(_inside()).then((hits) {
          completed = true;
          return hits;
        });
        await gate.started.future.timeout(_wait);

        expect(completed, isFalse);
        expect(_snapshot(provider), originalMemory);
        expect(await store.diskRaw(_remindersKey), raws[_remindersKey]);
        expect(effects.notifications, 0);
        expect(effects.persisted, 0);

        gate.release.complete();
        final hits = await triggering;

        expect(hits.map((hit) => hit.reminder.id), [reminder.id]);
        expect(hits.single.fix.at, _inside().at);
        expect(effects.notifications, 1);
        expect(effects.persisted, 1);
        expect(_tombstones(prefs)['todos'], contains('keep'));
        if (oneShot) {
          expect(provider.reminders, isEmpty);
          expect(_storedReminders(prefs), isEmpty);
          expect(
            _tombstones(prefs)['location_reminders'],
            contains(reminder.id),
          );
        } else {
          expect(provider.reminders.single.lastFiredAt, _inside().at);
          expect(_storedReminders(prefs).single.lastFiredAt, _inside().at);
          expect(prefs.getString(_deletedKey), raws[_deletedKey]);
        }
      },
    );
  }

  for (final operation in ['delete', 'one-shot trigger']) {
    for (final rejectedKey in [_deletedKey, _remindersKey]) {
      for (final throws in [false, true]) {
        test(
          '$operation rejects $rejectedKey throws=$throws and restores both keys',
          () async {
            final reminder = _reminder(oneShot: true);
            final raws = await seed([reminder]);
            final originalMemory = _snapshot(provider);
            final effects = _Effects(provider);
            store.rejectNext(rejectedKey, throws: throws);

            if (operation == 'delete') {
              await expectLater(provider.remove(reminder.id), throwsStateError);
            } else {
              await expectLater(
                provider.ingestFix(_inside()),
                throwsStateError,
              );
            }

            expect(_snapshot(provider), originalMemory);
            await expectRawStorage(raws);
            expect(effects.notifications, 0);
            expect(effects.persisted, 0);

            if (operation == 'delete') {
              await provider.remove(reminder.id);
            } else {
              final retryHits = await provider.ingestFix(_inside());
              expect(retryHits.map((hit) => hit.reminder.id), [reminder.id]);
            }
            expect(provider.reminders, isEmpty);
            expect(_storedReminders(prefs), isEmpty);
            expect(_tombstones(prefs)['todos'], contains('keep'));
            expect(
              _tombstones(prefs)['location_reminders'],
              contains(reminder.id),
            );
            expect(effects.notifications, 1);
            expect(effects.persisted, 1);
          },
        );
      }
    }
  }

  for (final throws in [false, true]) {
    test(
      'rejected recurring trigger throws=$throws preserves cooldown and edge for retry',
      () async {
        final reminder = _reminder();
        final raws = await seed([reminder]);
        final originalMemory = _snapshot(provider);
        final effects = _Effects(provider);
        store.rejectNext(_remindersKey, throws: throws);

        await expectLater(provider.ingestFix(_inside()), throwsStateError);

        expect(_snapshot(provider), originalMemory);
        await expectRawStorage(raws);
        expect(effects.notifications, 0);
        expect(effects.persisted, 0);

        final retryHits = await provider.ingestFix(_inside());
        expect(retryHits.map((hit) => hit.reminder.id), [reminder.id]);
        expect(provider.reminders.single.lastFiredAt, _inside().at);
        expect(_storedReminders(prefs).single.lastFiredAt, _inside().at);
        expect(prefs.getString(_deletedKey), raws[_deletedKey]);
        expect(effects.notifications, 1);
        expect(effects.persisted, 1);
        expect(await provider.ingestFix(_inside()), isEmpty);
        expect(effects.notifications, 1);
        expect(effects.persisted, 1);
      },
    );
  }

  test(
    'delete keeps its row visible until both durable writes succeed',
    () async {
      final reminder = _reminder();
      await seed([reminder]);
      final effects = _Effects(provider);
      final originalMemory = _snapshot(provider);
      final gate = store.holdNext(_remindersKey);
      final deleting = provider.remove(reminder.id);
      await gate.started.future.timeout(_wait);

      expect(_snapshot(provider), originalMemory);
      expect(effects.notifications, 0);
      expect(effects.persisted, 0);

      gate.release.complete();
      await deleting;

      expect(provider.reminders, isEmpty);
      expect(_storedReminders(prefs), isEmpty);
      expect(_tombstones(prefs)['location_reminders'], contains(reminder.id));
      expect(effects.notifications, 1);
      expect(effects.persisted, 1);
    },
  );

  test(
    'failed delete rollback preserves a queued tombstone in another collection',
    () async {
      final reminder = _reminder();
      final raws = await seed([reminder]);
      final gate = store.holdNext(_deletedKey);
      store.rejectNext(_remindersKey);
      final deleteRejected = expectLater(
        provider.remove(reminder.id),
        throwsStateError,
      );
      await gate.started.future.timeout(_wait);
      final independentDelete = CloudSyncProvider.recordDeletedItem(
        'notes',
        'independent-note',
      );
      await Future<void>.delayed(Duration.zero);

      gate.release.complete();
      await Future.wait([deleteRejected, independentDelete]);

      expect(prefs.getString(_remindersKey), raws[_remindersKey]);
      expect(provider.reminders.single.id, reminder.id);
      expect(_tombstones(prefs)['location_reminders'], isNull);
      expect(_tombstones(prefs)['todos'], contains('keep'));
      expect(_tombstones(prefs)['notes'], contains('independent-note'));
    },
  );

  for (final invalidation in ['reset', 'dispose', 'account']) {
    test(
      '$invalidation during a one-shot trigger restores row and tombstones',
      () async {
        final reminder = _reminder(oneShot: true);
        final raws = await seed([reminder]);
        final originalMemory = _snapshot(provider);
        final effects = _Effects(provider);
        final gate = store.holdNext(_remindersKey);
        final rejected = expectLater(
          provider.ingestFix(_inside()),
          throwsA(isA<AccountPreferenceWriteCanceled>()),
        );
        await gate.started.future.timeout(_wait);
        switch (invalidation) {
          case 'reset':
            provider.resetLocalState();
          case 'dispose':
            provider.dispose();
            disposed = true;
          case 'account':
            AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        }
        gate.release.complete();
        await rejected;

        await expectRawStorage(raws);
        expect(
          _snapshot(provider),
          invalidation == 'reset' ? [] : originalMemory,
        );
        expect(effects.notifications, invalidation == 'reset' ? 1 : 0);
        expect(effects.persisted, 0);
      },
    );
  }

  test('a queued fix cannot trigger an unacknowledged add', () async {
    await seed([]);
    final effects = _Effects(provider);
    final gate = store.holdNext(_remindersKey);
    final adding = provider.add(_reminder());
    await gate.started.future.timeout(_wait);
    var hitCompleted = false;
    final triggering = provider.ingestFix(_inside()).then((hits) {
      hitCompleted = true;
      return hits;
    });
    await Future<void>.delayed(Duration.zero);
    expect(provider.reminders, isEmpty);
    expect(hitCompleted, isFalse);
    expect(store.writes, [_remindersKey]);
    expect(effects.persisted, 0);

    gate.release.complete();
    await adding;
    final hits = await triggering;

    expect(hits.map((hit) => hit.reminder.id), ['active']);
    expect(provider.reminders.single.lastFiredAt, _inside().at);
    expect(effects.notifications, 2);
    expect(effects.persisted, 2);
  });

  test('a queued fix cannot trigger a rejected add', () async {
    final raws = await seed([]);
    final effects = _Effects(provider);
    final gate = store.holdNext(_remindersKey);
    store.rejectNext(_remindersKey);
    final addRejected = expectLater(
      provider.add(_reminder()),
      throwsStateError,
    );
    await gate.started.future.timeout(_wait);
    final triggering = provider.ingestFix(_inside());

    gate.release.complete();
    await addRejected;
    expect(await triggering, isEmpty);

    await expectRawStorage(raws);
    expect(provider.reminders, isEmpty);
    expect(effects.notifications, 0);
    expect(effects.persisted, 0);
  });

  test(
    'nontriggering fixes retain the leave edge without durable writes',
    () async {
      await seed([_reminder(trigger: LocationTrigger.leave)]);
      final effects = _Effects(provider);

      expect(await provider.ingestFix(_inside()), isEmpty);
      expect(store.writes, isEmpty);
      expect(effects.notifications, 0);
      expect(effects.persisted, 0);

      final leaving = LocationFix(
        latitude: 31.2304,
        longitude: 121.4737,
        at: _inside().at.add(const Duration(minutes: 1)),
      );
      final hits = await provider.ingestFix(leaving);

      expect(hits.single.triggeredBy, LocationTrigger.leave);
      expect(_storedReminders(prefs).single.lastFiredAt, leaving.at);
      expect(effects.notifications, 1);
      expect(effects.persisted, 1);
    },
  );

  test(
    'controller waits for durable trigger acknowledgement before notifying',
    () async {
      await seed([_reminder()]);
      final probe = ManualLocationProbe();
      final hits = <LocationReminderHit>[];
      final controller = LocationReminderController(
        probe: probe,
        provider: provider,
        onHit: hits.add,
      );
      addTearDown(controller.stop);
      await controller.start();
      final gate = store.holdNext(_remindersKey);
      probe.setCurrentLocation(39.9042, 116.4074);
      await gate.started.future.timeout(_wait);
      expect(hits, isEmpty);

      gate.release.complete();
      await AccountPreferenceWrites.drain();
      await Future<void>.delayed(Duration.zero);

      expect(hits.map((hit) => hit.reminder.id), ['active']);
      expect(_storedReminders(prefs).single.lastFiredAt, isNotNull);
    },
  );

  test(
    'controller stop cancels a held trigger and suppresses its notification',
    () async {
      final raws = await seed([_reminder()]);
      final probe = ManualLocationProbe();
      final hits = <LocationReminderHit>[];
      final controller = LocationReminderController(
        probe: probe,
        provider: provider,
        onHit: hits.add,
      );
      addTearDown(controller.stop);
      await controller.start();
      final gate = store.holdNext(_remindersKey);
      probe.setCurrentLocation(39.9042, 116.4074);
      await gate.started.future.timeout(_wait);
      await controller.stop();

      gate.release.complete();
      await AccountPreferenceWrites.drain();
      await Future<void>.delayed(Duration.zero);

      expect(hits, isEmpty);
      expect(probe.isTracking, isFalse);
      expect(_storedReminders(prefs).single.lastFiredAt, isNull);
      await expectRawStorage(raws);
    },
  );

  test(
    'controller suppresses a failed trigger and the next fix can retry',
    () async {
      await seed([_reminder()]);
      final probe = ManualLocationProbe();
      final hits = <LocationReminderHit>[];
      final controller = LocationReminderController(
        probe: probe,
        provider: provider,
        onHit: hits.add,
      );
      addTearDown(controller.stop);
      await controller.start();
      store.rejectNext(_remindersKey);
      probe.setCurrentLocation(39.9042, 116.4074);
      await AccountPreferenceWrites.drain();
      await Future<void>.delayed(Duration.zero);

      expect(hits, isEmpty);
      expect(provider.reminders.single.lastFiredAt, isNull);

      probe.setCurrentLocation(39.9042, 116.4074);
      await AccountPreferenceWrites.drain();
      await Future<void>.delayed(Duration.zero);

      expect(hits.map((hit) => hit.reminder.id), ['active']);
      expect(_storedReminders(prefs).single.lastFiredAt, isNotNull);
    },
  );

  test(
    'account invalidation after commit suppresses the outgoing hit notification',
    () async {
      await seed([_reminder()]);
      final probe = ManualLocationProbe();
      final hits = <LocationReminderHit>[];
      final controller = LocationReminderController(
        probe: probe,
        provider: provider,
        onHit: hits.add,
      );
      addTearDown(controller.stop);
      await controller.start();
      final storageGeneration = provider.storageGeneration;
      provider.onLocalMutationPersisted =
          AccountLocalDataCleaner.invalidateInFlightAccountWrites;

      probe.setCurrentLocation(39.9042, 116.4074);
      await AccountPreferenceWrites.drain();
      await Future<void>.delayed(Duration.zero);

      expect(provider.storageGeneration, storageGeneration);
      expect(_storedReminders(prefs).single.lastFiredAt, isNotNull);
      expect(hits, isEmpty);
    },
  );

  test(
    'stopping the controller from its first hit suppresses later hits',
    () async {
      final second = LocationReminder.fromJson({
        ..._reminder().toJson(),
        'id': 'second',
      });
      await seed([_reminder(), second]);
      final probe = ManualLocationProbe();
      final hits = <LocationReminderHit>[];
      late LocationReminderController controller;
      controller = LocationReminderController(
        probe: probe,
        provider: provider,
        onHit: (hit) {
          hits.add(hit);
          if (hits.length == 1) unawaited(controller.stop());
        },
      );
      addTearDown(controller.stop);
      await controller.start();

      probe.setCurrentLocation(39.9042, 116.4074);
      await AccountPreferenceWrites.drain();
      await Future<void>.delayed(Duration.zero);

      expect(hits.map((hit) => hit.reminder.id), ['active']);
      expect(probe.isTracking, isFalse);
      expect(
        _storedReminders(prefs).every((r) => r.lastFiredAt != null),
        isTrue,
      );
    },
  );

  test(
    'a callback retained by the previous tracking run cannot trigger after restart',
    () async {
      final raws = await seed([_reminder()]);
      final effects = _Effects(provider);
      final probe = _RetainingProbe();
      final hits = <LocationReminderHit>[];
      final controller = LocationReminderController(
        probe: probe,
        provider: provider,
        onHit: hits.add,
      );
      addTearDown(controller.stop);
      await controller.start();
      await controller.stop();
      await controller.start();
      expect(probe.callbacks, hasLength(2));
      expect(probe.isTracking, isTrue);

      probe.callbacks.first(_inside());
      await AccountPreferenceWrites.drain();
      await Future<void>.delayed(Duration.zero);

      await expectRawStorage(raws);
      expect(hits, isEmpty);
      expect(store.writes, isEmpty);
      expect(effects.notifications, 0);
      expect(effects.persisted, 0);

      probe.callbacks.last(_inside());
      await AccountPreferenceWrites.drain();
      await Future<void>.delayed(Duration.zero);

      expect(hits.map((hit) => hit.reminder.id), ['active']);
      expect(_storedReminders(prefs).single.lastFiredAt, _inside().at);
      expect(store.writes, [_remindersKey]);
      expect(effects.notifications, 1);
      expect(effects.persisted, 1);
    },
  );

  test(
    'a retained tracking callback expires when account generation changes',
    () async {
      final raws = await seed([_reminder()]);
      final effects = _Effects(provider);
      final probe = _RetainingProbe();
      final hits = <LocationReminderHit>[];
      final controller = LocationReminderController(
        probe: probe,
        provider: provider,
        onHit: hits.add,
      );
      addTearDown(controller.stop);
      await controller.start();
      final storageGeneration = provider.storageGeneration;
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      expect(provider.storageGeneration, storageGeneration);
      expect(probe.isTracking, isTrue);

      // A plugin can deliver a saved callback before its native subscription
      // has stopped. Its originating account must still be enforced.
      probe.callbacks.single(_inside());
      await AccountPreferenceWrites.drain();
      await Future<void>.delayed(Duration.zero);

      await expectRawStorage(raws);
      expect(hits, isEmpty);
      expect(store.writes, isEmpty);
      expect(effects.notifications, 0);
      expect(effects.persisted, 0);

      await controller.start();
      probe.callbacks.first(_inside());
      probe.callbacks.last(_inside());
      await AccountPreferenceWrites.drain();
      await Future<void>.delayed(Duration.zero);

      expect(hits.map((hit) => hit.reminder.id), ['active']);
      expect(_storedReminders(prefs).single.lastFiredAt, _inside().at);
      expect(store.writes, [_remindersKey]);
      expect(effects.notifications, 1);
      expect(effects.persisted, 1);
    },
  );

  test(
    'stopping a pending native start waits for cleanup and expires its callback immediately',
    () async {
      final raws = await seed([_reminder()]);
      final probe = _RetainingProbe();
      final hits = <LocationReminderHit>[];
      final controller = LocationReminderController(
        probe: probe,
        provider: provider,
        onHit: hits.add,
      );
      addTearDown(() async {
        probe.releaseAll();
        await controller.stop();
      });
      final startGate = probe.holdNextStart();
      final starting = controller.start();
      await startGate.started.future.timeout(_wait);
      var stopped = false;
      final stopping = controller.stop().then((_) => stopped = true);
      probe.callbacks.single(_inside());
      await AccountPreferenceWrites.drain();
      await Future<void>.delayed(Duration.zero);

      expect(stopped, isFalse);
      expect(hits, isEmpty);
      expect(store.writes, isEmpty);
      startGate.release.complete();
      await Future.wait([starting, stopping]).timeout(_wait);

      expect(stopped, isTrue);
      expect(probe.isTracking, isFalse);
      expect(probe.activeCallback, isNull);
      await expectRawStorage(raws);
      expect(hits, isEmpty);
    },
  );

  test(
    'pending start then stop then new start leaves only the latest native run active',
    () async {
      final raws = await seed([_reminder()]);
      final effects = _Effects(provider);
      final probe = _RetainingProbe();
      final hits = <LocationReminderHit>[];
      final controller = LocationReminderController(
        probe: probe,
        provider: provider,
        onHit: hits.add,
      );
      addTearDown(() async {
        probe.releaseAll();
        await controller.stop();
      });
      final startGate = probe.holdNextStart();
      final cleanupGate = probe.holdNextStop();
      final initialStarting = controller.start();
      await startGate.started.future.timeout(_wait);
      final stopping = controller.stop();
      final latestStarting = controller.start();
      await Future<void>.delayed(Duration.zero);

      expect(probe.callbacks, hasLength(1));
      probe.callbacks.single(_inside());
      await AccountPreferenceWrites.drain();
      await Future<void>.delayed(Duration.zero);
      expect(hits, isEmpty);
      expect(store.writes, isEmpty);

      startGate.release.complete();
      await cleanupGate.started.future.timeout(_wait);
      expect(
        probe.callbacks,
        hasLength(1),
        reason: 'new native start must wait for canceled start cleanup',
      );
      probe.callbacks.single(_inside());
      await AccountPreferenceWrites.drain();
      await Future<void>.delayed(Duration.zero);
      await expectRawStorage(raws);
      expect(hits, isEmpty);

      cleanupGate.release.complete();
      await Future.wait([
        initialStarting,
        stopping,
        latestStarting,
      ]).timeout(_wait);

      expect(probe.callbacks, hasLength(2));
      expect(probe.isTracking, isTrue);
      expect(identical(probe.activeCallback, probe.callbacks.last), isTrue);
      probe.callbacks.first(_inside());
      probe.activeCallback!(_inside());
      await AccountPreferenceWrites.drain();
      await Future<void>.delayed(Duration.zero);

      expect(hits.map((hit) => hit.reminder.id), ['active']);
      expect(_storedReminders(prefs).single.lastFiredAt, _inside().at);
      expect(store.writes, [_remindersKey]);
      expect(effects.notifications, 1);
      expect(effects.persisted, 1);
      expect(probe.isTracking, isTrue);
    },
  );
}

LocationReminder _reminder({
  bool oneShot = false,
  LocationTrigger trigger = LocationTrigger.enter,
}) => LocationReminder(
  id: 'active',
  title: '到办公室 / 原文保留',
  latitude: 39.9042,
  longitude: 116.4074,
  radiusMeters: 250,
  trigger: trigger,
  oneShot: oneShot,
  createdAt: DateTime.utc(2026, 11, 9, 10),
  updatedAt: DateTime.utc(2026, 11, 9, 10),
);

LocationFix _inside() => LocationFix(
  latitude: 39.9042,
  longitude: 116.4074,
  at: DateTime.utc(2026, 11, 9, 11),
);

List<Map<String, dynamic>> _snapshot(LocationReminderProvider provider) =>
    provider.reminders.map((reminder) => reminder.toJson()).toList();

List<LocationReminder> _storedReminders(SharedPreferences prefs) =>
    (jsonDecode(prefs.getString(_remindersKey) ?? '[]') as List)
        .map(
          (item) =>
              LocationReminder.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();

Map<String, dynamic> _tombstones(SharedPreferences prefs) =>
    jsonDecode(prefs.getString(_deletedKey) ?? '{}') as Map<String, dynamic>;

class _Effects {
  _Effects(LocationReminderProvider provider) {
    provider.addListener(() => notifications++);
    provider.onLocalMutationPersisted = () => persisted++;
  }
  int notifications = 0;
  int persisted = 0;
}

class _Gate {
  final started = Completer<void>();
  final release = Completer<void>();
}

class _RetainingProbe implements LocationProbe {
  final callbacks = <void Function(LocationFix)>[];
  final _allGates = <_Gate>[];
  void Function(LocationFix)? activeCallback;
  _Gate? _startGate;
  _Gate? _stopGate;
  bool _tracking = false;

  @override
  bool get isTracking => _tracking;

  _Gate holdNextStart() {
    final gate = _Gate();
    _startGate = gate;
    _allGates.add(gate);
    return gate;
  }

  _Gate holdNextStop() {
    final gate = _Gate();
    _stopGate = gate;
    _allGates.add(gate);
    return gate;
  }

  void releaseAll() {
    for (final gate in _allGates) {
      if (!gate.release.isCompleted) gate.release.complete();
    }
  }

  @override
  Future<void> start({required void Function(LocationFix) onFix}) async {
    callbacks.add(onFix);
    final gate = _startGate;
    _startGate = null;
    if (gate != null) {
      gate.started.complete();
      await gate.release.future;
    }
    // Model a native subscription becoming active only when start finishes.
    activeCallback = onFix;
    _tracking = true;
  }

  @override
  Future<void> stop() async {
    final gate = _stopGate;
    _stopGate = null;
    if (gate != null) {
      gate.started.complete();
      await gate.release.future;
    }
    activeCallback = null;
    _tracking = false;
    // Retain callbacks to model queued native events from earlier runs.
  }
}

class _Rejection {
  const _Rejection(this.throws);
  final bool throws;
}

class _TriggerStore extends InMemorySharedPreferencesStore {
  _TriggerStore() : super.withData(<String, Object>{});
  final writes = <String>[];
  final _holds = <String, _Gate>{};
  final _allGates = <_Gate>[];
  final _rejections = <String, _Rejection>{};

  _Gate holdNext(String key) {
    final gate = _Gate();
    _holds[key] = gate;
    _allGates.add(gate);
    return gate;
  }

  void rejectNext(String key, {bool throws = false}) {
    _rejections[key] = _Rejection(throws);
  }

  void releaseAll() {
    for (final gate in _allGates) {
      if (!gate.release.isCompleted) gate.release.complete();
    }
  }

  Future<String?> diskRaw(String key) async =>
      (await getAll())['flutter.$key'] as String?;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    final localKey = key.startsWith('flutter.') ? key.substring(8) : key;
    if (localKey != _remindersKey && localKey != _deletedKey) {
      return super.setValue(type, key, value);
    }
    writes.add(localKey);
    final rejection = _rejections.remove(localKey);
    final gate = _holds.remove(localKey);
    if (gate != null) {
      gate.started.complete();
      await gate.release.future;
    }
    // Force compensation to restore both disk and the optimistic prefs cache.
    await super.setValue(type, key, value);
    if (rejection != null) {
      if (rejection.throws) {
        throw StateError('synthetic $localKey write failure');
      }
      return false;
    }
    return true;
  }
}
