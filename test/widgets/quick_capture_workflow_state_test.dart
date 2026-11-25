import 'dart:async';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/note.dart';
import 'package:duoyi/models/quick_capture_template.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/quick_capture_template_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/app_access_route_gate.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/reminder_issue_copy.dart';
import 'package:duoyi/widgets/quick_capture_fab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets('Held note save is single use and updates its copy with locale', (
    tester,
  ) async {
    final notes = _Notes()
      ..nextWriteGate = Completer<void>()
      ..nextWriteStarted = Completer<void>();
    final started = notes.nextWriteStarted!;
    final gate = notes.nextWriteGate!;
    final fixture = await _mount(tester, notes: notes);
    await _openNote(tester);
    await tester.enterText(find.byType(TextField), 'held note');

    final save = _noteSave(tester);
    save();
    save();
    await tester.pump();
    expect(started.isCompleted, isTrue);
    await started.future;

    expect(notes.attempts, hasLength(1));
    expect(find.text('随手记'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);

    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();

    expect(find.text('Quick note'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(controller.text, 'held note');
    expect(notes.attempts, hasLength(1));

    gate.complete();
    await tester.pumpAndSettle();

    expect(notes.acknowledged, hasLength(1));
    expect(notes.acknowledged.single.content, 'held note');
    expect(find.text('Quick note'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(fixture.routeGate.currentRoute, isNotNull);
  });

  testWidgets('Failed note save retains controller and selection for retry', (
    tester,
  ) async {
    final notes = _Notes()..failNextWrite = true;
    await _mount(tester, notes: notes);
    await _openNote(tester);
    await tester.enterText(find.byType(TextField), 'draft after failure');
    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    const selection = TextSelection(baseOffset: 2, extentOffset: 8);
    controller.selection = selection;

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('保存失败，草稿已保留，请重试。'), findsOneWidget);
    expect(find.text('随手记'), findsOneWidget);
    expect(controller.text, 'draft after failure');
    expect(controller.selection, selection);
    expect(notes.attempts, hasLength(1));
    expect(notes.acknowledged, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(notes.attempts, hasLength(2));
    expect(notes.acknowledged.single.content, 'draft after failure');
    expect(find.text('随手记'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Removing FAB closes its held note dialog and late ack cannot pop new UI',
    (tester) async {
      final notes = _Notes()
        ..nextWriteGate = Completer<void>()
        ..nextWriteStarted = Completer<void>();
      final started = notes.nextWriteStarted!;
      final gate = notes.nextWriteGate!;
      final fabVisible = ValueNotifier(true);
      final fixture = await _mount(
        tester,
        notes: notes,
        fabVisible: fabVisible,
      );
      await _openNote(tester);
      await tester.enterText(find.byType(TextField), 'issued before removal');
      final save = _noteSave(tester);
      final cancel = _noteCancel(tester);
      save();
      await tester.pump();
      expect(started.isCompleted, isTrue);
      await started.future;

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      fabVisible.value = false;
      await tester.pumpAndSettle();

      expect(
        tester.state<NavigatorState>(find.byType(Navigator)),
        same(navigator),
      );
      expect(find.text('随手记'), findsNothing);
      expect(find.text('home screen'), findsOneWidget);
      save();
      cancel();
      await tester.pumpAndSettle();
      expect(notes.attempts, hasLength(1));

      final cover = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('new UI')),
      );
      unawaited(navigator.push(cover));
      await tester.pumpAndSettle();
      expect(fixture.routeGate.currentRoute, same(cover));
      expect(find.text('new UI'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();

      expect(notes.acknowledged, hasLength(1));
      expect(fixture.routeGate.currentRoute, same(cover));
      expect(find.text('new UI'), findsOneWidget);
      expect(find.text('随手记'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);

      navigator.pop();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Same-frame lock and unlock expires held note dialog and retained callbacks',
    (tester) async {
      final notes = _Notes()
        ..nextWriteGate = Completer<void>()
        ..nextWriteStarted = Completer<void>();
      final started = notes.nextWriteStarted!;
      final gate = notes.nextWriteGate!;
      final lock = _AccessLock();
      final fixture = await _mount(tester, notes: notes, lock: lock);
      await _openNote(tester);
      await tester.enterText(find.byType(TextField), 'held during lock change');
      final save = _noteSave(tester);
      final cancel = _noteCancel(tester);
      save();
      await tester.pump();
      expect(started.isCompleted, isTrue);
      await started.future;

      lock.setLocked(true);
      lock.setLocked(false);
      expect(lock.isLocked, isFalse);
      await tester.pumpAndSettle();

      expect(find.text('随手记'), findsNothing);
      save();
      cancel();
      await tester.pumpAndSettle();
      expect(notes.attempts, hasLength(1));
      expect(fixture.routeGate.currentRoute, isNotNull);

      gate.complete();
      await tester.pumpAndSettle();

      expect(notes.acknowledged, hasLength(1));
      expect(find.text('home screen'), findsOneWidget);
      expect(find.text('随手记'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Same-frame cover and return expires retained note callbacks and removes the dialog',
    (tester) async {
      final notes = _Notes();
      final fixture = await _mount(tester, notes: notes);
      await _openNote(tester);
      await tester.enterText(find.byType(TextField), 'must not save');
      final save = _noteSave(tester);
      final cancel = _noteCancel(tester);
      final revision = fixture.routeGate.routeRevision.value;
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      final cover = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('covered page')),
      );

      unawaited(navigator.push(cover));
      navigator.pop();
      expect(fixture.routeGate.routeRevision.value, revision + 2);
      await tester.pumpAndSettle();

      expect(find.text('covered page'), findsNothing);
      expect(find.text('随手记'), findsNothing);
      save();
      cancel();
      await tester.pumpAndSettle();

      expect(find.text('home screen'), findsOneWidget);
      expect(find.text('随手记'), findsNothing);
      expect(notes.attempts, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Template sheet follows locale and save then apply succeed from its source route',
    (tester) async {
      final templates = QuickCaptureTemplateProvider();
      final todos = _Todos();
      await _mount(tester, templates: templates, todos: todos);

      await _openTemplates(tester);
      expect(find.text('快捷模板'), findsOneWidget);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(find.text('Quick templates'), findsOneWidget);
      expect(find.text('Work meeting'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Save template'));
      await tester.pumpAndSettle();
      expect(find.text('Template name'), findsOneWidget);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Workflow template');
      await tester.enterText(fields.at(1), 'From template');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(
        templates.customTemplates.map((template) => template.name),
        contains('Workflow template'),
      );
      expect(find.text('Quick templates'), findsNothing);

      await _openTemplates(tester);
      await tester.tap(find.text('Workflow template'));
      await tester.pumpAndSettle();
      expect(find.text('Workflow template'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Prepare release');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(todos.writes, hasLength(1));
      expect(todos.writes.single.title, 'From template Prepare release');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Template deletion held across account invalidation cannot publish its result',
    (tester) async {
      final template = QuickCaptureTemplate(
        id: 'delete-me',
        name: 'Delete me',
        kind: QuickCaptureTemplateKind.todo,
      );
      final templates = _HeldDeleteTemplates(template);
      await _mount(tester, templates: templates);
      await _openTemplates(tester);

      await tester.tap(find.byTooltip('删除'));
      await tester.pump();
      await templates.deleteStarted.future;
      expect(templates.deleteAttempts, 1);

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      await tester.pumpAndSettle();
      expect(find.text('快捷模板'), findsNothing);

      templates.deleteRelease.complete();
      await tester.pumpAndSettle();

      expect(templates.customTemplates, contains(template));
      expect(templates.publishedDeletes, 0);
      expect(find.text('快捷模板'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'AI batch stops after its first held note loses account authority',
    (tester) async {
      final notes = _Notes()
        ..nextWriteGate = Completer<void>()
        ..nextWriteStarted = Completer<void>();
      final started = notes.nextWriteStarted!;
      final gate = notes.nextWriteGate!;
      final ai = AiService()..updateFromServerConfig({'ai_enabled': true});
      final pomodoro = _Pomodoro();
      await _mount(tester, notes: notes, ai: ai, pomodoro: pomodoro);
      await _openAiCommands(tester);
      await tester.enterText(find.byType(TextField), '记笔记 第一个；记笔记 第二个\n开始专注');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '执行'));
      await tester.pumpAndSettle();
      expect(started.isCompleted, isTrue);
      await started.future;

      expect(notes.attempts, hasLength(1));
      expect(notes.attempts.single.content, '第一个');

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      gate.complete();
      await tester.pumpAndSettle();

      expect(notes.attempts, hasLength(1));
      expect(notes.acknowledged, isEmpty);
      expect(pomodoro.focusStarts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Template reminder preflight cannot create a task after account invalidation',
    (tester) async {
      final notification = _HeldReminderPreflight();
      final todos = _Todos();
      await _mount(tester, notification: notification, todos: todos);
      await _openTemplates(tester);
      await tester.tap(find.text('工作会议'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '明天下午3点项目评审');
      await tester.tap(find.widgetWithText(FilledButton, '创建'));
      await tester.pumpAndSettle();
      expect(notification.preflightStarted.isCompleted, isTrue);
      await notification.preflightStarted.future;

      expect(notification.preflightCalls, 1);
      expect(todos.attempts, 0);

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      notification.preflightRelease.complete(true);
      await tester.pumpAndSettle();

      expect(todos.attempts, 0);
      expect(todos.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<_Fixture> _mount(
  WidgetTester tester, {
  _Notes? notes,
  AiService? ai,
  TodoProvider? todos,
  PomodoroProvider? pomodoro,
  QuickCaptureTemplateProvider? templates,
  NotificationService? notification,
  AppLockProvider? lock,
  ValueNotifier<bool>? fabVisible,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final effectiveNotes = notes ?? _Notes();
  final effectiveAi = ai ?? AiService();
  final routeGate = AppAccessRouteGate();
  final fixture = _Fixture(
    notes: effectiveNotes,
    ai: effectiveAi,
    todos: todos,
    pomodoro: pomodoro,
    templates: templates,
    notification: notification,
    lock: lock,
    fabVisible: fabVisible,
    routeGate: routeGate,
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<NoteProvider>.value(value: effectiveNotes),
        ChangeNotifierProvider<AiService>.value(value: effectiveAi),
        if (todos != null)
          ChangeNotifierProvider<TodoProvider>.value(value: todos),
        if (pomodoro != null)
          ChangeNotifierProvider<PomodoroProvider>.value(value: pomodoro),
        if (templates != null)
          ChangeNotifierProvider<QuickCaptureTemplateProvider>.value(
            value: templates,
          ),
        if (notification != null)
          ChangeNotifierProvider<NotificationService>.value(
            value: notification,
          ),
        if (lock != null)
          ChangeNotifierProvider<AppLockProvider>.value(value: lock),
      ],
      child: MaterialApp(
        navigatorObservers: [routeGate],
        home: Scaffold(
          body: Center(child: Text('home screen')),
          floatingActionButton: fabVisible == null
              ? const QuickCaptureFab()
              : ValueListenableBuilder<bool>(
                  valueListenable: fabVisible,
                  builder: (_, visible, _) => visible
                      ? const QuickCaptureFab()
                      : const SizedBox.shrink(),
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() => fixture.dispose(tester));
  return fixture;
}

Future<void> _openNote(WidgetTester tester) async {
  await tester.tap(_mainFab());
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithIcon(FloatingActionButton, Icons.edit_note));
  await tester.pumpAndSettle();
  expect(find.text('随手记'), findsOneWidget);
}

Future<void> _openTemplates(WidgetTester tester) async {
  await tester.tap(_mainFab());
  await tester.pumpAndSettle();
  await tester.tap(find.text(I18n.tr('quick.menu.template')));
  await tester.pumpAndSettle();
}

Future<void> _openAiCommands(WidgetTester tester) async {
  await tester.tap(_mainFab());
  await tester.pumpAndSettle();
  await tester.tap(find.text('AI 指令'));
  await tester.pumpAndSettle();
}

Finder _mainFab() => find.byWidgetPredicate(
  (widget) =>
      widget is FloatingActionButton && widget.heroTag == 'quick_capture',
);

VoidCallback _noteSave(WidgetTester tester) => tester
    .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
    .onPressed!;

VoidCallback _noteCancel(WidgetTester tester) =>
    tester.widget<TextButton>(find.widgetWithText(TextButton, '取消')).onPressed!;

class _Fixture {
  const _Fixture({
    required this.notes,
    required this.ai,
    required this.routeGate,
    this.todos,
    this.pomodoro,
    this.templates,
    this.notification,
    this.lock,
    this.fabVisible,
  });

  final _Notes notes;
  final AiService ai;
  final TodoProvider? todos;
  final PomodoroProvider? pomodoro;
  final QuickCaptureTemplateProvider? templates;
  final NotificationService? notification;
  final AppLockProvider? lock;
  final ValueNotifier<bool>? fabVisible;
  final AppAccessRouteGate routeGate;

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    routeGate.dispose();
    notes.dispose();
    ai.dispose();
    todos?.dispose();
    pomodoro?.dispose();
    templates?.dispose();
    notification?.dispose();
    lock?.dispose();
    fabVisible?.dispose();
  }
}

class _Notes extends NoteProvider {
  final attempts = <NoteItem>[];
  final acknowledged = <NoteItem>[];
  Completer<void>? nextWriteGate;
  Completer<void>? nextWriteStarted;
  bool failNextWrite = false;

  @override
  Future<void> addOrUpdateNotePersisted(
    NoteItem note, {
    bool Function()? canWrite,
  }) async {
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    attempts.add(note);
    final started = nextWriteStarted;
    nextWriteStarted = null;
    if (started != null && !started.isCompleted) started.complete();
    final gate = nextWriteGate;
    nextWriteGate = null;
    if (gate != null) await gate.future;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        ) ||
        canWrite?.call() == false) {
      throw const AccountPreferenceWriteCanceled();
    }
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('mock note write failed');
    }
    acknowledged.add(note);
  }
}

class _Todos extends TodoProvider {
  final writes = <TodoItem>[];
  var attempts = 0;

  @override
  Future<TodoReminderSyncResult?> addTodoWithResult(
    TodoItem todo, {
    bool waitForReminderSync = true,
    bool reportReminderScheduleFailure = false,
    bool Function()? canWrite,
  }) async {
    attempts++;
    if (canWrite?.call() == false) return null;
    writes.add(todo);
    return null;
  }
}

class _Pomodoro extends PomodoroProvider {
  var focusStarts = 0;

  @override
  void toggleTimer() {
    focusStarts++;
  }
}

class _AccessLock extends AppLockProvider {
  final ValueNotifier<bool> _locked = ValueNotifier(false);

  @override
  bool get isLocked => _locked.value;

  void setLocked(bool locked) {
    _locked.value = locked;
    notifyListeners();
  }

  @override
  void dispose() {
    _locked.dispose();
    super.dispose();
  }
}

class _HeldDeleteTemplates extends QuickCaptureTemplateProvider {
  _HeldDeleteTemplates(QuickCaptureTemplate template) : custom = [template];

  final List<QuickCaptureTemplate> custom;
  final deleteStarted = Completer<void>();
  final deleteRelease = Completer<void>();
  var deleteAttempts = 0;
  var publishedDeletes = 0;

  @override
  List<QuickCaptureTemplate> get customTemplates => List.unmodifiable(custom);

  @override
  List<QuickCaptureTemplate> get templates => [
    ...QuickCaptureTemplate.builtIns(),
    ...custom,
  ];

  @override
  Future<void> deleteTemplate(String id) async {
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    deleteAttempts++;
    deleteStarted.complete();
    await deleteRelease.future;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
      throw const AccountPreferenceWriteCanceled();
    }
    custom.removeWhere((template) => template.id == id);
    publishedDeletes++;
    notifyListeners();
  }
}

class _HeldReminderPreflight extends NotificationService {
  final preflightStarted = Completer<void>();
  final preflightRelease = Completer<bool>();
  var preflightCalls = 0;

  @override
  Future<bool> ensureReadyForReminder({
    DateTime? scheduledTime,
    String? issueTitle,
    NotificationIssueTitle? issueTitleCode,
    String? relatedId,
    bool Function()? canContinue,
  }) async {
    preflightCalls++;
    preflightStarted.complete();
    return preflightRelease.future;
  }
}
