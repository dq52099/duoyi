// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/core/oauth_pending_authorization.dart';
import 'package:duoyi/core/oauth_refresh_journal.dart';
import 'package:duoyi/core/oauth_calendar_workspace_codec.dart';
import 'package:duoyi/core/oauth_calendar_storage.dart';
import 'package:duoyi/core/ics_subscription_storage.dart';
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
const _journalKey = OAuthCalendarStorage.refreshJournalKey;
const _fenceKey = OAuthCalendarStorage.retirementFenceKey;
const _wait = Duration(seconds: 4);
const _oldTitle = 'Confirmed OAuth calendar event';
const _newTitle = 'Fetched OAuth calendar event';
const _codeVerifier =
    'synthetic-code-verifier-0123456789-ABCDEFGHIJKLMNOPQRSTUVWXYZ';

// Real-provider contract tests: the current unsafe OAuth implementation is
// expected to fail. HTTP injection uses the existing public package:http zone
// API and fresh MockClient instances, without subclassing provider methods.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;

  setUp(() async {
    f = await _Fixture.create();
  });
  tearDown(() async {
    await f.close();
  });

  for (final boundary in ['clear', 'failed clear', 'reset', 'dispose']) {
    test(
      'held authorization response cannot commit after $boundary',
      () => f.withHttp(() async {
        await f.seed();
        await f.savePending();
        final token = f.feed.plan('exchange', hold: true);
        final connecting = f.capture(f.connect());
        await token.started.future.timeout(_wait);
        final generation = AccountLocalDataCleaner.accountDataGeneration;
        final epoch = IcsSubscriptionStorage.epoch;

        if (boundary == 'failed clear') {
          f.store.plan('remove', _accountsKey, _WriteEffect.returnsFalse);
          expect(
            await f
                .capture(AccountLocalDataCleaner.clearSharedPreferences())
                .timeout(_wait),
            isA<StateError>(),
          );
          expect(IcsSubscriptionStorage.epoch, epoch);
          expect(
            AccountLocalDataCleaner.accountDataGeneration,
            greaterThan(generation),
          );
        } else if (boundary == 'clear') {
          expect(
            await f
                .capture(AccountLocalDataCleaner.clearSharedPreferences())
                .timeout(_wait),
            isNull,
          );
        } else if (boundary == 'reset') {
          f.provider.resetLocalState();
        } else {
          f.disposeProvider(f.provider);
        }
        final diskAtBoundary = await f.store.oauthDisk();
        final rowsAtBoundary = _rows(f.provider);
        final titlesAtBoundary = _titles(f.provider);
        final attemptsAtBoundary = f.store.attempts.toList();
        var notifications = 0;
        if (boundary != 'dispose') {
          f.provider.addListener(() => notifications++);
        }

        token.release.complete();
        expect(
          await connecting.timeout(_wait),
          isA<AccountPreferenceWriteCanceled>(),
        );
        expect(f.feed.count('exchange'), 1);
        expect(f.feed.count('events'), 0);
        expect(f.store.attempts, attemptsAtBoundary);
        expect(await f.store.oauthDisk(), diskAtBoundary);
        expect(_rows(f.provider), rowsAtBoundary);
        expect(_titles(f.provider), titlesAtBoundary);
        expect(notifications, 0);
        expect(f.provider.lastError, isNull);
      }),
    );
  }

  for (final status in [200, 500]) {
    test(
      'held calendar HTTP $status cannot publish after direct cleanup',
      () => f.withHttp(() async {
        await f.seed();
        final response = f.feed.plan('events', hold: true, status: status);
        final syncing = f.capture(f.provider.syncAll());
        await response.started.future.timeout(_wait);
        expect(
          await f
              .capture(AccountLocalDataCleaner.clearSharedPreferences())
              .timeout(_wait),
          isNull,
        );
        final attemptsAfterClear = f.store.attempts.toList();
        final titlesAfterClear = _titles(f.provider);
        var notifications = 0;
        f.provider.addListener(() => notifications++);

        response.release.complete();
        expect(await syncing.timeout(_wait), isNull);
        expect(f.feed.count('events'), 1);
        expect(f.store.attempts, attemptsAfterClear);
        expect(await f.store.oauthDisk(), isEmpty);
        expect(_titles(f.provider), titlesAfterClear);
        expect(f.provider.lastError, isNull);
        expect(f.provider.isSyncing, isFalse);
        expect(notifications, 0);
      }),
    );
  }

  test(
    'confirmed refresh blocks ordinary remove then permits settled removal',
    () => f.withHttp(() async {
      final original = await f.seed(expired: true);
      final before = await f.store.getAll();
      final opening = f.provider.oauthAccounts.single;
      final revision = OAuthCalendarStorage.sourceRevision(opening.id);
      final began = DateTime.now().toUtc();
      final response = f.feed.plan('refresh', hold: true);
      final syncing = f.capture(f.provider.syncAll());
      await response.started.future.timeout(_wait);
      final claim = await f.expectRefreshClaim(original, notBefore: began);
      final claimedDisk = <String, Object>{
        ...before, 'flutter.$_journalKey': claim.encode(),
      };
      final claimedWrites = <Map<String, Object?>>[
        {'kind': 'set', 'key': 'flutter.$_journalKey', 'value': claim.encode()},
      ];
      await f.expectCompleteDisk(claimedDisk);
      f.expectMutationSequence(claimedWrites);
      expect(f.feed.requests, ['refresh']);
      expect(f.feed.replayedCodes, isEmpty);
      expect(_rows(f.provider), [opening.toJson()]);
      expect(_titles(f.provider), [_oldTitle]);
      expect(OAuthCalendarStorage.ownsRequest(opening.id, 1), isTrue);
      expect(OAuthCalendarStorage.sourceRevision(opening.id), revision);
      expect(f.auth.isOAuthScopeLeaseCurrent(f.lease), isTrue);
      expect(f.provider.isSyncing, isTrue);
      expect(f.provider.lastError, isNull);

      var notifications = 0;
      void listener() => notifications++;
      f.provider.addListener(listener);
      final refused = await f.capture(f.provider.removeOAuthAccount(
        opening.id, expectedAccount: opening,
      )).timeout(_wait);
      expect(refused, isA<OAuthRefreshDispatchUnknown>());
      expect(refused.toString(), 'OAuth refresh outcome requires explicit reconnect');
      final recovery = await f.provider.loadOAuthRefreshRecovery().timeout(_wait);
      expect(recovery!.sourceId, opening.id);
      expect(recovery.phase, OAuthRefreshPhase.dispatched);
      expect(f.provider.oauthLocalCommitReceipts, isEmpty);
      await f.expectCompleteDisk(claimedDisk);
      f.expectMutationSequence(claimedWrites);
      expect(f.feed.requests, ['refresh']);
      expect(_rows(f.provider), [opening.toJson()]);
      expect(_titles(f.provider), [_oldTitle]);
      expect(OAuthCalendarStorage.sourceRevision(opening.id), revision);
      expect(OAuthCalendarStorage.ownsRequest(opening.id, 1), isTrue);
      expect(f.auth.isOAuthScopeLeaseCurrent(f.lease), isTrue);
      expect(notifications, 0);
      expect(f.provider.isSyncing, isTrue);
      expect(f.provider.lastError, isNull);
      f.provider.removeListener(listener);

      // Gate the actual received write before ACK or credential installation.
      final receivedWrite = f.store.plan(
        'set', _journalKey, _WriteEffect.accept, hold: true,
      );
      final released = DateTime.now().toUtc();
      response.release.complete();
      await receivedWrite.started.future.timeout(_wait);
      final received = f.expectedRefreshReceived(
        claim, receivedWrite.value!, notBefore: released,
      );
      expect(f.feed.requests, ['refresh']);
      await f.expectCompleteDisk(claimedDisk);
      expect(_rows(f.provider), [opening.toJson()]);
      expect(_titles(f.provider), [_oldTitle]);
      f.expectMutationSequence([
        ...claimedWrites,
        {'kind': 'set', 'key': 'flutter.$_journalKey', 'value': received.encode()},
      ]);
      receivedWrite.release.complete();
      expect(await syncing.timeout(_wait), isNull);
      final completed = DateTime.now();
      final actual = f.sourceRecords(f.prefs.getString(_accountsKey)!).single;
      final syncedAt = DateTime.parse(actual.account['lastSyncedAt'] as String);
      _expectTimeBetween(syncedAt, released, completed);
      final installed = received.returnedSource!;
      final expectedFinal = installed.withAccount({
        ...installed.account, 'lastSyncedAt': syncedAt.toIso8601String(),
      });
      final finalAccounts = jsonEncode([expectedFinal.toJson()]);
      final finalCache = OAuthOwnedEventsRecord.create(
        source: expectedFinal, events: [_expectedFetchedEvent()],
      ).encode();
      final completedWrites = <Map<String, Object?>>[
        ...claimedWrites,
        {'kind': 'set', 'key': 'flutter.$_journalKey', 'value': received.encode()},
        {'kind': 'set', 'key': 'flutter.$_accountsKey',
          'value': jsonEncode([installed.toJson()])},
        {'kind': 'remove', 'key': 'flutter.$_journalKey', 'value': null},
        {'kind': 'set', 'key': 'flutter.$_cacheKey', 'value': finalCache},
        {'kind': 'set', 'key': 'flutter.$_accountsKey', 'value': finalAccounts},
      ];
      f.expectMutationSequence(completedWrites);
      await f.expectCompleteDisk({
        ...before,
        'flutter.$_accountsKey': finalAccounts,
        'flutter.$_cacheKey': finalCache,
      });
      expect(actual.encode(), expectedFinal.encode());
      expect(_rows(f.provider), [expectedFinal.account]);
      expect(_titles(f.provider), [_newTitle]);
      expect(f.feed.requests, ['refresh', 'events']);
      expect(f.feed.replayedCodes, isEmpty);
      expect(f.provider.oauthLocalCommitReceipts, isEmpty);
      expect(f.provider.isSyncing, isFalse);
      expect(f.provider.lastError, isNull);
      expect(OAuthCalendarStorage.failure, isNull);
      expect(OAuthCalendarStorage.sourceRevision(opening.id), revision);
      expect(OAuthCalendarStorage.ownsRequest(opening.id, 1), isTrue);

      // Preserve successful deletion once the original refresh journal is settled.
      expect(await f.capture(f.provider.removeOAuthAccount(
        opening.id, expectedAccount: f.provider.oauthAccounts.single,
      )).timeout(_wait), isNull);
      f.expectMutationSequence([
        ...completedWrites,
        {'kind': 'set', 'key': 'flutter.$_accountsKey', 'value': '[]'},
        {'kind': 'remove', 'key': 'flutter.$_cacheKey', 'value': null},
      ]);
      await f.expectCompleteDisk({
        for (final entry in before.entries)
          if (entry.key != 'flutter.$_cacheKey' &&
              entry.key != 'flutter.$_accountsKey') entry.key: entry.value,
        'flutter.$_accountsKey': '[]',
      });
      expect(OAuthCalendarStorage.sourceRevision(opening.id), revision + 1);
      expect(OAuthCalendarStorage.ownsRequest(opening.id, 1), isTrue);
      expect(f.provider.oauthAccounts, isEmpty);
      expect(f.provider.allEvents(), isEmpty);
      expect(f.provider.oauthLocalCommitReceipts, isEmpty);
      expect(f.feed.requests, ['refresh', 'events']);
      expect(f.provider.lastError, isNull);
      expect(f.provider.isSyncing, isFalse);
    }),
  );

  test(
    'removing an account cancels its held events continuation',
    () => f.withHttp(() async {
      await f.seed();
      final response = f.feed.plan('events', hold: true);
      final syncing = f.capture(f.provider.syncAll());
      await response.started.future.timeout(_wait);
      expect(
        await f
            .capture(f.provider.removeOAuthAccount('existing'))
            .timeout(_wait),
        isNull,
      );
      expect(f.provider.oauthAccounts, isEmpty);
      final attemptsAfterRemove = f.store.attempts.toList();

      response.release.complete();
      expect(await syncing.timeout(_wait), isNull);
      expect(f.provider.oauthAccounts, isEmpty);
      expect(f.provider.allEvents(), isEmpty);
      expect(f.store.attempts, attemptsAfterRemove);
      expect((await f.store.getAll())['flutter.$_cacheKey'], isNull);
      expect(
        jsonDecode(
          (await f.store.getAll())['flutter.$_accountsKey'] as String,
        ),
        isEmpty,
      );
      expect(f.provider.lastError, isNull);
    }),
  );

  for (final failed in [false, true]) {
    test(
      'held refresh cannot write after explicit ${failed ? 'failed ' : ''}cleanup',
      () => f.withHttp(() async {
        final original = await f.seed(expired: true);
        final before = await f.store.getAll();
        final began = DateTime.now().toUtc();
        final response = f.feed.plan('refresh', hold: true);
        final syncing = f.capture(f.provider.syncAll());
        await response.started.future.timeout(_wait);
        final claim = await f.expectRefreshClaim(original, notBefore: began);
        final claimedDisk = <String, Object>{
          ...before, 'flutter.$_journalKey': claim.encode(),
        };
        await f.expectCompleteDisk(claimedDisk);
        final revision = OAuthCalendarStorage.sourceRevision('existing');
        expect(OAuthCalendarStorage.ownsRequest('existing', 1), isTrue);
        final epoch = OAuthCalendarStorage.epoch;
        final icsEpoch = IcsSubscriptionStorage.epoch;
        final reset = OAuthCalendarStorage.resetRevision;
        final generation = AccountLocalDataCleaner.accountDataGeneration;
        final ownerAck = f.store.plan(
          'remove', AccountLocalDataCleaner.accountDataOwnerKey,
          _WriteEffect.accept, hold: true,
        );
        if (failed) {
          f.store.plan('remove', _accountsKey, _WriteEffect.returnsFalse);
        }
        final clearing = f.capture(AccountLocalDataCleaner.clearSharedPreferences());
        await ownerAck.started.future.timeout(_wait);
        final fenceRaw = f.expectedRetirementFence(f.store.mutations[1]['value'] as String);
        await f.expectCompleteDisk({
          ...claimedDisk, 'flutter.$_fenceKey': fenceRaw,
        });
        f.expectMutationSequence([
          {'kind': 'set', 'key': 'flutter.$_journalKey', 'value': claim.encode()},
          {'kind': 'set', 'key': 'flutter.$_fenceKey', 'value': fenceRaw},
          {'kind': 'remove',
            'key': 'flutter.${AccountLocalDataCleaner.accountDataOwnerKey}', 'value': null},
        ]);
        expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isTrue);
        expect(OAuthCalendarStorage.epoch, epoch);
        expect(IcsSubscriptionStorage.epoch, icsEpoch);
        expect(f.feed.requests, ['refresh']);
        ownerAck.release.complete();
        final cleanupError = await clearing.timeout(_wait);
        expect(
          cleanupError,
          failed
              ? isA<StateError>().having((error) => error.message,
                  'checked cleanup message', 'Account preference cleanup failed: $_accountsKey')
              : isNull,
        );
        final cleanupWrites = <Map<String, Object?>>[
          {'kind': 'set', 'key': 'flutter.$_journalKey', 'value': claim.encode()},
          ...f.expectedCleanupWrites(fenceRaw, failed: failed),
        ];
        final remaining = <String, Object>{
          for (final entry in before.entries)
            if (entry.key != 'flutter.${AccountLocalDataCleaner.accountDataOwnerKey}' &&
                !entry.key.startsWith('flutter.duoyi_oauth_calendar_'))
              entry.key: entry.value,
          if (failed) ...{
            'flutter.$_accountsKey': original[_accountsKey]!,
            'flutter.$_fenceKey': fenceRaw,
          },
        };
        await f.expectCompleteDisk(remaining);
        f.expectMutationSequence(cleanupWrites);
        expect(OAuthCalendarStorage.epoch, epoch + (failed ? 0 : 1));
        expect(IcsSubscriptionStorage.epoch, icsEpoch + (failed ? 0 : 1));
        expect(OAuthCalendarStorage.resetRevision, reset + (failed ? 0 : 1));
        expect(AccountLocalDataCleaner.accountDataGeneration, greaterThan(generation));
        expect(f.auth.isOAuthScopeLeaseCurrent(f.lease), isFalse);
        expect(f.provider.isOAuthReady, isFalse);
        expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), failed);
        expect(f.provider.oauthAccounts, isEmpty);
        expect(f.provider.allEvents(), isEmpty);
        expect(f.provider.oauthLocalCommitReceipts, isEmpty);
        expect(OAuthCalendarStorage.failure, isNull);
        var notifications = 0;
        void listener() => notifications++;
        f.provider.addListener(listener);
        response.release.complete();
        expect(await syncing.timeout(_wait), isNull);
        await f.expectCompleteDisk(remaining);
        f.expectMutationSequence(cleanupWrites);
        expect(f.feed.requests, ['refresh']);
        expect(f.feed.replayedCodes, isEmpty);
        expect(f.provider.oauthAccounts, isEmpty);
        expect(f.provider.allEvents(), isEmpty);
        expect(f.provider.oauthLocalCommitReceipts, isEmpty);
        expect(f.provider.lastError, isNull);
        expect(f.provider.isSyncing, isFalse);
        expect(notifications, 0);
        expect(OAuthCalendarStorage.sourceRevision('existing'), failed ? revision : 0);
        expect(OAuthCalendarStorage.ownsRequest('existing', 1), failed);
        expect(OAuthCalendarStorage.failure, isNull);
        f.provider.removeListener(listener);
        if (failed) {
          expect(
            () => OAuthCalendarStorage.ensureAccountAdmissionLocked(f.prefs),
            throwsA(isA<OAuthAccountRetirementPending>()),
          );
          final retryArm = f.store.plan(
            'set', _fenceKey, _WriteEffect.accept, hold: true,
          );
          final retrying = f.capture(AccountLocalDataCleaner.clearSharedPreferences());
          await retryArm.started.future.timeout(_wait);
          final retryFence = f.expectedRetirementFence(retryArm.value!);
          expect(retryFence, isNot(fenceRaw));
          await f.expectCompleteDisk(remaining);
          f.expectMutationSequence([
            ...cleanupWrites,
            {'kind': 'set', 'key': 'flutter.$_fenceKey', 'value': retryFence},
          ]);
          expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isTrue);
          retryArm.release.complete();
          expect(await retrying.timeout(_wait), isNull);
          f.expectMutationSequence([
            ...cleanupWrites,
            {'kind': 'set', 'key': 'flutter.$_fenceKey', 'value': retryFence},
            {'kind': 'remove', 'key': 'flutter.$_accountsKey', 'value': null},
            {'kind': 'remove', 'key': 'flutter.$_fenceKey', 'value': null},
          ]);
          await f.expectCompleteDisk({
            for (final entry in remaining.entries)
              if (entry.key != 'flutter.$_accountsKey' &&
                  entry.key != 'flutter.$_fenceKey') entry.key: entry.value,
          });
          expect(OAuthCalendarStorage.epoch, epoch + 1);
          expect(IcsSubscriptionStorage.epoch, icsEpoch + 1);
          expect(OAuthCalendarStorage.resetRevision, reset + 1);
          expect(OAuthCalendarStorage.ownsRequest('existing', 1), isFalse);
          expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isFalse);
          expect(f.feed.requests, ['refresh']);
          await f.expectFreshAuthorizationAfterClear();
        }
      }),
    );
  }

  test(
    'direct cleanup drains an issued pending authorization acknowledgement',
    () async {
      final write = f.store.plan(
        'set',
        _pendingKey,
        _WriteEffect.accept,
        hold: true,
      );
      final saving = f.capture(f.savePending());
      await write.started.future.timeout(_wait);
      var cleaned = false;
      final cleanup = f.capture(
        AccountLocalDataCleaner.clearSharedPreferences().then((_) {
          cleaned = true;
        }),
      );
      final attemptsAtBoundary = f.store.attempts.toList();
      await _settleReadyWork();
      expect(cleaned, isFalse);
      expect(f.store.attempts, attemptsAtBoundary);

      write.release.complete();
      expect(
        await saving.timeout(_wait),
        isA<AccountPreferenceWriteCanceled>(),
      );
      expect(await cleanup.timeout(_wait), isNull);
      expect(cleaned, isTrue);
      expect(await f.store.oauthDisk(), isEmpty);
      await f.prefs.reload();
      expect(f.prefs.containsKey(_pendingKey), isFalse);
    },
  );

  test(
    'direct cleanup drains issued calendar cache without publishing its rows',
    () => f.withHttp(() async {
      await f.seed();
      final write = f.store.plan(
        'set',
        _cacheKey,
        _WriteEffect.accept,
        hold: true,
      );
      final syncing = f.capture(f.provider.syncAll());
      await write.started.future.timeout(_wait);
      expect(_titles(f.provider), [_oldTitle]);
      var cleaned = false;
      final cleanup = f.capture(
        AccountLocalDataCleaner.clearSharedPreferences().then((_) {
          cleaned = true;
        }),
      );
      final attemptsAtBoundary = f.store.attempts.toList();
      await _settleReadyWork();
      expect(cleaned, isFalse);
      expect(f.store.attempts, attemptsAtBoundary);

      write.release.complete();
      expect(await syncing.timeout(_wait), isNull);
      expect(await cleanup.timeout(_wait), isNull);
      expect(f.provider.isSyncing, isFalse);
      expect(_titles(f.provider), isNot(contains(_newTitle)));
      expect(f.provider.lastError, isNull);
      expect(await f.store.oauthDisk(), isEmpty);
      await f.prefs.reload();
      expect(f.prefs.containsKey(_cacheKey), isFalse);
    }),
  );

  test(
    'direct cleanup drains issued account commit and suppresses its event fetch',
    () => f.withHttp(() async {
      final write = f.store.plan(
        'set',
        _accountsKey,
        _WriteEffect.accept,
        hold: true,
      );
      await f.savePending();
      final connecting = f.capture(f.connect());
      await write.started.future.timeout(_wait);
      expect(f.provider.oauthAccounts, isEmpty);
      var cleaned = false;
      final cleanup = f.capture(
        AccountLocalDataCleaner.clearSharedPreferences().then((_) {
          cleaned = true;
        }),
      );
      final attemptsAtBoundary = f.store.attempts.toList();
      await _settleReadyWork();
      expect(cleaned, isFalse);
      expect(f.store.attempts, attemptsAtBoundary);

      write.release.complete();
      expect(
        await connecting.timeout(_wait),
        isA<AccountPreferenceWriteCanceled>(),
      );
      expect(await cleanup.timeout(_wait), isNull);
      expect(f.provider.oauthAccounts, isEmpty);
      expect(f.provider.allEvents(), isEmpty);
      expect(f.feed.count('exchange'), 1);
      expect(f.feed.count('events'), 0);
      expect(await f.store.oauthDisk(), isEmpty);
    }),
  );

  for (final effect in _failedWrites) {
    test(
      'connect ${effect.name} keeps confirmed credentials and never replays code',
      () => f.withHttp(() async {
        final original = await f.seed();
        await f.savePending();
        // The credential rollback must retain the exact received claim.
        final rows = _rows(f.provider);
        final titles = _titles(f.provider);
        final write = f.store.plan('set', _accountsKey, effect, hold: true);
        final connecting = f.capture(f.connect());
        await write.started.future.timeout(_wait);

        expect(_rows(f.provider), rows, reason: 'unpublished token candidate');
        expect(_titles(f.provider), titles);
        expect(f.feed.count('exchange'), 1);
        expect(f.feed.count('events'), 0);
        write.release.complete();
        expect(await connecting.timeout(_wait), _storageFailure);
        await _settleReadyWork();
        expect(
          f.feed.count('exchange'),
          1,
          reason: 'authorization code consumed',
        );
        expect(f.feed.replayedCodes, isEmpty);
        expect(f.feed.count('events'), 0);
        expect(_rows(f.provider), rows);
        expect(_titles(f.provider), titles);
        await f.expectRaw(original);
        await f.expectReceivedAuthorization(write, original);
      }),
    );
  }

  for (final effect in _failedWrites) {
    test(
      'calendar cache ${effect.name} retains cache and timestamp then permits retry',
      () => f.withHttp(() async {
        final original = await f.seed();
        final originalRows = _rows(f.provider);
        final write = f.store.plan('set', _cacheKey, effect, hold: true);
        final syncing = f.capture(f.provider.syncAll());
        await write.started.future.timeout(_wait);
        expect(_titles(f.provider), [_oldTitle]);
        expect(_rows(f.provider), originalRows);

        write.release.complete();
        expect(await syncing.timeout(_wait), isNull);
        expect(f.provider.isSyncing, isFalse);
        expect(f.provider.lastError, isNotNull);
        expect(_titles(f.provider), [_oldTitle]);
        expect(_rows(f.provider), originalRows);
        expect(f.feed.count('refresh'), 0);
        await f.expectRaw(original);

        expect(await f.capture(f.provider.syncAll()).timeout(_wait), isNull);
        expect(f.feed.count('events'), 2);
        expect(f.provider.isSyncing, isFalse);
        expect(f.provider.lastError, isNull);
        expect(_titles(f.provider), [_newTitle]);
        expect(
          f.provider.oauthAccounts.single.lastSyncedAt,
          isNot(DateTime.utc(2026, 10, 1)),
        );
        await f.prefs.reload();
        final cached = f.eventRecord(
          f.prefs.getString(_cacheKey)!, f.prefs.getString(_accountsKey)!);
        expect(cached.events.single['title'], _newTitle);
        final accounts = f.accountRows(f.prefs.getString(_accountsKey)!);
        expect(
          accounts.single['lastSyncedAt'],
          f.provider.oauthAccounts.single.lastSyncedAt!.toIso8601String(),
        );
      }),
    );
  }

  test(
    'rotated refresh token must commit before requesting calendar events',
    () => f.withHttp(() async {
      final original = await f.seed(expired: true);
      final rows = _rows(f.provider);
      f.store.plan('set', _accountsKey, _WriteEffect.returnsFalse);
      expect(await f.capture(f.provider.syncAll()).timeout(_wait), isNull);
      expect(f.feed.count('refresh'), 1);
      expect(f.feed.count('exchange'), 0);
      expect(f.feed.count('events'), 0);
      expect(f.provider.isSyncing, isFalse);
      expect(f.provider.lastError, isNotNull);
      expect(_rows(f.provider), rows);
      expect(_titles(f.provider), [_oldTitle]);
      await f.expectRaw(original);
    }),
  );

  test(
    'successful token HTTP status without access token cannot connect',
    () => f.withHttp(() async {
      f.feed.plan(
        'exchange',
        payload: {'refresh_token': 'synthetic-refresh', 'expires_in': 3600},
      );
      await f.savePending();
      expect(await f.capture(f.connect()).timeout(_wait), _storageFailure);
      expect(f.feed.count('exchange'), 1);
      expect(f.feed.count('events'), 0);
      expect(f.provider.oauthAccounts, isEmpty);
      expect(f.provider.allEvents(), isEmpty);
      await f.expectDispatchedAuthorizationOnly();
    }),
  );

  test(
    'cold OAuth connect retains another providers confirmed account row',
    () => f.withHttp(() async {
      await f.seed();
      final peer = f.newProvider();
      expect(peer.oauthAccounts, isEmpty);
      await f.savePending(provider: peer);
      expect(await f.capture(f.connect(provider: peer)).timeout(_wait), isNull);
      final disk = f.accountRows(f.prefs.getString(_accountsKey)!);
      expect(disk, hasLength(2));
      expect(disk.map((row) => row['id']), contains('existing'));
      expect(peer.oauthAccounts, hasLength(2));
      expect(_titles(peer), containsAll([_oldTitle, _newTitle]));
      expect(f.feed.count('exchange'), 1);
    }),
  );
}

