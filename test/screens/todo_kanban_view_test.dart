import 'dart:io';

import 'package:duoyi/models/todo.dart';
import 'package:duoyi/core/todo_kanban.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('快速创建待办成功后显示本机保存和云同步状态', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();
    expect(source, contains("import '../providers/cloud_sync_provider.dart';"));
    expect(source, contains('String _localSaveSyncMessage('));
    expect(source, contains('.read<CloudSyncProvider>()'));
    expect(source, contains('.localSaveSyncMessage('));

    final dialogStart = source.indexOf('void _showAddDialog()');
    final dialogEnd = source.indexOf(
      'Widget build(BuildContext context)',
      dialogStart,
    );
    expect(dialogStart, greaterThanOrEqualTo(0));
    expect(dialogEnd, greaterThan(dialogStart));
    final dialog = source.substring(dialogStart, dialogEnd);

    expect(dialog, contains('addTodoWithResult('));
    expect(dialog, contains('reminderSyncIssue != null'));
    expect(dialog, contains('_localSaveSyncMessage('));
    expect(dialog, contains("localSavedText: '待办已保存到本机'"));
  });

  testWidgets('TodoScreen can switch to kanban view', (tester) async {
    final todoProvider = TodoProvider();
    await todoProvider.addTodo(
      TodoItem(
        title: '准备汇报',
        quadrant: EisenhowerQuadrant.urgentImportant,
        priority: TodoPriority.high,
        dueDate: DateTime(2026, 5, 18, 9),
        subtasks: [Subtask(title: '整理数据')],
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
          ChangeNotifierProvider(create: (_) => HabitProvider()),
          ChangeNotifierProvider(create: (_) => GoalProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AiService()),
          ChangeNotifierProvider(create: (_) => ShareProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
        ],
        child: const MaterialApp(home: TodoScreen()),
      ),
    );

    expect(find.text('四象限'), findsOneWidget);
    expect(find.text('看板'), findsOneWidget);

    await tester.tap(find.text('看板'));
    await tester.pumpAndSettle();

    expect(find.text('待处理'), findsOneWidget);
    expect(find.text('进行中'), findsOneWidget);
    expect(find.text('已完成'), findsWidgets);
    expect(find.text('准备汇报'), findsOneWidget);
    expect(find.text('高'), findsOneWidget);
    expect(find.text('0/1 子任务'), findsOneWidget);

    await tester.tap(find.byTooltip('移动到'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进行中').last);
    await tester.pumpAndSettle();

    expect(
      todoProvider.todos.single.kanbanColumnId,
      defaultKanbanInProgressColumnId,
    );
    expect(find.text('准备汇报'), findsOneWidget);
  });

  testWidgets('TodoScreen surfaces cloud sync submit failures', (tester) async {
    final todoProvider = TodoProvider();
    await todoProvider.addTodo(TodoItem(title: '需要同步的待办'));
    todoProvider.lastCloudSyncError = '服务器暂时不可用';

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
          ChangeNotifierProvider(create: (_) => HabitProvider()),
          ChangeNotifierProvider(create: (_) => GoalProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AiService()),
          ChangeNotifierProvider(create: (_) => ShareProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
        ],
        child: const MaterialApp(home: TodoScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('本机待办已保存，但服务器同步失败'), findsOneWidget);
    expect(find.textContaining('服务器暂时不可用'), findsOneWidget);

    todoProvider.lastCloudSyncError = null;
    await tester.pumpAndSettle();

    expect(find.textContaining('本机待办已保存，但服务器同步失败'), findsNothing);
  });

  testWidgets('TodoScreen surfaces pending cloud sync status', (tester) async {
    final todoProvider = TodoProvider();
    await todoProvider.addTodo(TodoItem(title: '离线保存的待办'));
    todoProvider.cloudSyncNotice = const TodoCloudSyncNotice(
      message: '未登录云同步账号。',
      level: TodoCloudSyncNoticeLevel.warning,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
          ChangeNotifierProvider(create: (_) => HabitProvider()),
          ChangeNotifierProvider(create: (_) => GoalProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AiService()),
          ChangeNotifierProvider(create: (_) => ShareProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
        ],
        child: const MaterialApp(home: TodoScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('服务器同步暂未完成'), findsOneWidget);
    expect(find.textContaining('未登录云同步账号'), findsOneWidget);

    todoProvider.cloudSyncNotice = const TodoCloudSyncNotice(
      message: '远端有更新，当前同步完成后会继续拉取。',
      level: TodoCloudSyncNoticeLevel.info,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('云同步正在排队'), findsOneWidget);
    expect(find.textContaining('远端有更新'), findsOneWidget);
  });

  testWidgets('TodoScreen restores kanban grouping preference', (tester) async {
    final config = TodoKanbanBoardConfig.defaults().copyWith(
      groupMode: TodoKanbanGroupMode.priority,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      todoKanbanColumnsPrefsKey: config.encode(),
    });

    final todoProvider = TodoProvider();
    await todoProvider.addTodo(
      TodoItem(
        title: '高优先任务',
        priority: TodoPriority.high,
        kanbanColumnId: defaultKanbanPendingColumnId,
      ),
    );
    await todoProvider.addTodo(
      TodoItem(
        title: '低优先任务',
        priority: TodoPriority.low,
        kanbanColumnId: defaultKanbanPendingColumnId,
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
          ChangeNotifierProvider(create: (_) => HabitProvider()),
          ChangeNotifierProvider(create: (_) => GoalProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AiService()),
          ChangeNotifierProvider(create: (_) => ShareProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
        ],
        child: const MaterialApp(home: TodoScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('看板'));
    await tester.pumpAndSettle();

    expect(find.text('看板分组：按优先级'), findsOneWidget);
    expect(find.text('高'), findsWidgets);
    expect(find.text('低'), findsWidgets);
    expect(find.text('高优先任务'), findsOneWidget);
    expect(find.text('低优先任务'), findsOneWidget);
  });

  testWidgets('TodoScreen left swipe reveals completion and delete actions', (
    tester,
  ) async {
    final todoProvider = TodoProvider();
    await todoProvider.addTodo(
      TodoItem(title: '左滑任务', quadrant: EisenhowerQuadrant.urgentImportant),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
          ChangeNotifierProvider(create: (_) => HabitProvider()),
          ChangeNotifierProvider(create: (_) => GoalProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AiService()),
          ChangeNotifierProvider(create: (_) => ShareProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
        ],
        child: const MaterialApp(home: TodoScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('列表'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('todo_swipe_detail_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('todo_swipe_complete_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('todo_swipe_delete_button')),
      findsNothing,
    );

    await tester.drag(find.text('左滑任务'), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('todo_swipe_detail_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('todo_swipe_complete_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('todo_swipe_delete_button')),
      findsNothing,
    );

    await tester.drag(find.text('左滑任务'), const Offset(-160, 0));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('todo_swipe_detail_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('todo_swipe_complete_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('todo_swipe_delete_button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('todo_swipe_delete_button')));
    await tester.pumpAndSettle();
    expect(find.text('删除任务？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(todoProvider.todos.single.title, '左滑任务');

    await tester.drag(find.text('左滑任务'), const Offset(-160, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('todo_swipe_delete_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(todoProvider.todos, isEmpty);
    expect(find.text('左滑任务'), findsNothing);
  });

  testWidgets('TodoScreen scrolling closes open swipe actions', (tester) async {
    final previousSize = tester.view.physicalSize;
    final previousDevicePixelRatio = tester.view.devicePixelRatio;
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.physicalSize = previousSize;
      tester.view.devicePixelRatio = previousDevicePixelRatio;
    });

    final todoProvider = TodoProvider();
    for (var i = 0; i < 18; i++) {
      await todoProvider.addTodo(
        TodoItem(title: '滑动$i', quadrant: EisenhowerQuadrant.urgentImportant),
      );
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
          ChangeNotifierProvider(create: (_) => HabitProvider()),
          ChangeNotifierProvider(create: (_) => GoalProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AiService()),
          ChangeNotifierProvider(create: (_) => ShareProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
        ],
        child: const MaterialApp(home: TodoScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('列表'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('滑动0'), const Offset(-160, 0));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('todo_swipe_complete_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('todo_swipe_delete_button')),
      findsOneWidget,
    );

    final verticalScrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
      description: 'vertical Todo list scrollable',
    );
    expect(verticalScrollable, findsOneWidget);
    final verticalScrollState = tester.state<ScrollableState>(
      verticalScrollable,
    );
    final initialOffset = verticalScrollState.position.pixels;

    await tester.drag(verticalScrollable, const Offset(0, -260));
    await tester.pumpAndSettle();

    expect(
      verticalScrollState.position.pixels,
      greaterThan(initialOffset),
      reason: 'the vertical Todo list must actually scroll',
    );
    expect(
      find.byKey(const ValueKey('todo_swipe_complete_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('todo_swipe_delete_button')),
      findsNothing,
    );
  });

  testWidgets('TodoScreen kanban card left swipe can delete task', (
    tester,
  ) async {
    final todoProvider = TodoProvider();
    await todoProvider.addTodo(
      TodoItem(title: '看板左滑删除', kanbanColumnId: defaultKanbanPendingColumnId),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
          ChangeNotifierProvider(create: (_) => HabitProvider()),
          ChangeNotifierProvider(create: (_) => GoalProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AiService()),
          ChangeNotifierProvider(create: (_) => ShareProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
        ],
        child: const MaterialApp(home: TodoScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('看板'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('todo_swipe_detail_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('todo_swipe_complete_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('todo_swipe_delete_button')),
      findsNothing,
    );

    await tester.drag(find.text('看板左滑删除'), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('todo_swipe_detail_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('todo_swipe_complete_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('todo_swipe_delete_button')),
      findsNothing,
    );

    await tester.drag(find.text('看板左滑删除'), const Offset(-160, 0));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('todo_swipe_detail_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('todo_swipe_complete_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('todo_swipe_delete_button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('todo_swipe_delete_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(todoProvider.todos, isEmpty);
    expect(find.text('看板左滑删除'), findsNothing);
  });
}
