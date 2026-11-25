// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/location_reminder_storage.dart';
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

const _key = 'duoyi_location_reminders_v1';
const _platformKey = 'flutter.$_key';
const _deletedKey = CloudSyncProvider.deletedItemsStorageKey;
const _unrelatedDeletedRaw = '{"todos":{"keep":"2026-11-01T12:00:00.000Z"}}';
const _unrelatedTodoRaw = '[{"id":"kept-todo","title":"Unrelated local task"}]';
const _wait = Duration(seconds: 2);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferencesStorePlatform originalStore;
  late _ExternalStorageStore store;
  late SharedPreferences prefs;
  late LocationReminderProvider provider;
  final checks = <Future<void>>[];
  final cloudProviders = <CloudSyncProvider>[];
  final responseGates = <Completer<void>>[];

  setUp(() async {
    await AccountPreferenceWrites.drain().timeout(_wait);
    await LocationReminderStorage.run<void>(
      () async {},
      allowUncertain: true,
    ).timeout(_wait);
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    originalStore = SharedPreferencesStorePlatform.instance;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = _ExternalStorageStore();
    SharedPreferencesStorePlatform.instance = store;
    prefs = await SharedPreferences.getInstance();
    await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    provider = LocationReminderProvider();
    checks.clear();
    cloudProviders.clear();
    responseGates.clear();
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
        await AccountPreferenceWrites.drain().timeout(_wait);
      }
    } finally {
      for (final cloud in cloudProviders) {
        cloud.dispose();
      }
      provider.dispose();
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      SharedPreferencesStorePlatform.instance = originalStore;
    }
  });

  Future<void> watch(Future<dynamic> future, Matcher matcher) {
    // Attach error expectations before allowing any held platform write out.
    final check = expectLater(future, matcher);
    checks.add(check);
    return check;
  }

  Future<String> seedExisting() async {
    final raw = '[\n  ${jsonEncode(_reminder('existing').toJson())}\n]\n';
    await prefs.setString(_key, raw);
    await prefs.setString(_deletedKey, _unrelatedDeletedRaw);
    await prefs.setString('todos', _unrelatedTodoRaw);
    await provider.loadFromStorage();
    store.resetTracking();
    return raw;
  }

  Future<void> expectLocationRaw(String? raw) async {
    expect(prefs.getString(_key), raw, reason: 'preference cache');
    expect(await store.diskRaw(), raw, reason: 'platform backing storage');
    await prefs.reload();
    expect(prefs.getString(_key), raw, reason: 'reloaded preference cache');
  }

  Future<_PendingRejection> startRejectedWrite({bool remove = false}) async {
    final write = store.planWrite(hold: true, rejectAfterWrite: true);
    final rollback = store.planWrite(hold: true);
    final failed = watch(
      remove
          ? provider.remove('existing')
          : provider.add(_reminder('rejected')),
      throwsStateError,
    );
    await write.started.future.timeout(_wait);
    return _PendingRejection(write, rollback, failed);
  }

  Future<void> makeUncertain() async {
    store.planWrite(rejectAfterWrite: true);
    store.planWrite(rejectBeforeWrite: true);
    await watch(
      provider.add(_reminder('uncertain')),
      throwsA(isA<LocationReminderStorageIndeterminate>()),
    ).timeout(_wait);
    expect(provider.storageNeedsReconciliation, isTrue);
    expect(_ids(provider), ['existing']);
    expect(_rawIds(await store.diskRaw()), ['existing', 'uncertain']);
  }

  CloudSyncProvider cloudWith(
    Future<http.Response> Function(http.Request) handler,
  ) {
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'synthetic-token',
      httpClient: MockClient(handler),
    );
    final cloud = CloudSyncProvider();
    cloud.apiClientGetter = () => client;
    cloud.serverConfigGetter = () => {'backup_enabled': true};
    cloudProviders.add(cloud);
    return cloud;
  }

  test(
    'import waits for delete compensation and retains an unrelated queued tombstone',
    () async {
      final original = await seedExisting();
      final rejection = await startRejectedWrite(remove: true);
      var unrelatedCompleted = false;
      final unrelated = watch(
        CloudSyncProvider.recordDeletedItem('todos', 'queued-local').then((_) {
          unrelatedCompleted = true;
        }),
        completes,
      );
      final importedRaw = _rawReminders(['imported']);
      var importedCount = 0;
      final importing = watch(
        BackupService.importAll(
          _backup(importedRaw),
          clearMissing: true,
        ).then((count) => importedCount = count),
        completion(1),
      );

      await Future<void>.delayed(Duration.zero);
      expect(importedCount, 0);
      expect(unrelatedCompleted, isFalse);
      expect(store.locationWrites, hasLength(1));

      await rejection.enterRollback();
      await Future<void>.delayed(Duration.zero);
      expect(_rawIds(await store.diskRaw()), isEmpty);
      expect(store.locationWrites, hasLength(2));
      expect(importedCount, 0, reason: 'import cannot run during rollback');
      expect(unrelatedCompleted, isFalse, reason: 'delete lease owns rollback');

      rejection.rollback.release.complete();
      await Future.wait([
        rejection.failed,
        unrelated,
        importing,
      ]).timeout(_wait);
      expect(store.locationWrites, ['[]', original, importedRaw]);
      await expectLocationRaw(importedRaw);
      final deletedRaw = await store.diskRaw(_deletedKey);
      final deleted = jsonDecode(deletedRaw!) as Map;
      expect(
        (deleted['todos'] as Map).keys,
        containsAll(['keep', 'queued-local']),
      );
      expect(deleted.containsKey('location_reminders'), isFalse);
      expect(prefs.getString('todos'), isNull);

      // The already-loaded provider must read the imported storage snapshot.
      expect(_ids(provider), ['existing']);
      await provider.add(_reminder('after-import')).timeout(_wait);
      expect(_ids(provider), ['imported', 'after-import']);
      expect(_rawIds(await store.diskRaw()), ['imported', 'after-import']);
      expect(await store.diskRaw(_deletedKey), deletedRaw);
    },
  );

  test('wipe waits for rejected add rollback before clearing data', () async {
    final original = await seedExisting();
    final rejection = await startRejectedWrite();
    var wiped = false;
    final wiping = watch(
      BackupService.wipeAll().then((_) => wiped = true),
      completion(true),
    );

    await Future<void>.delayed(Duration.zero);
    expect(wiped, isFalse);
    expect(store.removedKeys, isEmpty);
    await rejection.enterRollback();
    await Future<void>.delayed(Duration.zero);
    expect(_rawIds(await store.diskRaw()), ['existing', 'rejected']);
    expect(store.locationWrites, hasLength(2));
    expect(store.removedKeys, isEmpty, reason: 'wipe is behind compensation');
    expect(wiped, isFalse);

    rejection.rollback.release.complete();
    await Future.wait([rejection.failed, wiping]).timeout(_wait);
    expect(store.locationWrites.last, original);
    expect(store.removedKeys, contains(_platformKey));
    await expectLocationRaw(null);
    expect(prefs.getString('todos'), isNull);
    expect(await store.diskRaw(_deletedKey), _unrelatedDeletedRaw);

    expect(_ids(provider), ['existing']);
    await provider.add(_reminder('after-wipe')).timeout(_wait);
    expect(_ids(provider), ['after-wipe']);
    expect(_rawIds(await store.diskRaw()), ['after-wipe']);
    expect(await store.diskRaw(_deletedKey), _unrelatedDeletedRaw);
  });

  test(
    'export waits for rollback and preserves the acknowledged raw text',
    () async {
      final original = await seedExisting();
      final rejection = await startRejectedWrite();
      String? exported;
      final exporting = watch(
        BackupService.exportAll().then((raw) {
          exported = raw;
        }),
        completes,
      );

      await Future<void>.delayed(Duration.zero);
      expect(exported, isNull);
      await rejection.enterRollback();
      await Future<void>.delayed(Duration.zero);
      expect(_rawIds(await store.diskRaw()), ['existing', 'rejected']);
      expect(exported, isNull, reason: 'export waits for durable restoration');

      rejection.rollback.release.complete();
      await Future.wait([rejection.failed, exporting]).timeout(_wait);
      final data = (jsonDecode(exported!) as Map)['data'] as Map;
      expect(data[_key], {'type': 'string', 'value': original});
      expect(_rawIds((data[_key] as Map)['value'] as String), ['existing']);
      expect(store.locationWrites, hasLength(2));
      await expectLocationRaw(original);
      expect(await store.diskRaw(_deletedKey), _unrelatedDeletedRaw);
    },
  );

  test('uncertain storage blocks backup until reconciliation', () async {
    final original = await seedExisting();
    await makeUncertain();
    final issued = await store.diskRaw();
    final writesBefore = store.writtenKeys.toList();
    final importedRaw = _rawReminders(['after-reconciliation-import']);
    final operations = <Future<dynamic> Function()>[
      BackupService.exportAll,
      () => BackupService.importAll(_backup(importedRaw), clearMissing: true),
      BackupService.wipeAll,
    ];
    for (final operation in operations) {
      await watch(
        operation(),
        throwsA(isA<LocationReminderStorageIndeterminate>()),
      ).timeout(_wait);
    }
    expect(store.writtenKeys, writesBefore);
    expect(store.removedKeys, isEmpty);
    await expectLocationRaw(issued);
    expect(prefs.getString('todos'), _unrelatedTodoRaw);
    expect(await store.diskRaw(_deletedKey), _unrelatedDeletedRaw);

    await provider.reconcileStorage().timeout(_wait);
    expect(provider.storageNeedsReconciliation, isFalse);
    await expectLocationRaw(original);
    final restoredBackup = await BackupService.exportAll().timeout(_wait);
    final restoredData = (jsonDecode(restoredBackup) as Map)['data'] as Map;
    expect((restoredData[_key] as Map)['value'], original);
    expect(
      await BackupService.importAll(_backup(importedRaw)).timeout(_wait),
      1,
    );
    await provider.add(_reminder('after-import')).timeout(_wait);
    expect(_ids(provider), ['after-reconciliation-import', 'after-import']);
    await BackupService.wipeAll().timeout(_wait);
    await provider.loadFromStorage().timeout(_wait);
    expect(_ids(provider), isEmpty);
    await expectLocationRaw(null);
    expect(await store.diskRaw(_deletedKey), _unrelatedDeletedRaw);
  });

  for (final responseAlreadyPending in [false, true]) {
    final phase = responseAlreadyPending
        ? 'response apply'
        : 'request snapshot';
    test(
      'cloud $phase waits for rollback and reloads outside the lane',
      () async {
        await seedExisting();
        final requestStarted = Completer<void>();
        final responseGate = Completer<void>();
        responseGates.add(responseGate);
        Map<String, dynamic>? outgoing;
        var callbacks = 0;
        var synced = false;
        final remoteRaw = _rawReminders(['remote']);
        final cloud = cloudWith((request) async {
          expect(request.url.path, '/api/sync');
          outgoing = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
          if (!requestStarted.isCompleted) requestStarted.complete();
          if (responseAlreadyPending) await responseGate.future;
          return _cloudResponse(outgoing!, remoteRaw);
        });
        cloud.onSynced = (changed) async {
          expect(changed, contains('location_reminders'));
          await provider.loadFromStorage();
          callbacks++;
          expect(_ids(provider), ['remote']);
        };

        Future<void> startSync() =>
            watch(cloud.syncNow().then((_) => synced = true), completion(true));
        Future<void>? syncing;
        if (responseAlreadyPending) {
          syncing = startSync();
          await requestStarted.future.timeout(_wait);
        }
        final rejection = await startRejectedWrite();
        if (responseAlreadyPending) {
          responseGate.complete();
        } else {
          syncing = startSync();
        }

        await Future<void>.delayed(Duration.zero);
        expect(synced, isFalse);
        expect(callbacks, 0);
        expect(store.locationWrites, hasLength(1));
        if (!responseAlreadyPending) {
          expect(requestStarted.isCompleted, isFalse);
        }

        await rejection.enterRollback();
        await Future<void>.delayed(Duration.zero);
        expect(_rawIds(await store.diskRaw()), ['existing', 'rejected']);
        expect(
          synced,
          isFalse,
          reason: 'cloud operation must wait for rollback',
        );
        expect(callbacks, 0);
        expect(store.locationWrites, hasLength(2));
        if (!responseAlreadyPending) {
          expect(requestStarted.isCompleted, isFalse);
        }

        rejection.rollback.release.complete();
        await Future.wait([rejection.failed, syncing!]).timeout(_wait);
        expect(_listIds(outgoing!['location_reminders'] as List), ['existing']);
        expect(callbacks, 1, reason: 'onSynced may await the location lane');
        expect(cloud.lastError, isNull);
        expect(cloud.hasSyncRetryPending, isFalse);
        expect(cloud.hasPendingChanges, isFalse);
        expect(_rawIds(await store.diskRaw()), ['remote']);
        expect(await store.diskRaw(_deletedKey), _unrelatedDeletedRaw);
        await provider.add(_reminder('after-cloud')).timeout(_wait);
        expect(_ids(provider), ['remote', 'after-cloud']);
        expect(_rawIds(await store.diskRaw()), ['remote', 'after-cloud']);
      },
    );
  }

  for (final responseAlreadyPending in [false, true]) {
    final phase = responseAlreadyPending ? 'in-flight response' : 'new request';
    test(
      'uncertain storage blocks cloud $phase until reconciliation',
      () async {
        final original = await seedExisting();
        final requestStarted = Completer<void>();
        final responseGate = Completer<void>();
        responseGates.add(responseGate);
        var requests = 0;
        var callbacks = 0;
        final remoteRaw = _rawReminders(['remote-after-reconciliation']);
        final cloud = cloudWith((request) async {
          requests++;
          final payload = Map<String, dynamic>.from(
            jsonDecode(request.body) as Map,
          );
          expect(_listIds(payload['location_reminders'] as List), ['existing']);
          if (!requestStarted.isCompleted) requestStarted.complete();
          if (responseAlreadyPending && requests == 1) {
            await responseGate.future;
          }
          return _cloudResponse(payload, remoteRaw);
        });
        cloud.onSynced = (_) async {
          await provider.loadFromStorage();
          callbacks++;
        };
        Future<void>? syncing;
        if (responseAlreadyPending) {
          syncing = watch(cloud.syncNow(), completes);
          await requestStarted.future.timeout(_wait);
        }
        await makeUncertain();
        final issued = await store.diskRaw();
        final writesBefore = store.writtenKeys.toList();
        if (responseAlreadyPending) {
          responseGate.complete();
        } else {
          syncing = watch(cloud.syncNow(), completes);
        }

        await syncing!.timeout(_wait);
        expect(requests, responseAlreadyPending ? 1 : 0);
        expect(callbacks, 0);
        expect(cloud.hasSyncRetryPending, isTrue);
        expect(cloud.syncRetryNotice, isNotNull);
        expect(cloud.isSyncing, isFalse);
        expect(cloud.config.lastSync.millisecondsSinceEpoch, 0);
        expect(prefs.getString('sync_last_time'), isNull);
        expect(prefs.getInt('sync_server_version'), isNull);
        expect(store.writtenKeys, writesBefore);
        await expectLocationRaw(issued);
        expect(await store.diskRaw(_deletedKey), _unrelatedDeletedRaw);

        await provider.reconcileStorage().timeout(_wait);
        await expectLocationRaw(original);
        await watch(cloud.syncNow(), completes).timeout(_wait);
        expect(requests, responseAlreadyPending ? 2 : 1);
        expect(callbacks, 1);
        expect(cloud.lastError, isNull);
        expect(cloud.hasSyncRetryPending, isFalse);
        expect(provider.storageNeedsReconciliation, isFalse);
        expect(_ids(provider), ['remote-after-reconciliation']);
        expect(_rawIds(await store.diskRaw()), ['remote-after-reconciliation']);
        expect(await store.diskRaw(_deletedKey), _unrelatedDeletedRaw);
      },
    );
  }
}