const _failedWrites = <_WriteEffect>[
  _WriteEffect.returnsFalse,
  _WriteEffect.persistThenFalse,
  _WriteEffect.throwsError,
  _WriteEffect.ackWithoutPersist,
];

final _storageFailure = allOf(
  isNotNull,
  isNot(isA<AccountPreferenceWriteCanceled>()),
);

Future<void> _settleReadyWork() => Future<void>(() {});

List<Map<String, dynamic>> _rows(CalendarSyncProvider provider) =>
    provider.oauthAccounts.map((row) => row.toJson()).toList();
List<String> _titles(CalendarSyncProvider provider) =>
    provider.allEvents().map((event) => event.title).toList();

OAuthCalendarAccount _account({bool expired = false}) => OAuthCalendarAccount(
  id: 'existing',
  provider: OAuthCalendarProvider.google,
  displayName: 'Confirmed OAuth account',
  clientId: 'synthetic-client',
  redirectUri: 'duoyi://oauth/calendar',
  accessToken: 'synthetic-old-access',
  refreshToken: 'synthetic-old-refresh',
  expiresAt: expired ? DateTime.utc(2000) : DateTime.utc(2099),
  lastSyncedAt: DateTime.utc(2026, 10, 1),
);

void _expectTimeBetween(DateTime value, DateTime lower, DateTime upper) {
  expect(value.isBefore(lower), isFalse);
  expect(value.isAfter(upper), isFalse);
}

