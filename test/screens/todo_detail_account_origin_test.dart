import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/todo_detail_ui_copy.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/todo_detail_screen.dart';
import 'package:duoyi/screens/today_detail_router.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'same-ID detail clears old draft, blocks retained callbacks, and allows a new-origin save',
    (tester) async {
      final provider = _RecordingTodoProvider();
      final old = TodoItem(
        id: 'colliding-task',
        title: 'Old account title',
        notes: 'Old account notes',
        subtasks: [
          Subtask(id: 'old-child', title: 'Old child', sortOrder: 0),
          Subtask(id: 'second-child', title: 'Second child', sortOrder: 1),
        ],
      );
      await provider.addTodo(old);
      final oldOrigin = AccountLocalDataCleaner.accountDataGeneration;
      _registerCleanup(tester, [provider]);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('duoyi_locale_v1', 'en');
      I18n.setLocale(AppLocale.en);

      await tester.pumpWidget(_directDetailApp(provider, old.id));
      await tester.tap(find.text('open-detail'));
      await tester.pumpAndSettle();
      expect(find.byType(TodoDetailScreen), findsOneWidget);

      final oldTitleController = tester
          .widget<TextField>(find.byType(TextField).at(0))
          .controller!;
      final oldNotesController = tester
          .widget<TextField>(find.byType(TextField).at(1))
          .controller!;
      final titleField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.controller == oldTitleController,
      );
      final notesField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.controller == oldNotesController,
      );

      final detailScrollable = find
          .descendant(
            of: find.byType(TodoDetailScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Old child'),
        300,
        scrollable: detailScrollable,
      );
      await tester.pumpAndSettle();

      final childTile = find.ancestor(
        of: find.text('Old child'),
        matching: find.byType(ListTile),
      );
      final oldChildCheckbox = tester.widget<Checkbox>(
        find.descendant(of: childTile, matching: find.byType(Checkbox)),
      );
      final retainedToggle = oldChildCheckbox.onChanged!;
      final oldSubtaskList = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      final retainedReorder = oldSubtaskList.onReorder;

      await tester.scrollUntilVisible(
        titleField,
        -300,
        scrollable: detailScrollable,
      );
      await tester.pumpAndSettle();

      // The recording provider accepts the production API's optional origin
      // argument, so this covers the actual detail callbacks while the origin
      // is still current.
      retainedToggle(true);
      retainedReorder(0, 1);
      await tester.pump();
      await tester.pump();
      expect(provider.subtaskCalls.map((call) => call.operation).toList(), [
        'toggle',
        'reorder',
      ]);
      expect(
        provider.subtaskCalls
            .map((call) => call.expectedAccountDataGeneration)
            .toList(),
        [oldOrigin, oldOrigin],
      );

      await tester.enterText(titleField, 'Old unsaved title draft');
      await tester.enterText(notesField, 'Old unsaved notes draft');
      await tester.pump();
      expect(oldTitleController.text, 'Old unsaved title draft');
      expect(oldNotesController.text, 'Old unsaved notes draft');

      final next = TodoItem(
        id: old.id,
        title: 'New account title',
        notes: 'New account notes',
        subtasks: [Subtask(id: 'new-child', title: 'New child', sortOrder: 0)],
      );

      // Exercise the account cleanup boundary: account data is cleared, while
      // the device-level locale preference remains available.
      await AccountLocalDataCleaner.clearSharedPreferences();
      expect(AccountLocalDataCleaner.accountDataGeneration, isNot(oldOrigin));
      expect(I18n.current, AppLocale.en);
      expect(prefs.getString('duoyi_locale_v1'), 'en');
      expect(oldTitleController.text, isEmpty);
      expect(oldNotesController.text, isEmpty);

      provider.resetLocalState();
      await prefs.setString('todos', jsonEncode([next.toJson()]));
      await provider.loadFromStorage();
      expect(provider.todos.single.title, next.title);
      expect(provider.todos.single.notes, next.notes);

      await tester.pumpAndSettle();
      expect(find.byType(TodoDetailScreen), findsOneWidget);
      expect(find.text(TodoDetailUiCopy.taskNotFound), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      for (final staleText in [
        old.title,
        old.notes,
        'Old unsaved title draft',
        'Old unsaved notes draft',
        next.title,
        next.notes,
      ]) {
        expect(find.text(staleText), findsNothing, reason: staleText);
      }

      // Callbacks retained from the old account's rendered list must stop
      // before reaching TodoProvider once that route's origin is stale.
      final recordedCallCount = provider.subtaskCalls.length;
      retainedToggle(false);
      retainedReorder(0, 1);
      await tester.pump();
      expect(provider.subtaskCalls, hasLength(recordedCallCount));
      expect(provider.todos.single.title, next.title);
      expect(provider.todos.single.subtasks.single.id, 'new-child');

      // The stale route stays navigable even though the editor was dirty.
      await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(TodoDetailScreen), findsNothing);
      expect(find.text('home-root'), findsOneWidget);

      // A new detail opened under the current account origin remains writable.
      await tester.tap(find.text('open-detail'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Saved new title');
      await tester.enterText(find.byType(TextField).at(1), 'Saved new notes');
      await tester.pump();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
      await tester.pumpAndSettle();

      expect(provider.todos.single.title, 'Saved new title');
      expect(provider.todos.single.notes, 'Saved new notes');
      expect(I18n.current, AppLocale.en);
      expect(prefs.getString('duoyi_locale_v1'), 'en');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'TodayDetailRouter captures origin before push and rejects a switch before the first route frame',
    (tester) async {
      final provider = TodoProvider();
      final old = TodoItem(
        id: 'router-colliding-task',
        title: 'Router old title',
        notes: 'Router old notes',
      );
      await provider.addTodo(old);
      final oldOrigin = AccountLocalDataCleaner.accountDataGeneration;
      final prefs = await SharedPreferences.getInstance();
      final next = TodoItem(
        id: old.id,
        title: 'Router new title',
        notes: 'Router new notes',
      );
      final observer = _SwitchAccountOnPushObserver(
        provider: provider,
        preferences: prefs,
        next: next,
      );
      final themeProvider = ThemeProvider();
      _registerCleanup(tester, [provider, themeProvider]);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TodoProvider>.value(value: provider),
            ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ],
          child: MaterialApp(
            navigatorObservers: [observer],
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    key: const ValueKey('open-via-today-detail-router'),
                    onPressed: () => unawaited(
                      TodayDetailRouter.open(
                        context,
                        TodaySectionKind.todos,
                        id: old.id,
                      ),
                    ),
                    child: const Text('open-router-detail'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Invoke the production router directly. Its NavigatorObserver callback
      // runs after route construction/push; defer pumping so the account switch
      // and replacement storage finish before the detail's first build.
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('open-via-today-detail-router')),
          )
          .onPressed!
          .call();
      await observer.detailRoutePushed.future;
      expect(AccountLocalDataCleaner.accountDataGeneration, isNot(oldOrigin));
      await observer.replacementWrite!;
      await provider.loadFromStorage();
      expect(provider.todos.single.title, next.title);
      expect(provider.todos.single.notes, next.notes);

      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(TodoDetailScreen), findsOneWidget);
      expect(find.text(TodoDetailUiCopy.taskNotFound), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      for (final staleText in [old.title, old.notes, next.title, next.notes]) {
        expect(find.text(staleText), findsNothing, reason: staleText);
      }
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(TodoDetailScreen), findsNothing);
    },
  );
}

