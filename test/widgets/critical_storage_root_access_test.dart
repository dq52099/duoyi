// Exact critical startup phase + real root/providers, synthetic preferences.
// Does not execute complete main() or native startup.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:duoyi/screens/login_screen.dart';
import 'package:duoyi/widgets/critical_storage_gate.dart';
import 'package:duoyi/widgets/shared_text_import_sheet.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:duoyi/main.dart';
import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/services/required_storage_startup.dart';
import 'package:duoyi/screens/lock_screen.dart';

Future<void> _startupGuard(
  String label,
  Future<void> Function() task, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  try {
    await task().timeout(timeout);
  } on TimeoutException {
    debugPrint('[startup] $label timed out after ${timeout.inSeconds}s');
  } catch (e, st) {
    debugPrint('[startup] $label failed: $e\n$st');
  }
}

Future<void> _runSyncReloadTasksInBatches(
  List<Future<void> Function()> tasks, {
  int batchSize = 1,
  bool continueOnError = false,
  String label = 'sync reload',
}) async {
  for (var i = 0; i < tasks.length; i += batchSize) {
    final end = (i + batchSize).clamp(0, tasks.length);
    if (continueOnError) {
      await Future.wait([
        for (var j = i; j < end; j++)
          () async {
            try {
              await tasks[j]();
            } catch (e, st) {
              debugPrint('[main] $label task#$j failed: $e\n$st');
            }
          }(),
      ]);
    } else {
      await Future.wait([for (var j = i; j < end; j++) tasks[j]()]);
    }
    if (end < tasks.length) {
      await _yieldForNextFrame();
    }
  }
}

Future<void> _yieldForNextFrame([
  Duration delay = const Duration(milliseconds: 32),
]) {
  return Future<void>.delayed(delay);
}

Future<void> _runStartupStoragePhase(
  String label,
  List<Future<void> Function()> tasks, {
  int batchSize = 1,
}) {
  final startedAt = DateTime.now();
  return _startupGuard(label, () async {
    await _runSyncReloadTasksInBatches(tasks, batchSize: batchSize);
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    debugPrint('[startup] $label completed in ${elapsedMs}ms');
  }, timeout: const Duration(seconds: 18));
}