Map<String, Object?> _expectedFetchedEvent({String accountId = 'existing'}) => {
  'id': 'oauth_google_${accountId}_fetched',
  'title': _newTitle,
  'date': DateTime.parse('2026-11-09T11:00:00.000Z').toLocal().toIso8601String(),
  'endDate': DateTime.parse('2026-11-09T12:00:00.000Z').toLocal().toIso8601String(),
  'subtitle': 'Google Calendar',
  'colorValue': 0xFF5E97F6,
  'sourceId': null,
  'timeHour': DateTime.parse('2026-11-09T11:00:00.000Z').toLocal().hour,
  'timeMinute': DateTime.parse('2026-11-09T11:00:00.000Z').toLocal().minute,
};

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

class _Fixture {
  _Fixture(this.previousStore, this.store, this.prefs) {
    provider = newProvider();
  }

  final SharedPreferencesStorePlatform previousStore;
  final _OAuthStore store;
  final SharedPreferences prefs;
  // This fixture owns the issuer; every Calendar provider borrows it.
  final AuthProvider auth = AuthProvider();
  final extraIssuers = <AuthProvider>[];
  late final AuthOAuthScopeLease lease;
  late final OAuthScopedOwnerRecord scope;
  final seedSources = <OAuthOwnedSourceRecord>[];
  late final String seedCacheRaw;
  OAuthOwnedPendingAuthorization? preparedAttempt;
  final feed = _OAuthFeed();
  final pending = <Future<Object?>>[];
  final providers = <CalendarSyncProvider>[];
  final disposed = <CalendarSyncProvider>{};
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
    final next = CalendarSyncProvider(authProvider: auth);
    providers.add(next);
    return next;
  }

  void disposeProvider(CalendarSyncProvider value) {
    if (disposed.add(value)) value.dispose();
  }

  Future<Object?> capture(Future<dynamic> future) {
    final result = future.then<Object?>(
      (_) => null,
      onError: (Object error, StackTrace _) => error,
    );
    pending.add(result);
    return result;
  }

  Future<void> withHttp(Future<void> Function() body) =>
      http.runWithClient(body, () => MockClient(feed.respond));

  Future<OAuthCalendarAccount> connect({CalendarSyncProvider? provider}) =>
      (provider ?? this.provider).addOAuthAccountFromCode(
        provider: OAuthCalendarProvider.google,
        displayName: 'New OAuth account',
        clientId: 'synthetic-client',
        redirectUri: 'duoyi://oauth/calendar',
        authorizationCode: 'synthetic-single-use-code',
        codeVerifier: _codeVerifier,
        expectedAttemptId: preparedAttempt?.attemptId,
      );

  Future<void> savePending({CalendarSyncProvider? provider}) async {
    final snapshot = await (provider ?? this.provider).savePendingOAuthAuthorization(
      provider: OAuthCalendarProvider.google,
      displayName: 'New OAuth account',
      clientId: 'synthetic-client',
      clientSecret: '',
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
        'clientSecret': '',
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

  Future<Map<String, String>> seed({bool expired = false}) async {
    expect(seedSources, isEmpty, reason: 'mint each seed source once');
    seedSources.add(OAuthOwnedSourceRecord.create(
      scope: scope,
      account: _account(expired: expired).toJson(),
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
    await provider.loadFromStorage().timeout(_wait);
    expect(_titles(provider), [_oldTitle]);
    store.attempts.clear();
    store.mutations.clear();
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

  OAuthOwnedPendingAuthorization expectedDispatchedAuthorization(String raw) {
    final actual = OAuthOwnedPendingAuthorization.parse(raw, scope: scope);
    expect(actual, isNotNull, reason: 'canonical owned dispatch claim');
    expect(actual!.phase, OAuthPendingPhase.dispatched);
    expect(preparedAttempt, isNotNull);
    final expected = preparedAttempt!.dispatched(
      fingerprint: sha256.convert(utf8.encode(jsonEncode([
        preparedAttempt!.draft['provider'],
        'synthetic-client',
        'duoyi://oauth/calendar',
        'synthetic-single-use-code',
      ]))).toString(),
      accountId: actual.sourceAccountId!,
    );
    // Only the product-generated source ID is observed; every other field is
    // fixed by the independently read prepared attempt and known request code.
    expect(actual.encode(), expected.encode());
    return expected;
  }

  Future<void> expectDispatchedAuthorizationOnly() async {
    final raw = (await store.getAll())['flutter.$_pendingKey'] as String;
    final expected = expectedDispatchedAuthorization(raw);
    await expectOAuthDisk({
      'flutter.${OAuthCalendarStorage.scopeOwnerKey}': lease.workspace.rawRecord,
      'flutter.$_pendingKey': expected.encode(),
    });
    expect(store.mutations, [
      {'kind': 'set', 'key': 'flutter.$_pendingKey', 'value': preparedAttempt!.encode()},
      {'kind': 'set', 'key': 'flutter.$_pendingKey', 'value': expected.encode()},
    ], reason: 'exact prepared then dispatched writes; no credential/cache writes');
    expect(store.attempts, [
      'set:flutter.$_pendingKey', 'set:flutter.$_pendingKey',
    ]);
  }

  Future<void> expectReceivedAuthorization(
    _WriteStep write,
    Map<String, String> original,
  ) async {
    final dispatched = expectedDispatchedAuthorization(
      store.mutations[1]['value']! as String,
    );
    final staged = sourceRecords(write.value!)
        .singleWhere((row) => row.account['id'] == dispatched.sourceAccountId);
    expect(staged.account['accessToken'], 'synthetic-new-access');
    expect(staged.account['refreshToken'], 'synthetic-new-refresh');
    final receipt = provider.oauthLocalCommitReceipts.single;
    expect(receipt.isRefresh, isFalse);
    final expected = dispatched.received(source: staged, handle: receipt.handle);
    final pendingRaw = (await store.getAll())['flutter.$_pendingKey'] as String;
    final actual = OAuthOwnedPendingAuthorization.parse(pendingRaw, scope: scope);
    expect(actual, isNotNull);
    expect(actual!.encode(), expected.encode());
    await expectOAuthDisk({
      'flutter.${OAuthCalendarStorage.scopeOwnerKey}': lease.workspace.rawRecord,
      for (final entry in original.entries) 'flutter.${entry.key}': entry.value,
      'flutter.$_pendingKey': expected.encode(),
    });
    expect(store.mutations, [
      {'kind': 'set', 'key': 'flutter.$_pendingKey', 'value': preparedAttempt!.encode()},
      {'kind': 'set', 'key': 'flutter.$_pendingKey', 'value': dispatched.encode()},
      {'kind': 'set', 'key': 'flutter.$_pendingKey', 'value': expected.encode()},
      {'kind': 'set', 'key': 'flutter.$_accountsKey', 'value': write.value},
      if (write.effect == _WriteEffect.ackWithoutPersist) ...[
        {'kind': 'remove', 'key': 'flutter.$_pendingKey', 'value': null},
        {'kind': 'set', 'key': 'flutter.$_pendingKey', 'value': expected.encode()},
      ],
      {'kind': 'set', 'key': 'flutter.$_accountsKey', 'value': original[_accountsKey]},
    ], reason: 'exact claims and failed credential write/compensation');
    expect(store.attempts, [
      'set:flutter.$_pendingKey', 'set:flutter.$_pendingKey',
      'set:flutter.$_pendingKey', 'set:flutter.$_accountsKey',
      if (write.effect == _WriteEffect.ackWithoutPersist) ...[
        'remove:flutter.$_pendingKey', 'set:flutter.$_pendingKey',
      ],
      'set:flutter.$_accountsKey',
    ]);
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

  Future<void> expectCompleteDisk(Map<String, Object> expected) async {
    expect(await store.getAll(), expected, reason: 'complete platform backing');
    await prefs.reload();
    expect({
      for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!,
    }, expected, reason: 'complete authoritative reload');
  }

  void expectMutationSequence(List<Map<String, Object?>> expected) {
    expect(store.mutations, expected, reason: 'all kinds, keys, values and ordering');
    expect(store.attempts, [
      for (final row in expected) '${row['kind']}:${row['key']}',
    ]);
  }

  Future<OAuthOwnedRefreshJournal> expectRefreshClaim(
    Map<String, String> original, {required DateTime notBefore}
  ) async {
    final actual = OAuthOwnedRefreshJournal.parse(
      (await store.getAll())['flutter.$_journalKey'] as String, scope: scope,
    );
    expect(actual, isNotNull);
    expect(actual!.phase, OAuthRefreshPhase.dispatched);
    expect(actual.sourceAccountId, 'existing');
    expect(actual.receivedAt, isNull);
    expect(actual.returnedSource, isNull);
    _expectTimeBetween(actual.dispatchedAt, notBefore, DateTime.now().toUtc());
    final expected = OAuthOwnedRefreshJournal.createDispatched(
      scope: scope,
      operationId: actual.operationId,
      receiptHandle: actual.receiptHandle,
      originalSource: seedSources.single,
      dispatchedAt: actual.dispatchedAt,
    );
    expect(actual.encode(), expected.encode());
    await expectOAuthDisk({
      'flutter.${OAuthCalendarStorage.scopeOwnerKey}': lease.workspace.rawRecord,
      for (final entry in original.entries) 'flutter.${entry.key}': entry.value,
      'flutter.$_journalKey': expected.encode(),
    });
    return expected;
  }

  OAuthOwnedRefreshJournal expectedRefreshReceived(
    OAuthOwnedRefreshJournal claim, String raw, {required DateTime notBefore}
  ) {
    final actual = OAuthOwnedRefreshJournal.parse(raw, scope: scope);
    expect(actual, isNotNull);
    expect(actual!.phase, OAuthRefreshPhase.received);
    final expiry = DateTime.parse(actual.returnedSource!.account['expiresAt'] as String);
    expect(expiry.isUtc, isTrue);
    _expectTimeBetween(expiry, notBefore.add(const Duration(seconds: 3600)),
        DateTime.now().toUtc().add(const Duration(seconds: 3600)));
    _expectTimeBetween(actual.receivedAt!, notBefore, DateTime.now().toUtc());
    final expectedSource = claim.originalSource.withAccount({
      ...claim.originalSource.account,
      'accessToken': 'synthetic-new-access',
      'refreshToken': 'synthetic-new-refresh',
      'expiresAt': expiry.toIso8601String(),
    });
    expect(expectedSource.sourceIncarnation, claim.originalSource.sourceIncarnation);
    expect(expectedSource.metadataRevision, claim.originalSource.metadataRevision);
    expect(expectedSource.credentialRevision, claim.originalSource.credentialRevision + 1);
    final expected = claim.received(
      returnedSource: expectedSource, receivedAt: actual.receivedAt!,
    );
    expect(actual.encode(), expected.encode());
    expect(raw, expected.encode());
    return expected;
  }

  String expectedRetirementFence(String raw) {
    final record = jsonDecode(raw) as Map<String, dynamic>;
    expect(record.keys.toSet(), {'schema', 'retirementId', 'state'});
    expect(record['schema'], 1);
    expect(record['state'], 'retiring');
    final id = record['retirementId'] as String;
    expect(RegExp(r'^[A-Za-z0-9_-]{32}$').hasMatch(id), isTrue);
    final expected = jsonEncode({'schema': 1, 'retirementId': id, 'state': 'retiring'});
    expect(raw, expected);
    return expected;
  }

  List<Map<String, Object?>> expectedCleanupWrites(String fence, {required bool failed}) => [
    {'kind': 'set', 'key': 'flutter.$_fenceKey', 'value': fence},
    {'kind': 'remove',
      'key': 'flutter.${AccountLocalDataCleaner.accountDataOwnerKey}', 'value': null},
    {'kind': 'remove', 'key': 'flutter.$_accountsKey', 'value': null},
    {'kind': 'remove', 'key': 'flutter.${OAuthCalendarStorage.scopeOwnerKey}', 'value': null},
    {'kind': 'remove', 'key': 'flutter.$_cacheKey', 'value': null},
    {'kind': 'remove', 'key': 'flutter.$_journalKey', 'value': null},
    if (!failed) {'kind': 'remove', 'key': 'flutter.$_fenceKey', 'value': null},
  ];

  Future<void> expectFreshAuthorizationAfterClear() async {
    final issuer = AuthProvider();
    extraIssuers.add(issuer);
    await issuer.loadFromStorage(refreshServerConfig: false).timeout(_wait);
    expect(issuer.state.userId, 'fixture-oauth');
    expect(issuer.isLocalAccountDataBlocked, isFalse);
    final peer = CalendarSyncProvider(authProvider: issuer);
    providers.add(peer);
    await peer.prepareOAuthScope(initialize: true).timeout(_wait);
    final freshLease = issuer.captureOAuthScopeLease();
    expect(issuer.isOAuthScopeLeaseCurrent(freshLease), isTrue);
    expect(freshLease.workspace.rawRecord, isNot(lease.workspace.rawRecord));
    expect(peer.isOAuthReady, isTrue);
    expect(peer.oauthAccounts, isEmpty);
    expect(feed.requests, ['refresh']);
    final freshBefore = await store.getAll();
    final writesBefore = store.mutations.toList();
    expect(freshBefore['flutter.${AccountLocalDataCleaner.accountDataOwnerKey}'],
        'id:fixture-oauth');
    expect({
      for (final entry in freshBefore.entries)
        if (entry.key.startsWith('flutter.duoyi_oauth_calendar_'))
          entry.key: entry.value,
    }, {
      'flutter.${OAuthCalendarStorage.scopeOwnerKey}': freshLease.workspace.rawRecord,
    });
    final draft = await peer.savePendingOAuthAuthorization(
      provider: OAuthCalendarProvider.google,
      displayName: 'New OAuth account',
      clientId: 'synthetic-client',
      clientSecret: '',
      redirectUri: 'duoyi://oauth/calendar',
      calendarId: 'primary',
      codeVerifier: _codeVerifier,
      state: 'synthetic-fresh-after-cleanup-state',
    ).timeout(_wait);
    final began = DateTime.now();
    final connected = await peer.addOAuthAccountFromCode(
      provider: OAuthCalendarProvider.google,
      displayName: 'New OAuth account',
      clientId: 'synthetic-client',
      redirectUri: 'duoyi://oauth/calendar',
      authorizationCode: 'synthetic-fresh-after-cleanup-code',
      expectedAttemptId: draft['attemptId'],
      codeVerifier: _codeVerifier,
    ).timeout(_wait);
    final completed = DateTime.now();
    expect(connected.accessToken, 'synthetic-new-access');
    expect(connected.refreshToken, 'synthetic-new-refresh');
    expect(connected.provider, OAuthCalendarProvider.google);
    expect(connected.displayName, 'New OAuth account');
    expect(connected.clientId, 'synthetic-client');
    expect(connected.clientSecret, '');
    expect(connected.redirectUri, 'duoyi://oauth/calendar');
    expect(connected.calendarId, 'primary');
    expect(connected.scope, 'https://www.googleapis.com/auth/calendar.readonly');
    expect(connected.colorValue, 0xFF5E97F6);
    expect(connected.enabled, isTrue);
    expect(RegExp(r'^[A-Za-z0-9_-]{64}$').hasMatch(connected.id), isTrue);
    _expectTimeBetween(connected.expiresAt, began.add(const Duration(seconds: 3600)),
        completed.add(const Duration(seconds: 3600)));
    _expectTimeBetween(connected.lastSyncedAt!, began, completed);
    expect(peer.oauthAccounts, hasLength(1));
    expect(peer.oauthAccounts.single.id, connected.id);
    expect(_titles(peer), [_newTitle]);
    expect(feed.requests, ['refresh', 'exchange', 'events']);
    expect(feed.replayedCodes, isEmpty);
    expect(peer.oauthLocalCommitReceipts, isEmpty);
    expect(peer.lastError, isNull);
    expect(peer.isSyncing, isFalse);
    final disk = await store.getAll();
    expect(disk.containsKey('flutter.$_pendingKey'), isFalse);
    expect(disk.containsKey('flutter.$_journalKey'), isFalse);
    expect(disk.containsKey('flutter.$_fenceKey'), isFalse);
    final sources = OAuthOwnedSourceRecord.parseList(
      disk['flutter.$_accountsKey'] as String, scope: freshLease.workspace.record,
    );
    expect(sources, hasLength(1));
    final actualSource = sources!.single;
    expect(RegExp(r'^[A-Za-z0-9_-]{32}$')
        .hasMatch(actualSource.sourceIncarnation), isTrue);
    final expectedAccount = OAuthCalendarAccount(
      id: connected.id,
      provider: OAuthCalendarProvider.google,
      displayName: 'New OAuth account',
      clientId: 'synthetic-client',
      redirectUri: 'duoyi://oauth/calendar',
      accessToken: 'synthetic-new-access',
      refreshToken: 'synthetic-new-refresh',
      expiresAt: connected.expiresAt,
      scope: 'https://www.googleapis.com/auth/calendar.readonly',
    );
    final initialSource = OAuthOwnedSourceRecord.parse(jsonEncode({
      'schema': 2,
      'scopedOwner': freshLease.workspace.record.scopedOwner,
      'oauthIncarnation': freshLease.workspace.record.oauthIncarnation,
      'sourceIncarnation': actualSource.sourceIncarnation,
      'metadataRevision': 1,
      'credentialRevision': 1,
      'account': expectedAccount.toJson(),
    }), scope: freshLease.workspace.record)!;
    final finalSource = initialSource.withAccount(
      expectedAccount.copyWith(lastSyncedAt: connected.lastSyncedAt).toJson(),
    );
    expect(actualSource.encode(), finalSource.encode());
    expect(connected.toJson(), finalSource.account);
    final expectedCache = OAuthOwnedEventsRecord.create(
      source: finalSource, events: [_expectedFetchedEvent(accountId: connected.id)],
    ).encode();
    final cache = OAuthOwnedEventsRecord.parse(
      disk['flutter.duoyi_oauth_calendar_events_${connected.id}'] as String,
      source: sources.single,
    );
    expect(cache, isNotNull);
    expect(cache!.encode(), expectedCache);
    final prepared = OAuthOwnedPendingAuthorization.create(
      scope: freshLease.workspace.record,
      attemptId: draft['attemptId']!,
      draft: {
        'provider': 'google',
        'displayName': 'New OAuth account',
        'clientId': 'synthetic-client',
        'clientSecret': '',
        'redirectUri': 'duoyi://oauth/calendar',
        'calendarId': 'primary',
        'codeVerifier': _codeVerifier,
        'state': 'synthetic-fresh-after-cleanup-state',
      },
      savedAt: DateTime.parse(draft['savedAt']!),
    );
    final dispatched = prepared.dispatched(
      fingerprint: sha256.convert(utf8.encode(jsonEncode([
        'google', 'synthetic-client', 'duoyi://oauth/calendar',
        'synthetic-fresh-after-cleanup-code',
      ]))).toString(),
      accountId: connected.id,
    );
    final recordedReceived = OAuthOwnedPendingAuthorization.parse(
      store.mutations[writesBefore.length + 2]['value'] as String,
      scope: freshLease.workspace.record,
    );
    expect(recordedReceived, isNotNull);
    expect(recordedReceived!.phase, OAuthPendingPhase.received);
    final received = dispatched.received(
      source: initialSource, handle: recordedReceived.receiptHandle!,
    );
    expect(recordedReceived.encode(), received.encode());
    final finalAccounts = jsonEncode([finalSource.toJson()]);
    expectMutationSequence([
      ...writesBefore,
      {'kind': 'set', 'key': 'flutter.$_pendingKey', 'value': prepared.encode()},
      {'kind': 'set', 'key': 'flutter.$_pendingKey', 'value': dispatched.encode()},
      {'kind': 'set', 'key': 'flutter.$_pendingKey', 'value': received.encode()},
      {'kind': 'set', 'key': 'flutter.$_accountsKey',
        'value': jsonEncode([initialSource.toJson()])},
      {'kind': 'remove', 'key': 'flutter.$_pendingKey', 'value': null},
      {'kind': 'set', 'key': 'flutter.duoyi_oauth_calendar_events_${connected.id}',
        'value': expectedCache},
      {'kind': 'set', 'key': 'flutter.$_accountsKey', 'value': finalAccounts},
    ]);
    await expectCompleteDisk({
      ...freshBefore,
      'flutter.$_accountsKey': finalAccounts,
      'flutter.duoyi_oauth_calendar_events_${connected.id}': expectedCache,
    });
    expect(issuer.isOAuthScopeLeaseCurrent(freshLease), isTrue);
    expect(OAuthCalendarStorage.ownsRequest(connected.id, 1), isTrue);
    expect(OAuthCalendarStorage.sourceRevision(connected.id), 0);
    expect(OAuthCalendarStorage.failure, isNull);
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
      for (final issuer in extraIssuers) {
        issuer.dispose();
      }
      auth.dispose();
      try {
        await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
      } finally {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        SharedPreferencesStorePlatform.instance = previousStore;
      }
    }
  }
}

class _ResponseStep {
  _ResponseStep(this.hold, this.status, this.payload);
  final bool hold;
  final int status;
  final Map<String, Object?>? payload;
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
    int status = 200,
    Map<String, Object?>? payload,
  }) {
    final step = _ResponseStep(hold, status, payload);
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
    if (!isToken) {
      expect(request.method, 'GET');
      expect(request.headers['Authorization'], startsWith('Bearer synthetic-'));
    }
    final kind = isToken
        ? request.bodyFields['grant_type'] == 'authorization_code'
              ? 'exchange'
              : 'refresh'
        : 'events';
    requests.add(kind);
    if (kind == 'exchange') {
      final code = request.bodyFields['code']!;
      if (!_consumedCodes.add(code)) {
        replayedCodes.add(code);
        return _jsonResponse({'error': 'invalid_grant'}, 400);
      }
    }
    final queue = _plans[kind];
    final step = queue == null || queue.isEmpty ? null : queue.removeAt(0);
    if (step != null) {
      step.started.complete();
      if (step.hold) await step.release.future;
    }
    final status = step?.status ?? 200;
    final payload =
        step?.payload ??
        (status == 200
            ? isToken
                  ? <String, Object?>{
                      'access_token': 'synthetic-new-access',
                      'refresh_token': 'synthetic-new-refresh',
                      'expires_in': 3600,
                      'token_type': 'Bearer',
                    }
                  : <String, Object?>{
                      'items': [
                        {
                          'id': 'fetched',
                          'summary': _newTitle,
                          'start': {'dateTime': '2026-11-09T11:00:00.000Z'},
                          'end': {'dateTime': '2026-11-09T12:00:00.000Z'},
                        },
                      ],
                    }
            : <String, Object?>{'error': 'synthetic-server-error'});
    return _jsonResponse(payload, status);
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
  _WriteStep(this.effect, this.hold);
  final _WriteEffect effect;
  final bool hold;
  final started = Completer<void>();
  final release = Completer<void>();
  String? value;
}

class _OAuthStore extends InMemorySharedPreferencesStore {
  _OAuthStore() : super.withData(<String, Object>{});
  final attempts = <String>[];
  final mutations = <Map<String, Object?>>[];
  final _plans = <String, List<_WriteStep>>{};
  final _all = <_WriteStep>[];

  _WriteStep plan(
    String kind,
    String key,
    _WriteEffect effect, {
    bool hold = false,
  }) {
    final step = _WriteStep(effect, hold);
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
    final queue = _plans[id];
    if (queue == null || queue.isEmpty) return persist();
    final step = queue.removeAt(0);
    step.value = value as String?;
    step.started.complete();
    if (step.hold) await step.release.future;
    if (step.effect == _WriteEffect.throwsError) {
      throw StateError('Synthetic OAuth persistence failure');
    }
    if (step.effect == _WriteEffect.returnsFalse) return false;
    if (step.effect == _WriteEffect.ackWithoutPersist) return true;
    final accepted = await persist();
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
