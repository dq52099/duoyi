// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/location_reminder_storage.dart'
    show LocationReminderStorage;
import 'package:duoyi/models/location_reminder.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _locationKey = 'duoyi_location_reminders_v1';
const _deletedKey = CloudSyncProvider.deletedItemsStorageKey;
const _todoRaw = '[{"id":"kept-todo","title":"Unrelated task"}]';
const _noteRaws = <String>['{"id":"kept-note","title":"Unrelated note"}'];
const _deletedRaw = '{"todos":{"keep":"2026-11-01T12:00:00.000Z"}}';
const _wait = Duration(seconds: 2);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // These cases specify recovery for external failure origins. They use the
  // existing public API without assuming the central implementation is ready.
  late SharedPreferencesStorePlatform originalStore;
  late _RecoveryStore store;
  late SharedPreferences prefs;
  late LocationReminderProvider provider;
  final providers = <LocationReminderProvider>[];
  final clouds = <CloudSyncProvider>[];
  final clients = <http.Client>[];
  final checks = <Future<void>>[];
  final responseGates = <Completer<void>>[];

  setUp(() async {
    await AccountPreferenceWrites.drain().timeout(_wait);
    originalStore = SharedPreferencesStorePlatform.instance;
    providers.clear();
    clouds.clear();
    clients.clear();
    checks.clear();
    responseGates.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = _RecoveryStore();
    SharedPreferencesStorePlatform.instance = store;
    prefs = await SharedPreferences.getInstance();
    // Store replacement/invalidation alone must not retire a recovery record.
    // Exercise the same confirmed-cleanup path that production uses.
    await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    provider = LocationReminderProvider();
    providers.add(provider);
  });

  tearDown(() async {
    store.releaseAll();
    for (final gate in responseGates) {
      if (!gate.isCompleted) gate.complete();
    }
    try {
      try {
        await Future.wait(checks).timeout(_wait);
      } finally {
        store.discardPlans();
        await AccountPreferenceWrites.drain().timeout(_wait);
      }
    } finally {
      for (final cloud in clouds) {
        cloud.dispose();
      }
      for (final client in clients) {
        client.close();
      }
      for (final item in providers) {
        item.dispose();
      }
      try {
        await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
      } finally {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        SharedPreferencesStorePlatform.instance = originalStore;
      }
    }
  });

  Future<void> watch(Future<dynamic> future, Matcher matcher) {
    final check = expectLater(future, matcher);
    // Held operations can outlive an earlier assertion. Observe rejection
    // immediately; the original check remains awaited by the case/teardown.
    unawaited(check.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    checks.add(check);
    return check;
  }

  LocationReminderProvider replacement() {
    final item = LocationReminderProvider();
    providers.add(item);
    return item;
  }

  Future<String> seed() async {
    final raw = '[\n  ${jsonEncode(_reminder('existing').toJson())}\n]\n';
    await prefs.setString(_locationKey, raw);
    await prefs.setString(_deletedKey, _deletedRaw);
    await prefs.setString('todos', _todoRaw);
    await prefs.setStringList('duoyi_notes', _noteRaws);
    await prefs.setBool('pref_haptic_feedback', false);
    await prefs.setInt('pref_default_tab', 2);
    await prefs.reload();
    expect(prefs.get('duoyi_notes'), isNot(isA<List<String>>()));
    await provider.loadFromStorage();
    store.attempts.clear();
    return raw;
  }

  Future<void> expectLocationRaw(String? raw) async {
    expect(prefs.getString(_locationKey), raw, reason: 'preference cache');
    expect(await store.diskValue(_locationKey), raw, reason: 'backing store');
    await prefs.reload();
    expect(prefs.getString(_locationKey), raw, reason: 'reloaded cache');
  }

  Future<void> expectUnrelatedValues() async {
    expect(prefs.getString('todos'), _todoRaw);
    expect(prefs.getStringList('duoyi_notes'), _noteRaws);
    expect(prefs.getBool('pref_haptic_feedback'), isFalse);
    expect(prefs.getInt('pref_default_tab'), 2);
    expect(await store.diskValue('todos'), _todoRaw);
    expect(await store.diskValue('duoyi_notes'), _noteRaws);
    expect(await store.diskValue('pref_haptic_feedback'), false);
    expect(await store.diskValue('pref_default_tab'), 2);
  }

  CloudSyncProvider cloudWith(
    Future<http.Response> Function(http.Request) handler,
  ) {
    final cloud = CloudSyncProvider();
    final httpClient = MockClient(handler);
    clients.add(httpClient);
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'synthetic-token',
      httpClient: httpClient,
    );
    cloud.apiClientGetter = () => client;
    cloud.serverConfigGetter = () => {'backup_enabled': true};
    clouds.add(cloud);
    return cloud;
  }

  Future<void> expectGated(LocationReminderProvider item) async {
    expect(item.storageNeedsReconciliation, isTrue);
    final before = store.attempts.toList();
    final operations = <Future<dynamic> Function()>[
      item.loadFromStorage,
      () => item.add(_reminder('blocked-provider')),
      BackupService.exportAll,
      () => BackupService.importAll(_backup(_rows(['blocked-import']))),
      BackupService.wipeAll,
    ];
    for (final operation in operations) {
      await watch(
        operation(),
        throwsA(isA<LocationReminderStorageIndeterminate>()),
      ).timeout(_wait);
    }
    expect(
      store.attempts,
      before,
      reason: 'gated data operations issue no writes',
    );
    var requests = 0;
    final cloud = cloudWith((request) async {
      requests++;
      return _response(request, _rows(['should-not-arrive']));
    });
    await watch(cloud.syncNow(), completes).timeout(_wait);
    expect(requests, 0, reason: 'uncertain rows must not enter a sync payload');
    expect(cloud.hasSyncRetryPending || cloud.lastError != null, isTrue);
    expect(
      store.attempts.where(
        (id) => id != 'set:flutter.sync_pending_local_changes',
      ),
      before.where((id) => id != 'set:flutter.sync_pending_local_changes'),
      reason:
          'a retry marker cannot permit uncertain data or sync acknowledgements',
    );
  }

  Future<void> failImport(String issued) async {
    store.planSet(_locationKey, failure: _Failure.persistThenFalse);
    store.planSet(_locationKey, failure: _Failure.rejectBeforePersist);
    await watch(
      BackupService.importAll(_backup(issued)),
      throwsA(isA<LocationReminderStorageIndeterminate>()),
    ).timeout(_wait);
  }

  test(
    'import failed compensation is recoverable through a replacement provider',
    () async {
      final original = await seed();
      final issued = _rows(['unconfirmed-import']);
      store.planSet(_locationKey, failure: _Failure.persistThenFalse);
      store.planSet(_locationKey, failure: _Failure.rejectBeforePersist);
      final rawBackup = jsonEncode({
        'app': 'duoyi',
        'schema': BackupService.schemaVersion,
        'data': {
          'pref_haptic_feedback': {'type': 'bool', 'value': true},
          'pref_default_tab': {'type': 'int', 'value': 5},
          _locationKey: {'type': 'string', 'value': issued},
        },
      });
      await watch(
        BackupService.importAll(rawBackup),
        throwsA(isA<LocationReminderStorageIndeterminate>()),
      ).timeout(_wait);
      expect(_ids(provider), ['existing']);
      await expectLocationRaw(issued);
      await expectUnrelatedValues();

      final next = replacement();
      var mutations = 0;
      next.onLocalMutationPersisted = () => mutations++;
      await expectGated(next);
      await next.reconcileStorage().timeout(_wait);
      expect(next.storageNeedsReconciliation, isFalse);
      expect(provider.storageNeedsReconciliation, isFalse);
      expect(_ids(next), ['existing']);
      expect(mutations, 0, reason: 'recovery is not a new local mutation');
      await expectLocationRaw(original);
      await expectUnrelatedValues();
      expect(await store.diskValue(_deletedKey), _deletedRaw);
      expect(
        _exportedRows(await BackupService.exportAll().timeout(_wait)),
        original,
      );

      expect(await BackupService.importAll(_backup(issued)).timeout(_wait), 1);
      await next.add(_reminder('after-import')).timeout(_wait);
      expect(_ids(next), ['unconfirmed-import', 'after-import']);
    },
  );

  test(
    'wipe removed rows then rejected acknowledgement stays gated until recovery',
    () async {
      final original = await seed();
      store.planRemove(_locationKey, failure: _Failure.persistThenFalse);
      store.planSet(_locationKey, failure: _Failure.rejectBeforePersist);
      await watch(
        BackupService.wipeAll(),
        throwsA(isA<LocationReminderStorageIndeterminate>()),
      ).timeout(_wait);
      expect(_ids(provider), ['existing']);
      await expectLocationRaw(null);
      // Earlier removed keys must compensate with their original storage types.
      await expectUnrelatedValues();
      expect(await store.diskValue(_deletedKey), _deletedRaw);

      final next = replacement();
      await expectGated(next);
      await next.reconcileStorage().timeout(_wait);
      await expectLocationRaw(original);
      await expectUnrelatedValues();
      expect(_ids(next), ['existing']);
      expect(next.storageNeedsReconciliation, isFalse);
      expect(
        _exportedRows(await BackupService.exportAll().timeout(_wait)),
        original,
      );

      await BackupService.wipeAll().timeout(_wait);
      await next.loadFromStorage().timeout(_wait);
      expect(_ids(next), isEmpty);
      await expectLocationRaw(null);
      expect(await store.diskValue(_deletedKey), _deletedRaw);
    },
  );

  test(
    'cloud false before disk change cannot publish its eagerly changed cache',
    () async {
      final original = await seed();
      final remote = _rows(['remote']);
      var requests = 0;
      var callbacks = 0;
      final cloud = cloudWith((request) async {
        requests++;
        return _response(request, remote);
      });
      cloud.onSynced = (_) async {
        callbacks++;
        await provider.loadFromStorage();
      };
      store.planSet(_locationKey, failure: _Failure.rejectBeforePersist);

      await watch(cloud.syncNow(), completes).timeout(_wait);

      expect(requests, 1);
      expect(
        callbacks,
        0,
        reason: 'rejected cache rows must not trigger reload',
      );
      expect(_ids(provider), ['existing']);
      await expectLocationRaw(original);
      expect(provider.storageNeedsReconciliation, isFalse);
      expect(cloud.hasSyncRetryPending || cloud.lastError != null, isTrue);
      expect(cloud.config.lastSync.millisecondsSinceEpoch, 0);
      expect(prefs.getString('sync_last_time'), isNull);
      expect(await store.diskValue(_deletedKey), _deletedRaw);

      await watch(cloud.syncNow(), completes).timeout(_wait);
      expect(requests, 2);
      expect(callbacks, 1);
      expect(_ids(provider), ['remote']);
      await expectLocationRaw(remote);
      expect(cloud.lastError, isNull);
      expect(cloud.hasSyncRetryPending, isFalse);
    },
  );

  test(
    'cloud wrote then rejected and failed compensation exposes shared recovery',
    () async {
      final original = await seed();
      final remote = _rows(['remote-unconfirmed']);
      var requests = 0;
      var callbacks = 0;
      final cloud = cloudWith((request) async {
        requests++;
        return _response(request, remote);
      });
      cloud.onSynced = (_) async {
        callbacks++;
        await provider.loadFromStorage();
      };
      store.planSet(_locationKey, failure: _Failure.persistThenFalse);
      store.planSet(_locationKey, failure: _Failure.rejectBeforePersist);

      await watch(cloud.syncNow(), completes).timeout(_wait);

      expect(requests, 1);
      expect(callbacks, 0);
      expect(_ids(provider), ['existing']);
      await expectLocationRaw(remote);
      final next = replacement();
      await expectGated(next);
      var mutations = 0;
      next.onLocalMutationPersisted = () => mutations++;
      await next.reconcileStorage().timeout(_wait);
      expect(mutations, 0);
      expect(_ids(next), ['existing']);
      expect(next.storageNeedsReconciliation, isFalse);
      await expectLocationRaw(original);
      expect(await store.diskValue(_deletedKey), _deletedRaw);

      await watch(cloud.syncNow(), completes).timeout(_wait);
      expect(requests, 2);
      expect(callbacks, 1);
      expect(_ids(provider), ['remote-unconfirmed']);
      await expectLocationRaw(remote);
      await next.add(_reminder('after-cloud')).timeout(_wait);
      expect(_ids(next), ['remote-unconfirmed', 'after-cloud']);
    },
  );

  test(
    'recovery of an indeterminate remove preserves a queued unrelated tombstone',
    () async {
      final original = await seed();
      final held = store.planSet(
        _locationKey,
        failure: _Failure.persistThenFalse,
        hold: true,
      );
      store.planSet(_locationKey, failure: _Failure.rejectBeforePersist);
      final rejected = watch(
        provider.remove('existing'),
        throwsA(isA<LocationReminderStorageIndeterminate>()),
      );
      await held.started.future.timeout(_wait);
      var noteDeleted = false;
      final unrelated = watch(
        CloudSyncProvider.recordDeletedItem('notes', 'after-failure').then((_) {
          noteDeleted = true;
        }),
        completes,
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        noteDeleted,
        isFalse,
        reason: 'the location delete owns the lease',
      );
      held.release.complete();
      await Future.wait([rejected, unrelated]).timeout(_wait);
      await expectLocationRaw('[]');
      final deletedBeforeRaw = (await store.diskValue(_deletedKey))! as String;
      final deletedBefore = jsonDecode(deletedBeforeRaw) as Map;
      expect(
        (deletedBefore['todos'] as Map)['keep'],
        '2026-11-01T12:00:00.000Z',
      );
      expect((deletedBefore['notes'] as Map), contains('after-failure'));
      expect(deletedBefore.containsKey('location_reminders'), isFalse);

      final next = replacement();
      expect(next.storageNeedsReconciliation, isTrue);
      await next.reconcileStorage().timeout(_wait);
      expect(next.storageNeedsReconciliation, isFalse);
      await expectLocationRaw(original);
      final deletedAfterRaw = (await store.diskValue(_deletedKey))! as String;
      final deletedAfter = jsonDecode(deletedAfterRaw) as Map;
      expect(
        deletedAfter,
        deletedBefore,
        reason: 'recovery keeps accepted unrelated tombstones',
      );
      expect(_ids(next), ['existing']);
      await next.add(_reminder('after-recovery')).timeout(_wait);
      expect(_ids(next), ['existing', 'after-recovery']);
    },
  );

  test(
    'failed cleanup keeps uncertainty and confirmed removal rejects old cloud work',
    () async {
      await seed();
      final issued = _rows(['unconfirmed-before-cleanup']);
      await failImport(issued);
      final generation = AccountLocalDataCleaner.accountDataGeneration;
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      expect(
        AccountLocalDataCleaner.accountDataGeneration,
        greaterThan(generation),
      );
      final next = replacement();
      await expectGated(next);
      await expectLocationRaw(issued);

      // Cleanup is permitted to bypass the gate, but this removal does not
      // complete. Its new cancellation generation must not retire the record.
      final beforeCleanupGeneration =
          AccountLocalDataCleaner.accountDataGeneration;
      store.planRemove(_locationKey, failure: _Failure.rejectBeforePersist);
      await watch(
        AccountLocalDataCleaner.clearSharedPreferences(),
        throwsA(isA<StateError>()),
      ).timeout(_wait);
      expect(
        AccountLocalDataCleaner.accountDataGeneration,
        greaterThan(beforeCleanupGeneration),
      );
      expect(await store.diskValue(_locationKey), issued);
      await prefs.reload();
      await expectLocationRaw(issued);
      expect(next.storageNeedsReconciliation, isTrue);
      await watch(
        BackupService.exportAll(),
        throwsA(isA<LocationReminderStorageIndeterminate>()),
      ).timeout(_wait);

      await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
      expect(provider.storageNeedsReconciliation, isFalse);
      expect(next.storageNeedsReconciliation, isFalse);
      await expectLocationRaw(null);
      await next.loadFromStorage().timeout(_wait);
      expect(_ids(next), isEmpty);
      expect(
        _exportedRows(await BackupService.exportAll().timeout(_wait)),
        isNull,
      );
      await next.add(_reminder('after-confirmed-clear')).timeout(_wait);
      expect(_ids(next), ['after-confirmed-clear']);
      expect(await store.diskValue(_deletedKey), isNull);

      final beforeLateResponseRaw = prefs.getString(_locationKey)!;
      final requestStarted = Completer<void>();
      final releaseResponse = Completer<void>();
      responseGates.add(releaseResponse);
      var requests = 0;
      var callbacks = 0;
      final oldCloud = cloudWith((request) async {
        requests++;
        final payload = jsonDecode(request.body) as Map;
        expect(
          payload['location_reminders'],
          jsonDecode(beforeLateResponseRaw),
        );
        if (!requestStarted.isCompleted) requestStarted.complete();
        await releaseResponse.future;
        return _response(request, _rows(['old-cloud-unconfirmed']));
      });
      oldCloud.onSynced = (_) async {
        callbacks++;
        await next.loadFromStorage();
      };
      final oldSync = watch(oldCloud.syncNow(), completes);
      await requestStarted.future.timeout(_wait);

      // The test does not reset this cloud instance. Direct cleanup must make
      // its previously dispatched response obsolete.
      await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
      const nextTodoRaw =
          '[{"id":"next-account-todo","title":"Current lifetime"}]';
      final currentBackup = jsonEncode({
        'app': 'duoyi',
        'schema': BackupService.schemaVersion,
        'data': {
          // Identical rows make a raw snapshot comparison insufficient to
          // distinguish the cleared storage lifetime from the current one.
          _locationKey: {'type': 'string', 'value': beforeLateResponseRaw},
          'todos': {'type': 'string', 'value': nextTodoRaw},
        },
      });
      expect(await BackupService.importAll(currentBackup).timeout(_wait), 2);
      await next.loadFromStorage().timeout(_wait);
      final beforeLateAttempts = store.attempts.toList();
      // A wrongly admitted late response would write, fail compensation, and
      // poison the new lifetime. Correct cancellation consumes neither plan.
      store.planSet(_locationKey, failure: _Failure.persistThenFalse);
      store.planSet(_locationKey, failure: _Failure.rejectBeforePersist);
      releaseResponse.complete();
      await oldSync.timeout(_wait);

      expect(requests, 1);
      expect(callbacks, 0);
      expect(store.attempts, beforeLateAttempts);
      expect(next.storageNeedsReconciliation, isFalse);
      expect(provider.storageNeedsReconciliation, isFalse);
      expect(oldCloud.config.lastSync.millisecondsSinceEpoch, 0);
      expect(prefs.getString('sync_last_time'), isNull);
      expect(prefs.getInt('sync_server_version'), isNull);
      await expectLocationRaw(beforeLateResponseRaw);
      expect(prefs.getString('todos'), nextTodoRaw);
      expect(await store.diskValue('todos'), nextTodoRaw);

      store.discardPlans();
      await next.add(_reminder('after-old-response')).timeout(_wait);
      expect(_ids(next), ['after-confirmed-clear', 'after-old-response']);
    },
  );

  test(
    'cleanup retry reloads a key hidden by a rejected remove without caller reload',
    () async {
      await seed();
      final issued = _rows(['unconfirmed-before-retry']);
      await failImport(issued);
      await expectLocationRaw(issued);
      final next = replacement();
      expect(next.storageNeedsReconciliation, isTrue);
      store.planRemove(
        _locationKey,
        failure: _Failure.rejectBeforePersist,
        failNextReload: true,
      );

      await watch(
        AccountLocalDataCleaner.clearSharedPreferences(),
        throwsA(isA<StateError>()),
      ).timeout(_wait);

      // remove publishes absence to the cache before platform rejection. The
      // failed final reload leaves that absence intact while disk is unchanged.
      expect(store.failedReloads, 1);
      expect(prefs.containsKey(_locationKey), isFalse);
      expect(next.storageNeedsReconciliation, isTrue);
      final failedRemoveAttempts = store.attempts
          .where((id) => id == 'remove:flutter.$_locationKey')
          .length;

      // Intentionally perform no caller reload or cache-repairing read here.
      // Cleanup itself must discover and remove the backing-store key on retry.
      await watch(
        AccountLocalDataCleaner.clearSharedPreferences(),
        completes,
      ).timeout(_wait);

      expect(
        store.attempts
            .where((id) => id == 'remove:flutter.$_locationKey')
            .length,
        failedRemoveAttempts + 1,
      );
      expect(await store.diskValue(_locationKey), isNull);
      expect(prefs.containsKey(_locationKey), isFalse);
      expect(next.storageNeedsReconciliation, isFalse);
      expect(provider.storageNeedsReconciliation, isFalse);
      await next.loadFromStorage().timeout(_wait);
      expect(_ids(next), isEmpty);
      await next.add(_reminder('after-cleanup-retry')).timeout(_wait);
      expect(_ids(next), ['after-cleanup-retry']);
      expect(await store.diskValue(_deletedKey), isNull);
    },
  );

  test(
    'failed direct cleanup cancels a held cloud response without retiring the storage epoch',
    () async {
      final original = await seed();
      expect(provider.storageNeedsReconciliation, isFalse);
      final epoch = LocationReminderStorage.storageEpoch;
      final generation = AccountLocalDataCleaner.accountDataGeneration;
      final requestStarted = Completer<void>();
      final releaseResponse = Completer<void>();
      responseGates.add(releaseResponse);
      var requests = 0;
      var callbacks = 0;
      final cloud = cloudWith((request) async {
        requests++;
        final payload = jsonDecode(request.body) as Map;
        expect(payload['location_reminders'], jsonDecode(original));
        if (!requestStarted.isCompleted) requestStarted.complete();
        await releaseResponse.future;
        return _response(request, _rows(['late-after-failed-clear']));
      });
      cloud.onSynced = (_) async {
        callbacks++;
        await provider.loadFromStorage();
      };
      final syncing = watch(cloud.syncNow(), completes);
      await requestStarted.future.timeout(_wait);

      // Keep the original rows on disk. Unlike a successful clear, this
      // boundary changes cancellation authority without changing the epoch.
      store.planRemove(_locationKey, failure: _Failure.rejectBeforePersist);
      await watch(
        AccountLocalDataCleaner.clearSharedPreferences(),
        throwsA(isA<StateError>()),
      ).timeout(_wait);
      expect(LocationReminderStorage.storageEpoch, epoch);
      expect(
        AccountLocalDataCleaner.accountDataGeneration,
        greaterThan(generation),
      );
      await expectLocationRaw(original);
      expect(provider.storageNeedsReconciliation, isFalse);
      final beforeResponse = store.attempts.toList();

      // No cloud reset is invoked. The unchanged raw rows also cannot make
      // this response current after the failed cleanup's invalidation.
      releaseResponse.complete();
      await syncing.timeout(_wait);
      expect(requests, 1);
      expect(callbacks, 0);
      expect(store.attempts, beforeResponse);
      expect(_ids(provider), ['existing']);
      expect(provider.storageNeedsReconciliation, isFalse);
      expect(cloud.isSyncing, isFalse);
      expect(cloud.config.lastSync.millisecondsSinceEpoch, 0);
      expect(prefs.getString('sync_last_time'), isNull);
      expect(prefs.getInt('sync_server_version'), isNull);
      expect(await store.diskValue(_deletedKey), isNull);
      await expectLocationRaw(original);
      await provider.add(_reminder('after-failed-clear')).timeout(_wait);
      expect(_ids(provider), ['existing', 'after-failed-clear']);
    },
  );

  test(
    'partial tombstone reconciliation retries a rejected row restoration',
    () async {
      final original = await seed();
      store.planSet(_deletedKey, failure: _Failure.accept);
      store.planSet(_deletedKey, failure: _Failure.rejectBeforePersist);
      store.planSet(_locationKey, failure: _Failure.persistThenFalse);
      store.planSet(_locationKey, failure: _Failure.rejectBeforePersist);
      await watch(
        provider.remove('existing'),
        throwsA(isA<LocationReminderStorageIndeterminate>()),
      ).timeout(_wait);
      expect(await store.diskValue(_locationKey), '[]');
      final issuedDeleted =
          jsonDecode((await store.diskValue(_deletedKey))! as String) as Map;
      expect(issuedDeleted['location_reminders'] as Map, contains('existing'));

      final next = replacement();
      var notifications = 0;
      var mutations = 0;
      next.addListener(() => notifications++);
      next.onLocalMutationPersisted = () => mutations++;
      store.planSet(_locationKey, failure: _Failure.rejectBeforePersist);
      await watch(
        next.reconcileStorage(),
        throwsA(isA<LocationReminderStorageIndeterminate>()),
      ).timeout(_wait);

      // The tombstone prefix restored durably, but the later row restore
      // did not. Memory stays unpublished until the complete plan verifies.
      expect(await store.diskValue(_deletedKey), _deletedRaw);
      expect(await store.diskValue(_locationKey), '[]');
      expect(_ids(next), isEmpty);
      expect(notifications, 0);
      expect(mutations, 0);
      await expectGated(next);
      await CloudSyncProvider.recordDeletedItem(
        'notes',
        'between-recovery-attempts',
      ).timeout(_wait);
      final partialDeleted =
          jsonDecode((await store.diskValue(_deletedKey))! as String) as Map;
      expect(partialDeleted.containsKey('location_reminders'), isFalse);

      // No caller reload repairs the eagerly changed row cache before retry.
      // Reconciliation must accept both its already-restored prefix and the
      // original issued row image, while retaining the new unrelated delete.
      await watch(next.reconcileStorage(), completes).timeout(_wait);
      expect(next.storageNeedsReconciliation, isFalse);
      expect(provider.storageNeedsReconciliation, isFalse);
      expect(_ids(next), ['existing']);
      expect(notifications, 1);
      expect(mutations, 0);
      await expectLocationRaw(original);
      final restoredDeleted =
          jsonDecode((await store.diskValue(_deletedKey))! as String) as Map;
      expect(restoredDeleted, partialDeleted);
      await expectUnrelatedValues();
      await next.add(_reminder('after-partial-retry')).timeout(_wait);
      expect(_ids(next), ['existing', 'after-partial-retry']);
      expect(mutations, 1);
    },
  );

  test(
    'an independent third affected tombstone timestamp refuses recovery before writes',
    () async {
      await seed();
      final previousStamp = DateTime.utc(2000, 1, 1).toIso8601String();
      await prefs.setString(
        _deletedKey,
        jsonEncode({
          'todos': {'keep': '2026-11-01T12:00:00.000Z'},
          'location_reminders': {'existing': previousStamp},
        }),
      );
      store.planSet(_deletedKey, failure: _Failure.accept);
      store.planSet(_deletedKey, failure: _Failure.rejectBeforePersist);
      store.planSet(_locationKey, failure: _Failure.persistThenFalse);
      store.planSet(_locationKey, failure: _Failure.rejectBeforePersist);
      await watch(
        provider.remove('existing'),
        throwsA(isA<LocationReminderStorageIndeterminate>()),
      ).timeout(_wait);
      final issuedDeleted =
          jsonDecode((await store.diskValue(_deletedKey))! as String) as Map;
      final issuedStamp =
          (issuedDeleted['location_reminders'] as Map)['existing'];
      expect(issuedStamp, isA<String>());
      expect(issuedStamp, isNot(previousStamp));

      final thirdTime = DateTime.utc(2099, 11, 9, 12, 34, 56);
      final thirdStamp = thirdTime.toIso8601String();
      expect(thirdStamp, isNot(issuedStamp));
      await CloudSyncProvider.recordDeletedItem(
        'location_reminders',
        'existing',
        deletedAt: thirdTime,
      ).timeout(_wait);
      final independentlyChanged =
          (await store.diskValue(_deletedKey))! as String;
      final changedDeleted = jsonDecode(independentlyChanged) as Map;
      expect(
        (changedDeleted['location_reminders'] as Map)['existing'],
        thirdStamp,
      );
      final next = replacement();
      var notifications = 0;
      next.addListener(() => notifications++);
      final beforeRecovery = store.attempts.toList();

      await watch(
        next.reconcileStorage(),
        throwsA(isA<LocationReminderStorageIndeterminate>()),
      ).timeout(_wait);

      expect(
        store.attempts,
        beforeRecovery,
        reason: 'validate before any restore',
      );
      expect(await store.diskValue(_deletedKey), independentlyChanged);
      await expectLocationRaw('[]');
      expect(_ids(next), isEmpty);
      expect(notifications, 0);
      expect(next.storageNeedsReconciliation, isTrue);
      expect(provider.storageNeedsReconciliation, isTrue);
      await expectGated(next);
    },
  );
}

