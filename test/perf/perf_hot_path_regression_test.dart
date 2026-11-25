import 'dart:convert';

import 'package:duoyi/core/diary_insights.dart';
import 'package:duoyi/core/habit_insights.dart';
import 'package:duoyi/core/habit_trend.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/image_decode_cache.dart';
import 'package:duoyi/core/lunar_calendar.dart';
import 'package:duoyi/core/report_engine.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/models/recurrence.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/screens/time_audit_screen.dart';
import 'package:duoyi/services/holiday_calendar.dart';
import 'package:duoyi/widgets/pomodoro_timer_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ImageDecodeCache.clear();
    HolidayCalendar.resetOverrides();
    PomodoroTimerRing.clearCachesForTest();
  });

  tearDown(() {
    ImageDecodeCache.clear();
    HolidayCalendar.resetOverrides();
    PomodoroTimerRing.clearCachesForTest();
    I18n.setLocale(AppLocale.zh);
  });

  group('LunarCalendar LRU caches', () {
    test('caches almanacDetail, solarTerm, solarFestival, and lunarFestival', () {
      final d = DateTime(2026, 2, 17); // Spring Festival 2026
      final detailA = LunarCalendar.almanacDetail(d);
      final detailB = LunarCalendar.almanacDetail(d);
      expect(identical(detailA, detailB), isTrue);

      final tryA = LunarCalendar.tryAlmanacDetail(d);
      final tryB = LunarCalendar.tryAlmanacDetail(d);
      expect(identical(tryA, tryB), isTrue);
      expect(tryA?.dayGanzhi, detailA.dayGanzhi);

      final solarFesDate = DateTime(2026, 5, 1);
      expect(LunarCalendar.solarFestival(solarFesDate), '劳动节');
      expect(LunarCalendar.solarFestival(solarFesDate), '劳动节');

      final termDate = DateTime(2026, 2, 4);
      final termA = LunarCalendar.solarTerm(termDate);
      final termB = LunarCalendar.solarTerm(termDate);
      expect(termA, termB);

      final lunar = LunarCalendar.fromSolar(d);
      final lunarFesA = LunarCalendar.lunarFestival(lunar);
      final lunarFesB = LunarCalendar.lunarFestival(lunar);
      expect(lunarFesA, '春节');
      expect(lunarFesB, '春节');

      // Exercise > 128 days to confirm bounded LRU eviction stays valid.
      for (var i = 0; i < 150; i++) {
        final probe = DateTime(2026, 1, 1).add(Duration(days: i));
        final probeDetail = LunarCalendar.almanacDetail(probe);
        expect(probeDetail.solarDate.year, probe.year);
      }
      final recomputed = LunarCalendar.almanacDetail(d);
      expect(recomputed.dayGanzhi, detailA.dayGanzhi);
    });
  });

  group('HolidayCalendar caching & updateFrom invalidation', () {
    test('updateFrom clears all 7 cached holiday lookups and bumps version', () {
      final probeHoliday = DateTime(2026, 7, 15);
      final probeMakeup = DateTime(2026, 7, 18);
      expect(HolidayCalendar.isHoliday(probeHoliday), isFalse);
      expect(HolidayCalendar.isWorkMakeupDay(probeMakeup), isFalse);
      expect(HolidayCalendar.holidayName(probeHoliday), isNull);
      expect(HolidayCalendar.scheduleItemFor(probeHoliday), isNull);
      final initialSchedules = HolidayCalendar.schedulesForYear(2026);
      expect(identical(HolidayCalendar.schedulesForYear(2026), initialSchedules), isTrue);
      final initialUpcoming = HolidayCalendar.upcomingHolidays(
        DateTime(2026, 7, 1),
        limit: 3,
      );
      expect(
        identical(
          HolidayCalendar.upcomingHolidays(DateTime(2026, 7, 1), limit: 3),
          initialUpcoming,
        ),
        isTrue,
      );
      final initialNext = HolidayCalendar.nextHoliday(DateTime(2026, 7, 1));
      final versionBefore = HolidayCalendar.cacheVersion;

      HolidayCalendar.updateFrom(
        2026,
        const HolidayYear(
          holidays: <String>{'07-15'},
          workMakeupDays: <String>{'07-18'},
        ),
      );

      expect(HolidayCalendar.cacheVersion, greaterThan(versionBefore));
      expect(HolidayCalendar.isHoliday(probeHoliday), isTrue);
      expect(HolidayCalendar.isWorkMakeupDay(probeMakeup), isTrue);
      expect(HolidayCalendar.holidayName(probeHoliday), isNotNull);
      expect(HolidayCalendar.scheduleItemFor(probeHoliday), isNotNull);
      final updatedSchedules = HolidayCalendar.schedulesForYear(2026);
      expect(updatedSchedules, isNotEmpty);
      expect(identical(updatedSchedules, initialSchedules), isFalse);
      final updatedNext = HolidayCalendar.nextHoliday(DateTime(2026, 7, 1));
      expect(updatedNext?.startDate, DateTime(2026, 7, 15));
      expect(initialNext?.startDate == updatedNext?.startDate, isFalse);
      final updatedUpcoming = HolidayCalendar.upcomingHolidays(
        DateTime(2026, 7, 1),
        limit: 3,
      );
      expect(updatedUpcoming.first.startDate, DateTime(2026, 7, 15));

      HolidayCalendar.resetOverrides();
      expect(HolidayCalendar.isHoliday(probeHoliday), isFalse);
      expect(HolidayCalendar.isWorkMakeupDay(probeMakeup), isFalse);
    });
  });

  group('ImageDecodeCache LRU reuse and eviction', () {
    test('reuses decoded bytes, rejects invalid input, and enforces LRU bounds', () {
      final pngBase64 = base64Encode(List<int>.generate(64, (i) => i & 0xff));
      final uri = 'data:image/png;base64,$pngBase64';

      final first = ImageDecodeCache.decodeBase64Image(uri);
      final second = ImageDecodeCache.decodeBase64Image(uri);
      expect(first, isNotNull);
      expect(identical(first, second), isTrue);
      expect(ImageDecodeCache.entryCount, 1);
      expect(ImageDecodeCache.totalBytes, 64);

      expect(ImageDecodeCache.decodeBase64Image(''), isNull);
      expect(ImageDecodeCache.decodeBase64Image('%%%invalid%%%'), isNull);
      expect(ImageDecodeCache.decodeBase64Image('data:text/plain,abc'), isNull);
      expect(ImageDecodeCache.entryCount, 1);

      ImageDecodeCache.clear();
      final payloads = List<String>.generate(
        ImageDecodeCache.maxEntries + 2,
        (i) => 'data:image/png;base64,${base64Encode(<int>[i + 1, 2, 3, 4])}',
      );
      for (final item in payloads) {
        expect(ImageDecodeCache.decodeBase64Image(item), isNotNull);
      }
      expect(ImageDecodeCache.entryCount, ImageDecodeCache.maxEntries);
      expect(
        ImageDecodeCache.totalBytes,
        lessThanOrEqualTo(ImageDecodeCache.maxTotalBytes),
      );

      ImageDecodeCache.clear();
      final fiveMb = base64Encode(List<int>.filled(5 * 1024 * 1024, 7));
      final fiveMbOther = base64Encode(List<int>.filled(5 * 1024 * 1024, 9));
      expect(
        ImageDecodeCache.decodeBase64Image('data:image/png;base64,$fiveMb'),
        isNotNull,
      );
      expect(ImageDecodeCache.entryCount, 1);
      expect(
        ImageDecodeCache.decodeBase64Image(
          'data:image/png;base64,$fiveMbOther',
        ),
        isNotNull,
      );
      expect(ImageDecodeCache.entryCount, 1);
      expect(
        ImageDecodeCache.totalBytes,
        lessThanOrEqualTo(ImageDecodeCache.maxTotalBytes),
      );

      final pixelCap = ImageDecodeCache.boundedCachePixels(48, 3.0);
      expect(pixelCap, 144);
    });
  });

  group('Insight and Report engine cache consistency', () {
    test('DiaryInsightEngine, HabitInsightEngine, and ReportEngine cache and invalidate', () {
      final today = DateTime(2026, 6, 10);
      final entries = <DiaryEntry>[
        DiaryEntry(
          id: 'd1',
          date: today,
          content: 'Focused deep work session\nCompleted design review',
          mood: Mood.good,
          tags: const ['work'],
          updatedAt: today,
        ),
      ];
      final dA = DiaryInsightEngine.buildInsights(
        entries,
        today: today,
        locale: AppLocale.zh,
      );
      final dB = DiaryInsightEngine.buildInsights(
        entries,
        today: today,
        locale: AppLocale.zh,
      );
      expect(identical(dA, dB), isTrue);

      final dEn = DiaryInsightEngine.buildInsights(
        entries,
        today: today,
        locale: AppLocale.en,
      );
      expect(identical(dA, dEn), isFalse);

      entries.add(
        DiaryEntry(
          id: 'd2',
          date: today.subtract(const Duration(days: 1)),
          content: 'Another great evening walk',
          mood: Mood.awesome,
          tags: const ['health'],
          updatedAt: today.add(const Duration(minutes: 1)),
        ),
      );
      final dUpdated = DiaryInsightEngine.buildInsights(
        entries,
        today: today,
        locale: AppLocale.zh,
      );
      expect(identical(dA, dUpdated), isFalse);

      final habits = <Habit>[
        Habit(
          id: 'h1',
          name: 'Morning Run',
          completions: {'2026-06-10': 1},
          updatedAt: today,
        ),
      ];
      final hA = HabitInsightEngine.buildInsights(
        habits,
        today: today,
        window: HabitTrendWindow.days30,
      );
      final hB = HabitInsightEngine.buildInsights(
        habits,
        today: today,
        window: HabitTrendWindow.days30,
      );
      expect(identical(hA, hB), isTrue);
      habits.first.completions['2026-06-09'] = 1;
      habits.first.updatedAt = today.add(const Duration(minutes: 2));
      final hUpdated = HabitInsightEngine.buildInsights(
        habits,
        today: today,
        window: HabitTrendWindow.days30,
      );
      expect(identical(hA, hUpdated), isFalse);

      final start = DateTime(2026, 6, 8);
      final todos = <TodoItem>[
        TodoItem(
          id: 't1',
          title: 'Write docs',
          isCompleted: true,
          completedAt: today,
          updatedAt: today,
          createdAt: start,
        ),
      ];
      final sessions = <PomodoroSession>[
        PomodoroSession(
          id: 'p1',
          startTime: today.add(const Duration(hours: 9)),
          endTime: today.add(const Duration(hours: 9, minutes: 25)),
          durationSeconds: 1500,
          type: PomodoroType.focus,
        ),
      ];
      final timeEntries = <TimeEntry>[
        TimeEntry(
          id: 'te1',
          title: 'Coding',
          startAt: today.add(const Duration(hours: 10)),
          endAt: today.add(const Duration(hours: 10, minutes: 30)),
          updatedAt: today,
        ),
      ];

      final rA = ReportEngine.buildReport(
        start: start,
        end: today,
        todos: todos,
        habits: habits,
        sessions: sessions,
        timeEntries: timeEntries,
      );
      final rB = ReportEngine.buildReport(
        start: start,
        end: today,
        todos: todos,
        habits: habits,
        sessions: sessions,
        timeEntries: timeEntries,
      );
      expect(identical(rA, rB), isTrue);

      todos.add(
        TodoItem(
          id: 't2',
          title: 'Ship perf fix',
          isCompleted: true,
          completedAt: today,
          updatedAt: today.add(const Duration(seconds: 1)),
          createdAt: today,
        ),
      );
      final rUpdated = ReportEngine.buildReport(
        start: start,
        end: today,
        todos: todos,
        habits: habits,
        sessions: sessions,
        timeEntries: timeEntries,
      );
      expect(identical(rA, rUpdated), isFalse);
      expect(rUpdated.todosCompleted, 2);
    });
  });

  group('GoalProvider direct clone isolation', () {
    test('mutating source goal, milestones, or recurrence lists does not leak', () async {
      final provider = GoalProvider();
      addTearDown(provider.dispose);

      final milestone = GoalMilestone(id: 'm1', title: 'Draft outline');
      final weekdays = <int>[1, 3];
      final goal = GoalItem(
        id: 'g1',
        title: 'Finish Q3 Launch',
        milestones: [milestone],
        recurrence: RecurrenceRule(
          frequency: RecurrenceFrequency.weekly,
          byWeekdays: weekdays,
        ),
      );

      await provider.add(goal);

      goal.title = 'Mutated Outside';
      milestone.title = 'Mutated Milestone';
      weekdays.add(5);

      final stored = provider.goals.single;
      expect(stored.title, 'Finish Q3 Launch');
      expect(stored.milestones.single.title, 'Draft outline');
      expect(stored.recurrence.byWeekdays, <int>[1, 3]);
    });

    test('HabitProvider caches read-only getters and invalidates on check-in', () async {
      final habits = HabitProvider();
      addTearDown(habits.dispose);
      await habits.addHabit(
        Habit(id: 'hab1', name: 'Read', targetCount: 2, tags: ['study']),
      );
      final activeA = habits.activeHabits;
      final activeB = habits.activeHabits;
      expect(identical(activeA, activeB), isTrue);
      expect(identical(habits.allTags, habits.allTags), isTrue);
      expect(
        identical(habits.currentWeekProgress(), habits.currentWeekProgress()),
        isTrue,
      );

      await habits.incrementHabit('hab1');
      final activeAfter = habits.activeHabits;
      expect(identical(activeA, activeAfter), isFalse);
      expect(activeAfter.single.todayCount(), 1);
    });
  });

  group('Hot-path tick isolation', () {
    testWidgets('PomodoroTimerRing verticalShift cache hits on 1s ticks', (
      tester,
    ) async {
      PomodoroTimerRing.clearCachesForTest();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PomodoroTimerRing(
              progress: 0.99,
              timeText: '24:59',
              color: Colors.red,
              size: 200,
            ),
          ),
        ),
      );
      expect(PomodoroTimerRing.verticalShiftCacheLengthForTest, 1);

      for (final tick in const ['24:58', '24:57', '24:56']) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PomodoroTimerRing(
                progress: 0.98,
                timeText: tick,
                color: Colors.red,
                size: 200,
              ),
            ),
          ),
        );
      }
      expect(PomodoroTimerRing.verticalShiftCacheLengthForTest, 1);
    });

    testWidgets('TimeAuditScreen stopwatch updates clock via ValueNotifier without rebuilding tracker card', (
      tester,
    ) async {
      final provider = TimeAuditProvider();
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<TimeAuditProvider>.value(
          value: provider,
          child: const MaterialApp(home: TimeAuditScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final startBtn = find.byKey(
        const ValueKey('time_audit_stopwatch_start_btn'),
      );
      await tester.tap(startBtn);
      await tester.pump();

      final cardFinder = find.byKey(
        const ValueKey('time_audit_stopwatch_card'),
      );
      final cardBeforeTicks = tester.widget(cardFinder);
      expect(find.text('00:00:00'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:00:01'), findsOneWidget);
      expect(identical(tester.widget(cardFinder), cardBeforeTicks), isTrue);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:00:02'), findsOneWidget);
      expect(identical(tester.widget(cardFinder), cardBeforeTicks), isTrue);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:00:03'), findsOneWidget);
      expect(identical(tester.widget(cardFinder), cardBeforeTicks), isTrue);

      // Pause cleanly before widget teardown cancels active periodic timers.
      await tester.tap(
        find.byKey(const ValueKey('time_audit_stopwatch_pause_btn')),
      );
      await tester.pump();
    });
  });
}
