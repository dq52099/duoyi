import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/services/ai_service.dart';

TodoItem _todo(String id, String title) => TodoItem(
  id: id,
  title: title,
  quadrant: EisenhowerQuadrant.urgentImportant,
);

Future<void> _pumpScreen(
  WidgetTester tester,
  TodoProvider provider, {
  required ValueChanged<EisenhowerQuadrant> onCreateTodo,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TodoProvider>.value(value: provider),
        ChangeNotifierProvider(create: (_) => ShareProvider()),
        ChangeNotifierProvider(create: (_) => PreferencesProvider()),
        ChangeNotifierProvider(create: (_) => AiService()),
      ],
      child: MaterialApp(
        home: QuadrantListScreen(
          quadrant: EisenhowerQuadrant.urgentImportant,
          onCreateTodo: onCreateTodo,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('象限列表页展示该象限任务，FAB 携带本页象限触发新建回调', (tester) async {
    final provider = TodoProvider();
    await provider.addTodo(_todo('t1', '象限任务一'));
    await provider.addTodo(_todo('t2', '象限任务二'));
    var created = 0;
    final createdInQuadrant = <EisenhowerQuadrant>[];

    await _pumpScreen(tester, provider, onCreateTodo: (quadrant) {
      created++;
      createdInQuadrant.add(quadrant);
    });

    expect(find.text('象限任务一'), findsOneWidget);
    expect(find.text('象限任务二'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();

    expect(created, 1, reason: 'FAB 应触发主屏传入的新建入口');
    expect(
      createdInQuadrant.single,
      EisenhowerQuadrant.urgentImportant,
      reason: 'FAB 必须携带本页象限，新建待办默认落入该象限',
    );
  });

  testWidgets('批量入口：进入批量、选择、批量完成并回写 provider', (tester) async {
    final provider = TodoProvider();
    await provider.addTodo(_todo('t1', '象限任务一'));
    await provider.addTodo(_todo('t2', '象限任务二'));

    await _pumpScreen(tester, provider, onCreateTodo: (_) {});

    // 进入批量模式。
    await tester.tap(find.byIcon(Icons.checklist_rounded));
    await tester.pump();
    expect(find.text('已选择 0 项'), findsOneWidget);

    // 点按条目加入选择。
    await tester.tap(find.text('象限任务一'));
    await tester.pump();
    expect(find.text('已选择 1 项'), findsOneWidget);

    // 批量条点「完成」→ provider 回写完成状态，批量模式退出。
    await tester.tap(find.widgetWithText(FilledButton, '完成'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5)); // 让批量 SnackBar 的计时器走完

    final stored = provider.todos;
    expect(
      stored.firstWhere((t) => t.id == 't1').isCompleted,
      isTrue,
      reason: '批量完成后 t1 应已完结',
    );
    expect(stored.firstWhere((t) => t.id == 't2').isCompleted, isFalse);
    expect(find.text('已选择 1 项'), findsNothing, reason: '批量动作后应退出批量模式');
  });
}
