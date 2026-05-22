import 'package:test/test.dart';

import 'package:duoyi/core/habit_trend.dart';
import 'package:duoyi/models/habit.dart';

void main() {
  group('HabitTrendSummary', () {
    test('summarizes completion rate, average count, streak, and delta', () {
      final today = DateTime(2026, 5, 19);
      final currentStart = today.subtract(const Duration(days: 29));
      final previousStart = currentStart.subtract(const Duration(days: 30));
      final completions = <String, int>{};
      final keyHelper = Habit(id: 'key-helper', name: 'helper');

      for (var i = 0; i < 10; i++) {
        completions[keyHelper.dateKey(currentStart.add(Duration(days: i)))] = 2;
      }
      for (var i = 10; i < 15; i++) {
        completions[keyHelper.dateKey(currentStart.add(Duration(days: i)))] = 1;
      }
      for (var i = 0; i < 3; i++) {
        completions[keyHelper.dateKey(previousStart.add(Duration(days: i)))] =
            2;
      }

      final habit = Habit(
        id: 'read',
        name: '阅读',
        targetCount: 2,
        completions: completions,
      );

      final summary = buildHabitTrendSummary(
        habit,
        window: HabitTrendWindow.days30,
        today: today,
      );

      expect(summary.points, hasLength(30));
      expect(summary.buckets, hasLength(30));
      expect(summary.activeDays, 30);
      expect(summary.completedDays, 10);
      expect(summary.totalCount, 25);
      expect(summary.averageCount, closeTo(25 / 30, 0.0001));
      expect(summary.completionRate, closeTo(10 / 30, 0.0001));
      expect(summary.previousCompletionRate, closeTo(3 / 30, 0.0001));
      expect(summary.direction, HabitTrendDirection.up);
      expect(summary.longestCompletedStreak, 10);
    });

    test('uses weekly buckets for 90-day view', () {
      final summary = buildHabitTrendSummary(
        Habit(id: 'run', name: '跑步'),
        window: HabitTrendWindow.days90,
        today: DateTime(2026, 5, 19),
      );

      expect(summary.points, hasLength(90));
      expect(summary.buckets, hasLength(13));
      expect(summary.buckets.first.label, contains('/'));
      expect(summary.buckets.first.activeDays, 7);
      expect(summary.buckets.last.activeDays, 6);
    });

    test('uses month buckets for yearly view', () {
      final summary = buildHabitTrendSummary(
        Habit(id: 'water', name: '喝水'),
        window: HabitTrendWindow.days365,
        today: DateTime(2026, 5, 19),
      );

      expect(summary.points, hasLength(365));
      expect(summary.buckets.length, greaterThanOrEqualTo(12));
      expect(summary.buckets.first.label, '2025/5');
      expect(summary.buckets.last.label, '2026/5');
    });

    test('respects habit start and end dates when computing active days', () {
      final habit = Habit(
        id: 'range',
        name: '阶段阅读',
        targetCount: 1,
        startDate: DateTime(2026, 5, 10),
        endDate: DateTime(2026, 5, 12),
        completions: {
          '2026-05-09': 1,
          '2026-05-10': 1,
          '2026-05-12': 1,
          '2026-05-13': 1,
        },
      );

      final summary = buildHabitTrendSummary(
        habit,
        window: HabitTrendWindow.days14,
        today: DateTime(2026, 5, 14),
      );

      expect(summary.activeDays, 3);
      expect(summary.completedDays, 2);
      expect(summary.totalCount, 2);
      expect(
        summary.points
            .where((point) => point.active)
            .map((point) => point.date),
        [DateTime(2026, 5, 10), DateTime(2026, 5, 11), DateTime(2026, 5, 12)],
      );
    });
  });
}
