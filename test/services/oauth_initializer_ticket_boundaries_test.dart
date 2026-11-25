// Prepared360 against the explicit345 API proposal. No active product reads,
// compiler, formatter or execution; main owns final API alignment and acceptance.

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
const _scopeKey = OAuthCalendarStorage.scopeOwnerKey;
const _accountsKey = OAuthCalendarStorage.accountsKey;
const _pendingKey = OAuthCalendarStorage.pendingAuthorizationKey;
const _account = 'initializer360-account-a';
const _ordinary = <String, Object>{
  'auth_state': '{ "token" : null }',
  'todos': '[ { "id" : "ticket360", "title" : "keep original todo" } ]',
  'duoyi_notes': '[ { "body" : "keep original note" } ]',
  'duoyi_ics_subscriptions_v1': '[]',
  'initializer360_device_setting': 360,
};

Matcher get _unavailable => anyOf(
  isA<ApiException>(),
  isA<AccountPreferenceWriteCanceled>(),
  isA<OAuthScopedWorkspaceUnavailable>(),
  isA<OAuthScopeInitializationPending>(),
  isA<OAuthAccountRetirementPending>(),
  isA<AccountLocalDataCleanupBlockedException>(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() async => f = await _Fixture.create());
  tearDown(() async => f.close());

  test(
    'OIT360-01 held signed-in false ACK returns original ticket then success consumes it',
    () => f.withHttp(() async {
      await f.enter(signedIn: true);
      final session = f.auth.captureSessionLease();
      final before = await f.disk();
      final hold = f.store.holdScopeAck();
      f.store.scopeFault = _ScopeFault.afterFalse;
      final initializing = f.observe(
        f.consumer.initializeOAuthScopeWithTicket(
          isCurrent: f.caller.isCurrent,
        ),
      );
      await hold.started.future.timeout(_wait);
      final issued = hold.value!;
      expect(await f.disk(), {...before, _scopeKey: issued});
      expect(f.consumer.isOAuthReady, isFalse);
      expect(f.auth.isSessionLeaseCurrent(session), isTrue);
      hold.release.complete();
      final result = await initializing.timeout(_wait);
      expect(result.error, isNull);
      expect(result.value, isA<AuthOAuthScopeInitializationTicket>());
      final ticket = result.value!;
      expect(
        f.auth.captureOAuthScopeInitializationTicket(
          isCurrent: f.caller.isCurrent,
        ),
        same(ticket),
      );
      expect(
        f.consumer.captureOAuthScopeInitializationTicket(
          isCurrent: f.caller.isCurrent,
        ),
        same(ticket),
      );
      expect(OAuthCalendarStorage.failure, isNull);
      expect(f.auth.captureOAuthScopeLease, throwsA(_unavailable));
      final failed = await f.disk();
      final writes = f.store.mutations.toList();
      await f.reject(
        f.consumer.prepareOAuthScope(isCurrent: f.caller.isCurrent),
        _unavailable,
      );
      await f.reject(
        f.consumer.prepareOAuthScope(
          initialize: true,
          isCurrent: f.caller.isCurrent,
        ),
        _unavailable,
      );
      await f.reject(f.save(), _unavailable);
      expect(await f.disk(), failed);
      expect(f.store.mutations, writes);
      // Rejected ordinary preparation must not destroy the original ticket.
      expect(
        f.auth.captureOAuthScopeInitializationTicket(
          isCurrent: f.caller.isCurrent,
        ),
        same(ticket),
      );
      await f.confirm(ticket).timeout(_wait);
      final lease = f.auth.captureOAuthScopeLease();
      expect(lease.workspace.rawRecord, issued);
      expect(lease.workspace.record.scopeKind, 'account');
      expect(
        lease.workspace.record.matchesAccountOwner('id:$_account'),
        isTrue,
      );
      expect(f.auth.isOAuthScopeLeaseCurrent(lease), isTrue);
      expect(f.auth.isSessionLeaseCurrent(session), isTrue);
      expect(f.consumer.isOAuthReady, isTrue);
      expect(
        f.consumer.captureOAuthScopeInitializationTicket(
          isCurrent: f.caller.isCurrent,
        ),
        isNull,
      );
      expect(f.store.scopeWrites, [issued, issued]);
      expect(await f.disk(), {...before, _scopeKey: issued});
      final settled = await f.disk();
      final settledWrites = f.store.mutations.toList();
      await f.reject(f.confirm(ticket), isA<OAuthScopedWorkspaceUnavailable>());
      expect(await f.disk(), settled);
      expect(f.store.mutations, settledWrites);
      expect(f.oauthRequests, isEmpty);
      f.expectOrdinary(settled);
      // A real public cleanup and independent same-account initialization B
      // must not make a consumed A usable again. This includes reset/issuer
      // rejection; the pre-cleanup assertion above isolates consumed A.
      await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
      await f.enter(signedIn: true);
      final ticketB = await f.pendingTicket(_ScopeFault.afterFalse);
      final issuedB = f.store.scopeWrites.last;
      expect(ticketB, isNot(same(ticket)));
      expect(issuedB, isNot(issued));
      final diskB = await f.disk();
      final writesB = f.store.mutations.toList();
      await f.reject(f.confirm(ticket), isA<OAuthScopedWorkspaceUnavailable>());
      expect(await f.disk(), diskB);
      expect(f.store.mutations, writesB);
      await f.confirm(ticketB).timeout(_wait);
      expect(f.auth.captureOAuthScopeLease().workspace.rawRecord, issuedB);
      final readyDisk = await f.disk();
      final readyWrites = f.store.mutations.toList();
      // The nullable initializer result must distinguish already-confirmed
      // empty scope from a surviving pending ticket, without rewriting it.
      expect(
        await f.consumer
            .initializeOAuthScopeWithTicket(isCurrent: f.caller.isCurrent)
            .timeout(_wait),
        isNull,
      );
      expect(f.consumer.isOAuthReady, isTrue);
      expect(await f.disk(), readyDisk);
      expect(f.store.mutations, readyWrites);
      expect(f.oauthRequests, isEmpty);
    }),
  );

  for (final fault in [_ScopeFault.beforeThrow, _ScopeFault.readbackThrow]) {
    final phase = fault == _ScopeFault.beforeThrow
        ? 'before-write'
        : 'readback';
    test(
      'OIT360-02-$phase actual guest failure preserves same candidate for explicit recovery',
      () => f.withHttp(() async {
        await f.enter(signedIn: false);
        final guest = f.auth.captureGuestWorkspaceLease();
        final before = await f.disk();
        final ticket = await f.pendingTicket(fault, directAuth: true);
        final issued = f.store.scopeWrites.single;
        final scope = OAuthScopedOwnerRecord.parse(issued)!;
        expect(scope.scopeKind, 'guest');
        expect(
          await f.disk(),
          fault == _ScopeFault.beforeThrow
              ? before
              : {...before, _scopeKey: issued},
        );
        expect(f.consumer.isOAuthReady, isFalse);
        expect(f.auth.isGuestWorkspaceLeaseCurrent(guest), isTrue);
        expect(
          f.consumer.captureOAuthScopeInitializationTicket(
            isCurrent: f.caller.isCurrent,
          ),
          same(ticket),
        );
        f.store.scopeFault = _ScopeFault.afterFalse;
        await f.reject(
          f.confirm(ticket),
          isA<OAuthScopeInitializationPending>(),
        );
        expect(f.consumer.isOAuthReady, isFalse);
        expect(
          f.auth.captureOAuthScopeInitializationTicket(
            isCurrent: f.caller.isCurrent,
          ),
          same(ticket),
        );
        await f.confirm(ticket).timeout(_wait);
        expect(f.store.scopeWrites, [issued, issued, issued]);
        expect(await f.disk(), {...before, _scopeKey: issued});
        expect(f.auth.captureOAuthScopeLease().workspace.rawRecord, issued);
        expect(f.auth.isGuestWorkspaceLeaseCurrent(guest), isTrue);
        expect(f.consumer.isOAuthReady, isTrue);
        expect(f.oauthRequests, isEmpty);
        f.expectOrdinary(await f.disk());
      }),
    );
  }

  test(
    'OIT360-03 another genuinely hydrated signed-in Auth cannot use original issuer ticket',
    () => f.withHttp(() async {
      await f.enter(signedIn: true);
      // Hydrate the other real Auth before A creates its pending candidate;
      // do not claim initialState or rejected hydration supplies authority.
      final otherAuth = f.newAuth();
      await otherAuth
          .loadFromStorage(refreshServerConfig: false)
          .timeout(_wait);
      final other = f.newConsumer(otherAuth);
      final otherSession = otherAuth.captureSessionLease();
      expect(otherAuth.state.userId, _account);
      expect(otherAuth.state.token, f.auth.state.token);
      final ticket = await f.pendingTicket(_ScopeFault.afterFalse);
      final before = await f.disk();
      final writes = f.store.mutations.toList();
      final requests = f.oauthRequests.toList();
      expect(otherAuth.isSessionLeaseCurrent(otherSession), isTrue);
      expect(
        otherAuth.captureOAuthScopeInitializationTicket(
          isCurrent: f.caller.isCurrent,
        ),
        isNull,
      );
      await f.reject(
        other.prepareOAuthScope(
          confirm: true,
          expectedInitialization: ticket,
          requireExpectedInitialization: true,
          isCurrent: f.caller.isCurrent,
        ),
        isA<OAuthScopedWorkspaceUnavailable>(),
      );
      expect(await f.disk(), before);
      expect(f.store.mutations, writes);
      expect(f.oauthRequests, requests);
      expect(other.isOAuthReady, isFalse);
      expect(
        f.consumer.captureOAuthScopeInitializationTicket(
          isCurrent: f.caller.isCurrent,
        ),
        same(ticket),
      );
      await f.confirm(ticket).timeout(_wait);
      expect(
        f.auth.captureOAuthScopeLease().workspace.rawRecord,
        before[_scopeKey],
      );
      expect(f.consumer.isOAuthReady, isTrue);
      expect(other.isOAuthReady, isFalse);
      expect(f.oauthRequests, requests);
    }),
  );

  for (final conflict in ['marker', 'sidecar']) {
    test(
      'OIT360-04-$conflict replacement during real confirm reload cannot be adopted or cleared',
      () => f.withHttp(() async {
        await f.enter(signedIn: true);
        final ticket = await f.pendingTicket(_ScopeFault.afterFalse);
        final issued = f.store.scopeWrites.single;
        final hold = f.store.holdReload();
        final confirming = f.observe(f.confirm(ticket));
        await hold.started.future.timeout(_wait);
        final key = conflict == 'marker'
            ? _scopeKey
            : 'duoyi_oauth_calendar_unrecognized360';
        f.restoreAtTeardown[key] = conflict == 'marker' ? issued : null;
        if (conflict == 'marker') {
          // Corrupt only hostile disk input, not authority. Same account owner
          // and schema, different canonical incarnation: never candidate A.
          final fields = jsonDecode(issued) as Map<String, dynamic>;
          final replacement = List.filled(32, 'A').join();
          fields['oauthIncarnation'] = fields['oauthIncarnation'] == replacement
              ? List.filled(32, 'B').join()
              : replacement;
          final hostile = jsonEncode(fields);
          expect(OAuthScopedOwnerRecord.parse(hostile), isNotNull);
          expect(hostile, isNot(issued));
          await f.store.inject(key, hostile);
        } else {
          await f.store.inject(key, '{ "unknown" : "preserve360" }');
        }
        final hostileDisk = await f.disk();
        final writes = f.store.mutations.toList();
        hold.release.complete();
        expect((await confirming.timeout(_wait)).error, _unavailable);
        expect(await f.disk(), hostileDisk);
        expect(f.store.mutations, writes);
        expect(f.store.scopeWrites, [issued]);
        expect(f.consumer.isOAuthReady, isFalse);
        expect(f.auth.captureOAuthScopeLease, throwsA(_unavailable));
        expect(f.oauthRequests, isEmpty);
        f.expectOrdinary(hostileDisk);
      }),
    );
  }

  for (final boundary in ['before', 'reload', 'ack']) {
    test(
      'OIT360-05-$boundary original caller cancellation cannot publish or continue confirmation',
      () => f.withHttp(() async {
        await f.enter(signedIn: true);
        final ticket = await f.pendingTicket(_ScopeFault.beforeThrow);
        final issued = f.store.scopeWrites.single;
        final before = await f.disk();
        final canceling = _Caller();
        if (boundary == 'before') {
          canceling.cancel();
          final writes = f.store.mutations.toList();
          await f.reject(
            f.confirm(ticket, caller: canceling),
            isA<AccountPreferenceWriteCanceled>(),
          );
          expect(await f.disk(), before);
          expect(f.store.mutations, writes);
        } else {
          final hold = boundary == 'reload'
              ? f.store.holdReload()
              : f.store.holdScopeAck();
          final confirming = f.observe(f.confirm(ticket, caller: canceling));
          await hold.started.future.timeout(_wait);
          final waitingDisk = await f.disk();
          expect(
            waitingDisk,
            boundary == 'reload' ? before : {...before, _scopeKey: issued},
          );
          if (boundary == 'ack') {
            expect(hold.value, issued);
          }
          canceling.cancel();
          final writes = f.store.mutations.toList();
          hold.release.complete();
          expect(
            (await confirming.timeout(_wait)).error,
            isA<AccountPreferenceWriteCanceled>(),
          );
          expect(await f.disk(), waitingDisk);
          expect(f.store.mutations, writes);
        }
        expect(f.consumer.isOAuthReady, isFalse);
        expect(f.oauthRequests, isEmpty);
        // New caller, same original token/issuer/session, a separate explicit
        // recovery. This never re-captures authority for the canceled action.
        expect(
          f.consumer.captureOAuthScopeInitializationTicket(
            isCurrent: f.caller.isCurrent,
          ),
          same(ticket),
        );
        await f.confirm(ticket).timeout(_wait);
        expect(f.consumer.isOAuthReady, isTrue);
        expect(f.auth.captureOAuthScopeLease().workspace.rawRecord, issued);
        expect(f.store.scopeWrites.every((raw) => raw == issued), isTrue);
        expect(
          f.store.scopeWrites,
          boundary == 'ack' ? [issued, issued, issued] : [issued, issued],
        );
        expect(await f.disk(), {...before, _scopeKey: issued});
        expect(f.oauthRequests, isEmpty);
      }),
    );
  }

  test(
    'OIT360-06 closed normal readiness separates initializer confirmation from actual transaction recovery',
    () => f.withHttp(() async {
      await f.enter(signedIn: true);
      final ticket = await f.pendingTicket(_ScopeFault.afterFalse);
      final before = await f.disk();
      final writes = f.store.mutations.toList();
      await f.reject(
        f.consumer.prepareOAuthScope(
          confirm: true,
          requireExpectedInitialization: true,
          isCurrent: f.caller.isCurrent,
        ),
        isA<ArgumentError>(),
      );
      await f.reject(
        f.consumer.reconcileOAuthStorage(isCurrent: f.caller.isCurrent),
        _unavailable,
      );
      expect(await f.disk(), before);
      expect(f.store.mutations, writes);
      expect(f.consumer.isOAuthReady, isFalse);
      expect(
        f.consumer.captureOAuthScopeInitializationTicket(
          isCurrent: f.caller.isCurrent,
        ),
        same(ticket),
      );
      await f.confirm(ticket).timeout(_wait);
      final lease = f.auth.captureOAuthScopeLease();
      final original = await f.connect().timeout(_wait);
      expect(f.oauthRequests, ['token', 'events']);
      final confirmedDisk = await f.disk();
      f.store.failAccountsPhase = 1;
      await f.reject(
        f.connect(),
        anyOf(
          isA<OAuthStorageIndeterminate>(),
          isA<OAuthLocalCommitRequired>(),
          isA<AccountPreferenceWriteCanceled>(),
        ),
      );
      await AccountPreferenceWrites.drain().timeout(_wait);
      final diagnostic = OAuthCalendarStorage.failure!;
      final preimage = f.store.transactionPreimage!;
      final received = OAuthOwnedPendingAuthorization.parse(
        preimage[_pendingKey]! as String,
        scope: lease.workspace.record,
      )!;
      expect(received.phase, OAuthPendingPhase.received);
      expect(
        received.receivedSource!.account['accessToken'],
        'synthetic-initializer360-access-2',
      );
      expect(f.consumer.isOAuthReady, isFalse);
      expect(f.auth.isOAuthScopeLeaseCurrent(lease), isFalse);
      expect(f.auth.isOAuthScopeLeaseRetainable(lease), isTrue);
      final recovery = f.auth.captureOAuthReconciliationLease();
      expect(f.auth.isOAuthReconciliationLeaseCurrent(recovery), isTrue);
      expect(
        f.consumer.captureOAuthScopeInitializationTicket(
          isCurrent: f.caller.isCurrent,
        ),
        isNull,
      );
      final uncertain = await f.disk();
      final uncertainWrites = f.store.mutations.toList();
      final requests = f.oauthRequests.toList();
      await f.reject(
        f.confirm(ticket),
        anyOf(isA<OAuthScopedWorkspaceUnavailable>(), same(diagnostic)),
      );
      expect(OAuthCalendarStorage.failure, same(diagnostic));
      expect(await f.disk(), uncertain);
      expect(f.store.mutations, uncertainWrites);
      // Exact original recovery works while the normal-ready getter is false;
      // it restores the received preimage, without installing returned tokens.
      await f.consumer
          .reconcileOAuthStorage(isCurrent: f.caller.isCurrent)
          .timeout(_wait);
      expect(OAuthCalendarStorage.failure, isNull);
      expect(f.auth.isOAuthReconciliationSettled(recovery), isTrue);
      expect(await f.disk(), preimage);
      expect((await f.disk())[_accountsKey], confirmedDisk[_accountsKey]);
      expect(f.oauthRequests, requests);
      final receipt = f.consumer.oauthLocalCommitReceipts.single;
      expect(receipt.handle, received.receiptHandle);
      final restored = await f.consumer
          .retryOAuthLocalCommit(receipt, isCurrent: f.caller.isCurrent)
          .timeout(_wait);
      expect(restored.id, received.sourceAccountId);
      expect(restored.id, isNot(original.id));
      expect(restored.accessToken, 'synthetic-initializer360-access-2');
      expect(restored.refreshToken, 'synthetic-initializer360-refresh-2');
      final accepted = await f.disk();
      expect(accepted.containsKey(_pendingKey), isFalse);
      expect(
        accepted['${OAuthCalendarStorage.eventsKeyPrefix}${original.id}'],
        confirmedDisk['${OAuthCalendarStorage.eventsKeyPrefix}${original.id}'],
      );
      expect(f.consumer.oauthLocalCommitReceipts, isEmpty);
      expect(f.oauthRequests, requests);
      expect(f.consumer.isOAuthReady, isTrue);
      f.expectOrdinary(accepted);
    }),
  );

  test(
    'OIT360-07 pending listener supersedes initializer result while original ticket remains recoverable',
    () => f.withHttp(() async {
      await f.enter(signedIn: true);
      final session = f.auth.captureSessionLease();
      final sessionGeneration = f.auth.sessionGeneration;
      final epoch = OAuthCalendarStorage.epoch;
      final reset = OAuthCalendarStorage.resetRevision;
      final writesGeneration = AccountPreferenceWrites.generation;
      final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
      final before = await f.disk();
      final writes = f.store.mutations.toList();
      final requests = f.oauthRequests.toList();
      AuthOAuthScopeInitializationTicket? ticketInNotice;
      Future<_Result<void>>? readonlyPreparing;
      var listenerCalls = 0;
      void onPendingInitialization() {
        listenerCalls++;
        // One shot: the fresh confirm's later notice must not supersede it.
        f.auth.removeListener(onPendingInitialization);
        ticketInNotice = f.auth.captureOAuthScopeInitializationTicket(
          isCurrent: f.caller.isCurrent,
        );
        // Attach the error observer in this same synchronous listener turn.
        // Assertions belong outside notifyListeners, which catches callbacks.
        readonlyPreparing = f.observe<void>(
          f.consumer.prepareOAuthScope(isCurrent: f.caller.isCurrent),
        );
      }

      f.auth.addListener(onPendingInitialization);
      try {
        f.store.scopeFault = _ScopeFault.afterFalse;
        final initializing = f.observe<AuthOAuthScopeInitializationTicket?>(
          f.auth.initializeOAuthScopeWithTicket(isCurrent: f.caller.isCurrent),
        );
        final result = await initializing.timeout(_wait);
        expect(listenerCalls, 1);
        expect(readonlyPreparing, isNotNull);
        expect(ticketInNotice, isA<AuthOAuthScopeInitializationTicket>());
        // The listener increments the original request before initialize's
        // finally returns. A pending token is not a current result anymore.
        expect(result.error, isA<AccountPreferenceWriteCanceled>());
        expect(result.value, isNull);
        expect(
          (await readonlyPreparing!.timeout(_wait)).error,
          isA<OAuthScopeInitializationPending>(),
        );
        await AccountPreferenceWrites.drain().timeout(_wait);
        final issued = f.store.scopeWrites.single;
        expect(await f.disk(), {...before, _scopeKey: issued});
        expect(f.store.mutations, [...writes, 'set:$_scopeKey']);
        expect(f.oauthRequests, requests);
        expect(f.consumer.isOAuthReady, isFalse);
        expect(f.auth.captureOAuthScopeLease, throwsA(_unavailable));
        expect(f.auth.isSessionLeaseCurrent(session), isTrue);
        expect(f.auth.sessionGeneration, sessionGeneration);
        expect(f.auth.isAccountTransitionInProgress, isFalse);
        expect(f.auth.isLocalAccountDataBlocked, isFalse);
        expect(OAuthCalendarStorage.failure, isNull);
        expect(OAuthCalendarStorage.epoch, epoch);
        expect(OAuthCalendarStorage.resetRevision, reset);
        expect(AccountPreferenceWrites.generation, writesGeneration);
        expect(
          AccountLocalDataCleaner.accountDataGeneration,
          accountGeneration,
        );
        // This is a new explicit entry after the canceled initializer and its
        // rejecting peer finish; it does not return a token to the old action.
        final freshTicket = f.consumer.captureOAuthScopeInitializationTicket(
          isCurrent: f.caller.isCurrent,
        );
        expect(freshTicket, same(ticketInNotice));
        await f.confirm(freshTicket!).timeout(_wait);
        expect(f.store.scopeWrites, [issued, issued]);
        expect(f.store.mutations, [
          ...writes,
          'set:$_scopeKey',
          'set:$_scopeKey',
        ]);
        expect(await f.disk(), {...before, _scopeKey: issued});
        expect(f.auth.captureOAuthScopeLease().workspace.rawRecord, issued);
        expect(f.auth.isSessionLeaseCurrent(session), isTrue);
        expect(f.consumer.isOAuthReady, isTrue);
        expect(listenerCalls, 1);
        expect(f.oauthRequests, requests);
        f.expectOrdinary(await f.disk());
      } finally {
        f.auth.removeListener(onPendingInitialization);
      }
    }),
  );

  test(
    'OIT360-08 pending outcome is current on return then microtask supersedes it without revival',
    () => f.withHttp(() async {
      await f.enter(signedIn: true);
      final session = f.auth.captureSessionLease();
      final generation = f.auth.sessionGeneration;
      final reset = OAuthCalendarStorage.resetRevision;
      final before = await f.disk();
      final writes = f.store.mutations.toList();
      final requests = f.oauthRequests.toList();
      final trace = <String>[];
      var guardCalls = 0;
      bool? outcomeCurrentAtReturn;
      bool originalInitCurrent() {
        final current = f.caller.isCurrent();
        trace.add('guard.${++guardCalls}:$current');
        return current;
      }

      final microtaskRan = Completer<void>();
      final microtaskObserved = f.observe<void>(microtaskRan.future);
      AuthOAuthScopeInitializationTicket? noticeTicket;
      Future<_Result<void>>? readonlyPreparing;
      var notices = 0;
      void onPendingNotice() {
        trace.add('notice.begin');
        notices++;
        f.auth.removeListener(onPendingNotice);
        noticeTicket = f.auth.captureOAuthScopeInitializationTicket(
          isCurrent: f.caller.isCurrent,
        );
        trace.add('microtask.schedule');
        scheduleMicrotask(() {
          trace.add('microtask.begin');
          // Actual378 showed Future completion precedes this microtask. This
          // new request revokes the returned outcome's original authority.
          trace.add('peer.call');
          readonlyPreparing = f.observe<void>(
            f.consumer.prepareOAuthScope(isCurrent: f.caller.isCurrent),
          );
          trace.add('peer.observer.attached');
          trace.add('microtask.end');
          microtaskRan.complete();
        });
        trace.add('notice.end');
      }

      f.auth.addListener(onPendingNotice);
      try {
        f.store.scopeFault = _ScopeFault.afterFalse;
        trace.add('method.call');
        final methodFuture = f.auth.initializeOAuthScopeWithOutcome(
          isCurrent: originalInitCurrent,
        );
        trace.add('method.future.return');
        trace.add('result.observer.attach');
        // Observe the actual method Future directly; record only completion
        // kind. The independent observer never rethrows or changes its result.
        final diagnosticObserver = methodFuture.then<void>(
          (outcome) {
            outcomeCurrentAtReturn = outcome.isCurrent;
            trace.add('result.observer.success');
          },
          onError: (Object _, StackTrace _) {
            trace.add('result.observer.error');
          },
        );
        f.pending.add(diagnosticObserver);
        final initializing = f.observe<AuthOAuthScopeInitializationOutcome>(
          methodFuture,
        );
        trace.add('result.observer.attached');
        final result = await initializing.timeout(_wait);
        trace.add('result.await.resumed');
        expect((await microtaskObserved.timeout(_wait)).error, isNull);
        expect(notices, 1);
        expect(noticeTicket, isA<AuthOAuthScopeInitializationTicket>());
        expect(readonlyPreparing, isNotNull);
        expect(result.error, isNull);
        expect(outcomeCurrentAtReturn, isTrue);
        expect(
          trace.indexOf('result.observer.success'),
          lessThan(trace.indexOf('microtask.begin')),
        );
        final outcome = result.value!;
        expect(outcome.ticket, same(noticeTicket));
        expect(outcome.isCurrent, isFalse);
        expect(
          (await readonlyPreparing!.timeout(_wait)).error,
          isA<OAuthScopeInitializationPending>(),
        );
        await AccountPreferenceWrites.drain().timeout(_wait);
        expect(outcome.isCurrent, isFalse);
        final issued = f.store.scopeWrites.single;
        expect(await f.disk(), {...before, _scopeKey: issued});
        expect(f.store.mutations, [...writes, 'set:$_scopeKey']);
        expect(f.consumer.isOAuthReady, isFalse);
        expect(f.auth.isSessionLeaseCurrent(session), isTrue);
        expect(f.auth.sessionGeneration, generation);
        expect(OAuthCalendarStorage.resetRevision, reset);
        expect(OAuthCalendarStorage.failure, isNull);
        expect(f.oauthRequests, requests);
        // Fresh entry uses the original candidate, while the prior returned
        // outcome stays revoked even after that candidate is confirmed.
        final ticket = f.consumer.captureOAuthScopeInitializationTicket(
          isCurrent: f.caller.isCurrent,
        );
        expect(ticket, same(noticeTicket));
        expect(ticket, same(outcome.ticket));
        await f.confirm(ticket!).timeout(_wait);
        expect(f.store.scopeWrites, [issued, issued]);
        expect(await f.disk(), {...before, _scopeKey: issued});
        expect(f.store.mutations, [
          ...writes,
          'set:$_scopeKey',
          'set:$_scopeKey',
        ]);
        expect(f.auth.captureOAuthScopeLease().workspace.rawRecord, issued);
        expect(f.consumer.isOAuthReady, isTrue);
        expect(outcome.isCurrent, isFalse);
        expect(f.auth.isSessionLeaseCurrent(session), isTrue);
        expect(notices, 1);
        expect(f.oauthRequests, requests);
        f.expectOrdinary(await f.disk());
      } finally {
        // Intentional OAuth boundary trace consumed from the test reporter.
        // ignore: avoid_print
        print('OIT360-08-trace ${trace.join(' > ')}');
        f.auth.removeListener(onPendingNotice);
      }
    }),
  );

  test(
    'OIT360-09 successful outcome is current on return then microtask reset revokes it permanently',
    () => f.withHttp(() async {
      await f.enter(signedIn: true);
      final session = f.auth.captureSessionLease();
      final generation = f.auth.sessionGeneration;
      final reset = OAuthCalendarStorage.resetRevision;
      final before = await f.disk();
      final writes = f.store.mutations.toList();
      final requests = f.oauthRequests.toList();
      final trace = <String>[];
      var guardCalls = 0;
      bool? outcomeCurrentAtReturn;
      bool originalInitCurrent() {
        final current = f.caller.isCurrent();
        trace.add('guard.${++guardCalls}:$current');
        return current;
      }

      final microtaskRan = Completer<void>();
      final microtaskObserved = f.observe<void>(microtaskRan.future);
      AuthOAuthScopeLease? publishedLease;
      AuthOAuthScopeInitializationTicket? noticeTicket;
      var wasCurrentInNotice = false;
      var notices = 0;
      void onSuccessfulNotice() {
        trace.add('notice.begin');
        notices++;
        f.auth.removeListener(onSuccessfulNotice);
        publishedLease = f.auth.captureOAuthScopeLease();
        wasCurrentInNotice = f.auth.isOAuthScopeLeaseCurrent(publishedLease!);
        noticeTicket = f.auth.captureOAuthScopeInitializationTicket(
          isCurrent: f.caller.isCurrent,
        );
        trace.add('microtask.schedule');
        scheduleMicrotask(() {
          trace.add('microtask.begin');
          trace.add('reset.call');
          OAuthCalendarStorage.invalidateReset();
          trace.add('reset.return');
          trace.add('microtask.end');
          microtaskRan.complete();
        });
        trace.add('notice.end');
      }

      f.auth.addListener(onSuccessfulNotice);
      try {
        // No failed ACK or fabricated ticket: real initialization succeeds in
        // its lane, then reset invalidates that exact published workspace.
        trace.add('method.call');
        final methodFuture = f.auth.initializeOAuthScopeWithOutcome(
          isCurrent: originalInitCurrent,
        );
        trace.add('method.future.return');
        trace.add('result.observer.attach');
        // Observe the actual method Future directly; record only completion
        // kind. The independent observer never rethrows or changes its result.
        final diagnosticObserver = methodFuture.then<void>(
          (outcome) {
            outcomeCurrentAtReturn = outcome.isCurrent;
            trace.add('result.observer.success');
          },
          onError: (Object _, StackTrace _) {
            trace.add('result.observer.error');
          },
        );
        f.pending.add(diagnosticObserver);
        final initializing = f.observe<AuthOAuthScopeInitializationOutcome>(
          methodFuture,
        );
        trace.add('result.observer.attached');
        final result = await initializing.timeout(_wait);
        trace.add('result.await.resumed');
        expect((await microtaskObserved.timeout(_wait)).error, isNull);
        expect(notices, 1);
        expect(publishedLease, isNotNull);
        expect(wasCurrentInNotice, isTrue);
        expect(noticeTicket, isNull);
        expect(result.error, isNull);
        expect(outcomeCurrentAtReturn, isTrue);
        expect(
          trace.indexOf('result.observer.success'),
          lessThan(trace.indexOf('microtask.begin')),
        );
        final outcome = result.value!;
        expect(outcome.ticket, isNull);
        expect(outcome.isCurrent, isFalse);
        await AccountPreferenceWrites.drain().timeout(_wait);
        final issued = f.store.scopeWrites.single;
        expect(publishedLease!.workspace.rawRecord, issued);
        expect(await f.disk(), {...before, _scopeKey: issued});
        expect(f.store.mutations, [...writes, 'set:$_scopeKey']);
        expect(OAuthCalendarStorage.resetRevision, reset + 1);
        expect(OAuthCalendarStorage.failure, isNull);
        expect(f.auth.isSessionLeaseCurrent(session), isTrue);
        expect(f.auth.sessionGeneration, generation);
        expect(f.auth.isOAuthScopeLeaseCurrent(publishedLease!), isFalse);
        expect(f.auth.isOAuthScopeLeaseRetainable(publishedLease!), isFalse);
        expect(f.consumer.isOAuthReady, isFalse);
        expect(f.auth.captureOAuthScopeLease, throwsA(_unavailable));
        expect(
          f.consumer.captureOAuthScopeInitializationTicket(
            isCurrent: f.caller.isCurrent,
          ),
          isNull,
        );
        expect(f.oauthRequests, requests);
        // invalidateReset alone preserves verified Auth/store evidence. This
        // separate readonly action may revalidate the durable scope; it does
        // not reinitialize, confirm a nonexistent ticket, or reuse the lease.
        await f.consumer
            .prepareOAuthScope(isCurrent: f.caller.isCurrent)
            .timeout(_wait);
        final restored = f.auth.captureOAuthScopeLease();
        expect(restored.workspace.rawRecord, issued);
        expect(restored.workspace, isNot(same(publishedLease!.workspace)));
        expect(f.auth.isOAuthScopeLeaseCurrent(restored), isTrue);
        expect(f.auth.isOAuthScopeLeaseCurrent(publishedLease!), isFalse);
        expect(f.auth.isSessionLeaseCurrent(session), isTrue);
        expect(f.auth.sessionGeneration, generation);
        expect(f.consumer.isOAuthReady, isTrue);
        expect(outcome.isCurrent, isFalse);
        expect(await f.disk(), {...before, _scopeKey: issued});
        expect(f.store.mutations, [...writes, 'set:$_scopeKey']);
        expect(f.store.scopeWrites, [issued]);
        expect(f.oauthRequests, requests);
        expect(notices, 1);
        f.expectOrdinary(await f.disk());
      } finally {
        // Intentional OAuth boundary trace consumed from the test reporter.
        // ignore: avoid_print
        print('OIT360-09-trace ${trace.join(' > ')}');
        f.auth.removeListener(onSuccessfulNotice);
      }
    }),
  );

  test(
    'OIT360-10 synchronous successful confirm listener supersedes original request without rewriting scope',
    () => f.withHttp(() async {
      await f.enter(signedIn: true);
      final ticket = await f.pendingTicket(_ScopeFault.afterFalse);
      final issued = f.store.scopeWrites.single;
      final before = await f.disk();
      final writes = f.store.mutations.toList();
      final requests = f.oauthRequests.toList();
      final session = f.auth.captureSessionLease();
      final generation = f.auth.sessionGeneration;
      final epoch = OAuthCalendarStorage.epoch;
      final reset = OAuthCalendarStorage.resetRevision;
      final writesGeneration = AccountPreferenceWrites.generation;
      final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
      AuthOAuthScopeLease? confirmedInNotice;
      AuthOAuthScopeInitializationTicket? noticeTicket;
      Future<_Result<void>>? readonlyPreparing;
      var wasCurrentInNotice = false;
      var notices = 0;
      void onConfirmedNotice() {
        notices++;
        f.auth.removeListener(onConfirmedNotice);
        confirmedInNotice = f.auth.captureOAuthScopeLease();
        wasCurrentInNotice = f.auth.isOAuthScopeLeaseCurrent(
          confirmedInNotice!,
        );
        noticeTicket = f.auth.captureOAuthScopeInitializationTicket(
          isCurrent: f.caller.isCurrent,
        );
        // Invoke in this notification turn. A ready consumer's readonly fast
        // path would not replace the actual Auth request being tested here.
        readonlyPreparing = f.observe<void>(
          f.auth.restoreOAuthScope(isCurrent: f.caller.isCurrent),
        );
      }

      f.auth.addListener(onConfirmedNotice);
      try {
        final confirming = f.observe<void>(f.confirm(ticket));
        final result = await confirming.timeout(_wait);
        expect(notices, 1);
        expect(confirmedInNotice, isNotNull);
        expect(wasCurrentInNotice, isTrue);
        expect(noticeTicket, isNull);
        expect(readonlyPreparing, isNotNull);
        expect(result.error, isA<AccountPreferenceWriteCanceled>());
        expect((await readonlyPreparing!.timeout(_wait)).error, isNull);
        await AccountPreferenceWrites.drain().timeout(_wait);
        expect(confirmedInNotice!.workspace.rawRecord, issued);
        final freshLease = f.auth.captureOAuthScopeLease();
        expect(freshLease.workspace.rawRecord, issued);
        expect(freshLease.workspace, isNot(same(confirmedInNotice!.workspace)));
        expect(f.auth.isOAuthScopeLeaseCurrent(freshLease), isTrue);
        expect(f.auth.isOAuthScopeLeaseCurrent(confirmedInNotice!), isFalse);
        expect(f.auth.isOAuthScopeLeaseRetainable(confirmedInNotice!), isFalse);
        expect(f.consumer.isOAuthReady, isTrue);
        expect(f.auth.isSessionLeaseCurrent(session), isTrue);
        expect(f.auth.sessionGeneration, generation);
        expect(OAuthCalendarStorage.epoch, epoch);
        expect(OAuthCalendarStorage.resetRevision, reset);
        expect(AccountPreferenceWrites.generation, writesGeneration);
        expect(
          AccountLocalDataCleaner.accountDataGeneration,
          accountGeneration,
        );
        expect(OAuthCalendarStorage.failure, isNull);
        expect(f.store.scopeWrites, [issued, issued]);
        expect(f.store.mutations, [...writes, 'set:$_scopeKey']);
        expect(await f.disk(), before);
        expect(f.oauthRequests, requests);
        expect(
          f.consumer.captureOAuthScopeInitializationTicket(
            isCurrent: f.caller.isCurrent,
          ),
          isNull,
        );
        await f.reject(
          f.confirm(ticket),
          isA<OAuthScopedWorkspaceUnavailable>(),
        );
        expect(await f.disk(), before);
        expect(f.store.mutations, [...writes, 'set:$_scopeKey']);
        expect(f.oauthRequests, requests);
        expect(notices, 1);
        f.expectOrdinary(await f.disk());
      } finally {
        f.auth.removeListener(onConfirmedNotice);
      }
    }),
  );

  for (final boundary in ['caller', 'request']) {
    test(
      'OIT360-11-$boundary synchronous repeated false ACK confirm listener supersedes pending result',
      () => f.withHttp(() async {
        await f.enter(signedIn: true);
        final ticket = await f.pendingTicket(_ScopeFault.afterFalse);
        final issued = f.store.scopeWrites.single;
        final before = await f.disk();
        final writes = f.store.mutations.toList();
        final requests = f.oauthRequests.toList();
        final session = f.auth.captureSessionLease();
        final generation = f.auth.sessionGeneration;
        final epoch = OAuthCalendarStorage.epoch;
        final reset = OAuthCalendarStorage.resetRevision;
        final writesGeneration = AccountPreferenceWrites.generation;
        final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
        final originalCaller = _Caller();
        AuthOAuthScopeInitializationTicket? noticeTicket;
        Future<_Result<void>>? readonlyPreparing;
        var notices = 0;
        void onRepeatedPendingNotice() {
          notices++;
          f.auth.removeListener(onRepeatedPendingNotice);
          noticeTicket = f.auth.captureOAuthScopeInitializationTicket(
            isCurrent: f.caller.isCurrent,
          );
          // Supersede before finally returns, not after Future completion.
          if (boundary == 'caller') {
            originalCaller.cancel();
          } else {
            readonlyPreparing = f.observe<void>(
              f.auth.restoreOAuthScope(isCurrent: f.caller.isCurrent),
            );
          }
        }

        f.auth.addListener(onRepeatedPendingNotice);
        try {
          f.store.scopeFault = _ScopeFault.afterFalse;
          final confirming = f.observe<void>(
            f.confirm(ticket, caller: originalCaller),
          );
          final result = await confirming.timeout(_wait);
          expect(notices, 1);
          expect(noticeTicket, same(ticket));
          expect(result.error, isA<AccountPreferenceWriteCanceled>());
          if (boundary == 'request') {
            expect(readonlyPreparing, isNotNull);
            expect(
              (await readonlyPreparing!.timeout(_wait)).error,
              isA<OAuthScopeInitializationPending>(),
            );
          } else {
            expect(originalCaller.isCurrent(), isFalse);
            expect(readonlyPreparing, isNull);
          }
          await AccountPreferenceWrites.drain().timeout(_wait);
          expect(f.store.scopeWrites, [issued, issued]);
          expect(f.store.mutations, [...writes, 'set:$_scopeKey']);
          expect(await f.disk(), before);
          expect(f.oauthRequests, requests);
          expect(f.consumer.isOAuthReady, isFalse);
          expect(f.auth.captureOAuthScopeLease, throwsA(_unavailable));
          expect(f.auth.isSessionLeaseCurrent(session), isTrue);
          expect(f.auth.sessionGeneration, generation);
          expect(f.auth.isAccountTransitionInProgress, isFalse);
          expect(f.auth.isLocalAccountDataBlocked, isFalse);
          expect(OAuthCalendarStorage.epoch, epoch);
          expect(OAuthCalendarStorage.resetRevision, reset);
          expect(AccountPreferenceWrites.generation, writesGeneration);
          expect(
            AccountLocalDataCleaner.accountDataGeneration,
            accountGeneration,
          );
          expect(OAuthCalendarStorage.failure, isNull);
          // New explicit caller keeps the original candidate/token. The old
          // canceled operation never acquires this recovery's authority.
          final freshTicket = f.consumer.captureOAuthScopeInitializationTicket(
            isCurrent: f.caller.isCurrent,
          );
          expect(freshTicket, same(ticket));
          await f.confirm(freshTicket!).timeout(_wait);
          expect(f.store.scopeWrites, [issued, issued, issued]);
          expect(f.store.mutations, [
            ...writes,
            'set:$_scopeKey',
            'set:$_scopeKey',
          ]);
          expect(await f.disk(), before);
          expect(f.auth.captureOAuthScopeLease().workspace.rawRecord, issued);
          expect(f.auth.isSessionLeaseCurrent(session), isTrue);
          expect(f.consumer.isOAuthReady, isTrue);
          expect(
            f.consumer.captureOAuthScopeInitializationTicket(
              isCurrent: f.caller.isCurrent,
            ),
            isNull,
          );
          expect(f.oauthRequests, requests);
          expect(notices, 1);
          f.expectOrdinary(await f.disk());
        } finally {
          f.auth.removeListener(onRepeatedPendingNotice);
        }
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
  String? value;
}

enum _ScopeFault { beforeThrow, afterFalse, readbackThrow }

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData({});
  final mutations = <String>[];
  final scopeWrites = <String>[];
  final holds = <_Hold>[];
  _ScopeFault? scopeFault;
  _Hold? scopeAck;
  _Hold? reloadHold;
  bool failNextReadback = false;
  int failAccountsPhase = 0;
  Map<String, Object>? transactionPreimage;

  _Hold holdScopeAck() {
    final h = _Hold();
    scopeAck = h;
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
    if (failNextReadback) {
      failNextReadback = false;
      throw StateError('Synthetic360 authoritative readback failure');
    }
    return super.getAllWithParameters(parameters);
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    final logicalKey = logical(key);
    mutations.add('set:$logicalKey');
    if (logicalKey == _scopeKey) {
      final raw = value as String;
      scopeWrites.add(raw);
      final fault = scopeFault;
      scopeFault = null;
      if (fault == _ScopeFault.beforeThrow) {
        throw StateError('Synthetic360 scope write failed before persistence');
      }
      final saved = await super.setValue(type, key, value);
      expect(saved, isTrue);
      if (fault == _ScopeFault.readbackThrow) {
        failNextReadback = true;
      }
      final h = scopeAck;
      scopeAck = null;
      if (h != null) {
        h.value = raw;
        h.started.complete();
        await h.release.future;
      }
      return fault == _ScopeFault.afterFalse ? false : saved;
    }
    if (logicalKey == _accountsKey && failAccountsPhase == 1) {
      transactionPreimage = {
        for (final e in (await super.getAll()).entries) logical(e.key): e.value,
      };
      expect(await super.setValue(type, key, value), isTrue);
      failAccountsPhase = 2;
      return false;
    }
    if (logicalKey == _accountsKey && failAccountsPhase == 2) {
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
        _ => throw ArgumentError('Unsupported360 fixture value'),
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
  final _Store store;
  final SharedPreferences prefs;
  final caller = _Caller();
  final auths = <AuthProvider>[];
  final consumers = <CalendarSyncProvider>[];
  final clients = <http.Client>[];
  final pending = <Future<void>>[];
  final oauthRequests = <String>[];
  final restoreAtTeardown = <String, Object?>{};
  final verifier = OAuthCalendarClient.generateCodeVerifier();
  final state = OAuthCalendarClient.generateCodeVerifier();
  late AuthProvider auth;
  late CalendarSyncProvider consumer;
  int tokenCalls = 0;

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
        expect(body['password'], 'synthetic-initializer360-password');
        return _json({
          'token': 'synthetic-initializer360-auth',
          'user': {'id': _account, 'username': _account},
        });
      }
      if (request.url.path == '/api/config') {
        return _json({});
      }
      if (request.url.host == 'oauth2.googleapis.com' &&
          request.method == 'POST') {
        oauthRequests.add('token');
        final form = Uri.splitQueryString(request.body);
        expect(form['grant_type'], 'authorization_code');
        expect(form['client_id'], 'synthetic-initializer360-client');
        expect(form['code_verifier'], verifier);
        expect(form['redirect_uri'], 'duoyi://oauth/calendar');
        tokenCalls++;
        return _json({
          'access_token': 'synthetic-initializer360-access-$tokenCalls',
          'refresh_token': 'synthetic-initializer360-refresh-$tokenCalls',
          'expires_in': 7200,
          'token_type': 'Bearer',
          'scope': 'https://www.googleapis.com/auth/calendar.readonly',
        });
      }
      if (request.url.host != 'www.googleapis.com' || request.method != 'GET') {
        throw StateError('Unexpected360 HTTP request');
      }
      oauthRequests.add('events');
      expect(
        request.headers['Authorization'],
        'Bearer synthetic-initializer360-access-1',
      );
      return _json({
        'items': [
          {
            'id': 'initializer360-event',
            'summary': 'Initializer360 confirmed event',
            'start': {'dateTime': '2026-11-12T09:00:00Z'},
            'end': {'dateTime': '2026-11-12T10:00:00Z'},
          },
        ],
      });
    });
    clients.add(c);
    return c;
  }

  AuthProvider newAuth() {
    final issuer = AuthProvider(
      client: ApiClient(
        baseUrl: 'https://initializer360.example',
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

  Future<void> enter({required bool signedIn}) async {
    auth = newAuth();
    if (signedIn) {
      await auth
          .login(
            username: _account,
            password: 'synthetic-initializer360-password',
          )
          .timeout(_wait);
      expect(auth.state.userId, _account);
      expect(
        (await disk())[AccountLocalDataCleaner.accountDataOwnerKey],
        'id:$_account',
      );
    } else {
      await auth.loadFromStorage(refreshServerConfig: false).timeout(_wait);
      expect(auth.isGuestWorkspaceReady, isTrue);
      expect(
        (await disk()).containsKey(AccountLocalDataCleaner.accountDataOwnerKey),
        isFalse,
      );
    }
    await AccountPreferenceWrites.drain().timeout(_wait);
    await Future<void>.delayed(Duration.zero);
    consumer = newConsumer(auth);
    expect(consumer.isOAuthReady, isFalse);
    expect(auth.isAccountTransitionInProgress, isFalse);
    expect(auth.isLocalAccountDataBlocked, isFalse);
  }

  Future<AuthOAuthScopeInitializationTicket> pendingTicket(
    _ScopeFault fault, {
    bool directAuth = false,
  }) async {
    store.scopeFault = fault;
    final result = await observe(
      directAuth
          ? auth.initializeOAuthScopeWithTicket(isCurrent: caller.isCurrent)
          : consumer.initializeOAuthScopeWithTicket(
              isCurrent: caller.isCurrent,
            ),
    ).timeout(_wait);
    expect(result.error, isNull);
    expect(result.value, isA<AuthOAuthScopeInitializationTicket>());
    expect(consumer.isOAuthReady, isFalse);
    expect(OAuthCalendarStorage.failure, isNull);
    return result.value!;
  }

  Future<void> confirm(
    AuthOAuthScopeInitializationTicket ticket, {
    _Caller? caller,
  }) => consumer.prepareOAuthScope(
    confirm: true,
    expectedInitialization: ticket,
    requireExpectedInitialization: true,
    isCurrent: (caller ?? this.caller).isCurrent,
  );

  Future<Map<String, String>> save() => consumer.savePendingOAuthAuthorization(
    provider: OAuthCalendarProvider.google,
    displayName: 'Initializer360 calendar',
    clientId: 'synthetic-initializer360-client',
    clientSecret: '',
    redirectUri: 'duoyi://oauth/calendar',
    calendarId: 'primary',
    codeVerifier: verifier,
    state: state,
    requireExpectedAttempt: true,
    isCurrent: caller.isCurrent,
  );

  Future<OAuthCalendarAccount> connect() async {
    final draft = await save();
    return consumer.addOAuthAccountFromCode(
      provider: OAuthCalendarProvider.google,
      displayName: 'Initializer360 calendar',
      clientId: 'synthetic-initializer360-client',
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
          queryParameters: {
            'code': 'synthetic-initializer360-code-${tokenCalls + 1}',
            'state': state,
          },
        ).toString(),
      ),
      isCurrent: caller.isCurrent,
    );
  }

  Future<Map<String, Object>> disk() async => {
    for (final e in (await store.backing()).entries)
      _Store.logical(e.key): e.value,
  };

  void expectOrdinary(Map<String, Object> disk) {
    for (final e in _ordinary.entries.where((e) => e.key != 'auth_state')) {
      expect(disk[e.key], e.value, reason: e.key);
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

  Future<void> reject<T>(Future<T> work, Matcher expected) async =>
      expect((await observe<T>(work).timeout(_wait)).error, expected);

  Future<void> close() async {
    caller.cancel();
    store.scopeFault = null;
    store.failNextReadback = false;
    store.failAccountsPhase = 0;
    store.scopeAck = null;
    store.reloadHold = null;
    for (final h in store.holds) {
      if (!h.release.isCompleted) {
        h.release.complete();
      }
    }
    try {
      await Future.wait(pending).timeout(_wait);
      await AccountPreferenceWrites.drain().timeout(_wait);
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
