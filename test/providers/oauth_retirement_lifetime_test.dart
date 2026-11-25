// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/oauth_calendar_storage.dart';
import 'package:duoyi/core/oauth_calendar_inventory.dart';
import 'package:duoyi/core/oauth_calendar_workspace_codec.dart';
import 'package:duoyi/core/oauth_refresh_journal.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _wait = Duration(seconds: 5);
const _accounts = 'duoyi_oauth_calendar_accounts_v1';
const _owner = AccountLocalDataCleaner.accountDataOwnerKey;
const _fence = OAuthCalendarStorage.retirementFenceKey;
const _device = 'lifetime_fixture_device_setting';
const _id = 'lifetime_expired_account';

// Real platform backing and production APIs. No cleanup/provider method stubs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() async => f = await _Fixture.create());
  tearDown(() async => f.close());

  test(
    'OL78-01 binding A cannot consume the independently announced B ticket',
    () async {
      final a = f.primary;
      final b = await f.slot('B');
      final ta = f.announce(store: a.prefs);
      final tb = f.announce(store: b.prefs);
      final sa = await f.bind(a, ta);
      final markerA = (await a.disk())[_fence];
      expect((await b.disk()).containsKey(_fence), isFalse);
      await f.finish(a, sa);
      expect(OAuthCalendarStorage.isAccountRetiring(a.prefs), isTrue);
      expect(OAuthCalendarStorage.isAccountRetiring(b.prefs), isTrue);
      expect(
        () => OAuthCalendarStorage.ensureAccountAdmissionLocked(a.prefs),
        throwsA(isA<OAuthAccountRetirementPending>()),
      );
      final sb = await f.bind(b, tb);
      expect((await b.disk())[_fence], isNot(markerA));
      expect((await a.disk()).containsKey(_fence), isFalse);
      expect(OAuthCalendarStorage.isAccountRetiring(a.prefs), isFalse);
      expect(OAuthCalendarStorage.isAccountRetiring(b.prefs), isTrue);
      await f.finish(b, sb);
      expect(OAuthCalendarStorage.isAccountRetiring(b.prefs), isFalse);
      expect(a.store.count('remove', _fence), 1);
      expect(b.store.count('remove', _fence), 1);
      expect((await a.disk())[_device], 'A');
      expect((await b.disk())[_device], 'B');
    },
  );

  test(
    'OL78-02 three tickets preserve B failed binding after A and C finish',
    () async {
      final a = f.primary;
      final b = await f.slot('B');
      final c = await f.slot('C');
      final ta = f.announce(store: a.prefs);
      final tb = f.announce(store: b.prefs);
      final tc = f.announce(store: c.prefs);
      final sa = await f.bind(a, ta);
      await f.finish(a, sa);
      b.store.rejectNextRemoveOrSet('set', _fence);
      expect(
        (await f.observe(f.bind(b, tb)).timeout(_wait)).error,
        isA<OAuthAccountRetirementPending>(),
      );
      expect(b.store.removals, isEmpty);
      expect((await b.disk()).containsKey(_fence), isFalse);
      final sc = await f.bind(c, tc);
      await f.finish(c, sc);
      expect(OAuthCalendarStorage.isAccountRetiring(a.prefs), isFalse);
      expect(OAuthCalendarStorage.isAccountRetiring(c.prefs), isFalse);
      expect(OAuthCalendarStorage.isAccountRetiring(b.prefs), isTrue);
      final retry = await f.bind(b, f.announce(store: b.prefs));
      await f.finish(b, retry);
      expect(OAuthCalendarStorage.isAccountRetiring(b.prefs), isFalse);
      expect(a.store.count('remove', _fence), 1);
      expect(c.store.count('remove', _fence), 1);
      expect(b.store.count('remove', _fence), 1);
    },
  );

  test(
    'OL78-03 older A completion cannot settle B failed unbound intent',
    () async {
      final a = f.primary;
      final b = await f.slot('B');
      final ta = f.announce(store: a.prefs);
      final tb = f.announce(store: b.prefs);
      OAuthCalendarStorage.failAccountRetirementAnnouncement(tb);
      final sa = await f.bind(a, ta);
      await f.finish(a, sa);
      expect(OAuthCalendarStorage.isAccountRetiring(a.prefs), isTrue);
      expect(OAuthCalendarStorage.isAccountRetiring(b.prefs), isTrue);
      final before = b.store.attempts.toList();
      expect(
        (await f.observe(f.bind(b, tb)).timeout(_wait)).error,
        isA<OAuthAccountRetirementPending>(),
      );
      expect(b.store.attempts, before);
      // Even a later checked A retirement cannot settle B's synthetic domain.
      final retryA = await f.bind(a, f.announce(store: a.prefs));
      await f.finish(a, retryA);
      expect(OAuthCalendarStorage.isAccountRetiring(a.prefs), isTrue);
      final retry = await f.bind(b, f.announce(store: b.prefs));
      await f.finish(b, retry);
      expect(OAuthCalendarStorage.isAccountRetiring(a.prefs), isFalse);
      expect(OAuthCalendarStorage.isAccountRetiring(b.prefs), isFalse);
    },
  );

  test(
    'OL78-04 bound retry cannot settle a newer same-domain failed ticket',
    () async {
      final a = f.primary;
      f.coreSlots.add(a);
      final failedA = f.announce(store: a.prefs);
      OAuthCalendarStorage.failAccountRetirementAnnouncement(failedA);
      final retryA = f.announce(store: a.prefs);
      final laterB = f.announce(store: a.prefs);
      final sa = await f.bind(a, retryA);
      OAuthCalendarStorage.failAccountRetirementAnnouncement(laterB);
      await f.finish(a, sa);
      expect(OAuthCalendarStorage.isAccountRetiring(a.prefs), isTrue);
      expect((await a.disk()).containsKey(_fence), isFalse);
      final sb = await f.bind(a, f.announce(store: a.prefs));
      await f.finish(a, sb);
      expect(OAuthCalendarStorage.isAccountRetiring(a.prefs), isFalse);
    },
  );

  test(
    'OL78-05 real cleaner store acquisition failure stays blocked until checked retry',
    () async {
      await f.readyCalendar();
      final before = await f.primary.disk();
      SharedPreferences.resetStatic();
      f.store.failNextRead = true;
      var called = false;
      final result = await f
          .observe(
            AccountLocalDataCleaner.runAccountRetirement<void>(() async {
              called = true;
            }),
          )
          .timeout(_wait);
      expect(result.error, isA<StateError>());
      expect(called, isFalse);
      expect(f.store.attempts, isEmpty);
      expect(await f.primary.disk(), before);
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isTrue);
      f.primary.prefs = await SharedPreferences.getInstance();
      final peer = f.calendar();
      expect(
        (await f.observe(peer.loadFromStorage()).timeout(_wait)).error,
        isNull,
        reason: 'Failed retirement revokes the issuer; load has no OAuth origin',
      );
      expect(peer.isOAuthReady, isFalse);
      expect(
        () => OAuthCalendarStorage.ensureAccountAdmissionLocked(f.prefs),
        throwsA(isA<OAuthAccountRetirementPending>()),
      );
      expect(
        (await f.observe(f.connect(peer)).timeout(_wait)).error,
        isA<OAuthScopedWorkspaceUnavailable>(),
      );
      expect(peer.oauthAccounts, isEmpty);
      expect(f.requests, isEmpty);
      expect(f.store.attempts, isEmpty);
      await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isFalse);
      expect(await f.primary.owned(), isEmpty);
      expect((await f.primary.disk())[_device], 'A');
    },
  );

  test(
    'OL78-06 queued cleaner request remains announced while first request is bound',
    () async {
      await f.seed();
      SharedPreferences.resetStatic();
      f.store.reads = 0;
      final acquisition = f.store.holdRead(1);
      final aGate = f.hold();
      final bGate = f.hold();
      var bCalled = false;
      final a = f.observe(
        AccountLocalDataCleaner.runAccountRetirement<void>(() async {
          aGate.started.complete();
          await aGate.release.future;
        }),
      );
      await acquisition.started.future.timeout(_wait);
      final b = f.observe(
        AccountLocalDataCleaner.runAccountRetirement<void>(() async {
          bCalled = true;
          bGate.started.complete();
          await bGate.release.future;
        }),
      );
      expect(OAuthCalendarStorage.isAccountRetiring(f.probe.prefs), isTrue);
      acquisition.release.complete();
      await aGate.started.future.timeout(_wait);
      f.primary.prefs = await SharedPreferences.getInstance();
      final markerA = (await f.primary.disk())[_fence];
      expect(markerA, isA<String>());
      expect(bCalled, isFalse);
      // Probe has no fence/session; only the still-unbound B ticket blocks it.
      expect((await f.probe.disk()).containsKey(_fence), isFalse);
      expect(OAuthCalendarStorage.isAccountRetiring(f.probe.prefs), isTrue);
      aGate.release.complete();
      expect((await a.timeout(_wait)).error, isNull);
      await bGate.started.future.timeout(_wait);
      expect((await f.primary.disk())[_fence], isNot(markerA));
      expect(f.store.count('remove', _fence), 1);
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isTrue);
      bGate.release.complete();
      expect((await b.timeout(_wait)).error, isNull);
      expect(f.store.count('set', _fence), 2);
      expect(f.store.count('remove', _fence), 2);
      expect(OAuthCalendarStorage.isAccountRetiring(f.probe.prefs), isFalse);
    },
  );

  test(
    'OL78-07 outer return waits for an unawaited enrolled child and its cleanup',
    () async {
      await f.readyCalendar();
      final gate = f.hold();
      final returned = Completer<void>();
      var completed = false;
      final epoch = OAuthCalendarStorage.epoch;
      final outer = f.observe(
        AccountLocalDataCleaner.runAccountRetirement<int>(() async {
          unawaited(
            f
                .observe(
                  AccountLocalDataCleaner.runAccountRetirement<void>(() async {
                    gate.started.complete();
                    await gate.release.future;
                    await AccountLocalDataCleaner.clearSharedPreferences();
                  }),
                )
                .then<void>((result) {
                  expect(result.error, isNull);
                }),
          );
          returned.complete();
          return 7;
        }).then((value) {
          completed = true;
          return value;
        }),
      );
      await returned.future.timeout(_wait);
      await gate.started.future.timeout(_wait);
      await _turn();
      expect(completed, isFalse);
      expect(AccountPreferenceWrites.isBoundaryActive, isTrue);
      expect(f.store.count('remove', _fence), 0);
      expect(OAuthCalendarStorage.epoch, epoch);
      expect((await f.primary.disk()).containsKey(_accounts), isTrue);
      final mutations = f.store.attempts.toList();
      expect(
        () => OAuthCalendarStorage.ensureAccountAdmissionLocked(f.prefs),
        throwsA(isA<OAuthAccountRetirementPending>()),
      );
      expect(
        (await f.observe(f.connect(f.calendar())).timeout(_wait)).error,
        isA<OAuthScopedWorkspaceUnavailable>(),
      );
      expect(f.store.attempts, mutations);
      expect(f.requests, isEmpty);
      gate.release.complete();
      final result = await outer.timeout(_wait);
      expect(result.error, isNull);
      expect(result.value, 7);
      expect(f.store.count('set', _fence), 1);
      expect(f.store.count('remove', _fence), 1);
      expect(OAuthCalendarStorage.epoch, epoch + 1);
      expect(await f.primary.owned(), isEmpty);
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isFalse);
    },
  );

  test(
    'OL78-08 caught nested cleanup failure still poisons the outer session',
    () async {
      await f.seed();
      f.store.rejectNextRemoveOrSet('remove', _accounts, persist: true);
      final epoch = OAuthCalendarStorage.epoch;
      Object? caught;
      final result = await f
          .observe(
            AccountLocalDataCleaner.runAccountRetirement<void>(() async {
              try {
                await AccountLocalDataCleaner.clearSharedPreferences();
              } catch (error) {
                caught = error;
              }
              expect(caught, isA<StateError>());
              expect(await f.primary.owned(), isEmpty);
              final attempts = f.store.attempts.toList();
              expect(
                (await f.observe(
                  AccountLocalDataCleaner.clearSharedPreferences(),
                )).error,
                same(caught),
              );
              expect(f.store.attempts, attempts);
            }),
          )
          .timeout(_wait);
      expect(result.error, same(caught));
      expect(OAuthCalendarStorage.epoch, epoch);
      expect(f.store.count('remove', _fence), 0);
      expect((await f.primary.disk()).containsKey(_fence), isTrue);
      await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
      expect(OAuthCalendarStorage.epoch, epoch + 1);
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isFalse);
    },
  );

  test(
    'OL78-09 late enrolled child cleanup failure poisons an already returned root',
    () async {
      await f.seed();
      final gate = f.hold();
      f.store.rejectNextRemoveOrSet('remove', _accounts, persist: true);
      final epoch = OAuthCalendarStorage.epoch;
      Future<_Result<void>>? child;
      final outer = f.observe(
        AccountLocalDataCleaner.runAccountRetirement<void>(() async {
          child = f.observe(
            AccountLocalDataCleaner.runAccountRetirement<void>(() async {
              gate.started.complete();
              await gate.release.future;
              await AccountLocalDataCleaner.clearSharedPreferences();
            }),
          );
        }),
      );
      await gate.started.future.timeout(_wait);
      await _turn();
      expect(f.store.count('remove', _fence), 0);
      gate.release.complete();
      final childResult = await child!.timeout(_wait);
      final outerResult = await outer.timeout(_wait);
      expect(childResult.error, isA<StateError>());
      expect(outerResult.error, same(childResult.error));
      expect(OAuthCalendarStorage.epoch, epoch);
      expect(await f.primary.owned(), isEmpty);
      expect(f.store.count('remove', _fence), 0);
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isTrue);
      await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isFalse);
    },
  );

  for (final fromChild in <bool>[false, true]) {
    test(
      fromChild
          ? 'OL78-11 completed child Zone clear cannot change the new owner generation'
          : 'OL78-10 completed root Zone clear cannot change the new owner generation',
      () async {
        await f.seed();
        Zone? stale;
        await AccountLocalDataCleaner.runAccountRetirement<void>(() async {
          if (fromChild) {
            await AccountLocalDataCleaner.runAccountRetirement<void>(() async {
              stale = Zone.current;
            });
          } else {
            stale = Zone.current;
          }
        }).timeout(_wait);
        await f.seed(owner: 'id:new-owner');
        final before = await f.primary.disk();
        final writes = AccountPreferenceWrites.generation;
        final account = AccountLocalDataCleaner.accountDataGeneration;
        final epoch = OAuthCalendarStorage.epoch;
        final result = await f
            .observe(stale!.run(AccountLocalDataCleaner.clearSharedPreferences))
            .timeout(_wait);
        expect(result.error, isA<OAuthAccountRetirementPending>());
        expect(f.store.attempts, isEmpty);
        expect(await f.primary.disk(), before);
        expect(AccountPreferenceWrites.generation, writes);
        expect(AccountLocalDataCleaner.accountDataGeneration, account);
        expect(OAuthCalendarStorage.epoch, epoch);
        expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isFalse);
        var ran = false;
        final nested = stale!.run(
          () => AccountLocalDataCleaner.runAccountRetirement<void>(() async {
            ran = true;
          }),
        );
        expect(
          (await f.observe(nested).timeout(_wait)).error,
          isA<OAuthAccountRetirementPending>(),
        );
        expect(ran, isFalse);
        expect(f.store.attempts, isEmpty);
        expect(AccountPreferenceWrites.generation, writes);
      },
    );
  }

  test(
    'OL78-12 awaited three-level nested cleanup completes without deadlock',
    () async {
      await f.seed();
      final epoch = OAuthCalendarStorage.epoch;
      final result = await f
          .observe(
            AccountLocalDataCleaner.runAccountRetirement<int>(() async {
              final marker = (await f.primary.disk())[_fence];
              return AccountLocalDataCleaner.runAccountRetirement<int>(
                () async {
                  await AccountLocalDataCleaner.runAccountRetirement<void>(
                    () async {
                      await AccountLocalDataCleaner.clearSharedPreferences();
                      expect((await f.primary.disk())[_fence], marker);
                      await f.prefs.setString('todos', 'synthetic-second-pass');
                      await AccountLocalDataCleaner.clearSharedPreferences();
                      expect((await f.primary.disk())[_fence], marker);
                    },
                  );
                  return 12;
                },
              );
            }),
          )
          .timeout(_wait);
      expect(result.error, isNull);
      expect(result.value, 12);
      expect(f.store.count('set', _fence), 1);
      expect(f.store.count('remove', _fence), 1);
      expect(OAuthCalendarStorage.epoch, epoch + 1);
      expect(AccountPreferenceWrites.isBoundaryActive, isFalse);
      expect(await f.primary.owned(), isEmpty);
    },
  );

  test(
    'OL78-13 returned root Zone is stale while its enrolled child remains active',
    () async {
      await f.seed();
      final gate = f.hold();
      Zone? root;
      final outer = f.observe(
        AccountLocalDataCleaner.runAccountRetirement<void>(() async {
          root = Zone.current;
          unawaited(
            f
                .observe(
                  AccountLocalDataCleaner.runAccountRetirement<void>(() async {
                    gate.started.complete();
                    await gate.release.future;
                    await AccountLocalDataCleaner.clearSharedPreferences();
                  }),
                )
                .then<void>((result) {
                  expect(result.error, isNull);
                }),
          );
        }),
      );
      await gate.started.future.timeout(_wait);
      await _turn();
      final attempts = f.store.attempts.toList();
      final writes = AccountPreferenceWrites.generation;
      expect(
        (await f
                .observe(
                  root!.run(AccountLocalDataCleaner.clearSharedPreferences),
                )
                .timeout(_wait))
            .error,
        isA<OAuthAccountRetirementPending>(),
      );
      expect(f.store.attempts, attempts);
      expect(AccountPreferenceWrites.generation, writes);
      expect(f.store.count('remove', _fence), 0);
      gate.release.complete();
      expect((await outer.timeout(_wait)).error, isNull);
      expect(f.store.count('remove', _fence), 1);
    },
  );

  const refreshCases = <(String, _Revocation)>[
    (
      'OL78-14 caller revoked after authoritative OAuth read dispatches zero HTTP',
      _Revocation.caller,
    ),
    (
      'OL78-15 source revoked after authoritative OAuth read dispatches zero HTTP',
      _Revocation.source,
    ),
    (
      'OL78-16 unbound retirement after authoritative OAuth read dispatches zero HTTP',
      _Revocation.retirement,
    ),
    (
      'OL78-17 admitted expired refresh crosses the same read observer and succeeds',
      _Revocation.none,
    ),
  ];
  for (final scenario in refreshCases) {
    test(scenario.$1, () async {
      var provider = await f.readyCalendar();
      expect(provider.isOAuthReady, isTrue);
      expect(provider.oauthAccounts.single.id, _id);
      expect(
        provider.oauthAccounts.single.expiresAt.isAfter(DateTime.now()),
        isTrue,
      );
      // Expiry is a credential field in the current owned schema. Preserve
      // the old fresh-snapshot/expired-backing vector as a stale-source negative.
      await f.writeOwnedExpiry(expired: true);
      expect(
        provider.oauthAccounts.single.expiresAt.isAfter(DateTime.now()),
        isTrue,
      );
      final staleBacking = await f.primary.disk();
      final staleRequest = OAuthCalendarStorage.beginRequest(_id);
      await provider.syncAll().timeout(_wait);
      expect(f.requests, isEmpty);
      expect(f.store.attempts, isEmpty);
      expect(await f.primary.disk(), staleBacking);
      expect(OAuthCalendarStorage.ownsRequest(_id, staleRequest), isTrue);

      // The actual refresh control loads the matching expired owned source.
      // Its authority comes from the same real Auth issuer, never from decoding.
      provider = f.calendar();
      await provider.loadFromStorage().timeout(_wait);
      expect(provider.isOAuthReady, isTrue);
      expect(provider.oauthAccounts.single.id, _id);
      expect(provider.oauthAccounts.single.expiresAt, DateTime.utc(2000));
      final before = await f.primary.disk();
      f.store.attempts.clear();
      f.store.reads = 0;
      // One ICS reload, then the opening authoritative OAuth reload. The
      // follower runs only after the OAuth lane's final readback allocates
      // request ownership, and before the new refresh-claim lane writes.
      final read = f.store.holdRead(2);
      final observed = Completer<void>();
      var queued = false;
      var callerCurrent = true;
      OAuthAccountRetirementAnnouncement? ticket;
      final predecessor = OAuthCalendarStorage.beginRequest(_id);
      Future<_Result<void>>? laneObserver;
      bool caller() {
        if (!queued && f.store.reads == 2 && read.release.isCompleted) {
          queued = true;
          // This real lane follower awaits the current OAuth operation's
          // result, including its actual account row read. No await is added
          // to production between the refresh guard and HTTP sender.
          laneObserver = f.observe(
            OAuthCalendarStorage.run<void>(() async {
              expect(f.requests, isEmpty);
              expect(f.store.attempts, isEmpty);
              expect(
                OAuthCalendarStorage.ownsRequest(_id, predecessor + 1),
                isTrue,
              );
              switch (scenario.$2) {
                case _Revocation.caller:
                  callerCurrent = false;
                case _Revocation.source:
                  OAuthCalendarStorage.sourceChanged(_id);
                case _Revocation.retirement:
                  ticket = f.announce();
                case _Revocation.none:
                  break;
              }
              observed.complete();
            }, epoch: OAuthCalendarStorage.epoch),
          );
        }
        return callerCurrent;
      }

      final sync = f.observe(provider.syncAll(isCurrent: caller));
      await read.started.future.timeout(_wait);
      expect(f.requests, isEmpty);
      read.release.complete();
      await observed.future.timeout(_wait);
      expect((await laneObserver!.timeout(_wait)).error, isNull);
      expect((await sync.timeout(_wait)).error, isNull);
      expect(queued, isTrue);
      if (scenario.$2 == _Revocation.none) {
        expect(f.requests, ['refresh', 'events']);
        expect(
          provider.oauthAccounts.single.accessToken,
          'synthetic-renewed-access',
        );
        expect(f.store.count('set', _accounts), greaterThanOrEqualTo(1));
        expect(
          f.store.count('set', OAuthCalendarStorage.refreshJournalKey),
          greaterThanOrEqualTo(2),
        );
        await f.expectOwnedRefreshCommitted();
      } else {
        expect(f.requests, isEmpty);
        expect(f.store.attempts, isEmpty);
        expect(await f.primary.disk(), before);
        expect(provider.oauthLocalCommitReceipts, isEmpty);
        expect(OAuthCalendarStorage.ownsRequest(_id, predecessor + 1), isTrue);
        if (ticket != null) {
          expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isTrue);
          OAuthCalendarStorage.failAccountRetirementAnnouncement(ticket!);
          await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
          await f.readyCalendar(expired: true);
        }
        // A fresh provider really refreshes afterward: cancellation cannot
        // strand a refreshing placeholder or steal its fresh operation.
        final peer = f.calendar();
        await peer.loadFromStorage().timeout(_wait);
        await peer.syncAll().timeout(_wait);
        expect(f.requests, ['refresh', 'events']);
        expect(
          peer.oauthAccounts.single.accessToken,
          'synthetic-renewed-access',
        );
        await f.expectOwnedRefreshCommitted();
      }
    });
  }

  test(
    'OL78-18 same-domain retry recovers an earlier ticket failing before bind',
    () async {
      final a = f.primary;
      f.coreSlots.add(a);
      final earlier = f.announce(store: a.prefs);
      final retry = f.announce(store: a.prefs);
      // Queue predecessors can fail after the retry was announced, but before
      // it acquires its store. Recovery must be captured at checked binding.
      OAuthCalendarStorage.failAccountRetirementAnnouncement(earlier);
      final session = await f.bind(a, retry);
      await f.finish(a, session);
      expect(OAuthCalendarStorage.isAccountRetiring(a.prefs), isFalse);
      expect(a.store.count('set', _fence), 1);
      expect(a.store.count('remove', _fence), 1);
    },
  );

  test(
    'OL78-19 same-domain retry cannot consume an older still-active ticket',
    () async {
      final a = f.primary;
      f.coreSlots.add(a);
      final active = f.announce(store: a.prefs);
      final failed = f.announce(store: a.prefs);
      OAuthCalendarStorage.failAccountRetirementAnnouncement(failed);
      final retry = await f.bind(a, f.announce(store: a.prefs));
      await f.finish(a, retry);
      expect(OAuthCalendarStorage.isAccountRetiring(a.prefs), isTrue);
      final activeSession = await f.bind(a, active);
      await f.finish(a, activeSession);
      expect(OAuthCalendarStorage.isAccountRetiring(a.prefs), isFalse);
      expect(a.store.count('remove', _fence), 2);
    },
  );

  test(
    'OL78-20 default-domain binding proves actual singleton identity before mutation',
    () async {
      final a = f.primary;
      final b = await f.slot('B'); // B is the actual getInstance singleton.
      final ticket = f.announce();
      expect(
        (await f.observe(f.bind(a, ticket)).timeout(_wait)).error,
        isA<OAuthAccountRetirementPending>(),
      );
      expect(a.store.attempts, isEmpty);
      expect((await a.disk()).containsKey(_fence), isFalse);
      expect(OAuthCalendarStorage.isAccountRetiring(a.prefs), isTrue);
      final session = await f.bind(b, ticket);
      await f.finish(b, session);
      expect(OAuthCalendarStorage.isAccountRetiring(a.prefs), isFalse);
      expect(OAuthCalendarStorage.isAccountRetiring(b.prefs), isFalse);
      expect(a.store.attempts, isEmpty);
      expect(b.store.count('remove', _fence), 1);
    },
  );

  test(
    'OL78-21 live child can enroll nested cleanup after the outer body returns',
    () async {
      await f.seed();
      final gate = f.hold();
      var nested = false;
      final outer = f.observe(
        AccountLocalDataCleaner.runAccountRetirement<void>(() async {
          unawaited(
            f
                .observe(
                  AccountLocalDataCleaner.runAccountRetirement<void>(() async {
                    gate.started.complete();
                    await gate.release.future;
                    await AccountLocalDataCleaner.runAccountRetirement<void>(
                      () async {
                        nested = true;
                        await AccountLocalDataCleaner.clearSharedPreferences();
                      },
                    );
                  }),
                )
                .then<void>((result) {
                  expect(result.error, isNull);
                }),
          );
        }),
      );
      await gate.started.future.timeout(_wait);
      await _turn();
      expect(nested, isFalse);
      expect(f.store.count('remove', _fence), 0);
      gate.release.complete();
      expect((await outer.timeout(_wait)).error, isNull);
      expect(nested, isTrue);
      expect(f.store.count('set', _fence), 1);
      expect(f.store.count('remove', _fence), 1);
      expect(await f.primary.owned(), isEmpty);
    },
  );

  test(
    'OL78-22 child result waits for descendants while its ended body Zone is stale',
    () async {
      await f.seed();
      final gate = f.hold();
      Zone? endedChild;
      var childSettled = false;
      Future<_Result<void>>? child;
      final outer = f.observe(
        AccountLocalDataCleaner.runAccountRetirement<void>(() async {
          child = f.observe(
            AccountLocalDataCleaner.runAccountRetirement<void>(() async {
              endedChild = Zone.current;
              unawaited(
                f
                    .observe(
                      AccountLocalDataCleaner.runAccountRetirement<
                        void
                      >(() async {
                        gate.started.complete();
                        await gate.release.future;
                        await AccountLocalDataCleaner.clearSharedPreferences();
                      }),
                    )
                    .then<void>((result) {
                      expect(result.error, isNull);
                    }),
              );
            }).then((_) {
              childSettled = true;
            }),
          );
        }),
      );
      await gate.started.future.timeout(_wait);
      await _turn();
      expect(childSettled, isFalse);
      expect(f.store.count('remove', _fence), 0);
      final writes = AccountPreferenceWrites.generation;
      final attempts = f.store.attempts.toList();
      expect(
        (await f
                .observe(
                  endedChild!.run(
                    AccountLocalDataCleaner.clearSharedPreferences,
                  ),
                )
                .timeout(_wait))
            .error,
        isA<OAuthAccountRetirementPending>(),
      );
      expect(AccountPreferenceWrites.generation, writes);
      expect(f.store.attempts, attempts);
      gate.release.complete();
      expect((await child!.timeout(_wait)).error, isNull);
      expect((await outer.timeout(_wait)).error, isNull);
      expect(childSettled, isTrue);
      expect(f.store.count('remove', _fence), 1);
      expect(await f.primary.owned(), isEmpty);
    },
  );

  test(
    'OL78-23 default cleanup settles failed explicit singleton alias without consuming another domain',
    () async {
      await f.seed();
      expect(identical(await SharedPreferences.getInstance(), f.prefs), isTrue);
      expect(identical(f.prefs, f.probe.prefs), isFalse);
      f.coreSlots.add(f.probe);
      final explicitAlias = f.announce(store: f.prefs);
      final foreign = f.announce(store: f.probe.prefs);
      OAuthCalendarStorage.failAccountRetirementAnnouncement(explicitAlias);
      OAuthCalendarStorage.failAccountRetirementAnnouncement(foreign);
      final foreignBefore = await f.probe.disk();
      final epoch = OAuthCalendarStorage.epoch;
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isTrue);

      // The actual cleaner uses a default-domain announcement and obtains the
      // existing real singleton. It must recognize that store's explicit alias.
      final cleared = await f
          .observe(AccountLocalDataCleaner.clearSharedPreferences())
          .timeout(_wait);
      expect(cleared.error, isNull);
      expect(await f.primary.owned(), isEmpty);
      expect((await f.primary.disk()).containsKey(_fence), isFalse);
      expect((await f.primary.disk())[_device], 'A');
      expect(f.store.count('set', _fence), 1);
      expect(f.store.count('remove', _fence), 1);
      expect(OAuthCalendarStorage.epoch, epoch + 1);
      expect(await f.probe.disk(), foreignBefore);
      expect(f.probe.store.attempts, isEmpty);
      // Conservative global blocking proves foreign intent was not consumed.
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isTrue);
      expect(
        () => OAuthCalendarStorage.ensureAccountAdmissionLocked(f.prefs),
        throwsA(isA<OAuthAccountRetirementPending>()),
      );

      // The foreign domain can recover only its own ticket. If the first clear
      // left the singleton alias behind, this completion cannot conceal it.
      final retry = await f.bind(f.probe, f.announce(store: f.probe.prefs));
      await f.finish(f.probe, retry).timeout(_wait);
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isFalse);
      expect(OAuthCalendarStorage.isAccountRetiring(f.probe.prefs), isFalse);
      expect(f.probe.store.count('set', _fence), 1);
      expect(f.probe.store.count('remove', _fence), 1);
      expect((await f.probe.disk())[_device], 'probe');
    },
  );

  test(
    'OL78-24 explicit singleton retry settles failed default alias without consuming another domain',
    () async {
      expect(identical(await SharedPreferences.getInstance(), f.prefs), isTrue);
      expect(identical(f.prefs, f.probe.prefs), isFalse);
      f.coreSlots.add(f.probe);
      final defaultAlias = f.announce();
      final foreign = f.announce(store: f.probe.prefs);
      OAuthCalendarStorage.failAccountRetirementAnnouncement(defaultAlias);
      OAuthCalendarStorage.failAccountRetirementAnnouncement(foreign);
      final foreignBefore = await f.probe.disk();
      final primaryBefore = await f.primary.disk();
      expect(await f.primary.owned(), isEmpty);

      final singletonRetry = await f.bind(
        f.primary,
        f.announce(store: f.prefs),
      );
      await f.finish(f.primary, singletonRetry).timeout(_wait);
      expect(await f.primary.disk(), primaryBefore);
      expect(f.store.count('set', _fence), 1);
      expect(f.store.count('remove', _fence), 1);
      expect(await f.probe.disk(), foreignBefore);
      expect(f.probe.store.attempts, isEmpty);
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isTrue);
      expect(
        () => OAuthCalendarStorage.ensureAccountAdmissionLocked(f.prefs),
        throwsA(isA<OAuthAccountRetirementPending>()),
      );

      final foreignRetry = await f.bind(
        f.probe,
        f.announce(store: f.probe.prefs),
      );
      await f.finish(f.probe, foreignRetry).timeout(_wait);
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isFalse);
      expect(OAuthCalendarStorage.isAccountRetiring(f.probe.prefs), isFalse);
      expect(f.probe.store.count('set', _fence), 1);
      expect(f.probe.store.count('remove', _fence), 1);
      expect((await f.probe.disk())[_device], 'probe');
    },
  );
}

