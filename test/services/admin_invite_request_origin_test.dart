import 'dart:async';
import 'dart:convert';

import 'package:duoyi/services/admin_api.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final operation in ['read', 'create', 'delete']) {
    test(
      '$operation rejects an expired invite action before dispatch',
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
      test('$operation rejects late $status without extra requests', () async {
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
            status != 200
                ? {'detail': 'Not Found'}
                : switch (operation) {
                    'read' => {'items': [], 'total': 0},
                    'create' => {
                      'codes': ['INV-LITERAL-NEW'],
                    },
                    _ => {'status': 'ok'},
                  },
            status,
          ),
        );
        await rejected;
        expect(requests, hasLength(1));
        expect(requests.single.url.path, startsWith('/api/admin/invite-codes'));
      });
    }

    test('$operation keeps a current server rejection without retry', () async {
      final requests = <http.Request>[];
      final api = _api((request) async {
        requests.add(request);
        return _json({'detail': 'literal rejection'}, 404);
      });
      await expectLater(
        _invoke(api, operation, () => true),
        throwsA(isA<ApiException>()),
      );
      expect(requests, hasLength(1));
    });
  }

  test('guarded invite GET preserves filters and pagination', () async {
    final api = _api((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/admin/invite-codes');
      expect(request.url.queryParameters, {
        'q': 'literal code',
        'status': 'unused',
        'sort': 'code_asc',
        'limit': '10',
        'offset': '20',
      });
      return _json({
        'items': [
          {'code': 'INV-LITERAL'},
        ],
        'total': 60,
        'limit': 10,
        'offset': 20,
      });
    });
    final page = await api.listInviteCodesPage(
      query: 'literal code',
      status: 'unused',
      sort: 'code_asc',
      limit: 10,
      offset: 20,
      isCurrent: () => true,
    );
    expect(page.items.single['code'], 'INV-LITERAL');
    expect(page.offset, 20);
    expect(page.hasMore, isTrue);
  });

  test(
    'guarded create preserves quantity, literal note and returned codes',
    () async {
      final api = _api((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/admin/invite-codes');
        expect(jsonDecode(request.body), {'count': 7, 'note': '  原文 note  '});
        return _json({
          'codes': ['INV-原文', 'literal-code'],
        });
      });
      expect(
        await api.createInviteCodes(
          count: 7,
          note: '  原文 note  ',
          isCurrent: () => true,
        ),
        ['INV-原文', 'literal-code'],
      );
    },
  );

  test(
    'guarded invite DELETE sends the original route without a body',
    () async {
      var calls = 0;
      final api = _api((request) async {
        calls++;
        expect(request.method, 'DELETE');
        expect(request.url.path, '/api/admin/invite-codes/INV-LITERAL');
        expect(request.body, isEmpty);
        return _json({'status': 'ok'});
      });
      await api.deleteInviteCode('INV-LITERAL', isCurrent: () => true);
      expect(calls, 1);
    },
  );
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
  'read' => api.listInviteCodesPage(isCurrent: current),
  'create' => api.createInviteCodes(
    count: 7,
    note: 'literal',
    isCurrent: current,
  ),
  _ => api.deleteInviteCode('INV-LITERAL', isCurrent: current),
};
