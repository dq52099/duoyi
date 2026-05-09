import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/goal_validation.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/recurrence.dart';

/// 纯函数校验器单测（Task 2.3）。
///
/// 覆盖场景（对应 requirements.md §1 的 1.6 / 1.7 / 1.8 / 1.10）：
/// - 默认 GoalItem 合法
/// - fixedWeekdays 越界、重复
/// - fixedMonthDays 越界
/// - random.minGapDays < 1
/// - dailyTargetCount < 0
/// - reminder.enabled 但 hour 越界
/// - timeTargetSeconds < 0
void main() {
  group('validateGoal - happy path', () {
    test('默认 GoalItem 应通过校验', () {
      final goal = GoalItem(title: '示例目标');

      expect(isGoalValid(goal), isTrue);
      expect(validateGoal(goal), isEmpty);
    });

    test('合法的 fixed/weekly 配置应通过', () {
      final goal = GoalItem(
        title: '周一三五练腹',
        recurrence: const RecurrenceRule(
          frequency: RecurrenceFrequency.weekly,
        ),
        scheduling: const GoalScheduling.fixed(
          fixedWeekdays: [0, 2, 4],
        ),
      );

      expect(isGoalValid(goal), isTrue);
    });

    test('合法的 random 配置应通过', () {
      final goal = GoalItem(
        title: '随机派发',
        scheduling: const GoalScheduling.random(
          minGapDays: 2,
          maxPerWeek: 3,
          maxPerMonth: 10,
        ),
      );

      expect(isGoalValid(goal), isTrue);
    });

    test('dailyTargetCount == 0 应视为允许（清零）', () {
      final goal = GoalItem(title: 't', dailyTargetCount: 0);
      expect(isGoalValid(goal), isTrue);
    });
  });

  group('validateGoal - invalid inputs', () {
    test('fixedWeekdays = [0, 2, 9] 应报错（超出 0..6）', () {
      final goal = GoalItem(
        title: 't',
        recurrence: const RecurrenceRule(
          frequency: RecurrenceFrequency.weekly,
        ),
        scheduling: const GoalScheduling.fixed(
          fixedWeekdays: [0, 2, 9],
        ),
      );

      expect(isGoalValid(goal), isFalse);
      expect(
        validateGoal(goal).where(
          (i) => i.field == GoalValidationField.fixedWeekdays,
        ),
        isNotEmpty,
      );
    });

    test('fixedWeekdays = [1, 1, 2] 应报错（重复）', () {
      final goal = GoalItem(
        title: 't',
        recurrence: const RecurrenceRule(
          frequency: RecurrenceFrequency.weekly,
        ),
        scheduling: const GoalScheduling.fixed(
          fixedWeekdays: [1, 1, 2],
        ),
      );

      expect(isGoalValid(goal), isFalse);
      expect(
        validateGoal(goal).where(
          (i) => i.field == GoalValidationField.fixedWeekdays,
        ),
        isNotEmpty,
      );
    });

    test('fixedMonthDays = [1, 32] 应报错（超出 1..31）', () {
      final goal = GoalItem(
        title: 't',
        recurrence: const RecurrenceRule(
          frequency: RecurrenceFrequency.monthly,
        ),
        scheduling: const GoalScheduling.fixed(
          fixedMonthDays: [1, 32],
        ),
      );

      expect(isGoalValid(goal), isFalse);
      expect(
        validateGoal(goal).where(
          (i) => i.field == GoalValidationField.fixedMonthDays,
        ),
        isNotEmpty,
      );
    });

    test('GoalScheduling.random(minGapDays: 0) 应报错', () {
      final goal = GoalItem(
        title: 't',
        scheduling: const GoalScheduling.random(minGapDays: 0),
      );

      expect(isGoalValid(goal), isFalse);
      expect(
        validateGoal(goal).where(
          (i) => i.field == GoalValidationField.randomMinGapDays,
        ),
        isNotEmpty,
      );
    });

    test('dailyTargetCount = -1 应报错', () {
      final goal = GoalItem(title: 't', dailyTargetCount: -1);

      expect(isGoalValid(goal), isFalse);
      expect(
        validateGoal(goal).where(
          (i) => i.field == GoalValidationField.dailyTargetCount,
        ),
        isNotEmpty,
      );
    });

    test('reminder.enabled = true 且 hour = 25 应报错', () {
      final goal = GoalItem(
        title: 't',
        reminder: const ReminderConfig(
          enabled: true,
          hour: 25,
          minute: 0,
        ),
      );

      expect(isGoalValid(goal), isFalse);
      expect(
        validateGoal(goal).where(
          (i) => i.field == GoalValidationField.hour,
        ),
        isNotEmpty,
      );
    });

    test('timeTargetSeconds = -10 应报错', () {
      final goal = GoalItem(title: 't', timeTargetSeconds: -10);

      expect(isGoalValid(goal), isFalse);
      expect(
        validateGoal(goal).where(
          (i) => i.field == GoalValidationField.timeTargetSeconds,
        ),
        isNotEmpty,
      );
    });
  });

  group('单字段 validator 函数', () {
    test('validateRandomMinGapDaysInt', () {
      expect(validateRandomMinGapDaysInt(null), isNull);
      expect(validateRandomMinGapDaysInt(1), isNull);
      expect(validateRandomMinGapDaysInt(7), isNull);
      expect(validateRandomMinGapDaysInt(0), isNotNull);
      expect(validateRandomMinGapDaysInt(-3), isNotNull);
    });

    test('validateDailyTargetCountInt', () {
      expect(validateDailyTargetCountInt(null), isNull);
      expect(validateDailyTargetCountInt(0), isNull);
      expect(validateDailyTargetCountInt(5), isNull);
      expect(validateDailyTargetCountInt(-1), isNotNull);
    });
  });
}
