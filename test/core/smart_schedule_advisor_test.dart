import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/smart_schedule_advisor.dart';
import 'package:duoyi/models/todo.dart';

void main() {
  final now = DateTime(2026, 5, 18, 10, 0);

  test('suggestToday ranks overdue and due-soon tasks first', () {
    final todos = [
      TodoItem(
        title: '低优先级未来任务',
        date: DateTime(2026, 5, 20),
        dueDate: DateTime(2026, 5, 20, 18),
        priority: TodoPriority.low,
      ),
      TodoItem(
        title: '三小时内提交',
        date: DateTime(2026, 5, 18),
        dueDate: DateTime(2026, 5, 18, 11),
        priority: TodoPriority.medium,
      ),
      TodoItem(
        title: '昨天该完成',
        date: DateTime(2026, 5, 17),
        dueDate: DateTime(2026, 5, 17, 21),
        priority: TodoPriority.low,
      ),
      TodoItem(
        title: '已完成不推荐',
        date: DateTime(2026, 5, 18),
        dueDate: DateTime(2026, 5, 18, 12),
        isCompleted: true,
        completedAt: now,
      ),
    ];

    final suggestions = SmartScheduleAdvisor.suggestToday(todos, now: now);

    expect(suggestions.map((s) => s.todo.title), ['昨天该完成', '三小时内提交']);
    expect(suggestions.first.reason, contains('已逾期'));
    expect(suggestions[1].reason, contains('3 小时内到期'));
  });

  test(
    'suggestToday includes important high-priority tasks without due date',
    () {
      final todos = [
        TodoItem(
          title: '重要规划',
          date: DateTime(2026, 5, 18),
          priority: TodoPriority.high,
          quadrant: EisenhowerQuadrant.notUrgentImportant,
        ),
        TodoItem(title: '普通未来任务', date: DateTime(2026, 5, 30)),
      ];

      final suggestions = SmartScheduleAdvisor.suggestToday(todos, now: now);

      expect(suggestions, hasLength(1));
      expect(suggestions.single.todo.title, '重要规划');
      expect(suggestions.single.reason, contains('高优先级'));
      expect(suggestions.single.reason, contains('重要任务'));
    },
  );
}
