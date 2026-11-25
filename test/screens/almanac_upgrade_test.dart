import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
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
import 'package:duoyi/screens/almanac_screen.dart';
import 'package:duoyi/screens/almanac_tools_screen.dart';
import 'package:duoyi/screens/calendar_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/widgets/app_date_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrapWithProviders(
  Widget child, {
  PreferencesProvider? preferencesProvider,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => TodoProvider()),
      ChangeNotifierProvider(create: (_) => HabitProvider()),
      ChangeNotifierProvider(create: (_) => PomodoroProvider()),
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => CloudSyncProvider()),
      ChangeNotifierProvider(create: (_) => CalendarProvider()),
      ChangeNotifierProvider(create: (_) => UserProvider()),
      ChangeNotifierProvider(create: (_) => CountdownProvider()),
      ChangeNotifierProvider(create: (_) => NoteProvider()),
      ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
      ChangeNotifierProvider(create: (_) => DiaryProvider()),
      ChangeNotifierProvider(create: (_) => GoalProvider()),
      ChangeNotifierProvider(create: (_) => CourseProvider()),
      ChangeNotifierProvider(create: (_) => AppLockProvider()),
      ChangeNotifierProvider.value(
        value: preferencesProvider ?? PreferencesProvider(),
      ),
      ChangeNotifierProvider(create: (_) => AchievementProvider()),
      ChangeNotifierProvider(create: (_) => ShareProvider()),
      ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
      ChangeNotifierProvider(create: (_) => NotificationService()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => AiService()),
      ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ChangeNotifierProvider(create: (_) => LocationReminderProvider()),
      ChangeNotifierProvider(create: (_) => CalendarSyncProvider()),
      ChangeNotifierProvider(
        create: (_) => AppUpdateService(
          repo: 'dq52099/duoyi',
          currentVersion: AppVersion.name,
        ),
      ),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() {
    I18n.setLocale(AppLocale.zh);
  });

  testWidgets(
    'CalendarScreen respects PreferencesProvider.showLunar, renders holiday/makeup tags, ISO week & constellation, and browsable Year view',
    (tester) async {
      // Use 480px width (still single-column mobile layout < 900px) so Ahem's
      // square 13px test glyphs leave room for CalendarMonthGrid's '休'/'班'
      // badge text instead of degrading to the compact dot indicator.
      tester.view.physicalSize = const Size(480, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final prefs = PreferencesProvider();
      await tester.pumpWidget(
        _wrapWithProviders(
          CalendarScreen(initialDate: DateTime(2026, 10, 1)),
          preferencesProvider: prefs,
        ),
      );
      await tester.pumpAndSettle();

      // Holiday '休' and makeup '班' badges in Oct 2026 (Oct 1-7 off, Oct 10 makeup).
      expect(find.text('休'), findsWidgets);
      expect(find.text('班'), findsWidgets);

      // Meta strip & agenda show ISO week + constellation + almanac shortcut.
      expect(find.byKey(const ValueKey('calendar_month_meta_strip')), findsOneWidget);
      expect(find.byKey(const ValueKey('agenda_open_almanac_chip')), findsOneWidget);
      expect(find.textContaining('第40周'), findsWidgets);
      expect(find.textContaining('天秤座'), findsWidgets);

      // Show lunar switch turns lunar display on/off dynamically.
      expect(find.textContaining('农历'), findsWidgets);
      await prefs.setShowLunar(false);
      await tester.pumpAndSettle();
      expect(find.text('农历 八月廿一'), findsNothing);

      // Year overview renders full mini-calendar grid day numbers and jumps cleanly.
      await tester.tap(find.text('年'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('calendar_year_overview')), findsOneWidget);
      expect(find.text('15'), findsWidgets);
    },
  );

  testWidgets(
    'AlmanacScreen provides quick tool bar, expandable highlights, P1 blocks, term dictionary sheet, and enriched shichen dialog',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrapWithProviders(AlmanacScreen(initialDate: DateTime(2026, 6, 3))),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('almanac_quick_tools_bar')), findsOneWidget);
      expect(find.byKey(const ValueKey('almanac_quick_tool_chip_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('almanac_quick_tool_chip_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('almanac_quick_tool_chip_2')), findsOneWidget);
      expect(find.byKey(const ValueKey('almanac_quick_tool_chip_3')), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('selected_date_almanac_summary_card')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('almanac_yiji_dictionary_card')), findsOneWidget);
      expect(find.byKey(const ValueKey('almanac_deities_directions_card')), findsOneWidget);
      expect(find.byKey(const ValueKey('almanac_phenology_season_card')), findsOneWidget);
      expect(find.text('财神'), findsOneWidget);
      expect(find.text('喜神'), findsOneWidget);
      expect(find.text('福神'), findsOneWidget);

      // Tap a Yi/Ji term chip to open plain-language dictionary sheet.
      await tester.ensureVisible(find.text('祭祀').last);
      await tester.tap(find.text('祭祀').last);
      await tester.pumpAndSettle();
      expect(find.text('白话释义'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('term_sheet_find_auspicious_btn')),
        findsOneWidget,
      );

      // Close sheet & test enriched shichen dialog.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('子'));
      await tester.tap(find.text('子'));
      await tester.pumpAndSettle();
      expect(find.text('冲煞'), findsWidgets);
      expect(find.text('财喜福方位'), findsOneWidget);
      expect(find.text('时辰宜'), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'AlmanacToolsScreen supports all 4 tabs: auspicious finder, holidays, interval/offset/leap-month converter, solar terms & BaZi',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrapWithProviders(
          AlmanacToolsScreen(initialDate: DateTime(2026, 6, 3)),
        ),
      );
      await tester.pumpAndSettle();

      // Tab 0: 择吉日查询
      expect(find.byKey(const ValueKey('auspicious_activity_input')), findsOneWidget);
      expect(find.byKey(const ValueKey('auspicious_matches_summary')), findsOneWidget);

      // Tab 1: 放假安排与倒计时
      await tester.tap(find.byKey(const ValueKey('almanac_tools_tab_1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('holiday_next_countdown_hero')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('holiday_year_chip_2027')));
      await tester.pumpAndSettle();

      // Tab 2: 日期工具 & 闰月互转
      await tester.tap(find.byKey(const ValueKey('almanac_tools_tab_2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('date_interval_card')), findsOneWidget);
      expect(find.byKey(const ValueKey('date_offset_card')), findsOneWidget);
      expect(find.byKey(const ValueKey('solar_lunar_converter_card')), findsOneWidget);

      // Switch converter to Lunar -> Solar and check 2025 闰六月 active toggle.
      await tester.ensureVisible(find.text('农历转公历'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('农历转公历'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('converter_lunar_year')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('converter_lunar_year')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('乙巳年（2025）').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('乙巳年（2025）').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('converter_leap_month_switch')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('converter_leap_month_switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('converter_leap_month_switch')));
      await tester.pumpAndSettle();
      // initialDate 2026-06-03 seeds lunar day 18; 2025 闰六月十八 is 2025-08-11.
      expect(find.textContaining('2025-08-11'), findsWidgets);
      expect(find.textContaining('闰六月十八'), findsWidgets);

      // Tab 3: 节气与八字
      await tester.ensureVisible(find.byKey(const ValueKey('almanac_tools_tab_3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('almanac_tools_tab_3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bazi_calculator_card')), findsOneWidget);
      expect(find.byKey(const ValueKey('solar_terms_24_card')), findsOneWidget);
      expect(find.text('立春'), findsWidgets);
    },
  );

  testWidgets(
    'AppDatePicker allows actively selecting leap month in 2025 and preserves zero CJK in English',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      Future<void> pumpPicker() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () {
                      AppDatePicker.show(
                        context,
                        initialDate: DateTime(2025, 7, 1),
                        initialMode: AppDatePickerMode.lunar,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030, 12, 31),
                      );
                    },
                    child: const Text('Open Picker'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();
      }

      // Chinese leap month selection
      await pumpPicker();
      final leapChipFinder = find.byKey(
        const ValueKey('app_date_picker_leap_month_chip'),
      );
      expect(leapChipFinder, findsOneWidget);
      await tester.tap(leapChipFinder);
      await tester.pumpAndSettle();
      expect(find.textContaining('闰六月'), findsWidgets);

      // English mode: zero CJK inside leap month chip
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      final enChip = tester.widget<FilterChip>(leapChipFinder);
      final enText = (enChip.label as Text).data ?? '';
      expect(RegExp(r'[\u4E00-\u9FFF]').hasMatch(enText), isFalse);
      expect(enText, contains('Leap Month 6'));
    },
  );
}
