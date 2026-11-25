// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/core/oauth_pending_authorization.dart';
import 'package:duoyi/core/oauth_refresh_journal.dart';
import 'package:duoyi/core/oauth_calendar_workspace_codec.dart';
import 'package:duoyi/core/ics_subscription_storage.dart';
import 'package:duoyi/core/oauth_calendar_storage.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _accountsKey = 'duoyi_oauth_calendar_accounts_v1';
const _pendingKey = 'duoyi_oauth_calendar_pending_authorization_v1';
const _cacheKey = 'duoyi_oauth_calendar_events_existing';
const _wait = Duration(seconds: 4);
const _oldTitle = 'Confirmed OAuth calendar event';
const _code = 'synthetic-receipt-single-use-code';
const _codeVerifier =
    'synthetic-code-verifier-0123456789-ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const _newAccess = 'synthetic-returned-access';
const _newRefresh = 'synthetic-returned-refresh';

// Real provider, controlled backing preferences, and injected MockClient.
// These tests intentionally do not override provider methods or inspect private
// candidates. Staged account bytes establish identity/expiry before an ACK;
// explicit gates establish ordering, and watchdogs only bound deadlocks.
// Each first exchange is explicitly prepared through the public pending API.
// Retry and cancellation keep the original attempt; no readiness is fabricated.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;

  setUp(() async {
    f = await _Fixture.create();
  });
  tearDown(() async {
    await f.close();
  });

  for (final effect in _failedWrites) {
    test(
      'connect ${effect.name} receipt retries locally with stable ID and expiry',
      () async {
        final original = await f.seed();
        final originalRows = _rows(f.provider);
        final write = f.store.plan('set', _accountsKey, effect, hold: true);
        await f.savePending();
        final connecting = f.observe(f.connect());
        await write.started.future.timeout(_wait);
        final staged = write.accountRow('New OAuth account', f.scope);

        expect(staged['id'], isNotEmpty);
        expect(staged['expiresAt'], isA<String>());
        expect(
          _rows(f.provider),
          originalRows,
          reason: 'candidate unpublished',
        );
        expect(_titles(f.provider), [_oldTitle]);
        expect(f.feed.count('exchange'), 1);
        expect(f.feed.count('events'), 0);

        write.release.complete();
        final failed = await connecting.timeout(_wait);
        expect(failed.error, isA<OAuthLocalCommitRequired>());
        final error = failed.error! as OAuthLocalCommitRequired;
        final receipt = error.receipt;
        _expectOpaque(receipt, error, refreshing: false);
        _expectReceipt(f.provider, receipt);
        expect(_rows(f.provider), originalRows);
        expect(_titles(f.provider), [_oldTitle]);
        await f.expectRaw(original);

        final requests = f.feed.requests.toList();
        final recovered = await f
            .observe(
              f.provider.retryOAuthLocalCommit(receipt, isCurrent: () => true),
            )
            .timeout(_wait);
        expect(recovered.error, isNull);
        final account = recovered.value!;
        expect(account.id, staged['id']);
        expect(account.expiresAt.toIso8601String(), staged['expiresAt']);
        expect(account.accessToken, _newAccess);
        expect(account.refreshToken, _newRefresh);
        expect(account.lastSyncedAt, isNull);
        expect(
          f.feed.requests,
          requests,
          reason: 'local recovery makes zero HTTP',
        );
        expect(f.feed.replayedCodes, isEmpty);
        expect(f.provider.oauthLocalCommitReceipts, isEmpty);
        expect(_titles(f.provider), [_oldTitle]);
        await f.expectAcceptedAccount(account, originalRows);
      },
    );

    test(
      'rotation ${effect.name} receipt saves returned tokens without HTTP',
      () async {
        final original = await f.seed(expired: true);
        final originalRows = _rows(f.provider);
        final write = f.store.plan('set', _accountsKey, effect, hold: true);
        final syncing = f.observe(f.provider.syncAll());
        await write.started.future.timeout(_wait);
        final staged = write.accountRow('Confirmed OAuth account', f.scope);

        expect(staged['id'], 'existing');
        expect(staged['refreshToken'], _newRefresh);
        expect(_rows(f.provider), originalRows);
        expect(_titles(f.provider), [_oldTitle]);
        expect(f.feed.count('refresh'), 1);
        expect(
          f.feed.count('events'),
          0,
          reason: 'rotation must be durable before event fetch',
        );
        write.release.complete();
        final completed = await syncing.timeout(_wait);
        expect(completed.error, isNull);
        expect(f.provider.lastError, isNotNull);
        expect(f.provider.isSyncing, isFalse);
        expect(_rows(f.provider), originalRows);
        await f.expectRaw(original);

        final receipt = f.provider.oauthLocalCommitReceipts.single;
        _expectOpaque(receipt, null, refreshing: true);
        final peer = f.newProvider();
        await f.readPeerRecovery(peer, refreshing: true);
        _expectReceipt(peer, receipt);
        final requests = f.feed.requests.toList();
        final recovered = await f
            .observe(peer.retryOAuthLocalCommit(receipt, isCurrent: () => true))
            .timeout(_wait);
        expect(recovered.error, isNull);
        final account = recovered.value!;
        expect(account.id, 'existing');
        expect(account.expiresAt.toIso8601String(), staged['expiresAt']);
        expect(account.accessToken, _newAccess);
        expect(account.refreshToken, _newRefresh);
        expect(account.lastSyncedAt, DateTime.utc(2026, 10, 1));
        expect(
          f.feed.requests,
          requests,
          reason: 'do not refresh the old token again',
        );
        expect(f.feed.count('exchange'), 0);
        expect(f.feed.count('events'), 0);
        expect(peer.oauthLocalCommitReceipts, isEmpty);
        expect(_titles(peer), [_oldTitle]);
        await f.expectAcceptedAccount(account, originalRows);
      },
    );
  }

  test(
    'disposed held exchange is recovered only by explicit new-provider retry',
    () async {
      final original = await f.seed();
      final originalRows = _rows(f.provider);
      final token = f.feed.plan('exchange', hold: true);
      var oldNotifications = 0;
      f.provider.addListener(() => oldNotifications++);
      await f.savePending();
      final connecting = f.observe(f.connect());
      await token.started.future.timeout(_wait);
      f.disposeProvider(f.provider);
      final oldCount = oldNotifications;

      final peer = f.newProvider();
      expect(peer.oauthLocalCommitReceipts, isEmpty);
      expect(
        (await f.observe(peer.loadFromStorage()).timeout(_wait)).error,
        isNull,
      );
      expect(_rows(peer), originalRows);
      final attempts = f.store.attempts.toList();
      var peerNotifications = 0;
      peer.addListener(() => peerNotifications++);

      token.release.complete();
      final canceled = await connecting.timeout(_wait);
      expect(canceled.error, isA<AccountPreferenceWriteCanceled>());
      expect(oldNotifications, oldCount);
      expect(
        peerNotifications,
        0,
        reason: 'no response publication into new UI',
      );
      expect(f.provider.lastError, isNull);
      expect(peer.lastError, isNull);
      expect(_rows(f.provider), originalRows);
      expect(_rows(peer), originalRows);
      expect(
        f.store.attempts,
        attempts,
        reason: 'obsolete caller writes nothing',
      );
      expect(f.feed.count('exchange'), 1);
      expect(f.feed.count('events'), 0);
      await f.expectRaw(original);

      final receipt = peer.oauthLocalCommitReceipts.single;
      _expectOpaque(receipt, null, refreshing: false);
      expect(
        (await f.observe(peer.loadFromStorage()).timeout(_wait)).error,
        isNull,
      );
      expect(
        _rows(peer),
        originalRows,
        reason: 'reload does not adopt candidate',
      );
      _expectReceipt(peer, receipt);
      expect(f.store.attempts, attempts);
      final requests = f.feed.requests.toList();
      final recovered = await f
          .observe(peer.retryOAuthLocalCommit(receipt, isCurrent: () => true))
          .timeout(_wait);
      expect(recovered.error, isNull);
      final account = recovered.value!;
      expect(account.accessToken, _newAccess);
      expect(account.refreshToken, _newRefresh);
      expect(f.feed.requests, requests);
      expect(f.feed.replayedCodes, isEmpty);
      expect(oldNotifications, oldCount);
      await f.expectAcceptedAccount(account, originalRows);

      final writesAfterRecovery = f.store.attempts.toList();
      final oldRetry = await f
          .observe(
            f.provider.retryOAuthLocalCommit(receipt, isCurrent: () => true),
          )
          .timeout(_wait);
      expect(oldRetry.error, isA<OAuthScopedWorkspaceUnavailable>());
      expect(f.store.attempts, writesAfterRecovery);
      expect(f.feed.requests, requests);
    },
  );

  for (final boundary in ['reset', 'clear', 'failed clear']) {
    test(
      '$boundary makes retained receipt ineligible even for a new provider',
      () async {
        await f.seed();
        final failed = await f.failConnect();
        final receipt = (failed.error! as OAuthLocalCommitRequired).receipt;
        final generation = AccountLocalDataCleaner.accountDataGeneration;
        final epoch = IcsSubscriptionStorage.epoch;
        final resetRevision = OAuthCalendarStorage.resetRevision;

        if (boundary == 'reset') {
          f.provider.resetLocalState();
        } else {
          if (boundary == 'failed clear') {
            f.store.plan('remove', _accountsKey, _WriteEffect.returnsFalse);
          }
          final cleared = await f
              .observe(AccountLocalDataCleaner.clearSharedPreferences())
              .timeout(_wait);
          if (boundary == 'failed clear') {
            expect(cleared.error, isA<StateError>());
            expect(
              IcsSubscriptionStorage.epoch,
              epoch,
              reason: 'failed cleanup need not advance the storage epoch',
            );
          } else {
            expect(cleared.error, isNull);
          }
          expect(
            AccountLocalDataCleaner.accountDataGeneration,
            greaterThan(generation),
          );
        }
        if (boundary == 'reset') {
          expect(
            OAuthCalendarStorage.resetRevision,
            greaterThan(resetRevision),
          );
        }

        final peer = f.newProvider();
        final diskAtBoundary = await f.store.oauthDisk();
        final attempts = f.store.attempts.toList();
        final requests = f.feed.requests.toList();
        expect(peer.oauthLocalCommitReceipts, isEmpty);
        expect(f.provider.oauthLocalCommitReceipts, isEmpty);
        for (final provider in [f.provider, peer]) {
          final retry = await f
              .observe(
                provider.retryOAuthLocalCommit(receipt, isCurrent: () => true),
              )
              .timeout(_wait);
          expect(retry.error, isA<OAuthScopedWorkspaceUnavailable>());
          expect(provider.isOAuthReady, isFalse);
        }
        expect(peer.oauthAccounts, isEmpty);
        expect(f.store.attempts, attempts);
        expect(await f.store.oauthDisk(), diskAtBoundary);
        expect(
          f.feed.requests,
          requests,
          reason: 'new current UI cannot adopt old owner',
        );
        expect(f.feed.replayedCodes, isEmpty);
      },
    );
  }

  test(
    'account reset cannot replay a consumed code in the same store',
    () async {
      await f.seed();
      final failed = await f.failConnect();
      expect(failed.error, isA<OAuthLocalCommitRequired>());
      final requests = f.feed.requests.toList();
      final attempts = f.store.attempts.toList();
      f.provider.resetLocalState();
      final diskAtReset = await f.store.oauthDisk();
      final repeated = await f.observe(f.connect()).timeout(_wait);
      expect(repeated.error, isA<OAuthScopedWorkspaceUnavailable>());
      expect(f.provider.isOAuthReady, isFalse);
      await f.expectOAuthDisk(diskAtReset);
      expect(f.feed.requests, requests);
      expect(f.store.attempts, attempts);
      expect(f.provider.oauthLocalCommitReceipts, isEmpty);
    },
  );

  test(
    'concurrent and duplicate receipt retries across providers commit once',
    () async {
      await f.seed();
      final originalRows = _rows(f.provider);
      final failed = await f.failConnect();
      final receipt = (failed.error! as OAuthLocalCommitRequired).receipt;
      final first = f.newProvider();
      final second = f.newProvider();
      final requests = f.feed.requests.toList();
      final writesBefore = f.store.accountWrites.length;
      final write = f.store.plan(
        'set',
        _accountsKey,
        _WriteEffect.accept,
        hold: true,
      );
      var firstDone = false;
      var secondDone = false;
      final retry1 = f.observe(first.retryOAuthLocalCommit(receipt)).then((
        value,
      ) {
        firstDone = true;
        return value;
      });
      await write.started.future.timeout(_wait);
      final staged = write.accountRow('New OAuth account', f.scope);
      final retry2 = f.observe(second.retryOAuthLocalCommit(receipt)).then((
        value,
      ) {
        secondDone = true;
        return value;
      });
      await _settleReadyWork();

      expect(firstDone, isFalse);
      expect(secondDone, isFalse);
      expect(f.store.accountWrites, hasLength(writesBefore + 1));
      expect(first.oauthAccounts, isEmpty);
      expect(second.oauthAccounts, isEmpty);
      expect(f.feed.requests, requests);

      write.release.complete();
      final results = await Future.wait([retry1, retry2]).timeout(_wait);
      for (final result in results) {
        expect(result.error, isNull);
        expect(result.value!.id, staged['id']);
        expect(result.value!.expiresAt.toIso8601String(), staged['expiresAt']);
      }
      expect(_rows(first), _rows(second));
      expect(first.oauthLocalCommitReceipts, isEmpty);
      expect(second.oauthLocalCommitReceipts, isEmpty);
      expect(f.store.accountWrites, hasLength(writesBefore + 1));
      await f.expectAcceptedAccount(results.first.value!, originalRows);

      final settledWrites = f.store.attempts.toList();
      for (final provider in [first, second]) {
        final duplicate = await f
            .observe(provider.retryOAuthLocalCommit(receipt))
            .timeout(_wait);
        expect(duplicate.error, isNull);
        expect(duplicate.value!.id, staged['id']);
        expect(
          duplicate.value!.expiresAt.toIso8601String(),
          staged['expiresAt'],
        );
      }
      expect(
        f.store.attempts,
        settledWrites,
        reason: 'already committed is idempotent',
      );
      expect(f.feed.requests, requests);
      expect(f.feed.replayedCodes, isEmpty);
    },
  );

  test(
    'obsolete current predicate rejects local recovery and keeps its receipt',
    () async {
      final original = await f.seed();
      final failed = await f.failConnect();
      final receipt = (failed.error! as OAuthLocalCommitRequired).receipt;
      final attempts = f.store.attempts.toList();
      final requests = f.feed.requests.toList();
      final rejected = await f
          .observe(
            f.provider.retryOAuthLocalCommit(receipt, isCurrent: () => false),
          )
          .timeout(_wait);
      expect(rejected.error, isA<AccountPreferenceWriteCanceled>());
      _expectReceipt(f.provider, receipt);
      expect(f.store.attempts, attempts);
      expect(f.feed.requests, requests);
      await f.expectRaw(original);

      final peer = f.newProvider();
      final recovered = await f
          .observe(peer.retryOAuthLocalCommit(receipt, isCurrent: () => true))
          .timeout(_wait);
      expect(recovered.error, isNull);
      expect(f.feed.requests, requests);
    },
  );

  test(
    'route cancellation during issued receipt save restores before new retry',
    () async {
      final original = await f.seed();
      final originalRows = _rows(f.provider);
      final failed = await f.failConnect();
      final receipt = (failed.error! as OAuthLocalCommitRequired).receipt;
      final write = f.store.plan(
        'set',
        _accountsKey,
        _WriteEffect.accept,
        hold: true,
      );
      var current = true;
      var notifications = 0;
      f.provider.addListener(() => notifications++);
      final retry = f.observe(
        f.provider.retryOAuthLocalCommit(receipt, isCurrent: () => current),
      );
      await write.started.future.timeout(_wait);
      final staged = write.accountRow('New OAuth account', f.scope);
      current = false;
      write.release.complete();
      final canceled = await retry.timeout(_wait);
      expect(canceled.error, isA<AccountPreferenceWriteCanceled>());
      expect(notifications, 0);
      expect(_rows(f.provider), originalRows);
      expect(_titles(f.provider), [_oldTitle]);
      expect(f.provider.lastError, isNull);
      _expectReceipt(f.provider, receipt);
      await f.expectRaw(original);

      final peer = f.newProvider();
      final requests = f.feed.requests.toList();
      final recovered = await f
          .observe(peer.retryOAuthLocalCommit(receipt, isCurrent: () => true))
          .timeout(_wait);
      expect(recovered.error, isNull);
      expect(recovered.value!.id, staged['id']);
      expect(recovered.value!.expiresAt.toIso8601String(), staged['expiresAt']);
      expect(f.feed.requests, requests);
      expect(notifications, 0);
      await f.expectAcceptedAccount(recovered.value!, originalRows);
    },
  );

  test(
    'shared reconciliation restores storage without adopting the receipt',
    () async {
      final original = await f.seed();
      final originalRows = _rows(f.provider);
      final write = f.store.plan(
        'set',
        _accountsKey,
        _WriteEffect.persistThenFalse,
      );
      f.store.plan('set', _accountsKey, _WriteEffect.returnsFalse);
      await f.savePending();
      final failed = await f.observe(f.connect()).timeout(_wait);
      expect(failed.error, isA<OAuthLocalCommitRequired>());
      final receipt = (failed.error! as OAuthLocalCommitRequired).receipt;
      final staged = write.accountRow('New OAuth account', f.scope);
      _expectOpaque(receipt, failed.error, refreshing: false);
      _expectUncertainOAuth(f.provider);
      expect(OAuthCalendarStorage.failure, isA<OAuthStorageIndeterminate>());
      expect(f.auth.isOAuthScopeLeaseCurrent(f.lease), isFalse);
      expect(f.auth.isOAuthScopeLeaseRetainable(f.lease), isTrue);
      final received = f.expectedReceivedAuthorization(write.value!, receipt);
      await f.expectAuthorizationInventory(write.value!, received, original);
      final expectedWrites = f.authorizationMutations(write.value!, received, original);
      expect(f.store.mutations, expectedWrites);
      expect(f.store.attempts,
        expectedWrites.map((row) => '${row['kind']}:${row['key']}').toList());
      final peer = f.newProvider();
      _expectUncertainOAuth(peer);
      final uncertainDisk = await f.store.oauthDisk();
      final attempts = f.store.attempts.toList();
      final requests = f.feed.requests.toList();

      final blocked = await f
          .observe(peer.retryOAuthLocalCommit(receipt))
          .timeout(_wait);
      expect(blocked.error, isA<OAuthScopedWorkspaceUnavailable>());
      _expectUncertainOAuth(peer);
      expect(f.store.attempts, attempts);
      expect(f.store.mutations, expectedWrites);
      await f.expectOAuthDisk(uncertainDisk);
      expect(f.feed.requests, requests);
      expect(f.feed.count('exchange'), 1);
      expect(f.feed.count('events'), 0);
      expect(f.feed.replayedCodes, isEmpty);

      final reconciled = await f
          .observe(peer.reconcileOAuthStorage(isCurrent: () => true))
          .timeout(_wait);
      expect(reconciled.error, isNull);
      expect(peer.oauthStorageNeedsReconciliation, isFalse);
      expect(f.provider.oauthStorageNeedsReconciliation, isFalse);
      expect(
        peer.oauthAccounts,
        isEmpty,
        reason: 'reconciliation is not adoption',
      );
      expect(f.provider.oauthAccounts, isEmpty);
      expect(f.provider.allEvents(), isEmpty);
      final reconciledWrites = [
        ...expectedWrites,
        {'kind': 'set', 'key': 'flutter.$_accountsKey', 'value': original[_accountsKey]},
      ];
      expect(f.store.mutations, reconciledWrites);
      await f.expectAuthorizationInventory(original[_accountsKey]!, received, original);
      await f.readPeerRecovery(peer);
      _expectReceipt(peer, receipt);
      expect(peer.oauthAccounts, isEmpty);
      expect(peer.allEvents(), isEmpty);
      expect(f.feed.requests, requests);
      await f.expectRaw(original);

      final recovered = await f
          .observe(peer.retryOAuthLocalCommit(receipt))
          .timeout(_wait);
      expect(recovered.error, isNull);
      expect(recovered.value!.id, staged['id']);
      expect(recovered.value!.expiresAt.toIso8601String(), staged['expiresAt']);
      expect(recovered.value!.accessToken, _newAccess);
      expect(recovered.value!.refreshToken, _newRefresh);
      expect(f.feed.requests, requests);
      expect(f.feed.replayedCodes, isEmpty);
      expect(f.store.mutations, [
        ...reconciledWrites,
        {'kind': 'set', 'key': 'flutter.$_accountsKey', 'value': write.value},
        {'kind': 'remove', 'key': 'flutter.$_pendingKey', 'value': null},
      ]);
      await f.expectAcceptedAccount(recovered.value!, originalRows);
      await f.expectOAuthDisk({
        'flutter.${OAuthCalendarStorage.scopeOwnerKey}': f.lease.workspace.rawRecord,
        'flutter.$_accountsKey': write.value!,
        'flutter.$_cacheKey': original[_cacheKey]!,
      });
    },
  );

  for (final rollback in [false, true]) {
    test(
      'peer load waits for ${rollback ? 'issued compensation' : 'credential ACK'} before publishing OAuth',
      () async {
        final original = await f.seed();
        final originalRows = _rows(f.provider);
        await f.prefs.setString(
          'duoyi_ics_subscriptions_v1',
          jsonEncode([
            const IcsSubscription(
              id: 'independent-ics',
              name: 'Independent calendar',
              url: 'https://example.invalid/calendar.ics',
            ).toJson(),
          ]),
        );
        final failed = await f.failConnect();
        final receipt = (failed.error! as OAuthLocalCommitRequired).receipt;
        final rejected = rollback
            ? f.store.plan('set', _accountsKey, _WriteEffect.persistThenFalse)
            : null;
        final held = f.store.plan(
          'set',
          _accountsKey,
          _WriteEffect.accept,
          hold: true,
          persistBeforeAck: !rollback,
        );
        final retry = f.observe(f.provider.retryOAuthLocalCommit(receipt));
        await held.started.future.timeout(_wait);
        final peer = f.newProvider();
        final icsPublished = Completer<void>();
        final oauthAdmission = Completer<void>();
        final publications = <List<Map<String, dynamic>>>[];
        peer.addListener(() {
          publications.add(_rows(peer));
          if (peer.subscriptions.isNotEmpty && !icsPublished.isCompleted) {
            icsPublished.complete();
          }
        });
        var loaded = false;
        final loading = f.observe(
          peer
              .loadFromStorage(
                isCurrent: () {
                  // After ICS publication, the next origin check is the OAuth
                  // admission. Completing this gate resumes the test in a microtask,
                  // after that synchronous admission has enrolled the queued load.
                  if (icsPublished.isCompleted && !oauthAdmission.isCompleted) {
                    oauthAdmission.complete();
                  }
                  return true;
                },
              )
              .then((_) {
                loaded = true;
              }),
        );
        await oauthAdmission.future.timeout(_wait);
        expect(peer.subscriptions.single.id, 'independent-ics');
        expect(
          peer.oauthAccounts,
          isEmpty,
          reason: 'no OAuth publication before settlement',
        );
        expect(loaded, isFalse);
        expect(publications, everyElement(isEmpty));
        final disk = await f.store.getAll();
        expect(
          f.sourceRecords(disk['flutter.$_accountsKey']! as String),
          hasLength(3),
          reason:
              'candidate is really persisted before held ACK or compensation',
        );
        final requests = f.feed.requests.toList();
        held.release.complete();
        final result = await retry.timeout(_wait);
        expect(
          result.error,
          rollback ? isA<OAuthLocalCommitRequired>() : isNull,
        );
        expect((await loading.timeout(_wait)).error, isNull);
        expect(loaded, isTrue);
        final expectedRows = [
          ...originalRows,
          if (!rollback) (rejected ?? held).accountRow('New OAuth account', f.scope),
        ];
        expect(_rows(peer), expectedRows);
        expect(publications.last, expectedRows);
        expect(
          publications.take(publications.length - 1),
          everyElement(isEmpty),
        );
        expect(_titles(peer), [_oldTitle]);
        expect(
          f.feed.requests,
          requests,
          reason: 'load and recovery make zero HTTP',
        );
        if (rollback) await f.expectRaw(original);
      },
    );
  }

  test(
    'indeterminate OAuth load preserves confirmed view and still loads ICS',
    () async {
      final original = await f.seed();
      final peer = f.newProvider();
      expect(
        (await f.observe(peer.loadFromStorage()).timeout(_wait)).error,
        isNull,
      );
      final peerRows = _rows(peer);
      final write = f.store.plan('set', _accountsKey, _WriteEffect.persistThenFalse);
      f.store.plan('set', _accountsKey, _WriteEffect.returnsFalse);
      await f.savePending();
      final failed = await f.observe(f.connect()).timeout(_wait);
      expect(failed.error, isA<OAuthLocalCommitRequired>());
      final receipt = (failed.error! as OAuthLocalCommitRequired).receipt;
      _expectOpaque(receipt, failed.error, refreshing: false);
      _expectUncertainOAuth(f.provider);
      _expectUncertainOAuth(peer);
      final received = f.expectedReceivedAuthorization(write.value!, receipt);
      await f.expectAuthorizationInventory(write.value!, received, original);
      final expectedWrites = f.authorizationMutations(write.value!, received, original);
      expect(f.store.mutations, expectedWrites);
      final icsRaw = jsonEncode([
          const IcsSubscription(
            id: 'independent-ics',
            name: 'Independent calendar',
            url: 'https://example.invalid/calendar.ics',
          ).toJson(),
        ]);
      expect(await f.prefs.setString('duoyi_ics_subscriptions_v1', icsRaw), isTrue);
      final allWrites = [
        ...expectedWrites,
        {'kind': 'set', 'key': 'flutter.duoyi_ics_subscriptions_v1', 'value': icsRaw},
      ];
      final requests = f.feed.requests.toList();
      final attempts = f.store.attempts.toList();
      final loaded = await f.observe(peer.loadFromStorage()).timeout(_wait);
      expect(loaded.error, isNull);
      expect(peer.subscriptions.single.id, 'independent-ics');
      _expectUncertainOAuth(peer);
      expect(OAuthCalendarStorage.failure, isA<OAuthStorageIndeterminate>());
      await f.expectAuthorizationInventory(write.value!, received, original);
      expect(f.store.mutations, allWrites);
      expect(f.store.attempts, attempts, reason: 'blocked read writes nothing');
      expect(f.feed.requests, requests);
      expect(
        (await f.observe(peer.reconcileOAuthStorage()).timeout(_wait)).error,
        isNull,
      );
      expect(peer.oauthStorageNeedsReconciliation, isFalse);
      expect(peer.oauthAccounts, isEmpty);
      expect(peer.allEvents(), isEmpty);
      final reconciledWrites = [
        ...allWrites,
        {'kind': 'set', 'key': 'flutter.$_accountsKey', 'value': original[_accountsKey]},
      ];
      expect(f.store.mutations, reconciledWrites);
      await f.expectAuthorizationInventory(original[_accountsKey]!, received, original);
      expect(
        (await f.observe(peer.loadFromStorage()).timeout(_wait)).error,
        isNull,
      );
      expect(_rows(peer), peerRows);
      expect(_titles(peer), [_oldTitle]);
      expect(peer.subscriptions.single.id, 'independent-ics');
      _expectReceipt(peer, receipt);
      expect(_rows(peer).any((row) => row['id'] == received.sourceAccountId), isFalse,
        reason: 'ordinary load restores confirmation without receipt adoption');
      expect(f.store.mutations, reconciledWrites);
      await f.expectRaw(original);
      expect(f.feed.requests, requests);
    },
  );

  test(
    'queued OAuth load keeps original route authority after ICS publication',
    () async {
      await f.seed();
      await f.prefs.setString(
        'duoyi_ics_subscriptions_v1',
        jsonEncode([
          const IcsSubscription(
            id: 'independent-ics',
            name: 'Independent calendar',
            url: 'https://example.invalid/calendar.ics',
          ).toJson(),
        ]),
      );
      final failed = await f.failConnect();
      final receipt = (failed.error! as OAuthLocalCommitRequired).receipt;
      final held = f.store.plan(
        'set',
        _accountsKey,
        _WriteEffect.accept,
        hold: true,
      );
      final retry = f.observe(f.provider.retryOAuthLocalCommit(receipt));
      await held.started.future.timeout(_wait);
      final peer = f.newProvider();
      var current = true;
      var notifications = 0;
      final icsPublished = Completer<void>();
      final oauthAdmission = Completer<void>();
      peer.addListener(() {
        notifications++;
        if (peer.subscriptions.isNotEmpty && !icsPublished.isCompleted) {
          icsPublished.complete();
        }
      });
      final loading = f.observe(
        peer.loadFromStorage(
          isCurrent: () {
            if (icsPublished.isCompleted && !oauthAdmission.isCompleted) {
              oauthAdmission.complete();
            }
            return current;
          },
        ),
      );
      await oauthAdmission.future.timeout(_wait);
      expect(peer.oauthAccounts, isEmpty);
      current = false;
      final atCancel = notifications;
      final requests = f.feed.requests.toList();
      held.release.complete();
      expect((await retry.timeout(_wait)).error, isNull);
      expect(
        (await loading.timeout(_wait)).error,
        isA<AccountPreferenceWriteCanceled>(),
      );
      expect(peer.oauthAccounts, isEmpty);
      expect(notifications, atCancel);
      expect(f.feed.requests, requests);
    },
  );

  test('canceled queued load rejects before predecessor uncertainty', () async {
    final original = await f.seed();
    final icsRaw = jsonEncode([
        const IcsSubscription(
          id: 'independent-ics',
          name: 'Independent calendar',
          url: 'https://example.invalid/calendar.ics',
        ).toJson(),
      ]);
    expect(await f.prefs.setString('duoyi_ics_subscriptions_v1', icsRaw), isTrue);
    final failed = await f.failConnect();
    final receipt = (failed.error! as OAuthLocalCommitRequired).receipt;
    _expectOpaque(receipt, failed.error, refreshing: false);
    final stagedRaw = f.store.accountWrites.first;
    final received = f.expectedReceivedAuthorization(stagedRaw, receipt);
    final initialWrites = [
      {'kind': 'set', 'key': 'flutter.duoyi_ics_subscriptions_v1', 'value': icsRaw},
      ...f.authorizationMutations(stagedRaw, received, original),
    ];
    expect(f.store.mutations, initialWrites);
    await f.expectAuthorizationInventory(original[_accountsKey]!, received, original);
    final issued = f.store.plan('set', _accountsKey, _WriteEffect.persistThenFalse);
    final compensation = f.store.plan(
      'set',
      _accountsKey,
      _WriteEffect.returnsFalse,
      hold: true,
    );
    final retry = f.observe(f.provider.retryOAuthLocalCommit(receipt));
    await compensation.started.future.timeout(_wait);
    final peer = f.newProvider();
    var current = true;
    var notifications = 0;
    final publications = <Map<String, Object?>>[];
    var icsPublished = false;
    final oauthAdmission = Completer<void>();
    peer.addListener(() {
      notifications++;
      publications.add(_publicOAuthState(peer));
      icsPublished = peer.subscriptions.isNotEmpty;
    });
    final loading = f.observe(
      peer.loadFromStorage(
        isCurrent: () {
          if (icsPublished && !oauthAdmission.isCompleted) {
            oauthAdmission.complete();
          }
          return current;
        },
      ),
    );
    await oauthAdmission.future.timeout(_wait);
    current = false;
    final atCancel = notifications;
    expect(publications, hasLength(atCancel));
    final atCancelState = _publicOAuthState(peer);
    expect(atCancelState['oauthAccounts'], isEmpty);
    expect(atCancelState['events'], isEmpty);
    expect(atCancelState['oauthReady'], isTrue);
    expect(atCancelState['oauthNeedsReconciliation'], isFalse);
    final expectedDiagnosisState = {
      ...atCancelState,
      'oauthReady': false,
      'oauthNeedsReconciliation': true,
    };
    final requests = f.feed.requests.toList();
    compensation.release.complete();
    final uncertain = await retry.timeout(_wait);
    expect(uncertain.error, isA<OAuthLocalCommitRequired>());
    expect((uncertain.error! as OAuthLocalCommitRequired).receipt, same(receipt));
    _expectOpaque(receipt, uncertain.error, refreshing: false);
    _expectUncertainOAuth(f.provider);
    expect(
      (await loading.timeout(_wait)).error,
      isA<AccountPreferenceWriteCanceled>(),
    );
    _expectUncertainOAuth(peer);
    expect(publications.skip(atCancel).toList(), [expectedDiagnosisState],
      reason: 'one explicit diagnostic notification, no canceled-load publication');
    expect(notifications, atCancel + 1);
    expect(f.feed.requests, requests);
    expect(f.feed.replayedCodes, isEmpty);
    expect(issued.value, stagedRaw);
    final uncertainWrites = [
      ...initialWrites,
      {'kind': 'set', 'key': 'flutter.$_accountsKey', 'value': issued.value},
      {'kind': 'set', 'key': 'flutter.$_accountsKey', 'value': original[_accountsKey]},
    ];
    expect(f.store.mutations, uncertainWrites);
    expect(f.store.attempts,
      uncertainWrites.map((row) => '${row['kind']}:${row['key']}').toList());
    await f.expectAuthorizationInventory(stagedRaw, received, original);
    expect(
      (await f.observe(peer.loadFromStorage()).timeout(_wait)).error,
      isNull,
    );
    _expectUncertainOAuth(peer);
    expect(peer.subscriptions.single.id, 'independent-ics');
    expect(publications.skip(atCancel).toList(), [
      expectedDiagnosisState, expectedDiagnosisState,
    ], reason: 'fresh ICS load publishes ICS once and leaves diagnosis active');
    expect(notifications, atCancel + 2);
    expect(f.store.mutations, uncertainWrites);
    await f.expectAuthorizationInventory(stagedRaw, received, original);
    expect(f.feed.requests, requests);
    expect(f.feed.count('exchange'), 1);
    expect(f.feed.count('events'), 0);
  });
  for (final boundary in ['false caller', 'throwing caller', 'dispose returning true', 'reset returning true']) {
    test('matching uncertainty cannot report into $boundary', () async {
      final original = await f.seed();
      final originalRows = _rows(f.provider);
      final write = f.store.plan('set', _accountsKey, _WriteEffect.persistThenFalse);
      final compensation = f.store.plan(
        'set', _accountsKey, _WriteEffect.returnsFalse, hold: true,
      );
      await f.savePending();
      var callbackReached = false;
      final connecting = f.observe(f.connect(isCurrent: () {
        if (OAuthCalendarStorage.failure != null) {
          callbackReached = true;
          if (boundary == 'false caller') return false;
          if (boundary == 'throwing caller') throw StateError('Synthetic revoked caller');
          if (boundary == 'dispose returning true') f.disposeProvider(f.provider);
          if (boundary == 'reset returning true') f.provider.resetLocalState();
        }
        return true;
      }));
      await compensation.started.future.timeout(_wait);
      final staged = write.accountRow('New OAuth account', f.scope);
      final backing = await f.store.getAll();
      final actual = OAuthOwnedPendingAuthorization.parse(
        backing['flutter.$_pendingKey']! as String, scope: f.scope,
      );
      expect(actual, isNotNull);
      expect(actual!.phase, OAuthPendingPhase.received);
      final received = f.expectedReceivedAuthorizationForHandle(write.value!, actual.receiptHandle!);
      expect(actual.encode(), received.encode());
      final expectedWrites = f.authorizationMutations(write.value!, received, original);
      expect(f.store.mutations, expectedWrites);
      final requests = f.feed.requests.toList();
      final attempts = f.store.attempts.toList();
      compensation.release.complete();
      final canceled = await connecting.timeout(_wait);
      expect(callbackReached, isTrue,
        reason: 'real failed compensation reaches the reporting caller, not an earlier gate');
      expect(canceled.error, isA<AccountPreferenceWriteCanceled>());
      _expectUncertainOAuth(f.provider);
      expect(f.store.mutations, expectedWrites);
      expect(f.store.attempts, attempts);
      await f.expectAuthorizationInventory(write.value!, received, original);
      expect(f.feed.requests, requests);
      expect(f.feed.count('exchange'), 1);
      expect(f.feed.count('events'), 0);
      expect(f.feed.replayedCodes, isEmpty);

      final peer = f.newProvider();
      if (boundary == 'reset returning true') {
        expect(f.auth.isOAuthScopeLeaseRetainable(f.lease), isFalse);
        expect((await f.observe(peer.reconcileOAuthStorage()).timeout(_wait)).error,
          isA<OAuthScopedWorkspaceUnavailable>());
        expect(f.store.mutations, expectedWrites);
        await f.expectAuthorizationInventory(write.value!, received, original);
      } else {
        expect(f.auth.isOAuthScopeLeaseRetainable(f.lease), isTrue);
        expect((await f.observe(peer.reconcileOAuthStorage()).timeout(_wait)).error, isNull);
        expect(peer.oauthAccounts, isEmpty);
        final reconciledWrites = [
          ...expectedWrites,
          {'kind': 'set', 'key': 'flutter.$_accountsKey', 'value': original[_accountsKey]},
        ];
        expect(f.store.mutations, reconciledWrites);
        await f.expectAuthorizationInventory(original[_accountsKey]!, received, original);
        await f.readPeerRecovery(peer);
        final receipt = peer.oauthLocalCommitReceipts.single;
        _expectOpaque(receipt, null, refreshing: false);
        expect(receipt.handle, received.receiptHandle);
        final recovered = await f.observe(peer.retryOAuthLocalCommit(receipt)).timeout(_wait);
        expect(recovered.error, isNull);
        expect(recovered.value!.id, staged['id']);
        expect(recovered.value!.expiresAt.toIso8601String(), staged['expiresAt']);
        expect(f.store.mutations, [
          ...reconciledWrites,
          {'kind': 'set', 'key': 'flutter.$_accountsKey', 'value': write.value},
          {'kind': 'remove', 'key': 'flutter.$_pendingKey', 'value': null},
        ]);
        await f.expectAcceptedAccount(recovered.value!, originalRows);
      }
      expect(f.feed.requests, requests);
      expect(f.feed.replayedCodes, isEmpty);
    });
  }

  test('matching diagnostic rejects foreign prepared issuer and revoked recovery callers', () async {
    final original = await f.seed();
    final foreignAuth = AuthProvider();
    final foreign = CalendarSyncProvider(oauthHttpClient: f.client, authProvider: foreignAuth);
    f.providers.add(foreign);
    try {
      final beforeForeign = await f.store.oauthDisk();
      final beforeWrites = f.store.mutations.toList();
      final beforeRequests = f.feed.requests.toList();
      await foreignAuth.loadFromStorage(refreshServerConfig: false).timeout(_wait);
      await foreign.prepareOAuthScope().timeout(_wait);
      final foreignLease = foreignAuth.captureOAuthScopeLease();
      expect(foreignLease.workspace.rawRecord, f.lease.workspace.rawRecord);
      expect(identical(foreignLease.workspace, f.lease.workspace), isFalse);
      expect(foreign.isOAuthReady, isTrue);
      expect(f.store.mutations, beforeWrites);
      await f.expectOAuthDisk(beforeForeign);
      expect(f.feed.requests, beforeRequests);

      final write = f.store.plan('set', _accountsKey, _WriteEffect.persistThenFalse);
      f.store.plan('set', _accountsKey, _WriteEffect.returnsFalse);
      await f.savePending();
      final failed = await f.observe(f.connect()).timeout(_wait);
      expect(failed.error, isA<OAuthLocalCommitRequired>());
      final receipt = (failed.error! as OAuthLocalCommitRequired).receipt;
      _expectOpaque(receipt, failed.error, refreshing: false);
      final received = f.expectedReceivedAuthorization(write.value!, receipt);
      final expectedWrites = f.authorizationMutations(write.value!, received, original);
      expect(f.store.mutations, expectedWrites);
      await f.expectAuthorizationInventory(write.value!, received, original);
      final diagnostic = OAuthCalendarStorage.failure;
      expect(diagnostic, isA<OAuthStorageIndeterminate>());
      expect(f.auth.isOAuthScopeLeaseRetainable(f.lease), isTrue);
      expect(foreignAuth.isOAuthScopeLeaseRetainable(foreignLease), isFalse);
      final noIssuer = CalendarSyncProvider(oauthHttpClient: f.client);
      f.providers.add(noIssuer);
      final disposedPeer = f.newProvider();
      f.disposeProvider(disposedPeer);
      final requests = f.feed.requests.toList();
      for (final provider in [foreign, noIssuer, disposedPeer]) {
        final beforeState = _publicOAuthState(provider);
        expect((await f.observe(provider.retryOAuthLocalCommit(receipt)).timeout(_wait)).error,
          isA<OAuthScopedWorkspaceUnavailable>());
        expect((await f.observe(provider.reconcileOAuthStorage()).timeout(_wait)).error,
          isA<OAuthScopedWorkspaceUnavailable>());
        expect(_publicOAuthState(provider), beforeState);
        expect(f.store.mutations, expectedWrites);
        await f.expectAuthorizationInventory(write.value!, received, original);
        expect(OAuthCalendarStorage.failure, same(diagnostic));
        expect(f.feed.requests, requests);
      }
      expect((await f.observe(f.provider.reconcileOAuthStorage(isCurrent: () => false)).timeout(_wait)).error,
        isA<AccountPreferenceWriteCanceled>());
      expect((await f.observe(f.auth.loadFromStorage(refreshServerConfig: false)).timeout(_wait)).error,
        same(diagnostic));
      expect((await f.observe(f.provider.prepareOAuthScope()).timeout(_wait)).error,
        same(diagnostic));
      expect(f.auth.isOAuthScopeLeaseRetainable(f.lease), isTrue);
      expect(f.store.mutations, expectedWrites);
      await f.expectAuthorizationInventory(write.value!, received, original);
      expect(f.feed.requests, requests);
      expect(f.feed.replayedCodes, isEmpty);
      _expectUncertainOAuth(f.provider);
    } finally {
      f.disposeProvider(foreign);
      foreignAuth.dispose();
    }
  });

  for (final boundary in ['current caller', 'revoked route', 'disposed caller']) {
    test('automatic uncertain refresh keeps raw diagnostic policy for $boundary', () async {
      final original = await f.seed(expired: true);
      final originalRows = _rows(f.provider);
      final account = f.provider.oauthAccounts.singleWhere((row) => row.id == 'existing');
      final startedAt = DateTime.now().toUtc();
      final write = f.store.plan('set', _accountsKey, _WriteEffect.persistThenFalse);
      final compensation = f.store.plan(
        'set', _accountsKey, _WriteEffect.returnsFalse, hold: true,
      );
      var current = true;
      final syncing = f.observe(f.provider.syncOAuthAccount(
        'existing', isCurrent: () => current, expectedAccount: account,
      ));
      await compensation.started.future.timeout(_wait);
      final staged = write.accountRow('Confirmed OAuth account', f.scope);
      expect(staged['accessToken'], _newAccess);
      expect(staged['refreshToken'], _newRefresh);
      final observedDispatch = OAuthOwnedRefreshJournal.parse(
        f.store.mutations[0]['value']! as String, scope: f.scope,
      );
      final observedReceived = OAuthOwnedRefreshJournal.parse(
        f.store.mutations[1]['value']! as String, scope: f.scope,
      );
      expect(observedDispatch, isNotNull);
      expect(observedReceived, isNotNull);
      expect(observedDispatch!.phase, OAuthRefreshPhase.dispatched);
      expect(observedReceived!.phase, OAuthRefreshPhase.received);
      expect(observedDispatch.dispatchedAt.isBefore(startedAt), isFalse);
      expect(observedReceived.receivedAt!.isAfter(DateTime.now().toUtc()), isFalse);
      final dispatched = OAuthOwnedRefreshJournal.createDispatched(
        scope: f.scope,
        operationId: observedDispatch.operationId,
        receiptHandle: observedDispatch.receiptHandle,
        originalSource: f.seedSources.first,
        dispatchedAt: observedDispatch.dispatchedAt,
      );
      final returnedSource = f.seedSources.first.withAccount(staged);
      final received = dispatched.received(
        returnedSource: returnedSource,
        receivedAt: observedReceived.receivedAt!,
      );
      expect(observedDispatch.encode(), dispatched.encode());
      expect(observedReceived.encode(), received.encode());
      expect(write.value, jsonEncode([
        returnedSource.toJson(), f.seedSources[1].toJson(),
      ]), reason: 'fixed rotated source and original unrelated source envelope');
      final expectedWrites = [
        {'kind': 'set', 'key': 'flutter.${OAuthCalendarStorage.refreshJournalKey}', 'value': dispatched.encode()},
        {'kind': 'set', 'key': 'flutter.${OAuthCalendarStorage.refreshJournalKey}', 'value': received.encode()},
        {'kind': 'set', 'key': 'flutter.$_accountsKey', 'value': write.value},
        {'kind': 'set', 'key': 'flutter.$_accountsKey', 'value': original[_accountsKey]},
      ];
      expect(f.store.mutations, expectedWrites);
      final requests = f.feed.requests.toList();
      if (boundary == 'revoked route') current = false;
      if (boundary == 'disposed caller') f.disposeProvider(f.provider);
      compensation.release.complete();
      final completed = await syncing.timeout(_wait);
      expect(completed.error, isNull);
      expect(completed.value!.sourceId, 'existing');
      expect(completed.value!.status, boundary == 'current caller'
        ? OAuthSyncStatus.storageFailure : OAuthSyncStatus.canceled);
      expect(completed.value!.receipt, isNull,
        reason: 'automatic refresh does not enter false-preserve receipt reporting');
      expect(completed.value!.eventCount, 0);
      expect(completed.value!.diagnosticStatus, isNull);
      expect(f.provider.lastError, boundary == 'current caller' ? 'storageFailure' : isNull);
      _expectUncertainOAuth(f.provider);
      expect(f.store.mutations, expectedWrites);
      expect(f.store.attempts,
        expectedWrites.map((row) => '${row['kind']}:${row['key']}').toList());
      await f.expectOAuthDisk({
        'flutter.${OAuthCalendarStorage.scopeOwnerKey}': f.lease.workspace.rawRecord,
        'flutter.$_accountsKey': write.value!,
        'flutter.$_cacheKey': original[_cacheKey]!,
        'flutter.${OAuthCalendarStorage.refreshJournalKey}': received.encode(),
      });
      expect(f.feed.requests, requests);
      expect(f.feed.count('exchange'), 0);
      expect(f.feed.count('refresh'), 1);
      expect(f.feed.count('events'), 0);
      expect(f.feed.replayedCodes, isEmpty);
      final peer = f.newProvider();
      expect((await f.observe(peer.reconcileOAuthStorage()).timeout(_wait)).error, isNull);
      expect(peer.oauthAccounts, isEmpty);
      final reconciledWrites = [
        ...expectedWrites,
        {'kind': 'set', 'key': 'flutter.$_accountsKey', 'value': original[_accountsKey]},
      ];
      expect(f.store.mutations, reconciledWrites);
      await f.expectRaw(original);
      await f.readPeerRecovery(peer, refreshing: true);
      final receipt = peer.oauthLocalCommitReceipts.single;
      _expectOpaque(receipt, null, refreshing: true);
      expect(receipt.handle, received.receiptHandle);
      final recovered = await f.observe(peer.retryOAuthLocalCommit(receipt)).timeout(_wait);
      expect(recovered.error, isNull);
      expect(recovered.value!.id, staged['id']);
      expect(recovered.value!.expiresAt.toIso8601String(), staged['expiresAt']);
      expect(f.store.mutations, [
        ...reconciledWrites,
        {'kind': 'set', 'key': 'flutter.$_accountsKey', 'value': write.value},
        {'kind': 'remove', 'key': 'flutter.${OAuthCalendarStorage.refreshJournalKey}', 'value': null},
      ]);
      await f.expectAcceptedAccount(recovered.value!, originalRows);
      await f.expectOAuthDisk({
        'flutter.${OAuthCalendarStorage.scopeOwnerKey}': f.lease.workspace.rawRecord,
        'flutter.$_accountsKey': write.value!,
        'flutter.$_cacheKey': original[_cacheKey]!,
      });
      expect(f.feed.requests, requests);
    });
  }

  test('revoked connect origin never dispatches authorization', () async {
    await f.seed();
    final before = await f.store.oauthDisk();
    final attempts = f.store.attempts.toList();
    final result = await f
        .observe(f.connect(isCurrent: () => false))
        .timeout(_wait);
    expect(result.error, isA<AccountPreferenceWriteCanceled>());
    expect(f.feed.requests, isEmpty);
    expect(f.store.attempts, attempts);
    expect(await f.store.oauthDisk(), before);
  });

  test(
    'surviving provider route cancellation retains returned credentials only for explicit recovery',
    () async {
      final original = await f.seed();
      final originalRows = _rows(f.provider);
      final token = f.feed.plan('exchange', hold: true);
      var current = true;
      var notifications = 0;
      f.provider.addListener(() => notifications++);
      await f.savePending();
      final connecting = f.observe(f.connect(isCurrent: () => current));
      await token.started.future.timeout(_wait);
      current = false;
      final attempts = f.store.attempts.toList();
      token.release.complete();
      expect(
        (await connecting.timeout(_wait)).error,
        isA<AccountPreferenceWriteCanceled>(),
      );
      expect(f.feed.requests, ['exchange']);
      expect(f.store.attempts, attempts);
      expect(notifications, 0);
      expect(_rows(f.provider), originalRows);
      await f.expectRaw(original);
      final peer = f.newProvider();
      await f.readPeerRecovery(peer);
      final receipt = peer.oauthLocalCommitReceipts.single;
      final requests = f.feed.requests.toList();
      final recovered = await f
          .observe(peer.retryOAuthLocalCommit(receipt, isCurrent: () => true))
          .timeout(_wait);
      expect(recovered.error, isNull);
      expect(f.feed.requests, requests);
      expect(notifications, 0);
      await f.expectAcceptedAccount(recovered.value!, originalRows);
    },
  );

  for (final revoke in ['route', 'cleanup']) {
    test(
      'connect rejects obsolete caller after initial events $revoke',
      () async {
        await f.seed();
        final events = f.feed.plan('events', hold: true);
        var current = true;
        var notifications = 0;
        f.provider.addListener(() => notifications++);
        await f.savePending();
        final connecting = f.observe(f.connect(isCurrent: () => current));
        await events.started.future.timeout(_wait);
        expect(
          f.provider.oauthAccounts,
          hasLength(3),
          reason: 'credentials already confirmed',
        );
        if (revoke == 'route') {
          current = false;
        } else {
          await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
        }
        final disk = await f.store.oauthDisk();
        final attempts = f.store.attempts.toList();
        final atCancel = notifications;
        events.release.complete();
        expect(
          (await connecting.timeout(_wait)).error,
          isA<AccountPreferenceWriteCanceled>(),
        );
        expect(f.store.attempts, attempts);
        expect(await f.store.oauthDisk(), disk);
        expect(notifications, atCancel);
        expect(f.feed.requests, ['exchange', 'events']);
        expect(f.provider.lastError, isNull);
        if (revoke == 'cleanup') {
          expect(disk, isEmpty);
        } else {
          final peer = f.newProvider();
          expect(
            (await f.observe(peer.loadFromStorage()).timeout(_wait)).error,
            isNull,
          );
          expect(peer.oauthAccounts, hasLength(3));
          expect(
            peer.oauthAccounts
                .singleWhere((row) => row.displayName == 'New OAuth account')
                .lastSyncedAt,
            isNull,
          );
        }
      },
    );
  }

  for (final change in ['shared reset', 'source edit']) {
    test(
      'outer sync does not adopt OAuth authority after held ICS $change',
      () async {
        await f.seed();
        await f.prefs.setString(
          'duoyi_ics_subscriptions_v1',
          jsonEncode([
            const IcsSubscription(
              id: 'held-ics',
              name: 'Held calendar',
              url: 'https://example.invalid/held.ics',
            ).toJson(),
          ]),
        );
        expect(
          (await f.observe(f.provider.loadFromStorage()).timeout(_wait)).error,
          isNull,
        );
        final started = Completer<void>();
        final release = Completer<void>();
        final icsClient = MockClient((request) async {
          expect(request.url.toString(), 'https://example.invalid/held.ics');
          started.complete();
          await release.future;
          return http.Response(
            'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n',
            200,
          );
        });
        final syncing = f.observe(
          http.runWithClient(() => f.provider.syncAll(), () => icsClient),
        );
        try {
          await started.future.timeout(_wait);
          if (change == 'shared reset') {
            f.newProvider().resetLocalState();
          } else {
            await f.provider.updateOAuthAccount(
              f.provider.oauthAccounts
                  .singleWhere((row) => row.id == 'existing')
                  .copyWith(calendarId: 'new-current-calendar'),
            );
          }
          final disk = await f.store.oauthDisk();
          release.complete();
          expect((await syncing.timeout(_wait)).error, isNull);
          expect(
            f.feed.requests,
            isEmpty,
            reason: 'old run cannot capture new OAuth reset/source authority',
          );
          expect(await f.store.oauthDisk(), disk);
          expect(f.provider.isSyncing, isFalse);
          expect(f.provider.lastError, isNull);
        } finally {
          if (!release.isCompleted) release.complete();
          await syncing.timeout(_wait);
          icsClient.close();
        }
      },
    );
  }

  test(
    'obsolete outer sync cannot cancel a current peer held event request',
    () async {
      await f.seed();
      await f.prefs.setString(
        'duoyi_ics_subscriptions_v1',
        jsonEncode([
          const IcsSubscription(
            id: 'held-ics',
            name: 'Held calendar',
            url: 'https://example.invalid/held.ics',
          ).toJson(),
        ]),
      );
      expect(
        (await f.observe(f.provider.loadFromStorage()).timeout(_wait)).error,
        isNull,
      );
      final started = Completer<void>();
      final release = Completer<void>();
      final oldIcsClient = MockClient((request) async {
        expect(request.url.toString(), 'https://example.invalid/held.ics');
        started.complete();
        await release.future;
        return http.Response(
          'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n',
          200,
        );
      });
      final currentIcsClient = MockClient((request) async {
        expect(request.url.toString(), 'https://example.invalid/held.ics');
        return http.Response(
          'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n',
          200,
        );
      });
      final obsolete = f.observe(
        http.runWithClient(() => f.provider.syncAll(), () => oldIcsClient),
      );
      final events = f.feed.plan('events', hold: true);
      Future<_Outcome<void>>? currentSync;
      try {
        await started.future.timeout(_wait);
        final peer = f.newProvider();
        expect(
          (await f.observe(peer.loadFromStorage()).timeout(_wait)).error,
          isNull,
        );
        await peer.updateOAuthAccount(
          peer.oauthAccounts
              .singleWhere((row) => row.id == 'existing')
              .copyWith(calendarId: 'new-current-calendar'),
        );
        currentSync = f.observe(
          http.runWithClient(() => peer.syncAll(), () => currentIcsClient),
        );
        await events.started.future.timeout(_wait);
        expect(f.feed.requests, ['events']);
        final heldDisk = await f.store.oauthDisk();
        release.complete();
        expect((await obsolete.timeout(_wait)).error, isNull);
        expect(f.feed.requests, [
          'events',
        ], reason: 'obsolete run never dispatches OAuth');
        expect(
          await f.store.oauthDisk(),
          heldDisk,
          reason: 'peer response still held',
        );
        expect(f.provider.isSyncing, isFalse);
        events.release.complete();
        expect((await currentSync.timeout(_wait)).error, isNull);
        await f.prefs.reload();
        expect(
          f.eventRecord(
            f.prefs.getString(_cacheKey)!, f.prefs.getString(_accountsKey)!,
          ).events,
          isEmpty,
          reason: 'current peer response committed',
        );
        expect(_titles(peer), isEmpty);
        expect(
          peer.oauthAccounts
              .singleWhere((row) => row.id == 'existing')
              .calendarId,
          'new-current-calendar',
        );
        expect(
          peer.oauthAccounts
              .singleWhere((row) => row.id == 'existing')
              .lastSyncedAt!
              .isAfter(DateTime.utc(2026, 10, 1)),
          isTrue,
        );
        expect(peer.isSyncing, isFalse);
        expect(peer.lastError, isNull);
        expect(f.feed.requests, ['events']);
      } finally {
        if (!release.isCompleted) release.complete();
        if (!events.release.isCompleted) events.release.complete();
        await obsolete.timeout(_wait);
        if (currentSync != null) await currentSync.timeout(_wait);
        oldIcsClient.close();
        currentIcsClient.close();
      }
    },
  );

  test(
    'retrying a committed receipt returns current renewed credentials without writes or HTTP',
    () async {
      await f.seed(expired: true);
      f.feed.plan(
        'refresh',
        tokenPayload: {
          'access_token': _newAccess,
          'refresh_token': _newRefresh,
          'expires_in': 1,
          'token_type': 'Bearer',
        },
      );
      f.store.plan('set', _accountsKey, _WriteEffect.returnsFalse);
      expect(
        (await f.observe(f.provider.syncAll()).timeout(_wait)).error,
        isNull,
      );
      final receipt = f.provider.oauthLocalCommitReceipts.single;
      final first = await f
          .observe(f.provider.retryOAuthLocalCommit(receipt))
          .timeout(_wait);
      expect(first.error, isNull);
      f.feed.plan(
        'refresh',
        expectedRefreshToken: _newRefresh,
        tokenPayload: {
          'access_token': 'synthetic-newest-access',
          'refresh_token': 'synthetic-newest-refresh',
          'expires_in': 3600,
          'token_type': 'Bearer',
        },
      );
      expect(
        (await f.observe(f.provider.syncAll()).timeout(_wait)).error,
        isNull,
      );
      final latest = f.provider.oauthAccounts.singleWhere(
        (row) => row.id == 'existing',
      );
      expect(latest.accessToken, 'synthetic-newest-access');
      expect(latest.expiresAt, isNot(first.value!.expiresAt));
      final requests = f.feed.requests.toList();
      final attempts = f.store.attempts.toList();
      final peer = f.newProvider();
      final repeated = await f
          .observe(peer.retryOAuthLocalCommit(receipt))
          .timeout(_wait);
      expect(repeated.error, isNull);
      expect(repeated.value!.toJson(), latest.toJson());
      expect(_rows(peer), _rows(f.provider));
      expect(f.feed.requests, requests);
      expect(f.store.attempts, attempts);
      await f.prefs.reload();
      expect(
        f.accountRows(f.prefs.getString(_accountsKey)!).singleWhere(
          (row) => row['id'] == 'existing',
        ),
        latest.toJson(),
      );
    },
  );
}

