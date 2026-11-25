import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/todo_board_ui_copy.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

const _deleteButtonKey = ValueKey('todo_swipe_delete_button');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final kanban in [false, true]) {
    group(kanban ? 'kanban delete origin' : 'list delete origin', () {
      testWidgets(
        'retained Todo delete opener rejects account generation reset',
        (tester) async {
          final todos = _FixtureTodoProvider([_todo('account-task', '原账号任务')]);
          final fixture = _TodoFixture(kanban: kanban, todos: todos);
          await fixture.mount(tester);
          _registerCleanup(tester, fixture);

          final retainedOpener = await _captureDeleteOpener(tester, '原账号任务');
          AccountLocalDataCleaner.invalidateInFlightAccountWrites();
          retainedOpener();
          await tester.pumpAndSettle();

          expect(
            find.text(TodoBoardUiCopy.deleteTaskDialogTitle),
            findsNothing,
          );
          expect(todos.deleteRequests, isEmpty);

          await _openSwipe(tester, '原账号任务');
          await tester.tap(find.byKey(_deleteButtonKey).hitTestable());
          await tester.pumpAndSettle();
          await _confirmDelete(tester);

          expect(todos.deleteRequests, ['account-task']);
        },
      );

      testWidgets('same-ID Todo task reuse rejects its retained opener', (
        tester,
      ) async {
        final original = _todo('reused-task', '旧标题');
        final todos = _FixtureTodoProvider([original]);
        final fixture = _TodoFixture(kanban: kanban, todos: todos);
        await fixture.mount(tester);
        _registerCleanup(tester, fixture);

        final retainedOpener = await _captureDeleteOpener(tester, '旧标题');
        todos.replaceTodo(_todo('reused-task', '新标题'));
        await tester.pumpAndSettle();
        expect(find.text('新标题'), findsOneWidget);

        retainedOpener();
        await tester.pumpAndSettle();
        expect(find.text(TodoBoardUiCopy.deleteTaskDialogTitle), findsNothing);
        expect(todos.deleteRequests, isEmpty);

        await _openSwipe(tester, '新标题');
        await tester.tap(find.byKey(_deleteButtonKey).hitTestable());
        await tester.pumpAndSettle();
        expect(
          find.text(TodoBoardUiCopy.deleteTaskDialogContent('新标题')),
          findsOneWidget,
        );
        await _confirmDelete(tester);

        expect(todos.deleteRequests, ['reused-task']);
        expect(find.text('新标题'), findsNothing);
      });

      testWidgets(
        'equivalent TodoProvider replacement rejects retained opener',
        (tester) async {
          final item = _todo('provider-task', '提供者任务');
          final originalProvider = _FixtureTodoProvider([item]);
          final replacementProvider = _FixtureTodoProvider([item]);
          final fixture = _TodoFixture(kanban: kanban, todos: originalProvider);
          await fixture.mount(tester);
          _registerCleanup(tester, fixture);

          final retainedOpener = await _captureDeleteOpener(tester, '提供者任务');
          fixture.replaceTodoProvider(replacementProvider);
          await tester.pumpAndSettle();

          expect(replacementProvider.revision, originalProvider.revision);
          expect(replacementProvider.todos.single, same(item));
          retainedOpener();
          await tester.pumpAndSettle();
          expect(
            find.text(TodoBoardUiCopy.deleteTaskDialogTitle),
            findsNothing,
          );
          expect(originalProvider.deleteRequests, isEmpty);
          expect(replacementProvider.deleteRequests, isEmpty);

          await _openSwipe(tester, '提供者任务');
          await tester.tap(find.byKey(_deleteButtonKey).hitTestable());
          await tester.pumpAndSettle();
          await _confirmDelete(tester);

          expect(originalProvider.deleteRequests, isEmpty);
          expect(replacementProvider.deleteRequests, ['provider-task']);
        },
      );

      testWidgets(
        'same-user auth session rotation after confirmation blocks delete',
        (tester) async {
          const state = AuthState(
            userId: 'same-user',
            username: 'same-user',
            token: 'same-session-token',
          );
          final preferences = await SharedPreferences.getInstance();
          await preferences.setString('auth_state', jsonEncode(state.toJson()));
          await preferences.setString(
            AccountLocalDataCleaner.accountDataOwnerKey,
            'id:same-user',
          );
          final auth = AuthProvider(
            initialState: state,
            baseUrl: 'http://fixture',
          );
          final todos = _FixtureTodoProvider([_todo('auth-task', '会话任务')]);
          final fixture = _TodoFixture(
            kanban: kanban,
            todos: todos,
            auth: auth,
          );
          await fixture.mount(tester);
          _registerCleanup(tester, fixture);

          final generationBefore = auth.sessionGeneration;
          await _openDeleteDialog(tester, '会话任务');
          final confirm = _dialogAction(tester, TodoBoardUiCopy.delete);
          confirm();
          final rotation = auth.loadFromStorage(refreshServerConfig: false);
          expect(auth.state.userId, 'same-user');
          expect(auth.sessionGeneration, greaterThan(generationBefore));
          await rotation;
          await tester.pumpAndSettle();

          expect(auth.state.userId, 'same-user');
          expect(todos.deleteRequests, isEmpty);
          expect(find.text('会话任务'), findsOneWidget);

          await _openSwipe(tester, '会话任务');
          await tester.tap(find.byKey(_deleteButtonKey).hitTestable());
          await tester.pumpAndSettle();
          await _confirmDelete(tester);
          expect(todos.deleteRequests, ['auth-task']);
        },
      );

      testWidgets(
        'locking after confirmation blocks delete and fresh action works',
        (tester) async {
          final lock = AppLockProvider();
          expect(await lock.setPin('2468'), isTrue);
          final todos = _FixtureTodoProvider([_todo('locked-task', '锁定任务')]);
          final fixture = _TodoFixture(
            kanban: kanban,
            todos: todos,
            lock: lock,
          );
          await fixture.mount(tester);
          _registerCleanup(tester, fixture);

          await _openDeleteDialog(tester, '锁定任务');
          final confirm = _dialogAction(tester, TodoBoardUiCopy.delete);
          confirm();
          lock.lock();
          await tester.pumpAndSettle();

          expect(lock.isLocked, isTrue);
          expect(todos.deleteRequests, isEmpty);
          expect(find.text('锁定任务'), findsOneWidget);

          await lock.unlockWith('2468');
          await _openSwipe(tester, '锁定任务');
          await tester.tap(find.byKey(_deleteButtonKey).hitTestable());
          await tester.pumpAndSettle();
          await _confirmDelete(tester);
          expect(todos.deleteRequests, ['locked-task']);
        },
      );

      testWidgets('Share edit revocation after confirmation blocks delete', (
        tester,
      ) async {
        final share = _FixtureShareProvider();
        final todos = _FixtureTodoProvider([
          _todo('shared-task', '共享任务', workspaceId: 'fixture-workspace'),
        ]);
        final fixture = _TodoFixture(
          kanban: kanban,
          todos: todos,
          share: share,
        );
        await fixture.mount(tester);
        _registerCleanup(tester, fixture);

        await _openDeleteDialog(tester, '共享任务');
        final confirm = _dialogAction(tester, TodoBoardUiCopy.delete);
        confirm();
        share.setCanEdit(false);
        await tester.pumpAndSettle();

        expect(share.canEdit('fixture-workspace'), isFalse);
        expect(todos.deleteRequests, isEmpty);
        expect(find.text('共享任务'), findsOneWidget);

        share.setCanEdit(true);
        await _openSwipe(tester, '共享任务');
        await tester.tap(find.byKey(_deleteButtonKey).hitTestable());
        await tester.pumpAndSettle();
        await _confirmDelete(tester);
        expect(todos.deleteRequests, ['shared-task']);
      });

      testWidgets('stale Todo dialog callbacks cannot pop a covering route', (
        tester,
      ) async {
        final todos = _FixtureTodoProvider([_todo('covered-task', '覆盖任务')]);
        final fixture = _TodoFixture(kanban: kanban, todos: todos);
        await fixture.mount(tester);
        _registerCleanup(tester, fixture);

        await _openDeleteDialog(tester, '覆盖任务');
        final cancel = _dialogAction(tester, TodoBoardUiCopy.cancel);
        final confirm = _dialogAction(tester, TodoBoardUiCopy.delete);
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        _pushCoveringRoute(fixture.navigatorKey);
        await tester.pumpAndSettle();

        confirm();
        cancel();
        await tester.pumpAndSettle();
        expect(find.text('covering route'), findsOneWidget);
        expect(todos.deleteRequests, isEmpty);

        fixture.navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
        cancel();
        await tester.pumpAndSettle();

        expect(find.text(TodoBoardUiCopy.deleteTaskDialogTitle), findsNothing);
        expect(find.text('覆盖任务'), findsOneWidget);
        expect(todos.deleteRequests, isEmpty);
      });

      testWidgets('Todo left-swipe delete and cancel work in zh and en', (
        tester,
      ) async {
        final tasks = <TodoItem>[];
        for (final locale in [AppLocale.zh, AppLocale.en]) {
          tasks
            ..add(_todo('cancel-${locale.name}', 'cancel ${locale.name}'))
            ..add(_todo('delete-${locale.name}', 'delete ${locale.name}'));
        }
        final todos = _FixtureTodoProvider(tasks);
        final fixture = _TodoFixture(kanban: kanban, todos: todos);
        await fixture.mount(tester);
        _registerCleanup(tester, fixture);

        for (final locale in [AppLocale.zh, AppLocale.en]) {
          I18n.setLocale(locale);
          await tester.pumpAndSettle();

          final cancelTitle = 'cancel ${locale.name}';
          final requestsBeforeCancel = List<String>.of(todos.deleteRequests);
          await _openDeleteDialog(tester, cancelTitle);
          expect(
            find.text(TodoBoardUiCopy.deleteTaskDialogTitle),
            findsOneWidget,
          );
          expect(
            find.text(TodoBoardUiCopy.deleteTaskDialogContent(cancelTitle)),
            findsOneWidget,
          );
          await tester.tap(
            find.widgetWithText(TextButton, TodoBoardUiCopy.cancel),
          );
          await tester.pumpAndSettle();
          expect(todos.deleteRequests, requestsBeforeCancel);
          expect(find.text(cancelTitle), findsOneWidget);

          final deleteTitle = 'delete ${locale.name}';
          await _openDeleteDialog(tester, deleteTitle);
          await tester.tap(
            find.widgetWithText(FilledButton, TodoBoardUiCopy.delete),
          );
          await tester.pumpAndSettle();
          expect(todos.deleteRequests, contains('delete-${locale.name}'));
          expect(find.text(deleteTitle), findsNothing);
        }
      });
      testWidgets(
        'visible single delete dialog follows zh-en-zh without changing raw title',
        (tester) async {
          final todos = _FixtureTodoProvider([
            _todo('locale-task', '原文 Raw 123'),
          ]);
          final fixture = _TodoFixture(kanban: kanban, todos: todos);
          await fixture.mount(tester);
          _registerCleanup(tester, fixture);
          await _openDeleteDialog(tester, '原文 Raw 123');
          final dialogElement = find.byType(Dialog).evaluate().single;
          for (final locale in [AppLocale.en, AppLocale.zh]) {
            I18n.setLocale(locale);
            await tester.pumpAndSettle();
            expect(
              find.text(TodoBoardUiCopy.deleteTaskDialogTitle),
              findsOneWidget,
            );
            expect(
              find.text(TodoBoardUiCopy.deleteTaskDialogContent('原文 Raw 123')),
              findsOneWidget,
            );
            expect(find.byType(Dialog).evaluate().single, same(dialogElement));
            expect(todos.deleteRequests, isEmpty);
            expect(tester.takeException(), isNull);
          }
          await tester.tap(
            find.widgetWithText(TextButton, TodoBoardUiCopy.cancel),
          );
          await tester.pumpAndSettle();
          expect(todos.deleteRequests, isEmpty);
        },
      );
    });
  }
}

