import 'dart:io';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/todo_board_ui_copy.dart';
import 'package:test/test.dart';

void main() {
  test('both list group variants use the same localized sharing button', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();
    expect(source, contains('_ListGroupShareButton(groupName: groupName)'));
    expect(
      source,
      contains('_ListGroupShareButton(groupName: widget.groupName)'),
    );
    expect(source, isNot(contains('Future<void> _shareGroup(')));
    expect(
      source,
      contains('TodoBoardUiCopy.sharedWorkspacePrefix(workspace.name)'),
    );
    expect(source, contains('TodoBoardUiCopy.shareListDialogSubtitle('));
    expect(source, contains('expectedGroupMembers: origin.members'));
    _expectBilingualCopy(
      () => TodoBoardUiCopy.workspaceMemberInfo(1, 'Owner'),
      zh: '1 位成员 · Owner',
      en: '1 member · Owner',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.workspaceMemberInfo(2, 'Owner'),
      zh: '2 位成员 · Owner',
      en: '2 members · Owner',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.shareStatusSaveFailed,
      zh: '共享状态保存失败，请重试',
      en: 'Could not update sharing. Please try again.',
    );
  });

  test('任务页提供批量操作入口和选择状态', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();

    expect(source, contains('bool _batchMode = false'));
    expect(source, contains('final Set<String> _selectedTodoIds'));
    expect(source, contains('_enterBatchMode({String? todoId'));
    expect(source, contains('switchToList: true'));
    expect(source, contains('tooltip: TodoBoardUiCopy.batchActionsTooltip'));
    expect(
      source,
      contains('TodoBoardUiCopy.batchModeSelected(_selectedTodoIds.length)'),
    );
    expect(source, contains('_selectAllVisible(editableVisibleIds)'));
    expect(source, contains('Icons.select_all_outlined'));
    expect(source, contains('Icons.deselect_outlined'));

    _expectBilingualCopy(
      () => TodoBoardUiCopy.batchActionsTooltip,
      zh: '批量操作',
      en: 'Batch actions',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.batchModeSelected(2),
      zh: '已选择 2 项',
      en: 'Selected 2 items',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.selectAllTooltip(false),
      zh: '全选当前视图',
      en: 'Select all in view',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.selectAllTooltip(true),
      zh: '取消全选',
      en: 'Deselect all',
    );
  });

  test('批量模式复用当前自定义视图并限制为可编辑任务', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();

    expect(source, contains('filteredTodos'));
    expect(source, contains('shareProvider.canEdit(todo.workspaceId)'));
    expect(source, contains('editableVisibleIds'));
    expect(source, contains('selectedTodoIds.contains'));
    expect(source, contains('onToggleSelection(todo.id)'));
    expect(source, contains('onLongPress: canEdit'));
    expect(source, contains('if (widget.batchMode) return content;'));
    expect(source, contains('floatingActionButton: _batchMode'));
    expect(source, contains('? null'));
    expect(source, contains('if (!_batchMode)'));
    expect(source, contains('_TodoViewSwitcher'));
  });

  test('底部批量操作栏覆盖完成恢复移动优先级和删除', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();

    expect(source, contains('_TodoBatchActionBar'));
    expect(source, contains('selectedCount: _selectedTodoIds.length'));
    expect(source, contains('onComplete: _selectedTodoIds.isEmpty'));
    expect(source, contains('onReopen: _selectedTodoIds.isEmpty'));
    expect(source, contains('onMove: _selectedTodoIds.isEmpty'));
    expect(source, contains('onPriority: _selectedTodoIds.isEmpty'));
    expect(source, contains('onDelete: _selectedTodoIds.isEmpty'));
    expect(source, contains('PopupMenuButton<EisenhowerQuadrant>'));
    expect(source, contains('PopupMenuButton<TodoPriority>'));
    expect(source, contains('label: Text(TodoBoardUiCopy.batchComplete)'));
    expect(source, contains('label: Text(TodoBoardUiCopy.batchRestore)'));
    expect(source, contains('tooltip: TodoBoardUiCopy.batchMoveTo'));
    expect(source, contains('label: TodoBoardUiCopy.batchMoveTo'));
    expect(source, contains('tooltip: TodoBoardUiCopy.batchPriority'));
    expect(source, contains('label: TodoBoardUiCopy.batchPriority'));

    _expectBilingualCopy(
      () => TodoBoardUiCopy.batchComplete,
      zh: '完成',
      en: 'Complete',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.batchRestore,
      zh: '恢复',
      en: 'Restore',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.batchMoveTo,
      zh: '移动到',
      en: 'Move to',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.batchPriority,
      zh: '优先级',
      en: 'Priority',
    );
  });

  test('任务页调用 provider 批量写接口', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();

    expect(source, contains('.completeTodos('));
    expect(source, contains('.reopenTodos('));
    expect(source, contains('.updateTodosQuadrant('));
    expect(source, contains('.updateTodosPriority('));
    expect(source, contains('.deleteTodos('));
    expect(source, contains('TodoBoardUiCopy.deleteSelectedTasksTitle'));
    expect(
      source,
      contains('TodoBoardUiCopy.deleteSelectedTasksContent(selectedCount)'),
    );
    expect(source, contains('TodoBoardUiCopy.batchDeleted(count)'));

    _expectBilingualCopy(
      () => TodoBoardUiCopy.deleteSelectedTasksTitle,
      zh: '删除所选任务',
      en: 'Delete selected tasks',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.deleteSelectedTasksContent(2),
      zh: '确认删除 2 个任务吗？相关时间足迹也会同步移除。',
      en: 'Are you sure you want to delete 2 tasks? Related time logs will also be removed.',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.batchDeleted(2),
      zh: '已删除 2 个任务',
      en: 'Deleted 2 tasks',
    );
  });

  test('任务列表支持清单内拖拽排序且不抢占批量选择长按', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();

    expect(source, contains('ReorderableListView.builder'));
    expect(source, contains('buildDefaultDragHandles: false'));
    expect(source, contains('ReorderableDragStartListener'));
    expect(source, contains('message: TodoBoardUiCopy.dragToReorderTooltip'));
    _expectBilingualCopy(
      () => TodoBoardUiCopy.dragToReorderTooltip,
      zh: '拖拽排序',
      en: 'Drag to reorder',
    );
    expect(source, contains('Icons.drag_indicator'));
    expect(source, contains('!widget.batchMode'));
    expect(
      source,
      contains('widget.todos.every((todo) => shareProvider.canEdit'),
    );
    expect(source, contains('Future<void> _reorderTodos('));
    expect(source, contains('if (newIndex > oldIndex) newIndex -= 1;'));
    expect(source, contains('ids.insert(newIndex, moved);'));
    expect(source, contains('.reorderVisibleTodos(ids)'));
    expect(source, contains('onLongPress: canEdit'));
  });

  test('任务左滑弹出操作按钮而不是直接删除', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();

    expect(source, contains('class _TodoTile extends StatefulWidget'));
    expect(source, contains('onHorizontalDragUpdate'));
    expect(source, contains('Matrix4.translationValues(-_swipeOffset'));
    expect(source, contains('class _TodoInlineSwipeActions'));
    expect(source, contains('bool get _swipeActive => _swipeOffset > 0'));
    expect(source, contains('if (_swipeActive)'));
    expect(source, contains('TodoBoardUiCopy.swipeRestore'));
    expect(source, contains('label: TodoBoardUiCopy.swipeDelete'));
    expect(source, contains('if (widget.batchMode) return content;'));
    expect(source, isNot(contains("label: '详情'")));
    expect(source, isNot(contains("ValueKey('todo_swipe_detail_button')")));
    expect(source, contains("'todo_swipe_complete_button'"));
    expect(source, contains("'todo_swipe_reopen_button'"));
    expect(source, contains("ValueKey('todo_swipe_delete_button')"));
    expect(
      source,
      contains('_toggleTodoCompletionFromSwipe(context, widget.todo)'),
    );
    expect(
      source,
      contains('completeTodoWithOptionalTimeRecord(context, todo)'),
    );
    expect(source, contains('reopenTodos([todo.id])'));
    expect(
      source,
      contains('title: Text(TodoBoardUiCopy.deleteTaskDialogTitle)'),
    );
    expect(source, isNot(contains('Dismissible(')));
    expect(source, isNot(contains('confirmDismiss: (_) async')));
    expect(source, isNot(contains('_showSwipeActions(context, provider)')));
    expect(source, isNot(contains("title: '任务操作'")));
    expect(source, isNot(contains('onDismissed:')));
  });

  test('任务列表减少滑动卡顿和重绘面积', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();

    expect(
      source.replaceAll(RegExp(r'\s+'), ' '),
      contains(
        '_TodoViewMode.list => NotificationListener<ScrollNotification>',
      ),
    );
    expect(source, contains('cacheExtent: 640'));
    expect(source, contains('cacheExtent: 560'));
    expect(source, contains('RepaintBoundary(child: content)'));
    expect(source, contains('RepaintBoundary(child: card)'));
    expect(source, contains('clipBehavior: Clip.hardEdge'));
    expect(source, isNot(contains('IntrinsicHeight(')));
  });

  test('任务滚动时自动收起横滑完成删除区', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();

    final screenStateStart = source.indexOf('class _TodoScreenState');
    final listScrollStart = source.indexOf('void _onListScroll() {');
    final listScrollEnd = source.indexOf(
      '\n  Future<void> _loadKanbanConfig(',
      listScrollStart,
    );
    expect(screenStateStart, greaterThanOrEqualTo(0));
    expect(listScrollStart, greaterThan(screenStateStart));
    expect(listScrollEnd, greaterThan(listScrollStart));
    final listScrollListener = source.substring(listScrollStart, listScrollEnd);
    expect(listScrollListener, contains('_listScrollController.hasClients'));
    expect(
      source,
      contains('_listScrollController.addListener(_onListScroll)'),
    );
    expect(
      source,
      contains('_listScrollController.removeListener(_onListScroll)'),
    );

    final scrollHandlerStart = source.indexOf(
      'bool _dismissSwipeActionsOnScroll(ScrollNotification notification) {',
      screenStateStart,
    );
    final scrollHandlerEnd = source.indexOf(
      '\n  Future<void> _completeSelected()',
      scrollHandlerStart,
    );
    expect(scrollHandlerStart, greaterThan(screenStateStart));
    expect(scrollHandlerEnd, greaterThan(scrollHandlerStart));
    final scrollHandler = source.substring(
      scrollHandlerStart,
      scrollHandlerEnd,
    );
    expect(scrollHandler, contains('notification is ScrollStartNotification'));
    expect(scrollHandler, contains('notification is UserScrollNotification'));
    expect(scrollHandler, contains('notification is ScrollEndNotification'));
    expect(
      scrollHandler,
      contains('if (_swipeDismissedForGesture) return false'),
    );
    expect(scrollHandler, contains('_swipeDismissedForGesture = false'));
    expect(source, contains('onNotification: _dismissSwipeActionsOnScroll'));
    expect(source, contains('controller: _listScrollController'));

    final tileStateStart = source.indexOf(
      'class _TodoTileState extends State<_TodoTile> {',
    );
    final tileStateEnd = source.indexOf(
      'class _TodoInlineSwipeButton extends StatelessWidget {',
      tileStateStart,
    );
    expect(tileStateStart, greaterThanOrEqualTo(0));
    expect(tileStateEnd, greaterThan(tileStateStart));
    final tileState = source.substring(tileStateStart, tileStateEnd);
    expect(
      tileState,
      contains(
        'widget.swipeDismissListenable?.addListener(_closeSwipeFromScroll)',
      ),
    );
    expect(
      tileState,
      contains(
        'widget.swipeDismissListenable?.removeListener(_closeSwipeFromScroll)',
      ),
    );
    expect(tileState, contains('void _closeSwipeFromScroll()'));
    expect(tileState, contains('_swipeOffset = 0;'));
    expect(tileState, contains('_dragging = false;'));
    expect(
      tileState,
      contains('widget.swipeDismissSerial != oldWidget.swipeDismissSerial'),
    );
    expect(
      source,
      matches(RegExp(r'swipeDismissListenable:\s*_swipeDismissSerial')),
    );
  });

  test('任务卡片按逾期完成临期状态和正常任务做视觉区分', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();

    expect(
      source,
      contains(
        'final stateColor = CompletionVisibilityPolicy.colorFor(visual)',
      ),
    );
    expect(source, contains('final visualAccentColor = switch (visual)'));
    expect(source, contains('final statusBackground = switch (visual)'));
    expect(source, contains('final statusBorder = switch (visual)'));
    expect(source, contains('TodoVisualState.completed'));
    expect(source, contains('TodoVisualState.overdue'));
    expect(source, contains('TodoVisualState.dueSoon'));
    expect(source, contains('Color.alphaBlend('));
    expect(source, contains('activeColor: visualAccentColor'));
    expect(
      source,
      contains('decoration: BoxDecoration(color: visualAccentColor)'),
    );
    expect(
      source,
      contains('final statusColor = isCompleted || isOverdue || isDueSoon'),
    );
    expect(
      source,
      contains('statusBackground = isCompleted || isOverdue || isDueSoon'),
    );
    expect(source, contains('TodoBoardUiCopy.badgeOverdue'));
    expect(source, contains('TodoBoardUiCopy.cardCompletedBadge'));
    expect(source, contains('TodoBoardUiCopy.badgeDueSoon'));
    _expectBilingualCopy(
      () => TodoBoardUiCopy.badgeOverdue,
      zh: '过期',
      en: 'Overdue',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.cardCompletedBadge,
      zh: '已完成',
      en: 'Completed',
    );
    _expectBilingualCopy(
      () => TodoBoardUiCopy.badgeDueSoon,
      zh: '临期',
      en: 'Due soon',
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
