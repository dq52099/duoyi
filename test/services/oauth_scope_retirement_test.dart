// ignore_for_file: depend_on_referenced_packages
// Preparation only: this fixture has not been executed or formatted.
import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/ics_subscription_storage.dart';
import 'package:duoyi/core/location_reminder_storage.dart';
import 'package:duoyi/core/oauth_calendar_storage.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _wait = Duration(seconds: 5);
const _scope = OAuthCalendarStorage.scopeRetirementFenceKey;
const _full = OAuthCalendarStorage.retirementFenceKey;
const _scopeOwner = OAuthCalendarStorage.scopeOwnerKey;
const _accounts = 'duoyi_oauth_calendar_accounts_v1';
const _accountOwner = AccountLocalDataCleaner.accountDataOwnerKey;
const _scopeBinding = 'synthetic-guest-scope110';
const _guest = <String, Object>{
  'todos': '[ { "title" : "guest110" } ]',
  'duoyi_notes': '[{"body":"keep guest note110"}]',
  'duoyi_ics_subscriptions_v1':
      '[{"id":"guest110","url":"https://example.invalid/guest.ics"}]',
  'duoyi_ics_events_guest110': '[{"summary":"keep110"}]',
  'duoyi_location_reminders_v1': '[]',
  'sync_deleted_items': '{"todos":["old110"]}',
  'sync_pending_local_changes': true,
  'pomodoro_config': '{ "minutes" : 25 }',
  'theme_unlocked_brands': <String>['guest-brand110'],
  'auth_state': '{ "token" : null }',
  'scope110_device_setting': 7,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() async {
    f = await _Fixture.create();
    await f.seed();
  });
  tearDown(() async => f.close());

  test(
    'OSR110-01 scoped retirement removes every OAuth key and preserves guest backing',
    () async {
      final result = await f
          .observe(f.retire<int>(() async => 110))
          .timeout(_wait);
      expect(result.error, isNull);
      expect(result.value, 110);
      await f.expectScopedSuccess();
      expect(f.store.count('set', _scope), 1);
      expect(f.store.count('remove', _scope), 1);
      expect(f.store.attempts.last, 'remove:$_scope');
    },
  );

  const faults = <(String, String, String, bool)>[
    (
      'OSR110-02 arm false before persistence cannot invoke cleanup',
      'set',
      _scope,
      false,
    ),
    (
      'OSR110-03 arm false after persistence cannot invoke cleanup',
      'set',
      _scope,
      true,
    ),
    (
      'OSR110-04 owned remove false before persistence keeps retirement blocked',
      'remove',
      _accounts,
      false,
    ),
    (
      'OSR110-05 owned remove false after persistence cannot finish an empty scope',
      'remove',
      _accounts,
      true,
    ),
    (
      'OSR110-06 final remove false before persistence cannot confirm scope clear',
      'remove',
      _scope,
      false,
    ),
    (
      'OSR110-07 final remove false after persistence stays blocked in this runtime',
      'remove',
      _scope,
      true,
    ),
  ];
  for (final (name, operation, key, persists) in faults) {
    test(name, () async {
      final step = f.store.plan(
        operation,
        key,
        accepted: false,
        persists: persists,
      );
      var callbacks = 0;
      var settled = false;
      final result = f.observe(
        f
            .retire<void>(() async {
              callbacks++;
            })
            .whenComplete(() => settled = true),
      );
      await step.started.future.timeout(_wait);
      expect(settled, isFalse);
      expect(AccountPreferenceWrites.isBoundaryActive, isTrue);
      expect(OAuthCalendarStorage.resetRevision, f.resetBefore);
      final held = await f.disk();
      await f.expectOrdinary();
      if (operation == 'set') {
        expect(callbacks, 0);
        expect(f.store.oauthRemovals, isEmpty);
        expect(held.containsKey(_scope), persists);
        expect(f.oauthData(held), f.oauthBefore);
      } else if (key == _accounts) {
        expect(callbacks, 1);
        expect(held.containsKey(_accounts), !persists);
        f.expectMarker(held[_scope]);
        expect(f.store.count('remove', _scope), 0);
      } else {
        expect(callbacks, 1);
        expect(f.oauthData(held), isEmpty);
        expect(held.containsKey(_scope), !persists);
      }
      step.release.complete();
      expect(
        (await result.timeout(_wait)).error,
        isA<OAuthAccountRetirementPending>(),
      );
      expect(OAuthCalendarStorage.resetRevision, f.resetBefore);
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isTrue);
      await f.expectOrdinary();
      final failed = await f.disk();
      if (operation == 'set') {
        expect(f.oauthData(failed), f.oauthBefore);
        expect(f.store.oauthRemovals, isEmpty);
      } else if (key == _accounts) {
        expect(failed.containsKey(_accounts), !persists);
        expect(f.store.count('remove', _scope), 0);
        if (persists) expect(f.oauthData(failed), isEmpty);
      } else {
        expect(f.oauthData(failed), isEmpty);
      }
      expect(
        failed.containsKey(_scope),
        operation == 'set' ? persists : key == _accounts || !persists,
      );
      await f.expectBlocked();
      expect(
        (await f.observe(f.retire<void>(() async {})).timeout(_wait)).error,
        isNull,
      );
      await f.expectScopedSuccess();
    });
  }

  test(
    'OSR110-08 already revoked request issues no mutation or boundary',
    () async {
      f.current = false;
      final generation = AccountPreferenceWrites.generation;
      final before = await f.disk();
      var called = false;
      expect(
        (await f
                .observe(
                  f.retire<void>(() async {
                    called = true;
                  }),
                )
                .timeout(_wait))
            .error,
        isA<OAuthAccountRetirementPending>(),
      );
      expect(called, isFalse);
      expect(f.store.attempts, isEmpty);
      expect(await f.disk(), before);
      expect(AccountPreferenceWrites.generation, generation);
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isFalse);
    },
  );

  test(
    'OSR110-09 request revoked during held arm issues no owned removal',
    () async {
      final step = f.store.plan('set', _scope, accepted: true, persists: true);
      var called = false;
      final result = f.observe(
        f.retire<void>(() async {
          called = true;
        }),
      );
      await step.started.future.timeout(_wait);
      f.current = false;
      step.release.complete();
      expect(
        (await result.timeout(_wait)).error,
        isA<OAuthAccountRetirementPending>(),
      );
      expect(called, isFalse);
      expect(f.store.oauthRemovals, isEmpty);
      expect(f.oauthData(await f.disk()), f.oauthBefore);
      expect(OAuthCalendarStorage.resetRevision, f.resetBefore);
      await f.expectOrdinary();
      f.current = true;
      expect(
        (await f.observe(f.retire<void>(() async {})).timeout(_wait)).error,
        isNull,
      );
      await f.expectScopedSuccess();
    },
  );

  test(
    'OSR110-10 returned root waits for live child and late enrolled grandchild',
    () async {
      final request = f.request();
      final childGate = f.gate();
      final grandchildGate = f.gate();
      final rootReturned = Completer<void>();
      var rootSettled = false;
      var childSettled = false;
      final root = f.observe(
        AccountLocalDataCleaner.runOAuthScopeRetirement<int>(request, () async {
          unawaited(
            f.observe(
              AccountLocalDataCleaner.runOAuthScopeRetirement<void>(
                request,
                () async {
                  childGate.started.complete();
                  await childGate.release.future;
                  await AccountLocalDataCleaner.runOAuthScopeRetirement<void>(
                    request,
                    () async {
                      grandchildGate.started.complete();
                      await grandchildGate.release.future;
                    },
                  );
                },
              ).whenComplete(() => childSettled = true),
            ),
          );
          rootReturned.complete();
          return 7;
        }).whenComplete(() => rootSettled = true),
      );
      await rootReturned.future.timeout(_wait);
      await childGate.started.future.timeout(_wait);
      await Future<void>.delayed(Duration.zero);
      expect(rootSettled, isFalse);
      expect(childSettled, isFalse);
      childGate.release.complete();
      await grandchildGate.started.future.timeout(_wait);
      expect(rootSettled, isFalse);
      expect(childSettled, isFalse);
      expect(f.store.count('set', _scope), 1);
      expect(f.store.count('remove', _scope), 0);
      expect(AccountPreferenceWrites.isBoundaryActive, isTrue);
      await f.expectOrdinary();
      grandchildGate.release.complete();
      final result = await root.timeout(_wait);
      expect(result.error, isNull);
      expect(result.value, 7);
      expect(childSettled, isTrue);
      expect(f.store.count('remove', _scope), 1);
      await f.expectScopedSuccess();
    },
  );

  test(
    'OSR110-11 caught child failure poisons root and further enrollment',
    () async {
      final request = f.request();
      final first = StateError('synthetic member failure110');
      final result = await f
          .observe(
            AccountLocalDataCleaner.runOAuthScopeRetirement<void>(
              request,
              () async {
                final child = await f.observe(
                  AccountLocalDataCleaner.runOAuthScopeRetirement<void>(
                    request,
                    () async {
                      throw first;
                    },
                  ),
                );
                expect(child.error, same(first));
                final attempts = f.store.attempts.toList();
                var called = false;
                final later = await f.observe(
                  AccountLocalDataCleaner.runOAuthScopeRetirement<void>(
                    request,
                    () async {
                      called = true;
                    },
                  ),
                );
                expect(later.error, same(first));
                expect(called, isFalse);
                expect(f.store.attempts, attempts);
              },
            ),
          )
          .timeout(_wait);
      expect(result.error, same(first));
      expect(f.store.oauthRemovals, isEmpty);
      expect(f.store.count('remove', _scope), 0);
      expect(f.oauthData(await f.disk()), f.oauthBefore);
      await f.expectOrdinary();
    },
  );

  test('OSR110-12 scoped root rejects nested full cleanup upgrade', () async {
    var fullCalled = false;
    final result = await f
        .observe(
          f.retire<void>(() async {
            await AccountLocalDataCleaner.runAccountRetirement<void>(() async {
              fullCalled = true;
            });
          }),
        )
        .timeout(_wait);
    expect(result.error, isA<OAuthAccountRetirementPending>());
    expect(fullCalled, isFalse);
    expect(f.store.count('set', _full), 0);
    expect(f.store.oauthRemovals, isEmpty);
    expect(f.store.count('remove', _scope), 0);
    await f.expectOrdinary();
  });

  test(
    'OSR110-13 failed full arm without a disk fence still blocks scoped retirement',
    () async {
      final step = f.store.plan('set', _full, accepted: false, persists: false);
      var fullCalled = false;
      final full = f.observe(
        AccountLocalDataCleaner.runAccountRetirement<void>(() async {
          fullCalled = true;
        }),
      );
      await step.started.future.timeout(_wait);
      step.release.complete();
      expect(
        (await full.timeout(_wait)).error,
        isA<OAuthAccountRetirementPending>(),
      );
      expect(fullCalled, isFalse);
      expect((await f.disk()).containsKey(_full), isFalse);
      expect(f.store.count('set', _full), 1);
      f.store.attempts.clear();
      final before = await f.disk();
      var scopedCalled = false;
      expect(
        (await f
                .observe(
                  f.retire<void>(() async {
                    scopedCalled = true;
                  }),
                )
                .timeout(_wait))
            .error,
        isA<OAuthAccountRetirementPending>(),
      );
      expect(scopedCalled, isFalse);
      expect(f.store.attempts, isEmpty);
      expect(await f.disk(), before);
      expect(f.store.count('set', _scope), 0);
      expect(f.store.count('remove', _scope), 0);
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isTrue);
      await f.expectOrdinary();
    },
  );

  test(
    'OSR110-14 full takeover retains scoped blocker until full arm ACK',
    () async {
      final interrupted = StateError('synthetic interrupted scope110');
      expect(
        (await f
                .observe(
                  f.retire<void>(() async {
                    throw interrupted;
                  }),
                )
                .timeout(_wait))
            .error,
        same(interrupted),
      );
      final oldScope = (await f.disk())[_scope];
      f.store.attempts.clear();
      final step = f.store.plan('set', _full, accepted: true, persists: true);
      var called = false;
      final result = f.observe(
        AccountLocalDataCleaner.runAccountRetirement<void>(() async {
          called = true;
          expect((await f.disk())[_scope], oldScope);
        }),
      );
      await step.started.future.timeout(_wait);
      expect(called, isFalse);
      expect((await f.disk())[_scope], oldScope);
      expect((await f.disk())[_full], isA<String>());
      expect(f.store.attempts, ['set:$_full']);
      await f.expectOrdinary();
      step.release.complete();
      expect((await result.timeout(_wait)).error, isNull);
      final mutations = f.store.attempts;
      expect(
        mutations.indexOf('remove:$_scope'),
        greaterThan(mutations.indexOf('set:$_full')),
      );
      expect(
        mutations.indexOf('remove:$_full'),
        greaterThan(mutations.indexOf('remove:$_scope')),
      );
      expect((await f.disk()).containsKey(_scope), isFalse);
      expect((await f.disk()).containsKey(_full), isFalse);
      expect((await f.disk()).containsKey('todos'), isFalse);
    },
  );

  test(
    'OSR110-15 malformed scoped fences reject without deleting guest or OAuth',
    () async {
      for (final marker in <Object>[false, '', '{broken', 'false']) {
        await AccountPreferenceTransaction.writeValue(f.prefs, _scope, marker);
        f.store.attempts.clear();
        final before = await f.disk();
        await f.prefs.reload();
        final inspection = OAuthCalendarStorage.inspectRetirementLocked(
          f.prefs,
        );
        expect(inspection.scopedPending, isTrue);
        expect(inspection.scopedRecoverable, isFalse);
        expect(inspection.fullPending, isFalse);
        var called = false;
        expect(
          (await f
                  .observe(
                    f.retire<void>(() async {
                      called = true;
                    }),
                  )
                  .timeout(_wait))
              .error,
          isA<OAuthAccountRetirementPending>(),
        );
        expect(called, isFalse);
        expect(f.store.attempts, isEmpty);
        expect(await f.disk(), before);
        await f.expectOrdinary();
        await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
        await f.seed();
      }
    },
  );

  test('OSR110-16 scoped request cannot take over a full fence', () async {
    await f.prefs.setString(_full, 'synthetic-existing-full-intent110');
    f.store.attempts.clear();
    final before = await f.disk();
    var called = false;
    expect(
      (await f
              .observe(
                f.retire<void>(() async {
                  called = true;
                }),
              )
              .timeout(_wait))
          .error,
      isA<OAuthAccountRetirementPending>(),
    );
    expect(called, isFalse);
    expect(f.store.attempts, isEmpty);
    expect(await f.disk(), before);
    final inspection = OAuthCalendarStorage.inspectRetirementLocked(f.prefs);
    expect(inspection.fullPending, isTrue);
    expect(inspection.scopedRecoverable, isFalse);
    await f.expectOrdinary();
  });

  test(
    'OSR110-17 queued request cannot substitute a changed scoped fence',
    () async {
      // Keep both owner bindings absent so only the captured fence changes.
      for (final key in (await f.disk()).keys.where(
        OAuthCalendarStorage.isOAuthScopeKey,
      )) {
        expect(await f.prefs.remove(key), isTrue);
      }
      await f.prefs.reload();
      f.store.attempts.clear();
      final gate = f.gate();
      final first = f.observe(
        f.retire<void>(() async {
          gate.started.complete();
          await gate.release.future;
        }),
      );
      await gate.started.future.timeout(_wait);
      final captured = (await f.disk())[_scope];
      expect(captured, isA<String>());
      final request = f.request();
      expect(request.expectedAccountOwner, isNull);
      expect(request.expectedScopedOwner, isNull);
      var secondCalled = false;
      final second = f.observe(
        AccountLocalDataCleaner.runOAuthScopeRetirement<void>(
          request,
          () async {
            secondCalled = true;
          },
        ),
      );
      expect(secondCalled, isFalse);
      gate.release.complete();
      expect((await first.timeout(_wait)).error, isNull);
      expect(
        (await second.timeout(_wait)).error,
        isA<OAuthAccountRetirementPending>(),
      );
      expect(secondCalled, isFalse);
      expect((await f.disk()).containsKey(_scope), isFalse);
      expect((await f.disk()).containsKey(_scopeOwner), isFalse);
      expect((await f.disk()).containsKey(_accountOwner), isFalse);
      expect(f.store.count('set', _scope), 1);
      expect(f.store.count('remove', _scope), 1);
      expect(OAuthCalendarStorage.resetRevision, f.resetBefore + 1);
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isTrue);
      await f.expectOrdinary();
    },
  );

  test(
    'OSR110-18 full final readback rejects a reappearing scoped marker',
    () async {
      final step = f.store.plan(
        'remove',
        _full,
        accepted: true,
        persists: true,
      );
      final result = f.observe(
        AccountLocalDataCleaner.runAccountRetirement<void>(() async {}),
      );
      await step.started.future.timeout(_wait);
      expect(f.oauthData(await f.disk()), isEmpty);
      expect((await f.disk()).containsKey(_full), isFalse);
      expect(OAuthCalendarStorage.resetRevision, f.resetBefore);
      const replacement = 'synthetic-reappeared-scoped-marker110';
      expect(await f.prefs.setString(_scope, replacement), isTrue);
      step.release.complete();
      expect(
        (await result.timeout(_wait)).error,
        isA<OAuthAccountRetirementPending>(),
      );
      expect((await f.disk())[_scope], replacement);
      expect(f.store.count('remove', _scope), 0);
      expect(OAuthCalendarStorage.resetRevision, f.resetBefore);
      expect(IcsSubscriptionStorage.epoch, f.icsBefore);
      expect(LocationReminderStorage.storageEpoch, f.locationBefore);
      expect(OAuthCalendarStorage.isAccountRetiring(f.prefs), isTrue);
      await f.expectBlocked();
    },
  );
}

