import 'package:test/test.dart';

import 'package:duoyi/models/habit.dart';

void main() {
  test(
    'Habit.fromJson tolerates legacy sparse data and safe heatmap target',
    () {
      final habit = Habit.fromJson(<String, dynamic>{
        'id': 'legacy-habit',
        'name': 'Legacy',
        'kind': 99,
        'targetCount': 0,
        'completions': {'2026-05-12': 2.0},
      });

      expect(habit.id, 'legacy-habit');
      expect(habit.kind, HabitKind.negative);
      expect(habit.targetCount, 1);
      expect(habit.createdAt, isA<DateTime>());
      expect(() => habit.heatmapData(1), returnsNormally);
    },
  );

  test('negative habit treats zero occurrences as complete progress', () {
    final habit = Habit(
      id: 'negative-habit',
      name: '少刷短视频',
      kind: HabitKind.negative,
      targetCount: 1,
    );

    expect(habit.todayCount(), 0);
    expect(habit.todayProgress(), 1.0);
    expect(habit.isCompletedToday(), isTrue);

    habit.completions[habit.todayKey()] = 1;

    expect(habit.todayProgress(), 0.0);
    expect(habit.isCompletedToday(), isFalse);
  });

  test('legacy data keeps flex rule empty until explicitly configured', () {
    final habit = Habit.fromJson(<String, dynamic>{
      'id': 'legacy-daily',
      'name': '每日阅读',
      'targetCount': 2,
      'completions': {'2026-05-12': 2},
    });

    expect(habit.flexTarget, isNull);
    expect(habit.flexPeriod, isNull);
    expect(habit.hasFlexRule, isFalse);
    expect(habit.isCompletedForDate(DateTime(2026, 5, 12)), isTrue);
    expect(habit.isCompletedForDate(DateTime(2026, 5, 13)), isFalse);
  });

  test(
    'weekly flex target completes one period instead of seven daily goals',
    () {
      final keyHelper = Habit(id: 'key-helper', name: 'helper');
      final habit = Habit(
        id: 'run',
        name: '跑步',
        flexTarget: 5,
        flexPeriod: HabitFlexPeriod.week,
        completions: {
          for (var day = 11; day <= 15; day++)
            keyHelper.dateKey(DateTime(2026, 5, day)): 1,
        },
      );

      final friday = DateTime(2026, 5, 15);
      final progress = habit.flexProgressForDate(friday);

      expect(habit.hasFlexRule, isTrue);
      expect(progress?.label, '本周 5/5');
      expect(progress?.isCompleted, isTrue);
      expect(habit.isCompletedForDate(DateTime(2026, 5, 11)), isTrue);
      expect(habit.streakUnitLabel, '周');
      expect(habit.flexPeriodGoalLabel, '每周至少 5 次');
      expect(habit.completionDatesInRange(DateTime(2026, 5, 11), friday), [
        DateTime(2026, 5, 15, 12),
      ]);
      expect(
        habit.completionDatesInRange(
          DateTime(2026, 5, 11),
          DateTime(2026, 5, 14),
        ),
        isEmpty,
      );
    },
  );

  test('monthly flex target round trips through JSON', () {
    final habit = Habit(
      id: 'swim',
      name: '游泳',
      flexTarget: 2,
      flexPeriod: HabitFlexPeriod.month,
      completions: {'2026-05-04': 1, '2026-05-18': 1},
    );
    final restored = Habit.fromJson(habit.toJson());

    expect(restored.flexTarget, 2);
    expect(restored.flexPeriod, HabitFlexPeriod.month);
    expect(
      restored.flexProgressForDate(DateTime(2026, 5, 20))?.label,
      '本月 2/2',
    );
    expect(restored.streakUnitLabel, '月');
  });

  test('date range round trips and gates active progress', () {
    final habit = Habit(
      id: 'range',
      name: '阶段阅读',
      targetCount: 2,
      startDate: DateTime(2026, 5, 10, 8),
      endDate: DateTime(2026, 5, 12, 23, 59),
      completions: {
        '2026-05-09': 2,
        '2026-05-10': 2,
        '2026-05-12': 2,
        '2026-05-13': 2,
      },
    );
    final restored = Habit.fromJson(habit.toJson());

    expect(restored.startDate, DateTime(2026, 5, 10, 8));
    expect(restored.endDate, DateTime(2026, 5, 12, 23, 59));
    expect(restored.activeForDate(DateTime(2026, 5, 9)), isFalse);
    expect(restored.activeForDate(DateTime(2026, 5, 10)), isTrue);
    expect(restored.activeForDate(DateTime(2026, 5, 12)), isTrue);
    expect(restored.activeForDate(DateTime(2026, 5, 13)), isFalse);
    expect(restored.progressForDate(DateTime(2026, 5, 9)), 0);
    expect(restored.isCompletedForDate(DateTime(2026, 5, 13)), isFalse);
    expect(
      restored.completionDatesInRange(
        DateTime(2026, 5, 8),
        DateTime(2026, 5, 14),
      ),
      [DateTime(2026, 5, 10, 12), DateTime(2026, 5, 12, 12)],
    );
  });

  test('copyWith can clear date range fields', () {
    final habit = Habit(
      id: 'range-clear',
      name: '阶段运动',
      startDate: DateTime(2026, 5, 10),
      endDate: DateTime(2026, 5, 20),
    );

    final cleared = habit.copyWith(clearStartDate: true, clearEndDate: true);

    expect(cleared.startDate, isNull);
    expect(cleared.endDate, isNull);
    expect(cleared.activeForDate(DateTime(2026, 5, 1)), isTrue);
  });
}