const _failedWrites = <_WriteEffect>[
  _WriteEffect.returnsFalse,
  _WriteEffect.persistThenFalse,
  _WriteEffect.throwsError,
  _WriteEffect.ackWithoutPersist,
];

Future<void> _settleReadyWork() => Future<void>(() {});

List<Map<String, dynamic>> _rows(CalendarSyncProvider provider) =>
    provider.oauthAccounts.map((row) => row.toJson()).toList();

List<String> _titles(CalendarSyncProvider provider) =>
    provider.allEvents().map((event) => event.title).toList();

Map<String, Object?> _publicOAuthState(CalendarSyncProvider provider) => {
  'subscriptions': provider.subscriptions.map((row) => row.toJson()).toList(),
  'oauthAccounts': _rows(provider),
  'events': provider.allEvents().map((event) => event.toJson()).toList(),
  'oauthReady': provider.isOAuthReady,
  'oauthNeedsReconciliation': provider.oauthStorageNeedsReconciliation,
  'icsNeedsReconciliation': provider.icsStorageNeedsReconciliation,
  'receipts': provider.oauthLocalCommitReceipts.map((receipt) => {
    'handle': receipt.handle,
    'isRefresh': receipt.isRefresh,
  }).toList(),
  'isSyncing': provider.isSyncing,
  'isTestingWriteTarget': provider.isTestingWriteTarget,
  'isUpdatingWriteTarget': provider.isUpdatingWriteTarget,
  'writeTarget': provider.writeTarget?.toJson(),
  'lastError': provider.lastError,
  'lastCalDavError': provider.lastCalDavError,
  'lastCalDavConflicts': provider.lastCalDavConflicts.toList(),
  'icsResults': provider.icsRefreshResults,
};

