import 'dart:async';
import 'dart:convert';

import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const dndChannel = MethodChannel('duoyi/focus_dnd');
  const distractionChannel = MethodChannel('duoyi/focus_distraction');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(dndChannel, (call) async {
      switch (call.method) {
        case 'getStatus':
          return <String, Object?>{
            'supported': true,
            'accessGranted': true,
            'currentFilter': 1,
          };
        case 'enableDnd':
          return <String, Object?>{
            'enabled': true,
            'previousFilter': 1,
            'currentFilter': 2,
          };
        case 'restoreDnd':
          return true;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(distractionChannel, (call) async {
      if (call.method == 'setFocusBlocker') return true;
      if (call.method == 'getStatus') {
        return <String, Object?>{
          'supported': true,
          'accessGranted': true,
          'accessibilityGranted': true,
          'blockerConfigured': true,
        };
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(dndChannel, null);
    messenger.setMockMethodCallHandler(distractionChannel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'failed DND restoration retains the original filter and gates the next enable',
    () async {
      final dnd = _DndHarness()..restoreResults.addAll([false, false, true]);
      messenger.setMockMethodCallHandler(dndChannel, dnd.handle);
      final timer = await _timer(config: PomodoroConfig(autoEnableDnd: true));

      timer.startIfIdle();
      await _until(() => dnd.enableCalls == 1 && timer.focusDndActive);
      timer.toggleTimer();
      await _until(() => dnd.restoreFilters.length == 1);
      await _settle();

      expect(dnd.restoreFilters, [1]);
      expect(timer.focusDndActive, isFalse);
      expect(dnd.enableCalls, 1);
      await _settle();
      expect(dnd.restoreFilters, [
        1,
      ], reason: 'failed restore must not busy retry');

      timer.startIfIdle();
      await _until(() => dnd.restoreFilters.length == 2);
      await _settle();
      expect(dnd.restoreFilters, [1, 1]);
      expect(
        dnd.enableCalls,
        1,
        reason: 'the pending filter blocks a new enable',
      );
      expect(dnd.events.where((event) => event.startsWith('enable:')), [
        'enable:1',
      ]);

      timer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _until(() => dnd.enableCalls == 2 && timer.focusDndActive);
      expect(dnd.restoreFilters, [1, 1, 1]);
      expect(
        dnd.events.indexOf('restore:1:true'),
        lessThan(dnd.events.indexOf('enable:2')),
      );

      timer.toggleTimer();
      await _until(() => dnd.restoreFilters.length == 4);
      expect(dnd.restoreFilters, [1, 1, 1, 1]);
    },
  );

  test(
    'obsolete held DND enable restores before a new owner can enable',
    () async {
      final enableGate = _Gate();
      final dnd = _DndHarness()
        ..holdNextEnable = enableGate
        ..restoreResults.addAll([false, true]);
      messenger.setMockMethodCallHandler(dndChannel, dnd.handle);
      final timer = await _timer(config: PomodoroConfig(autoEnableDnd: true));

      try {
        timer.startIfIdle();
        await enableGate.arrived.future;

        timer.resetLocalState();
        await timer.setAutoEnableDnd(true);
        timer.startIfIdle();
        await _settle();
        expect(dnd.enableCalls, 1, reason: 'new owner waits for old enable');

        enableGate.release();
        await _until(() => dnd.restoreFilters.length == 1);
        await _settle();
        expect(dnd.restoreFilters, [1]);
        expect(dnd.enableCalls, 1);
        expect(
          dnd.events.where((event) => event.startsWith('enable:')),
          ['enable:1'],
          reason: 'failed compensation restore must not cause a blind enable',
        );
        await _settle();
        expect(dnd.restoreFilters, [
          1,
        ], reason: 'failed restore must not busy retry');

        timer.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await _until(() => dnd.enableCalls == 2 && timer.focusDndActive);
        expect(dnd.restoreFilters, [1, 1]);
        expect(
          dnd.events.indexOf('restore:1:true'),
          lessThan(dnd.events.indexOf('enable:2')),
        );

        timer.toggleTimer();
        await _until(() => dnd.restoreFilters.length == 3);
      } finally {
        enableGate.release();
      }
    },
  );

  for (final invalidation in ['reset', 'account', 'start-pause']) {
    test(
      'held foreground app result cannot publish status or a distraction penalty after $invalidation',
      () async {
        final foregroundGate = _Gate();
        var foregroundCalls = 0;
        messenger.setMockMethodCallHandler(distractionChannel, (call) async {
          if (call.method == 'setFocusBlocker') return true;
          if (call.method == 'getStatus') {
            return <String, Object?>{
              'supported': true,
              'accessGranted': true,
              'accessibilityGranted': true,
              'blockerConfigured': true,
            };
          }
          if (call.method == 'getForegroundApp') {
            foregroundCalls++;
            await foregroundGate.wait();
            return 'blocked.example.app';
          }
          return null;
        });
        final timer = await _timer(
          config: PomodoroConfig(
            strictFocusMode: true,
            monitorDistractingApps: true,
            distractingAppPackages: const ['blocked.example.app'],
          ),
        );

        try {
          timer.startIfIdle();
          await foregroundGate.arrived.future;
          var notifications = 0;
          timer.addListener(() => notifications++);

          switch (invalidation) {
            case 'reset':
              timer.resetLocalState();
            case 'account':
              AccountLocalDataCleaner.invalidateInFlightAccountWrites();
            case 'start-pause':
              timer.toggleTimer();
          }
          await _until(
            () =>
                invalidation != 'start-pause' ||
                timer.penalties.any(
                  (penalty) => penalty.reason == FocusPenaltyReason.pause,
                ),
          );
          await _settle();
          final notificationsBeforeRelease = notifications;
          final penaltiesBeforeRelease = timer.penalties.length;

          foregroundGate.release();
          await _settle();

          expect(foregroundCalls, 1);
          expect(timer.focusDistractionStatus.supported, isFalse);
          expect(timer.focusDistractionStatus.foregroundPackage, isNull);
          expect(timer.penalties.length, penaltiesBeforeRelease);
          expect(
            timer.penalties.where(
              (penalty) => penalty.reason == FocusPenaltyReason.distractingApp,
            ),
            isEmpty,
          );
          expect(notifications, notificationsBeforeRelease);
        } finally {
          foregroundGate.release();
        }
      },
    );
  }
}

Future<PomodoroProvider> _timer({required PomodoroConfig config}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('pomodoro_config', jsonEncode(config.toJson()));
  final timer = PomodoroProvider();
  await timer.loadFromStorage();
  addTearDown(() async {
    timer.dispose();
    await timer.waitForSnapshotWrites();
    await _settle();
  });
  return timer;
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(
    done(),
    isTrue,
    reason: 'The expected plugin operation did not settle',
  );
}

class _DndHarness {
  final events = <String>[];
  final restoreFilters = <int>[];
  final restoreResults = <bool>[];
  int enableCalls = 0;
  _Gate? holdNextEnable;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'getStatus':
        return <String, Object?>{
          'supported': true,
          'accessGranted': true,
          'currentFilter': 1,
        };
      case 'enableDnd':
        enableCalls++;
        events.add('enable:$enableCalls');
        final gate = holdNextEnable;
        holdNextEnable = null;
        if (gate != null) await gate.wait();
        return <String, Object?>{
          'enabled': true,
          'previousFilter': 1,
          'currentFilter': 2,
        };
      case 'restoreDnd':
        final arguments = call.arguments as Map<dynamic, dynamic>;
        final previousFilter = arguments['previousFilter'] as int;
        restoreFilters.add(previousFilter);
        final restored = restoreResults.isEmpty
            ? true
            : restoreResults.removeAt(0);
        events.add('restore:$previousFilter:$restored');
        return restored;
    }
    return null;
  }
}

class _Gate {
  final arrived = Completer<void>();
  final finished = Completer<void>();

  Future<void> wait() {
    if (!arrived.isCompleted) arrived.complete();
    return finished.future;
  }

  void release() {
    if (!finished.isCompleted) finished.complete();
  }
}