LocationReminder _reminder(String id) => LocationReminder(
  id: id,
  title: 'Location recovery $id',
  latitude: 39.9042,
  longitude: 116.4074,
  radiusMeters: 250,
  linkedType: 'todo',
  linkedId: 'todo-$id',
  createdAt: DateTime.utc(2026, 11, 9, 10),
  updatedAt: DateTime.utc(2026, 11, 9, 10),
);

List<String> _ids(LocationReminderProvider item) =>
    item.reminders.map((row) => row.id).toList();

String _rows(List<String> ids) =>
    jsonEncode(ids.map((id) => _reminder(id).toJson()).toList());

String _backup(String raw) => jsonEncode({
  'app': 'duoyi',
  'schema': BackupService.schemaVersion,
  'data': {
    _locationKey: {'type': 'string', 'value': raw},
  },
});

String? _exportedRows(String raw) {
  final data = (jsonDecode(raw) as Map)['data'] as Map;
  return (data[_locationKey] as Map?)?['value'] as String?;
}

http.Response _response(http.Request request, String rows) {
  final payload = jsonDecode(request.body) as Map;
  return http.Response(
    jsonEncode({
      'server_updated_at': '2026-11-09T12:00:00.000Z',
      'server_version': 1,
      'collection_hashes': {
        for (final key in payload.keys) key: 'confirmed-$key',
      },
      'location_reminders': jsonDecode(rows),
      'deleted_items': payload['deleted_items'],
    }),
    200,
    headers: const {'content-type': 'application/json'},
  );
}

