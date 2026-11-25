// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/location_reminder_storage.dart';
import 'package:duoyi/core/oauth_calendar_storage.dart';
import 'package:duoyi/models/location_reminder.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _locationKey = LocationReminderStorage.locationKey;
const _pendingKey = 'sync_pending_local_changes';
const _lastSyncKey = 'sync_last_time';
const _wait = Duration(seconds: 5);
const _authTimeout = Duration(milliseconds: 20);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferencesStorePlatform originalStore;
  late _BoundaryStore store;
  late SharedPreferences prefs;
  final clouds = <CloudSyncProvider>[];
  final clients = <http.Client>[];
  final checks = <Future<void>>[];
  final responseGates = <Completer<void>>[];
  final clocks = <FakeAsync>[];

  setUp(() async {
    await AccountPreferenceWrites.drain().timeout(_wait);
    originalStore = SharedPreferencesStorePlatform.instance;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = _BoundaryStore();
    SharedPreferencesStorePlatform.instance = store;
    prefs = await SharedPreferences.getInstance();
    await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    store.events.clear();
    clouds.clear();
    clients.clear();
    checks.clear();
    responseGates.clear();
    clocks.clear();
  });

  tearDown(() async {
    store.releaseHeldWrite();
    for (final gate in responseGates) {
      if (!gate.isCompleted) gate.complete();
    }
    for (final clock in clocks) {
      clock.elapse(_authTimeout);
      clock.flushMicrotasks();
    }
    try {
      await Future.wait(checks).timeout(_wait);
    } finally {
      for (final clock in clocks) {
        clock.flushMicrotasks();
      }
      try {
        await AccountPreferenceWrites.drain().timeout(_wait);
        // Failed cleanup does not retire the epoch. Reset through a real,
        // confirmed cleanup after the old request and timeout have settled.
        store.rejectRemoveKeyOnce = null;
        await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
      } finally {
        for (final cloud in clouds) {
          cloud.dispose();
        }
        for (final client in clients) {
          client.close();
        }
        SharedPreferences.setMockInitialValues(<String, Object>{});
        SharedPreferencesStorePlatform.instance = originalStore;
      }
    }
  });

  Future<void> watch(Future<dynamic> future, Matcher matcher) {
    final check = expectLater(future, matcher);
    // Observe failures immediately, including when an earlier assertion fails
    // while a held write or response still needs teardown to release it.
    unawaited(check.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    checks.add(check);
    return check;
  }

  CloudSyncProvider cloudWith(
    Future<http.Response> Function(http.Request) handler,
  ) {
    final transport = MockClient(handler);
    clients.add(transport);
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'synthetic-token',
      httpClient: transport,
    );
    final cloud = CloudSyncProvider();
    cloud.apiClientGetter = () => client;
    cloud.serverConfigGetter = () => {'backup_enabled': true};
    clouds.add(cloud);
    return cloud;
  }

  Future<String> seedPending(CloudSyncProvider cloud) async {
    final raw = jsonEncode([_reminder('local').toJson()]);
    await prefs.setString(_locationKey, raw);
    await cloud.markUserMutationPendingDurably();
    expect(prefs.getBool(_pendingKey), isTrue);
    store.events.clear();
    return raw;
  }

  Future<void> expectCleared() async {
    final disk = await store.getAll();
    expect(
      disk.keys.where((key) => key.startsWith('flutter.sync_')),
      isEmpty,
      reason: 'confirmed cleanup must remove backing sync metadata',
    );
    expect(disk['flutter.$_locationKey'], isNull);
    await prefs.reload();
    expect(prefs.getKeys().where((key) => key.startsWith('sync_')), isEmpty);
    expect(prefs.getString(_locationKey), isNull);
  }

  for (final failure in _PendingWriteFailure.values) {
    test(
      'failed upload with ${failure.name} repair remains pending and can sync again',
      () async {
        var requests = 0;
        var callbacks = 0;
        final cloud = cloudWith((request) async {
          expect(request.url.path, '/api/sync');
          requests++;
          if (requests == 1) {
            return http.Response(
              jsonEncode({'detail': 'synthetic upload failure'}),
              500,
              headers: const {'content-type': 'application/json'},
            );
          }
          return _cloudResponse(request);
        });
        cloud.onSynced = (changed) async {
          expect(changed, contains('location_reminders'));
          callbacks++;
        };
        final originalRaw = await seedPending(cloud);
        store.planPendingWriteFailure(failure);

        // A failed repair is secondary to the failed upload. syncNow must
        // settle normally, retaining the failure and leaving the busy state.
        await watch(cloud.syncNow(), completes).timeout(_wait);
        expect(requests, 1);
        expect(callbacks, 0);
        expect(cloud.isSyncing, isFalse);
        expect(cloud.hasPendingChanges, isTrue);
        expect(cloud.lastError, isNotNull);
        expect(cloud.hasSyncRetryPending, isFalse);
        expect(cloud.config.lastSync.millisecondsSinceEpoch, 0);
        expect(store.events, contains('${failure.name}:flutter.$_pendingKey'));
        expect(store.events, isNot(contains('set:flutter.$_pendingKey')));
        final afterFailure = await store.getAll();
        expect(afterFailure['flutter.$_pendingKey'], isTrue);
        expect(afterFailure['flutter.$_locationKey'], originalRaw);
        expect(afterFailure['flutter.$_lastSyncKey'], isNull);

        // The one-shot failure is consumed. A new explicit sync must run,
        // rather than becoming a waiter behind the failed request forever.
        await watch(cloud.syncNow(), completes).timeout(_wait);
        expect(requests, 2);
        expect(callbacks, 1);
        expect(cloud.isSyncing, isFalse);
        expect(cloud.hasPendingChanges, isFalse);
        expect(cloud.lastError, isNull);
        expect(cloud.hasSyncRetryPending, isFalse);
        final afterRetry = await store.getAll();
        expect(afterRetry['flutter.$_pendingKey'], isFalse);
        expect(afterRetry['flutter.$_lastSyncKey'], isA<String>());
        expect(
          (jsonDecode(afterRetry['flutter.$_locationKey'] as String) as List)
              .map((item) => (item as Map)['id']),
          ['remote'],
        );
        await prefs.reload();
        expect(prefs.getBool(_pendingKey), isFalse);
      },
    );
  }

  test(
    'auth upload error marker settles before direct cleanup removes sync data',
    () async {
      var requests = 0;
      var callbacks = 0;
      final cloud = cloudWith((request) async {
        expect(request.url.path, '/api/sync');
        requests++;
        return http.Response(
          jsonEncode({'detail': 'synthetic upload failure'}),
          500,
          headers: const {'content-type': 'application/json'},
        );
      });
      cloud.onSynced = (_) async {
        callbacks++;
      };
      await seedPending(cloud);
      store.holdKey = 'flutter.$_pendingKey';
      try {
        final flushing = watch(
          AccountLocalDataCleaner.runPreferenceBoundary(
            cloud.flushPendingLocalChangesBeforeAccountChange,
          ),
          completion(isFalse),
        );
        await store.started.future.timeout(_wait);
        expect(requests, 1);
        expect(callbacks, 0);
        expect(AccountPreferenceWrites.isBoundaryActive, isTrue);
        expect(store.events, contains('issue:flutter.$_pendingKey'));
        final eventsWhileHeld = store.events.toList();

        var cleaned = false;
        final cleanup = watch(
          AccountLocalDataCleaner.clearSharedPreferences().then((_) {
            cleaned = true;
          }),
          completes,
        );
        await _settleReadyWork();
        expect(
          cleaned,
          isFalse,
          reason: 'the issued repair marker owns the lane',
        );
        expect(store.events, [
          ...eventsWhileHeld,
          'issue:flutter.${OAuthCalendarStorage.retirementFenceKey}',
          'set:flutter.${OAuthCalendarStorage.retirementFenceKey}',
        ]);

        store.releaseHeldWrite();
        await Future.wait([flushing, cleanup]).timeout(_wait);
        expect(cleaned, isTrue);
        expect(callbacks, 0);
        expect(store.events, contains('set:flutter.$_pendingKey'));
        expect(store.events, contains('remove:flutter.$_pendingKey'));
        expect(
          store.events.indexOf('set:flutter.$_pendingKey'),
          lessThan(store.events.indexOf('remove:flutter.$_pendingKey')),
        );
        await expectCleared();
      } finally {
        store.releaseHeldWrite();
      }
    },
  );

  test(
    'direct sync timestamp acknowledgement holds cleanup and suppresses callbacks',
    () async {
      var callbacks = 0;
      final cloud = cloudWith((request) async => _cloudResponse(request));
      cloud.onSynced = (_) async {
        callbacks++;
      };
      await seedPending(cloud);
      store.holdKey = 'flutter.$_lastSyncKey';
      try {
        final syncing = watch(cloud.syncNow(), completes);
        await store.started.future.timeout(_wait);
        expect(store.events, contains('set:flutter.$_locationKey'));
        expect(callbacks, 0);
        final eventsWhileHeld = store.events.toList();

        var cleaned = false;
        final cleanup = watch(
          AccountLocalDataCleaner.clearSharedPreferences().then((_) {
            cleaned = true;
          }),
          completes,
        );
        await _settleReadyWork();
        expect(
          cleaned,
          isFalse,
          reason: 'timestamp acknowledgement owns the lane',
        );
        expect(store.events, [
          ...eventsWhileHeld,
          'issue:flutter.${OAuthCalendarStorage.retirementFenceKey}',
          'set:flutter.${OAuthCalendarStorage.retirementFenceKey}',
        ]);
        expect(callbacks, 0);

        store.releaseHeldWrite();
        await Future.wait([syncing, cleanup]).timeout(_wait);
        expect(callbacks, 0, reason: 'cleanup invalidates publication authority');
        expect(store.events, contains('set:flutter.$_lastSyncKey'));
        expect(store.events, contains('remove:flutter.$_lastSyncKey'));
        expect(
          store.events.indexOf('set:flutter.$_lastSyncKey'),
          lessThan(store.events.indexOf('remove:flutter.$_lastSyncKey')),
        );
        await expectCleared();
      } finally {
        store.releaseHeldWrite();
      }
    },
  );

  test(
    'auth timeout retains old identity after failed direct cleanup',
    () async {
      final requestStarted = Completer<void>();
      final responseGate = Completer<void>();
      responseGates.add(responseGate);
      var requests = 0;
      var callbacks = 0;
      final cloud = cloudWith((request) async {
        requests++;
        if (!requestStarted.isCompleted) requestStarted.complete();
        await responseGate.future;
        return _cloudResponse(request);
      });
      cloud.onSynced = (_) async {
        callbacks++;
      };
      final originalRaw = await seedPending(cloud);
      final originalEpoch = LocationReminderStorage.storageEpoch;
      final originalGeneration = AccountLocalDataCleaner.accountDataGeneration;
      final syncing = watch(cloud.syncNow(), completes);
      await requestStarted.future.timeout(_wait);

      // The real request is already held. Auth queues behind that same request,
      // so its timeout can be advanced exactly without fake-clock isolate I/O.
      final clock = FakeAsync();
      clocks.add(clock);
      bool? accepted;
      // Keep the matcher/await future in the real zone. FakeAsync owns only
      // the auth deadline; its completion crosses this explicit bridge.
      final authFinished = Completer<bool>();
      clock.run((_) {
        final result = AccountLocalDataCleaner.runPreferenceBoundary(
          () => cloud.flushPendingLocalChangesBeforeAccountChange(
            timeout: _authTimeout,
          ),
        );
        unawaited(
          result.then<void>((value) {
            accepted = value;
            authFinished.complete(value);
          }, onError: authFinished.completeError),
        );
      });
      final flushing = watch(authFinished.future, completion(isFalse));
      clock.flushMicrotasks();
      expect(accepted, isNull);
      expect(AccountPreferenceWrites.isBoundaryActive, isTrue);
      expect(
        clock.nonPeriodicTimerCount,
        1,
        reason:
            'auth is waiting with its timeout armed behind the held request',
      );

      store.rejectRemoveKeyOnce = 'flutter.$_locationKey';
      await watch(
        AccountLocalDataCleaner.clearSharedPreferences(),
        throwsStateError,
      ).timeout(_wait);
      expect(LocationReminderStorage.storageEpoch, originalEpoch);
      expect(
        AccountLocalDataCleaner.accountDataGeneration,
        greaterThan(originalGeneration),
      );
      expect((await store.getAll())['flutter.$_locationKey'], originalRaw);
      final eventsAfterFailedClear = store.events.toList();

      clock.elapse(_authTimeout);
      clock.flushMicrotasks();
      expect(accepted, isFalse);
      expect(AccountPreferenceWrites.isBoundaryActive, isFalse);
      expect(
        store.events,
        eventsAfterFailedClear,
        reason: 'timeout must not adopt the failed cleanup\'s current identity',
      );
      expect((await store.getAll())['flutter.$_pendingKey'], isNull);

      responseGate.complete();
      await syncing.timeout(_wait);
      clock.flushMicrotasks();
      await flushing.timeout(_wait);
      expect(requests, 1);
      expect(callbacks, 0);
      expect(cloud.isSyncing, isFalse);
      expect(
        store.events,
        eventsAfterFailedClear,
        reason: 'old response cannot apply',
      );
      expect((await store.getAll())['flutter.$_locationKey'], originalRaw);
      await prefs.reload();
      expect(prefs.getString(_locationKey), originalRaw);
      expect(prefs.getKeys().where((key) => key.startsWith('sync_')), isEmpty);
    },
  );
}

