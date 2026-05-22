import 'dart:convert';
import 'dart:async';
import 'dart:collection';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/feature_flags.dart';
import '../services/api_client.dart';

class SyncConfig {
  final DateTime lastSync;
  final bool autoSync;

  const SyncConfig({required this.lastSync, this.autoSync = true});
}

class SyncMergeDecision {
  final String workspaceId;
  final String itemType;
  final String itemId;
  final String winner;
  final String reason;
  final List<String> changedFields;
  final String localUpdatedAt;
  final String remoteUpdatedAt;
  final DateTime decidedAt;

  const SyncMergeDecision({
    required this.workspaceId,
    required this.itemType,
    required this.itemId,
    required this.winner,
    required this.reason,
    this.changedFields = const [],
    required this.localUpdatedAt,
    required this.remoteUpdatedAt,
    required this.decidedAt,
  });

  Map<String, dynamic> toJson() => {
    'workspaceId': workspaceId,
    'itemType': itemType,
    'itemId': itemId,
    'winner': winner,
    'reason': reason,
    'changedFields': changedFields,
    'localUpdatedAt': localUpdatedAt,
    'remoteUpdatedAt': remoteUpdatedAt,
    'decidedAt': decidedAt.toIso8601String(),
  };

  factory SyncMergeDecision.fromJson(Map<String, dynamic> json) {
    return SyncMergeDecision(
      workspaceId: json['workspaceId']?.toString() ?? '',
      itemType: json['itemType']?.toString() ?? '',
      itemId: json['itemId']?.toString() ?? '',
      winner: json['winner']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
      changedFields:
          (json['changedFields'] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      localUpdatedAt: json['localUpdatedAt']?.toString() ?? '',
      remoteUpdatedAt: json['remoteUpdatedAt']?.toString() ?? '',
      decidedAt:
          DateTime.tryParse(json['decidedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class _WorkspacePayloadSpec {
  final String localKey;
  final String itemType;

  const _WorkspacePayloadSpec({required this.localKey, required this.itemType});
}

class _WorkspaceMergeResult {
  final List<dynamic> items;
  final List<SyncMergeDecision> decisions;

  const _WorkspaceMergeResult(this.items, this.decisions);
}

/// 云同步：服务器地址与 token 直接复用 AuthProvider(普通用户无需感知)。
/// 登录后和本地数据变更后自动同步。
class CloudSyncProvider extends ChangeNotifier {
  static const _autoSyncDelay = Duration(seconds: 20);
  static const _autoRetryDelay = Duration(minutes: 3);
  static const _remotePollDelay = Duration(minutes: 2);
  static const deletedItemsStorageKey = 'sync_deleted_items';
  static const _serverUpdatedAtStorageKey = 'sync_server_updated_at';
  static const _serverVersionStorageKey = 'sync_server_version';
  static const _collectionHashesStorageKey = 'sync_collection_hashes';
  static const _itemHashesStorageKey = 'sync_item_hashes';

  SyncConfig _config = SyncConfig(
    lastSync: DateTime.fromMillisecondsSinceEpoch(0),
    autoSync: true,
  );
  bool _isSyncing = false;
  String? _lastError;
  Timer? _autoSyncTimer;
  Timer? _remotePollTimer;
  Timer? _remoteEventRetryTimer;
  StreamSubscription<String>? _remoteEventSubscription;
  String _remoteEventName = '';
  final List<String> _remoteEventDataLines = <String>[];
  List<SyncMergeDecision> _lastWorkspaceMergeDecisions = const [];
  String _lastServerUpdatedAt = '';
  int? _lastServerVersion;
  Map<String, String> _lastCollectionHashes = const {};
  Map<String, Map<String, String>> _lastItemHashes = const {};

  VoidCallback? onSynced;

  // 由 main.dart 注入(通过 AuthProvider 取活跃的 ApiClient)
  ApiClient? Function()? apiClientGetter;

  /// 可选：返回当前服务端 /api/config，用来判断 backup_enabled
  Map<String, dynamic>? Function()? serverConfigGetter;

  SyncConfig get config => _config;
  bool get isSyncing => _isSyncing;
  String? get lastError => _lastError;
  bool get hasEverSynced => _config.lastSync.millisecondsSinceEpoch > 0;
  String get lastServerUpdatedAt => _lastServerUpdatedAt;
  int? get lastServerVersion => _lastServerVersion;
  List<SyncMergeDecision> get lastWorkspaceMergeDecisions =>
      List.unmodifiable(_lastWorkspaceMergeDecisions);

  /// 是否有未同步到后端的本地改动（由 Provider 写入时打上时间戳；本次同步成功后清零）。
  bool _hasPendingChanges = false;
  bool get hasPendingChanges => _hasPendingChanges;

  /// 由外部（Provider 的 addListener）在本地数据发生变动后调用，
  /// 标记待同步并排队后台自动同步。
  ///
  /// 为避免冷启动 `loadFromStorage` 触发的 notifyListeners 与同步回写
  /// `onSynced → loadFromStorage` 触发的 notifyListeners 被当作"脏改动"
  /// 误报 badge，本方法仅在 [_suppressDirtyMark] = false 时生效。
  void markPendingLocalChange() {
    if (_suppressDirtyMark) return;
    if (!_hasPendingChanges) {
      _hasPendingChanges = true;
      notifyListeners();
    }
    _remotePollTimer?.cancel();
    _scheduleAutoSync();
  }

  void _scheduleAutoSync([Duration delay = _autoSyncDelay]) {
    _autoSyncTimer?.cancel();
    if (!_config.autoSync || !FeatureFlags.cloudSyncV2) return;
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      return;
    }
    _autoSyncTimer = Timer(delay, () {
      if (_hasPendingChanges && _config.autoSync && !_isSyncing) {
        // ignore: discarded_futures
        syncNow();
      }
    });
  }

  void startRemotePolling() {
    _startRemoteEvents();
    _scheduleRemotePoll(Duration.zero);
  }

  void stopRemotePolling() {
    _remotePollTimer?.cancel();
    _remotePollTimer = null;
    _remoteEventRetryTimer?.cancel();
    _remoteEventRetryTimer = null;
    _remoteEventSubscription?.cancel();
    _remoteEventSubscription = null;
    _remoteEventName = '';
    _remoteEventDataLines.clear();
  }

  void _startRemoteEvents() {
    if (_remoteEventSubscription != null) return;
    if (!_config.autoSync || !FeatureFlags.cloudSyncV2) return;
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      return;
    }
    _remoteEventRetryTimer?.cancel();
    _remoteEventRetryTimer = null;
    _remoteEventSubscription = client
        .streamLines('/api/sync/events')
        .listen(
          _handleRemoteEventLine,
          onError: (Object error) {
            _lastError = error.toString();
            _remoteEventSubscription = null;
            _remoteEventName = '';
            _remoteEventDataLines.clear();
            _scheduleRemoteEventReconnect(_autoRetryDelay);
            _scheduleRemotePoll(_autoRetryDelay);
            notifyListeners();
          },
          onDone: () {
            _remoteEventSubscription = null;
            _remoteEventName = '';
            _remoteEventDataLines.clear();
            _scheduleRemoteEventReconnect(_autoRetryDelay);
            _scheduleRemotePoll(_autoRetryDelay);
          },
          cancelOnError: true,
        );
  }

  void _scheduleRemoteEventReconnect([Duration delay = _autoRetryDelay]) {
    _remoteEventRetryTimer?.cancel();
    if (!_config.autoSync || !FeatureFlags.cloudSyncV2) return;
    if (_remoteEventSubscription != null) return;
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      return;
    }
    _remoteEventRetryTimer = Timer(delay, () {
      _remoteEventRetryTimer = null;
      _startRemoteEvents();
    });
  }

  void _handleRemoteEventLine(String line) {
    if (line.isEmpty) {
      _dispatchRemoteEvent();
      return;
    }
    if (line.startsWith(':')) return;
    if (line.startsWith('event:')) {
      _remoteEventName = line.substring('event:'.length).trim();
      return;
    }
    if (line.startsWith('data:')) {
      _remoteEventDataLines.add(line.substring('data:'.length).trimLeft());
    }
  }

  void _dispatchRemoteEvent() {
    final eventName = _remoteEventName.isEmpty ? 'message' : _remoteEventName;
    final rawData = _remoteEventDataLines.join('\n');
    _remoteEventName = '';
    _remoteEventDataLines.clear();
    if (eventName != 'sync' || rawData.isEmpty) return;
    if (_hasPendingChanges || _isSyncing || !_config.autoSync) return;
    try {
      final decoded = json.decode(rawData);
      if (decoded is! Map) return;
      final serverVersion = (decoded['server_version'] as num?)?.toInt();
      final serverUpdatedAt = decoded['server_updated_at']?.toString() ?? '';
      final versionUnchanged =
          serverVersion != null &&
          _lastServerVersion != null &&
          serverVersion <= _lastServerVersion!;
      final timestampUnchanged =
          serverVersion == null &&
          serverUpdatedAt.isNotEmpty &&
          serverUpdatedAt == _lastServerUpdatedAt;
      if (versionUnchanged || timestampUnchanged) return;
      // ignore: discarded_futures
      _pullRemoteChanges();
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
    }
  }

  void _scheduleRemotePoll([Duration delay = _remotePollDelay]) {
    _remotePollTimer?.cancel();
    if (!_config.autoSync || !FeatureFlags.cloudSyncV2) return;
    if (_hasPendingChanges || _isSyncing) return;
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      return;
    }
    _remotePollTimer = Timer(delay, () {
      _remotePollTimer = null;
      if (_hasPendingChanges || !_config.autoSync || _isSyncing) {
        _scheduleRemotePoll();
        return;
      }
      // ignore: discarded_futures
      _pollRemoteChanges();
    });
  }

  /// 让一段代码块内的 `markPendingLocalChange` 静默（调用链返回后自动恢复）。
  ///
  /// 用法：
  /// ```dart
  /// await cloudSync.suppressDirtyMarkWhile(() async {
  ///   await todoProvider.loadFromStorage();
  /// });
  /// ```
  Future<void> suppressDirtyMarkWhile(Future<void> Function() body) async {
    _suppressDirtyMark = true;
    try {
      await body();
    } finally {
      _suppressDirtyMark = false;
    }
  }

  bool _suppressDirtyMark = true; // 初始 true，等 main.dart 显式放开

  /// 让外部显式放开 dirty 抑制。`main.dart` 在所有冷启动 `loadFromStorage`
  /// 完成、即将 `runApp` 之前调一次 `setDirtyMarkEnabled(true)`。
  set dirtyMarkEnabled(bool value) {
    _suppressDirtyMark = !value;
  }

  /// cloud_sync_v2 特性开关：关闭时 [syncNow] 直接返回，不发出网络请求。
  /// 对应 Requirements 12.6。
  bool get isCloudSyncV2Enabled => FeatureFlags.cloudSyncV2;

  Future<void> _pollRemoteChanges() async {
    if (!_config.autoSync || !FeatureFlags.cloudSyncV2) return;
    if (_hasPendingChanges || _isSyncing) {
      _scheduleRemotePoll();
      return;
    }
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      return;
    }

    try {
      final status = await client.get('/api/sync/status');
      final serverVersion = (status['server_version'] as num?)?.toInt();
      final serverUpdatedAt = status['server_updated_at']?.toString() ?? '';
      final versionUnchanged =
          serverVersion != null &&
          _lastServerVersion != null &&
          serverVersion <= _lastServerVersion!;
      final timestampUnchanged =
          serverVersion == null &&
          serverUpdatedAt.isNotEmpty &&
          serverUpdatedAt == _lastServerUpdatedAt;

      if (versionUnchanged || timestampUnchanged) {
        final hadError = _lastError != null;
        _lastError = null;
        _scheduleRemotePoll();
        if (hadError) notifyListeners();
        return;
      }

      await _pullRemoteChanges();
    } catch (e) {
      _lastError = e.toString();
      _scheduleRemotePoll(_autoRetryDelay);
      notifyListeners();
    }
  }

