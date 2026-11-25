import 'dart:async';
import 'dart:convert';

import 'package:duoyi/services/admin_api.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('expired Audit page is rejected before dispatch', () async {
    final requests = <http.Request>[];
    final api = _api((request) async {
      requests.add(request);
      return _json({'items': [], 'total': 0});
    });

    await expectLater(
      api.auditLogPage(isCurrent: () => false),
      throwsA(isA<AdminActionExpired>()),
    );
    expect(requests, isEmpty);
  });

  test('legacy auditLog forwards its optional guard before dispatch', () async {
    final requests = <http.Request>[];
    final api = _api((request) async {
      requests.add(request);
      return _json({'items': []});
    });

    await expectLater(
      api.auditLog(action: 'feedback.reply', isCurrent: () => false),
      throwsA(isA<AdminActionExpired>()),
    );
    expect(requests, isEmpty);
  });

  test(
    'held success, 404, and 403 Audit responses expire without diagnosis',
    () async {
      for (final status in [200, 404, 403]) {
        var current = true;
        final requests = <http.Request>[];
        final started = Completer<void>();
        final response = Completer<http.Response>();
        final api = _api((request) {
          requests.add(request);
          started.complete();
          return response.future;
        });

        final pending = api.auditLogPage(isCurrent: () => current);
        final rejected = expectLater(
          pending,
          throwsA(isA<AdminActionExpired>()),
        );
        await started.future;
        current = false;
        response.complete(
          _json(
            status == 200
                ? {
                    'items': [
                      {'id': 8, 'action': 'stale.action'},
                    ],
                    'total': 1,
                  }
                : {'detail': status == 404 ? 'Not Found' : 'Forbidden'},
            status,
          ),
        );

        await rejected;
        expect(requests, hasLength(1));
        expect(requests.single.method, 'GET');
        expect(requests.single.url.path, '/api/admin/audit-log');
        expect(
          requests.where((request) => request.url.path == '/api/config'),
          isEmpty,
        );
      }
    },
  );

  test('current Audit rejection stays on its exact endpoint', () async {
    final requests = <http.Request>[];
    final api = _api((request) async {
      requests.add(request);
      return _json({'detail': 'literal audit rejection'}, 404);
    });

    await expectLater(
      api.auditLogPage(isCurrent: () => true),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('literal audit rejection'),
        ),
      ),
    );
    expect(requests.map((request) => request.url.path), [
      '/api/admin/audit-log',
    ]);
  });

  test(
    'guarded Audit page preserves action, query, sort, and paging',
    () async {
      final api = _api((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/admin/audit-log');
        expect(request.url.queryParameters, {
          'action': 'feedback.reply',
          'q': 'literal actor 原文',
          'sort': 'target_asc',
          'limit': '17',
          'offset': '34',
        });
        return _json({
          'items': [
            {'id': 42, 'actor_name': 'literal actor 原文'},
          ],
          'total': 60,
          'limit': 17,
          'offset': 34,
        });
      });

      final page = await api.auditLogPage(
        action: 'feedback.reply',
        query: 'literal actor 原文',
        sort: 'target_asc',
        limit: 17,
        offset: 34,
        isCurrent: () => true,
      );
      expect(page.items.single['actor_name'], 'literal actor 原文');
      expect(page.total, 60);
      expect(page.offset, 34);
      expect(page.hasMore, isTrue);
    },
  );

  test('unguarded legacy Audit read keeps the 100-row default', () async {
    final requests = <http.Request>[];
    final api = _api((request) async {
      requests.add(request);
      expect(request.method, 'GET');
      expect(request.url.path, '/api/admin/audit-log');
      expect(request.url.queryParameters, {
        'action': 'user.update',
        'limit': '100',
        'offset': '0',
      });
      return _json({
        'items': [
          {'id': 1, 'action': 'user.update'},
        ],
        'total': 1,
      });
    });

    final rows = await api.auditLog(action: 'user.update');
    expect(rows.single['action'], 'user.update');
    expect(requests, hasLength(1));
  });
}

AdminApi _api(Future<http.Response> Function(http.Request) handler) {
  final transport = MockClient(handler);
  addTearDown(transport.close);
  return AdminApi(
    ApiClient(baseUrl: 'https://duoyi.test', httpClient: transport),
  );
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);
