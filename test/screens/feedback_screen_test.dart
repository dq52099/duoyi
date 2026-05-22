import 'dart:convert';

import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/screens/feedback_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('FeedbackScreen shows logged-out state without network', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        auth: _FakeAuthProvider(
          state: const AuthState(),
          client: ApiClient(
            baseUrl: 'https://duoyi.test',
            httpClient: MockClient((_) async {
              fail('未登录状态不应请求反馈接口');
            }),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('功能建议'), findsWidgets);
    expect(find.text('登录后提交功能建议'), findsOneWidget);
    expect(find.text('登录后可查看反馈记录'), findsWidgets);
    final submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '提交反馈'),
    );
    expect(submit.onPressed, isNull);
  });

  testWidgets('FeedbackScreen initialCategory opens independent modes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        screen: const FeedbackScreen(initialCategory: 'bug'),
        auth: _FakeAuthProvider(
          state: const AuthState(),
          client: ApiClient(
            baseUrl: 'https://duoyi.test',
            httpClient: MockClient((_) async {
              fail('未登录状态不应请求反馈接口');
            }),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('问题反馈'), findsWidgets);
    expect(find.text('登录后提交问题反馈'), findsOneWidget);
    expect(find.text('功能建议'), findsOneWidget);
    expect(find.text('许愿池'), findsOneWidget);
    expect(find.text('反馈与许愿'), findsNothing);
  });

  testWidgets('FeedbackScreen loads history and submits feedback', (
    tester,
  ) async {
    final requests = <String>[];
    final bodies = <Map<String, dynamic>>[];
    var getCount = 0;
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'token',
      httpClient: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.method == 'GET' && request.url.path == '/api/feedback/me') {
          getCount++;
          return http.Response(
            json.encode([
              {
                'id': 1,
                'category': 'bug',
                'content': getCount == 1 ? '通知没有声音' : '小组件想要月历',
                'status': getCount == 1 ? 'in_progress' : 'open',
                'admin_reply': getCount == 1 ? '已加入排查' : '',
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' && request.url.path == '/api/feedback') {
          bodies.add(json.decode(request.body) as Map<String, dynamic>);
          return http.Response(
            json.encode({'id': 2}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      _wrap(
        screen: const FeedbackScreen(),
        auth: _FakeAuthProvider(
          state: const AuthState(
            userId: 'u1',
            username: 'tester',
            token: 'token',
          ),
          client: client,
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('提交功能建议'), findsOneWidget);
    expect(find.text('通知没有声音'), findsOneWidget);
    expect(find.text('管理员回复'), findsOneWidget);
    expect(find.text('已加入排查'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '小组件想要月历');
    await tester.tap(find.widgetWithText(FilledButton, '提交反馈'));
    await tester.pumpAndSettle();

    expect(requests, <String>[
      'GET /api/feedback/me',
      'POST /api/feedback',
      'GET /api/feedback/me',
    ]);
    expect(bodies.single['category'], 'feature');
    expect(bodies.single['content'], '小组件想要月历');
    expect(find.text('反馈已提交，感谢！'), findsOneWidget);
    expect(find.text('小组件想要月历'), findsOneWidget);
  });
}

Widget _wrap({
  required AuthProvider auth,
  Widget screen = const FeedbackScreen(),
}) {
  return ChangeNotifierProvider<AuthProvider>.value(
    value: auth,
    child: MaterialApp(home: screen),
  );
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
