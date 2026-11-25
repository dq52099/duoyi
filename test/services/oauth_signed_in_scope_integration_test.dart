// ignore_for_file: depend_on_referenced_packages
// Real signed-in Auth/session + consumer contracts. These compile against the
// existing public consumer API but deliberately require signed-in scope support.
// Frozen259 consumer preparation is guest-only: positive cases are unmet, not
// skipped or treated as passing merely because preparation currently rejects.

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/oauth_authorization_input.dart';
import 'package:duoyi/core/oauth_calendar_storage.dart';
import 'package:duoyi/core/oauth_calendar_workspace_codec.dart';
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

const _wait = Duration(seconds: 5);
const _accounts = OAuthCalendarStorage.accountsKey;
const _scopeKey = OAuthCalendarStorage.scopeOwnerKey;
const _pendingKey = OAuthCalendarStorage.pendingAuthorizationKey;
const _accountOwner = AccountLocalDataCleaner.accountDataOwnerKey;
const _a = 'signed259-account-a';
const _b = 'signed259-account-b';
const _eventTitle = 'Signed259 real OAuth event';
const _ordinary = <String, Object>{
  'auth_state': '{ "token" : null }',
  'todos': '[ { "id" : "signed259_todo", "title" : "keep imported todo" } ]',
  'duoyi_notes': '[ { "body" : "keep imported note259" } ]',
  'duoyi_ics_subscriptions_v1': '[]',
  'signed259_device_setting': 259,
};