class _Result<T> {
  _Result.value(this.value) : error = null;
  _Result.error(this.error) : value = null;
  final T? value;
  final Object? error;
}

class _Gate {
  final started = Completer<void>();
  final release = Completer<void>();
}

class _Step extends _Gate {
  _Step({required this.accepted, required this.persists});
  final bool accepted;
  final bool persists;
}

class _BackingStore extends InMemorySharedPreferencesStore {
  _BackingStore() : super.withData(<String, Object>{});
  final attempts = <String>[];
  final steps = <_Step>[];
  final _plans = <String, List<_Step>>{};

  _Step plan(
    String operation,
    String key, {
    required bool accepted,
    required bool persists,
  }) {
    final step = _Step(accepted: accepted, persists: persists);
    _plans.putIfAbsent('$operation:$key', () => []).add(step);
    steps.add(step);
    return step;
  }

  int count(String operation, String key) =>
      attempts.where((entry) => entry == '$operation:$key').length;
  List<String> get oauthRemovals => attempts
      .where(
        (entry) =>
            entry.startsWith('remove:') &&
            OAuthCalendarStorage.isOAuthScopeKey(entry.substring(7)),
      )
      .toList();
  Future<Map<String, Object>> backing() => super.getAll();

  Future<bool> _perform(
    String operation,
    String platformKey,
    Future<bool> Function() persist,
  ) async {
    final key = platformKey.substring('flutter.'.length);
    final id = '$operation:$key';
    attempts.add(id);
    final plans = _plans[id];
    final step = plans == null || plans.isEmpty ? null : plans.removeAt(0);
    if (step == null) return persist();
    if (step.persists) expect(await persist(), isTrue);
    step.started.complete();
    await step.release.future;
    return step.accepted;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) =>
      _perform('set', key, () => super.setValue(type, key, value));
  @override
  Future<bool> remove(String key) =>
      _perform('remove', key, () => super.remove(key));

