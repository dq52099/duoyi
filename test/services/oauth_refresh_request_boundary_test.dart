// Prepared510 migration of419 against frozen500/505 and contracts373/503.
// Source preparation only; no formatter, analyzer, compiler or test execution.

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
const _account = 'refresh419-account';
const _ordinary = <String, Object>{
  'auth_state': '{ "token" : null }',
  'todos': '[ { "id" : "target419", "title" : "keep todo" } ]',
  'duoyi_notes': '[ { "body" : "keep note" } ]',
  'duoyi_ics_subscriptions_v1': '[]',
  'targeted419_setting': 419,
};

const _operationZone = #oauthRequest419Operation;
String get _operation => Zone.current[_operationZone] as String? ?? 'setup';
Future<T> _as<T>(String name, Future<T> Function() work) =>
    runZoned<Future<T>>(work, zoneValues: {_operationZone: name});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() async => f = await _Fixture.create());
  tearDown(() async => f.close());

  test(
    'ORR419-01 real peer sync supersedes during old prePOST readonly storage await with zero old HTTP or writes',
    () => f.withHttp(() async {
      await f.install();
      final peer = f.newConsumer();
      await peer.loadFromStorage().timeout(_wait);
      final opening = peer.oauthAccounts.single;
      final before = await f.disk();
      final writes = f.store.mutations.toList();
      final requests = f.requests.toList();
      final source = OAuthCalendarStorage.sourceRevision(f.first.id);
      // The real install performs exactly one automatic sync for this new id.
      // These are passive ownership observations, never beginRequest calls.
      expect(OAuthCalendarStorage.ownsRequest(f.first.id, 1), isTrue);
      final oldAllocated = Completer<void>();
      final peerAllocated = Completer<void>();
      bool oldCurrent() {
        if (OAuthCalendarStorage.ownsRequest(f.first.id, 2) &&
            !oldAllocated.isCompleted) {
          oldAllocated.complete();
        }
        return f.caller.isCurrent();
      }

      bool peerCurrent() {
        if (OAuthCalendarStorage.ownsRequest(f.first.id, 3) &&
            !peerAllocated.isCompleted) {
          peerAllocated.complete();
        }
        return f.caller.isCurrent();
      }

      // Each frozen readonly _withOAuthStorage has admission and final reloads.
      final oldPreflight = f.store.holdReload('old', 2);
      final peerPreflight = f.store.holdReload('peer', 2);
      final oldPrePost = f.store.holdReload('old', 3);
      final peerPrePost = f.store.holdReload('peer', 3);
      final original = f.observe<OAuthSyncResult>(
        _as(
          'old',
          () => f.consumer.syncOAuthAccount(
            f.first.id,
            expectedAccount: f.first,
            isCurrent: oldCurrent,
          ),
        ),
      );
      await oldPreflight.started.future.timeout(_wait);
      final other = f.observe<OAuthSyncResult>(
        _as(
          'peer',
          () => peer.syncOAuthAccount(
            f.first.id,
            expectedAccount: opening,
            isCurrent: peerCurrent,
          ),
        ),
      );
      oldPreflight.release.complete();
      await peerPreflight.started.future.timeout(_wait);
      await oldAllocated.future.timeout(_wait);
      expect(OAuthCalendarStorage.ownsRequest(f.first.id, 2), isTrue);
      expect(
        f.store.reloadCounts['old'],
        2,
        reason: 'Allocated old request is waiting for prePOST readonly lane',
      );
      expect(f.requests, requests);
      peerPreflight.release.complete();
      // The peer allocates outside its completed lane. If old admission wins,
      // its reload is held; if peer allocation wins, old cancels at admission.
      // Both are within the already pending prePOST readonly storage await.
      await peerAllocated.future.timeout(_wait);
      expect(OAuthCalendarStorage.ownsRequest(f.first.id, 3), isTrue);
      expect(OAuthCalendarStorage.sourceRevision(f.first.id), source);
      expect(f.requests, requests);
      expect(f.store.mutations, writes);
      expect(await f.disk(), before);
      oldPrePost.release.complete();
      final canceled = await original.timeout(_wait);
      await peerPrePost.started.future.timeout(_wait);
      expect(f.requests, requests);
      expect(f.store.mutations, writes);
      peerPrePost.release.complete();
      final completed = await other.timeout(_wait);
      expect(canceled.error, isNull);
      expect(canceled.value!.status, OAuthSyncStatus.canceled);
      expect(canceled.value!.isSuccess, isFalse);
      expect(canceled.value!.eventCount, 0);
      expect(canceled.value!.receipt, isNull);
      expect(completed.error, isNull);
      expect(completed.value!.status, OAuthSyncStatus.refreshed);
      expect(completed.value!.eventCount, 1);
      expect(f.httpOperations.where((op) => op.startsWith('old:')), isEmpty);
      expect(f.store.operations.where((op) => op.startsWith('old:')), isEmpty);
      expect(f.httpOperations.where((op) => op.startsWith('peer:')), [
        'peer:refresh',
        'peer:events:primary',
      ]);
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
      expect((await f.disk()).containsKey(_journal), isFalse);
      expect(
        peer.oauthAccounts.single.accessToken,
        'synthetic-targeted419-renewed-access-2',
      );
      expect(
        peer.oauthAccounts.single.refreshToken,
        'synthetic-targeted419-renewed-refresh-2',
      );
      expect(OAuthCalendarStorage.ownsRequest(f.first.id, 3), isTrue);
      expect(OAuthCalendarStorage.sourceRevision(f.first.id), source);
      expect(OAuthCalendarStorage.failure, isNull);
      expect(peer.oauthLocalCommitReceipts, isEmpty);
      expect(
        f.withoutTarget(await f.disk(), f.first.id),
        f.withoutTarget(before, f.first.id),
      );
      f.expectOrdinary(await f.disk());
    }),
  );

  test(
    'ORR419-02 held real refresh freezes queued metadata edit before dispatchUnknown and canceled caller saves fixed received for exact local retry',
    () => f.withHttp(() async {
      await f.install();
      final peer = f.newConsumer();
      await peer.loadFromStorage().timeout(_wait);
      final opening = peer.oauthAccounts.single;
      final before = await f.disk();
      final writes = f.store.mutations.toList();
      final requests = f.requests.toList();
      final source = OAuthCalendarStorage.sourceRevision(f.first.id);
      final scope = f.auth.captureOAuthScopeLease();
      final previous = OAuthOwnedSourceRecord.parseList(
        before[_accounts]! as String,
        scope: scope.workspace.record,
      )!.single;
      expect(before.containsKey(_journal), isFalse);
      expect(OAuthCalendarStorage.ownsRequest(f.first.id, 1), isTrue);
      final oldCaller = _Caller();
      final response = f.holdRefresh();
      final receivedWrite = f.store.holdReceived('old');
      final original = f.observe<OAuthSyncResult>(
        _as(
          'old',
          () => f.consumer.syncOAuthAccount(
            f.first.id,
            expectedAccount: f.first,
            isCurrent: () => f.caller.isCurrent() && oldCaller.isCurrent(),
          ),
        ),
      );
      await response.started.future.timeout(_wait);
      expect(OAuthCalendarStorage.ownsRequest(f.first.id, 2), isTrue);
      final claimedDisk = await f.disk();
      final claim = f.journal(claimedDisk);
      expect(claim.phase, OAuthRefreshPhase.dispatched);
      expect(claim.originalSource.encode(), previous.encode());
      expect(claim.sourceAccountId, f.first.id);
      expect(claim.scopedOwner, scope.workspace.record.scopedOwner);
      expect(claim.oauthIncarnation, scope.workspace.record.oauthIncarnation);
      expect(claim.dispatchedAt.isUtc, isTrue);
      expect(claim.returnedSource, isNull);
      expect(claim.receivedAt, isNull);
      expect(f.withoutJournal(claimedDisk), before);
      expect(f.store.mutations, [...writes, 'set:$_journal']);
      expect(f.requests, [...requests, 'refresh']);
      final editAdmission = f.store.holdReload('edit', 1);
      final edit = f.observe<void>(
        _as(
          'edit',
          () => peer.updateOAuthAccount(
            opening.copyWith(displayName: 'Request419 peer name'),
            isCurrent: f.caller.isCurrent,
          ),
        ),
      );
      await editAdmission.started.future.timeout(_wait);
      expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      expect(await f.disk(), claimedDisk);
      // The edit is genuinely in the storage lane while the response is held.
      // Persisted dispatch rejects it before metadataChanged/beginRequest.
      editAdmission.release.complete();
      final edited = await edit.timeout(_wait);
      expect(edited.error, isA<OAuthRefreshDispatchUnknown>());
      expect(OAuthCalendarStorage.ownsRequest(f.first.id, 2), isTrue);
      expect(OAuthCalendarStorage.sourceRevision(f.first.id), source);
      expect(await f.disk(), claimedDisk);
      expect(f.store.mutations, [...writes, 'set:$_journal']);
      expect(f.store.operations.where((op) => op.startsWith('edit:')), isEmpty);
      expect(f.httpOperations.where((op) => op.startsWith('edit:')), isEmpty);
      expect(peer.oauthAccounts.single.toJson(), opening.toJson());
      expect(peer.allEvents().single.title, 'Targeted419 initial event');
      expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      expect(oldCaller.isCurrent(), isTrue);
      // Retire the original route before its real response is released. Only
      // the original issuer's save-only authority may persist this response.
      oldCaller.cancel();
      response.release.complete();
      await receivedWrite.started.future.timeout(_wait);
      final stagedDisk = await f.disk();
      final staged = f.journal(stagedDisk);
      expect(staged.phase, OAuthRefreshPhase.received);
      expect(staged.operationId, claim.operationId);
      expect(staged.receiptHandle, claim.receiptHandle);
      expect(staged.dispatchedAt, claim.dispatchedAt);
      expect(staged.originalSource.encode(), previous.encode());
      expect(staged.receivedAt!.isUtc, isTrue);
      expect(staged.receivedAt!.isBefore(staged.dispatchedAt), isFalse);
      final target = staged.returnedSource!;
      expect(target.sourceIncarnation, previous.sourceIncarnation);
      expect(target.metadataRevision, previous.metadataRevision);
      expect(target.scopedOwner, previous.scopedOwner);
      expect(target.oauthIncarnation, previous.oauthIncarnation);
      expect(target.credentialRevision, previous.credentialRevision + 1);
      expect(
        target.account['accessToken'],
        'synthetic-targeted419-renewed-access-2',
      );
      expect(
        target.account['refreshToken'],
        'synthetic-targeted419-renewed-refresh-2',
      );
      final originalMetadata = Map<String, Object?>.from(previous.account)
        ..remove('accessToken')
        ..remove('refreshToken')
        ..remove('expiresAt')
        ..remove('scope');
      final returnedMetadata = Map<String, Object?>.from(target.account)
        ..remove('accessToken')
        ..remove('refreshToken')
        ..remove('expiresAt')
        ..remove('scope');
      expect(returnedMetadata, originalMetadata);
      expect(target.account['scope'], previous.account['scope']);
      expect(
        DateTime.parse(target.account['expiresAt']! as String).isUtc,
        isTrue,
      );
      expect(f.withoutJournal(stagedDisk), before);
      expect(f.store.mutations, [...writes, 'set:$_journal', 'set:$_journal']);
      expect(f.requests, [...requests, 'refresh']);
      final received = f.consumer.oauthLocalCommitReceipts.single;
      expect(received.isRefresh, isTrue);
      expect(received.handle, staged.receiptHandle);
      expect(OAuthCalendarStorage.ownsRequest(f.first.id, 2), isTrue);
      receivedWrite.release.complete();
      final canceled = await original.timeout(_wait);
      expect(canceled.error, isNull);
      expect(canceled.value!.status, OAuthSyncStatus.canceled);
      expect(canceled.value!.isSuccess, isFalse);
      expect(canceled.value!.eventCount, 0);
      expect(canceled.value!.receipt, isNull);
      expect(oldCaller.isCurrent(), isFalse);
      expect(OAuthCalendarStorage.ownsRequest(f.first.id, 2), isTrue);
      expect(OAuthCalendarStorage.sourceRevision(f.first.id), source);
      expect(f.auth.isOAuthScopeLeaseCurrent(scope), isTrue);
      expect(OAuthCalendarStorage.failure, isNull);
      expect(f.store.operations.where((op) => op.startsWith('old:')), [
        'old:set:$_journal',
        'old:set:$_journal',
      ]);
      expect(f.store.mutations, [...writes, 'set:$_journal', 'set:$_journal']);
      expect(f.httpOperations.where((op) => op.startsWith('old:')), [
        'old:refresh',
      ]);
      expect(f.requests, [...requests, 'refresh']);
      expect(await f.disk(), stagedDisk);
      expect(f.source(await f.disk()).encode(), previous.encode());
      expect(f.consumer.oauthAccounts.single.toJson(), f.first.toJson());
      expect(f.consumer.oauthLocalCommitReceipts.single, same(received));
      final loaded = await _as(
        'inspect',
        () =>
            f.consumer.loadOAuthRefreshRecovery(isCurrent: f.caller.isCurrent),
      ).timeout(_wait);
      expect(loaded!.phase, OAuthRefreshPhase.received);
      expect(loaded.sourceId, f.first.id);
      expect(await f.disk(), stagedDisk);
      expect(f.store.mutations, [...writes, 'set:$_journal', 'set:$_journal']);
      expect(f.requests, [...requests, 'refresh']);
      expect(
        f.store.operations.where((op) => op.startsWith('inspect:')),
        isEmpty,
      );
      expect(
        f.httpOperations.where((op) => op.startsWith('inspect:')),
        isEmpty,
      );
      expect(OAuthCalendarStorage.ownsRequest(f.first.id, 2), isTrue);
      expect(f.consumer.oauthLocalCommitReceipts.single, same(received));
      final freshCaller = _Caller();
      final installed = await _as(
        'retry',
        () => f.consumer.retryOAuthLocalCommit(
          received,
          isCurrent: () => f.caller.isCurrent() && freshCaller.isCurrent(),
        ),
      ).timeout(_wait);
      expect(installed.id, f.first.id);
      expect(installed.toJson(), target.account);
      expect(installed.displayName, opening.displayName);
      expect(installed.accessToken, 'synthetic-targeted419-renewed-access-2');
      expect(installed.refreshToken, 'synthetic-targeted419-renewed-refresh-2');
      expect(f.requests, [...requests, 'refresh']);
      expect(f.httpOperations.where((op) => op.startsWith('retry:')), isEmpty);
      expect(f.store.operations.where((op) => op.startsWith('retry:')), [
        'retry:set:$_accounts',
        'retry:remove:$_journal',
      ]);
      expect(f.store.mutations, [
        ...writes,
        'set:$_journal',
        'set:$_journal',
        'set:$_accounts',
        'remove:$_journal',
      ]);
      expect(
        (await f.disk())[f.cacheKey(f.first.id)],
        before[f.cacheKey(f.first.id)],
      );
      expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      expect(f.source(await f.disk()).encode(), target.encode());
      expect((await f.disk()).containsKey(_journal), isFalse);
      expect(
        f.withoutTarget(await f.disk(), f.first.id),
        f.withoutTarget(before, f.first.id),
      );
      expect(OAuthCalendarStorage.ownsRequest(f.first.id, 2), isTrue);
      expect(OAuthCalendarStorage.sourceRevision(f.first.id), source);
      expect(f.auth.isOAuthScopeLeaseCurrent(scope), isTrue);
      expect(oldCaller.isCurrent(), isFalse);
      expect(OAuthCalendarStorage.failure, isNull);
      f.expectOrdinary(await f.disk());
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
  final operations = <String>[];
  final reloadCounts = <String, int>{};
  final reloadHolds = <String, _Hold>{};
  final receivedHolds = <String, _Hold>{};
  final ownedHolds = <_Hold>[];

  _Hold holdReceived(String operation) {
    if (receivedHolds.containsKey(operation)) {
      throw StateError('Duplicate510 received hold');
    }
    final hold = _Hold();
    receivedHolds[operation] = hold;
    ownedHolds.add(hold);
    return hold;
  }

  _Hold holdReload(String operation, int ordinal) {
    final hold = _Hold();
    final key = '$operation:$ordinal';
    if (reloadHolds.containsKey(key)) {
      throw StateError('Duplicate419 hold $key');
    }
    reloadHolds[key] = hold;
    ownedHolds.add(hold);
    return hold;
  }

  @override
  Future<Map<String, Object>> getAll() async {
    final label = _operation;
    final ordinal = (reloadCounts[label] ?? 0) + 1;
    reloadCounts[label] = ordinal;
    final hold = reloadHolds.remove('$label:$ordinal');
    if (hold != null) {
      hold.started.complete();
      await hold.release.future;
    }
    return super.getAll();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    mutations.add('set:${logical(key)}');
    operations.add('$_operation:set:${logical(key)}');
    final result = await super.setValue(type, key, value);
    if (logical(key) == _journal &&
        value is String &&
        (jsonDecode(value) as Map<String, dynamic>)['phase'] == 'received') {
      final hold = receivedHolds.remove(_operation);
      if (hold != null) {
        hold.started.complete();
        await hold.release.future;
      }
    }
    return result;
  }

  @override
  Future<bool> remove(String key) {
    mutations.add('remove:${logical(key)}');
    operations.add('$_operation:remove:${logical(key)}');
    return super.remove(key);
  }

  @override
  Future<bool> clear() {
    mutations.add('clear');
    operations.add('$_operation:clear');
    return super.clear();
  }

  Future<Map<String, Object>> backing() => super.getAll();
  Future<void> inject(String key, Object value) async {
    final type = switch (value) {
      String() => 'String',
      int() => 'Int',
      _ => throw ArgumentError('Unsupported419 fixture value'),
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
  final httpOperations = <String>[];
  final httpHolds = <_Hold>[];
  final verifier = OAuthCalendarClient.generateCodeVerifier();
  final state = OAuthCalendarClient.generateCodeVerifier();
  late AuthProvider auth;
  late CalendarSyncProvider consumer;
  late OAuthCalendarAccount first;
  int tokenCalls = 0;
  int refreshCalls = 0;
  String latestAccess = '';
  _Hold? refreshHold;
  String eventTitle = 'Targeted419 initial event';

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
        expect(body['password'], 'synthetic-targeted419-password');
        return _json({
          'token': 'synthetic-targeted419-auth',
          'user': {'id': _account, 'username': _account},
        });
      }
      if (request.url.path == '/api/config') {
        return _json({});
      }
      if (request.url.host == 'oauth2.googleapis.com' &&
          request.method == 'POST') {
        final form = Uri.splitQueryString(request.body);
        expect(form['client_id'], 'synthetic-targeted419-client');
        if (form['grant_type'] == 'refresh_token') {
          requests.add('refresh');
          httpOperations.add('$_operation:refresh');
          expect(form.containsKey('code'), isFalse);
          expect(
            form['refresh_token'],
            refreshCalls == 0
                ? 'synthetic-targeted419-refresh-1'
                : 'synthetic-targeted419-renewed-refresh-$refreshCalls',
          );
          refreshCalls++;
          final hold = refreshHold;
          refreshHold = null;
          if (hold != null) {
            hold.started.complete();
            await hold.release.future;
          }
          latestAccess = 'synthetic-targeted419-renewed-access-$refreshCalls';
          return _json({
            'access_token': latestAccess,
            'refresh_token':
                'synthetic-targeted419-renewed-refresh-$refreshCalls',
            'expires_in': refreshCalls == 1 ? 60 : 7200,
            'token_type': 'Bearer',
          });
        }
        requests.add('token');
        httpOperations.add('$_operation:token');
        expect(form['grant_type'], 'authorization_code');
        expect(form['code_verifier'], verifier);
        tokenCalls++;
        latestAccess = 'synthetic-targeted419-access-$tokenCalls';
        return _json({
          'access_token': latestAccess,
          'refresh_token': 'synthetic-targeted419-refresh-$tokenCalls',
          'expires_in': 60,
          'token_type': 'Bearer',
        });
      }
      if (request.url.host != 'www.googleapis.com' || request.method != 'GET') {
        requests.add('unexpected');
        throw StateError(
          'Unexpected419 HTTP; targeted sync must not request ICS',
        );
      }
      final calendarId = request
          .url
          .pathSegments[request.url.pathSegments.indexOf('calendars') + 1];
      expect(request.headers['Authorization'], 'Bearer $latestAccess');
      requests.add('events:$calendarId');
      httpOperations.add('$_operation:events:$calendarId');
      return _json({
        'items': [
          {
            'id': 'target419-$calendarId',
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
        baseUrl: 'https://targeted419.example',
        httpClient: client(),
      ),
    );
    auths.add(auth);
    await auth
        .login(username: _account, password: 'synthetic-targeted419-password')
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
      displayName: 'Targeted419 $calendarId',
      clientId: 'synthetic-targeted419-client',
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
      displayName: 'Targeted419 $calendarId',
      clientId: 'synthetic-targeted419-client',
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
            'code': 'synthetic-targeted419-code-${tokenCalls + 1}',
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

  _Hold holdRefresh() {
    final hold = _Hold();
    refreshHold = hold;
    httpHolds.add(hold);
    return hold;
  }

  String cacheKey(String id) => '${OAuthCalendarStorage.eventsKeyPrefix}$id';
  OAuthOwnedRefreshJournal journal(Map<String, Object> raw) {
    final parsed = OAuthOwnedRefreshJournal.parse(
      raw[_journal]! as String,
      scope: auth.captureOAuthScopeLease().workspace.record,
    );
    expect(
      parsed,
      isNotNull,
      reason: 'Actual product journal must be canonical',
    );
    return parsed!;
  }

  OAuthOwnedSourceRecord source(Map<String, Object> raw) =>
      OAuthOwnedSourceRecord.parseList(
        raw[_accounts]! as String,
        scope: auth.captureOAuthScopeLease().workspace.record,
      )!.single;
  Map<String, Object> withoutJournal(Map<String, Object> raw) => {
    for (final e in raw.entries)
      if (e.key != _journal) e.key: e.value,
  };
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
    refreshHold = null;
    for (final hold in [...httpHolds, ...store.ownedHolds]) {
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