TodoItem _todo(String id, String title, {String workspaceId = 'private'}) {
  final now = DateTime.now();
  return TodoItem(
    id: id,
    title: title,
    workspaceId: workspaceId,
    date: DateTime(now.year, now.month, now.day),
  );
}

Future<void> _openSwipe(WidgetTester tester, String title) async {
  final titleFinder = find.text(title);
  await tester.ensureVisible(titleFinder);
  await tester.pumpAndSettle();
  await tester.drag(titleFinder, const Offset(-180, 0));
  await tester.pumpAndSettle();
  expect(find.byKey(_deleteButtonKey).hitTestable(), findsOneWidget);
}

Future<void> _openDeleteDialog(WidgetTester tester, String title) async {
  await _openSwipe(tester, title);
  await tester.tap(find.byKey(_deleteButtonKey).hitTestable());
  await tester.pumpAndSettle();
  expect(find.text(TodoBoardUiCopy.deleteTaskDialogTitle), findsOneWidget);
}

Future<VoidCallback> _captureDeleteOpener(
  WidgetTester tester,
  String title,
) async {
  await _openSwipe(tester, title);
  final button = find.byKey(_deleteButtonKey);
  final inkWellFinder = find.descendant(
    of: button,
    matching: find.byType(InkWell),
  );
  return tester.widget<InkWell>(inkWellFinder.first).onTap!;
}

