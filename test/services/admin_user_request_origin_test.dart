import 'dart:async';
import 'dart:convert';

import 'package:duoyi/services/admin_api.dart';
import 'package:duoyi/services/admin_response_error.dart';
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
  }

  for (final operation in _heldResponseOperations) {
    for (final status in [200, 404, 403]) {
      test(
        '$operation rejects held $status after expiration without diagnosis or fallback',
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
          response.complete(_responseFor(operation, status));
          await expired;

          expect(requests, hasLength(1));
          expect(requests.single.url.path, isNot('/api/config'));
          expect(requests.single.url.path, isNot('/api/admin/user-groups'));
          expect(requests.single.url.path, isNot('/api/admin/user_groups'));
          expect(requests.single.url.path, isNot('/api/admin/userGroups'));
        },
      );
    }
  }

  test(
    'users page preserves current filters, pagination, and response fields',
    () async {
      final api = _api((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/admin/users');
        expect(request.url.queryParameters, {
          'q': 'alice example',
          'status': 'disabled',
          'online': 'false',
          'sort': 'coins_desc',
          'limit': '17',
          'offset': '34',
        });
        return _json({
          'items': [
            {'user_id': 'user-7', 'username': 'alice'},
          ],
          'total': 60,
          'limit': 17,
          'offset': 34,
          'has_more': true,
        });
      });

      final page = await api.listUsersPage(
        query: 'alice example',
        status: 'disabled',
        online: false,
        sort: 'coins_desc',
        limit: 17,
        offset: 34,
        isCurrent: () => true,
      );

      expect(page.items.single['user_id'], 'user-7');
      expect(page.total, 60);
      expect(page.limit, 17);
      expect(page.offset, 34);
      expect(page.hasMore, isTrue);
    },
  );

  test(
    'listUsers compatibility wrapper keeps the 100 item first page',
    () async {
      final api = _api((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/admin/users');
        expect(request.url.queryParameters, {
          'q': 'alice',
          'limit': '100',
          'offset': '0',
        });
        return _json({
          'items': [
            {'user_id': 'user-7', 'username': 'alice'},
          ],
          'total': 1,
        });
      });

      final users = await api.listUsers(query: 'alice', isCurrent: () => true);
      expect(users, hasLength(1));
      expect(users.single['username'], 'alice');
    },
  );

  test('user writes preserve primary routes and payload fields', () async {
    final requests = <http.Request>[];
    final api = _api((request) async {
      requests.add(request);
      return _json({
        'id': 'user-7',
        'balance': 125,
        'lifetime': 225,
        'server_version': 3,
      });
    });

    await api.createUser(
      username: 'alice',
      password: '  secret  ',
      displayName: '  Alice Example  ',
      email: ' alice@example.test ',
      groupId: ' group-2 ',
      roleId: ' role-3 ',
      isAdmin: true,
      isDisabled: false,
      adminPermissions: const ['users.read', 'users.edit'],
      isCurrent: () => true,
    );
    await api.updateUser(
      'user-7',
      isAdmin: false,
      isDisabled: true,
      newPassword: ' new secret ',
      groupId: 'group-4',
      roleId: 'role-5',
      adminPermissions: const ['users.read'],
      isCurrent: () => true,
    );
    await api.setUserAdminPermissions(
      'user-7',
      permissions: const ['users.read', 'groups.read'],
      isCurrent: () => true,
    );
    await api.deleteUser('user-7', isCurrent: () => true);
    await api.bulkUpdateUserStatus(
      userIds: const ['user-7', 'user-8'],
      isDisabled: true,
      isCurrent: () => true,
    );

    expect(requests.map((request) => '${request.method} ${request.url.path}'), [
      'POST /api/admin/users',
      'PATCH /api/admin/users/user-7',
      'PATCH /api/admin/users/user-7',
      'DELETE /api/admin/users/user-7',
      'POST /api/admin/users/bulk-status',
    ]);
    expect(jsonDecode(requests[0].body), {
      'username': 'alice',
      'is_admin': true,
      'is_disabled': false,
      'password': 'secret',
      'display_name': 'Alice Example',
      'email': 'alice@example.test',
      'group_id': 'group-2',
      'role_id': 'role-3',
      'admin_permissions': ['users.read', 'users.edit'],
    });
    expect(jsonDecode(requests[1].body), {
      'is_admin': false,
      'is_disabled': true,
      'new_password': ' new secret ',
      'group_id': 'group-4',
      'role_id': 'role-5',
      'admin_permissions': ['users.read'],
    });
    expect(jsonDecode(requests[2].body), {
      'admin_permissions': ['users.read', 'groups.read'],
    });
    expect(requests[3].body, isEmpty);
    expect(jsonDecode(requests[4].body), {
      'user_ids': ['user-7', 'user-8'],
      'is_disabled': true,
    });
  });

  test('CSV export preserves all filters and limit', () async {
    final api = _api((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/admin/users/export.csv');
      expect(request.url.queryParameters, {
        'q': 'alice, bob',
        'status': 'active',
        'online': 'false',
        'sort': 'created_desc',
        'limit': '321',
      });
      expect(request.headers['accept'], 'text/plain, text/csv');
      return http.Response(
        'user_id,username\nuser-7,alice\n',
        200,
        headers: const {'content-type': 'text/csv'},
      );
    });

    expect(
      await api.exportUsersCsv(
        query: 'alice, bob',
        status: 'active',
        online: false,
        sort: 'created_desc',
        limit: 321,
        isCurrent: () => true,
      ),
      'user_id,username\nuser-7,alice\n',
    );
  });

  test(
    'guarded paged groups preserve page parameters across aliases',
    () async {
      final requests = <http.Request>[];
      final api = _api((request) async {
        requests.add(request);
        expect(request.url.queryParameters, {'limit': '11', 'offset': '22'});
        if (request.url.path == '/api/admin/groups') {
          return _json({'detail': 'Not Found'}, 404);
        }
        return _json({
          'items': [
            {'id': 'group-7', 'name': 'Example'},
          ],
          'total': 1,
          'limit': 11,
          'offset': 22,
        });
      });

      final page = await api.listGroupsPage(
        limit: 11,
        offset: 22,
        isCurrent: () => true,
      );
      expect(page.items.single['id'], 'group-7');
      expect(requests.map((request) => request.url.path), [
        '/api/admin/groups',
        '/api/admin/user-groups',
      ]);
    },
  );

  test(
    'listGroups keeps the 500 item auxiliary request and all aliases',
    () async {
      final requests = <http.Request>[];
      final rows = [
        for (var index = 0; index < 500; index++)
          {'id': 'group-$index', 'name': 'Group $index'},
      ];
      final api = _api((request) async {
        requests.add(request);
        expect(request.method, 'GET');
        expect(request.url.queryParameters, {'limit': '500', 'offset': '0'});
        if (request.url.path == '/api/admin/userGroups') {
          return _json({'items': rows});
        }
        return _json({'detail': 'Not Found'}, 404);
      });

      final groups = await api.listGroups(isCurrent: () => true);

      expect(groups, hasLength(500));
      expect(groups.first['id'], 'group-0');
      expect(groups.last['id'], 'group-499');
      expect(requests.map((request) => request.url.path), [
        '/api/admin/groups',
        '/api/admin/user-groups',
        '/api/admin/user_groups',
        '/api/admin/userGroups',
      ]);
    },
  );

  test('listRoles keeps the current primary route and object list', () async {
    final api = _api((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/admin/roles');
      expect(request.url.query, isEmpty);
      return _json([
        {'id': 'role-1', 'name': 'Operator'},
      ]);
    });

    final roles = await api.listRoles(isCurrent: () => true);
    expect(roles.single['name'], 'Operator');
  });

  test('coin adjustment uses one primary POST and trims its reason', () async {
    final requests = <http.Request>[];
    final api = _api((request) async {
      requests.add(request);
      return _json({'balance': 125, 'lifetime': 225, 'server_version': 3});
    });

    final result = await api.adjustUserCoins(
      'user-7',
      delta: -25,
      reason: '  correction  ',
      isCurrent: () => true,
    );

    expect(result['balance'], 125);
    expect(result['lifetime'], 225);
    expect(result['server_version'], 3);
    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/api/admin/users/user-7/coins');
    expect(jsonDecode(requests.single.body), {
      'delta': -25,
      'reason': 'correction',
    });
  });

  for (final missingField in ['balance', 'lifetime', 'server_version']) {
    test('coin adjustment rejects a response missing $missingField', () async {
      final requests = <http.Request>[];
      final body = <String, Object>{
        'balance': 125,
        'lifetime': 225,
        'server_version': 3,
      }..remove(missingField);
      final api = _api((request) async {
        requests.add(request);
        return _json(body);
      });

      await expectLater(
        api.adjustUserCoins('user-7', delta: 25, isCurrent: () => true),
        throwsA(
          isA<AdminResponseException>().having(
            (error) => error.failure,
            'failure',
            AdminResponseFailure.missingCoinBalance,
          ),
        ),
      );
      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/api/admin/users/user-7/coins');
    });
  }

  test('coin adjustment rejects nonnumeric balance fields', () async {
    final requests = <http.Request>[];
    final api = _api((request) async {
      requests.add(request);
      return _json({'balance': '125', 'lifetime': 225, 'server_version': 3});
    });

    await expectLater(
      api.adjustUserCoins('user-7', delta: 25, isCurrent: () => true),
      throwsA(
        isA<AdminResponseException>().having(
          (error) => error.failure,
          'failure',
          AdminResponseFailure.missingCoinBalance,
        ),
      ),
    );
    expect(requests, hasLength(1));
  });

  test('unguarded CSV export retains legacy missing-route diagnosis', () async {
    final requests = <String>[];
    final api = _api((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.url.path == '/api/config') {
        return _json({'version': 'legacy'});
      }
      return _json({'detail': 'Not Found'}, 404);
    });

    await expectLater(
      api.exportUsersCsv(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('当前后端未部署本版本接口：/api/admin/users/export.csv'),
        ),
      ),
    );
    expect(requests, ['GET /api/admin/users/export.csv', 'GET /api/config']);
  });
}

