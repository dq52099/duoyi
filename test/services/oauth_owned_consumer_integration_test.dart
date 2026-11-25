// ignore_for_file: depend_on_referenced_packages
// Real Auth + CalendarSyncProvider integration contract. Prepared against the
// frozen oauth-consumer-preimage-211.dart API plus the new authProvider argument.
// This worker does not run Flutter/Dart verification.

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/oauth_authorization_input.dart';
import 'package:duoyi/core/oauth_calendar_storage.dart';
import 'package:duoyi/core/oauth_calendar_workspace_codec.dart';
import 'package:duoyi/core/oauth_pending_authorization.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

const _wait = Duration(seconds: 5);
const _accounts = OAuthCalendarStorage.accountsKey;
const _owner = OAuthCalendarStorage.scopeOwnerKey;
const _pendingKey = OAuthCalendarStorage.pendingAuthorizationKey;
const _unknownKey = 'duoyi_oauth_calendar_unknown_owned_consumer';
const _title = 'Real owned consumer event';
final _verifier = OAuthCalendarClient.generateCodeVerifier();
const _state = 'synthetic-owned-consumer-state';
const _ordinary = <String, Object>{
  'auth_state': '{ "token" : null }',
  'todos': '[ { "id" : "owned_consumer_todo", "title" : "keep" } ]',
  'duoyi_notes': '[ { "body" : "keep owned consumer note" } ]',
  'duoyi_ics_subscriptions_v1': '[]',
  'sync_pending_local_changes': true,
  'owned_consumer_device_setting': 7,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() async => f = await _Fixture.create());
  tearDown(() async => f.close());

  test(
    'OCI-01 real guest prepares, connects, writes schema 2, restarts readonly',
    () => f.withHttp(() async {
      final auth = f.auth();
      final consumer = f.consumer(auth);
      expect(auth.isGuestWorkspaceReady, isFalse);
      await f.reject(f.connect(consumer));
      expect(f.requests, isEmpty);
      expect(f.store.mutations, isEmpty);

      await auth.loadFromStorage(refreshServerConfig: false).timeout(_wait);
      expect(auth.isGuestWorkspaceReady, isTrue);
      expect(
        auth.captureGuestOAuthScopeLease,
        throwsA(isA<OAuthScopedWorkspaceUnavailable>()),
      );
      await f.reject(f.connect(consumer));
      expect(f.requests, isEmpty);
      expect(f.store.mutations, isEmpty);
      await consumer.prepareOAuthScope(initialize: true).timeout(_wait);
      final lease = auth.captureGuestOAuthScopeLease();
      final account = await f.connect(consumer).timeout(_wait);
      expect(auth.isGuestOAuthScopeLeaseCurrent(lease), isTrue);
      expect(f.count('token'), 1);
      expect(f.count('events'), 1);
      expect(consumer.oauthAccounts.single.id, account.id);
      expect(consumer.allEvents().map((e) => e.title), [_title]);
      expect(account.accessToken, 'synthetic-owned-consumer-access');
      expect(account.refreshToken, 'synthetic-owned-consumer-refresh');
      final before = await f.disk();
      final source = f.source(before, lease);
      expect(source.account['id'], account.id);
      expect(source.account['accessToken'], account.accessToken);
      expect(source.account['refreshToken'], account.refreshToken);
      final rawCache = before[f.cacheKey(account.id)]! as String;
      expect(jsonDecode(rawCache)['schema'], 2);
      final cache = OAuthOwnedEventsRecord.parse(rawCache, source: source)!;
      expect(cache.events.single['title'], _title);
      expect(cache.sourceAccountId, account.id);
      expect(cache.sourceIncarnation, source.sourceIncarnation);
      expect(cache.scopedOwner, source.scopedOwner);
      expect(cache.oauthIncarnation, source.oauthIncarnation);
      expect(before[_owner], lease.workspace.rawRecord);
      expect(f.store.mutations, contains('set:${f.cacheKey(account.id)}'));
      f.expectOrdinary(before);

      f.disposeConsumer(consumer);
      f.disposeAuth(auth);
      final coldAuth = f.auth();
      final coldConsumer = f.consumer(coldAuth);
      final stamps = _RuntimeStamps();
      final requests = f.requests.toList();
      f.store.mutations.clear();
      await coldAuth.loadFromStorage(refreshServerConfig: false).timeout(_wait);
      final coldLease = coldAuth.captureGuestOAuthScopeLease();
      expect(coldLease.workspace.rawRecord, lease.workspace.rawRecord);
      await coldConsumer.loadFromStorage().timeout(_wait);
      await f.settle();
      expect(coldConsumer.oauthAccounts.single.toJson(), account.toJson());
      expect(coldConsumer.allEvents().map((e) => e.title), [_title]);
      expect(coldAuth.isGuestOAuthScopeLeaseCurrent(coldLease), isTrue);
      expect(await f.disk(), before);
      expect(f.store.mutations, isEmpty);
      expect(f.requests, requests);
      stamps.expectUnchanged();
      f.expectOrdinary(await f.disk());
    }),
  );

  test(
    'OCI-02 missing issuer cannot adopt real owned rows or dispatch a code',
    () => f.withHttp(() async {
      final installed = await f.install();
      final orphanConsumer = f.consumer();
      final before = await f.disk();
      final requests = f.requests.toList();
      f.store.mutations.clear();
      // A load may reject or return an empty OAuth projection. Neither grants
      // authority; a valid code and durable owner must still fail to dispatch.
      await f.observe(orphanConsumer.loadFromStorage()).timeout(_wait);
      await f.reject(f.connect(orphanConsumer, code: 'missing-issuer-code'));
      await f.reject(
        f.dispatch(orphanConsumer, code: 'missing-issuer-direct-code'),
      );
      expect(orphanConsumer.oauthAccounts, isEmpty);
      expect(orphanConsumer.allEvents(), isEmpty);
      expect(orphanConsumer.oauthLocalCommitReceipts, isEmpty);
      expect(
        installed.auth.isGuestOAuthScopeLeaseCurrent(installed.lease),
        isTrue,
      );
      await f.settle();
      expect(f.store.mutations, isEmpty);
      expect(f.requests, requests);
      expect(await f.disk(), before);
      f.expectOrdinary(before);
    }),
  );

  test(
    'OCI-03 hydrated but unprepared issuer cannot dispatch or initialize via consumer',
    () => f.withHttp(() async {
      final auth = f.auth();
      await auth.loadFromStorage(refreshServerConfig: false).timeout(_wait);
      final consumer = f.consumer(auth);
      final before = await f.disk();
      f.store.mutations.clear();
      await f.reject(f.dispatch(consumer));
      await f.reject(
        consumer.savePendingOAuthAuthorization(
          provider: OAuthCalendarProvider.google,
          clientId: 'synthetic-owned-consumer-client',
          redirectUri: 'duoyi://oauth/calendar',
          displayName: 'Owned consumer',
          codeVerifier: _verifier,
          state: _state,
          clientSecret: '',
          calendarId: 'primary',
        ),
      );
      expect(
        auth.captureGuestOAuthScopeLease,
        throwsA(isA<OAuthScopedWorkspaceUnavailable>()),
      );
      expect(await f.disk(), before);
      expect(f.store.mutations, isEmpty);
      expect(f.requests, isEmpty);
      expect(consumer.oauthAccounts, isEmpty);
      f.expectOrdinary(before);
    }),
  );

  for (final phase in ['token', 'events']) {
    test(
      'OCI-held-$phase Auth disposal revokes a held real consumer continuation',
      () => f.withHttp(() async {
        final auth = f.auth();
        await auth.loadFromStorage(refreshServerConfig: false).timeout(_wait);
        final consumer = f.consumer(auth);
        await consumer.prepareOAuthScope(initialize: true).timeout(_wait);
        final lease = auth.captureGuestOAuthScopeLease();
        final hold = f.hold(phase);
        final connecting = f.observe(f.connect(consumer));
        await hold.started.future.timeout(_wait);
        f.disposeAuth(auth);
        expect(auth.isGuestOAuthScopeLeaseCurrent(lease), isFalse);
        final before = await f.disk();
        final rows = consumer.oauthAccounts.map((a) => a.toJson()).toList();
        final titles = consumer.allEvents().map((e) => e.title).toList();
        expect(
          rows,
          isEmpty,
          reason: 'revoked issuer hides the OAuth projection',
        );
        expect(titles, isEmpty);
        final requests = f.requests.toList();
        f.store.mutations.clear();
        var notifications = 0;
        consumer.addListener(() => notifications++);
        hold.release.complete();
        final result = await connecting.timeout(_wait);
        expect(result.error, isNotNull);
        await f.settle();
        expect(await f.disk(), before);
        expect(f.store.mutations, isEmpty);
        expect(f.requests, requests);
        expect(consumer.oauthAccounts.map((a) => a.toJson()).toList(), rows);
        expect(consumer.allEvents().map((e) => e.title).toList(), titles);
        expect(consumer.oauthLocalCommitReceipts, isEmpty);
        expect(notifications, 0);
        if (phase == 'token') {
          expect(f.count('events'), 0);
          expect(before[_accounts], '[ \n ]');
        } else {
          expect(f.count('token'), 1);
          expect(
            before.containsKey(
              f.cacheKey(f.source(before, lease).account['id']! as String),
            ),
            isFalse,
          );
        }
        f.expectOrdinary(before);
      }),
    );
  }

  for (final corruption in ['foreign-scope', 'foreign-source-cache']) {
    test(
      'OCI-$corruption rejects cold adoption without rewriting private bytes',
      () => f.withHttp(() async {
        final installed = await f.install();
        final original = await f.disk();
        final source = f.source(original, installed.lease);
        if (corruption == 'foreign-scope') {
          // Deliberate hostile backing data, never an Auth permission predicate.
          final row = source.toJson();
          row['scopedOwner'] = 'g:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
          expect(row['scopedOwner'], isNot(source.scopedOwner));
          await f.store.inject(_accounts, jsonEncode([row]));
        } else {
          final other = OAuthOwnedSourceRecord.create(
            scope: OAuthScopedOwnerRecord.parse(
              installed.lease.workspace.rawRecord,
            )!,
            account: source.account,
          );
          expect(other.sourceIncarnation, isNot(source.sourceIncarnation));
          final cache = OAuthOwnedEventsRecord.parse(
            original[f.cacheKey(installed.account.id)]! as String,
            source: source,
          )!;
          final foreign = OAuthOwnedEventsRecord.create(
            source: other,
            events: cache.events,
          );
          expect(
            OAuthOwnedEventsRecord.parse(foreign.encode(), source: source),
            isNull,
          );
          await f.store.inject(
            f.cacheKey(installed.account.id),
            foreign.encode(),
          );
        }
        await f.prefs.reload();
        f.disposeConsumer(installed.consumer);
        f.disposeAuth(installed.auth);
        final coldAuth = f.auth();
        final coldConsumer = f.consumer(coldAuth);
        final before = await f.disk();
        final requests = f.requests.toList();
        final stamps = _RuntimeStamps();
        f.store.mutations.clear();
        await f.reject(
          coldAuth.loadFromStorage(refreshServerConfig: false),
          isA<AccountLocalDataCleanupBlockedException>(),
        );
        expect(coldAuth.isLocalAccountDataBlocked, isTrue);
        expect(coldAuth.isGuestWorkspaceReady, isFalse);
        await f.observe(coldConsumer.loadFromStorage()).timeout(_wait);
        await f.reject(f.connect(coldConsumer, code: 'blocked-cold-code'));
        expect(coldConsumer.oauthAccounts, isEmpty);
        expect(coldConsumer.allEvents(), isEmpty);
        await f.settle();
        expect(await f.disk(), before);
        expect(f.store.mutations, isEmpty);
        expect(f.requests, requests);
        stamps.expectUnchanged();
        f.expectOrdinary(before);
      }),
    );
  }

  test(
    'OCI-DUR-01 cold dispatched attempt cannot exchange its code again',
    () => f.withHttp(() async {
      final issuer = f.auth();
      await issuer.loadFromStorage(refreshServerConfig: false).timeout(_wait);
      final consumer = f.consumer(issuer);
      await consumer.prepareOAuthScope(initialize: true).timeout(_wait);
      final lease = issuer.captureGuestOAuthScopeLease();
      final hold = f.hold('token');
      final connecting = f.observe(f.connect(consumer));
      await hold.started.future.timeout(_wait);
      final dispatchedDisk = await f.disk();
      final dispatched = f.pendingRecord(dispatchedDisk, lease);
      expect(dispatched.phase, OAuthPendingPhase.dispatched);
      expect(dispatched.sourceAccountId, isNotEmpty);
      expect(dispatched.codeFingerprint, isNotEmpty);
      expect(dispatched.receivedSource, isNull);
      expect(dispatchedDisk[_accounts], '[ \n ]');
      f.disposeAuth(issuer);
      f.disposeConsumer(consumer);
      hold.release.complete();
      expect((await connecting.timeout(_wait)).error, isNotNull);
      await f.settle();
      expect(await f.disk(), dispatchedDisk);
      expect(f.count('token'), 1);
      expect(f.count('events'), 0);

      final coldAuth = f.auth();
      final coldConsumer = f.consumer(coldAuth);
      final requests = f.requests.toList();
      final stamps = _RuntimeStamps();
      f.store.mutations.clear();
      await coldAuth.loadFromStorage(refreshServerConfig: false).timeout(_wait);
      final coldLease = coldAuth.captureGuestOAuthScopeLease();
      expect(coldLease.workspace.rawRecord, lease.workspace.rawRecord);
      await coldConsumer.loadFromStorage().timeout(_wait);
      await coldConsumer.loadPendingOAuthAuthorization().timeout(_wait);
      expect(
        f.pendingRecord(await f.disk(), coldLease).encode(),
        dispatched.encode(),
      );
      // No savePending call here: that would be a fresh authorization attempt.
      // This is the exact previously claimed draft, callback and code.
      await f.reject(f.dispatch(coldConsumer));
      await f.reject(f.dispatch(coldConsumer));
      await f.settle();
      expect(coldConsumer.oauthAccounts, isEmpty);
      expect(coldConsumer.allEvents(), isEmpty);
      expect(coldConsumer.oauthLocalCommitReceipts, isEmpty);
      expect(await f.disk(), dispatchedDisk);
      expect(f.store.mutations, isEmpty);
      expect(f.requests, requests);
      stamps.expectUnchanged();
      f.expectOrdinary(dispatchedDisk);
    }),
  );

  test(
    'OCI-DUR-02 cold received attempt saves returned tokens only by explicit local retry',
    () => f.withHttp(() async {
      final issuer = f.auth();
      await issuer.loadFromStorage(refreshServerConfig: false).timeout(_wait);
      final consumer = f.consumer(issuer);
      await consumer.prepareOAuthScope(initialize: true).timeout(_wait);
      final lease = issuer.captureGuestOAuthScopeLease();
      // Fail the real account commit once, after the real token response and
      // separate received-pending commit. No durable attempt is fabricated.
      f.store.failNextAccountsWrite = true;
      final failed = await f.observe(f.connect(consumer)).timeout(_wait);
      expect(f.store.failNextAccountsWrite, isFalse);
      expect(failed.error, isA<OAuthLocalCommitRequired>());
      final oldReceipt = (failed.error! as OAuthLocalCommitRequired).receipt;
      await f.settle();
      final receivedDisk = await f.disk();
      final received = f.pendingRecord(receivedDisk, lease);
      expect(received.phase, OAuthPendingPhase.received);
      expect(received.receiptHandle, oldReceipt.handle);
      final returned = received.receivedSource!;
      final accountId = returned.account['id']! as String;
      expect(received.sourceAccountId, accountId);
      expect(
        returned.account['accessToken'],
        'synthetic-owned-consumer-access',
      );
      expect(
        returned.account['refreshToken'],
        'synthetic-owned-consumer-refresh',
      );
      expect(receivedDisk[_accounts], '[ \n ]');
      expect(receivedDisk.containsKey(f.cacheKey(accountId)), isFalse);
      expect(consumer.oauthAccounts, isEmpty);
      expect(f.count('token'), 1);
      expect(f.count('events'), 0);
      f.disposeConsumer(consumer);
      f.disposeAuth(issuer);

      final coldAuth = f.auth();
      final coldConsumer = f.consumer(coldAuth);
      final requests = f.requests.toList();
      final stamps = _RuntimeStamps();
      f.store.mutations.clear();
      await coldAuth.loadFromStorage(refreshServerConfig: false).timeout(_wait);
      final coldLease = coldAuth.captureGuestOAuthScopeLease();
      await coldConsumer.loadFromStorage().timeout(_wait);
      await coldConsumer.loadPendingOAuthAuthorization().timeout(_wait);
      expect(coldConsumer.oauthAccounts, isEmpty);
      expect(coldConsumer.allEvents(), isEmpty);
      final receipt = coldConsumer.oauthLocalCommitReceipts.single;
      expect(receipt.handle, received.receiptHandle);
      expect(receipt.isRefresh, isFalse);
      await f.reject(f.dispatch(coldConsumer));
      await f.settle();
      expect(await f.disk(), receivedDisk);
      expect(f.store.mutations, isEmpty);
      expect(f.requests, requests);
      stamps.expectUnchanged();

      final recovered = await coldConsumer
          .retryOAuthLocalCommit(receipt)
          .timeout(_wait);
      await f.settle();
      expect(recovered.id, accountId);
      expect(recovered.accessToken, returned.account['accessToken']);
      expect(recovered.refreshToken, returned.account['refreshToken']);
      expect(
        recovered.expiresAt.toIso8601String(),
        returned.account['expiresAt'],
      );
      final recoveredDisk = await f.disk();
      expect(f.source(recoveredDisk, coldLease).encode(), returned.encode());
      expect(recoveredDisk.containsKey(_pendingKey), isFalse);
      expect(recoveredDisk.containsKey(f.cacheKey(accountId)), isFalse);
      expect(coldConsumer.oauthAccounts.single.toJson(), recovered.toJson());
      expect(coldConsumer.oauthLocalCommitReceipts, isEmpty);
      expect(coldConsumer.allEvents(), isEmpty);
      expect(
        f.requests,
        requests,
        reason: 'local retry must never refetch tokens or events',
      );
      expect(recoveredDisk[_owner], receivedDisk[_owner]);
      f.expectOrdinary(recoveredDisk);
    }),
  );

  test(
    'OCI-DUR-05 cold retry consumes a received attempt whose exact source is already durable',
    () => f.withHttp(() async {
      final issuer = f.auth();
      await issuer.loadFromStorage(refreshServerConfig: false).timeout(_wait);
      final consumer = f.consumer(issuer);
      await consumer.prepareOAuthScope(initialize: true).timeout(_wait);
      final lease = issuer.captureGuestOAuthScopeLease();
      // A rejected pending removal normally rolls accounts back. Capture the
      // exact accounts payload actually issued by the consumer, then simulate
      // a process-cut surviving pair after all real work has settled. This is
      // an explicit backing-state simulation, not an actual process restart.
      f.store.failNextPendingRemove = true;
      final failed = await f.observe(f.connect(consumer)).timeout(_wait);
      expect(f.store.failNextPendingRemove, isFalse);
      expect(failed.error, isA<OAuthLocalCommitRequired>());
      await f.settle();
      final rolledBackDisk = await f.disk();
      final received = f.pendingRecord(rolledBackDisk, lease);
      expect(received.phase, OAuthPendingPhase.received);
      expect(rolledBackDisk[_accounts], '[ \n ]');
      final returned = received.receivedSource!;
      final scope = OAuthScopedOwnerRecord.parse(lease.workspace.rawRecord)!;
      final issued = f.store.issuedAccounts.where((raw) {
        final records = OAuthOwnedSourceRecord.parseList(raw, scope: scope);
        return records != null &&
            records.length == 1 &&
            records.single.encode() == returned.encode();
      }).toList();
      expect(issued, isNotEmpty, reason: 'retain a real issued source payload');
      final actualIssuedAccounts = issued.last;
      final actualReceivedPending = rolledBackDisk[_pendingKey]! as String;
      expect(f.count('token'), 1);
      expect(f.count('events'), 0);
      f.disposeConsumer(consumer);
      f.disposeAuth(issuer);
      await f.store.inject(_accounts, actualIssuedAccounts);
      await f.store.inject(_pendingKey, actualReceivedPending);
      await f.prefs.reload();
      final partialDisk = await f.disk();
      final alreadySaved = f.source(partialDisk, lease);
      expect(alreadySaved.encode(), returned.encode());
      expect(partialDisk[_accounts], actualIssuedAccounts);
      expect(partialDisk[_pendingKey], actualReceivedPending);
      final accountId = alreadySaved.account['id']! as String;
      expect(partialDisk.containsKey(f.cacheKey(accountId)), isFalse);

      final coldAuth = f.auth();
      final coldConsumer = f.consumer(coldAuth);
      final requests = f.requests.toList();
      f.store.mutations.clear();
      await coldAuth.loadFromStorage(refreshServerConfig: false).timeout(_wait);
      final coldLease = coldAuth.captureGuestOAuthScopeLease();
      await coldConsumer.loadFromStorage().timeout(_wait);
      final receipt = coldConsumer.oauthLocalCommitReceipts.single;
      expect(receipt.handle, received.receiptHandle);
      final coldAccount = coldConsumer.oauthAccounts.single;
      expect(coldAccount.id, accountId);
      expect(await f.disk(), partialDisk);
      expect(f.store.mutations, isEmpty);
      expect(f.requests, requests);

      // 231-R1: exact installed source + received pending remains locked until
      // explicit local recovery. Normal metadata edits must not strand it.
      for (final blocked in <Future<void> Function()>[
        () => coldConsumer.updateOAuthAccount(
          coldAccount.copyWith(displayName: 'Blocked recovery rename'),
        ),
        () => coldConsumer.updateOAuthAccount(
          coldAccount.copyWith(enabled: false),
        ),
        () => coldConsumer.removeOAuthAccount(accountId),
      ]) {
        final rejected = await f.observe(blocked()).timeout(_wait);
        expect(rejected.error, isA<OAuthLocalCommitRequired>());
        expect(
          (rejected.error! as OAuthLocalCommitRequired).receipt.handle,
          received.receiptHandle,
        );
        await f.settle();
        expect(await f.disk(), partialDisk);
        expect(f.store.mutations, isEmpty);
        expect(f.requests, requests);
        expect(
          coldConsumer.oauthAccounts.single.toJson(),
          coldAccount.toJson(),
        );
        expect(
          coldConsumer.oauthLocalCommitReceipts.single.handle,
          receipt.handle,
        );
      }

      // The shared sync guard keeps received recovery local: no events or
      // refresh HTTP, no pending mutation, and the receipt remains recoverable.
      final syncing = await f.observe(coldConsumer.syncAll()).timeout(_wait);
      expect(syncing.error, isNull);
      await f.settle();
      expect(coldConsumer.lastError, isNotNull);
      expect(coldConsumer.isSyncing, isFalse);
      expect(await f.disk(), partialDisk);
      expect(f.store.mutations, isEmpty);
      expect(f.requests, requests);
      expect(coldConsumer.oauthAccounts.single.toJson(), coldAccount.toJson());
      expect(coldConsumer.oauthLocalCommitReceipts.single.handle, receipt.handle);

      final recovered = await coldConsumer
          .retryOAuthLocalCommit(receipt)
          .timeout(_wait);
      await f.settle();
      final completeDisk = await f.disk();
      expect(recovered.id, accountId);
      expect(completeDisk[_accounts], partialDisk[_accounts]);
      expect(f.source(completeDisk, coldLease).encode(), alreadySaved.encode());
      expect(completeDisk.containsKey(_pendingKey), isFalse);
      expect(completeDisk.containsKey(f.cacheKey(accountId)), isFalse);
      expect(coldConsumer.oauthAccounts, hasLength(1));
      expect(coldConsumer.oauthLocalCommitReceipts, isEmpty);
      expect(coldConsumer.allEvents(), isEmpty);
      expect(
        f.store.mutations,
        isNot(contains('set:$_accounts')),
        reason: 'same exact durable source only needs pending consumption',
      );
      expect(f.requests, requests);
      f.expectOrdinary(completeDisk);
      // Once the original receipt has been explicitly consumed, normal edits
      // resume and the installed source retains its incarnation and credentials.
      await coldConsumer
          .updateOAuthAccount(
            recovered.copyWith(displayName: 'Allowed recovery rename'),
          )
          .timeout(_wait);
      await f.settle();
      final renamedDisk = await f.disk();
      final renamed = f.source(renamedDisk, coldLease);
      expect(renamed.account['displayName'], 'Allowed recovery rename');
      expect(renamed.sourceIncarnation, alreadySaved.sourceIncarnation);
      expect(
        renamed.account['accessToken'],
        alreadySaved.account['accessToken'],
      );
      expect(
        renamed.account['refreshToken'],
        alreadySaved.account['refreshToken'],
      );
      expect(renamedDisk.containsKey(_pendingKey), isFalse);
      expect(coldConsumer.oauthLocalCommitReceipts, isEmpty);
      expect(f.requests, requests);
      f.expectOrdinary(renamedDisk);
    }),
  );

  test(
    'OCI-DUR-03 connection configuration change retires the confirmed old cache',
    () => f.withHttp(() async {
      final installed = await f.install();
      final original = await f.disk();
      final oldSource = f.source(original, installed.lease);
      final cacheKey = f.cacheKey(installed.account.id);
      expect(original.containsKey(cacheKey), isTrue);
      final requests = f.requests.toList();
      await installed.consumer
          .updateOAuthAccount(
            installed.account.copyWith(
              calendarId: 'owned-consumer-new-calendar',
            ),
          )
          .timeout(_wait);
      await f.settle();
      final changed = await f.disk();
      final source = f.source(changed, installed.lease);
      expect(source.account['id'], installed.account.id);
      expect(source.account['calendarId'], 'owned-consumer-new-calendar');
      expect(source.sourceIncarnation, isNot(oldSource.sourceIncarnation));
      expect(source.scopedOwner, oldSource.scopedOwner);
      expect(source.oauthIncarnation, oldSource.oauthIncarnation);
      expect(changed.containsKey(cacheKey), isFalse);
      expect(installed.consumer.allEvents(), isEmpty);
      expect(f.requests, requests);
      f.expectOrdinary(changed);
      f.disposeConsumer(installed.consumer);
      f.disposeAuth(installed.auth);

      final coldAuth = f.auth();
      final coldConsumer = f.consumer(coldAuth);
      f.store.mutations.clear();
      await coldAuth.loadFromStorage(refreshServerConfig: false).timeout(_wait);
      await coldConsumer.loadFromStorage().timeout(_wait);
      await f.settle();
      expect(
        coldConsumer.oauthAccounts.single.calendarId,
        'owned-consumer-new-calendar',
      );
      expect(coldConsumer.allEvents(), isEmpty);
      expect(await f.disk(), changed);
      expect(f.store.mutations, isEmpty);
      expect(f.requests, requests);
    }),
  );

  test(
    'OCI-DUR-04 unknown typed sidecar blocks live dispatch and cold adoption without writes',
    () => f.withHttp(() async {
      final installed = await f.install();
      await f.store.inject(_unknownKey, 17);
      await f.prefs.reload();
      final before = await f.disk();
      final requests = f.requests.toList();
      final stamps = _RuntimeStamps();
      f.store.mutations.clear();
      await f.observe(installed.consumer.syncAll()).timeout(_wait);
      await f.reject(
        f.connect(installed.consumer, code: 'unknown-sidecar-code'),
      );
      await f.settle();
      expect(await f.disk(), before);
      expect(f.store.mutations, isEmpty);
      expect(f.requests, requests);
      f.disposeConsumer(installed.consumer);
      f.disposeAuth(installed.auth);

      final coldAuth = f.auth();
      final coldConsumer = f.consumer(coldAuth);
      await f.reject(
        coldAuth.loadFromStorage(refreshServerConfig: false),
        isA<AccountLocalDataCleanupBlockedException>(),
      );
      expect(coldAuth.isGuestWorkspaceReady, isFalse);
      expect(coldAuth.isLocalAccountDataBlocked, isTrue);
      await f.observe(coldConsumer.loadFromStorage()).timeout(_wait);
      await f.reject(
        f.dispatch(coldConsumer, code: 'unknown-sidecar-cold-code'),
      );
      await f.settle();
      expect(coldConsumer.oauthAccounts, isEmpty);
      expect(coldConsumer.allEvents(), isEmpty);
      expect(await f.disk(), before);
      expect((await f.disk())[_unknownKey], 17);
      expect(f.store.mutations, isEmpty);
      expect(f.requests, requests);
      stamps.expectUnchanged();
      f.expectOrdinary(before);
    }),
  );

  test(
    'OCI-CAS-01 old configuration DTO cannot disable its replacement source',
    () => f.withHttp(() async {
      final installed = await f.install();
      final oldAccount = installed.account;
      final oldSource = f.source(await f.disk(), installed.lease);
      await installed.consumer
          .updateOAuthAccount(
            oldAccount.copyWith(calendarId: 'owned-consumer-cas-replacement'),
          )
          .timeout(_wait);
      await f.settle();
      final replacementDisk = await f.disk();
      final replacement = f.source(replacementDisk, installed.lease);
      expect(replacement.account['id'], oldAccount.id);
      expect(replacement.sourceIncarnation, isNot(oldSource.sourceIncarnation));
      expect(replacement.account['enabled'], isTrue);
      final requests = f.requests.toList();
      f.store.mutations.clear();
      await f.reject(
        installed.consumer.updateOAuthAccount(
          oldAccount.copyWith(enabled: false),
        ),
      );
      await f.settle();
      expect(await f.disk(), replacementDisk);
      expect(f.store.mutations, isEmpty);
      expect(f.requests, requests);
      expect(
        f.source(await f.disk(), installed.lease).account['enabled'],
        isTrue,
      );
      f.expectOrdinary(replacementDisk);
    }),
  );

  test(
    'OCI-CAS-02 old same-source toggle preserves peer metadata and rotated tokens',
    () => f.withHttp(() async {
      final installed = await f.install();
      final oldAccount = installed.account;
      final original = f.source(await f.disk(), installed.lease);
      // Simulate only token expiry on the actually owned record. Access and
      // refresh tokens remain the real initial exchange result; rotation below
      // must go through the real peer syncAll refresh HTTP and commit path.
      final expired = original.withAccount({
        ...original.account,
        'expiresAt': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 5))
            .toIso8601String(),
      });
      expect(expired.sourceIncarnation, original.sourceIncarnation);
      expect(expired.account['accessToken'], original.account['accessToken']);
      expect(expired.account['refreshToken'], original.account['refreshToken']);
      await f.store.inject(_accounts, jsonEncode([expired.toJson()]));
      await f.prefs.reload();
      final peer = f.consumer(installed.auth);
      await peer.loadFromStorage().timeout(_wait);
      final peerAccount = peer.oauthAccounts.single;
      await peer
          .updateOAuthAccount(
            peerAccount.copyWith(displayName: 'Owned consumer peer rename'),
          )
          .timeout(_wait);
      await peer.syncAll().timeout(_wait);
      await f.settle();
      expect(peer.lastError, isNull);
      expect(f.count('token'), 1);
      expect(f.count('refresh'), 1);
      expect(f.count('events'), 2);
      final peerDisk = await f.disk();
      final renamed = f.source(peerDisk, installed.lease);
      expect(renamed.sourceIncarnation, original.sourceIncarnation);
      expect(renamed.account['displayName'], 'Owned consumer peer rename');
      expect(
        renamed.account['accessToken'],
        'synthetic-owned-consumer-peer-access',
      );
      expect(
        renamed.account['refreshToken'],
        'synthetic-owned-consumer-peer-refresh',
      );
      expect(renamed.credentialRevision, expired.credentialRevision + 1);
      final requests = f.requests.toList();
      await installed.consumer
          .updateOAuthAccount(oldAccount.copyWith(enabled: false))
          .timeout(_wait);
      await f.settle();
      final toggledDisk = await f.disk();
      final toggled = f.source(toggledDisk, installed.lease);
      expect(toggled.sourceIncarnation, renamed.sourceIncarnation);
      expect(toggled.account['enabled'], isFalse);
      for (final key in [
        'displayName',
        'accessToken',
        'refreshToken',
        'expiresAt',
      ]) {
        expect(toggled.account[key], renamed.account[key], reason: key);
      }
      expect(toggled.credentialRevision, renamed.credentialRevision);
      expect(toggled.metadataRevision, renamed.metadataRevision + 1);
      expect(
        toggledDisk[f.cacheKey(oldAccount.id)],
        peerDisk[f.cacheKey(oldAccount.id)],
      );
      expect(f.requests, requests);
      f.expectOrdinary(toggledDisk);
    }),
  );

  test(
    'OCI-R2-242 transaction readback rejects injected sidecar clears OAuth and retains ICS',
    () => f.withHttp(() async {
      final installed = await f.install();
      const subscription = IcsSubscription(
        id: 'owned_consumer_retained_ics',
        name: 'Retained ICS',
        url: 'https://owned-consumer-ics.example/calendar.ics',
      );
      await installed.consumer.addSubscription(subscription).timeout(_wait);
      final refreshed = await installed.consumer
          .syncSubscription(subscription.id)
          .timeout(_wait);
      expect(refreshed.isSuccess, isTrue);
      const icsTitle = 'Retained real ICS event';
      expect(installed.consumer.oauthAccounts, hasLength(1));
      expect(
        installed.consumer.allEvents().map((e) => e.title),
        containsAll([_title, icsTitle]),
      );
      final before = await f.disk();
      final subscriptions = installed.consumer.subscriptions
          .map((s) => s.toJson())
          .toList();
      final requests = f.requests.toList();
      final observed = <Map<String, Object>>[];
      installed.consumer.addListener(() {
        observed.add({
          'oauthIds': installed.consumer.oauthAccounts
              .map((a) => a.id)
              .toList(),
          'titles': installed.consumer.allEvents().map((e) => e.title).toList(),
          'subscriptions': installed.consumer.subscriptions
              .map((s) => s.toJson())
              .toList(),
        });
      });
      f.store.mutations.clear();
      f.store.injectSidecarAfterNextAccountsWrite = true;
      final result = await f
          .observe(
            installed.consumer.updateOAuthAccount(
              installed.account.copyWith(
                displayName: 'Rejected readback rename',
              ),
            ),
          )
          .timeout(_wait);
      expect(result.error, isNotNull);
      expect(f.store.injectSidecarAfterNextAccountsWrite, isFalse);
      expect(f.store.injectSidecarOnNextReload, isFalse);
      expect(f.store.readbackInjections, hasLength(1));
      final injectedRead = f.store.readbackInjections.single;
      expect(
        jsonDecode(
          injectedRead['accounts']! as String,
        ).single['account']['displayName'],
        'Rejected readback rename',
        reason: 'injection followed actual warm accounts persistence',
      );
      // Inspect immediately when the operation settles, before any later reload
      // or consumer operation could incidentally revoke the old projection.
      expect(installed.consumer.oauthAccounts, isEmpty);
      expect(installed.consumer.allEvents().map((e) => e.title), [icsTitle]);
      expect(
        installed.consumer.subscriptions.map((s) => s.toJson()).toList(),
        subscriptions,
      );
      expect(
        observed,
        isNotEmpty,
        reason: 'inventory rejection must notify projection revocation',
      );
      expect(
        observed.any(
          (s) =>
              (s['oauthIds']! as List).isEmpty &&
              (s['titles']! as List).contains(icsTitle) &&
              !(s['titles']! as List).contains(_title),
        ),
        isTrue,
      );
      expect(f.requests, requests);
      await f.settle();
      final after = await f.disk();
      expect(after, {...before, _unknownKey: 242});
      expect(
        after[_accounts],
        before[_accounts],
        reason: 'owned accounts safely roll back',
      );
      expect(
        after[f.cacheKey(installed.account.id)],
        before[f.cacheKey(installed.account.id)],
      );
      expect(after[_unknownKey], 242);
      expect(f.store.mutations, contains('set:$_accounts'));
      expect(f.store.mutations, isNot(contains('remove:$_unknownKey')));
      expect(f.requests, requests);
    }),
  );

  test(
    'OCI-F2-252 transaction scope replacement cancels hides OAuth and retains ICS',
    () => f.withHttp(() async {
      final installed = await f.install();
      const subscription = IcsSubscription(
        id: 'owned_consumer_scope_retained_ics',
        name: 'Scope retained ICS',
        url: 'https://owned-consumer-ics.example/calendar.ics',
      );
      await installed.consumer.addSubscription(subscription).timeout(_wait);
      final refreshed = await installed.consumer.syncSubscription(subscription.id)
          .timeout(_wait);
      expect(refreshed.isSuccess, isTrue);
      const icsTitle = 'Retained real ICS event';
      final before = await f.disk();
      final originalRaw = before[_owner]! as String;
      final original = OAuthScopedOwnerRecord.parse(originalRaw)!;
      final replacementFields = jsonDecode(originalRaw) as Map<String, dynamic>;
      final candidateOwner = 'g:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      replacementFields['scopedOwner'] = original.scopedOwner == candidateOwner
          ? 'g:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB' : candidateOwner;
      final replacementRaw = jsonEncode(replacementFields);
      final replacement = OAuthScopedOwnerRecord.parse(replacementRaw)!;
      expect(replacementRaw, isNot(originalRaw));
      expect(replacement.scopedOwner, isNot(original.scopedOwner));
      expect(replacement.oauthIncarnation, original.oauthIncarnation);
      expect(installed.consumer.oauthAccounts, hasLength(1));
      expect(installed.consumer.allEvents().map((e) => e.title),
          containsAll([_title, icsTitle]));
      final subscriptions = installed.consumer.subscriptions.map((s) => s.toJson()).toList();
      final requests = f.requests.toList();
      final notifications = <Map<String, Object>>[];
      installed.consumer.addListener(() {
        notifications.add({
          'oauthIds': installed.consumer.oauthAccounts.map((a) => a.id).toList(),
          'titles': installed.consumer.allEvents().map((e) => e.title).toList(),
        });
      });
      f.originalScopeForTeardown = originalRaw;
      f.replacedScopeForTeardown = replacementRaw;
      f.store.mutations.clear();
      f.store.replaceScopeAfterNextAccountsWrite = replacementRaw;
      final result = await f.observe(installed.consumer.updateOAuthAccount(
          installed.account.copyWith(displayName: 'Canceled scope readback rename')))
          .timeout(_wait);
      expect(result.error, isA<AccountPreferenceWriteCanceled>());
      expect(f.store.replaceScopeAfterNextAccountsWrite, isNull);
      expect(f.store.replaceScopeOnNextReload, isNull);
      expect(f.store.scopeReadbackInjections, hasLength(1));
      final injection = f.store.scopeReadbackInjections.single;
      expect(injection['scopeBefore'], originalRaw);
      expect(injection['scopeAfter'], replacementRaw);
      expect(jsonDecode(injection['accounts']! as String).single['account']['displayName'],
          'Canceled scope readback rename');
      // The generic cancellation must already have revoked the matching warm
      // projection; a later load is not allowed to make this assertion pass.
      expect(installed.consumer.oauthAccounts, isEmpty);
      expect(installed.consumer.allEvents().map((e) => e.title), [icsTitle]);
      expect(installed.consumer.subscriptions.map((s) => s.toJson()).toList(), subscriptions);
      expect(notifications, isNotEmpty);
      expect(notifications.any((n) => (n['oauthIds']! as List).isEmpty &&
          (n['titles']! as List).contains(icsTitle) &&
          !(n['titles']! as List).contains(_title)), isTrue);
      expect(f.requests, requests);
      await f.settle();
      final after = await f.disk();
      expect(after, {...before, _owner: replacementRaw});
      expect(after[_accounts], before[_accounts]);
      expect(after[f.cacheKey(installed.account.id)], before[f.cacheKey(installed.account.id)]);
      expect(after[_owner], replacementRaw, reason: 'rollback cannot overwrite foreign scope');
      expect(after.containsKey(_unknownKey), isFalse);
      expect(f.store.mutations, contains('set:$_accounts'));
      expect(f.store.mutations, isNot(contains('set:$_owner')));
      expect(f.store.mutations, isNot(contains('remove:$_owner')));
      expect(f.requests, requests);
      // Fixture teardown restores only the original test-owned scope, after
      // these measurements, and only if this exact injected replacement remains.
    }),
  );

}

