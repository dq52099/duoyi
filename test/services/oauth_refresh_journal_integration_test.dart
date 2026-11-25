// Prepared502 from frozen500 and the readonly public406 fixture.
// SharedPreferences mock integration; no process restart, execution or formatting.

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
const _account = 'refresh502-account';
const _ordinary = <String, Object>{
  'auth_state': '{ "token" : null }',
  'todos': '[ { "id" : "target502", "title" : "keep todo" } ]',
  'duoyi_notes': '[ { "body" : "keep note" } ]',
  'duoyi_ics_subscriptions_v1': '[]',
  'targeted502_setting': 502,
};

const _journal = OAuthCalendarStorage.refreshJournalKey;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() async => f = await _Fixture.create());
  tearDown(() async => f.close());

  test(
    'RJI502-01 actual claim ACK and readback precede refresh HTTP',
    () => f.withHttp(() async {
      await f.install();
      final before = await f.disk();
      final requests = f.requests.toList();
      final claimAck = f.store.holdNextClaim();
      final response = f.holdRefresh();
      final work = f.observe<OAuthSyncResult>(f.sync(f.first));
      await claimAck.started.future.timeout(_wait);
      final issued = await f.disk();
      final dispatched = f.journal(issued);
      expect(dispatched.phase, OAuthRefreshPhase.dispatched);
      expect(dispatched.originalSource.encode(), f.source(before).encode());
      expect(f.withoutJournal(issued), before);
      expect(f.requests, requests);
      expect(f.store.confirmedClaims, isNot(contains(dispatched.encode())));
      claimAck.release.complete();
      await response.started.future.timeout(_wait);
      expect(f.store.confirmedClaims, contains(dispatched.encode()));
      expect(f.refreshClaims.single, dispatched.encode());
      expect(f.requests, [...requests, 'refresh']);
      expect(f.withoutJournal(await f.disk()), before);
      response.release.complete();
      final result = await work.timeout(_wait);
      expect(result.error, isNull);
      expect(result.value!.status, OAuthSyncStatus.refreshed);
      expect(result.value!.eventCount, 1);
      expect((await f.disk()).containsKey(_journal), isFalse);
      expect(f.requests, [...requests, 'refresh', 'events:primary']);
      expect(
        f.consumer.oauthAccounts.single.accessToken,
        'synthetic-targeted502-renewed-access-2',
      );
      expect(OAuthCalendarStorage.failure, isNull);
    }),
  );

  test(
    'RJI502-02 claim false ACK before and after persistence dispatches zero HTTP',
    () => f.withHttp(() async {
      await f.install();
      for (final mode in [1, 2]) {
        final before = await f.disk();
        final requests = f.requests.toList();
        final writes = f.store.mutations.length;
        f.store.claimFailure = mode;
        final result = await f.sync(f.first).timeout(_wait);
        expect(
          result.status,
          OAuthSyncStatus.storageFailure,
          reason: 'claim false ACK mode $mode',
        );
        expect(result.isSuccess, isFalse);
        expect(result.eventCount, 0);
        expect(result.receipt, isNull);
        expect(f.requests, requests);
        expect(await f.disk(), before);
        expect(
          f.store.mutations.skip(writes),
          everyElement(anyOf('set:$_journal', 'remove:$_journal')),
        );
        expect(f.store.mutations.skip(writes), contains('set:$_journal'));
        expect(OAuthCalendarStorage.failure, isNull);
        expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      }
    }),
  );

  test(
    'RJI502-03 invalid response leaves actual dispatched journal and readonly unknown never replays',
    () => f.withHttp(() async {
      await f.install();
      final before = await f.disk();
      final requests = f.requests.toList();
      f.invalidRefreshToken = true;
      final failed = await f.sync(f.first).timeout(_wait);
      // Main's supplied post500 contract reports persisted uncertainty while
      // retaining the transport cause separately; do not replay this claim.
      expect(failed.status, OAuthSyncStatus.dispatchUnknown);
      expect(failed.diagnosticStatus, OAuthSyncStatus.httpFailure);
      expect(failed.receipt, isNull);
      final persisted = await f.disk();
      final claim = f.journal(persisted);
      expect(claim.phase, OAuthRefreshPhase.dispatched);
      expect(claim.returnedSource, isNull);
      expect(f.withoutJournal(persisted), before);
      final writes = f.store.mutations.toList();
      final attempted = f.requests.toList();
      await f.consumer
          .loadFromStorage(isCurrent: f.caller.isCurrent)
          .timeout(_wait);
      final state = await f.consumer
          .loadOAuthRefreshRecovery(isCurrent: f.caller.isCurrent)
          .timeout(_wait);
      expect(state!.sourceId, f.first.id);
      expect(state.phase, OAuthRefreshPhase.dispatched);
      expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      expect(OAuthCalendarStorage.ownsRequest(f.first.id, 2), isTrue);
      final refused = await f.sync(f.first).timeout(_wait);
      expect(refused.status, OAuthSyncStatus.dispatchUnknown);
      expect(refused.isSuccess, isFalse);
      expect(refused.receipt, isNull);
      expect(OAuthCalendarStorage.ownsRequest(f.first.id, 2), isTrue);
      expect(f.store.mutations, writes);
      expect(f.requests, attempted);
      expect(f.requests, [...requests, 'refresh']);
      expect(await f.disk(), persisted);
      expect(OAuthCalendarStorage.failure, isNull);
    }),
  );

  test(
    'RJI502-04 confirmed received survives accounts ACK failure and fresh real issuer installs fixed target locally',
    () => f.withHttp(() async {
      await f.install();
      final before = await f.disk();
      f.store.failAccountsPhase = 1;
      final failed = await f.sync(f.first).timeout(_wait);
      expect(failed.status, OAuthSyncStatus.localCommitRequired);
      final oldReceipt = failed.receipt!;
      final receivedDisk = await f.disk();
      final received = f.journal(receivedDisk);
      expect(received.phase, OAuthRefreshPhase.received);
      expect(f.withoutJournal(receivedDisk), before);
      expect(received.originalSource.encode(), f.source(before).encode());
      final requests = f.requests.toList();
      final writes = f.store.mutations.toList();
      await f.freshIssuer();
      final state = await f.consumer
          .loadOAuthRefreshRecovery(isCurrent: f.caller.isCurrent)
          .timeout(_wait);
      expect(state!.sourceId, f.first.id);
      expect(state.phase, OAuthRefreshPhase.received);
      expect(f.consumer.oauthAccounts.single.toJson(), f.first.toJson());
      final freshReceipt = f.consumer.oauthLocalCommitReceipts.single;
      expect(freshReceipt.isRefresh, isTrue);
      expect(freshReceipt, isNot(same(oldReceipt)));
      await expectLater(
        f.consumer.retryOAuthLocalCommit(
          oldReceipt,
          isCurrent: f.caller.isCurrent,
        ),
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      expect(f.store.mutations, writes);
      expect(f.requests, requests);
      expect(await f.disk(), receivedDisk);
      final installed = await f.consumer
          .retryOAuthLocalCommit(freshReceipt, isCurrent: f.caller.isCurrent)
          .timeout(_wait);
      expect(installed.toJson(), received.returnedSource!.account);
      final settled = await f.disk();
      expect(f.source(settled).encode(), received.returnedSource!.encode());
      expect(settled.containsKey(_journal), isFalse);
      expect(settled[f.cacheKey(f.first.id)], before[f.cacheKey(f.first.id)]);
      expect(f.store.mutations, [
        ...writes,
        'set:$_accounts',
        'remove:$_journal',
      ]);
      expect(f.requests, requests);
      expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      expect(OAuthCalendarStorage.failure, isNull);
    }),
  );

  test(
    'RJI502-05 actual returned plus received consumes only with zero accounts write or target recomputation',
    () => f.withHttp(() async {
      await f.install();
      final before = await f.disk();
      f.store.failJournalRemove = true;
      final failed = await f.sync(f.first).timeout(_wait);
      expect(failed.status, OAuthSyncStatus.localCommitRequired);
      final persisted = await f.disk();
      final journal = f.journal(persisted);
      expect(journal.phase, OAuthRefreshPhase.received);
      expect(f.source(persisted).encode(), journal.returnedSource!.encode());
      final requests = f.requests.toList();
      final writes = f.store.mutations.toList();
      await f.freshIssuer();
      final state = await f.consumer
          .loadOAuthRefreshRecovery(isCurrent: f.caller.isCurrent)
          .timeout(_wait);
      expect(state!.phase, OAuthRefreshPhase.received);
      final receipt = f.consumer.oauthLocalCommitReceipts.single;
      expect(f.store.mutations, writes);
      final result = await f.consumer
          .retryOAuthLocalCommit(receipt, isCurrent: f.caller.isCurrent)
          .timeout(_wait);
      expect(result.toJson(), journal.returnedSource!.account);
      final settled = await f.disk();
      expect(settled[_accounts], persisted[_accounts]);
      expect(settled.containsKey(_journal), isFalse);
      expect(settled[f.cacheKey(f.first.id)], before[f.cacheKey(f.first.id)]);
      expect(f.store.mutations, [...writes, 'remove:$_journal']);
      expect(f.requests, requests);
      expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      expect(OAuthCalendarStorage.failure, isNull);
    }),
  );

  test(
    'RJI502-06 third source foreign journal and typed corruption are rejected with exact bytes preserved',
    () => f.withHttp(() async {
      await f.install();
      f.store.failAccountsPhase = 1;
      final failed = await f.sync(f.first).timeout(_wait);
      expect(failed.status, OAuthSyncStatus.localCommitRequired);
      final good = await f.disk();
      final journal = f.journal(good);
      final third = journal.originalSource.withAccount({
        ...journal.originalSource.account,
        'displayName': 'RJ502 third metadata',
      });
      final foreign =
          jsonDecode(good[_journal]! as String) as Map<String, dynamic>;
      foreign['oauthIncarnation'] = 'ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ';
      final patches = <Map<String, Object>>[
        {
          _accounts: jsonEncode([third.toJson()]),
        },
        {_journal: jsonEncode(foreign)},
        {_journal: 502},
      ];
      final requests = f.requests.toList();
      for (final patch in patches) {
        for (final entry in patch.entries) {
          await f.store.inject(entry.key, entry.value);
        }
        final corrupted = await f.disk();
        final writes = f.store.mutations.toList();
        await expectLater(
          f.consumer.loadOAuthRefreshRecovery(isCurrent: f.caller.isCurrent),
          throwsA(isA<OAuthWorkspaceCodecException>()),
        );
        expect(await f.disk(), corrupted);
        expect(f.store.mutations, writes);
        expect(f.requests, requests);
        // Restore only the exact real values explicitly tampered by this
        // negative fixture; never seed a positive journal or authority.
        for (final key in patch.keys) {
          await f.store.inject(key, good[key]!);
        }
        await f.consumer
            .loadFromStorage(isCurrent: f.caller.isCurrent)
            .timeout(_wait);
        expect(await f.disk(), good);
        expect(f.store.mutations, writes);
      }
      expect(OAuthCalendarStorage.failure, isNull);
    }),
  );

  test(
    'RJI502-07 route cancellation after issued refresh saves only received and never installs or fetches events',
    () => f.withHttp(() async {
      await f.install();
      final before = await f.disk();
      final requests = f.requests.toList();
      final writes = f.store.mutations.length;
      final route = _Caller();
      final response = f.holdRefresh();
      final original = f.observe<OAuthSyncResult>(
        f.sync(f.first, caller: route),
      );
      await response.started.future.timeout(_wait);
      route.cancel();
      response.release.complete();
      final canceled = await original.timeout(_wait);
      expect(canceled.error, isNull);
      expect(canceled.value!.status, OAuthSyncStatus.canceled);
      expect(canceled.value!.isSuccess, isFalse);
      expect(canceled.value!.eventCount, 0);
      final actual = await f.disk();
      final received = f.journal(actual);
      expect(received.phase, OAuthRefreshPhase.received);
      expect(
        received.returnedSource!.account['accessToken'],
        'synthetic-targeted502-renewed-access-2',
      );
      expect(f.withoutJournal(actual), before);
      expect(f.consumer.oauthAccounts.single.toJson(), f.first.toJson());
      expect(f.requests, [...requests, 'refresh']);
      expect(f.store.mutations.skip(writes), [
        'set:$_journal',
        'set:$_journal',
      ]);
      final savedWrites = f.store.mutations.toList();
      final state = await f.consumer
          .loadOAuthRefreshRecovery(isCurrent: f.caller.isCurrent)
          .timeout(_wait);
      expect(state!.phase, OAuthRefreshPhase.received);
      expect(f.consumer.oauthLocalCommitReceipts.single.isRefresh, isTrue);
      expect(f.store.mutations, savedWrites);
      expect(f.requests, [...requests, 'refresh']);
      expect(route.isCurrent(), isFalse);
      expect(OAuthCalendarStorage.failure, isNull);
    }),
  );

  test(
    'RJI502-08 real same source rename remove and held events cannot write through a confirmed peer claim',
    () => f.withHttp(() async {
      await f.install();
      f.shortRefreshCalls.add(2);
      f.eventTitle = 'RJ502 obsolete held event';
      final events = f.holdEvents();
      final old = f.observe<OAuthSyncResult>(f.sync(f.first));
      await events.started.future.timeout(_wait);
      final peer = f.newConsumer();
      await peer.loadFromStorage().timeout(_wait);
      final opening = peer.oauthAccounts.single;
      final source = OAuthCalendarStorage.sourceRevision(opening.id);
      final response = f.holdRefresh();
      final current = f.observe<OAuthSyncResult>(
        peer.syncOAuthAccount(
          opening.id,
          expectedAccount: opening,
          isCurrent: f.caller.isCurrent,
        ),
      );
      await response.started.future.timeout(_wait);
      final blockedDisk = await f.disk();
      final claim = f.journal(blockedDisk);
      expect(claim.phase, OAuthRefreshPhase.dispatched);
      expect(claim.originalSource.encode(), f.source(blockedDisk).encode());
      expect(OAuthCalendarStorage.ownsRequest(opening.id, 3), isTrue);
      final requests = f.requests.toList();
      final writes = f.store.mutations.toList();
      await expectLater(
        peer.updateOAuthAccount(
          opening.copyWith(displayName: 'RJ502 blocked rename'),
          isCurrent: f.caller.isCurrent,
        ),
        throwsA(isA<OAuthRefreshDispatchUnknown>()),
      );
      await expectLater(
        peer.removeOAuthAccount(
          opening.id,
          expectedAccount: opening,
          isCurrent: f.caller.isCurrent,
        ),
        throwsA(isA<OAuthRefreshDispatchUnknown>()),
      );
      expect(OAuthCalendarStorage.sourceRevision(opening.id), source);
      expect(OAuthCalendarStorage.ownsRequest(opening.id, 3), isTrue);
      expect(f.store.mutations, writes);
      expect(f.requests, requests);
      expect(await f.disk(), blockedDisk);
      events.release.complete();
      final canceled = await old.timeout(_wait);
      expect(canceled.error, isNull);
      expect(canceled.value!.status, OAuthSyncStatus.canceled);
      expect(canceled.value!.eventCount, 0);
      expect(f.store.mutations, writes);
      expect(f.requests, requests);
      expect(await f.disk(), blockedDisk);
      expect(
        blockedDisk[f.cacheKey(opening.id)],
        isNot(contains('obsolete held event')),
      );
      f.eventTitle = 'RJ502 current peer accepted event';
      response.release.complete();
      final success = await current.timeout(_wait);
      expect(success.error, isNull);
      expect(success.value!.status, OAuthSyncStatus.refreshed);
      expect(success.value!.eventCount, 1);
      expect((await f.disk()).containsKey(_journal), isFalse);
      expect(peer.allEvents().single.title, f.eventTitle);
      expect(OAuthCalendarStorage.ownsRequest(opening.id, 3), isTrue);
      expect(OAuthCalendarStorage.failure, isNull);
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
  final confirmedClaims = <String>[];
  final acknowledgedClaims = <String>{};
  final holds = <_Hold>[];
  int claimFailure = 0;
  int failAccountsPhase = 0;
  bool failJournalRemove = false;
  _Hold? claimHold;

  _Hold holdNextClaim() {
    final hold = _Hold();
    claimHold = hold;
    holds.add(hold);
    return hold;
  }

  static String? phase(Object? raw) => raw is String
      ? (jsonDecode(raw) as Map<String, dynamic>)['phase'] as String?
      : null;

  @override
  Future<Map<String, Object>> getAll() async {
    final raw = await super.getAll();
    final journal = raw['flutter.$_journal'] ?? raw[_journal];
    if (journal is String &&
        phase(journal) == 'dispatched' &&
        acknowledgedClaims.contains(journal) &&
        !confirmedClaims.contains(journal)) {
      confirmedClaims.add(journal);
    }
    return raw;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    final name = logical(key);
    mutations.add('set:$name');
    if (name == _journal && phase(value) == 'dispatched') {
      final failure = claimFailure;
      claimFailure = 0;
      if (failure == 1) return false;
      if (failure == 2) {
        expect(await super.setValue(type, key, value), isTrue);
        return false;
      }
      expect(await super.setValue(type, key, value), isTrue);
      final hold = claimHold;
      claimHold = null;
      if (hold != null) {
        hold.started.complete();
        await hold.release.future;
      }
      acknowledgedClaims.add(value as String);
      return true;
    }
    if (name == _accounts && failAccountsPhase == 1) {
      expect(await super.setValue(type, key, value), isTrue);
      failAccountsPhase = 2;
      return false;
    }
    if (name == _accounts && failAccountsPhase == 2) failAccountsPhase = 0;
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) {
    mutations.add('remove:${logical(key)}');
    if (logical(key) == _journal && failJournalRemove) {
      failJournalRemove = false;
      return Future<bool>.value(false);
    }
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
      _ => throw ArgumentError('Unsupported502 negative fixture value'),
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
  final refreshClaims = <String>[];
  final shortRefreshCalls = <int>{1};
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
  _Hold? eventHold;
  String eventTitle = 'Targeted502 initial event';

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
        expect(body['password'], 'synthetic-targeted502-password');
        return _json({
          'token': 'synthetic-targeted502-auth',
          'user': {'id': _account, 'username': _account},
        });
      }
      if (request.url.path == '/api/config') {
        return _json({});
      }
      if (request.url.host == 'oauth2.googleapis.com' &&
          request.method == 'POST') {
        final form = Uri.splitQueryString(request.body);
        expect(form['client_id'], 'synthetic-targeted502-client');
        if (form['grant_type'] == 'refresh_token') {
          final raw = await disk();
          final dispatched = journal(raw);
          expect(dispatched.phase, OAuthRefreshPhase.dispatched);
          expect(store.confirmedClaims, contains(dispatched.encode()));
          refreshClaims.add(dispatched.encode());
          requests.add('refresh');
          expect(form.containsKey('code'), isFalse);
          expect(
            form['refresh_token'],
            refreshCalls == 0
                ? 'synthetic-targeted502-refresh-1'
                : 'synthetic-targeted502-renewed-refresh-$refreshCalls',
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
          latestAccess = 'synthetic-targeted502-renewed-access-$refreshCalls';
          return _json({
            'access_token': latestAccess,
            'refresh_token':
                'synthetic-targeted502-renewed-refresh-$refreshCalls',
            'expires_in': shortRefreshCalls.contains(refreshCalls) ? 60 : 7200,
            'token_type': 'Bearer',
          });
        }
        requests.add('token');
        expect(form['grant_type'], 'authorization_code');
        expect(form['code_verifier'], verifier);
        tokenCalls++;
        latestAccess = 'synthetic-targeted502-access-$tokenCalls';
        return _json({
          'access_token': latestAccess,
          'refresh_token': 'synthetic-targeted502-refresh-$tokenCalls',
          'expires_in': 60,
          'token_type': 'Bearer',
        });
      }
      if (request.url.host != 'www.googleapis.com' || request.method != 'GET') {
        requests.add('unexpected');
        throw StateError(
          'Unexpected502 HTTP; targeted sync must not request ICS',
        );
      }
      final calendarId = request
          .url
          .pathSegments[request.url.pathSegments.indexOf('calendars') + 1];
      expect(request.headers['Authorization'], 'Bearer $latestAccess');
      requests.add('events:$calendarId');
      final title = eventTitle;
      final hold = eventHold;
      eventHold = null;
      if (hold != null) {
        hold.started.complete();
        await hold.release.future;
      }
      return _json({
        'items': [
          {
            'id': 'target502-$calendarId',
            'summary': title,
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
        baseUrl: 'https://targeted502.example',
        httpClient: client(),
      ),
    );
    auths.add(auth);
    await auth
        .login(username: _account, password: 'synthetic-targeted502-password')
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
    expect((await disk()).containsKey(_journal), isFalse);
    refreshClaims.clear();
    expect(
      first.expiresAt.isBefore(DateTime.now().add(const Duration(minutes: 2))),
      isTrue,
    );
  }

  Future<OAuthCalendarAccount> connect(String calendarId) async {
    final draft = await consumer.savePendingOAuthAuthorization(
      provider: OAuthCalendarProvider.google,
      displayName: 'Targeted502 $calendarId',
      clientId: 'synthetic-targeted502-client',
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
      displayName: 'Targeted502 $calendarId',
      clientId: 'synthetic-targeted502-client',
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
            'code': 'synthetic-targeted502-code-${tokenCalls + 1}',
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

  _Hold holdEvents() {
    final hold = _Hold();
    eventHold = hold;
    httpHolds.add(hold);
    return hold;
  }

  OAuthOwnedRefreshJournal journal(Map<String, Object> disk) {
    final parsed = OAuthOwnedRefreshJournal.parse(
      disk[_journal]! as String,
      scope: auth.captureOAuthScopeLease().workspace.record,
    );
    expect(
      parsed,
      isNotNull,
      reason: 'Actual product journal must be canonical',
    );
    return parsed!;
  }

  OAuthOwnedSourceRecord source(Map<String, Object> disk) =>
      OAuthOwnedSourceRecord.parseList(
        disk[_accounts]! as String,
        scope: auth.captureOAuthScopeLease().workspace.record,
      )!.single;

  Map<String, Object> withoutJournal(Map<String, Object> disk) => {
    for (final e in disk.entries)
      if (e.key != _journal) e.key: e.value,
  };

  Future<void> freshIssuer() async {
    for (final provider in consumers.toList()) {
      provider.dispose();
      consumers.remove(provider);
    }
    final previousIssuer = auth;
    previousIssuer.dispose();
    auths.remove(previousIssuer);
    auth = AuthProvider(
      client: ApiClient(
        baseUrl: 'https://targeted502.example',
        httpClient: client(),
      ),
    );
    auths.add(auth);
    await auth.loadFromStorage().timeout(_wait);
    consumer = newConsumer();
    await consumer
        .prepareOAuthScope(isCurrent: caller.isCurrent)
        .timeout(_wait);
    await consumer.loadFromStorage(isCurrent: caller.isCurrent).timeout(_wait);
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
    store.claimFailure = 0;
    store.failJournalRemove = false;
    refreshHold = null;
    eventHold = null;
    for (final hold in [...httpHolds, ...store.holds]) {
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
