import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

import '../test_support/recording_reminder_scheduler.dart';

void main() {
  test('TodoProvider skips duplicate in-flight creates', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = TodoProvider();
    final date = DateTime(2026, 6, 15);
    final first = TodoItem(id: 'todo-a', title: '重复提交', date: date);
    final second = TodoItem(id: 'todo-b', title: '  重复提交  ', date: date);

    final results = await Future.wait([
      provider.addTodo(first).then((_) => 'success').catchError((e) => 'error'),
      provider
          .addTodo(second)
          .then((_) => 'success')
          .catchError((e) => 'error'),
    ]);

    // 至少一个成功，至少一个因重复而失败
    expect(
      results.where((r) => r == 'success').length,
      greaterThanOrEqualTo(1),
    );
    expect(results.where((r) => r == 'error').length, greaterThanOrEqualTo(1));

    expect(provider.todos, hasLength(1));
    expect(provider.todos.single.id, 'todo-a');
    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString('todos')!) as List<Object?>;
    expect(stored, hasLength(1));
  });

  test('TodoProvider skips duplicate in-flight subtask creates', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = TodoProvider();
    final todo = TodoItem(id: 'todo-subtask', title: '父任务');
    await provider.addTodo(todo);

    final results = await Future.wait([
      provider
          .addSubtask(todo.id, '复核材料')
          .then((_) => 'success')
          .catchError((e) => 'error'),
      provider
          .addSubtask(todo.id, '  复核材料  ')
          .then((_) => 'success')
          .catchError((e) => 'error'),
    ]);

    // 至少一个成功，至少一个因重复而失败
    expect(
      results.where((r) => r == 'success').length,
      greaterThanOrEqualTo(1),
    );
    expect(results.where((r) => r == 'error').length, greaterThanOrEqualTo(1));

    final updated = provider.todos.singleWhere((item) => item.id == todo.id);
    expect(updated.subtasks, hasLength(1));
    expect(updated.subtasks.single.title, '复核材料');
  });

  test('TodoProvider skips duplicate in-flight deletes', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = TodoProvider();
    final todo = TodoItem(id: 'todo-delete', title: '删除一次');
    await provider.addTodo(todo);

    final results = await Future.wait([
      provider
          .deleteTodo(todo.id)
          .then((_) => 'success')
          .catchError((e) => 'error'),
      provider
          .deleteTodo(todo.id)
          .then((_) => 'success')
          .catchError((e) => 'error'),
    ]);

    // 至少一个成功，至少一个因重复而失败
    expect(
      results.where((r) => r == 'success').length,
      greaterThanOrEqualTo(1),
    );
    expect(results.where((r) => r == 'error').length, greaterThanOrEqualTo(1));

    expect(provider.todos, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString('todos')!) as List<Object?>;
    expect(stored, isEmpty);
  });

  test(
    'TodoProvider ignores duplicate in-flight updates for same todo',
    () async {
      SharedPreferences.setMockInitialValues({});
      final provider = TodoProvider();
      final todo = TodoItem(id: 'todo-update', title: '原始');
      await provider.addTodo(todo);

      final scheduler = _GatedTodoScheduler();
      provider.scheduler = scheduler;
      final first = provider.updateTodo(
        todo.id,
        provider.todos.single.copyWith(title: '第一次保存'),
      );
      await _waitForScheduler(scheduler);
      expect(scheduler.started, isTrue);

      await provider.updateTodo(
        todo.id,
        provider.todos.single.copyWith(title: '第二次保存'),
      );
      scheduler.complete();
      await first;

      expect(provider.todos.single.title, '第一次保存');
    },
  );

  test('TodoProvider ignores duplicate in-flight completions', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = TodoProvider();
    final todo = TodoItem(id: 'todo-complete', title: '完成一次');
    await provider.addTodo(todo);

    final scheduler = _GatedTodoScheduler();
    provider.scheduler = scheduler;
    final first = provider.completeTodos([todo.id]);
    await _waitForScheduler(scheduler);
    expect(scheduler.started, isTrue);

    final duplicate = await provider.completeTodos([todo.id]);
    scheduler.complete();
    final changed = await first;

    expect(changed, 1);
    expect(duplicate, 0);
    expect(provider.todos.single.isCompleted, isTrue);
  });

  test('TodoProvider exposes batch completion and recurrence preservation', () {
    final source = File('lib/providers/todo_provider.dart').readAsStringSync();

    expect(source, contains('Future<int> completeTodos('));
    expect(source, contains('final requested = ids.toSet();'));
    expect(source, contains('_claimInFlightKeys('));
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

  test(
    'TodoProvider resyncs reminders after completion and deletion changes',
    () {
      final source = File(
        'lib/providers/todo_provider.dart',
      ).readAsStringSync();

      String method(String startNeedle, String endNeedle) {
        final start = source.indexOf(startNeedle);
        final end = source.indexOf(endNeedle, start);
        expect(start, greaterThanOrEqualTo(0), reason: startNeedle);
        expect(end, greaterThan(start), reason: endNeedle);
        return source.substring(start, end);
      }

      expect(source, contains('Future<void> _syncTodoRemindersNow() async'));
      expect(source, contains('String? get lastReminderSyncIssue'));
      expect(source, contains('DateTime? get lastReminderSyncAttemptAt'));
      expect(source, contains('DateTime? get lastReminderSyncSucceededAt'));
      expect(source, contains('Future<void> _storageWriteQueue'));
      expect(source, contains('final Set<String> _inFlightCreateKeys'));
      expect(source, contains('_createInFlightDuplicateKey(todo)'));
      expect(
        source,
        contains("_lastReminderSyncIssue = 'reminder_scheduler_missing'"),
      );
      expect(
        source,
        contains(
          "debugPrint('[TodoProvider] reminder sync skipped: scheduler missing')",
        ),
      );
      expect(source, contains('await scheduler.syncTodos(List.of(_todos))'));
      expect(source, contains('_lastReminderSyncIssue = null'));
      expect(source, contains('_lastReminderSyncSucceededAt = DateTime.now()'));
      expect(source, contains('_lastReminderSyncIssue = e.toString()'));

      expect(
        method(
          'Future<void> addTodo(',
          'Future<TodoImportSummary> importTodos(',
        ),
        allOf(
          contains('bool waitForReminderSync = true'),
          contains('await _syncTodoRemindersNow();'),
          contains('unawaited(_syncTodoRemindersNow());'),
        ),
      );
      expect(
        method(
          'Future<TodoImportSummary> importTodos(',
          'Future<void> updateTodo(',
        ),
        contains('await _syncTodoRemindersNow();'),
      );
      expect(source, contains('bool waitForReminderSync = true'));
      expect(source, contains('unawaited(_syncTodoRemindersNow())'));
      expect(
        method(
          'Future<int> completeTodos(',
          'Future<int> reopenTodos(Iterable<String> ids)',
        ),
        contains('await _syncTodoRemindersNow();'),
      );
      expect(
        method('Future<int> reopenTodos(Iterable<String> ids)', '/// 切换完成状态。'),
        contains('await _syncTodoRemindersNow();'),
      );
      expect(
        method(
          'Future<void> toggleTodo(String id',
          'Future<void> deleteTodo(String id)',
        ),
        contains('await _syncTodoRemindersNow();'),
      );
      expect(
        method(
          'Future<void> deleteTodo(String id)',
          'Future<int> deleteTodos(Iterable<String> ids)',
        ),
        contains('await deleteTodos([id]);'),
      );
      expect(
        method(
          'Future<int> _deleteTodosLocked(Set<String> selected)',
          'Future<int> updateTodosQuadrant(',
        ),
        contains('await _syncTodoRemindersNow();'),
      );
      expect(
        method(
          'Future<int> updateTodosKanbanColumn(',
          'Future<bool> scheduleTodoForToday(',
        ),
        contains('await _syncTodoRemindersNow();'),
      );
      expect(
        method('Future<bool> scheduleTodoForToday(', 'Future<void> reorder('),
        contains('await _syncTodoRemindersNow();'),
      );
      expect(
        method(
          'Future<void> updateListGroupWorkspace(',
          '// --- Subtask operations ---',
        ),
        contains('await _syncTodoRemindersNow();'),
      );
    },
  );

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
    expect(source, contains('date: today,'));
    expect(source, contains('dueDate: nextDue'));
    expect(
      source,
      contains(
        'final endOfToday = DateTime(today.year, today.month, today.day, 23, 59, 59)',
      ),
    );
    expect(source, contains('preferredDue.isBefore(endOfToday)'));
    expect(source, contains('waitForReminderSync = true'));
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

Future<void> _waitForScheduler(_GatedTodoScheduler scheduler) async {
  for (var i = 0; i < 50; i++) {
    if (scheduler.started) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

class _GatedTodoScheduler extends RecordingReminderScheduler {
  final Completer<void> _gate = Completer<void>();

  bool get started => todoSyncs.isNotEmpty;

  void complete() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<void> syncTodos(
    Iterable<TodoItem> todos, {
    bool allowJustMissedOneShotReminders = true,
  }) async {
    todoSyncs.add(todos.map((todo) => todo.id).toList(growable: false));
    await _gate.future;
  }
}