enum _Revocation { caller, source, retirement, none }

bool _owned(String key) =>
    key != _fence &&
    (AccountLocalDataCleaner.accountScopedKeys.contains(key) ||
        AccountLocalDataCleaner.accountScopedPrefixes.any(key.startsWith));

// A zero-duration event lets already queued root-finally microtasks settle;
// actual release/order assertions use explicit gates, never elapsed sleeps.
Future<void> _turn() => Future<void>.delayed(Duration.zero);

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

class _ReadHold extends _Hold {
  _ReadHold(this.number);
  final int number;
}

class _BackingStore extends InMemorySharedPreferencesStore {
  _BackingStore(String label) : super.withData({'flutter.$_device': label});
  final attempts = <String>[];
  final holds = <_ReadHold>[];
  final _reject = <String, bool>{};
  int reads = 0;
  bool failNextRead = false;

  _ReadHold holdRead(int number) {
    final hold = _ReadHold(number);
    holds.add(hold);
    return hold;
  }

  void rejectNextRemoveOrSet(
    String operation,
    String key, {
    bool persist = false,
  }) => _reject['$operation:$key'] = persist;
  int count(String operation, String key) =>
      attempts.where((value) => value == '$operation:$key').length;
  List<String> get removals =>
      attempts.where((value) => value.startsWith('remove:')).toList();
  Future<Map<String, Object>> backing() => super.getAll();

