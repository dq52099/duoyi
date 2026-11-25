// Prepared398 using frozen396 and the owner's targeted-sync API contract.
// No active product reads, formatter, compiler or execution.

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
import 'package:shared_preferences_platform_interface/types.dart';

const _wait = Duration(seconds: 5);
const _accounts = OAuthCalendarStorage.accountsKey;
const _pendingKey = OAuthCalendarStorage.pendingAuthorizationKey;
const _account = 'targeted398-account';
const _ordinary = <String, Object>{
  'auth_state': '{ "token" : null }',
  'todos': '[ { "id" : "target398", "title" : "keep todo" } ]',
  'duoyi_notes': '[ { "body" : "keep note" } ]',
  'duoyi_ics_subscriptions_v1': '[]',
  'targeted398_setting': 398,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() async => f = await _Fixture.create());
  tearDown(() async => f.close());

  test(
    'OTS398-01 targeted refresh touches only original source and never requests ICS or other account',
    () => f.withHttp(() async {
      await f.install();
      final second = await f.connect('second').timeout(_wait);
      await f.consumer
          .addSubscription(
            const IcsSubscription(
              id: 'target398-ics',
              name: 'Keep ICS',
              url: 'https://ics398.example/calendar.ics',
            ),
            isCurrent: f.caller.isCurrent,
          )
          .timeout(_wait);
      final first = f.consumer.oauthAccounts.singleWhere(
        (a) => a.id == f.first.id,
      );
      final before = await f.disk();
      final secondStoredRow = f.storedSource(before, second.id);
      final secondDto = f.consumer.oauthAccounts
          .singleWhere((a) => a.id == second.id)
          .toJson();
      final requests = f.requests.toList();
      final writes = f.store.mutations.toList();
      f.eventTitle = 'Targeted398 fresh event';
      final result = await f.sync(first).timeout(_wait);
      expect(result.status, OAuthSyncStatus.refreshed);
      expect(result.sourceId, first.id);
      expect(result.eventCount, 1);
      expect(result.isSuccess, isTrue);
      expect(result.receipt, isNull);
      expect(f.requests, [...requests, 'events:primary']);
      final after = await f.disk();
      expect(f.store.mutations, [
        ...writes,
        'set:${f.cacheKey(first.id)}',
        'set:$_accounts',
      ]);
      expect(
        f.withoutTarget(after, first.id),
        f.withoutTarget(before, first.id),
      );
      expect(
        f.consumer.oauthAccounts.singleWhere((a) => a.id == second.id).toJson(),
        secondDto,
      );
      expect(f.storedSource(after, second.id), secondStoredRow);
      expect(
        f.consumer.allEvents().where((e) => e.title == f.eventTitle),
        hasLength(1),
      );
      expect(after[f.cacheKey(first.id)], isNot(before[f.cacheKey(first.id)]));
      f.expectOrdinary(after);
    }),
  );

  for (final boundary in ['before', 'reload', 'response']) {
    test(
      'OTS398-02-$boundary original caller cancellation preserves original cache and emits no stale write',
      () => f.withHttp(() async {
        await f.install();
        final before = await f.disk();
        final writes = f.store.mutations.toList();
        final requests = f.requests.toList();
        final caller = _Caller();
        late OAuthSyncResult result;
        if (boundary == 'before') {
          caller.cancel();
          result = await f.sync(f.first, caller: caller).timeout(_wait);
        } else {
          final hold = boundary == 'reload'
              ? f.store.holdReload()
              : f.holdEvents();
          final work = f.observe<OAuthSyncResult>(
            f.sync(f.first, caller: caller),
          );
          await hold.started.future.timeout(_wait);
          caller.cancel();
          hold.release.complete();
          final observed = await work.timeout(_wait);
          expect(observed.error, isNull);
          result = observed.value!;
        }
        expect(result.status, OAuthSyncStatus.canceled);
        expect(result.sourceId, f.first.id);
        expect(result.eventCount, 0);
        expect(result.isSuccess, isFalse);
        expect(result.receipt, isNull);
        expect(await f.disk(), before);
        expect(f.store.mutations, writes);
        expect(
          f.requests,
          boundary == 'response' ? [...requests, 'events:primary'] : requests,
        );
        expect(f.consumer.oauthAccounts.single.toJson(), f.first.toJson());
        expect(
          f.consumer.allEvents().single.title,
          'Targeted398 initial event',
        );
        expect(OAuthCalendarStorage.failure, isNull);
      }),
    );
  }

  test(
    'OTS398-03 original expected row rejects peer metadata replacement before allocating a new request',
    () => f.withHttp(() async {
      await f.install();
      final opening = f.first;
      final peer = f.newConsumer();
      await peer.loadFromStorage().timeout(_wait);
      final originalPeerRow = peer.oauthAccounts.single;
      await peer
          .updateOAuthAccount(
            originalPeerRow.copyWith(displayName: 'Peer changed name'),
            isCurrent: f.caller.isCurrent,
          )
          .timeout(_wait);
      final before = await f.disk();
      final writes = f.store.mutations.toList();
      final requests = f.requests.toList();
      final request = OAuthCalendarStorage.beginRequest(opening.id);
      final source = OAuthCalendarStorage.sourceRevision(opening.id);
      final result = await f.sync(opening).timeout(_wait);
      expect(result.status, OAuthSyncStatus.canceled);
      expect(result.isSuccess, isFalse);
      expect(result.sourceId, opening.id);
      expect(result.eventCount, 0);
      expect(result.receipt, isNull);
      expect(OAuthCalendarStorage.ownsRequest(opening.id, request), isTrue);
      expect(OAuthCalendarStorage.sourceRevision(opening.id), source);
      expect(await f.disk(), before);
      expect(f.store.mutations, writes);
      expect(f.requests, requests);
      expect(peer.oauthAccounts.single.displayName, 'Peer changed name');
      expect(before[f.cacheKey(opening.id)], isNotNull);
    }),
  );

  test(
    'OTS398-04 actual received uninstalled source is unavailable without request allocation and remains locally recoverable',
    () => f.withHttp(() async {
      await f.install();
      final originalCache = (await f.disk())[f.cacheKey(f.first.id)];
      f.store.rejectNextAccounts = true;
      final connecting = await f
          .observe<OAuthCalendarAccount>(f.connect('received'))
          .timeout(_wait);
      expect(connecting.error, isA<OAuthLocalCommitRequired>());
      final receipt = (connecting.error! as OAuthLocalCommitRequired).receipt;
      await AccountPreferenceWrites.drain().timeout(_wait);
      expect(OAuthCalendarStorage.failure, isNull);
      final before = await f.disk();
      final pending = OAuthOwnedPendingAuthorization.parse(
        before[_pendingKey]! as String,
        scope: f.auth.captureOAuthScopeLease().workspace.record,
      )!;
      expect(pending.phase, OAuthPendingPhase.received);
      expect(receipt.handle, pending.receiptHandle);
      final id = pending.sourceAccountId!;
      final requests = f.requests.toList();
      final writes = f.store.mutations.toList();
      final request = OAuthCalendarStorage.beginRequest(id);
      final result = await f.consumer
          .syncOAuthAccount(id, isCurrent: f.caller.isCurrent)
          .timeout(_wait);
      // A returned new candidate has no installed row yet. Public targeted
      // sync cannot turn that data into authority or expose its credentials.
      expect(result.status, OAuthSyncStatus.unavailable);
      expect(result.sourceId, id);
      expect(result.isSuccess, isFalse);
      expect(result.eventCount, 0);
      expect(result.receipt, isNull);
      expect(OAuthCalendarStorage.ownsRequest(id, request), isTrue);
      expect(await f.disk(), before);
      expect(f.store.mutations, writes);
      expect(f.requests, requests);
      final restored = await f.consumer
          .retryOAuthLocalCommit(receipt, isCurrent: f.caller.isCurrent)
          .timeout(_wait);
      expect(restored.id, id);
      expect(
        restored.accessToken,
        pending.receivedSource!.account['accessToken'],
      );
      expect((await f.disk()).containsKey(_pendingKey), isFalse);
      expect((await f.disk())[f.cacheKey(f.first.id)], originalCache);
      expect(f.requests, requests);
    }),
  );

  for (final failure in ['http', 'invalid']) {
    test(
      'OTS398-05-$failure typed failure preserves confirmed cache and last synced source bytes',
      () => f.withHttp(() async {
        await f.install();
        final before = await f.disk();
        final writes = f.store.mutations.toList();
        final requests = f.requests.toList();
        f.responseFailure = failure;
        final result = await f.sync(f.first).timeout(_wait);
        expect(
          result.status,
          failure == 'http'
              ? OAuthSyncStatus.httpFailure
              : OAuthSyncStatus.invalidCalendar,
        );
        expect(result.isSuccess, isFalse);
        expect(result.sourceId, f.first.id);
        expect(result.eventCount, 0);
        expect(result.receipt, isNull);
        expect(f.requests, [...requests, 'events:primary']);
        expect(await f.disk(), before);
        expect(f.store.mutations, writes);
        expect(f.consumer.oauthAccounts.single.toJson(), f.first.toJson());
        expect(
          f.consumer.allEvents().single.title,
          'Targeted398 initial event',
        );
        expect(OAuthCalendarStorage.failure, isNull);
      }),
    );
  }
}

