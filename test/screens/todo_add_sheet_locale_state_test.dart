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
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    'Todo add sheet retains its literal draft and selected priority through zh-en-zh',
    (tester) async {
      _setPhoneSurface(tester);
      final harness = await _pumpTodoScreen(tester);
      final accountBefore = harness.auth.state;
      final accountJsonBefore = accountBefore.toJson();
      final accountGenerationBefore =
          AccountLocalDataCleaner.accountDataGeneration;
      final todoRevisionBefore = harness.todos.revision;
      var todoNotifications = 0;
      var authNotifications = 0;
      harness.todos.addListener(() => todoNotifications++);
      harness.auth.addListener(() => authNotifications++);

      final sheet = await _openAddSheet(tester);
      final field = _titleField(tester, sheet);
      const draft = '中文任务 literal：整理项目资料！';
      await tester.enterText(field, draft);
      await tester.pumpAndSettle();

      final highPriority = find.descendant(of: sheet, matching: find.text('高'));
      await tester.ensureVisible(highPriority);
      await tester.tap(highPriority);
      await tester.pumpAndSettle();
      _expectSingleSelectedPriority(tester, sheet);
      final controllerBefore = tester.widget<TextField>(field).controller!;
      final valueBefore = controllerBefore.value;

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();

        expect(find.byType(BottomSheet), findsOneWidget);
        expect(
          tester.widget<TextField>(field).controller,
          same(controllerBefore),
        );
        expect(controllerBefore.value, valueBefore);
        expect(tester.widget<TextField>(field).controller!.text, draft);
        _expectSingleSelectedPriority(tester, sheet);
        expect(harness.todos.todos, isEmpty);
        expect(harness.todos.revision, todoRevisionBefore);
        expect(identical(harness.auth.state, accountBefore), isTrue);
        expect(harness.auth.state.toJson(), accountJsonBefore);
        expect(
          AccountLocalDataCleaner.accountDataGeneration,
          accountGenerationBefore,
        );
        expect(todoNotifications, 0);
        expect(authNotifications, 0);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'Todo add sheet and its real priority menu redraw app copy for zh-en-zh',
    (tester) async {
      _setPhoneSurface(tester);
      final harness = await _pumpTodoScreen(tester);
      final accountBefore = harness.auth.state;
      final accountJsonBefore = accountBefore.toJson();
      final accountGenerationBefore =
          AccountLocalDataCleaner.accountDataGeneration;
      final todoRevisionBefore = harness.todos.revision;
      var todoNotifications = 0;
      var authNotifications = 0;
      harness.todos.addListener(() => todoNotifications++);
      harness.auth.addListener(() => authNotifications++);

      final sheet = await _openAddSheet(tester);
      final field = _titleField(tester, sheet);
      const draft = '中文任务 literal：整理项目资料！';
      await tester.enterText(field, draft);
      await tester.pumpAndSettle();

      final highPriority = find.descendant(of: sheet, matching: find.text('高'));
      await tester.ensureVisible(highPriority);
      await tester.tap(highPriority);
      await tester.pumpAndSettle();
      _expectSingleSelectedPriority(tester, sheet);

      final expectedZhBefore = _expectedCopySnapshot(draft);
      final expectedMenuZh = _expectedQuadrantOptions();
      final observedZhBefore = _readCopySnapshot(tester, sheet, field);
      final menuZhBefore = await _openQuadrantMenuAndReadLabels(tester, sheet);
      await _selectCurrentQuadrant(tester);

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      final expectedEn = _expectedCopySnapshot(draft);
      final expectedMenuEn = _expectedQuadrantOptions();
      final observedEn = _readCopySnapshot(tester, sheet, field);
      final menuEn = await _openQuadrantMenuAndReadLabels(tester, sheet);
      await _selectCurrentQuadrant(tester);

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      final expectedZhAfter = _expectedCopySnapshot(draft);
      final observedZhAfter = _readCopySnapshot(tester, sheet, field);

      expect(
        [
          _copyValues(observedZhBefore),
          _copyValues(observedEn),
          _copyValues(observedZhAfter),
          menuZhBefore,
          menuEn,
        ],
        [
          _copyValues(expectedZhBefore),
          _copyValues(expectedEn),
          _copyValues(expectedZhAfter),
          expectedMenuZh,
          expectedMenuEn,
        ],
      );
      expect(harness.todos.todos, isEmpty);
      expect(harness.todos.revision, todoRevisionBefore);
      expect(identical(harness.auth.state, accountBefore), isTrue);
      expect(harness.auth.state.toJson(), accountJsonBefore);
      expect(
        AccountLocalDataCleaner.accountDataGeneration,
        accountGenerationBefore,
      );
      expect(todoNotifications, 0);
      expect(authNotifications, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

void _setPhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<_TodoHarness> _pumpTodoScreen(WidgetTester tester) async {
  final todos = TodoProvider();
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

Future<Finder> _openAddSheet(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
  final sheet = find.byType(BottomSheet);
  expect(sheet, findsOneWidget, reason: 'FAB must open the real add sheet');
  expect(tester.takeException(), isNull);
  return sheet;
}

Finder _titleField(WidgetTester tester, Finder sheet) =>
    find.descendant(of: sheet, matching: find.byType(TextField)).first;

void _expectSingleSelectedPriority(WidgetTester tester, Finder sheet) {
  final chips = tester.widgetList<ChoiceChip>(
    find.descendant(of: sheet, matching: find.byType(ChoiceChip)),
  );
  expect(chips.where((chip) => chip.selected), hasLength(1));
}

Future<List<String>> _openQuadrantMenuAndReadLabels(
  WidgetTester tester,
  Finder sheet,
) async {
  final field = find.descendant(
    of: sheet,
    matching: find.byType(AppDropdownField<EisenhowerQuadrant>),
  );
  expect(field, findsOneWidget);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  // Keyboard dismissal waits for timed layout frames before the menu opens.
  for (
    var frame = 0;
    frame < 40 &&
        find
            .byWidgetPredicate(
              (widget) => widget is PopupMenuItem<EisenhowerQuadrant>,
            )
            .evaluate()
            .isEmpty;
    frame++
  ) {
    await tester.pump(const Duration(milliseconds: 32));
  }
  await tester.pumpAndSettle();

  final menuItems = tester.widgetList<PopupMenuItem<EisenhowerQuadrant>>(
    find.byWidgetPredicate(
      (widget) => widget is PopupMenuItem<EisenhowerQuadrant>,
    ),
  );
  expect(menuItems, hasLength(4));
  final labels = <String>[];
  for (final item in menuItems) {
    final text = tester.widgetList<Text>(
      find.descendant(of: find.byWidget(item), matching: find.byType(Text)),
    );
    expect(text, hasLength(1));
    labels.add(text.single.data!);
  }
  expect(tester.takeException(), isNull);
  return labels;
}

Future<void> _selectCurrentQuadrant(WidgetTester tester) async {
  final currentItem = tester
      .widgetList<PopupMenuItem<EisenhowerQuadrant>>(
        find.byWidgetPredicate(
          (widget) => widget is PopupMenuItem<EisenhowerQuadrant>,
        ),
      )
      .singleWhere(
        (item) => item.value == EisenhowerQuadrant.notUrgentImportant,
      );
  await tester.tap(find.byWidget(currentItem));
  await tester.pumpAndSettle();
  expect(find.byType(BottomSheet), findsOneWidget);
  expect(tester.takeException(), isNull);
}

_TodoAddCopySnapshot _readCopySnapshot(
  WidgetTester tester,
  Finder sheet,
  Finder field,
) {
  final titleField = tester.widget<TextField>(field);
  final submitButtons = tester.widgetList<ElevatedButton>(
    find.descendant(of: sheet, matching: find.byType(ElevatedButton)),
  );
  expect(submitButtons, hasLength(1));
  final action = submitButtons.single.child as Text;

  final selectedPriority = tester
      .widgetList<ChoiceChip>(
        find.descendant(of: sheet, matching: find.byType(ChoiceChip)),
      )
      .singleWhere((chip) => chip.selected);
  final priorityLabel = selectedPriority.label as Text;
  final quadrantLabel = tester.widget<Text>(
    find.descendant(of: sheet, matching: find.textContaining('(Q2)')),
  );

  return (
    hint: titleField.decoration!.hintText!,
    action: action.data!,
    priority: priorityLabel.data!,
    selectedQuadrant: quadrantLabel.data!,
    draft: titleField.controller!.text,
  );
}

_TodoAddCopySnapshot _expectedCopySnapshot(String draft) => (
  hint: TodoBoardUiCopy.taskHint,
  action: TodoBoardUiCopy.addTask,
  priority: TodoPriority.high.label,
  selectedQuadrant: TodoBoardUiCopy.quadrantQ2WithEmoji,
  draft: draft,
);

List<String> _expectedQuadrantOptions() => [
  TodoBoardUiCopy.quadrantQ1WithEmoji,
  TodoBoardUiCopy.quadrantQ2WithEmoji,
  TodoBoardUiCopy.quadrantQ3WithEmoji,
  TodoBoardUiCopy.quadrantQ4WithEmoji,
];

List<Object> _copyValues(_TodoAddCopySnapshot snapshot) => [
  snapshot.hint,
  snapshot.action,
  snapshot.priority,
  snapshot.selectedQuadrant,
  snapshot.draft,
];

typedef _TodoAddCopySnapshot = ({
  String hint,
  String action,
  String priority,
  String selectedQuadrant,
  String draft,
});

class _TodoHarness {
  final TodoProvider todos;
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
