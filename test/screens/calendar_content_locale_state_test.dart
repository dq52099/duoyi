import 'dart:async';

import 'package:duoyi/core/calendar_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/models/workspace.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/calendar_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/widgets/app_time_picker.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FixtureTodoProvider extends TodoProvider {
  _FixtureTodoProvider({
    List<TodoItem> todos = const <TodoItem>[],
    this.addGate,
  }) : _fixtureTodos = todos;

  final List<TodoItem> _fixtureTodos;
  final Completer<void>? addGate;
  final List<TodoItem> addedTodos = <TodoItem>[];
  int addCalls = 0;

  @override
  List<TodoItem> get todos => [..._fixtureTodos, ...addedTodos];

  @override
  Future<void> addTodo(
    TodoItem todo, {
    bool waitForReminderSync = true,
    bool reportReminderScheduleFailure = false,
  }) async {
    addCalls++;
    addedTodos.add(todo);
    final gate = addGate;
    if (gate != null) await gate.future;
  }
}

class _FixtureTimeAuditProvider extends TimeAuditProvider {
  _FixtureTimeAuditProvider({this.addGate});

  final Completer<void>? addGate;
  final List<TimeEntry> addedEntries = <TimeEntry>[];
  int addCalls = 0;

  @override
  List<TimeEntry> get entries => addedEntries;

  @override
  Future<void> add(TimeEntry entry) async {
    addCalls++;
    addedEntries.add(entry);
    final gate = addGate;
    if (gate != null) await gate.future;
  }
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];
  final List<Route<dynamic>> popped = <Route<dynamic>>[];
  final List<Route<dynamic>> removed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped.add(route);
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    removed.add(route);
    super.didRemove(route, previousRoute);
  }
}

class _FixtureHabitProvider extends HabitProvider {
  @override
  List<Habit> get habits => const <Habit>[];
}

class _FixturePomodoroProvider extends PomodoroProvider {
  @override
  List<PomodoroSession> get sessions => const <PomodoroSession>[];
}

class _FixtureShareProvider extends ShareProvider {
  _FixtureShareProvider(this.fixtureWorkspaces);

  final List<Workspace> fixtureWorkspaces;

  @override
  List<Workspace> get workspaces => fixtureWorkspaces;
}

Widget _calendarApp({
  required _FixtureTodoProvider todoProvider,
  required Widget home,
  _FixtureTimeAuditProvider? timeAuditProvider,
  List<Workspace> workspaces = const <Workspace>[],
  GlobalKey<NavigatorState>? navigatorKey,
  List<NavigatorObserver> navigatorObservers = const <NavigatorObserver>[],
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
      ChangeNotifierProvider<HabitProvider>(
        create: (_) => _FixtureHabitProvider(),
      ),
      ChangeNotifierProvider<PomodoroProvider>(
        create: (_) => _FixturePomodoroProvider(),
      ),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ChangeNotifierProvider<CalendarProvider>(
        create: (_) => CalendarProvider(),
      ),
      ChangeNotifierProvider<AnniversaryProvider>(
        create: (_) => AnniversaryProvider(),
      ),
      ChangeNotifierProvider<CountdownProvider>(
        create: (_) => CountdownProvider(),
      ),
      ChangeNotifierProvider<CourseProvider>(create: (_) => CourseProvider()),
      ChangeNotifierProvider<DiaryProvider>(create: (_) => DiaryProvider()),
      ChangeNotifierProvider<GoalProvider>(create: (_) => GoalProvider()),
      ChangeNotifierProvider<ShareProvider>(
        create: (_) => _FixtureShareProvider(workspaces),
      ),
      ChangeNotifierProvider<TimeAuditProvider>(
        create: (_) => timeAuditProvider ?? _FixtureTimeAuditProvider(),
      ),
    ],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: navigatorObservers,
      home: home,
    ),
  );
}

Finder _calendarDateLabel(String text) => find.descendant(
  of: find.byKey(const ValueKey('calendar_navigation_date_button')),
  matching: find.text(text),
);

Finder _quickAddMenu() => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_QuickAddMenuSheet',
  description: 'Calendar quick-add menu sheet',
);

Finder _projectDetailSheet() => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_ProjectDetailSheet',
  description: 'Calendar project detail sheet',
);

Finder _todoTitleField() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      widget.decoration?.labelText == CalendarUiCopy.todoTitleLabel,
  description: 'Calendar quick-add task title field',
);

Finder _timeEntryField(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
  description: 'Calendar time-entry field: $label',
);

Finder _timeEntryCategoryField() =>
    find.byType(AppDropdownField<TimeEntryCategory>);

Finder _headerText(String text) => find.descendant(
  of: find.byType(AppSectionHeader),
  matching: find.text(text),
);

Finder _modalAction(String text) =>
    find.descendant(of: find.byType(AppModalSheet), matching: find.text(text));

Finder _dialogAction(String text) =>
    find.descendant(of: find.byType(AppDialog), matching: find.text(text));

