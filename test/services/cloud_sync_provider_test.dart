import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/services/cloud_sync_notice.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  test(
    'generated sync notices render both locales without exposing diagnostics',
    () {
      for (final kind in CloudSyncNoticeKind.values) {
        final notice = CloudSyncNotice(
          kind,
          error: StateError('secret diagnostic'),
        );
        final zh = notice.render(locale: AppLocale.zh);
        final en = notice.render(locale: AppLocale.en);
        expect(zh, isNotEmpty, reason: kind.name);
        expect(en, isNotEmpty, reason: kind.name);
        expect(
          en,
          isNot(matches(RegExp(r'[\u3400-\u9fff]'))),
          reason: kind.name,
        );
        expect(en, isNot(contains('secret diagnostic')));
        expect(zh, isNot(contains('secret diagnostic')));
        expect(zh, isNot(en));
        expect(I18n.current, AppLocale.zh);
      }
      const error = ApiException('409: 项目 Aurora 已在其他设备修改');
      const notice = CloudSyncNotice(
        CloudSyncNoticeKind.remotePullRetry,
        error: error,
      );
      for (final locale in AppLocale.values) {
        expect(notice.render(locale: locale), contains('项目 Aurora 已在其他设备修改'));
      }
      expect(notice.withKind(CloudSyncNoticeKind.failure).error, same(error));
    },
  );

  test(
    'locale notifications are detached when sync provider is disposed',
    () async {
      final provider = CloudSyncProvider();
      var notifications = 0;
      provider.addListener(() => notifications++);
      I18n.setLocale(AppLocale.en);
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1);
      expect(provider.localSaveSyncMessage(), contains('Saved on this device'));
      expect(
        provider.localSaveSyncMessage(localSavedText: '自定义已保存'),
        startsWith('自定义已保存'),
      );
      expect(provider.hasPendingChanges, isFalse);
      expect(provider.hasSyncRetryPending, isFalse);
      provider.dispose();
      I18n.setLocale(AppLocale.zh);
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1);
    },
  );

  for (final pendingChanges in [false, true]) {
    test(
      'cached sync failure follows locale without new requests (pending=$pendingChanges)',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          if (pendingChanges) 'sync_pending_local_changes': true,
        });
        var requests = 0;
        final httpClient = MockClient((request) async {
          requests++;
          return http.Response(
            json.encode({'detail': 'internal diagnostic'}),
            500,
          );
        });
        addTearDown(httpClient.close);
        final client = ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'synthetic-token',
          httpClient: httpClient,
        );
        final provider = CloudSyncProvider();
        addTearDown(provider.dispose);
        provider.apiClientGetter = () => client;
        provider.serverConfigGetter = () => {'backup_enabled': true};
        await provider.loadFromStorage();
        await provider.syncNow();
        await Future<void>.delayed(Duration.zero);
        final zhStatus = pendingChanges
            ? provider.lastError
            : provider.syncRetryStatus;
        final zhLocalSave = provider.localSaveSyncMessage();
        final notice = pendingChanges
            ? provider.lastErrorNotice
            : provider.syncRetryNotice;
        final config = provider.config;
        final requestCount = requests;
        expect(requestCount, greaterThan(0));
        var notifications = 0;
        provider.addListener(() => notifications++);
        I18n.setLocale(AppLocale.en);
        await Future<void>.delayed(Duration.zero);
        final enStatus = pendingChanges
            ? provider.lastError
            : provider.syncRetryStatus;
        expect(enStatus, isNot(zhStatus));
        expect(enStatus, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
        expect(enStatus, isNot(contains('internal diagnostic')));
        expect(provider.localSaveSyncMessage(), isNot(zhLocalSave));
        expect(
          provider.localSaveSyncMessage(),
          contains(pendingChanges ? 'Cloud sync failed' : 'Initial sync'),
        );
        expect(notifications, 1);
        expect(
          pendingChanges ? provider.lastErrorNotice : provider.syncRetryNotice,
          same(notice),
        );
        expect(provider.config, same(config));
        expect(provider.hasPendingChanges, pendingChanges);
        expect(provider.hasSyncRetryPending, !pendingChanges);
        expect(provider.isSyncSuspended, isFalse);
        expect(provider.isSyncing, isFalse);
        expect(provider.lastServerVersion, isNull);
        I18n.setLocale(AppLocale.zh);
        await Future<void>.delayed(Duration.zero);
        expect(
          pendingChanges ? provider.lastError : provider.syncRetryStatus,
          zhStatus,
        );
        expect(provider.localSaveSyncMessage(), zhLocalSave);
        expect(requests, requestCount);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getBool('sync_pending_local_changes') == true,
          pendingChanges,
        );
      },
    );
  }

  test('账号切换会冻结云同步并阻断旧账号异步回写', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();

    for (final field in const [
      'int _accountGeneration = 0;',
      'bool _syncSuspendedForAccountChange = false;',
      'Future<void>? _activeLocalWriteback;',
      'Future<T> _runAccountBoundWriteback<T>',
      'Future<void> resetForAccountChange() async',
      '_syncSuspendedForAccountChange = true;',
      'final activeWriteback = _activeLocalWriteback;',
      'await activeWriteback;',
      'void resumeForActiveAccount()',
      'expectedAccountGeneration',
      '_pullRemoteChanges(expectedAccountGeneration: accountGenerationAtStart)',
      'accountGenerationAtStart: accountGenerationAtStart',
    ]) {
      expect(providerSource, contains(field), reason: field);
    }

    expect(
      providerSource,
      contains(
        'if (_syncSuspendedForAccountChange) {\n'
        '      _lastError = null;\n'
        '      _clearSyncRetryPending();\n'
        '      _notifySyncStateChanged();\n'
        '      return;\n'
        '    }',
      ),
    );
    expect(mainSource, contains('cloudSyncProvider.resetForAccountChange,'));
    expect(mainSource, contains('cloudSyncProvider.resumeForActiveAccount();'));
  });

  test('resetForAccountChange 后旧账号 sync 响应不会写回本地', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'todos': json.encode([
        {'id': 'local-before-switch', 'title': '切号前本地数据'},
      ]),
    });
    final requestStarted = Completer<void>();
    final responseCompleter = Completer<http.Response>();
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/sync') {
          if (!requestStarted.isCompleted) requestStarted.complete();
          return responseCompleter.future;
        }
        return http.Response('{}', 200);
      }),
    );
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () => client;
    provider.serverConfigGetter = () => {'backup_enabled': true};

    final syncFuture = provider.syncNow();
    await requestStarted.future.timeout(const Duration(seconds: 1));
    await provider.resetForAccountChange();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'todos',
      json.encode([
        {'id': 'test-local', 'title': '新账号清理后的本地数据'},
      ]),
    );
    responseCompleter.complete(
      http.Response(
        json.encode({
          'server_updated_at': '2026-06-07T00:00:00.000Z',
          'server_version': 1,
          'todos': [
            {'id': 'admin-remote', 'title': '旧账号远端数据'},
          ],
        }),
        200,
        headers: const {'content-type': 'application/json'},
      ),
    );

    await syncFuture.timeout(const Duration(seconds: 2));
    final todos = prefs.getString('todos') ?? '';
    expect(todos, contains('test-local'));
    expect(todos, isNot(contains('admin-remote')));

    provider.dispose();
  });

  test('resetForAccountChange 后旧账号本地同步元数据不会重新载入内存', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sync_last_time': '2026-06-07T12:00:00.000Z',
      'sync_auto': false,
      'sync_pending_local_changes': true,
      'sync_server_updated_at': '2026-06-07T12:00:00.000Z',
      'sync_server_version': 9,
    });
    final provider = CloudSyncProvider();

    final loadFuture = provider.loadFromStorage();
    await provider.resetForAccountChange();
    await loadFuture.timeout(const Duration(seconds: 1));

    expect(provider.config.autoSync, isTrue);
    expect(provider.config.lastSync.millisecondsSinceEpoch, 0);
    expect(provider.hasPendingChanges, isFalse);
    expect(provider.lastServerUpdatedAt, isEmpty);
    expect(provider.lastServerVersion, isNull);

    provider.dispose();
  });

  test('resetForAccountChange 会等待进行中的同步回调退出', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final onSyncedStarted = Completer<void>();
    final releaseOnSynced = Completer<void>();
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        return http.Response(
          json.encode({
            'server_updated_at': '2026-06-07T00:00:00.000Z',
            'server_version': 1,
            'todos': [
              {'id': 'remote-during-switch', 'title': '写回中'},
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () => client;
    provider.serverConfigGetter = () => {'backup_enabled': true};
    provider.onSynced = (changedCollections) async {
      expect(changedCollections, contains('todos'));
      if (!onSyncedStarted.isCompleted) onSyncedStarted.complete();
      await releaseOnSynced.future;
    };

    final syncFuture = provider.syncNow();
    await onSyncedStarted.future.timeout(const Duration(seconds: 1));

    var resetCompleted = false;
    final resetFuture = provider.resetForAccountChange().then((_) {
      resetCompleted = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(resetCompleted, isFalse);

    releaseOnSynced.complete();
    await resetFuture.timeout(const Duration(seconds: 1));
    await syncFuture.timeout(const Duration(seconds: 1));
    expect(resetCompleted, isTrue);

    provider.dispose();
  });

  test('未登录 syncNow 不写 lastError 且不伪装本地 pending', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () => ApiClient(baseUrl: 'https://duoyi.test');

    await provider.syncNow();

    expect(provider.lastError, isNull);
    expect(provider.hasPendingChanges, isFalse);
    expect(provider.syncUnavailableStatus, contains('未登录'));
    expect(provider.hasSyncRetryPending, isFalse);

    provider.dispose();
  });

  test('管理员关闭备份不写 lastError 且不伪装本地 pending', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () =>
        ApiClient(baseUrl: 'https://duoyi.test', token: 'admin-token');
    provider.serverConfigGetter = () => {'backup_enabled': false};

    await provider.syncNow();

    expect(provider.lastError, isNull);
    expect(provider.hasPendingChanges, isFalse);
    expect(provider.isBackupDisabledByServer, isTrue);
    expect(provider.syncUnavailableStatus, contains('管理员已关闭云端备份'));
    expect(provider.hasSyncRetryPending, isFalse);

    provider.dispose();
  });

  test('本机保存提示按云同步可用性区分是否已上传服务器', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () => ApiClient(baseUrl: 'https://duoyi.test');

    expect(provider.localSaveSyncMessage(), contains('尚未上传服务器：未登录云同步账号'));

    provider.apiClientGetter = () =>
        ApiClient(baseUrl: 'https://duoyi.test', token: 'token');
    provider.serverConfigGetter = () => {'backup_enabled': false};
    expect(
      provider.localSaveSyncMessage(localSavedText: '待办已保存到本机'),
      contains('待办已保存到本机，尚未上传服务器：管理员已关闭云端备份'),
    );

    provider.serverConfigGetter = () => {'backup_enabled': true};
    await provider.setAutoSync(false);
    expect(provider.localSaveSyncMessage(), contains('自动同步已关闭'));

    await provider.setAutoSync(true);
    expect(provider.localSaveSyncMessage(), contains('云同步会后台上传'));

    provider.dispose();
  });

  test('账号切换恢复后备份关闭状态不再吞本地 dirty mark', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () =>
        ApiClient(baseUrl: 'https://duoyi.test', token: 'admin-token');
    provider.serverConfigGetter = () => {'backup_enabled': false};
    provider.dirtyMarkEnabled = true;

    await provider.resetForAccountChange();

    expect(provider.isSyncSuspended, isTrue);
    expect(provider.syncUnavailableStatus, contains('账号切换处理中'));

    provider.resumeForActiveAccount();
    provider.markPendingLocalChange();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final prefs = await SharedPreferences.getInstance();
    expect(provider.isSyncSuspended, isFalse);
    expect(provider.syncUnavailableStatus, contains('管理员已关闭云端备份'));
    expect(provider.hasPendingChanges, isTrue);
    expect(prefs.getBool('sync_pending_local_changes'), isTrue);

    provider.dispose();
  });

  test('账号切换恢复后未登录状态不再吞本地 dirty mark', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () => ApiClient(baseUrl: 'https://duoyi.test');
    provider.dirtyMarkEnabled = true;

    await provider.resetForAccountChange();
    provider.resumeForActiveAccount();
    provider.markPendingLocalChange();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final prefs = await SharedPreferences.getInstance();
    expect(provider.isSyncSuspended, isFalse);
    expect(provider.syncUnavailableStatus, contains('未登录云同步账号'));
    expect(provider.hasPendingChanges, isTrue);
    expect(prefs.getBool('sync_pending_local_changes'), isTrue);

    provider.dispose();
  });

  test('账号切换暂停期间真实本地 dirty mark 会保留到恢复后同步', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () =>
        ApiClient(baseUrl: 'https://duoyi.test', token: 'admin-token');
    provider.serverConfigGetter = () => {'backup_enabled': true};
    provider.dirtyMarkEnabled = true;

    await provider.resetForAccountChange();
    provider.markPendingLocalChange();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final prefs = await SharedPreferences.getInstance();
    expect(provider.isSyncSuspended, isTrue);
    expect(provider.hasPendingChanges, isTrue);
    expect(prefs.getBool('sync_pending_local_changes'), isTrue);

    provider.resumeForActiveAccount();
    expect(provider.isSyncSuspended, isFalse);
    expect(provider.hasPendingChanges, isTrue);

    provider.dispose();
  });

  test('用户本地变更 pending 不会被 dirty 抑制窗口吞掉', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () =>
        ApiClient(baseUrl: 'https://duoyi.test', token: 'admin-token');
    provider.serverConfigGetter = () => {'backup_enabled': true};
    provider.dirtyMarkEnabled = true;

    await provider.suppressDirtyMarkWhile(() async {
      provider.markPendingLocalChange();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      var prefs = await SharedPreferences.getInstance();
      expect(provider.hasPendingChanges, isFalse);
      expect(prefs.getBool('sync_pending_local_changes'), isNot(isTrue));

      provider.markUserMutationPending();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      prefs = await SharedPreferences.getInstance();
      expect(provider.hasPendingChanges, isTrue);
      expect(prefs.getBool('sync_pending_local_changes'), isTrue);
    });

    provider.dispose();
  });

  test('用户本地变更 durable pending 返回时已经持久化', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () =>
        ApiClient(baseUrl: 'https://duoyi.test', token: 'admin-token');
    provider.serverConfigGetter = () => {'backup_enabled': true};
    provider.dirtyMarkEnabled = true;

    await provider.markUserMutationPendingDurably();

    final prefs = await SharedPreferences.getInstance();
    expect(provider.hasPendingChanges, isTrue);
    expect(prefs.getBool('sync_pending_local_changes'), isTrue);

    provider.dispose();
  });

  test('基线同步失败只标记同步重试不标记本地 pending', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/sync');
        return http.Response(
          json.encode({'detail': 'baseline failed'}),
          500,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () => client;
    provider.serverConfigGetter = () => {'backup_enabled': true};

    await provider.syncNow();

    final prefs = await SharedPreferences.getInstance();
    expect(provider.lastError, isNull);
    expect(provider.hasPendingChanges, isFalse);
    expect(provider.hasSyncRetryPending, isTrue);
    expect(provider.syncRetryStatus, contains('同步基线建立失败'));
    expect(prefs.getBool('sync_pending_local_changes'), isNot(isTrue));

    provider.dispose();
  });

  test('真实本地 pending 同步失败保留 pending 和 lastError', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sync_pending_local_changes': true,
    });
    var acceptUpload = false;
    var applyCallbacks = 0;
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/sync');
        if (acceptUpload) {
          final sent = json.decode(request.body) as Map<String, dynamic>;
          return http.Response(
            json.encode({
              'server_updated_at': '2026-10-08T03:00:00.000Z',
              'server_version': 7,
              'collection_hashes': {
                for (final key in sent.keys) key: 'confirmed-$key',
              },
              'todos': sent['todos'],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.Response(
          json.encode({'detail': 'local upload failed'}),
          500,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () => client;
    provider.serverConfigGetter = () => {'backup_enabled': true};
    provider.onSynced = (_) async => applyCallbacks++;
    await provider.loadFromStorage();

    await provider.syncNow();

    final prefs = await SharedPreferences.getInstance();
    expect(provider.hasPendingChanges, isTrue);
    expect(provider.lastError, isNotNull);
    expect(provider.lastError, '云同步暂不可用，请稍后重试或联系管理员');
    expect(provider.lastError, isNot(contains('local upload failed')));
    expect(provider.isSyncing, isFalse);
    expect(provider.config.lastSync.millisecondsSinceEpoch, 0);
    expect(applyCallbacks, 0);
    expect(prefs.getString('sync_server_updated_at'), isNull);
    expect(prefs.getInt('sync_server_version'), isNull);
    expect(prefs.getString('sync_collection_hashes'), isNull);
    final localNotice = provider.localSaveSyncMessage(
      localSavedText: '待办已保存到本机',
    );
    expect(localNotice, contains('待办已保存到本机'));
    expect(localNotice, contains('云同步上次失败'));
    expect(localNotice, isNot(contains('local upload failed')));
    expect(provider.hasSyncRetryPending, isFalse);
    expect(prefs.getBool('sync_pending_local_changes'), isTrue);

    acceptUpload = true;
    await provider.syncNow();
    expect(provider.lastError, isNull);
    expect(provider.hasPendingChanges, isFalse);
    expect(provider.hasSyncRetryPending, isFalse);
    expect(provider.isSyncing, isFalse);
    expect(prefs.getBool('sync_pending_local_changes'), isFalse);
    expect(provider.lastServerVersion, 7);
    expect(prefs.getInt('sync_server_version'), 7);
    expect(
      prefs.getString('sync_server_updated_at'),
      '2026-10-08T03:00:00.000Z',
    );
    expect(provider.config.lastSync.millisecondsSinceEpoch, greaterThan(0));
    expect(prefs.getString('sync_collection_hashes'), isNotNull);
    provider.dispose();
  });

  test('本地 pending 上传收到缺确认字段的 200 响应时保留重试', () async {
    final localTodos = json.encode([
      {'id': 'local-todo', 'title': '本地待办'},
    ]);
    var applyCallbacks = 0;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sync_pending_local_changes': true,
      'todos': localTodos,
    });
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/sync');
        return http.Response(
          json.encode({
            'todos': [
              {'id': 'unconfirmed-remote-todo', 'title': '不可覆盖本机'},
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () => client;
    provider.serverConfigGetter = () => {'backup_enabled': true};
    provider.onSynced = (_) async => applyCallbacks++;
    await provider.loadFromStorage();

    await provider.syncNow();

    final prefs = await SharedPreferences.getInstance();
    expect(provider.hasPendingChanges, isTrue);
    expect(provider.lastError, '云同步暂不可用，请稍后重试或联系管理员');
    for (final diagnostic in [
      '服务器同步响应缺少确认字段',
      'server_updated_at',
      'server_version',
      'collection_hashes',
    ]) {
      expect(provider.lastError, isNot(contains(diagnostic)));
    }
    expect(provider.isSyncing, isFalse);
    expect(provider.hasSyncRetryPending, isFalse);
    expect(provider.syncRetryStatus, isNull);
    expect(provider.config.lastSync.millisecondsSinceEpoch, 0);
    expect(prefs.getString('todos'), localTodos);
    expect(prefs.getString('sync_collection_hashes'), isNull);
    expect(applyCallbacks, 0);
    final localNotice = provider.localSaveSyncMessage(
      localSavedText: '待办已保存到本机',
    );
    expect(localNotice, contains('待办已保存到本机'));
    expect(localNotice, contains('云同步上次失败'));
    expect(prefs.getBool('sync_pending_local_changes'), isTrue);
    expect(prefs.getString('sync_server_updated_at'), isNull);
    expect(prefs.getInt('sync_server_version'), isNull);

    provider.dispose();
  });

  test('账号清理前 pending 本地改动未上传时阻止继续清理', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sync_pending_local_changes': true,
    });
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () => ApiClient(baseUrl: 'https://duoyi.test');

    final flushed = await provider.flushPendingLocalChangesBeforeAccountChange(
      timeout: const Duration(milliseconds: 20),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(flushed, isFalse);
    expect(provider.hasPendingChanges, isTrue);
    expect(prefs.getBool('sync_pending_local_changes'), isTrue);
    expect(provider.lastError, contains('未上传服务器'));

    provider.dispose();
  });

  test('显式 syncNow 忙时会等待排队同步真正完成', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'todos': json.encode([
        {'id': 'local-todo', 'title': '本地待办'},
      ]),
    });
    final firstRequestStarted = Completer<void>();
    final firstResponse = Completer<http.Response>();
    final secondRequestStarted = Completer<void>();
    final secondResponse = Completer<http.Response>();
    var syncRequestCount = 0;
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/sync') {
          syncRequestCount++;
          if (syncRequestCount == 1) {
            if (!firstRequestStarted.isCompleted) {
              firstRequestStarted.complete();
            }
            return firstResponse.future;
          }
          if (syncRequestCount == 2) {
            if (!secondRequestStarted.isCompleted) {
              secondRequestStarted.complete();
            }
            return secondResponse.future;
          }
        }
        return http.Response('{}', 200);
      }),
    );
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () => client;
    provider.serverConfigGetter = () => {'backup_enabled': true};

    final first = provider.syncNow();
    await firstRequestStarted.future.timeout(const Duration(seconds: 1));

    var secondCompleted = false;
    final second = provider.syncNow().then((_) {
      secondCompleted = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(secondCompleted, isFalse);
    expect(syncRequestCount, 1);

    firstResponse.complete(_syncResponse(version: 1));
    await secondRequestStarted.future.timeout(const Duration(seconds: 1));
    expect(secondCompleted, isFalse);
    expect(syncRequestCount, 2);

    secondResponse.complete(_syncResponse(version: 2));
    await first.timeout(const Duration(seconds: 1));
    await second.timeout(const Duration(seconds: 1));
    expect(secondCompleted, isTrue);

    provider.dispose();
  });

  test('本地改动会后台自动同步，不需要手动入口', () {
    final source = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();
    final todoProviderSource = File(
      'lib/providers/todo_provider.dart',
    ).readAsStringSync();
    final mutationProviderSources = <String, String>{
      'habitProvider': File(
        'lib/providers/habit_provider.dart',
      ).readAsStringSync(),
      'anniversaryProvider': File(
        'lib/providers/anniversary_provider.dart',
      ).readAsStringSync(),
      'countdownProvider': File(
        'lib/providers/countdown_provider.dart',
      ).readAsStringSync(),
      'goalProvider': File(
        'lib/providers/goal_provider.dart',
      ).readAsStringSync(),
      'noteProvider': File(
        'lib/providers/note_provider.dart',
      ).readAsStringSync(),
      'diaryProvider': File(
        'lib/providers/diary_provider.dart',
      ).readAsStringSync(),
      'courseProvider': File(
        'lib/providers/course_provider.dart',
      ).readAsStringSync(),
      'timeAuditProvider': File(
        'lib/providers/time_audit_provider.dart',
      ).readAsStringSync(),
    };

    expect(source, contains('static const _autoSyncDelay'));
    expect(
      source,
      contains('static const _autoSyncDelay = Duration(seconds: 20);'),
      reason: '登录后本地回放、提醒重放和 Mine 首屏需要先让出主线程，云同步不能 1 秒级抢占。',
    );
    expect(source, contains('_scheduleAutoSync(_autoSyncDelay);'));
    expect(source, contains('Timer? _autoSyncTimer'));
    expect(source, contains('void markPendingLocalChange()'));
    expect(source, contains('if (_suppressDirtyMark) return;'));
    expect(source, contains('void markUserMutationPending()'));
    expect(source, contains('Future<void> markUserMutationPendingDurably()'));
    expect(source, contains('_hasPendingChanges = true'));
    expect(source, contains('if (!_syncSuspendedForAccountChange)'));
    expect(source, contains('_scheduleAutoSync();'));
    expect(
      source,
      contains('if ((_hasPendingChanges || _syncRetryPending) &&'),
    );
    expect(source, contains('_syncNowInternal();'));
    expect(source, contains('_autoSyncTimer?.cancel();'));
    expect(source, contains("'user_profile': 'user_profile'"));
    expect(
      mainSource,
      contains(
        'userProvider.addListener(markUserProfileDirtyOnEditableChange);',
      ),
    );
    expect(
      mainSource,
      contains(
        'locationReminderProvider.onLocalMutationPersisted =\n      cloudSyncProvider.markUserMutationPending;',
      ),
    );
    expect(
      mainSource,
      contains(
        'userProvider.onLocalMutationPersisted =\n      cloudSyncProvider.markUserMutationPending;',
      ),
    );
    expect(
      mainSource,
      contains(
        'todoProvider.onLocalMutationPersisted =\n      cloudSyncProvider.markUserMutationPendingDurably;',
      ),
    );
    expect(
      todoProviderSource,
      contains('FutureOr<void> Function()? onLocalMutationPersisted'),
    );
    expect(
      todoProviderSource,
      contains('Future<void> _notifyLocalMutationPersisted()'),
    );
    expect(
      todoProviderSource.indexOf("await prefs.setString('todos', data);"),
      lessThan(
        todoProviderSource.indexOf('await _notifyLocalMutationPersisted();'),
      ),
      reason: '待办用户变更必须在本地落盘成功后再标记云同步 pending。',
    );
    for (final entry in mutationProviderSources.entries) {
      final providerVariable = entry.key;
      final providerSource = entry.value;
      expect(
        mainSource,
        contains(
          '$providerVariable.onLocalMutationPersisted =\n      cloudSyncProvider.markUserMutationPending;',
        ),
        reason: '$providerVariable 用户写入不能再依赖会被 suppression 吞掉的普通 listener。',
      );
      expect(
        providerSource,
        contains('VoidCallback? onLocalMutationPersisted'),
        reason: '$providerVariable 需要显式落盘回调。',
      );
      expect(
        providerSource,
        contains('void _notifyLocalMutationPersisted()'),
        reason: '$providerVariable 需要安全调用落盘回调。',
      );
      expect(
        providerSource.indexOf('_notifyLocalMutationPersisted();'),
        greaterThan(providerSource.indexOf('await prefs.set')),
        reason: '$providerVariable 必须在 SharedPreferences 写入成功后再标记待上传。',
      );
    }
    final quickCaptureTemplateProviderSource = File(
      'lib/providers/quick_capture_template_provider.dart',
    ).readAsStringSync();
    expect(
      mainSource,
      contains(
        'quickCaptureTemplateProvider.onLocalMutationPersisted =\n      cloudSyncProvider.markUserQuickCaptureTemplatesChanged;',
      ),
      reason: '快速模板保存成功后也必须绕过 dirty suppression 标记待上传。',
    );
    expect(
      quickCaptureTemplateProviderSource,
      contains('VoidCallback? onLocalMutationPersisted'),
    );
    expect(
      quickCaptureTemplateProviderSource,
      contains('void _notifyLocalMutationPersisted()'),
    );
    expect(
      quickCaptureTemplateProviderSource.indexOf(
        '_notifyLocalMutationPersisted();',
      ),
      greaterThan(
        quickCaptureTemplateProviderSource.indexOf('await prefs.set'),
      ),
    );
    expect(
      mainSource,
      contains(
        'calendarProvider.onLocalEventsChanged =\n      cloudSyncProvider.markUserMutationPending;',
      ),
      reason: '日历本地事件保存后已有回调，应使用不受 suppression 影响的用户 mutation pending。',
    );
    expect(mainSource, contains('ReminderRingtoneSettings.onChanged = (keys)'));
    expect(
      mainSource,
      contains('cloudSyncProvider.markUserPreferencesChanged(keys);'),
    );
    expect(
      mainSource,
      contains(
        'preferencesProvider.onChangedKeys =\n      cloudSyncProvider.markUserPreferencesChanged;',
      ),
    );
    expect(
      mainSource,
      contains(
        'focusRoomProvider.onLocalChanged = cloudSyncProvider.markUserMutationPending;',
      ),
    );
    expect(
      mainSource,
      isNot(
        contains(
          'preferencesProvider.addListener(cloudSyncProvider.markPreferencesChanged);',
        ),
      ),
    );
    expect(
      mainSource,
      isNot(
        contains(
          'preferencesProvider.onChangedKeys = cloudSyncProvider.markPreferencesChanged;',
        ),
      ),
    );
  });

  test('云同步错误镜像不会反向标记本地待提交改动', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final todoProviderSource = File(
      'lib/providers/todo_provider.dart',
    ).readAsStringSync();

    expect(mainSource, contains('var mirroringCloudSyncError = false;'));
    expect(mainSource, contains('if (mirroringCloudSyncError) return;'));
    expect(
      mainSource,
      contains('TodoCloudSyncNotice? buildTodoCloudSyncNotice()'),
    );
    expect(mainSource, contains('cloudSyncProvider.syncRetryStatus'));
    expect(mainSource, contains('cloudSyncProvider.syncUnavailableStatus'));
    final noticeStart = mainSource.indexOf(
      'WidgetActionMessage _quickTodoCreatedNotice(TodoItem todo)',
    );
    final noticeEnd = mainSource.indexOf(
      '\nFuture<bool> _syncNotificationQuickAdd',
      noticeStart,
    );
    expect(noticeStart, greaterThanOrEqualTo(0));
    expect(noticeEnd, greaterThan(noticeStart));
    final quickTodoNotice = mainSource.substring(noticeStart, noticeEnd);
    expect(quickTodoNotice, contains('WidgetActionSyncStatus.fromFacts('));
    expect(quickTodoNotice, contains('syncState = status.state;'));
    expect(quickTodoNotice, contains('syncNotice = status.notice;'));
    expect(
      quickTodoNotice,
      contains("syncReason = status.notice == null ? status.reason : '';"),
    );
    expect(quickTodoNotice, contains('syncState: syncState'));
    expect(quickTodoNotice, contains('syncReason: syncReason'));
    expect(mainSource, contains('cloudSyncProvider.queuedRemotePullStatus'));
    expect(mainSource, contains('cloudSyncProvider.hasPendingChanges'));
    expect(mainSource, contains('!cloudSyncProvider.config.autoSync'));
    expect(mainSource, contains('CloudSyncNoticeKind.automaticSyncOff'));
    expect(mainSource, contains('mirroringCloudSyncError = true;'));
    expect(
      mainSource,
      contains('todoProvider.cloudSyncNotice = buildTodoCloudSyncNotice();'),
    );
    expect(mainSource, contains('mirroringCloudSyncError = false;'));
    expect(
      todoProviderSource,
      contains('if (_cloudSyncNotice == value) return;'),
    );
    expect(
      todoProviderSource,
      contains('enum TodoCloudSyncNoticeLevel { info, warning, error }'),
    );
  });

  test('待办保存成功不展示旧云同步错误为本次提交异常', () {
    final todoScreen = File('lib/screens/todo_screen.dart').readAsStringSync();
    final todoDetail = File(
      'lib/screens/todo_detail_screen.dart',
    ).readAsStringSync();

    expect(todoScreen, isNot(contains('云端同步上次未成功')));
    expect(todoDetail, isNot(contains('云端同步上次未成功')));
    expect(todoScreen, isNot(contains('lastCloudSyncError != null')));
    expect(todoDetail, isNot(contains('provider.lastCloudSyncError')));
  });

  test('离线本地改动的待同步状态会持久化并在失败后保留重试', () {
    final source = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(source, contains("static const _pendingLocalChangesStorageKey"));
    expect(source, contains("'sync_pending_local_changes'"));
    expect(source, contains('prefs.getBool(_pendingLocalChangesStorageKey)'));
    expect(source, contains('await _persistPendingChanges(true);'));
    expect(source, contains('_markPendingLocalChangeInBackground()'));
    expect(source, contains('Future<void> _setPendingChanges('));
    expect(source, contains('() => _setPendingChanges('));
    expect(
      source,
      contains('var shouldRetryLocalChanges = _hasPendingChanges'),
    );
    expect(source, contains('bool _syncRetryPending = false;'));
    expect(source, contains('String? get syncRetryStatus'));
    expect(source, contains('String? get syncUnavailableStatus'));
    expect(source, contains('changedCollections == null'));
    expect(
      source,
      contains('(changedCollections != null && changedCollections.isNotEmpty)'),
    );
    expect(
      source,
      isNot(
        contains(
          'shouldRetryLocalChanges ||\n'
          '          changedCollections == null ||\n'
          '          changedCollections.isNotEmpty',
        ),
      ),
    );
    expect(source, contains('await _writePendingChanges(localPrefs, true);'));
    expect(source, contains('_setSyncRetryPending('));
    expect(source, contains('CloudSyncNoticeKind.baselineRetry'));
    expect(
      File('lib/services/cloud_sync_notice.dart').readAsStringSync(),
      contains('同步基线建立失败'),
    );
    expect(source, contains('_scheduleAutoSync(_autoRetryDelay);'));
    expect(source, contains('Completer<void>? _queuedSyncCompleter'));
    expect(source, contains('Future<void> _queueSyncWhileBusy('));
    expect(source, contains('return _syncNowInternal(explicitRequest: true);'));
    expect(source, contains('_queueSyncWhileBusy(explicit: explicitRequest)'));
  });

  test('登录后启用远端轮询拉取，登出或关闭自动同步会停止轮询', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(providerSource, contains('static const _remotePollDelay'));
    expect(providerSource, contains('Timer? _remotePollTimer'));
    expect(
      providerSource,
      contains('StreamSubscription<String>? _remoteEventSubscription'),
    );
    expect(providerSource, contains('void startRemotePolling()'));
    expect(providerSource, contains('void stopRemotePolling()'));
    expect(providerSource, contains('void _startRemoteEvents()'));
    expect(providerSource, contains('void _scheduleRemoteEventReconnect('));
    expect(providerSource, contains('void _scheduleRemotePoll'));
    expect(providerSource, contains('Future<void> _pollRemoteChanges()'));
    expect(providerSource, contains("client.get('/api/sync/status')"));
    expect(providerSource, contains(".streamLines('/api/sync/events')"));
    expect(providerSource, contains("'server_version'"));
    expect(providerSource, contains('_lastServerVersion'));
    expect(providerSource, contains('serverVersion <= _lastServerVersion!'));
    expect(
      providerSource,
      contains('await _pullRemoteChanges(\n        expectedAccountGeneration:'),
    );
    expect(providerSource, contains('_hasPendingChanges || _isSyncing'));
    expect(providerSource, contains('bool _remotePullQueued = false;'));
    expect(providerSource, contains('void _queueRemotePull()'));
    expect(providerSource, contains('void _drainQueuedRemotePullIfReady'));
    expect(
      providerSource,
      contains(
        'if (_hasPendingChanges || _isSyncing) {\n'
        '      _queueRemotePull();\n'
        '      _scheduleRemotePoll();',
      ),
      reason: '远端轮询碰到本地同步忙时要排队立即补拉，不能只等下一轮 2 分钟轮询。',
    );
    expect(
      providerSource,
      contains(
        '} else if (_remotePullQueued) {\n'
        '          _drainQueuedRemotePullIfReady(',
      ),
      reason: '本地无变化同步结束后也要消化已排队远端事件。',
    );
    expect(providerSource, contains('_scheduleRemotePoll();'));
    expect(mainSource, contains('Future<void> startCloudSyncAfterAuth'));
    expect(mainSource, contains('Duration cloudSyncDelayAfterAuth({'));
    expect(mainSource, contains('if (cloudSyncProvider.hasPendingChanges)'));
    expect(mainSource, contains('return const Duration(milliseconds: 900);'));
    expect(
      mainSource,
      contains('delay: cloudSyncDelayAfterAuth(initialStartup: false)'),
    );
    expect(
      mainSource,
      contains('delay: cloudSyncDelayAfterAuth(initialStartup: true)'),
    );
    expect(mainSource, contains("'server config before cloud sync'"));
    expect(mainSource, contains(r"'cloud sync $reason'"));
    expect(mainSource, contains('cloudSyncProvider.startRemotePolling();'));
    expect(mainSource, contains('cloudSyncProvider.stopRemotePolling();'));
    expect(mainSource, contains("label: 'cloud sync post reload'"));
  });

  test('同步回写不会用旧主题或旧时光币对象覆盖本地新状态', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(providerSource, contains('bool _remoteObjectIsOlderThanLocal'));
    expect(providerSource, contains("localKey != 'theme_shop_state'"));
    expect(providerSource, contains("localKey != 'duoyi_virtual_rewards'"));
    expect(
      providerSource,
      contains('_timestampGt(localUpdatedAt, remoteUpdatedAt)'),
    );
    expect(
      providerSource,
      contains('if (localUpdatedAt.isNotEmpty && remoteUpdatedAt.isEmpty)'),
    );
    expect(providerSource, contains(r'skipped stale object $remoteKey'));
  });

  test('同步事件流收到新版本后即时拉取，轮询仍作为兜底', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final backendSource = File('backend/main.py').readAsStringSync();

    for (final field in [
      'StreamSubscription<String>? _remoteEventSubscription',
      "Timer? _remoteEventRetryTimer",
      'CloudSyncNotice? _lastRealtimeWarning',
      'String? get lastRealtimeWarning',
      'String? get queuedRemotePullStatus',
      'CloudSyncNoticeKind.queuedWaitingLocalChanges',
      ".streamLines('/api/sync/events')",
      'void _handleRemoteEventLine(String line)',
      'void _dispatchRemoteEvent()',
      'void _scheduleRemoteEventReconnect(',
      "line.startsWith('event:')",
      "line.startsWith('data:')",
      "final eventName = _remoteEventName.isEmpty ? 'message' : _remoteEventName",
      "if (eventName != 'sync' || rawData.isEmpty) return;",
      "json.decode(rawData)",
      "decoded['server_version']",
      "decoded['server_updated_at']",
      'if (versionUnchanged || timestampUnchanged) return;',
      'if (_hasPendingChanges || _isSyncing) {\n        _queueRemotePull();',
      '_drainQueuedRemotePullIfReady(',
      'cancelOnError: true',
      '_scheduleRemoteEventReconnect(_autoRetryDelay)',
      '_scheduleRemotePoll(_autoRetryDelay)',
      '_remoteEventRetryTimer?.cancel();',
      '_remoteEventSubscription?.cancel();',
    ]) {
      expect(providerSource, contains(field));
    }
    final eventsStart = providerSource.indexOf('void _startRemoteEvents()');
    final eventsOnError = providerSource.indexOf(
      'onError: (Object error)',
      eventsStart,
    );
    final eventsOnDone = providerSource.indexOf('onDone: ()', eventsOnError);
    expect(eventsStart, greaterThanOrEqualTo(0));
    expect(eventsOnError, greaterThan(eventsStart));
    expect(eventsOnDone, greaterThan(eventsOnError));
    final eventsErrorBody = providerSource.substring(
      eventsOnError,
      eventsOnDone,
    );
    expect(eventsErrorBody, contains('_lastRealtimeWarning ='));
    expect(eventsErrorBody, isNot(contains('_lastError =')));

    for (final field in [
      '@app.get("/api/sync/events")',
      'async def sync_events',
      'interval_seconds: int = Query(15, ge=2, le=60)',
      '"event: sync\\n"',
      'json.dumps(payload, ensure_ascii=False)',
      'media_type="text/event-stream"',
      '"Cache-Control": "no-cache"',
      '"X-Accel-Buffering": "no"',
    ]) {
      expect(backendSource, contains(field));
    }
  });

  test('远端轮询使用轻量版本探针，未变化时跳过全量同步', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final backendSource = File('backend/main.py').readAsStringSync();

    expect(providerSource, contains("static const _serverVersionStorageKey"));
    expect(providerSource, contains("'sync_server_version'"));
    expect(providerSource, contains("static const _serverUpdatedAtStorageKey"));
    expect(providerSource, contains("'sync_server_updated_at'"));
    expect(providerSource, contains('int? get lastServerVersion'));
    expect(providerSource, contains('String get lastServerUpdatedAt'));
    expect(providerSource, contains('_persistServerRevision(prefs, response)'));
    expect(providerSource, contains("response['server_updated_at']"));
    expect(providerSource, contains("response['server_version']"));
    expect(providerSource, contains('prefs.setInt(_serverVersionStorageKey'));
    expect(
      providerSource,
      contains('prefs.setString(_serverUpdatedAtStorageKey'),
    );
    expect(providerSource, contains('versionUnchanged || timestampUnchanged'));

    expect(backendSource, contains('sync_version INTEGER DEFAULT 0'));
    expect(backendSource, contains('("sync_data", "sync_version", "0")'));
    expect(backendSource, contains('@app.get("/api/sync/status")'));
    expect(backendSource, contains('def sync_status'));
    expect(backendSource, contains('"server_version"'));
    expect(backendSource, contains('next_sync_version'));
  });

  test('远端变化拉取使用集合 hash 增量接口，避免无本地改动时整包同步', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final backendSource = File('backend/main.py').readAsStringSync();

    expect(
      providerSource,
      contains(
        'Future<void> _pullRemoteChanges({int? expectedAccountGeneration})',
      ),
    );
    expect(providerSource, contains("client.post('/api/sync/pull'"));
    expect(providerSource, contains("'collection_hashes'"));
    expect(providerSource, contains('_collectionHashForKey('));
    expect(providerSource, contains('_itemHashBucketForKey('));
    expect(providerSource, contains('static const _syncPullCollections'));
    expect(providerSource, contains('sha256'));
    expect(providerSource, contains('.convert(utf8.encode'));
    expect(providerSource, contains('SplayTreeMap<String, Object?>'));
    expect(providerSource, contains('await _applySyncResponse('));
    expect(
      providerSource,
      contains('await _pullRemoteChanges(\n        expectedAccountGeneration:'),
    );

    final pollBody = providerSource.substring(
      providerSource.indexOf('Future<void> _pollRemoteChanges()'),
      providerSource.indexOf('static const _stringEncodedListKeys'),
    );
    expect(pollBody, isNot(contains('await syncNow();')));

    expect(backendSource, contains('class SyncPullRequest'));
    expect(backendSource, contains('@app.post("/api/sync/pull")'));
    expect(backendSource, contains('def sync_pull'));
    expect(backendSource, contains('SYNC_PULL_COLLECTIONS'));
    expect(backendSource, contains('def _sync_collection_hashes'));
    expect(backendSource, contains('def _payload_hash'));
    expect(
      backendSource,
      contains('collection_hashes = _sync_collection_hashes'),
    );
    expect(backendSource, contains('changed_payload = {'));
    expect(
      backendSource,
      contains(
        'if str(client_hashes.get(key) or "") != collection_hashes[key]',
      ),
    );
  });

  test('本地改动上传使用集合 hash delta，避免每次整包上传', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final backendSource = File('backend/main.py').readAsStringSync();

    expect(
      providerSource,
      contains("static const _collectionHashesStorageKey"),
    );
    expect(providerSource, contains("'sync_collection_hashes'"));
    expect(providerSource, contains('_lastCollectionHashes'));
    expect(providerSource, contains('_decodeCollectionHashes('));
    expect(providerSource, contains('_changedSyncCollections('));
    expect(providerSource, contains("client.post('/api/sync/delta'"));
    expect(providerSource, contains("'collections': changedCollections"));
    expect(providerSource, contains("response['collection_hashes']"));
    expect(providerSource, contains('_collectionHashesStorageKey'));

    final syncBody = providerSource.substring(
      providerSource.indexOf('Future<void> _syncNowInternal'),
      providerSource.indexOf(
        'Future<void> _pullRemoteChanges({int? expectedAccountGeneration})',
      ),
    );
    expect(syncBody, contains("client.post('/api/sync', payload)"));
    expect(syncBody, contains("client.post('/api/sync/delta'"));
    expect(syncBody, contains('changedCollections == null'));
    expect(syncBody, contains('changedCollections.isEmpty'));
    expect(syncBody, contains('_validateLocalUploadAcknowledgement('));
    expect(providerSource, contains('服务器同步响应缺少确认字段'));

    expect(backendSource, contains('class SyncDeltaRequest'));
    expect(backendSource, contains('@app.post("/api/sync/delta")'));
    expect(backendSource, contains('def sync_delta'));
    expect(backendSource, contains('SyncRequest(**payload)'));
    expect(backendSource, contains('model_dump_payload=req.model_dump()'));
  });

  test('有条目 hash 基线时优先按条目 delta 上传', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final backendSource = File('backend/main.py').readAsStringSync();

    expect(providerSource, contains("static const _itemHashesStorageKey"));
    expect(providerSource, contains("'sync_item_hashes'"));
    expect(providerSource, contains('_lastItemHashes'));
    expect(
      providerSource,
      contains('_itemHashBucketForKey('),
      reason: '条目哈希按集合计算并缓存，原始存储不变的集合复用结果，避免重复全量哈希。',
    );
    expect(providerSource, contains('_buildSyncItemDelta('));
    expect(providerSource, contains("client.post('/api/sync/item-delta'"));
    expect(providerSource, contains("'items': items"));
    expect(providerSource, contains("'objects': objects"));
    expect(providerSource, contains("'deleted_items': deletedItems"));
    expect(providerSource, contains('_decodeItemHashes('));
    expect(providerSource, contains('_itemDeltaCollections'));
    expect(providerSource, contains('_objectDeltaCollections'));
    expect(providerSource, contains("'location_reminders'"));
    expect(providerSource, contains("_itemHashesStorageKey"));

    final syncBody = providerSource.substring(
      providerSource.indexOf('Future<void> _syncNowInternal'),
      providerSource.indexOf(
        'Future<void> _pullRemoteChanges({int? expectedAccountGeneration})',
      ),
    );
    expect(syncBody, contains("client.post('/api/sync/item-delta'"));
    expect(syncBody, contains("client.post('/api/sync/delta'"));
    expect(
      syncBody.indexOf("client.post('/api/sync/item-delta'"),
      lessThan(syncBody.indexOf("client.post('/api/sync/delta'")),
    );

    expect(backendSource, contains('class SyncItemDeltaRequest'));
    expect(backendSource, contains('@app.post("/api/sync/item-delta")'));
    expect(backendSource, contains('def sync_item_delta'));
    expect(backendSource, contains('def _apply_item_delta_to_payload'));
    expect(backendSource, contains('SYNC_OBJECT_COLLECTIONS'));
    expect(backendSource, contains('SYNC_STATE_OBJECT_COLLECTIONS'));
    expect(backendSource, contains('_merge_by_timestamp('));
    expect(backendSource, contains('_merge_deleted_items('));
    expect(backendSource, contains('_prune_deleted_items('));
  });

  test('倒数日集合参与云同步 pull、delta 和删除墓碑', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final countdownSource = File(
      'lib/providers/countdown_provider.dart',
    ).readAsStringSync();

    final listPayloadsBody = providerSource.substring(
      providerSource.indexOf('static const _listPayloads'),
      providerSource.indexOf('static const _objectPayloads'),
    );
    expect(listPayloadsBody, contains("'duoyi_countdowns': 'countdowns'"));

    final pullCollectionsBody = providerSource.substring(
      providerSource.indexOf('static const _syncPullCollections'),
      providerSource.indexOf('static const _itemDeltaCollections'),
    );
    expect(pullCollectionsBody, contains("'countdowns'"));

    final itemDeltaCollectionsBody = providerSource.substring(
      providerSource.indexOf('static const _itemDeltaCollections'),
      providerSource.indexOf('static const _objectDeltaCollections'),
    );
    expect(itemDeltaCollectionsBody, contains("'countdowns'"));
    expect(
      countdownSource,
      contains("CloudSyncProvider.recordDeletedItem('countdowns'"),
    );
  });

  test('旧周年表 type=0 记录不会被 Flutter 同步过滤删除', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(providerSource, isNot(contains('_filterLocalSyncList')));
    expect(providerSource, isNot(contains("type.trim() != '0'")));
    expect(providerSource, isNot(contains('type.toInt() != 0')));
  });

  test('云端回写后会刷新本地个人资料且不触发二次脏标记', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(providerSource, contains("'user_profile': 'user_profile'"));
    expect(
      mainSource,
      contains('cloudSyncProvider.onSynced = (changedCollections)'),
    );
    expect(
      mainSource,
      contains('cloudSyncProvider.suppressDirtyMarkWhile(() async {'),
    );
    expect(
      mainSource,
      contains('reloadTasks.add(userProvider.loadFromStorage)'),
    );
    expect(mainSource, contains('_runSyncReloadTasksInBatches('));
    expect(mainSource, contains('continueOnError: true'));
    expect(mainSource, contains("label: 'cloud sync reload'"));
    expect(
      mainSource,
      contains(
        'userProvider.addListener(markUserProfileDirtyOnEditableChange);',
      ),
    );
  });

  test('同步回调携带实际变更集合，main 只刷新命中的 provider', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(providerSource, contains('typedef SyncChangedCollectionsCallback'));
    expect(
      providerSource,
      contains('Future<void> Function(Set<String> changedCollections)'),
    );
    expect(providerSource, contains('class _SyncApplyResult'));
    expect(
      providerSource,
      contains('Future<_SyncApplyResult> _applySyncResponse'),
    );
    expect(providerSource, contains('final skippedCollections = <String>{};'));
    expect(
      providerSource,
      contains(
        'var localChangedBeforeApply =\n'
        '        _localChangeGeneration != localChangeGenerationAtStart;',
      ),
      reason: '应用前的本地改动判定改用变更生成数，避免每轮同步在主线程全量重建负载比对哈希。',
    );
    expect(providerSource, contains('skippedCollections.add(remoteKey);'));
    expect(
      providerSource,
      contains('if (!localChangedBeforeApply && skippedCollections.isEmpty)'),
    );
    expect(providerSource, contains('final nextHashes ='));
    expect(
      providerSource,
      contains('if (applyResult.changedCollections.isNotEmpty)'),
    );
    expect(
      providerSource,
      contains('await onSynced?.call(applyResult.changedCollections);'),
    );

    expect(
      mainSource,
      contains('cloudSyncProvider.onSynced = (changedCollections)'),
    );
    expect(mainSource, contains("changedCollections.contains('todos')"));
    expect(
      mainSource,
      contains(
        'reloadTasks.add(() => todoProvider.loadFromStorage(force: true))',
      ),
    );
    expect(
      mainSource,
      contains('todoProvider.loadFromStorage(force: true)'),
      reason: '云同步回写后 TodoProvider 必须强制重读，避免内存旧快照覆盖同步结果。',
    );
    expect(mainSource, contains("changedCollections.contains('habits')"));
    expect(
      mainSource,
      contains('reloadTasks.add(habitProvider.loadFromStorage)'),
    );
    expect(
      mainSource,
      contains("changedCollections.contains('pomodoro_sessions')"),
    );
    expect(
      mainSource,
      contains('reloadTasks.add(pomodoroProvider.loadFromStorage)'),
    );
    expect(mainSource, contains("changedCollections.contains('user_profile')"));
    expect(
      mainSource,
      contains(
        "await authProvider.refreshMe(reason: 'cloud_sync_account_snapshot')",
      ),
    );
    expect(
      mainSource,
      contains('final postReloadTasks = <Future<void> Function()>[];'),
    );
    expect(mainSource, contains("label: 'cloud sync post reload'"));
    expect(
      mainSource,
      contains("changedCollections.contains('virtual_rewards')"),
    );
    expect(mainSource, isNot(contains("reason: 'cloud_sync_virtual_rewards'")));
    expect(
      mainSource,
      contains("changedCollections.contains('location_reminders')"),
    );
    expect(
      mainSource,
      contains('reloadTasks.add(locationReminderProvider.loadFromStorage)'),
    );
    expect(
      mainSource,
      contains('locationReminderProvider.addListener(syncLocationGeofences);'),
    );
    expect(
      mainSource,
      contains(
        'await ReminderRingtoneSettings.applyPersistedSettingsToNative();',
      ),
    );
    expect(
      mainSource,
      contains("changedCollections.contains('workspace_payloads')"),
    );
    expect(mainSource, contains('shareProvider.load(force: true)'));
    expect(mainSource, contains('queueShareLoadAfterAuth'));
    expect(
      mainSource,
      contains('queueShareLoadAfterAuth(delay: const Duration(seconds: 8))'),
    );

    final onSyncedBody = mainSource.substring(
      mainSource.indexOf('cloudSyncProvider.onSynced = (changedCollections)'),
      mainSource.indexOf(
        'authProvider.addListener(() {',
        mainSource.indexOf('cloudSyncProvider.onSynced = (changedCollections)'),
      ),
    );
    expect(
      onSyncedBody,
      isNot(contains('await todoProvider.loadFromStorage();')),
    );
    expect(
      onSyncedBody,
      contains(
        'await _runSyncReloadTasksInBatches(\n        reloadTasks,\n        continueOnError: true,',
      ),
    );
    expect(onSyncedBody, contains("label: 'cloud sync reload'"));
  });

  test('同步回写内容相同时跳过 SharedPreferences 写入，降低无效 IO', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(providerSource, contains('Future<bool> _writeLocalList('));
    expect(providerSource, contains('Map<String, dynamic> _readLocalObject('));
    expect(providerSource, contains('Future<void> _writeLocalObject('));
    expect(
      providerSource,
      contains('_syncPayloadHash(_readLocalList(prefs, localKey))'),
    );
    expect(
      providerSource,
      contains('_syncPayloadHash(_readLocalObject(prefs, localKey))'),
    );
    expect(
      providerSource,
      contains('if (!await _writeLocalList(prefs, localKey, writeValue))'),
    );
    expect(
      providerSource,
      contains('await _writeLocalObject(prefs, localKey, value);'),
    );

    final applyBody = providerSource.substring(
      providerSource.indexOf('Future<_SyncApplyResult> _applySyncResponse'),
      providerSource.indexOf('Future<void> _persistServerRevision'),
    );
    expect(applyBody, isNot(contains('await prefs.setString(localKey')));
    expect(
      applyBody,
      isNot(contains('await prefs.setStringList(\n          localKey')),
    );
  });

  test('个人资料仍可同步但统计重算不会刷新资料更新时间', () {
    final modelSource = File('lib/models/user_profile.dart').readAsStringSync();
    final providerSource = File(
      'lib/providers/user_provider.dart',
    ).readAsStringSync();
    final backendSource = File('backend/main.py').readAsStringSync();
    final recalcBody = providerSource.substring(
      providerSource.indexOf('void recalc({'),
      providerSource.indexOf('void _notifyListenersSafely()'),
    );

    expect(modelSource, contains('DateTime? updatedAt;'));
    expect(modelSource, contains("'updatedAt': updatedAt?.toIso8601String()"));
    expect(recalcBody, isNot(contains('updatedAt')));
    expect(
      providerSource,
      contains('if (touchUpdatedAt || _profile.updatedAt == null)'),
    );
    expect(
      backendSource,
      contains('def _merge_dict(server: dict, client: dict)'),
    );
    expect(backendSource, contains('def _item_updated_at(item: dict)'));
    expect(
      backendSource,
      contains(
        'for key in ("updatedAt", "updated_at", "modifiedAt", "endTime", "createdAt")',
      ),
    );
    expect(backendSource, contains('client_ts = _item_updated_at(client)'));
    expect(backendSource, contains('def _timestamp_gt(left: str, right: str)'));
    expect(backendSource, contains('_timestamp_gt(client_ts, server_ts)'));
  });

  test('屏幕和组件层不暴露手动云同步入口', () {
    final uiFiles = <File>[
      ...Directory('lib/screens')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      ...Directory('lib/widgets')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
    ];

    final offenders = <String>[];
    for (final file in uiFiles) {
      final text = file.readAsStringSync();
      if (text.contains('syncNow()') || text.contains('.syncNow(')) {
        offenders.add(file.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '云同步应由 main.dart/provider 后台排队触发，UI 层不能重新出现立即同步按钮。',
    );
  });

  test('共享空间合并保留可解释的冲突决策记录', () {
    final source = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(source, contains('class SyncMergeDecision'));
    expect(source, contains('lastWorkspaceMergeDecisions'));
    expect(source, contains('sync_merge_decisions'));
    expect(source, contains('final List<String> changedFields'));
    expect(source, contains("'changedFields': changedFields"));
    expect(source, contains('_changedWorkspaceFields(prior, item)'));
    expect(source, contains("'id', 'workspaceId', 'createdAt', 'updatedAt'"));
    expect(source, contains("winner: remoteWins ? 'remote' : 'local'"));
    expect(source, contains('final oldTs = _remoteItemUpdatedAt(prior);'));
    expect(source, contains('final newTs = _remoteItemUpdatedAt(item);'));
    expect(
      source,
      contains(
        'final remoteWins = oldTs.isEmpty || !_timestampGt(oldTs, newTs);',
      ),
    );
    expect(source, isNot(contains('newTs.compareTo(oldTs)')));
    expect(source, contains('云端更新时间不早于本地'));
    expect(source, contains('本地更新时间更新'));
  });

  test('冲突决策序列化保留字段级差异说明', () {
    final source = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(source, contains('SyncMergeDecision.fromJson'));
    expect(source, contains("json['changedFields'] as List?"));
    expect(source, contains("'changedFields': changedFields"));
    expect(source, contains("json['decidedAt']"));
    expect(source, contains('decision.toJson()'));
  });

  test('同步删除墓碑会上传并保存，避免云端旧列表复活本地删除', () {
    final source = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(
      source,
      contains("static const deletedItemsStorageKey = 'sync_deleted_items'"),
    );
    expect(source, contains('static Future<void> recordDeletedItem'));
    expect(source, contains('static Future<void> recordDeletedItems'));
    expect(source, contains("payload['deleted_items']"));
    expect(
      source,
      contains("final responseDeletedItems = response['deleted_items'];"),
    );
    expect(source, contains('var mergedDeletedItems ='));
    expect(source, contains('_filterDeletedRemoteList('));
    expect(source, contains('collection: remoteKey'));
    expect(source, contains('deletedItems: mergedDeletedItems'));
    expect(
      source,
      contains(
        'return updatedAt.isNotEmpty && _timestampGt(updatedAt, deletedAt);',
      ),
    );
    expect(source, contains('prefs.setString('));
  });

  test('共享空间删除墓碑独立持久化并随空数据桶上传', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'todos': json.encode(const <dynamic>[]),
    });
    const deletedAt = '2026-10-03T12:00:00.000Z';
    await CloudSyncProvider.recordDeletedItem(
      'todos',
      'shared-deleted',
      deletedAt: DateTime.parse(deletedAt),
      workspaceId: 'workspace-only-tombstone',
    );
    await CloudSyncProvider.recordDeletedItem(
      'todos',
      'private-deleted',
      deletedAt: DateTime.parse(deletedAt),
      workspaceId: 'private:owner',
    );

    final firstRequestBody = Completer<Map<String, dynamic>>();
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () => ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/sync') {
          firstRequestBody.complete(
            Map<String, dynamic>.from(json.decode(request.body) as Map),
          );
        }
        return http.Response(
          json.encode({
            'server_updated_at': deletedAt,
            'server_version': 1,
            'todos': const <dynamic>[],
            'deleted_items': {
              'todos': {'private-deleted': deletedAt},
            },
            'workspace_payloads': {
              'workspace-only-tombstone': {
                'todos': const <dynamic>[],
                'deleted_items': {
                  'todos': {'shared-deleted': deletedAt},
                },
              },
            },
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    provider.serverConfigGetter = () => {'backup_enabled': true};

    await provider.syncNow();
    final request = await firstRequestBody.future.timeout(
      const Duration(seconds: 1),
    );
    final workspaceBucket =
        (request['workspace_payloads'] as Map)['workspace-only-tombstone']
            as Map;
    expect(request['todos'], isEmpty);
    expect(request['deleted_items'], {
      'todos': {'private-deleted': deletedAt},
    });
    expect(workspaceBucket['todos'], isEmpty);
    expect(workspaceBucket['deleted_items'], {
      'todos': {'shared-deleted': deletedAt},
    });

    final prefs = await SharedPreferences.getInstance();
    expect(
      json.decode(
        prefs.getString(CloudSyncProvider.workspaceDeletedItemsStorageKey)!,
      ),
      {
        'workspace-only-tombstone': {
          'todos': {'shared-deleted': deletedAt},
        },
      },
    );
    provider.dispose();
  });

  test('共享删除墓碑只删对应空间副本且跨重启保留', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'todos': json.encode([
        {
          'id': 'overlap',
          'title': '私人副本',
          'workspaceId': 'private',
          'updatedAt': '2026-10-01T00:00:00.000Z',
        },
        {
          'id': 'overlap',
          'title': '空间 A 已删除副本',
          'workspaceId': 'space-a',
          'updatedAt': '2026-10-01T00:00:00.000Z',
        },
        {
          'id': 'overlap',
          'title': '空间 B 副本',
          'workspaceId': 'space-b',
          'updatedAt': '2026-10-02T00:00:00.000Z',
        },
        {
          'id': 'private-tombstone-overlap',
          'title': '空间 B 不受私人墓碑影响',
          'workspaceId': 'space-b',
          'updatedAt': '2026-10-02T00:00:00.000Z',
        },
      ]),
      'sync_deleted_items': json.encode({
        'todos': {'private-tombstone-overlap': '2026-12-01T00:00:00.000Z'},
      }),
    });
    const sharedDeletedAt = '2026-11-01T00:00:00.000Z';
    const globalDeletedAt = '2026-12-01T00:00:00.000Z';

    final requestBodies = <Map<String, dynamic>>[];
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () => ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/sync') {
          requestBodies.add(
            Map<String, dynamic>.from(json.decode(request.body) as Map),
          );
        }
        return http.Response(
          json.encode({
            'server_updated_at': '2026-10-03T12:00:00.000Z',
            'server_version': requestBodies.length,
            // Legacy servers may still echo shared rows in their personal list.
            'todos': [
              {
                'id': 'overlap',
                'title': '私人副本',
                'workspaceId': 'private',
                'updatedAt': '2026-10-01T00:00:00.000Z',
              },
              {
                'id': 'overlap',
                'title': '空间 A 已删除副本',
                'workspaceId': 'space-a',
                'updatedAt': '2026-10-01T00:00:00.000Z',
              },
              {
                'id': 'overlap',
                'title': '空间 B 副本',
                'workspaceId': 'space-b',
                'updatedAt': '2026-10-02T00:00:00.000Z',
              },
              {
                'id': 'private-tombstone-overlap',
                'title': '空间 B 不受私人墓碑影响',
                'workspaceId': 'space-b',
                'updatedAt': '2026-10-02T00:00:00.000Z',
              },
              {
                'id': 'unrecognized-workspace-item',
                'title': '未授权空间的旧顶层副本',
                'workspaceId': 'not-a-member',
                'updatedAt': '2026-10-02T00:00:00.000Z',
              },
            ],
            'deleted_items': {
              'todos': {'private-tombstone-overlap': globalDeletedAt},
            },
            'workspace_payloads': {
              'space-a': {
                'todos': [
                  {
                    'id': 'overlap',
                    'title': '空间 A 已删除副本',
                    'workspaceId': 'space-a',
                    'updatedAt': '2026-10-01T00:00:00.000Z',
                  },
                ],
                'deleted_items': {
                  'todos': {'overlap': sharedDeletedAt},
                },
              },
              'space-b': {
                'todos': [
                  {
                    'id': 'overlap',
                    'title': '空间 B 副本',
                    'workspaceId': 'space-b',
                    'updatedAt': '2026-10-02T00:00:00.000Z',
                  },
                  {
                    'id': 'private-tombstone-overlap',
                    'title': '空间 B 不受私人墓碑影响',
                    'workspaceId': 'space-b',
                    'updatedAt': '2026-10-02T00:00:00.000Z',
                  },
                ],
                'deleted_items': <String, dynamic>{},
              },
            },
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    provider.serverConfigGetter = () => {'backup_enabled': true};

    await provider.syncNow();

    final prefs = await SharedPreferences.getInstance();
    final localTodos = (json.decode(prefs.getString('todos')!) as List)
        .cast<Map>();
    expect(
      localTodos
          .where((item) => item['id'] == 'overlap')
          .map((item) => '${item['workspaceId']}:${item['title']}'),
      containsAll(['private:私人副本', 'space-b:空间 B 副本']),
    );
    expect(
      localTodos.any(
        (item) => item['workspaceId'] == 'space-a' && item['id'] == 'overlap',
      ),
      isFalse,
    );
    expect(
      localTodos.any(
        (item) =>
            item['workspaceId'] == 'space-b' &&
            item['id'] == 'private-tombstone-overlap',
      ),
      isTrue,
    );
    expect(
      localTodos.any((item) => item['id'] == 'unrecognized-workspace-item'),
      isFalse,
    );
    expect(requestBodies, isNotEmpty);
    expect(
      (requestBodies.first['todos'] as List).cast<Map>(),
      everyElement(predicate<Map>((item) => item['workspaceId'] == 'private')),
    );

    final persistedWorkspaceTombstones =
        json.decode(
              prefs.getString(
                CloudSyncProvider.workspaceDeletedItemsStorageKey,
              )!,
            )
            as Map;
    expect(persistedWorkspaceTombstones, {
      'space-a': {
        'todos': {'overlap': sharedDeletedAt},
      },
    });

    provider.dispose();
    final restartedRequest = Completer<Map<String, dynamic>>();
    final restartedProvider = CloudSyncProvider();
    restartedProvider.apiClientGetter = () => ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/sync') {
          restartedRequest.complete(
            Map<String, dynamic>.from(json.decode(request.body) as Map),
          );
        }
        return http.Response(
          json.encode({
            'server_updated_at': '2026-10-03T12:00:00.000Z',
            'server_version': 2,
            'todos': localTodos,
            'deleted_items': {
              'todos': {'private-tombstone-overlap': globalDeletedAt},
            },
            'workspace_payloads': {
              'space-a': {
                'todos': const <dynamic>[],
                'deleted_items': {
                  'todos': {'overlap': sharedDeletedAt},
                },
              },
              'space-b': {
                'todos': localTodos
                    .where((item) => item['workspaceId'] == 'space-b')
                    .toList(),
                'deleted_items': <String, dynamic>{},
              },
            },
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    restartedProvider.serverConfigGetter = () => {'backup_enabled': true};
    await restartedProvider.loadFromStorage();
    await restartedProvider.syncNow();
    final restartedBody = await restartedRequest.future.timeout(
      const Duration(seconds: 1),
    );
    expect(
      ((restartedBody['workspace_payloads'] as Map)['space-a']
          as Map)['deleted_items'],
      {
        'todos': {'overlap': sharedDeletedAt},
      },
    );
    expect(
      (restartedBody['todos'] as List).cast<Map>().any(
        (item) => item['workspaceId'] == 'space-a',
      ),
      isFalse,
    );

    restartedProvider.dispose();
  });

  test('私有待办变更与共享墓碑同批使用集合 delta', () async {
    const collectionHashKeys = <String>[
      'todos',
      'habits',
      'pomodoro_sessions',
      'focus_penalties',
      'notes',
      'countdowns',
      'anniversaries',
      'diaries',
      'goals',
      'calendar_events',
      'time_entries',
      'courses',
      'location_reminders',
      'pomodoro_config',
      'user_profile',
      'course_settings',
      'achievement_states',
      'virtual_rewards',
      'focus_rooms',
      'theme_shop_state',
      'preferences',
      'quick_capture_templates',
      'deleted_items',
      'workspace_payloads',
    ];
    const itemHashKeys = <String>[
      'todos',
      'habits',
      'pomodoro_sessions',
      'focus_penalties',
      'notes',
      'countdowns',
      'anniversaries',
      'diaries',
      'goals',
      'calendar_events',
      'time_entries',
      'courses',
      'location_reminders',
      'pomodoro_config',
      'user_profile',
      'course_settings',
      'achievement_states',
      'virtual_rewards',
      'focus_rooms',
      'theme_shop_state',
      'preferences',
      'quick_capture_templates',
    ];
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sync_auto': false,
      'todos': json.encode([
        {
          'id': 'private-todo',
          'title': '私人旧标题',
          'workspaceId': 'private',
          'updatedAt': '2026-10-02T12:00:00.000Z',
        },
        {
          'id': 'shared-todo',
          'title': '共享待删除',
          'workspaceId': 'space-a',
          'updatedAt': '2026-10-02T12:00:00.000Z',
        },
      ]),
      'sync_collection_hashes': json.encode({
        for (final key in collectionHashKeys) key: 'prior-$key',
      }),
      'sync_item_hashes': json.encode({
        for (final key in itemHashKeys)
          key: key == 'todos'
              ? <String, String>{'private-todo': 'prior-private-todo-hash'}
              : <String, String>{},
      }),
    });
    const deletedAt = '2026-10-03T12:00:00.000Z';
    await CloudSyncProvider.recordDeletedItem(
      'todos',
      'shared-todo',
      deletedAt: DateTime.parse(deletedAt),
      workspaceId: 'space-a',
    );

    final requestPaths = <String>[];
    Map<String, dynamic>? deltaRequestBody;
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () => ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        requestPaths.add(request.url.path);
        final body = Map<String, dynamic>.from(
          json.decode(request.body) as Map,
        );
        if (request.url.path != '/api/sync/delta') {
          return http.Response(
            json.encode({'detail': 'unexpected sync path'}),
            500,
            headers: const {'content-type': 'application/json'},
          );
        }
        deltaRequestBody = body;
        final collections = body['collections'] as Map;
        return http.Response(
          json.encode({
            'server_updated_at': deletedAt,
            'server_version': 2,
            'collection_hashes': {
              for (final key in collections.keys) key.toString(): 'accepted',
            },
            'workspace_payloads': collections['workspace_payloads'],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    provider.serverConfigGetter = () => {'backup_enabled': true};
    await provider.loadFromStorage();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'todos',
      json.encode([
        {
          'id': 'private-todo',
          'title': '私人新标题',
          'workspaceId': 'private',
          'updatedAt': deletedAt,
        },
        {
          'id': 'shared-todo',
          'title': '共享待删除',
          'workspaceId': 'space-a',
          'updatedAt': '2026-10-02T12:00:00.000Z',
        },
      ]),
    );

    await provider.syncNow();

    expect(requestPaths, ['/api/sync/delta']);
    final collections = deltaRequestBody!['collections'] as Map;
    expect(collections['todos'], [
      {
        'id': 'private-todo',
        'title': '私人新标题',
        'workspaceId': 'private',
        'updatedAt': deletedAt,
      },
    ]);
    final workspacePayloads = collections['workspace_payloads'] as Map;
    expect(
      ((workspacePayloads['space-a'] as Map)['deleted_items'] as Map)['todos'],
      {'shared-todo': deletedAt},
    );
    expect((workspacePayloads['space-a'] as Map)['todos'], [
      {
        'id': 'shared-todo',
        'title': '共享待删除',
        'workspaceId': 'space-a',
        'updatedAt': '2026-10-02T12:00:00.000Z',
      },
    ]);
    provider.dispose();
  });

  test('账号代次变化后旧删除墓碑不会写入新账号本地缓存', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final writeFuture = CloudSyncProvider.recordDeletedItems('todos', const [
      'old-account-todo',
    ]);
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    await writeFuture;

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(CloudSyncProvider.deletedItemsStorageKey), isNull);
  });

  test('本地模块删除都会记录同步删除墓碑', () {
    final pomodoro = File(
      'lib/providers/pomodoro_provider.dart',
    ).readAsStringSync();
    final timeAudit = File(
      'lib/providers/time_audit_provider.dart',
    ).readAsStringSync();
    final habit = File('lib/providers/habit_provider.dart').readAsStringSync();
    final todo = File('lib/providers/todo_provider.dart').readAsStringSync();
    final note = File('lib/providers/note_provider.dart').readAsStringSync();
    final countdown = File(
      'lib/providers/countdown_provider.dart',
    ).readAsStringSync();
    final calendar = File(
      'lib/providers/calendar_provider.dart',
    ).readAsStringSync();
    final locationReminders = File(
      'lib/providers/location_reminder_provider.dart',
    ).readAsStringSync();
    final quickCaptureTemplates = File(
      'lib/providers/quick_capture_template_provider.dart',
    ).readAsStringSync();
    final course = File(
      'lib/providers/course_provider.dart',
    ).readAsStringSync();
    final diary = File('lib/providers/diary_provider.dart').readAsStringSync();
    final anniversary = File(
      'lib/providers/anniversary_provider.dart',
    ).readAsStringSync();
    final goal = File('lib/providers/goal_provider.dart').readAsStringSync();

    expect(
      pomodoro,
      contains("CloudSyncProvider.recordDeletedItem('pomodoro_sessions'"),
    );
    expect(
      timeAudit.replaceAll(RegExp(r'\s+'), ''),
      contains("CloudSyncProvider.recordDeletedItems('time_entries'"),
    );
    expect(habit, contains("CloudSyncProvider.recordDeletedItem('habits'"));
    // TodoProvider 统一使用批量删除 recordDeletedItems
    expect(todo, contains('CloudSyncProvider.recordDeletedItems('));
    expect(todo, contains("'todos',"));
    expect(note, contains("CloudSyncProvider.recordDeletedItem('notes'"));
    expect(
      countdown,
      contains("CloudSyncProvider.recordDeletedItem('countdowns'"),
    );
    expect(
      calendar.replaceAll(RegExp(r'\s+'), ''),
      contains("CloudSyncProvider.recordDeletedItem('calendar_events'"),
    );
    expect(
      locationReminders,
      contains("CloudSyncProvider.recordDeletedItem('location_reminders'"),
    );
    expect(
      quickCaptureTemplates,
      contains("CloudSyncProvider.recordDeletedItem('quick_capture_templates'"),
    );
    expect(
      course.replaceAll(RegExp(r'\s+'), ''),
      contains("CloudSyncProvider.recordDeletedItem('courses'"),
    );
    expect(diary, contains("CloudSyncProvider.recordDeletedItem('diaries'"));
    expect(
      anniversary,
      contains("CloudSyncProvider.recordDeletedItem('anniversaries'"),
    );
    expect(
      goal.replaceAll(RegExp(r'\s+'), ''),
      contains("CloudSyncProvider.recordDeletedItem('goals'"),
    );
    expect(goal, contains('workspaceId: entry.key'));
  });

  test('偏好、位置提醒和共享空间漏项纳入同步链路', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();
    final backendSource = File('backend/main.py').readAsStringSync();

    for (final field in const [
      "'duoyi_location_reminders_v1': 'location_reminders'",
      "'location_reminders'",
      "'pref_reminder_ringtone_volume_percent'",
      "'pref_reminder_ringtone_sound'",
      "'pref_daily_reminder_kind'",
      "'pref_daily_reminder_slot2_kind'",
      "'pref_daily_reminder_slot3_kind'",
      "'courses': _WorkspacePayloadSpec(",
      "'time_entries': _WorkspacePayloadSpec(",
      "localKey: 'duoyi_courses'",
      "localKey: 'duoyi_time_entries'",
    ]) {
      expect(providerSource, contains(field), reason: field);
    }

    for (final field in const [
      'locationReminderProvider.onLocalMutationPersisted =\n      cloudSyncProvider.markUserMutationPending;',
      "changedCollections.contains('location_reminders')",
      'reloadTasks.add(locationReminderProvider.loadFromStorage)',
      'locationReminderProvider.addListener(syncLocationGeofences);',
      'preferencesProvider.onChangedKeys =\n      cloudSyncProvider.markUserPreferencesChanged;',
      'ReminderRingtoneSettings.onChanged = (keys)',
      'cloudSyncProvider.markUserPreferencesChanged(keys);',
      'await ReminderRingtoneSettings.applyPersistedSettingsToNative();',
    ]) {
      expect(mainSource, contains(field), reason: field);
    }

    expect(
      mainSource,
      isNot(
        contains(
          'preferencesProvider.addListener(cloudSyncProvider.markPreferencesChanged);',
        ),
      ),
    );

    for (final field in const [
      'static const _preferencesChangedKeysStorageKey',
      'void markPreferencesChanged([Iterable<String>? keys])',
      'void markUserPreferencesChanged([Iterable<String>? keys])',
      'void _markPreferencesChanged(',
      'void markUserQuickCaptureTemplatesChanged()',
      'void _markQuickCaptureTemplatesChanged({required bool markUserMutation})',
      'if (keys != null && normalizedKeys.isEmpty) return;',
      'final changedKeys = _readPendingPreferenceChangedKeys(prefs);',
      "if (changedKeys.isNotEmpty) 'changedKeys': changedKeys",
      'await storage.remove(_preferencesChangedKeysStorageKey)',
      'normalized.remove(\'changedKeys\');',
      'normalized.remove(\'changed_keys\');',
    ]) {
      expect(providerSource, contains(field), reason: field);
    }

    final preferencesProvider = File(
      'lib/providers/preferences_provider.dart',
    ).readAsStringSync();
    final ringtoneSettings = File(
      'lib/services/reminder_ringtone_settings.dart',
    ).readAsStringSync();
    for (final field in const [
      'void Function(Iterable<String> keys)? onChangedKeys;',
      'onChangedKeys?.call(cleanKeys);',
      '_notifyPreferenceKeys(const [_kFirstDayOfWeek]);',
      '_notifyPreferenceKeys(_dailyReminderSlotKeys(index));',
      '_notifyPreferenceKeys(const [_kBottomNavVisible]);',
      '_notifyPreferenceKeys(const [_kBottomNavOrder]);',
    ]) {
      expect(preferencesProvider, contains(field), reason: field);
    }
    for (final field in const [
      'static void Function(Iterable<String> keys)? onChanged;',
      'onChanged?.call(changedKeys);',
      'changedKeys: const [volumePreferenceKey],',
      'changedKeys: const [soundPreferenceKey],',
    ]) {
      expect(ringtoneSettings, contains(field), reason: field);
    }

    for (final field in const [
      'location_reminders TEXT DEFAULT',
      '("sync_data", "location_reminders", "\'[]\'")',
      'location_reminders: list = []',
      '"location_reminders"',
      'server_location_reminders = _list("location_reminders")',
      'merged_location_reminders = _merge_by_timestamp(',
      'req.location_reminders',
      'json.dumps(merged_location_reminders, ensure_ascii=False)',
      'merged_diaries = _merge_diaries_by_date(',
      'def _apply_tombstones_to_list(',
      'next_payload[collection_key] = _apply_tombstones_to_list(',
      'raw_changed_keys = client.get("changedKeys") or client.get("changed_keys")',
      'if changed_keys:',
      'result.pop("changedKeys", None)',
    ]) {
      expect(backendSource, contains(field), reason: field);
    }
  });

  test('课表、纪念日和位置提醒携带 updatedAt 防止旧同步覆盖', () {
    final courseModel = File(
      'lib/models/course_schedule.dart',
    ).readAsStringSync();
    final courseProvider = File(
      'lib/providers/course_provider.dart',
    ).readAsStringSync();
    final anniversaryModel = File(
      'lib/models/anniversary.dart',
    ).readAsStringSync();
    final anniversaryProvider = File(
      'lib/providers/anniversary_provider.dart',
    ).readAsStringSync();
    final locationModel = File(
      'lib/models/location_reminder.dart',
    ).readAsStringSync();
    final locationProvider = File(
      'lib/providers/location_reminder_provider.dart',
    ).readAsStringSync();

    for (final field in const [
      'DateTime updatedAt;',
      "'updatedAt': updatedAt.toIso8601String()",
      "DateTime.tryParse(json['updatedAt']?.toString() ?? '')",
      "DateTime.tryParse(json['updated_at']?.toString() ?? '')",
    ]) {
      expect(courseModel, contains(field), reason: 'course $field');
      expect(anniversaryModel, contains(field), reason: 'anniversary $field');
    }

    for (final field in const [
      'final DateTime updatedAt;',
      "'updatedAt': updatedAt.toIso8601String()",
      "DateTime.tryParse(json['updatedAt']?.toString() ?? '')",
      "DateTime.tryParse(json['updated_at']?.toString() ?? '')",
    ]) {
      expect(locationModel, contains(field), reason: 'location $field');
    }

    expect(courseProvider, contains('course.updatedAt = DateTime.now();'));
    expect(anniversaryProvider, contains('item.updatedAt = DateTime.now();'));
    expect(
      anniversaryProvider,
      contains('_items[idx].updatedAt = DateTime.now();'),
    );
    expect(
      locationProvider,
      contains('reminder.copyWith(updatedAt: DateTime.now())'),
    );

    final backendSource = File('backend/main.py').readAsStringSync();
    for (final field in const [
      'merged_annis = _merge_by_timestamp(',
      'server_annis,',
      'req_annis,',
      'merged_courses = _merge_by_timestamp(',
      'server_courses,',
      '_private_sync_items(req.courses),',
      'merged_location_reminders = _merge_by_timestamp(',
      'server_location_reminders,',
      'req.location_reminders,',
    ]) {
      expect(backendSource, contains(field), reason: field);
    }
  });

  test('会触发云同步的本地修改必须先落盘再通知监听', () {
    final habit = File('lib/providers/habit_provider.dart').readAsStringSync();
    final locationReminders = File(
      'lib/providers/location_reminder_provider.dart',
    ).readAsStringSync();
    final quickCaptureTemplates = File(
      'lib/providers/quick_capture_template_provider.dart',
    ).readAsStringSync();

    final addHabitBody = _methodBody(habit, 'Future<void> addHabit(');
    expect(addHabitBody, contains('await _save();'));
    expect(addHabitBody, contains('notifyListeners();'));
    _expectBefore(addHabitBody, 'await _save();', 'notifyListeners();');

    final importHabitsBody = _methodBody(
      habit,
      'Future<HabitImportSummary> importHabits(',
    );
    _expectBefore(importHabitsBody, 'await _save();', 'notifyListeners();');

    final incrementBody = _methodBody(
      habit,
      'Future<void> incrementHabitForDate(',
    );
    _expectBefore(incrementBody, 'await _save();', 'notifyListeners();');

    final decrementBody = _methodBody(
      habit,
      'Future<void> decrementHabitForDate(',
    );
    _expectBefore(decrementBody, 'await _save();', 'notifyListeners();');

    final locationRemoveBody = _methodBody(
      locationReminders,
      'Future<void> remove(String id)',
    );
    _expectBefore(
      locationRemoveBody,
      "await CloudSyncProvider.recordDeletedItem('location_reminders', id);",
      'notifyListeners();',
    );
    _expectBefore(locationRemoveBody, 'await _save();', 'notifyListeners();');

    final saveTriggeredHitsBody = _methodBody(
      locationReminders,
      'Future<void> _saveTriggeredHits(',
    );
    final normalizedSaveTriggeredHitsBody = saveTriggeredHitsBody.replaceAll(
      '\r\n',
      '\n',
    );
    expect(
      normalizedSaveTriggeredHitsBody,
      contains(
        "CloudSyncProvider.recordDeletedItems(\n        'location_reminders',",
      ),
    );
    _expectBefore(
      saveTriggeredHitsBody,
      "await CloudSyncProvider.recordDeletedItems(",
      'await _save();',
    );
    _expectBefore(
      saveTriggeredHitsBody,
      'await _save();',
      'notifyListeners();',
    );

    final ingestFixBody = _methodBody(
      locationReminders,
      'List<LocationReminderHit> ingestFix(',
    );
    expect(ingestFixBody, contains('_saveTriggeredHits(removedIds);'));
    expect(
      ingestFixBody,
      isNot(contains('_save();\n      notifyListeners();')),
    );

    final saveTemplateBody = _methodBody(
      quickCaptureTemplates,
      'Future<void> saveTemplate(',
    );
    _expectBefore(saveTemplateBody, 'await _persist();', 'notifyListeners();');

    final deleteTemplateBody = _methodBody(
      quickCaptureTemplates,
      'Future<void> deleteTemplate(String id)',
    );
    _expectBefore(
      deleteTemplateBody,
      "await CloudSyncProvider.recordDeletedItem('quick_capture_templates', id);",
      'notifyListeners();',
    );
    _expectBefore(
      deleteTemplateBody,
      'await _persist();',
      'notifyListeners();',
    );
  });
}

