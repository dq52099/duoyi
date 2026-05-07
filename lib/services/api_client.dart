import 'dart:convert';
import 'package:http/http.dart' as http;

/// 跨平台 HTTP 封装(web/android/linux 通用)。
class ApiClient {
  String baseUrl;
  String? token;

  ApiClient({this.baseUrl = '', this.token});

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
    final uri = baseUrl.isEmpty
        ? Uri.parse(path)
        : Uri.parse('$baseUrl$path');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    http.Response resp;
    final encoded = body == null ? null : json.encode(body);
    switch (method) {
      case 'GET':
        resp = await http.get(uri, headers: headers);
        break;
      case 'POST':
        resp = await http.post(uri, headers: headers, body: encoded);
        break;
      case 'PATCH':
        resp = await http.patch(uri, headers: headers, body: encoded);
        break;
      case 'DELETE':
        resp = await http.delete(uri, headers: headers, body: encoded);
        break;
      default:
        throw ApiException('不支持的方法: $method');
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
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => message;
}
