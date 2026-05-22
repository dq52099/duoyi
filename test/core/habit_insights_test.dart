import 'package:test/test.dart';

import 'package:duoyi/core/habit_insights.dart';
import 'package:duoyi/models/habit.dart';

void main() {
  test(
    'buildInsights summarizes overview, rising, slipping and streak habits',
    () {
      final today = DateTime(2026, 5, 20);
      final currentStart = today.subtract(const Duration(days: 29));
      final previousStart = currentStart.subtract(const Duration(days: 30));

      final improving = Habit(
        id: 'read',
        name: '阅读',
        completions: _completions(
          currentStart: currentStart,
          previousStart: previousStart,
          currentCompletedDays: 18,
          previousCompletedDays: 4,
        ),
      );
      final slipping = Habit(
        id: 'run',
        name: '跑步',
        completions: _completions(
          currentStart: currentStart,
          previousStart: previousStart,
          currentCompletedDays: 5,
          previousCompletedDays: 18,
        ),
      );
      final stable = Habit(
        id: 'water',
        name: '喝水',
        completions: _completions(
          currentStart: currentStart,
          previousStart: previousStart,
          currentCompletedDays: 12,
          previousCompletedDays: 12,
        ),
      );

      final insights = HabitInsightEngine.buildInsights(
        [improving, slipping, stable],
        today: today,
        limit: 5,
      );

      expect(insights.first.kind, HabitInsightKind.overview);
      expect(insights.first.message, contains('30天平均达标率'));
      expect(
        insights.any(
          (insight) =>
              insight.kind == HabitInsightKind.rising &&
              insight.habitId == 'read',
        ),
        isTrue,
      );
      expect(
        insights.any(
          (insight) =>
              insight.kind == HabitInsightKind.slipping &&
              insight.habitId == 'run',
        ),
        isTrue,
      );
      expect(
        insights.any((insight) => insight.kind == HabitInsightKind.streak),
        isTrue,
      );
    },
  );

  test('buildInsights returns empty list when there are no active habits', () {
    final inactive = Habit(
      id: 'inactive',
      name: '暂停',
      activeWeekdays: const [],
    );

    expect(HabitInsightEngine.buildInsights([inactive]), isEmpty);
  });
}

Map<String, int> _completions({
  required DateTime currentStart,
  required DateTime previousStart,
  required int currentCompletedDays,
  required int previousCompletedDays,
}) {
  final map = <String, int>{};
  for (var i = 0; i < currentCompletedDays; i++) {
    final date = currentStart.add(Duration(days: i));
    map[_dateKey(date)] = 1;
  }
  for (var i = 0; i < previousCompletedDays; i++) {
    final date = previousStart.add(Duration(days: i));
    map[_dateKey(date)] = 1;
  }
  return map;
}

String _dateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
