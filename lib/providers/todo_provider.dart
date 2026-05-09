import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/completion_visibility_policy.dart';
import '../models/todo.dart';
import '../services/reminder_scheduler.dart';

class TodoProvider extends ChangeNotifier {
  List<TodoItem> _todos = [];

  /// 可选的 [ReminderScheduler] 引用，由 `main.dart` 在构造完整对象图后注入。
  ///
  /// 设计上允许 `null`：TodoProvider 的持久化路径**不**强依赖调度器，
  /// 只有在 [postponeOverdue] 这种显式 hook 里才会尝试转发给调度器，做一次
  /// 额外的重同步。常规写路径依然由 `main.dart` 的 `addListener(resyncReminders)`
  /// 覆盖。
  ///
  /// TODO(task-14): 调度器 API 稳定后把 dynamic 兜底调用替换为直接
  /// `_scheduler!.syncTodos(_todos)` 调用（参见 GoalProvider 4.3 的相同模式）。
  ReminderScheduler? _scheduler;

  /// 注入或解绑调度器；传 `null` 即解绑。
  // ignore: use_setters_to_change_properties
  set scheduler(ReminderScheduler? s) {
    _scheduler = s;
  }

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

  /// "今日"视图可见的 todos（不包含归档项，但保留当日完成项）。
  ///
  /// 与 [activeTodos] 不同：后者是"未完成"过滤，跨日通用；这里严格对齐
  /// `CompletionVisibilityPolicy.shouldShowInToday`，只返回
  /// `t.date` 在今日、且未被跨日归档的条目。
  /// 供 Today 列表 / Today Widget 复用，避免各处重复判断。
  List<TodoItem> visibleTodayTodos(DateTime now) =>
      _todos
          .where((t) => CompletionVisibilityPolicy.shouldShowInToday(t, now))
          .toList();

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
    if (idx == -1) return;
    final sIdx = _todos[idx].subtasks.indexWhere((s) => s.id == subtaskId);
    if (sIdx == -1) return;
    _todos[idx].subtasks[sIdx].isCompleted =
        !_todos[idx].subtasks[sIdx].isCompleted;
    await recomputeParent(todoId);
  }

  /// 依据子任务聚合状态重算父任务完成态（P6/P7 不变式）。
  ///
  /// - 若 `subtasks.isEmpty`：视为 no-op，不触碰父任务也不写入存储。
  /// - 若 `autoToggleByChildren = true`：
  ///   - 全部子任务完成且父任务未完成 → `isCompleted = true` 且 `completedAt = now`
  ///   - 存在未完成子任务且父任务已完成 → `isCompleted = false` 且 `completedAt = null`
  /// - 若 `autoToggleByChildren = false`：不触碰父任务完成态，仅持久化当前子任务变动。
  Future<void> recomputeParent(String todoId) async {
    final idx = _todos.indexWhere((t) => t.id == todoId);
    if (idx == -1) return;
    final t = _todos[idx];
    if (t.subtasks.isEmpty) return;

    if (t.autoToggleByChildren) {
      final allDone = t.subtasks.every((s) => s.isCompleted);
      if (allDone && !t.isCompleted) {
        t.isCompleted = true;
        t.completedAt = DateTime.now();
      } else if (!allDone && t.isCompleted) {
        t.isCompleted = false;
        t.completedAt = null;
      }
    }

    _notify();
    await _saveToStorage();
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

  // --- Daily rollover ---

  /// 归档"昨天及更早"的已完成 todos（P5 / Requirement 3.4, 3.5）。
  ///
  /// 对每个满足 `t.isCompleted ∧ t.completedAt != null ∧
  /// dateOnly(completedAt) < todayDay ∧ !t.isArchivedAfterRollover` 的任务，
  /// 置 `isArchivedAfterRollover = true` 并刷新 `updatedAt`。
  ///
  /// 幂等性：若没有任务满足条件（例如二次调用），方法不会写入存储也不会通知
  /// 监听器。`todayDay` 会先裁剪到本地"日"起点，避免在调用方未对齐时误判。
  ///
  /// 注意：本方法只处理"已完成 → 归档"的迁移；对"昨日未完成且已过期"的任务
  /// 由 [postponeOverdue] 负责顺延。两者在 `CompletionVisibilityPolicy
  /// .runDailyRollover` 中组合使用。
  Future<void> archivePastCompletions(DateTime todayDay) async {
    final todayStart = DateTime(todayDay.year, todayDay.month, todayDay.day);
    var mutated = false;

    for (final t in _todos) {
      if (!t.isCompleted) continue;
      if (t.isArchivedAfterRollover) continue;
      final completedAt = t.completedAt;
      if (completedAt == null) continue;

      final completedDay =
          DateTime(completedAt.year, completedAt.month, completedAt.day);
      if (!completedDay.isBefore(todayStart)) continue;

      t.isArchivedAfterRollover = true;
      t.updatedAt = DateTime.now();
      mutated = true;
    }

    if (!mutated) return;

    await _saveToStorage();
    _notify();
  }

  /// 把所有"未完成且已过期"的 todo 顺延到 [today] 同一时刻。
  ///
  /// 对每个满足 `!isCompleted ∧ dueDate != null ∧ dueDay < todayDay` 的任务：
  /// - 生成新的 `dueDate = todayDay + (prev.hour, prev.minute)`；
  /// - 在 `postponeHistory` 追加一条 `reason = 'auto_daily_rollover'` 记录；
  /// - 若任务启用了提醒（新版 `reminder.enabled` 或遗留 `hasReminder`），
  ///   同步把遗留字段 `reminderAt` 镜像到新的 `dueDate`，保证既有
  ///   `ReminderScheduler.syncTodos` 能按新时间重新调度；
  ///   新版 `ReminderConfig` 只含 `hour / minute`，不持有日期，这里不需要改动。
  ///
  /// 幂等性（P13）：若所有任务已满足 `dueDay ≥ todayDay`，二次调用不会追加任何
  /// 新的 `PostponeRecord`，也不会写入存储、不会通知监听器。
  ///
  /// [today] 作为参数注入，便于测试；内部会先取其日部分做"本地 00:00"对齐。
  Future<void> postponeOverdue(DateTime today) async {
    final todayDay = DateTime(today.year, today.month, today.day);
    var mutated = false;

    for (final t in _todos) {
      if (t.isCompleted) continue;
      final prevDue = t.dueDate;
      if (prevDue == null) continue;

      final dueDay = DateTime(prevDue.year, prevDue.month, prevDue.day);
      // 未到期：dueDay == todayDay 或更晚。
      if (!dueDay.isBefore(todayDay)) continue;

      final newDue = DateTime(
        todayDay.year,
        todayDay.month,
        todayDay.day,
        prevDue.hour,
        prevDue.minute,
      );

      t.postponeHistory.add(
        PostponeRecord(
          from: prevDue,
          to: newDue,
          reason: 'auto_daily_rollover',
          at: DateTime.now(),
        ),
      );
      t.dueDate = newDue;
      t.updatedAt = DateTime.now();

      // 同步遗留的 reminderAt 镜像：新版 ReminderConfig 只记录 hour/minute，
      // 但 ReminderScheduler 仍会优先读 `reminderAt ?? dueDate`，因此把镜像
      // 保持在最新的 dueDate 上，触发下一次 `syncTodos` 重新调度。
      // ignore: deprecated_member_use_from_same_package
      final reminderEnabled = t.reminder.enabled || t.hasReminder;
      if (reminderEnabled) {
        // ignore: deprecated_member_use_from_same_package
        t.reminderAt = newDue;
      }

      mutated = true;
    }

    if (!mutated) return;

    await _saveToStorage();
    _notify();

    // TODO(task-14): ReminderScheduler.syncTodos 签名稳定后改为直接调用。
    final scheduler = _scheduler;
    if (scheduler != null) {
      try {
        // ignore: avoid_dynamic_calls
        final result = (scheduler as dynamic).syncTodos(List.of(_todos));
        if (result is Future) await result;
      } on NoSuchMethodError {
        debugPrint(
          '[TodoProvider] postponeOverdue: scheduler.syncTodos not yet '
          'implemented; falling back to no-op. TODO(task-14)',
        );
      } catch (e, st) {
        debugPrint('[TodoProvider] postponeOverdue scheduler sync failed: $e\n$st');
      }
    }
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