enum _Failure { persistThenFalse, rejectBeforePersist, accept }

class _Plan {
  _Plan(this.failure, this.hold, {this.failNextReload = false});

  final _Failure failure;
  final bool hold;
  final bool failNextReload;
  final started = Completer<void>();
  final release = Completer<void>();
}

class _RecoveryStore extends InMemorySharedPreferencesStore {
  _RecoveryStore() : super.withData(<String, Object>{});

  final attempts = <String>[];
  final _plans = <String, List<_Plan>>{};
  final _allPlans = <_Plan>[];
  bool _rejectNextRead = false;
  int failedReloads = 0;

  _Plan planSet(String key, {required _Failure failure, bool hold = false}) =>
      _plan('set', key, failure, hold);

  _Plan planRemove(
    String key, {
    required _Failure failure,
    bool hold = false,
    bool failNextReload = false,
  }) => _plan('remove', key, failure, hold, failNextReload: failNextReload);

  _Plan _plan(
    String kind,
    String key,
    _Failure failure,
    bool hold, {
    bool failNextReload = false,
  }) {
    final step = _Plan(failure, hold, failNextReload: failNextReload);
    _plans.putIfAbsent('$kind:flutter.$key', () => <_Plan>[]).add(step);
    _allPlans.add(step);
    return step;
  }

