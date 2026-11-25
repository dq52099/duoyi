// Prepared527: two live real Auth issuers over one mock backing store.
// Source preparation only; no cold-process, device or durability claim.
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
const _account = 'refresh527-account';
const _ordinary = <String, Object>{
  'todos': '[ { "id" : "527", "title" : "keep todo" } ]',
  'duoyi_notes': '[ { "body" : "keep note" } ]',
  'duoyi_ics_subscriptions_v1': '[]',
  'refresh527_setting': 527,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() async => f = await _Fixture.create());
  tearDown(() async => f.close());

  test(
    'RJI527-01 live eligible issuer cannot lend its receipt to a second readonly issuer',
    () => f.withHttp('old', () async {
      await f.install();
      final opening = f.oldConsumer.oauthAccounts.single;
      final before = await f.disk();
      final oldLease = f.oldAuth.captureOAuthScopeLease();
      final sourceRevision = OAuthCalendarStorage.sourceRevision(opening.id);
      final epoch = OAuthCalendarStorage.epoch;
      final reset = OAuthCalendarStorage.resetRevision;
      final generation = AccountPreferenceWrites.generation;
      final owner = AccountLocalDataCleaner.accountDataGeneration;
      expect(oldLease.workspace.record.scopeKind, 'account');
      expect(f.oldAuth.isOAuthScopeLeaseCurrent(oldLease), isTrue);
      expect(OAuthCalendarStorage.ownsRequest(opening.id, 1), isTrue);
      final previous = f.source(before, oldLease);
      final requestsBeforeRefresh = f.requests.toList();
      final writesBeforeRefresh = f.store.mutations.toList();

      // The fault targets the genuine accounts install, after received is
      // confirmed. Its checked rollback preserves that already saved journal.
      f.store.failNextAccountsAfterPersist = true;
      final failed = await f.oldConsumer
          .syncOAuthAccount(
            opening.id,
            expectedAccount: opening,
            isCurrent: f.caller.isCurrent,
          )
          .timeout(_wait);
      expect(failed.status, OAuthSyncStatus.localCommitRequired);
      expect(failed.sourceId, opening.id);
      expect(failed.isSuccess, isFalse);
      expect(failed.eventCount, 0);
      final oldReceipt = failed.receipt!;
      expect(oldReceipt.isRefresh, isTrue);
      expect(f.store.accountsFaults, 1);
      expect(f.store.mutations, [
        ...writesBeforeRefresh,
        'set:$_journal',
        'set:$_journal',
        'set:$_accounts',
        'set:$_accounts',
      ]);
      expect(OAuthCalendarStorage.failure, isNull);
      expect(f.oldConsumer.isOAuthReady, isTrue);
      expect(f.oldAuth.isOAuthScopeLeaseCurrent(oldLease), isTrue);
      expect(f.oldAuth.isOAuthScopeLeaseRetainable(oldLease), isTrue);
      expect(f.caller.isCurrent(), isTrue);
      expect(f.oldConsumer.oauthLocalCommitReceipts.single, same(oldReceipt));
      expect(OAuthCalendarStorage.ownsRequest(opening.id, 2), isTrue);
      expect(f.requests, [...requestsBeforeRefresh, 'old:refresh']);

      final receivedDisk = await f.disk();
      final received = f.journal(receivedDisk, oldLease);
      expect(received.phase, OAuthRefreshPhase.received);
      expect(received.sourceAccountId, opening.id);
      expect(received.receiptHandle, oldReceipt.handle);
      expect(received.originalSource.encode(), previous.encode());
      expect(received.scopedOwner, oldLease.workspace.record.scopedOwner);
      expect(
        received.oauthIncarnation,
        oldLease.workspace.record.oauthIncarnation,
      );
      expect(received.dispatchedAt.isUtc, isTrue);
      expect(received.receivedAt!.isUtc, isTrue);
      expect(received.receivedAt!.isBefore(received.dispatchedAt), isFalse);
      expect(f.store.confirmedReceived, contains(received.encode()));
      expect(f.store.failedAccountsPreimage, receivedDisk);
      expect(f.without(receivedDisk, {_journal}), before);
      expect(f.source(receivedDisk, oldLease).encode(), previous.encode());
      final target = received.returnedSource!;
      expect(target.sourceIncarnation, previous.sourceIncarnation);
      expect(target.metadataRevision, previous.metadataRevision);
      expect(target.credentialRevision, previous.credentialRevision + 1);
      expect(target.scopedOwner, previous.scopedOwner);
      expect(target.oauthIncarnation, previous.oauthIncarnation);
      expect(target.account['accessToken'], 'synthetic527-renewed-access-2');
      expect(target.account['refreshToken'], 'synthetic527-renewed-refresh-2');
      final originalMetadata = Map<String, Object?>.from(previous.account)
        ..remove('accessToken')
        ..remove('refreshToken')
        ..remove('expiresAt');
      final returnedMetadata = Map<String, Object?>.from(target.account)
        ..remove('accessToken')
        ..remove('refreshToken')
        ..remove('expiresAt');
      expect(returnedMetadata, originalMetadata);
      expect(
        DateTime.parse(target.account['expiresAt']! as String).isUtc,
        isTrue,
      );
      final writes = f.store.mutations.toList();
      final requests = f.requests.toList();

      await f.withHttp('new', () async {
        // Retain both original objects: no dispose, reset, login or caller
        // cancellation can manufacture eligibility for the second issuer.
        final newAuth = f.newAuth('new');
        expect(newAuth, isNot(same(f.oldAuth)));
        await newAuth
            .loadFromStorage(refreshServerConfig: false)
            .timeout(_wait);
        expect(f.oldAuth.isOAuthScopeLeaseCurrent(oldLease), isTrue);
        expect(f.oldConsumer.oauthLocalCommitReceipts.single, same(oldReceipt));
        expect(f.store.mutations, writes);
        expect(f.requests, requests);
        expect(await f.disk(), receivedDisk);
        final newConsumer = f.newConsumer(newAuth);
        expect(newConsumer, isNot(same(f.oldConsumer)));
        await newConsumer
            .prepareOAuthScope(initialize: false, isCurrent: f.caller.isCurrent)
            .timeout(_wait);
        expect(f.oldAuth.isOAuthScopeLeaseCurrent(oldLease), isTrue);
        expect(f.oldConsumer.oauthLocalCommitReceipts.single, same(oldReceipt));
        final newLease = newAuth.captureOAuthScopeLease();
        expect(newLease, isNot(same(oldLease)));
        expect(newLease.workspace.rawRecord, oldLease.workspace.rawRecord);
        expect(newAuth.isOAuthScopeLeaseCurrent(newLease), isTrue);
        expect(f.store.mutations, writes);
        expect(f.requests, requests);
        expect(await f.disk(), receivedDisk);

        await newConsumer
            .loadFromStorage(isCurrent: f.caller.isCurrent)
            .timeout(_wait);
        final state = await newConsumer
            .loadOAuthRefreshRecovery(isCurrent: f.caller.isCurrent)
            .timeout(_wait);
        expect(state!.phase, OAuthRefreshPhase.received);
        expect(state.sourceId, opening.id);
        expect(newConsumer.isOAuthReady, isTrue);
        expect(newConsumer.oauthAccounts.single.toJson(), opening.toJson());
        expect(newConsumer.allEvents().single.title, 'Initial527 event');
        final newReceipt = newConsumer.oauthLocalCommitReceipts.single;
        expect(newReceipt.isRefresh, isTrue);
        expect(newReceipt.handle, received.receiptHandle);
        expect(newReceipt, isNot(same(oldReceipt)));
        expect(f.oldAuth.isOAuthScopeLeaseCurrent(oldLease), isTrue);
        expect(f.oldAuth.isOAuthScopeLeaseRetainable(oldLease), isTrue);
        expect(f.oldConsumer.isOAuthReady, isTrue);
        expect(f.caller.isCurrent(), isTrue);
        expect(OAuthCalendarStorage.epoch, epoch);
        expect(OAuthCalendarStorage.resetRevision, reset);
        expect(AccountPreferenceWrites.generation, generation);
        expect(AccountLocalDataCleaner.accountDataGeneration, owner);
        expect(OAuthCalendarStorage.sourceRevision(opening.id), sourceRevision);
        expect(OAuthCalendarStorage.ownsRequest(opening.id, 2), isTrue);
        expect(f.store.mutations, writes);
        expect(f.requests, requests);
        expect(await f.disk(), receivedDisk);

        // A public wrong-object retry, while the old issuer remains alive.
        await expectLater(
          newConsumer
              .retryOAuthLocalCommit(oldReceipt, isCurrent: f.caller.isCurrent)
              .timeout(_wait),
          throwsA(isA<AccountPreferenceWriteCanceled>()),
        );
        expect(newConsumer.oauthLocalCommitReceipts.single, same(newReceipt));
        expect(f.oldAuth.isOAuthScopeLeaseCurrent(oldLease), isTrue);
        expect(f.store.mutations, writes);
        expect(f.requests, requests);
        expect(await f.disk(), receivedDisk);

        final installed = await newConsumer
            .retryOAuthLocalCommit(newReceipt, isCurrent: f.caller.isCurrent)
            .timeout(_wait);
        expect(installed.toJson(), target.account);
        final settled = await f.disk();
        expect(f.source(settled, newLease).encode(), target.encode());
        expect(settled.containsKey(_journal), isFalse);
        expect(
          f.without(settled, {_accounts, _journal}),
          f.without(receivedDisk, {_accounts, _journal}),
        );
        expect(settled[f.cacheKey(opening.id)], before[f.cacheKey(opening.id)]);
        expect(f.store.mutations, [
          ...writes,
          'set:$_accounts',
          'remove:$_journal',
        ]);
        expect(f.requests, requests);
        expect(f.requests.where((r) => r.startsWith('new:')), isEmpty);
        expect(newConsumer.oauthLocalCommitReceipts, isEmpty);
        expect(OAuthCalendarStorage.ownsRequest(opening.id, 2), isTrue);
        expect(OAuthCalendarStorage.sourceRevision(opening.id), sourceRevision);
        expect(f.oldAuth.isOAuthScopeLeaseCurrent(oldLease), isTrue);
        expect(newAuth.isOAuthScopeLeaseCurrent(newLease), isTrue);
        expect(OAuthCalendarStorage.failure, isNull);
        for (final entry in _ordinary.entries) {
          expect(settled[entry.key], entry.value, reason: entry.key);
        }
      });
    }),
  );
}

