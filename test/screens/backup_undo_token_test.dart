import 'dart:convert';

import 'package:duoyi/core/data_settings_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/quick_capture_template_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/backup_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/recording_reminder_scheduler.dart';

void main() {
  setUp(() {
    // Restore reloads the actual PreferencesProvider. Supply its system
    // timezone boundary because the widget host has no native plugin.
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
  });
  tearDown(() {
    I18n.setLocale(AppLocale.zh);
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
  });

  testWidgets('a retained Undo callback is inert after Backup route disposal', (
    tester,
  ) async {
    final fixture = await _pumpBackupScreen(tester);
    final prefs = await SharedPreferences.getInstance();
    await _importTaskThroughUi(tester, 'Imported before close');
    final undo = _snackbarUndoCallback(tester);
    final stored = prefs.getString('todos');
    final titles = _providerTodoTitles(fixture.todos);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    undo();
    await tester.pumpAndSettle();
    expect(prefs.getString('todos'), stored);
    expect(_providerTodoTitles(fixture.todos), titles);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an older competitor import Undo cannot roll back a newer import, and the latest Undo restores its snapshot',
    (tester) async {
      final fixture = await _pumpBackupScreen(tester);
      final prefs = await SharedPreferences.getInstance();

      await _importTaskThroughUi(tester, 'Imported from A');
      final undoA = _snackbarUndoCallback(tester);
      final preB = prefs.getString('todos')!;

      await _importTasksThroughUi(tester, [
        'Imported from B',
        'Imported from B second task',
      ]);
      expect(
        find.text(
          DataSettingsUiCopy.importSuccessBanner(
            DataSettingsUiCopy.sourceGeneric,
            2,
            0,
            '',
          ),
        ),
        findsOneWidget,
        reason: 'B’s newer completion banner must be the visible Undo action',
      );
      final undoB = _snackbarUndoCallback(tester);
      expect(undoB, isNot(same(undoA)));
      final afterB = prefs.getString('todos')!;
      final bTitles = _persistedTodoTitles(afterB);
      final bProviderTitles = _providerTodoTitles(fixture.todos);

      expect(bTitles, [
        'Pre-import task',
        'Imported from A',
        'Imported from B',
        'Imported from B second task',
      ]);
      expect(_persistedTodoTitles(preB), [
        'Pre-import task',
        'Imported from A',
      ]);
      expect(bProviderTitles, bTitles);
      expect(
        prefs.getInt('pref_default_pomodoro_minutes'),
        37,
        reason: 'the unrelated mocked preference remains part of the B state',
      );

      // Keep and invoke the callback rendered for A after B has replaced its
      // SnackBar. This exercises the real closure and its captured rollback
      // token instead of calling a service or private State method directly.
      undoA();
      await tester.pumpAndSettle();

      expect(prefs.getString('todos'), afterB);
      expect(_persistedTodoTitles(prefs.getString('todos')!), bTitles);
      expect(_providerTodoTitles(fixture.todos), bProviderTitles);
      expect(prefs.getInt('pref_default_pomodoro_minutes'), 37);
      expect(
        find.text(
          DataSettingsUiCopy.importSuccessBanner(
            DataSettingsUiCopy.sourceGeneric,
            2,
            0,
            '',
          ),
        ),
        findsOneWidget,
      );
      expect(_snackbarUndoCallback(tester), same(undoB));
      expect(find.text(DataSettingsUiCopy.undoImportSuccess), findsNothing);
      expect(
        find.widgetWithText(SnackBarAction, DataSettingsUiCopy.undoImport),
        findsOneWidget,
        reason: 'A stale callback must not consume B’s still-valid Undo action',
      );

      // B's own rendered callback is still current and must restore the exact
      // persisted snapshot that existed immediately before B.
      undoB();
      await tester.pumpAndSettle();

      expect(prefs.getString('todos'), preB);
      expect(_persistedTodoTitles(prefs.getString('todos')!), [
        'Pre-import task',
        'Imported from A',
      ]);
      expect(_providerTodoTitles(fixture.todos), [
        'Pre-import task',
        'Imported from A',
      ]);
      expect(prefs.getInt('pref_default_pomodoro_minutes'), 37);
      // A directly invoked retained callback does not perform the SnackBar's
      // tap-to-dismiss behavior; close B's old banner to reveal the queued
      // completion message.
      ScaffoldMessenger.of(
        tester.element(find.byType(BackupScreen)),
      ).hideCurrentSnackBar();
      await tester.pumpAndSettle();
      expect(find.text(DataSettingsUiCopy.undoImportSuccess), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account switching invalidates a retained competitor Undo callback',
    (tester) async {
      await _pumpBackupScreen(tester);
      final prefs = await SharedPreferences.getInstance();

      await _importTaskThroughUi(tester, 'Old account import');
      final oldAccountUndo = _snackbarUndoCallback(tester);

      // Model the account boundary used by logout/account replacement: in-flight
      // writes and BackupScreen's current rollback token are invalidated before
      // the next account's mocked data is installed.
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      final nextAccountTodos = jsonEncode([
        TodoItem(
          id: 'next-account-task',
          title: 'Next account task',
          date: DateTime(2026, 10, 11),
        ).toJson(),
      ]);
      await prefs.setString('todos', nextAccountTodos);
      await tester.pumpAndSettle();

      oldAccountUndo();
      await tester.pumpAndSettle();

      expect(prefs.getString('todos'), nextAccountTodos);
      expect(_persistedTodoTitles(prefs.getString('todos')!), [
        'Next account task',
      ]);
      expect(find.text(DataSettingsUiCopy.undoImportSuccess), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('brand route keeps generated module export across locales', (
    tester,
  ) async {
    await _pumpBackupScreen(tester);
    final export = find.text(DataSettingsUiCopy.exportChipTodoCsv);
    await _scrollUntilVisible(tester, export);
    await tester.tap(export);
    await tester.pumpAndSettle();
    final output = find.byType(SelectableText);
    await _scrollUntilVisible(tester, output);
    final exported = tester.widget<SelectableText>(output).data!;
    expect(exported, contains('Pre-import task'));
    final screenState = tester.state(find.byType(BackupScreen));
    for (final locale in [AppLocale.en, AppLocale.zh]) {
      I18n.setLocale(locale);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(BackupScreen)), same(screenState));
      expect(tester.widget<SelectableText>(output).data, exported);
      expect(find.text(DataSettingsUiCopy.exportTitleTodoCsv), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('tapping latest Undo restores data and shows its completion', (
    tester,
  ) async {
    final fixture = await _pumpBackupScreen(tester);
    final prefs = await SharedPreferences.getInstance();
    final original = prefs.getString('todos');
    await _importTaskThroughUi(tester, 'Current import from tap');
    final screenState = tester.state(find.byType(BackupScreen));
    final undoBefore = _snackbarUndoCallback(tester);
    final imported = prefs.getString('todos');
    for (final locale in [AppLocale.en, AppLocale.zh]) {
      I18n.setLocale(locale);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(BackupScreen)), same(screenState));
      expect(prefs.getString('todos'), imported);
      expect(
        tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed,
        same(undoBefore),
      );
    }
    final action = find.widgetWithText(
      SnackBarAction,
      DataSettingsUiCopy.undoImport,
    );
    expect(action.hitTestable(), findsOneWidget);
    await tester.tap(action);
    for (
      var i = 0;
      i < 100 &&
          find.text(DataSettingsUiCopy.undoImportSuccess).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(prefs.getString('todos'), original);
    expect(_providerTodoTitles(fixture.todos), ['Pre-import task']);
    expect(find.text(DataSettingsUiCopy.undoImportSuccess), findsOneWidget);
    expect(find.byType(SnackBarAction), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<_BackupFixture> _pumpBackupScreen(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'pref_default_pomodoro_minutes': 37});
  I18n.setLocale(AppLocale.zh);
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final fixture = _BackupFixture();
  await fixture.todos.addTodo(
    TodoItem(
      id: 'pre-import-task',
      title: 'Pre-import task',
      date: DateTime(2026, 10, 11),
    ),
  );

  await tester.pumpWidget(
    fixture.wrap(
      const MaterialApp(
        home: BrandRouteSurface(
          child: BackupScreen(initialMode: BackupEntryMode.restore),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });
  return fixture;
}

Future<void> _importTaskThroughUi(WidgetTester tester, String title) =>
    _importTasksThroughUi(tester, [title]);

Future<void> _importTasksThroughUi(
  WidgetTester tester,
  List<String> titles,
) async {
  final importButton = find.text(
    DataSettingsUiCopy.importTasksFromOtherAppsButton,
  );
  await _scrollUntilVisible(tester, importButton);
  await tester.tap(importButton);
  await tester.pumpAndSettle();

  // The dialog defaults to Zhijian Time. Select the source whose completion
  // label this fixture checks, using the same dropdown a user interacts with.
  await tester.tap(find.text(DataSettingsUiCopy.sourceZhijianTime));
  await tester.pumpAndSettle();
  await tester.tap(find.text(DataSettingsUiCopy.sourceGeneric).last);
  await tester.pumpAndSettle();
  expect(find.text(DataSettingsUiCopy.sourceGeneric), findsOneWidget);

  final input = find.byType(TextField);
  expect(input, findsOneWidget);
  await tester.enterText(
    input,
    jsonEncode({
      'tasks': titles.map((title) => {'title': title}).toList(),
    }),
  );
  await tester.tap(
    find.widgetWithText(
      FilledButton,
      DataSettingsUiCopy.competitorImportPreviewAction(true),
    ),
  );
  await tester.pumpAndSettle();
  expect(_dialogText(DataSettingsUiCopy.importPreviewTitle), findsOneWidget);

  final policyConfirmation = find.byType(CheckboxListTile);
  await tester.ensureVisible(policyConfirmation);
  await tester.tap(policyConfirmation);
  await tester.pumpAndSettle();
  expect(tester.widget<CheckboxListTile>(policyConfirmation).value, isTrue);
  final confirm = find.descendant(
    of: find.byType(AppDialog),
    matching: find.widgetWithText(
      FilledButton,
      DataSettingsUiCopy.confirmImport,
    ),
  );
  await tester.ensureVisible(confirm);
  final todos =
      tester.element(find.byType(BackupScreen)).read<TodoProvider>()
          as _TracingTodoProvider;
  final generation = AccountLocalDataCleaner.accountDataGeneration;
  await tester.tap(confirm);
  // Storage and reminder reconciliation can finish after the transition has
  // stopped scheduling frames. Wait for their visible result explicitly.
  for (
    var i = 0;
    i < 100 &&
        _dialogText(DataSettingsUiCopy.importCompletedTitle).evaluate().isEmpty;
    i++
  ) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
  expect(
    _dialogText(DataSettingsUiCopy.importCompletedTitle),
    findsOneWidget,
    reason:
        'imports=${todos.importCalls}, result=${todos.lastImport?.inserted}, error=${todos.lastImportError}, generation=$generation/${AccountLocalDataCleaner.accountDataGeneration}; '
        '${find.byType(Text).evaluate().map((element) => (element.widget as Text).data).whereType<String>().join(' | ')}',
  );

  final dismissResult = find.descendant(
    of: find.byType(AppDialog),
    matching: find.widgetWithText(FilledButton, DataSettingsUiCopy.gotIt),
  );
  await tester.ensureVisible(dismissResult);
  await tester.tap(dismissResult);
  final completionBanner = find.text(
    DataSettingsUiCopy.importSuccessBanner(
      DataSettingsUiCopy.sourceGeneric,
      titles.length,
      0,
      '',
    ),
  );
  for (var i = 0; i < 100 && completionBanner.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
  expect(find.byType(AppDialog), findsNothing);
  expect(completionBanner, findsOneWidget);
  expect(
    find.widgetWithText(SnackBarAction, DataSettingsUiCopy.undoImport),
    findsOneWidget,
  );
}

VoidCallback _snackbarUndoCallback(WidgetTester tester) {
  final actionFinder = find.widgetWithText(
    SnackBarAction,
    DataSettingsUiCopy.undoImport,
  );
  expect(actionFinder, findsOneWidget);
  return tester.widget<SnackBarAction>(actionFinder).onPressed;
}

List<String> _persistedTodoTitles(String raw) {
  return (jsonDecode(raw) as List<dynamic>)
      .map((row) => (row as Map<String, dynamic>)['title'] as String)
      .toList();
}

List<String> _providerTodoTitles(TodoProvider provider) =>
    provider.todos.map((todo) => todo.title).toList();

Future<void> _scrollUntilVisible(WidgetTester tester, Finder target) async {
  final scrollable = find.byType(Scrollable).first;
  await tester.scrollUntilVisible(target, 280, scrollable: scrollable);
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
}

Finder _dialogText(String value) =>
    find.descendant(of: find.byType(AppDialog), matching: find.text(value));

class _BackupFixture {
  final reminderScheduler = RecordingReminderScheduler();
  late final todos = _TracingTodoProvider()..scheduler = reminderScheduler;
  final habits = HabitProvider();
  final pomodoro = PomodoroProvider();
  final notes = NoteProvider();
  final anniversaries = AnniversaryProvider();
  final diary = DiaryProvider();
  final goals = GoalProvider();
  final courses = CourseProvider();
  final users = UserProvider();
  final timeAudit = TimeAuditProvider();
  final achievements = AchievementProvider();
  final shares = ShareProvider();
  final calendar = CalendarProvider();
  final countdowns = CountdownProvider();
  final locationReminders = LocationReminderProvider();
  final preferences = PreferencesProvider();
  final quickCaptureTemplates = QuickCaptureTemplateProvider();
  final theme = ThemeProvider();

  Widget wrap(Widget child) => MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeProvider>.value(value: theme),
      ChangeNotifierProvider<TodoProvider>.value(value: todos),
      ChangeNotifierProvider<HabitProvider>.value(value: habits),
      ChangeNotifierProvider<PomodoroProvider>.value(value: pomodoro),
      ChangeNotifierProvider<NoteProvider>.value(value: notes),
      ChangeNotifierProvider<AnniversaryProvider>.value(value: anniversaries),
      ChangeNotifierProvider<DiaryProvider>.value(value: diary),
      ChangeNotifierProvider<GoalProvider>.value(value: goals),
      ChangeNotifierProvider<CourseProvider>.value(value: courses),
      ChangeNotifierProvider<UserProvider>.value(value: users),
      ChangeNotifierProvider<TimeAuditProvider>.value(value: timeAudit),
      ChangeNotifierProvider<AchievementProvider>.value(value: achievements),
      ChangeNotifierProvider<ShareProvider>.value(value: shares),
      ChangeNotifierProvider<CalendarProvider>.value(value: calendar),
      ChangeNotifierProvider<CountdownProvider>.value(value: countdowns),
      ChangeNotifierProvider<LocationReminderProvider>.value(
        value: locationReminders,
      ),
      ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
      ChangeNotifierProvider<QuickCaptureTemplateProvider>.value(
        value: quickCaptureTemplates,
      ),
    ],
    child: child,
  );

  void dispose() {
    for (final provider in [
      theme,
      quickCaptureTemplates,
      preferences,
      locationReminders,
      countdowns,
      calendar,
      shares,
      achievements,
      timeAudit,
      users,
      courses,
      goals,
      diary,
      anniversaries,
      notes,
      pomodoro,
      habits,
      todos,
    ]) {
      provider.dispose();
    }
  }
}

class _TracingTodoProvider extends TodoProvider {
  int importCalls = 0;
  TodoImportSummary? lastImport;
  Object? lastImportError;
  @override
  Future<TodoImportSummary> importTodos(Iterable<TodoItem> imported) async {
    importCalls++;
    try {
      return lastImport = await super.importTodos(imported);
    } catch (error) {
      lastImportError = error;
      rethrow;
    }
  }
}