  @override
  Future<Map<String, Object>> getAll() async {
    reads++;
    for (final hold in holds) {
      if (hold.number == reads && !hold.started.isCompleted) {
        hold.started.complete();
        await hold.release.future;
      }
    }
    if (failNextRead) {
      failNextRead = false;
      throw StateError('synthetic prebind store acquisition failure');
    }
    return super.getAll();
  }

  Future<bool> _mutate(
    String operation,
    String key,
    Future<bool> Function() persist,
  ) async {
    final id = '$operation:${key.substring('flutter.'.length)}';
    attempts.add(id);
    if (_reject.containsKey(id)) {
      final writeFirst = _reject.remove(id)!;
      if (writeFirst) expect(await persist(), isTrue);
      return false;
    }
    return persist();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) =>
      _mutate('set', key, () => super.setValue(type, key, value));
  @override
  Future<bool> remove(String key) =>
      _mutate('remove', key, () => super.remove(key));

  void releaseAll() {
    for (final hold in holds) {
      if (!hold.release.isCompleted) hold.release.complete();
    }
    _reject.clear();
    failNextRead = false;
  }
}

class _Slot {
  _Slot(this.store, this.prefs);
  final _BackingStore store;
  SharedPreferences prefs;
  Future<Map<String, Object>> disk() async => {
    for (final entry in (await store.backing()).entries)
      entry.key.substring('flutter.'.length): entry.value,
  };
  Future<Map<String, Object>> owned() async => {
    for (final entry in (await disk()).entries)
      if (_owned(entry.key)) entry.key: entry.value,
  };
}

