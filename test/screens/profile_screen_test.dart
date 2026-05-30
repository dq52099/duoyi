import 'dart:convert';
import 'dart:io';

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
    await tester.tap(find.widgetWithText(FilledButton, '保存').last);
    await tester.pumpAndSettle();

    expect(userProvider.profile.username, '旧昵称');
    expect(userProvider.profile.displayName, '新显示名');
    expect(userProvider.profile.avatarUrl, 'https://example.com/old.png');
    expect(userProvider.profile.email, 'new@example.com');
    expect(userProvider.profile.bio, '新的个人简介');
  });

  test('profile email binding uses dedicated compact dialog flow', () {
    final source = File('lib/screens/profile_screen.dart').readAsStringSync();

    final accountBody = source.substring(
      source.indexOf('class _AccountProfileEditor'),
      source.indexOf('class _LocalProfileEditor'),
    );
    expect(source, contains('class _EmailBindingDialog'));
    expect(accountBody, contains('_showEmailBindingDialog'));
    expect(accountBody, isNot(contains('controller: _emailCodeCtrl')));
    expect(accountBody, isNot(contains('action: _sendButton(context)')));
    expect(accountBody, isNot(contains("const Text('绑定')")));
    expect(accountBody, contains("Text(I18n.tr('profile.email.binding'))"));
  });

  test('profile metric chips render their icons', () {
    final source = File('lib/screens/profile_screen.dart').readAsStringSync();
    final metricChip = source.substring(
      source.indexOf('class _ProfileMetricChip'),
      source.indexOf('class _ProfileSectionHeader'),
    );

    expect(metricChip, contains('Icon(icon'));
    expect(metricChip, contains('Semantics('));
    expect(metricChip, contains('Flexible('));
    expect(metricChip, contains('Text('));
  });

  test('profile actions keep fixed compact sizes and save flows editable', () {
    final source = File('lib/screens/profile_screen.dart').readAsStringSync();
    final auth = File('lib/providers/auth_provider.dart').readAsStringSync();

    expect(source, contains('const double _profileActionButtonHeight = 30'));
    expect(source, contains('const double _profileActionButtonWidth = 58'));
    expect(source, contains('const double _profileLongActionButtonWidth = 72'));
    expect(source, contains('double _profileInlineActionWidth'));
    expect(source, contains('width: _profileActionButtonWidth'));
    expect(source, contains('width: _profileLongActionButtonWidth'));
    expect(source, contains('height: _profileActionButtonHeight'));
    expect(source, contains('FittedBox('));
    expect(source, contains("child: Text(I18n.tr('action.save'), maxLines: 1)"));
    expect(
      source,
      contains('titleTextStyle: appSecondaryRouteTitleTextStyle('),
    );
    expect(source, contains(').copyWith(color: Colors.white)'));
    expect(source, contains("I18n.tr('auth.send')"));
    expect(source, contains("I18n.tr('action.save')"));
    expect(source, contains('_showChangePasswordDialog'));
    expect(source, contains('changePassword('));
    expect(source, contains('await auth.updateProfile('));

    expect(auth, contains("'/api/me/profile'"));
    expect(auth, contains("'/api/auth/profile'"));
    expect(auth, contains("'/api/me/password'"));
    expect(auth, contains("'/api/auth/change-password'"));
  });

  test('account profile long email labels are single-line ellipsized', () {
    final source = File('lib/screens/profile_screen.dart').readAsStringSync();
    final accountBody = source.substring(
      source.indexOf('class _AccountProfileEditor'),
      source.indexOf('class _LocalProfileEditor'),
    );

    final headerEmail = accountBody.substring(
      accountBody.indexOf('state.email?.isNotEmpty == true'),
      accountBody.indexOf('const SizedBox(height: 8)'),
    );
    final bindingEmail = accountBody.substring(
      accountBody.indexOf('state.email?.trim().isEmpty != false'),
      accountBody.indexOf('const SizedBox(height: 10)'),
    );

    for (final block in [headerEmail, bindingEmail]) {
      expect(block, contains('maxLines: 1'));
      expect(block, contains('overflow: TextOverflow.ellipsis'));
    }
  });

  testWidgets('local profile avatar opens full screen preview', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final userProvider = UserProvider();
    await userProvider.updateProfile(
      username: '本地用户',
      displayName: '本地显示名',
      avatarUrl: '本',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AchievementProvider()),
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final editRect = tester.getRect(
      find.byKey(const ValueKey('profile_avatar_edit_button')),
    );
    expect(editRect.width, greaterThan(43.5));
    expect(editRect.height, greaterThan(43.5));

    final avatarButton = find.byKey(
      const ValueKey('profile_avatar_preview_button'),
    );
    await tester.tapAt(tester.getTopLeft(avatarButton) + const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('头像'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('account profile keeps username/avatar stable and binds email', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final requestBodies = <Map<String, dynamic>>[];
    final emailCodeRequests = <Map<String, dynamic>>[];
    final passwordRequests = <Map<String, dynamic>>[];
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
              request.url.path == '/api/me/profile') {
            final body = json.decode(request.body) as Map<String, dynamic>;
            requestBodies.add(body);
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
              request.url.path == '/api/me/email-code') {
            final body = json.decode(request.body) as Map<String, dynamic>;
            emailCodeRequests.add(body);
            return http.Response(
              json.encode({'message': '验证码已发送，请查收邮箱'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'PATCH' &&
              request.url.path == '/api/me/email') {
            final body = json.decode(request.body) as Map<String, dynamic>;
            requestBodies.add(body);
            serverEmail = (body['email'] ?? '').toString();
            serverEmailVerified = body.containsKey('code');
            return http.Response(
              json.encode({
                'user_id': 'u-1',
                'username': 'old-user',
                'email': serverEmail,
                'email_verified': serverEmailVerified,
                'display_name': '新昵称',
                'avatar': 'https://example.com/old.png',
                'bio': '新的账号简介',
                'coin_balance': 88,
                'lifetime_coins': 144,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'POST' &&
              request.url.path == '/api/auth/change-password') {
            final body = json.decode(request.body) as Map<String, dynamic>;
            passwordRequests.add(body);
            return http.Response(
              json.encode({'ok': true}),
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
    expect(find.text('邮箱绑定'), findsAtLeastNWidgets(1));
    expect(find.widgetWithText(TextField, '邮箱'), findsNothing);
    expect(find.widgetWithText(TextField, '邮箱验证码'), findsNothing);
    expect(find.text('账号安全'), findsOneWidget);
    expect(find.text('修改登录密码'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '简介'), '新的账号简介');
    await tester.tap(find.widgetWithText(FilledButton, '保存').last);
    await tester.pumpAndSettle();

    expect(requestBodies.removeAt(0), {'display_name': '新昵称', 'bio': '新的账号简介'});
    expect(auth.state.username, 'old-user');
    expect(auth.state.avatar, 'https://example.com/old.png');

    await tester.tap(find.widgetWithText(TextButton, '邮箱绑定'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '邮箱'), findsOneWidget);
    expect(find.widgetWithText(TextField, '邮箱验证码'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, '邮箱'),
      'new@example.com',
    );
    await tester.enterText(find.widgetWithText(TextField, '邮箱验证码'), '123456');
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pump();
    expect(emailCodeRequests.single, {
      'email': 'new@example.com',
      'purpose': 'bind',
    });
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '邮箱绑定'));
    await tester.pumpAndSettle();

    expect(requestBodies.single, {
      'email': 'new@example.com',
      'code': '123456',
      'email_code': '123456',
    });
    expect(auth.state.email, 'new@example.com');
    expect(auth.state.emailVerified, isTrue);

    await tester.tap(find.text('修改登录密码'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '当前密码'), 'old-pass');
    await tester.enterText(find.widgetWithText(TextField, '新密码'), '123456');
    await tester.enterText(find.widgetWithText(TextField, '确认新密码'), '123456');
    await tester.tap(find.widgetWithText(FilledButton, '保存').last);
    await tester.pumpAndSettle();

    expect(passwordRequests.single, {
      'current_password': 'old-pass',
      'new_password': '123456',
    });
  });
}
