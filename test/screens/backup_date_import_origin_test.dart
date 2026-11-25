import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
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
import 'package:duoyi/widgets/surface_components.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../test_support/recording_reminder_scheduler.dart';

const _countdownStorageKey = 'duoyi_countdowns';
const _anniversaryStorageKey = 'duoyi_anniversaries_v2';
const _countdownPlatformKey = 'flutter.duoyi_countdowns';
const _anniversaryPlatformKey = 'flutter.duoyi_anniversaries_v2';
const _fullDateImport = '''
{
  "anniversaries": [
    {"title": "Imported anniversary", "date": "2031-04-15"}
  ],
  "countdowns": [
    {"title": "Imported countdown", "targetDate": "2032-09-20"}
  ]
}
''';

late _Store _store;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pref_default_pomodoro_minutes': 37,
    });
    _store = _Store();
    SharedPreferencesStorePlatform.instance = _store;
    I18n.setLocale(AppLocale.zh);
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
  });

  tearDown(() async {
    _store.release();
    await AccountPreferenceWrites.drain();
    I18n.setLocale(AppLocale.zh);
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'full productivity import saves anniversaries and countdowns after preview dismissal',
    (tester) async {
      final fixture = await _pumpBackupScreen(tester);
      final preferences = await SharedPreferences.getInstance();
      _store.resetDateWrites();
      final confirm = await _openDatePreview(tester);
      _store.previewVisibilityProbe = () => _dialogText(
        tester,
        DataSettingsUiCopy.importPreviewTitle,
      ).evaluate().isNotEmpty;

      await tester.tap(confirm);
      await tester.pump(const Duration(milliseconds: 1));

      expect(
        _dialogText(tester, DataSettingsUiCopy.importPreviewTitle),
        findsOneWidget,
        reason: 'the preview remains mounted while its reverse transition runs',
      );
      expect(_store.dateWriteCount, 0);
      expect(fixture.anniversaries.items, isEmpty);
      expect(fixture.countdowns.items, isEmpty);

      await _waitForCompletedImport(tester);

      expect(_store.dateWriteCountFor(_anniversaryPlatformKey), 1);
      expect(_store.dateWriteCountFor(_countdownPlatformKey), 1);
      expect(_store.previewVisibleAtFirstDateWrite, isFalse);
      expect(fixture.anniversaries.items.single.title, 'Imported anniversary');
      expect(
        fixture.anniversaries.items.single.originDate,
        DateTime(2031, 4, 15),
      );
      expect(fixture.countdowns.items.single.title, 'Imported countdown');
      expect(fixture.countdowns.items.single.targetDate, DateTime(2032, 9, 20));
      expect(
        _storedDate(preferences, _anniversaryStorageKey, 'originDate'),
        DateTime(2031, 4, 15),
      );
      expect(
        _storedDate(preferences, _countdownStorageKey, 'targetDate'),
        DateTime(2032, 9, 20),
      );
      final screenState = tester.state(find.byType(BackupScreen));
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(BackupScreen)), same(screenState));
      expect(fixture.anniversaries.items.single.title, 'Imported anniversary');
      expect(fixture.countdowns.items.single.title, 'Imported countdown');
      expect(_store.dateWriteCountFor(_anniversaryPlatformKey), 1);
      expect(_store.dateWriteCountFor(_countdownPlatformKey), 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'retained import dialog callbacks cannot pop a route covering the dialog',
    (tester) async {
      final fixture = await _pumpBackupScreen(tester);
      _store.resetDateWrites();
      final confirm = await _openDatePreview(tester);
      final staleConfirm = tester.widget<FilledButton>(confirm).onPressed!;
      final cancel = find.descendant(
        of: find.byType(AppDialog),
        matching: find.widgetWithText(TextButton, I18n.tr('action.cancel')),
      );
      final staleCancel = tester.widget<TextButton>(cancel).onPressed!;
      final backupContext = tester.element(find.byType(BackupScreen));

      unawaited(
        Navigator.of(backupContext).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Preview covering route')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      staleConfirm();
      staleCancel();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Preview covering route'), findsOneWidget);
      expect(_store.dateWriteCount, 0);

      Navigator.of(backupContext).pop();
      await tester.pumpAndSettle();
      expect(
        _dialogText(tester, DataSettingsUiCopy.importPreviewTitle),
        findsOneWidget,
      );

      unawaited(
        Navigator.of(backupContext).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Preview Cancel covering route')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      staleCancel();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Preview Cancel covering route'), findsOneWidget);
      expect(_store.dateWriteCount, 0);
      Navigator.of(backupContext).pop();
      await tester.pumpAndSettle();
      expect(
        _dialogText(tester, DataSettingsUiCopy.importPreviewTitle),
        findsOneWidget,
      );
      expect(fixture.anniversaries.items, isEmpty);
      expect(fixture.countdowns.items, isEmpty);

      await tester.tap(_previewConfirmButton(tester));
      await _waitForCompletedImport(tester);
      expect(fixture.anniversaries.items.single.title, 'Imported anniversary');
      expect(fixture.countdowns.items.single.title, 'Imported countdown');

      final resultUndo = find.descendant(
        of: find.byType(AppDialog),
        matching: find.widgetWithText(
          TextButton,
          DataSettingsUiCopy.undoImport,
        ),
      );
      final resultGotIt = find.descendant(
        of: find.byType(AppDialog),
        matching: find.widgetWithText(FilledButton, DataSettingsUiCopy.gotIt),
      );
      final staleResultUndo = tester.widget<TextButton>(resultUndo).onPressed!;
      final staleResultGotIt = tester
          .widget<FilledButton>(resultGotIt)
          .onPressed!;

      unawaited(
        Navigator.of(backupContext).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Result covering route')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      staleResultUndo();
      staleResultGotIt();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Result covering route'), findsOneWidget);
      expect(_store.dateWriteCountFor(_anniversaryPlatformKey), 1);
      expect(_store.dateWriteCountFor(_countdownPlatformKey), 1);
      expect(fixture.anniversaries.items.single.title, 'Imported anniversary');
      expect(fixture.countdowns.items.single.title, 'Imported countdown');

      Navigator.of(backupContext).pop();
      await tester.pumpAndSettle();
      expect(
        _dialogText(tester, DataSettingsUiCopy.importCompletedTitle),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(FilledButton, DataSettingsUiCopy.gotIt),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'resetting AnniversaryProvider during a held import write leaves no date data or stale feedback',
    (tester) async {
      final fixture = await _pumpBackupScreen(tester);
      final preferences = await SharedPreferences.getInstance();
      _store.resetDateWrites();
      _store.holdNextDateWrite(_anniversaryPlatformKey);
      final heldWriteStarted = _store.heldDateWriteStarted;

      final confirm = await _openDatePreview(tester);
      await tester.tap(confirm);

      for (var i = 0; i < 100 && !heldWriteStarted.isCompleted; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      try {
        expect(
          heldWriteStarted.isCompleted,
          isTrue,
          reason: 'the test must reach the bounded Anniversary storage write',
        );
        fixture.anniversaries.resetLocalState();
      } finally {
        _store.release();
      }

      for (var i = 0; i < 100 && !_store.heldDateWriteCompleted; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(_store.heldDateWriteCompleted, isTrue);
      await tester.pumpAndSettle();

      expect(_store.dateWriteCountFor(_anniversaryPlatformKey), 1);
      expect(_store.dateWriteCountFor(_countdownPlatformKey), 0);
      expect(preferences.getStringList(_anniversaryStorageKey), isNull);
      expect(preferences.getStringList(_countdownStorageKey), isNull);
      expect(fixture.anniversaries.items, isEmpty);
      expect(fixture.countdowns.items, isEmpty);
      expect(
        _dialogText(tester, DataSettingsUiCopy.importCompletedTitle),
        findsNothing,
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<_BackupFixture> _pumpBackupScreen(WidgetTester tester) async {
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
    _store.release();
    await AccountPreferenceWrites.drain();
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });
  return fixture;
}

Future<Finder> _openDatePreview(WidgetTester tester) async {
  final importButton = find.text(
    DataSettingsUiCopy.importProductivityFromOtherAppsButton,
  );
  await _scrollUntilVisible(tester, importButton);
  await tester.tap(importButton);
  await tester.pumpAndSettle();

  await tester.tap(find.text(DataSettingsUiCopy.sourceZhijianTime));
  await tester.pumpAndSettle();
  await tester.tap(find.text(DataSettingsUiCopy.sourceGeneric).last);
  await tester.pumpAndSettle();
  expect(find.text(DataSettingsUiCopy.sourceGeneric), findsOneWidget);

  final input = find.byType(TextField);
  expect(input, findsOneWidget);
  await tester.enterText(input, _fullDateImport);
  await tester.tap(
    find.widgetWithText(
      FilledButton,
      DataSettingsUiCopy.competitorImportPreviewAction(false),
    ),
  );
  await tester.pumpAndSettle();
  expect(
    _dialogText(tester, DataSettingsUiCopy.importPreviewTitle),
    findsOneWidget,
  );

  final policyConfirmation = find.byType(CheckboxListTile);
  await tester.ensureVisible(policyConfirmation);
  await tester.tap(policyConfirmation);
  await tester.pumpAndSettle();
  expect(tester.widget<CheckboxListTile>(policyConfirmation).value, isTrue);

  final confirm = _previewConfirmButton(tester);
  await tester.ensureVisible(confirm);
  expect(confirm.hitTestable(), findsOneWidget);
  return confirm;
}

Finder _previewConfirmButton(WidgetTester tester) => find.descendant(
  of: find.byType(AppDialog),
  matching: find.widgetWithText(FilledButton, DataSettingsUiCopy.confirmImport),
);

Future<void> _waitForCompletedImport(WidgetTester tester) async {
  final completed = _dialogText(
    tester,
    DataSettingsUiCopy.importCompletedTitle,
  );
  for (var i = 0; i < 100 && completed.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
  expect(completed, findsOneWidget);
}

DateTime _storedDate(
  SharedPreferences preferences,
  String key,
  String dateField,
) {
  final row =
      jsonDecode(preferences.getStringList(key)!.single)
          as Map<String, dynamic>;
  return DateTime.parse(row[dateField] as String);
}

Future<void> _scrollUntilVisible(WidgetTester tester, Finder target) async {
  final scrollable = find.byType(Scrollable).first;
  await tester.scrollUntilVisible(target, 280, scrollable: scrollable);
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
}

Finder _dialogText(WidgetTester tester, String value) =>
    find.descendant(of: find.byType(AppDialog), matching: find.text(value));

class _BackupFixture {
  final reminderScheduler = RecordingReminderScheduler();
  late final todos = TodoProvider()..scheduler = reminderScheduler;
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

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData(<String, Object>{});

  final Map<String, int> _dateWrites = <String, int>{};
  bool Function()? previewVisibilityProbe;
  bool? previewVisibleAtFirstDateWrite;
  String? _heldDateWriteKey;
  Completer<void>? _heldDateWriteStarted;
  Completer<void>? _heldDateWriteRelease;
  Completer<void>? _heldDateWriteFinished;

  Completer<void> get heldDateWriteStarted => _heldDateWriteStarted!;
  bool get heldDateWriteCompleted =>
      _heldDateWriteFinished?.isCompleted ?? false;

  int get dateWriteCount =>
      _dateWrites.values.fold<int>(0, (total, count) => total + count);

  int dateWriteCountFor(String key) => _dateWrites[key] ?? 0;

  void resetDateWrites() {
    _dateWrites.clear();
    previewVisibleAtFirstDateWrite = null;
  }

  void holdNextDateWrite(String key) {
    _heldDateWriteKey = key;
    _heldDateWriteStarted = Completer<void>();
    _heldDateWriteRelease = Completer<void>();
    _heldDateWriteFinished = Completer<void>();
  }

  void release() {
    _heldDateWriteKey = null;
    final release = _heldDateWriteRelease;
    if (release != null && !release.isCompleted) release.complete();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == _anniversaryPlatformKey || key == _countdownPlatformKey) {
      _dateWrites.update(key, (count) => count + 1, ifAbsent: () => 1);
      previewVisibleAtFirstDateWrite ??= previewVisibilityProbe?.call();
    }
    if (_heldDateWriteKey == key) {
      _heldDateWriteKey = null;
      _heldDateWriteStarted!.complete();
      await _heldDateWriteRelease!.future;
      final saved = await super.setValue(type, key, value);
      _heldDateWriteFinished!.complete();
      return saved;
    }
    return super.setValue(type, key, value);
  }
}
