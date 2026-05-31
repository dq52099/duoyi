import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/completion_visibility_policy.dart';
import '../core/domain_event_bus.dart';
import '../core/todo_kanban.dart';
import '../models/time_entry.dart';
import '../models/todo.dart';
import '../services/reminder_scheduler.dart';
import 'cloud_sync_provider.dart';
import 'time_audit_provider.dart';

class TodoImportSummary {
  final int inserted;
  final int skippedDuplicates;

  const TodoImportSummary({
    required this.inserted,
    required this.skippedDuplicates,
  });
}

class TodoProvider extends ChangeNotifier {
  List<TodoItem> _todos = [];

  /// 可选的 [ReminderScheduler] 引用，由 `main.dart` 在构造完整对象图后注入。
  ///
  /// 设计上允许 `null`：TodoProvider 的持久化路径**不**强依赖调度器。
  /// 注入后，创建、编辑、完成、恢复、删除和顺延会主动重同步，确保系统
  /// 队列及时注册或取消；`main.dart` 的监听重同步仍作为兜底。
  ReminderScheduler? _scheduler;
  TimeAuditProvider? _timeAudit;
  String? _lastReminderSyncIssue;
  DateTime? _lastReminderSyncAttemptAt;
  DateTime? _lastReminderSyncSucceededAt;

  /// 注入或解绑调度器；传 `null` 即解绑。
  // ignore: use_setters_to_change_properties
  set scheduler(ReminderScheduler? s) {
    _scheduler = s;
    if (s != null && _lastReminderSyncIssue == 'reminder_scheduler_missing') {
      _lastReminderSyncIssue = null;
    }
  }

  // ignore: use_setters_to_change_properties
  set timeAudit(TimeAuditProvider? provider) {
    _timeAudit = provider;
  }

  List<TodoItem> get todos => _todos;
  String? get lastReminderSyncIssue => _lastReminderSyncIssue;
  DateTime? get lastReminderSyncAttemptAt => _lastReminderSyncAttemptAt;
  DateTime? get lastReminderSyncSucceededAt => _lastReminderSyncSucceededAt;

  int _compareTodos(TodoItem a, TodoItem b) {
    if (a.sortOrder != b.sortOrder) {
      return a.sortOrder.compareTo(b.sortOrder);
    }
    // 次序相同时按优先级倒序，再按创建时间
    final p = b.priority.rank.compareTo(a.priority.rank);
    if (p != 0) return p;
    return a.createdAt.compareTo(b.createdAt);
  }

