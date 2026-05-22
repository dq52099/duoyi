import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_service.dart';

class WebDavBackupConfig {
  final String baseUrl;
  final String username;
  final String password;
  final String remotePath;
  final String filename;

  const WebDavBackupConfig({
    required this.baseUrl,
    required this.username,
    required this.password,
    this.remotePath = '/duoyi-backups',
    this.filename = 'duoyi-latest.json',
  });

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  Map<String, String> toPrefs() => {
    'webdav_backup_base_url': baseUrl,
    'webdav_backup_username': username,
    'webdav_backup_password': password,
    'webdav_backup_remote_path': remotePath,
    'webdav_backup_filename': filename,
  };

  factory WebDavBackupConfig.empty() =>
      const WebDavBackupConfig(baseUrl: '', username: '', password: '');

  factory WebDavBackupConfig.fromPrefs(SharedPreferences prefs) {
    return WebDavBackupConfig(
      baseUrl: prefs.getString('webdav_backup_base_url') ?? '',
      username: prefs.getString('webdav_backup_username') ?? '',
      password: prefs.getString('webdav_backup_password') ?? '',
      remotePath:
          prefs.getString('webdav_backup_remote_path') ?? '/duoyi-backups',
      filename:
          prefs.getString('webdav_backup_filename') ?? 'duoyi-latest.json',
    );
  }
}

class WebDavBackupResult {
  final Uri uri;
  final int statusCode;
  final int bytes;

  const WebDavBackupResult({
    required this.uri,
    required this.statusCode,
    required this.bytes,
  });
}

class WebDavBackupService {
  final http.Client _client;

  WebDavBackupService({http.Client? client})
    : _client = client ?? http.Client();

  static Future<WebDavBackupConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return WebDavBackupConfig.fromPrefs(prefs);
  }

  static Future<void> saveConfig(WebDavBackupConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in config.toPrefs().entries) {
      await prefs.setString(entry.key, entry.value);
    }
  }

  Future<WebDavBackupResult> uploadCurrentBackup(
    WebDavBackupConfig config,
  ) async {
    _validate(config);
    await _ensureCollection(config);
    final body = await BackupService.exportAll();
    final bytes = utf8.encode(body);
    final uri = uploadUri(config);
    final response = await _client.put(
      uri,
      headers: {
        ..._authHeaders(config),
        'content-type': 'application/json; charset=utf-8',
      },
      body: bytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('WebDAV 上传失败: HTTP ${response.statusCode}');
    }
    return WebDavBackupResult(
      uri: uri,
      statusCode: response.statusCode,
      bytes: bytes.length,
    );
  }

  Future<String> downloadLatestBackup(WebDavBackupConfig config) async {
    _validate(config);
    final uri = uploadUri(config);
    final response = await _client.get(uri, headers: _authHeaders(config));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('WebDAV 下载失败: HTTP ${response.statusCode}');
    }
    return utf8.decode(response.bodyBytes);
  }

  Future<void> _ensureCollection(WebDavBackupConfig config) async {
    final uri = collectionUri(config);
    final response = await _client.send(
      http.Request('MKCOL', uri)..headers.addAll(_authHeaders(config)),
    );
    if (response.statusCode == 201 ||
        response.statusCode == 200 ||
        response.statusCode == 405) {
      return;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw StateError('WebDAV 目录创建失败: HTTP ${response.statusCode}');
  }

  static Uri collectionUri(WebDavBackupConfig config) {
    return _join(config.baseUrl, config.remotePath);
  }

  static Uri uploadUri(WebDavBackupConfig config) {
    final filename = _sanitizeSegment(config.filename, 'duoyi-latest.json');
    return _join(config.baseUrl, '${config.remotePath}/$filename');
  }

  static Uri _join(String baseUrl, String path) {
    final base = Uri.parse(baseUrl.trim().replaceAll(RegExp(r'/+$'), ''));
    final cleaned = path.trim().isEmpty ? '/' : path.trim();
    final segments = cleaned
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .map((segment) => _sanitizeSegment(segment, 'backup'))
        .toList();
    return base.replace(pathSegments: [...base.pathSegments, ...segments]);
  }

  static String _sanitizeSegment(String value, String fallback) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return fallback;
    return trimmed.replaceAll(RegExp(r'[\\/]'), '-');
  }

  static Map<String, String> _authHeaders(WebDavBackupConfig config) {
    if (config.username.trim().isEmpty && config.password.isEmpty) {
      return const <String, String>{};
    }
    final token = base64Encode(
      utf8.encode('${config.username}:${config.password}'),
    );
    return {'authorization': 'Basic $token'};
  }

  static void _validate(WebDavBackupConfig config) {
    final uri = Uri.tryParse(config.baseUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('请输入有效的 WebDAV URL');
    }
  }
}
