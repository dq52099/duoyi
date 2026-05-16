import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/recurrence.dart';

/// GoalItem JSON 向后兼容 + 往返一致性单元测试。
///
/// 覆盖场景（见 `.kiro/specs/app-alignment-overhaul/tasks.md` Task 2.2）：
///   1. 最小旧版 JSON（仅 id / title）填充安全默认值
///   2. legacy category: "health" → GoalCategory.health
///   3. legacy category: "unknown" → GoalCategory.custom
///   4. category 缺失 → GoalCategory.custom
///   5. legacy category 数字字符串 "1" → GoalCategory.values[1]
///   6. 数字 category → 按 index 匹配
///   7. scheduling.mode 缺失 → SchedulingMode.fixed
///   8. reminder.kind 缺失 → ReminderKind.alarm
///   9. 完整对象 toJson → fromJson → toJson 结构等价
///  10. focusLink.whiteNoise 缺失 → 'none'
///
/// Requirements: 1.2
void main() {
  group('GoalItem JSON backward compatibility', () {
    test('1. minimal legacy {id, title} parses with safe defaults', () {
      final goal = GoalItem.fromJson({'id': 'legacy-goal-1', 'title': '旧版目标'});

      expect(goal.id, 'legacy-goal-1');
      expect(goal.title, '旧版目标');
      expect(goal.category, GoalCategory.custom);
      expect(goal.recurrence.frequency, RecurrenceFrequency.none);
      expect(goal.scheduling.mode, SchedulingMode.fixed);
      expect(goal.skipHolidays, isFalse);
      expect(goal.focusLink.enabled, isFalse);
      expect(goal.reminder.enabled, isFalse);
      expect(goal.timeTargetSeconds, isNull);
      expect(goal.dailyTargetCount, isNull);
    });

    test('2. legacy category "health" maps to GoalCategory.health', () {
      final goal = GoalItem.fromJson({
        'id': 'a',
        'title': 't',
        'category': 'health',
      });
      expect(goal.category, GoalCategory.health);
    });

    test('3. legacy category "unknown" falls back to custom', () {
      final goal = GoalItem.fromJson({
        'id': 'a',
        'title': 't',
        'category': 'unknown',
      });
      expect(goal.category, GoalCategory.custom);
    });

    test('4. missing category falls back to custom', () {
      final goal = GoalItem.fromJson({'id': 'a', 'title': 't'});
      expect(goal.category, GoalCategory.custom);
    });

    test(
      '5. legacy numeric string category "1" maps to GoalCategory.values[1]',
      () {
        final goal = GoalItem.fromJson({
          'id': 'a',
          'title': 't',
          'category': '1',
        });
        expect(goal.category, GoalCategory.values[1]);
      },
    );

    test('6. numeric integer category still works', () {
      final goal = GoalItem.fromJson({'id': 'a', 'title': 't', 'category': 2});
      expect(goal.category, GoalCategory.values[2]);
    });

    test('7. scheduling without mode defaults to SchedulingMode.fixed', () {
      final goal = GoalItem.fromJson({
        'id': 'a',
        'title': 't',
        'scheduling': <String, dynamic>{}, // mode key missing
      });
      expect(goal.scheduling.mode, SchedulingMode.fixed);
    });

    test('8. reminder without kind defaults to ReminderKind.alarm', () {
      final goal = GoalItem.fromJson({
        'id': 'a',
        'title': 't',
        'reminder': {
          'enabled': true,
          'hour': 8,
          'minute': 0,
          // kind missing
        },
      });
      expect(goal.reminder.enabled, isTrue);
      expect(goal.reminder.kind, ReminderKind.alarm);
    });

    test('10. focusLink without whiteNoise defaults to "none"', () {
      final goal = GoalItem.fromJson({
        'id': 'a',
        'title': 't',
        'focusLink': {
          'enabled': true,
          // whiteNoise missing
        },
      });
      expect(goal.focusLink.enabled, isTrue);
      expect(goal.focusLink.whiteNoise, 'none');
    });

    test(
      '9. full GoalItem toJson → fromJson → toJson is structurally equal',
      () {
        final original = GoalItem(
          id: 'roundtrip-goal-1',
          title: '阅读 30 分钟',
          description: '每天晚上读书 30 分钟，保持大脑活跃。',
          icon: 'book',
          colorValue: 0xFF1234FF,
          startDate: DateTime(2025, 1, 1, 8, 30),
          targetDate: DateTime(2025, 12, 31, 23, 59),
          status: GoalStatus.active,
          progress: 0.25,
          autoProgress: false,
          milestones: [
            GoalMilestone(
              id: 'ms-1',
              title: '读完第一章',
              isCompleted: true,
              completedAt: DateTime(2025, 1, 5, 10, 0),
            ),
            GoalMilestone(id: 'ms-2', title: '读完第二章'),
          ],
          category: GoalCategory.study,
          recurrence: const RecurrenceRule(
            frequency: RecurrenceFrequency.weekly,
            interval: 1,
            byWeekdays: [0, 2, 4],
          ),
          scheduling: const GoalScheduling(
            mode: SchedulingMode.random,
            randomMinGapDays: 2,
            randomMaxPerWeek: 3,
            randomMaxPerMonth: 10,
          ),
          skipHolidays: true,
          focusLink: const FocusLink(
            enabled: true,
            presetId: 'pomodoro-25',
            focusSeconds: 1500,
            whiteNoise: 'rain',
          ),
          reminder: const ReminderConfig(
            enabled: true,
            kind: ReminderKind.alarm,
            hour: 20,
            minute: 30,
            daysBefore: 0,
            vibrate: true,
            fullScreen: true,
          ),
          timeTargetSeconds: 1800,
          dailyTargetCount: 1,
          sortOrder: 3,
          createdAt: DateTime(2024, 12, 25, 9, 0),
          updatedAt: DateTime(2025, 1, 6, 18, 0),
        );

        final firstJson = original.toJson();

        // 经过一次真实的 JSON 编解码，确保类型经过字符串化也能正确还原。
        final decoded = GoalItem.fromJson(
          jsonDecode(jsonEncode(firstJson)) as Map<String, dynamic>,
        );
        final secondJson = decoded.toJson();

        // 显式键集一致，避免意外新增 / 丢失字段。
        expect(
          secondJson.keys.toSet(),
          firstJson.keys.toSet(),
          reason: 'toJson key set must be stable across round-trip',
        );

        // 深度相等校验：列表、嵌套 map、null 值都应一致。
        expect(secondJson, equals(firstJson));
      },
    );
  });
}