void _expectUncertainOAuth(CalendarSyncProvider provider) {
  expect(provider.oauthStorageNeedsReconciliation, isTrue);
  expect(provider.isOAuthReady, isFalse);
  expect(provider.oauthAccounts, isEmpty);
  expect(provider.allEvents(), isEmpty);
  expect(provider.oauthLocalCommitReceipts, isEmpty);
}

void _expectReceipt(
  CalendarSyncProvider provider,
  OAuthLocalCommitReceipt receipt,
) {
  final receipts = provider.oauthLocalCommitReceipts;
  expect(receipts, hasLength(1));
  expect(receipts.single, same(receipt));
}

void _expectOpaque(
  OAuthLocalCommitReceipt receipt,
  Object? error, {
  required bool refreshing,
}) {
  expect(receipt.handle, isNotEmpty);
  expect(receipt.isRefresh, refreshing);
  final text = '${receipt.handle} $receipt ${error ?? ''}';
  for (final secret in [
    _newAccess,
    _newRefresh,
    'synthetic-old-access',
    'synthetic-old-refresh',
    _code,
    _codeVerifier,
    'synthetic-client-secret',
  ]) {
    expect(
      text,
      isNot(contains(secret)),
      reason: 'receipt/error stays sanitized',
    );
  }
}

