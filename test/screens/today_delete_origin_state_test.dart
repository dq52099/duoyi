import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/today_ui_copy.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/today_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

const _deleteButtonKey = ValueKey('today_todo_swipe_delete_button');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final surface in ['today_todo', 'today_reminder_todo']) {
    for (final change in ['account', 'provider']) {
      testWidgets(
        'Today completion rejects retained $change action on $surface',
        (tester) async {
          final now = DateTime.now();
          final item = _todo('reopen-origin', '完成状态来源').copyWith(
            dueDate: DateTime(now.year, now.month, now.day, 23, 59),
            isCompleted: true,
            completedAt: now,
          );
          final original = _FixtureTodoProvider([item]);
          final replacement = _FixtureTodoProvider([item]);
          final fixture = _TodayFixture(todos: original);
          await fixture.mount(tester);
          _registerCleanup(tester, fixture);
          addTearDown(() {
            if (change != 'provider') replacement.dispose();
          });
          if (surface == 'today_reminder_todo') {
            await tester.tap(
              find.byKey(const ValueKey('today_reminder_header_toggle')),
            );
            await tester.pumpAndSettle();
          }
          final tile = find.byKey(ValueKey('${surface}_${item.id}'));
          await tester.ensureVisible(tile);
          await tester.pumpAndSettle();
          final semantics = find.descendant(
            of: tile,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.checked != null,
            ),
          );
          final button = find.descendant(
            of: semantics,
            matching: find.byType(InkWell),
          );
          final retained = tester.widget<InkWell>(button).onTap!;
          if (change == 'account') {
            AccountLocalDataCleaner.invalidateInFlightAccountWrites();
          } else {
            fixture.replaceTodoProvider(replacement);
            await tester.pumpAndSettle();
          }
          retained();
          await tester.pumpAndSettle();
          expect(original.reopenRequests, isEmpty);
          expect(replacement.reopenRequests, isEmpty);
        },
      );
    }
  }

  testWidgets('retained Today delete opener rejects account generation reset', (
    tester,
  ) async {
    final todos = _FixtureTodoProvider([_todo('account-task', '原账号任务')]);
    final fixture = _TodayFixture(todos: todos);
    await fixture.mount(tester);
    _registerCleanup(tester, fixture);

    final retainedOpener = await _captureDeleteOpener(tester, '原账号任务');
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    retainedOpener();
    await tester.pumpAndSettle();

    expect(find.text(TodayUiCopy.deleteTaskTitle()), findsNothing);
    expect(todos.deleteRequests, isEmpty);

    await _openSwipe(tester, '原账号任务');
    await tester.tap(find.byKey(_deleteButtonKey).hitTestable());
    await tester.pumpAndSettle();
    await _confirmDelete(tester);

    expect(todos.deleteRequests, ['account-task']);
  });

  testWidgets('same-ID Today task reuse rejects its retained opener', (
    tester,
  ) async {
    final original = _todo('reused-task', '旧标题');
    final todos = _FixtureTodoProvider([original]);
    final fixture = _TodayFixture(todos: todos);
    await fixture.mount(tester);
    _registerCleanup(tester, fixture);

    final retainedOpener = await _captureDeleteOpener(tester, '旧标题');
    todos.replaceTodo(_todo('reused-task', '新标题'));
    await tester.pumpAndSettle();
    expect(find.text('新标题'), findsOneWidget);

    retainedOpener();
    await tester.pumpAndSettle();
    expect(find.text(TodayUiCopy.deleteTaskTitle()), findsNothing);
    expect(todos.deleteRequests, isEmpty);

    await _openSwipe(tester, '新标题');
    await tester.tap(find.byKey(_deleteButtonKey).hitTestable());
    await tester.pumpAndSettle();
    expect(find.text(TodayUiCopy.deleteTaskContent('新标题')), findsOneWidget);
    await _confirmDelete(tester);

    expect(todos.deleteRequests, ['reused-task']);
    expect(find.text('新标题'), findsNothing);
  });

  testWidgets('equivalent TodoProvider replacement rejects retained opener', (
    tester,
  ) async {
    final item = _todo('provider-task', '提供者任务');
    final originalProvider = _FixtureTodoProvider([item]);
    final replacementProvider = _FixtureTodoProvider([item]);
    final fixture = _TodayFixture(todos: originalProvider);
    await fixture.mount(tester);
    _registerCleanup(tester, fixture);

    final retainedOpener = await _captureDeleteOpener(tester, '提供者任务');
    fixture.replaceTodoProvider(replacementProvider);
    await tester.pumpAndSettle();

    expect(replacementProvider.revision, originalProvider.revision);
    expect(replacementProvider.todos.single, same(item));
    retainedOpener();
    await tester.pumpAndSettle();
    expect(find.text(TodayUiCopy.deleteTaskTitle()), findsNothing);
    expect(originalProvider.deleteRequests, isEmpty);
    expect(replacementProvider.deleteRequests, isEmpty);

    await _openSwipe(tester, '提供者任务');
    await tester.tap(find.byKey(_deleteButtonKey).hitTestable());
    await tester.pumpAndSettle();
    await _confirmDelete(tester);

    expect(originalProvider.deleteRequests, isEmpty);
    expect(replacementProvider.deleteRequests, ['provider-task']);
  });

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
      final auth = AuthProvider(initialState: state, baseUrl: 'http://fixture');
      final todos = _FixtureTodoProvider([_todo('auth-task', '会话任务')]);
      final fixture = _TodayFixture(todos: todos, auth: auth);
      await fixture.mount(tester);
      _registerCleanup(tester, fixture);

      final generationBefore = auth.sessionGeneration;
      await _openDeleteDialog(tester, '会话任务');
      final confirm = _dialogAction(tester, I18n.tr('action.delete'));
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
      final fixture = _TodayFixture(todos: todos, lock: lock);
      await fixture.mount(tester);
      _registerCleanup(tester, fixture);

      await _openDeleteDialog(tester, '锁定任务');
      final confirm = _dialogAction(tester, I18n.tr('action.delete'));
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
    final fixture = _TodayFixture(todos: todos, share: share);
    await fixture.mount(tester);
    _registerCleanup(tester, fixture);

    await _openDeleteDialog(tester, '共享任务');
    final confirm = _dialogAction(tester, I18n.tr('action.delete'));
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

  testWidgets('stale Today dialog callbacks cannot pop a covering route', (
    tester,
  ) async {
    final todos = _FixtureTodoProvider([_todo('covered-task', '覆盖任务')]);
    final fixture = _TodayFixture(todos: todos);
    await fixture.mount(tester);
    _registerCleanup(tester, fixture);

    await _openDeleteDialog(tester, '覆盖任务');
    final cancel = _dialogAction(tester, I18n.tr('action.cancel'));
    final confirm = _dialogAction(tester, I18n.tr('action.delete'));
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

    expect(find.text(TodayUiCopy.deleteTaskTitle()), findsNothing);
    expect(find.text('覆盖任务'), findsOneWidget);
    expect(todos.deleteRequests, isEmpty);
  });

  testWidgets('Today left-swipe delete and cancel work in zh and en', (
    tester,
  ) async {
    final tasks = <TodoItem>[];
    for (final locale in [AppLocale.zh, AppLocale.en]) {
      tasks
        ..add(_todo('cancel-${locale.name}', 'cancel ${locale.name}'))
        ..add(_todo('delete-${locale.name}', 'delete ${locale.name}'));
    }
    final todos = _FixtureTodoProvider(tasks);
    final fixture = _TodayFixture(todos: todos);
    await fixture.mount(tester);
    _registerCleanup(tester, fixture);

    for (final locale in [AppLocale.zh, AppLocale.en]) {
      I18n.setLocale(locale);
      await tester.pumpAndSettle();

      final cancelTitle = 'cancel ${locale.name}';
      final requestsBeforeCancel = List<String>.of(todos.deleteRequests);
      await _openDeleteDialog(tester, cancelTitle);
      expect(find.text(TodayUiCopy.deleteTaskTitle(locale)), findsOneWidget);
      expect(
        find.text(TodayUiCopy.deleteTaskContent(cancelTitle, locale)),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(TextButton, I18n.tr('action.cancel')),
      );
      await tester.pumpAndSettle();
      expect(todos.deleteRequests, requestsBeforeCancel);
      expect(find.text(cancelTitle), findsOneWidget);

      final deleteTitle = 'delete ${locale.name}';
      await _openDeleteDialog(tester, deleteTitle);
      await tester.tap(
        find.widgetWithText(FilledButton, I18n.tr('action.delete')),
      );
      await tester.pumpAndSettle();
      expect(todos.deleteRequests, contains('delete-${locale.name}'));
      expect(find.text(deleteTitle), findsNothing);
    }
  });
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
  expect(find.text(TodayUiCopy.deleteTaskTitle()), findsOneWidget);
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
  await tester.tap(find.widgetWithText(FilledButton, I18n.tr('action.delete')));
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

