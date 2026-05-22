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
      String? ifMatch;
      final client = MockClient((request) async {
        putUrl = request.url.toString();
        ifMatch = request.headers['If-Match'];
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
        ifMatch: '"etag-1"',
      );
      expect(putUrl, 'https://example.com/cal/event-001.ics');
      expect(ifMatch, '"etag-1"');
    });

    test('deleteEvent 发起 DELETE', () async {
      String? deleteUrl;
      String? ifMatch;
      final client = MockClient((request) async {
        deleteUrl = request.url.toString();
        ifMatch = request.headers['If-Match'];
        expect(request.method, 'DELETE');
        return http.Response('', 204);
      });
      final writer = HttpCalDavWriter(
        collectionUrl: 'https://example.com/cal/',
        client: client,
      );
      await writer.deleteEvent('event-001', ifMatch: '"etag-2"');
      expect(deleteUrl, 'https://example.com/cal/event-001.ics');
      expect(ifMatch, '"etag-2"');
    });

    test('remoteEtag 在 HEAD 不支持时回退 GET 读取 ETag', () async {
      final methods = <String>[];
      final client = MockClient((request) async {
        methods.add(request.method);
        expect(request.url.toString(), 'https://example.com/cal/event-001.ics');
        if (request.method == 'HEAD') {
          return http.Response('', 405);
        }
        expect(request.method, 'GET');
        return http.Response(
          'BEGIN:VCALENDAR',
          200,
          headers: {'etag': '"remote-etag"'},
        );
      });
      final writer = HttpCalDavWriter(
        collectionUrl: 'https://example.com/cal/',
        client: client,
      );

      final etag = await writer.remoteEtag('event-001');

      expect(methods, ['HEAD', 'GET']);
      expect(etag, '"remote-etag"');
    });

    test('412 响应抛 CalDavConflictException', () async {
      final client = MockClient(
        (request) async => http.Response('precondition failed', 412),
      );
      final writer = HttpCalDavWriter(
        collectionUrl: 'https://example.com/cal/',
        client: client,
      );

      await expectLater(
        writer.updateEvent(
          uid: 'event-001',
          summary: '冲突',
          start: DateTime.utc(2026, 5, 18, 10),
          end: DateTime.utc(2026, 5, 18, 11),
          ifMatch: '"old"',
        ),
        throwsA(isA<CalDavConflictException>()),
      );
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