const _guardedOperations = <String>[
  'users-page',
  'users-list',
  'user-create',
  'user-update',
  'user-permissions',
  'user-delete',
  'user-coins',
  'users-export',
  'users-bulk-status',
  'groups-page',
  'groups-list',
  'roles-list',
];

const _heldResponseOperations = <String>[..._guardedOperations];

Future<Object?> _invoke(
  AdminApi api,
  String operation,
  bool Function() isCurrent,
) async {
  switch (operation) {
    case 'users-page':
      return api.listUsersPage(isCurrent: isCurrent);
    case 'users-list':
      return api.listUsers(query: 'alice', isCurrent: isCurrent);
    case 'user-create':
      return api.createUser(username: 'alice', isCurrent: isCurrent);
    case 'user-update':
      return api.updateUser('user-7', isDisabled: true, isCurrent: isCurrent);
    case 'user-permissions':
      await api.setUserAdminPermissions(
        'user-7',
        permissions: const ['users.read'],
        isCurrent: isCurrent,
      );
      return null;
    case 'user-delete':
      await api.deleteUser('user-7', isCurrent: isCurrent);
      return null;
    case 'user-coins':
      return api.adjustUserCoins('user-7', delta: 1, isCurrent: isCurrent);
    case 'users-export':
      return api.exportUsersCsv(isCurrent: isCurrent);
    case 'users-bulk-status':
      await api.bulkUpdateUserStatus(
        userIds: const ['user-7'],
        isDisabled: true,
        isCurrent: isCurrent,
      );
      return null;
    case 'groups-page':
      return api.listGroupsPage(isCurrent: isCurrent);
    case 'groups-list':
      return api.listGroups(isCurrent: isCurrent);
    case 'roles-list':
      return api.listRoles(isCurrent: isCurrent);
    default:
      throw ArgumentError.value(operation, 'operation');
  }
}

http.Response _responseFor(String operation, int status) {
  if (status != 200) {
    return _json({'detail': status == 404 ? 'Not Found' : 'Forbidden'}, status);
  }
  return switch (operation) {
    'users-page' ||
    'users-list' ||
    'groups-page' => _json({'items': <Object?>[], 'total': 0}),
    'groups-list' || 'roles-list' => _json(<Object?>[]),
    'users-export' => http.Response('user_id,username\n', status),
    'user-coins' => _json({'balance': 1, 'lifetime': 1, 'server_version': 1}),
    _ => _json({'id': 'user-7'}),
  };
}

AdminApi _api(Future<http.Response> Function(http.Request) handler) {
  final transport = MockClient(handler);
  addTearDown(transport.close);
  return AdminApi(
    ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'synthetic-admin-token',
      httpClient: transport,
    ),
  );
}

http.Response _json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: const {'content-type': 'application/json'},
);
