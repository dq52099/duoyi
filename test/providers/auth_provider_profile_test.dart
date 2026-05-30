import 'dart:convert';
import 'dart:typed_data';

import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'bindEmail keeps immutable username/avatar out of profile payload',
    () async {
      Map<String, dynamic>? requestBody;
      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'u-1',
          username: 'stable-user',
          avatar: 'https://example.com/stable.png',
          token: 'token-1',
        ),
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token-1',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/me/email');
            requestBody = json.decode(request.body) as Map<String, dynamic>;
            return http.Response(
              json.encode({
                'user_id': 'u-1',
                'username': 'stable-user',
                'email': requestBody!['email'],
                'email_verified': true,
                'display_name': '旧昵称',
                'avatar': 'https://example.com/stable.png',
                'bio': '旧简介',
                'coin_balance': '42',
                'lifetime_coins': 108,
                'token': 'token-ignored',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      await auth.bindEmail(email: 'new@example.com', code: '123456');

      expect(requestBody, {
        'email': 'new@example.com',
        'code': '123456',
        'email_code': '123456',
      });
      expect(auth.state.username, 'stable-user');
      expect(auth.state.avatar, 'https://example.com/stable.png');
      expect(auth.state.coinBalance, 42);
      expect(auth.state.lifetimeCoins, 108);
      expect(auth.state.token, 'token-1');
    },
  );

  test('email code send and login use stable auth routes', () async {
    final paths = <String>[];
    final auth = AuthProvider(
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          final body = json.decode(request.body) as Map<String, dynamic>;
          if (request.url.path == '/api/auth/email-code') {
            expect(body, {'email': 'login@example.com', 'purpose': 'login'});
            return http.Response(
              json.encode({'ok': true}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/api/auth/email-login') {
            expect(body, {
              'email': 'login@example.com',
              'code': '654321',
              'email_code': '654321',
            });
            return http.Response(
              json.encode({
                'user_id': 'u-1',
                'username': 'stable-user',
                'email': 'login@example.com',
                'email_verified': true,
                'token': 'token-1',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        }),
      ),
    );

    await auth.sendEmailCode(email: 'login@example.com');
    await auth.emailLogin(email: 'login@example.com', code: '654321');

    expect(paths, ['/api/auth/email-code', '/api/auth/email-login']);
    expect(auth.state.token, 'token-1');
  });

  test('email login retries compatible routes after 404', () async {
    final paths = <String>[];
    final auth = AuthProvider(
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          final body = json.decode(request.body) as Map<String, dynamic>;
          if (request.url.path == '/api/auth/login/email-code') {
            expect(body, {
              'email': 'login@example.com',
              'code': '654321',
              'email_code': '654321',
            });
            return http.Response(
              json.encode({
                'user_id': 'u-1',
                'username': 'stable-user',
                'email': 'login@example.com',
                'email_verified': true,
                'token': 'token-1',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        }),
      ),
    );

    await auth.emailLogin(email: 'login@example.com', code: '654321');

    expect(paths, [
      '/api/auth/email-login',
      '/api/auth/email/login',
      '/api/auth/login/email',
      '/api/auth/email-code-login',
      '/api/auth/login/email-code',
    ]);
    expect(auth.state.token, 'token-1');
  });

  test('binding email code uses authenticated me route', () async {
    Map<String, dynamic>? requestBody;
    final auth = AuthProvider(
      initialState: const AuthState(token: 'token-1'),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token-1',
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/me/email-code');
          requestBody = json.decode(request.body) as Map<String, dynamic>;
          return http.Response(
            json.encode({'message': '验证码已发送，请查收邮箱'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    await auth.sendBindEmailCode(email: 'new@example.com');

    expect(requestBody, {'email': 'new@example.com', 'purpose': 'bind'});
  });

  test(
    'profile email and avatar APIs retry compatible routes after 404',
    () async {
      final paths = <String>[];
      final auth = AuthProvider(
        initialState: const AuthState(token: 'token-1'),
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token-1',
          httpClient: MockClient((request) async {
            paths.add('${request.method} ${request.url.path}');
            if (request.url.path == '/api/me/email-code/send') {
              return http.Response(
                json.encode({'message': 'ok'}),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            if (request.url.path == '/api/auth/profile/avatar') {
              return http.Response(
                json.encode({
                  'user_id': 'u-1',
                  'username': 'stable-user',
                  'avatar': '/api/uploads/avatars/u-1.png',
                  'token': 'ignored',
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response('not found', 404);
          }),
        ),
      );

      await auth.sendBindEmailCode(email: 'new@example.com');
      await auth.uploadAvatarBytes(
        filename: 'avatar.png',
        bytes: Uint8List.fromList([137, 80, 78, 71]),
      );

      expect(paths, contains('POST /api/me/email-code'));
      expect(paths, contains('POST /api/me/email-code/send'));
      expect(paths, contains('POST /api/me/avatar'));
      expect(paths, contains('POST /api/me/profile/avatar'));
      expect(paths, contains('POST /api/auth/profile/avatar'));
      expect(
        auth.state.avatar,
        'https://duoyi.test/api/uploads/avatars/u-1.png',
      );
    },
  );

  test('avatar upload uses RE0-compatible me avatar route first', () async {
    final auth = AuthProvider(
      initialState: const AuthState(token: 'token-1'),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token-1',
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/me/avatar');
          return http.Response(
            json.encode({
              'user_id': 'u-1',
              'username': 'stable-user',
              'avatar': 'https://duoyi.test/api/uploads/avatars/u-1.png',
              'token': 'ignored',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    await auth.uploadAvatarBytes(
      filename: 'avatar.png',
      bytes: Uint8List.fromList([137, 80, 78, 71]),
    );

    expect(auth.state.avatar, 'https://duoyi.test/api/uploads/avatars/u-1.png');
    expect(auth.state.token, 'token-1');
  });

  test(
    'avatar upload does not duplicate api prefix when base URL includes /api',
    () async {
      final paths = <String>[];
      final auth = AuthProvider(
        initialState: const AuthState(token: 'token-1'),
        client: ApiClient(
          baseUrl: 'https://duoyi.test/api/',
          token: 'token-1',
          httpClient: MockClient((request) async {
            paths.add(request.url.toString());
            return http.Response(
              json.encode({
                'user_id': 'u-1',
                'username': 'stable-user',
                'avatar': '/api/uploads/avatars/u-1.png',
                'token': 'ignored',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      await auth.uploadAvatarBytes(
        filename: 'avatar.png',
        bytes: Uint8List.fromList([137, 80, 78, 71]),
      );

      expect(paths.single, 'https://duoyi.test/api/me/avatar');
      expect(
        auth.state.avatar,
        'https://duoyi.test/api/uploads/avatars/u-1.png',
      );
      expect(auth.state.avatar, isNot(contains('/api/api/')));
    },
  );

  test('updateProfile omits untouched profile fields', () async {
    Map<String, dynamic>? requestBody;
    final auth = AuthProvider(
      initialState: const AuthState(
        userId: 'u-1',
        username: 'stable-user',
        email: 'old@example.com',
        displayName: '旧昵称',
        bio: '旧简介',
        token: 'token-1',
      ),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token-1',
        httpClient: MockClient((request) async {
          requestBody = json.decode(request.body) as Map<String, dynamic>;
          return http.Response(
            json.encode({
              'user_id': 'u-1',
              'username': 'stable-user',
              'email': 'old@example.com',
              'display_name': requestBody!['display_name'],
              'bio': requestBody!['bio'],
              'token': 'ignored',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    await auth.updateProfile(displayName: '新昵称', bio: '');

    expect(requestBody, {'display_name': '新昵称', 'bio': ''});
    expect(auth.state.email, 'old@example.com');
  });

  test('refreshMe retries compatible me route after 404', () async {
    final paths = <String>[];
    final auth = AuthProvider(
      initialState: const AuthState(token: 'token-1'),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token-1',
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/api/me') {
            return http.Response(
              json.encode({
                'user_id': 'u-1',
                'username': 'stable-user',
                'email': 'me@example.com',
                'display_name': '当前用户',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            json.encode({'detail': 'Not Found'}),
            404,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    await auth.refreshMe();

    expect(paths, ['/api/auth/me', '/api/me']);
    expect(auth.state.displayName, '当前用户');
    expect(auth.state.token, 'token-1');
  });

  test(
    'changePassword retries RE0-compatible me password route first',
    () async {
      final paths = <String>[];
      Map<String, dynamic>? requestBody;
      final auth = AuthProvider(
        initialState: const AuthState(token: 'token-1'),
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token-1',
          httpClient: MockClient((request) async {
            paths.add(request.url.path);
            requestBody = json.decode(request.body) as Map<String, dynamic>;
            if (request.url.path == '/api/me/password') {
              return http.Response(
                json.encode({'ok': true}),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              json.encode({'detail': 'Not Found'}),
              404,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      await auth.changePassword(
        currentPassword: 'oldpass123',
        newPassword: 'newpass456',
      );

      expect(paths, ['/api/me/password']);
      expect(requestBody, {
        'current_password': 'oldpass123',
        'new_password': 'newpass456',
      });
    },
  );

  test('password reset request retries compatible routes after 404', () async {
    final paths = <String>[];
    final auth = AuthProvider(
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          final body = json.decode(request.body) as Map<String, dynamic>;
          if (request.url.path == '/api/auth/password-reset/request') {
            expect(body, {
              'username': 'reset@example.com',
              'account': 'reset@example.com',
              'identifier': 'reset@example.com',
              'email': 'reset@example.com',
            });
            return http.Response(
              json.encode({'ok': true}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            json.encode({'detail': 'Not Found'}),
            404,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final result = await auth.requestPasswordReset(
      account: 'reset@example.com',
    );

    expect(paths, [
      '/api/auth/password-reset',
      '/api/auth/password-reset/request',
    ]);
    expect(result['ok'], isTrue);
  });

  test('password reset confirm retries compatible routes after 404', () async {
    final paths = <String>[];
    Map<String, dynamic>? requestBody;
    final auth = AuthProvider(
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          requestBody = json.decode(request.body) as Map<String, dynamic>;
          if (request.url.path == '/api/auth/reset-password/confirm') {
            return http.Response(
              json.encode({'ok': true}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            json.encode({'detail': 'Not Found'}),
            404,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    await auth.confirmPasswordReset(
      email: 'reset@example.com',
      code: '123456',
      newPassword: 'newpass456',
    );

    expect(paths, [
      '/api/auth/password-reset/confirm',
      '/api/auth/reset-password/confirm',
    ]);
    expect(requestBody, {
      'password': 'newpass456',
      'new_password': 'newpass456',
      'account': 'reset@example.com',
      'identifier': 'reset@example.com',
      'email': 'reset@example.com',
      'code': '123456',
    });
  });

  test(
    'register requires username and sends optional email verification',
    () async {
      final requests = <Map<String, dynamic>>[];
      final auth = AuthProvider(
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          httpClient: MockClient((request) async {
            if (request.method == 'POST' &&
                request.url.path == '/api/auth/register') {
              final body = json.decode(request.body) as Map<String, dynamic>;
              requests.add(body);
              return http.Response(
                json.encode({
                  'user_id': 'u-2',
                  'username': body['username'],
                  'email': body['email'],
                  'email_verified': true,
                  'display_name': body['display_name'],
                  'avatar': '',
                  'bio': '',
                  'token': 'token-2',
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response('not found', 404);
          }),
        ),
      );

      await auth.register(
        username: 'new-user',
        password: 'pass123456',
        email: 'new@example.com',
        emailCode: '654321',
        displayName: '新用户',
      );

      expect(requests.single, {
        'username': 'new-user',
        'password': 'pass123456',
        'email': 'new@example.com',
        'email_code': '654321',
        'display_name': '新用户',
      });
      expect(auth.state.username, 'new-user');
      expect(auth.state.emailVerified, isTrue);
    },
  );

  test('registration email verification defaults to required', () {
    final auth = AuthProvider();

    expect(auth.registrationEmailRequired, isTrue);
  });

  test(
    'email code sent false without dev code throws and does not succeed',
    () async {
      final auth = AuthProvider(
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          httpClient: MockClient((request) async {
            expect(request.url.path, '/api/auth/email-code');
            return http.Response(
              json.encode({'ok': true, 'sent': false, 'detail': 'SMTP 未完整配置'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      await expectLater(
        auth.sendEmailCode(email: 'login@example.com'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('SMTP 未完整配置'),
          ),
        ),
      );
    },
  );

  test('business 404 is not swallowed as a route fallback', () async {
    final paths = <String>[];
    final auth = AuthProvider(
      initialState: const AuthState(token: 'token-1'),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token-1',
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/api/me/email-code') {
            return http.Response(
              json.encode({'detail': '邮箱未绑定'}),
              404,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            json.encode({'detail': 'unexpected fallback'}),
            500,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    await expectLater(
      auth.sendBindEmailCode(email: 'new@example.com'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('邮箱未绑定'),
        ),
      ),
    );
    expect(paths, ['/api/me/email-code']);
  });
}