// Every fake-store operation completes in microtasks. A single event-queue
// barrier drains all currently runnable continuations; no elapsed-time sleep
// is used to establish whether cleanup is blocked on the explicit write gate.
Future<void> _settleReadyWork() => Future<void>(() {});

LocationReminder _reminder(String id) => LocationReminder(
  id: id,
  title: 'Synthetic $id reminder',
  latitude: 31.2,
  longitude: 121.5,
  createdAt: DateTime.utc(2026, 11, 1),
  updatedAt: DateTime.utc(2026, 11, 9),
);

http.Response _cloudResponse(http.Request request) {
  final sent = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
  return http.Response(
    jsonEncode({
      'server_updated_at': '2026-11-09T12:00:00.000Z',
      'server_version': 1,
      'collection_hashes': {for (final key in sent.keys) key: 'confirmed-$key'},
      'location_reminders': [_reminder('remote').toJson()],
      'deleted_items': sent['deleted_items'],
    }),
    200,
    headers: const {'content-type': 'application/json'},
  );
}

enum _PendingWriteFailure { returnsFalse, throwsError }

class _BoundaryStore extends InMemorySharedPreferencesStore {
  _BoundaryStore() : super.withData(<String, Object>{});

  String? holdKey;
  String? rejectRemoveKeyOnce;
  final started = Completer<void>();
  final release = Completer<void>();
  final events = <String>[];
  final _pendingWriteFailures = <_PendingWriteFailure>[];

  void planPendingWriteFailure(_PendingWriteFailure failure) {
    _pendingWriteFailures.add(failure);
  }

  void releaseHeldWrite() {
    if (!release.isCompleted) release.complete();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    events.add('issue:$key');
    if (key == holdKey && !started.isCompleted) {
      started.complete();
      await release.future;
    }
    if (key == 'flutter.$_pendingKey' && _pendingWriteFailures.isNotEmpty) {
      final failure = _pendingWriteFailures.removeAt(0);
      events.add('${failure.name}:$key');
      if (failure == _PendingWriteFailure.throwsError) {
        throw StateError('Synthetic pending-marker write failure');
      }
      return false;
    }
    final saved = await super.setValue(type, key, value);
    events.add('set:$key');
    return saved;
  }

  @override
  Future<bool> remove(String key) async {
    events.add('remove:$key');
    if (key == rejectRemoveKeyOnce) {
      rejectRemoveKeyOnce = null;
      return false;
    }
    return super.remove(key);
  }
}
