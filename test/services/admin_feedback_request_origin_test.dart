import 'dart:async';
import 'dart:convert';

import 'package:duoyi/services/admin_api.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final operation in _guardedOperations) {
    test('$operation rejects an expired action before dispatch', () async {
      final requests = <http.Request>[];
      final api = _api((request) async {
        requests.add(request);
        return _responseFor(operation, 200);
      });

      await expectLater(
        _invoke(api, operation, () => false),
        throwsA(isA<AdminActionExpired>()),
      );
      expect(requests, isEmpty);
    });

    for (final outcome in const ['200', '403', '404', '500', 'transport']) {
      test(
        '$operation rejects a held $outcome after expiration without HTTP diagnostics',
        () async {
          var current = true;
          final requests = <http.Request>[];
          final dispatched = Completer<void>();
          final response = Completer<http.Response>();
          final api = _api((request) {
            requests.add(request);
            if (!dispatched.isCompleted) dispatched.complete();
            return response.future;
          });

          final pending = _invoke(api, operation, () => current);
          final expired = expectLater(
            pending,
            throwsA(isA<AdminActionExpired>()),
          );
          await dispatched.future;
          current = false;
          if (outcome == 'transport') {
            response.completeError(StateError('synthetic transport failure'));
          } else {
            response.complete(_responseFor(operation, int.parse(outcome)));
          }

          await expired;
          expect(requests, hasLength(1));
          expect(requests.single.url.path, startsWith('/api/admin/feedback'));
          expect(
            requests.where((request) => request.url.path == '/api/config'),
            isEmpty,
          );
        },
      );
    }

    for (final status in const [403, 404, 500]) {
      test('$operation preserves current HTTP $status errors', () async {
        final requests = <http.Request>[];
        final api = _api((request) async {
          requests.add(request);
          return _json({'detail': 'literal feedback rejection'}, status);
        });

        await expectLater(
          _invoke(api, operation, () => true),
          throwsA(
            isA<ApiException>().having(
              (error) => error.message,
              'message',
              contains('literal feedback rejection'),
            ),
          ),
        );
        expect(requests, hasLength(1));
        expect(requests.single.url.path, startsWith('/api/admin/feedback'));
        expect(
          requests.where((request) => request.url.path == '/api/config'),
          isEmpty,
        );
      });
    }
  }

  test('feedback page preserves filters, sorting, and pagination', () async {
    final api = _api((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/admin/feedback');
      expect(request.url.queryParameters, {
        'status': 'open',
        'q': 'literal title 原文',
        'category': 'suggestion',
        'sort': 'created_desc',
        'limit': '17',
        'offset': '34',
      });
      return _json({
        'items': [
          {'id': 42, 'title': 'literal title 原文'},
        ],
        'total': 60,
        'limit': 17,
        'offset': 34,
        'has_more': true,
      });
    });

    final page = await api.listFeedbackPage(
      status: 'open',
      query: 'literal title 原文',
      category: 'suggestion',
      sort: 'created_desc',
      limit: 17,
      offset: 34,
      isCurrent: () => true,
    );
    expect(page.items.single['id'], 42);
    expect(page.total, 60);
    expect(page.limit, 17);
    expect(page.offset, 34);
    expect(page.hasMore, isTrue);
  });

  test('legacy listFeedback keeps its guarded 100-row first page', () async {
    final api = _api((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/admin/feedback');
      expect(request.url.queryParameters, {
        'status': 'pending',
        'limit': '100',
        'offset': '0',
      });
      return _json({
        'items': [
          {'id': 7, 'status': 'pending'},
        ],
        'total': 1,
      });
    });

    final rows = await api.listFeedback(
      status: 'pending',
      isCurrent: () => true,
    );
    expect(rows.single['id'], 7);
  });

  test('feedback detail forwards its guard to the exact route', () async {
    final api = _api((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/admin/feedback/42');
      return _json({'id': 42, 'content': 'literal detail'});
    });

    final detail = await api.getFeedbackDetail(42, isCurrent: () => true);
    expect(detail['content'], 'literal detail');
  });

  test('feedback writes keep defaults and send one request each', () async {
    final requests = <http.Request>[];
    final api = _api((request) async {
      requests.add(request);
      return _json({'status': 'ok'});
    });
    final feedbackIds = List<int>.generate(101, (index) => index + 1);

    await api.replyFeedback(
      feedbackId: 42,
      reply: 'literal reply',
      isCurrent: () => true,
    );
    await api.bulkUpdateFeedbackStatus(
      feedbackIds: feedbackIds,
      reply: 'literal bulk reply',
      isCurrent: () => true,
    );
    await api.closeFeedback(43, isCurrent: () => true);
    await api.deleteFeedback(44, isCurrent: () => true);

    expect(requests.map((request) => '${request.method} ${request.url.path}'), [
      'POST /api/admin/feedback/reply',
      'POST /api/admin/feedback/bulk-status',
      'POST /api/admin/feedback/bulk-status',
      'DELETE /api/admin/feedback/44',
    ]);
    expect(jsonDecode(requests[0].body), {
      'feedback_id': 42,
      'reply': 'literal reply',
      'status': 'resolved',
    });
    expect(jsonDecode(requests[1].body), {
      'feedback_ids': feedbackIds,
      'reply': 'literal bulk reply',
      'status': 'in_progress',
    });
    expect(jsonDecode(requests[2].body), {
      'feedback_ids': [43],
      'reply': '已关闭。',
      'status': 'closed',
    });
    expect(requests[3].body, isEmpty);
  });

  test(
    'feedback CSV export preserves filters, default limit, and existing UTF-8 decoding',
    () async {
      final api = _api((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/admin/feedback/export.csv');
        expect(request.url.queryParameters, {
          'status': 'open',
          'q': 'literal title 原文',
          'category': 'suggestion',
          'sort': 'created_asc',
          'limit': '5000',
        });
        expect(request.headers['accept'], 'text/plain, text/csv');
        return http.Response.bytes(
          utf8.encode('\uFEFFid,title\n42,literal title 原文\n'),
          200,
          headers: const {'content-type': 'text/csv; charset=utf-8'},
        );
      });

      final csv = await api.exportFeedbackCsv(
        status: 'open',
        query: 'literal title 原文',
        category: 'suggestion',
        sort: 'created_asc',
        isCurrent: () => true,
      );
      // ApiClient.getText uses utf8.decode, which consumes the leading BOM.
      expect(csv, 'id,title\n42,literal title 原文\n');
      expect(csv.startsWith('\uFEFF'), isFalse);
    },
  );

  test('feedback CSV export forwards a custom limit', () async {
    final api = _api((request) async {
      expect(request.url.path, '/api/admin/feedback/export.csv');
      expect(request.url.queryParameters, {
        'category': 'bug',
        'sort': 'created_desc',
        'limit': '321',
      });
      return http.Response('id\n', 200);
    });

    expect(
      await api.exportFeedbackCsv(
        category: 'bug',
        sort: 'created_desc',
        limit: 321,
        isCurrent: () => true,
      ),
      'id\n',
    );
  });
}