  void releaseAll() {
    for (final step in _allPlans) {
      if (!step.release.isCompleted) step.release.complete();
    }
  }

  void discardPlans() {
    releaseAll();
    _plans.clear();
    _rejectNextRead = false;
  }

  @override
  Future<Map<String, Object>> getAll() async {
    if (_rejectNextRead) {
      _rejectNextRead = false;
      failedReloads++;
      throw StateError('synthetic final reload failure after rejected removal');
    }
    // The Android legacy codec returns lists with an Object? element type.
    // Exercise that platform shape instead of an already typed test cache.
    final values = await super.getAll();
    return values.map(
      (key, value) =>
          MapEntry(key, value is List ? List<Object?>.from(value) : value),
    );
  }

  Future<Object?> diskValue(String key) async =>
      (await getAll())['flutter.$key'];

  Future<bool> _perform(
    String kind,
    String key,
    Future<bool> Function() persist,
  ) async {
    final id = '$kind:$key';
    attempts.add(id);
    final queue = _plans[id];
    if (queue == null || queue.isEmpty) return persist();
    final step = queue.removeAt(0);
    step.started.complete();
    if (step.hold) await step.release.future;
    if (step.failNextReload) _rejectNextRead = true;
    if (step.failure == _Failure.rejectBeforePersist) return false;
    final accepted = await persist();
    return step.failure == _Failure.accept ? accepted : false;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) =>
      _perform('set', key, () => super.setValue(type, key, value));

  @override
  Future<bool> remove(String key) =>
      _perform('remove', key, () => super.remove(key));
}