VoidCallback _dialogAction(WidgetTester tester, String label) {
  final cancel = find.widgetWithText(TextButton, label);
  if (cancel.evaluate().isNotEmpty) {
    return tester.widget<TextButton>(cancel).onPressed!;
  }
  return tester
      .widget<FilledButton>(find.widgetWithText(FilledButton, label))
      .onPressed!;
}

Future<void> _confirmDelete(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, TodoBoardUiCopy.delete));
  await tester.pumpAndSettle();
}

void _pushCoveringRoute(GlobalKey<NavigatorState> navigatorKey) {
  navigatorKey.currentState!
      .push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: Center(child: Text('covering route'))),
        ),
      )
      .then<void>((_) {});
}

void _registerCleanup(WidgetTester tester, _TodoFixture fixture) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });
}

class _TodoFixture {
  _TodoFixture({
    required this.kanban,
    required TodoProvider todos,
    AuthProvider? auth,
    AppLockProvider? lock,
    PreferencesProvider? preferences,
    _FixtureShareProvider? share,
  }) : _todos = todos,
       _auth = auth,
       _lock = lock,
       _preferences = preferences,
       _share = share,
       _notifiers = {todos, ?auth, ?lock, ?preferences, ?share};

  final GlobalKey<_TodoHarnessState> harnessKey =
      GlobalKey<_TodoHarnessState>();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final bool kanban;
  TodoProvider _todos;
  final AuthProvider? _auth;
  final AppLockProvider? _lock;
  final PreferencesProvider? _preferences;
  final _FixtureShareProvider? _share;
  final Set<ChangeNotifier> _notifiers;

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _TodoHarness(
        key: harnessKey,
        todoProvider: _todos,
        authProvider: _auth,
        lockProvider: _lock,
        preferencesProvider: _preferences,
        shareProvider: _share,
        navigatorKey: navigatorKey,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(kanban ? TodoBoardUiCopy.viewKanban : TodoBoardUiCopy.viewList),
    );
    await tester.pumpAndSettle();
  }

  void replaceTodoProvider(TodoProvider provider) {
    _notifiers.add(provider);
    _todos = provider;
    harnessKey.currentState!.replaceTodoProvider(provider);
  }

  void dispose() {
    for (final notifier in _notifiers) {
      notifier.dispose();
    }
  }
}