const _guardedOperations = [
  'listFeedbackPage',
  'listFeedback',
  'getFeedbackDetail',
  'replyFeedback',
  'bulkUpdateFeedbackStatus',
  'closeFeedback',
  'exportFeedbackCsv',
  'deleteFeedback',
];

AdminApi _api(Future<http.Response> Function(http.Request) handler) {
  final transport = MockClient(handler);
  addTearDown(transport.close);
  return AdminApi(
    ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'synthetic-admin',
      httpClient: transport,
    ),
  );
}

Future<Object?> _invoke(
  AdminApi api,
  String operation,
  bool Function() guard,
) => switch (operation) {
  'listFeedbackPage' => api.listFeedbackPage(isCurrent: guard),
  'listFeedback' => api.listFeedback(isCurrent: guard),
  'getFeedbackDetail' => api.getFeedbackDetail(42, isCurrent: guard),
  'replyFeedback' => api.replyFeedback(
    feedbackId: 42,
    reply: 'literal reply',
    isCurrent: guard,
  ),
  'bulkUpdateFeedbackStatus' => api.bulkUpdateFeedbackStatus(
    feedbackIds: const [42, 43],
    reply: 'literal reply',
    isCurrent: guard,
  ),
  'closeFeedback' => api.closeFeedback(42, isCurrent: guard),
  'exportFeedbackCsv' => api.exportFeedbackCsv(isCurrent: guard),
  'deleteFeedback' => api.deleteFeedback(42, isCurrent: guard),
  _ => throw ArgumentError.value(operation, 'operation'),
};

http.Response _responseFor(String operation, int status) {
  if (status != 200) {
    return _json({'detail': 'literal feedback rejection'}, status);
  }
  if (operation == 'exportFeedbackCsv') {
    return http.Response(
      '\uFEFFid\n',
      status,
      headers: const {'content-type': 'text/csv; charset=utf-8'},
    );
  }
  if (operation == 'listFeedbackPage' || operation == 'listFeedback') {
    return _json({'items': [], 'total': 0}, status);
  }
  return _json({'id': 42}, status);
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);