  static const _stringEncodedListKeys = <String>{
    'todos',
    'habits',
    'pomodoro_sessions',
    'pomodoro_focus_penalties',
  };

  static const _listPayloads = <String, String>{
    'todos': 'todos',
    'habits': 'habits',
    'pomodoro_sessions': 'pomodoro_sessions',
    'pomodoro_focus_penalties': 'focus_penalties',
    'duoyi_notes': 'notes',
    'duoyi_countdowns': 'countdowns',
    'duoyi_anniversaries_v2': 'anniversaries',
    'duoyi_diary': 'diaries',
    'duoyi_goals': 'goals',
    'duoyi_local_calendar_events_v1': 'calendar_events',
    'duoyi_time_entries': 'time_entries',
    'duoyi_courses': 'courses',
  };

  static const _objectPayloads = <String, String>{
    'pomodoro_config': 'pomodoro_config',
    'user_profile': 'user_profile',
    'duoyi_course_settings': 'course_settings',
    'duoyi_achievements_unlocked': 'achievement_states',
    'duoyi_virtual_rewards': 'virtual_rewards',
    'duoyi_focus_rooms': 'focus_rooms',
    'theme_shop_state': 'theme_shop_state',
  };

  static const _syncPullCollections = <String>{
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
    'pomodoro_config',
    'user_profile',
    'course_settings',
    'achievement_states',
    'virtual_rewards',
    'focus_rooms',
    'theme_shop_state',
    'deleted_items',
    'workspace_payloads',
  };

