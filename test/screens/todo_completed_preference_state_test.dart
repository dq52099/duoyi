import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/core/todo_board_ui_copy.dart';
import 'package:duoyi/core/todo_filters.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';

const _activeId = 'completed-preference-active';
const _completedId = 'completed-preference-completed';
const _archivedId = 'completed-preference-archived';
const _activeTitle = 'Preference fixture active task';
const _completedTitle = 'Preference fixture completed task';
const _archivedTitle = 'Preference fixture archived task';

late AppLocale _previousLocale;
late Future<String?> Function()? _previousTimezoneReader;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _previousLocale = I18n.current;
    _previousTimezoneReader = LocalTimezoneResolver.debugSystemTimeZoneReader;
    I18n.setLocale(AppLocale.zh);
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalTimezoneResolver.applyApplicationTimeZone('system');
  });

  tearDown(() async {
    await AccountPreferenceWrites.drain();
    LocalTimezoneResolver.debugSystemTimeZoneReader = _previousTimezoneReader;
    I18n.setLocale(_previousLocale);
  });

  testWidgets('built-in group and completed badge follow the live locale', (
    tester,
  ) async {
    await _pumpTodoScreen(tester, showCompletedTodos: true);
    await _selectView(tester, TodoBoardUiCopy.viewList);
    expect(find.text('未分组'), findsOneWidget);
    expect(find.text(TodoBoardUiCopy.cardCompletedBadge), findsWidgets);
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(find.text('Ungrouped'), findsOneWidget);
    expect(find.text('未分组'), findsNothing);
    expect(find.text(TodoBoardUiCopy.cardCompletedBadge), findsWidgets);
    expect(find.text('已完成'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a literal user group named 未分组 stays unchanged in English', (
    tester,
  ) async {
    await _pumpTodoScreen(tester, fixtureGroupName: '未分组');
    await _selectView(tester, TodoBoardUiCopy.viewList);
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(find.text('未分组'), findsOneWidget);
    expect(find.text('Ungrouped'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Matrix, List, and Kanban refresh completed visibility without changing todos',
    (tester) async {
      final harness = await _pumpTodoScreen(tester);
      final revisionBefore = harness.todos.revision;

      _expectTodoVisibility(tester, completedVisible: false);
      await _setShowCompletedTodos(tester, harness.preferences!, true);
      _expectTodoVisibility(tester, completedVisible: true);
      expect(harness.todos.revision, revisionBefore);

      await _setShowCompletedTodos(tester, harness.preferences!, false);
      _expectTodoVisibility(tester, completedVisible: false);
      expect(harness.todos.revision, revisionBefore);

      await _selectView(tester, TodoBoardUiCopy.viewList);
      _expectTodoVisibility(tester, completedVisible: false);
      await _setShowCompletedTodos(tester, harness.preferences!, true);
      _expectTodoVisibility(tester, completedVisible: true);
      expect(harness.todos.revision, revisionBefore);

      await _setShowCompletedTodos(tester, harness.preferences!, false);
      _expectTodoVisibility(tester, completedVisible: false);
      expect(harness.todos.revision, revisionBefore);

      await _selectView(tester, TodoBoardUiCopy.viewKanban);
      _expectTodoVisibility(tester, completedVisible: false);
      // A phone builds the horizontal board lazily. Reveal the done column
      // before checking its rows, so absence is not mistaken for filtering.
      final board = find.byWidgetPredicate(
        (widget) =>
            widget is ListView && widget.scrollDirection == Axis.horizontal,
      );
      expect(board, findsOneWidget);
      await tester.drag(board, const Offset(-700, 0));
      await tester.pumpAndSettle();
      await _setShowCompletedTodos(tester, harness.preferences!, true);
      expect(find.text(_completedTitle), findsOneWidget);
      expect(find.text(_archivedTitle), findsNothing);
      expect(harness.todos.revision, revisionBefore);

      await _setShowCompletedTodos(tester, harness.preferences!, false);
      expect(find.text(_completedTitle), findsNothing);
      expect(find.text(_archivedTitle), findsNothing);
      expect(harness.todos.revision, revisionBefore);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'TodoScreen archive chip shows history without changing defaults',
    (tester) async {
      final harness = await _pumpTodoScreen(tester);
      final revision = harness.todos.revision;
      await _selectView(tester, TodoBoardUiCopy.viewList);
      final history = find.widgetWithText(
        FilterChip,
        TodoBoardUiCopy.filterIncludeArchived,
      );
      await tester.ensureVisible(history);
      await tester.pumpAndSettle();
      await tester.tap(history);
      await tester.pumpAndSettle();
      expect(find.text(_activeTitle), findsOneWidget);
      expect(find.text(_completedTitle), findsOneWidget);
      expect(find.text(_archivedTitle), findsOneWidget);
      await _captureTodoPreferences(tester, 'todo-history-390-zh');
      final completed = find.widgetWithText(
        FilterChip,
        TodoBoardUiCopy.filterCompleted,
      );
      await tester.ensureVisible(completed);
      await tester.pumpAndSettle();
      await tester.tap(completed);
      await tester.pumpAndSettle();
      expect(find.text(_activeTitle), findsNothing);
      expect(find.text(_completedTitle), findsOneWidget);
      expect(find.text(_archivedTitle), findsOneWidget);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(find.text('Include archived'), findsOneWidget);
      expect(find.text(_archivedTitle), findsOneWidget);
      expect(harness.todos.revision, revision);
      expect(harness.preferences!.showCompletedTodos, isFalse);
      await _captureTodoPreferences(tester, 'todo-completed-history-390-en');
      await tester.ensureVisible(
        find.widgetWithText(FilterChip, TodoBoardUiCopy.filterIncludeArchived),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilterChip, TodoBoardUiCopy.filterIncludeArchived),
      );
      await tester.pumpAndSettle();
      expect(find.text(_completedTitle), findsOneWidget);
      expect(find.text(_archivedTitle), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('TodoScreen remains compatible without PreferencesProvider', (
    tester,
  ) async {
    await _pumpTodoScreen(tester, includePreferences: false);

    _expectTodoVisibility(tester, completedVisible: true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explicit Completed filter works while the preference is off', (
    tester,
  ) async {
    final harness = await _pumpTodoScreen(tester);
    final revisionBefore = harness.todos.revision;

    await _selectView(tester, TodoBoardUiCopy.viewList);
    final completedFilter = find.text(TodoBoardUiCopy.filterCompleted);
    await tester.ensureVisible(completedFilter);
    await tester.tap(completedFilter);
    await tester.pumpAndSettle();

    expect(find.text(_activeTitle), findsNothing);
    expect(find.text(_completedTitle), findsOneWidget);
    expect(find.text(_archivedTitle), findsNothing);
    expect(harness.todos.revision, revisionBefore);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Quadrant uses the same default and explicit completed visibility',
    (tester) async {
      final harness = await _pumpTodoScreen(tester);
      final revisionBefore = harness.todos.revision;

      _expectTodoVisibility(tester, completedVisible: false);
      await tester.tap(find.text(harness.theme.brand.strings.quadrantQ1Label));
      await tester.pumpAndSettle();

      _expectTodoVisibility(tester, completedVisible: false);
      await _setShowCompletedTodos(tester, harness.preferences!, true);
      _expectTodoVisibility(tester, completedVisible: true);
      expect(harness.todos.revision, revisionBefore);

      await _setShowCompletedTodos(tester, harness.preferences!, false);
      _expectTodoVisibility(tester, completedVisible: false);
      expect(harness.todos.revision, revisionBefore);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hidden completed selections are excluded from batch deletion', (
    tester,
  ) async {
    final harness = await _pumpTodoScreen(tester, showCompletedTodos: true);
    final revisionBefore = harness.todos.revision;

    await _selectView(tester, TodoBoardUiCopy.viewList);
    await tester.longPress(find.text(_activeTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_completedTitle));
    await tester.pumpAndSettle();

    await _setShowCompletedTodos(tester, harness.preferences!, false);
    expect(find.text(_completedTitle), findsNothing);
    expect(find.text(_activeTitle), findsOneWidget);
    expect(harness.todos.revision, revisionBefore);

    final deleteButton = find.widgetWithText(
      OutlinedButton,
      TodoBoardUiCopy.delete,
    );
    await tester.ensureVisible(deleteButton);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, TodoBoardUiCopy.delete));
    await tester.pumpAndSettle();

    expect(harness.todos.deleteCalls, hasLength(1));
    expect(harness.todos.deleteCalls.single, {_activeId});
    expect(harness.todos.todos.map((todo) => todo.id), contains(_completedId));
    expect(harness.todos.todos.map((todo) => todo.id), contains(_archivedId));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Quadrant keeps an explicit Completed plus Archived filter when default is off',
    (tester) async {
      final harness = await _pumpTodoScreen(
        tester,
        home: QuadrantListScreen(
          quadrant: EisenhowerQuadrant.urgentImportant,
          filter: const TodoFilterState(
            completion: TodoCompletionFilter.completed,
            includeArchived: true,
          ),
        ),
      );
      final revisionBefore = harness.todos.revision;

      expect(find.text(_activeTitle), findsNothing);
      expect(find.text(_completedTitle), findsOneWidget);
      expect(find.text(_archivedTitle), findsOneWidget);
      expect(harness.preferences!.showCompletedTodos, isFalse);
      expect(harness.todos.revision, revisionBefore);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Quadrant batch deletion excludes a completed task hidden by the preference',
    (tester) async {
      final harness = await _pumpTodoScreen(tester, showCompletedTodos: true);
      final revisionBefore = harness.todos.revision;

      await tester.tap(find.text(harness.theme.brand.strings.quadrantQ1Label));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(TodoBoardUiCopy.batchManageTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_activeTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_completedTitle));
      await tester.pumpAndSettle();

      await _setShowCompletedTodos(tester, harness.preferences!, false);
      expect(find.text(_activeTitle), findsOneWidget);
      expect(find.text(_completedTitle), findsNothing);
      expect(harness.todos.revision, revisionBefore);

      final deleteButton = find.widgetWithText(
        OutlinedButton,
        TodoBoardUiCopy.delete,
      );
      await tester.ensureVisible(deleteButton);
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, TodoBoardUiCopy.delete),
      );
      await tester.pumpAndSettle();

      expect(harness.todos.deleteCalls, hasLength(1));
      expect(harness.todos.deleteCalls.single, {_activeId});
      expect(
        harness.todos.todos.map((todo) => todo.id),
        contains(_completedId),
      );
      expect(harness.todos.todos.map((todo) => todo.id), contains(_archivedId));
      expect(tester.takeException(), isNull);
    },
  );
}

Future<_TodoHarness> _pumpTodoScreen(
  WidgetTester tester, {
  bool includePreferences = true,
  bool showCompletedTodos = false,
  String? fixtureGroupName,
  Widget? home,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(<String, Object>{
    if (includePreferences) 'pref_show_completed_todos': showCompletedTodos,
  });

  final todos = _RecordingTodoProvider();
  for (final todo in _fixtureTodos()) {
    await todos.addTodo(
      fixtureGroupName == null
          ? todo
          : todo.copyWith(listGroupName: fixtureGroupName),
    );
  }
  final preferences = includePreferences ? PreferencesProvider() : null;
  await preferences?.loadFromStorage();
  final habits = HabitProvider();
  final goals = GoalProvider();
  final theme = ThemeProvider();
  if (_screenshotDirectory != null) {
    await tester.runAsync(() async {
      await loadWidgetPolishScreenshotFonts();
      final bytes = File(
        'assets/fonts/DroidSansFallbackFull.ttf',
      ).readAsBytesSync();
      await (FontLoader(
        'DroidSansFallbackFull',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      await (FontLoader(
        'PingFang SC',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      final latin = File('assets/fonts/DejaVuSans.ttf').readAsBytesSync();
      for (final family in ['sans-serif', 'DejaVu Sans']) {
        await (FontLoader(
          family,
        )..addFont(Future.value(ByteData.sublistView(latin)))).load();
      }
      await PaintingBinding.instance.handleSystemMessage(<String, dynamic>{
        'type': 'fontsChange',
      });
    });
  }
  final ai = AiService();
  final share = ShareProvider();
  final auth = AuthProvider();
  final harness = _TodoHarness(
    todos: todos,
    preferences: preferences,
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
    await AccountPreferenceWrites.drain();
    await tester.pump();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TodoProvider>.value(value: todos),
        if (preferences != null)
          ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
        ChangeNotifierProvider<HabitProvider>.value(value: habits),
        ChangeNotifierProvider<GoalProvider>.value(value: goals),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<AiService>.value(value: ai),
        ChangeNotifierProvider<ShareProvider>.value(value: share),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: MaterialApp(
        theme: _screenshotDirectory == null
            ? theme.brand.theme
            : theme.brand.theme.copyWith(
                textTheme: theme.brand.theme.textTheme.apply(
                  fontFamily: 'DuoyiScreenshotLatin',
                ),
                primaryTextTheme: theme.brand.theme.primaryTextTheme.apply(
                  fontFamily: 'DuoyiScreenshotLatin',
                ),
              ),
        home: RepaintBoundary(
          key: const ValueKey('todo-completed-preference-capture'),
          child: ColoredBox(
            color: theme.brand.theme.scaffoldBackgroundColor,
            child: home ?? const TodoScreen(),
          ),
        ),
      ),
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

String? get _screenshotDirectory =>
    Platform.environment['DUOYI_TODO_COMPLETED_SCREENSHOT_DIR'];

Future<void> _captureTodoPreferences(WidgetTester tester, String name) async {
  final directory = _screenshotDirectory;
  if (directory == null || directory.isEmpty) return;
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('todo-completed-preference-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(directory).createSync(recursive: true);
      File(
        '$directory/$name.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

List<TodoItem> _fixtureTodos() {
  final now = DateTime.now();
  return [
    TodoItem(
      id: _activeId,
      title: _activeTitle,
      quadrant: EisenhowerQuadrant.urgentImportant,
    ),
    TodoItem(
      id: _completedId,
      title: _completedTitle,
      quadrant: EisenhowerQuadrant.urgentImportant,
      isCompleted: true,
      completedAt: now,
    ),
    TodoItem(
      id: _archivedId,
      title: _archivedTitle,
      quadrant: EisenhowerQuadrant.urgentImportant,
      isCompleted: true,
      completedAt: now.subtract(const Duration(days: 1)),
      isArchivedAfterRollover: true,
    ),
  ];
}

Future<void> _selectView(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _setShowCompletedTodos(
  WidgetTester tester,
  PreferencesProvider preferences,
  bool value,
) async {
  await preferences.setShowCompletedTodos(value);
  await tester.pump();
}

void _expectTodoVisibility(
  WidgetTester tester, {
  required bool completedVisible,
}) {
  expect(find.text(_activeTitle), findsOneWidget);
  expect(
    find.text(_completedTitle),
    completedVisible ? findsOneWidget : findsNothing,
  );
  expect(find.text(_archivedTitle), findsNothing);
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
  final PreferencesProvider? preferences;
  final HabitProvider habits;
  final GoalProvider goals;
  final ThemeProvider theme;
  final AiService ai;
  final ShareProvider share;
  final AuthProvider auth;

  const _TodoHarness({
    required this.todos,
    required this.preferences,
    required this.habits,
    required this.goals,
    required this.theme,
    required this.ai,
    required this.share,
    required this.auth,
  });

  void dispose() {
    todos.dispose();
    preferences?.dispose();
    habits.dispose();
    goals.dispose();
    theme.dispose();
    ai.dispose();
    share.dispose();
    auth.dispose();
  }
}
