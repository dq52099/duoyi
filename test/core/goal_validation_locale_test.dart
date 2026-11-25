import 'package:duoyi/core/goal_validation.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Every generated validation reason has stable bilingual copy', () {
    final cases = [
      GoalItem(
        title: 'Literal goal / 自定义',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              type: ReminderRuleType.relativeToDue,
              hour: 9,
              minute: 0,
            ),
          ],
        ),
      ),
      GoalItem(
        title: 'Literal goal / 自定义',
        recurrence: const RecurrenceRule(frequency: RecurrenceFrequency.weekly),
        scheduling: const GoalScheduling.fixed(fixedWeekdays: [7]),
      ),
      GoalItem(
        title: 'Literal goal / 自定义',
        recurrence: const RecurrenceRule(frequency: RecurrenceFrequency.weekly),
        scheduling: const GoalScheduling.fixed(fixedWeekdays: [1, 1]),
      ),
      GoalItem(
        title: 'Literal goal / 自定义',
        recurrence: const RecurrenceRule(
          frequency: RecurrenceFrequency.monthly,
        ),
        scheduling: const GoalScheduling.fixed(fixedMonthDays: [32]),
      ),
      GoalItem(
        title: 'Literal goal / 自定义',
        recurrence: const RecurrenceRule(
          frequency: RecurrenceFrequency.monthly,
        ),
        scheduling: const GoalScheduling.fixed(fixedMonthDays: [2, 2]),
      ),
      GoalItem(
        title: 'Literal goal / 自定义',
        scheduling: const GoalScheduling.random(
          minGapDays: 0,
          maxPerWeek: 0,
          maxPerMonth: 0,
        ),
      ),
      GoalItem(
        title: 'Literal goal / 自定义',
        dailyTargetCount: -1,
        timeTargetSeconds: -1,
        reminder: const ReminderConfig(enabled: true, hour: 24, minute: 60),
      ),
    ];
    final codes = <GoalValidationCode>{};
    for (final goal in cases) {
      final before = goal.toJson();
      for (final issue in validateGoal(goal)) {
        expect(issue.code, isNotNull);
        codes.add(issue.code!);
        final english = issue.localizedMessage(isEnglish: true);
        expect(english, isNotEmpty);
        expect(english, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
        expect(issue.localizedMessage(isEnglish: false), issue.message);
        expect(issue.message, matches(RegExp(r'[\u3400-\u9fff]')));
        expect(issue.localizedMessage(isEnglish: true), english);
      }
      expect(goal.toJson(), before);
    }
    expect(codes, unorderedEquals(GoalValidationCode.values));
  });

  test('Legacy issues retain literal copy and equality', () {
    const custom = GoalValidationIssue('custom', 'Literal message / 自定义');
    expect(custom.localizedMessage(isEnglish: true), custom.message);
    expect(custom.localizedMessage(isEnglish: false), custom.message);
    const legacy = GoalValidationIssue(
      GoalValidationField.dailyTargetCount,
      '每日目标次数不能为负数',
    );
    final generated = validateGoal(
      GoalItem(title: 'Literal', dailyTargetCount: -1),
    ).single;
    expect(generated, legacy);
    expect(generated.hashCode, legacy.hashCode);
  });

  test('Field validators accept null and valid values in both languages', () {
    for (final english in [false, true]) {
      expect(validateRandomMinGapDaysInt(null, isEnglish: english), isNull);
      expect(validateRandomMinGapDaysInt(1, isEnglish: english), isNull);
      expect(validateDailyTargetCountInt(null, isEnglish: english), isNull);
      expect(validateDailyTargetCountInt(0, isEnglish: english), isNull);
    }
  });

  test('Invalid field validators share the typed issue copy', () {
    final goal = GoalItem(
      title: 'Literal',
      dailyTargetCount: -1,
      scheduling: const GoalScheduling.random(minGapDays: 0),
    );
    final issues = validateGoal(goal);
    for (final english in [false, true]) {
      expect(
        validateRandomMinGapDaysInt(0, isEnglish: english),
        issues.first.localizedMessage(isEnglish: english),
      );
      expect(
        validateDailyTargetCountInt(-1, isEnglish: english),
        issues.last.localizedMessage(isEnglish: english),
      );
    }
  });
}