  static const _itemDeltaCollections = <String>{
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
  };

  static const _objectDeltaCollections = <String>{
    'pomodoro_config',
    'user_profile',
    'course_settings',
    'achievement_states',
    'virtual_rewards',
    'focus_rooms',
    'theme_shop_state',
  };

  static Future<void> recordDeletedItem(
    String collection,
    String id, {
    DateTime? deletedAt,
  }) async {
    await recordDeletedItems(collection, [id], deletedAt: deletedAt);
  }

  static Future<void> recordDeletedItems(
    String collection,
    Iterable<String> ids, {
    DateTime? deletedAt,
  }) async {
    final cleanIds = ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (cleanIds.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final deleted = _decodeDeletedItems(
      prefs.getString(deletedItemsStorageKey),
    );
    final bucket = deleted.putIfAbsent(collection, () => <String, String>{});
    final stamp = (deletedAt ?? DateTime.now()).toIso8601String();
    for (final id in cleanIds) {
      final current = bucket[id];
      if (current == null || stamp.compareTo(current) > 0) {
        bucket[id] = stamp;
      }
    }
    await prefs.setString(deletedItemsStorageKey, json.encode(deleted));
  }

  static Map<String, Map<String, String>> _decodeDeletedItems(String? raw) {
    if (raw == null || raw.isEmpty) return <String, Map<String, String>>{};
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return <String, Map<String, String>>{};
      final result = <String, Map<String, String>>{};
      for (final entry in decoded.entries) {
        final bucket = <String, String>{};
        final value = entry.value;
        if (value is Map) {
          for (final entry in value.entries) {
            final id = entry.key.toString().trim();
            final deletedAt = entry.value?.toString() ?? '';
            if (id.isNotEmpty && deletedAt.isNotEmpty) {
              bucket[id] = deletedAt;
            }
          }
        }
        if (bucket.isNotEmpty) {
          result[entry.key.toString()] = bucket;
        }
      }
      return result;
    } catch (_) {
      return <String, Map<String, String>>{};
    }
  }

