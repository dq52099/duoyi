// ignore_for_file: depend_on_referenced_packages
// Prepared309 from oauth-ui-preimage-303 and main's explicit API contract.
// No live Auth/service reads, formatter, compiler or test execution.

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/oauth_authorization_input.dart';
import 'package:duoyi/core/oauth_calendar_storage.dart';
import 'package:duoyi/core/oauth_pending_authorization.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

const _wait = Duration(seconds: 5);
const _pendingKey = OAuthCalendarStorage.pendingAuthorizationKey;
const _accountsKey = OAuthCalendarStorage.accountsKey;
const _account = 'ui309-account-a';
const _title = 'UI309 confirmed event';
const _ordinary = <String, Object>{
  'auth_state': '{ "token" : null }',
  'todos': '[ { "id" : "ui309", "title" : "keep todo309" } ]',
  'duoyi_notes': '[ { "body" : "keep note309" } ]',
  'duoyi_ics_subscriptions_v1': '[]',
  'ui309_device_setting': 309,
};
Matcher get _canceled => anyOf(
  isA<AccountPreferenceWriteCanceled>(),
  isA<OAuthScopedWorkspaceUnavailable>(),
  isA<ApiException>(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() async => f = await _Fixture.create());
  tearDown(() async => f.close());

  for (final action in ['prepare', 'load', 'save', 'clear']) {
    test(
      'UI309-canceled-$action caller canceled before admission preserves disk and pending',
      () => f.withHttp(() async {
        await f.login();
        if (action != 'prepare') {
          await f.provider.prepareOAuthScope(initialize: true).timeout(_wait);
          await f.save(f.provider);
        }
        final before = await f.disk();
        final writes = f.store.mutations.toList();
        final requests = f.requests.toList();
        var current = false;
        await f.reject(f.action(action, () => current), _canceled);
        expect(await f.disk(), before);
        expect(f.store.mutations, writes);
        expect(f.requests, requests);
        expect(f.provider.oauthLocalCommitReceipts, isEmpty);
        if (action == 'prepare') expect(f.provider.isOAuthReady, isFalse);
      }),
    );
  }

  for (final action in ['load', 'save']) {
    test(
      'UI309-queued-$action caller cancellation behind an issued account write cannot create or adopt an attempt',
      () => f.withHttp(() async {
        await f.install();
        await f.save(f.provider);
        final before = await f.disk();
        final peer = f.consumer();
        await peer.loadPendingOAuthAuthorization().timeout(_wait);
        final h = f.store.holdWrite(_accountsKey);
        final updating = f.observe<void>(
          f.provider.updateOAuthAccount(
            f.account!.copyWith(displayName: 'UI309 peer write'),
          ),
        );
        await h.started.future.timeout(_wait);
        var current = true;
        var settled = false;
        final waiting = f.observe<dynamic>(
          f.action(action, () => current, peer),
        );
        waiting.then<void>((_) {
          settled = true;
        });
        await Future<void>.delayed(Duration.zero);
        expect(settled, isFalse);
        final writes = f.store.mutations.toList();
        final requests = f.requests.toList();
        current = false;
        h.release.complete();
        expect((await updating.timeout(_wait)).error, isNull);
        expect((await waiting.timeout(_wait)).error, _canceled);
        await AccountPreferenceWrites.drain().timeout(_wait);
        final after = await f.disk();
        expect(after[_pendingKey], before[_pendingKey]);
        expect(f.store.mutations, writes);
        expect(f.requests, requests);
        expect(peer.oauthLocalCommitReceipts, isEmpty);
      }),
    );
  }

  for (final action in ['load', 'save', 'clear']) {
    test(
      'UI309-read-$action caller canceled during authoritative reload preserves exact old attempt',
      () => f.withHttp(() async {
        await f.login();
        await f.provider.prepareOAuthScope(initialize: true).timeout(_wait);
        await f.save(f.provider);
        final before = await f.disk();
        final writes = f.store.mutations.toList();
        final requests = f.requests.toList();
        final h = f.store.holdReload();
        var current = true;
        final work = f.observe<dynamic>(f.action(action, () => current));
        await h.started.future.timeout(_wait);
        current = false;
        h.release.complete();
        expect((await work.timeout(_wait)).error, _canceled);
        expect(await f.disk(), before);
        expect(f.store.mutations, writes);
        expect(f.requests, requests);
      }),
    );
  }

  test(
    'UI309-read-prepare signed-in caller canceled during scope reload cannot issue readiness',
    () => f.withHttp(() async {
      await f.login();
      final before = await f.disk();
      final writes = f.store.mutations.toList();
      final h = f.store.holdReload();
      var current = true;
      final preparing = f.observe<void>(
        f.provider.prepareOAuthScope(
          initialize: true,
          isCurrent: () => current,
        ),
      );
      await h.started.future.timeout(_wait);
      current = false;
      h.release.complete();
      expect((await preparing.timeout(_wait)).error, _canceled);
      expect(f.provider.isOAuthReady, isFalse);
      expect(f.auth.captureOAuthScopeLease, throwsA(_canceled));
      expect(await f.disk(), before);
      expect(f.store.mutations, writes);
      expect(f.requests, isEmpty);
    }),
  );

  test(
    'UI309-save-ack caller canceled after pending persistence rolls back exact previous attempt without HTTP',
    () => f.withHttp(() async {
      await f.login();
      await f.provider.prepareOAuthScope(initialize: true).timeout(_wait);
      final old = await f.save(f.provider);
      final before = await f.disk();
      final h = f.store.holdWrite(_pendingKey);
      var current = true;
      final work = f.observe<Map<String, String>>(
        f.save(
          f.provider,
          expected: old['attemptId'],
          requireExpected: true,
          current: () => current,
        ),
      );
      await h.started.future.timeout(_wait);
      final issued = OAuthOwnedPendingAuthorization.parse(
        h.value!,
        scope: f.auth.captureOAuthScopeLease().workspace.record,
      )!;
      expect(issued.attemptId, isNot(old['attemptId']));
      expect((await f.disk())[_pendingKey], h.value);
      current = false;
      h.release.complete();
      expect((await work.timeout(_wait)).error, _canceled);
      await AccountPreferenceWrites.drain().timeout(_wait);
      expect(OAuthCalendarStorage.failure, isNull);
      expect(await f.disk(), before);
      expect(f.requests, isEmpty);
      expect(f.provider.oauthLocalCommitReceipts, isEmpty);
    }),
  );

  for (final change in ['replacement', 'disappearance']) {
    for (final action in ['save', 'dispatch']) {
      test(
        'UI309-attempt-$change-$action supplied original attempt cannot adopt a changed durable claim',
        () => f.withHttp(() async {
          await f.login();
          await f.provider.prepareOAuthScope(initialize: true).timeout(_wait);
          final original = await f.save(f.provider);
          final peer = f.consumer();
          await peer.loadPendingOAuthAuthorization().timeout(_wait);
          if (change == 'replacement') {
            final replacement = await f.save(
              peer,
              expected: original['attemptId'],
              requireExpected: true,
            );
            expect(replacement['attemptId'], isNot(original['attemptId']));
            // Refresh the provider's legacy observed ID. Explicit CAS must still
            // obey the UI's original ID rather than this newer global observation.
            await f.provider.loadPendingOAuthAuthorization().timeout(_wait);
          } else {
            await peer
                .clearPendingOAuthAuthorization(
                  expectedAttemptId: original['attemptId'],
                )
                .timeout(_wait);
          }
          final before = await f.disk();
          final writes = f.store.mutations.toList();
          if (action == 'save') {
            await f.reject(
              f.save(
                f.provider,
                expected: original['attemptId'],
                requireExpected: true,
              ),
              _canceled,
            );
          } else {
            await f.reject(
              f.dispatch(f.provider, expected: original['attemptId']),
              _canceled,
            );
          }
          expect(await f.disk(), before);
          expect(f.store.mutations, writes);
          expect(f.requests, isEmpty);
          expect(f.provider.oauthLocalCommitReceipts, isEmpty);
        }),
      );
    }
  }

  test(
    'UI309-attempt-none explicit absent expectation rejects a pending draft despite legacy observation',
    () => f.withHttp(() async {
      await f.login();
      await f.provider.prepareOAuthScope(initialize: true).timeout(_wait);
      final saved = await f.save(f.provider, requireExpected: true);
      expect(saved['attemptId'], isNotEmpty);
      final before = await f.disk();
      final writes = f.store.mutations.toList();
      await f.reject(f.save(f.provider, requireExpected: true), _canceled);
      expect(await f.disk(), before);
      expect(f.store.mutations, writes);
      expect(f.requests, isEmpty);
    }),
  );

  test(
    'UI309-attempt-current saved return map identifies the exact dispatchable durable draft',
    () => f.withHttp(() async {
      await f.login();
      await f.provider.prepareOAuthScope(initialize: true).timeout(_wait);
      final saved = await f.save(f.provider, requireExpected: true);
      final pending = OAuthOwnedPendingAuthorization.parse(
        (await f.disk())[_pendingKey]! as String,
        scope: f.auth.captureOAuthScopeLease().workspace.record,
      )!;
      expect(saved['attemptId'], pending.attemptId);
      expect(saved['phase'], 'prepared');
      expect(saved['savedAt'], pending.savedAt.toIso8601String());
      for (final e in pending.draft.entries) {
        expect(saved[e.key], e.value);
      }
      final account = await f
          .dispatch(f.provider, expected: saved['attemptId'])
          .timeout(_wait);
      expect(account.accessToken, 'synthetic-ui309-access');
      expect(f.provider.oauthAccounts.single.id, account.id);
      expect(f.provider.allEvents().map((e) => e.title), [_title]);
      expect(f.requests, ['token', 'events']);
      expect((await f.disk()).containsKey(_pendingKey), isFalse);
    }),
  );

  test(
    'UI309-ready account prepare notifies empty providers and peer reset revokes readiness without writes',
    () => f.withHttp(() async {
      await f.login();
      final peer = f.consumer();
      final states = <bool>[];
      peer.addListener(() => states.add(peer.isOAuthReady));
      await f.provider.prepareOAuthScope(initialize: true).timeout(_wait);
      expect(peer.isOAuthReady, isTrue);
      expect(peer.oauthAccounts, isEmpty);
      expect(states, contains(true));
      final durable = await f.disk();
      final originalScope = f.auth.captureOAuthScopeLease().workspace.rawRecord;
      final writes = f.store.mutations.toList();
      states.clear();
      f.provider.resetLocalState();
      expect(peer.isOAuthReady, isFalse);
      // Storage observers coalesce changes into the next microtask; authority
      // itself is revoked synchronously before a pending UI action can proceed.
      await Future<void>.value();
      expect(states, contains(false));
      expect(await f.disk(), durable);
      expect(f.store.mutations, writes);
      await peer.prepareOAuthScope().timeout(_wait);
      expect(peer.isOAuthReady, isTrue);
      expect(
        f.auth.captureOAuthScopeLease().workspace.rawRecord,
        originalScope,
      );
      expect(await f.disk(), durable);
      expect(f.store.mutations, writes);
      expect(f.requests, isEmpty);
    }),
  );

  test(
    'UI309-account-actions canceled update and expected removed account cannot affect successor data',
    () => f.withHttp(() async {
      await f.install();
      final old = f.account!;
      final before = await f.disk();
      final writes = f.store.mutations.toList();
      var current = false;
      await f.reject(
        f.provider.updateOAuthAccount(
          old.copyWith(displayName: 'Canceled name'),
          isCurrent: () => current,
        ),
        _canceled,
      );
      await f.reject(
        f.provider.removeOAuthAccount(
          old.id,
          expectedAccount: old,
          isCurrent: () => current,
        ),
        _canceled,
      );
      expect(await f.disk(), before);
      expect(f.store.mutations, writes);
      final peer = f.consumer();
      await peer.loadFromStorage().timeout(_wait);
      await peer
          .removeOAuthAccount(
            old.id,
            expectedAccount: peer.oauthAccounts.single,
          )
          .timeout(_wait);
      final removed = await f.disk();
      final removedWrites = f.store.mutations.toList();
      await f.reject(
        f.provider.removeOAuthAccount(old.id, expectedAccount: old),
        _canceled,
      );
      expect(await f.disk(), removed);
      expect(f.store.mutations, removedWrites);
      expect(f.requests, ['token', 'events']);
    }),
  );
}

