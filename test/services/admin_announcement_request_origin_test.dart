import 'dart:async';
import 'dart:convert';

import 'package:duoyi/services/admin_api.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final operation in ['read', 'create', 'edit', 'delete']) {
    test(
      '$operation rejects an expired announcement action before dispatch',
      () async {
        final requests = <http.Request>[];
        final api = _api((request) async {
          requests.add(request);
          return _json({});
        });
        await expectLater(
          _invoke(api, operation, () => false),
          throwsA(isA<AdminActionExpired>()),
        );
        expect(requests, isEmpty);
      },
    );

    for (final status in [200, 404, 403]) {
      test(
        '$operation rejects late $status without diagnosis or another request',
        () async {
          var current = true;
          final requests = <http.Request>[];
          final started = Completer<void>();
          final response = Completer<http.Response>();
          final api = _api((request) {
            requests.add(request);
            started.complete();
            return response.future;
          });
          final pending = _invoke(api, operation, () => current);
          final rejected = expectLater(
            pending,
            throwsA(isA<AdminActionExpired>()),
          );
          await started.future;
          current = false;
          response.complete(
            _json(
              status == 200 && operation == 'read'
                  ? {'items': [], 'total': 0}
                  : {'id': 42, 'detail': 'Not Found'},
              status,
            ),
          );
          await rejected;
          expect(requests, hasLength(1));
          expect(
            requests.single.url.path,
            startsWith('/api/admin/announcements'),
          );
        },
      );
    }

    test(
      '$operation keeps a current server rejection without automatic write retry',
      () async {
        final paths = <String>[];
        final api = _api((request) async {
          paths.add(request.url.path);
          return _json({'detail': 'literal rejection'}, 404);
        });
        await expectLater(
          _invoke(api, operation, () => true),
          throwsA(isA<ApiException>()),
        );
        expect(paths, hasLength(1));
        expect(paths.single, startsWith('/api/admin/announcements'));
      },
    );
  }

  test('guarded read preserves all filters and pagination fields', () async {
    final api = _api((request) async {
      expect(request.method, 'GET');
      expect(request.url.queryParameters, {
        'q': 'literal title',
        'status': 'draft',
        'level': 'legacy-level',
        'sort': 'title_asc',
        'limit': '10',
        'offset': '20',
      });
      return _json({
        'items': [
          {'id': 42, 'title': 'literal title'},
        ],
        'total': 60,
        'limit': 10,
        'offset': 20,
      });
    });
    final page = await api.listAnnouncementsPage(
      query: 'literal title',
      status: 'draft',
      level: 'legacy-level',
      sort: 'title_asc',
      limit: 10,
      offset: 20,
      isCurrent: () => true,
    );
    expect(page.offset, 20);
    expect(page.total, 60);
    expect(page.hasMore, isTrue);
    expect(page.items.single['id'], 42);
  });

  test(
    'create preserves literal title body and unknown level with a numeric id',
    () async {
      final api = _api((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/admin/announcements');
        expect(jsonDecode(request.body), {
          'title': 'literal title 标题',
          'body': 'literal body 正文',
          'level': 'legacy-level',
          'published': false,
        });
        return _json({'id': 42});
      });
      expect(
        await api.createAnnouncement(
          title: 'literal title 标题',
          body: 'literal body 正文',
          level: 'legacy-level',
          published: false,
          isCurrent: () => true,
        ),
        42,
      );
    },
  );

  test(
    'toggle PATCH sends only published and leaves content untouched',
    () async {
      final api = _api((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/api/admin/announcements/42');
        expect(jsonDecode(request.body), {'published': false});
        return _json({'status': 'ok'});
      });
      await api.updateAnnouncement(42, published: false, isCurrent: () => true);
    },
  );

  test('delete dispatches a single DELETE with no body', () async {
    var calls = 0;
    final api = _api((request) async {
      calls++;
      expect(request.method, 'DELETE');
      expect(request.url.path, '/api/admin/announcements/42');
      expect(request.body, isEmpty);
      return _json({'status': 'ok'});
    });
    await api.deleteAnnouncement(42, isCurrent: () => true);
    expect(calls, 1);
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

Future<Object?> _invoke(
  AdminApi api,
  String operation,
  bool Function() current,
) => switch (operation) {
  'read' => api.listAnnouncementsPage(isCurrent: current),
  'create' => api.createAnnouncement(
    title: 'literal',
    body: 'literal',
    isCurrent: current,
  ),
  'edit' => api.updateAnnouncement(42, published: true, isCurrent: current),
  _ => api.deleteAnnouncement(42, isCurrent: current),
};
