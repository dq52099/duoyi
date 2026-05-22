import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('本地改动会后台自动同步，不需要手动入口', () {
    final source = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(source, contains('static const _autoSyncDelay'));
    expect(source, contains('Timer? _autoSyncTimer'));
    expect(source, contains('void markPendingLocalChange()'));
    expect(source, contains('_hasPendingChanges = true'));
    expect(source, contains('_scheduleAutoSync();'));
    expect(source, contains('if (_hasPendingChanges && _config.autoSync'));
    expect(source, contains('syncNow();'));
    expect(source, contains('_autoSyncTimer?.cancel();'));
    expect(source, contains("'user_profile': 'user_profile'"));
    expect(mainSource, contains('userProvider.addListener(markDirty);'));
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
    expect(providerSource, contains('await _pullRemoteChanges();'));
    expect(providerSource, contains('_hasPendingChanges || _isSyncing'));
    expect(providerSource, contains('_scheduleRemotePoll();'));
    expect(mainSource, contains('cloudSyncProvider.startRemotePolling();'));
    expect(mainSource, contains('cloudSyncProvider.stopRemotePolling();'));
  });

  test('同步事件流收到新版本后即时拉取，轮询仍作为兜底', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final backendSource = File('backend/main.py').readAsStringSync();

    for (final field in [
      'StreamSubscription<String>? _remoteEventSubscription',
      "Timer? _remoteEventRetryTimer",
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
      'if (_hasPendingChanges || _isSyncing || !_config.autoSync) return;',
      'cancelOnError: true',
      '_scheduleRemoteEventReconnect(_autoRetryDelay)',
      '_scheduleRemotePoll(_autoRetryDelay)',
      '_remoteEventRetryTimer?.cancel();',
      '_remoteEventSubscription?.cancel();',
    ]) {
      expect(providerSource, contains(field));
    }

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

    expect(providerSource, contains('Future<void> _pullRemoteChanges()'));
    expect(providerSource, contains("client.post('/api/sync/pull'"));
    expect(providerSource, contains("'collection_hashes'"));
    expect(providerSource, contains('_buildCollectionHashes(payload)'));
    expect(providerSource, contains('static const _syncPullCollections'));
    expect(providerSource, contains('sha256'));
    expect(providerSource, contains('.convert(utf8.encode'));
    expect(providerSource, contains('SplayTreeMap<String, Object?>'));
    expect(providerSource, contains('await _applySyncResponse('));
    expect(providerSource, contains('await _pullRemoteChanges();'));

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
      providerSource.indexOf('Future<void> syncNow()'),
      providerSource.indexOf('Future<void> _pullRemoteChanges()'),
    );
    expect(syncBody, contains("client.post('/api/sync', payload)"));
    expect(syncBody, contains("client.post('/api/sync/delta'"));
    expect(syncBody, contains('changedCollections == null'));
    expect(syncBody, contains('changedCollections.isEmpty'));

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
    expect(providerSource, contains('_buildItemHashes(payload)'));
    expect(providerSource, contains('_buildSyncItemDelta('));
    expect(providerSource, contains("client.post('/api/sync/item-delta'"));
    expect(providerSource, contains("'items': items"));
    expect(providerSource, contains("'objects': objects"));
    expect(providerSource, contains("'deleted_items': deletedItems"));
    expect(providerSource, contains('_decodeItemHashes('));
    expect(providerSource, contains('_itemDeltaCollections'));
    expect(providerSource, contains('_objectDeltaCollections'));
    expect(providerSource, contains("_itemHashesStorageKey"));

    final syncBody = providerSource.substring(
      providerSource.indexOf('Future<void> syncNow()'),
      providerSource.indexOf('Future<void> _pullRemoteChanges()'),
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

  test('云端回写后会刷新本地个人资料且不触发二次脏标记', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(providerSource, contains("'user_profile': 'user_profile'"));
    expect(mainSource, contains('cloudSyncProvider.onSynced = ()'));
    expect(
      mainSource,
      contains('cloudSyncProvider.suppressDirtyMarkWhile(() async {'),
    );
    expect(mainSource, contains('await userProvider.loadFromStorage();'));
    expect(mainSource, contains('userProvider.addListener(markDirty);'));
  });

  test('个人资料带更新时间，服务端可以按 updatedAt 合并新资料', () {
    final modelSource = File('lib/models/user_profile.dart').readAsStringSync();
    final providerSource = File(
      'lib/providers/user_provider.dart',
    ).readAsStringSync();
    final backendSource = File('backend/main.py').readAsStringSync();

    expect(modelSource, contains('DateTime? updatedAt;'));
    expect(modelSource, contains("'updatedAt': updatedAt?.toIso8601String()"));
    expect(providerSource, contains('_profile.updatedAt = DateTime.now()'));
    expect(
      backendSource,
      contains('def _merge_dict(server: dict, client: dict)'),
    );
    expect(backendSource, contains('client_ts = client.get("updatedAt")'));
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
      if (text.contains('CloudSyncProvider') ||
          text.contains('syncNow()') ||
          text.contains('.syncNow(')) {
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
        'return updatedAt.isNotEmpty && updatedAt.compareTo(deletedAt) > 0',
      ),
    );
    expect(source, contains('prefs.setString('));
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
      timeAudit,
      contains("CloudSyncProvider.recordDeletedItems('time_entries'"),
    );
    expect(habit, contains("CloudSyncProvider.recordDeletedItem('habits'"));
    expect(todo, contains("CloudSyncProvider.recordDeletedItem('todos'"));
    expect(todo, contains('CloudSyncProvider.recordDeletedItems('));
    expect(todo, contains("'todos',"));
    expect(note, contains("CloudSyncProvider.recordDeletedItem('notes'"));
    expect(
      countdown,
      contains("CloudSyncProvider.recordDeletedItem('countdowns'"),
    );
    expect(
      calendar,
      contains("CloudSyncProvider.recordDeletedItem('calendar_events'"),
    );
    expect(course, contains("CloudSyncProvider.recordDeletedItem('courses'"));
    expect(diary, contains("CloudSyncProvider.recordDeletedItem('diaries'"));
    expect(
      anniversary,
      contains("CloudSyncProvider.recordDeletedItem('anniversaries'"),
    );
    expect(goal, contains("CloudSyncProvider.recordDeletedItem('goals'"));
  });
}