Future<void> _openQuickAddMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip(CalendarUiCopy.quickAddTooltip));
  await tester.pumpAndSettle();
}

Future<void> _openTodoDialog(WidgetTester tester) async {
  await _openQuickAddMenu(tester);
  await tester.tap(find.text(CalendarUiCopy.quickAddNewTodoTitle));
  await tester.pumpAndSettle();
}

Future<void> _openTimeEntryDialog(WidgetTester tester) async {
  await _openQuickAddMenu(tester);
  await tester.tap(find.text(CalendarUiCopy.quickAddTimeEntryTitle));
  await tester.pumpAndSettle();
}

Workspace _literalWorkspace() => Workspace(
  id: 'literal-workspace-id',
  name: 'literal workspace',
  ownerUserId: 'fixture-owner',
  isPrivate: false,
  createdAt: DateTime(2021, 1, 1),
  updatedAt: DateTime(2021, 1, 1),
);

TodoItem _calendarTodo({
  required String id,
  required String title,
  required DateTime date,
  required String projectId,
  required String projectName,
  String workspaceId = 'literal-workspace-id',
}) => TodoItem(
  id: id,
  title: title,
  date: date,
  isCompleted: true,
  listGroupId: projectId,
  listGroupName: projectName,
  workspaceId: workspaceId,
  createdAt: DateTime(2021, 1, 1),
  updatedAt: DateTime(2021, 1, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    I18n.setLocale(AppLocale.zh);
  });

  testWidgets(
    'Calendar date, filter, year, and three-day counts refresh in Chinese and English',
    (tester) async {
      final firstDay = DateTime(2021, 2, 1);
      final secondDay = DateTime(2021, 2, 2);
      final todoProvider = _FixtureTodoProvider(
        todos: [
          _calendarTodo(
            id: 'literal-alpha-1',
            title: 'Literal task alpha one',
            date: firstDay,
            projectId: 'literal-alpha',
            projectName: 'literal project',
          ),
          _calendarTodo(
            id: 'literal-alpha-2',
            title: 'Literal task alpha two',
            date: firstDay,
            projectId: 'literal-alpha',
            projectName: 'literal project',
          ),
          _calendarTodo(
            id: 'literal-other-1',
            title: 'Literal task other one',
            date: firstDay,
            projectId: 'literal-other',
            projectName: 'other project',
          ),
          _calendarTodo(
            id: 'literal-other-2',
            title: 'Literal task other two',
            date: secondDay,
            projectId: 'literal-other',
            projectName: 'other project',
          ),
        ],
      );

      await tester.pumpWidget(
        _calendarApp(
          todoProvider: todoProvider,
          home: CalendarScreen(initialDate: firstDay),
          workspaces: [_literalWorkspace()],
        ),
      );
      await tester.pumpAndSettle();

      final chineseDayTab = find.widgetWithText(Tab, '日');
      await tester.ensureVisible(chineseDayTab);
      await tester.tap(chineseDayTab);
      await tester.pumpAndSettle();
      expect(find.text('日历'), findsOneWidget);
      expect(_calendarDateLabel('2021年2月1日'), findsOneWidget);
      expect(
        find.widgetWithText(FilterChip, 'literal project 2'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilterChip, 'other project 2'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilterChip, 'literal workspace 4'),
        findsOneWidget,
      );
      expect(find.text('Literal task alpha one'), findsOneWidget);
      expect(find.text('Literal task alpha two'), findsOneWidget);
      expect(find.text('Literal task other one'), findsOneWidget);

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();

      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
      expect(find.text('Week'), findsOneWidget);
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('3-Day'), findsOneWidget);
      expect(find.text('Year'), findsOneWidget);
      expect(_calendarDateLabel('Feb 1, 2021'), findsOneWidget);
      expect(
        find.widgetWithText(FilterChip, 'literal project 2'),
        findsOneWidget,
      );
      expect(find.text('Literal task alpha one'), findsOneWidget);
      expect(find.text('Literal task other one'), findsOneWidget);

      final workspaceChip = find.widgetWithText(
        FilterChip,
        'literal workspace 4',
      );
      final filterScrollable = find.descendant(
        of: find.byKey(const ValueKey('calendar_unified_filter_strip')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        workspaceChip,
        180,
        scrollable: filterScrollable,
      );
      expect(workspaceChip, findsOneWidget);

      final alphaChip = find.widgetWithText(FilterChip, 'literal project 2');
      await tester.scrollUntilVisible(
        alphaChip,
        -180,
        scrollable: filterScrollable,
      );
      await tester.pumpAndSettle();
      await tester.tap(alphaChip);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(alphaChip).selected, isTrue);
      expect(find.text('Literal task alpha one'), findsOneWidget);
      expect(find.text('Literal task alpha two'), findsOneWidget);
      expect(find.text('Literal task other one'), findsNothing);

      final yearTab = find.widgetWithText(Tab, 'Year');
      await tester.ensureVisible(yearTab);
      await tester.tap(yearTab);
      await tester.pumpAndSettle();
      expect(find.text('Feb'), findsOneWidget);
      expect(find.text('1 event'), findsOneWidget);
      expect(find.text('2 events'), findsNothing);

      final allProjects = find.widgetWithText(FilterChip, 'All projects');
      await tester.scrollUntilVisible(
        allProjects,
        -180,
        scrollable: filterScrollable,
      );
      await tester.pumpAndSettle();
      await tester.tap(allProjects);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(allProjects).selected, isTrue);
      expect(find.text('2 events'), findsOneWidget);

      final threeDayTab = find.widgetWithText(Tab, '3-Day');
      await tester.ensureVisible(threeDayTab);
      await tester.tap(threeDayTab);
      await tester.pumpAndSettle();
      expect(find.text('Feb 1 · Mon'), findsOneWidget);
      expect(find.text('3 items'), findsOneWidget);
      expect(find.text('Feb 2 · Tue'), findsOneWidget);
      expect(find.text('1 item'), findsOneWidget);
      expect(find.text('Feb 3 · Wed'), findsOneWidget);
      expect(find.text('0 items'), findsOneWidget);

      await tester.scrollUntilVisible(
        alphaChip,
        180,
        scrollable: filterScrollable,
      );
      await tester.pumpAndSettle();
      await tester.tap(alphaChip);
      await tester.pumpAndSettle();
      expect(find.text('2 items'), findsOneWidget);
      expect(find.text('1 item'), findsNothing);
      expect(find.text('Literal task alpha one'), findsOneWidget);
      expect(find.text('Literal task other one'), findsNothing);

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(find.text('日历'), findsOneWidget);
      expect(find.text('三日'), findsOneWidget);
      expect(_calendarDateLabel('2月1日 - 2月3日'), findsOneWidget);
      Finder laneCount(String heading, String count) => find.descendant(
        of: find.ancestor(
          of: find.text(heading),
          matching: find.byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == '_ThreeDayLane',
          ),
        ),
        matching: find.text(count),
      );
      expect(laneCount('2月1日 周一', '2 项'), findsOneWidget);
      expect(laneCount('2月2日 周二', '0 项'), findsOneWidget);
      expect(laneCount('2月3日 周三', '0 项'), findsOneWidget);
      expect(find.text('literal project 2'), findsOneWidget);
      expect(find.text('Literal task alpha one'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mounted quick-add menu and project detail sheet keep state and literal content across locales',
    (tester) async {
      final day = DateTime(2021, 2, 1);
      final todoProvider = _FixtureTodoProvider(
        todos: [
          _calendarTodo(
            id: 'literal-project-task-1',
            title: 'Literal project task one',
            date: day,
            projectId: 'literal-project-id',
            projectName: 'literal project',
          ),
          _calendarTodo(
            id: 'literal-project-task-2',
            title: 'Literal project task two',
            date: day,
            projectId: 'literal-project-id',
            projectName: 'literal project',
          ),
        ],
      );
      await tester.pumpWidget(
        _calendarApp(
          todoProvider: todoProvider,
          home: CalendarScreen(initialDate: day),
          workspaces: [_literalWorkspace()],
        ),
      );
      await tester.pumpAndSettle();

      await _openQuickAddMenu(tester);
      expect(_quickAddMenu(), findsOneWidget);
      final menuState = tester.state(_quickAddMenu());
      expect(find.text('新建'), findsOneWidget);
      expect(find.text('literal project 2'), findsOneWidget);

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(_quickAddMenu(), findsOneWidget);
      expect(tester.state(_quickAddMenu()), same(menuState));
      expect(find.text(CalendarUiCopy.quickAddMenuTitle), findsOneWidget);
      expect(find.text('literal project 2'), findsOneWidget);
      expect(find.text('literal workspace 2'), findsOneWidget);

      Navigator.of(tester.element(_quickAddMenu())).pop();
      await tester.pumpAndSettle();
      final projectChip = find.widgetWithText(FilterChip, 'literal project 2');
      await tester.ensureVisible(projectChip);
      await tester.tap(projectChip);
      await tester.pumpAndSettle();
      final projectAction = find.text(CalendarUiCopy.projectDetailAction);
      await tester.ensureVisible(projectAction);
      await tester.pumpAndSettle();
      await tester.tap(projectAction);
      await tester.pumpAndSettle();

      expect(_projectDetailSheet(), findsOneWidget);
      final projectState = tester.state(_projectDetailSheet());
      final projectSheet = _projectDetailSheet();
      expect(
        find.descendant(
          of: projectSheet,
          matching: find.text('Project details'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: projectSheet,
          matching: find.text('literal project'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: projectSheet,
          matching: find.text('Literal project task one'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: projectSheet,
          matching: find.text('Literal project task two'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: projectSheet, matching: find.text('Total')),
        findsOneWidget,
      );

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(_projectDetailSheet(), findsOneWidget);
      expect(tester.state(_projectDetailSheet()), same(projectState));
      expect(
        find.descendant(
          of: projectSheet,
          matching: find.text(CalendarUiCopy.projectDetailSheetTitle),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: projectSheet,
          matching: find.text('literal project'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: projectSheet,
          matching: find.text('Literal project task one'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: projectSheet,
          matching: find.text('Literal project task two'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: projectSheet, matching: find.text('总数')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'normalized project filter IDs select the same literal tasks in the agenda and detail sheet',
    (tester) async {
      final day = DateTime(2021, 2, 1);
      final todoProvider = _FixtureTodoProvider(
        todos: [
          _calendarTodo(
            id: 'padded-project-id-task',
            title: 'Literal raw-id task',
            date: day,
            projectId: ' padded-project-id ',
            projectName: 'literal padded project',
            workspaceId: 'private',
          ),
        ],
      );
      await tester.pumpWidget(
        _calendarApp(
          todoProvider: todoProvider,
          home: CalendarScreen(initialDate: day),
        ),
      );
      await tester.pumpAndSettle();

      final projectChip = find.widgetWithText(
        FilterChip,
        'literal padded project 1',
      );
      await tester.ensureVisible(projectChip);
      await tester.tap(projectChip);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(projectChip).selected, isTrue);
      expect(find.text('Literal raw-id task'), findsOneWidget);

      final projectAction = find.text(CalendarUiCopy.projectDetailAction);
      await tester.ensureVisible(projectAction);
      await tester.tap(projectAction);
      await tester.pumpAndSettle();
      final projectSheet = _projectDetailSheet();
      expect(
        find.descendant(
          of: projectSheet,
          matching: find.text('Literal raw-id task'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: projectSheet,
          matching: find.text(CalendarUiCopy.projectEmptyTasks),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'date picker resolves semantic copy live, preserves its choice, and dismisses cleanly across locale changes',
    (tester) async {
      final initialDay = DateTime(2021, 2, 1);
      final pickedDay = DateTime(2021, 2, 8);
      final todoProvider = _FixtureTodoProvider();
      await tester.pumpWidget(
        _calendarApp(
          todoProvider: todoProvider,
          home: CalendarScreen(initialDate: initialDay),
        ),
      );
      await tester.pumpAndSettle();

      final dayTab = find.widgetWithText(Tab, '日');
      await tester.ensureVisible(dayTab);
      await tester.tap(dayTab);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('calendar_navigation_date_button')),
      );
      await tester.pumpAndSettle();
      expect(
        _headerText(I18n.tr('calendar.content.date_picker_title')),
        findsOneWidget,
      );
      expect(
        _headerText(I18n.tr('calendar.content.date_picker_subtitle')),
        findsOneWidget,
      );
      final dateChoice = find.byKey(const ValueKey('solar-day-2021-02-08'));
      await tester.ensureVisible(dateChoice);
      await tester.tap(dateChoice);
      await tester.pumpAndSettle();
      expect(find.text(I18nDateFormat.date(pickedDay)), findsOneWidget);

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(find.byType(AppModalSheet), findsOneWidget);
      expect(
        _headerText(I18n.tr('calendar.content.date_picker_title')),
        findsOneWidget,
      );
      expect(find.text('Select date'), findsOneWidget);
      expect(find.text('Feb 8, 2021'), findsOneWidget);

      await tester.tap(_modalAction(I18n.tr('action.cancel')));
      await tester.pumpAndSettle();
      expect(_calendarDateLabel('Feb 1, 2021'), findsOneWidget);

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(find.byType(AppModalSheet), findsNothing);
      expect(_calendarDateLabel('2021年2月1日'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(const ValueKey('calendar_navigation_date_button')),
      );
      await tester.pumpAndSettle();
      final confirmedChoice = find.byKey(
        const ValueKey('solar-day-2021-02-08'),
      );
      await tester.ensureVisible(confirmedChoice);
      await tester.tap(confirmedChoice);
      await tester.pumpAndSettle();
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(find.text('Feb 8, 2021'), findsOneWidget);
      await tester.tap(_modalAction(I18n.tr('action.confirm')));
      await tester.pumpAndSettle();
      expect(_calendarDateLabel('Feb 8, 2021'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Todo quick-add draft keeps controller, selection, and focus through locale changes and duplicate submit triggers',
    (tester) async {
      final submitGate = Completer<void>();
      final todoProvider = _FixtureTodoProvider(addGate: submitGate);
      await tester.pumpWidget(
        _calendarApp(
          todoProvider: todoProvider,
          home: CalendarScreen(initialDate: DateTime(2021, 2, 1)),
        ),
      );
      await tester.pumpAndSettle();
      await _openTodoDialog(tester);

      final titleFinder = _todoTitleField();
      await tester.enterText(titleFinder, 'literal todo draft');
      final titleField = tester.widget<TextField>(titleFinder);
      final controller = titleField.controller!;
      final focusNode = titleField.focusNode!;
      const selection = TextSelection(baseOffset: 2, extentOffset: 11);
      controller.selection = selection;
      expect(focusNode.hasFocus, isTrue);

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      final englishField = tester.widget<TextField>(titleFinder);
      expect(identical(englishField.controller, controller), isTrue);
      expect(identical(englishField.focusNode, focusNode), isTrue);
      expect(controller.text, 'literal todo draft');
      expect(controller.selection, selection);
      expect(focusNode.hasFocus, isTrue);
      expect(englishField.decoration?.labelText, 'Task title');

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(
        identical(tester.widget<TextField>(titleFinder).controller, controller),
        isTrue,
      );
      expect(controller.text, 'literal todo draft');
      expect(controller.selection, selection);
      expect(focusNode.hasFocus, isTrue);

      await tester.tap(find.text(I18n.tr('action.add')));
      await tester.pump();
      expect(todoProvider.addCalls, 1);
      expect(todoProvider.addedTodos.single.title, 'literal todo draft');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(todoProvider.addCalls, 1);
      expect(find.byType(AppDialog), findsOneWidget);

      submitGate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'time-log draft and semantic time picker retain user choices through locale changes and dismissal',
    (tester) async {
      final day = DateTime(2021, 2, 1);
      final todoProvider = _FixtureTodoProvider();
      final timeAuditProvider = _FixtureTimeAuditProvider();
      await tester.pumpWidget(
        _calendarApp(
          todoProvider: todoProvider,
          timeAuditProvider: timeAuditProvider,
          home: CalendarScreen(initialDate: day),
        ),
      );
      await tester.pumpAndSettle();
      await _openTimeEntryDialog(tester);

      final titleFinder = _timeEntryField(CalendarUiCopy.timeEntryTitleLabel);
      final durationFinder = _timeEntryField(
        CalendarUiCopy.timeEntryDurationLabel,
      );
      final noteFinder = _timeEntryField(CalendarUiCopy.timeEntryNoteLabel);
      await tester.enterText(titleFinder, 'literal time-log title');
      await tester.enterText(durationFinder, '45');
      await tester.enterText(noteFinder, 'literal time-log note');
      final titleController = tester.widget<TextField>(titleFinder).controller!;
      final durationController = tester
          .widget<TextField>(durationFinder)
          .controller!;
      final noteField = tester.widget<TextField>(noteFinder);
      final noteController = noteField.controller!;
      final noteFocusNode = tester
          .widget<EditableText>(
            find.descendant(
              of: noteFinder,
              matching: find.byType(EditableText),
            ),
          )
          .focusNode;
      const noteSelection = TextSelection(baseOffset: 3, extentOffset: 12);
      noteController.selection = noteSelection;
      expect(noteFocusNode.hasFocus, isTrue);

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(
        identical(
          tester.widget<TextField>(_timeEntryField('Title')).controller,
          titleController,
        ),
        isTrue,
      );
      expect(
        identical(
          tester
              .widget<TextField>(_timeEntryField('Duration (minutes)'))
              .controller,
          durationController,
        ),
        isTrue,
      );
      final englishNoteField = tester.widget<TextField>(
        _timeEntryField('Notes'),
      );
      final englishNoteEditable = tester.widget<EditableText>(
        find.descendant(
          of: _timeEntryField('Notes'),
          matching: find.byType(EditableText),
        ),
      );
      expect(identical(englishNoteField.controller, noteController), isTrue);
      expect(identical(englishNoteEditable.focusNode, noteFocusNode), isTrue);
      expect(titleController.text, 'literal time-log title');
      expect(durationController.text, '45');
      expect(noteController.text, 'literal time-log note');
      expect(noteController.selection, noteSelection);
      expect(noteFocusNode.hasFocus, isTrue);

      final startTimeTile = find.widgetWithText(ListTile, 'Start time');
      await tester.ensureVisible(startTimeTile);
      await tester.tap(startTimeTile);
      await tester.pumpAndSettle();
      expect(
        _headerText(I18n.tr('calendar.content.time_picker_start_time')),
        findsOneWidget,
      );

      final eveningPreset = find.text(I18n.tr('picker.time.preset_evening'));
      await tester.ensureVisible(eveningPreset);
      await tester.tap(eveningPreset);
      await tester.pumpAndSettle();
      final hourController =
          tester
                  .widgetList<ListWheelScrollView>(
                    find.byType(ListWheelScrollView),
                  )
                  .first
                  .controller!
              as FixedExtentScrollController;
      final minuteController =
          tester
                  .widgetList<ListWheelScrollView>(
                    find.byType(ListWheelScrollView),
                  )
                  .elementAt(1)
                  .controller!
              as FixedExtentScrollController;
      expect(hourController.selectedItem, 20);
      expect(minuteController.selectedItem, 0);

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(_headerText('开始时间'), findsOneWidget);
      final chineseWheels = tester
          .widgetList<ListWheelScrollView>(find.byType(ListWheelScrollView))
          .toList();
      expect(identical(chineseWheels[0].controller, hourController), isTrue);
      expect(identical(chineseWheels[1].controller, minuteController), isTrue);
      expect(hourController.selectedItem, 20);
      expect(minuteController.selectedItem, 0);

      await tester.tap(_modalAction(I18n.tr('action.cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(AppModalSheet), findsNothing);
      expect(
        find.text(AppTimePicker.format(const TimeOfDay(hour: 9, minute: 0))),
        findsOneWidget,
      );

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(find.byType(AppModalSheet), findsNothing);
      expect(tester.takeException(), isNull);

      final startTimeEnglish = find.widgetWithText(ListTile, 'Start time');
      await tester.ensureVisible(startTimeEnglish);
      await tester.tap(startTimeEnglish);
      await tester.pumpAndSettle();
      final secondEveningPreset = find.text(
        I18n.tr('picker.time.preset_evening'),
      );
      await tester.ensureVisible(secondEveningPreset);
      await tester.tap(secondEveningPreset);
      await tester.pumpAndSettle();
      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      await tester.tap(_modalAction(I18n.tr('action.confirm')));
      await tester.pumpAndSettle();

      expect(
        find.text(AppTimePicker.format(const TimeOfDay(hour: 20, minute: 0))),
        findsOneWidget,
      );
      expect(titleController.text, 'literal time-log title');
      expect(durationController.text, '45');
      expect(noteController.text, 'literal time-log note');
      expect(noteController.selection, noteSelection);
      expect(
        tester.widget<TextField>(_timeEntryField('备注')).controller,
        same(noteController),
      );

      await tester.tap(_dialogAction(I18n.tr('action.cancel')));
      await tester.pumpAndSettle();
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'time-entry category selection flows through its typed callback and saves',
    (tester) async {
      final todoProvider = _FixtureTodoProvider();
      final timeAuditProvider = _FixtureTimeAuditProvider();
      final observer = _RecordingNavigatorObserver();
      await tester.pumpWidget(
        _calendarApp(
          todoProvider: todoProvider,
          timeAuditProvider: timeAuditProvider,
          home: CalendarScreen(initialDate: DateTime(2021, 2, 1)),
          navigatorObservers: [observer],
        ),
      );
      await tester.pumpAndSettle();
      await _openTimeEntryDialog(tester);

      final categoryField = _timeEntryCategoryField();
      expect(categoryField, findsOneWidget);
      final categoryDropdown = tester
          .widget<AppDropdownField<TimeEntryCategory>>(categoryField);
      final ValueChanged<TimeEntryCategory?> typedCallback =
          categoryDropdown.onChanged;
      expect(typedCallback, isNotNull);
      expect(categoryDropdown.enabled, isTrue);

      final pushesBeforeCategoryMenu = observer.pushed.length;
      await tester.tap(categoryField);
      await tester.pumpAndSettle();
      expect(observer.pushed.length, pushesBeforeCategoryMenu + 1);
      final categoryMenuRoute = observer.pushed.last;
      expect(categoryMenuRoute.isCurrent, isTrue);

      final selectedCategory = TimeEntryCategory.study;
      await tester.tap(find.text(selectedCategory.label));
      await tester.pumpAndSettle();
      expect(categoryMenuRoute.isActive, isFalse);
      expect(find.text(selectedCategory.label), findsOneWidget);

      await tester.enterText(
        _timeEntryField(CalendarUiCopy.timeEntryTitleLabel),
        'categorized time entry',
      );
      await tester.tap(find.text(CalendarUiCopy.timeEntrySubmitButton));
      await tester.pumpAndSettle();
      expect(timeAuditProvider.addCalls, 1);
      expect(timeAuditProvider.addedEntries.single.category, selectedCategory);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'same account owner cannot submit Todo or time-log drafts from an invalidated account generation',
    (tester) async {
      final day = DateTime(2021, 2, 1);
      final todoProvider = _FixtureTodoProvider();
      final timeAuditProvider = _FixtureTimeAuditProvider();
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        AccountLocalDataCleaner.accountDataOwnerKey,
        'same-account-id',
      );
      await tester.pumpWidget(
        _calendarApp(
          todoProvider: todoProvider,
          timeAuditProvider: timeAuditProvider,
          home: CalendarScreen(initialDate: day),
        ),
      );
      await tester.pumpAndSettle();

      await _openTodoDialog(tester);
      await tester.enterText(_todoTitleField(), 'stale todo draft');
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      await tester.pump();
      if (find.byType(AppDialog).evaluate().isNotEmpty) {
        await tester.tap(find.text(I18n.tr('action.add')));
        await tester.pumpAndSettle();
      }

      if (find.byType(AppDialog).evaluate().isNotEmpty) {
        await tester.tap(find.text(I18n.tr('action.cancel')));
        await tester.pumpAndSettle();
      }
      await _openTimeEntryDialog(tester);
      await tester.enterText(
        _timeEntryField(CalendarUiCopy.timeEntryTitleLabel),
        'stale time-log draft',
      );
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      await tester.pump();
      if (find.byType(AppDialog).evaluate().isNotEmpty) {
        await tester.tap(find.text(CalendarUiCopy.timeEntrySubmitButton));
        await tester.pumpAndSettle();
      }

      expect(todoProvider.addCalls, 0);
      expect(timeAuditProvider.addCalls, 0);
      expect(
        preferences.getString(AccountLocalDataCleaner.accountDataOwnerKey),
        'same-account-id',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an invalidated time-entry origin cannot push a category menu', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      AccountLocalDataCleaner.accountDataOwnerKey,
      'account-A',
    );
    final observer = _RecordingNavigatorObserver();
    final todoProvider = _FixtureTodoProvider();
    final timeAuditProvider = _FixtureTimeAuditProvider();
    await tester.pumpWidget(
      _calendarApp(
        todoProvider: todoProvider,
        timeAuditProvider: timeAuditProvider,
        home: CalendarScreen(initialDate: DateTime(2021, 2, 1)),
        navigatorObservers: [observer],
      ),
    );
    await tester.pumpAndSettle();
    await _openTimeEntryDialog(tester);
    final dialogRoute = observer.pushed.last;
    expect(dialogRoute.isCurrent, isTrue);

    final pushesBeforeInvalidation = observer.pushed.length;
    await preferences.setString(
      AccountLocalDataCleaner.accountDataOwnerKey,
      'account-B',
    );
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    await tester.pumpAndSettle();
    expect(
      preferences.getString(AccountLocalDataCleaner.accountDataOwnerKey),
      'account-B',
    );

    final categoryField = _timeEntryCategoryField();
    if (categoryField.evaluate().isNotEmpty) {
      await tester.tap(categoryField);
      await tester.pumpAndSettle();
    }
    expect(
      observer.pushed.length,
      pushesBeforeInvalidation,
      reason: 'a stale account origin must not push a category route',
    );
    if (categoryField.evaluate().isNotEmpty) {
      expect(
        tester
            .widget<AppDropdownField<TimeEntryCategory>>(categoryField)
            .enabled,
        isFalse,
        reason: 'a stale field left mounted must be unavailable',
      );
    }
    final fieldRemainsAfterAttempt = categoryField.evaluate().isNotEmpty;
    expect(
      !dialogRoute.isActive ||
          (fieldRemainsAfterAttempt &&
              !tester
                  .widget<AppDropdownField<TimeEntryCategory>>(categoryField)
                  .enabled),
      isTrue,
      reason: 'the stale origin is dismissed or its category field is disabled',
    );
    expect(timeAuditProvider.addCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an open category menu cannot apply after account switch or pop an unrelated route',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        AccountLocalDataCleaner.accountDataOwnerKey,
        'account-A',
      );
      final navigatorKey = GlobalKey<NavigatorState>();
      final observer = _RecordingNavigatorObserver();
      final todoProvider = _FixtureTodoProvider();
      final timeAuditProvider = _FixtureTimeAuditProvider();
      await tester.pumpWidget(
        _calendarApp(
          todoProvider: todoProvider,
          timeAuditProvider: timeAuditProvider,
          home: CalendarScreen(initialDate: DateTime(2021, 2, 1)),
          navigatorKey: navigatorKey,
          navigatorObservers: [observer],
        ),
      );
      await tester.pumpAndSettle();
      await _openTimeEntryDialog(tester);

      final dialogRoute = observer.pushed.last;
      expect(dialogRoute.isCurrent, isTrue);
      final categoryField = _timeEntryCategoryField();
      final categoryFormField = find.descendant(
        of: categoryField,
        matching: find.byType(FormField<TimeEntryCategory>),
      );
      expect(categoryFormField, findsOneWidget);
      final categoryFieldState = tester
          .state<FormFieldState<TimeEntryCategory>>(categoryFormField);
      const originalCategory = TimeEntryCategory.work;
      expect(categoryFieldState.value, originalCategory);

      final pushesBeforeCategoryMenu = observer.pushed.length;
      await tester.tap(categoryField);
      await tester.pumpAndSettle();
      expect(observer.pushed.length, pushesBeforeCategoryMenu + 1);
      final categoryMenuRoute = observer.pushed.last;
      expect(categoryMenuRoute.isCurrent, isTrue);

      final unrelatedTopRoute = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Unrelated top route')),
      );
      navigatorKey.currentState!.push(unrelatedTopRoute);
      await tester.pumpAndSettle();
      expect(unrelatedTopRoute.isCurrent, isTrue);

      final pushesBeforeAccountSwitch = observer.pushed.length;
      await preferences.setString(
        AccountLocalDataCleaner.accountDataOwnerKey,
        'account-B',
      );
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      await tester.pumpAndSettle();

      expect(unrelatedTopRoute.isCurrent, isTrue);
      expect(observer.popped, isNot(contains(unrelatedTopRoute)));
      expect(observer.removed, isNot(contains(unrelatedTopRoute)));
      expect(observer.pushed.length, pushesBeforeAccountSwitch);
      expect(dialogRoute.isActive, isFalse);
      expect(categoryFieldState.mounted, isFalse);
      expect(categoryFieldState.value, originalCategory);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(categoryMenuRoute.isCurrent, isTrue);
      final staleSelection = TimeEntryCategory.study;
      await tester.tap(find.text(staleSelection.label));
      await tester.pumpAndSettle();

      expect(categoryMenuRoute.isActive, isFalse);
      expect(categoryFieldState.value, originalCategory);
      expect(find.byType(AppDialog), findsNothing);
      expect(timeAuditProvider.addCalls, 0);
      expect(timeAuditProvider.addedEntries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'quick-add submission does not outlive its Calendar caller route',
    (tester) async {
      final todoProvider = _FixtureTodoProvider();
      final callerNavigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        _calendarApp(
          todoProvider: todoProvider,
          home: Navigator(
            key: callerNavigatorKey,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: SizedBox.shrink()),
            ),
          ),
        ),
      );
      callerNavigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => CalendarScreen(initialDate: DateTime(2021, 2, 1)),
        ),
      );
      await tester.pumpAndSettle();
      await _openTodoDialog(tester);
      await tester.enterText(_todoTitleField(), 'caller-owned todo draft');

      callerNavigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOneWidget);
      if (find.byType(AppDialog).evaluate().isNotEmpty) {
        await tester.tap(find.text(I18n.tr('action.add')));
        await tester.pumpAndSettle();
      }

      final addCallsAfterCallerRemoval = todoProvider.addCalls;
      if (find.byType(AppDialog).evaluate().isNotEmpty) {
        await tester.tap(find.text(I18n.tr('action.cancel')));
        await tester.pumpAndSettle();
      }
      expect(addCallsAfterCallerRemoval, 0);
      expect(todoProvider.addedTodos, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'held Todo submit completes safely after its caller and widget tree are removed',
    (tester) async {
      final submitGate = Completer<void>();
      final todoProvider = _FixtureTodoProvider(addGate: submitGate);
      await tester.pumpWidget(
        _calendarApp(
          todoProvider: todoProvider,
          home: CalendarScreen(initialDate: DateTime(2021, 2, 1)),
        ),
      );
      await tester.pumpAndSettle();
      await _openTodoDialog(tester);
      await tester.enterText(_todoTitleField(), 'held todo draft');
      await tester.tap(find.text(I18n.tr('action.add')));
      await tester.pump();
      expect(todoProvider.addCalls, 1);

      I18n.setLocale(AppLocale.en);
      await tester.pump();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('replacement route'))),
      );
      submitGate.complete();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('replacement route'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending time-log submit disables nested picker controls and cannot leave a duplicate draft',
    (tester) async {
      final submitGate = Completer<void>();
      final todoProvider = _FixtureTodoProvider();
      final timeAuditProvider = _FixtureTimeAuditProvider(addGate: submitGate);
      final observer = _RecordingNavigatorObserver();
      await tester.pumpWidget(
        _calendarApp(
          todoProvider: todoProvider,
          timeAuditProvider: timeAuditProvider,
          home: CalendarScreen(initialDate: DateTime(2021, 2, 1)),
          navigatorObservers: [observer],
        ),
      );
      await tester.pumpAndSettle();
      await _openTimeEntryDialog(tester);
      await tester.enterText(
        _timeEntryField(CalendarUiCopy.timeEntryTitleLabel),
        'pending time-log title',
      );

      await tester.tap(find.text(CalendarUiCopy.timeEntrySubmitButton));
      await tester.pump();
      expect(timeAuditProvider.addCalls, 1);
      final pushesBeforePickerAttempts = observer.pushed.length;
      final categoryField = _timeEntryCategoryField();
      await tester.ensureVisible(categoryField);
      await tester.tap(categoryField);
      await tester.pump(const Duration(milliseconds: 500));
      expect(observer.pushed.length, pushesBeforePickerAttempts);

      final startTimeTile = find.widgetWithText(
        ListTile,
        CalendarUiCopy.timeEntryStartTimeLabel,
      );
      await tester.ensureVisible(startTimeTile);
      await tester.tap(startTimeTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final pickerWasOpened = find.byType(AppModalSheet).evaluate().isNotEmpty;
      expect(observer.pushed.length, pushesBeforePickerAttempts);

      submitGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      final draftRemainsAfterCompletion = find
          .byType(AppDialog)
          .evaluate()
          .isNotEmpty;
      if (draftRemainsAfterCompletion) {
        await tester.tap(find.text(CalendarUiCopy.timeEntrySubmitButton));
        await tester.pumpAndSettle();
      }

      expect(pickerWasOpened, isFalse);
      expect(draftRemainsAfterCompletion, isFalse);
      expect(_timeEntryCategoryField(), findsNothing);
      expect(
        find.widgetWithText(ListTile, CalendarUiCopy.timeEntryStartTimeLabel),
        findsNothing,
      );
      expect(timeAuditProvider.addCalls, 1);
      expect(timeAuditProvider.addedEntries, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