  void _notify() {
    _todos.sort(_compareTodos);
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
  List<TodoItem> visibleTodayTodos(DateTime now) => _todos
      .where((t) => CompletionVisibilityPolicy.shouldShowInToday(t, now))
      .toList();

  List<TodoItem> get activeTodos =>
      _todos.where((t) => !t.isCompleted).toList();
  List<TodoItem> get visibleListTodos => _todos
      .where(
        (t) =>
            CompletionVisibilityPolicy.visualState(t) !=
            TodoVisualState.archived,
      )
      .toList();
  List<TodoItem> get completedTodos =>
      _todos.where((t) => t.isCompleted).toList();

  List<TodoItem> get overdueTodos => _todos.where((t) => t.isOverdue).toList();

  Map<EisenhowerQuadrant, List<TodoItem>> get quadrantGroups {
    final map = <EisenhowerQuadrant, List<TodoItem>>{};
    for (final q in EisenhowerQuadrant.values) {
      map[q] = visibleListTodos.where((t) => t.quadrant == q).toList();
    }
    return map;
  }

  List<TodoItem> getQuadrantTodos(EisenhowerQuadrant q) =>
      visibleListTodos.where((t) => t.quadrant == q).toList();

  Map<String, List<TodoItem>> get listGroupedTodos {
    final map = <String, List<TodoItem>>{};
    for (final t in visibleListTodos) {
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

  String? workspaceForListGroup(String groupName) {
    final group = visibleListTodos.where(
      (todo) => (todo.listGroupName ?? '未分组') == groupName,
    );
    for (final todo in group) {
      if (todo.workspaceId != 'private' && todo.workspaceId.isNotEmpty) {
        return todo.workspaceId;
      }
    }
    return null;
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

  Future<void> _syncTodoRemindersNow() async {
    _lastReminderSyncAttemptAt = DateTime.now();
    final scheduler = _scheduler;
    if (scheduler == null) {
      _lastReminderSyncIssue = 'reminder_scheduler_missing';
      debugPrint('[TodoProvider] reminder sync skipped: scheduler missing');
      return;
    }
    try {
      await scheduler.syncTodos(List.of(_todos));
      _lastReminderSyncIssue = null;
      _lastReminderSyncSucceededAt = DateTime.now();
    } catch (e, st) {
      _lastReminderSyncIssue = e.toString();
      debugPrint('[TodoProvider] reminder sync failed: $e\n$st');
    }
  }

  Future<void> addTodo(TodoItem todo) async {
    _todos.add(todo);
    DomainEventBus.instance.publish(
      DomainEvent(type: DomainEventType.todoCreated, objectId: todo.id),
    );
    await _saveToStorage();
    _notify();
    await _syncTodoRemindersNow();
  }

  Future<TodoImportSummary> importTodos(Iterable<TodoItem> imported) async {
    final incoming = imported.toList();
    if (incoming.isEmpty) {
      return const TodoImportSummary(inserted: 0, skippedDuplicates: 0);
    }

    final seen = _todos.map(_importDuplicateKey).toSet();
    final currentMaxSortOrder = _todos.isEmpty
        ? -1
        : _todos.map((todo) => todo.sortOrder).reduce((a, b) => a > b ? a : b);
    var nextSortOrder = currentMaxSortOrder + 1;
    var inserted = 0;
    var skippedDuplicates = 0;

    for (final todo in incoming) {
      final key = _importDuplicateKey(todo);
      if (seen.contains(key)) {
        skippedDuplicates++;
        continue;
      }
      seen.add(key);
      final next = todo.copyWith(sortOrder: nextSortOrder++);
      _todos.add(next);
      inserted++;
      DomainEventBus.instance.publish(
        DomainEvent(type: DomainEventType.todoCreated, objectId: next.id),
      );
    }

    if (inserted == 0) {
      return TodoImportSummary(
        inserted: 0,
        skippedDuplicates: skippedDuplicates,
      );
    }
    await _saveToStorage();
    _notify();
    await _syncTodoRemindersNow();
    return TodoImportSummary(
      inserted: inserted,
      skippedDuplicates: skippedDuplicates,
    );
  }

  Future<void> updateTodo(String id, TodoItem updated) async {
    final idx = _todos.indexWhere((t) => t.id == id);
    if (idx != -1) {
      final prev = _todos[idx];
      var next = updated.isCompleted && updated.completedAt == null
          ? updated.copyWith(completedAt: DateTime.now())
          : updated;
      if (!prev.isCompleted && next.isCompleted) {
        next = next.copyWith(kanbanColumnId: defaultKanbanDoneColumnId);
      } else if (prev.isCompleted &&
          !next.isCompleted &&
          next.kanbanColumnId == defaultKanbanDoneColumnId) {
        next = next.copyWith(kanbanColumnId: defaultKanbanPendingColumnId);
      }
      _todos[idx] = next;
      if (!prev.isCompleted && next.isCompleted) {
        DomainEventBus.instance.publish(
          DomainEvent(type: DomainEventType.todoCompleted, objectId: next.id),
        );
      }
      await _saveToStorage();
      _notify();
      await _syncTodoRemindersNow();
      if (next.isCompleted) {
        await _timeAudit?.recordTodoCompletion(
          next,
          completedAt: next.completedAt,
        );
      } else if (prev.isCompleted && !next.isCompleted) {
        await _timeAudit?.removeTodoCompletion(
          prev,
          completedAt: prev.completedAt,
        );
      }
    }
  }

  Future<int> completeTodos(
    Iterable<String> ids, {
    bool recordCompletionTime = true,
  }) async {
    final selected = ids.toSet();
    if (selected.isEmpty) return 0;

    final completed = <TodoItem>[];
    var changed = 0;
    for (var i = 0; i < _todos.length; i++) {
      final prev = _todos[i];
      if (!selected.contains(prev.id) || prev.isCompleted) continue;

      final next = prev.copyWith(
        isCompleted: true,
        completedAt: DateTime.now(),
        kanbanColumnId: defaultKanbanDoneColumnId,
      );
      _todos[i] = next;
      completed.add(next);
      changed++;
      DomainEventBus.instance.publish(
        DomainEvent(type: DomainEventType.todoCompleted, objectId: next.id),
      );

      if (prev.recurrence.isActive) {
        final recurring = _nextRecurringTodo(prev);
        if (recurring != null) _todos.add(recurring);
      }
    }

    if (changed == 0) return 0;
    await _saveToStorage();
    _notify();

    if (recordCompletionTime) {
      for (final todo in completed) {
        await _timeAudit?.recordTodoCompletion(
          todo,
          completedAt: todo.completedAt,
        );
      }
    }
    await _syncTodoRemindersNow();
    return changed;
  }

  Future<int> reopenTodos(Iterable<String> ids) async {
    final selected = ids.toSet();
    if (selected.isEmpty) return 0;

    final reopened = <TodoItem>[];
    var changed = 0;
    for (var i = 0; i < _todos.length; i++) {
      final prev = _todos[i];
      if (!selected.contains(prev.id) || !prev.isCompleted) continue;
      _todos[i] = prev.copyWith(
        isCompleted: false,
        completedAt: null,
        kanbanColumnId: prev.kanbanColumnId == defaultKanbanDoneColumnId
            ? defaultKanbanPendingColumnId
            : prev.kanbanColumnId,
      );
      reopened.add(prev);
      changed++;
    }

    if (changed == 0) return 0;
    await _saveToStorage();
    _notify();

    for (final todo in reopened) {
      await _timeAudit?.removeTodoCompletion(
        todo,
        completedAt: todo.completedAt,
      );
    }
    await _syncTodoRemindersNow();
    return changed;
  }

  /// 切换完成状态。若任务带有重复规则并且本次变为已完成，自动克隆一条下次的任务。
  ///
  /// [recordCompletionTime] 为 `true` 时，在完成状态变更后会自动写入时间足迹；
  /// 由 UI 层统一决定是否要先弹出"顺手记耗时"对话框，或改用自定义时长。
  Future<void> toggleTodo(String id, {bool recordCompletionTime = true}) async {
    final idx = _todos.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    final prev = _todos[idx];
    final nowCompleted = !prev.isCompleted;
    _todos[idx] = prev.copyWith(
      isCompleted: nowCompleted,
      completedAt: nowCompleted ? DateTime.now() : null,
      kanbanColumnId: nowCompleted
          ? defaultKanbanDoneColumnId
          : prev.kanbanColumnId == defaultKanbanDoneColumnId
          ? defaultKanbanPendingColumnId
          : prev.kanbanColumnId,
    );
    if (nowCompleted) {
      DomainEventBus.instance.publish(
        DomainEvent(type: DomainEventType.todoCompleted, objectId: prev.id),
      );
    }

    if (nowCompleted && prev.recurrence.isActive) {
      final recurring = _nextRecurringTodo(prev);
      if (recurring != null) _todos.add(recurring);
    }

    await _saveToStorage();
    _notify();
    if (nowCompleted && recordCompletionTime) {
      await _timeAudit?.recordTodoCompletion(
        _todos[idx],
        completedAt: _todos[idx].completedAt,
      );
    } else if (!nowCompleted) {
      await _timeAudit?.removeTodoCompletion(
        prev,
        completedAt: prev.completedAt,
      );
    }
    await _syncTodoRemindersNow();
  }

  Future<void> deleteTodo(String id) async {
    final idx = _todos.indexWhere((t) => t.id == id);
    if (idx == -1) return;

    final removed = _todos[idx];
    await CloudSyncProvider.recordDeletedItem('todos', removed.id);
    await _timeAudit?.deleteBySource(TimeEntrySource.todo, removed.id);
    _todos.removeAt(idx);
    await _saveToStorage();
    _notify();
    await _syncTodoRemindersNow();
  }

  Future<int> deleteTodos(Iterable<String> ids) async {
    final selected = ids.toSet();
    if (selected.isEmpty) return 0;
    final existing = _todos.where((t) => selected.contains(t.id)).toList();
    if (existing.isEmpty) return 0;

    await CloudSyncProvider.recordDeletedItems(
      'todos',
      existing.map((todo) => todo.id),
    );
    for (final todo in existing) {
      await _timeAudit?.deleteBySource(TimeEntrySource.todo, todo.id);
    }
    _todos.removeWhere((t) => selected.contains(t.id));
    await _saveToStorage();
    _notify();
    await _syncTodoRemindersNow();
    return existing.length;
  }

  Future<int> updateTodosQuadrant(
    Iterable<String> ids,
    EisenhowerQuadrant quadrant,
  ) async {
    final selected = ids.toSet();
    if (selected.isEmpty) return 0;
    var changed = 0;
    for (var i = 0; i < _todos.length; i++) {
      final todo = _todos[i];
      if (!selected.contains(todo.id) || todo.quadrant == quadrant) continue;
      _todos[i] = todo.copyWith(quadrant: quadrant);
      changed++;
    }
    if (changed == 0) return 0;
    await _saveToStorage();
    _notify();
    return changed;
  }

  Future<int> updateTodosPriority(
    Iterable<String> ids,
    TodoPriority priority,
  ) async {
    final selected = ids.toSet();
    if (selected.isEmpty) return 0;
    var changed = 0;
    for (var i = 0; i < _todos.length; i++) {
      final todo = _todos[i];
      if (!selected.contains(todo.id) || todo.priority == priority) continue;
      _todos[i] = todo.copyWith(priority: priority);
      changed++;
    }
    if (changed == 0) return 0;
    await _saveToStorage();
    _notify();
    return changed;
  }

  Future<int> updateTodosKanbanColumn(
    Iterable<String> ids,
    String columnId,
  ) async {
    final target = columnId.trim().isEmpty
        ? defaultKanbanPendingColumnId
        : columnId.trim();
    final selected = ids.toSet();
    if (selected.isEmpty) return 0;
    final completed = <TodoItem>[];
    final reopened = <TodoItem>[];
    var changed = 0;
    for (var i = 0; i < _todos.length; i++) {
      final todo = _todos[i];
      if (!selected.contains(todo.id) || todo.kanbanColumnId == target) {
        continue;
      }
      final next = todo.copyWith(
        kanbanColumnId: target,
        isCompleted: target == defaultKanbanDoneColumnId
            ? true
            : target != defaultKanbanDoneColumnId &&
                  todo.kanbanColumnId == defaultKanbanDoneColumnId
            ? false
            : todo.isCompleted,
        completedAt: target == defaultKanbanDoneColumnId && !todo.isCompleted
            ? DateTime.now()
            : target != defaultKanbanDoneColumnId &&
                  todo.kanbanColumnId == defaultKanbanDoneColumnId
            ? null
            : todo.completedAt,
      );
      _todos[i] = next;
      if (!todo.isCompleted && next.isCompleted) {
        completed.add(next);
        DomainEventBus.instance.publish(
          DomainEvent(type: DomainEventType.todoCompleted, objectId: next.id),
        );
        if (todo.recurrence.isActive) {
          final recurring = _nextRecurringTodo(todo);
          if (recurring != null) _todos.add(recurring);
        }
      } else if (todo.isCompleted && !next.isCompleted) {
        reopened.add(todo);
      }
      changed++;
    }
    if (changed == 0) return 0;
    await _saveToStorage();
    _notify();
    for (final todo in completed) {
      await _timeAudit?.recordTodoCompletion(
        todo,
        completedAt: todo.completedAt,
      );
    }
    for (final todo in reopened) {
      await _timeAudit?.removeTodoCompletion(
        todo,
        completedAt: todo.completedAt,
      );
    }
    await _syncTodoRemindersNow();
    return changed;
  }

  Future<bool> scheduleTodoForToday(String id, {DateTime? now}) async {
    final idx = _todos.indexWhere((t) => t.id == id);
    if (idx == -1) return false;
    final todo = _todos[idx];
    if (todo.isCompleted || todo.isArchivedAfterRollover) return false;

    final base = now ?? DateTime.now();
    final today = DateTime(base.year, base.month, base.day);
    final currentDay = DateTime(todo.date.year, todo.date.month, todo.date.day);
    if (currentDay == today && !todo.isArchivedAfterRollover) return false;

    _todos[idx] = todo.copyWith(date: today, isArchivedAfterRollover: false);
    await _saveToStorage();
    _notify();
    await _syncTodoRemindersNow();
    return true;
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
    await _saveToStorage();
    _notify();
  }

  Future<int> reorderVisibleTodos(List<String> orderedIds) async {
    final ordered = orderedIds.toList(growable: false);
    if (ordered.length < 2) return 0;
    final orderedSet = ordered.toSet();
    if (orderedSet.length != ordered.length) return 0;

    final byId = {for (final todo in _todos) todo.id: todo};
    if (!ordered.every(byId.containsKey)) return 0;

    final sorted = [..._todos]..sort(_compareTodos);
    final slots = <int>[];
    for (var i = 0; i < sorted.length; i++) {
      if (orderedSet.contains(sorted[i].id)) slots.add(i);
    }
    if (slots.length != ordered.length) return 0;

    final current = [for (final slot in slots) sorted[slot].id];
    var changedOrder = false;
    for (var i = 0; i < current.length; i++) {
      if (current[i] != ordered[i]) {
        changedOrder = true;
        break;
      }
    }
    if (!changedOrder) return 0;

    for (var i = 0; i < slots.length; i++) {
      sorted[slots[i]] = byId[ordered[i]]!;
    }

    var changed = 0;
    final rebuilt = <TodoItem>[];
    for (var i = 0; i < sorted.length; i++) {
      final todo = sorted[i];
      if (todo.sortOrder == i) {
        rebuilt.add(todo);
      } else {
        rebuilt.add(todo.copyWith(sortOrder: i));
        changed++;
      }
    }
    _todos = rebuilt;
    await _saveToStorage();
    _notify();
    return changed;
  }

  TodoItem? _nextRecurringTodo(TodoItem prev) {
    final remainingOccurrences = prev.recurrence.maxOccurrences;
    if (remainingOccurrences != null && remainingOccurrences <= 1) {
      return null;
    }
    final next = prev.recurrence.nextAfter(prev.date);
    if (next == null) return null;
    final nextRecurrence = remainingOccurrences == null
        ? prev.recurrence
        : prev.recurrence.copyWith(maxOccurrences: remainingOccurrences - 1);
    final delta = prev.dueDate == null
        ? Duration.zero
        : prev.dueDate!.difference(prev.date);
    final nextDue = prev.dueDate == null ? null : next.add(delta);
    DateTime? nextReminderAt;
    // ignore: deprecated_member_use_from_same_package
    final reminderEnabled = prev.reminder.enabled || prev.hasReminder;
    if (reminderEnabled) {
      final hour = prev.reminder.enabled
          ? prev.reminder.hour
          // ignore: deprecated_member_use_from_same_package
          : prev.reminderAt?.hour;
      final minute = prev.reminder.enabled
          ? prev.reminder.minute
          // ignore: deprecated_member_use_from_same_package
          : prev.reminderAt?.minute;
      if (hour != null && minute != null) {
        final reminderAnchor = nextDue ?? next;
        nextReminderAt = DateTime(
          reminderAnchor.year,
          reminderAnchor.month,
          reminderAnchor.day,
          hour,
          minute,
        );
      }
    }
    return TodoItem(
      title: prev.title,
      notes: prev.notes,
      quadrant: prev.quadrant,
      priority: prev.priority,
      listGroupId: prev.listGroupId,
      listGroupName: prev.listGroupName,
      workspaceId: prev.workspaceId,
      createdBy: prev.createdBy,
      updatedBy: prev.updatedBy,
      assigneeId: prev.assigneeId,
      tags: [...prev.tags],
      attachments: [...prev.attachments],
      dueDate: nextDue,
      date: next,
      hasReminder: reminderEnabled,
      reminderAt: nextReminderAt,
      reminder: prev.reminder,
      reminderPlan: prev.reminderPlan,
      focusLink: prev.focusLink,
      timeTargetSeconds: prev.timeTargetSeconds,
      subtasks: prev.subtasks
          .map((s) => Subtask(title: s.title, sortOrder: s.sortOrder))
          .toList(),
      autoToggleByChildren: prev.autoToggleByChildren,
      recurrence: nextRecurrence,
      sortOrder: prev.sortOrder,
    );
  }

  Future<void> updateListGroupWorkspace(
    String groupName,
    String workspaceId, {
    String? userId,
  }) async {
    var mutated = false;
    for (var i = 0; i < _todos.length; i++) {
      final todo = _todos[i];
      if ((todo.listGroupName ?? '未分组') != groupName) continue;
      _todos[i] = todo.copyWith(
        workspaceId: workspaceId,
        updatedBy: userId,
        createdBy: todo.createdBy ?? userId,
      );
      mutated = true;
    }
    if (!mutated) return;
    await _saveToStorage();
    _notify();
    await _syncTodoRemindersNow();
  }

  // --- Subtask operations ---

  Future<void> addSubtask(String todoId, String title) async {
    final idx = _todos.indexWhere((t) => t.id == todoId);
    if (idx != -1) {
      final newSubtasks = List<Subtask>.from(_todos[idx].subtasks)
        ..add(Subtask(title: title, sortOrder: _todos[idx].subtasks.length));
      _todos[idx] = _todos[idx].copyWith(subtasks: newSubtasks);
      await _saveToStorage();
      _notify();
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

    TodoItem? completedTodo;
    DateTime? removedCompletedAt;
    if (t.autoToggleByChildren) {
      final allDone = t.subtasks.every((s) => s.isCompleted);
      if (allDone && !t.isCompleted) {
        t.isCompleted = true;
        t.completedAt = DateTime.now();
        completedTodo = t;
      } else if (!allDone && t.isCompleted) {
        removedCompletedAt = t.completedAt;
        t.isCompleted = false;
        t.completedAt = null;
      }
    }

    await _saveToStorage();
    _notify();
    if (completedTodo != null) {
      await _timeAudit?.recordTodoCompletion(
        completedTodo,
        completedAt: completedTodo.completedAt,
      );
    } else if (removedCompletedAt != null) {
      await _timeAudit?.removeTodoCompletion(
        t,
        completedAt: removedCompletedAt,
      );
    }
    await _syncTodoRemindersNow();
  }

  Future<void> deleteSubtask(String todoId, String subtaskId) async {
    final idx = _todos.indexWhere((t) => t.id == todoId);
    if (idx != -1) {
      _todos[idx].subtasks.removeWhere((s) => s.id == subtaskId);
      await _saveToStorage();
      _notify();
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
    await _saveToStorage();
    _notify();
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

      final completedDay = DateTime(
        completedAt.year,
        completedAt.month,
        completedAt.day,
      );
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

    // 顺延后重新同步提醒调度队列。
    await _syncTodoRemindersNow();
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _importDuplicateKey(TodoItem todo) {
    final dueKey = todo.dueDate == null ? '' : _dateKey(todo.dueDate!);
    final title = todo.title.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final list = (todo.listGroupName ?? '').trim().toLowerCase();
    return '$title|$dueKey|$list';
  }
}
