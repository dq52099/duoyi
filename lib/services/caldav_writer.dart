/// CalDAV 写回基础接口。
///
/// 当前实现提供通用 HTTP CalDAV 写回能力，调用方负责提供日历集合 URL
/// 与已准备好的 Authorization 头。Google / Outlook OAuth 只读同步由
/// `CalendarSyncService` 处理；iCloud / 通用 CalDAV 写回通过本接口完成。
library;

import 'package:http/http.dart' as http;

abstract class CalDavWriter {
  /// 返回远端 VEVENT 的 ETag；服务器不支持或事件不存在时返回 null。
  Future<String?> remoteEtag(String uid);

  /// 创建一条 VEVENT，返回新事件的 UID。
  Future<String> createEvent({
    required String summary,
    required DateTime start,
    required DateTime end,
    String? description,
    String? location,
  });

  /// 更新已存在的 VEVENT。
  Future<void> updateEvent({
    required String uid,
    required String summary,
    required DateTime start,
    required DateTime end,
    String? description,
    String? location,
    String? ifMatch,
  });

  /// 删除 VEVENT。
  Future<void> deleteEvent(String uid, {String? ifMatch});
}

/// 通用 CalDAV HTTP 写回实现。
///
/// 调用方需要提供：
/// - `collectionUrl` — 用户日历集合的完整 URL（如
///   `https://caldav.example.com/calendars/user@example.com/default/`）；
/// - `headers` — 已经包含 Authorization 的请求头（OAuth Bearer / Basic Auth
///   由调用方处理）。
///
/// IntegrationsScreen 可保存写回目标，导出页会通过 CalendarSyncService
/// 注入本 writer 完成写回、ETag 探测和远端冲突跳过。
class HttpCalDavWriter implements CalDavWriter {
  final String collectionUrl;
  final Map<String, String> headers;
  final http.Client client;

  HttpCalDavWriter({
    required this.collectionUrl,
    Map<String, String>? headers,
    http.Client? client,
  }) : headers = headers ?? const <String, String>{},
       client = client ?? http.Client();

  String _eventUrl(String uid) {
    final base = collectionUrl.endsWith('/')
        ? collectionUrl
        : '$collectionUrl/';
    return '$base$uid.ics';
  }

  String? _etag(http.Response resp) {
    final value = resp.headers['etag'] ?? resp.headers['ETag'];
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  Map<String, String> _requestHeaders({String? contentType, String? ifMatch}) {
    final out = <String, String>{...headers};
    if (contentType != null) out['Content-Type'] = contentType;
    if (ifMatch != null) out['If-Match'] = ifMatch;
    return out;
  }

  String _buildIcs({
    required String uid,
    required String summary,
    required DateTime start,
    required DateTime end,
    String? description,
    String? location,
  }) {
    String fmt(DateTime d) {
      String two(int v) => v.toString().padLeft(2, '0');
      final utc = d.toUtc();
      return '${utc.year}${two(utc.month)}${two(utc.day)}'
          'T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
    }

    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Duoyi//CalDavWriter//EN',
      'BEGIN:VEVENT',
      'UID:$uid',
      'SUMMARY:${_escape(summary)}',
      'DTSTART:${fmt(start)}',
      'DTEND:${fmt(end)}',
      if (description != null) 'DESCRIPTION:${_escape(description)}',
      if (location != null) 'LOCATION:${_escape(location)}',
      'END:VEVENT',
      'END:VCALENDAR',
    ];
    return lines.join('\r\n');
  }

  String _escape(String s) {
    return s
        .replaceAll(r'\\', r'\\\\')
        .replaceAll(';', r'\;')
        .replaceAll(',', r'\,')
        .replaceAll('\n', r'\n');
  }

  @override
  Future<String?> remoteEtag(String uid) async {
    final url = Uri.parse(_eventUrl(uid));
    final resp = await client.head(url, headers: headers);
    if (resp.statusCode == 404) return null;
    if (resp.statusCode == 405) {
      final fallback = await client.get(url, headers: headers);
      if (fallback.statusCode == 404) return null;
      if (fallback.statusCode < 200 || fallback.statusCode >= 300) {
        throw Exception(
          'CalDAV GET fallback failed: ${fallback.statusCode} ${fallback.body}',
        );
      }
      return _etag(fallback);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('CalDAV HEAD failed: ${resp.statusCode} ${resp.body}');
    }
    return _etag(resp);
  }

  @override
  Future<String> createEvent({
    required String summary,
    required DateTime start,
    required DateTime end,
    String? description,
    String? location,
  }) async {
    final uid =
        'duoyi-${DateTime.now().millisecondsSinceEpoch}'
        '@duoyi.local';
    final ics = _buildIcs(
      uid: uid,
      summary: summary,
      start: start,
      end: end,
      description: description,
      location: location,
    );
    final resp = await client.put(
      Uri.parse(_eventUrl(uid)),
      headers: _requestHeaders(contentType: 'text/calendar; charset=utf-8'),
      body: ics,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('CalDAV create failed: ${resp.statusCode} ${resp.body}');
    }
    return uid;
  }

  @override
  Future<void> updateEvent({
    required String uid,
    required String summary,
    required DateTime start,
    required DateTime end,
    String? description,
    String? location,
    String? ifMatch,
  }) async {
    final ics = _buildIcs(
      uid: uid,
      summary: summary,
      start: start,
      end: end,
      description: description,
      location: location,
    );
    final resp = await client.put(
      Uri.parse(_eventUrl(uid)),
      headers: _requestHeaders(
        contentType: 'text/calendar; charset=utf-8',
        ifMatch: ifMatch,
      ),
      body: ics,
    );
    if (resp.statusCode == 412) {
      throw CalDavConflictException(uid);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('CalDAV update failed: ${resp.statusCode} ${resp.body}');
    }
  }

  @override
  Future<void> deleteEvent(String uid, {String? ifMatch}) async {
    final resp = await client.delete(
      Uri.parse(_eventUrl(uid)),
      headers: _requestHeaders(ifMatch: ifMatch),
    );
    if (resp.statusCode == 404) return;
    if (resp.statusCode == 412) {
      throw CalDavConflictException(uid);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('CalDAV delete failed: ${resp.statusCode} ${resp.body}');
    }
  }
}

class CalDavConflictException implements Exception {
  final String uid;

  const CalDavConflictException(this.uid);

  @override
  String toString() => 'CalDAV conflict: $uid was changed remotely';
}
