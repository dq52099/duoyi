import 'dart:async';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/todo_board_ui_copy.dart';
import 'package:duoyi/core/todo_kanban.dart';
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
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

const _taskTitle = '账号边界中保留的真实任务';
const _aBuiltInTitle = '账号A自定义待办列';
const _aCustomTitle = '账号A自定义列';
const _aCustomId = 'account_a_custom_column';
const _bBuiltInTitle = '账号B自定义待办列';
const _bCustomTitle = '账号B自定义列';
const _bCustomId = 'account_b_custom_column';
const _cBuiltInTitle = '账号C自定义待办列';
const _cCustomTitle = '账号C自定义列';
const _cCustomId = 'account_c_custom_column';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
    await AccountPreferenceWrites.drain();
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'account generation clears A immediately, waits for boundary and auth, then loads B without locale writes',
    (tester) async {
      final harness = await _pumpKanbanHarness(tester);
      final screen = find.byType(TodoScreen);
      final screenState = tester.state(screen);
      _expectConfigA(tester);
      _expectSettingsEnabled(tester);

      final enteredBoundary = Completer<void>();
      final releaseBoundary = Completer<void>();
      final boundary = AccountPreferenceWrites.boundary(() async {
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        await harness.preferences.setString(
          todoKanbanColumnsPrefsKey,
          _configB().encode(),
        );
        harness.auth.setAvailability(transition: true);
        enteredBoundary.complete();
        await releaseBoundary.future;
      });
      addTearDown(() async {
        final settled = boundary.then<void>((_) {});
        if (!releaseBoundary.isCompleted) releaseBoundary.complete();
        await tester.pump();
        await settled;
      });
      await enteredBoundary.future;
      await tester.pumpAndSettle();

      expect(tester.state(screen), same(screenState));
      _expectDefaultColumns(tester);
      _expectSettingsDisabled(tester);
      expect(
        harness.preferences.getString(todoKanbanColumnsPrefsKey),
        _configB().encode(),
      );
      expect(
        harness.store.configWriteCount,
        1,
        reason: '${harness.store.writes}',
      );

      releaseBoundary.complete();
      await boundary;
      await tester.pumpAndSettle();

      expect(tester.state(screen), same(screenState));
      _expectDefaultColumns(tester);
      _expectSettingsDisabled(tester);
      expect(
        harness.preferences.getString(todoKanbanColumnsPrefsKey),
        _configB().encode(),
      );

      harness.store.writes.clear();
      harness.auth.setAvailability(transition: false);
      await tester.pumpAndSettle();

      expect(tester.state(screen), same(screenState));
      _expectConfigB(tester);
      _expectSettingsEnabled(tester);
      expect(harness.store.configWriteCount, 0);

      for (final locale in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        _expectConfigB(tester);
        expect(tester.state(screen), same(screenState));
        expect(harness.store.configWriteCount, 0);
        expect(
          harness.preferences.getString(todoKanbanColumnsPrefsKey),
          _configB().encode(),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'logout clears the stored board and blocked auth keeps settings disabled until recovery',
    (tester) async {
      final harness = await _pumpKanbanHarness(tester);
      final screen = find.byType(TodoScreen);
      final screenState = tester.state(screen);
      _expectConfigA(tester);

      final boundary = AccountPreferenceWrites.boundary(() async {
        harness.auth.setAvailability(transition: true, blocked: true);
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        await harness.preferences.remove(todoKanbanColumnsPrefsKey);
      });
      await boundary;
      await tester.pumpAndSettle();

      expect(tester.state(screen), same(screenState));
      expect(harness.preferences.getString(todoKanbanColumnsPrefsKey), isNull);
      _expectDefaultColumns(tester);
      _expectSettingsDisabled(tester);

      harness.store.writes.clear();
      harness.auth.setAvailability(transition: false);
      await tester.pumpAndSettle();

      _expectDefaultColumns(tester);
      _expectSettingsDisabled(tester);
      expect(harness.store.configWriteCount, 0);

      harness.auth.setAvailability(blocked: false);
      await tester.pumpAndSettle();

      expect(tester.state(screen), same(screenState));
      _expectDefaultColumns(tester);
      _expectSettingsEnabled(tester);
      expect(find.text(_taskTitle), findsOneWidget);
      expect(harness.store.configWriteCount, 0);
      expect(harness.preferences.getString(todoKanbanColumnsPrefsKey), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'replacing AuthProvider clears retained account config and reloads the replacement account',
    (tester) async {
      final harness = await _pumpKanbanHarness(tester);
      final screen = find.byType(TodoScreen);
      final screenState = tester.state(screen);
      _expectConfigA(tester);

      await harness.preferences.setString(
        todoKanbanColumnsPrefsKey,
        _configB().encode(),
      );
      harness.store.writes.clear();
      final replacement = _ControlledAuthProvider(transition: true);
      harness.replaceAuth(replacement);
      await tester.pumpAndSettle();

      expect(tester.state(screen), same(screenState));
      _expectDefaultColumns(tester);
      _expectSettingsDisabled(tester);
      expect(find.text(_aBuiltInTitle), findsNothing);
      expect(find.text(_aCustomTitle), findsNothing);
      expect(find.text(_bBuiltInTitle), findsNothing);
      expect(find.text(_bCustomTitle), findsNothing);

      replacement.setAvailability(transition: false);
      await tester.pumpAndSettle();

      expect(tester.state(screen), same(screenState));
      _expectConfigB(tester);
      _expectSettingsEnabled(tester);
      expect(harness.store.configWriteCount, 0);
      expect(
        harness.preferences.getString(todoKanbanColumnsPrefsKey),
        _configB().encode(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a genuine stale B read is rejected during C transition before current C config loads',
    (tester) async {
      final harness = await _pumpKanbanHarness(tester);
      final screen = find.byType(TodoScreen);
      final screenState = tester.state(screen);
      _expectConfigA(tester);

      final storedTodos = harness.preferences.getString('todos');
      SharedPreferences.setMockInitialValues(<String, Object>{
        todoKanbanColumnsPrefsKey: _configB().encode(),
        'todos': ?storedTodos,
      });
      final delayedBStore = _DelayedReadPreferencesStore(
        SharedPreferencesStorePlatform.instance,
      );
      addTearDown(delayedBStore.releaseRead);
      SharedPreferencesStorePlatform.instance = delayedBStore;

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      await tester.pump();
      await delayedBStore.readStarted;
      await tester.pumpAndSettle();

      expect(tester.state(screen), same(screenState));
      _expectDefaultColumns(tester);
      _expectSettingsDisabled(tester);

      harness.auth.setAvailability(transition: true);
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      await tester.pumpAndSettle();

      expect(tester.state(screen), same(screenState));
      _expectDefaultColumns(tester);
      _expectSettingsDisabled(tester);

      delayedBStore.releaseRead();
      await tester.pumpAndSettle();
      final loadedB = await SharedPreferences.getInstance();
      expect(loadedB.getString(todoKanbanColumnsPrefsKey), _configB().encode());
      _expectDefaultColumns(tester);
      _expectSettingsDisabled(tester);

      await AccountPreferenceWrites.boundary(() async {
        await loadedB.setString(todoKanbanColumnsPrefsKey, _configC().encode());
      });
      harness.auth.setAvailability(transition: false);
      await tester.pumpAndSettle();

      _expectConfigC(tester);
      _expectSettingsEnabled(tester);
      expect(find.text(_bBuiltInTitle), findsNothing);
      expect(find.text(_bCustomTitle), findsNothing);
      expect(find.text(_taskTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<_TodoHydrationHarness> _pumpKanbanHarness(WidgetTester tester) async {
  final config = _configA();
  SharedPreferences.setMockInitialValues(<String, Object>{
    todoKanbanColumnsPrefsKey: config.encode(),
  });
  final store = _RecordingPreferencesStore(
    SharedPreferencesStorePlatform.instance,
  );
  SharedPreferencesStorePlatform.instance = store;
  final preferences = await SharedPreferences.getInstance();
  final todos = TodoProvider();
  await todos.addTodo(
    TodoItem(title: _taskTitle, kanbanColumnId: _aCustomId),
    waitForReminderSync: false,
  );
  await AccountPreferenceWrites.drain();
  store.writes.clear();

  final habits = HabitProvider();
  final goals = GoalProvider();
  final theme = ThemeProvider();
  final ai = AiService();
  final share = ShareProvider();
  final auth = _ControlledAuthProvider();
  final harness = _TodoHydrationHarness(
    preferences: preferences,
    store: store,
    todos: todos,
    habits: habits,
    goals: goals,
    theme: theme,
    ai: ai,
    share: share,
    auth: auth,
  );

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1600, 1000);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final drained = AccountPreferenceWrites.drain();
    await tester.pump();
    await drained;
    harness.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'TodoScreen must mount');
  await tester.tap(find.text(TodoBoardUiCopy.viewKanban));
  await tester.pumpAndSettle();
  _expectConfigA(tester);
  expect(tester.takeException(), isNull);
  return harness;
}

TodoKanbanBoardConfig _configA() {
  final defaults = TodoKanbanBoardConfig.defaults();
  return defaults.copyWith(
    groupMode: TodoKanbanGroupMode.tag,
    columns: [
      for (final column in defaults.sortedColumns)
        column.id == defaultKanbanPendingColumnId
            ? column.copyWith(title: _aBuiltInTitle)
            : column,
      const TodoKanbanColumn(
        id: _aCustomId,
        title: _aCustomTitle,
        colorValue: 0xFF7B1FA2,
        sortOrder: 3,
      ),
    ],
  );
}

TodoKanbanBoardConfig _configB() {
  final defaults = TodoKanbanBoardConfig.defaults();
  return defaults.copyWith(
    groupMode: TodoKanbanGroupMode.priority,
    columns: [
      for (final column in defaults.sortedColumns)
        column.id == defaultKanbanPendingColumnId
            ? column.copyWith(title: _bBuiltInTitle)
            : column,
      const TodoKanbanColumn(
        id: _bCustomId,
        title: _bCustomTitle,
        colorValue: 0xFF1976D2,
        sortOrder: 3,
      ),
    ],
  );
}

TodoKanbanBoardConfig _configC() {
  final defaults = TodoKanbanBoardConfig.defaults();
  return defaults.copyWith(
    groupMode: TodoKanbanGroupMode.dueDate,
    columns: [
      for (final column in defaults.sortedColumns)
        column.id == defaultKanbanPendingColumnId
            ? column.copyWith(title: _cBuiltInTitle)
            : column,
      const TodoKanbanColumn(
        id: _cCustomId,
        title: _cCustomTitle,
        colorValue: 0xFF00897B,
        sortOrder: 3,
      ),
    ],
  );
}

void _expectConfigA(WidgetTester tester) {
  expect(find.text(_aBuiltInTitle), findsOneWidget);
  expect(find.text(_aCustomTitle), findsOneWidget);
  expect(find.text(_bBuiltInTitle), findsNothing);
  expect(find.text(_bCustomTitle), findsNothing);
  expect(find.text(_taskTitle), findsOneWidget);
  expect(
    find.text(TodoBoardUiCopy.kanbanGrouping(TodoKanbanGroupMode.tag.label)),
    findsOneWidget,
  );
}

void _expectConfigB(WidgetTester tester) {
  expect(find.text(_bBuiltInTitle), findsOneWidget);
  expect(find.text(_bCustomTitle), findsOneWidget);
  expect(find.text(_aBuiltInTitle), findsNothing);
  expect(find.text(_aCustomTitle), findsNothing);
  expect(find.text(_taskTitle), findsOneWidget);
  expect(
    find.text(
      TodoBoardUiCopy.kanbanGrouping(TodoKanbanGroupMode.priority.label),
    ),
    findsOneWidget,
  );
}

void _expectConfigC(WidgetTester tester) {
  expect(find.text(_cBuiltInTitle), findsOneWidget);
  expect(find.text(_cCustomTitle), findsOneWidget);
  expect(find.text(_aBuiltInTitle), findsNothing);
  expect(find.text(_aCustomTitle), findsNothing);
  expect(find.text(_bBuiltInTitle), findsNothing);
  expect(find.text(_bCustomTitle), findsNothing);
  expect(find.text(_taskTitle), findsOneWidget);
  expect(
    find.text(
      TodoBoardUiCopy.kanbanGrouping(TodoKanbanGroupMode.dueDate.label),
    ),
    findsOneWidget,
  );
}

void _expectDefaultColumns(WidgetTester tester) {
  expect(find.text('待处理'), findsOneWidget);
  expect(find.text('进行中'), findsOneWidget);
  expect(
    find.descendant(
      of: find.byKey(
        const ValueKey('todo_kanban_board_column_$defaultKanbanDoneColumnId'),
      ),
      matching: find.text('已完成'),
    ),
    findsOneWidget,
  );
  expect(find.text(_aBuiltInTitle), findsNothing);
  expect(find.text(_aCustomTitle), findsNothing);
  expect(find.text(_bBuiltInTitle), findsNothing);
  expect(find.text(_bCustomTitle), findsNothing);
  expect(find.text(_cBuiltInTitle), findsNothing);
  expect(find.text(_cCustomTitle), findsNothing);
  expect(find.text(_taskTitle), findsOneWidget);
}

void _expectSettingsEnabled(WidgetTester tester) {
  expect(tester.widget<IconButton>(_settingsButton()).onPressed, isNotNull);
}

void _expectSettingsDisabled(WidgetTester tester) {
  expect(tester.widget<IconButton>(_settingsButton()).onPressed, isNull);
  expect(find.byType(BottomSheet), findsNothing);
}

Finder _settingsButton() => find.ancestor(
  of: find.byTooltip(TodoBoardUiCopy.kanbanColumnSettingsTooltip),
  matching: find.byType(IconButton),
);

class _ControlledAuthProvider extends AuthProvider {
  _ControlledAuthProvider({bool transition = false, bool blocked = false})
    : _transition = transition,
      _blocked = blocked;

  bool _transition;
  bool _blocked;

  @override
  bool get isAccountTransitionInProgress => _transition;

  @override
  bool get isLocalAccountDataBlocked => _blocked;

  void setAvailability({bool? transition, bool? blocked}) {
    if (transition != null) _transition = transition;
    if (blocked != null) _blocked = blocked;
    notifyListeners();
  }
}

class _TodoHydrationHarness {
  final SharedPreferences preferences;
  final _RecordingPreferencesStore store;
  final TodoProvider todos;
  final HabitProvider habits;
  final GoalProvider goals;
  final ThemeProvider theme;
  final AiService ai;
  final ShareProvider share;
  final GlobalKey<_TodoHydrationAppState> appKey =
      GlobalKey<_TodoHydrationAppState>();
  final List<_ControlledAuthProvider> _authProviders;

  _TodoHydrationHarness({
    required this.preferences,
    required this.store,
    required this.todos,
    required this.habits,
    required this.goals,
    required this.theme,
    required this.ai,
    required this.share,
    required this.auth,
  }) : _authProviders = [auth];

  _ControlledAuthProvider auth;

  Widget get app => _TodoHydrationApp(key: appKey, harness: this);

  void replaceAuth(_ControlledAuthProvider replacement) {
    auth = replacement;
    _authProviders.add(replacement);
    appKey.currentState!.rebuildWithLatestAuth();
  }

  void dispose() {
    todos.dispose();
    habits.dispose();
    goals.dispose();
    theme.dispose();
    ai.dispose();
    share.dispose();
    for (final provider in _authProviders) {
      provider.dispose();
    }
  }
}

class _TodoHydrationApp extends StatefulWidget {
  const _TodoHydrationApp({required this.harness, super.key});

  final _TodoHydrationHarness harness;

  @override
  State<_TodoHydrationApp> createState() => _TodoHydrationAppState();
}

class _TodoHydrationAppState extends State<_TodoHydrationApp> {
  void rebuildWithLatestAuth() => setState(() {});

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider<TodoProvider>.value(value: widget.harness.todos),
      ChangeNotifierProvider<HabitProvider>.value(value: widget.harness.habits),
      ChangeNotifierProvider<GoalProvider>.value(value: widget.harness.goals),
      ChangeNotifierProvider<ThemeProvider>.value(value: widget.harness.theme),
      ChangeNotifierProvider<AiService>.value(value: widget.harness.ai),
      ChangeNotifierProvider<ShareProvider>.value(value: widget.harness.share),
      ChangeNotifierProvider<AuthProvider>.value(value: widget.harness.auth),
    ],
    child: MaterialApp(home: const TodoScreen()),
  );
}

class _RecordingPreferencesStore extends SharedPreferencesStorePlatform {
  _RecordingPreferencesStore(this._delegate);

  final SharedPreferencesStorePlatform _delegate;
  final List<String> writes = [];

  int get configWriteCount => writes
      .where(
        (write) =>
            write == 'clear' ||
            write == 'clearWithParameters' ||
            ((write.startsWith('remove:') || write.startsWith('set:')) &&
                write.endsWith(todoKanbanColumnsPrefsKey)),
      )
      .length;

  @override
  Future<bool> clear() {
    writes.add('clear');
    return _delegate.clear();
  }

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) {
    writes.add('clearWithParameters');
    return _delegate.clearWithParameters(parameters);
  }

  @override
  Future<Map<String, Object>> getAll() => _delegate.getAll();

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) => _delegate.getAllWithParameters(parameters);

  @override
  Future<bool> remove(String key) {
    writes.add('remove:$key');
    return _delegate.remove(key);
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    writes.add('set:$key');
    return _delegate.setValue(valueType, key, value);
  }
}

class _DelayedReadPreferencesStore extends SharedPreferencesStorePlatform {
  _DelayedReadPreferencesStore(this._delegate);

  final SharedPreferencesStorePlatform _delegate;
  final Completer<void> _readStarted = Completer<void>();
  final Completer<void> _release = Completer<void>();
  bool _heldFirstRead = false;

  Future<void> get readStarted => _readStarted.future;

  void releaseRead() {
    if (!_release.isCompleted) _release.complete();
  }

  Future<void> _holdFirstRead() async {
    if (_heldFirstRead) return;
    _heldFirstRead = true;
    _readStarted.complete();
    await _release.future;
  }

  @override
  Future<Map<String, Object>> getAll() async {
    await _holdFirstRead();
    return _delegate.getAll();
  }

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    await _holdFirstRead();
    return _delegate.getAllWithParameters(parameters);
  }

  @override
  Future<bool> clear() => _delegate.clear();

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) =>
      _delegate.clearWithParameters(parameters);

  @override
  Future<bool> remove(String key) => _delegate.remove(key);

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _delegate.setValue(valueType, key, value);
}
