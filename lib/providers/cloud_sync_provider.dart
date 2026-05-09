import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/feature_flags.dart';
import '../services/api_client.dart';

class SyncConfig {
  final DateTime lastSync;
  final bool autoSync;

  const SyncConfig({
    required this.lastSync,
    this.autoSync = true,
  });
}

/// 云同步：服务器地址与 token 直接复用 AuthProvider(普通用户无需感知)。
/// 登录后自动同步；用户可在"我的"里点"立即同步"。
class CloudSyncProvider extends ChangeNotifier {
  SyncConfig _config = SyncConfig(
    lastSync: DateTime.fromMillisecondsSinceEpoch(0),
    autoSync: true,
  );
  bool _isSyncing = false;
  String? _lastError;

  VoidCallback? onSynced;

  // 由 main.dart 注入(通过 AuthProvider 取活跃的 ApiClient)
  ApiClient? Function()? apiClientGetter;

  /// 可选：返回当前服务端 /api/config，用来判断 backup_enabled
  Map<String, dynamic>? Function()? serverConfigGetter;

  SyncConfig get config => _config;
  bool get isSyncing => _isSyncing;
  String? get lastError => _lastError;
  bool get hasEverSynced => _config.lastSync.millisecondsSinceEpoch > 0;

  /// 是否有未同步到后端的本地改动（由 Provider 写入时打上时间戳；本次同步成功后清零）。
  /// 对应 Requirement 12.7 —— UI 侧可据此显示小角标提醒用户。
  bool _hasPendingChanges = false;
  bool get hasPendingChanges => _hasPendingChanges;

  /// 由外部（Provider 的 addListener）在本地数据发生变动后调用，
  /// 标记"有未同步改动"，以便 UI 角标显示。
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

  static const _stringEncodedListKeys = <String>{
    'todos',
    'habits',
    'pomodoro_sessions',
  };

  static const _listPayloads = <String, String>{
    'todos': 'todos',
    'habits': 'habits',
    'pomodoro_sessions': 'pomodoro_sessions',
    'duoyi_notes': 'notes',
    'duoyi_countdowns': 'countdowns',
    'duoyi_anniversaries_v2': 'anniversaries',
    'duoyi_diary': 'diaries',
    'duoyi_goals': 'goals',
    'duoyi_courses': 'courses',
  };

  static const _objectPayloads = <String, String>{
    'pomodoro_config': 'pomodoro_config',
    'user_profile': 'user_profile',
    'duoyi_course_settings': 'course_settings',
  };

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncStr = prefs.getString('sync_last_time');
    final lastSync = lastSyncStr != null
        ? DateTime.parse(lastSyncStr)
        : DateTime.fromMillisecondsSinceEpoch(0);
    final autoSync = prefs.getBool('sync_auto') ?? true;
    _config = SyncConfig(lastSync: lastSync, autoSync: autoSync);
    notifyListeners();
  }

  Future<void> setAutoSync(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_auto', value);
    _config = SyncConfig(lastSync: _config.lastSync, autoSync: value);
    notifyListeners();
  }

  Future<void> syncNow() async {
    // Req 12.6：关闭 cloud_sync_v2 时完全离线可用，不发出任何网络请求。
    if (!FeatureFlags.cloudSyncV2) {
      return;
    }
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

      final response = await client.post('/api/sync', payload);

      for (final entry in _listPayloads.entries) {
        final remoteKey = entry.value;
        final localKey = entry.key;
        final value = response[remoteKey];
        if (value is! List) continue;
        if (_stringEncodedListKeys.contains(localKey)) {
          await prefs.setString(localKey, json.encode(value));
        } else {
          await prefs.setStringList(
            localKey,
            value.map((e) => json.encode(e)).toList(),
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

      final now = DateTime.now();
      _config = SyncConfig(lastSync: now, autoSync: _config.autoSync);
      await prefs.setString('sync_last_time', now.toIso8601String());
      _hasPendingChanges = false; // Req 12.7: 同步成功后清零"未同步"标记

      onSynced?.call();
    } catch (e) {
      _lastError = e.toString();
    }

    _isSyncing = false;
    notifyListeners();
  }

  // legacy helper kept for future, but not wired to UI
  Future<Map<String, dynamic>?> rawPost(String url, Map<String, dynamic> body,
      {required String token}) async {
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