  static List<dynamic> _filterDeletedRemoteList({
    required String collection,
    required List<dynamic> items,
    required Map<String, Map<String, String>> deletedItems,
  }) {
    final tombstones = deletedItems[collection];
    if (tombstones == null || tombstones.isEmpty) return items;
    return items.where((item) {
      if (item is! Map || item['id'] == null) return true;
      final deletedAt = tombstones[item['id'].toString()];
      if (deletedAt == null || deletedAt.isEmpty) return true;
      final updatedAt = _remoteItemUpdatedAt(item);
      return updatedAt.isNotEmpty && updatedAt.compareTo(deletedAt) > 0;
    }).toList();
  }

  static String _remoteItemUpdatedAt(Map<dynamic, dynamic> item) {
    for (final key in const [
      'updatedAt',
      'updated_at',
      'modifiedAt',
      'endTime',
      'createdAt',
    ]) {
      final value = item[key]?.toString() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncStr = prefs.getString('sync_last_time');
    final lastSync = lastSyncStr != null
        ? DateTime.parse(lastSyncStr)
        : DateTime.fromMillisecondsSinceEpoch(0);
    final autoSync = prefs.getBool('sync_auto') ?? true;
    _lastServerUpdatedAt = prefs.getString(_serverUpdatedAtStorageKey) ?? '';
    _lastServerVersion = prefs.getInt(_serverVersionStorageKey);
    _lastCollectionHashes = _decodeCollectionHashes(
      prefs.getString(_collectionHashesStorageKey),
    );
    _lastItemHashes = _decodeItemHashes(prefs.getString(_itemHashesStorageKey));
    _config = SyncConfig(lastSync: lastSync, autoSync: autoSync);
    _lastWorkspaceMergeDecisions =
        (prefs.getStringList('sync_merge_decisions') ?? const [])
            .map((raw) {
              try {
                return SyncMergeDecision.fromJson(
                  Map<String, dynamic>.from(json.decode(raw) as Map),
                );
              } catch (_) {
                return null;
              }
            })
            .whereType<SyncMergeDecision>()
            .toList();
    notifyListeners();
  }

  Future<void> setAutoSync(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_auto', value);
    _config = SyncConfig(lastSync: _config.lastSync, autoSync: value);
    if (value && _hasPendingChanges) {
      _scheduleAutoSync();
    } else if (value) {
      _scheduleRemotePoll(Duration.zero);
    } else {
      _autoSyncTimer?.cancel();
      stopRemotePolling();
    }
    notifyListeners();
  }

  Future<void> syncNow() async {
    _autoSyncTimer?.cancel();
    // Req 12.6：关闭 cloud_sync_v2 时完全离线可用，不发出任何网络请求。
    if (!FeatureFlags.cloudSyncV2) {
      return;
    }
    if (_isSyncing) return;
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      _lastError = '请先登录';
      notifyListeners();
      return;
    }
    // 如果服务端关掉了 backup_enabled，就不要浪费网络
    if (serverConfigGetter != null) {
      final cfg = serverConfigGetter!.call();
      if (cfg != null && cfg['backup_enabled'] == false) {
        _lastError = '管理员已关闭云端备份';
        notifyListeners();
        return;
      }
    }
    _isSyncing = true;
    _lastError = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();

      final payload = _buildLocalSyncPayload(prefs);
      final localHashes = _buildCollectionHashes(payload);
      final localItemHashes = _buildItemHashes(payload);
      final itemDelta = _buildSyncItemDelta(payload, localItemHashes);
      final changedCollections = _changedSyncCollections(payload, localHashes);
      Map<String, dynamic> response;
      if (changedCollections == null) {
        response = await client.post('/api/sync', payload);
      } else if (changedCollections.isEmpty) {
        _lastCollectionHashes = localHashes;
        _lastItemHashes = localItemHashes;
        await prefs.setString(
          _collectionHashesStorageKey,
          json.encode(localHashes),
        );
        await prefs.setString(
          _itemHashesStorageKey,
          json.encode(localItemHashes),
        );
        _hasPendingChanges = false;
        _lastError = null;
        _isSyncing = false;
        _scheduleRemotePoll();
        notifyListeners();
        return;
      } else if (itemDelta != null && itemDelta.isNotEmpty) {
        response = await client.post('/api/sync/item-delta', {
          ...itemDelta,
          'collection_hashes': localHashes,
        });
      } else {
        response = await client.post('/api/sync/delta', {
          'collections': changedCollections,
          'collection_hashes': localHashes,
        });
      }
      await _applySyncResponse(
        prefs,
        response,
        fallbackDeletedItems:
            payload['deleted_items'] as Map<String, Map<String, String>>,
      );

      final now = DateTime.now();
      _config = SyncConfig(lastSync: now, autoSync: _config.autoSync);
      await prefs.setString('sync_last_time', now.toIso8601String());
      _hasPendingChanges = false;

      onSynced?.call();
    } catch (e) {
      _lastError = e.toString();
    }

