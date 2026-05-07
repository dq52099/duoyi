import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/todo.dart';

class TodoProvider extends ChangeNotifier {
  List<TodoItem> _todos = [];

  List<TodoItem> get todos => _todos;

  void _notify() {
    _todos.sort((a, b) {
      if (a.sortOrder != b.sortOrder) {
        return a.sortOrder.compareTo(b.sortOrder);
      }
      // 次序相同时按优先级倒序，再按创建时间
      final p = b.priority.rank.compareTo(a.priority.rank);
      if (p != 0) return p;
      return a.createdAt.compareTo(b.createdAt);
    });
    notifyListeners();
  }

  // --- Queries ---

  List<TodoItem> getTodosForDate(DateTime date) {
    final key = _dateKey(date);
    return _todos.where((t) => _dateKey(t.date) == key).toList();
  }

  List<TodoItem> get activeTodos =>
      _todos.where((t) => !t.isCompleted).toList();
  List<TodoItem> get completedTodos =>
      _todos.where((t) => t.isCompleted).toList();

  List<TodoItem> get overdueTodos =>
      _todos.where((t) => t.isOverdue).toList();

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

  Set<String> get allTags {
    final tags = <String>{};
    for (final t in _todos) {
      tags.addAll(t.tags);
    }
    return tags;
  }

  List<TodoItem> byTag(String tag) =>
      _todos.where((t) => t.tags.contains(tag)).toList();

  // --- Persistence ---

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('todos');
    if (data != null) {
      final list = json.decode(data) as List;
      _todos = list.map((e) => TodoItem.fromJson(e)).toList();
    }
    _notify();
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

  /// 切换完成状态。若任务带有重复规则并且本次变为已完成，自动克隆一条下次的任务。
  Future<void> toggleTodo(String id) async {
    final idx = _todos.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    final prev = _todos[idx];
    final nowCompleted = !prev.isCompleted;
    _todos[idx] = prev.copyWith(
      isCompleted: nowCompleted,
      completedAt: nowCompleted ? DateTime.now() : null,
    );

    if (nowCompleted && prev.recurrence.isActive) {
      final anchor = prev.dueDate ?? prev.date;
      final next = prev.recurrence.nextAfter(anchor);
      if (next != null) {
        final delta = prev.dueDate == null
            ? Duration.zero
            : prev.dueDate!.difference(prev.date);
        _todos.add(
          TodoItem(
            title: prev.title,
            notes: prev.notes,
            quadrant: prev.quadrant,
            priority: prev.priority,
            listGroupId: prev.listGroupId,
            listGroupName: prev.listGroupName,
            tags: [...prev.tags],
            dueDate: prev.dueDate == null ? null : next.add(delta),
            date: next,
            hasReminder: prev.hasReminder,
            reminderAt: null,
            subtasks: prev.subtasks
                .map((s) => Subtask(title: s.title, sortOrder: s.sortOrder))
                .toList(),
            recurrence: prev.recurrence,
            sortOrder: prev.sortOrder,
          ),
        );
      }
    }

    _notify();
    await _saveToStorage();
  }

  Future<void> deleteTodo(String id) async {
    _todos.removeWhere((t) => t.id == id);
    _notify();
    await _saveToStorage();
  }

  Future<void> reorder(List<String> orderedIds) async {
    final map = {for (final t in _todos) t.id: t};
    final newList = <TodoItem>[];
    for (int i = 0; i < orderedIds.length; i++) {
      final t = map[orderedIds[i]];
      if (t != null) {
        newList.add(t.copyWith(sortOrder: i));
        map.remove(orderedIds[i]);
      }
    }
    newList.addAll(map.values);
    _todos = newList;
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
        _todos[idx].subtasks[sIdx].isCompleted =
            !_todos[idx].subtasks[sIdx].isCompleted;
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

  Future<void> reorderSubtasks(String todoId, List<String> orderedIds) async {
    final idx = _todos.indexWhere((t) => t.id == todoId);
    if (idx == -1) return;
    final map = {for (final s in _todos[idx].subtasks) s.id: s};
    final newList = <Subtask>[];
    for (int i = 0; i < orderedIds.length; i++) {
      final s = map[orderedIds[i]];
      if (s != null) {
        s.sortOrder = i;
        newList.add(s);
        map.remove(orderedIds[i]);
      }
    }
    newList.addAll(map.values);
    _todos[idx] = _todos[idx].copyWith(subtasks: newList);
    _notify();
    await _saveToStorage();
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