class _Fixture {
  _Fixture(this.previous, this.primary, this.probe) {
    client = MockClient((request) async {
      if (request.method == 'POST') {
        expect(request.url.host, 'oauth2.googleapis.com');
        expect(request.bodyFields['grant_type'], 'refresh_token');
        expect(
          request.bodyFields['refresh_token'],
          'synthetic-expired-refresh',
        );
        final raw = (await primary.disk())[OAuthCalendarStorage.refreshJournalKey];
        expect(raw, isA<String>(), reason: 'Durable refresh claim before HTTP');
        final journal = OAuthOwnedRefreshJournal.parse(raw as String, scope: scope!);
        expect(journal, isNotNull);
        expect(journal!.phase, OAuthRefreshPhase.dispatched);
        expect(journal.originalSource.encode(), installedSource!.encode());
        requests.add('refresh');
        return _json({
          'access_token': 'synthetic-renewed-access',
          'refresh_token': 'synthetic-renewed-refresh',
          'expires_in': 3600,
          'token_type': 'Bearer',
        });
      }
      requests.add('events');
      expect(request.method, 'GET');
      expect(request.url.host, 'www.googleapis.com');
      expect(
        request.headers['Authorization'],
        'Bearer synthetic-renewed-access',
      );
      return _json({'items': <Object>[]});
    });
  }
  final SharedPreferencesStorePlatform previous;
  final _Slot primary;
  final _Slot probe;
  final coreSlots = <_Slot>{};
  final providers = <CalendarSyncProvider>[];
  final authProviders = <AuthProvider>[];
  AuthProvider? issuer;
  OAuthScopedOwnerRecord? scope;
  OAuthOwnedSourceRecord? installedSource;
  final pending = <Future<void>>[];
  final holds = <_Hold>[];
  final requests = <String>[];
  final tickets = <OAuthAccountRetirementAnnouncement>[];
  late final MockClient client;
  SharedPreferences get prefs => primary.prefs;
  _BackingStore get store => primary.store;

