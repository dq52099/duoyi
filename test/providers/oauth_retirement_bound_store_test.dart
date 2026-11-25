// ignore_for_file: depend_on_referenced_packages

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/oauth_calendar_storage.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _wait = Duration(seconds: 5);
const _fence = OAuthCalendarStorage.retirementFenceKey;
const _device = 'bound_store_fixture_device_setting';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() async => f = await _Fixture.create());
  tearDown(() async => f.close());

  test(
    'OBS122-01 default B false-before arm stays bound after singleton C and explicit B retry settles it',
    () async => _exerciseBoundFailure(f, persist: false),
  );

  test(
    'OBS122-02 default B false-after arm stays bound after singleton C and explicit B retry settles it',
    () async => _exerciseBoundFailure(f, persist: true),
  );
}

Future<void> _exerciseBoundFailure(_Fixture f, {required bool persist}) async {
  final a = f.primary;
  final b = await f.slot('B');
  expect(identical(await SharedPreferences.getInstance(), b.prefs), isTrue);

  // C has not acquired its store yet. Its older default ticket cannot recover
  // B by sequence. Otherwise an incorrect C recovery could hide a broken B
  // recovery, since B's failed session also keeps B pending independently.
  final queuedC = f.announce();
  final defaultB = f.announce();
  final beforeB = await b.disk();
  b.store.rejectNextSet(_fence, persist: persist);
  final failure = await f.observe(f.bind(b, defaultB)).timeout(_wait);
  expect(failure.error, isA<OAuthAccountRetirementPending>());
  expect(failure.value, isNull);
  expect(b.store.attempts, ['set:$_fence']);
  expect(b.store.removals, isEmpty);
  final failedBacking = await b.disk();
  expect(failedBacking.containsKey(_fence), persist);
  if (persist) {
    expect(failedBacking[_fence], isA<String>());
    expect({
      for (final entry in failedBacking.entries)
        if (entry.key != _fence) entry.key: entry.value,
    }, beforeB);
  } else {
    expect(failedBacking, beforeB);
  }

  // This resets the real singleton only after B has failed its actual arm.
  final c = await f.slot('C');
  expect(identical(await SharedPreferences.getInstance(), c.prefs), isTrue);
  expect(identical(b.prefs, c.prefs), isFalse);
  // Until C binds, its own unbound ticket still blocks every store.
  await f.expectState(a, pending: true, fullFence: false);
  await f.expectState(c, pending: true, fullFence: false);
  await f.expectState(b, pending: true, fullFence: persist);

  final sessionC = await f.bind(c, queuedC).timeout(_wait);
  await f.expectState(a, pending: false, fullFence: false);
  await f.expectState(c, pending: true, fullFence: true);
  await f.expectState(b, pending: true, fullFence: persist);
  await f.finish(c, sessionC).timeout(_wait);
  expect(c.store.count('set', _fence), 1);
  expect(c.store.count('remove', _fence), 1);
  expect(b.store.removals, isEmpty);
  expect(await b.disk(), failedBacking);
  // C's full finish does not settle B or spread B's bound failure to A/C.
  await f.expectState(a, pending: false, fullFence: false);
  await f.expectState(c, pending: false, fullFence: false);
  await f.expectState(b, pending: true, fullFence: persist);

  // Selecting B's backing platform for reload/write does not reset getInstance.
  // B must recover its bound default ticket using an explicit B alias even
  // though the current singleton remains C throughout this retry.
  expect(identical(await SharedPreferences.getInstance(), c.prefs), isTrue);
  final retryB = await f.bind(b, f.announce(store: b.prefs)).timeout(_wait);
  expect(identical(await SharedPreferences.getInstance(), c.prefs), isTrue);
  final retryBacking = await b.disk();
  expect(retryBacking[_fence], isA<String>());
  expect(retryBacking[_fence], isNot(failedBacking[_fence]));
  expect(b.store.count('set', _fence), 2);
  expect(b.store.removals, isEmpty);
  await f.expectState(a, pending: false, fullFence: false);
  await f.expectState(c, pending: false, fullFence: false);
  await f.expectState(b, pending: true, fullFence: true);

  await f.finish(b, retryB).timeout(_wait);
  expect(identical(await SharedPreferences.getInstance(), c.prefs), isTrue);
  await f.expectState(a, pending: false, fullFence: false);
  await f.expectState(c, pending: false, fullFence: false);
  await f.expectState(b, pending: false, fullFence: false);
  // Without B's correct recovery, its failed announcement survives this finish.
  expect(await b.disk(), beforeB);
  expect(b.store.count('remove', _fence), 1);
  expect(a.store.attempts, isEmpty);
  expect((await a.disk())[_device], 'A');
  expect((await c.disk())[_device], 'C');
  expect(c.store.count('set', _fence), 1);
  expect(c.store.count('remove', _fence), 1);
}

bool _owned(String key) =>
    key != _fence &&
    (AccountLocalDataCleaner.accountScopedKeys.contains(key) ||
        AccountLocalDataCleaner.accountScopedPrefixes.any(key.startsWith));

