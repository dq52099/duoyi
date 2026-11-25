// ignore_for_file: depend_on_referenced_packages
// Preparation only: OSI113 has not been executed or formatted.
import 'dart:async';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/oauth_calendar_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _wait113 = Duration(seconds: 5);
const _key113 = 'duoyi_oauth_calendar_store_identity113';
const _preimage113 = '{"synthetic":"preimage113"}';
const _issued113 = '{"synthetic":"issued113"}';
const _ordinary113 = <String, Object>{
  'todos': '[{"title":"ordinary113"}]',
  'osi113_device_setting': 7,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture113 f;
  setUp(() async => f = await _Fixture113.create());
  tearDown(() async => f.close());

  test(
    'OSI113-01 wrong-store reconcile rejects matching issued and preimage without writes',
    () async {
      final diagB = await f.makeDiagnosticB();
      expect(f.a.prefs, isNot(same(f.b.prefs)));
      final bBefore = await f.b.store.backing();
      final bAttempts = List<String>.of(f.b.store.attempts);
      for (final value in [_issued113, _preimage113]) {
        f.activate(f.a);
        if (f.a.prefs.getString(_key113) != value) {
          expect(await f.a.prefs.setString(_key113, value), isTrue);
          await f.a.prefs.reload();
        }
        expect(f.a.prefs.getString(_key113), value);
        final aBefore = await f.a.store.backing();
        final aAttempts = List<String>.of(f.a.store.attempts);
        final aReads = f.a.store.reads;
        final bReads = f.b.store.reads;
        final entries = f.laneEntries;
        final error = await f
            .observe(
              f.invoke(
                f.a,
                () =>
                    OAuthCalendarStorage.reconcileLocked(f.a.prefs, () => true),
              ),
            )
            .timeout(_wait113);
        expect(f.laneEntries, entries + 1);
        expect(error, same(diagB));
        expect(OAuthCalendarStorage.failure, same(diagB));
        expect(f.a.store.attempts, aAttempts);
        expect(f.b.store.attempts, bAttempts);
        expect(f.a.store.reads, aReads);
        expect(f.b.store.reads, bReads);
        expect(await f.a.store.backing(), aBefore);
        expect(await f.b.store.backing(), bBefore);
      }

      // Positive control: the same diagnostic is recoverable through its actual
      // B preferences while its captured epoch/generation are still current.
      final aAttempts = List<String>.of(f.a.store.attempts);
      expect(
        await f
            .observe(
              f.invoke(
                f.b,
                () =>
                    OAuthCalendarStorage.reconcileLocked(f.b.prefs, () => true),
              ),
            )
            .timeout(_wait113),
        isNull,
      );
      expect(OAuthCalendarStorage.failure, isNull);
      expect(f.b.prefs.getString(_key113), _preimage113);
      expect((await f.b.store.backing())['flutter.$_key113'], _preimage113);
      expect(f.a.store.attempts, aAttempts);
      expect(f.b.store.attempts, [...bAttempts, 'set:$_key113']);
    },
  );

  test(
    'OSI113-02 scoped and full confirmation of cleared A preserve diagnostic owned by B',
    () async {
      final diagB = await f.makeDiagnosticB();
      final bBefore = await f.b.store.backing();
      final bAttempts = List<String>.of(f.b.store.attempts);
      // Establish the public confirmation hooks' clear-store precondition on A.
      // This is synthetic A cleanup, never a substitute cleanup of failing B.
      f.activate(f.a);
      expect(await f.a.prefs.clear(), isTrue);
      await f.a.prefs.reload();
      expect(f.a.prefs.getKeys(), isEmpty);
      expect(await f.a.store.backing(), isEmpty);
      final aAttempts = List<String>.of(f.a.store.attempts);
      final epoch = OAuthCalendarStorage.epoch;
      final reset = OAuthCalendarStorage.resetRevision;
      expect(
        await f
            .observe(
              f.invoke(f.a, () async {
                OAuthCalendarStorage.confirmOAuthScopeClearLocked(f.a.prefs);
              }),
            )
            .timeout(_wait113),
        isNull,
      );
      expect(OAuthCalendarStorage.failure, same(diagB));
      expect(OAuthCalendarStorage.epoch, epoch);
      expect(OAuthCalendarStorage.resetRevision, reset + 1);
      expect(f.a.store.attempts, aAttempts);
      expect(f.b.store.attempts, bAttempts);
      expect(await f.b.store.backing(), bBefore);
      expect(
        await f
            .observe(
              f.invoke(f.a, () async {
                OAuthCalendarStorage.confirmAccountClearLocked(f.a.prefs);
              }),
            )
            .timeout(_wait113),
        isNull,
      );
      expect(OAuthCalendarStorage.failure, same(diagB));
      expect(OAuthCalendarStorage.epoch, epoch + 1);
      expect(OAuthCalendarStorage.resetRevision, reset + 2);
      expect(f.a.store.attempts, aAttempts);
      expect(f.b.store.attempts, bAttempts);
      expect(await f.a.store.backing(), isEmpty);
      expect(await f.b.store.backing(), bBefore);
      // Preserving B's diagnostic does not refresh its old global epoch lease.
      final bReads = f.b.store.reads;
      expect(
        await f
            .observe(
              f.invoke(
                f.b,
                () =>
                    OAuthCalendarStorage.reconcileLocked(f.b.prefs, () => true),
              ),
            )
            .timeout(_wait113),
        isA<AccountPreferenceWriteCanceled>(),
      );
      expect(OAuthCalendarStorage.failure, same(diagB));
      expect(f.b.store.reads, bReads);
      expect(f.b.store.attempts, bAttempts);
      expect(await f.b.store.backing(), bBefore);
    },
  );

  test(
    'OSI113-03 repeated commits on A and B reject without replacing B diagnostic',
    () async {
      final diagB = await f.makeDiagnosticB();
      final aBefore = await f.a.store.backing();
      final bBefore = await f.b.store.backing();
      final aAttempts = List<String>.of(f.a.store.attempts);
      final bAttempts = List<String>.of(f.b.store.attempts);
      final aReads = f.a.store.reads;
      final bReads = f.b.store.reads;
      final unusedFaults = <_Step113>[];
      for (final slot in [f.a, f.b]) {
        // If admission regresses, these would create another real failed commit
        // and failed rollback. Correct admission must never consume either step.
        unusedFaults.add(
          slot.store.plan('set', _key113, accepted: false, persists: true),
        );
        unusedFaults.add(
          slot.store.plan('set', _key113, accepted: false, persists: false),
        );
        for (var attempt = 0; attempt < 2; attempt++) {
          final entries = f.laneEntries;
          expect(
            await f
                .observe(
                  f.invoke(
                    slot,
                    () => OAuthCalendarStorage.commitLocked(slot.prefs, {
                      _key113: 'synthetic-new-commit113-$attempt',
                    }, () => true),
                  ),
                )
                .timeout(_wait113),
            same(diagB),
          );
          // recovering:true enters commitLocked itself rather than having run()
          // short-circuit this check at its ordinary global failure gate.
          expect(f.laneEntries, entries + 1);
          expect(OAuthCalendarStorage.failure, same(diagB));
          expect(f.a.store.attempts, aAttempts);
          expect(f.b.store.attempts, bAttempts);
          expect(f.a.store.reads, aReads);
          expect(f.b.store.reads, bReads);
          expect(await f.a.store.backing(), aBefore);
          expect(await f.b.store.backing(), bBefore);
        }
      }
      expect(unusedFaults.every((step) => !step.started.isCompleted), isTrue);
    },
  );
}

