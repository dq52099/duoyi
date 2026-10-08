import 'dart:async';
import 'dart:convert';

import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/widget_quick_todo_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('guest quick todo is persisted by the original provider', () async {
    final todo = TodoItem(
      id: 'guest-quick-todo',
      title: 'Guest task',
      date: DateTime(2026, 10, 8),
      createdAt: DateTime(2026, 10, 8, 9),
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final provider = TodoProvider();
    addTearDown(provider.dispose);
    var createCalls = 0;
    final messages = <String>[];

    await runWidgetQuickTodoAction(
      isCallerAvailable: () => true,
      preflight: (_) async => true,
      create: () async {
        createCalls++;
        await provider.addTodo(todo, waitForReminderSync: false);
        return 'saved';
      },
      feedback: (message, isCurrent) {
        expect(isCurrent(), isTrue);
        messages.add(message);
      },
      failureMessage: 'create failed',
    );

    expect(createCalls, 1);
    expect(messages, ['saved']);
    expect(todo.hasReminder, isFalse);
    expect(provider.todos, hasLength(1));
    expect(provider.todos.single, same(todo));

    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('todos')!), [todo.toJson()]);
  });

  test('quick todo preflight cannot write into the next account', () async {
    final draft = TodoItem(
      id: 'account-a-widget-draft',
      title: 'Unsaved widget draft from A',
      date: DateTime(2026, 10, 8),
      createdAt: DateTime(2026, 10, 8, 9),
    );
    final accountATodo = TodoItem(
      id: 'account-a-todo',
      title: 'Account A task',
      date: DateTime(2026, 10, 7),
      createdAt: DateTime(2026, 10, 7, 9),
    );
    final accountBTodos = <TodoItem>[
      TodoItem(
        id: 'account-b-sentinel-1',
        title: 'Account B sentinel one',
        date: DateTime(2026, 10, 8),
        createdAt: DateTime(2026, 10, 8, 8),
      ),
      TodoItem(
        id: 'account-b-sentinel-2',
        title: 'Account B sentinel two',
        date: DateTime(2026, 10, 8),
        createdAt: DateTime(2026, 10, 8, 10),
      ),
    ];
    SharedPreferences.setMockInitialValues(<String, Object>{
      'todos': jsonEncode([accountATodo.toJson()]),
    });

    final provider = TodoProvider();
    addTearDown(provider.dispose);
    await provider.loadFromStorage();
    expect(provider.todos.map((todo) => todo.id), [accountATodo.id]);

    final enteredPreflight = Completer<void>();
    final releasePreflight = Completer<bool>();
    var createCalls = 0;
    final messages = <String>[];
    final pending = runWidgetQuickTodoAction(
      isCallerAvailable: () => true,
      preflight: (_) {
        enteredPreflight.complete();
        return releasePreflight.future;
      },
      create: () async {
        createCalls++;
        await provider.addTodo(draft, waitForReminderSync: false);
        return 'saved';
      },
      feedback: (message, _) => messages.add(message),
      failureMessage: 'create failed',
    );

    await enteredPreflight.future;
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    provider.resetLocalState();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'todos',
      jsonEncode(accountBTodos.map((todo) => todo.toJson()).toList()),
    );
    await provider.loadFromStorage(force: true);

    releasePreflight.complete(true);
    await pending;

    final expectedIds = accountBTodos.map((todo) => todo.id).toSet();
    expect(createCalls, 0);
    expect(messages, isEmpty);
    expect(provider.todos.map((todo) => todo.id).toSet(), expectedIds);
    expect(
      provider.todos.map((todo) => todo.id),
      isNot(contains(accountATodo.id)),
    );
    expect(provider.todos.map((todo) => todo.id), isNot(contains(draft.id)));
    expect(
      jsonDecode(prefs.getString('todos')!) as List<dynamic>,
      accountBTodos.map((todo) => todo.toJson()).toList(),
    );
  });
}
