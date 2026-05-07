import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SyncConfig {
  final String serverUrl;
  final String token;
  final DateTime lastSync;
  final bool autoSync;

  const SyncConfig({
    this.serverUrl = '',
    this.token = '',
    required this.lastSync,
    this.autoSync = false,
  });
}

class CloudSyncProvider extends ChangeNotifier {
  SyncConfig _config = SyncConfig(
    lastSync: DateTime.fromMillisecondsSinceEpoch(0),
  );
  bool _isSyncing = false;

  SyncConfig get config => _config;
  bool get isSyncing => _isSyncing;

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('sync_server_url') ?? '';
    final token = prefs.getString('sync_token') ?? '';
    final lastSyncStr = prefs.getString('sync_last_time');
    final lastSync = lastSyncStr != null
        ? DateTime.parse(lastSyncStr)
        : DateTime.fromMillisecondsSinceEpoch(0);
    final autoSync = prefs.getBool('sync_auto') ?? false;

    _config = SyncConfig(
      serverUrl: url,
      token: token,
      lastSync: lastSync,
      autoSync: autoSync,
    );
    notifyListeners();
  }

  Future<void> configure({
    required String serverUrl,
    required String token,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sync_server_url', serverUrl);
    await prefs.setString('sync_token', token);
    _config = SyncConfig(
      serverUrl: serverUrl,
      token: token,
      lastSync: _config.lastSync,
      autoSync: _config.autoSync,
    );
    notifyListeners();
  }

  Future<void> syncNow() async {
    if (_config.serverUrl.isEmpty || _config.token.isEmpty) return;
    _isSyncing = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final todos = prefs.getString('todos') ?? '[]';
      final habits = prefs.getString('habits') ?? '[]';

      final response = await _httpPost('${_config.serverUrl}/api/sync', {
        'todos': json.decode(todos),
        'habits': json.decode(habits),
      });

      if (response != null) {
        if (response['todos'] != null) {
          await prefs.setString('todos', json.encode(response['todos']));
        }
        if (response['habits'] != null) {
          await prefs.setString('habits', json.encode(response['habits']));
        }
      }

      final now = DateTime.now();
      _config = SyncConfig(
        serverUrl: _config.serverUrl,
        token: _config.token,
        lastSync: now,
        autoSync: _config.autoSync,
      );
      await prefs.setString('sync_last_time', now.toIso8601String());
    } catch (_) {}

    _isSyncing = false;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> _httpPost(
    String url,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse(url);
    final httpClient = HttpClient();
    try {
      final request = await httpClient.postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Authorization', 'Bearer ${_config.token}');
      request.write(json.encode(body));
      final response = await request.close();
      if (response.statusCode == 200) {
        final data = await response.transform(utf8.decoder).join();
        return json.decode(data);
      }
    } finally {
      httpClient.close();
    }
    return null;
  }
}