OAuthCalendarAccount _account({bool expired = false}) => OAuthCalendarAccount(
  id: 'existing',
  provider: OAuthCalendarProvider.google,
  displayName: 'Confirmed OAuth account',
  clientId: 'synthetic-client',
  clientSecret: 'synthetic-client-secret',
  redirectUri: 'duoyi://oauth/calendar',
  accessToken: 'synthetic-old-access',
  refreshToken: 'synthetic-old-refresh',
  expiresAt: expired ? DateTime.utc(2000) : DateTime.utc(2099),
  lastSyncedAt: DateTime.utc(2026, 10, 1),
);

OAuthCalendarAccount _otherAccount() => OAuthCalendarAccount(
  id: 'unrelated-outlook',
  provider: OAuthCalendarProvider.outlook,
  displayName: 'Unrelated confirmed account',
  clientId: 'synthetic-other-client',
  redirectUri: 'duoyi://oauth/calendar',
  accessToken: 'synthetic-other-access',
  refreshToken: 'synthetic-other-refresh',
  expiresAt: DateTime.utc(2099),
  colorValue: 0xFF123456,
  enabled: false,
  lastSyncedAt: DateTime.utc(2026, 9, 1),
);

Map<String, Object?> _cachedEvent() => {
  'id': 'oauth_google_existing_cached',
  'title': _oldTitle,
  'date': '2026-11-09T11:00:00.000Z',
  'endDate': '2026-11-09T12:00:00.000Z',
  'subtitle': null,
  'colorValue': 0xFF5E97F6,
  'sourceId': null,
  'timeHour': 11,
  'timeMinute': 0,
};

