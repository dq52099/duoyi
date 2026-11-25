import 'package:duoyi/core/goal_validation.dart';
import 'package:duoyi/models/goal.dart';
import 'package:flutter_test/flutter_test.dart';

ReminderRule _rule(
  ReminderRuleType type, {
  bool enabled = true,
  ReminderKind kind = ReminderKind.push,
}) => ReminderRule(
  type: type,
  enabled: enabled,
  kind: kind,
  hour: 9,
  minute: 0,
  offsetMinutes: -30,
  weekdays: const [1, 3],
);

GoalItem _goal(
  List<ReminderRule> rules, {
  DateTime? targetDate,
  bool enabled = true,
}) => GoalItem(
  title: 'Literal goal / 自定义',
  targetDate: targetDate,
  reminderPlan: ReminderPlan(enabled: enabled, rules: rules),
);

void main() {
  test(
    'relative rule without target is rejected without mutating the goal',
    () {
      final goal = _goal([_rule(ReminderRuleType.relativeToDue)]);
      final original = goal.toJson();
      final issue = validateGoal(goal).single;
      expect(issue.field, GoalValidationField.targetDate);
      expect(issue.code, GoalValidationCode.reminderTargetDate);
      expect(
        issue.localizedMessage(isEnglish: true),
        'Set a target date for advance reminders.',
      );
      expect(issue.localizedMessage(isEnglish: false), '请先设置目标日期，再使用提前提醒。');
      expect(goal.toJson(), original);
    },
  );

  test(
    'a later relative rule is validated even when primary rule is daily',
    () {
      final goal = _goal([
        _rule(ReminderRuleType.dailyTime),
        _rule(ReminderRuleType.relativeToDue),
      ]);
      expect(
        validateGoal(goal).single.code,
        GoalValidationCode.reminderTargetDate,
      );
    },
  );

  test('relative rule becomes valid once a target date is supplied', () {
    final goal = _goal([
      _rule(ReminderRuleType.relativeToDue),
    ], targetDate: DateTime(2030, 6, 29));
    expect(validateGoal(goal), isEmpty);
  });

  test('disabled relative rule does not require a date', () {
    expect(
      validateGoal(
        _goal([_rule(ReminderRuleType.relativeToDue, enabled: false)]),
      ),
      isEmpty,
    );
  });

  test('off-channel relative rule does not require a date', () {
    expect(
      validateGoal(
        _goal([_rule(ReminderRuleType.relativeToDue, kind: ReminderKind.off)]),
      ),
      isEmpty,
    );
  });

  test('disabled plan without legacy fallback does not require a date', () {
    expect(
      validateGoal(
        _goal([_rule(ReminderRuleType.relativeToDue)], enabled: false),
      ),
      isEmpty,
    );
  });

  for (final type in [
    ReminderRuleType.absolute,
    ReminderRuleType.dailyTime,
    ReminderRuleType.weeklyTime,
  ]) {
    test('$type remains valid without a target date', () {
      expect(validateGoal(_goal([_rule(type)])), isEmpty);
    });
  }

  test('legacy advance reminders require the same target date', () {
    final goal = GoalItem(
      title: 'Legacy goal',
      reminder: const ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 9,
        minute: 0,
        daysBefore: 1,
      ),
    );
    expect(
      validateGoal(goal).single.code,
      GoalValidationCode.reminderTargetDate,
    );
  });
}
