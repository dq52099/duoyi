import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(AccountPreferenceWrites.drain);

  test(
    'cleanup drains issued metadata and discards queued account marks',
    () async {
      final store = _MetadataStore()
        ..holdKey = 'flutter.sync_preferences_updated_at';
      SharedPreferencesStorePlatform.instance = store;
      final provider = CloudSyncProvider()..dirtyMarkEnabled = true;
      addTearDown(provider.dispose);

      provider.markUserPreferencesChanged(['pref_show_lunar']);
      await store.started.future;
      provider.markUserQuickCaptureTemplatesChanged();
      var cleaned = false;
      final cleanup = AccountLocalDataCleaner.clearSharedPreferences().then((
        _,
      ) {
        cleaned = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(cleaned, isFalse);
      store.release.complete();
      await cleanup;

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((key) => key.startsWith('sync_')), isEmpty);
      expect(
        store.events,
        isNot(contains('set:flutter.sync_preferences_changed_keys')),
      );
      expect(
        store.events,
        isNot(contains('set:flutter.sync_pending_local_changes')),
      );
      expect(
        store.events.indexOf('set:flutter.sync_preferences_updated_at'),
        lessThan(
          store.events.indexOf('remove:flutter.sync_preferences_updated_at'),
        ),
      );
    },
  );

  test('provider suspension drains metadata before reset completes', () async {
    final store = _MetadataStore()
      ..holdKey = 'flutter.sync_preferences_updated_at';
    SharedPreferencesStorePlatform.instance = store;
    final provider = CloudSyncProvider()..dirtyMarkEnabled = true;
    addTearDown(provider.dispose);

    provider.markUserPreferencesChanged(['pref_show_lunar']);
    await store.started.future;
    var reset = false;
    final resetting = provider.resetForAccountChange().then(
      (_) => reset = true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(reset, isFalse);
    store.release.complete();
    await resetting;
    expect(provider.hasPendingChanges, isFalse);
    expect(
      store.events,
      isNot(contains('set:flutter.sync_preferences_changed_keys')),
    );

    await AccountLocalDataCleaner.clearSharedPreferences();
    provider.resumeForActiveAccount();
    provider.markUserPreferencesChanged(['pref_haptic_feedback']);
    await AccountPreferenceWrites.drain();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('sync_preferences_changed_keys'), [
      'pref_haptic_feedback',
    ]);
    expect(prefs.getBool('sync_pending_local_changes'), isTrue);
  });

  test(
    'queued preference key snapshots are persisted in submission order',
    () async {
      final store = _MetadataStore()
        ..holdKey = 'flutter.sync_preferences_updated_at';
      SharedPreferencesStorePlatform.instance = store;
      final provider = CloudSyncProvider()..dirtyMarkEnabled = true;
      addTearDown(provider.dispose);

      provider.markUserPreferencesChanged(['pref_show_lunar']);
      await store.started.future;
      provider.markUserPreferencesChanged(['pref_haptic_feedback']);
      store.release.complete();
      await AccountPreferenceWrites.drain();

      expect(store.keySnapshots, [
        ['pref_show_lunar'],
        ['pref_haptic_feedback', 'pref_show_lunar'],
      ]);
    },
  );

  test(
    'durable mark reports rejection and next write still succeeds',
    () async {
      final store = _MetadataStore()
        ..rejectKeyOnce = 'flutter.sync_pending_local_changes';
      SharedPreferencesStorePlatform.instance = store;
      final provider = CloudSyncProvider();
      addTearDown(provider.dispose);

      await expectLater(
        provider.markUserMutationPendingDurably(),
        throwsStateError,
      );
      await provider.markUserMutationPendingDurably();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sync_pending_local_changes'), isTrue);
    },
  );
  test(
    'successful sync acknowledges slow queued metadata after it drains',
    () async {
      final store = _MetadataStore()
        ..holdKey = 'flutter.sync_preferences_updated_at';
      SharedPreferencesStorePlatform.instance = store;
      final requestStarted = Completer<void>();
      final provider = _syncProvider(requestStarted);
      addTearDown(provider.dispose);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('pref_show_lunar', false);
      provider.markUserPreferencesChanged(['pref_show_lunar']);
      await store.started.future;

      var synced = false;
      final syncing = provider.syncNow().then((_) => synced = true);
      await requestStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(synced, isFalse);
      store.release.complete();
      await syncing;
      await AccountPreferenceWrites.drain();
      expect(provider.lastError, isNull);
      expect(provider.hasPendingChanges, isFalse);
      expect(prefs.getBool('sync_pending_local_changes'), isFalse);
      expect(prefs.getStringList('sync_preferences_changed_keys'), isNull);
    },
  );

  test(
    'a local preference mark during sync acknowledgement remains pending',
    () async {
      final store = _MetadataStore()
        ..holdKey = 'flutter.sync_preferences_values_snapshot';
      SharedPreferencesStorePlatform.instance = store;
      final provider = _syncProvider(Completer<void>());
      addTearDown(provider.dispose);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('pref_show_lunar', false);
      provider.markUserPreferencesChanged(['pref_show_lunar']);
      await AccountPreferenceWrites.drain();

      final syncing = provider.syncNow();
      await store.started.future;
      await prefs.setBool('pref_haptic_feedback', false);
      provider.markUserPreferencesChanged(['pref_haptic_feedback']);
      store.release.complete();
      await syncing;
      await AccountPreferenceWrites.drain();
      expect(provider.lastError, isNull);
      expect(provider.hasPendingChanges, isTrue);
      expect(prefs.getBool('sync_pending_local_changes'), isTrue);
      expect(
        prefs.getStringList('sync_preferences_changed_keys'),
        contains('pref_haptic_feedback'),
      );
    },
  );
  test(
    'auth upload preflight can acknowledge dirty data inside its boundary',
    () async {
      final provider = _syncProvider(Completer<void>());
      addTearDown(provider.dispose);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('pref_show_lunar', false);
      provider.markUserPreferencesChanged(['pref_show_lunar']);
      await AccountPreferenceWrites.drain();

      final accepted = await AccountLocalDataCleaner.runPreferenceBoundary(
        provider.flushPendingLocalChangesBeforeAccountChange,
      );
      expect(accepted, isTrue);
      expect(provider.lastError, isNull);
      expect(provider.hasPendingChanges, isFalse);
      expect(prefs.getBool('sync_pending_local_changes'), isFalse);
      expect(prefs.getStringList('sync_preferences_changed_keys'), isNull);
    },
  );
  test(
    'standalone cleanup drains ordinary sync acknowledgement writes',
    () async {
      final store = _MetadataStore()
        ..holdKey = 'flutter.sync_preferences_values_snapshot';
      SharedPreferencesStorePlatform.instance = store;
      final provider = _syncProvider(Completer<void>());
      addTearDown(provider.dispose);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('pref_show_lunar', false);
      provider.markUserPreferencesChanged(['pref_show_lunar']);
      await AccountPreferenceWrites.drain();

      final syncing = provider.syncNow();
      await store.started.future;
      var cleared = false;
      final cleanup = AccountLocalDataCleaner.clearSharedPreferences().then(
        (_) => cleared = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(cleared, isFalse);
      store.release.complete();
      await Future.wait([syncing, cleanup]);
      await AccountPreferenceWrites.drain();
      expect(prefs.getKeys().where((key) => key.startsWith('sync_')), isEmpty);
    },
  );

  for (final responseKind in ['private', 'workspace', 'both']) {
    test(
      'auth boundary accepts $responseKind tombstone acknowledgement before cleanup',
      () async {
        const stamp = '2026-10-11T03:00:00.000Z';
        final responseExtras = <String, Object>{
          if (responseKind != 'workspace')
            'deleted_items': {
              'todos': {'remote-private': stamp},
            },
          if (responseKind != 'private')
            'workspace_payloads': {
              'synthetic-space': {
                'deleted_items': {
                  'todos': {'remote-shared': stamp},
                },
              },
            },
        };
        final provider = _syncProvider(
          Completer<void>(),
          responseExtras: responseExtras,
        );
        addTearDown(provider.dispose);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('pref_show_lunar', false);
        provider.markUserPreferencesChanged(['pref_show_lunar']);
        await AccountPreferenceWrites.drain();

        await AccountLocalDataCleaner.runPreferenceBoundary(() async {
          final accepted = await provider
              .flushPendingLocalChangesBeforeAccountChange();
          expect(accepted, isTrue);
          expect(provider.lastError, isNull);
          expect(provider.hasPendingChanges, isFalse);
          expect(prefs.getBool('sync_pending_local_changes'), isFalse);
          if (responseKind != 'workspace') {
            expect(
              jsonDecode(prefs.getString('sync_deleted_items')!),
              responseExtras['deleted_items'],
            );
          }
          if (responseKind != 'private') {
            expect(
              jsonDecode(prefs.getString('sync_workspace_deleted_items')!),
              {
                'synthetic-space': {
                  'todos': {'remote-shared': stamp},
                },
              },
            );
          }
          await provider.suspendForAccountChange();
          await AccountLocalDataCleaner.clearSharedPreferences();
        }).timeout(const Duration(seconds: 10));
        expect(
          prefs.getKeys().where((key) => key.startsWith('sync_')),
          isEmpty,
        );
      },
    );
  }
}

CloudSyncProvider _syncProvider(
  Completer<void> requestStarted, {
  Map<String, Object> responseExtras = const {},
}) {
  final client = ApiClient(
    baseUrl: 'https://duoyi.test',
    token: 'synthetic-token',
    httpClient: MockClient((request) async {
      final sent = json.decode(request.body) as Map<String, dynamic>;
      if (!requestStarted.isCompleted) requestStarted.complete();
      return http.Response(
        json.encode({
          'server_updated_at': '2026-10-11T03:00:00.000Z',
          'server_version': 1,
          'collection_hashes': {
            for (final key in sent.keys) key: 'confirmed-$key',
          },
          'preferences': sent['preferences'],
          ...responseExtras,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  final provider = CloudSyncProvider()..dirtyMarkEnabled = true;
  provider.apiClientGetter = () => client;
  provider.serverConfigGetter = () => {'backup_enabled': true};
  return provider;
}

class _MetadataStore extends InMemorySharedPreferencesStore {
  _MetadataStore() : super.withData({});

  String? holdKey;
  String? rejectKeyOnce;
  final started = Completer<void>();
  final release = Completer<void>();
  final events = <String>[];
  final keySnapshots = <List<String>>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == holdKey && !started.isCompleted) {
      started.complete();
      await release.future;
    }
    if (key == rejectKeyOnce) {
      rejectKeyOnce = null;
      return false;
    }
    final saved = await super.setValue(valueType, key, value);
    events.add('set:$key');
    if (key == 'flutter.sync_preferences_changed_keys') {
      keySnapshots.add(List<String>.from(value as List));
    }
    return saved;
  }

  @override
  Future<bool> remove(String key) async {
    final removed = await super.remove(key);
    events.add('remove:$key');
    return removed;
  }
}
