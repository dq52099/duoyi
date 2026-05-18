import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 跨平台 HTTP 封装(web/android/linux 通用)。
class ApiClient {
  String baseUrl;
  String? token;
  final http.Client _httpClient;

  ApiClient({this.baseUrl = '', this.token, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  Future<Map<String, dynamic>> get(String path) => _send('GET', path);
  Future<Map<String, dynamic>> post(String path, [Object? body]) =>
      _send('POST', path, body: body);
  Future<Map<String, dynamic>> patch(String path, [Object? body]) =>
      _send('PATCH', path, body: body);
  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);

  Future<List<dynamic>> getList(String path) async {
    final res = await _sendRaw('GET', path);
    if (res is List) return res;
    return const [];
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
  }) async {
    final raw = await _sendRaw(method, path, body: body);
    if (raw is Map<String, dynamic>) return raw;
    return <String, dynamic>{};
  }

  Future<dynamic> _sendRaw(String method, String path, {Object? body}) async {
    // baseUrl 为空时走相对路径(web 前后端同域反代)；
    // 移动端固定构建时注入的 url。
    if (baseUrl.isEmpty && !kIsWeb) {
      throw const ApiException(
        '当前安装包未配置服务器地址，公告、登录和云同步不可用。请在构建时注入 DUOYI_SERVER_URL。',
      );
    }
    final uri = baseUrl.isEmpty ? Uri.parse(path) : Uri.parse('$baseUrl$path');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    http.Response resp;
    final encoded = body == null ? null : json.encode(body);
    try {
      switch (method) {
        case 'GET':
          resp = await _httpClient
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 12));
          break;
        case 'POST':
          resp = await _httpClient
              .post(uri, headers: headers, body: encoded)
              .timeout(const Duration(seconds: 12));
          break;
        case 'PATCH':
          resp = await _httpClient
              .patch(uri, headers: headers, body: encoded)
              .timeout(const Duration(seconds: 12));
          break;
        case 'DELETE':
          resp = await _httpClient
              .delete(uri, headers: headers, body: encoded)
              .timeout(const Duration(seconds: 12));
          break;
        default:
          throw ApiException('不支持的方法: $method');
      }
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('连接服务器超时：${_serverLabel(uri)}');
    } catch (e) {
      throw ApiException(
        '无法连接服务器 ${_serverLabel(uri)}：${_friendlyNetworkError(uri, e)}',
      );
    }

    final raw = utf8.decode(resp.bodyBytes, allowMalformed: true);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      if (raw.isEmpty) return const <String, dynamic>{};
      return json.decode(raw);
    }
    String detail = raw;
    try {
      final m = json.decode(raw);
      if (m is Map && m['detail'] != null) detail = m['detail'].toString();
    } catch (_) {}
    throw ApiException('${resp.statusCode}: $detail');
  }

  String _serverLabel(Uri uri) {
    if (uri.host.isEmpty) return uri.toString();
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  String _friendlyNetworkError(Uri uri, Object error) {
    if (uri.host == 'duoyi.example.com') {
      return '当前仍是示例服务器地址，请在 GitHub Actions 或本地构建中配置 DUOYI_SERVER_URL。';
    }
    final text = error.toString();
    if (text.contains('Failed host lookup')) return '域名无法解析';
    if (text.contains('Connection refused')) return '服务器拒绝连接';
    if (text.contains('No route to host')) return '网络不可达';
    return text;
  }
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => message;
}