    _isSyncing = false;
    if (_lastError != null && _hasPendingChanges) {
      _scheduleAutoSync(_autoRetryDelay);
    } else if (_lastError == null && !_hasPendingChanges) {
      _scheduleRemotePoll();
    }
    notifyListeners();
  }

  Future<void> _pullRemoteChanges() async {
    if (_isSyncing) return;
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      return;
    }
    if (serverConfigGetter != null) {
      final cfg = serverConfigGetter!.call();
      if (cfg != null && cfg['backup_enabled'] == false) {
        _lastError = '管理员已关闭云端备份';
        notifyListeners();
        return;
      }
    }

    _isSyncing = true;
    _lastError = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = _buildLocalSyncPayload(prefs);
      final response = await client.post('/api/sync/pull', {
        'collection_hashes': _buildCollectionHashes(payload),
      });
      await _applySyncResponse(
        prefs,
        response,
        fallbackDeletedItems:
            payload['deleted_items'] as Map<String, Map<String, String>>,
      );
      final now = DateTime.now();
      _config = SyncConfig(lastSync: now, autoSync: _config.autoSync);
      await prefs.setString('sync_last_time', now.toIso8601String());
      onSynced?.call();
    } catch (e) {
      _lastError = e.toString();
    }

    _isSyncing = false;
    if (_lastError == null && !_hasPendingChanges) {
      _scheduleRemotePoll();
    } else if (_lastError != null) {
      _scheduleRemotePoll(_autoRetryDelay);
    }
    notifyListeners();
  }

  Map<String, dynamic> _buildLocalSyncPayload(SharedPreferences prefs) {
    final payload = <String, dynamic>{};
    _listPayloads.forEach((localKey, remoteKey) {
      if (_stringEncodedListKeys.contains(localKey)) {
        final str = prefs.getString(localKey);
        if (str != null && str.isNotEmpty) {
          try {
            final decoded = json.decode(str);
            payload[remoteKey] = decoded is List ? decoded : [];
          } catch (_) {
            payload[remoteKey] = [];
          }
        } else {
          payload[remoteKey] = [];
        }
      } else {
        final raw = prefs.getStringList(localKey);
        if (raw != null) {
          payload[remoteKey] = raw
              .map((e) {
                try {
                  return json.decode(e);
                } catch (_) {
                  return null;
                }
              })
              .where((e) => e != null)
              .toList();
        } else {
          payload[remoteKey] = [];
        }
      }
    });

    _objectPayloads.forEach((localKey, remoteKey) {
      final str = prefs.getString(localKey);
      if (str != null && str.isNotEmpty) {
        try {
          final decoded = json.decode(str);
          payload[remoteKey] = decoded is Map ? decoded : {};
        } catch (_) {
          payload[remoteKey] = <String, dynamic>{};
        }
      } else {
        payload[remoteKey] = <String, dynamic>{};
      }
    });

    payload['deleted_items'] = _decodeDeletedItems(
      prefs.getString(deletedItemsStorageKey),
    );
    payload['workspace_payloads'] = _buildWorkspacePayloads(payload);
    return payload;
  }

  Map<String, String> _buildCollectionHashes(Map<String, dynamic> payload) {
    final result = <String, String>{};
    for (final key in _syncPullCollections) {
      result[key] = _syncPayloadHash(payload[key]);
    }
    return result;
  }

  Map<String, Map<String, String>> _buildItemHashes(
    Map<String, dynamic> payload,
  ) {
    final result = <String, Map<String, String>>{};
    for (final key in _itemDeltaCollections) {
      final list = payload[key];
      if (list is! List) continue;
      final bucket = <String, String>{};
      for (final item in list) {
        if (item is! Map || item['id'] == null) continue;
        final id = item['id'].toString();
        if (id.isEmpty) continue;
        bucket[id] = _syncPayloadHash(item);
      }
      result[key] = bucket;
    }
    for (final key in _objectDeltaCollections) {
      result[key] = {'_': _syncPayloadHash(payload[key])};
    }
    return result;
  }

  Map<String, dynamic>? _buildSyncItemDelta(
    Map<String, dynamic> payload,
    Map<String, Map<String, String>> localItemHashes,
  ) {
    final hasBaseline = _itemDeltaCollections.every(
      _lastItemHashes.containsKey,
    );
    if (!hasBaseline) return null;

    final items = <String, List<dynamic>>{};
    final objects = <String, dynamic>{};
    final deletedItems = _decodeDeletedItems(
      json.encode(payload['deleted_items']),
    );

    for (final key in _itemDeltaCollections) {
      final baseline = _lastItemHashes[key] ?? const <String, String>{};
      final current = localItemHashes[key] ?? const <String, String>{};
      final list = payload[key];
      if (list is List) {
        final changed = <dynamic>[];
        for (final item in list) {
          if (item is! Map || item['id'] == null) continue;
          final id = item['id'].toString();
          if (baseline[id] != current[id]) {
            changed.add(item);
          }
        }
        if (changed.isNotEmpty) items[key] = changed;
      }
    }

    for (final key in _objectDeltaCollections) {
      final baselineHash = _lastItemHashes[key]?['_'];
      final currentHash = localItemHashes[key]?['_'];
      if (baselineHash != currentHash) {
        objects[key] = payload[key];
      }
    }

    if (items.isEmpty && objects.isEmpty && deletedItems.isEmpty) {
      return const <String, dynamic>{};
    }
    return {'items': items, 'objects': objects, 'deleted_items': deletedItems};
  }

  Map<String, dynamic>? _changedSyncCollections(
    Map<String, dynamic> payload,
    Map<String, String> localHashes,
  ) {
    final hasBaseline = _syncPullCollections.every(
      _lastCollectionHashes.containsKey,
    );
    if (!hasBaseline) return null;
    final changed = <String, dynamic>{};
    for (final key in _syncPullCollections) {
      if (_lastCollectionHashes[key] != localHashes[key]) {
        changed[key] = payload[key];
      }
    }
    return changed;
  }

  String _syncPayloadHash(Object? value) {
    return sha256
        .convert(utf8.encode(json.encode(_canonicalize(value))))
        .toString();
  }

  Object? _canonicalize(Object? value) {
    if (value is Map) {
      final sorted = SplayTreeMap<String, Object?>();
      for (final entry in value.entries) {
        sorted[entry.key.toString()] = _canonicalize(entry.value);
      }
      return sorted;
    }
    if (value is Iterable) {
      return value.map(_canonicalize).toList(growable: false);
    }
    return value;
  }

  Future<void> _applySyncResponse(
    SharedPreferences prefs,
    Map<String, dynamic> response, {
    required Map<String, Map<String, String>> fallbackDeletedItems,
  }) async {
    await _persistServerRevision(prefs, response);

    final responseDeletedItems = response['deleted_items'];
    var mergedDeletedItems = fallbackDeletedItems;
    if (responseDeletedItems is Map) {
      mergedDeletedItems = _decodeDeletedItems(
        json.encode(responseDeletedItems),
      );
      await prefs.setString(
        deletedItemsStorageKey,
        json.encode(mergedDeletedItems),
      );
    }

    for (final entry in _listPayloads.entries) {
      final remoteKey = entry.value;
      final localKey = entry.key;
      final value = response[remoteKey];
      if (value is! List) continue;
      final filteredValue = _filterDeletedRemoteList(
        collection: remoteKey,
        items: value,
        deletedItems: mergedDeletedItems,
      );
      if (_stringEncodedListKeys.contains(localKey)) {
        await prefs.setString(localKey, json.encode(filteredValue));
      } else {
        await prefs.setStringList(
          localKey,
          filteredValue.map((e) => json.encode(e)).toList(),
        );
      }
    }
    for (final entry in _objectPayloads.entries) {
      final remoteKey = entry.value;
      final localKey = entry.key;
      final value = response[remoteKey];
      if (value is! Map) continue;
      await prefs.setString(localKey, json.encode(value));
    }

    final workspacePayloads = response['workspace_payloads'];
    if (workspacePayloads is Map) {
      _lastWorkspaceMergeDecisions = await _mergeWorkspacePayloads(
        prefs,
        workspacePayloads,
      );
      await prefs.setStringList(
        'sync_merge_decisions',
        _lastWorkspaceMergeDecisions
            .take(50)
            .map((decision) => json.encode(decision.toJson()))
            .toList(),
      );
    }
    final nextPayload = _buildLocalSyncPayload(prefs);
    _lastItemHashes = _buildItemHashes(nextPayload);
    await prefs.setString(_itemHashesStorageKey, json.encode(_lastItemHashes));
  }

  Future<void> _persistServerRevision(
    SharedPreferences prefs,
    Map<String, dynamic> response,
  ) async {
    final serverUpdatedAt = response['server_updated_at']?.toString() ?? '';
    final serverVersion = (response['server_version'] as num?)?.toInt();
    if (serverUpdatedAt.isNotEmpty) {
      _lastServerUpdatedAt = serverUpdatedAt;
      await prefs.setString(_serverUpdatedAtStorageKey, serverUpdatedAt);
    }
    if (serverVersion != null) {
      _lastServerVersion = serverVersion;
      await prefs.setInt(_serverVersionStorageKey, serverVersion);
    }
    final collectionHashes = response['collection_hashes'];
    if (collectionHashes is Map) {
      _lastCollectionHashes = _decodeCollectionHashes(
        json.encode(collectionHashes),
      );
      await prefs.setString(
        _collectionHashesStorageKey,
        json.encode(_lastCollectionHashes),
      );
    }
  }

  static Map<String, String> _decodeCollectionHashes(String? raw) {
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return <String, String>{};
      return {
        for (final entry in decoded.entries)
          if (entry.value != null) entry.key.toString(): entry.value.toString(),
      };
    } catch (_) {
      return <String, String>{};
    }
  }

  static Map<String, Map<String, String>> _decodeItemHashes(String? raw) {
    if (raw == null || raw.isEmpty) return <String, Map<String, String>>{};
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return <String, Map<String, String>>{};
      final result = <String, Map<String, String>>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        result[entry.key.toString()] = {
          for (final item in value.entries)
            if (item.value != null) item.key.toString(): item.value.toString(),
        };
      }
      return result;
    } catch (_) {
      return <String, Map<String, String>>{};
    }
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _remotePollTimer?.cancel();
    _remoteEventRetryTimer?.cancel();
    _remoteEventSubscription?.cancel();
    super.dispose();
  }

  Map<String, dynamic> _buildWorkspacePayloads(Map<String, dynamic> payload) {
    final result = <String, dynamic>{};
    for (final collection in _workspacePayloadCollections.keys) {
      final list = payload[collection];
      if (list is! List) continue;
      for (final item in list) {
        if (item is! Map) continue;
        final workspaceId = _sharedWorkspaceId(item);
        if (workspaceId == null) continue;
        final bucket = _workspaceBucket(result, workspaceId);
        (bucket[collection] as List).add(item);
      }
    }
    return result;
  }

  Future<List<SyncMergeDecision>> _mergeWorkspacePayloads(
    SharedPreferences prefs,
    Map<dynamic, dynamic> payloads,
  ) async {
    final decisions = <SyncMergeDecision>[];
    final remoteByCollection = <String, List<Map<String, dynamic>>>{};
    final remoteWorkspaceIdsByCollection = <String, Map<String, String>>{};
    for (final collection in _workspacePayloadCollections.keys) {
      remoteByCollection[collection] = <Map<String, dynamic>>[];
      remoteWorkspaceIdsByCollection[collection] = <String, String>{};
    }

    for (final entry in payloads.entries) {
      final workspaceId = entry.key.toString();
      final payload = entry.value;
      if (payload is! Map) continue;
      for (final collection in _workspacePayloadCollections.keys) {
        final list = payload[collection];
        if (list is! List) continue;
        for (final item in list) {
          if (item is Map && item['id'] != null) {
            final normalized = Map<String, dynamic>.from(item);
            final itemWorkspaceId = normalized['workspaceId']?.toString();
            if (itemWorkspaceId == null ||
                itemWorkspaceId.isEmpty ||
                itemWorkspaceId == 'private') {
              normalized['workspaceId'] = workspaceId;
            }
            final id = normalized['id'].toString();
            remoteWorkspaceIdsByCollection[collection]![id] = workspaceId;
            remoteByCollection[collection]!.add(normalized);
          }
        }
      }
    }

    for (final entry in _workspacePayloadCollections.entries) {
      final collection = entry.key;
      final spec = entry.value;
      final remoteItems = remoteByCollection[collection]!;
      if (remoteItems.isEmpty) continue;
      final merge = _mergeRemoteWorkspaceItems(
        current: _readLocalList(prefs, spec.localKey),
        remote: remoteItems,
        remoteWorkspaceIds: remoteWorkspaceIdsByCollection[collection]!,
        itemType: spec.itemType,
      );
      await _writeLocalList(prefs, spec.localKey, merge.items);
      decisions.addAll(merge.decisions);
    }

    return decisions;
  }

  List<dynamic> _readLocalList(SharedPreferences prefs, String localKey) {
    if (_stringEncodedListKeys.contains(localKey)) {
      final currentRaw = prefs.getString(localKey);
      if (currentRaw == null || currentRaw.isEmpty) return <dynamic>[];
      try {
        final decoded = json.decode(currentRaw);
        return decoded is List ? decoded : <dynamic>[];
      } catch (_) {
        return <dynamic>[];
      }
    }
    return (prefs.getStringList(localKey) ?? const <String>[])
        .map((raw) {
          try {
            return json.decode(raw);
          } catch (_) {
            return null;
          }
        })
        .where((item) => item != null)
        .toList();
  }

  Future<void> _writeLocalList(
    SharedPreferences prefs,
    String localKey,
    Iterable<dynamic> items,
  ) async {
    final list = items.toList(growable: false);
    if (_stringEncodedListKeys.contains(localKey)) {
      await prefs.setString(localKey, json.encode(list));
      return;
    }
    await prefs.setStringList(
      localKey,
      list.map((item) => json.encode(item)).toList(growable: false),
    );
  }

  _WorkspaceMergeResult _mergeRemoteWorkspaceItems({
    required List<dynamic> current,
    required List<Map<String, dynamic>> remote,
    required Map<String, String> remoteWorkspaceIds,
    required String itemType,
  }) {
    final merged = <String, dynamic>{};
    for (final item in current) {
      if (item is Map && item['id'] != null) {
        merged[item['id'].toString()] = item;
      }
    }
    final decisions = <SyncMergeDecision>[];
    for (final item in remote) {
      final id = item['id'].toString();
      final prior = merged[id];
      if (prior is Map) {
        final oldTs = prior['updatedAt']?.toString() ?? '';
        final newTs = item['updatedAt']?.toString() ?? '';
        if (json.encode(prior) != json.encode(item)) {
          final remoteWins = newTs.compareTo(oldTs) >= 0;
          final changedFields = _changedWorkspaceFields(prior, item);
          decisions.add(
            SyncMergeDecision(
              workspaceId: remoteWorkspaceIds[id] ?? '',
              itemType: itemType,
              itemId: id,
              winner: remoteWins ? 'remote' : 'local',
              reason: remoteWins ? '云端更新时间不早于本地' : '本地更新时间更新',
              changedFields: changedFields,
              localUpdatedAt: oldTs,
              remoteUpdatedAt: newTs,
              decidedAt: DateTime.now(),
            ),
          );
          if (remoteWins) merged[id] = item;
        }
      } else {
        merged[id] = item;
        decisions.add(
          SyncMergeDecision(
            workspaceId: remoteWorkspaceIds[id] ?? '',
            itemType: itemType,
            itemId: id,
            winner: 'remote',
            reason: '本地不存在该共享${_itemTypeLabel(itemType)}',
            localUpdatedAt: '',
            remoteUpdatedAt: item['updatedAt']?.toString() ?? '',
            decidedAt: DateTime.now(),
          ),
        );
      }
    }
    return _WorkspaceMergeResult(merged.values.toList(), decisions);
  }

  List<String> _changedWorkspaceFields(
    Map<dynamic, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    final keys = <String>{
      for (final key in local.keys) key.toString(),
      ...remote.keys,
    }..removeAll(const {'id', 'workspaceId', 'createdAt', 'updatedAt'});
    final changed = <String>[];
    for (final key in keys) {
      final localValue = local[key];
      final remoteValue = remote[key];
      if (json.encode(localValue) != json.encode(remoteValue)) {
        changed.add(key);
      }
    }
    changed.sort();
    return changed;
  }

  static const _workspacePayloadCollections = <String, _WorkspacePayloadSpec>{
    'todos': _WorkspacePayloadSpec(localKey: 'todos', itemType: 'todo'),
    'goals': _WorkspacePayloadSpec(localKey: 'duoyi_goals', itemType: 'goal'),
    'calendar_events': _WorkspacePayloadSpec(
      localKey: 'duoyi_local_calendar_events_v1',
      itemType: 'calendar_event',
    ),
  };

  static Map<String, dynamic> _workspaceBucket(
    Map<String, dynamic> result,
    String workspaceId,
  ) {
    return result.putIfAbsent(
          workspaceId,
          () => <String, dynamic>{
            'todos': <dynamic>[],
            'goals': <dynamic>[],
            'courses': <dynamic>[],
            'time_entries': <dynamic>[],
            'calendar_events': <dynamic>[],
          },
        )
        as Map<String, dynamic>;
  }

  static String? _sharedWorkspaceId(Map<dynamic, dynamic> item) {
    final workspaceId = item['workspaceId']?.toString().trim();
    if (workspaceId == null ||
        workspaceId.isEmpty ||
        workspaceId == 'private') {
      return null;
    }
    return workspaceId;
  }

  static String _itemTypeLabel(String itemType) {
    return switch (itemType) {
      'goal' => '目标',
      'calendar_event' => '日程',
      _ => '任务',
    };
  }

  // legacy helper kept for future, but not wired to UI
  Future<Map<String, dynamic>?> rawPost(
    String url,
    Map<String, dynamic> body, {
    required String token,
  }) async {
    final resp = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode(body),
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>?;
    }
    return null;
  }
}