void main() {
  setUp(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
  });
  tearDown(() {
    I18n.setLocale(AppLocale.zh);
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = null;
  });
  for (final recovery in ['button', 'external', 'disposed', 'locked-config']) {
    testWidgets('real critical failure root recovery via $recovery', (
      tester,
    ) async {
      final initiallyLocked = recovery == 'locked-config';
      SharedPreferences.setMockInitialValues(
        initiallyLocked
            ? {
                'app_lock_enabled': true,
                'pref_first_day_of_week': 'invalid synthetic setting',
              }
            : {'app_lock_enabled': 7},
      );
      final appLockProvider = AppLockProvider();
      final authProvider = AuthProvider();
      final localeProvider = LocaleProvider();
      final themeProvider = ThemeProvider();
      final preferencesProvider = PreferencesProvider();
      final userProvider = UserProvider();
      final cloudSyncProvider = CloudSyncProvider();
      final criticalStorageStartup = RequiredStorageStartup();
      if (initiallyLocked) await appLockProvider.setPin('2468');
      Future<void> ensureCriticalLocalStorageStartup() {
        return criticalStorageStartup.ensure(
          isCurrent: () => !AccountPreferenceWrites.isBoundaryActive,
          run: (load) => cloudSyncProvider.suppressDirtyMarkWhile(
            () => _runSyncReloadTasksInBatches([
              // 关键 Provider 必须成功加载，失败后允许显式重试。
              () => load(() => appLockProvider.loadFromStorage()),
              () => load(() => localeProvider.loadFromStorage()),
              () => load(
                () => authProvider.loadFromStorage(refreshServerConfig: false),
              ),
              () => load(() => themeProvider.loadFromStorage()),
              () => load(() => preferencesProvider.loadFromStorage()),
              () => load(() => userProvider.loadFromStorage()),
              () => load(() => cloudSyncProvider.loadFromStorage()),
            ]),
          ),
        );
      }

      final initialCritical = _runStartupStoragePhase(
        'critical local storage',
        [ensureCriticalLocalStorageStartup],
      );
      for (
        var step = 0;
        step < 100 &&
            !criticalStorageStartup.failed &&
            !criticalStorageStartup.ready;
        step++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await initialCritical;

      expect(criticalStorageStartup.ready, isFalse);
      expect(
        authProvider.successfulAccountTransitionRevision,
        initiallyLocked ? 1 : 0,
      );
      expect(appLockProvider.isLocked, initiallyLocked);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => TodoProvider()),
            ChangeNotifierProvider(create: (_) => HabitProvider()),
            ChangeNotifierProvider(create: (_) => PomodoroProvider()),
            ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
            ChangeNotifierProvider(create: (_) => FocusRoomProvider()),
            ChangeNotifierProvider(create: (_) => CustomFocusSoundProvider()),
            ChangeNotifierProvider<CloudSyncProvider>.value(
              value: cloudSyncProvider,
            ),
            ChangeNotifierProvider(create: (_) => CalendarProvider()),
            ChangeNotifierProvider<UserProvider>.value(value: userProvider),
            ChangeNotifierProvider(create: (_) => CountdownProvider()),
            ChangeNotifierProvider(create: (_) => NoteProvider()),
            ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
            ChangeNotifierProvider(create: (_) => DiaryProvider()),
            ChangeNotifierProvider(create: (_) => GoalProvider()),
            ChangeNotifierProvider(create: (_) => CourseProvider()),
            ChangeNotifierProvider<AppLockProvider>.value(
              value: appLockProvider,
            ),
            ChangeNotifierProvider<PreferencesProvider>.value(
              value: preferencesProvider,
            ),
            ChangeNotifierProvider(create: (_) => AchievementProvider()),
            ChangeNotifierProvider(create: (_) => ShareProvider()),
            ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
            ChangeNotifierProvider(create: (_) => NotificationService()),
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider(create: (_) => AiService()),
            ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
            ChangeNotifierProvider(create: (_) => LocationReminderProvider()),
            ChangeNotifierProvider(create: (_) => CalendarSyncProvider()),
            ChangeNotifierProvider(
              create: (_) => AppUpdateService(
                repo: 'dq52099/duoyi',
                currentVersion: AppVersion.name,
              ),
            ),
          ],
          child: DuoyiApp(
            criticalStorageStartup: criticalStorageStartup,
            retryCriticalStorage: ensureCriticalLocalStorageStartup,
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(MainShell), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(CriticalStorageGate), findsOneWidget);
      expect(criticalStorageStartup.failed, isTrue);
      expect(
        find.byKey(const ValueKey('critical_storage_retry')).hitTestable(),
        findsOneWidget,
        reason: 'partial lock hydration must not hide initial storage recovery',
      );
      expect(find.byType(LockScreen), findsNothing);
      final gateRoute = ModalRoute.of(
        tester.element(find.byType(CriticalStorageGate)),
      )!;
      expect(gateRoute.popDisposition, RoutePopDisposition.doNotPop);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(CriticalStorageGate), findsOneWidget);
      if (recovery == 'external') {
        receiveSharedText('synthetic share queued during failed startup');
        await tester.pumpAndSettle();
        expect(find.byType(SharedTextImportSheet), findsNothing);
      }
      final prefs = await SharedPreferences.getInstance();
      if (initiallyLocked) {
        await prefs.remove('pref_first_day_of_week');
      } else {
        await prefs.setBool('app_lock_enabled', false);
      }
      Future<void> finishRetry() async {
        // Keep provider futures and the extracted frame-yield timers in the
        // same FakeAsync zone. pumpAndSettle may finish between load batches.
        for (
          var step = 0;
          step < 100 && !criticalStorageStartup.ready;
          step++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
          if (criticalStorageStartup.failed && !criticalStorageStartup.busy) {
            break;
          }
        }
      }

      if (recovery == 'disposed') {
        await tester.pumpWidget(const SizedBox.shrink());
        unawaited(
          _startupGuard(
            'external critical retry',
            ensureCriticalLocalStorageStartup,
          ),
        );
        await finishRetry();
        expect(criticalStorageStartup.ready, isTrue);
        expect(tester.takeException(), isNull);
      } else {
        if (recovery == 'button' || initiallyLocked) {
          await tester.tap(
            find.byKey(const ValueKey('critical_storage_retry')),
          );
        } else {
          unawaited(
            _startupGuard(
              'external critical retry',
              ensureCriticalLocalStorageStartup,
            ),
          );
          await finishRetry();
        }
        await finishRetry();
        await tester.pumpAndSettle();
        expect(criticalStorageStartup.ready, isTrue);
        expect(
          authProvider.successfulAccountTransitionRevision,
          greaterThan(0),
        );
        expect(find.byType(CriticalStorageGate), findsNothing);
        expect(find.byType(MainShell), findsOneWidget);
        if (initiallyLocked) {
          expect(find.byType(LockScreen), findsOneWidget);
          expect(gateRoute.popDisposition, RoutePopDisposition.doNotPop);
          await appLockProvider.unlockWith('2468');
          expect(appLockProvider.isLocked, isFalse);
          await tester.pumpAndSettle();
        }
        expect(gateRoute.popDisposition, RoutePopDisposition.bubble);
        if (recovery != 'external') {
          receiveSharedText('synthetic startup recovery text');
        }
        await tester.pumpAndSettle();
        expect(find.byType(SharedTextImportSheet), findsOneWidget);
        if (recovery == 'external') {
          expect(
            find.text('synthetic share queued during failed startup'),
            findsOneWidget,
          );
        }
        Navigator.of(tester.element(find.byType(SharedTextImportSheet))).pop();
        await tester.pumpAndSettle();
        final shell = tester.state(find.byType(MainShell));
        criticalStorageStartup.invalidate();
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(MainShell)), same(shell));
        expect(find.byType(LockScreen), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
      }
      criticalStorageStartup.dispose();
      appLockProvider.dispose();
      authProvider.dispose();
      localeProvider.dispose();
      themeProvider.dispose();
      preferencesProvider.dispose();
      userProvider.dispose();
      cloudSyncProvider.dispose();
    });
  }
}
