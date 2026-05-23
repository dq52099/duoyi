import 'dart:convert';

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
    'updateProfile keeps immutable username/avatar out of profile payload',
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
            expect(request.method, 'PATCH');
            expect(request.url.path, '/api/auth/profile');
            requestBody = json.decode(request.body) as Map<String, dynamic>;
            return http.Response(
              json.encode({
                'user_id': 'u-1',
                'username': 'stable-user',
                'email': requestBody!['email'],
                'email_verified': true,
                'display_name': requestBody!['display_name'],
                'avatar': 'https://example.com/stable.png',
                'bio': requestBody!['bio'],
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

      await auth.updateProfile(
        email: 'new@example.com',
        emailCode: '123456',
        displayName: '新昵称',
        bio: '简介',
      );

      expect(requestBody, {
        'email': 'new@example.com',
        'email_code': '123456',
        'display_name': '新昵称',
        'bio': '简介',
      });
      expect(auth.state.username, 'stable-user');
      expect(auth.state.avatar, 'https://example.com/stable.png');
      expect(auth.state.coinBalance, 42);
      expect(auth.state.lifetimeCoins, 108);
      expect(auth.state.token, 'token-1');
    },
  );

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
}