  static Future<_Slot> _makeSlot(String label) async {
    SharedPreferences.resetStatic();
    final store = _BackingStore(label);
    SharedPreferencesStorePlatform.instance = store;
    return _Slot(store, await SharedPreferences.getInstance());
  }

  static Future<_Fixture> create() async {
    await AccountPreferenceWrites.drain().timeout(_wait);
    final previous = SharedPreferencesStorePlatform.instance;
    final probe = await _makeSlot('probe');
    final primary = await _makeSlot('A');
    await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    primary.store.attempts.clear();
    return _Fixture(previous, primary, probe);
  }

  Future<_Slot> slot(String label) async {
    coreSlots.add(primary);
    final result = await _makeSlot(label);
    coreSlots.add(result);
    return result;
  }

  OAuthAccountRetirementAnnouncement announce({SharedPreferences? store}) {
    final ticket = OAuthCalendarStorage.announceAccountRetirement(store: store);
    tickets.add(ticket);
    return ticket;
  }

  Future<OAuthAccountRetirementSession> bind(
    _Slot slot,
    OAuthAccountRetirementAnnouncement ticket,
  ) {
    SharedPreferencesStorePlatform.instance = slot.store;
    return AccountPreferenceWrites.boundary(
      () => OAuthCalendarStorage.beginAccountRetirementLocked(
        slot.prefs,
        announcement: ticket,
      ),
    );
  }

