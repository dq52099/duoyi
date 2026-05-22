import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('任务页提供批量操作入口和选择状态', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();

    expect(source, contains('bool _batchMode = false'));
    expect(source, contains('final Set<String> _selectedTodoIds'));
    expect(source, contains('_enterBatchMode({String? todoId'));
    expect(source, contains('switchToList: true'));
    expect(source, contains("tooltip: '批量操作'"));
    expect(source, contains("'已选择 \${_selectedTodoIds.length} 项'"));
    expect(source, contains('_selectAllVisible(editableVisibleIds)'));
    expect(source, contains('Icons.select_all_outlined'));
    expect(source, contains('Icons.deselect_outlined'));
  });

  test('批量模式复用当前自定义视图并限制为可编辑任务', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();

    expect(source, contains('filteredTodos'));
    expect(source, contains('shareProvider.canEdit(todo.workspaceId)'));
    expect(source, contains('editableVisibleIds'));
    expect(source, contains('selectedTodoIds.contains'));
    expect(source, contains('onToggleSelection(todo.id)'));
    expect(source, contains('onLongPress: canEdit'));
    expect(source, contains('if (batchMode) return content;'));
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
    expect(source, contains("label: const Text('完成')"));
    expect(source, contains("label: const Text('恢复')"));
    expect(source, contains("label: const Text('删除')"));
  });

  test('任务页调用 provider 批量写接口', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();

    expect(source, contains('.completeTodos('));
    expect(source, contains('.reopenTodos('));
    expect(source, contains('.updateTodosQuadrant('));
    expect(source, contains('.updateTodosPriority('));
    expect(source, contains('.deleteTodos('));
    expect(source, contains('删除所选任务'));
    expect(source, contains('已删除 \$count 个任务'));
  });

  test('任务列表支持清单内拖拽排序且不抢占批量选择长按', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();

    expect(source, contains('ReorderableListView.builder'));
    expect(source, contains('buildDefaultDragHandles: false'));
    expect(source, contains('ReorderableDragStartListener'));
    expect(source, contains("message: '拖拽排序'"));
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
}
