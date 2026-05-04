import 'dart:convert';
import 'dart:io';

/// Tiny HTTP wrapper around dart:io HttpClient so we don't need to add
/// http/dio. All endpoints under our Python backend.
class ApiClient {
  String baseUrl;
  String? token;

  ApiClient({this.baseUrl = '', this.token});

  Future<Map<String, dynamic>> get(String path) => _send('GET', path);
  Future<Map<String, dynamic>> post(String path, [Object? body]) =>
      _send('POST', path, body: body);

  Future<List<dynamic>> getList(String path) async {
    final res = await _sendRaw('GET', path);
    if (res is List) return res;
    return const [];
  }

  Future<Map<String, dynamic>> _send(String method, String path, {Object? body}) async {
    final raw = await _sendRaw(method, path, body: body);
    if (raw is Map<String, dynamic>) return raw;
    return {};
  }

  Future<dynamic> _sendRaw(String method, String path, {Object? body}) async {
    if (baseUrl.isEmpty) {
      throw const ApiException('未配置后端地址');
    }
    final uri = Uri.parse('$baseUrl$path');
    final client = HttpClient();
    try {
      final req = await client.openUrl(method, uri);
      req.headers.set('Content-Type', 'application/json');
      if (token != null && token!.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $token');
      }
      if (body != null) req.write(json.encode(body));
      final resp = await req.close();
      final raw = await resp.transform(utf8.decoder).join();
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        if (raw.isEmpty) return const <String, dynamic>{};
        return json.decode(raw);
      }
      String detail = '';
      try {
        final m = json.decode(raw);
        if (m is Map && m['detail'] != null) detail = m['detail'].toString();
      } catch (_) {
        detail = raw;
      }
      throw ApiException('${resp.statusCode}: $detail');
    } finally {
      client.close();
    }
  }
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => message;
}