class _Outcome<T> {
  const _Outcome.success(T result) : value = result, error = null;
  const _Outcome.failure(Object exception) : value = null, error = exception;

  final T? value;
  final Object? error;
}

class _Fixture {
  _Fixture(this.previousStore, this.store, this.prefs) {
    client = MockClient(feed.respond);
    provider = newProvider();
  }

  final SharedPreferencesStorePlatform previousStore;
  final _OAuthStore store;
  final SharedPreferences prefs;
  // This fixture owns the issuer; every Calendar provider borrows it.
  final AuthProvider auth = AuthProvider();
  late final AuthOAuthScopeLease lease;
  late final OAuthScopedOwnerRecord scope;
  final seedSources = <OAuthOwnedSourceRecord>[];
  late final String seedCacheRaw;
  OAuthOwnedPendingAuthorization? preparedAttempt;
  final feed = _OAuthFeed();
  final pending = <Future<void>>[];
  final providers = <CalendarSyncProvider>[];
  final disposed = <CalendarSyncProvider>{};
  late final MockClient client;
  late final CalendarSyncProvider provider;

  static Future<_Fixture> create() async {
    await AccountPreferenceWrites.drain().timeout(_wait);
    final previous = SharedPreferencesStorePlatform.instance;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = _OAuthStore();
    SharedPreferencesStorePlatform.instance = store;
    final prefs = await SharedPreferences.getInstance();
    await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    expect(
      await prefs.setString(
        AccountLocalDataCleaner.accountDataOwnerKey,
        'id:fixture-oauth',
      ),
      isTrue,
    );
    expect(
      await prefs.setString(
        'auth_state',
        jsonEncode(const AuthState(
          userId: 'fixture-oauth',
          token: 'synthetic-fixture-auth-token',
        ).toJson()),
      ),
      isTrue,
    );
    final fixture = _Fixture(previous, store, prefs);
    await fixture.prepareScope();

    store.attempts.clear();
    store.mutations.clear();
    return fixture;
  }