  void releaseAll() {
    for (final step in steps) {
      if (!step.release.isCompleted) step.release.complete();
    }
    _plans.clear();
  }
}

class _Fixture {
  _Fixture(this.previous, this.store, this.prefs);
  final SharedPreferencesStorePlatform previous;
  final _BackingStore store;
  final SharedPreferences prefs;
  final pending = <Future<void>>[];
  final gates = <_Gate>[];
  bool current = true;
  late Map<String, Object> ordinaryBefore;
  late Map<String, Object> oauthBefore;
  late int resetBefore;
  late int icsBefore;
  late int locationBefore;

  static Future<_Fixture> create() async {
    await AccountPreferenceWrites.drain().timeout(_wait);
    final previous = SharedPreferencesStorePlatform.instance;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = _BackingStore();
    SharedPreferencesStorePlatform.instance = store;
    final prefs = await SharedPreferences.getInstance();
    return _Fixture(previous, store, prefs);
  }

  Future<void> seed() async {
    final values = <String, Object>{
      ..._guest,
      _scopeOwner: _scopeBinding,
      _accounts: 'synthetic-credential-bearing-accounts110',
      'duoyi_oauth_calendar_pending_authorization_v1': 'synthetic-pending110',
      'duoyi_oauth_calendar_events_guest110': '[]',
      'duoyi_oauth_calendar_commit_state_v1': 'synthetic-claim110',
      'duoyi_oauth_calendar_future_private110': <String>[
        'synthetic-fingerprint110',
      ],
      'duoyi_oauth_calendar_future_bool110': true,
    };
    for (final entry in values.entries) {
      expect(
        await AccountPreferenceTransaction.writeValue(
          prefs,
          entry.key,
          entry.value,
        ),
        isTrue,
      );
    }
    await prefs.reload();
    final raw = await disk();
    ordinaryBefore = ordinaryData(raw);
    oauthBefore = oauthData(raw);
    resetBefore = OAuthCalendarStorage.resetRevision;
    icsBefore = IcsSubscriptionStorage.epoch;
    locationBefore = LocationReminderStorage.storageEpoch;
    store.attempts.clear();
  }

