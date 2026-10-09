import 'dart:async';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/todo_kanban.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/widgets/eisenhower_matrix.dart';
import 'package:duoyi/widgets/todo_completion_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocale previousLocale;

  setUp(() {
    previousLocale = I18n.current;
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() {
    I18n.setLocale(previousLocale);
  });

  test('TodoKanbanGroupMode labels follow original zh-en-zh locale events', () {
    final modes = TodoKanbanGroupMode.values;
    final storageKeys = modes.map((mode) => mode.storageKey).toList();
    final chineseLabels = modes.map((mode) => mode.label).toList();

    expect(modes, [
      TodoKanbanGroupMode.none,
      TodoKanbanGroupMode.priority,
      TodoKanbanGroupMode.dueDate,
      TodoKanbanGroupMode.tag,
      TodoKanbanGroupMode.list,
    ]);
    expect(chineseLabels, ['不分组', '按优先级', '按截止日', '按标签', '按清单']);

    I18n.setLocale(AppLocale.en);
    final englishLabels = modes.map((mode) => mode.label).toList();
    expect(englishLabels, [
      'No grouping',
      'By priority',
      'By due date',
      'By tag',
      'By list',
    ]);

    I18n.setLocale(AppLocale.zh);
    expect(modes.map((mode) => mode.label).toList(), [
      '不分组',
      '按优先级',
      '按截止日',
      '按标签',
      '按清单',
    ]);
    expect(storageKeys, ['none', 'priority', 'due_date', 'tag', 'list']);
    expect(modes.map((mode) => mode.storageKey).toList(), storageKeys);
  });

  testWidgets('cancelled completion confirmation never completes or records', (
    tester,
  ) async {
    final todo = TodoItem(
      id: 'locale-cancel-flow',
      title: '准备复盘：A/B！',
      timeTargetSeconds: 1800,
    );
    final todos = _CountingTodoProvider(todo);
    final audit = _CountingTimeAuditProvider();
    await _pumpCompletionLauncher(tester, todo, todos, audit);

    await tester.tap(find.text('launch'));
    await tester.pumpAndSettle();
    _expectConfirmationCopy(tester, todo.title, english: false);

    I18n.setLocale(AppLocale.en);
    await tester.pump();
    _expectConfirmationCopy(tester, todo.title, english: true);

    I18n.setLocale(AppLocale.zh);
    await tester.pump();
    _expectConfirmationCopy(tester, todo.title, english: false);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(todos.completeCalls, 0);
    expect(audit.addCalls, 0);
    expect(audit.automaticRecordCalls, 0);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(_hasLocaleListeners(), isFalse);
  });

  testWidgets('duplicate in-flight launches show one flow and record once', (
    tester,
  ) async {
    final todo = TodoItem(id: 'locale-duplicate-flow', title: '重复点击任务');
    final todos = _CountingTodoProvider(todo);
    final audit = _CountingTimeAuditProvider();
    await _pumpCompletionLauncher(
      tester,
      todo,
      todos,
      audit,
      launchTwice: true,
    );

    await tester.tap(find.text('launch'));
    await tester.pumpAndSettle();
    _expectConfirmationCopy(tester, todo.title, english: false);
    expect(find.byType(Dialog), findsOneWidget);
    expect(todos.completeCalls, 0);

    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    _expectDurationCopy(tester, todo.title, english: false);
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();

    expect(todos.completeCalls, 1);
    expect(todos.completedIds, [todo.id]);
    expect(audit.addCalls, 0);
    expect(audit.automaticRecordCalls, 1);
    expect(audit.automaticallyRecordedTodos.single.title, todo.title);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(_hasLocaleListeners(), isFalse);
  });

  testWidgets('disposing the caller during confirmation cancels completion', (
    tester,
  ) async {
    final todo = TodoItem(id: 'locale-dispose-confirm', title: '确认中任务');
    final todos = _CountingTodoProvider(todo);
    final audit = _CountingTimeAuditProvider();
    await _pumpCompletionLauncher(tester, todo, todos, audit);

    await tester.tap(find.text('launch'));
    await tester.pumpAndSettle();
    _expectConfirmationCopy(tester, todo.title, english: false);
    expect(_hasLocaleListeners(), isTrue);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('replacement'))),
    );
    await tester.pumpAndSettle();

    expect(todos.completeCalls, 0);
    expect(audit.addCalls, 0);
    expect(audit.automaticRecordCalls, 0);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(_hasLocaleListeners(), isFalse);
    I18n.setLocale(AppLocale.en);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'disposing the caller during duration prompt cancels completion and removes locale listener',
    (tester) async {
      final todo = TodoItem(id: 'locale-dispose-duration', title: '记录中任务');
      final todos = _CountingTodoProvider(todo);
      final audit = _CountingTimeAuditProvider();
      await _pumpCompletionLauncher(tester, todo, todos, audit);

      await tester.tap(find.text('launch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      _expectDurationCopy(tester, todo.title, english: false);
      expect(_hasLocaleListeners(), isTrue);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('replacement'))),
      );
      await tester.pumpAndSettle();

      expect(todos.completeCalls, 0);
      expect(todos.completedIds, isEmpty);
      expect(audit.addCalls, 0);
      expect(audit.automaticRecordCalls, 0);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(_hasLocaleListeners(), isFalse);
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a new account generation can start the same todo while confirmation is pending',
    (tester) async {
      final todo = TodoItem(id: 'locale-generation-confirm', title: '账号确认任务');
      final todos = _CountingTodoProvider(todo);
      final audit = _CountingTimeAuditProvider();
      late BuildContext launcherContext;
      await _pumpCompletionLauncher(
        tester,
        todo,
        todos,
        audit,
        captureLauncherContext: (context) => launcherContext = context,
      );

      await tester.tap(find.text('launch'));
      await tester.pumpAndSettle();
      _expectConfirmationCopy(tester, todo.title, english: false);
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();

      completeTodoWithOptionalTimeRecord(launcherContext, todo);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNWidgets(2));

      // Complete the new-generation flow while the old confirmation stays open.
      await tester.tap(find.text('继续').last);
      await tester.pumpAndSettle();
      _expectDurationCopy(tester, todo.title, english: false);
      await tester.tap(find.text('跳过'));
      await tester.pumpAndSettle();
      expect(todos.completeCalls, 1);
      expect(todos.completedIds, [todo.id]);
      expect(audit.automaticRecordCalls, 1);
      expect(find.byType(SnackBar), findsOneWidget);

      // Returning from the invalidated old confirmation must not run it.
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(todos.completeCalls, 1);
      expect(audit.automaticRecordCalls, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(_hasLocaleListeners(), isFalse);
    },
  );

  testWidgets(
    'a new account generation can start the same todo while duration is pending',
    (tester) async {
      final todo = TodoItem(id: 'locale-generation-duration', title: '账号耗时任务');
      final todos = _CountingTodoProvider(todo);
      final audit = _CountingTimeAuditProvider();
      late BuildContext launcherContext;
      await _pumpCompletionLauncher(
        tester,
        todo,
        todos,
        audit,
        captureLauncherContext: (context) => launcherContext = context,
      );

      await tester.tap(find.text('launch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      _expectDurationCopy(tester, todo.title, english: false);
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();

      completeTodoWithOptionalTimeRecord(launcherContext, todo);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNWidgets(2));
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNWidgets(2));

      // The upper duration route belongs to the valid new-generation flow.
      await tester.tap(find.text('跳过').last);
      await tester.pumpAndSettle();
      expect(todos.completeCalls, 1);
      expect(audit.automaticRecordCalls, 1);

      // The old duration route is still pending, but is now stale.
      await tester.tap(find.text('跳过'));
      await tester.pumpAndSettle();
      expect(todos.completeCalls, 1);
      expect(audit.automaticRecordCalls, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(_hasLocaleListeners(), isFalse);
    },
  );

  testWidgets(
    'account invalidation while completion is held prevents recording and feedback',
    (tester) async {
      final todo = TodoItem(id: 'locale-held-completion', title: '等待完成任务');
      final completionGate = Completer<int>();
      final todos = _CountingTodoProvider(todo, completionGate: completionGate);
      final audit = _CountingTimeAuditProvider();
      await _pumpCompletionLauncher(tester, todo, todos, audit);

      await tester.tap(find.text('launch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('记录'));
      await tester.pumpAndSettle();
      expect(todos.completeCalls, 1);
      expect(todos.completedIds, [todo.id]);
      expect(audit.addCalls, 0);
      expect(audit.automaticRecordCalls, 0);

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      completionGate.complete(1);
      await tester.pumpAndSettle();

      // Completion had already started; later recording and feedback are fenced.
      expect(todos.completeCalls, 1);
      expect(audit.addCalls, 0);
      expect(audit.automaticRecordCalls, 0);
      expect(find.byType(SnackBar), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(_hasLocaleListeners(), isFalse);
    },
  );

  testWidgets(
    'account invalidation during held automatic recording suppresses feedback',
    (tester) async {
      final todo = TodoItem(id: 'locale-held-auto-record', title: '自动记录：A/B！');
      final recordGate = Completer<void>();
      final todos = _CountingTodoProvider(todo);
      final audit = _CountingTimeAuditProvider(automaticRecordGate: recordGate);
      await _pumpCompletionLauncher(tester, todo, todos, audit);

      await tester.tap(find.text('launch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('跳过'));
      await tester.pumpAndSettle();
      expect(todos.completeCalls, 1);
      expect(audit.addCalls, 0);
      expect(audit.automaticRecordCalls, 1);
      expect(audit.automaticallyRecordedTodos.single.id, todo.id);
      expect(find.byType(SnackBar), findsNothing);

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      recordGate.complete();
      await tester.pumpAndSettle();

      // The valid recording was already started; stale completion cannot show
      // feedback or begin a second recording in the new account generation.
      expect(todos.completeCalls, 1);
      expect(audit.addCalls, 0);
      expect(audit.automaticRecordCalls, 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(_hasLocaleListeners(), isFalse);
    },
  );

  testWidgets(
    'caller removal while time recording is held prevents stale feedback',
    (tester) async {
      final todo = TodoItem(id: 'locale-held-time-record', title: '等待记录任务');
      final recordGate = Completer<void>();
      final todos = _CountingTodoProvider(todo);
      final audit = _CountingTimeAuditProvider(addGate: recordGate);
      await _pumpCompletionLauncher(tester, todo, todos, audit);

      await tester.tap(find.text('launch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '18');
      await tester.pump();
      await tester.tap(find.text('记录'));
      await tester.pumpAndSettle();
      expect(todos.completeCalls, 1);
      expect(audit.addCalls, 1);
      expect(audit.addedEntries, hasLength(1));
      expect(find.byType(SnackBar), findsNothing);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('replacement'))),
      );
      await tester.pumpAndSettle();
      recordGate.complete();
      await tester.pumpAndSettle();

      // The add call was already in flight when its caller disappeared.
      expect(todos.completeCalls, 1);
      expect(audit.addCalls, 1);
      expect(audit.addedEntries, hasLength(1));
      expect(audit.automaticRecordCalls, 0);
      expect(find.byType(SnackBar), findsNothing);
      expect(_hasLocaleListeners(), isFalse);
    },
  );

  testWidgets(
    'active confirmation and duration prompt translate without losing route input or focus',
    (tester) async {
      final title = '整理周报：A/B！';
      final todo = TodoItem(
        id: 'locale-live-flow',
        title: title,
        timeTargetSeconds: 1800,
      );
      final todos = _CountingTodoProvider(todo);
      final audit = _CountingTimeAuditProvider();
      await _pumpCompletionLauncher(tester, todo, todos, audit);

      await tester.tap(find.text('launch'));
      await tester.pumpAndSettle();
      _expectConfirmationCopy(tester, title, english: false);
      expect(todos.completeCalls, 0);
      expect(audit.addCalls, 0);

      I18n.setLocale(AppLocale.en);
      await tester.pump();
      _expectConfirmationCopy(tester, title, english: true);
      expect(todos.completeCalls, 0);

      I18n.setLocale(AppLocale.zh);
      await tester.pump();
      _expectConfirmationCopy(tester, title, english: false);
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      _expectDurationCopy(tester, title, english: false);
      final textFieldFinder = find.byType(EditableText);
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '47');
      await tester.pump();
      final before = tester.widget<EditableText>(textFieldFinder);
      final controller = before.controller;
      final focusNode = before.focusNode;
      final selection = controller.selection;
      final route = ModalRoute.of(tester.element(textFieldFinder));
      expect(before.focusNode.hasFocus, isTrue);
      expect(controller.text, '47');

      I18n.setLocale(AppLocale.en);
      await tester.pump();
      _expectDurationCopy(tester, title, english: true);
      _expectInputState(
        tester,
        textFieldFinder,
        controller: controller,
        focusNode: focusNode,
        selection: selection,
        route: route,
      );

      I18n.setLocale(AppLocale.zh);
      await tester.pump();
      _expectDurationCopy(tester, title, english: false);
      _expectInputState(
        tester,
        textFieldFinder,
        controller: controller,
        focusNode: focusNode,
        selection: selection,
        route: route,
      );
      expect(todos.completeCalls, 0);
      expect(audit.addCalls, 0);
      expect(audit.automaticRecordCalls, 0);

      await tester.tap(find.text('记录'));
      await tester.pumpAndSettle();

      expect(todos.completeCalls, 1);
      expect(todos.completedIds, [todo.id]);
      expect(audit.addCalls, 1);
      expect(audit.addedEntries, hasLength(1));
      expect(audit.addedEntries.single.title, title);
      expect(audit.addedEntries.single.durationSeconds, 47 * 60);
      expect(audit.addedEntries.single.note, '手动记录耗时：47 分钟');
      expect(audit.automaticRecordCalls, 0);
      expect(find.text('已完成：$title'), findsOneWidget);

      // A visible snackbar changes copy in place; its existing timeout keeps running.
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(SnackBar), findsOneWidget);
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      expect(find.text('Completed: $title'), findsOneWidget);
      expect(todos.completeCalls, 1);
      expect(audit.addCalls, 1);
      I18n.setLocale(AppLocale.zh);
      await tester.pump();
      expect(find.text('已完成：$title'), findsOneWidget);
      expect(todos.completeCalls, 1);
      expect(audit.addCalls, 1);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(todos.completeCalls, 1);
      expect(audit.addCalls, 1);
      expect(_hasLocaleListeners(), isFalse);
    },
  );

  testWidgets(
    'locale changes during duration dismissal retain dialog resources until route removal',
    (tester) async {
      final title = '退出动画：A/B！';
      final todo = TodoItem(id: 'locale-dismiss-resources', title: title);
      final todos = _CountingTodoProvider(todo);
      final audit = _CountingTimeAuditProvider();
      await _pumpCompletionLauncher(tester, todo, todos, audit);

      await tester.tap(find.text('launch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '23');
      await tester.pump();

      final fieldFinder = find.byType(EditableText);
      final before = tester.widget<EditableText>(fieldFinder);
      final controller = before.controller;
      final focusNode = before.focusNode;
      final selection = controller.selection;
      final route = ModalRoute.of(tester.element(fieldFinder));

      await tester.tap(find.text('跳过'));
      await tester.pump(const Duration(milliseconds: 35));
      expect(find.byType(EditableText), findsOneWidget);

      I18n.setLocale(AppLocale.en);
      await tester.pump(const Duration(milliseconds: 35));
      _expectDurationCopy(tester, title, english: true);
      _expectRetainedInputResources(
        tester,
        fieldFinder,
        controller: controller,
        focusNode: focusNode,
        selection: selection,
        route: route,
      );

      I18n.setLocale(AppLocale.zh);
      await tester.pump(const Duration(milliseconds: 35));
      _expectDurationCopy(tester, title, english: false);
      _expectRetainedInputResources(
        tester,
        fieldFinder,
        controller: controller,
        focusNode: focusNode,
        selection: selection,
        route: route,
      );
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsNothing);
      expect(todos.completeCalls, 1);
      expect(audit.automaticRecordCalls, 1);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(_hasLocaleListeners(), isFalse);
    },
  );

  testWidgets('skipping duration records completion exactly once', (
    tester,
  ) async {
    final todo = TodoItem(id: 'locale-skip-flow', title: '完成回归测试');
    final todos = _CountingTodoProvider(todo);
    final audit = _CountingTimeAuditProvider();
    await _pumpCompletionLauncher(tester, todo, todos, audit);

    await tester.tap(find.text('launch'));
    await tester.pumpAndSettle();
    _expectConfirmationCopy(tester, todo.title, english: false);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    _expectDurationCopy(tester, todo.title, english: false);
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();

    expect(todos.completeCalls, 1);
    expect(todos.completedIds, [todo.id]);
    expect(audit.addCalls, 0);
    expect(audit.automaticRecordCalls, 1);
    expect(audit.automaticallyRecordedTodos.single.title, todo.title);
  });

  testWidgets(
    'standalone Eisenhower matrix refreshes empty status and more copy on locale events',
    (tester) async {
      final completed = TodoItem(
        id: 'matrix-completed',
        title: '用户已完成：一！',
        quadrant: EisenhowerQuadrant.urgentImportant,
        isCompleted: true,
      );
      final overdue = TodoItem(
        id: 'matrix-overdue',
        title: '用户逾期：二？',
        quadrant: EisenhowerQuadrant.notUrgentImportant,
        dueDate: DateTime(2000, 1, 1),
      );
      final moreItems = List.generate(
        4,
        (index) => TodoItem(
          id: 'matrix-more-$index',
          title: '用户任务：$index。',
          quadrant: EisenhowerQuadrant.urgentNotImportant,
        ),
      );
      await tester.pumpWidget(
        _matrixApp({
          EisenhowerQuadrant.urgentImportant: [completed],
          EisenhowerQuadrant.notUrgentImportant: [overdue],
          EisenhowerQuadrant.urgentNotImportant: moreItems,
        }),
      );
      await tester.pumpAndSettle();

      _expectMatrixCopy(tester, english: false);
      expect(find.text(completed.title), findsOneWidget);
      expect(find.text(overdue.title), findsOneWidget);
      final chineseMore = tester.widget<Text>(find.textContaining('更多')).data!;
      final hiddenCount = RegExp(
        r'^\+(\d+) 更多\.\.\.$',
      ).firstMatch(chineseMore)!.group(1);

      I18n.setLocale(AppLocale.en);
      await tester.pump();

      _expectMatrixCopy(tester, english: true);
      expect(find.text('+$hiddenCount more...'), findsOneWidget);
      expect(find.text(completed.title), findsOneWidget);
      expect(find.text(overdue.title), findsOneWidget);

      I18n.setLocale(AppLocale.zh);
      await tester.pump();
      _expectMatrixCopy(tester, english: false);
      expect(find.text(chineseMore), findsOneWidget);
      expect(find.text(completed.title), findsOneWidget);
      expect(find.text(overdue.title), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(_hasLocaleListeners(), isFalse);
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'locale rebuild preserves Eisenhower edit permissions and drag callback',
    (tester) async {
      final editable = TodoItem(
        id: 'editable',
        title: '可移动任务',
        quadrant: EisenhowerQuadrant.urgentImportant,
      );
      final readOnly = TodoItem(
        id: 'read-only',
        title: '只读任务',
        quadrant: EisenhowerQuadrant.urgentImportant,
      );
      final moves = <(TodoItem, EisenhowerQuadrant)>[];
      await tester.pumpWidget(
        _matrixApp(
          {
            EisenhowerQuadrant.urgentImportant: [editable, readOnly],
          },
          canEditTodo: (todo) => todo.id != readOnly.id,
          onTodoQuadrantChanged: (todo, quadrant) =>
              moves.add((todo, quadrant)),
        ),
      );

      expect(find.byType(LongPressDraggable<TodoItem>), findsOneWidget);
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      expect(find.byType(LongPressDraggable<TodoItem>), findsOneWidget);
      await _longPressDrag(
        tester,
        find.text(editable.title),
        const Offset(0, 190),
      );

      expect(moves, hasLength(1));
      expect(moves.single.$1.id, editable.id);
      expect(moves.single.$2, EisenhowerQuadrant.urgentNotImportant);
      expect(find.text(readOnly.title), findsOneWidget);
    },
  );
}

// These fixtures inspect Flutter's protected notifier getter only to prove
// listener teardown; a single local exemption keeps all lifecycle assertions.
bool _hasLocaleListeners() {
  // ignore: invalid_use_of_protected_member
  return I18n.localeListenable.hasListeners;
}

Future<void> _pumpCompletionLauncher(
  WidgetTester tester,
  TodoItem todo,
  _CountingTodoProvider todos,
  _CountingTimeAuditProvider audit, {
  bool launchTwice = false,
  void Function(BuildContext context)? captureLauncherContext,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TodoProvider>.value(value: todos),
        ChangeNotifierProvider<TimeAuditProvider>.value(value: audit),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              captureLauncherContext?.call(context);
              return FilledButton(
                onPressed: () {
                  completeTodoWithOptionalTimeRecord(context, todo);
                  if (launchTwice) {
                    completeTodoWithOptionalTimeRecord(context, todo);
                  }
                },
                child: const Text('launch'),
              );
            },
          ),
        ),
      ),
    ),
  );
}

Widget _matrixApp(
  Map<EisenhowerQuadrant, List<TodoItem>> groups, {
  bool Function(TodoItem)? canEditTodo,
  void Function(TodoItem, EisenhowerQuadrant)? onTodoQuadrantChanged,
}) {
  return ChangeNotifierProvider(
    create: (_) => ThemeProvider(),
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: EisenhowerMatrix(
            quadrantGroups: groups,
            onQuadrantTap: (_) {},
            canEditTodo: canEditTodo,
            onTodoQuadrantChanged: onTodoQuadrantChanged,
          ),
        ),
      ),
    ),
  );
}

