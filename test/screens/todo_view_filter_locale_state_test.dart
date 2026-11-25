import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/todo_board_ui_copy.dart';
import 'package:duoyi/models/todo.dart';
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

const _targetTag = '用户原始Tag';
const _targetList = '用户原始清单';
const _targetTitleA = '保留原始标题 A：整理路线图';
const _targetTitleB = '保留原始标题 B：检查依赖';
const _excludedTitle = '未筛选标题：更新运维记录';
const _targetQuadrant = EisenhowerQuadrant.urgentImportant;
const _targetIds = {'todo-filter-a', 'todo-filter-b'};
const _allIds = {..._targetIds, 'todo-filter-excluded'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocale previousLocale;

  setUp(() {
    previousLocale = I18n.current;
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() => I18n.setLocale(previousLocale));

  testWidgets(
    'Todo list view and quadrant filter retain their rows and raw task content through zh-en-zh',
    (tester) async {
      final harness = await _pumpTodoScreen(tester);
      final revisionBefore = harness.todos.revision;

      await _selectListViewAndQuadrantFilter(tester);
      _expectFilteredListState(tester);
      _expectOriginalTodoData(harness.todos);

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();

        _expectFilteredListState(tester);
        _expectOriginalTodoData(harness.todos);
        expect(harness.todos.revision, revisionBefore);
        expect(tester.takeException(), isNull);
      }

      await _removeScreenAndChangeLocale(tester, AppLocale.en);
    },
  );

  testWidgets(
    'vertical list scrolling closes an open swipe row without changing tasks',
    (tester) async {
      final harness = await _pumpTodoScreen(tester);
      for (var index = 0; index < 12; index++) {
        await harness.todos.addTodo(
          TodoItem(
            id: 'scroll-row-$index',
            title: 'Scroll row $index',
            quadrant: _targetQuadrant,
            listGroupName: _targetList,
          ),
        );
      }
      await _selectListViewAndQuadrantFilter(tester);
      final revisionBefore = harness.todos.revision;
      final row = find.byKey(const ValueKey('list-todo-todo-filter-a'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.drag(row, const Offset(-130, 0));
      await tester.pumpAndSettle();
      final deleteAction = find.descendant(
        of: row,
        matching: find.byKey(const ValueKey('todo_swipe_delete_button')),
      );
      expect(deleteAction, findsOneWidget);
      final list = find.byType(ReorderableListView);
      final scrollable = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(0));
      final offsetBefore = position.pixels;
      await tester.drag(list, const Offset(0, -32));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(offsetBefore));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text(_targetTitleA)),
        findsOneWidget,
      );
      expect(deleteAction, findsNothing);
      expect(harness.todos.revision, revisionBefore);
      expect(harness.todos.deleteCalls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Todo root retains selected batch IDs while delete confirmation copy follows zh-en-zh',
    (tester) async {
      final harness = await _pumpTodoScreen(tester);
      final revisionBefore = harness.todos.revision;
      await _selectListViewAndQuadrantFilter(tester);

      await tester.longPress(find.text(_targetTitleA));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_targetTitleB));
      await tester.pumpAndSettle();
      _expectBatchSelection(tester, 2);
      _expectTargetRowsVisible(tester);

      await _openBatchDeleteDialog(tester);
      _expectDeleteDialog(tester, 2);
      _expectBatchSelection(tester, 2);

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      _expectDeleteDialog(tester, 2);
      _expectBatchSelection(tester, 2);
      _expectTargetRowsVisible(tester);

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      _expectDeleteDialog(tester, 2);
      _expectBatchSelection(tester, 2);
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(TextButton, TodoBoardUiCopy.cancel));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      _expectBatchSelection(tester, 2);
      _expectOriginalTodoData(harness.todos);
      expect(harness.todos.deleteCalls, isEmpty);
      expect(harness.todos.revision, revisionBefore);

      await _openBatchDeleteDialog(tester);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      _expectDeleteDialog(tester, 2);
      _expectBatchSelection(tester, 2);

      await tester.tap(
        find.widgetWithText(FilledButton, TodoBoardUiCopy.delete),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(harness.todos.deleteCalls, hasLength(1));
      expect(harness.todos.deleteCalls.single, _targetIds);
      expect(harness.todos.todos.map((todo) => todo.id).toSet(), {
        'todo-filter-excluded',
      });
      expect(harness.todos.revision, greaterThan(revisionBefore));
      expect(tester.takeException(), isNull);

      await _removeScreenAndChangeLocale(tester, AppLocale.zh);
    },
  );
}

