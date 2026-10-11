import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/widgets/calendar_event_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'open editor preserves user input and all-day dates on locale change',
    (tester) async {
      final provider = CalendarProvider();
      await tester.pumpWidget(_editorApp(provider));
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '日程标题'),
        '用户标题 New Event',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '备注'),
        '用户备注 Notes',
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(find.text('New Event'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Event title'), findsOneWidget);
      expect(find.text('用户标题 New Event'), findsOneWidget);
      expect(find.text('用户备注 Notes'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final saved = provider.localEvents.single;
      expect(saved.title, '用户标题 New Event');
      expect(saved.note, '用户备注 Notes');
      expect(saved.date, DateTime(2026, 5, 18));
      expect(saved.endDate, DateTime(2026, 5, 19));
      expect(saved.time, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'nested date picker heading switches language with selection intact',
    (tester) async {
      final provider = CalendarProvider();
      await tester.pumpWidget(_editorApp(provider));
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始日期').first);
      await tester.pumpAndSettle();
      expect(find.text('开始日期'), findsWidgets);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(find.text('开始日期'), findsNothing);
      expect(find.text('Start date'), findsWidgets);
      expect(tester.takeException(), isNull);
      final cancel = find
          .widgetWithText(TextButton, I18n.tr('action.cancel'))
          .last;
      await tester.ensureVisible(cancel);
      await tester.pumpAndSettle();
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(find.text('New Event'), findsOneWidget);
    },
  );

  testWidgets('editor from the old account cannot save to the new account', (
    tester,
  ) async {
    final provider = CalendarProvider();
    await tester.pumpWidget(_editorApp(provider));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '日程标题'), '旧账号的输入');
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(provider.localEvents, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mounted old detail sheet cannot delete a colliding new-account task',
    (tester) async {
      final provider = TodoProvider();
      final old = TodoItem(
        id: 'same-task-id',
        title: '旧账号标题',
        date: DateTime(2026, 5, 18),
      );
      await provider.addTodo(old);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TodoProvider>.value(value: provider),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CalendarEventSheet(
                event: CalendarEvent(
                  id: 'todo_same-task-id',
                  sourceId: old.id,
                  title: old.title,
                  date: old.date,
                  type: CalendarEventType.todo,
                  color: Colors.blue,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('todos');
      provider.resetLocalState();
      await provider.addTodo(
        TodoItem(id: old.id, title: '新账号标题', date: old.date),
      );
      await tester.pumpAndSettle();
      final delete = find.text('删除').hitTestable();
      if (delete.evaluate().isNotEmpty) {
        await tester.tap(delete);
        await tester.pumpAndSettle();
      }
      expect(provider.todos.single.title, '新账号标题');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('viewer detail keeps navigation and disables mutation actions', (
    tester,
  ) async {
    final provider = TodoProvider();
    final todo = TodoItem(
      id: 'shared-task',
      title: '只读共享任务',
      date: DateTime(2026, 5, 18),
      workspaceId: 'readonly-space',
    );
    await provider.addTodo(todo);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TodoProvider>.value(value: provider),
          ChangeNotifierProvider<ShareProvider>(create: (_) => _ViewerShares()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CalendarEventSheet(
              event: CalendarEvent(
                id: 'todo_shared-task',
                sourceId: todo.id,
                workspaceId: todo.workspaceId,
                title: todo.title,
                date: todo.date,
                type: CalendarEventType.todo,
                color: Colors.blue,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['删除', '编辑', '改期', '完成', '调整时间']) {
      final button = find.widgetWithText(FilledButton, label);
      expect(button, findsOneWidget);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
    }
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '跳转详情'))
          .onPressed,
      isNotNull,
    );
    expect(find.text('跳转详情'), findsOneWidget);
    expect(provider.todos.single.isCompleted, isFalse);
  });

  testWidgets(
    'sheet opening keeps the generation from before its route builds',
    (tester) async {
      final provider = TodoProvider();
      final old = TodoItem(
        id: 'route-opening-collision',
        title: 'Old account task',
        date: DateTime(2026, 5, 18),
      );
      await provider.addTodo(old);
      late BuildContext rootContext;
      await tester.pumpWidget(
        ChangeNotifierProvider<TodoProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  rootContext = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      final sheet = showCalendarEventSheet(
        rootContext,
        CalendarEvent(
          id: 'todo_${old.id}',
          sourceId: old.id,
          title: old.title,
          date: old.date,
          type: CalendarEventType.todo,
          color: Colors.blue,
        ),
      );
      // No frame has built the sheet yet. Its event still belongs to the
      // generation at the show call even when the next frame belongs to B.
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      await (await SharedPreferences.getInstance()).remove('todos');
      provider.resetLocalState();
      await provider.addTodo(
        TodoItem(id: old.id, title: 'New account task', date: old.date),
      );
      await tester.pumpAndSettle();
      final delete = find.widgetWithText(FilledButton, '删除');
      expect(delete, findsOneWidget);
      expect(tester.widget<FilledButton>(delete).onPressed, isNull);
      expect(provider.todos.single.title, 'New account task');
      expect(tester.takeException(), isNull);
      Navigator.of(rootContext).pop();
      await tester.pumpAndSettle();
      await sheet;
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    },
  );
}

Widget _editorApp(CalendarProvider provider) =>
    ChangeNotifierProvider<CalendarProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showLocalCalendarEventEditor(
                context,
                initialDate: DateTime(2026, 5, 18),
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );

class _ViewerShares extends ShareProvider {
  @override
  bool canEdit(String? workspaceId) => workspaceId == null;
}
