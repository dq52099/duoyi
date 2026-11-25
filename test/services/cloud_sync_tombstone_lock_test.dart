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
  late _TombstoneStore store;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = _TombstoneStore();
    SharedPreferencesStorePlatform.instance = store;
  });
  tearDown(() async {
    if (!store.release.isCompleted) store.release.complete();
    await AccountPreferenceWrites.drain();
  });

  for (final workspace in [false, true]) {
    final key = workspace
        ? CloudSyncProvider.workspaceDeletedItemsStorageKey
        : CloudSyncProvider.deletedItemsStorageKey;
    final space = workspace ? 'synthetic-space' : null;

    test('concurrent standalone deletes retain both records in $key', () async {
      store.holdKey = 'flutter.$key';
      final first = CloudSyncProvider.recordDeletedItem(
        'todos',
        'first',
        workspaceId: space,
      );
      await store.started.future;
      final second = CloudSyncProvider.recordDeletedItem(
        'todos',
        'second',
        workspaceId: space,
      );
      await Future<void>.delayed(Duration.zero);
      expect(store.tombstoneWrites, 1);
      store.release.complete();
      await Future.wait([first, second]);
      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(prefs.getString(key)!) as Map;
      final bucket = workspace ? decoded['synthetic-space'] as Map : decoded;
      expect((bucket['todos'] as Map).keys, containsAll(['first', 'second']));
    });

    test(
      'failed sync merge cannot erase a queued local delete in $key',
      () async {
        store.holdKey = 'flutter.$key';
        store.rejectHeld = true;
        final provider = _sync(workspace);
        addTearDown(provider.dispose);
        final syncing = provider.syncNow();
        await store.started.future;
        final localDelete = CloudSyncProvider.recordDeletedItem(
          'todos',
          'accepted-local',
          workspaceId: space,
        );
        await Future<void>.delayed(Duration.zero);
        expect(store.tombstoneWrites, 1);
        store.release.complete();
        await Future.wait([syncing, localDelete]);
        expect(provider.hasSyncRetryPending, isTrue);
        expect(provider.syncRetryNotice, isNotNull);
        final prefs = await SharedPreferences.getInstance();
        final decoded = jsonDecode(prefs.getString(key)!) as Map;
        final bucket = workspace ? decoded['synthetic-space'] as Map : decoded;
        expect((bucket['todos'] as Map).keys, ['accepted-local']);
      },
    );

    test(
      'cleanup drains $key and rejects its queued account follower',
      () async {
        store.holdKey = 'flutter.$key';
        final first = CloudSyncProvider.recordDeletedItem(
          'todos',
          'old-first',
          workspaceId: space,
        );
        await store.started.future;
        final second = CloudSyncProvider.recordDeletedItem(
          'todos',
          'old-follower',
          workspaceId: space,
        );
        var cleaned = false;
        final cleanup = AccountLocalDataCleaner.clearSharedPreferences().then(
          (_) => cleaned = true,
        );
        await Future<void>.delayed(Duration.zero);
        expect(cleaned, isFalse);
        store.release.complete();
        await Future.wait([first, second, cleanup]);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(key), isNull);
        await CloudSyncProvider.recordDeletedItem(
          'todos',
          'new-account',
          workspaceId: space,
        );
        final decoded = jsonDecode(prefs.getString(key)!) as Map;
        final bucket = workspace ? decoded['synthetic-space'] as Map : decoded;
        expect((bucket['todos'] as Map).keys, ['new-account']);
      },
    );
  }

  test('an expired lease cannot join a later transaction', () async {
    late DeletedItemsWriteLease retained;
    await CloudSyncProvider.withDeletedItemsLock((lease) async {
      retained = lease;
      expect(lease.isCurrent, isTrue);
    });
    expect(retained.isCurrent, isFalse);
    final prefs = await SharedPreferences.getInstance();
    final transaction = AccountPreferenceTransaction(prefs, () => true);
    await expectLater(
      CloudSyncProvider.recordDeletedItem(
        'todos',
        'expired',
        transaction: transaction,
        lease: retained,
      ),
      throwsA(isA<AccountPreferenceWriteCanceled>()),
    );
    expect(prefs.getString(CloudSyncProvider.deletedItemsStorageKey), isNull);
  });

  test('joining a transaction requires its owning lease', () async {
    final prefs = await SharedPreferences.getInstance();
    final transaction = AccountPreferenceTransaction(prefs, () => true);
    await expectLater(
      CloudSyncProvider.recordDeletedItem(
        'todos',
        'missing-lease',
        transaction: transaction,
      ),
      throwsStateError,
    );
    await CloudSyncProvider.withDeletedItemsLock((lease) async {
      await expectLater(
        CloudSyncProvider.recordDeletedItem(
          'todos',
          'missing-transaction',
          lease: lease,
        ),
        throwsStateError,
      );
    });
    expect(prefs.getString(CloudSyncProvider.deletedItemsStorageKey), isNull);
  });

  test(
    'ordinary deletes cannot use an auth boundary to gain write authority',
    () async {
      var entered = false;
      await AccountLocalDataCleaner.runPreferenceBoundary(() async {
        await CloudSyncProvider.recordDeletedItem('todos', 'private-blocked');
        await CloudSyncProvider.recordDeletedItem(
          'todos',
          'shared-blocked',
          workspaceId: 'synthetic-space',
        );
        await expectLater(
          CloudSyncProvider.withDeletedItemsLock((_) async => entered = true),
          throwsA(isA<AccountPreferenceWriteCanceled>()),
        );
      });
      expect(entered, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(CloudSyncProvider.deletedItemsStorageKey), isNull);
      expect(
        prefs.getString(CloudSyncProvider.workspaceDeletedItemsStorageKey),
        isNull,
      );
    },
  );
}

CloudSyncProvider _sync(bool workspace) {
  const stamp = '2026-10-12T10:00:00.000Z';
  final provider = CloudSyncProvider();
  final client = ApiClient(
    baseUrl: 'https://duoyi.test',
    token: 'synthetic-token',
    httpClient: MockClient((request) async {
      final payload = jsonDecode(request.body) as Map;
      return http.Response(
        jsonEncode({
          'server_updated_at': stamp,
          'server_version': 1,
          'collection_hashes': {
            for (final key in payload.keys) key: 'confirmed-$key',
          },
          if (!workspace)
            'deleted_items': {
              'todos': {'rejected-remote': stamp},
            },
          if (workspace)
            'workspace_payloads': {
              'synthetic-space': {
                'deleted_items': {
                  'todos': {'rejected-remote': stamp},
                },
              },
            },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  provider.apiClientGetter = () => client;
  provider.serverConfigGetter = () => {'backup_enabled': true};
  return provider;
}

class _TombstoneStore extends InMemorySharedPreferencesStore {
  _TombstoneStore() : super.withData({});
  String? holdKey;
  bool rejectHeld = false;
  int tombstoneWrites = 0;
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.sync_deleted_items' ||
        key == 'flutter.sync_workspace_deleted_items') {
      tombstoneWrites++;
    }
    if (key == holdKey && !started.isCompleted) {
      started.complete();
      await release.future;
      await super.setValue(type, key, value);
      return !rejectHeld;
    }
    return super.setValue(type, key, value);
  }
}
