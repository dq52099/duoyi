// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'storage hydration notifies with the old revision, then advances on success',
    () async {
      final auth = AuthProvider();
      addTearDown(auth.dispose);
      final events = _observeTransitions(auth);
      final revisionBefore = auth.successfulAccountTransitionRevision;

      final loading = auth.loadFromStorage(refreshServerConfig: false);
      // Hydration claims its transition only after preceding OAuth writes
      // settle. The call must preserve an in-flight issuer before lane admission.
      expect(events, isEmpty);
      expect(auth.successfulAccountTransitionRevision, revisionBefore);

      await loading;

      expect(events, [
        [true, revisionBefore],
        [false, revisionBefore + 1],
      ]);
      expect(auth.successfulAccountTransitionRevision, revisionBefore + 1);
    },
  );

  test(
    'storage owner write failure leaves the transition revision unchanged',
    () async {
      final account = _account();
      final store = _installStore({'auth_state': jsonEncode(account.toJson())});
      store.rejectedSetKeys.add(
        'flutter.${AccountLocalDataCleaner.accountDataOwnerKey}',
      );
      final auth = AuthProvider();
      addTearDown(auth.dispose);
      final events = _observeTransitions(auth);

      await expectLater(
        auth.loadFromStorage(refreshServerConfig: false),
        throwsA(isA<AccountLocalDataCleanupBlockedException>()),
      );

      expect(auth.successfulAccountTransitionRevision, 0);
      expect(auth.isAccountTransitionInProgress, isFalse);
      expect(events.first, [true, 0]);
      expect(events.last, [false, 0]);
    },
  );

  test(
    'login advances the revision when persistence succeeds with the same token',
    () async {
      final account = _account();
      _installStore({
        'auth_state': jsonEncode(account.toJson()),
        AccountLocalDataCleaner.accountDataOwnerKey: 'id:${account.userId}',
      });
      final auth = AuthProvider(
        initialState: account,
        client: _client((request) async {
          if (request.url.path == '/api/auth/login') {
            return _jsonResponse({
              'user_id': account.userId,
              'username': account.username,
              'token': account.token,
            });
          }
          if (request.url.path == '/api/config') return _jsonResponse({});
          return http.Response('not found', 404);
        }, token: account.token),
      );
      addTearDown(auth.dispose);
      final events = _observeTransitions(auth);

      await auth.login(
        username: account.username!,
        password: 'synthetic-password',
      );

      expect(auth.state.token, account.token);
      expect(auth.successfulAccountTransitionRevision, 1);
      expect(events.first, [true, 0]);
      expect(events.last, [false, 1]);
    },
  );

  test(
    'login cleanup block ends the transition without advancing the revision',
    () async {
      final account = _account(userId: 'next-user', token: 'next-token');
      _installStore({
        AccountLocalDataCleaner.accountDataOwnerKey: 'id:previous-user',
        'todos': '[{"id":"previous-account-todo"}]',
      });
      final auth = AuthProvider(
        client: _client((request) async {
          if (request.url.path == '/api/auth/login') {
            return _jsonResponse({
              'user_id': account.userId,
              'username': account.username,
              'token': account.token,
            });
          }
          return http.Response('not found', 404);
        }),
      );
      addTearDown(auth.dispose);
      auth.onAccountIdentityChanging = (_, _) async {
        throw const AccountLocalDataCleanupBlockedException('cleanup blocked');
      };
      final events = _observeTransitions(auth);

      await expectLater(
        auth.login(username: account.username!, password: 'synthetic-password'),
        throwsA(isA<AccountLocalDataCleanupBlockedException>()),
      );

      expect(auth.successfulAccountTransitionRevision, 0);
      expect(auth.isAccountTransitionInProgress, isFalse);
      expect(auth.state.isLoggedIn, isFalse);
      expect(events.first, [true, 0]);
      expect(events.last, [false, 0]);
    },
  );

  test(
    'login outer final preference cleanup failure keeps the revision unchanged',
    () async {
      final previous = _account(
        userId: 'previous-user',
        token: 'previous-token',
      );
      final next = _account(userId: 'next-user', token: 'next-token');
      final store = _installStore({
        'auth_state': jsonEncode(previous.toJson()),
        AccountLocalDataCleaner.accountDataOwnerKey: 'id:previous-user',
        'todos': '[]',
      });
      final auth = AuthProvider(
        initialState: previous,
        client: _client((request) async {
          if (request.url.path == '/api/auth/login') {
            return _jsonResponse({
              'user_id': next.userId,
              'username': next.username,
              'token': next.token,
            });
          }
          return http.Response('not found', 404);
        }, token: previous.token),
      );
      addTearDown(auth.dispose);
      var callbackFinished = false;
      auth.onAccountIdentityChanging = (_, _) async {
        callbackFinished = true;
        store.rejectedRemoveKeys.add('flutter.todos');
      };
      await expectLater(
        auth.login(username: next.username!, password: 'synthetic-password'),
        throwsA(isA<StateError>()),
      );
      expect(callbackFinished, isTrue);
      expect(auth.state.token, previous.token);
      expect(auth.isAccountTransitionInProgress, isFalse);
      expect(auth.successfulAccountTransitionRevision, 0);
    },
  );

  test(
    'login auth-state persistence failure does not advance the revision',
    () async {
      final store = _installStore({});
      store.rejectedSetKeys.add('flutter.auth_state');
      final account = _account();
      final auth = AuthProvider(
        client: _client((request) async {
          if (request.url.path == '/api/auth/login') {
            return _jsonResponse({
              'user_id': account.userId,
              'username': account.username,
              'token': account.token,
            });
          }
          return http.Response('not found', 404);
        }),
      );
      addTearDown(auth.dispose);
      final events = _observeTransitions(auth);

      await expectLater(
        auth.login(username: account.username!, password: 'synthetic-password'),
        throwsA(isA<AccountLocalDataCleanupBlockedException>()),
      );

      expect(auth.successfulAccountTransitionRevision, 0);
      expect(auth.isAccountTransitionInProgress, isFalse);
      expect(events.first, [true, 0]);
      expect(events.last, [false, 0]);
      expect(events.every((event) => event[1] == 0), isTrue);
    },
  );

  test('successful logged-in logout advances the revision once', () async {
    final account = _account();
    _installStore({
      'auth_state': jsonEncode(account.toJson()),
      AccountLocalDataCleaner.accountDataOwnerKey: 'id:${account.userId}',
    });
    final auth = AuthProvider(
      initialState: account,
      client: _client((request) async {
        if (request.url.path == '/api/auth/logout') {
          return _jsonResponse({'ok': true});
        }
        return http.Response('not found', 404);
      }, token: account.token),
    );
    addTearDown(auth.dispose);
    final events = _observeTransitions(auth);

    await auth.logout();

    expect(auth.state.isLoggedIn, isFalse);
    expect(auth.successfulAccountTransitionRevision, 1);
    expect(events.first, [true, 0]);
    expect(events.last, [false, 1]);
  });

  test('successful guest logout advances the revision once', () async {
    final auth = AuthProvider();
    addTearDown(auth.dispose);
    final events = _observeTransitions(auth);

    await auth.logout();

    expect(auth.state.isLoggedIn, isFalse);
    expect(auth.successfulAccountTransitionRevision, 1);
    expect(events.first, [true, 0]);
    expect(events.last, [false, 1]);
  });

  test(
    'blocked logout cleanup ends the transition without advancing the revision',
    () async {
      final account = _account();
      final auth = AuthProvider(initialState: account);
      addTearDown(auth.dispose);
      auth.onAccountLoggedOut = () async {
        throw const AccountLocalDataCleanupBlockedException('cleanup blocked');
      };
      final events = _observeTransitions(auth);

      await expectLater(
        auth.logout(),
        throwsA(isA<AccountLocalDataCleanupBlockedException>()),
      );

      expect(auth.state.token, account.token);
      expect(auth.successfulAccountTransitionRevision, 0);
      expect(auth.isAccountTransitionInProgress, isFalse);
      expect(events, [
        [true, 0],
        [false, 0],
      ]);
    },
  );

  test('a failed final session clear does not advance the revision', () async {
    final store = _installStore({});
    store.throwOnRemoveKeys.add('flutter.auth_state');
    final auth = AuthProvider();
    addTearDown(auth.dispose);
    final events = _observeTransitions(auth);

    await expectLater(auth.logout(), throwsA(isA<StateError>()));

    expect(auth.successfulAccountTransitionRevision, 0);
    expect(auth.isAccountTransitionInProgress, isFalse);
    expect(events.first, [true, 0]);
    expect(events.last, [false, 0]);
  });

  test(
    'a rejected final session clear does not advance the revision',
    () async {
      final store = _installStore({});
      store.rejectedRemoveKeys.add('flutter.auth_state');
      final auth = AuthProvider();
      addTearDown(auth.dispose);
      final events = _observeTransitions(auth);

      await expectLater(
        auth.logout(),
        throwsA(isA<AccountLocalDataCleanupBlockedException>()),
      );

      expect(auth.successfulAccountTransitionRevision, 0);
      expect(auth.isAccountTransitionInProgress, isFalse);
      expect(auth.isLocalAccountDataBlocked, isTrue);
      expect(events.first, [true, 0]);
      expect(events.last, [false, 0]);
    },
  );
}