  Future<Map<String, Object>> disk() async => {
    for (final entry in (await store.backing()).entries)
      entry.key.substring('flutter.'.length): entry.value is List
          ? List<String>.unmodifiable((entry.value as List).cast<String>())
          : entry.value,
  };
  Map<String, Object> oauthData(Map<String, Object> raw) => {
    for (final entry in raw.entries)
      if (OAuthCalendarStorage.isOAuthScopeKey(entry.key))
        entry.key: entry.value,
  };
  Map<String, Object> ordinaryData(Map<String, Object> raw) => {
    for (final entry in raw.entries)
      if (!entry.key.startsWith('duoyi_oauth_calendar_'))
        entry.key: entry.value,
  };

  OAuthScopeRetirementRequest request() => OAuthScopeRetirementRequest(
    preferences: prefs,
    expectedAccountOwner: prefs.getString(_accountOwner),
    expectedScopedOwner: prefs.getString(_scopeOwner),
    purpose: OAuthScopeRetirementPurpose.explicitReconnect,
    isCurrent: () => current,
  );
  Future<T> retire<T>(Future<T> Function() operation) =>
      AccountLocalDataCleaner.runOAuthScopeRetirement<T>(request(), operation);
  _Gate gate() {
    final result = _Gate();
    gates.add(result);
    return result;
  }

