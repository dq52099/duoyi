import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/todo.dart';

void main() {
  group('ReminderPlan JSON compatibility', () {
    test('fromLegacy preserves the legacy reminder mirror', () {
      final legacy = ReminderConfig(
        enabled: true,
        kind: ReminderKind.alarm,
        hour: 20,
        minute: 30,
        daysBefore: 2,
        vibrate: false,
        fullScreen: false,
      );

      final plan = ReminderPlan.fromLegacy(legacy);
      expect(plan.enabled, isTrue);
      expect(plan.rules, hasLength(1));

      final rule = plan.rules.single;
      expect(rule.type, ReminderRuleType.relativeToDue);
      expect(rule.kind, ReminderKind.alarm);
      expect(rule.hour, 20);
      expect(rule.minute, 30);
      expect(rule.offsetMinutes, -2880);
      expect(rule.vibrate, isFalse);
      expect(rule.fullScreen, isFalse);

      final mirrored = plan.toLegacyReminderConfig();
      expect(mirrored.enabled, isTrue);
      expect(mirrored.kind, ReminderKind.alarm);
      expect(mirrored.hour, 20);
      expect(mirrored.minute, 30);
      expect(mirrored.daysBefore, 2);
      expect(mirrored.vibrate, isFalse);
      expect(mirrored.fullScreen, isFalse);
    });

    test('ReminderPlan toJson/fromJson roundtrip is stable', () {
      final original = ReminderPlan(
        enabled: true,
        rules: [
          ReminderRule(
            id: 'rule-1',
            enabled: true,
            type: ReminderRuleType.absolute,
            kind: ReminderKind.push,
            hour: 8,
            minute: 30,
          ),
          ReminderRule(
            id: 'rule-2',
            enabled: true,
            type: ReminderRuleType.weeklyTime,
            kind: ReminderKind.alarm,
            hour: 20,
            minute: 0,
            weekdays: const [1, 3, 5],
            vibrate: true,
            fullScreen: true,
            snoozeMinutes: 10,
            repeatCount: 2,
          ),
        ],
      );

      final decoded = ReminderPlan.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.toJson(), equals(original.toJson()));
    });

    test(
      'TodoItem and GoalItem persist reminderPlan together with legacy reminder',
      () {
        final plan = ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'todo-rule',
              enabled: true,
              type: ReminderRuleType.absolute,
              kind: ReminderKind.alarm,
              hour: 21,
              minute: 15,
            ),
            ReminderRule(
              id: 'todo-rule-2',
              enabled: true,
              type: ReminderRuleType.dailyTime,
              kind: ReminderKind.push,
              hour: 7,
              minute: 45,
            ),
          ],
        );

        final todo = TodoItem(
          id: 'todo-plan',
          title: '多提醒任务',
          date: DateTime(2026, 5, 10, 9, 0),
          dueDate: DateTime(2026, 5, 10, 21, 0),
          reminderPlan: plan,
        );
        final todoJson = todo.toJson();
        expect(todoJson['reminderPlan'], isA<Map<String, dynamic>>());
        expect(todoJson['reminder'], isA<Map<String, dynamic>>());

        final todoRoundTrip = TodoItem.fromJson(
          jsonDecode(jsonEncode(todoJson)) as Map<String, dynamic>,
        );
        expect(todoRoundTrip.reminderPlan.toJson(), equals(plan.toJson()));
        expect(todoRoundTrip.reminder.enabled, isTrue);
        expect(todoRoundTrip.reminder.kind, ReminderKind.alarm);
        expect(todoRoundTrip.hasReminder, isTrue);

        final goal = GoalItem(
          id: 'goal-plan',
          title: '多提醒目标',
          targetDate: DateTime(2026, 5, 12, 20, 0),
          reminderPlan: plan,
        );
        final goalJson = goal.toJson();
        expect(goalJson['reminderPlan'], isA<Map<String, dynamic>>());
        expect(goalJson['reminder'], isA<Map<String, dynamic>>());

        final goalRoundTrip = GoalItem.fromJson(
          jsonDecode(jsonEncode(goalJson)) as Map<String, dynamic>,
        );
        expect(goalRoundTrip.reminderPlan.toJson(), equals(plan.toJson()));
        expect(goalRoundTrip.reminder.enabled, isTrue);
        expect(goalRoundTrip.reminder.kind, ReminderKind.alarm);
      },
    );
  });
}
