// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart' show clock;
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'account preference cleanup removes the running timer snapshot',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PomodoroProvider.runningSnapshotKey: '{stale}',
      });
      expect(
        AccountLocalDataCleaner.accountScopedKeys,
        contains(PomodoroProvider.runningSnapshotKey),
      );

      await AccountLocalDataCleaner.clearSharedPreferences();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(PomodoroProvider.runningSnapshotKey), isFalse);
    },
  );

  test(
    'queued snapshot write followed by reset ends with no running snapshot',
    () async {
      final store = _installControlledStore(<String, Object>{});
      store.blockNextSnapshotSet = true;
      final provider = PomodoroProvider();

      provider.startIfIdle();
      await store.snapshotSetEntered.future;
      provider.resetTimer();
      store.releaseSnapshotSet.complete();

      expect(await provider.waitForSnapshotWrites(), isTrue);
      expect(store.snapshotOperations, ['set', 'remove']);
      expect(await _readStoredSnapshot(), isNull);
      provider.dispose();
    },
  );

  test(
    'failed pause removal writes a tombstone before another restore',
    () async {
      final store = _installControlledStore(<String, Object>{});
      final provider = PomodoroProvider();
      await provider.setConfig(PomodoroConfig(focusDuration: 60));
      provider.startIfIdle();
      expect(await provider.waitForSnapshotWrites(), isTrue);

      store.failedSnapshotRemovesRemaining = 1;
      provider.toggleTimer();
      expect(await provider.waitForSnapshotWrites(), isTrue);
      expect(
        jsonDecode((await _readStoredSnapshot())!) as Map<String, dynamic>,
        {'isRunning': false},
      );
      provider.dispose();

      final restored = PomodoroProvider();
      await restored.loadFromStorage();
      expect(restored.state.isRunning, isFalse);
      expect(restored.sessions, isEmpty);
      expect(await restored.waitForSnapshotWrites(), isTrue);
      restored.dispose();
    },
  );

  test(
    'failed completion clear cannot revive or duplicate its persisted session',
    () async {
      final store = _installControlledStore(<String, Object>{});
      final provider = PomodoroProvider();
      await provider.setConfig(PomodoroConfig(focusDuration: 60));
      provider.startIfIdle();
      expect(await provider.waitForSnapshotWrites(), isTrue);

      final originalSnapshot =
          jsonDecode((await _readStoredSnapshot())!) as Map<String, dynamic>;
      final sessionId = originalSnapshot['sessionId'] as String;
      expect(sessionId, isNotEmpty);

      store.failedSnapshotRemovesRemaining = 1;
      store.failedSnapshotSetsRemaining = 1;
      provider.finishCurrentSession();
      expect(await provider.waitForSnapshotWrites(), isFalse);
      expect(provider.sessions, hasLength(1));
      expect(provider.sessions.single.id, sessionId);
      expect(provider.sessions.single.type, PomodoroType.focus);
      expect(provider.state.type, PomodoroType.shortBreak);
      expect(provider.state.isRunning, isFalse);

      final persistedSessions = await _waitForPersistedSessions(
        expectedTodayCount: 1,
      );
      expect(persistedSessions, hasLength(1));
      expect(persistedSessions.single.id, sessionId);
      provider
          .dispose(); // Cancel clear retries; preserve the stale disk snapshot.

      final staleDiskSnapshot =
          jsonDecode((await _readStoredSnapshot())!) as Map<String, dynamic>;
      expect(staleDiskSnapshot['isRunning'], isTrue);
      expect(staleDiskSnapshot['sessionId'], sessionId);

      final restored = PomodoroProvider();
      await restored.loadFromStorage();
      await restored.waitForSnapshotWrites();

      expect(restored.state.isRunning, isFalse);
      expect(restored.sessions, hasLength(1));
      expect(restored.sessions.single.id, sessionId);
      expect(restored.sessionCountToday, 1);
      expect(await _readStoredSnapshot(), isNull);
      restored.dispose();
    },
  );

  for (final resetProvider in [true, false]) {
    test(
      resetProvider
          ? 'blocked expired restore cannot settle after provider reset'
          : 'blocked expired restore cannot settle after account invalidation',
      () async {
        final store = _installControlledStore(<String, Object>{
          PomodoroProvider.runningSnapshotKey: jsonEncode(
            _expiredSnapshotPayload(),
          ),
        });
        store.blockNextSnapshotRemove = true;
        final provider = PomodoroProvider();

        final loading = provider.loadFromStorage();
        await store.snapshotRemoveEntered.future;
        if (resetProvider) {
          provider.resetLocalState();
        } else {
          AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        }
        store.releaseSnapshotRemove.complete();

        await loading;
        await provider.waitForSnapshotWrites();
        expect(provider.state.isRunning, isFalse);
        expect(provider.sessions, isEmpty);
        expect(provider.sessionCountToday, 0);
        expect(await _readStoredSnapshot(), isNull);
        provider.dispose();
      },
    );
  }

  test('a later storage load cannot restore an expired old snapshot', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final provider = PomodoroProvider();

    await provider.loadFromStorage();
    provider.startIfIdle();
    expect(await provider.waitForSnapshotWrites(), isTrue);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      PomodoroProvider.runningSnapshotKey,
      jsonEncode(_expiredSnapshotPayload()),
    );
    final sessionsBeforeReload = provider.sessions.length;
    final countBeforeReload = provider.sessionCountToday;
    final timerEndBeforeReload = provider.focusTimerEndsAtMillis;

    await provider.loadFromStorage();

    expect(provider.state.isRunning, isTrue);
    expect(provider.sessions, hasLength(sessionsBeforeReload));
    expect(provider.sessionCountToday, countBeforeReload);
    expect(provider.focusTimerEndsAtMillis, timerEndBeforeReload);
    provider.dispose();
  });

  test('a failed snapshot write is retried by the next timer tick', () async {
    final store = _installControlledStore(<String, Object>{});
    store.failedSnapshotSetsRemaining = 1;
    final provider = PomodoroProvider();
    await provider.setConfig(PomodoroConfig(focusDuration: 60));

    fakeAsync((async) {
      bool? firstWriteSucceeded;
      provider.startIfIdle();
      unawaited(
        provider.waitForSnapshotWrites().then((value) {
          firstWriteSucceeded = value;
        }),
      );
      async.flushMicrotasks();

      expect(firstWriteSucceeded, isFalse);
      expect(store.snapshotSetAttempts, 1);

      async.elapse(const Duration(seconds: 1));
      bool? retrySucceeded;
      unawaited(
        provider.waitForSnapshotWrites().then((value) {
          retrySucceeded = value;
        }),
      );
      async.flushMicrotasks();

      expect(retrySucceeded, isTrue);
      expect(store.snapshotSetAttempts, 2);
      expect(async.periodicTimerCount, 1);
      provider.dispose();
    });

    expect(await _readStoredSnapshot(), isNotNull);
  });

  test('timer anchors keep elapsed time after a blocked event loop', () async {
    final provider = PomodoroProvider();
    await provider.setConfig(PomodoroConfig(focusDuration: 60));

    fakeAsync((async) {
      final startedAt = clock.now().millisecondsSinceEpoch;
      expect(provider.focusTimerEndsAtMillis, 0);
      expect(provider.focusTimerStartedAtMillis, 0);

      provider.startIfIdle();
      final endsAt = provider.focusTimerEndsAtMillis;
      expect(endsAt, startedAt + const Duration(seconds: 60).inMilliseconds);
      expect(provider.focusTimerStartedAtMillis, 0);

      // Simulate a blocked UI isolate: clock time advances while periodic
      // callbacks do not run. The first callback after the block must recalc
      // from the persisted deadline, not subtract only one second.
      async.elapseBlocking(const Duration(seconds: 15));
      async.elapse(Duration.zero);
      expect(provider.state.remainingSeconds, 45);
      expect(provider.focusTimerEndsAtMillis, endsAt);

      provider.resetTimer();
      expect(provider.focusTimerEndsAtMillis, 0);
      expect(provider.focusTimerStartedAtMillis, 0);

      provider.setCountUpMode(true);
      final countUpStartedAt = clock.now().millisecondsSinceEpoch;
      provider.startIfIdle();
      expect(provider.focusTimerStartedAtMillis, countUpStartedAt);
      expect(provider.focusTimerEndsAtMillis, 0);

      async.elapseBlocking(const Duration(seconds: 9));
      async.elapse(Duration.zero);
      expect(provider.state.remainingSeconds, 9);
      expect(provider.focusTimerStartedAtMillis, countUpStartedAt);

      provider.resetTimer();
      expect(provider.focusTimerStartedAtMillis, 0);

      bool? snapshotWritesSucceeded;
      unawaited(
        provider.waitForSnapshotWrites().then((value) {
          snapshotWritesSucceeded = value;
        }),
      );
      async.flushMicrotasks();
      expect(snapshotWritesSucceeded, isTrue);
      provider.dispose();
    });
  });
}