Future<void> _longPressDrag(
  WidgetTester tester,
  Finder from,
  Offset delta,
) async {
  final gesture = await tester.startGesture(tester.getCenter(from));
  await tester.pump(const Duration(milliseconds: 500));
  await gesture.moveBy(delta);
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

void _expectInputState(
  WidgetTester tester,
  Finder finder, {
  required TextEditingController controller,
  required FocusNode focusNode,
  required TextSelection selection,
  required ModalRoute<dynamic>? route,
}) {
  final editable = tester.widget<EditableText>(finder);
  expect(identical(editable.controller, controller), isTrue);
  expect(identical(editable.focusNode, focusNode), isTrue);
  expect(editable.controller.text, '47');
  expect(editable.controller.selection, selection);
  expect(editable.focusNode.hasFocus, isTrue);
  expect(identical(ModalRoute.of(tester.element(finder)), route), isTrue);
}

void _expectRetainedInputResources(
  WidgetTester tester,
  Finder finder, {
  required TextEditingController controller,
  required FocusNode focusNode,
  required TextSelection selection,
  required ModalRoute<dynamic>? route,
}) {
  final editable = tester.widget<EditableText>(finder);
  expect(identical(editable.controller, controller), isTrue);
  expect(identical(editable.focusNode, focusNode), isTrue);
  expect(editable.controller.text, '23');
  expect(editable.controller.selection, selection);
  expect(identical(ModalRoute.of(tester.element(finder)), route), isTrue);
}

void _expectConfirmationCopy(
  WidgetTester tester,
  String title, {
  required bool english,
}) {
  expect(find.text(english ? 'Confirm completion' : '确认完成任务'), findsOneWidget);
  expect(
    find.text(english ? 'Complete "$title" now?' : '现在完成“$title”吗？'),
    findsOneWidget,
  );
  expect(find.text(english ? 'Cancel' : '取消'), findsOneWidget);
  expect(find.text(english ? 'Continue' : '继续'), findsOneWidget);
}

void _expectDurationCopy(
  WidgetTester tester,
  String title, {
  required bool english,
}) {
  expect(find.text(english ? 'Record duration' : '记录耗时'), findsOneWidget);
  expect(
    find.text(
      english
          ? 'Would you like to log how long you spent on "$title"?'
          : '要不要顺手记录一下“$title”这次花了多久？',
    ),
    findsOneWidget,
  );
  expect(find.text(english ? 'Skip' : '跳过'), findsOneWidget);
  expect(find.text(english ? 'Record' : '记录'), findsOneWidget);
  final decoration = tester
      .widget<TextField>(find.byType(TextField))
      .decoration!;
  expect(decoration.labelText, english ? 'Duration' : '耗时');
  expect(decoration.suffixText, english ? 'min' : '分钟');
  expect(decoration.hintText, english ? 'Leave empty to skip' : '留空则跳过');
}

void _expectMatrixCopy(WidgetTester tester, {required bool english}) {
  expect(find.text(english ? 'No tasks' : '暂无任务'), findsOneWidget);
  expect(find.text(english ? 'Completed' : '已完成'), findsOneWidget);
  expect(find.text(english ? 'Overdue' : '逾期'), findsOneWidget);

  final quadrantTexts = english
      ? const [
          'Important & Urgent',
          'Do now',
          'Important, Not Urgent',
          'Schedule',
          'Urgent, Not Important',
          'Delegate',
          'Not Important, Not Urgent',
          'Do less',
        ]
      : const ['重要且紧急', '马上做', '重要不紧急', '计划做', '紧急不重要', '委托做', '不重要不紧急', '减少做'];
  for (final text in quadrantTexts) {
    expect(find.text(text), findsOneWidget, reason: 'quadrant copy: $text');
  }
}

class _CountingTodoProvider extends TodoProvider {
  _CountingTodoProvider(this.todo, {this.completionGate});

  final TodoItem todo;
  final Completer<int>? completionGate;
  int completeCalls = 0;
  List<String> completedIds = const [];

  @override
  List<TodoItem> get todos => [todo];

  @override
  Future<int> completeTodos(
    Iterable<String> ids, {
    bool recordCompletionTime = true,
  }) async {
    completeCalls++;
    completedIds = ids.toList();
    if (completionGate != null) await completionGate!.future;
    return completedIds.contains(todo.id) ? 1 : 0;
  }
}

class _CountingTimeAuditProvider extends TimeAuditProvider {
  _CountingTimeAuditProvider({this.addGate, this.automaticRecordGate});

  final Completer<void>? addGate;
  final Completer<void>? automaticRecordGate;
  int addCalls = 0;
  int automaticRecordCalls = 0;
  final List<TimeEntry> addedEntries = [];
  final List<TodoItem> automaticallyRecordedTodos = [];

  @override
  Future<void> add(TimeEntry entry) async {
    addCalls++;
    addedEntries.add(entry);
    if (addGate != null) await addGate!.future;
  }

  @override
  Future<void> recordTodoCompletion(
    TodoItem todo, {
    DateTime? completedAt,
  }) async {
    automaticRecordCalls++;
    automaticallyRecordedTodos.add(todo);
    if (automaticRecordGate != null) await automaticRecordGate!.future;
  }
}
