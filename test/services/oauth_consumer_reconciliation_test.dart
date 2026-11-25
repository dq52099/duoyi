// ignore_for_file: depend_on_referenced_packages
// Prepared270 against frozen consumer16 fixtures and contract258; statically
// checked against released274 APIs. No compiler/test was run by this worker.

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
const _owner = OAuthCalendarStorage.scopeOwnerKey;
const _pendingKey = OAuthCalendarStorage.pendingAuthorizationKey;
const _ordinary = <String, Object>{
  'auth_state': '{ "token" : null }',
  'todos': '[ { "id" : "reconcile270", "title" : "confirmed ordinary todo" } ]',
  'duoyi_notes': '[ { "body" : "keep confirmed ordinary note270" } ]',
  'duoyi_ics_subscriptions_v1': '[]',
  'reconcile270_device_setting': 270,
};
Matcher get _rejected => anyOf(
  isA<OAuthStorageIndeterminate>(),
  isA<OAuthScopedWorkspaceUnavailable>(),
  isA<AccountPreferenceWriteCanceled>(),
  isA<OAuthLocalCommitRequired>(),
  isA<ApiException>(),
  isA<AccountLocalDataCleanupBlockedException>(),
  isA<OAuthAccountRetirementPending>(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() async => f = await _Fixture.create());
  tearDown(() async => f.close());

  test(
    'OCR270-01 public real issuer reconciliation restores confirmed rows before explicit fixed credential retry',
    () => f.withHttp(() async {
      final failed = await f.failRealCommit();
      final requests = f.requests.toList();
      final uncertain = await f.disk();
      final attempts = f.store.mutations.toList();
      final diagnostic = OAuthCalendarStorage.failure!;
      expect(f.consumer.oauthStorageNeedsReconciliation, isTrue);
      expect(f.consumer.oauthAccounts, isEmpty);
      expect(f.consumer.allEvents(), isEmpty);
      expect(f.auth.isGuestOAuthScopeLeaseCurrent(f.lease), isFalse);
      expect(f.auth.isGuestOAuthScopeLeaseRetainable(f.lease), isTrue);
      final recovery = f.auth.captureGuestOAuthReconciliationLease();
      expect(f.auth.isGuestOAuthReconciliationLeaseCurrent(recovery), isTrue);
      // Released274 hides local receipts while retaining the original candidate.
      for (var i = 0; i < 3; i++) {
        final handles = f.consumer.oauthLocalCommitReceipts
            .map((r) => r.handle)
            .toList();
        expect(handles, isEmpty);
        expect(OAuthCalendarStorage.failure, same(diagnostic));
      }
      await f.reject(
        f.consumer.updateOAuthAccount(f.confirmedAccount!),
        _rejected,
      );
      await f.reject(f.connect(code: 'blocked-reconciliation-code'), _rejected);
      final originalSession = f.auth.sessionGeneration;
      await f.reject(f.consumer.prepareOAuthScope(), _rejected);
      await f.reject(
        f.auth.loadFromStorage(refreshServerConfig: false),
        _rejected,
      );
      expect(f.auth.sessionGeneration, originalSession);
      expect(f.auth.isGuestOAuthReconciliationLeaseCurrent(recovery), isTrue);
      expect(await f.disk(), uncertain);
      expect(f.store.mutations, attempts);
      expect(f.requests, requests);

      // Positive control uses only the public consumer method. No direct-core
      // reconciliation, fabricated recovery lease, or constant authority predicate.
      await f.consumer.reconcileOAuthStorage().timeout(_wait);
      expect(OAuthCalendarStorage.failure, isNull);
      expect(f.consumer.oauthStorageNeedsReconciliation, isFalse);
      expect(f.auth.isGuestOAuthReconciliationLeaseCurrent(recovery), isFalse);
      expect(f.auth.isGuestOAuthScopeLeaseCurrent(f.lease), isTrue);
      // Check before load can reconstruct from durable pending: getter reads
      // during uncertainty must have retained the exact original candidate.
      final retainedReceipt = f.consumer.oauthLocalCommitReceipts.single;
      expect(retainedReceipt.handle, failed.pending.receiptHandle);
      expect(await f.disk(), failed.confirmedTransactionPreimage);
      expect(f.requests, requests);
      final restoredSources = f.sources(await f.disk());
      expect(restoredSources, hasLength(1));
      expect(restoredSources.single.account['id'], f.confirmedAccount!.id);
      expect(
        restoredSources.any(
          (s) => s.account['id'] == failed.returned.account['id'],
        ),
        isFalse,
      );
      // Explicit load may expose confirmed previous rows/cache, never candidate.
      await f.consumer.loadFromStorage().timeout(_wait);
      expect(f.consumer.oauthAccounts.single.id, f.confirmedAccount!.id);
      expect(f.consumer.allEvents().map((e) => e.title), [
        'Confirmed270 event',
      ]);
      final receipt = f.consumer.oauthLocalCommitReceipts.single;
      expect(receipt, same(retainedReceipt));
      expect(receipt.handle, failed.pending.receiptHandle);
      expect(receipt.isRefresh, isFalse);
      final account = await f.consumer
          .retryOAuthLocalCommit(receipt)
          .timeout(_wait);
      await AccountPreferenceWrites.drain().timeout(_wait);
      expect(account.id, failed.returned.account['id']);
      expect(account.accessToken, failed.returned.account['accessToken']);
      expect(account.refreshToken, failed.returned.account['refreshToken']);
      expect(
        account.expiresAt.toIso8601String(),
        failed.returned.account['expiresAt'],
      );
      final accepted = await f.disk();
      final rows = f.sources(accepted);
      expect(rows, hasLength(2));
      expect(
        rows.singleWhere((s) => s.account['id'] == account.id).encode(),
        failed.returned.encode(),
      );
      expect(accepted.containsKey(f.cacheKey(account.id)), isFalse);
      expect(
        accepted[f.cacheKey(f.confirmedAccount!.id)],
        failed.confirmedTransactionPreimage[f.cacheKey(f.confirmedAccount!.id)],
      );
      expect(accepted.containsKey(_pendingKey), isFalse);
      expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      expect(
        f.requests,
        requests,
        reason: 'reconcile and explicit retry are local only',
      );
      f.expectOrdinary(accepted);
    }),
  );

  test(
    'OCR270-02 default Auth and missing issuer cannot reconcile another issuers diagnostic',
    () => f.withHttp(() async {
      late CalendarSyncProvider otherPreparedIssuer;
      final failed = await f.failRealCommit(
        beforeFault: () async {
          final otherAuth = AuthProvider();
          f.auths.add(otherAuth);
          otherPreparedIssuer = CalendarSyncProvider(authProvider: otherAuth);
          f.consumers.add(otherPreparedIssuer);
          await otherAuth
              .loadFromStorage(refreshServerConfig: false)
              .timeout(_wait);
          await otherPreparedIssuer.prepareOAuthScope().timeout(_wait);
          expect(otherPreparedIssuer.isOAuthReady, isTrue);
          expect(
            otherAuth.isGuestOAuthScopeLeaseCurrent(
              otherAuth.captureGuestOAuthScopeLease(),
            ),
            isTrue,
          );
        },
      );
      final before = await f.disk();
      final diagnostic = OAuthCalendarStorage.failure!;
      final attempts = f.store.mutations.toList();
      final requests = f.requests.toList();
      final defaultAuth = AuthProvider();
      f.auths.add(defaultAuth);
      final foreign = CalendarSyncProvider(authProvider: defaultAuth);
      final missing = CalendarSyncProvider();
      f.consumers.addAll([foreign, missing]);
      for (final consumer in [otherPreparedIssuer, foreign, missing]) {
        await f.reject(consumer.reconcileOAuthStorage(), _rejected);
        expect(consumer.oauthAccounts, isEmpty);
        expect(consumer.oauthLocalCommitReceipts, isEmpty);
        expect(OAuthCalendarStorage.failure, same(diagnostic));
        expect(await f.disk(), before);
        expect(f.store.mutations, attempts);
        expect(f.requests, requests);
      }
      // The original real issuer is still permitted after these failed probes.
      await f.consumer.reconcileOAuthStorage().timeout(_wait);
      expect(await f.disk(), failed.confirmedTransactionPreimage);
      expect(OAuthCalendarStorage.failure, isNull);
      expect(
        f.consumer.oauthLocalCommitReceipts.single.handle,
        failed.pending.receiptHandle,
      );
      expect(f.requests, requests);
    }),
  );

  test(
    'OCR270-03 foreign canonical scope rejects public recovery and preserves diagnostic and replacement bytes',
    () => f.withHttp(() async {
      final failed = await f.failRealCommit();
      final originalRaw = (await f.disk())[_owner]! as String;
      final fields = jsonDecode(originalRaw) as Map<String, dynamic>;
      fields['scopedOwner'] =
          fields['scopedOwner'] == 'g:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
          ? 'g:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
          : 'g:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      final foreignRaw = jsonEncode(fields);
      expect(OAuthScopedOwnerRecord.parse(foreignRaw), isNotNull);
      f.restoreAtTeardown[_owner] = originalRaw;
      await f.store.inject(_owner, foreignRaw);
      await f.prefs.reload();
      final before = await f.disk();
      final diagnostic = OAuthCalendarStorage.failure!;
      final attempts = f.store.mutations.toList();
      final requests = f.requests.toList();
      await f.reject(f.consumer.reconcileOAuthStorage(), _rejected);
      expect(OAuthCalendarStorage.failure, same(diagnostic));
      expect(await f.disk(), before);
      expect((await f.disk())[_owner], foreignRaw);
      expect(f.store.mutations, attempts);
      expect(f.requests, requests);
      expect(f.consumer.oauthAccounts, isEmpty);
      expect(f.consumer.allEvents(), isEmpty);
      expect(failed.returned.account['id'], isNot(f.confirmedAccount!.id));
    }),
  );

  test(
    'OCR270-04 third typed accounts value rejects public reconciliation without normalizing foreign bytes',
    () => f.withHttp(() async {
      await f.failRealCommit();
      final uncertain = await f.disk();
      f.restoreAtTeardown[_accounts] = uncertain[_accounts]!;
      await f.store.inject(_accounts, 270);
      await f.prefs.reload();
      final before = await f.disk();
      final diagnostic = OAuthCalendarStorage.failure!;
      final requests = f.requests.toList();
      final attempts = f.store.mutations.toList();
      await f.reject(f.consumer.reconcileOAuthStorage(), _rejected);
      expect(OAuthCalendarStorage.failure, same(diagnostic));
      expect(await f.disk(), before);
      expect((await f.disk())[_accounts], 270);
      expect(f.store.mutations, attempts);
      expect(f.requests, requests);
      expect(f.consumer.oauthAccounts, isEmpty);
    }),
  );

  test(
    'OCR270-05 token returned during another sources indeterminate write remains memory-only until explicit retry',
    () => f.withHttp(() async {
      await f.initializeConfirmed();
      final targetHold = f.holdNextHttp('token');
      final connecting = f.observe(
        f.connect(code: 'synthetic-reconcile270-held-code'),
      );
      await targetHold.started.future.timeout(_wait);
      final dispatchedDisk = await f.disk();
      final scope = OAuthScopedOwnerRecord.parse(f.lease.workspace.rawRecord)!;
      final dispatched = OAuthOwnedPendingAuthorization.parse(
        dispatchedDisk[_pendingKey]! as String,
        scope: scope,
      )!;
      expect(dispatched.phase, OAuthPendingPhase.dispatched);
      expect(dispatched.receivedSource, isNull);
      expect(dispatched.receiptHandle, isNull);
      final targetId = dispatched.sourceAccountId!;
      final targetRevision = OAuthCalendarStorage.sourceRevision(targetId);
      f.store.failAccountsPhase = 1;
      await f.reject(
        f.consumer.updateOAuthAccount(
          f.confirmedAccount!.copyWith(
            displayName: 'Failed unrelated source rename',
          ),
        ),
        _rejected,
      );
      await AccountPreferenceWrites.drain().timeout(_wait);
      final diagnostic = OAuthCalendarStorage.failure!;
      expect(diagnostic, isA<OAuthStorageIndeterminate>());
      expect(OAuthCalendarStorage.sourceRevision(targetId), targetRevision);
      expect(f.auth.isGuestOAuthScopeLeaseRetainable(f.lease), isTrue);
      final uncertain = await f.disk();
      final requests = f.requests.toList();
      final attempts = f.store.mutations.toList();
      targetHold.release.complete();
      expect(
        (await connecting.timeout(_wait)).error,
        isA<AccountPreferenceWriteCanceled>(),
      );
      await AccountPreferenceWrites.drain().timeout(_wait);
      expect(await f.disk(), uncertain);
      expect(f.store.mutations, attempts);
      expect(f.requests, requests);
      expect(OAuthCalendarStorage.failure, same(diagnostic));
      for (var i = 0; i < 3; i++) {
        expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      }
      final stillDispatched = OAuthOwnedPendingAuthorization.parse(
        (await f.disk())[_pendingKey]! as String,
        scope: scope,
      )!;
      expect(stillDispatched.encode(), dispatched.encode());
      expect(stillDispatched.phase, OAuthPendingPhase.dispatched);
      expect(stillDispatched.receivedSource, isNull);
      await f.consumer.reconcileOAuthStorage().timeout(_wait);
      expect(OAuthCalendarStorage.failure, isNull);
      expect(await f.disk(), f.store.transactionPreimage!);
      // No load/loadPending has occurred: a dispatched record contains no tokens
      // and cannot reconstruct this returned in-memory-only candidate.
      final receipt = f.consumer.oauthLocalCommitReceipts.single;
      expect(receipt.isRefresh, isFalse);
      final write = f.store.holdNextAcceptedAccountsWrite();
      final retrying = f.observe(f.consumer.retryOAuthLocalCommit(receipt));
      await write.started.future.timeout(_wait);
      final issued = OAuthOwnedSourceRecord.parseList(
        write.value!,
        scope: scope,
      )!.singleWhere((s) => s.account['id'] == targetId);
      expect(issued.account['accessToken'], 'synthetic-reconcile270-access-2');
      expect(
        issued.account['refreshToken'],
        'synthetic-reconcile270-refresh-2',
      );
      expect(issued.account['displayName'], dispatched.draft['displayName']);
      expect(f.requests, requests);
      write.release.complete();
      final recovered = await retrying.timeout(_wait);
      expect(recovered.error, isNull);
      final account = recovered.value!;
      expect(account.id, targetId);
      expect(account.accessToken, issued.account['accessToken']);
      expect(account.refreshToken, issued.account['refreshToken']);
      expect(account.expiresAt.toIso8601String(), issued.account['expiresAt']);
      final accepted = await f.disk();
      expect(
        f
            .sources(accepted)
            .singleWhere((s) => s.account['id'] == targetId)
            .encode(),
        issued.encode(),
      );
      expect(accepted.containsKey(_pendingKey), isFalse);
      expect(accepted.containsKey(f.cacheKey(targetId)), isFalse);
      expect(
        accepted[f.cacheKey(f.confirmedAccount!.id)],
        dispatchedDisk[f.cacheKey(f.confirmedAccount!.id)],
      );
      expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      expect(f.requests, requests);
      f.expectOrdinary(accepted);
    }),
  );

  test(
    'OCR270-06 refresh returned during another sources failure survives hidden getter and retries without HTTP',
    () => f.withHttp(() async {
      await f.initializeConfirmed();
      final target = f.confirmedAccount!;
      final other = await f
          .connect(code: 'synthetic-reconcile270-other-source-code')
          .timeout(_wait);
      final confirmedDisk = await f.disk();
      final targetSource = f
          .sources(confirmedDisk)
          .singleWhere((s) => s.account['id'] == target.id);
      final expired = targetSource.withAccount({
        ...targetSource.account,
        'expiresAt': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 5))
            .toIso8601String(),
      });
      final rows = f
          .sources(confirmedDisk)
          .map((s) => s.account['id'] == target.id ? expired : s)
          .toList();
      await f.store.inject(
        _accounts,
        jsonEncode(rows.map((s) => s.toJson()).toList()),
      );
      await f.prefs.reload();
      await f.consumer.loadFromStorage().timeout(_wait);
      final peer = CalendarSyncProvider(authProvider: f.auth);
      f.consumers.add(peer);
      await peer.loadFromStorage().timeout(_wait);
      final peerOther = peer.oauthAccounts.singleWhere((a) => a.id == other.id);
      final hold = f.holdNextHttp('refresh');
      final syncing = f.observe(f.consumer.syncAll());
      await hold.started.future.timeout(_wait);
      final targetRevision = OAuthCalendarStorage.sourceRevision(target.id);
      f.store.failAccountsPhase = 1;
      await f.reject(
        peer.updateOAuthAccount(
          peerOther.copyWith(displayName: 'Failed refresh peer rename'),
        ),
        _rejected,
      );
      await AccountPreferenceWrites.drain().timeout(_wait);
      final diagnostic = OAuthCalendarStorage.failure!;
      expect(OAuthCalendarStorage.sourceRevision(target.id), targetRevision);
      final uncertain = await f.disk();
      final requests = f.requests.toList();
      final attempts = f.store.mutations.toList();
      hold.release.complete();
      expect((await syncing.timeout(_wait)).error, isNull);
      await AccountPreferenceWrites.drain().timeout(_wait);
      expect(await f.disk(), uncertain);
      expect(f.store.mutations, attempts);
      expect(f.requests, requests);
      expect(OAuthCalendarStorage.failure, same(diagnostic));
      expect((await f.disk()).containsKey(_pendingKey), isFalse);
      for (var i = 0; i < 3; i++) {
        expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      }
      await f.consumer.reconcileOAuthStorage().timeout(_wait);
      expect(await f.disk(), f.store.transactionPreimage!);
      // No durable received refresh/pending record and no load can supply tokens.
      final receipt = f.consumer.oauthLocalCommitReceipts.single;
      expect(receipt.isRefresh, isTrue);
      final write = f.store.holdNextAcceptedAccountsWrite();
      final retrying = f.observe(f.consumer.retryOAuthLocalCommit(receipt));
      await write.started.future.timeout(_wait);
      final scope = OAuthScopedOwnerRecord.parse(f.lease.workspace.rawRecord)!;
      final issued = OAuthOwnedSourceRecord.parseList(
        write.value!,
        scope: scope,
      )!.singleWhere((s) => s.account['id'] == target.id);
      expect(
        issued.account['accessToken'],
        'synthetic-reconcile270-rotated-access',
      );
      expect(
        issued.account['refreshToken'],
        'synthetic-reconcile270-rotated-refresh',
      );
      expect(issued.sourceIncarnation, expired.sourceIncarnation);
      expect(issued.credentialRevision, expired.credentialRevision + 1);
      expect(f.requests, requests);
      write.release.complete();
      final result = await retrying.timeout(_wait);
      expect(result.error, isNull);
      expect(result.value!.id, target.id);
      expect(result.value!.accessToken, issued.account['accessToken']);
      expect(result.value!.refreshToken, issued.account['refreshToken']);
      expect(
        result.value!.expiresAt.toIso8601String(),
        issued.account['expiresAt'],
      );
      final accepted = await f.disk();
      expect(
        f
            .sources(accepted)
            .singleWhere((s) => s.account['id'] == target.id)
            .encode(),
        issued.encode(),
      );
      expect(
        accepted[f.cacheKey(target.id)],
        confirmedDisk[f.cacheKey(target.id)],
      );
      expect(
        f
            .sources(accepted)
            .singleWhere((s) => s.account['id'] == other.id)
            .encode(),
        f
            .sources(confirmedDisk)
            .singleWhere((s) => s.account['id'] == other.id)
            .encode(),
      );
      expect(accepted.containsKey(_pendingKey), isFalse);
      expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      expect(f.requests, requests);
      f.expectOrdinary(accepted);
    }),
  );

  test(
    'OCR270-07 queued Auth scope restore during held failed local write preserves original reconciliation authority',
    () => f.withHttp(() => f.rejectQueuedAuthDuringHeldWrite(hydrate: false)),
  );

  test(
    'OCR270-08 queued Auth hydration during held failed local write preserves original session and reconciliation authority',
    () => f.withHttp(() => f.rejectQueuedAuthDuringHeldWrite(hydrate: true)),
  );
}