Widget _directDetailApp(TodoProvider provider, String todoId) =>
    ChangeNotifierProvider<TodoProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('home-root'),
                  TextButton(
                    onPressed: () {
                      final openingGeneration =
                          AccountLocalDataCleaner.accountDataGeneration;
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TodoDetailScreen(
                            todoId: todoId,
                            accountGeneration: openingGeneration,
                          ),
                        ),
                      );
                    },
                    child: const Text('open-detail'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

void _registerCleanup(WidgetTester tester, Iterable<ChangeNotifier> providers) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (final provider in providers) {
      provider.dispose();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('todos');
  });
}

class _RecordedSubtaskCall {
  final String operation;
  final int? expectedAccountDataGeneration;

  const _RecordedSubtaskCall(
    this.operation,
    this.expectedAccountDataGeneration,
  );
}

class _RecordingTodoProvider extends TodoProvider {
  final List<_RecordedSubtaskCall> subtaskCalls = [];

  @override
  Future<void> toggleSubtask(
    String todoId,
    String subtaskId, {
    int? expectedAccountDataGeneration,
  }) async {
    subtaskCalls.add(
      _RecordedSubtaskCall('toggle', expectedAccountDataGeneration),
    );
  }

  @override
  Future<void> reorderSubtasks(
    String todoId,
    List<String> orderedIds, {
    int? expectedAccountDataGeneration,
  }) async {
    subtaskCalls.add(
      _RecordedSubtaskCall('reorder', expectedAccountDataGeneration),
    );
  }
}

class _SwitchAccountOnPushObserver extends NavigatorObserver {
  final TodoProvider provider;
  final SharedPreferences preferences;
  final TodoItem next;
  final Completer<void> detailRoutePushed = Completer<void>();
  Future<bool>? replacementWrite;

  _SwitchAccountOnPushObserver({
    required this.provider,
    required this.preferences,
    required this.next,
  });

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null || detailRoutePushed.isCompleted) return;
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    provider.resetLocalState();
    replacementWrite = preferences.setString(
      'todos',
      jsonEncode([next.toJson()]),
    );
    detailRoutePushed.complete();
  }
}
