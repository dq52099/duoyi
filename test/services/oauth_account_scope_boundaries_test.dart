// ignore_for_file: depend_on_referenced_packages
// Prepared290 against the real account issuer288 public APIs. Static only;
// no compiler, formatter or test execution was performed by this worker.

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
const _account = 'signed290-account-a';
const _eventTitle = 'Signed290 confirmed event';
const _ordinary = <String, Object>{
  'auth_state': '{ "token" : null }',
  'todos': '[ { "id" : "signed290", "title" : "keep imported todo290" } ]',
  'duoyi_notes': '[ { "body" : "keep imported note290" } ]',
  'duoyi_ics_subscriptions_v1': '[]',
  'signed290_device_setting': 290,
};
Matcher get _rejected => anyOf([
  isA<ApiException>(),
  isA<AccountPreferenceWriteCanceled>(),
  isA<OAuthScopedWorkspaceUnavailable>(),
  isA<OAuthScopeInitializationPending>(),
  isA<OAuthStorageIndeterminate>(),
  isA<OAuthLocalCommitRequired>(),
  isA<OAuthAccountRetirementPending>(),
  isA<AccountLocalDataCleanupBlockedException>(),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() async => f = await _Fixture.create());
  tearDown(() async => f.close());

  test(
    'ASB290-01 initialState-only signed-in Auth cannot prepare or dispatch OAuth',
    () => f.withHttp(() async {
      await f.initializeConfirmed();
      // Even matching state over actual account-owned inventory supplies neither
      // this new Auth's durable readback nor its original preparation evidence.
      final auth = f.newAuth(
        initialState: const AuthState(
          userId: _account,
          username: _account,
          token: 'synthetic-auth290-$_account',
        ),
      );
      final session = auth.captureSessionLease();
      final consumer = f.newConsumer(auth);
      final before = await f.disk();
      final writes = f.store.mutations.toList();
      final api = f.apiRequests.toList();
      final requests = f.oauthRequests.toList();
      await f.reject(consumer.prepareOAuthScope(initialize: true), _rejected);
      await f.reject(auth.restoreOAuthScope(), _rejected);
      await f.reject(f.savePending(consumer), _rejected);
      await f.reject(f.dispatch(consumer), _rejected);
      expect(auth.captureOAuthScopeLease, throwsA(_rejected));
      expect(auth.isSessionLeaseCurrent(session), isTrue);
      expect(consumer.isOAuthReady, isFalse);
      expect(consumer.oauthAccounts, isEmpty);
      expect(consumer.oauthLocalCommitReceipts, isEmpty);
      expect(await f.disk(), before);
      expect(f.store.mutations, writes);
      expect(f.apiRequests, api);
      expect(f.oauthRequests, requests);
      expect(f.auth.isOAuthScopeLeaseCurrent(f.lease), isTrue);
      expect(f.consumer.oauthAccounts.single.id, f.confirmedAccount!.id);
    }),
  );

  for (final variant in ['foreign', 'malformed', 'missing', 'orphan']) {
    test(
      'ASB290-cold-$variant same-account cold hydration rejects private corruption without writes',
      () => f.withHttp(() async {
        await f.initializeConfirmed();
        final confirmed = await f.disk();
        final scope = f.accountScope(confirmed);
        final authBytes = confirmed['auth_state'];
        f.disposeConsumer(f.consumer);
        f.disposeAuth(f.auth);
        if (variant == 'foreign') {
          // Persisted Auth/account owner remain A; a canonical scope for another
          // account must not authorize A's actual source/cache inventory.
          final fields = jsonDecode(scope.encode()) as Map<String, dynamic>;
          final foreignOwner = 'a:${List.filled(64, '0').join()}';
          fields['scopedOwner'] = scope.scopedOwner == foreignOwner
              ? 'a:${List.filled(64, '1').join()}'
              : foreignOwner;
          final foreign = jsonEncode(fields);
          final parsed = OAuthScopedOwnerRecord.parse(foreign)!;
          expect(parsed.matchesAccountOwner('id:$_account'), isFalse);
          expect(parsed.oauthIncarnation, scope.oauthIncarnation);
          f.restoreAtTeardown[_scopeKey] = confirmed[_scopeKey];
          await f.store.inject(_scopeKey, foreign);
        } else if (variant == 'malformed') {
          f.restoreAtTeardown[_scopeKey] = confirmed[_scopeKey];
          final truncated = scope.encode().substring(
            0,
            scope.encode().length - 1,
          );
          expect(OAuthScopedOwnerRecord.parse(truncated), isNull);
          await f.store.inject(_scopeKey, truncated);
        } else if (variant == 'missing') {
          f.restoreAtTeardown[_scopeKey] = confirmed[_scopeKey];
          await f.store.inject(_scopeKey, null);
        } else {
          final orphanId = f.verifier == f.confirmedAccount!.id
              ? f.state
              : f.verifier;
          expect(orphanId, isNot(f.confirmedAccount!.id));
          final orphanKey = f.cacheKey(orphanId);
          expect(confirmed.containsKey(orphanKey), isFalse);
          f.restoreAtTeardown[orphanKey] = null;
          await f.store.inject(
            orphanKey,
            confirmed[f.cacheKey(f.confirmedAccount!.id)]!,
          );
        }
        await f.prefs.reload();
        final before = await f.disk();
        expect(before['auth_state'], authBytes);
        expect(before[_accountOwner], 'id:$_account');
        final writes = f.store.mutations.toList();
        final requests = f.oauthRequests.toList();
        final coldAuth = f.newAuth();
        final cold = f.newConsumer(coldAuth);
        await f.reject(
          coldAuth.loadFromStorage(refreshServerConfig: false),
          isA<AccountLocalDataCleanupBlockedException>(),
        );
        await f.reject(cold.prepareOAuthScope(), _rejected);
        await f.reject(f.savePending(cold), _rejected);
        await f.reject(f.dispatch(cold), _rejected);
        expect(coldAuth.captureOAuthScopeLease, throwsA(_rejected));
        expect(coldAuth.isLocalAccountDataBlocked, isTrue);
        expect(cold.isOAuthReady, isFalse);
        expect(cold.oauthAccounts, isEmpty);
        expect(cold.allEvents(), isEmpty);
        expect(cold.oauthLocalCommitReceipts, isEmpty);
        expect(await f.disk(), before);
        expect(f.store.mutations, writes);
        expect(f.oauthRequests, requests);
        f.expectOrdinary(before);
      }),
    );
  }

  for (final persist in [false, true]) {
    final phase = persist ? 'after' : 'before';
    test(
      'ASB290-init-$phase account scope ACK false requires exact explicit confirmation',
      () => f.withHttp(() async {
        f.auth = await f.login();
        f.consumer = f.newConsumer(f.auth);
        final session = f.auth.captureSessionLease();
        final before = await f.disk();
        expect(before.containsKey(_scopeKey), isFalse);
        f.store.ownerFault = persist;
        await f.reject(
          f.consumer.prepareOAuthScope(initialize: true),
          isA<OAuthScopeInitializationPending>(),
        );
        final issued = f.store.issuedOwner!;
        final scope = OAuthScopedOwnerRecord.parse(issued)!;
        expect(scope.scopeKind, 'account');
        expect(scope.matchesAccountOwner('id:$_account'), isTrue);
        final failed = await f.disk();
        expect(failed, persist ? {...before, _scopeKey: issued} : before);
        expect(OAuthCalendarStorage.failure, isNull);
        expect(f.consumer.isOAuthReady, isFalse);
        expect(f.auth.isSessionLeaseCurrent(session), isTrue);
        expect(f.auth.captureOAuthScopeLease, throwsA(_rejected));
        final writes = f.store.mutations.toList();
        final requests = f.oauthRequests.toList();
        await f.reject(f.auth.restoreOAuthScope(), _rejected);
        await f.reject(
          f.consumer.prepareOAuthScope(initialize: true),
          _rejected,
        );
        await f.reject(f.savePending(f.consumer), _rejected);
        expect(await f.disk(), failed);
        expect(f.store.mutations, writes);
        expect(f.oauthRequests, requests);
        // Public explicit confirmation must reuse the actual issued identity.
        await f.auth.confirmOAuthScopeInitialization().timeout(_wait);
        final lease = f.auth.captureOAuthScopeLease();
        expect(lease.workspace.rawRecord, issued);
        expect(f.auth.isOAuthScopeLeaseCurrent(lease), isTrue);
        expect(f.auth.isSessionLeaseCurrent(session), isTrue);
        expect(f.consumer.isOAuthReady, isTrue);
        expect(f.store.ownerWrites, [issued, issued]);
        expect(await f.disk(), {...before, _scopeKey: issued});
        expect(f.oauthRequests, requests);
        f.expectOrdinary(await f.disk());
      }),
    );
  }

  test(
    'ASB290-reconcile original account issuer repairs failed commit before explicit fixed-token retry and rejects another prepared issuer',
    () => f.withHttp(() async {
      await f.initializeConfirmed();
      final otherAuth = f.newAuth();
      final other = f.newConsumer(otherAuth);
      await otherAuth
          .loadFromStorage(refreshServerConfig: false)
          .timeout(_wait);
      await other.prepareOAuthScope().timeout(_wait);
      expect(other.isOAuthReady, isTrue);
      final otherLease = otherAuth.captureOAuthScopeLease();
      expect(otherLease.workspace.rawRecord, f.lease.workspace.rawRecord);
      expect(otherLease.workspace, isNot(same(f.lease.workspace)));
      final session = f.auth.captureSessionLease();
      f.store.failAccountsPhase = 1;
      await f.reject(
        f.connect(f.consumer, code: 'synthetic-signed290-second-code'),
        _rejected,
      );
      await AccountPreferenceWrites.drain().timeout(_wait);
      final diagnostic = OAuthCalendarStorage.failure!;
      expect(diagnostic, isA<OAuthStorageIndeterminate>());
      expect(f.store.failAccountsPhase, 0);
      final preimage = f.store.transactionPreimage!;
      final pending = OAuthOwnedPendingAuthorization.parse(
        preimage[_pendingKey]! as String,
        scope: f.lease.workspace.record,
      )!;
      expect(pending.phase, OAuthPendingPhase.received);
      final returned = pending.receivedSource!;
      expect(returned.account['accessToken'], 'synthetic-signed290-access-2');
      expect(returned.account['refreshToken'], 'synthetic-signed290-refresh-2');
      final uncertain = await f.disk();
      expect(uncertain[_accounts], f.store.issuedAccounts);
      final writes = f.store.mutations.toList();
      final requests = f.oauthRequests.toList();
      final originalSession = f.auth.sessionGeneration;
      final recovery = f.auth.captureOAuthReconciliationLease();
      expect(recovery.recovery.workspace, same(f.lease.workspace));
      expect(f.auth.isOAuthReconciliationLeaseCurrent(recovery), isTrue);
      expect(f.auth.isOAuthScopeLeaseRetainable(f.lease), isTrue);
      expect(f.auth.isOAuthScopeLeaseCurrent(f.lease), isFalse);
      for (var i = 0; i < 3; i++) {
        expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      }
      await f.reject(other.reconcileOAuthStorage(), _rejected);
      expect(other.oauthAccounts, isEmpty);
      expect(other.oauthLocalCommitReceipts, isEmpty);
      await f.reject(f.auth.restoreOAuthScope(), _rejected);
      await f.reject(
        f.auth.loadFromStorage(refreshServerConfig: false),
        _rejected,
      );
      expect(f.auth.sessionGeneration, originalSession);
      expect(f.auth.isSessionLeaseCurrent(session), isTrue);
      expect(f.auth.isOAuthReconciliationLeaseCurrent(recovery), isTrue);
      expect(OAuthCalendarStorage.failure, same(diagnostic));
      expect(await f.disk(), uncertain);
      expect(f.store.mutations, writes);
      expect(f.oauthRequests, requests);
      await f.consumer.reconcileOAuthStorage().timeout(_wait);
      expect(OAuthCalendarStorage.failure, isNull);
      expect(await f.disk(), preimage);
      expect(f.auth.isOAuthScopeLeaseCurrent(f.lease), isTrue);
      expect(f.auth.isOAuthReconciliationLeaseCurrent(recovery), isFalse);
      final receipt = f.consumer.oauthLocalCommitReceipts.single;
      expect(receipt.handle, pending.receiptHandle);
      expect(receipt.isRefresh, isFalse);
      expect(f.sources(await f.disk()), hasLength(1));
      final account = await f.consumer
          .retryOAuthLocalCommit(receipt)
          .timeout(_wait);
      final accepted = await f.disk();
      expect(account.id, returned.account['id']);
      expect(account.accessToken, returned.account['accessToken']);
      expect(account.refreshToken, returned.account['refreshToken']);
      expect(
        account.expiresAt.toIso8601String(),
        returned.account['expiresAt'],
      );
      expect(
        f
            .sources(accepted)
            .singleWhere((s) => s.account['id'] == account.id)
            .encode(),
        returned.encode(),
      );
      expect(accepted.containsKey(_pendingKey), isFalse);
      expect(accepted.containsKey(f.cacheKey(account.id)), isFalse);
      expect(
        accepted[f.cacheKey(f.confirmedAccount!.id)],
        preimage[f.cacheKey(f.confirmedAccount!.id)],
      );
      expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      expect(f.oauthRequests, requests);
      expect(f.auth.isSessionLeaseCurrent(session), isTrue);
      f.expectOrdinary(accepted);
    }),
  );

  for (final hydrate in [false, true]) {
    final action = hydrate ? 'hydrate' : 'restore';
    test(
      'ASB290-held-$action queued account Auth request preserves held-write issuer for public reconciliation',
      () => f.withHttp(() => f.heldAuthRequest(hydrate: hydrate)),
    );
  }

  test(
    'ASB290-profile-failure same-owner server snapshot rejects existing diagnostic without replacing issuer evidence',
    () => f.withHttp(() async {
      await f.initializeConfirmed();
      final confirmed = await f.disk();
      final originalState = f.auth.state;
      final originalClient = f.auth.client;
      final session = f.auth.captureSessionLease();
      final generation = f.auth.sessionGeneration;
      f.store.failAccountsPhase = 1;
      await f.reject(
        f.consumer.updateOAuthAccount(
          f.confirmedAccount!.copyWith(
            displayName: 'Signed290 failed rename before profile',
          ),
        ),
        _rejected,
      );
      await AccountPreferenceWrites.drain().timeout(_wait);
      final diagnostic = OAuthCalendarStorage.failure!;
      expect(diagnostic, isA<OAuthStorageIndeterminate>());
      final recovery = f.auth.captureOAuthReconciliationLease();
      expect(recovery.recovery.workspace, same(f.lease.workspace));
      final uncertain = await f.disk();
      final writes = f.store.mutations.toList();
      final requests = f.oauthRequests.toList();
      var notifications = 0;
      var callbacks = 0;
      f.auth.addListener(() => notifications++);
      f.auth.onAccountPayloadChanged = (_) async {
        callbacks++;
      };
      f.auth.onAccountProfileChanged = (_) async {
        callbacks++;
      };
      await f.reject(
        f.profileSnapshot('Rejected during diagnostic'),
        same(diagnostic),
      );
      expect(f.auth.state, same(originalState));
      expect(f.auth.client, same(originalClient));
      expect(f.auth.sessionGeneration, generation);
      expect(f.auth.isSessionLeaseCurrent(session), isTrue);
      expect(f.auth.isAccountTransitionInProgress, isFalse);
      expect(f.auth.isLocalAccountDataBlocked, isFalse);
      expect(f.auth.isOAuthScopeLeaseRetainable(f.lease), isTrue);
      expect(f.auth.isOAuthReconciliationLeaseCurrent(recovery), isTrue);
      expect(OAuthCalendarStorage.failure, same(diagnostic));
      expect(await f.disk(), uncertain);
      expect(f.store.mutations, writes);
      expect(f.oauthRequests, requests);
      expect(notifications, 0);
      expect(callbacks, 0);
      await f.consumer.reconcileOAuthStorage().timeout(_wait);
      expect(await f.disk(), confirmed);
      expect(OAuthCalendarStorage.failure, isNull);
      expect(f.auth.state, same(originalState));
      expect(f.auth.isSessionLeaseCurrent(session), isTrue);
      expect(f.auth.isOAuthScopeLeaseCurrent(f.lease), isTrue);
      expect(f.auth.isOAuthReconciliationLeaseCurrent(recovery), isFalse);
      expect(f.oauthRequests, requests);
    }),
  );

  test(
    'ASB290-profile-held same-owner server snapshot waits for issued local write and preserves original recovery authority',
    () => f.withHttp(() => f.heldProfileSnapshot()),
  );

  test(
    'ASB290-profile-success same-owner server snapshot preserves OAuth bytes and issues a current replacement lease',
    () => f.withHttp(() async {
      await f.initializeConfirmed();
      final before = await f.disk();
      final originalState = f.auth.state;
      final originalClient = f.auth.client;
      final session = f.auth.captureSessionLease();
      final generation = f.auth.sessionGeneration;
      final requests = f.oauthRequests.toList();
      final writes = f.store.mutations.length;
      var payloadCallbacks = 0;
      var profileCallbacks = 0;
      String? callbackScopeRaw;
      var callbackReadCompleted = false;
      f.auth.onAccountPayloadChanged = (_) async {
        payloadCallbacks++;
        callbackScopeRaw = f.auth.captureOAuthScopeLease().workspace.rawRecord;
      };
      f.auth.onAccountProfileChanged = (_) async {
        profileCallbacks++;
        // A genuine consumer read here must complete: callbacks execute after
        // profile persistence releases the OAuth lane and publishes new evidence.
        await f.consumer.loadFromStorage().timeout(_wait);
        callbackReadCompleted = true;
      };
      await f.profileSnapshot('Accepted account profile').timeout(_wait);
      final accepted = await f.disk();
      final nextLease = f.auth.captureOAuthScopeLease();
      expect(f.auth.state, isNot(same(originalState)));
      expect(f.auth.state.userId, _account);
      expect(f.auth.state.displayName, 'Accepted account profile');
      expect(f.auth.state.bio, 'Signed290 profile snapshot');
      expect(f.auth.state.token, originalState.token);
      expect(accepted['auth_state'], jsonEncode(f.auth.state.toJson()));
      expect(accepted['auth_state'], isNot(before['auth_state']));
      expect(accepted[_accountOwner], before[_accountOwner]);
      expect(f.oauthData(accepted), f.oauthData(before));
      expect(
        f.store.mutations
            .skip(writes)
            .where(
              (m) =>
                  m == 'clear' ||
                  OAuthCalendarStorage.isOAuthScopeKey(
                    m.substring(m.indexOf(':') + 1),
                  ),
            ),
        isEmpty,
      );
      expect(nextLease.workspace.rawRecord, f.lease.workspace.rawRecord);
      expect(nextLease.workspace, isNot(same(f.lease.workspace)));
      expect(f.auth.isOAuthScopeLeaseCurrent(nextLease), isTrue);
      expect(f.auth.isOAuthScopeLeaseRetainable(nextLease), isTrue);
      expect(f.auth.isOAuthScopeLeaseCurrent(f.lease), isFalse);
      expect(f.auth.isOAuthScopeLeaseRetainable(f.lease), isFalse);
      expect(f.auth.client, same(originalClient));
      expect(f.auth.sessionGeneration, generation);
      expect(f.auth.isSessionLeaseCurrent(session), isTrue);
      expect(f.auth.isAccountTransitionInProgress, isFalse);
      expect(f.auth.isLocalAccountDataBlocked, isFalse);
      expect(f.consumer.isOAuthReady, isTrue);
      expect(
        f.consumer.oauthAccounts.single.toJson(),
        f.confirmedAccount!.toJson(),
      );
      expect(f.consumer.allEvents().map((e) => e.title), [_eventTitle]);
      expect(payloadCallbacks, 1);
      expect(profileCallbacks, 1);
      expect(callbackScopeRaw, f.lease.workspace.rawRecord);
      expect(callbackReadCompleted, isTrue);
      expect(f.oauthRequests, requests);
      f.expectOrdinary(accepted);
    }),
  );

  test(
    'ASB290-profile-reset reset during held auth-state ACK rejects stale profile until explicit scope restore',
    () => f.withHttp(() async {
      await f.initializeConfirmed();
      final before = await f.disk();
      final session = f.auth.captureSessionLease();
      final generation = f.auth.sessionGeneration;
      final reset = OAuthCalendarStorage.resetRevision;
      final requests = f.oauthRequests.toList();
      final api = f.apiRequests.toList();
      final writes = f.store.mutations.toList();
      var payloadCallbacks = 0;
      var profileCallbacks = 0;
      f.auth.onAccountPayloadChanged = (_) async {
        payloadCallbacks++;
      };
      f.auth.onAccountProfileChanged = (_) async {
        profileCallbacks++;
      };
      final hold = f.store.holdNextAuthStateWrite();
      final updating = f.observe<void>(
        f.profileSnapshot('Profile issued before reset'),
      );
      await hold.started.future.timeout(_wait);
      // Real auth_state persistence is held after writing the issued bytes;
      // no accounts fault or synthetic diagnostic participates in this case.
      final heldDisk = await f.disk();
      expect(heldDisk['auth_state'], hold.value);
      expect(heldDisk['auth_state'], isNot(before['auth_state']));
      expect(
        jsonDecode(hold.value!)['display_name'],
        'Profile issued before reset',
      );
      expect(f.oauthData(heldDisk), f.oauthData(before));
      expect(f.store.mutations, [...writes, 'set:auth_state']);
      expect(payloadCallbacks, 0);
      expect(profileCallbacks, 0);
      expect(OAuthCalendarStorage.failure, isNull);
      f.consumer.resetLocalState();
      expect(OAuthCalendarStorage.resetRevision, reset + 1);
      expect(f.auth.isOAuthScopeLeaseCurrent(f.lease), isFalse);
      expect(f.auth.captureOAuthScopeLease, throwsA(_rejected));
      expect(f.consumer.oauthAccounts, isEmpty);
      expect(f.consumer.allEvents(), isEmpty);
      hold.release.complete();
      expect(
        (await updating.timeout(_wait)).error,
        isA<AccountPreferenceWriteCanceled>(),
      );
      await AccountPreferenceWrites.drain().timeout(_wait);
      expect(payloadCallbacks, 0);
      expect(profileCallbacks, 0);
      expect(OAuthCalendarStorage.failure, isNull);
      expect(await f.disk(), heldDisk);
      expect(f.store.mutations, [...writes, 'set:auth_state']);
      expect(f.oauthRequests, requests);
      expect(f.apiRequests, api);
      expect(f.auth.sessionGeneration, generation);
      expect(f.auth.isSessionLeaseCurrent(session), isTrue);
      expect(f.auth.isOAuthScopeLeaseCurrent(f.lease), isFalse);
      expect(f.auth.isOAuthScopeLeaseRetainable(f.lease), isFalse);
      expect(f.auth.captureOAuthScopeLease, throwsA(_rejected));
      expect(f.consumer.isOAuthReady, isFalse);
      expect(f.consumer.oauthAccounts, isEmpty);
      expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      // Missing private readback evidence cannot issue a scope, even through
      // direct restore. A new explicit hydration must first verify real storage.
      await f.reject(
        f.auth.restoreOAuthScope(),
        isA<OAuthScopedWorkspaceUnavailable>(),
      );
      expect(f.auth.captureOAuthScopeLease, throwsA(_rejected));
      expect(f.auth.isSessionLeaseCurrent(session), isTrue);
      expect(await f.disk(), heldDisk);
      expect(f.store.mutations, [...writes, 'set:auth_state']);
      expect(payloadCallbacks, 0);
      expect(profileCallbacks, 0);
      await f.auth.loadFromStorage(refreshServerConfig: false).timeout(_wait);
      final hydratedSession = f.auth.captureSessionLease();
      expect(f.auth.state.userId, _account);
      expect(f.auth.state.token, 'synthetic-auth290-$_account');
      expect(f.auth.state.displayName, 'Profile issued before reset');
      expect(f.auth.isSessionLeaseCurrent(session), isFalse);
      expect(f.auth.isSessionLeaseCurrent(hydratedSession), isTrue);
      // This separate user action may restore verified durable scope evidence;
      // the obsolete profile operation itself must never do so after reset.
      await f.auth.restoreOAuthScope().timeout(_wait);
      final restoredLease = f.auth.captureOAuthScopeLease();
      expect(restoredLease.workspace.rawRecord, f.lease.workspace.rawRecord);
      expect(restoredLease.workspace, isNot(same(f.lease.workspace)));
      expect(f.auth.isOAuthScopeLeaseCurrent(restoredLease), isTrue);
      expect(f.auth.isOAuthScopeLeaseCurrent(f.lease), isFalse);
      expect(f.auth.isSessionLeaseCurrent(hydratedSession), isTrue);
      await f.consumer.loadFromStorage().timeout(_wait);
      expect(
        f.consumer.oauthAccounts.single.toJson(),
        f.confirmedAccount!.toJson(),
      );
      expect(f.consumer.allEvents().map((e) => e.title), [_eventTitle]);
      expect(await f.disk(), heldDisk);
      expect(f.store.mutations, [...writes, 'set:auth_state']);
      expect(f.oauthRequests, requests);
      expect(f.apiRequests, api);
      expect(f.oauthData(await f.disk()), f.oauthData(before));
      expect(payloadCallbacks, 0);
      expect(profileCallbacks, 0);
      f.expectOrdinary(await f.disk());
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

class _BackingStore extends InMemorySharedPreferencesStore {
  _BackingStore() : super.withData({});
  final mutations = <String>[];
  final ownerWrites = <String>[];
  bool? ownerFault;
  String? issuedOwner;
  int failAccountsPhase = 0;
  String? issuedAccounts;
  Map<String, Object>? transactionPreimage;
  _Hold? failedAccountsHold;
  _Hold? authStateHold;
  final holds = <_Hold>[];
  _Hold holdNextAuthStateWrite() {
    final h = _Hold();
    authStateHold = h;
    holds.add(h);
    return h;
  }

  _Hold holdNextFailedAccountsWrite() {
    final h = _Hold();
    failAccountsPhase = 1;
    failedAccountsHold = h;
    holds.add(h);
    return h;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    mutations.add('set:${logical(key)}');
    if (logical(key) == 'auth_state' && authStateHold != null) {
      final h = authStateHold!;
      authStateHold = null;
      final saved = await super.setValue(type, key, value);
      expect(saved, isTrue);
      h.value = value as String;
      h.started.complete();
      await h.release.future;
      return saved;
    }
    if (logical(key) == _scopeKey) {
      final raw = value as String;
      ownerWrites.add(raw);
      if (ownerFault != null) {
        final persist = ownerFault!;
        ownerFault = null;
        issuedOwner = raw;
        if (persist) expect(await super.setValue(type, key, value), isTrue);
        return false;
      }
    }
    if (logical(key) == _accounts && failAccountsPhase == 1) {
      transactionPreimage = {
        for (final e in (await super.getAll()).entries) logical(e.key): e.value,
      };
      final raw = value as String;
      issuedAccounts = raw;
      expect(await super.setValue(type, key, value), isTrue);
      failAccountsPhase = 2;
      final h = failedAccountsHold;
      failedAccountsHold = null;
      if (h != null) {
        h.value = raw;
        h.started.complete();
        await h.release.future;
      }
      return false;
    }
    if (logical(key) == _accounts && failAccountsPhase == 2) {
      failAccountsPhase = 0;
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
  Future<void> inject(String key, Object? value) async {
    if (value == null) {
      expect(await super.remove('flutter.$key'), isTrue);
    } else {
      final type = switch (value) {
        String() => 'String',
        int() => 'Int',
        _ => throw ArgumentError('Unsupported fixture value'),
      };
      expect(await super.setValue(type, 'flutter.$key', value), isTrue);
    }
  }

  static String logical(String key) =>
      key.startsWith('flutter.') ? key.substring(8) : key;
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
  final restoreAtTeardown = <String, Object?>{};
  final verifier = OAuthCalendarClient.generateCodeVerifier();
  final state = OAuthCalendarClient.generateCodeVerifier();
  late AuthProvider auth;
  late CalendarSyncProvider consumer;
  late AuthOAuthScopeLease lease;
  OAuthCalendarAccount? confirmedAccount;
  int tokenCalls = 0;

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
        expect(body['username'], _account);
        expect(body['password'], 'synthetic-signed290-password');
        return _json({
          'token': 'synthetic-auth290-$_account',
          'user': {'id': _account, 'username': _account},
        });
      }
      if (request.url.path == '/api/config') {
        apiRequests.add('config');
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
        throw StateError('Unexpected signed290 request');
      }
      if (phase == 'token') {
        final form = Uri.splitQueryString(request.body);
        expect(form['grant_type'], 'authorization_code');
        expect(form['client_id'], 'synthetic-signed290-client');
        expect(form['code_verifier'], verifier);
        expect(form['code'], isNotEmpty);
        expect(form['redirect_uri'], 'duoyi://oauth/calendar');
        tokenCalls++;
        return _json({
          'access_token': 'synthetic-signed290-access-$tokenCalls',
          'refresh_token': 'synthetic-signed290-refresh-$tokenCalls',
          'expires_in': 7200,
          'token_type': 'Bearer',
          'scope': 'https://www.googleapis.com/auth/calendar.readonly',
        });
      }
      expect(
        request.headers['Authorization'],
        'Bearer synthetic-signed290-access-1',
      );
      return _json({
        'items': [
          {
            'id': 'signed290-event',
            'summary': _eventTitle,
            'start': {'dateTime': '2026-11-11T09:00:00Z'},
            'end': {'dateTime': '2026-11-11T10:00:00Z'},
          },
        ],
      });
    });
    clients.add(client);
    return client;
  }

  AuthProvider newAuth({AuthState initialState = const AuthState()}) {
    final issuer = AuthProvider(
      initialState: initialState,
      client: ApiClient(
        baseUrl: 'https://signed290.example',
        httpClient: client(),
      ),
    );
    auths.add(issuer);
    return issuer;
  }

  CalendarSyncProvider newConsumer(AuthProvider issuer) {
    final provider = CalendarSyncProvider(authProvider: issuer);
    consumers.add(provider);
    return provider;
  }

  Future<AuthProvider> login() async {
    final issuer = newAuth();
    await issuer
        .login(username: _account, password: 'synthetic-signed290-password')
        .timeout(_wait);
    await AccountPreferenceWrites.drain().timeout(_wait);
    await Future<void>.delayed(Duration.zero);
    expect(issuer.state.userId, _account);
    expect(issuer.state.isLoggedIn, isTrue);
    expect(issuer.isAccountTransitionInProgress, isFalse);
    expect(issuer.isLocalAccountDataBlocked, isFalse);
    expect((await disk())[_accountOwner], 'id:$_account');
    return issuer;
  }

  Future<void> initializeConfirmed() async {
    auth = await login();
    consumer = newConsumer(auth);
    await consumer.prepareOAuthScope(initialize: true).timeout(_wait);
    lease = auth.captureOAuthScopeLease();
    expect(lease.workspace.record.scopeKind, 'account');
    expect(lease.workspace.record.matchesAccountOwner('id:$_account'), isTrue);
    confirmedAccount = await connect(consumer).timeout(_wait);
    expect(consumer.allEvents().map((e) => e.title), [_eventTitle]);
    expect(oauthRequests, ['token', 'events']);
  }

  Future<void> savePending(CalendarSyncProvider provider) =>
      provider.savePendingOAuthAuthorization(
        provider: OAuthCalendarProvider.google,
        displayName: 'Signed290 calendar',
        clientId: 'synthetic-signed290-client',
        clientSecret: '',
        redirectUri: 'duoyi://oauth/calendar',
        calendarId: 'primary',
        codeVerifier: verifier,
        state: state,
      );
  Future<OAuthCalendarAccount> connect(
    CalendarSyncProvider provider, {
    String code = 'synthetic-signed290-first-code',
  }) async {
    await savePending(provider);
    return dispatch(provider, code: code);
  }

  Future<OAuthCalendarAccount> dispatch(
    CalendarSyncProvider provider, {
    String code = 'synthetic-signed290-first-code',
  }) => provider.addOAuthAccountFromCode(
    provider: OAuthCalendarProvider.google,
    displayName: 'Signed290 calendar',
    clientId: 'synthetic-signed290-client',
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
  OAuthScopedOwnerRecord accountScope(Map<String, Object> raw) {
    final scope = OAuthScopedOwnerRecord.parse(raw[_scopeKey])!;
    expect(scope.scopeKind, 'account');
    expect(scope.matchesAccountOwner('id:$_account'), isTrue);
    expect(raw[_accountOwner], 'id:$_account');
    return scope;
  }

  List<OAuthOwnedSourceRecord> sources(Map<String, Object> raw) =>
      OAuthOwnedSourceRecord.parseList(
        raw[_accounts]! as String,
        scope: accountScope(raw),
      )!;
  String cacheKey(String id) => '${OAuthCalendarStorage.eventsKeyPrefix}$id';
  Future<Map<String, Object>> disk() async => {
    for (final e in (await store.backing()).entries)
      _BackingStore.logical(e.key): e.value,
  };
  Map<String, Object> oauthData(Map<String, Object> raw) => {
    for (final e in raw.entries.where(
      (e) => OAuthCalendarStorage.isOAuthScopeKey(e.key),
    ))
      e.key: e.value,
  };
  Future<void> profileSnapshot(String displayName) =>
      auth.applyServerAccountSnapshot(
        {
          'user': {
            'id': _account,
            'username': _account,
            'display_name': displayName,
            'bio': 'Signed290 profile snapshot',
          },
        },
        reason: 'signed290_profile_snapshot',
        expectedToken: auth.state.token,
        expectedUserId: _account,
      );
  void expectOrdinary(Map<String, Object> raw) {
    for (final e in _ordinary.entries.where((e) => e.key != 'auth_state')) {
      expect(raw[e.key], e.value, reason: e.key);
    }
  }

  void disposeAuth(AuthProvider issuer) {
    issuer.dispose();
    auths.remove(issuer);
  }

  void disposeConsumer(CalendarSyncProvider provider) {
    provider.dispose();
    consumers.remove(provider);
  }

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
  Future<void> heldAuthRequest({required bool hydrate}) async {
    await initializeConfirmed();
    final confirmed = await disk();
    final session = auth.captureSessionLease();
    final originalSession = auth.sessionGeneration;
    final hold = store.holdNextFailedAccountsWrite();
    final writing = observe<void>(
      consumer.updateOAuthAccount(
        confirmedAccount!.copyWith(
          displayName: 'Signed290 held account rename',
        ),
      ),
    );
    await hold.started.future.timeout(_wait);
    expect(OAuthCalendarStorage.failure, isNull);
    expect(store.failAccountsPhase, 2);
    expect(store.transactionPreimage, confirmed);
    final heldDisk = await disk();
    expect(heldDisk[_accounts], hold.value);
    expect(heldDisk[_accounts], isNot(confirmed[_accounts]));
    final writes = store.mutations.toList();
    final requests = oauthRequests.toList();
    var settled = false;
    final queued = observe<void>(
      hydrate
          ? auth.loadFromStorage(refreshServerConfig: false)
          : auth.restoreOAuthScope(),
    );
    queued.then<void>((_) {
      settled = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(settled, isFalse);
    expect(OAuthCalendarStorage.failure, isNull);
    expect(auth.sessionGeneration, originalSession);
    expect(auth.isSessionLeaseCurrent(session), isTrue);
    expect(auth.isAccountTransitionInProgress, isFalse);
    expect(auth.isLocalAccountDataBlocked, isFalse);
    expect(auth.isOAuthScopeLeaseCurrent(lease), isTrue);
    expect(auth.captureOAuthScopeLease().workspace, same(lease.workspace));
    expect(await disk(), heldDisk);
    expect(store.mutations, writes);
    expect(oauthRequests, requests);
    hold.release.complete();
    final writeResult = await writing.timeout(_wait);
    final diagnostic = OAuthCalendarStorage.failure!;
    expect(diagnostic, isA<OAuthStorageIndeterminate>());
    expect(writeResult.error, same(diagnostic));
    final recovery = auth.captureOAuthReconciliationLease();
    expect(recovery.recovery.workspace, same(lease.workspace));
    expect((await queued.timeout(_wait)).error, same(diagnostic));
    await AccountPreferenceWrites.drain().timeout(_wait);
    expect(store.failAccountsPhase, 0);
    expect(OAuthCalendarStorage.failure, same(diagnostic));
    expect(auth.sessionGeneration, originalSession);
    expect(auth.isSessionLeaseCurrent(session), isTrue);
    expect(auth.isAccountTransitionInProgress, isFalse);
    expect(auth.isLocalAccountDataBlocked, isFalse);
    expect(auth.isOAuthScopeLeaseCurrent(lease), isFalse);
    expect(auth.isOAuthScopeLeaseRetainable(lease), isTrue);
    expect(auth.isOAuthReconciliationLeaseCurrent(recovery), isTrue);
    expect(await disk(), heldDisk);
    expect(store.mutations, [...writes, 'set:$_accounts']);
    expect(oauthRequests, requests);
    expect(consumer.oauthAccounts, isEmpty);
    expect(consumer.allEvents(), isEmpty);
    await consumer.reconcileOAuthStorage().timeout(_wait);
    expect(OAuthCalendarStorage.failure, isNull);
    expect(await disk(), confirmed);
    expect(auth.sessionGeneration, originalSession);
    expect(auth.isSessionLeaseCurrent(session), isTrue);
    expect(auth.isOAuthScopeLeaseCurrent(lease), isTrue);
    expect(auth.isOAuthReconciliationLeaseCurrent(recovery), isFalse);
    expect(consumer.oauthLocalCommitReceipts, isEmpty);
    expect(oauthRequests, requests);
    expectOrdinary(await disk());
  }

  Future<void> heldProfileSnapshot() async {
    await initializeConfirmed();
    final confirmed = await disk();
    final originalState = auth.state;
    final originalClient = auth.client;
    final session = auth.captureSessionLease();
    final generation = auth.sessionGeneration;
    final hold = store.holdNextFailedAccountsWrite();
    final writing = observe<void>(
      consumer.updateOAuthAccount(
        confirmedAccount!.copyWith(
          displayName: 'Signed290 held rename before profile',
        ),
      ),
    );
    await hold.started.future.timeout(_wait);
    expect(OAuthCalendarStorage.failure, isNull);
    expect(store.transactionPreimage, confirmed);
    expect(store.failAccountsPhase, 2);
    final heldDisk = await disk();
    expect(heldDisk[_accounts], hold.value);
    expect(heldDisk[_accounts], isNot(confirmed[_accounts]));
    final writes = store.mutations.toList();
    final requests = oauthRequests.toList();
    var notifications = 0;
    var callbacks = 0;
    auth.addListener(() => notifications++);
    auth.onAccountPayloadChanged = (_) async {
      callbacks++;
    };
    auth.onAccountProfileChanged = (_) async {
      callbacks++;
    };
    var settled = false;
    final queued = observe<void>(
      profileSnapshot('Rejected behind held local write'),
    );
    queued.then<void>((_) {
      settled = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(settled, isFalse);
    expect(OAuthCalendarStorage.failure, isNull);
    expect(auth.state, same(originalState));
    expect(auth.client, same(originalClient));
    expect(auth.sessionGeneration, generation);
    expect(auth.isSessionLeaseCurrent(session), isTrue);
    expect(auth.isOAuthScopeLeaseCurrent(lease), isTrue);
    expect(auth.captureOAuthScopeLease().workspace, same(lease.workspace));
    expect(auth.isAccountTransitionInProgress, isFalse);
    expect(auth.isLocalAccountDataBlocked, isFalse);
    expect(await disk(), heldDisk);
    expect(store.mutations, writes);
    expect(oauthRequests, requests);
    expect(notifications, 0);
    expect(callbacks, 0);
    hold.release.complete();
    final writeResult = await writing.timeout(_wait);
    final diagnostic = OAuthCalendarStorage.failure!;
    expect(diagnostic, isA<OAuthStorageIndeterminate>());
    expect(writeResult.error, same(diagnostic));
    final recovery = auth.captureOAuthReconciliationLease();
    expect(recovery.recovery.workspace, same(lease.workspace));
    expect((await queued.timeout(_wait)).error, same(diagnostic));
    await AccountPreferenceWrites.drain().timeout(_wait);
    expect(store.failAccountsPhase, 0);
    expect(auth.state, same(originalState));
    expect(auth.client, same(originalClient));
    expect(auth.sessionGeneration, generation);
    expect(auth.isSessionLeaseCurrent(session), isTrue);
    expect(auth.isOAuthScopeLeaseRetainable(lease), isTrue);
    expect(auth.isOAuthReconciliationLeaseCurrent(recovery), isTrue);
    expect(OAuthCalendarStorage.failure, same(diagnostic));
    expect(await disk(), heldDisk);
    expect(store.mutations, [...writes, 'set:$_accounts']);
    expect(oauthRequests, requests);
    expect(notifications, 0);
    expect(callbacks, 0);
    await consumer.reconcileOAuthStorage().timeout(_wait);
    expect(await disk(), confirmed);
    expect(OAuthCalendarStorage.failure, isNull);
    expect(auth.state, same(originalState));
    expect(auth.isSessionLeaseCurrent(session), isTrue);
    expect(auth.isOAuthScopeLeaseCurrent(lease), isTrue);
    expect(auth.isOAuthReconciliationLeaseCurrent(recovery), isFalse);
    expect(oauthRequests, requests);
    expectOrdinary(await disk());
  }

  Future<void> close() async {
    store.ownerFault = null;
    store.failAccountsPhase = 0;
    store.failedAccountsHold = null;
    store.authStateHold = null;
    for (final h in store.holds) {
      if (!h.release.isCompleted) h.release.complete();
    }
    try {
      await Future.wait(pending).timeout(_wait);
      await AccountPreferenceWrites.drain().timeout(_wait);
      // Restore only hostile synthetic input after assertions/futures settle;
      // the actual positive recovery is exclusively public consumer reconcile.
      for (final e in restoreAtTeardown.entries) {
        await store.inject(e.key, e.value);
      }
      await prefs.reload();
      for (final provider in consumers) {
        provider.dispose();
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