Matcher get _authorityError => anyOf(
  isA<ApiException>(),
  isA<AccountPreferenceWriteCanceled>(),
  isA<OAuthScopedWorkspaceUnavailable>(),
  isA<OAuthAccountRetirementPending>(),
  isA<AccountLocalDataCleanupBlockedException>(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() async => f = await _Fixture.create());
  tearDown(() async => f.close());

  test(
    'OSI259-01 real login prepares account scope connects and cold restores readonly',
    () => f.withHttp(() async {
      final auth = await f.login(_a);
      final session = auth.captureSessionLease();
      expect(auth.isSessionLeaseCurrent(session), isTrue);
      final consumer = f.consumer(auth);
      expect(consumer.isOAuthReady, isFalse);
      final beforePreparation = await f.disk();
      expect(beforePreparation[_accountOwner], 'id:$_a');
      final authBytes = beforePreparation['auth_state'];
      // Positive contract: the real issuer must prepare an account scope here.
      // No new private/public Auth lease type is fabricated by this fixture.
      await consumer.prepareOAuthScope(initialize: true).timeout(_wait);
      expect(consumer.isOAuthReady, isTrue);
      final prepared = await f.disk();
      final scope = f.accountScope(prepared, _a);
      expect(prepared['auth_state'], authBytes);
      expect(prepared[_accountOwner], beforePreparation[_accountOwner]);
      expect(auth.isSessionLeaseCurrent(session), isTrue);
      final account = await f.connect(consumer).timeout(_wait);
      expect(f.count('token'), 1);
      expect(f.count('events'), 1);
      final persisted = await f.disk();
      final source = f.source(persisted, scope);
      expect(source.account['id'], account.id);
      expect(source.account['accessToken'], 'synthetic-signed259-access');
      expect(source.account['refreshToken'], 'synthetic-signed259-refresh');
      final cache = OAuthOwnedEventsRecord.parse(
        persisted[f.cacheKey(account.id)]! as String,
        source: source,
      )!;
      expect(cache.events.single['title'], _eventTitle);
      expect(cache.sourceAccountId, account.id);
      expect(consumer.allEvents().map((e) => e.title), [_eventTitle]);
      expect(auth.isSessionLeaseCurrent(session), isTrue);
      f.expectImportedOrdinary(persisted);
      f.disposeConsumer(consumer);
      f.disposeAuth(auth);

      final coldAuth = f.auth();
      final coldConsumer = f.consumer(coldAuth);
      final oauthBefore = f.oauthData(persisted);
      final requests = f.oauthRequests.toList();
      f.store.mutations.clear();
      await coldAuth.loadFromStorage(refreshServerConfig: false).timeout(_wait);
      final coldSession = coldAuth.captureSessionLease();
      expect(coldAuth.state.userId, _a);
      await coldConsumer.prepareOAuthScope().timeout(_wait);
      await coldConsumer.loadFromStorage().timeout(_wait);
      await f.settle();
      final restored = await f.disk();
      expect(coldConsumer.isOAuthReady, isTrue);
      expect(coldAuth.isSessionLeaseCurrent(coldSession), isTrue);
      expect(f.accountScope(restored, _a).encode(), scope.encode());
      expect(f.oauthData(restored), oauthBefore);
      expect(f.store.oauthMutations, isEmpty);
      expect(f.oauthRequests, requests);
      expect(coldConsumer.oauthAccounts.single.toJson(), account.toJson());
      expect(coldConsumer.allEvents().map((e) => e.title), [_eventTitle]);
      f.expectImportedOrdinary(restored);
    }),
  );

  test(
    'OSI259-02 real session without prepared scope cannot dispatch or save pending',
    () => f.withHttp(() async {
      final auth = await f.login(_a);
      final session = auth.captureSessionLease();
      final consumer = f.consumer(auth);
      final before = await f.disk();
      f.store.mutations.clear();
      await f.reject(f.dispatch(consumer), _authorityError);
      await f.reject(f.savePending(consumer), _authorityError);
      await f.settle();
      expect(auth.isSessionLeaseCurrent(session), isTrue);
      expect(consumer.isOAuthReady, isFalse);
      expect(consumer.oauthAccounts, isEmpty);
      expect(consumer.oauthLocalCommitReceipts, isEmpty);
      expect(await f.disk(), before);
      expect(f.store.mutations, isEmpty);
      expect(f.oauthRequests, isEmpty);
    }),
  );

  for (final phase in ['token', 'events']) {
    for (final boundary in ['logout', 'account-switch']) {
      test(
        'OSI259-held-$phase $boundary revokes real session and rejects late OAuth work',
        () => f.withHttp(() async {
          final auth = await f.login(_a);
          final session = auth.captureSessionLease();
          final consumer = f.consumer(auth);
          await consumer.prepareOAuthScope(initialize: true).timeout(_wait);
          final oldScope = f.accountScope(await f.disk(), _a);
          final hold = f.hold(phase);
          final connecting = f.observe(f.connect(consumer));
          await hold.started.future.timeout(_wait);
          final dispatched = await f.disk();
          if (phase == 'token') {
            final pending = OAuthOwnedPendingAuthorization.parse(
              dispatched[_pendingKey]! as String,
              scope: oldScope,
            )!;
            expect(pending.phase, OAuthPendingPhase.dispatched);
          } else {
            final source = f.source(dispatched, oldScope);
            expect(
              dispatched.containsKey(
                f.cacheKey(source.account['id']! as String),
              ),
              isFalse,
            );
          }
          // A real transition must finish while network is held. No fixture
          // reset, raw auth write, callback substitution or boolean permission.
          if (boundary == 'logout') {
            await auth.logout().timeout(_wait);
            expect(auth.state.isLoggedIn, isFalse);
          } else {
            await f.login(_b, auth: auth);
            expect(auth.state.userId, _b);
            expect(auth.state.isLoggedIn, isTrue);
          }
          expect(auth.isSessionLeaseCurrent(session), isFalse);
          await f.settle();
          final boundaryDisk = await f.disk();
          expect(f.oauthData(boundaryDisk), isEmpty);
          expect(consumer.oauthAccounts, isEmpty);
          expect(consumer.allEvents(), isEmpty);
          final requests = f.oauthRequests.toList();
          final mutations = f.store.mutations.toList();
          var notifications = 0;
          consumer.addListener(() => notifications++);
          hold.release.complete();
          final result = await connecting.timeout(_wait);
          expect(result.error, _authorityError);
          await f.settle();
          expect(await f.disk(), boundaryDisk);
          expect(f.store.mutations, mutations);
          expect(f.oauthRequests, requests);
          expect(consumer.oauthAccounts, isEmpty);
          expect(consumer.allEvents(), isEmpty);
          expect(consumer.oauthLocalCommitReceipts, isEmpty);
          expect(notifications, 0);
          if (phase == 'token') expect(f.count('events'), 0);
          if (boundary == 'account-switch') {
            expect(boundaryDisk[_accountOwner], 'id:$_b');
            expect(
              auth.isSessionLeaseCurrent(auth.captureSessionLease()),
              isTrue,
            );
          }
        }),
      );
    }
  }

  test(
    'OSI259-03 real guest login retires guest OAuth before independent account prepare',
    () => f.withHttp(() async {
      final guestAuth = f.auth();
      await guestAuth
          .loadFromStorage(refreshServerConfig: false)
          .timeout(_wait);
      final guestConsumer = f.consumer(guestAuth);
      await guestConsumer.prepareOAuthScope(initialize: true).timeout(_wait);
      final guestLease = guestAuth.captureGuestOAuthScopeLease();
      final guestAccount = await f.connect(guestConsumer).timeout(_wait);
      final guestDisk = await f.disk();
      final guestScope = OAuthScopedOwnerRecord.parse(guestDisk[_scopeKey])!;
      expect(guestScope.scopeKind, 'guest');
      final guestSource = f.source(guestDisk, guestScope);
      final guestCache = guestDisk[f.cacheKey(guestAccount.id)]! as String;
      // A fresh real issuer logs in on the same actual backing store. The old
      // guest issuer is kept alive so retirement must invalidate its lease.
      final accountAuth = await f.login(_a);
      expect(guestAuth.isGuestOAuthScopeLeaseCurrent(guestLease), isFalse);
      expect(guestConsumer.oauthAccounts, isEmpty);
      final retired = await f.disk();
      expect(f.oauthData(retired), isEmpty);
      f.expectImportedOrdinary(retired);
      final accountConsumer = f.consumer(accountAuth);
      await accountConsumer.prepareOAuthScope(initialize: true).timeout(_wait);
      final accountScope = f.accountScope(await f.disk(), _a);
      expect(accountScope.scopedOwner, isNot(guestScope.scopedOwner));
      expect(accountScope.oauthIncarnation, isNot(guestScope.oauthIncarnation));
      expect(
        OAuthOwnedSourceRecord.parse(guestSource.encode(), scope: accountScope),
        isNull,
      );
      final account = await f
          .connect(accountConsumer, code: 'synthetic-signed259-second-code')
          .timeout(_wait);
      final current = await f.disk();
      final currentSource = f.source(current, accountScope);
      expect(currentSource.account['id'], account.id);
      expect(currentSource.account['id'], isNot(guestAccount.id));
      expect(
        OAuthOwnedEventsRecord.parse(guestCache, source: currentSource),
        isNull,
      );
      expect(current.containsKey(f.cacheKey(guestAccount.id)), isFalse);
      expect(accountConsumer.oauthAccounts.single.id, account.id);
      expect(guestConsumer.oauthAccounts, isEmpty);
      f.expectImportedOrdinary(current);
    }),
  );

  test(
    'OSI259-04 real account logout creates an independent empty guest OAuth scope',
    () => f.withHttp(() async {
      final auth = await f.login(_a);
      final session = auth.captureSessionLease();
      final accountConsumer = f.consumer(auth);
      await accountConsumer.prepareOAuthScope(initialize: true).timeout(_wait);
      final accountScope = f.accountScope(await f.disk(), _a);
      final account = await f.connect(accountConsumer).timeout(_wait);
      final signedDisk = await f.disk();
      final accountSource = f.source(signedDisk, accountScope);
      await auth.logout().timeout(_wait);
      expect(auth.isSessionLeaseCurrent(session), isFalse);
      expect(accountConsumer.oauthAccounts, isEmpty);
      expect(f.oauthData(await f.disk()), isEmpty);
      f.disposeConsumer(accountConsumer);
      f.disposeAuth(auth);
      final guestAuth = f.auth();
      await guestAuth
          .loadFromStorage(refreshServerConfig: false)
          .timeout(_wait);
      final guestConsumer = f.consumer(guestAuth);
      await guestConsumer.prepareOAuthScope(initialize: true).timeout(_wait);
      final guestLease = guestAuth.captureGuestOAuthScopeLease();
      expect(guestAuth.isGuestOAuthScopeLeaseCurrent(guestLease), isTrue);
      final guestDisk = await f.disk();
      final guestScope = OAuthScopedOwnerRecord.parse(guestDisk[_scopeKey])!;
      expect(guestScope.scopeKind, 'guest');
      expect(guestScope.scopedOwner, isNot(accountScope.scopedOwner));
      expect(guestScope.oauthIncarnation, isNot(accountScope.oauthIncarnation));
      expect(guestDisk.containsKey(_accountOwner), isFalse);
      expect(guestDisk.containsKey(f.cacheKey(account.id)), isFalse);
      expect(
        OAuthOwnedSourceRecord.parse(accountSource.encode(), scope: guestScope),
        isNull,
      );
      expect(guestConsumer.oauthAccounts, isEmpty);
      expect(guestConsumer.allEvents(), isEmpty);
    }),
  );
}

