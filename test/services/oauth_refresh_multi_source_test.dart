// Prepared528 using actual public Auth/code/refresh/ICS APIs.
// Source preparation only: no compiler, formatter, or execution.
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
const _icsId = 'multi528-ics';
const _icsUrl = 'https://multi528.invalid/calendar.ics';
const _icsList = 'duoyi_ics_subscriptions_v1';
const _icsCache = 'duoyi_ics_events_$_icsId';
const _ordinary = <String, Object>{
  'multi528_setting': 528,
  'todos': '[ { "id" : "todo528", "title" : "keep todo" } ]',
  'duoyi_notes': '[ { "body" : "keep note" } ]',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() async => f = await _Fixture.create());
  tearDown(() async => f.close());

  test(
    'RMS528-01 A confirmed claim refuses expired B before allocation and preserves B plus nonempty ICS',
    () => f.withHttp(() async {
      await f.install();
      final before = await f.disk();
      final peer = f.newConsumer();
      await peer.loadFromStorage(isCurrent: f.current).timeout(_wait);
      final openingB = peer.oauthAccounts.singleWhere(
        (row) => row.id == f.b.id,
      );
      expect(openingB.toJson(), f.b.toJson());
      expect(
        openingB.expiresAt.isBefore(
          DateTime.now().add(const Duration(minutes: 2)),
        ),
        isTrue,
      );
      expect(OAuthCalendarStorage.ownsRequest(f.b.id, 1), isTrue);
      final revisionB = OAuthCalendarStorage.sourceRevision(f.b.id);
      final response = f.holdARefresh();
      final original = f.observe(f.sync(f.a));
      await response.started.future.timeout(_wait);
      final occupied = await f.disk();
      final claim = f.journal(occupied);
      expect(claim.sourceAccountId, f.a.id);
      expect(claim.phase, OAuthRefreshPhase.dispatched);
      expect(claim.originalSource.encode(), f.record(before, f.a.id).encode());
      expect(OAuthCalendarStorage.ownsRequest(f.a.id, 2), isTrue);
      f.expectPreserved(before, occupied);
      final requests = f.requests.toList();
      final writes = f.store.mutations.toList();
      final refused = await peer
          .syncOAuthAccount(
            openingB.id,
            expectedAccount: openingB,
            isCurrent: f.current,
          )
          .timeout(_wait);
      expect(refused.status, OAuthSyncStatus.canceled);
      expect(refused.diagnosticStatus, isNull);
      expect(refused.isSuccess, isFalse);
      expect(refused.eventCount, 0);
      expect(refused.receipt, isNull);
      expect(OAuthCalendarStorage.ownsRequest(f.b.id, 1), isTrue);
      expect(OAuthCalendarStorage.sourceRevision(f.b.id), revisionB);
      expect(OAuthCalendarStorage.ownsRequest(f.a.id, 2), isTrue);
      expect(await f.disk(), occupied);
      expect(f.requests, requests);
      expect(f.store.mutations, writes);
      expect(f.transportB.ledger, ['code', 'refresh:1', 'events']);
      response.release.complete();
      final completed = await original.timeout(_wait);
      expect(completed.error, isNull);
      expect(completed.value!.status, OAuthSyncStatus.refreshed);
      expect(completed.value!.eventCount, 1);
      final settled = await f.disk();
      expect(settled.containsKey(_journal), isFalse);
      expect(
        f.record(settled, f.a.id).account['accessToken'],
        f.transportA.access,
      );
      f.expectPreserved(before, settled);
      expect(f.requests, [...requests, 'A:events']);
      expect(f.transportB.ledger, ['code', 'refresh:1', 'events']);
      expect(OAuthCalendarStorage.ownsRequest(f.b.id, 1), isTrue);
      expect(OAuthCalendarStorage.failure, isNull);
    }),
  );

  test(
    'RMS528-02 fixed A local install preserves complete B source cache ICS and ordinary typed preferences',
    () => f.withHttp(() async {
      await f.install();
      final before = await f.disk();
      f.store.failAccounts = 1;
      final failed = await f.sync(f.a).timeout(_wait);
      expect(failed.status, OAuthSyncStatus.localCommitRequired);
      expect(failed.eventCount, 0);
      final receivedDisk = await f.disk();
      final received = f.journal(receivedDisk);
      expect(received.phase, OAuthRefreshPhase.received);
      expect(
        f.record(receivedDisk, f.a.id).encode(),
        received.originalSource.encode(),
      );
      f.expectPreserved(before, receivedDisk);
      expect(f.withoutJournal(receivedDisk), before);
      final writes = f.store.mutations.toList();
      final requests = f.requests.toList();
      final state = await f.consumer
          .loadOAuthRefreshRecovery(isCurrent: f.current)
          .timeout(_wait);
      expect(state!.sourceId, f.a.id);
      expect(state.phase, OAuthRefreshPhase.received);
      final receipt = f.consumer.oauthLocalCommitReceipts.single;
      expect(receipt, same(failed.receipt));
      expect(receipt.isRefresh, isTrue);
      expect(f.store.mutations, writes);
      expect(f.requests, requests);
      final installed = await f.consumer
          .retryOAuthLocalCommit(receipt, isCurrent: f.current)
          .timeout(_wait);
      expect(installed.toJson(), received.returnedSource!.account);
      final settled = await f.disk();
      expect(
        f.record(settled, f.a.id).encode(),
        received.returnedSource!.encode(),
      );
      expect(settled.containsKey(_journal), isFalse);
      expect(settled[f.cacheKey(f.a.id)], before[f.cacheKey(f.a.id)]);
      f.expectPreserved(before, settled);
      expect(f.store.mutations, [
        ...writes,
        'set:$_accounts',
        'remove:$_journal',
      ]);
      expect(f.requests, requests);
      expect(f.transportB.ledger, ['code', 'refresh:1', 'events']);
      expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      expect(OAuthCalendarStorage.failure, isNull);
    }),
  );

  test(
    'RMS528-03 actual returned A consumes only without rewriting accounts B caches ICS or fixed target',
    () => f.withHttp(() async {
      await f.install();
      final before = await f.disk();
      f.store.failJournalRemove = true;
      final failed = await f.sync(f.a).timeout(_wait);
      expect(failed.status, OAuthSyncStatus.localCommitRequired);
      expect(failed.eventCount, 0);
      final installedDisk = await f.disk();
      final received = f.journal(installedDisk);
      expect(received.phase, OAuthRefreshPhase.received);
      expect(
        f.record(installedDisk, f.a.id).encode(),
        received.returnedSource!.encode(),
      );
      f.expectPreserved(before, installedDisk);
      final requests = f.requests.toList();
      final writes = f.store.mutations.toList();
      await f.consumer.loadFromStorage(isCurrent: f.current).timeout(_wait);
      final state = await f.consumer
          .loadOAuthRefreshRecovery(isCurrent: f.current)
          .timeout(_wait);
      expect(state!.phase, OAuthRefreshPhase.received);
      expect(f.store.mutations, writes);
      expect(f.requests, requests);
      final receipt = f.consumer.oauthLocalCommitReceipts.single;
      final fixed = await f.consumer
          .retryOAuthLocalCommit(receipt, isCurrent: f.current)
          .timeout(_wait);
      expect(fixed.toJson(), received.returnedSource!.account);
      final settled = await f.disk();
      expect(settled[_accounts], installedDisk[_accounts]);
      expect(
        f.record(settled, f.a.id).encode(),
        received.returnedSource!.encode(),
      );
      expect(settled.containsKey(_journal), isFalse);
      expect(settled[f.cacheKey(f.a.id)], before[f.cacheKey(f.a.id)]);
      f.expectPreserved(before, settled);
      expect(f.store.mutations, [...writes, 'remove:$_journal']);
      expect(f.requests, requests);
      expect(f.transportB.ledger, ['code', 'refresh:1', 'events']);
      expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      expect(OAuthCalendarStorage.failure, isNull);
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
}

class _Transport {
  _Transport(this.label);
  final String label;
  final ledger = <String>[];
  final verifier = OAuthCalendarClient.generateCodeVerifier();
  final state = OAuthCalendarClient.generateCodeVerifier();
  int refreshCount = 0;
  String access = '';
  String refresh = '';
  _Hold? hold;
  String get clientId => 'synthetic-multi528-$label-client';
  String get calendarId => 'calendar-$label';
}

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData({});
  final mutations = <String>[];
  final acknowledgedClaims = <String>{};
  final readClaims = <String>{};
  int failAccounts = 0;
  bool failJournalRemove = false;
  @override
  Future<Map<String, Object>> getAll() async {
    final raw = await super.getAll();
    final journal = raw['flutter.$_journal'] ?? raw[_journal];
    if (journal is String && acknowledgedClaims.contains(journal)) {
      readClaims.add(journal);
    }
    return raw;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    final name = logical(key);
    mutations.add('set:$name');
    if (name == _accounts && failAccounts == 1) {
      expect(await super.setValue(type, key, value), isTrue);
      failAccounts = 2;
      return false;
    }
    if (name == _accounts && failAccounts == 2) failAccounts = 0;
    final ack = await super.setValue(type, key, value);
    if (name == _journal &&
        value is String &&
        (jsonDecode(value) as Map<String, dynamic>)['phase'] == 'dispatched' &&
        ack) {
      acknowledgedClaims.add(value);
    }
    return ack;
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
  static String logical(String key) =>
      key.startsWith('flutter.') ? key.substring(8) : key;
}

class _Fixture {
  _Fixture(this.previous, this.store, this.prefs);
  final SharedPreferencesStorePlatform previous;
  final _Store store;
  final SharedPreferences prefs;
  final transportA = _Transport('A');
  final transportB = _Transport('B');
  final requests = <String>[];
  final clients = <http.Client>[];
  final consumers = <CalendarSyncProvider>[];
  final pending = <Future<void>>[];
  final holds = <_Hold>[];
  bool active = true;
  bool current() => active;
  late AuthProvider auth;
  late CalendarSyncProvider consumer;
  late OAuthCalendarAccount a;
  late OAuthCalendarAccount b;

  static Future<_Fixture> create() async {
    await AccountPreferenceWrites.drain().timeout(_wait);
    final previous = SharedPreferencesStorePlatform.instance;
    final store = _Store();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = store;
    final prefs = await SharedPreferences.getInstance();
    await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    return _Fixture(previous, store, prefs);
  }

  Future<void> withHttp(Future<void> Function() body) =>
      http.runWithClient(body, client);
  http.Client client() {
    final result = MockClient((request) async {
      if (request.url.path == '/api/auth/login') {
        expect(jsonDecode(request.body), {
          'username': 'multi528-account',
          'account': 'multi528-account',
          'password': 'synthetic-multi528-password',
        });
        return _json({
          'token': 'synthetic-multi528-auth',
          'user': {'id': 'multi528-account', 'username': 'multi528-account'},
        });
      }
      if (request.url.path == '/api/config') return _json({});
      if (request.url.toString() == _icsUrl) {
        expect(request.method, 'GET');
        requests.add('ICS:events');
        return http.Response(
          'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Fixture528//EN\r\nBEGIN:VEVENT\r\nUID:ics528-event\r\nDTSTAMP:20261113T000000Z\r\nDTSTART:20261113T090000Z\r\nDTEND:20261113T100000Z\r\nSUMMARY:ICS528 preserved event\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n',
          200,
          headers: {'content-type': 'text/calendar'},
        );
      }
      if (request.url.host == 'oauth2.googleapis.com' &&
          request.method == 'POST') {
        final form = Uri.splitQueryString(request.body);
        final t = [
          transportA,
          transportB,
        ].singleWhere((value) => value.clientId == form['client_id']);
        expect(form.containsKey('client_secret'), isFalse);
        if (form['grant_type'] == 'authorization_code') {
          expect(form['code'], 'synthetic-multi528-${t.label}-code');
          expect(form['code_verifier'], t.verifier);
          expect(form['redirect_uri'], 'duoyi://oauth/calendar');
          t.ledger.add('code');
          requests.add('${t.label}:code');
          t.access = 'synthetic-multi528-${t.label}-code-access';
          t.refresh = 'synthetic-multi528-${t.label}-code-refresh';
          return _json({
            'access_token': t.access,
            'refresh_token': t.refresh,
            'expires_in': 60,
            'token_type': 'Bearer',
          });
        }
        expect(form['grant_type'], 'refresh_token');
        expect(form.containsKey('code'), isFalse);
        expect(form['refresh_token'], t.refresh);
        final claim = journal(await disk());
        expect(claim.originalSource.account['clientId'], t.clientId);
        expect(claim.phase, OAuthRefreshPhase.dispatched);
        expect(store.readClaims, contains(claim.encode()));
        t.refreshCount++;
        t.ledger.add('refresh:${t.refreshCount}');
        requests.add('${t.label}:refresh:${t.refreshCount}');
        final hold = t.hold;
        t.hold = null;
        if (hold != null) {
          hold.started.complete();
          await hold.release.future;
        }
        t.access = 'synthetic-multi528-${t.label}-access-${t.refreshCount}';
        t.refresh = 'synthetic-multi528-${t.label}-refresh-${t.refreshCount}';
        return _json({
          'access_token': t.access,
          'refresh_token': t.refresh,
          'expires_in': t.refreshCount == 1 ? 60 : 7200,
          'token_type': 'Bearer',
        });
      }
      if (request.url.host == 'www.googleapis.com' && request.method == 'GET') {
        final calendar = request
            .url
            .pathSegments[request.url.pathSegments.indexOf('calendars') + 1];
        final t = [
          transportA,
          transportB,
        ].singleWhere((value) => value.calendarId == calendar);
        expect(request.headers['Authorization'], 'Bearer ${t.access}');
        t.ledger.add('events');
        requests.add('${t.label}:events');
        return _json({
          'items': [
            {
              'id': 'multi528-${t.label}-event',
              'summary': 'OAuth528 ${t.label} preserved event',
              'start': {'dateTime': '2026-11-13T09:00:00Z'},
              'end': {'dateTime': '2026-11-13T10:00:00Z'},
            },
          ],
        });
      }
      requests.add('unexpected');
      throw StateError('Unexpected528 mock transport request');
    });
    clients.add(result);
    return result;
  }

  CalendarSyncProvider newConsumer() {
    final result = CalendarSyncProvider(authProvider: auth);
    consumers.add(result);
    return result;
  }

  Future<void> install() async {
    auth = AuthProvider(
      client: ApiClient(
        baseUrl: 'https://multi528.invalid',
        httpClient: client(),
      ),
    );
    await auth
        .login(
          username: 'multi528-account',
          password: 'synthetic-multi528-password',
        )
        .timeout(_wait);
    await AccountPreferenceWrites.drain().timeout(_wait);
    await Future<void>.delayed(Duration.zero);
    consumer = newConsumer();
    await consumer
        .prepareOAuthScope(initialize: true, isCurrent: current)
        .timeout(_wait);
    a = await connect(transportA).timeout(_wait);
    b = await connect(transportB).timeout(_wait);
    const subscription = IcsSubscription(
      id: _icsId,
      name: 'ICS528 nonempty subscription',
      url: _icsUrl,
    );
    await consumer
        .addSubscription(subscription, isCurrent: current)
        .timeout(_wait);
    final synced = await consumer
        .syncSubscription(_icsId, isCurrent: current)
        .timeout(_wait);
    expect(synced.status, IcsRefreshStatus.refreshed);
    expect(synced.eventCount, 1);
    a = consumer.oauthAccounts.singleWhere((row) => row.id == a.id);
    b = consumer.oauthAccounts.singleWhere((row) => row.id == b.id);
    expect(a.id, isNot(b.id));
    expect(
      a.expiresAt.isBefore(DateTime.now().add(const Duration(minutes: 2))),
      isTrue,
    );
    expect(
      b.expiresAt.isBefore(DateTime.now().add(const Duration(minutes: 2))),
      isTrue,
    );
    expect(consumer.subscriptions.single.id, _icsId);
    expect(consumer.subscriptions.single.lastSyncedAt, isNotNull);
    expect(
      consumer.allEvents().map((event) => event.title),
      unorderedEquals([
        'OAuth528 A preserved event',
        'OAuth528 B preserved event',
        'ICS528 preserved event',
      ]),
    );
    expect(requests, [
      'A:code',
      'A:refresh:1',
      'A:events',
      'B:code',
      'B:refresh:1',
      'B:events',
      'ICS:events',
    ]);
    final raw = await disk();
    expect(raw.containsKey(_journal), isFalse);
    expect(records(raw).length, 2);
    expect(raw[_icsList], contains('ICS528 nonempty subscription'));
    expect(raw[_icsCache], contains('ICS528 preserved event'));
    expect(
      raw[AccountLocalDataCleaner.accountDataOwnerKey],
      'id:multi528-account',
    );
    // Login intentionally clears ordinary data from the previous account.
    // Establish this account's preferences through their real prefs APIs now.
    for (final e in _ordinary.entries) {
      if (e.value is String) await prefs.setString(e.key, e.value as String);
      if (e.value is int) await prefs.setInt(e.key, e.value as int);
    }
  }

  Future<OAuthCalendarAccount> connect(_Transport t) async {
    final pending = await consumer.savePendingOAuthAuthorization(
      provider: OAuthCalendarProvider.google,
      displayName: 'OAuth528 ${t.label}',
      clientId: t.clientId,
      clientSecret: '',
      redirectUri: 'duoyi://oauth/calendar',
      calendarId: t.calendarId,
      codeVerifier: t.verifier,
      state: t.state,
      requireExpectedAttempt: true,
      isCurrent: current,
    );
    final account = await consumer.addOAuthAccountFromCode(
      provider: OAuthCalendarProvider.google,
      displayName: 'OAuth528 ${t.label}',
      clientId: t.clientId,
      clientSecret: '',
      redirectUri: 'duoyi://oauth/calendar',
      calendarId: t.calendarId,
      codeVerifier: t.verifier,
      expectedState: t.state,
      expectedAttemptId: pending['attemptId'],
      isCurrent: current,
      authorizationInput: OAuthAuthorizationInput.callback(
        Uri(
          scheme: 'duoyi',
          host: 'oauth',
          path: '/calendar',
          queryParameters: {
            'code': 'synthetic-multi528-${t.label}-code',
            'state': t.state,
          },
        ).toString(),
      ),
    );
    return consumer.oauthAccounts.singleWhere((row) => row.id == account.id);
  }

  Future<OAuthSyncResult> sync(OAuthCalendarAccount opening) =>
      consumer.syncOAuthAccount(
        opening.id,
        expectedAccount: opening,
        isCurrent: current,
      );
  _Hold holdARefresh() {
    final hold = _Hold();
    transportA.hold = hold;
    holds.add(hold);
    return hold;
  }

  Future<_Result<T>> observe<T>(Future<T> work) {
    final result = work.then<_Result<T>>(
      (value) => _Result<T>.value(value),
      onError: (Object error, StackTrace _) => _Result<T>.error(error),
    );
    pending.add(result.then<void>((_) {}));
    return result;
  }

  Future<Map<String, Object>> disk() async => {
    for (final e in (await store.backing()).entries)
      _Store.logical(e.key): e.value,
  };
  List<OAuthOwnedSourceRecord> records(Map<String, Object> raw) =>
      OAuthOwnedSourceRecord.parseList(
        raw[_accounts]! as String,
        scope: auth.captureOAuthScopeLease().workspace.record,
      )!;
  OAuthOwnedSourceRecord record(Map<String, Object> raw, String id) =>
      records(raw).singleWhere((row) => row.account['id'] == id);
  OAuthOwnedRefreshJournal journal(Map<String, Object> raw) =>
      OAuthOwnedRefreshJournal.parse(
        raw[_journal]! as String,
        scope: auth.captureOAuthScopeLease().workspace.record,
      )!;
  Map<String, Object> withoutJournal(Map<String, Object> raw) => {
    for (final e in raw.entries)
      if (e.key != _journal) e.key: e.value,
  };
  void expectPreserved(Map<String, Object> before, Map<String, Object> after) {
    expect(
      records(after).map((row) => row.account['id']).toList(),
      records(before).map((row) => row.account['id']).toList(),
    );
    expect(record(after, b.id).encode(), record(before, b.id).encode());
    expect(after[cacheKey(b.id)], before[cacheKey(b.id)]);
    expect(after[_icsList], before[_icsList]);
    expect(after[_icsCache], before[_icsCache]);
    expect(after[_icsList], contains('ICS528 nonempty subscription'));
    expect(after[_icsCache], contains('ICS528 preserved event'));
    final beforeOther = {
      for (final e in before.entries)
        if (e.key != _accounts && e.key != _journal && e.key != cacheKey(a.id))
          e.key: e.value,
    };
    final afterOther = {
      for (final e in after.entries)
        if (e.key != _accounts && e.key != _journal && e.key != cacheKey(a.id))
          e.key: e.value,
    };
    expect(afterOther, beforeOther);
    for (final e in _ordinary.entries) {
      expect(after[e.key], e.value, reason: e.key);
    }
  }

  String cacheKey(String id) => '${OAuthCalendarStorage.eventsKeyPrefix}$id';
  Future<void> close() async {
    active = false;
    store.failAccounts = 0;
    store.failJournalRemove = false;
    for (final hold in holds) {
      if (!hold.release.isCompleted) hold.release.complete();
    }
    try {
      await Future.wait(pending).timeout(_wait);
      await AccountPreferenceWrites.drain().timeout(_wait);
      for (final provider in consumers) {
        provider.dispose();
      }
      auth.dispose();
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

http.Response _json(Map<String, Object?> value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);