String _methodBody(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNonNegative, reason: signature);
  var parenDepth = 0;
  var open = -1;
  for (var i = start; i < source.length; i++) {
    final char = source.codeUnitAt(i);
    if (char == 40) parenDepth++;
    if (char == 41 && parenDepth > 0) parenDepth--;
    if (char == 123 && parenDepth == 0) {
      open = i;
      break;
    }
  }
  expect(open, isNonNegative, reason: signature);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final char = source.codeUnitAt(i);
    if (char == 123) depth++;
    if (char == 125) depth--;
    if (depth == 0) return source.substring(open, i + 1);
  }
  fail('未找到方法结束：$signature');
}

void _expectBefore(String source, String first, String second) {
  final firstIndex = source.indexOf(first);
  final secondIndex = source.indexOf(second);
  expect(firstIndex, isNonNegative, reason: first);
  expect(secondIndex, isNonNegative, reason: second);
  expect(
    firstIndex,
    lessThan(secondIndex),
    reason: '$first should precede $second',
  );
}

http.Response _syncResponse({required int version}) {
  return http.Response(
    json.encode({
      'server_updated_at': '2026-06-07T00:00:00.000Z',
      'server_version': version,
      'todos': [
        {'id': 'local-todo', 'title': '本地待办'},
      ],
      'collection_hashes': <String, String>{},
    }),
    200,
    headers: const {'content-type': 'application/json'},
  );
}