class _Caller {
  bool _active = true;
  bool isCurrent() => _active;
  void cancel() => _active = false;
}

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData({});
  final mutations = <String>[];
  final acknowledgedJournals = <String>{};
  final confirmedClaims = <String>{};
  final confirmedReceived = <String>{};
  bool failNextAccountsAfterPersist = false;
  int accountsFaults = 0;
  Map<String, Object>? failedAccountsPreimage;

  @override
  Future<Map<String, Object>> getAll() async {
    final raw = await super.getAll();
    final journal = raw['flutter.$_journal'] ?? raw[_journal];
    if (journal is String && acknowledgedJournals.contains(journal)) {
      final phase = (jsonDecode(journal) as Map<String, dynamic>)['phase'];
      if (phase == 'dispatched') confirmedClaims.add(journal);
      if (phase == 'received') confirmedReceived.add(journal);
    }
    return raw;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    final name = logical(key);
    mutations.add('set:$name');
    if (name == _accounts && failNextAccountsAfterPersist) {
      failNextAccountsAfterPersist = false;
      accountsFaults++;
      failedAccountsPreimage = normalize(await super.getAll());
      final journal = failedAccountsPreimage![_journal]! as String;
      expect(
        (jsonDecode(journal) as Map<String, dynamic>)['phase'],
        'received',
      );
      expect(confirmedReceived, contains(journal));
      expect(await super.setValue(type, key, value), isTrue);
      return false;
    }
    final result = await super.setValue(type, key, value);
    if (name == _journal && result && value is String) {
      acknowledgedJournals.add(value);
    }
    return result;
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

  Future<Map<String, Object>> backing() async =>
      normalize(await super.getAll());
  Future<void> seedOrdinary() async {
    for (final entry in _ordinary.entries) {
      expect(
        await super.setValue(
          entry.value is int ? 'Int' : 'String',
          'flutter.${entry.key}',
          entry.value,
        ),
        isTrue,
      );
    }
  }

  static String logical(String key) =>
      key.startsWith('flutter.') ? key.substring(8) : key;
  static Map<String, Object> normalize(Map<String, Object> raw) => {
    for (final entry in raw.entries) logical(entry.key): entry.value,
  };
}