LocationReminder _reminder(String id) => LocationReminder(
  id: id,
  title: 'Location reminder $id',
  note: 'Keep original text / $id',
  latitude: 39.9042,
  longitude: 116.4074,
  radiusMeters: 250,
  trigger: LocationTrigger.enter,
  linkedType: 'todo',
  linkedId: 'todo-$id',
  createdAt: DateTime.utc(2026, 11, 9, 10),
  updatedAt: DateTime.utc(2026, 11, 9, 10),
);

List<String> _ids(LocationReminderProvider provider) =>
    provider.reminders.map((reminder) => reminder.id).toList();

List<String> _listIds(List<dynamic> rows) =>
    rows.map((item) => (item as Map)['id'] as String).toList();

List<String> _rawIds(String? raw) => _listIds(jsonDecode(raw ?? '[]') as List);

String _rawReminders(List<String> ids) =>
    jsonEncode(ids.map((id) => _reminder(id).toJson()).toList());

String _backup(String raw) => jsonEncode({
  'app': 'duoyi',
  'schema': BackupService.schemaVersion,
  'data': {
    _key: {'type': 'string', 'value': raw},
  },
});

http.Response _cloudResponse(Map<String, dynamic> request, String remoteRaw) =>
    http.Response(
      jsonEncode({
        'server_updated_at': '2026-11-09T12:00:00.000Z',
        'server_version': 1,
        'collection_hashes': {
          for (final key in request.keys) key: 'confirmed-$key',
        },
        'location_reminders': jsonDecode(remoteRaw),
        'deleted_items': request['deleted_items'],
      }),
      200,
      headers: const {'content-type': 'application/json'},
    );

