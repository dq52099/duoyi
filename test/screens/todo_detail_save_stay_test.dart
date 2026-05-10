import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/models/todo.dart';
import 'package:duoyi/models/recurrence.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/todo_detail_screen.dart';

/// TodoDetailScreen "保存不返回" 路由快照测试（Task 9）。
///
/// Feature: app-alignment-overhaul
/// Property 18 (P18): ∀ TodoDetailScreen.save() 调用：Navigator 栈顶路由在
///                    调用前后保持同一路由实例（`ModalRoute.of(context).isCurrent`
///                    与 `settings.name` 均不变）。
///
/// Validates: Requirements 2.3, 2.4, 2.5
///
/// 用例形态：
/// - 在一个 `Navigator` 下从 `/home` push 一个 detail route；
/// - 在详情页中编辑标题并点 AppBar 的保存按钮；
/// - 断言：detail route 仍在栈顶、是 `isCurrent = true`、"已保存" snackbar 可见、
///   "home" 页面的入口 Text 不可见（说明没有 pop 回去）。
/// - 再覆盖几个关键状态转移：脏 → 返回 → 确认弹窗 → 取消/放弃。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  /// 构造一个带一条 TodoItem 的 TodoProvider。
  Future<(TodoProvider, TodoItem)> buildProviderWithOne() async {
    final provider = TodoProvider();
    final item = TodoItem(title: '原始标题', notes: '原始备注');
    await provider.addTodo(item);
    return (provider, item);
  }

  /// 构造一个包含 Home 入口 + TodoDetail 的 MaterialApp。
  /// Home 上的 Text("home-root") 与 Button 用来断言路由层级。
  Widget buildApp({
    required TodoProvider provider,
    required String todoId,
  }) {
    return ChangeNotifierProvider<TodoProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Builder(
          builder: (rootCtx) => Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('home-root'),
                  ElevatedButton(
                    onPressed: () => Navigator.of(rootCtx).push(
                      MaterialPageRoute(
                        settings: const RouteSettings(name: '/todo-detail'),
                        builder: (_) => TodoDetailScreen(todoId: todoId),
                      ),
                    ),
                    child: const Text('open-detail'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('P18 - save does not pop the route', () {
    testWidgets(
      '编辑标题 → 点 AppBar check：detail 路由仍在栈顶，显示已保存',
      (tester) async {
        final (provider, item) = await buildProviderWithOne();

        await tester.pumpWidget(
          buildApp(provider: provider, todoId: item.id),
        );
        await tester.pumpAndSettle();

        // Home 页应当可见，detail 尚未打开。
        expect(find.text('home-root'), findsOneWidget);
        expect(find.byType(TodoDetailScreen), findsNothing);

        // 打开详情页。
        await tester.tap(find.text('open-detail'));
        await tester.pumpAndSettle();
        expect(find.byType(TodoDetailScreen), findsOneWidget);

        // 快照保存前的栈顶路由信息。
        final BuildContext detailCtx =
            tester.element(find.byType(TodoDetailScreen));
        final ModalRoute<Object?>? beforeRoute = ModalRoute.of(detailCtx);
        expect(beforeRoute, isNotNull);
        expect(beforeRoute!.isCurrent, isTrue);
        expect(beforeRoute.settings.name, '/todo-detail');

        // 编辑标题，让页面进入 editing 状态。
        final titleField = find.widgetWithText(TextField, '任务名称');
        expect(titleField, findsOneWidget);
        await tester.enterText(titleField, '修改后的标题');
        await tester.pump();

        // 点 AppBar 的 check 按钮触发保存。
        final checkBtn = find.byIcon(Icons.check);
        expect(checkBtn, findsOneWidget);
        await tester.tap(checkBtn);
        // 等 updateTodo 的 Future、snackbar 弹出与可能的过渡动画。
        // 不用 pumpAndSettle，否则会一直等到 snackbar 1200ms 自行消失。
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 300));

        // 核心断言：detail 仍是当前路由，没有 pop。
        expect(
          find.byType(TodoDetailScreen),
          findsOneWidget,
          reason: 'save 不应触发 Navigator.pop，详情页必须仍在栈顶',
        );
        final BuildContext detailCtxAfter =
            tester.element(find.byType(TodoDetailScreen));
        final ModalRoute<Object?>? afterRoute = ModalRoute.of(detailCtxAfter);
        expect(afterRoute, isNotNull);
        expect(afterRoute!.isCurrent, isTrue,
            reason: 'save 之后栈顶路由仍应是 detail');
        expect(
          afterRoute.settings.name,
          beforeRoute.settings.name,
          reason: 'save 前后路由 name 不变',
        );
        expect(
          identical(afterRoute, beforeRoute),
          isTrue,
          reason: 'save 不应替换路由实例',
        );

        // home-root 不可见（证明没有退回到上一路由）。
        expect(find.text('home-root'), findsNothing);

        // inline banner "已保存" 可见。
        expect(
          find.text('已保存'),
          findsOneWidget,
          reason: 'save 成功后应以 SnackBar 展示"已保存"反馈',
        );

        // Provider 真的被写入了新标题。
        final stored = provider.todos.firstWhere((t) => t.id == item.id);
        expect(stored.title, '修改后的标题');
      },
    );

    testWidgets(
      'clean 状态点保存：路由也保持不变，仅提示"无未保存改动"',
      (tester) async {
        final (provider, item) = await buildProviderWithOne();

        await tester.pumpWidget(
          buildApp(provider: provider, todoId: item.id),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('open-detail'));
        await tester.pumpAndSettle();

        final BuildContext detailCtx =
            tester.element(find.byType(TodoDetailScreen));
        final ModalRoute<Object?>? before = ModalRoute.of(detailCtx);

        // 不做任何编辑，直接点 check。
        await tester.tap(find.byIcon(Icons.check));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(TodoDetailScreen), findsOneWidget);
        final BuildContext after =
            tester.element(find.byType(TodoDetailScreen));
        expect(ModalRoute.of(after)!.isCurrent, isTrue);
        expect(identical(ModalRoute.of(after), before), isTrue);
        expect(find.text('无未保存改动'), findsOneWidget);
      },
    );

    testWidgets(
      '设置重复与到期提醒后保存：provider 持久化新值',
      (tester) async {
        final (provider, item) = await buildProviderWithOne();

        await tester.pumpWidget(
          buildApp(provider: provider, todoId: item.id),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('open-detail'));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('重复'));
        await tester.tap(find.text('重复'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('每天'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, '保存'));
        await tester.pumpAndSettle();

        expect(find.text('每天'), findsOneWidget);

        await tester.ensureVisible(find.text('到期提醒'));
        await tester.tap(find.text('到期提醒'));
        await tester.pump();

        expect(find.textContaining('闹钟 ·'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.check));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 300));

        final stored = provider.todos.firstWhere((t) => t.id == item.id);
        expect(stored.recurrence.frequency, RecurrenceFrequency.daily);
        expect(stored.reminder.enabled, isTrue);
        expect(stored.reminder.hour, isNotNull);
        expect(stored.reminder.minute, isNotNull);
        // ignore: deprecated_member_use_from_same_package
        expect(stored.hasReminder, isTrue);
        // ignore: deprecated_member_use_from_same_package
        expect(stored.reminderAt, isNotNull);
      },
    );
  });

  group('Editing 下返回键弹出确认框', () {
    testWidgets(
      '取消 → 保持 editing，路由不 pop',
      (tester) async {
        final (provider, item) = await buildProviderWithOne();
        await tester.pumpWidget(
          buildApp(provider: provider, todoId: item.id),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('open-detail'));
        await tester.pumpAndSettle();

        // 制造脏状态。
        await tester.enterText(
            find.widgetWithText(TextField, '任务名称'), '改名中');
        await tester.pump();

        // 点 AppBar 的返回按钮。
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        expect(find.text('放弃未保存的修改？'), findsOneWidget);

        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();

        // 仍然停留在详情页。
        expect(find.byType(TodoDetailScreen), findsOneWidget);
        expect(find.text('home-root'), findsNothing);
      },
    );

    testWidgets(
      '放弃 → 路由 pop 回 home，改动未写入',
      (tester) async {
        final (provider, item) = await buildProviderWithOne();
        await tester.pumpWidget(
          buildApp(provider: provider, todoId: item.id),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('open-detail'));
        await tester.pumpAndSettle();

        await tester.enterText(
            find.widgetWithText(TextField, '任务名称'), '即将被放弃');
        await tester.pump();

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        await tester.tap(find.text('放弃'));
        await tester.pumpAndSettle();

        // 已经回到 home。
        expect(find.text('home-root'), findsOneWidget);
        expect(find.byType(TodoDetailScreen), findsNothing);

        // Provider 中仍是原始标题。
        final stored = provider.todos.firstWhere((t) => t.id == item.id);
        expect(stored.title, '原始标题');
      },
    );
  });
}