class _Caller {
  bool _active = true;
  bool isCurrent() => _active;
  void cancel() => _active = false;
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
}

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData({});
  final mutations = <String>[];
  final holds = <_Hold>[];
  _Hold? reloadHold;
  bool rejectNextAccounts = false;

  _Hold holdReload() {
    final hold = _Hold();
    reloadHold = hold;
    holds.add(hold);
    return hold;
  }

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    final hold = reloadHold;
    reloadHold = null;
    if (hold != null) {
      hold.started.complete();
      await hold.release.future;
    }
    return super.getAllWithParameters(parameters);
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    mutations.add('set:${logical(key)}');
    if (logical(key) == _accounts && rejectNextAccounts) {
      rejectNextAccounts = false;
      return false;
    }
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
      _ => throw ArgumentError('Unsupported398 fixture value'),
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
  final caller = _Caller();
  final auths = <AuthProvider>[];
  final consumers = <CalendarSyncProvider>[];
  final clients = <http.Client>[];
  final pending = <Future<void>>[];
  final requests = <String>[];
  final httpHolds = <_Hold>[];
  final verifier = OAuthCalendarClient.generateCodeVerifier();
  final state = OAuthCalendarClient.generateCodeVerifier();
  late AuthProvider auth;
  late CalendarSyncProvider consumer;
  late OAuthCalendarAccount first;
  int tokenCalls = 0;
  String eventTitle = 'Targeted398 initial event';
  String? responseFailure;
  _Hold? eventsHold;

  static Future<_Fixture> create() async {
    await AccountPreferenceWrites.drain().timeout(_wait);
    final previous = SharedPreferencesStorePlatform.instance;
    final store = _Store();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = store;
    final prefs = await SharedPreferences.getInstance();
    await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    for (final entry in _ordinary.entries) {
      await store.inject(entry.key, entry.value);
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
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['username'], _account);
        expect(body['password'], 'synthetic-targeted398-password');
        return _json({
          'token': 'synthetic-targeted398-auth',
          'user': {'id': _account, 'username': _account},
        });
      }
      if (request.url.path == '/api/config') {
        return _json({});
      }
      if (request.url.host == 'oauth2.googleapis.com' &&
          request.method == 'POST') {
        final form = Uri.splitQueryString(request.body);
        requests.add('token');
        expect(form['grant_type'], 'authorization_code');
        expect(form['code_verifier'], verifier);
        expect(form['client_id'], 'synthetic-targeted398-client');
        tokenCalls++;
        return _json({
          'access_token': 'synthetic-targeted398-access-$tokenCalls',
          'refresh_token': 'synthetic-targeted398-refresh-$tokenCalls',
          'expires_in': 7200,
          'token_type': 'Bearer',
        });
      }
      if (request.url.host != 'www.googleapis.com' || request.method != 'GET') {
        requests.add('unexpected');
        throw StateError(
          'Unexpected398 HTTP; targeted sync must not request ICS',
        );
      }
      final calendarId = request
          .url
          .pathSegments[request.url.pathSegments.indexOf('calendars') + 1];
      expect(
        request.headers['Authorization'],
        calendarId == 'primary'
            ? 'Bearer synthetic-targeted398-access-1'
            : 'Bearer synthetic-targeted398-access-2',
      );
      requests.add('events:$calendarId');
      final hold = eventsHold;
      eventsHold = null;
      if (hold != null) {
        hold.started.complete();
        await hold.release.future;
      }
      if (responseFailure == 'http') {
        return http.Response('Synthetic failure398', 503);
      }
      if (responseFailure == 'invalid') {
        return _json({
          'items': [42],
        });
      }
      return _json({
        'items': [
          {
            'id': 'target398-$calendarId',
            'summary': eventTitle,
            'start': {'dateTime': '2026-11-12T09:00:00Z'},
            'end': {'dateTime': '2026-11-12T10:00:00Z'},
          },
        ],
      });
    });
    clients.add(client);
    return client;
  }

  CalendarSyncProvider newConsumer() {
    final provider = CalendarSyncProvider(authProvider: auth);
    consumers.add(provider);
    return provider;
  }

  Future<void> install() async {
    auth = AuthProvider(
      client: ApiClient(
        baseUrl: 'https://targeted398.example',
        httpClient: client(),
      ),
    );
    auths.add(auth);
    await auth
        .login(username: _account, password: 'synthetic-targeted398-password')
        .timeout(_wait);
    await AccountPreferenceWrites.drain().timeout(_wait);
    await Future<void>.delayed(Duration.zero);
    expect(
      (await disk())[AccountLocalDataCleaner.accountDataOwnerKey],
      'id:$_account',
    );
    consumer = newConsumer();
    await consumer
        .prepareOAuthScope(initialize: true, isCurrent: caller.isCurrent)
        .timeout(_wait);
    first = await connect('primary').timeout(_wait);
    expect(consumer.isOAuthReady, isTrue);
    expect(consumer.allEvents().single.title, eventTitle);
    expect(requests, ['token', 'events:primary']);
  }

  Future<OAuthCalendarAccount> connect(String calendarId) async {
    final draft = await consumer.savePendingOAuthAuthorization(
      provider: OAuthCalendarProvider.google,
      displayName: 'Targeted398 $calendarId',
      clientId: 'synthetic-targeted398-client',
      clientSecret: '',
      redirectUri: 'duoyi://oauth/calendar',
      calendarId: calendarId,
      codeVerifier: verifier,
      state: state,
      requireExpectedAttempt: true,
      isCurrent: caller.isCurrent,
    );
    final result = await consumer.addOAuthAccountFromCode(
      provider: OAuthCalendarProvider.google,
      displayName: 'Targeted398 $calendarId',
      clientId: 'synthetic-targeted398-client',
      clientSecret: '',
      redirectUri: 'duoyi://oauth/calendar',
      calendarId: calendarId,
      codeVerifier: verifier,
      expectedState: state,
      expectedAttemptId: draft['attemptId'],
      authorizationInput: OAuthAuthorizationInput.callback(
        Uri(
          scheme: 'duoyi',
          host: 'oauth',
          path: '/calendar',
          queryParameters: {
            'code': 'synthetic-targeted398-code-${tokenCalls + 1}',
            'state': state,
          },
        ).toString(),
      ),
      isCurrent: caller.isCurrent,
    );
    // Return the published, lastSyncedAt-bearing real DTO as opening authority.
    return consumer.oauthAccounts.singleWhere(
      (account) => account.id == result.id,
    );
  }

  Future<OAuthSyncResult> sync(
    OAuthCalendarAccount opening, {
    _Caller? caller,
  }) => consumer.syncOAuthAccount(
    opening.id,
    expectedAccount: opening,
    isCurrent: (caller ?? this.caller).isCurrent,
  );

  _Hold holdEvents() {
    final hold = _Hold();
    eventsHold = hold;
    httpHolds.add(hold);
    return hold;
  }

  String cacheKey(String id) => '${OAuthCalendarStorage.eventsKeyPrefix}$id';
  Future<Map<String, Object>> disk() async => {
    for (final e in (await store.backing()).entries)
      _Store.logical(e.key): e.value,
  };
  Map<String, Object> withoutTarget(Map<String, Object> raw, String id) => {
    for (final e in raw.entries)
      if (e.key != _accounts && e.key != cacheKey(id)) e.key: e.value,
  };
  String storedSource(Map<String, Object> raw, String id) =>
      OAuthOwnedSourceRecord.parseList(
        raw[_accounts]! as String,
        scope: auth.captureOAuthScopeLease().workspace.record,
      )!.singleWhere((row) => row.account['id'] == id).encode();
  void expectOrdinary(Map<String, Object> raw) {
    for (final entry in _ordinary.entries.where(
      (e) => e.key != 'auth_state' && e.key != 'duoyi_ics_subscriptions_v1',
    )) {
      expect(raw[entry.key], entry.value, reason: entry.key);
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

  Future<void> close() async {
    caller.cancel();
    store.rejectNextAccounts = false;
    store.reloadHold = null;
    eventsHold = null;
    for (final hold in [...store.holds, ...httpHolds]) {
      if (!hold.release.isCompleted) {
        hold.release.complete();
      }
    }
    try {
      await Future.wait(pending).timeout(_wait);
      await AccountPreferenceWrites.drain().timeout(_wait);
      for (final consumer in consumers) {
        consumer.dispose();
      }
      for (final issuer in auths) {
        issuer.dispose();
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
