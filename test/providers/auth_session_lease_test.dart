// Provider contract tests for AuthSessionLease lifecycle and API preflight.
// These cover AuthProvider contracts, not picker or other UI workflows.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _accountA = AuthState(
  userId: 'user-a',
  username: 'user-a',
  email: 'user-a@example.test',
  token: 'synthetic-token-a',
);

http.Response _jsonResponse(Map<String, Object?> body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json'},
    );

AuthProvider _loggedInAuth(
  Future<http.Response> Function(http.Request request) handler, {
  AuthState state = _accountA,
}) => AuthProvider(
  initialState: state,
  client: ApiClient(
    baseUrl: 'https://example.test',
    token: state.token,
    httpClient: MockClient(handler),
  ),
);

Future<T> _withMockClientFactory<T>(
  Future<T> Function() body,
  Future<http.Response> Function(http.Request request) handler,
) => http.runWithClient(body, () => MockClient(handler));

String _requestLabel(http.Request request) =>
    '${request.method} ${request.url.path}';

Matcher _accountChangedFailure() => isA<ApiException>().having(
  (error) => error.message,
  'message',
  '账号已发生变化，请在当前账号重试操作。',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'capture rejects signed-out state; leases are provider-owned and disposed',
    () {
      final signedOut = AuthProvider();
      final first = _loggedInAuth((_) async => _jsonResponse({'ok': true}));
      final second = _loggedInAuth((_) async => _jsonResponse({'ok': true}));
      var signedOutDisposed = false;
      var firstDisposed = false;
      var secondDisposed = false;
      addTearDown(() {
        if (!signedOutDisposed) signedOut.dispose();
        if (!firstDisposed) first.dispose();
        if (!secondDisposed) second.dispose();
      });

      expect(
        () => signedOut.captureSessionLease(),
        throwsA(isA<ApiException>()),
      );
      final lease = first.captureSessionLease();
      expect(first.isSessionLeaseCurrent(lease), isTrue);
      expect(second.isSessionLeaseCurrent(lease), isFalse);
      expect(
        () => second.requireCurrentSessionLease(lease),
        throwsA(_accountChangedFailure()),
      );

      first.dispose();
      firstDisposed = true;
      expect(first.isSessionLeaseCurrent(lease), isFalse);
      signedOut.dispose();
      signedOutDisposed = true;
      second.dispose();
      secondDisposed = true;
    },
  );

  test('capture rejects while an account transition is in progress', () async {
    final dispatches = <String>[];
    Future<http.Response> handler(http.Request request) async {
      dispatches.add(_requestLabel(request));
      if (request.url.path == '/api/auth/login') {
        return _jsonResponse({
          'user_id': 'user-b',
          'username': 'user-b',
          'token': 'synthetic-token-b',
        });
      }
      if (request.url.path == '/api/config') return _jsonResponse({});
      return _jsonResponse({'detail': 'Not Found'}, status: 404);
    }

    final cleanupStarted = Completer<void>();
    final allowCleanup = Completer<void>();
    await _withMockClientFactory(() async {
      final auth = _loggedInAuth(handler);
      auth.onAccountIdentityChanging = (_, _) async {
        cleanupStarted.complete();
        await allowCleanup.future;
      };
      addTearDown(auth.dispose);

      final login = auth.login(
        username: 'user-b',
        password: 'synthetic-password',
      );
      await cleanupStarted.future.timeout(const Duration(seconds: 2));
      expect(auth.isLocalAccountDataBlocked, isFalse);
      expect(
        () => auth.captureSessionLease(),
        throwsA(_accountChangedFailure()),
      );

      allowCleanup.complete();
      await login;
      await auth.refreshServerConfigFromServer();
      expect(dispatches, contains('POST /api/auth/login'));
      expect(dispatches, contains('GET /api/config'));
    }, handler);
  });

  test('capture rejects while storage hydration blocks account data', () async {
    SharedPreferences.setMockInitialValues({
      'auth_state': jsonEncode(_accountA.toJson()),
      'duoyi_account_data_owner_v1': 'id:another-user',
    });
    final cleanupStarted = Completer<void>();
    final allowCleanup = Completer<void>();
    final auth = _loggedInAuth((_) async => _jsonResponse({'ok': true}));
    auth.onAccountIdentityChanging = (_, _) async {
      cleanupStarted.complete();
      await allowCleanup.future;
    };
    addTearDown(auth.dispose);

    final hydration = auth.loadFromStorage(refreshServerConfig: false);
    await cleanupStarted.future;
    expect(auth.isLocalAccountDataBlocked, isTrue);
    expect(() => auth.captureSessionLease(), throwsA(_accountChangedFailure()));

    allowCleanup.complete();
    await hydration;
    final lease = auth.captureSessionLease();
    expect(auth.isSessionLeaseCurrent(lease), isTrue);
  });

  test(
    'same-account profile update and refresh keep an existing lease current',
    () async {
      final auth = _loggedInAuth((request) async {
        if (request.url.path == '/api/me/profile') {
          return _jsonResponse({
            'user_id': 'user-a',
            'username': 'user-a',
            'display_name': 'Updated name',
            'bio': 'Updated bio',
          });
        }
        if (request.url.path == '/api/auth/me') {
          return _jsonResponse({
            'user_id': 'user-a',
            'username': 'user-a',
            'display_name': 'Refreshed name',
            'coin_balance': 23,
          });
        }
        return _jsonResponse({'detail': 'Not Found'}, status: 404);
      });
      addTearDown(auth.dispose);
      final lease = auth.captureSessionLease();

      await auth.updateProfile(
        displayName: 'Updated name',
        bio: 'Updated bio',
        sessionLease: lease,
      );
      expect(auth.isSessionLeaseCurrent(lease), isTrue);

      await auth.refreshMe(reason: 'session_lease_contract', force: true);
      expect(auth.isSessionLeaseCurrent(lease), isTrue);
    },
  );

  test('legacy lease stays current when refresh fills the user ID', () async {
    const legacyState = AuthState(token: 'synthetic-token-a');
    final auth = _loggedInAuth((request) async {
      if (request.url.path == '/api/auth/me') {
        return _jsonResponse({
          'user_id': 'user-a',
          'username': 'user-a',
          'display_name': 'Refreshed legacy session',
        });
      }
      return _jsonResponse({'detail': 'Not Found'}, status: 404);
    }, state: legacyState);
    addTearDown(auth.dispose);
    final lease = auth.captureSessionLease();

    await auth.refreshMe(reason: 'legacy_session_lease', force: true);

    expect(auth.state.userId, 'user-a');
    expect(auth.isSessionLeaseCurrent(lease), isTrue);
  });

  test('lease rejects a different known user ID in provider state', () async {
    final auth = _loggedInAuth((_) async => _jsonResponse({'ok': true}));
    addTearDown(auth.dispose);
    final lease = auth.captureSessionLease();

    await auth.applyServerAccountSnapshot({
      'user_id': 'user-b',
      'username': 'user-b',
    }, reason: 'session_lease_user_mismatch');

    expect(auth.state.userId, 'user-b');
    expect(auth.isSessionLeaseCurrent(lease), isFalse);
  });

  test(
    'same-id same-token login invalidates lease even when cleanup fails',
    () async {
      SharedPreferences.setMockInitialValues({
        'duoyi_account_data_owner_v1': 'id:another-user',
      });
      var cleanupCalls = 0;
      final auth = _loggedInAuth((request) async {
        if (request.url.path == '/api/auth/login') {
          return _jsonResponse({
            'user_id': 'user-a',
            'username': 'user-a',
            'token': 'synthetic-token-a',
          });
        }
        return _jsonResponse({'detail': 'Not Found'}, status: 404);
      });
      auth.onAccountIdentityChanging = (_, _) async {
        cleanupCalls++;
        throw const ApiException('synthetic cleanup failure');
      };
      addTearDown(auth.dispose);
      final lease = auth.captureSessionLease();

      await expectLater(
        auth.login(username: 'user-a', password: 'synthetic-password'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            'synthetic cleanup failure',
          ),
        ),
      );

      expect(cleanupCalls, 1);
      expect(auth.state.userId, 'user-a');
      expect(auth.state.token, 'synthetic-token-a');
      expect(auth.isSessionLeaseCurrent(lease), isFalse);
    },
  );

  test(
    'dispose during login identity cleanup prevents the final prefs pass',
    () async {
      final originalAuthState = jsonEncode(_accountA.toJson());
      SharedPreferences.setMockInitialValues({
        'auth_state': originalAuthState,
        'duoyi_account_data_owner_v1': 'id:user-a',
      });
      final dispatches = <String>[];
      final cleanupStarted = Completer<void>();
      final allowCleanup = Completer<void>();
      var cleanupCalls = 0;
      var disposed = false;
      var notificationsAfterDispose = 0;
      final auth = _loggedInAuth((request) async {
        dispatches.add(_requestLabel(request));
        if (request.url.path == '/api/auth/login') {
          return _jsonResponse({
            'user_id': 'user-b',
            'username': 'user-b',
            'token': 'synthetic-token-b',
          });
        }
        return _jsonResponse({'ok': true});
      });
      auth.addListener(() {
        if (disposed) notificationsAfterDispose++;
      });
      auth.onAccountIdentityChanging = (_, _) async {
        cleanupStarted.complete();
        await allowCleanup.future;
        cleanupCalls++;
      };
      addTearDown(() {
        if (!disposed) auth.dispose();
      });

      final login = auth.login(
        username: 'user-b',
        password: 'synthetic-password',
      );
      await cleanupStarted.future.timeout(const Duration(seconds: 2));
      auth.dispose();
      disposed = true;
      allowCleanup.complete();

      await expectLater(login, throwsA(_accountChangedFailure()));
      final prefs = await SharedPreferences.getInstance();
      expect(cleanupCalls, 1);
      expect(dispatches, ['POST /api/auth/login']);
      expect(prefs.getString('auth_state'), originalAuthState);
      expect(prefs.getString('duoyi_account_data_owner_v1'), 'id:user-a');
      expect(notificationsAfterDispose, 0);
    },
  );

  test(
    'all five account APIs reject a stale lease before sending a request',
    () async {
      final dispatches = <String>[];
      Future<http.Response> handler(http.Request request) async {
        dispatches.add(_requestLabel(request));
        if (request.url.path == '/api/auth/login') {
          return _jsonResponse({
            'user_id': 'user-a',
            'username': 'user-a',
            'token': 'synthetic-token-a',
          });
        }
        if (request.url.path == '/api/config') return _jsonResponse({});
        return _jsonResponse({'ok': true});
      }

      await _withMockClientFactory(() async {
        final auth = _loggedInAuth(handler);
        addTearDown(auth.dispose);
        final staleLease = auth.captureSessionLease();
        await auth.login(username: 'user-a', password: 'synthetic-password');
        await auth.refreshServerConfigFromServer();
        final beforeStaleCalls = List<String>.of(dispatches);
        expect(beforeStaleCalls, contains('POST /api/auth/login'));
        expect(beforeStaleCalls, contains('GET /api/config'));

        await expectLater(
          auth.updateProfile(
            displayName: 'No request',
            sessionLease: staleLease,
          ),
          throwsA(_accountChangedFailure()),
        );
        await expectLater(
          auth.uploadAvatarBytes(
            filename: 'synthetic-avatar.png',
            bytes: Uint8List.fromList([1, 2, 3]),
            sessionLease: staleLease,
          ),
          throwsA(_accountChangedFailure()),
        );
        await expectLater(
          auth.bindEmail(
            email: 'new-address@example.test',
            code: '000000',
            sessionLease: staleLease,
          ),
          throwsA(_accountChangedFailure()),
        );
        await expectLater(
          auth.changePassword(
            currentPassword: 'synthetic-current-password',
            newPassword: 'synthetic-new-password',
            sessionLease: staleLease,
          ),
          throwsA(_accountChangedFailure()),
        );
        await expectLater(
          auth.sendBindEmailCode(
            email: 'new-address@example.test',
            sessionLease: staleLease,
          ),
          throwsA(_accountChangedFailure()),
        );

        expect(dispatches.length, beforeStaleCalls.length);
        expect(dispatches, beforeStaleCalls);
      }, handler);
    },
  );

  test(
    'account A lease rejects avatar upload after provider switches to B',
    () async {
      final dispatches = <String>[];
      Future<http.Response> handler(http.Request request) async {
        dispatches.add(_requestLabel(request));
        if (request.url.path == '/api/auth/login') {
          return _jsonResponse({
            'user_id': 'user-b',
            'username': 'user-b',
            'token': 'synthetic-token-b',
          });
        }
        if (request.url.path == '/api/config') return _jsonResponse({});
        return _jsonResponse({'ok': true});
      }

      await _withMockClientFactory(() async {
        final auth = _loggedInAuth(handler);
        addTearDown(auth.dispose);
        final leaseA = auth.captureSessionLease();

        await auth.login(username: 'user-b', password: 'synthetic-password');
        await auth.refreshServerConfigFromServer();
        final beforeAvatar = List<String>.of(dispatches);
        expect(beforeAvatar, contains('POST /api/auth/login'));
        expect(beforeAvatar, contains('GET /api/config'));
        await expectLater(
          auth.uploadAvatarBytes(
            filename: 'synthetic-avatar.png',
            bytes: Uint8List.fromList([1, 2, 3]),
            sessionLease: leaseA,
          ),
          throwsA(_accountChangedFailure()),
        );

        expect(auth.state.userId, 'user-b');
        expect(dispatches.length, beforeAvatar.length);
        expect(dispatches, beforeAvatar);
      }, handler);
    },
  );

  test(
    'response arriving after dispose cannot write auth preferences',
    () async {
      final originalState = _accountA.toJson();
      SharedPreferences.setMockInitialValues({
        'auth_state': jsonEncode(originalState),
      });
      final requestStarted = Completer<void>();
      final response = Completer<http.Response>();
      final auth = _loggedInAuth((request) {
        requestStarted.complete();
        return response.future;
      });
      var disposed = false;
      addTearDown(() {
        if (!disposed) auth.dispose();
      });
      final lease = auth.captureSessionLease();
      final update = auth.updateProfile(
        displayName: 'Must not persist',
        sessionLease: lease,
      );
      await requestStarted.future;

      auth.dispose();
      disposed = true;
      response.complete(
        _jsonResponse({
          'user_id': 'user-a',
          'username': 'user-a',
          'display_name': 'Must not persist',
        }),
      );
      await expectLater(update, throwsA(_accountChangedFailure()));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_state'), jsonEncode(originalState));
    },
  );

  test(
    'successful password change clears session and still completes',
    () async {
      final auth = _loggedInAuth((request) async {
        if (request.url.path == '/api/me/password') {
          return _jsonResponse({'ok': true});
        }
        return _jsonResponse({'detail': 'Not Found'}, status: 404);
      });
      addTearDown(auth.dispose);
      final lease = auth.captureSessionLease();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_state', jsonEncode(_accountA.toJson()));

      await expectLater(
        auth.changePassword(
          currentPassword: 'synthetic-current-password',
          newPassword: 'synthetic-new-password',
          sessionLease: lease,
        ),
        completes,
      );

      expect(auth.state.isLoggedIn, isFalse);
      expect(auth.isSessionLeaseCurrent(lease), isFalse);
      expect(prefs.getString('auth_state'), isNull);
    },
  );

  test(
    'dispose during logout cleanup callback prevents prefs and route cleanup',
    () async {
      final originalAuthState = jsonEncode(_accountA.toJson());
      SharedPreferences.setMockInitialValues({
        'auth_state': originalAuthState,
        'duoyi_account_data_owner_v1': 'id:user-a',
      });
      final dispatches = <String>[];
      final cleanupStarted = Completer<void>();
      final allowCleanup = Completer<void>();
      var callbackReturned = false;
      var disposed = false;
      var notificationsAfterDispose = 0;
      final auth = _loggedInAuth((request) async {
        dispatches.add(_requestLabel(request));
        return _jsonResponse({'ok': true});
      });
      auth.addListener(() {
        if (disposed) notificationsAfterDispose++;
      });
      auth.onAccountLoggedOut = () async {
        cleanupStarted.complete();
        await allowCleanup.future;
        callbackReturned = true;
      };
      addTearDown(() {
        if (!disposed) auth.dispose();
      });

      final logout = auth.logout();
      await cleanupStarted.future.timeout(const Duration(seconds: 2));
      auth.dispose();
      disposed = true;
      allowCleanup.complete();

      await expectLater(logout, throwsA(_accountChangedFailure()));
      final prefs = await SharedPreferences.getInstance();
      expect(callbackReturned, isTrue);
      expect(dispatches, isEmpty);
      expect(prefs.getString('auth_state'), originalAuthState);
      expect(prefs.getString('duoyi_account_data_owner_v1'), 'id:user-a');
      expect(notificationsAfterDispose, 0);
    },
  );

  test(
    'old logout preflight cannot log out same-token reauthenticated session',
    () async {
      final dispatches = <String>[];
      final preflightStarted = Completer<void>();
      final allowPreflight = Completer<void>();
      Future<http.Response> handler(http.Request request) async {
        dispatches.add(_requestLabel(request));
        if (request.url.path == '/api/auth/login') {
          return _jsonResponse({
            'user_id': 'user-a',
            'username': 'user-a',
            'token': 'synthetic-token-a',
          });
        }
        if (request.url.path == '/api/config') return _jsonResponse({});
        return _jsonResponse({'ok': true});
      }

      SharedPreferences.setMockInitialValues({
        'auth_state': jsonEncode(_accountA.toJson()),
        'duoyi_account_data_owner_v1': 'id:user-a',
      });
      await _withMockClientFactory(() async {
        final auth = _loggedInAuth(handler);
        addTearDown(auth.dispose);
        auth.onBeforeAccountLogout = () async {
          preflightStarted.complete();
          await allowPreflight.future;
        };

        final oldLogout = auth.logout();
        await preflightStarted.future.timeout(const Duration(seconds: 2));
        await auth.login(username: 'user-a', password: 'synthetic-password');
        await auth.refreshServerConfigFromServer();
        final freshLease = auth.captureSessionLease();
        final beforePreflightRelease = List<String>.of(dispatches);

        allowPreflight.complete();
        await oldLogout;

        expect(dispatches, beforePreflightRelease);
        expect(
          dispatches.where((path) => path.endsWith('/api/auth/logout')),
          isEmpty,
        );
        expect(auth.state.userId, 'user-a');
        expect(auth.state.token, 'synthetic-token-a');
        expect(auth.isSessionLeaseCurrent(freshLease), isTrue);
      }, handler);
    },
  );

  test(
    'lease from a newly authenticated session survives same-account mutation',
    () async {
      final dispatches = <String>[];
      Future<http.Response> handler(http.Request request) async {
        dispatches.add(_requestLabel(request));
        if (request.url.path == '/api/auth/login') {
          return _jsonResponse({
            'user_id': 'user-a',
            'username': 'user-a',
            'token': 'synthetic-token-a',
          });
        }
        if (request.url.path == '/api/config') return _jsonResponse({});
        return _jsonResponse({'detail': 'Not Found'}, status: 404);
      }

      await _withMockClientFactory(() async {
        final auth = AuthProvider(
          client: ApiClient(
            baseUrl: 'https://example.test',
            httpClient: MockClient(handler),
          ),
        );
        addTearDown(auth.dispose);

        await auth.login(username: 'user-a', password: 'synthetic-password');
        await auth.refreshServerConfigFromServer();
        expect(dispatches, contains('POST /api/auth/login'));
        expect(dispatches, contains('GET /api/config'));
        final lease = auth.captureSessionLease();
        await auth.applyServerAccountSnapshot({
          'user_id': 'user-a',
          'username': 'user-a',
          'display_name': 'Updated in same session',
        }, reason: 'session_lease_contract');

        expect(auth.state.displayName, 'Updated in same session');
        expect(auth.isSessionLeaseCurrent(lease), isTrue);
      }, handler);
    },
  );
}
