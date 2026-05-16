/// CalDAV 写回基础接口（v2 占位）。
///
/// 当前实现仅声明协议契约 + 一个未启用的 HTTP 实现。完整的 OAuth 流程
/// 需要为每个供应商单独申请 client_id（Google）/ tenant（Microsoft），
/// 不在本期范围内。开放接口便于未来按需挂接。
library;

import 'package:http/http.dart' as http;

abstract class CalDavWriter {
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
  });

  /// 删除 VEVENT。
  Future<void> deleteEvent(String uid);
}

/// 通用 CalDAV HTTP 写回实现。
///
/// 调用方需要提供：
/// - `collectionUrl` — 用户日历集合的完整 URL（如
///   `https://caldav.example.com/calendars/user@example.com/default/`）；
/// - `headers` — 已经包含 Authorization 的请求头（OAuth Bearer / Basic Auth
///   由调用方处理）。
///
/// 注意：本类**未在生产路径启用**。需要使用时在 IntegrationsScreen 加配置
/// 入口并把它注入 CalendarSyncProvider 的写回流程。
class HttpCalDavWriter implements CalDavWriter {
  final String collectionUrl;
  final Map<String, String> headers;
  final http.Client client;

  HttpCalDavWriter({
    required this.collectionUrl,
    Map<String, String>? headers,
    http.Client? client,
  })  : headers = headers ?? const <String, String>{},
        client = client ?? http.Client();

  String _eventUrl(String uid) {
    final base = collectionUrl.endsWith('/')
        ? collectionUrl
        : '$collectionUrl/';
    return '$base$uid.ics';
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
  Future<String> createEvent({
    required String summary,
    required DateTime start,
    required DateTime end,
    String? description,
    String? location,
  }) async {
    final uid = 'duoyi-${DateTime.now().millisecondsSinceEpoch}'
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
      headers: {
        'Content-Type': 'text/calendar; charset=utf-8',
        ...headers,
      },
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
      headers: {
        'Content-Type': 'text/calendar; charset=utf-8',
        ...headers,
      },
      body: ics,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('CalDAV update failed: ${resp.statusCode} ${resp.body}');
    }
  }

  @override
  Future<void> deleteEvent(String uid) async {
    final resp = await client.delete(
      Uri.parse(_eventUrl(uid)),
      headers: headers,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('CalDAV delete failed: ${resp.statusCode} ${resp.body}');
    }
  }
}
