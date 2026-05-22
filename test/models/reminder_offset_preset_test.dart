import 'dart:io';

import 'package:test/test.dart';

import 'package:duoyi/models/goal.dart';

void main() {
  group('Reminder offset presets', () {
    test('cover common before-due reminder templates', () {
      expect(
        ReminderRule.relativeOffsetPresetMinutes,
        containsAll(const <int>[
          -5,
          -15,
          -30,
          -60,
          -24 * 60,
          -2 * 24 * 60,
          -3 * 24 * 60,
        ]),
      );
      expect(
        ReminderRule.relativeOffsetPresetMinutes.every(
          (minutes) => minutes < 0,
        ),
        isTrue,
        reason: 'Relative reminder presets must mean "before due time".',
      );
      expect(
        ReminderRule.relativeOffsetPresetMinutes.toSet(),
        hasLength(ReminderRule.relativeOffsetPresetMinutes.length),
      );
    });

    test('relative reminders keep exact minute offsets through JSON', () {
      final plan = ReminderPlan(
        enabled: true,
        rules: [
          for (final minutes in ReminderRule.relativeOffsetPresetMinutes)
            ReminderRule(
              id: 'offset-$minutes',
              type: ReminderRuleType.relativeToDue,
              kind: ReminderKind.alarm,
              hour: 9,
              minute: 0,
              offsetMinutes: minutes,
            ),
        ],
      );

      final decoded = ReminderPlan.fromJson(plan.toJson());

      expect(
        decoded.rules.map((rule) => rule.offsetMinutes),
        orderedEquals(ReminderRule.relativeOffsetPresetMinutes),
      );
    });

    test('ReminderPlanEditor reuses the shared preset source', () {
      final source = File(
        'lib/widgets/reminder_plan_editor.dart',
      ).readAsStringSync();

      expect(source, contains('ReminderRule.relativeOffsetPresetMinutes'));
      expect(source, isNot(contains("(-10, '10 分钟')")));
    });
  });
}