  Future<_Result<T>> observe<T>(Future<T> task) {
    final result = task.then<_Result<T>>(
      (value) => _Result<T>.value(value),
      onError: (Object error, StackTrace _) => _Result<T>.error(error),
    );
    pending.add(result.then<void>((_) {}));
    return result;
  }

  void expectMarker(Object? raw) {
    expect(raw, isA<String>());
    final marker = jsonDecode(raw! as String) as Map<String, dynamic>;
    expect(marker.keys.toSet(), {
      'schema',
      'retirementId',
      'state',
      'scope',
      'purpose',
      'globalOwner',
      'scopeOwner',
    });
    expect(marker['schema'], 1);
    expect(marker['state'], 'retiring');
    expect(marker['scope'], 'oauthOnly');
    expect(marker['purpose'], 'explicitReconnect');
    expect(marker['globalOwner'], isNull);
    expect(marker['retirementId'], matches(r'^[A-Za-z0-9_-]{32}$'));
    expect(marker['scopeOwner'], matches(r'^[0-9a-f]{64}$'));
    expect(raw, isNot(contains(_scopeBinding)));
  }

  Future<void> expectOrdinary() async {
    expect(ordinaryData(await disk()), ordinaryBefore);
    expect(store.count('set', _accountOwner), 0);
    expect(store.count('remove', _accountOwner), 0);
    expect(store.count('set', 'auth_state'), 0);
    expect(store.count('remove', 'auth_state'), 0);
    expect(IcsSubscriptionStorage.epoch, icsBefore);
    expect(LocationReminderStorage.storageEpoch, locationBefore);
  }

