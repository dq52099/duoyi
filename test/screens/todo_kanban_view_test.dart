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