class _Result<T> {
  _Result.value(this.value) : error = null;
  _Result.error(this.error) : value = null;
  final T? value;
  final Object? error;
}

class _Hold {
  final started = Completer<void>();
  final release = Completer<void>();
  String? value;
}

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData({});
  final mutations = <String>[];
  final holds = <_Hold>[];
  final writeHolds = <String, _Hold>{};
  _Hold? reloadHold;
  _Hold holdWrite(String key) {
    final h = _Hold();
    writeHolds[key] = h;
    holds.add(h);
    return h;
  }

  _Hold holdReload() {
    final h = _Hold();
    reloadHold = h;
    holds.add(h);
    return h;
  }

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    final h = reloadHold;
    reloadHold = null;
    if (h != null) {
      h.started.complete();
      await h.release.future;
    }
    return super.getAllWithParameters(parameters);
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    mutations.add('set:${logical(key)}');
    final saved = await super.setValue(type, key, value);
    final h = writeHolds.remove(logical(key));
    if (h != null) {
      h.value = value as String;
      h.started.complete();
      await h.release.future;
    }
    return saved;
  }

  @override
  Future<bool> remove(String key) {
    mutations.add('remove:${logical(key)}');
    return super.remove(key);
  }

  @override
  Future<bool> clear() {
    mutations.add('clear');
    return super.clear();
  }

  Future<Map<String, Object>> backing() => super.getAll();
  Future<void> inject(String key, Object value) async {
    final type = switch (value) {
      String() => 'String',
      int() => 'Int',
      _ => throw ArgumentError('Unsupported fixture value'),
    };
    expect(await super.setValue(type, 'flutter.$key', value), isTrue);
  }

  static String logical(String key) =>
      key.startsWith('flutter.') ? key.substring(8) : key;
}

