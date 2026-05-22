import 'package:test/test.dart';

import 'package:duoyi/core/habit_grouping.dart';
import 'package:duoyi/models/habit.dart';

void main() {
  group('habit category grouping', () {
    test('normalizes empty category into default group', () {
      expect(normalizeHabitCategory(null), defaultHabitCategoryName);
      expect(normalizeHabitCategory('   '), defaultHabitCategoryName);
      expect(habitCategoryOrNull('  学习提升  '), '学习提升');
      expect(habitCategoryOrNull(''), isNull);
    });

    test(
      'groups habits by category while preserving first-seen group order',
      () {
        final helper = Habit(id: 'helper', name: 'helper');
        final today = helper.todayKey();
        final habits = [
          Habit(id: 'water', name: '喝水', category: '身体健康'),
          Habit(
            id: 'read',
            name: '阅读',
            category: '学习提升',
            targetCount: 2,
            completions: {today: 2},
          ),
          Habit(id: 'sleep', name: '早睡', category: '身体健康'),
          Habit(id: 'plain', name: '无分类'),
        ];

        final groups = groupHabitsByCategory(habits);

        expect(groups.map((group) => group.category), [
          '身体健康',
          '学习提升',
          defaultHabitCategoryName,
        ]);
        expect(groups[0].habits.map((habit) => habit.id), ['water', 'sleep']);
        expect(groups[1].completedTodayCount, 1);
        expect(groups[2].habits.single.id, 'plain');
      },
    );

    test('habit copyWith can clear category for regrouping', () {
      final habit = Habit(id: 'water', name: '喝水', category: '身体健康');

      expect(habit.copyWith(category: '学习提升').category, '学习提升');
      expect(habit.copyWith(clearCategory: true).category, isNull);
    });
  });
}