class _RuntimeStamps {
  final epoch = OAuthCalendarStorage.epoch;
  final reset = OAuthCalendarStorage.resetRevision;
  final writes = AccountPreferenceWrites.generation;
  final account = AccountLocalDataCleaner.accountDataGeneration;
  void expectUnchanged() {
    expect(OAuthCalendarStorage.epoch, epoch);
    expect(OAuthCalendarStorage.resetRevision, reset);
    expect(AccountPreferenceWrites.generation, writes);
    expect(AccountLocalDataCleaner.accountDataGeneration, account);
  }
}

class _BackingStore extends InMemorySharedPreferencesStore {
  _BackingStore() : super.withData({});
  final mutations = <String>[];
  final issuedAccounts = <String>[];
  bool failNextAccountsWrite = false;
  bool failNextPendingRemove = false;
  bool injectSidecarAfterNextAccountsWrite = false;
  bool injectSidecarOnNextReload = false;
  final readbackInjections = <Map<String, Object>>[];
  String? replaceScopeAfterNextAccountsWrite;
  String? replaceScopeOnNextReload;
  final scopeReadbackInjections = <Map<String, Object>>[];
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    mutations.add('set:${logical(key)}');
    if (logical(key) == _accounts && value is String) {
      issuedAccounts.add(value);
    }
    if (logical(key) == _accounts && failNextAccountsWrite) {
      failNextAccountsWrite = false;
      return false;
    }
    final saved = await super.setValue(type, key, value);
    if (saved &&
        logical(key) == _accounts &&
        injectSidecarAfterNextAccountsWrite) {
      injectSidecarAfterNextAccountsWrite = false;
      injectSidecarOnNextReload = true;
    }
    if (saved && logical(key) == _accounts && replaceScopeAfterNextAccountsWrite != null) {
      replaceScopeOnNextReload = replaceScopeAfterNextAccountsWrite;
      replaceScopeAfterNextAccountsWrite = null;
    }
    return saved;
  }

  @override
  Future<bool> remove(String key) {
    mutations.add('remove:${logical(key)}');
    if (logical(key) == _pendingKey && failNextPendingRemove) {
      failNextPendingRemove = false;
      return Future<bool>.value(false);
    }
    return super.remove(key);
  }

  @override
  Future<bool> clear() {
    mutations.add('clear');
    return super.clear();
  }

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    final replacement = replaceScopeOnNextReload;
    if (replacement != null) {
      replaceScopeOnNextReload = null;
      final actual = await super.getAllWithParameters(parameters);
      scopeReadbackInjections.add({
        'accounts': actual['flutter.$_accounts']!,
        'scopeBefore': actual['flutter.$_owner']!,
        'scopeAfter': replacement,
      });
      expect(await super.setValue('String', 'flutter.$_owner', replacement), isTrue);
    }
    if (injectSidecarOnNextReload) {
      injectSidecarOnNextReload = false;
      // A non-cooperating backing writer inserts this key only on the first
      // read after the armed accounts set. It is outside the consumer's changes.
      final actual = await super.getAllWithParameters(parameters);
      readbackInjections.add({'accounts': actual['flutter.$_accounts']!});
      expect(await super.setValue('Int', 'flutter.$_unknownKey', 242), isTrue);
    }
    return super.getAllWithParameters(parameters);
  }

  Future<Map<String, Object>> backing() => super.getAll();
  Future<void> inject(String key, Object value) async {
    final type = switch (value) {
      String() => 'String',
      bool() => 'Bool',
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
}

class _Installed {
  _Installed(this.auth, this.consumer, this.lease, this.account);
  final AuthProvider auth;
  final CalendarSyncProvider consumer;
  final AuthGuestOAuthScopeLease lease;
  final OAuthCalendarAccount account;
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
  final holds = <_Hold>[];
  String acceptedEventAccessToken = 'synthetic-owned-consumer-access';
  String? originalScopeForTeardown;
  String? replacedScopeForTeardown;

  static Future<_Fixture> create() async {
    await AccountPreferenceWrites.drain().timeout(_wait);
    final previous = SharedPreferencesStorePlatform.instance;
    final store = _BackingStore();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = store;
    final prefs = await SharedPreferences.getInstance();
    await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    for (final entry in _ordinary.entries) {
      await store.inject(entry.key, entry.value);
    }
    await store.inject(_accounts, '[ \n ]');
    await prefs.reload();
    store.mutations.clear();
    return _Fixture(previous, store, prefs);
  }

  AuthProvider auth() {
    final auth = AuthProvider();
    auths.add(auth);
    return auth;
  }

  CalendarSyncProvider consumer([AuthProvider? auth]) {
    final consumer = auth == null
        ? CalendarSyncProvider()
        : CalendarSyncProvider(authProvider: auth);
    consumers.add(consumer);
    return consumer;
  }

  void disposeAuth(AuthProvider auth) {
    auth.dispose();
    auths.remove(auth);
  }

  void disposeConsumer(CalendarSyncProvider consumer) {
    consumer.dispose();
    consumers.remove(consumer);
  }

  String cacheKey(String id) => '${OAuthCalendarStorage.eventsKeyPrefix}$id';
  int count(String phase) => requests.where((r) => r == phase).length;
  _Hold hold(String phase) {
    final hold = _Hold(phase);
    holds.add(hold);
    return hold;
  }

  Future<void> withHttp(
    Future<void> Function() body,
  ) => http.runWithClient(body, () {
    final client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.host == 'owned-consumer-ics.example') {
        requests.add('ics');
        return http.Response(
          'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\n'
          'UID:retained-owned-consumer-ics\r\nSUMMARY:Retained real ICS event\r\n'
          'DTSTART:20261110T090000Z\r\nDTEND:20261110T100000Z\r\n'
          'END:VEVENT\r\nEND:VCALENDAR\r\n',
          200,
        );
      }
      final isTokenEndpoint =
          request.method == 'POST' &&
          request.url.host == 'oauth2.googleapis.com';
      final form = isTokenEndpoint ? Uri.splitQueryString(request.body) : null;
      final phase = isTokenEndpoint
          ? switch (form!['grant_type']) {
              'authorization_code' => 'token',
              'refresh_token' => 'refresh',
              _ => 'unexpected',
            }
          : request.method == 'GET' && request.url.host == 'www.googleapis.com'
          ? 'events'
          : 'unexpected';
      requests.add(phase);
      if (phase == 'unexpected') {
        throw StateError('Unexpected owned consumer HTTP request');
      }
      final waiting = holds.where(
        (h) => h.phase == phase && !h.started.isCompleted,
      );
      if (waiting.isNotEmpty) {
        final hold = waiting.first;
        hold.started.complete();
        await hold.release.future;
      }
      if (phase == 'token') {
        final tokenForm = form!;
        expect(request.method, 'POST');
        expect(tokenForm['grant_type'], 'authorization_code');
        expect(tokenForm['client_id'], 'synthetic-owned-consumer-client');
        expect(tokenForm['code_verifier'], _verifier);
        acceptedEventAccessToken = 'synthetic-owned-consumer-access';
        return http.Response(
          jsonEncode({
            'access_token': 'synthetic-owned-consumer-access',
            'refresh_token': 'synthetic-owned-consumer-refresh',
            'expires_in': 7200,
            'token_type': 'Bearer',
            'scope': 'https://www.googleapis.com/auth/calendar.readonly',
          }),
          200,
        );
      }
      if (phase == 'refresh') {
        final tokenForm = form!;
        expect(tokenForm['grant_type'], 'refresh_token');
        expect(tokenForm['client_id'], 'synthetic-owned-consumer-client');
        expect(tokenForm['refresh_token'], 'synthetic-owned-consumer-refresh');
        expect(tokenForm.containsKey('code'), isFalse);
        acceptedEventAccessToken = 'synthetic-owned-consumer-peer-access';
        return http.Response(
          jsonEncode({
            'access_token': 'synthetic-owned-consumer-peer-access',
            'refresh_token': 'synthetic-owned-consumer-peer-refresh',
            'expires_in': 7200,
            'token_type': 'Bearer',
            'scope': 'https://www.googleapis.com/auth/calendar.readonly',
          }),
          200,
        );
      }
      expect(
        request.headers['Authorization'],
        'Bearer $acceptedEventAccessToken',
      );
      return http.Response(
        jsonEncode({
          'items': [
            {
              'id': 'owned-consumer-event',
              'summary': _title,
              'start': {'dateTime': '2026-11-10T09:00:00Z'},
              'end': {'dateTime': '2026-11-10T10:00:00Z'},
            },
          ],
        }),
        200,
      );
    });
    clients.add(client);
    return client;
  });

  Future<OAuthCalendarAccount> connect(
    CalendarSyncProvider consumer, {
    String code = 'synthetic-owned-consumer-code',
  }) async {
    // The pending attempt is created by the real consumer, bound to the real
    // issuer, full draft and generated PKCE. No synthetic pending JSON is seeded.
    await consumer.savePendingOAuthAuthorization(
      provider: OAuthCalendarProvider.google,
      displayName: 'Owned consumer',
      clientId: 'synthetic-owned-consumer-client',
      clientSecret: '',
      redirectUri: 'duoyi://oauth/calendar',
      calendarId: 'primary',
      codeVerifier: _verifier,
      state: _state,
    );
    return dispatch(consumer, code: code);
  }

  Future<OAuthCalendarAccount> dispatch(
    CalendarSyncProvider consumer, {
    String code = 'synthetic-owned-consumer-code',
  }) => consumer.addOAuthAccountFromCode(
    provider: OAuthCalendarProvider.google,
    displayName: 'Owned consumer',
    clientId: 'synthetic-owned-consumer-client',
    clientSecret: '',
    redirectUri: 'duoyi://oauth/calendar',
    calendarId: 'primary',
    authorizationInput: OAuthAuthorizationInput.callback(
      Uri(
        scheme: 'duoyi',
        host: 'oauth',
        path: '/calendar',
        queryParameters: {'code': code, 'state': _state},
      ).toString(),
    ),
    expectedState: _state,
    codeVerifier: _verifier,
  );

  Future<_Installed> install() async {
    final issuer = auth();
    await issuer.loadFromStorage(refreshServerConfig: false).timeout(_wait);
    final provider = consumer(issuer);
    await provider.prepareOAuthScope(initialize: true).timeout(_wait);
    final lease = issuer.captureGuestOAuthScopeLease();
    final account = await connect(provider).timeout(_wait);
    expect(provider.allEvents().map((e) => e.title), [_title]);
    source(await disk(), lease);
    return _Installed(issuer, provider, lease, account);
  }

  OAuthOwnedSourceRecord source(
    Map<String, Object> raw,
    AuthGuestOAuthScopeLease lease,
  ) {
    final scope = OAuthScopedOwnerRecord.parse(lease.workspace.rawRecord)!;
    final accountsRaw = raw[_accounts]! as String;
    expect((jsonDecode(accountsRaw) as List).single['schema'], 2);
    final records = OAuthOwnedSourceRecord.parseList(
      accountsRaw,
      scope: scope,
    )!;
    expect(records, hasLength(1));
    expect(records.single.scopedOwner, scope.scopedOwner);
    expect(records.single.oauthIncarnation, scope.oauthIncarnation);
    return records.single;
  }

  OAuthOwnedPendingAuthorization pendingRecord(
    Map<String, Object> raw,
    AuthGuestOAuthScopeLease lease,
  ) {
    final scope = OAuthScopedOwnerRecord.parse(lease.workspace.rawRecord)!;
    final encoded = raw[_pendingKey]! as String;
    expect(jsonDecode(encoded)['schema'], 2);
    final pending = OAuthOwnedPendingAuthorization.parse(
      encoded,
      scope: scope,
    )!;
    expect(pending.scopedOwner, scope.scopedOwner);
    expect(pending.oauthIncarnation, scope.oauthIncarnation);
    return pending;
  }

  Future<Map<String, Object>> disk() async => {
    for (final entry in (await store.backing()).entries)
      _BackingStore.logical(entry.key): entry.value,
  };
  void expectOrdinary(Map<String, Object> raw) {
    for (final entry in _ordinary.entries) {
      expect(raw[entry.key], entry.value, reason: entry.key);
    }
    expect(
      raw.containsKey(AccountLocalDataCleaner.accountDataOwnerKey),
      isFalse,
    );
    expect(raw.containsKey(OAuthCalendarStorage.retirementFenceKey), isFalse);
    expect(
      raw.containsKey(OAuthCalendarStorage.scopeRetirementFenceKey),
      isFalse,
    );
  }

  Future<_Outcome<T>> observe<T>(Future<T> work) {
    final observed = work.then<_Outcome<T>>(
      (value) => _Outcome<T>.value(value),
      onError: (Object error, StackTrace _) => _Outcome<T>.error(error),
    );
    pending.add(observed.then<void>((_) {}));
    return observed;
  }

  Future<void> reject<T>(Future<T> work, [Matcher? matcher]) async {
    final result = await observe(work).timeout(_wait);
    expect(result.error, matcher ?? isNotNull);
  }

  Future<void> settle() async {
    await AccountPreferenceWrites.drain().timeout(_wait);
    await OAuthCalendarStorage.run<void>(
      () async {},
      epoch: OAuthCalendarStorage.epoch,
    ).timeout(_wait);
  }

  Future<void> close() async {
    // Faults target measured operations only, never rollback/fixture cleanup.
    store.replaceScopeAfterNextAccountsWrite = null;
    store.replaceScopeOnNextReload = null;
    for (final hold in holds) {
      if (!hold.release.isCompleted) hold.release.complete();
    }
    try {
      await Future.wait(pending).timeout(_wait);
      await settle();
      for (final consumer in consumers) {
        consumer.dispose();
      }
      for (final auth in auths) {
        auth.dispose();
      }
      final original = originalScopeForTeardown;
      final replacement = replacedScopeForTeardown;
      if (original != null && replacement != null) {
        final measured = await store.backing();
        if (measured['flutter.$_owner'] == replacement) {
          await store.inject(_owner, original);
          await prefs.reload();
        }
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
