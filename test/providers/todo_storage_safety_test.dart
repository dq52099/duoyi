import 'dart:convert';

import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'TodoProvider skips corrupt persisted records and rewrites storage',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'todos': '[123, "bad-record"]',
      });

      final provider = TodoProvider();
      await provider.loadFromStorage();

      expect(provider.todos, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('todos'), '[]');
      expect(
        prefs.getKeys().where((key) => key.startsWith('todos_corrupt_backup_')),
        isNotEmpty,
      );
    },
  );

  test('TodoProvider hydrates storage before first write', () async {
    final existing = TodoItem(
      id: 'existing',
      title: '旧待办',
      date: DateTime(2026, 6, 5),
      createdAt: DateTime(2026, 6, 5, 8),
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'todos': jsonEncode([existing.toJson()]),
    });

    final provider = TodoProvider();
    await provider.addTodo(
      TodoItem(
        id: 'quick',
        title: '快捷待办',
        date: DateTime(2026, 6, 5),
        createdAt: DateTime(2026, 6, 5, 9),
      ),
    );

    expect(
      provider.todos.map((todo) => todo.id),
      containsAll(['existing', 'quick']),
    );
    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString('todos')!) as List<dynamic>;
    expect(
      stored
          .cast<Map<dynamic, dynamic>>()
          .map((raw) => raw['id'] as String)
          .toSet(),
      {'existing', 'quick'},
    );
  });
}
