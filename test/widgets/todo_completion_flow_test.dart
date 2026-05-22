import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/widgets/todo_completion_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('completion flow can skip manual duration and keep auto record', (
    tester,
  ) async {
    final todoProvider = TodoProvider();
    final timeAuditProvider = TimeAuditProvider();
    final todo = TodoItem(
      id: 'todo-flow-1',
      title: '整理周计划',
      date: DateTime(2026, 5, 19, 9),
      timeTargetSeconds: 1800,
    );
    await todoProvider.addTodo(todo);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
          ChangeNotifierProvider<TimeAuditProvider>.value(
            value: timeAuditProvider,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () =>
                    completeTodoWithOptionalTimeRecord(context, todo),
                child: const Text('完成任务'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('完成任务'));
    await tester.pumpAndSettle();
    expect(find.text('确认完成任务'), findsOneWidget);

    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(find.text('记录耗时'), findsOneWidget);

    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();

    expect(todoProvider.todos.single.isCompleted, isTrue);
    expect(timeAuditProvider.entries, hasLength(1));
    expect(timeAuditProvider.entries.single.category, TimeEntryCategory.todo);
    expect(timeAuditProvider.entries.single.durationSeconds, 1800);
  });
}
