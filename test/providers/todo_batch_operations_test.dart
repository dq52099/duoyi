import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('TodoProvider exposes batch completion and recurrence preservation', () {
    final source = File('lib/providers/todo_provider.dart').readAsStringSync();

    expect(source, contains('Future<int> completeTodos('));
    expect(source, contains('final selected = ids.toSet();'));
    expect(
      source,
      contains('if (!selected.contains(prev.id) || prev.isCompleted)'),
    );
    expect(source, contains('completed.add(next);'));
    expect(source, contains('DomainEventType.todoCompleted'));
    expect(source, contains('if (prev.recurrence.isActive)'));
    expect(source, contains('final recurring = _nextRecurringTodo(prev);'));
    expect(source, contains('await _timeAudit?.recordTodoCompletion('));
    expect(source, contains('return changed;'));
  });

  test('TodoProvider exposes batch reopen and deletion paths', () {
    final source = File('lib/providers/todo_provider.dart').readAsStringSync();

    expect(source, contains('Future<int> reopenTodos(Iterable<String> ids)'));
    expect(
      source,
      contains('if (!selected.contains(prev.id) || !prev.isCompleted)'),
    );
    expect(source, contains('prev.copyWith('));
    expect(source, contains('isCompleted: false'));
    expect(source, contains('completedAt: null'));
    expect(source, contains('kanbanColumnId: prev.kanbanColumnId'));
    expect(source, contains('await _timeAudit?.removeTodoCompletion('));
    expect(source, contains('Future<int> deleteTodos(Iterable<String> ids)'));
    expect(
      source,
      contains(
        'await _timeAudit?.deleteBySource(TimeEntrySource.todo, todo.id)',
      ),
    );
    expect(
      source,
      contains('_todos.removeWhere((t) => selected.contains(t.id))'),
    );
    expect(source, contains('return existing.length;'));
  });

  test('TodoProvider exposes batch quadrant and priority updates', () {
    final source = File('lib/providers/todo_provider.dart').readAsStringSync();

    expect(source, contains('Future<int> updateTodosQuadrant('));
    expect(source, contains('EisenhowerQuadrant quadrant'));
    expect(source, contains('todo.copyWith(quadrant: quadrant)'));
    expect(source, contains('Future<int> updateTodosPriority('));
    expect(source, contains('TodoPriority priority'));
    expect(source, contains('todo.copyWith(priority: priority)'));
    expect(source, contains('if (changed == 0) return 0;'));
    expect(source, contains('await _saveToStorage();'));
  });

  test('TodoProvider exposes kanban column updates with completion sync', () {
    final source = File('lib/providers/todo_provider.dart').readAsStringSync();

    expect(source, contains("import '../core/todo_kanban.dart';"));
    expect(source, contains('Future<int> updateTodosKanbanColumn('));
    expect(source, contains('String columnId'));
    expect(source, contains('defaultKanbanPendingColumnId'));
    expect(source, contains('defaultKanbanDoneColumnId'));
    expect(source, contains('todo.copyWith('));
    expect(source, contains('kanbanColumnId: target'));
    expect(
      source,
      contains('isCompleted: target == defaultKanbanDoneColumnId'),
    );
    expect(
      source,
      contains('completedAt: target == defaultKanbanDoneColumnId'),
    );
    expect(source, contains('final completed = <TodoItem>[]'));
    expect(source, contains('final reopened = <TodoItem>[]'));
    expect(source, contains('DomainEventType.todoCompleted'));
    expect(source, contains('await _timeAudit?.recordTodoCompletion('));
    expect(source, contains('await _timeAudit?.removeTodoCompletion('));
  });

  test('TodoProvider can schedule a suggested task for today', () {
    final source = File('lib/providers/todo_provider.dart').readAsStringSync();

    expect(source, contains('Future<bool> scheduleTodoForToday('));
    expect(
      source,
      contains('todo.isCompleted || todo.isArchivedAfterRollover'),
    );
    expect(
      source,
      contains('final today = DateTime(base.year, base.month, base.day)'),
    );
    expect(
      source,
      contains('todo.copyWith(date: today, isArchivedAfterRollover: false)'),
    );
    expect(source, contains('return true;'));
  });

  test('recurring todo clone keeps shared ownership and assignment fields', () {
    final source = File('lib/providers/todo_provider.dart').readAsStringSync();

    expect(source, contains('TodoItem? _nextRecurringTodo(TodoItem prev)'));
    expect(source, contains('workspaceId: prev.workspaceId'));
    expect(source, contains('createdBy: prev.createdBy'));
    expect(source, contains('updatedBy: prev.updatedBy'));
    expect(source, contains('assigneeId: prev.assigneeId'));
    expect(source, contains('tags: [...prev.tags]'));
    expect(
      source,
      contains('final remainingOccurrences = prev.recurrence.maxOccurrences'),
    );
    expect(source, contains('remainingOccurrences <= 1'));
    expect(
      source,
      contains('final nextRecurrence = remainingOccurrences == null'),
    );
    expect(source, contains('maxOccurrences: remainingOccurrences - 1'));
    expect(source, contains('recurrence: nextRecurrence'));
  });

  test('TodoProvider can reorder the current visible todo sequence', () {
    final source = File('lib/providers/todo_provider.dart').readAsStringSync();

    expect(source, contains('int _compareTodos(TodoItem a, TodoItem b)'));
    expect(source, contains('_todos.sort(_compareTodos)'));
    expect(source, contains('Future<int> reorderVisibleTodos('));
    expect(source, contains('final orderedSet = ordered.toSet();'));
    expect(source, contains('if (orderedSet.length != ordered.length)'));
    expect(source, contains('final sorted = [..._todos]..sort(_compareTodos)'));
    expect(source, contains('if (orderedSet.contains(sorted[i].id))'));
    expect(source, contains('sorted[slots[i]] = byId[ordered[i]]!'));
    expect(source, contains('rebuilt.add(todo.copyWith(sortOrder: i))'));
    expect(source, contains('return changed;'));
  });
}