Future<_TodoHarness> _pumpTodoScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final todos = _RecordingTodoProvider();
  for (final todo in _fixtureTodos()) {
    await todos.addTodo(todo);
  }
  final habits = HabitProvider();
  final goals = GoalProvider();
  final theme = ThemeProvider();
  final ai = AiService();
  final share = ShareProvider();
  final auth = AuthProvider();
  final harness = _TodoHarness(
    todos: todos,
    habits: habits,
    goals: goals,
    theme: theme,
    ai: ai,
    share: share,
    auth: auth,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    harness.dispose();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TodoProvider>.value(value: todos),
        ChangeNotifierProvider<HabitProvider>.value(value: habits),
        ChangeNotifierProvider<GoalProvider>.value(value: goals),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<AiService>.value(value: ai),
        ChangeNotifierProvider<ShareProvider>.value(value: share),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: const MaterialApp(home: TodoScreen()),
    ),
  );
  await tester.pumpAndSettle();
  expect(
    tester.takeException(),
    isNull,
    reason: 'TodoScreen fixture must mount',
  );
  return harness;
}

List<TodoItem> _fixtureTodos() => [
  TodoItem(
    id: 'todo-filter-a',
    title: _targetTitleA,
    quadrant: _targetQuadrant,
    priority: TodoPriority.high,
    tags: [_targetTag],
    listGroupName: _targetList,
  ),
  TodoItem(
    id: 'todo-filter-b',
    title: _targetTitleB,
    quadrant: _targetQuadrant,
    priority: TodoPriority.high,
    tags: [_targetTag],
    listGroupName: _targetList,
  ),
  TodoItem(
    id: 'todo-filter-excluded',
    title: _excludedTitle,
    quadrant: EisenhowerQuadrant.notUrgentImportant,
    priority: TodoPriority.low,
    tags: ['other-user-tag'],
    listGroupName: '其他原始清单',
  ),
];