class _TodoHarness extends StatefulWidget {
  const _TodoHarness({
    super.key,
    required this.todoProvider,
    required this.navigatorKey,
    this.authProvider,
    this.lockProvider,
    this.preferencesProvider,
    this.shareProvider,
  });

  final TodoProvider todoProvider;
  final GlobalKey<NavigatorState> navigatorKey;
  final AuthProvider? authProvider;
  final AppLockProvider? lockProvider;
  final PreferencesProvider? preferencesProvider;
  final _FixtureShareProvider? shareProvider;

  @override
  State<_TodoHarness> createState() => _TodoHarnessState();
}

class _TodoHarnessState extends State<_TodoHarness> {
  late TodoProvider _todoProvider = widget.todoProvider;

  void replaceTodoProvider(TodoProvider provider) {
    setState(() => _todoProvider = provider);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<TodoProvider>.value(value: _todoProvider),
        ChangeNotifierProvider(create: (_) => HabitProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AiService()),
        ChangeNotifierProvider(create: (_) => GoalProvider()),
        if (widget.authProvider == null)
          ChangeNotifierProvider(create: (_) => AuthProvider()),
        if (widget.authProvider != null)
          ChangeNotifierProvider<AuthProvider>.value(
            value: widget.authProvider!,
          ),
        if (widget.lockProvider != null)
          ChangeNotifierProvider<AppLockProvider>.value(
            value: widget.lockProvider!,
          ),
        if (widget.preferencesProvider != null)
          ChangeNotifierProvider<PreferencesProvider>.value(
            value: widget.preferencesProvider!,
          ),
        if (widget.shareProvider == null)
          ChangeNotifierProvider(create: (_) => ShareProvider()),
        if (widget.shareProvider != null)
          ChangeNotifierProvider<ShareProvider>.value(
            value: widget.shareProvider!,
          ),
      ],
      child: MaterialApp(
        navigatorKey: widget.navigatorKey,
        home: const TodoScreen(),
      ),
    );
  }
}

class _FixtureTodoProvider extends TodoProvider {
  _FixtureTodoProvider(Iterable<TodoItem> initialTodos)
    : _items = [...initialTodos];

  final List<TodoItem> _items;
  final List<String> deleteRequests = [];
  int _fixtureRevision = 0;

  @override
  List<TodoItem> get todos => _items;

  @override
  List<TodoItem> get visibleListTodos => _items;

  @override
  int get revision => _fixtureRevision;

  void replaceTodo(TodoItem todo) {
    _items.removeWhere((item) => item.id == todo.id);
    _items.add(todo);
    _fixtureRevision++;
    notifyListeners();
  }

  @override
  Future<void> deleteTodo(String id) async {
    deleteRequests.add(id);
    _items.removeWhere((item) => item.id == id);
    _fixtureRevision++;
    notifyListeners();
  }
}

class _FixtureShareProvider extends ShareProvider {
  bool _canEditFixtureWorkspace = true;

  @override
  bool canEdit(String? workspaceId) {
    if (workspaceId == 'fixture-workspace') {
      return _canEditFixtureWorkspace;
    }
    return super.canEdit(workspaceId);
  }

  void setCanEdit(bool value) {
    _canEditFixtureWorkspace = value;
    notifyListeners();
  }
}
