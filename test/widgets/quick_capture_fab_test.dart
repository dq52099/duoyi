import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/widgets/quick_capture_fab.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAiService extends AiService {
  @override
  bool get enabled => true;

  @override
  Future<List<String>> breakDownTask(String goal) async {
    return List<String>.generate(14, (i) => '子任务 ${i + 1}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('AI quick todo keeps create button visible with many subtasks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final todoProvider = TodoProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
          ChangeNotifierProvider<NoteProvider>(create: (_) => NoteProvider()),
          ChangeNotifierProvider<AiService>(create: (_) => _FakeAiService()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(),
            floatingActionButton: QuickCaptureFab(),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(FloatingActionButton).last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithIcon(FloatingActionButton, Icons.auto_awesome),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '准备周五汇报');
    await tester.tap(find.widgetWithText(TextButton, '生成'));
    await tester.pumpAndSettle();

    expect(find.text('子任务 1'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '创建'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pumpAndSettle();

    expect(todoProvider.todos, hasLength(1));
    final todo = todoProvider.todos.single;
    final now = DateTime.now();
    expect(todo.title, '准备周五汇报');
    expect(DateUtils.isSameDay(todo.date, now), isTrue);
    expect(todo.subtasks, hasLength(14));
    expect(todo.subtasks.first.title, '子任务 1');
  });

  test('AI quick todo reuses smart date parsing before attaching subtasks', () {
    final source = File(
      'lib/widgets/quick_capture_fab.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> _quickAiTodo');
    final end = source.indexOf('Future<void> _quickNote', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final method = source.substring(start, end);

    expect(method, contains('SmartTodoDraftBuilder.fromText'));
    expect(method, contains('draft.toTodo'));
    expect(method, contains('subtasks: subtasks.map'));
  });
}
