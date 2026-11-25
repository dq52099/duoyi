import 'dart:async';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/widgets/todo_completion_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });

  testWidgets(
    'rejected completion shows live language feedback without an unhandled error',
    (tester) async {
      final gate = Completer<int>();
      final todos = _Todos(gate: gate);
      await _mount(tester, todos, _Audit(), () => true);
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('跳过'));
      await tester.pumpAndSettle();
      gate.completeError(StateError('rejected store'));
      await tester.pumpAndSettle();
      expect(find.text('未能保存完成记录，请检查任务状态后重试'), findsOneWidget);
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      expect(
        find.text(
          'Could not save the completion record. Check the task and try again.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmation and duration callbacks recheck access before writes',
    (tester) async {
      final todos = _Todos();
      final audit = _Audit();
      var allowed = true;
      await _mount(tester, todos, audit, () => allowed);
      final confirm = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '继续'))
          .onPressed!;
      allowed = false;
      confirm();
      await tester.pumpAndSettle();
      expect(find.text('记录耗时'), findsNothing);
      expect(todos.calls, 0);
      allowed = true;
      confirm();
      await tester.pumpAndSettle();
      final skip = tester
          .widget<TextButton>(find.widgetWithText(TextButton, '跳过'))
          .onPressed!;
      allowed = false;
      skip();
      await tester.pumpAndSettle();
      expect(todos.calls, 0);
      expect(find.text('记录耗时'), findsOneWidget);
      allowed = true;
      skip();
      await tester.pumpAndSettle();
      expect(todos.calls, 1);
      expect(audit.calls, 1);
    },
  );

  testWidgets(
    'accepted completion finishes recording while locking suppresses feedback',
    (tester) async {
      final gate = Completer<int>();
      final todos = _Todos(gate: gate);
      final audit = _Audit();
      var allowed = true;
      var started = 0;
      await _mount(
        tester,
        todos,
        audit,
        () => allowed,
        onStarted: () => started++,
      );
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('跳过'));
      await tester.pumpAndSettle();
      expect(todos.calls, 1);
      expect(started, 1);
      allowed = false;
      gate.complete(1);
      await tester.pumpAndSettle();
      expect(audit.calls, 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _mount(
  WidgetTester tester,
  _Todos todos,
  _Audit audit,
  bool Function() access, {
  VoidCallback? onStarted,
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
            builder: (context) => TextButton(
              onPressed: () => completeTodoWithOptionalTimeRecord(
                context,
                todos.todo,
                isAccessAvailable: access,
                isFeedbackAvailable: access,
                onActionStarted: onStarted,
              ),
              child: const Text('launch'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('launch'));
  await tester.pumpAndSettle();
}

class _Todos extends TodoProvider {
  _Todos({this.gate});
  final Completer<int>? gate;
  final todo = TodoItem(id: 'access-todo', title: '保留任务');
  int calls = 0;
  @override
  List<TodoItem> get todos => [todo];
  @override
  Future<int> completeTodos(
    Iterable<String> ids, {
    bool recordCompletionTime = true,
  }) async {
    calls++;
    return gate == null ? 1 : gate!.future;
  }
}

class _Audit extends TimeAuditProvider {
  int calls = 0;
  @override
  Future<void> recordTodoCompletion(
    TodoItem todo, {
    DateTime? completedAt,
  }) async {
    calls++;
  }
}
