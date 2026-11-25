import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/todo_kanban.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(AccountPreferenceWrites.drain);

  for (final action in ['toggle', 'batch', 'edit', 'kanban', 'child']) {
    test(
      'archived todo reopened by $action becomes visible and persists',
      () async {
        final provider = TodoProvider();
        addTearDown(provider.dispose);
        await provider.addTodo(
          TodoItem(
            id: 'archived-reopen',
            title: 'Synthetic archived completion',
            quadrant: EisenhowerQuadrant.urgentImportant,
            isCompleted: true,
            completedAt: DateTime(2026, 10, 1),
            isArchivedAfterRollover: true,
            kanbanColumnId: defaultKanbanDoneColumnId,
            autoToggleByChildren: true,
            subtasks: [
              Subtask(id: 'child', title: 'Synthetic child', isCompleted: true),
            ],
          ),
        );
        expect(provider.visibleListTodos, isEmpty);
        final old = provider.todos.single;
        switch (action) {
          case 'toggle':
            await provider.toggleTodo(old.id);
          case 'batch':
            expect(await provider.reopenTodos([old.id]), 1);
          case 'edit':
            expect(
              await provider.updateTodo(
                old.id,
                old.copyWith(isCompleted: false, completedAt: null),
              ),
              isTrue,
            );
          case 'kanban':
            expect(
              await provider.updateTodosKanbanColumn([
                old.id,
              ], defaultKanbanPendingColumnId),
              1,
            );
          case 'child':
            await provider.toggleSubtask(old.id, 'child');
        }
        final current = provider.todos.single;
        expect(current.isCompleted, isFalse);
        expect(current.isArchivedAfterRollover, isFalse);
        expect(provider.visibleListTodos.map((todo) => todo.id), [old.id]);
        await AccountPreferenceWrites.drain();
        final storage = await SharedPreferences.getInstance();
        final stored =
            (jsonDecode(storage.getString('todos')!) as List).single
                as Map<String, dynamic>;
        final restored = TodoItem.fromJson(stored);
        expect(restored.isCompleted, isFalse);
        expect(restored.isArchivedAfterRollover, isFalse);
      },
    );
  }
}