class _PendingRejection {
  _PendingRejection(this.write, this.rollback, this.failed);

  final _PlannedWrite write;
  final _PlannedWrite rollback;
  final Future<void> failed;

  Future<void> enterRollback() async {
    write.release.complete();
    await rollback.started.future.timeout(_wait);
  }
}

class _PlannedWrite {
  _PlannedWrite({
    this.hold = false,
    this.rejectAfterWrite = false,
    this.rejectBeforeWrite = false,
  });

  final bool hold;
  final bool rejectAfterWrite;
  final bool rejectBeforeWrite;
  final started = Completer<void>();
  final release = Completer<void>();
}

class _ExternalStorageStore extends InMemorySharedPreferencesStore {
  _ExternalStorageStore() : super.withData(<String, Object>{});

  final locationWrites = <String>[];
  final writtenKeys = <String>[];
  final removedKeys = <String>[];
  final _plannedWrites = <_PlannedWrite>[];
  final _allPlans = <_PlannedWrite>[];

  _PlannedWrite planWrite({
    bool hold = false,
    bool rejectAfterWrite = false,
    bool rejectBeforeWrite = false,
  }) {
    final plan = _PlannedWrite(
      hold: hold,
      rejectAfterWrite: rejectAfterWrite,
      rejectBeforeWrite: rejectBeforeWrite,
    );
    _plannedWrites.add(plan);
    _allPlans.add(plan);
    return plan;
  }

  void releaseAll() {
    for (final plan in _allPlans) {
      if (!plan.release.isCompleted) plan.release.complete();
    }
  }

  void resetTracking() {
    locationWrites.clear();
    writtenKeys.clear();
    removedKeys.clear();
  }

  Future<String?> diskRaw([String key = _key]) async =>
      (await getAll())['flutter.$key'] as String?;

  @override
  Future<bool> remove(String key) async {
    removedKeys.add(key);
    return super.remove(key);
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writtenKeys.add(key);
    if (key != _platformKey) return super.setValue(type, key, value);
    locationWrites.add(value as String);
    if (_plannedWrites.isEmpty) return super.setValue(type, key, value);
    final plan = _plannedWrites.removeAt(0);
    plan.started.complete();
    if (plan.hold) await plan.release.future;
    if (plan.rejectBeforeWrite) return false;
    final accepted = await super.setValue(type, key, value);
    return plan.rejectAfterWrite ? false : accepted;
  }
}