Map<String, Object?> _expiredSnapshotPayload() => <String, Object?>{
  'isRunning': true,
  'type': PomodoroType.focus.index,
  'isCountUp': false,
  'totalSeconds': 60,
  'endsAtMs': DateTime.now()
      .subtract(const Duration(seconds: 5))
      .millisecondsSinceEpoch,
  'completedSessions': 0,
};

_ControlledPreferencesStore _installControlledStore(
  Map<String, Object> initialValues,
) {
  SharedPreferences.setMockInitialValues(initialValues);
  final prefixedValues = <String, Object>{
    for (final entry in initialValues.entries)
      'flutter.${entry.key}': entry.value,
  };
  final store = _ControlledPreferencesStore(prefixedValues);
  SharedPreferencesStorePlatform.instance = store;
  return store;
}

Future<List<PomodoroSession>> _waitForPersistedSessions({
  int? expectedTodayCount,
}) async {
  final prefs = await SharedPreferences.getInstance();
  for (var attempt = 0; attempt < 10; attempt++) {
    await prefs.reload();
    final raw = prefs.getString('pomodoro_sessions');
    if (raw != null &&
        (expectedTodayCount == null ||
            prefs.getInt('pomodoro_count_today') == expectedTodayCount)) {
      return (jsonDecode(raw) as List)
          .map((item) => PomodoroSession.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    await Future<void>.delayed(Duration.zero);
  }
  return <PomodoroSession>[];
}

Future<String?> _readStoredSnapshot() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return prefs.getString(PomodoroProvider.runningSnapshotKey);
}

class _ControlledPreferencesStore extends InMemorySharedPreferencesStore {
  _ControlledPreferencesStore(super.data) : super.withData();

  static const _snapshotPlatformKey =
      'flutter.${PomodoroProvider.runningSnapshotKey}';

  final snapshotOperations = <String>[];
  int snapshotSetAttempts = 0;
  int failedSnapshotSetsRemaining = 0;
  int failedSnapshotRemovesRemaining = 0;
  bool blockNextSnapshotSet = false;
  bool blockNextSnapshotRemove = false;
  final snapshotSetEntered = Completer<void>();
  final releaseSnapshotSet = Completer<void>();
  final snapshotRemoveEntered = Completer<void>();
  final releaseSnapshotRemove = Completer<void>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == _snapshotPlatformKey) {
      snapshotSetAttempts++;
      snapshotOperations.add('set');
      if (blockNextSnapshotSet) {
        blockNextSnapshotSet = false;
        snapshotSetEntered.complete();
        await releaseSnapshotSet.future;
      }
      if (failedSnapshotSetsRemaining > 0) {
        failedSnapshotSetsRemaining--;
        return false;
      }
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (key == _snapshotPlatformKey) {
      snapshotOperations.add('remove');
      if (blockNextSnapshotRemove) {
        blockNextSnapshotRemove = false;
        snapshotRemoveEntered.complete();
        await releaseSnapshotRemove.future;
      }
      if (failedSnapshotRemovesRemaining > 0) {
        failedSnapshotRemovesRemaining--;
        return false;
      }
    }
    return super.remove(key);
  }
}
