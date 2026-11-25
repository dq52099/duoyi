import 'dart:async';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/screens/habit_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'rejected check-in preserves count and gives live retry feedback',
    (tester) async {
      final f = _Fixture();
      await f.pump(tester);
      f.store.reject = true;
      await _tapAndDrain(tester);
      expect(tester.takeException(), isNull);
      expect(f.habits.habits.single.todayCount(), 0);
      expect(find.byType(SnackBar), findsOneWidget);
      final zh = tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byType(SnackBar),
                  matching: find.byType(Text),
                )
                .first,
          )
          .data!;
      expect(zh, isNot(contains('StateError')));
      expect(f.haptics, 0);
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      final en = tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byType(SnackBar),
                  matching: find.byType(Text),
                )
                .first,
          )
          .data!;
      expect(en, isNot(zh));
      expect(en, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
      await _tapAndDrain(tester);
      expect(f.habits.habits.single.todayCount(), 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('held check-in success follows locale selected before feedback', (
    tester,
  ) async {
    final f = _Fixture();
    await f.pump(tester);
    await tester.runAsync(() async {
      f.store.armHold();
      await tester.tap(_checkIn());
      await f.store.started.future;
    });
    I18n.setLocale(AppLocale.en);
    await tester.pump();
    await tester.runAsync(() async {
      f.store.release.complete();
      await AccountPreferenceWrites.drain();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(f.habits.habits.single.todayCount(), 1);
    final message = tester
        .widget<Text>(
          find
              .descendant(
                of: find.byType(SnackBar),
                matching: find.byType(Text),
              )
              .first,
        )
        .data!;
    expect(message, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
    I18n.setLocale(AppLocale.zh);
    await tester.pump();
    final updated = tester
        .widget<Text>(
          find
              .descendant(
                of: find.byType(SnackBar),
                matching: find.byType(Text),
              )
              .first,
        )
        .data!;
    expect(updated, isNot(message));
  });

  testWidgets('disabled haptics do not block check-in or success feedback', (
    tester,
  ) async {
    final preferences = PreferencesProvider();
    final f = _Fixture(preferences: preferences);
    await f.pump(tester);
    await preferences.setHaptic(false);

    await _tapAndDrain(tester);

    expect(f.habits.habits.single.todayCount(), 1);
    expect(f.haptics, 0);
    _expectCheckInSuccess(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('held check-in reads haptics setting after the save completes', (
    tester,
  ) async {
    final preferences = PreferencesProvider();
    final f = _Fixture(preferences: preferences);
    await f.pump(tester);
    await tester.runAsync(() async {
      f.store.armHold();
      await tester.tap(_checkIn());
      await f.store.started.future;
    });

    await tester.runAsync(() async {
      await preferences.setHaptic(false);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await tester.runAsync(() async {
      f.store.release.complete();
      await AccountPreferenceWrites.drain();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(f.habits.habits.single.todayCount(), 1);
    expect(f.haptics, 0);
    _expectCheckInSuccess(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('platform haptic failure preserves check-in success', (
    tester,
  ) async {
    final preferences = PreferencesProvider();
    final f = _Fixture(preferences: preferences);
    await f.pump(tester);
    f.rejectHaptics = true;

    await _tapAndDrain(tester);

    expect(f.habits.habits.single.todayCount(), 1);
    expect(f.haptics, 1);
    _expectCheckInSuccess(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('covered check-in stays silent after its held haptic', (
    tester,
  ) async {
    final f = _Fixture();
    await f.pump(tester);
    await tester.runAsync(() async {
      f.armHapticHold();
      await tester.tap(_checkIn());
      await f.hapticStarted.future.timeout(const Duration(seconds: 3));
    });
    final systemSoundsAtHapticStart = f.systemSoundsAtHapticStart;

    unawaited(
      f.navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covering route')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      f.releaseHaptic();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(f.haptics, 1);
    expect(f.hapticArguments, ['HapticFeedbackType.mediumImpact']);
    expect(systemSoundsAtHapticStart, isNotNull);
    expect(f.systemSounds, systemSoundsAtHapticStart);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account reset during held check-in haptic stays silent', (
    tester,
  ) async {
    final f = _Fixture();
    await f.pump(tester);
    await tester.runAsync(() async {
      f.armHapticHold();
      await tester.tap(_checkIn());
      await f.hapticStarted.future.timeout(const Duration(seconds: 3));
    });
    final systemSoundsAtHapticStart = f.systemSoundsAtHapticStart;

    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    f.habits.resetLocalState();
    f.audit.resetLocalState();
    await tester.runAsync(() async {
      f.releaseHaptic();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(f.habits.habits, isEmpty);
    expect(f.haptics, 1);
    expect(f.hapticArguments, ['HapticFeedbackType.mediumImpact']);
    expect(systemSoundsAtHapticStart, isNotNull);
    expect(f.systemSounds, systemSoundsAtHapticStart);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final hapticsEnabled in [true, false]) {
    testWidgets(
      'undo honors the live haptics setting when enabled=$hapticsEnabled',
      (tester) async {
        final preferences = PreferencesProvider();
        final f = _Fixture(preferences: preferences);
        await f.pump(tester);
        if (!hapticsEnabled) await preferences.setHaptic(false);

        await _tapAndDrain(tester);
        expect(f.habits.habits.single.todayCount(), 1);
        f.haptics = 0;

        final undo = find.byKey(const ValueKey('habit-undo-inline-button'));
        expect(undo, findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(undo);
          await AccountPreferenceWrites.drain();
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();

        expect(f.habits.habits.single.todayCount(), 0);
        expect(f.haptics, hapticsEnabled ? 1 : 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('covered retained check-in callback cannot write', (
    tester,
  ) async {
    final f = _Fixture();
    await f.pump(tester);
    final callback = tester.widget<FilledButton>(_checkIn()).onPressed!;
    final writes = f.store.habitWrites;
    unawaited(
      f.navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Unrelated route')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      callback();
      await AccountPreferenceWrites.drain();
    });
    await tester.pumpAndSettle();
    expect(f.store.habitWrites, writes);
    expect(f.habits.habits.single.todayCount(), 0);
    expect(find.byType(SnackBar), findsNothing);
    expect(f.haptics, 0);
  });

  testWidgets(
    'check-in invalidated during write stays silent without an uncaught error',
    (tester) async {
      final f = _Fixture();
      await f.pump(tester);
      await tester.runAsync(() async {
        f.store.armHold();
        await tester.tap(_checkIn());
        await f.store.started.future;
      });
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      f.habits.resetLocalState();
      f.audit.resetLocalState();
      await tester.runAsync(() async {
        f.store.release.complete();
        await AccountPreferenceWrites.drain();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(f.habits.habits, isEmpty);
      expect(f.audit.entries, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(f.haptics, 0);
    },
  );
}

void _expectCheckInSuccess(WidgetTester tester) {
  expect(find.byType(SnackBar), findsOneWidget);
  expect(find.textContaining('已打卡「Synthetic habit」'), findsOneWidget);
}

Finder _checkIn() => find.widgetWithText(
  FilledButton,
  I18n.current == AppLocale.en ? 'Check in' : '打卡',
);

Future<void> _tapAndDrain(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(_checkIn());
    await AccountPreferenceWrites.drain();
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
}

class _Fixture {
  _Fixture({this.preferences});

  final PreferencesProvider? preferences;
  final store = _HabitStore();
  final habits = HabitProvider();
  final audit = TimeAuditProvider();
  final theme = ThemeProvider();
  final navigator = GlobalKey<NavigatorState>();
  int haptics = 0;
  final List<Object?> hapticArguments = [];
  int systemSounds = 0;
  int? systemSoundsAtHapticStart;
  bool rejectHaptics = false;
  bool holdHaptics = false;
  Completer<void> hapticStarted = Completer<void>();
  Completer<void> hapticRelease = Completer<void>();

  void armHapticHold() {
    holdHaptics = true;
    hapticStarted = Completer<void>();
    hapticRelease = Completer<void>();
    systemSoundsAtHapticStart = null;
  }

  void releaseHaptic() {
    if (!hapticRelease.isCompleted) hapticRelease.complete();
  }

  Future<void> pump(WidgetTester tester) async {
    SharedPreferencesStorePlatform.instance = store;
    habits.timeAudit = audit;
    await tester.runAsync(
      () => habits.addHabit(
        Habit(id: 'synthetic', name: 'Synthetic habit', targetCount: 5),
      ),
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics++;
        hapticArguments.add(call.arguments);
        if (holdHaptics) {
          systemSoundsAtHapticStart ??= systemSounds;
          if (!hapticStarted.isCompleted) hapticStarted.complete();
          await hapticRelease.future;
        }
        if (rejectHaptics) {
          throw PlatformException(code: 'haptic_unavailable');
        }
      } else if (call.method == 'SystemSound.play') {
        systemSounds++;
      }
      return null;
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        if (!store.release.isCompleted) store.release.complete();
        releaseHaptic();
        await AccountPreferenceWrites.drain();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      habits.dispose();
      audit.dispose();
      theme.dispose();
      preferences?.dispose();
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      tester.view.reset();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<HabitProvider>.value(value: habits),
          ChangeNotifierProvider<TimeAuditProvider>.value(value: audit),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          if (preferences != null)
            ChangeNotifierProvider<PreferencesProvider>.value(
              value: preferences!,
            ),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          theme: theme.brand.theme,
          home: const HabitScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_checkIn(), findsOneWidget);
  }
}

class _HabitStore extends InMemorySharedPreferencesStore {
  _HabitStore() : super.withData({});
  bool reject = false;
  bool hold = false;
  int habitWrites = 0;
  Completer<void> started = Completer<void>();
  Completer<void> release = Completer<void>();
  // Called inside runAsync: held storage futures must share its real zone.
  void armHold() {
    hold = true;
    started = Completer<void>();
    release = Completer<void>();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.habits') {
      habitWrites++;
      if (hold && !started.isCompleted) {
        started.complete();
        await release.future;
      }
      await super.setValue(type, key, value);
      if (reject) {
        reject = false;
        return false;
      }
      return true;
    }
    return super.setValue(type, key, value);
  }
}