  Future<void> finish(_Slot slot, OAuthAccountRetirementSession session) {
    SharedPreferencesStorePlatform.instance = slot.store;
    return AccountPreferenceWrites.boundary(
      () => OAuthCalendarStorage.finishAccountRetirementLocked(
        session,
        hasRemainingOwnedData: (prefs) => prefs.getKeys().any(_owned),
      ),
    );
  }

  Future<void> seed({
    bool expired = false,
    String owner = 'id:departing-owner',
  }) async {
    final account = OAuthCalendarAccount(
      id: _id,
      provider: OAuthCalendarProvider.google,
      displayName: 'Lifetime calendar',
      clientId: 'synthetic-client',
      redirectUri: 'duoyi://oauth/calendar',
      accessToken: 'synthetic-expired-access',
      refreshToken: 'synthetic-expired-refresh',
      expiresAt: expired ? DateTime.utc(2000) : DateTime.utc(2099),
    );
    expect(await prefs.setString(_owner, owner), isTrue);
    expect(
      await prefs.setString(_accounts, jsonEncode([account.toJson()])),
      isTrue,
    );
    expect(await prefs.setString('todos', '[]'), isTrue);
    store.attempts.clear();
  }

  Future<CalendarSyncProvider> readyCalendar({bool expired = false}) async {
    // Called only on an empty OAuth inventory, before installing fault plans.
    final next = AuthProvider(
      client: ApiClient(baseUrl: 'https://duoyi.test', httpClient: client),
    );
    authProviders.add(next);
    expect(next.isGuestWorkspaceReady, isFalse);
    await http.runWithClient(
      () => next.loadFromStorage(refreshServerConfig: false),
      () => client,
    ).timeout(_wait);
    expect(next.isGuestWorkspaceReady, isTrue);
    expect(next.captureOAuthScopeLease,
        throwsA(isA<OAuthScopedWorkspaceUnavailable>()));
    await next.initializeOAuthScope().timeout(_wait);
    final lease = next.captureOAuthScopeLease();
    expect(next.isOAuthScopeLeaseCurrent(lease), isTrue);
    issuer = next;
    scope = OAuthScopedOwnerRecord.parse(lease.workspace.rawRecord)!;
    expect(scope!.scopeKind, 'guest');
    installedSource = null;
    await writeOwnedExpiry(expired: expired);
    await next.restoreOAuthScope().timeout(_wait);
    final provider = calendar();
    await provider.prepareOAuthScope().timeout(_wait);
    await provider.loadFromStorage().timeout(_wait);
    expect(provider.isOAuthReady, isTrue);
    expect(provider.oauthAccounts.single.id, _id);
    expect(provider.oauthAccounts.single.expiresAt,
        expired ? DateTime.utc(2000) : DateTime.utc(2099));
    expect(requests, isEmpty);
    store.attempts.clear();
    return provider;
  }