  Future<void> expectScopedSuccess() async {
    await expectOrdinary();
    final raw = await disk();
    expect(oauthData(raw), isEmpty);
    expect(raw.containsKey(_scope), isFalse);
    expect(raw.containsKey(_full), isFalse);
    expect(store.count('set', _full), 0);
    expect(store.count('remove', _full), 0);
    expect(OAuthCalendarStorage.resetRevision, resetBefore + 1);
    expect(OAuthCalendarStorage.isAccountRetiring(prefs), isFalse);
    expect(AccountPreferenceWrites.isBoundaryActive, isFalse);
  }

  Future<void> expectBlocked() async {
    final before = await disk();
    final attempts = store.attempts.toList();
    final result = await observe(
      OAuthCalendarStorage.run<void>(
        () => OAuthCalendarStorage.commitLocked(prefs, {
          'duoyi_oauth_calendar_forbidden110': 'must-not-write110',
        }, () => true),
        epoch: OAuthCalendarStorage.epoch,
        recovering: true,
      ),
    ).timeout(_wait);
    expect(result.error, isA<OAuthAccountRetirementPending>());
    expect(store.attempts, attempts);
    expect(await disk(), before);
  }

  Future<void> close() async {
    store.releaseAll();
    for (final gate in gates) {
      if (!gate.release.isCompleted) gate.release.complete();
    }
    try {
      await Future.wait(pending).timeout(_wait);
      await AccountPreferenceWrites.drain().timeout(_wait);
      current = true;
      // Explicit fixture teardown uses real full retirement only after assertions.
      await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    } finally {
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = previous;
    }
  }
}
