import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('任务页提供可组合的自定义视图筛选条', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();

    expect(source, contains("import '../core/todo_filters.dart';"));
    expect(
      source,
      contains('TodoFilterState<EisenhowerQuadrant, TodoPriority> _filter'),
    );
    expect(source, contains('filterTodos('));
    expect(source, contains('baseTodos,'));
    expect(source, contains('_filter,'));
    expect(source, contains('quadrantOf: (todo) => todo.quadrant'));
    expect(source, contains('priorityOf: (todo) => todo.priority'));
    expect(source, contains('tagsOf: (todo) => todo.tags'));
    expect(source, contains('listGroupNameOf: (todo) => todo.listGroupName'));
    expect(source, contains('dueDateOf: (todo) => todo.dueDate'));
    expect(source, contains('isCompletedOf: (todo) => todo.isCompleted'));
    expect(source, contains('groupTodosByQuadrant('));
    expect(source, contains('quadrants: EisenhowerQuadrant.values'));
    expect(source, contains('groupTodosByList('));
    expect(source, contains('collectTodoTags(baseTodos, (todo) => todo.tags)'));
    expect(source, contains('collectTodoListGroups('));
    expect(source, contains('_TodoFilterBar'));
    expect(source, contains('自定义视图 ·'));
    expect(source, contains('_TodoQuickFilterChip'));
    expect(source, contains('_TodoFilterMenu<EisenhowerQuadrant>'));
    expect(source, contains('_TodoFilterMenu<TodoPriority>'));
    expect(source, contains('_TodoFilterMenu<TodoDueFilter>'));
    expect(source, contains('_TodoFilterMenu<TodoCompletionFilter>'));
  });

  test('任务筛选覆盖日期、完成状态、标签、清单和空结果', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();

    expect(source, contains("label: '今日'"));
    expect(source, contains("label: '逾期'"));
    expect(source, contains("label: '7天内'"));
    expect(source, contains("label: '已完成'"));
    expect(source, contains("label: filter.tag == null ? '标签'"));
    expect(source, contains("label: filter.listGroupName ?? '清单'"));
    expect(source, contains('TodoDueFilter.noDue'));
    expect(source, contains('TodoCompletionFilter.active'));
    expect(source, contains('TodoCompletionFilter.completed'));
    expect(source, contains('_TodoNoMatches'));
    expect(source, contains('没有匹配任务'));
    expect(source, contains('清空筛选'));
  });

  test('四象限详情继承外层自定义视图条件', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();

    expect(source, contains('filter: _filter'));
    expect(
      source,
      contains(
        'final TodoFilterState<EisenhowerQuadrant, TodoPriority>? filter',
      ),
    );
    expect(source, contains('filter?.copyWith(quadrant: quadrant)'));
    expect(
      source,
      contains(
        'TodoFilterState<EisenhowerQuadrant, TodoPriority>(quadrant: quadrant)',
      ),
    );
    expect(source, contains('effectiveFilter,'));
  });

  test('看板视图支持自定义列、拖拽移动和本地持久化', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();

    expect(source, contains("import '../core/todo_kanban.dart';"));
    expect(
      source,
      contains("import 'package:shared_preferences/shared_preferences.dart';"),
    );
    expect(source, contains('TodoKanbanBoardConfig _kanbanConfig'));
    expect(source, contains('todoKanbanColumnsPrefsKey'));
    expect(source, contains('TodoKanbanBoardConfig.decode'));
    expect(source, contains('_saveKanbanConfig'));
    expect(source, contains("tooltip: '看板列设置'"));
    expect(source, contains('class _KanbanSettingsSheet'));
    expect(source, contains("labelText: '默认分组'"));
    expect(source, contains('TodoKanbanGroupMode.values'));
    expect(source, contains('_groupKanbanTodos'));
    expect(source, contains('config.groupMode'));
    expect(source, contains("labelText: '列名称'"));
    expect(source, contains("label: const Text('新增列')"));
    expect(source, contains('DragTarget<String>'));
    expect(source, contains('LongPressDraggable<String>'));
    expect(source, contains('updateTodosKanbanColumn'));
    expect(source, contains('kanbanGroups'));
    expect(source, contains('config.sortedColumns'));
  });
}
