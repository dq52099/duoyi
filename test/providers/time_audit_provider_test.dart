import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('manual entries persist and aggregate by category / day', () async {
    final provider = TimeAuditProvider();
    await provider.add(
      TimeEntry(
        title: '阅读',
        startAt: DateTime(2026, 5, 11, 8, 0),
        endAt: DateTime(2026, 5, 11, 8, 30),
        category: TimeEntryCategory.study,
      ),
    );
    await provider.add(
      TimeEntry(
        title: '工作',
        startAt: DateTime(2026, 5, 11, 9, 0),
        endAt: DateTime(2026, 5, 11, 10, 0),
        category: TimeEntryCategory.work,
      ),
    );

    final reloaded = TimeAuditProvider();
    await reloaded.loadFromStorage();

    expect(reloaded.entries, hasLength(2));
    expect(
      reloaded.totalSecondsInRange(
        DateTime(2026, 5, 11, 0, 0),
        DateTime(2026, 5, 12, 0, 0),
      ),
      5400,
    );
    expect(
      reloaded.secondsByCategory(
        DateTime(2026, 5, 11, 0, 0),
        DateTime(2026, 5, 12, 0, 0),
      )[TimeEntryCategory.study],
      1800,
    );
    expect(
      reloaded.secondsByDay(
        DateTime(2026, 5, 11, 0, 0),
        DateTime(2026, 5, 12, 0, 0),
      )['2026-05-11'],
      5400,
    );

    await reloaded.delete(reloaded.entries.first.id);
    expect(reloaded.entries, hasLength(1));
  });

  test('todo completion writes and removes a time entry', () async {
    final timeAudit = TimeAuditProvider();
    final todoProvider = TodoProvider()..timeAudit = timeAudit;
    final todo = TodoItem(
      title: '写周报',
      date: DateTime(2026, 5, 11, 9, 0),
      timeTargetSeconds: 1800,
    );
    await todoProvider.addTodo(todo);

    await todoProvider.toggleTodo(todo.id);
    expect(timeAudit.entries, hasLength(1));
    expect(timeAudit.entries.single.category, TimeEntryCategory.todo);
    expect(timeAudit.entries.single.durationSeconds, 1800);

    await todoProvider.toggleTodo(todo.id);
    expect(timeAudit.entries, isEmpty);
  });

  test(
    'todo completion can skip automatic time entry for manual duration',
    () async {
      final timeAudit = TimeAuditProvider();
      final todoProvider = TodoProvider()..timeAudit = timeAudit;
      final todo = TodoItem(
        title: '复盘设计稿',
        date: DateTime(2026, 5, 11, 9, 0),
        timeTargetSeconds: 1800,
      );
      await todoProvider.addTodo(todo);

      await todoProvider.toggleTodo(todo.id, recordCompletionTime: false);
      expect(timeAudit.entries, isEmpty);

      final completedTodo = todoProvider.todos.single;
      final completedAt = completedTodo.completedAt!;
      await timeAudit.add(
        TimeEntry(
          title: completedTodo.title,
          startAt: completedAt.subtract(const Duration(minutes: 45)),
          endAt: completedAt,
          category: TimeEntryCategory.todo,
          source: TimeEntrySource.todo,
          sourceId: completedTodo.id,
          dedupeKey: TimeAuditProvider.todoCompletionDedupeKey(
            completedTodo.id,
            completedAt,
          ),
          note: '手动记录耗时：45 分钟',
        ),
      );

      expect(timeAudit.entries, hasLength(1));
      expect(timeAudit.entries.single.durationSeconds, 2700);
      expect(timeAudit.entries.single.note, '手动记录耗时：45 分钟');
    },
  );

  test('habit check-ins write and remove time entries', () async {
    final timeAudit = TimeAuditProvider();
    final habitProvider = HabitProvider()..timeAudit = timeAudit;
    final habit = Habit(id: 'habit-1', name: '晨跑', targetCount: 30, unit: '分钟');
    await habitProvider.addHabit(habit);

    await habitProvider.incrementHabit(habit.id);
    expect(habitProvider.habits.single.todayCount(), 30);
    expect(timeAudit.entries, hasLength(1));
    expect(timeAudit.entries.single.category, TimeEntryCategory.habit);
    expect(timeAudit.entries.single.durationSeconds, 30 * 60);

    await habitProvider.decrementHabit(habit.id);
    expect(habitProvider.habits.single.todayCount(), 0);
    expect(timeAudit.entries, isEmpty);
  });

  test(
    'goal milestone completion writes and clears entries on delete',
    () async {
      final timeAudit = TimeAuditProvider();
      final goalProvider = GoalProvider()..timeAudit = timeAudit;
      final goal = GoalItem(
        title: '完成阅读计划',
        timeTargetSeconds: 2700,
        milestones: [GoalMilestone(title: '读完第一章')],
      );
      await goalProvider.add(goal);

      final milestone = goalProvider.goals.single.milestones.single;
      await goalProvider.toggleMilestone(goal.id, milestone.id);
      expect(timeAudit.entries, hasLength(1));
      expect(timeAudit.entries.single.category, TimeEntryCategory.goal);
      expect(timeAudit.entries.single.durationSeconds, 2700);

      await goalProvider.delete(goal.id);
      expect(timeAudit.entries, isEmpty);
    },
  );
}
