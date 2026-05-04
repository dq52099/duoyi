import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/todo.dart';

class TodoProvider extends ChangeNotifier {
  List<TodoItem> _todos = [];

  List<TodoItem> get todos => _todos;

  void _notify() {
    _todos.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    notifyListeners();
  }

  // --- Queries ---

  List<TodoItem> getTodosForDate(DateTime date) {
    final key = _dateKey(date);
    return _todos.where((t) => _dateKey(t.date) == key).toList();
  }

  List<TodoItem> get activeTodos => _todos.where((t) => !t.isCompleted).toList();
  List<TodoItem> get completedTodos => _todos.where((t) => t.isCompleted).toList();

  Map<EisenhowerQuadrant, List<TodoItem>> get quadrantGroups {
    final map = <EisenhowerQuadrant, List<TodoItem>>{};
    for (final q in EisenhowerQuadrant.values) {
      map[q] = activeTodos.where((t) => t.quadrant == q).toList();
    }
    return map;
  }

  List<TodoItem> getQuadrantTodos(EisenhowerQuadrant q) =>
      activeTodos.where((t) => t.quadrant == q).toList();

  Map<String, List<TodoItem>> get listGroupedTodos {
    final map = <String, List<TodoItem>>{};
    for (final t in activeTodos) {
      final key = t.listGroupName ?? '未分组';
      map.putIfAbsent(key, () => []).add(t);
    }
    return map;
  }

  Set<String> get listGroupNames {
    final names = <String>{};
    for (final t in todos) {
      if (t.listGroupName != null && t.listGroupName!.isNotEmpty) {
        names.add(t.listGroupName!);
      }
    }
    return names;
  }

  // --- Persistence ---

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('todos');
    if (data != null) {
      final list = json.decode(data) as List;
      _todos = list.map((e) => TodoItem.fromJson(e)).toList();
      _notify();
    }
  }

  Future<void> _saveToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final data = json.encode(_todos.map((e) => e.toJson()).toList());
    await prefs.setString('todos', data);
  }

  // --- CRUD ---

  Future<void> addTodo(TodoItem todo) async {
    _todos.add(todo);
    _notify();
    await _saveToStorage();
  }

  Future<void> updateTodo(String id, TodoItem updated) async {
    final idx = _todos.indexWhere((t) => t.id == id);
    if (idx != -1) {
      _todos[idx] = updated;
      _notify();
      await _saveToStorage();
    }
  }

  Future<void> toggleTodo(String id) async {
    final idx = _todos.indexWhere((t) => t.id == id);
    if (idx != -1) {
      _todos[idx] = _todos[idx].copyWith(isCompleted: !_todos[idx].isCompleted);
      _notify();
      await _saveToStorage();
    }
  }

  Future<void> deleteTodo(String id) async {
    _todos.removeWhere((t) => t.id == id);
    _notify();
    await _saveToStorage();
  }

  // --- Subtask operations ---

  Future<void> addSubtask(String todoId, String title) async {
    final idx = _todos.indexWhere((t) => t.id == todoId);
    if (idx != -1) {
      final newSubtasks = List<Subtask>.from(_todos[idx].subtasks)
        ..add(Subtask(title: title, sortOrder: _todos[idx].subtasks.length));
      _todos[idx] = _todos[idx].copyWith(subtasks: newSubtasks);
      _notify();
      await _saveToStorage();
    }
  }

  Future<void> toggleSubtask(String todoId, String subtaskId) async {
    final idx = _todos.indexWhere((t) => t.id == todoId);
    if (idx != -1) {
      final sIdx = _todos[idx].subtasks.indexWhere((s) => s.id == subtaskId);
      if (sIdx != -1) {
        _todos[idx].subtasks[sIdx].isCompleted = !_todos[idx].subtasks[sIdx].isCompleted;
        _notify();
        await _saveToStorage();
      }
    }
  }

  Future<void> deleteSubtask(String todoId, String subtaskId) async {
    final idx = _todos.indexWhere((t) => t.id == todoId);
    if (idx != -1) {
      _todos[idx].subtasks.removeWhere((s) => s.id == subtaskId);
      _notify();
      await _saveToStorage();
    }
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}