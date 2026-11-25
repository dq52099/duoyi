import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/todo_board_ui_copy.dart';
import 'package:duoyi/core/todo_kanban.dart';
import 'package:duoyi/core/todo_ui_copy.dart';
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
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import '../support/widget_polish_screenshot_font.dart';

const _alphaId = 'custom_alpha';
const _betaId = 'custom_beta';
const _deleteCandidateId = 'custom_delete_candidate';
const _alphaTitle = '自定义甲列';
const _betaTitle = '自定义乙列';
const _deleteCandidateTitle = '待删除原始列名';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocale previousLocale;

  setUp(() {
    previousLocale = I18n.current;
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(previousLocale));

  testWidgets(
    'settings sheet tracks zh-en-zh and retains grouping selection, keyed draft, text selection, and focus node through reorder without preference writes',
    (tester) async {
      final harness = await _pumpTodoScreen(
        tester,
        config: _configWithTwoCustomColumns(),
      );
      await _openKanbanSettings(tester);

      await tester.tap(find.text(TodoUiCopy.kanbanGroupNone));
      await tester.pumpAndSettle();
      await tester.tap(find.text(TodoUiCopy.kanbanGroupPriority));
      await tester.pumpAndSettle();

      final betaRow = _columnRow(_betaId);
      final betaField = _columnField(_betaId);
      final alphaField = _columnField(_alphaId);
      await _ensureColumnVisible(tester, _columnRow(_alphaId));
      final alphaControllerBeforeMove = tester
          .widget<TextFormField>(alphaField)
          .controller!;
      await _ensureColumnVisible(tester, betaRow);
      final betaControllerBeforeMove = tester
          .widget<TextFormField>(betaField)
          .controller!;
      final betaFocusBeforeMove = _editable(tester, betaField).focusNode;
      await tester.ensureVisible(betaField);
      await tester.tap(betaField);
      await tester.enterText(betaField, '草稿保留焦点选择');
      await tester.pump();
      betaControllerBeforeMove.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 6,
      );
      await tester.pump();
      final valueBeforeMove = betaControllerBeforeMove.value;
      final editableStateBeforeMove = tester.state<EditableTextState>(
        find.descendant(of: betaField, matching: find.byType(EditableText)),
      );

      final moveUp = find.descendant(
        of: betaRow,
        matching: find.byTooltip(TodoBoardUiCopy.moveUpTooltip),
      );
      expect(moveUp, findsOneWidget);
      await tester.tap(moveUp);
      await tester.pumpAndSettle();

      await _ensureColumnVisible(tester, betaRow);
      await _ensureColumnVisible(tester, _columnRow(_alphaId));
      expect(
        tester.widget<TextFormField>(betaField).controller,
        same(betaControllerBeforeMove),
      );
      expect(_editable(tester, betaField).focusNode, same(betaFocusBeforeMove));
      expect(
        tester.widget<TextFormField>(alphaField).controller,
        same(alphaControllerBeforeMove),
      );
      expect(betaControllerBeforeMove.value, valueBeforeMove);
      expect(betaControllerBeforeMove.text, '草稿保留焦点选择');
      expect(alphaControllerBeforeMove.text, _alphaTitle);
      expect(
        tester.state<EditableTextState>(
          find.descendant(of: betaField, matching: find.byType(EditableText)),
        ),
        same(editableStateBeforeMove),
      );
      expect(
        tester.getCenter(betaRow).dy,
        lessThan(tester.getCenter(_columnRow(_alphaId)).dy),
      );

      await tester.ensureVisible(betaField);
      await tester.tap(betaField);
      final betaFieldBeforeLocale = tester.widget<TextFormField>(betaField);
      final controllerBeforeLocale = betaFieldBeforeLocale.controller!;
      final focusNodeBeforeLocale = _editable(tester, betaField).focusNode;
      controllerBeforeLocale.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 6,
      );
      await tester.pump();
      final valueBeforeLocale = controllerBeforeLocale.value;
      final editableStateBeforeLocale = tester.state<EditableTextState>(
        find.descendant(of: betaField, matching: find.byType(EditableText)),
      );
      expect(focusNodeBeforeLocale.hasFocus, isTrue);

      harness.store.writes.clear();
      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();

        _expectSettingsCopy(tester);
        final betaFieldAfterLocale = tester.widget<TextFormField>(betaField);
        expect(betaFieldAfterLocale.controller, same(controllerBeforeLocale));
        expect(
          _editable(tester, betaField).focusNode,
          same(focusNodeBeforeLocale),
        );
        expect(betaFieldAfterLocale.controller!.value, valueBeforeLocale);
        expect(betaFieldAfterLocale.controller!.text, '草稿保留焦点选择');
        expect(
          find.text(
            TodoUiCopy.kanbanGroupModeLabel(TodoKanbanGroupMode.priority),
          ),
          findsOneWidget,
        );
        expect(focusNodeBeforeLocale.hasFocus, isTrue);
        expect(
          tester.state<EditableTextState>(
            find.descendant(of: betaField, matching: find.byType(EditableText)),
          ),
          same(editableStateBeforeLocale),
        );
        expect(betaRow, findsOneWidget);
        expect(harness.store.writes, isEmpty);
        expect(
          harness.preferences.getString(todoKanbanColumnsPrefsKey),
          harness.initialConfig.encode(),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'saving a renamed built-in column persists it and preserves its raw title in zh and en headers',
    (tester) async {
      final harness = await _pumpTodoScreen(
        tester,
        config: TodoKanbanBoardConfig.defaults(),
      );
      await _openKanbanSettings(tester);

      final pendingField = _columnField(defaultKanbanPendingColumnId);
      await _ensureColumnVisible(
        tester,
        _columnRow(defaultKanbanPendingColumnId),
      );
      await tester.ensureVisible(pendingField);
      harness.store.writes.clear();
      await tester.enterText(pendingField, '自定义待办列');
      await tester.pumpAndSettle();

      final save = find.widgetWithText(FilledButton, TodoBoardUiCopy.save);
      await _ensureSheetChildVisible(tester, save, columnList: false);
      await tester.tap(save);
      await tester.pumpAndSettle();
      await AccountPreferenceWrites.drain();

      final persistedRaw = harness.preferences.getString(
        todoKanbanColumnsPrefsKey,
      );
      expect(persistedRaw, isNotNull);
      final persisted = TodoKanbanBoardConfig.decode(persistedRaw);
      final pending = persisted.columnById(defaultKanbanPendingColumnId)!;
      expect(pending.title, '自定义待办列');
      expect(pending.builtIn, isTrue);
      expect(harness.store.writes, hasLength(1));
      expect(harness.store.writes.single, contains(todoKanbanColumnsPrefsKey));
      expect(find.text('自定义待办列'), findsOneWidget);

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(find.text('自定义待办列'), findsOneWidget);
        expect(
          find.text(locale == AppLocale.en ? 'In Progress' : '进行中'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'live delete-column dialog translates around the unchanged raw title and cancel keeps the column',
    (tester) async {
      final harness = await _pumpTodoScreen(
        tester,
        config: _configWithDeleteCandidate(),
      );
      await _openKanbanSettings(tester);

      final row = _columnRow(_deleteCandidateId);
      await _ensureColumnVisible(tester, row);
      final delete = find.descendant(
        of: row,
        matching: find.byTooltip(TodoBoardUiCopy.deleteColumnTooltip),
      );
      expect(delete, findsOneWidget);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      _expectDeleteColumnDialog(tester);

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        _expectDeleteColumnDialog(tester);
        expect(tester.takeException(), isNull);
      }

      await tester.tap(find.widgetWithText(TextButton, TodoBoardUiCopy.cancel));
      await tester.pumpAndSettle();
      await _ensureColumnVisible(tester, row);
      expect(row, findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(_columnField(_deleteCandidateId))
            .controller!
            .text,
        _deleteCandidateTitle,
      );

      final save = find.widgetWithText(FilledButton, TodoBoardUiCopy.save);
      await _ensureSheetChildVisible(tester, save, columnList: false);
      await tester.tap(save);
      await tester.pumpAndSettle();
      await AccountPreferenceWrites.drain();
      final persisted = TodoKanbanBoardConfig.decode(
        harness.preferences.getString(todoKanbanColumnsPrefsKey),
      );
      expect(
        persisted.columnById(_deleteCandidateId)?.title,
        _deleteCandidateTitle,
      );
    },
  );

  testWidgets(
    'a retained kanban Save callback cannot pop a covering route or write preferences',
    (tester) async {
      final harness = await _pumpTodoScreen(
        tester,
        config: _configWithTwoCustomColumns(),
      );
      await _openKanbanSettings(tester);

      final save = find.widgetWithText(FilledButton, TodoBoardUiCopy.save);
      final staleSave = tester.widget<FilledButton>(save).onPressed!;
      harness.store.writes.clear();
      unawaited(
        harness.navigatorKey.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Covering kanban route')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      staleSave();
      await tester.pumpAndSettle();

      expect(find.text('Covering kanban route'), findsOneWidget);
      expect(harness.store.writes, isEmpty);
      expect(
        harness.preferences.getString(todoKanbanColumnsPrefsKey),
        harness.initialConfig.encode(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a retained kanban Save callback rejects account write invalidation',
    (tester) async {
      final harness = await _pumpTodoScreen(
        tester,
        config: _configWithTwoCustomColumns(),
      );
      await _openKanbanSettings(tester);

      final save = find.widgetWithText(FilledButton, TodoBoardUiCopy.save);
      final staleSave = tester.widget<FilledButton>(save).onPressed!;
      harness.store.writes.clear();
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      staleSave();
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(harness.store.writes, isEmpty);
      expect(
        harness.preferences.getString(todoKanbanColumnsPrefsKey),
        harness.initialConfig.encode(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a delete-column dialog stays open after account invalidation and cancel keeps the column',
    (tester) async {
      final harness = await _pumpTodoScreen(
        tester,
        config: _configWithDeleteCandidate(),
      );
      await _openKanbanSettings(tester);

      final row = _columnRow(_deleteCandidateId);
      await _ensureColumnVisible(tester, row);
      final delete = find.descendant(
        of: row,
        matching: find.byTooltip(TodoBoardUiCopy.deleteColumnTooltip),
      );
      await tester.tap(delete);
      await tester.pumpAndSettle();
      _expectDeleteColumnDialog(tester);

      harness.store.writes.clear();
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, TodoBoardUiCopy.delete),
      );
      await tester.pumpAndSettle();
      _expectDeleteColumnDialog(tester);

      await tester.tap(find.widgetWithText(TextButton, TodoBoardUiCopy.cancel));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await _ensureColumnVisible(tester, row);
      expect(row, findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(_columnField(_deleteCandidateId))
            .controller!
            .text,
        _deleteCandidateTitle,
      );
      expect(harness.store.writes, isEmpty);
      expect(
        harness.preferences.getString(todoKanbanColumnsPrefsKey),
        harness.initialConfig.encode(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'kanban settings sheet has no layout exception at 320 logical pixels and 1.6 text scale',
    (tester) async {
      final harness = await _pumpTodoScreen(
        tester,
        config: _configWithTwoCustomColumns(),
        textScale: 1.6,
        viewport: const Size(320, 900),
      );
      await _openKanbanSettings(tester);
      expect(tester.takeException(), isNull);
      await _capture(
        tester,
        harness.screenshotKey,
        'settings-zh-320-scale-1.6.png',
      );

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      _expectSettingsCopy(tester);
      expect(tester.takeException(), isNull);
      await _capture(
        tester,
        harness.screenshotKey,
        'settings-en-320-scale-1.6.png',
      );
    },
  );
}

TodoKanbanBoardConfig _configWithTwoCustomColumns() {
  final defaults = TodoKanbanBoardConfig.defaults();
  return defaults.copyWith(
    columns: [
      ...defaults.columns,
      const TodoKanbanColumn(
        id: _alphaId,
        title: _alphaTitle,
        colorValue: 0xFF607D8B,
        sortOrder: 3,
      ),
      const TodoKanbanColumn(
        id: _betaId,
        title: _betaTitle,
        colorValue: 0xFF1976D2,
        sortOrder: 4,
      ),
    ],
  );
}

TodoKanbanBoardConfig _configWithDeleteCandidate() {
  final defaults = TodoKanbanBoardConfig.defaults();
  return defaults.copyWith(
    columns: [
      ...defaults.columns,
      const TodoKanbanColumn(
        id: _deleteCandidateId,
        title: _deleteCandidateTitle,
        colorValue: 0xFF7B1FA2,
        sortOrder: 3,
      ),
    ],
  );
}

Future<_TodoHarness> _pumpTodoScreen(
  WidgetTester tester, {
  required TodoKanbanBoardConfig config,
  double textScale = 1,
  Size viewport = const Size(1280, 900),
}) async {
  SharedPreferences.setMockInitialValues({
    todoKanbanColumnsPrefsKey: config.encode(),
  });
  final store = _RecordingPreferencesStore(
    SharedPreferencesStorePlatform.instance,
  );
  SharedPreferencesStorePlatform.instance = store;
  final preferences = await SharedPreferences.getInstance();

  if (Platform.environment['DUOYI_TODO_SCREENSHOT_DIR'] != null) {
    await tester.runAsync(loadWidgetPolishScreenshotFonts);
  }
  final todos = TodoProvider();
  await todos.addTodo(TodoItem(title: '原文 Raw fixture task'));
  final habits = HabitProvider();
  final goals = GoalProvider();
  final theme = ThemeProvider();
  final ai = AiService();
  final share = ShareProvider();
  final auth = AuthProvider();
  final navigatorKey = GlobalKey<NavigatorState>();
  final harness = _TodoHarness(
    initialConfig: config,
    preferences: preferences,
    store: store,
    todos: todos,
    habits: habits,
    goals: goals,
    theme: theme,
    ai: ai,
    share: share,
    auth: auth,
    navigatorKey: navigatorKey,
  );

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    harness.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
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
      child: MaterialApp(
        navigatorKey: navigatorKey,
        theme: widgetPolishScreenshotTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: RepaintBoundary(
            key: harness.screenshotKey,
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
        home: const TodoScreen(),
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

Future<void> _openKanbanSettings(WidgetTester tester) async {
  await tester.tap(find.text(TodoBoardUiCopy.viewKanban));
  await tester.pumpAndSettle();
  final settingsButton = find.byTooltip(
    TodoBoardUiCopy.kanbanColumnSettingsTooltip,
  );
  expect(settingsButton, findsOneWidget);
  await tester.tap(settingsButton);
  await tester.pumpAndSettle();
  expect(find.byType(BottomSheet), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void _expectSettingsCopy(WidgetTester tester) {
  expect(find.text(TodoBoardUiCopy.kanbanSettingsTitle), findsOneWidget);
  expect(find.text(TodoBoardUiCopy.kanbanSettingsSubtitle), findsOneWidget);
  expect(
    find.widgetWithText(FilledButton, TodoBoardUiCopy.save),
    findsOneWidget,
  );
  expect(find.text(TodoBoardUiCopy.defaultGroupingLabel), findsOneWidget);
  expect(find.text(TodoBoardUiCopy.defaultGroupingHelper), findsOneWidget);
  expect(find.text(TodoBoardUiCopy.columnNameLabel), findsWidgets);
  expect(find.text(TodoBoardUiCopy.addColumn), findsOneWidget);
}

void _expectDeleteColumnDialog(WidgetTester tester) {
  expect(find.text(TodoBoardUiCopy.deleteColumnDialogTitle), findsOneWidget);
  expect(
    find.text(TodoBoardUiCopy.deleteColumnDialogContent(_deleteCandidateTitle)),
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

Finder _columnRow(String id) =>
    find.byKey(ValueKey<String>('todo_kanban_column_$id'));

Finder _columnField(String id) =>
    find.byKey(ValueKey<String>('todo_kanban_column_name_$id'));

Future<void> _ensureColumnVisible(WidgetTester tester, Finder target) =>
    _ensureSheetChildVisible(tester, target, columnList: true);

Future<void> _ensureSheetChildVisible(
  WidgetTester tester,
  Finder target, {
  required bool columnList,
}) async {
  final sheet = find.byType(BottomSheet);
  expect(sheet, findsOneWidget);
  final sheetElement = tester.element(sheet);
  final sheetRoute = ModalRoute.of(sheetElement);
  expect(sheetRoute, isNotNull);

  void expectCurrentSheet() {
    expect(tester.element(sheet), same(sheetElement));
    expect(ModalRoute.of(sheetElement), same(sheetRoute));
    expect(
      sheetRoute?.isActive == true && sheetRoute?.isCurrent == true,
      isTrue,
      reason: 'Kanban settings must be current before scrolling; '
          'a grouping popup or other covering route must not intercept drags',
    );
  }

  expectCurrentSheet();
  final columns = find.descendant(
    of: sheet,
    matching: find.byKey(const ValueKey('todo_kanban_settings_columns')),
  );
  expect(columns, findsOneWidget);
  final vertical = find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  );
  final inner = find.descendant(of: columns, matching: vertical);
  final outer = find.ancestor(
    of: columns,
    matching: find.descendant(of: sheet, matching: vertical),
  );
  expect(inner, findsOneWidget);
  expect(outer, findsOneWidget);
  final innerState = tester.state<ScrollableState>(inner);
  final outerState = tester.state<ScrollableState>(outer);

  void expectScrollers() {
    expectCurrentSheet();
    expect(inner, findsOneWidget);
    expect(outer, findsOneWidget);
    expect(tester.state<ScrollableState>(inner), same(innerState));
    expect(tester.state<ScrollableState>(outer), same(outerState));
    expect(innerState.position.hasContentDimensions, isTrue);
    expect(outerState.position.hasContentDimensions, isTrue);
  }

  expectScrollers();
  final ownedTarget = find.descendant(
    of: columnList ? columns : sheet,
    matching: target,
  );
  if (columnList) {
    // The list is mounted even when a lazily built row is absent. Reveal its
    // viewport through the enclosing sheet before admitting a real inner drag.
    await tester.ensureVisible(columns);
    await tester.pumpAndSettle();
    expectScrollers();
    expect(inner.hitTestable(), findsOneWidget);

    var forward = true;
    for (var step = 0; ; step++) {
      expectScrollers();
      if (ownedTarget.evaluate().isNotEmpty) {
        expect(ownedTarget, findsOneWidget);
        break;
      }
      final position = innerState.position;
      if (forward && position.pixels >= position.maxScrollExtent - 0.5) {
        forward = false;
      }
      if (step == 40 ||
          (!forward && position.pixels <= position.minScrollExtent + 0.5)) {
        fail(
          'Kanban column target missing after $step real drags: '
          '$target; pixels=${position.pixels}, '
          'min=${position.minScrollExtent}, max=${position.maxScrollExtent}',
        );
      }
      expect(inner.hitTestable(), findsOneWidget);
      final before = position.pixels;
      await tester.drag(inner, Offset(0, forward ? -160 : 160));
      await tester.pumpAndSettle();
      expectScrollers();
      final after = innerState.position.pixels;
      if (ownedTarget.evaluate().isEmpty &&
          (forward ? after <= before + 0.5 : after >= before - 0.5)) {
        fail(
          'Kanban column drag made no progress: $target; '
          'step=$step, forward=$forward, before=$before, after=$after',
        );
      }
    }
  }
  // Save is an eagerly mounted outer-sheet action. A missing action never
  // admits a search in the unrelated inner list.
  expect(ownedTarget, findsOneWidget);
  await tester.ensureVisible(ownedTarget);
  await tester.pumpAndSettle();
  expectScrollers();
  expect(ownedTarget.hitTestable(), findsOneWidget);
}

class _TodoHarness {
  final TodoKanbanBoardConfig initialConfig;
  final SharedPreferences preferences;
  final _RecordingPreferencesStore store;
  final TodoProvider todos;
  final HabitProvider habits;
  final GoalProvider goals;
  final ThemeProvider theme;
  final AiService ai;
  final ShareProvider share;
  final AuthProvider auth;
  final GlobalKey<NavigatorState> navigatorKey;

  final GlobalKey screenshotKey = GlobalKey();

  _TodoHarness({
    required this.initialConfig,
    required this.preferences,
    required this.store,
    required this.todos,
    required this.habits,
    required this.goals,
    required this.theme,
    required this.ai,
    required this.share,
    required this.auth,
    required this.navigatorKey,
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

class _RecordingPreferencesStore extends SharedPreferencesStorePlatform {
  _RecordingPreferencesStore(this._delegate);

  final SharedPreferencesStorePlatform _delegate;
  final List<String> writes = [];

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

EditableText _editable(WidgetTester tester, Finder field) =>
    tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final directory = Platform.environment['DUOYI_TODO_SCREENSHOT_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$directory/$name');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