Future<void> _selectListViewAndQuadrantFilter(WidgetTester tester) async {
  final viewListText = find.text(TodoBoardUiCopy.viewList);
  final viewSwitcher = find.ancestor(
    of: viewListText,
    matching: find.byWidgetPredicate((widget) => widget is SegmentedButton),
  );
  expect(viewSwitcher, findsOneWidget);
  await tester.tap(find.descendant(of: viewSwitcher, matching: viewListText));
  await tester.pumpAndSettle();

  final quadrantFilter = find.byTooltip(TodoBoardUiCopy.filterQuadrant);
  await tester.ensureVisible(quadrantFilter);
  await tester.tap(quadrantFilter);
  await tester.pumpAndSettle();

  final quadrantOption = find.text(
    TodoBoardUiCopy.quadrantLabel(_targetQuadrant),
  );
  expect(quadrantOption, findsOneWidget);
  await tester.tap(quadrantOption);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void _expectFilteredListState(WidgetTester tester) {
  final viewListText = find.text(TodoBoardUiCopy.viewList);
  final viewSwitcher = find.ancestor(
    of: viewListText,
    matching: find.byWidgetPredicate((widget) => widget is SegmentedButton),
  );
  expect(viewSwitcher, findsOneWidget);
  final control = tester.widget<SegmentedButton<dynamic>>(viewSwitcher);
  final listSegment = control.segments.singleWhere(
    (segment) => (segment.label as Text).data == TodoBoardUiCopy.viewList,
  );
  expect(control.selected, {listSegment.value});
  expect(find.byType(ReorderableListView), findsOneWidget);
  expect(find.text(TodoBoardUiCopy.customViewTitle(2, 3)), findsOneWidget);
  expect(find.text(TodoBoardUiCopy.clear), findsOneWidget);
  expect(
    find.byTooltip(TodoBoardUiCopy.quadrantLabel(_targetQuadrant)),
    findsOneWidget,
  );
  expect(find.byTooltip(TodoBoardUiCopy.filterPriority), findsOneWidget);
  _expectTargetRowsVisible(tester);
}

void _expectTargetRowsVisible(WidgetTester tester) {
  expect(find.text(_targetTitleA), findsOneWidget);
  expect(find.text(_targetTitleB), findsOneWidget);
  expect(find.text(_excludedTitle), findsNothing);
  expect(find.text(_targetList), findsOneWidget);
  expect(find.text('#$_targetTag'), findsNWidgets(2));
}

void _expectOriginalTodoData(_RecordingTodoProvider todos) {
  final byId = {for (final todo in todos.todos) todo.id: todo};
  expect(byId.keys.toSet(), _allIds);
  for (final id in _targetIds) {
    final todo = byId[id]!;
    expect(todo.tags, [_targetTag]);
    expect(todo.listGroupName, _targetList);
  }
  expect(byId['todo-filter-a']!.title, _targetTitleA);
  expect(byId['todo-filter-b']!.title, _targetTitleB);
  expect(byId['todo-filter-excluded']!.title, _excludedTitle);
}

void _expectBatchSelection(WidgetTester tester, int count) {
  expect(find.text(TodoBoardUiCopy.batchModeSelected(count)), findsOneWidget);
  expect(find.text(TodoBoardUiCopy.batchSelected(count)), findsOneWidget);
  final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
  expect(checkboxes, hasLength(count));
  expect(
    checkboxes.where((checkbox) => checkbox.value == true),
    hasLength(count),
  );
}

Future<void> _openBatchDeleteDialog(WidgetTester tester) async {
  final deleteButton = find.widgetWithText(
    OutlinedButton,
    TodoBoardUiCopy.delete,
  );
  await tester.ensureVisible(deleteButton);
  await tester.tap(deleteButton);
  await tester.pumpAndSettle();
  expect(find.byType(Dialog), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void _expectDeleteDialog(WidgetTester tester, int count) {
  expect(find.text(TodoBoardUiCopy.deleteSelectedTasksTitle), findsOneWidget);
  expect(
    find.text(TodoBoardUiCopy.deleteSelectedTasksContent(count)),
    findsOneWidget,
  );
  expect(
    find.widgetWithText(TextButton, TodoBoardUiCopy.cancel),
    findsOneWidget,
  );
  expect(
    find.widgetWithText(FilledButton, TodoBoardUiCopy.delete),
    findsOneWidget,
  );
}

Future<void> _removeScreenAndChangeLocale(
  WidgetTester tester,
  AppLocale locale,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  I18n.setLocale(locale);
  await tester.pump();
  expect(tester.takeException(), isNull);
}

class _RecordingTodoProvider extends TodoProvider {
  final List<Set<String>> deleteCalls = [];

  @override
  Future<int> deleteTodos(Iterable<String> ids) {
    final snapshot = ids.toSet();
    deleteCalls.add(snapshot);
    return super.deleteTodos(snapshot);
  }
}

class _TodoHarness {
  final _RecordingTodoProvider todos;
  final HabitProvider habits;
  final GoalProvider goals;
  final ThemeProvider theme;
  final AiService ai;
  final ShareProvider share;
  final AuthProvider auth;

  const _TodoHarness({
    required this.todos,
    required this.habits,
    required this.goals,
    required this.theme,
    required this.ai,
    required this.share,
    required this.auth,
  });

  void dispose() {
    todos.dispose();
    habits.dispose();
    goals.dispose();
    theme.dispose();
    ai.dispose();
    share.dispose();
    auth.dispose();
  }
}
