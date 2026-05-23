import 'dart:convert';
import 'dart:io';

import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/screens/admin_screen.dart';
import 'package:duoyi/services/admin_api.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  test(
    'Admin large-data tabs keep stable refresh state and ignore stale loads',
    () {
      final source = File('lib/screens/admin_screen.dart').readAsStringSync();

      expect(source, contains('class _AdminInlineLoadingIndicator'));
      expect(source, contains("label: '正在更新当前页'"));
      expect(source, contains("label: '正在更新反馈列表'"));
      expect(source, contains("text: '许愿与反馈'"));
      expect(source, contains("tooltip: '刷新当前页'"));
      expect(source, contains('final loadSerial = ++_loadSerial;'));
      expect(
        RegExp(r'int _loadSerial = 0;').allMatches(source).length,
        greaterThanOrEqualTo(5),
      );
      expect(
        source,
        contains('if (!mounted || loadSerial != _loadSerial) return;'),
      );
      expect(
        source,
        contains('if (mounted && loadSerial == _loadSerial) setState'),
      );
    },
  );

  testWidgets('Admin feedback tab lists feedback and paginates', (
    tester,
  ) async {
    final requests = <String>[];
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        final query = request.url.query.isEmpty ? '' : '?${request.url.query}';
        requests.add('${request.method} ${request.url.path}$query');
        if (request.method == 'GET' &&
            request.url.path == '/api/admin/feedback') {
          final offset =
              int.tryParse(request.url.queryParameters['offset'] ?? '0') ?? 0;
          return http.Response(
            json.encode({
              'items': [
                {
                  'id': 7,
                  'username': 'tester',
                  'email': 'tester@example.com',
                  'email_verified': true,
                  'display_name': '测试同学',
                  'category': 'bug',
                  'content': offset == 0 ? '通知没有声音' : '第二页反馈',
                  'status': 'open',
                  'admin_reply': '',
                },
                if (offset == 0)
                  {
                    'id': 8,
                    'username': 'tester',
                    'email': 'tester@example.com',
                    'email_verified': false,
                    'display_name': '',
                    'category': 'feature',
                    'content': '希望支持批量处理',
                    'status': 'in_progress',
                    'admin_reply': '处理中',
                  },
              ],
              'total': 25,
              'limit':
                  int.tryParse(request.url.queryParameters['limit'] ?? '20') ??
                  20,
              'offset': offset,
              'has_more': offset == 0,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _FakeAuthProvider(
          state: const AuthState(
            userId: 'admin',
            username: 'admin',
            token: 'admin-token',
            isAdmin: true,
          ),
          client: client,
        ),
        child: const MaterialApp(home: AdminScreen(initialTabIndex: 6)),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.textContaining('测试同学', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('@tester', skipOffstage: false), findsWidgets);
    expect(
      find.textContaining('tester@example.com (已验证)', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining('tester@example.com (未验证)', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.textContaining('问题反馈', skipOffstage: false), findsWidgets);
    expect(find.textContaining('通知没有声音', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('第 1-2 条 / 共 25 条'), findsWidgets);
    expect(find.textContaining('本页 2 条 · 待处理 1'), findsOneWidget);
    expect(find.text('本页待处理转处理中'), findsOneWidget);
    expect(find.text('本页处理中转已解决'), findsOneWidget);
    expect(find.byTooltip('回复', skipOffstage: false), findsNWidgets(2));
    expect(find.byTooltip('删除', skipOffstage: false), findsNWidgets(2));

    final nextPageButton = find.descendant(
      of: find.byKey(const ValueKey('admin_feedback_pagination')),
      matching: find.widgetWithText(FilledButton, '下一页'),
    );
    await tester.ensureVisible(nextPageButton);
    await tester.tap(nextPageButton);
    await tester.pumpAndSettle();

    expect(
      requests,
      contains('GET /api/admin/feedback?sort=created_desc&limit=20&offset=0'),
    );
    expect(
      requests,
      contains('GET /api/admin/feedback?sort=created_desc&limit=20&offset=20'),
    );
  });

  testWidgets('Admin feedback tab bulk-updates current page open feedback', (
    tester,
  ) async {
    final requests = <String>[];
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        final query = request.url.query.isEmpty ? '' : '?${request.url.query}';
        requests.add('${request.method} ${request.url.path}$query');
        if (request.method == 'GET' &&
            request.url.path == '/api/admin/feedback') {
          return http.Response(
            json.encode({
              'items': [
                {
                  'id': 7,
                  'username': 'tester',
                  'email': 'tester@example.com',
                  'email_verified': true,
                  'display_name': '测试同学',
                  'category': 'bug',
                  'content': '通知没有声音',
                  'status': 'open',
                  'admin_reply': '',
                },
                {
                  'id': 8,
                  'username': 'tester',
                  'email': 'tester@example.com',
                  'email_verified': true,
                  'display_name': '测试同学',
                  'category': 'feature',
                  'content': '希望支持批量处理',
                  'status': 'in_progress',
                  'admin_reply': '处理中',
                },
              ],
              'total': 2,
              'limit': 20,
              'offset': 0,
              'has_more': false,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/admin/feedback/bulk-status') {
          final body = json.decode(request.body) as Map<String, dynamic>;
          expect(body['feedback_ids'], [7]);
          expect(body['status'], 'in_progress');
          return http.Response(
            json.encode({'status': 'ok', 'updated': 1}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _FakeAuthProvider(
          state: const AuthState(
            userId: 'admin',
            username: 'admin',
            token: 'admin-token',
            isAdmin: true,
          ),
          client: client,
        ),
        child: const MaterialApp(home: AdminScreen(initialTabIndex: 6)),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('本页待处理转处理中'));
    await tester.pumpAndSettle();

    expect(requests, contains('POST /api/admin/feedback/bulk-status'));
  });

  test('AdminApi user export includes online filter', () async {
    final requests = <String>[];
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        final query = request.url.query.isEmpty ? '' : '?${request.url.query}';
        requests.add('${request.method} ${request.url.path}$query');
        expect(request.url.queryParameters['online'], 'true');
        expect(request.url.queryParameters['status'], isNull);
        return http.Response(
          'user_id,username\nuser-a,user-a\n',
          200,
          headers: {'content-type': 'text/csv'},
        );
      }),
    );

    final csv = await AdminApi(
      client,
    ).exportUsersCsv(online: true, sort: 'created_desc');

    expect(csv, contains('user-a'));
    expect(
      requests,
      contains(
        'GET /api/admin/users/export.csv?online=true&sort=created_desc&limit=5000',
      ),
    );
  });

  testWidgets('Admin users tab bulk-disables selected users', (tester) async {
    final requests = <String>[];
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        final query = request.url.query.isEmpty ? '' : '?${request.url.query}';
        requests.add('${request.method} ${request.url.path}$query');
        if (request.method == 'GET' && request.url.path == '/api/admin/users') {
          return http.Response(
            json.encode({
              'items': [
                {
                  'user_id': 'admin',
                  'username': 'admin',
                  'email': 'admin@example.com',
                  'email_verified': true,
                  'display_name': '',
                  'is_admin': true,
                  'is_disabled': false,
                  'created_at': '2026-05-20 00:00:00',
                  'last_login_at': '2026-05-20 00:00:00',
                  'last_active_at': '2026-05-20 00:00:00',
                  'feedback_count': 0,
                  'online': true,
                },
                {
                  'user_id': 'user-a',
                  'username': 'user-a',
                  'email': 'a@example.com',
                  'email_verified': false,
                  'display_name': 'A',
                  'is_admin': false,
                  'is_disabled': false,
                  'created_at': '2026-05-20 00:00:00',
                  'last_login_at': null,
                  'last_active_at': null,
                  'feedback_count': 2,
                  'online': true,
                },
              ],
              'total': 2,
              'limit': 20,
              'offset': 0,
              'has_more': false,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/admin/users/bulk-status') {
          final body = json.decode(request.body) as Map<String, dynamic>;
          expect(body['user_ids'], ['user-a']);
          expect(body['is_disabled'], true);
          return http.Response(
            json.encode({'status': 'ok', 'updated': 1}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _FakeAuthProvider(
          state: const AuthState(
            userId: 'admin',
            username: 'admin',
            token: 'admin-token',
            isAdmin: true,
          ),
          client: client,
        ),
        child: const MaterialApp(home: AdminScreen(initialTabIndex: 4)),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '在线'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选本页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('批量禁用'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('禁用').last);
    await tester.pumpAndSettle();

    expect(
      requests,
      contains(
        'GET /api/admin/users?online=true&sort=created_desc&limit=20&offset=0',
      ),
    );
    expect(requests, contains('POST /api/admin/users/bulk-status'));
  });
}

class _FakeAuthProvider extends AuthProvider {
  final AuthState _fakeState;
  final ApiClient _fakeClient;

  _FakeAuthProvider({required AuthState state, required ApiClient client})
    : _fakeState = state,
      _fakeClient = client;

  @override
  AuthState get state => _fakeState;

  @override
  ApiClient get client => _fakeClient;
}