  CalendarSyncProvider newProvider() {
    final next = CalendarSyncProvider(oauthHttpClient: client, authProvider: auth);
    providers.add(next);
    return next;
  }

  void disposeProvider(CalendarSyncProvider value) {
    if (disposed.add(value)) value.dispose();
  }

  Future<_Outcome<T>> observe<T>(Future<T> task) {
    final result = task.then<_Outcome<T>>(
      (value) => _Outcome<T>.success(value),
      onError: (Object error, StackTrace _) => _Outcome<T>.failure(error),
    );
    pending.add(result.then<void>((_) {}));
    return result;
  }

  Future<void> savePending({CalendarSyncProvider? provider}) async {
    final snapshot = await (provider ?? this.provider).savePendingOAuthAuthorization(
      provider: OAuthCalendarProvider.google,
      displayName: 'New OAuth account',
      clientId: 'synthetic-client',
      clientSecret: 'synthetic-client-secret',
      redirectUri: 'duoyi://oauth/calendar',
      calendarId: 'primary',
      codeVerifier: _codeVerifier,
      state: 'synthetic-attempt-state',
    );
    final prepared = OAuthOwnedPendingAuthorization.create(
      scope: scope,
      attemptId: snapshot['attemptId']!,
      draft: {
        'provider': 'google',
        'displayName': 'New OAuth account',
        'clientId': 'synthetic-client',
        'clientSecret': 'synthetic-client-secret',
        'redirectUri': 'duoyi://oauth/calendar',
        'calendarId': 'primary',
        'codeVerifier': _codeVerifier,
        'state': 'synthetic-attempt-state',
      },
      savedAt: DateTime.parse(snapshot['savedAt']!),
    );
    expect(snapshot, {
      ...prepared.draft,
      'attemptId': prepared.attemptId,
      'savedAt': prepared.savedAt.toIso8601String(),
      'phase': 'prepared',
    });
    expect(prepared.canDispatchAt(DateTime.now()), isTrue);
    await expectRaw({_pendingKey: prepared.encode()});
    final parsed = OAuthOwnedPendingAuthorization.parse(
      prefs.getString(_pendingKey)!,
      scope: scope,
    );
    expect(parsed, isNotNull);
    expect(parsed!.encode(), prepared.encode());
    preparedAttempt = prepared;
  }