class _Result<T> {
  _Result.value(this.value) : error = null;
  _Result.error(this.error) : value = null;
  final T? value;
  final Object? error;
}

// Real shared_preferences platform backing, with one rejected set ACK. The
// false-after variant persists through the superclass before returning false.
class _BackingStore extends InMemorySharedPreferencesStore {
  _BackingStore(String label) : super.withData({'flutter.$_device': label});
  final attempts = <String>[];
  final _reject = <String, bool>{};

  void rejectNextSet(String key, {required bool persist}) =>
      _reject['set:$key'] = persist;
  int count(String operation, String key) =>
      attempts.where((value) => value == '$operation:$key').length;
  List<String> get removals =>
      attempts.where((value) => value.startsWith('remove:')).toList();
  Future<Map<String, Object>> backing() => super.getAll();
  void clearFaults() => _reject.clear();

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
}

class _Slot {
  _Slot(this.store, this.prefs);
  final _BackingStore store;
  final SharedPreferences prefs;
  Future<Map<String, Object>> disk() async => {
    for (final entry in (await store.backing()).entries)
      entry.key.substring('flutter.'.length): entry.value,
  };
}

class _Fixture {
  _Fixture(this.previous, this.primary) : slots = [primary];
  final SharedPreferencesStorePlatform previous;
  final _Slot primary;
  final List<_Slot> slots;
  final tickets = <OAuthAccountRetirementAnnouncement>[];
  final sessions = <OAuthAccountRetirementSession>[];
  final pending = <Future<void>>[];

  static Future<_Slot> _makeSlot(String label) async {
    SharedPreferences.resetStatic();
    final store = _BackingStore(label);
    SharedPreferencesStorePlatform.instance = store;
    return _Slot(store, await SharedPreferences.getInstance());
  }

  static Future<_Fixture> create() async {
    await AccountPreferenceWrites.drain().timeout(_wait);
    final previous = SharedPreferencesStorePlatform.instance;
    final primary = await _makeSlot('A');
    await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    primary.store.attempts.clear();
    return _Fixture(previous, primary);
  }

  Future<_Slot> slot(String label) async {
    final result = await _makeSlot(label);
    slots.add(result);
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
  ) => AccountPreferenceWrites.boundary(() async {
    SharedPreferencesStorePlatform.instance = slot.store;
    final session = await OAuthCalendarStorage.beginAccountRetirementLocked(
      slot.prefs,
      announcement: ticket,
    );
    sessions.add(session);
    return session;
  });

  Future<void> finish(_Slot slot, OAuthAccountRetirementSession session) =>
      AccountPreferenceWrites.boundary(() async {
        SharedPreferencesStorePlatform.instance = slot.store;
        await OAuthCalendarStorage.finishAccountRetirementLocked(
          session,
          hasRemainingOwnedData: (prefs) => prefs.getKeys().any(_owned),
        );
      });

  Future<void> expectState(
    _Slot slot, {
    required bool pending,
    required bool fullFence,
  }) => AccountPreferenceWrites.boundary(() async {
    SharedPreferencesStorePlatform.instance = slot.store;
    final attempts = slot.store.attempts.toList();
    await slot.prefs.reload();
    final inspection = OAuthCalendarStorage.inspectRetirementLocked(slot.prefs);
    expect(inspection.runtimePending, pending);
    expect(inspection.fullPending, fullFence);
    expect(inspection.scopedPending, isFalse);
    expect(inspection.hasPending, pending);
    expect(OAuthCalendarStorage.isAccountRetiring(slot.prefs), pending);
    if (pending) {
      expect(
        () => OAuthCalendarStorage.ensureAccountAdmissionLocked(slot.prefs),
        throwsA(isA<OAuthAccountRetirementPending>()),
      );
    } else {
      expect(
        () => OAuthCalendarStorage.ensureAccountAdmissionLocked(slot.prefs),
        returnsNormally,
      );
    }
    expect(slot.store.attempts, attempts);
  }).timeout(_wait);

  Future<_Result<T>> observe<T>(Future<T> task) {
    final result = task.then<_Result<T>>(
      (value) => _Result<T>.value(value),
      onError: (Object error, StackTrace _) => _Result<T>.error(error),
    );
    pending.add(result.then<void>((_) {}));
    return result;
  }

  Future<void> close() async {
    for (final slot in slots) {
      slot.store.clearFaults();
    }
    try {
      await Future.wait(pending).timeout(_wait);
      await AccountPreferenceWrites.drain().timeout(_wait);
      // After body assertions, settle owned incomplete work using public APIs.
      // This also allows teardown after an assertion with a live C/B session.
      await AccountPreferenceWrites.boundary(() async {
        for (final ticket in tickets) {
          OAuthCalendarStorage.failAccountRetirementAnnouncement(ticket);
        }
        for (final session in sessions) {
          OAuthCalendarStorage.failAccountRetirementLocked(session);
        }
      }).timeout(_wait);
      for (final slot in slots) {
        final session = await bind(
          slot,
          OAuthCalendarStorage.announceAccountRetirement(store: slot.prefs),
        ).timeout(_wait);
        await finish(slot, session).timeout(_wait);
      }
    } finally {
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = previous;
    }
  }
}