class _Failure {
  _Failure(this.confirmedTransactionPreimage, this.pending, this.returned);
  final Map<String, Object> confirmedTransactionPreimage;
  final OAuthOwnedPendingAuthorization pending;
  final OAuthOwnedSourceRecord returned;
}

class _BackingStore extends InMemorySharedPreferencesStore {
  _BackingStore() : super.withData({});
  final mutations = <String>[];
  int failAccountsPhase = 0;
  Map<String, Object>? transactionPreimage;
  String? issuedAccounts;
  _Hold? acceptedAccountsHold;
  _Hold? failedAccountsHold;
  final accountHolds = <_Hold>[];
  _Hold holdNextFailedAccountsWrite() {
    final h = _Hold('failed-accounts');
    failAccountsPhase = 1;
    failedAccountsHold = h;
    accountHolds.add(h);
    return h;
  }

  _Hold holdNextAcceptedAccountsWrite() {
    final h = _Hold('accounts');
    acceptedAccountsHold = h;
    accountHolds.add(h);
    return h;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    mutations.add('set:${logical(key)}');
    if (logical(key) == _accounts && failAccountsPhase == 1) {
      transactionPreimage = {
        for (final e in (await super.getAll()).entries) logical(e.key): e.value,
      };
      issuedAccounts = value as String;
      expect(await super.setValue(type, key, value), isTrue);
      failAccountsPhase = 2;
      if (failedAccountsHold != null) {
        final h = failedAccountsHold!;
        failedAccountsHold = null;
        h.value = value;
        h.started.complete();
        await h.release.future;
      }
      return false; // Real issued row survives the failed acknowledgement.
    }
    if (logical(key) == _accounts && failAccountsPhase == 2) {
      failAccountsPhase = 0;
      return false; // Checked compensation cannot restore its previous bytes.
    }
    final saved = await super.setValue(type, key, value);
    if (logical(key) == _accounts && acceptedAccountsHold != null) {
      final h = acceptedAccountsHold!;
      acceptedAccountsHold = null;
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

class _Outcome<T> {
  _Outcome.value(this.value) : error = null;
  _Outcome.error(this.error) : value = null;
  final T? value;
  final Object? error;
}

class _Hold {
  _Hold(this.phase);
  final String phase;
  final started = Completer<void>();
  final release = Completer<void>();
  String? value;
}

class _Fixture {
  _Fixture(this.previous, this.store, this.prefs);
  final SharedPreferencesStorePlatform previous;
  final _BackingStore store;
  final SharedPreferences prefs;
  final auths = <AuthProvider>[];
  final consumers = <CalendarSyncProvider>[];
  final clients = <http.Client>[];
  final requests = <String>[];
  final pending = <Future<void>>[];
  final restoreAtTeardown = <String, Object>{};
  final verifier = OAuthCalendarClient.generateCodeVerifier();
  final state = OAuthCalendarClient.generateCodeVerifier();
  late AuthProvider auth;
  late CalendarSyncProvider consumer;
  late AuthGuestOAuthScopeLease lease;
  OAuthCalendarAccount? confirmedAccount;
  int tokenCalls = 0;
  final httpHolds = <_Hold>[];
  _Hold holdNextHttp(String phase) {
    final h = _Hold(phase);
    httpHolds.add(h);
    return h;
  }

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

  Future<void> withHttp(
    Future<void> Function() body,
  ) => http.runWithClient(body, () {
    final client = MockClient((request) async {
      final form =
          request.method == 'POST' &&
              request.url.host == 'oauth2.googleapis.com'
          ? Uri.splitQueryString(request.body)
          : null;
      final phase = form != null
          ? (form['grant_type'] == 'refresh_token' ? 'refresh' : 'token')
          : request.method == 'GET' && request.url.host == 'www.googleapis.com'
          ? 'events'
          : 'unexpected';
      requests.add(phase);
      if (phase == 'unexpected') {
        throw StateError('Unexpected reconciliation request');
      }
      final waiting = httpHolds.where(
        (h) => h.phase == phase && !h.started.isCompleted,
      );
      if (waiting.isNotEmpty) {
        final h = waiting.first;
        h.started.complete();
        await h.release.future;
      }
      if (phase == 'refresh') {
        final tokenForm = form!;
        expect(tokenForm['refresh_token'], 'synthetic-reconcile270-refresh-1');
        expect(tokenForm['client_id'], 'synthetic-reconcile270-client');
        expect(tokenForm.containsKey('code'), isFalse);
        return _json({
          'access_token': 'synthetic-reconcile270-rotated-access',
          'refresh_token': 'synthetic-reconcile270-rotated-refresh',
          'expires_in': 7200,
          'token_type': 'Bearer',
          'scope': 'https://www.googleapis.com/auth/calendar.readonly',
        });
      }
      if (phase == 'token') {
        final tokenForm = form!;
        expect(tokenForm['grant_type'], 'authorization_code');
        expect(tokenForm['client_id'], 'synthetic-reconcile270-client');
        expect(tokenForm['code_verifier'], verifier);
        expect(tokenForm['code'], isNotEmpty);
        expect(tokenForm['redirect_uri'], 'duoyi://oauth/calendar');
        tokenCalls++;
        return _json({
          'access_token': 'synthetic-reconcile270-access-$tokenCalls',
          'refresh_token': 'synthetic-reconcile270-refresh-$tokenCalls',
          'expires_in': 7200,
          'token_type': 'Bearer',
          'scope': 'https://www.googleapis.com/auth/calendar.readonly',
        });
      }
      expect(
        request.headers['Authorization'],
        anyOf(
          'Bearer synthetic-reconcile270-access-1',
          'Bearer synthetic-reconcile270-access-2',
        ),
      );
      return _json({
        'items': [
          {
            'id': 'confirmed270',
            'summary': 'Confirmed270 event',
            'start': {'dateTime': '2026-11-10T09:00:00Z'},
            'end': {'dateTime': '2026-11-10T10:00:00Z'},
          },
        ],
      });
    });
    clients.add(client);
    return client;
  });
  Future<void> initializeConfirmed() async {
    auth = AuthProvider();
    auths.add(auth);
    consumer = CalendarSyncProvider(authProvider: auth);
    consumers.add(consumer);
    await auth.loadFromStorage(refreshServerConfig: false).timeout(_wait);
    await consumer.prepareOAuthScope(initialize: true).timeout(_wait);
    lease = auth.captureGuestOAuthScopeLease();
    confirmedAccount = await connect(
      code: 'synthetic-reconcile270-first-code',
    ).timeout(_wait);
    expect(consumer.allEvents().map((e) => e.title), ['Confirmed270 event']);
  }

  Future<void> rejectQueuedAuthDuringHeldWrite({required bool hydrate}) async {
    await initializeConfirmed();
    final confirmed = await disk();
    final originalSession = auth.sessionGeneration;
    final guest = auth.captureGuestWorkspaceLease();
    final hold = store.holdNextFailedAccountsWrite();
    final writing = observe(
      consumer.updateOAuthAccount(
        confirmedAccount!.copyWith(
          displayName: 'Held local write must not revoke issuer',
        ),
      ),
    );
    await hold.started.future.timeout(_wait);
    // This is a held local storage ACK, after persistence, not a held HTTP
    // response. The checked rollback and diagnostic do not yet exist.
    expect(OAuthCalendarStorage.failure, isNull);
    expect(store.failAccountsPhase, 2);
    expect(store.transactionPreimage, confirmed);
    final heldDisk = await disk();
    expect(heldDisk[_accounts], hold.value);
    expect(heldDisk[_accounts], isNot(confirmed[_accounts]));
    final attempts = store.mutations.toList();
    final httpRequests = requests.toList();
    var queuedSettled = false;
    final queued = observe(
      hydrate
          ? auth.loadFromStorage(refreshServerConfig: false)
          : auth.restoreGuestOAuthScope(),
    );
    queued.then<void>((_) {
      queuedSettled = true;
    });
    // Give the public request's continuation an event turn to enter the
    // occupied OAuth lane. The platform ACK remains explicitly unreleased.
    await Future<void>.delayed(Duration.zero);
    expect(queuedSettled, isFalse);
    expect(OAuthCalendarStorage.failure, isNull);
    expect(auth.sessionGeneration, originalSession);
    expect(auth.isAccountTransitionInProgress, isFalse);
    expect(auth.isLocalAccountDataBlocked, isFalse);
    expect(auth.isGuestWorkspaceLeaseCurrent(guest), isTrue);
    expect(auth.isGuestOAuthScopeLeaseCurrent(lease), isTrue);
    expect(auth.captureGuestOAuthScopeLease().workspace, same(lease.workspace));
    expect(await disk(), heldDisk);
    expect(store.mutations, attempts);
    expect(requests, httpRequests);

    hold.release.complete();
    final writeResult = await writing.timeout(_wait);
    final diagnostic = OAuthCalendarStorage.failure!;
    expect(diagnostic, isA<OAuthStorageIndeterminate>());
    expect(writeResult.error, same(diagnostic));
    final recovery = auth.captureGuestOAuthReconciliationLease();
    expect(recovery.recovery.workspace, same(lease.workspace));
    expect(auth.isGuestOAuthReconciliationLeaseCurrent(recovery), isTrue);
    expect((await queued.timeout(_wait)).error, same(diagnostic));
    await AccountPreferenceWrites.drain().timeout(_wait);
    expect(store.failAccountsPhase, 0);
    expect(OAuthCalendarStorage.failure, same(diagnostic));
    expect(auth.sessionGeneration, originalSession);
    expect(auth.isAccountTransitionInProgress, isFalse);
    expect(auth.isLocalAccountDataBlocked, isFalse);
    expect(auth.isGuestWorkspaceLeaseCurrent(guest), isTrue);
    expect(auth.isGuestOAuthScopeLeaseCurrent(lease), isFalse);
    expect(auth.isGuestOAuthScopeLeaseRetainable(lease), isTrue);
    expect(auth.isGuestOAuthReconciliationLeaseCurrent(recovery), isTrue);
    expect(await disk(), heldDisk);
    expect(store.mutations, [...attempts, 'set:$_accounts']);
    expect(requests, httpRequests);
    expect(consumer.oauthAccounts, isEmpty);
    expect(consumer.allEvents(), isEmpty);

    // Only the original issuer's public consumer recovery repairs storage.
    await consumer.reconcileOAuthStorage().timeout(_wait);
    expect(OAuthCalendarStorage.failure, isNull);
    expect(await disk(), confirmed);
    expect(auth.sessionGeneration, originalSession);
    expect(auth.isGuestWorkspaceLeaseCurrent(guest), isTrue);
    expect(auth.isGuestOAuthScopeLeaseCurrent(lease), isTrue);
    expect(auth.isGuestOAuthReconciliationLeaseCurrent(recovery), isFalse);
    expect(consumer.oauthLocalCommitReceipts, isEmpty);
    expect(requests, httpRequests);
    expectOrdinary(await disk());
  }

  Future<_Failure> failRealCommit({
    Future<void> Function()? beforeFault,
  }) async {
    await initializeConfirmed();
    if (beforeFault != null) await beforeFault();
    store.failAccountsPhase = 1;
    final failed = await observe(
      connect(code: 'synthetic-reconcile270-second-code'),
    ).timeout(_wait);
    expect(failed.error, _rejected);
    await AccountPreferenceWrites.drain().timeout(_wait);
    expect(store.failAccountsPhase, 0);
    expect(OAuthCalendarStorage.failure, isA<OAuthStorageIndeterminate>());
    final preimage = store.transactionPreimage!;
    final scope = OAuthScopedOwnerRecord.parse(lease.workspace.rawRecord)!;
    final received = OAuthOwnedPendingAuthorization.parse(
      preimage[_pendingKey]! as String,
      scope: scope,
    )!;
    expect(received.phase, OAuthPendingPhase.received);
    final returned = received.receivedSource!;
    expect(returned.account['accessToken'], 'synthetic-reconcile270-access-2');
    expect(
      returned.account['refreshToken'],
      'synthetic-reconcile270-refresh-2',
    );
    expect((await disk())[_accounts], store.issuedAccounts);
    expect(returned.account['id'], isNot(confirmedAccount!.id));
    expect(requests.where((r) => r == 'token'), hasLength(2));
    expect(requests.where((r) => r == 'events'), hasLength(1));
    return _Failure(preimage, received, returned);
  }

  Future<OAuthCalendarAccount> connect({required String code}) async {
    await consumer.savePendingOAuthAuthorization(
      provider: OAuthCalendarProvider.google,
      displayName: tokenCalls == 0
          ? 'Confirmed270 calendar'
          : 'Candidate270 calendar',
      clientId: 'synthetic-reconcile270-client',
      clientSecret: '',
      redirectUri: 'duoyi://oauth/calendar',
      calendarId: 'primary',
      codeVerifier: verifier,
      state: state,
    );
    final displayName = tokenCalls == 0
        ? 'Confirmed270 calendar'
        : 'Candidate270 calendar';
    return consumer.addOAuthAccountFromCode(
      provider: OAuthCalendarProvider.google,
      displayName: displayName,
      clientId: 'synthetic-reconcile270-client',
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
  }

  List<OAuthOwnedSourceRecord> sources(Map<String, Object> raw) =>
      OAuthOwnedSourceRecord.parseList(
        raw[_accounts]! as String,
        scope: OAuthScopedOwnerRecord.parse(raw[_owner])!,
      )!;
  String cacheKey(String id) => '${OAuthCalendarStorage.eventsKeyPrefix}$id';
  Future<Map<String, Object>> disk() async => {
    for (final e in (await store.backing()).entries)
      _BackingStore.logical(e.key): e.value,
  };
  void expectOrdinary(Map<String, Object> raw) {
    for (final e in _ordinary.entries) {
      expect(raw[e.key], e.value, reason: e.key);
    }
  }

  Future<_Outcome<T>> observe<T>(Future<T> work) {
    final result = work.then<_Outcome<T>>(
      (value) => _Outcome<T>.value(value),
      onError: (Object error, StackTrace _) => _Outcome<T>.error(error),
    );
    pending.add(result.then<void>((_) {}));
    return result;
  }

  Future<void> reject<T>(Future<T> work, Matcher expected) async =>
      expect((await observe(work).timeout(_wait)).error, expected);
  Future<void> close() async {
    store.failAccountsPhase = 0;
    store.acceptedAccountsHold = null;
    store.failedAccountsHold = null;
    for (final h in [...httpHolds, ...store.accountHolds]) {
      if (!h.release.isCompleted) h.release.complete();
    }
    try {
      await Future.wait(pending).timeout(_wait);
      await AccountPreferenceWrites.drain().timeout(_wait);
      // Fault/foreign-byte restoration is test-isolation after all assertions.
      // Recovery itself is never performed through a direct core positive call.
      for (final e in restoreAtTeardown.entries) {
        await store.inject(e.key, e.value);
      }
      await prefs.reload();
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