class _BackingStore extends InMemorySharedPreferencesStore {
  _BackingStore() : super.withData({});
  final mutations = <String>[];
  List<String> get oauthMutations => mutations
      .where(
        (m) =>
            m != 'clear' &&
            OAuthCalendarStorage.isOAuthScopeKey(
              m.substring(m.indexOf(':') + 1),
            ),
      )
      .toList();
  @override
  Future<bool> setValue(String type, String key, Object value) {
    mutations.add('set:${logical(key)}');
    return super.setValue(type, key, value);
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

class _Result<T> {
  _Result.value(this.value) : error = null;
  _Result.error(this.error) : value = null;
  final T? value;
  final Object? error;
}

class _Hold {
  _Hold(this.phase);
  final String phase;
  final started = Completer<void>();
  final release = Completer<void>();
}

class _Fixture {
  _Fixture(this.previous, this.store, this.prefs);
  final SharedPreferencesStorePlatform previous;
  final _BackingStore store;
  final SharedPreferences prefs;
  final auths = <AuthProvider>[];
  final consumers = <CalendarSyncProvider>[];
  final clients = <http.Client>[];
  final oauthRequests = <String>[];
  final apiRequests = <String>[];
  final pending = <Future<void>>[];
  final holds = <_Hold>[];
  final verifier = OAuthCalendarClient.generateCodeVerifier();
  final state = OAuthCalendarClient.generateCodeVerifier();

  static Future<_Fixture> create() async {
    await AccountPreferenceWrites.drain().timeout(_wait);
    final previous = SharedPreferencesStorePlatform.instance;
    final store = _BackingStore();
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
    final client = MockClient((request) async {
      if (request.url.path == '/api/auth/login') {
        apiRequests.add('login');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final username = body['username'] as String;
        expect(username, anyOf(_a, _b));
        expect(body['password'], 'synthetic-signed259-password');
        return _json({
          'token': 'synthetic-auth259-$username',
          'user': {'id': username, 'username': username},
        });
      }
      if (request.url.path == '/api/config') {
        apiRequests.add('config');
        return _json({});
      }
      if (request.url.path == '/api/auth/logout') {
        apiRequests.add('logout');
        expect(
          request.headers['Authorization'],
          startsWith('Bearer synthetic-auth259-'),
        );
        return _json({});
      }
      final phase =
          request.method == 'POST' &&
              request.url.host == 'oauth2.googleapis.com'
          ? 'token'
          : request.method == 'GET' && request.url.host == 'www.googleapis.com'
          ? 'events'
          : 'unexpected';
      oauthRequests.add(phase);
      if (phase == 'unexpected') {
        throw StateError('Unexpected signed259 request');
      }
      final active = holds.where(
        (h) => h.phase == phase && !h.started.isCompleted,
      );
      if (active.isNotEmpty) {
        final hold = active.first;
        hold.started.complete();
        await hold.release.future;
      }
      if (phase == 'token') {
        final form = Uri.splitQueryString(request.body);
        expect(form['grant_type'], 'authorization_code');
        expect(form['client_id'], 'synthetic-signed259-client');
        expect(form['code_verifier'], verifier);
        return _json({
          'access_token': 'synthetic-signed259-access',
          'refresh_token': 'synthetic-signed259-refresh',
          'expires_in': 7200,
          'token_type': 'Bearer',
          'scope': 'https://www.googleapis.com/auth/calendar.readonly',
        });
      }
      expect(
        request.headers['Authorization'],
        'Bearer synthetic-signed259-access',
      );
      return _json({
        'items': [
          {
            'id': 'signed259-event',
            'summary': _eventTitle,
            'start': {'dateTime': '2026-11-10T09:00:00Z'},
            'end': {'dateTime': '2026-11-10T10:00:00Z'},
          },
        ],
      });
    });
    clients.add(client);
    return client;
  }

  AuthProvider auth() {
    final auth = AuthProvider(
      client: ApiClient(
        baseUrl: 'https://signed259.example',
        httpClient: client(),
      ),
    );
    auths.add(auth);
    return auth;
  }

  Future<AuthProvider> login(String account, {AuthProvider? auth}) async {
    final issuer = auth ?? this.auth();
    await issuer
        .login(username: account, password: 'synthetic-signed259-password')
        .timeout(_wait);
    await settle();
    expect(issuer.state.isLoggedIn, isTrue);
    expect(issuer.state.userId, account);
    expect(issuer.isAccountTransitionInProgress, isFalse);
    expect(issuer.isLocalAccountDataBlocked, isFalse);
    expect(issuer.isSessionLeaseCurrent(issuer.captureSessionLease()), isTrue);
    expect((await disk())[_accountOwner], 'id:$account');
    return issuer;
  }

  CalendarSyncProvider consumer(AuthProvider auth) {
    final consumer = CalendarSyncProvider(authProvider: auth);
    consumers.add(consumer);
    return consumer;
  }

  void disposeAuth(AuthProvider auth) {
    auth.dispose();
    auths.remove(auth);
  }

  void disposeConsumer(CalendarSyncProvider consumer) {
    consumer.dispose();
    consumers.remove(consumer);
  }

  int count(String phase) => oauthRequests.where((p) => p == phase).length;
  _Hold hold(String phase) {
    final h = _Hold(phase);
    holds.add(h);
    return h;
  }

  String cacheKey(String id) => '${OAuthCalendarStorage.eventsKeyPrefix}$id';
  Future<void> savePending(CalendarSyncProvider consumer) =>
      consumer.savePendingOAuthAuthorization(
        provider: OAuthCalendarProvider.google,
        displayName: 'Signed259 calendar',
        clientId: 'synthetic-signed259-client',
        clientSecret: '',
        redirectUri: 'duoyi://oauth/calendar',
        calendarId: 'primary',
        codeVerifier: verifier,
        state: state,
      );
  Future<OAuthCalendarAccount> connect(
    CalendarSyncProvider consumer, {
    String code = 'synthetic-signed259-code',
  }) async {
    await savePending(consumer);
    return dispatch(consumer, code: code);
  }

  Future<OAuthCalendarAccount> dispatch(
    CalendarSyncProvider consumer, {
    String code = 'synthetic-signed259-code',
  }) => consumer.addOAuthAccountFromCode(
    provider: OAuthCalendarProvider.google,
    displayName: 'Signed259 calendar',
    clientId: 'synthetic-signed259-client',
    clientSecret: '',
    redirectUri: 'duoyi://oauth/calendar',
    calendarId: 'primary',
    codeVerifier: verifier,
    expectedState: state,
    authorizationInput: OAuthAuthorizationInput.callback(
      Uri(
        scheme: 'duoyi',
        host: 'oauth',
        path: '/calendar',
        queryParameters: {'code': code, 'state': state},
      ).toString(),
    ),
  );
  OAuthScopedOwnerRecord accountScope(Map<String, Object> raw, String account) {
    final scope = OAuthScopedOwnerRecord.parse(raw[_scopeKey])!;
    expect(scope.scopeKind, 'account');
    expect(scope.matchesAccountOwner('id:$account'), isTrue);
    expect(scope.matchesAccountOwner(null), isFalse);
    expect(scope.matchesAccountOwner('id:${account == _a ? _b : _a}'), isFalse);
    expect(raw[_accountOwner], 'id:$account');
    return scope;
  }

  OAuthOwnedSourceRecord source(
    Map<String, Object> raw,
    OAuthScopedOwnerRecord scope,
  ) {
    final rows = OAuthOwnedSourceRecord.parseList(
      raw[_accounts]! as String,
      scope: scope,
    )!;
    expect(rows, hasLength(1));
    return rows.single;
  }

  Map<String, Object> oauthData(Map<String, Object> raw) => {
    for (final e in raw.entries.where(
      (e) => OAuthCalendarStorage.isOAuthScopeKey(e.key),
    ))
      e.key: e.value,
  };
  Future<Map<String, Object>> disk() async => {
    for (final e in (await store.backing()).entries)
      _BackingStore.logical(e.key): e.value,
  };
  void expectImportedOrdinary(Map<String, Object> raw) {
    for (final e in _ordinary.entries.where((e) => e.key != 'auth_state')) {
      expect(raw[e.key], e.value, reason: e.key);
    }
  }

  Future<_Result<T>> observe<T>(Future<T> work) {
    final result = work.then<_Result<T>>(
      (value) => _Result<T>.value(value),
      onError: (Object error, StackTrace _) => _Result<T>.error(error),
    );
    pending.add(result.then<void>((_) {}));
    return result;
  }

  Future<void> reject<T>(Future<T> work, Matcher expected) async {
    expect((await observe(work).timeout(_wait)).error, expected);
  }

  Future<void> settle() async {
    await AccountPreferenceWrites.drain().timeout(_wait);
    await OAuthCalendarStorage.run<void>(
      () async {},
      epoch: OAuthCalendarStorage.epoch,
    ).timeout(_wait);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> close() async {
    for (final h in holds) {
      if (!h.release.isCompleted) h.release.complete();
    }
    try {
      await Future.wait(pending).timeout(_wait);
      await settle();
      for (final consumer in consumers) {
        consumer.dispose();
      }
      for (final auth in auths) {
        auth.dispose();
      }
      await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    } finally {
      for (final client in clients) {
        client.close();
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
