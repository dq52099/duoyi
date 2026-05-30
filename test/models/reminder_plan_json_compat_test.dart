import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/habit.dart';
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

    test('push rule JSON and copyWith cannot keep dirty fullScreen=true', () {
      final rule = ReminderRule.fromJson({
        'id': 'dirty-push',
        'enabled': true,
        'kind': ReminderKind.push.index,
        'fullScreen': true,
      });
      expect(rule.kind, ReminderKind.push);
      expect(rule.fullScreen, isFalse);

      final copied = ReminderRule(
        kind: ReminderKind.alarm,
        fullScreen: true,
      ).copyWith(kind: ReminderKind.push);
      expect(copied.kind, ReminderKind.push);
      expect(copied.fullScreen, isFalse);
    });

    test('off reminder kind preserves compatibility but disables delivery', () {
      expect(
        ReminderKind.off.index,
        4,
        reason:
            'append-only enum value keeps existing saved kind indexes stable',
      );

      final rule = ReminderRule.fromJson({
        'id': 'off-rule',
        'enabled': true,
        'kind': ReminderKind.off.index,
        'fullScreen': true,
      });
      expect(rule.kind, ReminderKind.off);
      expect(rule.enabled, isFalse);
      expect(rule.fullScreen, isFalse);

      final plan = ReminderPlan(enabled: true, rules: [rule]);
      final legacy = plan.toLegacyReminderConfig();
      expect(legacy.enabled, isFalse);
      expect(legacy.kind, ReminderKind.off);

      final config = ReminderConfig.fromJson({
        'enabled': true,
        'kind': ReminderKind.off.index,
      });
      expect(config.enabled, isFalse);
      expect(config.kind, ReminderKind.off);
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

    test('Habit persists reminderPlan and migrates legacy habit reminder', () {
      final plan = ReminderPlan(
        enabled: true,
        rules: [
          ReminderRule(
            id: 'habit-popup',
            enabled: true,
            type: ReminderRuleType.weeklyTime,
            kind: ReminderKind.popup,
            hour: 8,
            minute: 20,
            weekdays: const [1, 3, 5],
          ),
        ],
      );
      final habit = Habit(
        id: 'habit-plan',
        name: '喝水',
        remind: true,
        remindHour: 8,
        remindMinute: 20,
        reminderPlan: plan,
      );

      final json = habit.toJson();
      expect(json['reminderPlan'], isA<Map<String, dynamic>>());
      expect(json['remind'], isTrue);
      expect(json['remindHour'], 8);
      expect(json['remindMinute'], 20);

      final roundTrip = Habit.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(roundTrip.reminderPlan.toJson(), equals(plan.toJson()));

      final migrated = Habit.fromJson({
        'id': 'legacy-habit',
        'name': '阅读',
        'remind': true,
        'remindHour': 21,
        'remindMinute': 30,
        'activeWeekdays': [0, 2, 4],
      });
      expect(migrated.reminderPlan.enabled, isTrue);
      expect(migrated.reminderPlan.primaryRule?.kind, ReminderKind.alarm);
      expect(
        migrated.reminderPlan.primaryRule?.type,
        ReminderRuleType.weeklyTime,
      );
      expect(migrated.reminderPlan.primaryRule?.weekdays, <int>[1, 3, 5]);
    });
  });
}
