import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/core/calendar_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/core/main_ui_copy.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/ai_schedule_screen.dart';
import 'package:duoyi/screens/calendar_screen.dart';
import 'package:duoyi/screens/goal_edit_screen.dart';
import 'package:duoyi/screens/mine_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/widgets/quick_capture_fab.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalLocale = I18n.current;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
  });

  tearDown(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = null;
    I18n.setLocale(originalLocale);
  });

  group('PreferencesProvider calendar & mine menu config persistence', () {
    test('calendar menu defaults, visibility guard, reorder, and reset persist',
        () async {
      final prefs = PreferencesProvider();
      addTearDown(prefs.dispose);
      await prefs.loadFromStorage();

      expect(
        prefs.calendarMenuOrder,
        PreferencesProvider.defaultCalendarMenuOrder,
      );
      expect(prefs.calendarMenuHidden, isEmpty);
      expect(
        prefs.visibleCalendarMenuItems,
        PreferencesProvider.defaultCalendarMenuOrder,
      );

      await prefs.setCalendarMenuItemVisible('year', false);
      await prefs.moveCalendarMenuItem('year', -2);
      expect(prefs.calendarMenuHidden, <String>{'year'});
      expect(prefs.visibleCalendarMenuItems, isNot(contains('year')));
      expect(
        prefs.calendarMenuOrder.indexOf('year'),
        PreferencesProvider.defaultCalendarMenuOrder.length - 3,
      );

      final reloaded = PreferencesProvider();
      addTearDown(reloaded.dispose);
      await reloaded.loadFromStorage();
      expect(reloaded.calendarMenuHidden, <String>{'year'});
      expect(reloaded.calendarMenuOrder, prefs.calendarMenuOrder);

      // Cannot hide the last remaining item.
      for (final item in PreferencesProvider.defaultCalendarMenuOrder) {
        await reloaded.setCalendarMenuItemVisible(item, false);
      }
      expect(reloaded.visibleCalendarMenuItems.length, greaterThanOrEqualTo(1));

      await reloaded.resetCalendarMenuConfig();
      expect(
        reloaded.calendarMenuOrder,
        PreferencesProvider.defaultCalendarMenuOrder,
      );
      expect(reloaded.calendarMenuHidden, isEmpty);
    });

    test('mine menu order defaults, reorder, reload, and reset persist',
        () async {
      final prefs = PreferencesProvider();
      addTearDown(prefs.dispose);
      await prefs.loadFromStorage();

      expect(prefs.mineMenuOrder, PreferencesProvider.defaultMineMenuOrder);

      await prefs.moveMineMenuGroup(9, -2);
      expect(prefs.mineMenuOrder, <int>[4, 5, 6, 9, 7, 8]);

      final reloaded = PreferencesProvider();
      addTearDown(reloaded.dispose);
      await reloaded.loadFromStorage();
      expect(reloaded.mineMenuOrder, <int>[4, 5, 6, 9, 7, 8]);

      await reloaded.resetMineMenuOrder();
      expect(reloaded.mineMenuOrder, PreferencesProvider.defaultMineMenuOrder);
    });
  });

  group('Gap 1: Goal creation entries (Calendar, QuickCapture, AI)', () {
    for (final brand in ['defaultBrand', 'liquidGlass']) {
      for (final locale in AppLocale.values) {
        testWidgets(
          'Calendar _QuickAddMenuSheet shows New goal at end and opens GoalEditScreen ($brand, ${locale.name})',
          (tester) async {
            final goalLabel = locale == AppLocale.en ? 'New goal' : '新建目标';
            final prefs = await _mountApp(
              tester,
              brand: brand,
              locale: locale,
              child: CalendarScreen(initialDate: DateTime(2026, 6, 29)),
            );
            expect(prefs.calendarMenuHidden, isEmpty);

            await tester.tap(find.byTooltip(CalendarUiCopy.quickAddTooltip));
            await tester.pumpAndSettle();

            final todoFinder = find.text(CalendarUiCopy.quickAddNewTodoTitle);
            final goalFinder = find.text(goalLabel);
            expect(todoFinder, findsOneWidget);
            expect(goalFinder, findsOneWidget);
            expect(
              tester.getTopLeft(todoFinder).dy,
              lessThan(tester.getTopLeft(goalFinder).dy),
            );
            if (locale == AppLocale.en) {
              _expectNoCjk(tester);
            }

            await tester.tap(goalFinder);
            await tester.pumpAndSettle();
            expect(find.byType(GoalEditScreen), findsOneWidget);
            if (locale == AppLocale.en) {
              _expectNoCjk(tester);
            }
          },
        );

        testWidgets(
          'QuickCaptureFab has goal mini FAB with unique heroTag and opens GoalEditScreen ($brand, ${locale.name})',
          (tester) async {
            final goalLabel = locale == AppLocale.en ? 'New goal' : '新建目标';
            await _mountApp(
              tester,
              brand: brand,
              locale: locale,
              child: const Scaffold(
                body: SizedBox.expand(),
                floatingActionButton: QuickCaptureFab(),
              ),
            );

            await tester.tap(find.byType(FloatingActionButton).last);
            await tester.pumpAndSettle();

            final goalFab = find.widgetWithIcon(
              FloatingActionButton,
              Icons.flag_circle_outlined,
            );
            expect(goalFab, findsOneWidget);
            expect(
              tester.widget<FloatingActionButton>(goalFab).heroTag,
              'quick_capture_goal',
            );
            expect(find.text(goalLabel), findsOneWidget);
            if (locale == AppLocale.en) {
              _expectNoCjk(tester);
            }

            await tester.tap(goalFab);
            await tester.pumpAndSettle();
            expect(find.byType(GoalEditScreen), findsOneWidget);
          },
        );

        testWidgets(
          'AiScheduleScreen provides New goal entry opening GoalEditScreen ($brand, ${locale.name})',
          (tester) async {
            final goalLabel = locale == AppLocale.en ? 'New goal' : '新建目标';
            await _mountApp(
              tester,
              brand: brand,
              locale: locale,
              child: const AiScheduleScreen(),
            );

            final goalBtn = find.byKey(
              const ValueKey('ai_schedule_new_goal_button'),
            );
            expect(goalBtn, findsOneWidget);
            expect(find.text(goalLabel), findsOneWidget);
            if (locale == AppLocale.en) {
              _expectNoCjk(tester);
            }

            await tester.ensureVisible(goalBtn);
            await tester.tap(goalBtn);
            await tester.pumpAndSettle();
            expect(find.byType(GoalEditScreen), findsOneWidget);
          },
        );
      }
    }
  });

  group('Gap 2: Calendar menu item configuration UI', () {
    for (final brand in ['defaultBrand', 'liquidGlass']) {
      for (final locale in AppLocale.values) {
        testWidgets(
          'Calendar menu configures visibility, reorder, and reset ($brand, ${locale.name})',
          (tester) async {
            final prefs = await _mountApp(
              tester,
              brand: brand,
              locale: locale,
              child: CalendarScreen(initialDate: DateTime(2026, 6, 29)),
            );
            final configureLabel =
                locale == AppLocale.en ? 'Configure menu' : '配置菜单';

            await tester.tap(find.byTooltip(MainUiCopy.calendarMenu));
            await tester.pumpAndSettle();
            expect(find.text(MainUiCopy.calendarViewYear), findsOneWidget);
            expect(find.text(configureLabel), findsOneWidget);

            await tester.tap(find.text(configureLabel));
            await tester.pumpAndSettle();
            expect(find.byType(AppModalSheet), findsOneWidget);
            if (locale == AppLocale.en) {
              _expectNoCjk(tester);
            }

            // Hide Year view and move Today down.
            await tester.tap(
              find.byKey(const ValueKey('calendar_menu_toggle_year')),
            );
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('calendar_menu_down_today')),
            );
            await tester.pumpAndSettle();

            expect(prefs.calendarMenuHidden, contains('year'));
            expect(prefs.calendarMenuOrder.first, 'pick');

            final doneLabel = locale == AppLocale.en ? 'Done' : '完成';
            await tester.tap(find.text(doneLabel));
            await tester.pumpAndSettle();

            // Verify menu reflects hidden & reordered items.
            await tester.tap(find.byTooltip(MainUiCopy.calendarMenu));
            await tester.pumpAndSettle();
            expect(find.text(MainUiCopy.calendarViewYear), findsNothing);
            expect(
              tester.getTopLeft(find.text(MainUiCopy.calendarPickDate)).dy,
              lessThan(
                tester.getTopLeft(find.text(MainUiCopy.calendarBackToToday)).dy,
              ),
            );

            // Reopen config and reset.
            await tester.tap(find.text(configureLabel));
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('calendar_menu_reset_button')),
            );
            await tester.pumpAndSettle();
            expect(prefs.calendarMenuHidden, isEmpty);
            expect(
              prefs.calendarMenuOrder,
              PreferencesProvider.defaultCalendarMenuOrder,
            );
          },
        );
      }
    }
  });

  group('Gap 3: Mine menu group sorting UI', () {
    for (final brand in ['defaultBrand', 'liquidGlass']) {
      for (final locale in AppLocale.values) {
        testWidgets(
          'Mine menu sort sheet reorders groups while keeping header/stats fixed and resets ($brand, ${locale.name})',
          (tester) async {
            final prefs = await _mountApp(
              tester,
              brand: brand,
              locale: locale,
              child: const MineScreen(),
            );

            final sortBtn = find.byKey(const ValueKey('mine_sort_menu_button'));
            expect(sortBtn, findsOneWidget);

            // Initially action_plan (4) appears above review (5).
            final actionTitle = I18n.tr('mine.group.action_plan');
            final reviewTitle = I18n.tr('mine.group.review');
            expect(
              tester.getTopLeft(find.text(actionTitle)).dy,
              lessThan(tester.getTopLeft(find.text(reviewTitle)).dy),
            );

            await tester.tap(sortBtn);
            await tester.pumpAndSettle();
            expect(find.byType(AppModalSheet), findsOneWidget);
            if (locale == AppLocale.en) {
              _expectNoCjk(tester, within: find.byType(AppModalSheet));
            }

            // Move group 5 (review) up above group 4 (action_plan).
            await tester.tap(find.byKey(const ValueKey('mine_sort_up_5')));
            await tester.pumpAndSettle();
            expect(prefs.mineMenuOrder.take(2).toList(), <int>[5, 4]);

            final doneLabel = locale == AppLocale.en ? 'Done' : '完成';
            await tester.tap(find.text(doneLabel));
            await tester.pumpAndSettle();

            // Review now appears above action_plan, while header/stats remain fixed above.
            expect(
              tester.getTopLeft(find.text(reviewTitle)).dy,
              lessThan(tester.getTopLeft(find.text(actionTitle)).dy),
            );
            expect(
              find.byKey(const ValueKey('mine_header_stable_box')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('mine_stats_stable_grid')),
              findsOneWidget,
            );

            // Reset restores original order.
            await tester.tap(sortBtn);
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('mine_sort_reset_button')),
            );
            await tester.pumpAndSettle();
            expect(prefs.mineMenuOrder, PreferencesProvider.defaultMineMenuOrder);
          },
        );
      }
    }
  });
}

