// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/ics_subscription_storage.dart';
import 'package:duoyi/core/oauth_calendar_storage.dart';
import 'package:duoyi/core/oauth_calendar_inventory.dart';
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
const _accounts = 'duoyi_oauth_calendar_accounts_v1';
const _pending = 'duoyi_oauth_calendar_pending_authorization_v1';
const _sidecar = 'duoyi_oauth_calendar_fingerprint_retirement_fixture';
const _cache = 'duoyi_oauth_calendar_events_retirement_existing';
const _device = 'retirement_fixture_device_setting';
const _fence = OAuthCalendarStorage.retirementFenceKey;
const _owner = AccountLocalDataCleaner.accountDataOwnerKey;
const _code = 'synthetic-retirement-code';
const _verifier =
    'synthetic-retirement-verifier-0123456789-ABCDEFGHIJKLMNOPQRSTUVWXYZ';

// Dedicated behavioral cases. Platform fault injection changes real backing
// bytes independently of ACKs; no provider/storage/cleanup method is replaced.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() async => f = await _Fixture.create());
  tearDown(() async => f.close());

  test('OR77-01 Auth nested two-pass callback retains one outer fence', () async {
    await f.seed();
    const account = AuthState(
      userId: 'retiring-user',
      username: 'retiring-user',
      token: 'synthetic-auth-token',
    );
    final auth = f.issuer!;
    expect(auth.state.toJson(), account.toJson());
    final transition = auth.successfulAccountTransitionRevision;
    expect(transition, greaterThan(0));
    final gate = f.hold();
    String? firstFence;
    final epoch = OAuthCalendarStorage.epoch;
    auth.onAccountLoggedOut = () =>
        AccountLocalDataCleaner.runAccountRetirement(() async {
          firstFence = (await f.disk())[_fence] as String;
          _expectFenceRecord(firstFence!);
          await AccountLocalDataCleaner.clearSharedPreferences();
          expect(await f.owned(), isEmpty);
          expect((await f.disk())[_fence], firstFence);
          gate.started.complete();
          await gate.release.future;
          // Model callback/platform settlement between the real cleanup passes.
          await f.prefs.setString(_pending, 'synthetic-late-owned-state');
          await AccountLocalDataCleaner.clearSharedPreferences();
          expect((await f.disk())[_fence], firstFence);
          expect(await f.owned(), isEmpty);
          expect(OAuthCalendarStorage.epoch, epoch);
        });
    f.store.attempts.clear();
    final retiring = f.observe(auth.logout());
    await gate.started.future.timeout(_wait);
    expect((await f.disk())[_fence], firstFence);
    expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isTrue);
    expect(f.store.count('set', _fence), 1);
    expect(f.store.count('remove', _fence), 0);
    expect(auth.successfulAccountTransitionRevision, transition);
    expect(auth.isAccountTransitionInProgress, isTrue);
    final mutations = f.store.attempts.toList();
    expect(
      () => OAuthCalendarStorage.ensureAccountAdmissionLocked(f.prefs),
      throwsA(isA<OAuthAccountRetirementPending>()),
    );
    expect(
      (await f.observe(f.connect(f.calendar())).timeout(_wait)).error,
      isA<OAuthScopedWorkspaceUnavailable>(),
    );
    expect(f.requests, isEmpty);
    expect(f.store.attempts, mutations);
    gate.release.complete();
    expect((await retiring.timeout(_wait)).error, isNull);
    expect(f.store.count('set', _fence), 1);
    expect(f.store.count('remove', _fence), 1);
    expect((await f.disk()).containsKey(_fence), isFalse);
    expect((await f.disk()).containsKey('auth_state'), isFalse);
    expect(await f.owned(), isEmpty);
    expect(OAuthCalendarStorage.epoch, epoch + 1);
    expect(auth.successfulAccountTransitionRevision, transition + 1);
    expect(auth.state.isLoggedIn, isFalse);
    expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isFalse);
    expect(f.requests.single, 'auth:/api/auth/logout');
  });

  test(
    'OR77-02 interrupted outer callback keeps the first-pass fence',
    () async {
      await f.seed();
      final epoch = OAuthCalendarStorage.epoch;
      final result = await f
          .observe(
            AccountLocalDataCleaner.runAccountRetirement<void>(() async {
              await AccountLocalDataCleaner.clearSharedPreferences();
              expect(await f.owned(), isEmpty);
              expect((await f.disk()).containsKey(_fence), isTrue);
              throw StateError('synthetic callback interruption');
            }),
          )
          .timeout(_wait);
      expect(result.error, isA<StateError>());
      expect(OAuthCalendarStorage.epoch, epoch);
      expect(f.store.count('remove', _fence), 0);
      await f.restartPreferences();
      await f.expectBlocked(f.calendar());
      await f.retryClear(epoch);
    },
  );

  const armCases = <(String, _Effect)>[
    (
      'OR77-03 arm false before persistence issues no owned removal',
      _Effect.reject,
    ),
    (
      'OR77-04 arm persisted false issues no owned removal',
      _Effect.persistReject,
    ),
    (
      'OR77-05 arm true without persistence issues no owned removal',
      _Effect.ghost,
    ),
    (
      'OR77-06 arm throw before persistence issues no owned removal',
      _Effect.throwBefore,
    ),
    (
      'OR77-07 arm persisted throw issues no owned removal',
      _Effect.persistThrow,
    ),
  ];
  for (final scenario in armCases) {
    test(scenario.$1, () async {
      await f.seed();
      final before = await f.owned();
      final epoch = OAuthCalendarStorage.epoch;
      var callbacks = 0;
      f.store.plan('set', _fence, scenario.$2);
      final result = await f
          .observe(
            AccountLocalDataCleaner.runAccountRetirement<void>(() async {
              callbacks++;
            }),
          )
          .timeout(_wait);
      expect(
        result.error,
        scenario.$2.throwsError
            ? isA<StateError>()
            : isA<OAuthAccountRetirementPending>(),
      );
      expect(callbacks, 0);
      expect(f.store.ownedRemovals, isEmpty);
      expect(f.store.count('set', _owner), 0);
      expect(await f.owned(), before);
      expect(OAuthCalendarStorage.epoch, epoch);
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isTrue);
      final disk = await f.disk();
      expect(disk.containsKey(_fence), scenario.$2.persists);
      await f.expectBlocked(f.calendar());
      if (scenario.$2.persists) {
        await f.restartPreferences();
        await f.expectBlocked(f.calendar());
      }
      await f.retryClear(epoch);
    });
  }

  test(
    'OR77-08 persisted held arm ACK precedes callback and all owned removals',
    () async {
      await f.seed();
      final before = await f.owned();
      final step = f.store.plan(
        'set',
        _fence,
        _Effect.accept,
        hold: true,
        persistBeforeAck: true,
      );
      var callbacks = 0;
      final result = f.observe(
        AccountLocalDataCleaner.runAccountRetirement<void>(() async {
          callbacks++;
        }),
      );
      await step.started.future.timeout(_wait);
      _expectFenceRecord((await f.disk())[_fence] as String);
      expect(callbacks, 0);
      expect(f.store.ownedRemovals, isEmpty);
      expect(f.store.count('set', _owner), 0);
      expect(await f.owned(), before);
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isTrue);
      final peer = f.calendar();
      final mutations = f.store.attempts.toList();
      expect(
        () => OAuthCalendarStorage.ensureAccountAdmissionLocked(f.prefs),
        throwsA(isA<OAuthAccountRetirementPending>()),
      );
      expect(
        (await f.observe(f.connect(peer)).timeout(_wait)).error,
        isA<OAuthScopedWorkspaceUnavailable>(),
      );
      expect(f.requests, isEmpty);
      expect(f.store.attempts, mutations);
      step.release.complete();
      expect((await result.timeout(_wait)).error, isNull);
      expect(callbacks, 1);
      expect(await f.owned(), isEmpty);
      expect(f.store.attempts.last, 'remove:$_fence');
    },
  );

  test(
    'OR77-09 arm ACK followed by reload failure issues no owned removal',
    () async {
      await f.seed();
      final before = await f.owned();
      final epoch = OAuthCalendarStorage.epoch;
      final step = f.store.plan(
        'set',
        _fence,
        _Effect.accept,
        hold: true,
        persistBeforeAck: true,
      );
      final result = f.observe(
        AccountLocalDataCleaner.clearSharedPreferences(),
      );
      await step.started.future.timeout(_wait);
      f.store.failNextRead();
      step.release.complete();
      expect((await result.timeout(_wait)).error, isA<StateError>());
      expect(f.store.ownedRemovals, isEmpty);
      expect(f.store.count('set', _owner), 0);
      expect(await f.owned(), before);
      await f.restartPreferences();
      await f.expectBlocked(f.calendar());
      await f.retryClear(epoch);
    },
  );

  const partialCases = <(String, String, _Effect, bool)>[
    (
      'OR77-10 owner remove failure keeps persistent retirement admission closed',
      _owner,
      _Effect.reject,
      false,
    ),
    (
      'OR77-11 held accounts remove failure cannot expose missing-owner residuals',
      _accounts,
      _Effect.reject,
      true,
    ),
    (
      'OR77-12 accounts true without removal cannot finish retirement',
      _accounts,
      _Effect.ghost,
      false,
    ),
    (
      'OR77-13 persisted accounts false remains a failed retirement',
      _accounts,
      _Effect.persistReject,
      false,
    ),
    (
      'OR77-14 accounts removal throw retains fence across fresh hydration',
      _accounts,
      _Effect.throwBefore,
      false,
    ),
  ];
  for (final scenario in partialCases) {
    test(scenario.$1, () async {
      await f.seed();
      final epoch = OAuthCalendarStorage.epoch;
      final icsEpoch = IcsSubscriptionStorage.epoch;
      final step = f.store.plan(
        'remove',
        scenario.$2,
        scenario.$3,
        hold: scenario.$4,
      );
      final clearing = f.observe(
        AccountLocalDataCleaner.clearSharedPreferences(),
      );
      if (scenario.$4) {
        await step.started.future.timeout(_wait);
        final held = await f.disk();
        expect(held.containsKey(_owner), isFalse);
        expect(held.containsKey(_accounts), isTrue);
        _expectFenceRecord(held[_fence] as String);
        expect(f.store.count('remove', _fence), 0);
        step.release.complete();
      }
      expect((await clearing.timeout(_wait)).error, isA<StateError>());
      final disk = await f.disk();
      expect(disk.containsKey(_fence), isTrue);
      expect(disk.containsKey(scenario.$2), !scenario.$3.persists);
      if (scenario.$2 == _accounts) expect(disk.containsKey(_owner), isFalse);
      expect(disk.containsKey(_sidecar), isFalse);
      expect(f.store.count('remove', _fence), 0);
      expect(OAuthCalendarStorage.epoch, epoch);
      expect(IcsSubscriptionStorage.epoch, icsEpoch);
      expect(OAuthCalendarStorage.failure, isNull);
      await f.restartPreferences();
      // A new preferences identity has no old session-map entry. Its actual
      // persistent fence, not the retired provider, must close admission.
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isTrue);
      await f.expectBlocked(f.calendar());
      await f.retryClear(epoch);
    });
  }

  const finishCases = <(String, _Effect)>[
    (
      'OR77-15 final fence false remains sticky until checked retry',
      _Effect.reject,
    ),
    (
      'OR77-16 final fence persisted false cannot advance success',
      _Effect.persistReject,
    ),
    ('OR77-17 final fence true without removal remains sticky', _Effect.ghost),
    (
      'OR77-18 final fence throw before removal remains sticky',
      _Effect.throwBefore,
    ),
    (
      'OR77-19 final fence persisted throw remains sticky in this runtime',
      _Effect.persistThrow,
    ),
  ];
  for (final scenario in finishCases) {
    test(scenario.$1, () async {
      await f.seed();
      final epoch = OAuthCalendarStorage.epoch;
      final icsEpoch = IcsSubscriptionStorage.epoch;
      final step = f.store.plan('remove', _fence, scenario.$2, hold: true);
      final clearing = f.observe(
        AccountLocalDataCleaner.clearSharedPreferences(),
      );
      await step.started.future.timeout(_wait);
      expect(await f.owned(), isEmpty);
      expect((await f.disk()).containsKey(_fence), isTrue);
      expect(OAuthCalendarStorage.epoch, epoch);
      expect(IcsSubscriptionStorage.epoch, icsEpoch);
      step.release.complete();
      expect(
        (await clearing.timeout(_wait)).error,
        scenario.$2.throwsError
            ? isA<StateError>()
            : isA<OAuthAccountRetirementPending>(),
      );
      expect((await f.disk()).containsKey(_fence), !scenario.$2.persists);
      expect(await f.owned(), isEmpty);
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isTrue);
      expect(OAuthCalendarStorage.epoch, epoch);
      expect(IcsSubscriptionStorage.epoch, icsEpoch);
      await f.expectBlocked(f.calendar());
      await f.retryClear(epoch);
    });
  }

  test(
    'OR77-20 final fence removal reload failure cannot confirm clear',
    () async {
      await f.seed();
      final epoch = OAuthCalendarStorage.epoch;
      final step = f.store.plan(
        'remove',
        _fence,
        _Effect.accept,
        hold: true,
        persistBeforeAck: true,
      );
      final clearing = f.observe(
        AccountLocalDataCleaner.clearSharedPreferences(),
      );
      await step.started.future.timeout(_wait);
      expect(await f.owned(), isEmpty);
      expect((await f.disk()).containsKey(_fence), isFalse);
      f.store.failNextRead();
      step.release.complete();
      expect((await clearing.timeout(_wait)).error, isA<StateError>());
      expect(OAuthCalendarStorage.epoch, epoch);
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isTrue);
      await f.expectBlocked(f.calendar());
      await f.retryClear(epoch);
    },
  );

  const markerCases = <(String, Object)>[
    ('OR77-21 boolean false fence still blocks ordinary OAuth', false),
    ('OR77-22 empty string fence still blocks ordinary OAuth', ''),
    ('OR77-23 malformed JSON fence still blocks ordinary OAuth', '{broken'),
    ('OR77-24 string false fence still blocks ordinary OAuth', 'false'),
  ];
  for (final scenario in markerCases) {
    test(scenario.$1, () async {
      await f.seed();
      if (scenario.$2 is bool) {
        await f.prefs.setBool(_fence, scenario.$2 as bool);
      } else {
        await f.prefs.setString(_fence, scenario.$2 as String);
      }
      f.store.attempts.clear();
      final before = await f.owned();
      await f.restartPreferences();
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isTrue);
      await f.expectBlocked(f.calendar());
      expect(await f.owned(), before);
      expect(f.store.ownedRemovals, isEmpty);
      await f.retryClear(OAuthCalendarStorage.epoch);
    });
  }

  for (final signedIn in [false, true]) {
    test(
      signedIn
          ? 'OR77-26 signed-in missing owner cannot adopt fenced OAuth residuals'
          : 'OR77-25 signed-out missing owner cannot adopt fenced guest residuals',
      () async {
        await f.seed(owner: false);
        await f.prefs.setString(_fence, 'synthetic-existing-retirement');
        if (signedIn) {
          const next = AuthState(
            userId: 'next-user',
            username: 'next-user',
            token: 'synthetic-next-token',
          );
          await f.prefs.setString('auth_state', jsonEncode(next.toJson()));
        }
        await f.restartPreferences();
        final beforeAccounts = (await f.disk())[_accounts];
        final epoch = OAuthCalendarStorage.epoch;
        f.store.rejectAlways('remove', _accounts);
        final auth = f.auth();
        f.store.attempts.clear();
        final loaded = await f
            .observe(auth.loadFromStorage(refreshServerConfig: false))
            .timeout(_wait);
        expect(loaded.error, isA<StateError>());
        expect(auth.isLocalAccountDataBlocked, isTrue);
        expect(auth.successfulAccountTransitionRevision, 0);
        expect(auth.isAccountTransitionInProgress, isFalse);
        expect(auth.state.isLoggedIn, isFalse);
        expect((await f.disk()).containsKey(_owner), isFalse);
        expect((await f.disk())[_accounts], beforeAccounts);
        expect((await f.disk()).containsKey(_fence), isTrue);
        expect(f.store.count('set', _owner), 0);
        expect(f.requests, isEmpty);
        await f.expectBlocked(f.calendar());
        f.store.clearPlans();
        await f.retryClear(epoch);
      },
    );
  }

  test(
    'OR77-27 non-destructive reset differs from confirmed account retirement',
    () async {
      await f.seed(includeSidecar: false);
      final provider = f.calendar();
      expect(provider.isOAuthReady, isTrue);
      await provider.loadFromStorage().timeout(_wait);
      expect(provider.oauthAccounts, hasLength(1));
      // The draft was saved publicly before the controlled accounts fault.
      final originalAccounts = (await f.disk())[_accounts];
      f.store.plan('set', _accounts, _Effect.reject);
      final failed = await f.observe(f.connect(provider)).timeout(_wait);
      expect(failed.error, isA<OAuthLocalCommitRequired>());
      final receipt = (failed.error! as OAuthLocalCommitRequired).receipt;
      final received = OAuthOwnedPendingAuthorization.parse(
        (await f.disk())[_pending] as String, scope: f.scope!,
      );
      expect(received, isNotNull);
      expect(received!.phase, OAuthPendingPhase.received);
      expect(received.receiptHandle, receipt.handle);
      expect((await f.disk())[_accounts], originalAccounts);
      final beforeReset = await f.owned();
      final epoch = OAuthCalendarStorage.epoch;
      final writes = f.store.attempts.toList();
      final transport = f.requests.toList();
      provider.resetLocalState();
      expect(await f.owned(), beforeReset);
      expect(OAuthCalendarStorage.epoch, epoch);
      expect(
        (await f.observe(f.connect(provider)).timeout(_wait)).error,
        isA<OAuthScopedWorkspaceUnavailable>(),
      );
      expect(f.tokenRequests, 1);
      expect(f.requests, transport);
      expect(f.store.attempts, writes);
      expect(provider.oauthLocalCommitReceipts, isEmpty);

      // Explicit restoration can see the durable received claim. Reset alone
      // cannot replay it, and restoration does not turn it into a new draft.
      await f.issuer!.restoreOAuthScope().timeout(_wait);
      final restored = f.calendar();
      await restored.loadFromStorage().timeout(_wait);
      expect(restored.isOAuthReady, isTrue);
      expect(restored.oauthLocalCommitReceipts, hasLength(1));
      expect(restored.oauthLocalCommitReceipts.single.handle, receipt.handle);
      expect(
        (await f.observe(f.connect(restored)).timeout(_wait)).error,
        isA<AccountPreferenceWriteCanceled>(),
      );
      expect(f.tokenRequests, 1);
      expect(f.store.attempts, writes);
      expect(await f.owned(), beforeReset);

      await f.retryClear(epoch);
      expect(await f.owned(), isEmpty);
      await f.hydrateEmptyScope();
      final peer = f.calendar();
      await peer.loadFromStorage().timeout(_wait);
      final freshBacking = await f.owned();
      expect(
        (await f.observe(peer.retryOAuthLocalCommit(receipt)).timeout(_wait))
            .error,
        isA<AccountPreferenceWriteCanceled>(),
      );
      expect(f.tokenRequests, 1);
      expect(f.requests, transport);
      expect(await f.owned(), freshBacking);
      // Confirmed clear retires the client-side history. The fake SERVER keeps
      // its consumed-code set; the same code under a new public draft reaches
      // HTTP and is denied by that server.
      await f.prepareAttempt(peer);
      final beforeOldDispatch = await f.owned();
      final oldCode = await f.observe(f.connect(peer)).timeout(_wait);
      expect(
        oldCode.error,
        isA<StateError>().having(
          (error) => error.message,
          'fixed safe message',
          'OAuth calendar request failed',
        ),
      );
      expect(oldCode.error.toString(), 'Bad state: OAuth calendar request failed');
      expect(f.tokenRequests, 2);
      expect(f.rejectedCodes, [_code]);
      expect(f.rejectedResponses, [
        {'code': _code, 'status': 400, 'error': 'invalid_grant'},
      ]);
      final dispatched = OAuthOwnedPendingAuthorization.parse(
        (await f.disk())[_pending] as String, scope: f.scope!,
      );
      expect(dispatched, isNotNull);
      expect(dispatched!.phase, OAuthPendingPhase.dispatched);
      for (final entry in beforeOldDispatch.entries) {
        if (entry.key != _pending) expect((await f.owned())[entry.key], entry.value);
      }
      final deniedBacking = await f.owned();
      final deniedWrites = f.store.attempts.toList();
      expect(
        (await f.observe(f.connect(peer)).timeout(_wait)).error,
        isA<AccountPreferenceWriteCanceled>(),
      );
      expect(f.tokenRequests, 2);
      expect(f.store.attempts, deniedWrites);
      expect(await f.owned(), deniedBacking);

      // A denied remote outcome remains durably dispatched. Only another
      // confirmed retirement may remove it before a fresh positive attempt.
      await f.retryClear(OAuthCalendarStorage.epoch);
      expect(await f.owned(), isEmpty);
      await f.hydrateEmptyScope();
      final fresh = f.calendar();
      await fresh.loadFromStorage().timeout(_wait);
      await f.prepareAttempt(fresh);
      final connected = await f
          .observe(f.connect(fresh, code: 'synthetic-fresh-retirement-code'))
          .timeout(_wait);
      expect(connected.error, isNull);
      expect(connected.value, isA<OAuthCalendarAccount>());
      expect(f.tokenRequests, 3);
      expect(fresh.oauthAccounts, hasLength(1));
      expect((await f.disk()).containsKey(_pending), isFalse);
    },
  );
}

