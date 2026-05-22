import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/todo_kanban.dart';
import 'package:duoyi/models/goal.dart'
    show FocusLink, ReminderConfig, ReminderKind;
import 'package:duoyi/models/recurrence.dart';
import 'package:duoyi/models/todo.dart';

/// TodoItem JSON 向后兼容 + 往返一致性单元测试。
///
/// 覆盖场景（见 `.kiro/specs/app-alignment-overhaul/tasks.md` Task 5.2）：
///   1. 最小旧版 JSON（仅必需字段）填充安全默认值
///   2. legacy `hasReminder + reminderAt` 迁移到新 ReminderConfig(alarm)
///   3. 同时存在新 `reminder` 与 legacy `hasReminder`：新字段优先
///   4. PostponeRecord 往返：toJson → fromJson 字段一致
///   5. 完整 TodoItem 往返：encode → decode → fromJson → toJson 深度相等
///   6. 旧 JSON 缺失 `postponeHistory` 时解析为空列表（非 null）
///
/// Requirements: 2.2
void main() {
  group('TodoItem JSON backward compatibility', () {
    test('1. minimal legacy JSON parses with safe defaults for new fields', () {
      final today = DateTime(2025, 1, 15, 9, 0).toIso8601String();
      // ignore: deprecated_member_use_from_same_package
      final todo = TodoItem.fromJson(<String, dynamic>{
        'id': 'legacy-todo-1',
        'title': '旧任务',
        'quadrant': 1,
        'priority': 0,
        'date': today,
        'createdAt': today,
        'updatedAt': today,
      });

      expect(todo.id, 'legacy-todo-1');
      expect(todo.title, '旧任务');
      expect(todo.focusLink.enabled, isFalse);
      expect(todo.reminder.enabled, isFalse);
      expect(todo.timeTargetSeconds, isNull);
      expect(todo.postponeHistory, isEmpty);
      expect(todo.tags, isEmpty);
      expect(todo.subtasks, isEmpty);
      expect(todo.kanbanColumnId, defaultKanbanPendingColumnId);
      // 重复规则缺省为 none。
      expect(todo.recurrence.frequency, RecurrenceFrequency.none);
    });

    test(
      '2. legacy hasReminder + reminderAt migrates to ReminderConfig(alarm)',
      () {
        final today = DateTime(2025, 1, 15, 0, 0).toIso8601String();
        final reminderAt = DateTime(2025, 1, 15, 8, 30).toIso8601String();
        final todo = TodoItem.fromJson(<String, dynamic>{
          'id': 't-legacy-reminder',
          'title': '旧提醒任务',
          'quadrant': 1,
          'priority': 0,
          'date': today,
          'createdAt': today,
          'updatedAt': today,
          'hasReminder': true,
          'reminderAt': reminderAt,
          // 无 reminder 字段，走迁移路径。
        });

        expect(todo.reminder.enabled, isTrue);
        expect(todo.reminder.kind, ReminderKind.alarm);
        expect(todo.reminder.hour, 8);
        expect(todo.reminder.minute, 30);
        // legacy getter 仍返回 true，保证旧代码读路径不破。
        // ignore: deprecated_member_use_from_same_package
        expect(todo.hasReminder, isTrue);
      },
    );

    test('3. new reminder takes precedence over legacy hasReminder=false', () {
      final today = DateTime(2025, 1, 15, 0, 0).toIso8601String();
      final todo = TodoItem.fromJson(<String, dynamic>{
        'id': 't-new-reminder',
        'title': '新提醒任务',
        'quadrant': 1,
        'priority': 0,
        'date': today,
        'createdAt': today,
        'updatedAt': today,
        'hasReminder': false,
        'reminder': <String, dynamic>{
          'enabled': true,
          'kind': 0, // push
          'hour': 9,
          'minute': 30,
        },
      });

      expect(todo.reminder.enabled, isTrue);
      expect(todo.reminder.kind, ReminderKind.push);
      expect(todo.reminder.hour, 9);
      expect(todo.reminder.minute, 30);
    });

    test('4. PostponeRecord roundtrip preserves fields', () {
      final from = DateTime(2025, 1, 14, 9, 0);
      final to = DateTime(2025, 1, 15, 9, 0);
      final at = DateTime(2025, 1, 15, 0, 0, 1);
      final record = PostponeRecord(
        from: from,
        to: to,
        reason: 'auto_daily_rollover',
        at: at,
      );

      final today = to.toIso8601String();
      final todo = TodoItem(
        id: 'postpone-todo',
        title: '顺延任务',
        date: to,
        dueDate: to,
        postponeHistory: [record],
        createdAt: from,
        updatedAt: at,
      );

      final json =
          jsonDecode(jsonEncode(todo.toJson())) as Map<String, dynamic>;
      // 保证往返时序列化确实包含 postponeHistory。
      expect(json['postponeHistory'], isA<List<dynamic>>());
      expect((json['postponeHistory'] as List).length, 1);
      expect(today, isNotEmpty);

      final restored = TodoItem.fromJson(json);
      expect(restored.postponeHistory.length, 1);
      final r = restored.postponeHistory.single;
      expect(r.from.toIso8601String(), from.toIso8601String());
      expect(r.to.toIso8601String(), to.toIso8601String());
      expect(r.reason, 'auto_daily_rollover');
      expect(r.at.toIso8601String(), at.toIso8601String());
    });

    test('5. full TodoItem toJson → encode → decode → fromJson → toJson is '
        'structurally equal', () {
      final original = TodoItem(
        id: 'roundtrip-todo-1',
        title: '写作 25 分钟',
        notes: '专注写一段 app 设计稿。',
        isCompleted: false,
        quadrant: EisenhowerQuadrant.notUrgentImportant,
        priority: TodoPriority.high,
        kanbanColumnId: defaultKanbanInProgressColumnId,
        listGroupId: 'lg-1',
        listGroupName: '写作',
        tags: const ['writing', 'deep-work'],
        dueDate: DateTime(2025, 1, 15, 21, 0),
        date: DateTime(2025, 1, 15, 9, 0),
        // ignore: deprecated_member_use_from_same_package
        hasReminder: true,
        // ignore: deprecated_member_use_from_same_package
        reminderAt: DateTime(2025, 1, 15, 20, 0),
        reminder: const ReminderConfig(
          enabled: true,
          kind: ReminderKind.alarm,
          hour: 20,
          minute: 0,
          daysBefore: 0,
          vibrate: true,
          fullScreen: true,
        ),
        focusLink: const FocusLink(
          enabled: true,
          presetId: 'pomodoro-25',
          focusSeconds: 1500,
          whiteNoise: 'rain',
        ),
        timeTargetSeconds: 1500,
        postponeHistory: [
          PostponeRecord(
            from: DateTime(2025, 1, 14, 21, 0),
            to: DateTime(2025, 1, 15, 21, 0),
            reason: 'auto_daily_rollover',
            at: DateTime(2025, 1, 15, 0, 0, 1),
          ),
        ],
        subtasks: [
          Subtask(id: 'st-1', title: '写提纲', isCompleted: true, sortOrder: 0),
          Subtask(id: 'st-2', title: '写正文', sortOrder: 1),
        ],
        sortOrder: 2,
        recurrence: const RecurrenceRule(
          frequency: RecurrenceFrequency.weekly,
          interval: 1,
          byWeekdays: [0, 2, 4],
        ),
        completedAt: null,
        createdAt: DateTime(2025, 1, 1, 8, 0),
        updatedAt: DateTime(2025, 1, 14, 22, 30),
      );

      final firstJson = original.toJson();

      final decoded = TodoItem.fromJson(
        jsonDecode(jsonEncode(firstJson)) as Map<String, dynamic>,
      );
      final secondJson = decoded.toJson();

      // 键集必须一致，避免意外新增/丢失字段。
      expect(
        secondJson.keys.toSet(),
        firstJson.keys.toSet(),
        reason: 'toJson key set must be stable across round-trip',
      );

      // 深度相等：列表、嵌套 map、null 值都应一致。
      expect(secondJson, equals(firstJson));
      expect(decoded.kanbanColumnId, defaultKanbanInProgressColumnId);
    });

    test(
      '6. missing postponeHistory in legacy JSON parses to empty list (not null)',
      () {
        final today = DateTime(2025, 1, 15, 0, 0).toIso8601String();
        final todo = TodoItem.fromJson(<String, dynamic>{
          'id': 't-no-postpone',
          'title': '无顺延历史的旧任务',
          'quadrant': 1,
          'priority': 0,
          'date': today,
          'createdAt': today,
          'updatedAt': today,
          // postponeHistory 键完全缺失。
        });

        expect(todo.postponeHistory, isNotNull);
        expect(todo.postponeHistory, isEmpty);
      },
    );
  });
}
