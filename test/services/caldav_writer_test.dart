import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:duoyi/services/caldav_writer.dart';

void main() {
  group('HttpCalDavWriter', () {
    test('createEvent 发起 PUT 请求并返回 UID', () async {
      String? putUrl;
      String? putBody;
      final client = MockClient((request) async {
        putUrl = request.url.toString();
        putBody = request.body;
        return http.Response('', 201);
      });
      final writer = HttpCalDavWriter(
        collectionUrl: 'https://example.com/cal/',
        client: client,
      );
      final uid = await writer.createEvent(
        summary: '测试',
        start: DateTime.utc(2026, 5, 18, 10),
        end: DateTime.utc(2026, 5, 18, 11),
      );
      expect(uid, contains('duoyi-'));
      expect(putUrl, startsWith('https://example.com/cal/'));
      expect(putUrl, endsWith('.ics'));
      expect(putBody, contains('BEGIN:VCALENDAR'));
      expect(putBody, contains('SUMMARY:测试'));
      expect(putBody, contains('DTSTART:20260518T100000Z'));
    });

    test('updateEvent 用指定 UID 发起 PUT', () async {
      String? putUrl;
      final client = MockClient((request) async {
        putUrl = request.url.toString();
        return http.Response('', 204);
      });
      final writer = HttpCalDavWriter(
        collectionUrl: 'https://example.com/cal',
        client: client,
      );
      await writer.updateEvent(
        uid: 'event-001',
        summary: '更新后',
        start: DateTime.utc(2026, 5, 18, 10),
        end: DateTime.utc(2026, 5, 18, 11),
      );
      expect(putUrl, 'https://example.com/cal/event-001.ics');
    });

    test('deleteEvent 发起 DELETE', () async {
      String? deleteUrl;
      final client = MockClient((request) async {
        deleteUrl = request.url.toString();
        expect(request.method, 'DELETE');
        return http.Response('', 204);
      });
      final writer = HttpCalDavWriter(
        collectionUrl: 'https://example.com/cal/',
        client: client,
      );
      await writer.deleteEvent('event-001');
      expect(deleteUrl, 'https://example.com/cal/event-001.ics');
    });

    test('非 2xx 响应抛异常', () async {
      final client = MockClient(
        (request) async => http.Response('forbidden', 403),
      );
      final writer = HttpCalDavWriter(
        collectionUrl: 'https://example.com/cal/',
        client: client,
      );
      expect(
        () => writer.deleteEvent('x'),
        throwsA(isA<Exception>()),
      );
    });

    test('特殊字符在 SUMMARY 中转义', () async {
      String? putBody;
      final client = MockClient((request) async {
        putBody = request.body;
        return http.Response('', 201);
      });
      final writer = HttpCalDavWriter(
        collectionUrl: 'https://example.com/cal/',
        client: client,
      );
      await writer.createEvent(
        summary: '带逗号, 分号; 换行\n第二行',
        start: DateTime.utc(2026, 5, 18, 10),
        end: DateTime.utc(2026, 5, 18, 11),
      );
      expect(putBody, contains(r'SUMMARY:带逗号\, 分号\; 换行\n第二行'));
    });
  });
}