AuthState _account({
  String userId = 'synthetic-user',
  String token = 'synthetic-token',
}) => AuthState(userId: userId, username: userId, token: token);

ApiClient _client(
  Future<http.Response> Function(http.Request request) handler, {
  String? token,
}) => ApiClient(
  baseUrl: 'https://duoyi.test',
  token: token,
  httpClient: MockClient(handler),
);

http.Response _jsonResponse(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

List<List<Object>> _observeTransitions(AuthProvider auth) {
  final events = <List<Object>>[];
  auth.addListener(() {
    events.add([
      auth.isAccountTransitionInProgress,
      auth.successfulAccountTransitionRevision,
    ]);
  });
  return events;
}

_ControlledPreferencesStore _installStore(Map<String, Object> values) {
  SharedPreferences.setMockInitialValues(values);
  final store = _ControlledPreferencesStore({
    for (final entry in values.entries) 'flutter.${entry.key}': entry.value,
  });
  SharedPreferencesStorePlatform.instance = store;
  return store;
}

class _ControlledPreferencesStore extends InMemorySharedPreferencesStore {
  _ControlledPreferencesStore(super.data) : super.withData();

  final rejectedSetKeys = <String>{};
  final rejectedRemoveKeys = <String>{};
  final throwOnRemoveKeys = <String>{};

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (rejectedSetKeys.contains(key)) return false;
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (throwOnRemoveKeys.contains(key)) {
      throw StateError('synthetic preference removal failure: $key');
    }
    if (rejectedRemoveKeys.contains(key)) return false;
    return super.remove(key);
  }
}
