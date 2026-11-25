import 'dart:async';
import 'dart:convert';

import 'package:duoyi/services/admin_api.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final operation in ['create', 'edit', 'delete', 'read']) {
    test('$operation refuses an already expired interaction', () async {
      final requests = <String>[];
      final api = _api((request) async {
        requests.add(request.url.path);
        return _json({});
      });
      await expectLater(
        _invoke(api, operation, () => false),
        throwsA(isA<AdminActionExpired>()),
      );
      expect(requests, isEmpty);
    });

    for (final status in [200, 404, 403]) {
      test('$operation drops late $status and cannot retry', () async {
        var current = true;
        final requests = <String>[];
        final response = Completer<http.Response>();
        final started = Completer<void>();
        final api = _api((request) {
          requests.add('${request.method} ${request.url.path}');
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
                : {'detail': status == 404 ? 'Not Found' : 'Forbidden'},
            status,
          ),
        );
        await rejected;
        expect(requests, hasLength(1));
      });
    }
  }

  test('current edit keeps PATCH then PUT compatibility', () async {
    final requests = <String>[];
    final api = _api((request) async {
      requests.add('${request.method} ${request.url.path}');
      return request.method == 'PATCH'
          ? _json({'detail': 'Not Found'}, 404)
          : _json({'id': 'group-synthetic'});
    });
    final result = await api.saveGroup(
      id: 'group-synthetic',
      name: 'literal',
      isCurrent: () => true,
    );
    expect(result['id'], 'group-synthetic');
    expect(requests, [
      'PATCH /api/admin/groups/group-synthetic',
      'PUT /api/admin/groups/group-synthetic',
    ]);
  });

  test('current delete keeps alias compatibility', () async {
    final requests = <String>[];
    final api = _api((request) async {
      requests.add('${request.method} ${request.url.path}');
      return requests.length == 1
          ? _json({'detail': 'Not Found'}, 404)
          : _json({'reassigned_users': 2});
    });
    final result = await api.deleteGroup('literal', isCurrent: () => true);
    expect(result['reassigned_users'], 2);
    expect(requests, [
      'DELETE /api/admin/groups/literal',
      'DELETE /api/admin/user-groups/literal',
    ]);
  });

  test(
    'guarded read keeps aliases and page parameters without diagnosis',
    () async {
      final paths = <String>[];
      final api = _api((request) async {
        paths.add(request.url.path);
        expect(request.url.queryParameters, {'limit': '10', 'offset': '20'});
        return paths.length == 1
            ? _json({'detail': 'Not Found'}, 404)
            : _json({'items': [], 'total': 20, 'limit': 10, 'offset': 20});
      });
      final page = await api.listGroupsPage(
        limit: 10,
        offset: 20,
        isCurrent: () => true,
      );
      expect(page.offset, 20);
      expect(paths, ['/api/admin/groups', '/api/admin/user-groups']);
    },
  );

  test('current server rejection is retained and never retried', () async {
    var requests = 0;
    final api = _api((request) async {
      requests++;
      return _json({'detail': 'literal diagnostic'}, 403);
    });
    await expectLater(
      api.saveGroup(name: 'literal', isCurrent: () => true),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('literal diagnostic'),
        ),
      ),
    );
    expect(requests, 1);
  });
}

AdminApi _api(Future<http.Response> Function(http.Request) handler) => AdminApi(
  ApiClient(
    baseUrl: 'https://duoyi.test',
    token: 'synthetic-admin',
    httpClient: MockClient(handler),
  ),
);

http.Response _json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

Future<Object?> _invoke(
  AdminApi api,
  String operation,
  bool Function() guard,
) => switch (operation) {
  'create' => api.saveGroup(name: 'literal', isCurrent: guard),
  'edit' => api.saveGroup(id: 'literal', name: 'literal', isCurrent: guard),
  'delete' => api.deleteGroup('literal', isCurrent: guard),
  _ => api.listGroupsPage(isCurrent: guard),
};