// The scope110 platform fault stub's persist-before-ACK mechanism is retained.
// Neither core operation nor transaction/diagnostic construction is stubbed.
class _Step113 {
  _Step113({required this.accepted, required this.persists});
  final bool accepted;
  final bool persists;
  final started = Completer<void>();
  final release = Completer<void>();
}

class _Backing113 extends InMemorySharedPreferencesStore {
  _Backing113(Map<String, Object> values)
    : super.withData({
        for (final entry in values.entries) 'flutter.${entry.key}': entry.value,
      });
  final attempts = <String>[];
  final steps = <_Step113>[];
  final _plans = <String, List<_Step113>>{};
  int reads = 0;

  _Step113 plan(
    String operation,
    String key, {
    required bool accepted,
    required bool persists,
  }) {
    final step = _Step113(accepted: accepted, persists: persists);
    _plans.putIfAbsent('$operation:$key', () => []).add(step);
    steps.add(step);
    return step;
  }

  Future<Map<String, Object>> backing() => super.getAll();

  @override
  Future<Map<String, Object>> getAll() {
    reads++;
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
  @override
  Future<bool> clear() {
    attempts.add('clear');
    return super.clear();
  }

  void releaseAll() {
    for (final step in steps) {
      if (!step.release.isCompleted) step.release.complete();
    }
    _plans.clear();
  }
}

class _Slot113 {
  _Slot113(this.store, this.prefs);
  final _Backing113 store;
  final SharedPreferences prefs;
}

class _Fixture113 {
  _Fixture113(this.previous, this.a, this.b);
  final SharedPreferencesStorePlatform previous;
  final _Slot113 a;
  final _Slot113 b;
  final pending = <Future<void>>[];
  int laneEntries = 0;