bool _ownedKey(String key) =>
    key != _fence &&
    (AccountLocalDataCleaner.accountScopedKeys.contains(key) ||
        AccountLocalDataCleaner.accountScopedPrefixes.any(key.startsWith));

void _expectFenceRecord(String raw) {
  final record = jsonDecode(raw) as Map<String, dynamic>;
  expect(record.keys.toSet(), {'schema', 'retirementId', 'state'});
  expect(record['schema'], 1);
  expect(record['state'], 'retiring');
  expect(
    record['retirementId'],
    isA<String>().having((value) => value.isNotEmpty, 'opaque id', isTrue),
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

enum _Effect {
  accept,
  reject,
  ghost,
  persistReject,
  throwBefore,
  persistThrow;

  bool get persists =>
      this == accept || this == persistReject || this == persistThrow;
  bool get throwsError => this == throwBefore || this == persistThrow;
}

class _Step extends _Hold {
  _Step(this.effect, this.isHeld, this.persistBeforeAck);
  final _Effect effect;
  final bool isHeld;
  final bool persistBeforeAck;
}

class _BackingStore extends InMemorySharedPreferencesStore {
  _BackingStore() : super.withData(<String, Object>{});
  final attempts = <String>[];
  final _plans = <String, List<_Step>>{};
  final _alwaysRejected = <String>{};
  final _steps = <_Step>[];
  int _readFailures = 0;

  _Step plan(
    String operation,
    String key,
    _Effect effect, {
    bool hold = false,
    bool persistBeforeAck = false,
  }) {
    final step = _Step(effect, hold, persistBeforeAck);
    _plans.putIfAbsent('$operation:$key', () => []).add(step);
    _steps.add(step);
    return step;
  }

  void rejectAlways(String operation, String key) =>
      _alwaysRejected.add('$operation:$key');
  void failNextRead() => _readFailures++;
  int count(String operation, String key) =>
      attempts.where((value) => value == '$operation:$key').length;
  List<String> get ownedRemovals => attempts
      .where(
        (value) => value.startsWith('remove:') && _ownedKey(value.substring(7)),
      )
      .toList();

  // Read real platform backing bytes without consuming a planned reload fault.
  Future<Map<String, Object>> backing() => super.getAll();

  @override
  Future<Map<String, Object>> getAll() async {
    if (_readFailures > 0) {
      _readFailures--;
      throw StateError('synthetic backing reload failure');
    }
    return super.getAll();
  }

  Future<bool> _perform(
    String operation,
    String platformKey,
    Future<bool> Function() persist,
  ) async {
    final key = platformKey.substring('flutter.'.length);
    final id = '$operation:$key';
    attempts.add(id);
    final queue = _plans[id];
    final step = queue == null || queue.isEmpty ? null : queue.removeAt(0);
    if (step == null) {
      if (_alwaysRejected.contains(id)) return false;
      return await persist();
    }
    var persisted = false;
    if (step.persistBeforeAck) {
      expect(await persist(), isTrue);
      persisted = true;
    }
    step.started.complete();
    if (step.isHeld) await step.release.future;
    if (step.effect.persists && !persisted) expect(await persist(), isTrue);
    if (step.effect.throwsError) {
      throw StateError('synthetic platform mutation failure');
    }
    return step.effect == _Effect.accept || step.effect == _Effect.ghost;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) =>
      _perform('set', key, () => super.setValue(type, key, value));

  @override
  Future<bool> remove(String key) =>
      _perform('remove', key, () => super.remove(key));

  void clearPlans() {
    for (final step in _steps) {
      if (!step.release.isCompleted) step.release.complete();
    }
    _plans.clear();
    _alwaysRejected.clear();
    _readFailures = 0;
  }
}

class _Fixture {
  _Fixture(this.previousStore, this.store, this.prefs) {
    client = MockClient(_respond);
  }
  final SharedPreferencesStorePlatform previousStore;
  final _BackingStore store;
  SharedPreferences prefs;
  late final MockClient client;
  final providers = <CalendarSyncProvider>[];
  final authProviders = <AuthProvider>[];
  AuthProvider? issuer;
  OAuthScopedOwnerRecord? scope;
  final holds = <_Hold>[];
  final pending = <Future<void>>[];
  final requests = <String>[];
  final consumedCodes = <String>{};
  final rejectedCodes = <String>[];
  final rejectedResponses = <Map<String, Object>>[];
  int get tokenRequests => requests
      .where((value) => value == 'exchange' || value == 'refresh')
      .length;

  static Future<_Fixture> create() async {
    await AccountPreferenceWrites.drain().timeout(_wait);
    final previous = SharedPreferencesStorePlatform.instance;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = _BackingStore();
    SharedPreferencesStorePlatform.instance = store;
    final prefs = await SharedPreferences.getInstance();
    await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    store.attempts.clear();
    return _Fixture(previous, store, prefs);
  }

  Future<void> hydrateEmptyScope({AuthState? initial}) async {
    if (initial != null) {
      expect(await prefs.setString('auth_state', jsonEncode(initial.toJson())), isTrue);
    }
    final next = auth(initial: initial);
    expect(
      next.captureOAuthScopeLease,
      throwsA(initial?.isLoggedIn == true
          ? isA<OAuthScopedWorkspaceUnavailable>()
          : isA<ApiException>()),
      reason: 'Constructor initialState is not verified storage authority',
    );
    await http.runWithClient(
      () => next.loadFromStorage(refreshServerConfig: false),
      () => client,
    ).timeout(_wait);
    expect(next.isLocalAccountDataBlocked, isFalse);
    expect(next.isAccountTransitionInProgress, isFalse);
    expect(
      next.captureOAuthScopeLease,
      throwsA(isA<OAuthScopedWorkspaceUnavailable>()),
    );
    await next.initializeOAuthScope().timeout(_wait);
    final lease = next.captureOAuthScopeLease();
    expect(next.isOAuthScopeLeaseCurrent(lease), isTrue);
    scope = OAuthScopedOwnerRecord.parse(lease.workspace.rawRecord)!;
    issuer = next;
  }

  Future<void> prepareAttempt(CalendarSyncProvider provider) async {
    final draft = await provider.savePendingOAuthAuthorization(
      provider: OAuthCalendarProvider.google,
      displayName: 'Fresh calendar',
      clientId: 'synthetic-client',
      clientSecret: '',
      redirectUri: 'duoyi://oauth/calendar',
      calendarId: 'primary',
      codeVerifier: _verifier,
      state: 'synthetic-retirement-state',
    ).timeout(_wait);
    final pending = OAuthOwnedPendingAuthorization.parse(
      (await disk())[_pending] as String, scope: scope!,
    );
    expect(pending, isNotNull);
    expect(pending!.attemptId, draft['attemptId']);
    expect(pending.phase, OAuthPendingPhase.prepared);
    expect(pending.canDispatchAt(DateTime.now()), isTrue);
  }

  Future<void> seed({bool owner = true, bool includeSidecar = true}) async {
    final account = OAuthCalendarAccount(
      id: 'retirement_existing',
      provider: OAuthCalendarProvider.google,
      displayName: 'Retiring calendar',
      clientId: 'synthetic-client',
      redirectUri: 'duoyi://oauth/calendar',
      accessToken: 'synthetic-existing-access',
      refreshToken: 'synthetic-existing-refresh',
      expiresAt: DateTime.utc(2099),
    );
    if (!owner) {
      // OR77-25/26 deliberately retain the original ownerless, legacy bytes.
      // Hydrating these into an issuer would destroy the negative preimage.
      final values = <String, String>{
        _accounts: jsonEncode([account.toJson()]),
        _pending: 'synthetic-pending-owned-by-retiring-user',
        _sidecar: 'synthetic-owned-fingerprint',
        _cache: '[]',
        'todos': '[]',
        _device: 'synthetic-device-setting',
      };
      for (final entry in values.entries) {
        expect(await prefs.setString(entry.key, entry.value), isTrue);
      }
      issuer = null;
      scope = null;
      store.attempts.clear();
      return;
    }
    await hydrateEmptyScope(initial: const AuthState(
      userId: 'retiring-user',
      username: 'retiring-user',
      token: 'synthetic-auth-token',
    ));
    final lease = issuer!.captureOAuthScopeLease();
    final source = OAuthOwnedSourceRecord.create(
      scope: scope!, account: account.toJson(),
    );
    final cache = OAuthOwnedEventsRecord.create(
      source: source, events: <Map<String, Object?>>[],
    );
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
            _cache: cache.encode(),
            'todos': '[]',
            _device: 'synthetic-device-setting',
          },
          current,
          scopedWorkspace: lease.workspace,
          validateReadback: () => OAuthCalendarInventory.validate(prefs, scope!),
        );
      }, epoch: OAuthCalendarStorage.epoch, isCurrent: current);
    }, canceledResult: () => throw const AccountPreferenceWriteCanceled())
        .timeout(_wait);
    await issuer!.restoreOAuthScope().timeout(_wait);
    final ready = calendar();
    await ready.prepareOAuthScope().timeout(_wait);
    await ready.loadFromStorage().timeout(_wait);
    expect(ready.isOAuthReady, isTrue);
    expect(ready.oauthAccounts.single.toJson(), account.toJson());
    await prepareAttempt(ready);
    expect(requests, isEmpty);
    if (includeSidecar) {
      // Deliberate unknown residual is added only after proven valid readiness.
      // Cleanup cases must remove its exact bytes; no codec adopts it.
      expect(await prefs.setString(_sidecar, 'synthetic-owned-fingerprint'), isTrue);
    }
    store.attempts.clear();
  }

  Future<Map<String, Object>> disk() async => {
    for (final entry in (await store.backing()).entries)
      entry.key.substring('flutter.'.length): entry.value,
  };
  Future<Map<String, Object>> owned() async => {
    for (final entry in (await disk()).entries)
      if (_ownedKey(entry.key)) entry.key: entry.value,
  };

  Future<void> restartPreferences() async {
    final before = prefs;
    final bytes = await disk();
    for (final provider in providers) {
      provider.dispose();
    }
    providers.clear();
    SharedPreferences.setMockInitialValues(bytes);
    SharedPreferencesStorePlatform.instance = store;
    prefs = await SharedPreferences.getInstance();
    expect(identical(before, prefs), isFalse);
    expect(await disk(), bytes);
    await prefs.reload();
  }

  CalendarSyncProvider calendar() {
    final provider = CalendarSyncProvider(
      oauthHttpClient: client,
      authProvider: issuer,
    );
    providers.add(provider);
    return provider;
  }

  // Same minimal real AuthProvider + ApiClient/MockClient construction used by
  // auth_transition_completion_test; its private helpers cannot be imported.
  AuthProvider auth({AuthState? initial}) {
    final provider = AuthProvider(
      initialState: initial ?? const AuthState(),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: initial?.token,
        httpClient: client,
      ),
    );
    authProviders.add(provider);
    return provider;
  }

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

  Future<OAuthCalendarAccount> connect(
    CalendarSyncProvider provider, {
    String code = _code,
  }) => provider.addOAuthAccountFromCode(
    provider: OAuthCalendarProvider.google,
    displayName: 'Fresh calendar',
    clientId: 'synthetic-client',
    redirectUri: 'duoyi://oauth/calendar',
    authorizationCode: code,
    codeVerifier: _verifier,
  );

  Future<void> expectBlocked(CalendarSyncProvider provider) async {
    final before = await disk();
    final mutations = store.attempts.toList();
    final transport = requests.toList();
    await prefs.reload();
    expect(OAuthCalendarStorage.isAccountRetiring(prefs), isTrue);
    expect(
      () => OAuthCalendarStorage.ensureAccountAdmissionLocked(prefs),
      throwsA(isA<OAuthAccountRetirementPending>()),
      reason: 'Core admission remains closed even without an issuer',
    );
    expect(provider.isOAuthReady, isFalse);
    expect(
      (await observe(provider.loadFromStorage()).timeout(_wait)).error,
      isNull,
      reason: 'Absent/revoked issuer loads the ICS projection only',
    );
    expect(provider.oauthAccounts, isEmpty);
    expect(provider.oauthLocalCommitReceipts, isEmpty);
    expect(provider.isOAuthReady, isFalse);
    expect(
      (await observe(
        provider.loadPendingOAuthAuthorization(),
      ).timeout(_wait)).error,
      isA<OAuthScopedWorkspaceUnavailable>(),
    );
    expect(
      (await observe(connect(provider)).timeout(_wait)).error,
      isA<OAuthScopedWorkspaceUnavailable>(),
    );
    expect(
      (await observe(provider.reconcileOAuthStorage()).timeout(_wait)).error,
      isA<OAuthScopedWorkspaceUnavailable>(),
    );
    expect(provider.oauthAccounts, isEmpty);
    expect(requests, transport);
    expect(store.attempts, mutations);
    expect(await disk(), before);
  }

  Future<void> retryClear(int epoch) async {
    expect(
      (await observe(
        AccountLocalDataCleaner.clearSharedPreferences(),
      ).timeout(_wait)).error,
      isNull,
    );
    expect(await owned(), isEmpty);
    expect((await disk()).containsKey(_fence), isFalse);
    expect((await disk())[_device], 'synthetic-device-setting');
    await prefs.reload();
    expect(OAuthCalendarStorage.isAccountRetiring(prefs), isFalse);
    expect(OAuthCalendarStorage.epoch, epoch + 1);
    final admitted = calendar();
    expect(
      (await observe(admitted.loadFromStorage()).timeout(_wait)).error,
      isNull,
    );
    expect(admitted.oauthAccounts, isEmpty);
  }

  Future<http.Response> _respond(http.Request request) async {
    if (request.url.path.startsWith('/api/')) {
      requests.add('auth:${request.url.path}');
      return _json(<String, Object>{});
    }
    if (request.method == 'POST' && request.url.path.endsWith('/token')) {
      expect(request.url.host, 'oauth2.googleapis.com');
      final isExchange =
          request.bodyFields['grant_type'] == 'authorization_code';
      requests.add(isExchange ? 'exchange' : 'refresh');
      if (isExchange) {
        final code = request.bodyFields['code']!;
        if (!consumedCodes.add(code)) {
          rejectedCodes.add(code);
          final response = _json({'error': 'invalid_grant'}, status: 400);
          rejectedResponses.add({
            'code': code,
            'status': response.statusCode,
            'error': (jsonDecode(response.body) as Map)['error'] as String,
          });
          return response;
        }
      }
      return _json({
        'access_token': 'synthetic-new-access',
        'refresh_token': 'synthetic-new-refresh',
        'expires_in': 3600,
        'token_type': 'Bearer',
      });
    }
    requests.add('events');
    expect(request.method, 'GET');
    expect(request.url.host, 'www.googleapis.com');
    return _json({'items': <Object>[]});
  }

  Future<void> close() async {
    store.clearPlans();
    for (final gate in holds) {
      if (!gate.release.isCompleted) gate.release.complete();
    }
    try {
      await Future.wait(pending).timeout(_wait);
      await AccountPreferenceWrites.drain().timeout(_wait);
    } finally {
      for (final provider in providers) {
        provider.dispose();
      }
      for (final auth in authProviders) {
        auth.dispose();
      }
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

http.Response _json(Map<String, Object> body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json'},
    );
