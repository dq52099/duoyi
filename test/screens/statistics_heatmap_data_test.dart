import 'package:duoyi/core/heatmap_calendar.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/statistics_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/widgets/activity_heatmap_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('statistics retains weighted activity and local instant dates', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final todos = TodoProvider();
    final goals = GoalProvider();
    final habits = HabitProvider();
    final focus = PomodoroProvider();
    final time = TimeAuditProvider();
    final diary = DiaryProvider();
    final ai = AiService();
    final instant = DateTime.utc(2026, 5, 17, 1);
    final instantKey = HeatmapCalendarWindow.dateKey(instant.toLocal());
    todos.todos.addAll([
      TodoItem(
        id: 'done',
        title: 'Synthetic done task',
        isCompleted: true,
        completedAt: instant,
      ),
      TodoItem(
        id: 'unfinished',
        title: 'Synthetic unfinished task',
        completedAt: DateTime(2026, 5, 23),
      ),
    ]);
    focus.sessions.addAll([
      PomodoroSession(
        id: 'focus',
        startTime: instant.subtract(const Duration(minutes: 25)),
        endTime: instant,
        durationSeconds: 1500,
        type: PomodoroType.focus,
      ),
      PomodoroSession(
        id: 'break',
        startTime: DateTime(2026, 5, 23),
        endTime: DateTime(2026, 5, 23, 0, 5),
        durationSeconds: 300,
        type: PomodoroType.shortBreak,
      ),
    ]);
    habits.habits.add(
      Habit(
        id: 'habit',
        name: 'Synthetic habit',
        targetCount: 8,
        startDate: DateTime(2026, 5, 1),
        completions: {
          instantKey: 2,
          '2026-02-30': 5,
          '2026-2-09': 5,
          '2026-04-30': 5,
          '2026-05-22': -1,
        },
      ),
    );
    for (final sample in [(18, 30), (19, 60), (20, 0)]) {
      final start = DateTime.utc(2026, 5, sample.$1, 10);
      await time.add(
        TimeEntry(
          id: 'time-${sample.$1}',
          title: 'Synthetic time',
          startAt: start,
          endAt: start.add(Duration(minutes: sample.$2)),
        ),
      );
    }
    await diary.addOrUpdate(
      DiaryEntry(id: 'diary', date: DateTime(2026, 5, 21), mood: null),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TodoProvider>.value(value: todos),
          ChangeNotifierProvider<GoalProvider>.value(value: goals),
          ChangeNotifierProvider<HabitProvider>.value(value: habits),
          ChangeNotifierProvider<PomodoroProvider>.value(value: focus),
          ChangeNotifierProvider<TimeAuditProvider>.value(value: time),
          ChangeNotifierProvider<DiaryProvider>.value(value: diary),
          ChangeNotifierProvider<AiService>.value(value: ai),
        ],
        child: const MaterialApp(home: StatisticsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    // Inspect the actual screen's child data even before this lower card is
    // mounted by ListView. No duplicate implementation of the producer.
    final list = tester.widget<ListView>(find.byType(ListView).first);
    final children =
        (list.childrenDelegate as SliverChildListDelegate).children;
    final data = children.whereType<ActivityHeatmapCard>().single.heatmapData;
    expect(data, {
      instantKey: 5, // todo2 + focus2 + habit2, clipped to5.
      HeatmapCalendarWindow.dateKey(DateTime.utc(2026, 5, 18, 10).toLocal()): 1,
      HeatmapCalendarWindow.dateKey(DateTime.utc(2026, 5, 19, 10).toLocal()): 2,
      HeatmapCalendarWindow.dateKey(DateTime.utc(2026, 5, 20, 10).toLocal()): 1,
      '2026-05-21': 1, // A declared diary date with no mood is still activity.
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    for (final provider in [todos, goals, habits, focus, time, diary, ai]) {
      provider.dispose();
    }
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
