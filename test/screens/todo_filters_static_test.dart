import 'dart:io';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/todo_board_ui_copy.dart';
import 'package:duoyi/core/todo_filters.dart';
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
    expect(
      source,
      matches(
        RegExp(
          r'TodoBoardUiCopy\.customViewTitle\(\s*'
          r'filteredCount,\s*totalCount,?\s*\)',
        ),
      ),
    );
    expect(source, contains('_TodoQuickFilterChip'));
    expect(source, contains('_TodoFilterMenu<EisenhowerQuadrant>'));
    expect(source, contains('_TodoFilterMenu<TodoPriority>'));
    expect(source, contains('_TodoFilterMenu<TodoDueFilter>'));
    expect(source, contains('_TodoFilterMenu<TodoCompletionFilter>'));
    expect(source, contains('AppSecondaryMenuText('));
    expect(source, contains('AppSecondaryControlTheme('));
    expect(source, contains('appSecondaryRouteTitleTextStyle(ctx)'));
    expect(source, contains('appSecondaryControlLabelStyle(ctx)'));
    expect(source, contains('height: 42'));
    expect(source, isNot(contains('fontSize: 20')));
    expect(source, isNot(contains('selectedColor: t.color,')));
    expect(
      RegExp(
        r'selectedColor:\s*t\.color\.withValues\(\s*alpha:\s*0\.12,?\s*\)',
      ).hasMatch(source),
      isTrue,
    );

    _expectBilingualCopy(
      () => TodoBoardUiCopy.customViewTitle(2, 3),
      zh: '自定义视图 · 2/3',
      en: 'Custom view · 2/3',
    );
    _expectBilingualCopy(() => TodoBoardUiCopy.clear, zh: '清空', en: 'Clear');
  });

  test('任务筛选覆盖日期、完成状态、标签、清单和空结果', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();

    expect(source, contains('label: TodoBoardUiCopy.filterToday'));
    expect(source, contains('label: TodoBoardUiCopy.filterOverdue'));
    expect(source, contains('label: TodoBoardUiCopy.filterNext7Days'));
    expect(source, contains('label: TodoBoardUiCopy.filterCompleted'));
    expect(source, contains('? TodoBoardUiCopy.filterTag'));
    expect(
      source,
      contains('filter.listGroupName ?? TodoBoardUiCopy.filterList'),
    );
    expect(source, contains('TodoBoardUiCopy.filterDueLabel(filter)'));
    expect(source, contains('TodoBoardUiCopy.filterCompletionLabel(filter)'));
    expect(source, contains('TodoDueFilter.values'));
    expect(source, contains('TodoCompletionFilter.active'));
    expect(source, contains('TodoCompletionFilter.completed'));
    expect(source, contains('_TodoNoMatches'));
    expect(source, contains('TodoBoardUiCopy.noMatchingTasks'));
    expect(source, contains('TodoBoardUiCopy.clearFilters'));

    _expectBilingualCopy(
      () => TodoBoardUiCopy.filterToday,
      zh: '今日',
      en: 'Today',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.filterOverdue,
      zh: '逾期',
      en: 'Overdue',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.filterNext7Days,
      zh: '7天内',
      en: 'Within 7 days',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.filterCompleted,
      zh: '已完成',
      en: 'Completed',
    );
    _expectBilingualCopy(() => TodoBoardUiCopy.filterTag, zh: '标签', en: 'Tag');
    _expectBilingualCopy(
      () => TodoBoardUiCopy.filterList,
      zh: '清单',
      en: 'List',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.filterDueLabel(TodoDueFilter.next7Days),
      zh: '未来7天',
      en: 'Next 7 days',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.filterDueLabel(TodoDueFilter.noDue),
      zh: '无日期',
      en: 'No date',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.filterCompletionLabel(TodoCompletionFilter.active),
      zh: '未完成',
      en: 'Incomplete',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.noMatchingTasks,
      zh: '没有匹配任务',
      en: 'No matching tasks',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.clearFilters,
      zh: '清空筛选',
      en: 'Clear filters',
    );
  });

  test('任务页展示今日摘要且目标计入剩余项', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();

    expect(source, contains("import '../providers/habit_provider.dart';"));
    expect(source, contains("import '../providers/goal_provider.dart';"));
    expect(
      source,
      contains('class _TodoTodaySummaryCard extends StatelessWidget'),
    );
    expect(source, contains("key: const ValueKey('todo_today_summary_card')"));
    expect(source, contains('TodoBoardUiCopy.todayRemainingTasks(remaining)'));
    expect(
      source,
      contains(
        'final remaining = dailyRemaining + todoCount + activeGoalCount;',
      ),
    );
    expect(
      source,
      isNot(contains('final remaining = dailyRemaining + todoCount;')),
    );
    expect(source, isNot(contains("'今日还要完成 \$actionableRemaining 项'")));
    expect(source, contains('TodoBoardUiCopy.todaySummaryBreakdown('));
    expect(
      source,
      contains('CompletionVisibilityPolicy.shouldShowInToday(todo, now)'),
    );
    expect(source, isNot(contains('下一个')));
    expect(source, isNot(contains('upcomingToday')));
    expect(source, isNot(contains('nextDue')));
    expect(source, contains('habitProvider.habits'));
    expect(source, contains('goalProvider.activeGoals.length'));
  });

  test('清单模板选中态使用浅色主题背景避免白字实心块', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();

    expect(source, isNot(contains('Color _todoTemplateChipForeground')));
    expect(source, isNot(contains('double _todoContrastRatio')));
    expect(source, isNot(contains('_todoTemplateChipForeground(t.color)')));
    final templateStart = source.indexOf('TodoListTemplates.all');
    final templateEnd = source.indexOf(
      'const SizedBox(height: 20)',
      templateStart,
    );
    expect(templateStart, greaterThanOrEqualTo(0));
    expect(templateEnd, greaterThan(templateStart));
    final templateBlock = source.substring(templateStart, templateEnd);
    expect(templateBlock, isNot(contains('? Colors.white')));
    expect(templateBlock, isNot(contains('selectedColor: t.color,')));
    expect(
      templateBlock,
      matches(
        RegExp(
          r'.*selectedColor:\s*t\.color\.withValues\(\s*alpha:\s*0\.12,?\s*\).*',
          dotAll: true,
        ),
      ),
    );
    expect(templateBlock, contains('checkmarkColor: t.color'));
  });

  test('四象限详情继承外层自定义视图条件', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();
    final compactSource = source.replaceAll(RegExp(r'\s+'), '');

    expect(source, contains('filter: _filter'));
    expect(
      source,
      contains(
        'final TodoFilterState<EisenhowerQuadrant, TodoPriority>? filter',
      ),
    );
    expect(
      source,
      contains('widget.filter?.copyWith(quadrant: widget.quadrant)'),
    );
    expect(
      compactSource,
      contains(
        'TodoFilterState<EisenhowerQuadrant,TodoPriority>(quadrant:widget.quadrant,)',
      ),
    );
    expect(
      compactSource,
      contains(
        'finalbaseTodos=filter.includeArchived?provider.todos:provider.visibleListTodos;',
      ),
    );
    expect(
      compactSource,
      contains(
        'effectiveTodoFilter(filter,showCompletedTodos:preferences?.showCompletedTodos??true,)',
      ),
    );
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
    expect(
      source,
      matches(
        RegExp(
          r'tooltip:\s*_kanbanLoadFailed\s*\?\s*'
          r'TodoBoardUiCopy\.kanbanRetryLoadTooltip\s*:\s*'
          r'TodoBoardUiCopy\.kanbanColumnSettingsTooltip',
        ),
      ),
    );
    expect(source, contains('class _KanbanSettingsSheet'));
    expect(source, contains('labelText: TodoBoardUiCopy.defaultGroupingLabel'));
    expect(source, contains('TodoKanbanGroupMode.values'));
    expect(source, contains('_groupKanbanTodos'));
    expect(source, contains('config.groupMode'));
    expect(source, contains('labelText: TodoBoardUiCopy.columnNameLabel'));
    expect(source, contains('label: Text(TodoBoardUiCopy.addColumn)'));
    expect(source, contains('DragTarget<String>'));
    expect(source, contains('LongPressDraggable<String>'));
    expect(source, contains('updateTodosKanbanColumn'));
    expect(source, contains('kanbanGroups'));
    expect(source, contains('config.sortedColumns'));

    _expectBilingualCopy(
      () => TodoBoardUiCopy.kanbanColumnSettingsTooltip,
      zh: '看板列设置',
      en: 'Column settings',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.kanbanSettingsTitle,
      zh: '看板列设置',
      en: 'Kanban Column Settings',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.defaultGroupingLabel,
      zh: '默认分组',
      en: 'Default grouping',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.columnNameLabel,
      zh: '列名称',
      en: 'Column name',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.addColumn,
      zh: '新增列',
      en: 'Add column',
    );
  });
}

void _expectBilingualCopy(
  String Function() copy, {
  required String zh,
  required String en,
}) {
  final previousLocale = I18n.current;
  try {
    I18n.setLocale(AppLocale.zh);
    expect(copy(), zh);
    I18n.setLocale(AppLocale.en);
    expect(copy(), en);
  } finally {
    I18n.setLocale(previousLocale);
  }
}