  Future<void> writeOwnedExpiry({required bool expired}) async {
    final account = OAuthCalendarAccount(
      id: _id,
      provider: OAuthCalendarProvider.google,
      displayName: 'Lifetime calendar',
      clientId: 'synthetic-client',
      redirectUri: 'duoyi://oauth/calendar',
      accessToken: 'synthetic-expired-access',
      refreshToken: 'synthetic-expired-refresh',
      expiresAt: expired ? DateTime.utc(2000) : DateTime.utc(2099),
    );
    final previousSource = installedSource;
    final source = previousSource == null
        ? OAuthOwnedSourceRecord.create(scope: scope!, account: account.toJson())
        : previousSource.withAccount(account.toJson());
    if (previousSource != null) {
      expect(source.sourceIncarnation, previousSource.sourceIncarnation);
      expect(source.metadataRevision, previousSource.metadataRevision);
      expect(source.credentialRevision, previousSource.credentialRevision + 1);
    }
    final lease = issuer!.captureOAuthScopeLease();
    await AccountPreferenceWrites.runResult<void>((token) {
      bool current() => token.isCurrent && issuer!.isOAuthScopeLeaseCurrent(lease);
      return OAuthCalendarStorage.run<void>(() async {
        await prefs.reload();
        token.ensureCurrent();
        OAuthCalendarStorage.ensureScopedWorkspaceCurrentLocked(
          lease.workspace, prefs,
        );
        await OAuthCalendarStorage.commitLocked(
          prefs,
          <String, Object?>{
            _accounts: jsonEncode([source.toJson()]),
            '${OAuthCalendarStorage.eventsKeyPrefix}$_id':
                OAuthOwnedEventsRecord.create(
                  source: source, events: <Map<String, Object?>>[],
                ).encode(),
            'todos': '[]',
          },
          current,
          scopedWorkspace: lease.workspace,
          validateReadback: () => OAuthCalendarInventory.validate(prefs, scope!),
        );
      }, epoch: OAuthCalendarStorage.epoch, isCurrent: current);
    }, canceledResult: () => throw const AccountPreferenceWriteCanceled())
        .timeout(_wait);
    installedSource = source;
    expect(requests, isEmpty);
    store.attempts.clear();
  }