  Future<OAuthCalendarAccount> connect({bool Function()? isCurrent}) =>
      provider.addOAuthAccountFromCode(
        provider: OAuthCalendarProvider.google,
        displayName: 'New OAuth account',
        clientId: 'synthetic-client',
        clientSecret: 'synthetic-client-secret',
        redirectUri: 'duoyi://oauth/calendar',
        authorizationCode: _code,
        codeVerifier: _codeVerifier,
        expectedAttemptId: preparedAttempt?.attemptId,
        isCurrent: isCurrent,
      );

  Future<_Outcome<OAuthCalendarAccount>> failConnect() async {
    await savePending();
    store.plan('set', _accountsKey, _WriteEffect.returnsFalse);
    final failed = await observe(connect()).timeout(_wait);
    expect(failed.error, isA<OAuthLocalCommitRequired>());
    expect(provider.oauthLocalCommitReceipts, hasLength(1));
    expect(feed.count('exchange'), 1);
    expect(feed.count('events'), 0);
    return failed;
  }

  Future<Map<String, String>> seed({bool expired = false}) async {
    expect(seedSources, isEmpty, reason: 'mint each seed source once');
    seedSources.add(OAuthOwnedSourceRecord.create(
      scope: scope,
      account: _account(expired: expired).toJson(),
    ));
    seedSources.add(OAuthOwnedSourceRecord.create(
      scope: scope,
      account: _otherAccount().toJson(),
    ));
    seedCacheRaw = OAuthOwnedEventsRecord.create(
      source: seedSources.first,
      events: [_cachedEvent()],
    ).encode();
    final raw = <String, String>{
      _accountsKey: jsonEncode(seedSources.map((row) => row.toJson()).toList()),
      _cacheKey: seedCacheRaw,
    };
    await installSeed(raw);
    expect(
      (await observe(provider.loadFromStorage()).timeout(_wait)).error,
      isNull,
    );
    expect(_titles(provider), [_oldTitle]);
    store.attempts.clear();
    store.mutations.clear();
    store.accountWrites.clear();
    return raw;
  }

  Future<void> prepareScope() async {
    expect(await store.oauthDisk(), isEmpty, reason: 'prepare an empty scope');
    expect(provider.isOAuthReady, isFalse);
    await auth.loadFromStorage(refreshServerConfig: false).timeout(_wait);
    expect(auth.state.userId, 'fixture-oauth');
    expect(auth.state.isLoggedIn, isTrue);
    expect(provider.isOAuthReady, isFalse);
    await provider.prepareOAuthScope(initialize: true).timeout(_wait);
    expect(provider.isOAuthReady, isTrue);
    lease = auth.captureOAuthScopeLease();
    expect(auth.isOAuthScopeLeaseCurrent(lease), isTrue);
    // Parsed owner data is never substituted for the real issuer capability.
    scope = OAuthScopedOwnerRecord.parse(lease.workspace.rawRecord)!;
    expect(scope.scopeKind, 'account');
    expect(scope.matchesAccountOwner('id:fixture-oauth'), isTrue);
    expect(scope.encode(), lease.workspace.rawRecord);
    await expectOAuthDisk({
      'flutter.${OAuthCalendarStorage.scopeOwnerKey}': lease.workspace.rawRecord,
    });
  }

  Future<void> installSeed(Map<String, String> raw) async {
    final epoch = OAuthCalendarStorage.epoch;
    await AccountPreferenceWrites.runResult<void>((token) {
      bool current() => token.isCurrent && auth.isOAuthScopeLeaseCurrent(lease);
      return OAuthCalendarStorage.run<void>(() async {
        await prefs.reload();
        token.ensureCurrent();
        OAuthCalendarStorage.ensureScopedWorkspaceCurrentLocked(
          lease.workspace,
          prefs,
        );
        if (!current()) throw const AccountPreferenceWriteCanceled();
        await OAuthCalendarStorage.commitLocked(
          prefs,
          raw,
          current,
          scopedWorkspace: lease.workspace,
          validateReadback: () {
            OAuthCalendarStorage.ensureScopedWorkspaceCurrentLocked(
              lease.workspace,
              prefs,
            );
            expect(sourceRecords(prefs.getString(_accountsKey)!)
                .map((row) => row.encode()), seedSources.map((row) => row.encode()));
            final cache = OAuthOwnedEventsRecord.parse(
              prefs.getString(_cacheKey)!,
              source: seedSources.first,
            );
            expect(cache, isNotNull);
            expect(cache!.encode(), seedCacheRaw);
          },
        );
      }, epoch: epoch, isCurrent: current);
    }, canceledResult: () => throw const AccountPreferenceWriteCanceled())
        .timeout(_wait);
    await expectRaw(raw);
    await expectOAuthDisk({
      'flutter.${OAuthCalendarStorage.scopeOwnerKey}': lease.workspace.rawRecord,
      for (final entry in raw.entries) 'flutter.${entry.key}': entry.value,
    });
    expect(auth.isOAuthScopeLeaseCurrent(lease), isTrue);
  }

  List<OAuthOwnedSourceRecord> sourceRecords(String raw) {
    final records = OAuthOwnedSourceRecord.parseList(raw, scope: scope);
    expect(records, isNotNull, reason: 'validate the original complete source list');
    return records!;
  }

  List<Map<String, dynamic>> accountRows(String raw) =>
      sourceRecords(raw).map((row) => Map<String, dynamic>.from(row.account)).toList();

  OAuthOwnedEventsRecord eventRecord(String raw, String accountsRaw) {
    final source = sourceRecords(accountsRaw)
        .singleWhere((row) => row.account['id'] == 'existing');
    final record = OAuthOwnedEventsRecord.parse(raw, source: source);
    expect(record, isNotNull, reason: 'cache is bound to the current owned source');
    return record!;
  }

  Future<void> expectOAuthDisk(Map<String, Object> expected) async {
    expect(await store.oauthDisk(), expected, reason: 'complete backing OAuth inventory');
    await prefs.reload();
    expect({
      for (final key in prefs.getKeys().where(OAuthCalendarStorage.isOAuthScopeKey))
        'flutter.$key': prefs.get(key)!,
    }, expected, reason: 'complete reloaded OAuth inventory');
  }

  OAuthOwnedPendingAuthorization expectedReceivedAuthorization(
    String stagedRaw,
    OAuthLocalCommitReceipt receipt,
  ) => expectedReceivedAuthorizationForHandle(stagedRaw, receipt.handle);

  OAuthOwnedPendingAuthorization expectedReceivedAuthorizationForHandle(
    String stagedRaw,
    String handle,
  ) {
    final staged = sourceRecords(stagedRaw)
        .singleWhere((row) => row.account['displayName'] == 'New OAuth account');
    expect(staged.account['accessToken'], _newAccess);
    expect(staged.account['refreshToken'], _newRefresh);
    expect(staged.account['id'], isNotEmpty);
    expect(staged.account['expiresAt'], isA<String>());
    expect(stagedRaw, jsonEncode([
      ...seedSources.map((row) => row.toJson()),
      staged.toJson(),
    ]), reason: 'all original source envelopes remain byte-exact and ordered');
    final dispatched = preparedAttempt!.dispatched(
      fingerprint: sha256.convert(utf8.encode(jsonEncode([
        'google', 'synthetic-client', 'duoyi://oauth/calendar', _code,
      ]))).toString(),
      accountId: staged.account['id']! as String,
    );
    // Only product-generated source bytes/ID and the public receipt are observed.
    // Scope, attempt, draft, time, phase and fingerprint come from the prepared
    // preimage and known dispatch input, never from an unvalidated journal.
    return dispatched.received(source: staged, handle: handle);
  }

  List<Map<String, Object?>> authorizationMutations(
    String stagedRaw,
    OAuthOwnedPendingAuthorization received,
    Map<String, String> original,
  ) => [
    {'kind': 'set', 'key': 'flutter.$_pendingKey', 'value': preparedAttempt!.encode()},
    {'kind': 'set', 'key': 'flutter.$_pendingKey', 'value': preparedAttempt!.dispatched(
      fingerprint: received.codeFingerprint!,
      accountId: received.sourceAccountId!,
    ).encode()},
    {'kind': 'set', 'key': 'flutter.$_pendingKey', 'value': received.encode()},
    {'kind': 'set', 'key': 'flutter.$_accountsKey', 'value': stagedRaw},
    {'kind': 'set', 'key': 'flutter.$_accountsKey', 'value': original[_accountsKey]},
  ];

