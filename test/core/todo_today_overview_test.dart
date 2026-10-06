import 'package:duoyi/core/completion_visibility_policy.dart';
import 'package:duoyi/core/todo_filters.dart';
import 'package:duoyi/models/todo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 6, 12);
  final todos = [
    TodoItem(id: 'no-due', title: 'No due date', date: now),
    TodoItem(
      id: 'future-due-done-today',
      title: 'Completed today',
      date: now,
      dueDate: DateTime(2026, 10, 8),
      isCompleted: true,
      completedAt: now,
    ),
    TodoItem(
      id: 'due-today-done-yesterday',
      title: 'Already completed yesterday',
      date: DateTime(2026, 10, 5),
      dueDate: now,
      isCompleted: true,
      completedAt: DateTime(2026, 10, 5),
    ),
    TodoItem(
      id: 'tomorrow-entry',
      title: 'Tomorrow',
      date: DateTime(2026, 10, 7),
    ),
  ];

  List<TodoItem> apply(
    TodoFilterState<EisenhowerQuadrant, TodoPriority> filter,
  ) => filterTodos(
    todos,
    filter,
    now: now,
    quadrantOf: (t) => t.quadrant,
    priorityOf: (t) => t.priority,
    tagsOf: (t) => t.tags,
    listGroupNameOf: (t) => t.listGroupName,
    dueDateOf: (t) => t.dueDate,
    isCompletedOf: (t) => t.isCompleted,
    isArchivedAfterRolloverOf: (t) => t.isArchivedAfterRollover,
    isInTodayOverviewOf: CompletionVisibilityPolicy.isInTodayOverview,
  );

  test('overview filter matches visible pending and completions today', () {
    const filter = TodoFilterState<EisenhowerQuadrant, TodoPriority>(
      todayOverview: true,
    );
    expect(apply(filter).map((t) => t.id), ['no-due', 'future-due-done-today']);
    expect(filter.hasActiveFilters, isTrue);
    expect(filter.copyWith(tag: 'work').todayOverview, isTrue);
    expect(filter.copyWith(todayOverview: false).hasActiveFilters, isFalse);
    expect(apply(filter.copyWith(todayOverview: false)), hasLength(4));
  });

  test('due-today filter retains its existing independent meaning', () {
    expect(
      apply(
        const TodoFilterState(due: TodoDueFilter.dueToday),
      ).map((t) => t.id),
      ['due-today-done-yesterday'],
    );
  });
}
