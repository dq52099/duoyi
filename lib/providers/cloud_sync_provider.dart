import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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

  SyncConfig get config => _config;
  bool get isSyncing => _isSyncing;
  String? get lastError => _lastError;
  bool get hasEverSynced => _config.lastSync.millisecondsSinceEpoch > 0;

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
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      _lastError = '请先登录';
      notifyListeners();
      return;
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
