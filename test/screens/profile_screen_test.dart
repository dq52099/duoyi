import 'dart:convert';

import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/profile_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('local profile removes avatar URL editor', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final userProvider = UserProvider();
    await userProvider.updateProfile(
      username: '旧昵称',
      displayName: '旧显示名',
      email: 'old@example.com',
      avatarUrl: 'https://example.com/old.png',
      bio: '旧简介',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录账号'), findsOneWidget);
    expect(find.text('头像 URL、本地文件或文字'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '选择'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, '显示名'), '新显示名');
    await tester.enterText(find.widgetWithText(TextField, '本地昵称'), '新昵称');
    await tester.enterText(
      find.widgetWithText(TextField, '邮箱（仅本地展示，不用于登录或找回）'),
      'new@example.com',
    );
    await tester.enterText(find.widgetWithText(TextField, '简介'), '新的个人简介');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(userProvider.profile.username, '新昵称');
    expect(userProvider.profile.displayName, '新显示名');
    expect(userProvider.profile.avatarUrl, 'https://example.com/old.png');
    expect(userProvider.profile.email, 'new@example.com');
    expect(userProvider.profile.bio, '新的个人简介');
  });

  testWidgets('account profile keeps username/avatar stable and binds email', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final requestBodies = <Map<String, dynamic>>[];
    final emailCodeRequests = <Map<String, dynamic>>[];
    var serverEmail = 'old@example.com';
    var serverEmailVerified = true;
    final auth = AuthProvider(
      initialState: const AuthState(
        userId: 'u-1',
        username: 'old-user',
        email: 'old@example.com',
        emailVerified: true,
        displayName: '旧昵称',
        avatar: 'https://example.com/old.png',
        bio: '旧简介',
        coinBalance: 88,
        lifetimeCoins: 144,
        token: 'token-1',
      ),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token-1',
        httpClient: MockClient((request) async {
          if (request.method == 'PATCH' &&
              request.url.path == '/api/auth/profile') {
            final body = json.decode(request.body) as Map<String, dynamic>;
            requestBodies.add(body);
            if (body.containsKey('email')) {
              serverEmail = (body['email'] ?? '').toString();
              serverEmailVerified = body.containsKey('email_code');
            }
            return http.Response(
              json.encode({
                'user_id': 'u-1',
                'username': 'old-user',
                'email': serverEmail,
                'email_verified': serverEmailVerified,
                'display_name': body['display_name'] ?? '旧昵称',
                'avatar': 'https://example.com/old.png',
                'bio': body['bio'] ?? '旧简介',
                'coin_balance': 88,
                'lifetime_coins': 144,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'POST' &&
              request.url.path == '/api/auth/email-code') {
            final body = json.decode(request.body) as Map<String, dynamic>;
            emailCodeRequests.add(body);
            return http.Response(
              json.encode({'message': '验证码已发送，请查收邮箱'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        }),
      ),
    );
    final userProvider = UserProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AchievementProvider()),
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('时光币 88'), findsOneWidget);
    expect(find.text('头像 URL 或文字'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '上传'), findsNothing);
    final usernameField = tester.widget<TextField>(
      find.widgetWithText(TextField, '用户名'),
    );
    expect(usernameField.readOnly, isTrue);

    await tester.enterText(find.widgetWithText(TextField, '昵称'), '新昵称');
    expect(find.text('邮箱绑定'), findsOneWidget);
    expect(find.widgetWithText(TextField, '邮箱'), findsNothing);
    expect(find.widgetWithText(TextField, '邮箱验证码'), findsNothing);
    expect(find.text('账号安全'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '简介'), '新的账号简介');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(requestBodies.removeAt(0), {'display_name': '新昵称', 'bio': '新的账号简介'});
    expect(auth.state.username, 'old-user');
    expect(auth.state.avatar, 'https://example.com/old.png');

    await tester.tap(find.text('old@example.com'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '邮箱'),
      'new@example.com',
    );
    await tester.enterText(find.widgetWithText(TextField, '邮箱验证码'), '123456');
    await tester.tap(find.text('发送'));
    await tester.pump();
    expect(emailCodeRequests.single, {
      'email': 'new@example.com',
      'purpose': 'bind',
    });
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(requestBodies.single, {
      'email': 'new@example.com',
      'email_code': '123456',
    });
    expect(auth.state.email, 'new@example.com');
    expect(auth.state.emailVerified, isTrue);
  });
}
