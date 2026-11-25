// Prepared406; migrated509 to the persisted refresh contract reviewed in503.
// No active product reads, compiler, formatter or execution.

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/oauth_authorization_input.dart';
import 'package:duoyi/core/oauth_calendar_storage.dart';
import 'package:duoyi/core/oauth_calendar_workspace_codec.dart';
import 'package:duoyi/core/oauth_refresh_journal.dart';
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
const _journal = OAuthCalendarStorage.refreshJournalKey;
const _account = 'refresh406-account';
const _ordinary = <String, Object>{
  'auth_state': '{ "token" : null }',
  'todos': '[ { "id" : "target406", "title" : "keep todo" } ]',
  'duoyi_notes': '[ { "body" : "keep note" } ]',
  'duoyi_ics_subscriptions_v1': '[]',
  'targeted406_setting': 406,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() async => f = await _Fixture.create());
  tearDown(() async => f.close());

  test(
    'OTR406-01 actual short expiry refreshes original credentials then commits only selected source events',
    () => f.withHttp(() async {
      await f.install();
      final before = await f.disk();
      final writes = f.store.mutations.toList();
      final requests = f.requests.toList();
      f.eventTitle = 'Targeted406 refreshed event';
      final result = await f.sync(f.first).timeout(_wait);
      expect(result.status, OAuthSyncStatus.refreshed);
      expect(result.sourceId, f.first.id);
      expect(result.isSuccess, isTrue);
      expect(result.eventCount, 1);
      expect(result.receipt, isNull);
      expect(f.requests, [...requests, 'refresh', 'events:primary']);
      expect(f.store.mutations, [
        ...writes,
        'set:$_journal',
        'set:$_journal',
        'set:$_accounts',
        'remove:$_journal',
        'set:${f.cacheKey(f.first.id)}',
        'set:$_accounts',
      ]);
      final actual = f.consumer.oauthAccounts.single;
      expect(actual.id, f.first.id);
      expect(actual.accessToken, 'synthetic-targeted406-renewed-access-2');
      expect(actual.refreshToken, 'synthetic-targeted406-renewed-refresh-2');
      expect(f.consumer.allEvents().single.title, f.eventTitle);
      expect(
        f.withoutTarget(await f.disk(), f.first.id),
        f.withoutTarget(before, f.first.id),
      );
      expect(OAuthCalendarStorage.failure, isNull);
      expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      expect((await f.disk()).containsKey(_journal), isFalse);
      f.expectOrdinary(await f.disk());
    }),
  );

  test(
    'OTR406-02 invalid actual refresh token format persists dispatch unknown with HTTP diagnostic and zero replay',
    () => f.withHttp(() async {
      await f.install();
      final before = await f.disk();
      final writes = f.store.mutations.toList();
      final requests = f.requests.toList();
      f.invalidRefreshToken = true;
      final result = await f.sync(f.first).timeout(_wait);
      expect(result.status, OAuthSyncStatus.dispatchUnknown);
      expect(result.diagnosticStatus, OAuthSyncStatus.httpFailure);
      expect(result.isSuccess, isFalse);
      expect(result.eventCount, 0);
      expect(result.receipt, isNull);
      expect(f.requests, [...requests, 'refresh']);
      expect(f.store.mutations, [...writes, 'set:$_journal']);
      final dispatchedDisk = await f.disk();
      f.expectJournal(dispatchedDisk, before, OAuthRefreshPhase.dispatched);
      expect(f.consumer.oauthAccounts.single.toJson(), f.first.toJson());
      expect(f.consumer.allEvents().single.title, 'Targeted406 initial event');
      expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      expect(OAuthCalendarStorage.failure, isNull);
      final attempted = f.requests.toList();
      final claimWrites = f.store.mutations.toList();
      final recovery = await f.consumer
          .loadOAuthRefreshRecovery(isCurrent: f.caller.isCurrent)
          .timeout(_wait);
      expect(recovery, isNotNull);
      expect(recovery!.sourceId, f.first.id);
      expect(recovery.phase, OAuthRefreshPhase.dispatched);
      expect(await f.disk(), dispatchedDisk);
      expect(f.store.mutations, claimWrites);
      expect(f.requests, attempted);
      final request = OAuthCalendarStorage.beginRequest(f.first.id);
      final refused = await f.sync(f.first).timeout(_wait);
      expect(refused.status, OAuthSyncStatus.dispatchUnknown);
      expect(refused.diagnosticStatus, isNull);
      expect(refused.isSuccess, isFalse);
      expect(refused.eventCount, 0);
      expect(refused.receipt, isNull);
      expect(OAuthCalendarStorage.ownsRequest(f.first.id, request), isTrue);
      expect(await f.disk(), dispatchedDisk);
      expect(f.store.mutations, claimWrites);
      expect(f.requests, attempted);
      expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      expect(OAuthCalendarStorage.failure, isNull);
      final source = OAuthCalendarStorage.sourceRevision(f.first.id);
      await expectLater(
        f.consumer
            .updateOAuthAccount(
              f.first.copyWith(displayName: 'Blocked unknown refresh rename'),
              isCurrent: f.caller.isCurrent,
            )
            .timeout(_wait),
        throwsA(isA<OAuthRefreshDispatchUnknown>()),
      );
      expect(OAuthCalendarStorage.sourceRevision(f.first.id), source);
      expect(OAuthCalendarStorage.ownsRequest(f.first.id, request), isTrue);
      expect(await f.disk(), dispatchedDisk);
      expect(f.store.mutations, claimWrites);
      expect(f.requests, attempted);
      expect(f.consumer.oauthAccounts.single.toJson(), f.first.toJson());
    }),
  );

  test(
    'OTR406-03 refreshed credential ACK false retains exact receipt and targeted refusal allocates no new request',
    () => f.withHttp(() async {
      await f.install();
      final before = await f.disk();
      final requests = f.requests.toList();
      f.store.failAccountsPhase = 1;
      final result = await f.sync(f.first).timeout(_wait);
      expect(result.status, OAuthSyncStatus.localCommitRequired);
      expect(result.isSuccess, isFalse);
      expect(result.eventCount, 0);
      expect(result.receipt, isA<OAuthLocalCommitReceipt>());
      final receipt = result.receipt!;
      expect(receipt.isRefresh, isTrue);
      expect(f.consumer.oauthLocalCommitReceipts.single, same(receipt));
      expect(OAuthCalendarStorage.failure, isNull);
      final receivedDisk = await f.disk();
      final received = f.expectJournal(
        receivedDisk,
        before,
        OAuthRefreshPhase.received,
        receipt: receipt,
      );
      expect(f.store.transactionPreimage, receivedDisk);
      expect(f.requests, [...requests, 'refresh']);
      final writes = f.store.mutations.toList();
      final attempted = f.requests.toList();
      final request = OAuthCalendarStorage.beginRequest(f.first.id);
      final refused = await f.sync(f.first).timeout(_wait);
      expect(refused.status, OAuthSyncStatus.localCommitRequired);
      expect(refused.receipt, same(receipt));
      expect(refused.isSuccess, isFalse);
      expect(OAuthCalendarStorage.ownsRequest(f.first.id, request), isTrue);
      expect(f.requests, attempted);
      expect(f.store.mutations, writes);
      expect(await f.disk(), receivedDisk);
      final installed = await f.consumer
          .retryOAuthLocalCommit(receipt, isCurrent: f.caller.isCurrent)
          .timeout(_wait);
      expect(installed.id, f.first.id);
      expect(installed.accessToken, 'synthetic-targeted406-renewed-access-2');
      expect(installed.refreshToken, 'synthetic-targeted406-renewed-refresh-2');
      expect(
        (await f.disk())[f.cacheKey(f.first.id)],
        before[f.cacheKey(f.first.id)],
      );
      expect(f.requests, attempted);
      expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      expect(f.store.mutations, [
        ...writes,
        'set:$_accounts',
        'remove:$_journal',
      ]);
      f.expectInstalledReceived(await f.disk(), before, received);
    }),
  );

  test(
    'OTR406-04 refresh ACK and compensation failure reports storage failure while original reconciliation retains receipt',
    () => f.withHttp(() async {
      await f.install();
      final before = await f.disk();
      final lease = f.auth.captureOAuthScopeLease();
      final requests = f.requests.toList();
      f.store.failAccountsPhase = 1;
      f.store.failCompensation = true;
      final result = await f.sync(f.first).timeout(_wait);
      expect(result.status, OAuthSyncStatus.storageFailure);
      expect(result.isSuccess, isFalse);
      expect(result.eventCount, 0);
      expect(f.requests, [...requests, 'refresh']);
      expect(OAuthCalendarStorage.failure, isA<OAuthStorageIndeterminate>());
      expect(f.consumer.isOAuthReady, isFalse);
      expect(f.auth.isOAuthScopeLeaseCurrent(lease), isFalse);
      expect(f.auth.isOAuthScopeLeaseRetainable(lease), isTrue);
      expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      expect(f.store.transactionPreimage, isNotNull);
      final preimage = f.store.transactionPreimage!;
      final received = f.expectJournal(
        preimage,
        before,
        OAuthRefreshPhase.received,
        scope: lease.workspace.record,
      );
      expect((await f.disk())[_journal], preimage[_journal]);
      final recovery = f.auth.captureOAuthReconciliationLease();
      expect(f.auth.isOAuthReconciliationLeaseCurrent(recovery), isTrue);
      final attempted = f.requests.toList();
      await f.consumer
          .reconcileOAuthStorage(isCurrent: f.caller.isCurrent)
          .timeout(_wait);
      expect(OAuthCalendarStorage.failure, isNull);
      expect(f.auth.isOAuthReconciliationSettled(recovery), isTrue);
      expect(await f.disk(), preimage);
      expect(f.requests, attempted);
      // Reconciliation restores durable bytes; the cleared projection must be
      // explicitly loaded before a targeted operation can select its source.
      final reloadWrites = f.store.mutations.toList();
      await f.consumer
          .loadFromStorage(isCurrent: f.caller.isCurrent)
          .timeout(_wait);
      expect(f.consumer.oauthAccounts.single.toJson(), f.first.toJson());
      expect(f.store.mutations, reloadWrites);
      expect(f.requests, attempted);
      final receipt = f.consumer.oauthLocalCommitReceipts.single;
      expect(receipt.isRefresh, isTrue);
      expect(receipt.handle, received.receiptHandle);
      expect(await f.disk(), preimage);
      final request = OAuthCalendarStorage.beginRequest(f.first.id);
      final writes = f.store.mutations.toList();
      final refused = await f.sync(f.first).timeout(_wait);
      expect(refused.status, OAuthSyncStatus.localCommitRequired);
      expect(refused.receipt, same(receipt));
      expect(OAuthCalendarStorage.ownsRequest(f.first.id, request), isTrue);
      expect(f.store.mutations, writes);
      expect(f.requests, attempted);
      expect(await f.disk(), preimage);
      final installed = await f.consumer
          .retryOAuthLocalCommit(receipt, isCurrent: f.caller.isCurrent)
          .timeout(_wait);
      expect(installed.id, f.first.id);
      expect(installed.accessToken, 'synthetic-targeted406-renewed-access-2');
      expect(installed.refreshToken, 'synthetic-targeted406-renewed-refresh-2');
      expect(
        (await f.disk())[f.cacheKey(f.first.id)],
        before[f.cacheKey(f.first.id)],
      );
      expect(f.requests, attempted);
      expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      expect(f.store.mutations, [
        ...writes,
        'set:$_accounts',
        'remove:$_journal',
      ]);
      f.expectInstalledReceived(await f.disk(), before, received);
    }),
  );

  test(
    'OTR406-05 synchronous reset in refreshed notification cancels old result while confirmed bytes survive',
    () => f.withHttp(() async {
      await f.install();
      final requests = f.requests.toList();
      final reset = OAuthCalendarStorage.resetRevision;
      final session = f.auth.captureSessionLease();
      final scope = f.auth.captureOAuthScopeLease().workspace.record;
      OAuthCalendarAccount? confirmed;
      var notifications = 0;
      void onSynced() {
        // Credential commit can notify before events. Select the actual event
        // publication, leaving that earlier real notification uninterrupted.
        if (!f.consumer.allEvents().any(
          (event) => event.title == f.eventTitle,
        )) {
          return;
        }
        notifications++;
        f.consumer.removeListener(onSynced);
        confirmed = f.consumer.oauthAccounts.single;
        OAuthCalendarStorage.invalidateReset();
      }

      f.consumer.addListener(onSynced);
      try {
        f.eventTitle = 'Targeted406 saved before reset';
        final result = await f.sync(f.first).timeout(_wait);
        expect(notifications, 1);
        expect(confirmed, isNotNull);
        expect(
          confirmed!.accessToken,
          'synthetic-targeted406-renewed-access-2',
        );
        expect(result.status, OAuthSyncStatus.canceled);
        expect(result.isSuccess, isFalse);
        expect(OAuthCalendarStorage.resetRevision, reset + 1);
        expect(OAuthCalendarStorage.failure, isNull);
        expect(f.consumer.isOAuthReady, isFalse);
        expect(f.auth.isSessionLeaseCurrent(session), isTrue);
        expect(f.requests, [...requests, 'refresh', 'events:primary']);
        final disk = await f.disk();
        final rows = OAuthOwnedSourceRecord.parseList(
          disk[_accounts]! as String,
          scope: scope,
        )!;
        expect(rows.single.account['accessToken'], confirmed!.accessToken);
        expect(disk[f.cacheKey(f.first.id)], contains(f.eventTitle));
        expect(disk.containsKey(_journal), isFalse);
      } finally {
        f.consumer.removeListener(onSynced);
      }
    }),
  );

  test(
    'OTR406-06 busy refresh peer returns canceled without taking original request ownership',
    () => f.withHttp(() async {
      await f.install();
      final peer = f.newConsumer();
      await peer.loadFromStorage().timeout(_wait);
      final before = await f.disk();
      final writes = f.store.mutations.toList();
      final requests = f.requests.toList();
      final marker = OAuthCalendarStorage.beginRequest(f.first.id);
      final hold = f.holdRefresh();
      final original = f.observe<OAuthSyncResult>(f.sync(f.first));
      await hold.started.future.timeout(_wait);
      expect(OAuthCalendarStorage.ownsRequest(f.first.id, marker + 1), isTrue);
      final dispatchedDisk = await f.disk();
      f.expectJournal(dispatchedDisk, before, OAuthRefreshPhase.dispatched);
      final claimWrites = f.store.mutations.toList();
      expect(claimWrites, [...writes, 'set:$_journal']);
      final other = await peer
          .syncOAuthAccount(
            f.first.id,
            expectedAccount: peer.oauthAccounts.single,
            isCurrent: f.caller.isCurrent,
          )
          .timeout(_wait);
      // The persisted claim refuses this peer before request allocation.
      expect(other.status, OAuthSyncStatus.dispatchUnknown);
      expect(other.diagnosticStatus, isNull);
      expect(other.isSuccess, isFalse);
      expect(other.receipt, isNull);
      expect(OAuthCalendarStorage.ownsRequest(f.first.id, marker + 1), isTrue);
      expect(f.requests, [...requests, 'refresh']);
      expect(await f.disk(), dispatchedDisk);
      expect(f.store.mutations, claimWrites);
      hold.release.complete();
      final finished = await original.timeout(_wait);
      expect(finished.error, isNull);
      expect(finished.value!.status, OAuthSyncStatus.refreshed);
      expect(finished.value!.eventCount, 1);
      expect(f.requests, [...requests, 'refresh', 'events:primary']);
      expect(
        f.consumer.oauthAccounts.single.accessToken,
        'synthetic-targeted406-renewed-access-2',
      );
      expect((await f.disk()).containsKey(_journal), isFalse);
    }),
  );
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
  int failAccountsPhase = 0;
  bool failCompensation = false;
  Map<String, Object>? transactionPreimage;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    mutations.add('set:${logical(key)}');
    if (logical(key) == _accounts && failAccountsPhase == 1) {
      transactionPreimage = {
        for (final entry in (await super.getAll()).entries)
          logical(entry.key): entry.value,
      };
      expect(await super.setValue(type, key, value), isTrue);
      failAccountsPhase = 2;
      return false;
    }
    if (logical(key) == _accounts && failAccountsPhase == 2) {
      failAccountsPhase = 0;
      if (failCompensation) {
        return false;
      }
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
      _ => throw ArgumentError('Unsupported406 fixture value'),
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
  int refreshCalls = 0;
  bool invalidRefreshToken = false;
  String latestAccess = '';
  _Hold? refreshHold;
  String eventTitle = 'Targeted406 initial event';

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
        expect(body['password'], 'synthetic-targeted406-password');
        return _json({
          'token': 'synthetic-targeted406-auth',
          'user': {'id': _account, 'username': _account},
        });
      }
      if (request.url.path == '/api/config') {
        return _json({});
      }
      if (request.url.host == 'oauth2.googleapis.com' &&
          request.method == 'POST') {
        final form = Uri.splitQueryString(request.body);
        expect(form['client_id'], 'synthetic-targeted406-client');
        if (form['grant_type'] == 'refresh_token') {
          requests.add('refresh');
          expect(form.containsKey('code'), isFalse);
          expect(
            form['refresh_token'],
            refreshCalls == 0
                ? 'synthetic-targeted406-refresh-1'
                : 'synthetic-targeted406-renewed-refresh-$refreshCalls',
          );
          refreshCalls++;
          final hold = refreshHold;
          refreshHold = null;
          if (hold != null) {
            hold.started.complete();
            await hold.release.future;
          }
          if (invalidRefreshToken) {
            return _json({'access_token': 42, 'expires_in': 7200});
          }
          latestAccess = 'synthetic-targeted406-renewed-access-$refreshCalls';
          return _json({
            'access_token': latestAccess,
            'refresh_token':
                'synthetic-targeted406-renewed-refresh-$refreshCalls',
            'expires_in': refreshCalls == 1 ? 60 : 7200,
            'token_type': 'Bearer',
          });
        }
        requests.add('token');
        expect(form['grant_type'], 'authorization_code');
        expect(form['code_verifier'], verifier);
        tokenCalls++;
        latestAccess = 'synthetic-targeted406-access-$tokenCalls';
        return _json({
          'access_token': latestAccess,
          'refresh_token': 'synthetic-targeted406-refresh-$tokenCalls',
          'expires_in': 60,
          'token_type': 'Bearer',
        });
      }
      if (request.url.host != 'www.googleapis.com' || request.method != 'GET') {
        requests.add('unexpected');
        throw StateError(
          'Unexpected406 HTTP; targeted sync must not request ICS',
        );
      }
      final calendarId = request
          .url
          .pathSegments[request.url.pathSegments.indexOf('calendars') + 1];
      expect(request.headers['Authorization'], 'Bearer $latestAccess');
      requests.add('events:$calendarId');
      return _json({
        'items': [
          {
            'id': 'target406-$calendarId',
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
        baseUrl: 'https://targeted406.example',
        httpClient: client(),
      ),
    );
    auths.add(auth);
    await auth
        .login(username: _account, password: 'synthetic-targeted406-password')
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
    expect(requests, ['token', 'refresh', 'events:primary']);
    expect(refreshCalls, 1);
    expect(
      first.expiresAt.isBefore(DateTime.now().add(const Duration(minutes: 2))),
      isTrue,
    );
  }

  Future<OAuthCalendarAccount> connect(String calendarId) async {
    final draft = await consumer.savePendingOAuthAuthorization(
      provider: OAuthCalendarProvider.google,
      displayName: 'Targeted406 $calendarId',
      clientId: 'synthetic-targeted406-client',
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
      displayName: 'Targeted406 $calendarId',
      clientId: 'synthetic-targeted406-client',
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
            'code': 'synthetic-targeted406-code-${tokenCalls + 1}',
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

  _Hold holdRefresh() {
    final hold = _Hold();
    refreshHold = hold;
    httpHolds.add(hold);
    return hold;
  }

  String cacheKey(String id) => '${OAuthCalendarStorage.eventsKeyPrefix}$id';
  Future<Map<String, Object>> disk() async => {
    for (final e in (await store.backing()).entries)
      _Store.logical(e.key): e.value,
  };
  OAuthOwnedRefreshJournal expectJournal(
    Map<String, Object> actual,
    Map<String, Object> before,
    OAuthRefreshPhase phase, {
    OAuthScopedOwnerRecord? scope,
    OAuthLocalCommitReceipt? receipt,
  }) {
    expect(before.containsKey(_journal), isFalse);
    expect({
      for (final entry in actual.entries)
        if (entry.key != _journal) entry.key: entry.value,
    }, before);
    final actualScope = scope ?? auth.captureOAuthScopeLease().workspace.record;
    final raw = actual[_journal];
    expect(raw, isA<String>());
    final journal = OAuthOwnedRefreshJournal.parse(
      raw as String,
      scope: actualScope,
    );
    expect(journal, isNotNull);
    final saved = journal!;
    expect(saved.encode(), raw);
    expect(saved.phase, phase);
    expect(saved.sourceAccountId, first.id);
    expect(saved.operationId, isNotEmpty);
    expect(saved.receiptHandle, isNotEmpty);
    final original = OAuthOwnedSourceRecord.parseList(
      before[_accounts]! as String,
      scope: actualScope,
    )!.single;
    expect(saved.originalSource.encode(), original.encode());
    if (phase == OAuthRefreshPhase.received) {
      expect(saved.returnedSource, isNotNull);
      expect(saved.receivedAt, isNotNull);
      expect(
        saved.returnedSource!.account['accessToken'],
        'synthetic-targeted406-renewed-access-2',
      );
      expect(
        saved.returnedSource!.account['refreshToken'],
        'synthetic-targeted406-renewed-refresh-2',
      );
    } else {
      expect(saved.returnedSource, isNull);
      expect(saved.receivedAt, isNull);
    }
    if (receipt != null) expect(saved.receiptHandle, receipt.handle);
    return saved;
  }

  void expectInstalledReceived(
    Map<String, Object> actual,
    Map<String, Object> before,
    OAuthOwnedRefreshJournal received,
  ) {
    expect(actual.containsKey(_journal), isFalse);
    expect(withoutTarget(actual, first.id), withoutTarget(before, first.id));
    expect(actual[cacheKey(first.id)], before[cacheKey(first.id)]);
    final installed = OAuthOwnedSourceRecord.parseList(
      actual[_accounts]! as String,
      scope: auth.captureOAuthScopeLease().workspace.record,
    )!.single;
    // Exact fixed bytes also cover expiry, revision, incarnation and metadata.
    expect(installed.encode(), received.returnedSource!.encode());
  }

  Map<String, Object> withoutTarget(Map<String, Object> raw, String id) => {
    for (final e in raw.entries)
      if (e.key != _accounts && e.key != cacheKey(id)) e.key: e.value,
  };
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
    store.failAccountsPhase = 0;
    store.failCompensation = false;
    refreshHold = null;
    for (final hold in httpHolds) {
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
