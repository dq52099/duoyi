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
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _draftTitle = '原始待办字段：整理项目资料 📝';
const _authState = AuthState(
  userId: 'create-feedback-user',
  username: 'create-feedback-user',
  token: 'create-feedback-session',
);
const _createFailedZh = '创建失败，请稍后重试';
const _createFailedEn = 'Failed to create, please try again later';

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
    'quick create empty StateError fallback follows zh-en-zh without repeating the save or changing the draft/account',
    (tester) async {
      final fixture = await _submitQuickCreateFailure(
        tester,
        stateErrorMessage: '',
      );

      _expectFailureState(fixture, tester, snackbarText: _createFailedZh);

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      _expectFailureState(fixture, tester, snackbarText: _createFailedEn);

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      _expectFailureState(fixture, tester, snackbarText: _createFailedZh);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'quick create preserves a non-empty StateError message verbatim through zh-en-zh',
    (tester) async {
      const rawMessage = '原始平台诊断：EACCES 0xE17';
      final fixture = await _submitQuickCreateFailure(
        tester,
        stateErrorMessage: rawMessage,
      );

      _expectFailureState(fixture, tester, snackbarText: rawMessage);

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      _expectFailureState(fixture, tester, snackbarText: rawMessage);

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      _expectFailureState(fixture, tester, snackbarText: rawMessage);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<_FailureFixture> _submitQuickCreateFailure(
  WidgetTester tester, {
  required String stateErrorMessage,
}) async {
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final todos = _ThrowingTodoProvider(stateErrorMessage);
  final habits = HabitProvider();
  final goals = GoalProvider();
  final theme = ThemeProvider();
  final ai = AiService();
  final share = ShareProvider();
  final auth = AuthProvider(initialState: _authState);
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
  expect(find.byType(TodoScreen), findsOneWidget);
  expect(tester.takeException(), isNull);

  final authStateBefore = auth.state;
  final authJsonBefore = authStateBefore.toJson();
  final accountGenerationBefore = AccountLocalDataCleaner.accountDataGeneration;
  final todoRevisionBefore = todos.revision;
  final notifications = _NotificationCounts();
  todos.addListener(() => notifications.todos++);
  auth.addListener(() => notifications.auth++);

  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
  final sheet = find.byType(BottomSheet);
  expect(sheet, findsOneWidget, reason: 'FAB must open the actual add sheet');

  final titleField = find
      .descendant(of: sheet, matching: find.byType(TextField))
      .first;
  await tester.enterText(titleField, _draftTitle);
  await tester.pumpAndSettle();

  final highPriority = find.descendant(of: sheet, matching: find.text('高'));
  expect(highPriority, findsOneWidget);
  await tester.ensureVisible(highPriority);
  await tester.tap(highPriority);
  await tester.pumpAndSettle();

  final titleController = tester.widget<TextField>(titleField).controller!;
  final titleValueBefore = titleController.value;
  final addButton = find.descendant(
    of: sheet,
    matching: find.widgetWithText(ElevatedButton, TodoBoardUiCopy.addTask),
  );
  expect(addButton, findsOneWidget);
  final submitContextFinder = find.ancestor(
    of: addButton,
    matching: find.byWidgetPredicate(
      (widget) => widget is ValueListenableBuilder<AppLocale>,
      description: 'locale builder that owns the quick-create submit callback',
    ),
  );
  expect(submitContextFinder, findsOneWidget);
  final submitContext = tester.element(submitContextFinder);
  expect(submitContext.mounted, isTrue);

  await tester.ensureVisible(addButton);
  await tester.tap(addButton);
  await tester.pumpAndSettle();

  expect(todos.addTodoWithResultCalls, 1);
  expect(todos.lastWaitForReminderSync, isFalse);
  expect(todos.lastReportReminderScheduleFailure, isFalse);
  expect(todos.submittedTodos, hasLength(1));
  final submittedTodo = todos.submittedTodos.single;
  expect(submittedTodo.title, _draftTitle);
  expect(submittedTodo.priority, TodoPriority.high);
  expect(submittedTodo.quadrant, EisenhowerQuadrant.notUrgentImportant);
  expect(submittedTodo.listGroupName, isNull);
  expect(submittedTodo.workspaceId, 'private');
  expect(submittedTodo.createdBy, authStateBefore.userId);
  expect(submittedTodo.updatedBy, authStateBefore.userId);
  expect(submittedTodo.hasReminder, isFalse);

  return _FailureFixture(
    harness: harness,
    sheet: sheet,
    titleField: titleField,
    titleController: titleController,
    titleValueBefore: titleValueBefore,
    submitContext: submitContext,
    submittedTodo: submittedTodo,
    submittedTodoJsonBefore: submittedTodo.toJson(),
    authStateBefore: authStateBefore,
    authJsonBefore: authJsonBefore,
    accountGenerationBefore: accountGenerationBefore,
    todoRevisionBefore: todoRevisionBefore,
    notifications: notifications,
  );
}

void _expectFailureState(
  _FailureFixture fixture,
  WidgetTester tester, {
  required String snackbarText,
}) {
  final snackbar = find.byType(SnackBar);
  expect(snackbar, findsOneWidget);
  expect(
    find.descendant(of: snackbar, matching: find.text(snackbarText)),
    findsOneWidget,
  );

  expect(find.byType(BottomSheet), findsOneWidget);
  expect(tester.element(fixture.sheet).mounted, isTrue);
  // This is the ValueListenableBuilder BuildContext captured by the actual
  // quick-create onPressed closure, so the catch block's ctx.mounted guard ran
  // while that same context was mounted.
  expect(fixture.submitContext.mounted, isTrue);

  expect(
    tester.widget<TextField>(fixture.titleField).controller,
    same(fixture.titleController),
  );
  expect(fixture.titleController.value, fixture.titleValueBefore);
  expect(fixture.titleController.text, _draftTitle);
  final selectedPriorities = tester
      .widgetList<ChoiceChip>(
        find.descendant(of: fixture.sheet, matching: find.byType(ChoiceChip)),
      )
      .where((chip) => chip.selected)
      .toList();
  expect(selectedPriorities, hasLength(1));
  expect(
    (selectedPriorities.single.label as Text).data,
    TodoPriority.high.label,
  );

  final todos = fixture.harness.todos;
  expect(todos.addTodoWithResultCalls, 1);
  expect(todos.lastWaitForReminderSync, isFalse);
  expect(todos.lastReportReminderScheduleFailure, isFalse);
  expect(todos.submittedTodos, hasLength(1));
  expect(identical(todos.submittedTodos.single, fixture.submittedTodo), isTrue);
  expect(fixture.submittedTodo.toJson(), fixture.submittedTodoJsonBefore);
  expect(fixture.submittedTodo.title, _draftTitle);
  expect(fixture.submittedTodo.priority, TodoPriority.high);
  expect(fixture.submittedTodo.quadrant, EisenhowerQuadrant.notUrgentImportant);
  expect(fixture.submittedTodo.listGroupName, isNull);
  expect(fixture.submittedTodo.workspaceId, 'private');
  expect(fixture.submittedTodo.createdBy, fixture.authStateBefore.userId);
  expect(fixture.submittedTodo.updatedBy, fixture.authStateBefore.userId);
  expect(fixture.submittedTodo.hasReminder, isFalse);
  expect(todos.todos, isEmpty);
  expect(todos.revision, fixture.todoRevisionBefore);
  expect(fixture.harness.auth.state, same(fixture.authStateBefore));
  expect(fixture.harness.auth.state.toJson(), fixture.authJsonBefore);
  expect(
    AccountLocalDataCleaner.accountDataGeneration,
    fixture.accountGenerationBefore,
  );
  expect(fixture.notifications.todos, 0);
  expect(fixture.notifications.auth, 0);
}

class _ThrowingTodoProvider extends TodoProvider {
  _ThrowingTodoProvider(this.stateErrorMessage);

  final String stateErrorMessage;
  final List<TodoItem> submittedTodos = [];
  int addTodoWithResultCalls = 0;
  bool? lastWaitForReminderSync;
  bool? lastReportReminderScheduleFailure;

  @override
  Future<TodoReminderSyncResult?> addTodoWithResult(
    TodoItem todo, {
    bool waitForReminderSync = true,
    bool reportReminderScheduleFailure = false,
    bool Function()? canWrite,
  }) async {
    addTodoWithResultCalls++;
    lastWaitForReminderSync = waitForReminderSync;
    lastReportReminderScheduleFailure = reportReminderScheduleFailure;
    submittedTodos.add(todo);
    throw StateError(stateErrorMessage);
  }
}

class _NotificationCounts {
  int todos = 0;
  int auth = 0;
}

class _FailureFixture {
  const _FailureFixture({
    required this.harness,
    required this.sheet,
    required this.titleField,
    required this.titleController,
    required this.titleValueBefore,
    required this.submitContext,
    required this.submittedTodo,
    required this.submittedTodoJsonBefore,
    required this.authStateBefore,
    required this.authJsonBefore,
    required this.accountGenerationBefore,
    required this.todoRevisionBefore,
    required this.notifications,
  });

  final _TodoHarness harness;
  final Finder sheet;
  final Finder titleField;
  final TextEditingController titleController;
  final TextEditingValue titleValueBefore;
  final BuildContext submitContext;
  final TodoItem submittedTodo;
  final Map<String, dynamic> submittedTodoJsonBefore;
  final AuthState authStateBefore;
  final Map<String, dynamic> authJsonBefore;
  final int accountGenerationBefore;
  final int todoRevisionBefore;
  final _NotificationCounts notifications;
}

class _TodoHarness {
  const _TodoHarness({
    required this.todos,
    required this.habits,
    required this.goals,
    required this.theme,
    required this.ai,
    required this.share,
    required this.auth,
  });

  final _ThrowingTodoProvider todos;
  final HabitProvider habits;
  final GoalProvider goals;
  final ThemeProvider theme;
  final AiService ai;
  final ShareProvider share;
  final AuthProvider auth;

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