  static Future<_Slot113> _slot(String value) async {
    SharedPreferences.resetStatic();
    final store = _Backing113({..._ordinary113, _key113: value});
    SharedPreferencesStorePlatform.instance = store;
    return _Slot113(store, await SharedPreferences.getInstance());
  }

  static Future<_Fixture113> create() async {
    await AccountPreferenceWrites.drain().timeout(_wait113);
    expect(OAuthCalendarStorage.failure, isNull);
    final previous = SharedPreferencesStorePlatform.instance;
    final a = await _slot(_issued113);
    final b = await _slot(_preimage113);
    expect(a.prefs, isNot(same(b.prefs)));
    expect(await SharedPreferences.getInstance(), same(b.prefs));
    return _Fixture113(previous, a, b);
  }

  void activate(_Slot113 slot) =>
      SharedPreferencesStorePlatform.instance = slot.store;

  Future<void> invoke(_Slot113 slot, Future<void> Function() operation) {
    activate(slot);
    return OAuthCalendarStorage.run<void>(
      () {
        laneEntries++;
        return operation();
      },
      epoch: OAuthCalendarStorage.epoch,
      recovering: true,
    );
  }

  Future<Object?> observe(Future<void> work) {
    final result = work.then<Object?>(
      (_) => null,
      onError: (Object error, StackTrace _) => error,
    );
    pending.add(result.then<void>((_) {}));
    return result;
  }

  Future<OAuthStorageIndeterminate> makeDiagnosticB() async {
    final before = await b.store.backing();
    final forward = b.store.plan(
      'set',
      _key113,
      accepted: false,
      persists: true,
    );
    final rollback = b.store.plan(
      'set',
      _key113,
      accepted: false,
      persists: false,
    );
    final result = observe(
      invoke(
        b,
        () => OAuthCalendarStorage.commitLocked(b.prefs, {
          _key113: _issued113,
        }, () => true),
      ),
    );
    await forward.started.future.timeout(_wait113);
    expect(OAuthCalendarStorage.failure, isNull);
    expect((await b.store.backing())['flutter.$_key113'], _issued113);
    forward.release.complete();
    await rollback.started.future.timeout(_wait113);
    expect(OAuthCalendarStorage.failure, isNull);
    expect((await b.store.backing())['flutter.$_key113'], _issued113);
    rollback.release.complete();
    final error = await result.timeout(_wait113);
    expect(error, isA<OAuthStorageIndeterminate>());
    final diagnostic = error as OAuthStorageIndeterminate;
    expect(OAuthCalendarStorage.failure, same(diagnostic));
    expect(b.store.attempts, ['set:$_key113', 'set:$_key113']);
    final backing = await b.store.backing();
    expect(backing, {...before, 'flutter.$_key113': _issued113});
    expect(b.prefs.getString(_key113), _issued113);
    expect(a.prefs.getString(_key113), _issued113);
    return diagnostic;
  }

  Future<void> close() async {
    a.store.releaseAll();
    b.store.releaseAll();
    try {
      await Future.wait(pending).timeout(_wait113);
      await AccountPreferenceWrites.drain().timeout(_wait113);
      // Clear only these synthetic backing stores after assertions. Confirm
      // each exact cleared identity through the public core hook, so B's
      // global failure state cannot leak into the next independent case.
      for (final slot in [a, b]) {
        await invoke(slot, () async {
          expect(await slot.prefs.clear(), isTrue);
          await slot.prefs.reload();
          expect(slot.prefs.getKeys(), isEmpty);
          OAuthCalendarStorage.confirmAccountClearLocked(slot.prefs);
        }).timeout(_wait113);
      }
      expect(OAuthCalendarStorage.failure, isNull);
    } finally {
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = previous;
    }
  }
}