class _Fixture {
  _Fixture(this.previous, this.store, this.prefs);
  final SharedPreferencesStorePlatform previous;
  final _Store store;
  final SharedPreferences prefs;
  final auths = <AuthProvider>[];
  final providers = <CalendarSyncProvider>[];
  final clients = <http.Client>[];
  final pending = <Future<void>>[];
  final requests = <String>[];
  final verifier = OAuthCalendarClient.generateCodeVerifier();
  final state = OAuthCalendarClient.generateCodeVerifier();
  late AuthProvider auth;
  late CalendarSyncProvider provider;
  OAuthCalendarAccount? account;
  static Future<_Fixture> create() async {
    await AccountPreferenceWrites.drain().timeout(_wait);
    final previous = SharedPreferencesStorePlatform.instance;
    final store = _Store();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = store;
    final prefs = await SharedPreferences.getInstance();
    await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    for (final e in _ordinary.entries) {
      await store.inject(e.key, e.value);
    }
    await prefs.reload();
    store.mutations.clear();
    return _Fixture(previous, store, prefs);
  }

  Future<void> withHttp(Future<void> Function() body) =>
      http.runWithClient(body, client);
  http.Client client() {
    final c = MockClient((request) async {
      if (request.url.path == '/api/auth/login') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['username'], _account);
        expect(body['password'], 'synthetic-ui309-password');
        return _json({
          'token': 'synthetic-auth309-token',
          'user': {'id': _account, 'username': _account},
        });
      }
      if (request.url.path == '/api/config') return _json({});
      if (request.url.host == 'oauth2.googleapis.com' &&
          request.method == 'POST') {
        requests.add('token');
        final form = Uri.splitQueryString(request.body);
        expect(form['grant_type'], 'authorization_code');
        expect(form['client_id'], 'synthetic-ui309-client');
        expect(form['code_verifier'], verifier);
        expect(form['redirect_uri'], 'duoyi://oauth/calendar');
        return _json({
          'access_token': 'synthetic-ui309-access',
          'refresh_token': 'synthetic-ui309-refresh',
          'expires_in': 7200,
          'token_type': 'Bearer',
          'scope': 'https://www.googleapis.com/auth/calendar.readonly',
        });
      }
      if (request.url.host != 'www.googleapis.com' || request.method != 'GET') {
        throw StateError('Unexpected ui309 request');
      }
      requests.add('events');
      expect(request.headers['Authorization'], 'Bearer synthetic-ui309-access');
      return _json({
        'items': [
          {
            'id': 'ui309-event',
            'summary': _title,
            'start': {'dateTime': '2026-11-11T09:00:00Z'},
            'end': {'dateTime': '2026-11-11T10:00:00Z'},
          },
        ],
      });
    });
    clients.add(c);
    return c;
  }

  Future<void> login() async {
    auth = AuthProvider(
      client: ApiClient(baseUrl: 'https://ui309.example', httpClient: client()),
    );
    auths.add(auth);
    provider = consumer();
    await auth
        .login(username: _account, password: 'synthetic-ui309-password')
        .timeout(_wait);
    await AccountPreferenceWrites.drain().timeout(_wait);
    await Future<void>.delayed(Duration.zero);
    expect(auth.state.userId, _account);
    expect(
      (await disk())[AccountLocalDataCleaner.accountDataOwnerKey],
      'id:$_account',
    );
  }

  CalendarSyncProvider consumer() {
    final p = CalendarSyncProvider(authProvider: auth);
    providers.add(p);
    return p;
  }

  Future<void> install() async {
    await login();
    await provider.prepareOAuthScope(initialize: true).timeout(_wait);
    final draft = await save(provider);
    account = await dispatch(
      provider,
      expected: draft['attemptId'],
    ).timeout(_wait);
    expect(provider.allEvents().map((e) => e.title), [_title]);
  }

  Future<Map<String, String>> save(
    CalendarSyncProvider p, {
    String? expected,
    bool requireExpected = false,
    bool Function()? current,
  }) => p.savePendingOAuthAuthorization(
    provider: OAuthCalendarProvider.google,
    displayName: 'UI309 calendar',
    clientId: 'synthetic-ui309-client',
    clientSecret: '',
    redirectUri: 'duoyi://oauth/calendar',
    calendarId: 'primary',
    codeVerifier: verifier,
    state: state,
    expectedAttemptId: expected,
    requireExpectedAttempt: requireExpected,
    isCurrent: current,
  );
  Future<OAuthCalendarAccount> dispatch(
    CalendarSyncProvider p, {
    String? expected,
  }) => p.addOAuthAccountFromCode(
    provider: OAuthCalendarProvider.google,
    displayName: 'UI309 calendar',
    clientId: 'synthetic-ui309-client',
    clientSecret: '',
    redirectUri: 'duoyi://oauth/calendar',
    calendarId: 'primary',
    codeVerifier: verifier,
    expectedState: state,
    expectedAttemptId: expected,
    authorizationInput: OAuthAuthorizationInput.callback(
      Uri(
        scheme: 'duoyi',
        host: 'oauth',
        path: '/calendar',
        queryParameters: {'code': 'synthetic-ui309-code', 'state': state},
      ).toString(),
    ),
  );
  Future<dynamic> action(
    String action,
    bool Function() current, [
    CalendarSyncProvider? target,
  ]) {
    final p = target ?? provider;
    return switch (action) {
      'prepare' => p.prepareOAuthScope(initialize: true, isCurrent: current),
      'load' => p.loadPendingOAuthAuthorization(isCurrent: current),
      'save' => save(p, current: current),
      'clear' => p.clearPendingOAuthAuthorization(isCurrent: current),
      _ => throw ArgumentError('Unknown action'),
    };
  }

  Future<Map<String, Object>> disk() async => {
    for (final e in (await store.backing()).entries)
      _Store.logical(e.key): e.value,
  };
  Future<_Result<T>> observe<T>(Future<T> work) {
    final result = work.then<_Result<T>>(
      (value) => _Result<T>.value(value),
      onError: (Object error, StackTrace _) => _Result<T>.error(error),
    );
    pending.add(result.then<void>((_) {}));
    return result;
  }

  Future<void> reject<T>(Future<T> work, Matcher expected) async =>
      expect((await observe<T>(work).timeout(_wait)).error, expected);
  Future<void> close() async {
    store.reloadHold = null;
    store.writeHolds.clear();
    for (final h in store.holds) {
      if (!h.release.isCompleted) h.release.complete();
    }
    try {
      await Future.wait(pending).timeout(_wait);
      await AccountPreferenceWrites.drain().timeout(_wait);
      for (final p in providers) {
        p.dispose();
      }
      for (final a in auths) {
        a.dispose();
      }
      await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    } finally {
      for (final c in clients) {
        c.close();
      }
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = previous;
    }
  }
}

http.Response _json(Map<String, dynamic> value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);