  Future<void> expectAuthorizationInventory(
    String accountsRaw,
    OAuthOwnedPendingAuthorization received,
    Map<String, String> original,
  ) async {
    await expectOAuthDisk({
      'flutter.${OAuthCalendarStorage.scopeOwnerKey}': lease.workspace.rawRecord,
      for (final entry in original.entries)
        'flutter.${entry.key}': entry.key == _accountsKey ? accountsRaw : entry.value,
      'flutter.$_pendingKey': received.encode(),
    });
    final actual = OAuthOwnedPendingAuthorization.parse(
      prefs.getString(_pendingKey)!, scope: scope,
    );
    expect(actual, isNotNull);
    expect(actual!.encode(), received.encode(), reason: 'complete received journal');
  }

  Future<void> readPeerRecovery(
    CalendarSyncProvider peer, {
    bool refreshing = false,
  }) async {
    final before = await store.oauthDisk();
    final attempts = store.attempts.toList();
    final requests = feed.requests.toList();
    final rows = _rows(peer);
    final titles = _titles(peer);
    if (refreshing) {
      final raw = before['flutter.${OAuthCalendarStorage.refreshJournalKey}'] as String;
      final expected = OAuthOwnedRefreshJournal.parse(raw, scope: scope);
      expect(expected, isNotNull);
      final recovery = await peer.loadOAuthRefreshRecovery().timeout(_wait);
      expect(recovery, isNotNull);
      expect(recovery!.sourceId, expected!.sourceAccountId);
      expect(recovery.phase, expected.phase);
    } else {
      final raw = before['flutter.$_pendingKey'] as String;
      final expected = OAuthOwnedPendingAuthorization.parse(raw, scope: scope);
      expect(expected, isNotNull);
      final snapshot = await peer.loadPendingOAuthAuthorization().timeout(_wait);
      expect(snapshot, {
        ...expected!.draft,
        'attemptId': expected.attemptId,
        'savedAt': expected.savedAt.toIso8601String(),
        'phase': expected.phase.name,
      });
    }
    expect(store.attempts, attempts, reason: 'public recovery read writes nothing');
    await expectOAuthDisk(before);
    expect(feed.requests, requests, reason: 'public recovery read makes zero HTTP');
    expect(_rows(peer), rows, reason: 'recovery read does not adopt credentials');
    expect(_titles(peer), titles);
  }

  Future<void> expectRaw(Map<String, String> raw) async {
    final disk = await store.getAll();
    for (final entry in raw.entries) {
      expect(
        disk['flutter.${entry.key}'],
        entry.value,
        reason: 'backing bytes',
      );
    }
    await prefs.reload();
    for (final entry in raw.entries) {
      expect(prefs.getString(entry.key), entry.value, reason: 'reloaded bytes');
    }
  }

  Future<void> expectAcceptedAccount(
    OAuthCalendarAccount account,
    List<Map<String, dynamic>> originalRows,
  ) async {
    final disk = await store.getAll();
    final raw = disk['flutter.$_accountsKey']! as String;
    final records = sourceRecords(raw);
    final rows = accountRows(raw);
    expect(rows.where((row) => row['id'] == account.id), hasLength(1));
    expect(
      rows.singleWhere((row) => row['id'] == account.id),
      account.toJson(),
    );
    final replaced = originalRows.any((row) => row['id'] == account.id);
    expect(rows, hasLength(originalRows.length + (replaced ? 0 : 1)));
    for (final previous in originalRows) {
      if (previous['id'] == account.id) continue;
      expect(
        rows.singleWhere((row) => row['id'] == previous['id']),
        previous,
        reason: 'unrelated confirmed row preserved',
      );
      expect(
        records.singleWhere((row) => row.account['id'] == previous['id']).encode(),
        seedSources.singleWhere((row) => row.account['id'] == previous['id']).encode(),
        reason: 'unrelated complete owned envelope preserved',
      );
    }
    await prefs.reload();
    expect(
      prefs.getString(_accountsKey),
      raw,
      reason: 'authoritative readback',
    );
    final cacheBytes = seedCacheRaw;
    expect(
      disk['flutter.$_cacheKey'],
      cacheBytes,
      reason: 'local recovery preserves backing cache bytes',
    );
    expect(
      prefs.getString(_cacheKey),
      cacheBytes,
      reason: 'local recovery preserves reloaded cache bytes',
    );
    expect(
      feed.count('events'),
      0,
      reason: 'local receipt retry does not fetch events',
    );
  }

  Future<void> close() async {
    feed.releaseAll();
    store.releaseAll();
    try {
      await Future.wait(pending).timeout(_wait);
      await AccountPreferenceWrites.drain().timeout(_wait);
    } finally {
      store.discardPlans();
      for (final value in providers) {
        disposeProvider(value);
      }
      auth.dispose();
      try {
        await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
      } finally {
        client.close();
        SharedPreferences.setMockInitialValues(<String, Object>{});
        SharedPreferencesStorePlatform.instance = previousStore;
      }
    }
  }
}

class _ResponseStep {
  _ResponseStep(this.hold, this.tokenPayload, this.expectedRefreshToken);
  final bool hold;
  final Map<String, Object?>? tokenPayload;
  final String? expectedRefreshToken;
  final started = Completer<void>();
  final release = Completer<void>();
}

class _OAuthFeed {
  final requests = <String>[];
  final replayedCodes = <String>[];
  final _consumedCodes = <String>{};
  final _plans = <String, List<_ResponseStep>>{};
  final _all = <_ResponseStep>[];

  _ResponseStep plan(
    String kind, {
    bool hold = false,
    Map<String, Object?>? tokenPayload,
    String? expectedRefreshToken,
  }) {
    final step = _ResponseStep(hold, tokenPayload, expectedRefreshToken);
    _plans.putIfAbsent(kind, () => []).add(step);
    _all.add(step);
    return step;
  }

  int count(String kind) => requests.where((item) => item == kind).length;

  Future<http.Response> respond(http.Request request) async {
    final isToken =
        request.method == 'POST' && request.url.path.endsWith('/token');
    expect(
      request.url.host,
      isToken ? 'oauth2.googleapis.com' : 'www.googleapis.com',
    );
    final kind = isToken
        ? request.bodyFields['grant_type'] == 'authorization_code'
              ? 'exchange'
              : 'refresh'
        : 'events';
    requests.add(kind);
    final queue = _plans[kind];
    final step = queue == null || queue.isEmpty ? null : queue.removeAt(0);
    if (kind == 'exchange') {
      final code = request.bodyFields['code']!;
      if (!_consumedCodes.add(code)) {
        replayedCodes.add(code);
        return _jsonResponse({'error': 'invalid_grant'}, 400);
      }
    } else if (kind == 'refresh') {
      expect(
        request.bodyFields['refresh_token'],
        step?.expectedRefreshToken ?? 'synthetic-old-refresh',
      );
    } else {
      expect(request.method, 'GET');
      expect(request.headers['Authorization'], startsWith('Bearer synthetic-'));
    }
    if (step != null) {
      step.started.complete();
      if (step.hold) await step.release.future;
    }
    return _jsonResponse(
      isToken
          ? step?.tokenPayload ??
                <String, Object?>{
                  'access_token': _newAccess,
                  'refresh_token': _newRefresh,
                  'expires_in': 3600,
                  'token_type': 'Bearer',
                }
          : <String, Object?>{'items': <Object>[]},
      200,
    );
  }

  void releaseAll() {
    for (final step in _all) {
      if (!step.release.isCompleted) step.release.complete();
    }
  }
}

http.Response _jsonResponse(Map<String, Object?> payload, int status) =>
    http.Response(
      jsonEncode(payload),
      status,
      headers: const {'content-type': 'application/json'},
    );

enum _WriteEffect {
  accept,
  returnsFalse,
  persistThenFalse,
  throwsError,
  ackWithoutPersist,
}

class _WriteStep {
  _WriteStep(this.effect, this.hold, this.persistBeforeAck);
  final _WriteEffect effect;
  final bool hold;
  final bool persistBeforeAck;
  final started = Completer<void>();
  final release = Completer<void>();
  String? value;

  Map<String, dynamic> accountRow(String displayName, OAuthScopedOwnerRecord scope) {
    final rows = OAuthOwnedSourceRecord.parseList(value!, scope: scope);
    expect(rows, isNotNull, reason: 'original complete staged source list');
    return Map<String, dynamic>.from(
      rows!.singleWhere((row) => row.account['displayName'] == displayName).account,
    );
  }
}

class _OAuthStore extends InMemorySharedPreferencesStore {
  _OAuthStore() : super.withData(<String, Object>{});
  final attempts = <String>[];
  final mutations = <Map<String, Object?>>[];
  final accountWrites = <String>[];
  final _plans = <String, List<_WriteStep>>{};
  final _all = <_WriteStep>[];

  _WriteStep plan(
    String kind,
    String key,
    _WriteEffect effect, {
    bool hold = false,
    bool persistBeforeAck = false,
  }) {
    final step = _WriteStep(effect, hold, persistBeforeAck);
    _plans.putIfAbsent('$kind:flutter.$key', () => []).add(step);
    _all.add(step);
    return step;
  }

  Future<Map<String, Object>> oauthDisk() async => {
    for (final entry in (await getAll()).entries)
      if (entry.key.startsWith('flutter.duoyi_oauth_calendar_'))
        entry.key: entry.value,
  };

  Future<bool> _perform(
    String kind,
    String key,
    Object? value,
    Future<bool> Function() persist,
  ) async {
    final id = '$kind:$key';
    attempts.add(id);
    mutations.add({'kind': kind, 'key': key, 'value': value});
    if (kind == 'set' && key == 'flutter.$_accountsKey') {
      accountWrites.add(value! as String);
    }
    final queue = _plans[id];
    if (queue == null || queue.isEmpty) return persist();
    final step = queue.removeAt(0);
    step.value = value as String?;
    final persisted = step.persistBeforeAck ? await persist() : null;
    step.started.complete();
    if (step.hold) await step.release.future;
    if (step.effect == _WriteEffect.throwsError) {
      throw StateError('Synthetic OAuth persistence failure');
    }
    if (step.effect == _WriteEffect.returnsFalse) return false;
    if (step.effect == _WriteEffect.ackWithoutPersist) return true;
    final accepted = persisted ?? await persist();
    return step.effect == _WriteEffect.persistThenFalse ? false : accepted;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) =>
      _perform('set', key, value, () => super.setValue(type, key, value));

  @override
  Future<bool> remove(String key) =>
      _perform('remove', key, null, () => super.remove(key));

  void releaseAll() {
    for (final step in _all) {
      if (!step.release.isCompleted) step.release.complete();
    }
  }

  void discardPlans() {
    releaseAll();
    _plans.clear();
  }
}