  Future<void> expectOwnedRefreshCommitted() async {
    final backing = await primary.disk();
    final rows = OAuthOwnedSourceRecord.parseList(
      backing[_accounts] as String, scope: scope!,
    );
    expect(rows, hasLength(1));
    final source = rows!.single;
    expect(source.sourceIncarnation, installedSource!.sourceIncarnation);
    expect(source.credentialRevision, installedSource!.credentialRevision + 1);
    expect(source.account['accessToken'], 'synthetic-renewed-access');
    expect(source.account['refreshToken'], 'synthetic-renewed-refresh');
    expect(source.account['lastSyncedAt'], isNotNull);
    final events = OAuthOwnedEventsRecord.parse(
      backing['${OAuthCalendarStorage.eventsKeyPrefix}$_id'] as String,
      source: source,
    );
    expect(events, isNotNull);
    expect(events!.events, isEmpty);
    expect(backing.containsKey(OAuthCalendarStorage.refreshJournalKey), isFalse);
    await prefs.reload();
    OAuthCalendarInventory.validate(prefs, scope!);
  }

  CalendarSyncProvider calendar() {
    final provider = CalendarSyncProvider(
      oauthHttpClient: client,
      authProvider: issuer,
    );
    providers.add(provider);
    return provider;
  }

  Future<OAuthCalendarAccount> connect(CalendarSyncProvider provider) =>
      provider.addOAuthAccountFromCode(
        provider: OAuthCalendarProvider.google,
        displayName: 'Rejected during cleanup',
        clientId: 'synthetic-client',
        redirectUri: 'duoyi://oauth/calendar',
        authorizationCode: 'synthetic-lifetime-code',
        codeVerifier:
            'synthetic-lifetime-verifier-0123456789-ABCDEFGHIJKLMNOPQRSTUVWXYZ',
      );
  _Hold hold() {
    final gate = _Hold();
    holds.add(gate);
    return gate;
  }

  Future<_Result<T>> observe<T>(Future<T> task) {
    final result = task.then<_Result<T>>(
      (value) => _Result<T>.value(value),
      onError: (Object error, StackTrace _) => _Result<T>.error(error),
    );
    pending.add(result.then<void>((_) {}));
    return result;
  }

  Future<void> close() async {
    for (final slot in <_Slot>{primary, probe, ...coreSlots}) {
      slot.store.releaseAll();
    }
    for (final hold in holds) {
      if (!hold.release.isCompleted) hold.release.complete();
    }
    try {
      await Future.wait(pending).timeout(_wait);
      await AccountPreferenceWrites.drain().timeout(_wait);
      for (final ticket in tickets) {
        OAuthCalendarStorage.failAccountRetirementAnnouncement(ticket);
      }
      // Core-only cases seed unowned device data. Settle any failed identity
      // through the actual checked fence API before resetting the singleton.
      for (final slot in coreSlots) {
        SharedPreferencesStorePlatform.instance = slot.store;
        final session = await bind(
          slot,
          OAuthCalendarStorage.announceAccountRetirement(store: slot.prefs),
        );
        await finish(slot, session).timeout(_wait);
      }
      SharedPreferencesStorePlatform.instance = primary.store;
      if (coreSlots.isNotEmpty) {
        SharedPreferences.resetStatic();
        primary.prefs = await SharedPreferences.getInstance();
      }
      await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    } finally {
      for (final provider in providers) {
        provider.dispose();
      }
      for (final auth in authProviders) {
        auth.dispose();
      }
      client.close();
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = previous;
    }
  }
}

http.Response _json(Map<String, Object> body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);