void _registerCleanup(WidgetTester tester, _TodayFixture fixture) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });
}

class _TodayFixture {
  _TodayFixture({
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

  final GlobalKey<_TodayHarnessState> harnessKey =
      GlobalKey<_TodayHarnessState>();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
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
      _TodayHarness(
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

class _TodayHarness extends StatefulWidget {
  const _TodayHarness({
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
  State<_TodayHarness> createState() => _TodayHarnessState();
}

class _TodayHarnessState extends State<_TodayHarness> {
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
        ChangeNotifierProvider(create: (_) => PomodoroProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => DiaryProvider()),
        ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
        ChangeNotifierProvider(create: (_) => CourseProvider()),
        ChangeNotifierProvider(create: (_) => GoalProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
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
        if (widget.shareProvider != null)
          ChangeNotifierProvider<ShareProvider>.value(
            value: widget.shareProvider!,
          ),
      ],
      child: MaterialApp(
        navigatorKey: widget.navigatorKey,
        home: const TodayScreen(),
      ),
    );
  }
}

class _FixtureTodoProvider extends TodoProvider {
  _FixtureTodoProvider(Iterable<TodoItem> initialTodos)
    : _items = [...initialTodos];

  final List<TodoItem> _items;
  final List<String> deleteRequests = [];
  final List<String> reopenRequests = [];
  int _fixtureRevision = 0;

  @override
  List<TodoItem> get todos => _items;

  @override
  int get revision => _fixtureRevision;

  void replaceTodo(TodoItem todo) {
    _items.removeWhere((item) => item.id == todo.id);
    _items.add(todo);
    _fixtureRevision++;
    notifyListeners();
  }

  @override
  Future<int> reopenTodos(Iterable<String> ids) async {
    reopenRequests.addAll(ids);
    return ids.length;
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