Future<PreferencesProvider> _mountApp(
  WidgetTester tester, {
  required String brand,
  required AppLocale locale,
  required Widget child,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'active_brand': brand,
  });
  I18n.setLocale(locale);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final themeProvider = ThemeProvider();
  final prefs = PreferencesProvider();
  await themeProvider.loadFromStorage();
  await prefs.loadFromStorage();

  final auth = AuthProvider();
  final ai = _IdleAiService();
  final goalProvider = GoalProvider();
  final customSounds = CustomFocusSoundProvider();
  final updater = AppUpdateService(
    repo: 'dq52099/duoyi',
    currentVersion: AppVersion.name,
  );

  addTearDown(() async {
    await AccountPreferenceWrites.drain();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    themeProvider.dispose();
    prefs.dispose();
    auth.dispose();
    ai.dispose();
    goalProvider.dispose();
    customSounds.dispose();
    updater.dispose();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<PreferencesProvider>.value(value: prefs),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<AiService>.value(value: ai),
        ChangeNotifierProvider<GoalProvider>.value(value: goalProvider),
        ChangeNotifierProvider<CustomFocusSoundProvider>.value(
          value: customSounds,
        ),
        ChangeNotifierProvider<AppUpdateService>.value(value: updater),
        ChangeNotifierProvider(create: (_) => TodoProvider()),
        ChangeNotifierProvider(create: (_) => HabitProvider()),
        ChangeNotifierProvider(create: (_) => PomodoroProvider()),
        ChangeNotifierProvider(create: (_) => CloudSyncProvider()),
        ChangeNotifierProvider(create: (_) => CalendarProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => CountdownProvider()),
        ChangeNotifierProvider(create: (_) => NoteProvider()),
        ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
        ChangeNotifierProvider(create: (_) => DiaryProvider()),
        ChangeNotifierProvider(create: (_) => CourseProvider()),
        ChangeNotifierProvider(create: (_) => AppLockProvider()),
        ChangeNotifierProvider(create: (_) => AchievementProvider()),
        ChangeNotifierProvider(create: (_) => ShareProvider()),
        ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
        ChangeNotifierProvider(create: (_) => NotificationService()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => LocationReminderProvider()),
        ChangeNotifierProvider(create: (_) => CalendarSyncProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: Locale(locale == AppLocale.en ? 'en' : 'zh'),
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: themeProvider.brand.theme,
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return prefs;
}

void _expectNoCjk(WidgetTester tester, {Finder? within}) {
  final chinese = RegExp(r'[\u3400-\u9fff]');
  final textFinder = within == null
      ? find.byType(Text)
      : find.descendant(of: within, matching: find.byType(Text));
  final fieldFinder = within == null
      ? find.byType(TextField)
      : find.descendant(of: within, matching: find.byType(TextField));
  final strings = <String>[
    for (final w in tester.widgetList<Text>(textFinder))
      w.data ?? w.textSpan?.toPlainText() ?? '',
    for (final w in tester.widgetList<TextField>(fieldFinder)) ...[
      w.decoration?.labelText ?? '',
      w.decoration?.hintText ?? '',
      w.decoration?.helperText ?? '',
      w.decoration?.errorText ?? '',
    ],
  ];
  expect(strings.where(chinese.hasMatch), isEmpty);
}

class _IdleAiService extends AiService {
  @override
  bool get enabled => false;
}