class _Fixture {
  _Fixture(this.previous, this.store);
  final SharedPreferencesStorePlatform previous;
  final _Store store;
  final caller = _Caller();
  final auths = <AuthProvider>[];
  final consumers = <CalendarSyncProvider>[];
  final clients = <http.Client>[];
  final requests = <String>[];
  final verifier = OAuthCalendarClient.generateCodeVerifier();
  final state = OAuthCalendarClient.generateCodeVerifier();
  late AuthProvider oldAuth;
  late CalendarSyncProvider oldConsumer;
  int refreshCalls = 0;
  String latestAccess = '';

  static Future<_Fixture> create() async {
    await AccountPreferenceWrites.drain().timeout(_wait);
    final previous = SharedPreferencesStorePlatform.instance;
    final store = _Store();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = store;
    await SharedPreferences.getInstance();
    await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    await store.seedOrdinary();
    store.mutations.clear();
    return _Fixture(previous, store);
  }

  Future<void> withHttp(String issuer, Future<void> Function() body) =>
      http.runWithClient(body, () => client(issuer));

  http.Client client(String issuer) {
    final client = MockClient((request) async {
      // Every transport category is recorded, including Auth and unknown URLs.
      if (request.url.path == '/api/auth/login') {
        requests.add('$issuer:login');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['username'], _account);
        expect(body['password'], 'synthetic527-password');
        return _json({
          'token': 'synthetic527-auth',
          'user': {'id': _account, 'username': _account},
        });
      }
      if (request.url.path == '/api/config') {
        requests.add('$issuer:config');
        return _json({});
      }
      if (request.url.host == 'oauth2.googleapis.com' &&
          request.method == 'POST') {
        final form = Uri.splitQueryString(request.body);
        expect(form['client_id'], 'synthetic527-client');
        if (form['grant_type'] == 'refresh_token') {
          requests.add('$issuer:refresh');
          final claim = journal(await disk(), oldAuth.captureOAuthScopeLease());
          expect(claim.phase, OAuthRefreshPhase.dispatched);
          expect(store.confirmedClaims, contains(claim.encode()));
          expect(
            form['refresh_token'],
            refreshCalls == 0
                ? 'synthetic527-refresh-1'
                : 'synthetic527-renewed-refresh-$refreshCalls',
          );
          expect(form.containsKey('code'), isFalse);
          refreshCalls++;
          latestAccess = 'synthetic527-renewed-access-$refreshCalls';
          return _json({
            'access_token': latestAccess,
            'refresh_token': 'synthetic527-renewed-refresh-$refreshCalls',
            'expires_in': refreshCalls == 1 ? 60 : 7200,
            'token_type': 'Bearer',
          });
        }
        requests.add('$issuer:token');
        expect(form['grant_type'], 'authorization_code');
        expect(form['code'], 'synthetic527-code');
        expect(form['code_verifier'], verifier);
        latestAccess = 'synthetic527-access-1';
        return _json({
          'access_token': latestAccess,
          'refresh_token': 'synthetic527-refresh-1',
          'expires_in': 60,
          'token_type': 'Bearer',
        });
      }
      if (request.url.host == 'www.googleapis.com' &&
          request.method == 'GET' &&
          request.url.path.endsWith('/calendars/primary/events')) {
        requests.add('$issuer:events:primary');
        expect(request.headers['Authorization'], 'Bearer $latestAccess');
        return _json({
          'items': [
            {
              'id': '527-event',
              'summary': 'Initial527 event',
              'start': {'dateTime': '2026-11-13T09:00:00Z'},
              'end': {'dateTime': '2026-11-13T10:00:00Z'},
            },
          ],
        });
      }
      requests.add('$issuer:unexpected:${request.method}:${request.url.path}');
      throw StateError('Unexpected527 mock transport');
    });
    clients.add(client);
    return client;
  }

  AuthProvider newAuth(String issuer) {
    final auth = AuthProvider(
      client: ApiClient(
        baseUrl: 'https://fixture527.example',
        httpClient: client(issuer),
      ),
    );
    auths.add(auth);
    return auth;
  }

  CalendarSyncProvider newConsumer(AuthProvider auth) {
    final provider = CalendarSyncProvider(authProvider: auth);
    consumers.add(provider);
    return provider;
  }

  Future<void> install() async {
    oldAuth = newAuth('old');
    await oldAuth
        .login(username: _account, password: 'synthetic527-password')
        .timeout(_wait);
    await AccountPreferenceWrites.drain().timeout(_wait);
    expect(
      (await disk())[AccountLocalDataCleaner.accountDataOwnerKey],
      'id:$_account',
    );
    oldConsumer = newConsumer(oldAuth);
    await oldConsumer
        .prepareOAuthScope(initialize: true, isCurrent: caller.isCurrent)
        .timeout(_wait);
    final draft = await oldConsumer
        .savePendingOAuthAuthorization(
          provider: OAuthCalendarProvider.google,
          displayName: 'Live527 primary',
          clientId: 'synthetic527-client',
          clientSecret: '',
          redirectUri: 'duoyi://oauth/calendar',
          calendarId: 'primary',
          codeVerifier: verifier,
          state: state,
          requireExpectedAttempt: true,
          isCurrent: caller.isCurrent,
        )
        .timeout(_wait);
    final account = await oldConsumer
        .addOAuthAccountFromCode(
          provider: OAuthCalendarProvider.google,
          displayName: 'Live527 primary',
          clientId: 'synthetic527-client',
          clientSecret: '',
          redirectUri: 'duoyi://oauth/calendar',
          calendarId: 'primary',
          codeVerifier: verifier,
          expectedState: state,
          expectedAttemptId: draft['attemptId'],
          authorizationInput: OAuthAuthorizationInput.callback(
            Uri(
              scheme: 'duoyi',
              host: 'oauth',
              path: '/calendar',
              queryParameters: {'code': 'synthetic527-code', 'state': state},
            ).toString(),
          ),
          isCurrent: caller.isCurrent,
        )
        .timeout(_wait);
    expect(oldConsumer.oauthAccounts.single.id, account.id);
    expect(oldConsumer.isOAuthReady, isTrue);
    expect(oldConsumer.allEvents().single.title, 'Initial527 event');
    expect(refreshCalls, 1);
    expect(
      requests.where(
        (r) =>
            r.contains(':token') ||
            r.contains(':refresh') ||
            r.contains(':events:'),
      ),
      ['old:token', 'old:refresh', 'old:events:primary'],
    );
    expect(
      oldConsumer.oauthAccounts.single.expiresAt.isBefore(
        DateTime.now().add(const Duration(minutes: 2)),
      ),
      isTrue,
    );
    expect((await disk()).containsKey(_journal), isFalse);
  }

  Future<Map<String, Object>> disk() => store.backing();
  String cacheKey(String id) => '${OAuthCalendarStorage.eventsKeyPrefix}$id';
  OAuthOwnedRefreshJournal journal(
    Map<String, Object> raw,
    AuthOAuthScopeLease lease,
  ) {
    final result = OAuthOwnedRefreshJournal.parse(
      raw[_journal]! as String,
      scope: lease.workspace.record,
    );
    expect(
      result,
      isNotNull,
      reason: 'Actual product journal must be canonical',
    );
    return result!;
  }

  OAuthOwnedSourceRecord source(
    Map<String, Object> raw,
    AuthOAuthScopeLease lease,
  ) => OAuthOwnedSourceRecord.parseList(
    raw[_accounts]! as String,
    scope: lease.workspace.record,
  )!.single;
  Map<String, Object> without(Map<String, Object> raw, Set<String> keys) => {
    for (final entry in raw.entries)
      if (!keys.contains(entry.key)) entry.key: entry.value,
  };
  Future<void> close() async {
    caller.cancel();
    store.failNextAccountsAfterPersist = false;
    try {
      await AccountPreferenceWrites.drain().timeout(_wait);
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
