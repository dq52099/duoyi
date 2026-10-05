import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/completion_visibility_policy.dart';
import '../core/domain_event_bus.dart';
import '../core/todo_kanban.dart';
import '../models/time_entry.dart';
import '../models/todo.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/reminder_scheduler.dart';
import 'cloud_sync_provider.dart';
import 'time_audit_provider.dart';

class TodoImportSummary {
  final int inserted;
  final int skippedDuplicates;
  final String? reminderSyncIssue;

  const TodoImportSummary({
    required this.inserted,
    required this.skippedDuplicates,
    this.reminderSyncIssue,
  });
}

class TodoReminderSyncResult {
  final int generation;
  final String? issue;
  final DateTime attemptedAt;
  final DateTime? succeededAt;

  const TodoReminderSyncResult({
    required this.generation,
    required this.issue,
    required this.attemptedAt,
    this.succeededAt,
  });

  bool get hasIssue => issue != null;
}

class TodoMutationResult {
  final bool saved;
  final TodoReminderSyncResult? reminderSync;

  const TodoMutationResult({required this.saved, this.reminderSync});

  const TodoMutationResult.notSaved() : saved = false, reminderSync = null;
}

enum TodoCloudSyncNoticeLevel { info, warning, error }

@immutable
class TodoCloudSyncNotice {
  final String message;
  final TodoCloudSyncNoticeLevel level;

  const TodoCloudSyncNotice({required this.message, required this.level});

  bool get isError => level == TodoCloudSyncNoticeLevel.error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TodoCloudSyncNotice &&
          other.message == message &&
          other.level == level;

  @override
  int get hashCode => Object.hash(message, level);
}

class TodoProvider extends ChangeNotifier {
  static const Duration _reminderSyncTimeout = Duration(seconds: 5);

  /// 超过该条数时，持久化编码放到后台 isolate 执行：主 isolate 只付出
  /// 对象图快照拷贝的成本，JSON 编码不再阻塞 UI 帧。
  static const int _isolateEncodeMinItems = 500;

  /// 存储字符串超过该长度时，启动解码放到后台 isolate 执行
  /// （约对应数百条待办）。
  static const int _isolateDecodeMinChars = 60000;

  /// 确认等待上限可在测试中缩短；生产默认 5 秒。
  @visibleForTesting
  Duration reminderSyncTimeout = _reminderSyncTimeout;

  List<TodoItem> _todos = [];
  bool _storageLoaded = false;
  Future<void>? _storageLoadFuture;
  Future<void> _storageWriteQueue = Future<void>.value();
  int _storageGeneration = 0;
  final Set<String> _inFlightCreateKeys = {};
  final Set<String> _inFlightTodoMutationIds = {};
  final Set<String> _inFlightUpdateTodoIds = {};
  final Set<String> _inFlightCompleteTodoIds = {};
  final Set<String> _inFlightDeleteTodoIds = {};
  final Set<String> _inFlightQuadrantTodoIds = {};
  final Set<String> _inFlightPriorityTodoIds = {};
  final Set<String> _inFlightKanbanTodoIds = {};
  final Set<String> _inFlightScheduleTodayTodoIds = {};
  final Set<String> _inFlightReorderKeys = {};
  final Set<String> _inFlightListGroupWorkspaceKeys = {};
  final Set<String> _inFlightArchiveKeys = {};
  final Set<String> _inFlightPostponeKeys = {};
  final Set<String> _inFlightSubtaskCreateKeys = {};
  final Set<String> _inFlightSubtaskToggleKeys = {};
  final Set<String> _inFlightSubtaskDeleteKeys = {};
  final Set<String> _inFlightSubtaskReorderKeys = {};

  /// 可选的 [ReminderScheduler] 引用，由 `main.dart` 在构造完整对象图后注入。
  ///
  /// 设计上允许 `null`：TodoProvider 的持久化路径**不**强依赖调度器。
  /// 注入后，创建、编辑、完成、恢复、删除和顺延会主动重同步，确保系统
  /// 队列及时注册或取消；`main.dart` 的监听重同步仍作为兜底。
  ReminderScheduler? _scheduler;
  TimeAuditProvider? _timeAudit;
  FutureOr<void> Function()? onLocalMutationPersisted;
  String? _lastReminderSyncIssue;
  String? _lastReminderScheduleIssue;
  DateTime? _lastReminderScheduleIssueAt;
  DateTime? _lastReminderSyncAttemptAt;
  DateTime? _lastReminderSyncSucceededAt;
  int _nextReminderSyncGeneration = 0;
  int _lastAppliedReminderSyncGeneration = 0;
  int _mineCompletionRate = 0;
  // 最近一次云同步提示镜像（由 main.dart 从 CloudSyncProvider 单向透传）。
  // break-local-fallback: UI 层只读本字段、不直接持有 CloudSyncProvider，符合
  // "云同步由后台排队触发、UI 层不暴露同步入口"的架构守卫。
  TodoCloudSyncNotice? _cloudSyncNotice;

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

  /// 由 `main.dart` 在监听到 [CloudSyncProvider] 状态变化后单向写入：
  /// 传入 `null` 表示最近一次云同步已完成（清空旧提示）。
  // ignore: use_setters_to_change_properties
  set cloudSyncNotice(TodoCloudSyncNotice? value) {
    if (_cloudSyncNotice == value) return;
    _cloudSyncNotice = value;
    notifyListeners();
  }

  /// 兼容旧测试和旧调用点；新 UI 使用 [cloudSyncNotice]。
  // ignore: use_setters_to_change_properties
  set lastCloudSyncError(String? value) {
    cloudSyncNotice = value == null || value.trim().isEmpty
        ? null
        : TodoCloudSyncNotice(
            message: value.trim(),
            level: TodoCloudSyncNoticeLevel.error,
          );
  }

  List<TodoItem> get todos => _todos;
  int get mineCompletionRate => _mineCompletionRate;
  String? get lastReminderSyncIssue => _lastReminderSyncIssue;
  TodoCloudSyncNotice? get cloudSyncNotice => _cloudSyncNotice;
  String? get lastCloudSyncError =>
      _cloudSyncNotice?.isError == true ? _cloudSyncNotice!.message : null;
  String? get lastReminderScheduleIssue => _lastReminderScheduleIssue;
  DateTime? get lastReminderScheduleIssueAt => _lastReminderScheduleIssueAt;
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

  int _revision = 0;

  /// 每次 [notifyListeners] 自增；供界面做派生数据 memo 化，避免
  /// 每帧重复过滤/分组整份待办列表。
  int get revision => _revision;

  void _notify() {
    _revision++;
    // 大列表下每次 notify 全量 sort 是明显热点；大多数变更不改变排序，
    // 先做一次 O(n) 有序性检查，已有序时直接跳过 sort。
    var sorted = true;
    for (var i = 1; i < _todos.length; i++) {
      if (_compareTodos(_todos[i - 1], _todos[i]) > 0) {
        sorted = false;
        break;
      }
    }
    if (!sorted) {
      _todos.sort(_compareTodos);
    }
    _recomputeMineStats();
    notifyListeners();
  }

  void _recomputeMineStats() {
    if (_todos.isEmpty) {
      _mineCompletionRate = 0;
      return;
    }
    var completed = 0;
    for (final todo in _todos) {
      if (todo.isCompleted) completed += 1;
    }
    _mineCompletionRate = (completed / _todos.length * 100).round();
  }

  // --- Queries ---

  List<TodoItem> getTodosForDate(DateTime date) {
    final key = _dateKey(date);
    return _todos.where((t) => _dateKey(t.date) == key).toList();
  }

  /// "今日"视图可见的 todos（不包含已完成、归档、未到进入日期与已逾期项）。
  ///
  /// 与 [activeTodos] 不同：后者是"未完成"过滤，跨日通用；这里严格对齐
  /// `CompletionVisibilityPolicy.shouldShowInToday`，只返回
  /// 从进入日期起、到截止日期当天的未完成条目；无截止日期则从进入日期起持续展示。
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

  Future<void> loadFromStorage({bool force = false}) async {
    if (!force) {
      if (_storageLoaded) return;
      final running = _storageLoadFuture;
      if (running != null) return running;
      final generation = _storageGeneration;
      final future = _loadFromStorage(generation);
      _storageLoadFuture = future;
      try {
        await future;
      } finally {
        if (identical(_storageLoadFuture, future)) {
          _storageLoadFuture = null;
        }
      }
      return;
    }
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    await _storageLoadFuture;
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
    // 云同步回写 SharedPreferences 后必须强制重读：内存列表若停留在旧快照，
    // 下一次本地写入会把同步结果整表覆盖，重启后服务端数据又“回来”。
    // 强制重读与写入共用同一条串行队列——先落盘未写入的内存改动再重读，
    // 重读之后的写入看到的是包含同步结果的最新列表。
    final reload = _storageWriteQueue.then((_) async {
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
      await _loadFromStorage(generation);
    });
    _storageLoadFuture = reload;
    _storageWriteQueue = reload.catchError((Object e, StackTrace st) {
      debugPrint('[TodoProvider] forced reload from storage failed: $e\n$st');
    });
    try {
      await reload;
    } finally {
      if (identical(_storageLoadFuture, reload)) {
        _storageLoadFuture = null;
      }
    }
  }

  void resetLocalState() {
    _storageGeneration++;
    _nextReminderSyncGeneration++;
    _todos = [];
    _storageLoaded = false;
    _storageLoadFuture = null;
    _lastReminderSyncIssue = null;
    _lastReminderScheduleIssue = null;
    _lastReminderScheduleIssueAt = null;
    _lastReminderSyncAttemptAt = null;
    _lastReminderSyncSucceededAt = null;
    _notify();
  }

  Future<void> _loadFromStorage(int generation) async {
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return;
    }
    final data = prefs.getString('todos');
    if (data != null && data.isNotEmpty) {
      List<TodoItem> parsed = <TodoItem>[];
      var shouldRewrite = false;
      try {
        if (data.length >= _isolateDecodeMinChars) {
          // 大列表的 JSON 解码 + 逐条 fromJson 会阻塞主 isolate 数十毫秒，
          // 且发生在启动关键路径上；挪到后台 isolate，容错语义保持一致。
          final result = await compute(_decodeTodoStoragePayload, data);
          if (!_isCurrentStorageGeneration(generation, accountGeneration)) {
            return;
          }
          parsed = result.items;
          shouldRewrite = result.rewrite;
          if (result.notAList) {
            debugPrint(
              '[TodoProvider] ignored invalid todos storage: not a list',
            );
          }
          final errorDetail = result.errorDetail;
          if (errorDetail != null) {
            debugPrint(
              '[TodoProvider] todos storage decode failed: $errorDetail',
            );
          }
        } else {
          final decoded = json.decode(data);
          if (decoded is List) {
            for (var i = 0; i < decoded.length; i++) {
              final raw = decoded[i];
              try {
                if (raw is! Map) {
                  shouldRewrite = true;
                  debugPrint(
                    '[TodoProvider] skipped invalid todo[$i]: not a map',
                  );
                  continue;
                }
                parsed.add(TodoItem.fromJson(Map<String, dynamic>.from(raw)));
              } catch (e, st) {
                shouldRewrite = true;
                debugPrint('[TodoProvider] skipped invalid todo[$i]: $e\n$st');
              }
            }
          } else {
            shouldRewrite = true;
            debugPrint(
              '[TodoProvider] ignored invalid todos storage: not a list',
            );
          }
        }
        _todos = _dedupeTodosById(
          parsed,
          onDuplicate: () => shouldRewrite = true,
        );
      } catch (e, st) {
        shouldRewrite = true;
        debugPrint('[TodoProvider] todos storage decode failed: $e\n$st');
      }
      if (shouldRewrite) {
        if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
        await prefs.setString(
          'todos_corrupt_backup_${DateTime.now().millisecondsSinceEpoch}',
          data,
        );
        if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
        // 内联写入重写结果，不经 _writeToStorage 的队列串联——
        // 强制重读自身占用 _storageWriteQueue 尾部，再入队会循环等待死锁。
        await _writeTodosSnapshot();
        if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
      }
    } else {
      _todos = [];
    }
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
    _storageLoaded = true;
    _notify();
  }

  /// 同一 id 出现多条属于存储异常（例如同步应用与本地写入交叠留下的重复），
  /// 保留 `updatedAt` 最新的一条，避免列表重复展示并被再次同步放大。
  List<TodoItem> _dedupeTodosById(
    List<TodoItem> items, {
    VoidCallback? onDuplicate,
  }) {
    if (items.length < 2) return items;
    final byId = <String, TodoItem>{};
    final order = <String>[];
    var duplicated = false;
    for (final todo in items) {
      final existing = byId[todo.id];
      if (existing == null) {
        byId[todo.id] = todo;
        order.add(todo.id);
        continue;
      }
      duplicated = true;
      if (existing.updatedAt.isBefore(todo.updatedAt)) {
        byId[todo.id] = todo;
      }
    }
    if (!duplicated) return items;
    onDuplicate?.call();
    return [for (final id in order) byId[id]!];
  }

  Future<void> _ensureStorageLoaded() async {
    final loading = _storageLoadFuture;
    if (loading != null) await loading;
    if (_storageLoaded) return;
    debugPrint('[TodoProvider] waiting for local todo hydration before write');
    await loadFromStorage();
  }

  Future<void> _saveToStorage() async {
    await _ensureStorageLoaded();
    await _writeToStorage();
  }

  /// 将当前内存列表编码并写入存储，不做队列串联。
  /// 只应在上游已与写入队列串行化的上下文调用：
  /// - `_writeToStorage` 的队列任务内部；
  /// - `_loadFromStorage` 的损坏重写分支（加载流程已与队列串行：
  ///   pending 写入先于加载执行，加载期间新提交的写入链在加载完成之后；
  ///   若此处再走队列，强制重读会链到自身导致循环等待死锁）。
  Future<void> _writeTodosSnapshot() async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    // 大列表的 JSON 编码会阻塞主 isolate 数十毫秒（2000 条 ≈ 20ms），
    // 挪到后台 isolate 执行；模型对象图在发送时自动快照拷贝，
    // 因此这里直接传列表，不需要在主 isolate 先做 toJson。
    final data = _todos.length >= _isolateEncodeMinItems
        ? await compute(_encodeTodoStoragePayload, List<TodoItem>.of(_todos))
        : json.encode(_todos.map((e) => e.toJson()).toList());
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return;
    }
    await prefs.setString('todos', data);
    if (_isCurrentStorageGeneration(generation, accountGeneration)) {
      await _notifyLocalMutationPersisted();
    }
  }

  Future<void> _writeToStorage() async {
    final write = _storageWriteQueue.then((_) => _writeTodosSnapshot());
    _storageWriteQueue = write.catchError((Object e, StackTrace st) {
      debugPrint('[TodoProvider] queued local todo write failed: $e\n$st');
    });
    await write;
  }

  Future<void> _notifyLocalMutationPersisted() async {
    try {
      await onLocalMutationPersisted?.call();
    } catch (e, st) {
      debugPrint('[TodoProvider] local mutation callback failed: $e\n$st');
    }
  }

  // --- CRUD ---

  Future<TodoReminderSyncResult> _syncTodoRemindersNow({
    String? reportTodoId,
  }) async {
    final generation = ++_nextReminderSyncGeneration;
    final storageGeneration = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final attemptedAt = DateTime.now();
    bool isCurrent() =>
        _isCurrentStorageGeneration(storageGeneration, accountGeneration) &&
        generation == _nextReminderSyncGeneration;
    void apply(TodoReminderSyncResult result) {
      if (!isCurrent()) return;
      if (reportTodoId != null) {
        _lastReminderScheduleIssue = result.issue;
        _lastReminderScheduleIssueAt = result.hasIssue ? attemptedAt : null;
      }
      _applyReminderSyncResult(result);
    }

    TodoReminderSyncResult resultFor(String? issue, {bool confirmed = true}) =>
        TodoReminderSyncResult(
          generation: generation,
          issue: issue,
          attemptedAt: attemptedAt,
          succeededAt: confirmed && issue == null ? DateTime.now() : null,
        );
    final scheduler = _scheduler;
    if (scheduler == null) {
      final result = resultFor('reminder_scheduler_missing');
      if (_lastReminderSyncIssue != result.issue) {
        debugPrint('[TodoProvider] reminder sync skipped: scheduler missing');
      }
      apply(result);
      return result;
    }
    if (isCurrent()) {
      _lastReminderScheduleIssue = null;
      _lastReminderScheduleIssueAt = null;
    }
    final Future<String?> pending = reportTodoId == null
        ? scheduler.syncTodos(List.of(_todos)).then((_) => null)
        : scheduler.syncTodosAndGetTodoFailure(List.of(_todos), reportTodoId);
    try {
      final failure = await pending.timeout(reminderSyncTimeout);
      final result = resultFor(failure);
      apply(result);
      return result;
    } on TimeoutException {
      // 确认等待结束时调度仍可能继续；迟到结果必须属于原账号和原请求。
      final result = resultFor(null, confirmed: false);
      apply(result);
      unawaited(
        pending.then(
          (failure) {
            if (!isCurrent()) return;
            apply(resultFor(failure));
            notifyListeners();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!isCurrent()) return;
            final issue = error is ReminderScheduleSyncException
                ? error.failures.join('；')
                : error.toString();
            apply(resultFor(issue));
            debugPrint(
              '[TodoProvider] reminder sync failed late: $error\n$stackTrace',
            );
            notifyListeners();
          },
        ),
      );
      return result;
    } on ReminderScheduleSyncException catch (error, stackTrace) {
      final issue = error.failures.isEmpty
          ? '提醒未注册成功，请检查通知权限、提醒方式和提醒时间。'
          : error.failures.join('；');
      final result = resultFor(issue);
      apply(result);
      debugPrint('[TodoProvider] reminder sync failed: $error\n$stackTrace');
      return result;
    } catch (error, stackTrace) {
      final result = resultFor(error.toString());
      apply(result);
      debugPrint('[TodoProvider] reminder sync failed: $error\n$stackTrace');
      return result;
    }
  }

  void _applyReminderSyncResult(TodoReminderSyncResult result) {
    if (result.generation < _nextReminderSyncGeneration ||
        result.generation < _lastAppliedReminderSyncGeneration) {
      return;
    }
    _lastAppliedReminderSyncGeneration = result.generation;
    _lastReminderSyncAttemptAt = result.attemptedAt;
    _lastReminderSyncIssue = result.issue;
    if (result.succeededAt != null) {
      _lastReminderSyncSucceededAt = result.succeededAt;
    }
  }

  Future<void> addTodo(
    TodoItem todo, {
    bool waitForReminderSync = true,
    bool reportReminderScheduleFailure = false,
  }) async {
    await addTodoWithResult(
      todo,
      waitForReminderSync: waitForReminderSync,
      reportReminderScheduleFailure: reportReminderScheduleFailure,
    );
  }

  Future<TodoReminderSyncResult?> addTodoWithResult(
    TodoItem todo, {
    bool waitForReminderSync = true,
    bool reportReminderScheduleFailure = false,
  }) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    await _ensureStorageLoaded();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) {
      return null;
    }
    final createKey = _createInFlightDuplicateKey(todo);
    final claimed = _claimInFlightKeys(
      _inFlightCreateKeys,
      [createKey],
      label: 'todo create',
      duplicateMessage: '待办正在创建中，请勿重复提交',
    );
    try {
      _todos.add(todo);
      DomainEventBus.instance.publish(
        DomainEvent(type: DomainEventType.todoCreated, objectId: todo.id),
      );
      await _saveToStorage();
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) {
        return null;
      }
      _notify();
      if (waitForReminderSync) {
        return await _syncTodoRemindersNow(
          reportTodoId: reportReminderScheduleFailure ? todo.id : null,
        );
      } else {
        unawaited(_syncTodoRemindersNow());
        return null;
      }
    } finally {
      _inFlightCreateKeys.removeAll(claimed);
    }
  }

  Future<TodoImportSummary> importTodos(Iterable<TodoItem> imported) async {
    await _ensureStorageLoaded();
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
    final reminderSyncResult = await _syncTodoRemindersNow();
    return TodoImportSummary(
      inserted: inserted,
      skippedDuplicates: skippedDuplicates,
      reminderSyncIssue: reminderSyncResult.issue,
    );
  }

  Future<bool> updateTodo(
    String id,
    TodoItem updated, {
    bool waitForReminderSync = true,
  }) async {
    final result = await updateTodoWithResult(
      id,
      updated,
      waitForReminderSync: waitForReminderSync,
    );
    return result.saved;
  }

  Future<TodoMutationResult> updateTodoWithResult(
    String id,
    TodoItem updated, {
    bool waitForReminderSync = true,
  }) async {
    final claimed = _claimInFlightKeys(
      _inFlightUpdateTodoIds,
      [id],
      label: 'todo update',
      duplicateMessage: '待办保存正在进行中，请勿重复提交',
      throwWhenDuplicate: false,
    );
    if (claimed.isEmpty) return const TodoMutationResult.notSaved();
    final mutationClaimed = _claimTodoMutationIds([id], label: 'todo update');
    if (mutationClaimed.isEmpty) {
      _inFlightUpdateTodoIds.removeAll(claimed);
      return const TodoMutationResult.notSaved();
    }
    try {
      return await _updateTodoLocked(
        id,
        updated,
        waitForReminderSync: waitForReminderSync,
      );
    } finally {
      _inFlightUpdateTodoIds.removeAll(claimed);
      _inFlightTodoMutationIds.removeAll(mutationClaimed);
    }
  }

  Future<TodoMutationResult> _updateTodoLocked(
    String id,
    TodoItem updated, {
    required bool waitForReminderSync,
  }) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    await _ensureStorageLoaded();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) {
      return const TodoMutationResult.notSaved();
    }
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
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) {
        return const TodoMutationResult.notSaved();
      }
      _notify();
      TodoReminderSyncResult? reminderSync;
      if (waitForReminderSync) {
        reminderSync = await _syncTodoRemindersNow();
        if (!_isCurrentStorageGeneration(generation, accountGeneration)) {
          return const TodoMutationResult.notSaved();
        }
      } else {
        unawaited(_syncTodoRemindersNow());
      }
      if (next.isCompleted) {
        if (!_isCurrentStorageGeneration(generation, accountGeneration)) {
          return const TodoMutationResult.notSaved();
        }
        await _timeAudit?.recordTodoCompletion(
          next,
          completedAt: next.completedAt,
        );
        if (!_isCurrentStorageGeneration(generation, accountGeneration)) {
          return const TodoMutationResult.notSaved();
        }
      } else if (prev.isCompleted && !next.isCompleted) {
        if (!_isCurrentStorageGeneration(generation, accountGeneration)) {
          return const TodoMutationResult.notSaved();
        }
        await _timeAudit?.removeTodoCompletion(
          prev,
          completedAt: prev.completedAt,
        );
        if (!_isCurrentStorageGeneration(generation, accountGeneration)) {
          return const TodoMutationResult.notSaved();
        }
      }
      return TodoMutationResult(saved: true, reminderSync: reminderSync);
    }
    return const TodoMutationResult.notSaved();
  }

  Future<int> completeTodos(
    Iterable<String> ids, {
    bool recordCompletionTime = true,
  }) async {
    final requested = ids.toSet();
    if (requested.isEmpty) return 0;
    final selected = _claimInFlightKeys(
      _inFlightCompleteTodoIds,
      requested,
      label: 'todo complete',
      duplicateMessage: '待办完成操作正在进行中，请勿重复提交',
      allowPartial: true,
      throwWhenDuplicate: false,
    );
    if (selected.isEmpty) return 0;
    final mutationSelected = _claimTodoMutationIds(
      selected,
      label: 'todo complete',
      allowPartial: true,
    );
    if (mutationSelected.isEmpty) {
      _inFlightCompleteTodoIds.removeAll(selected);
      return 0;
    }
    _inFlightCompleteTodoIds.removeAll(selected.difference(mutationSelected));
    try {
      return await _completeTodosLocked(
        mutationSelected,
        recordCompletionTime: recordCompletionTime,
      );
    } finally {
      _inFlightCompleteTodoIds.removeAll(mutationSelected);
      _inFlightTodoMutationIds.removeAll(mutationSelected);
    }
  }

  Future<int> _completeTodosLocked(
    Set<String> selected, {
    required bool recordCompletionTime,
  }) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    await _ensureStorageLoaded();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
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
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
    _notify();

    if (recordCompletionTime) {
      for (final todo in completed) {
        if (!_isCurrentStorageGeneration(generation, accountGeneration)) {
          return 0;
        }
        await _timeAudit?.recordTodoCompletion(
          todo,
          completedAt: todo.completedAt,
        );
        if (!_isCurrentStorageGeneration(generation, accountGeneration)) {
          return 0;
        }
      }
    }
    await _syncTodoRemindersNow();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
    return changed;
  }

  Future<int> reopenTodos(Iterable<String> ids) async {
    final requested = ids.toSet();
    if (requested.isEmpty) return 0;
    final selected = _claimInFlightKeys(
      _inFlightCompleteTodoIds,
      requested,
      label: 'todo reopen',
      duplicateMessage: '待办恢复操作正在进行中，请勿重复提交',
      allowPartial: true,
      throwWhenDuplicate: false,
    );
    if (selected.isEmpty) return 0;
    final mutationSelected = _claimTodoMutationIds(
      selected,
      label: 'todo reopen',
      allowPartial: true,
    );
    if (mutationSelected.isEmpty) {
      _inFlightCompleteTodoIds.removeAll(selected);
      return 0;
    }
    _inFlightCompleteTodoIds.removeAll(selected.difference(mutationSelected));
    try {
      return await _reopenTodosLocked(mutationSelected);
    } finally {
      _inFlightCompleteTodoIds.removeAll(mutationSelected);
      _inFlightTodoMutationIds.removeAll(mutationSelected);
    }
  }

  Future<int> _reopenTodosLocked(Set<String> selected) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    await _ensureStorageLoaded();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
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
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
    _notify();

    for (final todo in reopened) {
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
      await _timeAudit?.removeTodoCompletion(
        todo,
        completedAt: todo.completedAt,
      );
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
    }
    await _syncTodoRemindersNow();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
    return changed;
  }

  /// 切换完成状态。若任务带有重复规则并且本次变为已完成，自动克隆一条下次的任务。
  ///
  /// [recordCompletionTime] 为 `true` 时，在完成状态变更后会自动写入时间足迹；
  /// 由 UI 层统一决定是否要先弹出"顺手记耗时"对话框，或改用自定义时长。
  Future<void> toggleTodo(String id, {bool recordCompletionTime = true}) async {
    final claimed = _claimInFlightKeys(
      _inFlightCompleteTodoIds,
      [id],
      label: 'todo toggle',
      duplicateMessage: '待办状态更新正在进行中，请勿重复提交',
      throwWhenDuplicate: false,
    );
    if (claimed.isEmpty) return;
    final mutationClaimed = _claimTodoMutationIds([id], label: 'todo toggle');
    if (mutationClaimed.isEmpty) {
      _inFlightCompleteTodoIds.removeAll(claimed);
      return;
    }
    try {
      await _toggleTodoLocked(id, recordCompletionTime: recordCompletionTime);
    } finally {
      _inFlightCompleteTodoIds.removeAll(claimed);
      _inFlightTodoMutationIds.removeAll(mutationClaimed);
    }
  }

  Future<void> _toggleTodoLocked(
    String id, {
    required bool recordCompletionTime,
  }) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    await _ensureStorageLoaded();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
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
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
    _notify();
    if (nowCompleted && recordCompletionTime) {
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
      await _timeAudit?.recordTodoCompletion(
        _todos[idx],
        completedAt: _todos[idx].completedAt,
      );
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
    } else if (!nowCompleted) {
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
      await _timeAudit?.removeTodoCompletion(
        prev,
        completedAt: prev.completedAt,
      );
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
    }
    await _syncTodoRemindersNow();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
  }

  Future<void> deleteTodo(String id) async {
    await deleteTodos([id]);
  }

  Future<int> deleteTodos(Iterable<String> ids) async {
    final requested = ids.toSet();
    if (requested.isEmpty) return 0;
    final selected = _claimInFlightKeys(
      _inFlightDeleteTodoIds,
      requested,
      label: 'todo delete',
      duplicateMessage: '待办删除操作正在进行中，请勿重复提交',
      allowPartial: true,
    );
    if (selected.isEmpty) return 0;
    final mutationSelected = _claimTodoMutationIds(
      selected,
      label: 'todo delete',
      allowPartial: true,
    );
    if (mutationSelected.isEmpty) {
      _inFlightDeleteTodoIds.removeAll(selected);
      return 0;
    }
    _inFlightDeleteTodoIds.removeAll(selected.difference(mutationSelected));

    try {
      return await _deleteTodosLocked(mutationSelected);
    } finally {
      _inFlightDeleteTodoIds.removeAll(mutationSelected);
      _inFlightTodoMutationIds.removeAll(mutationSelected);
    }
  }

  Future<int> _deleteTodosLocked(Set<String> selected) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    await _ensureStorageLoaded();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
    final existing = _todos.where((t) => selected.contains(t.id)).toList();
    if (existing.isEmpty) return 0;

    final idsByWorkspace = <String, List<String>>{};
    for (final todo in existing) {
      idsByWorkspace
          .putIfAbsent(todo.workspaceId, () => <String>[])
          .add(todo.id);
    }
    for (final entry in idsByWorkspace.entries) {
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
      await CloudSyncProvider.recordDeletedItems(
        'todos',
        entry.value,
        workspaceId: entry.key,
      );
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
    }
    for (final todo in existing) {
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
      await _timeAudit?.deleteBySource(TimeEntrySource.todo, todo.id);
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
    }
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
    _todos.removeWhere((t) => selected.contains(t.id));
    await _saveToStorage();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
    _notify();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
    await _syncTodoRemindersNow();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
    return existing.length;
  }

  Future<int> updateTodosQuadrant(
    Iterable<String> ids,
    EisenhowerQuadrant quadrant,
  ) async {
    final requested = ids.toSet();
    if (requested.isEmpty) return 0;
    final selected = _claimInFlightKeys(
      _inFlightQuadrantTodoIds,
      requested,
      label: 'todo quadrant update',
      duplicateMessage: '待办移动操作正在进行中，请勿重复提交',
      allowPartial: true,
      throwWhenDuplicate: false,
    );
    if (selected.isEmpty) return 0;
    final mutationSelected = _claimTodoMutationIds(
      selected,
      label: 'todo quadrant update',
      allowPartial: true,
    );
    if (mutationSelected.isEmpty) {
      _inFlightQuadrantTodoIds.removeAll(selected);
      return 0;
    }
    _inFlightQuadrantTodoIds.removeAll(selected.difference(mutationSelected));
    try {
      return await _updateTodosQuadrantLocked(mutationSelected, quadrant);
    } finally {
      _inFlightQuadrantTodoIds.removeAll(mutationSelected);
      _inFlightTodoMutationIds.removeAll(mutationSelected);
    }
  }

  Future<int> _updateTodosQuadrantLocked(
    Set<String> selected,
    EisenhowerQuadrant quadrant,
  ) async {
    await _ensureStorageLoaded();
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
    final requested = ids.toSet();
    if (requested.isEmpty) return 0;
    final selected = _claimInFlightKeys(
      _inFlightPriorityTodoIds,
      requested,
      label: 'todo priority update',
      duplicateMessage: '待办优先级更新正在进行中，请勿重复提交',
      allowPartial: true,
      throwWhenDuplicate: false,
    );
    if (selected.isEmpty) return 0;
    final mutationSelected = _claimTodoMutationIds(
      selected,
      label: 'todo priority update',
      allowPartial: true,
    );
    if (mutationSelected.isEmpty) {
      _inFlightPriorityTodoIds.removeAll(selected);
      return 0;
    }
    _inFlightPriorityTodoIds.removeAll(selected.difference(mutationSelected));
    try {
      return await _updateTodosPriorityLocked(mutationSelected, priority);
    } finally {
      _inFlightPriorityTodoIds.removeAll(mutationSelected);
      _inFlightTodoMutationIds.removeAll(mutationSelected);
    }
  }

  Future<int> _updateTodosPriorityLocked(
    Set<String> selected,
    TodoPriority priority,
  ) async {
    await _ensureStorageLoaded();
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
    final requested = ids.toSet();
    if (requested.isEmpty) return 0;
    final target = columnId.trim().isEmpty
        ? defaultKanbanPendingColumnId
        : columnId.trim();
    final selected = _claimInFlightKeys(
      _inFlightKanbanTodoIds,
      requested.map((id) => '$id:$target'),
      label: 'todo kanban update',
      duplicateMessage: '待办看板更新正在进行中，请勿重复提交',
      allowPartial: true,
      throwWhenDuplicate: false,
    );
    if (selected.isEmpty) return 0;
    final selectedIds = {
      for (final key in selected) key.substring(0, key.lastIndexOf(':')),
    };
    final mutationSelectedIds = _claimTodoMutationIds(
      selectedIds,
      label: 'todo kanban update',
      allowPartial: true,
    );
    if (mutationSelectedIds.isEmpty) {
      _inFlightKanbanTodoIds.removeAll(selected);
      return 0;
    }
    final skippedIds = selectedIds.difference(mutationSelectedIds);
    if (skippedIds.isNotEmpty) {
      _inFlightKanbanTodoIds.removeAll(
        selected.where(
          (key) => skippedIds.contains(key.substring(0, key.lastIndexOf(':'))),
        ),
      );
    }
    try {
      return await _updateTodosKanbanColumnLocked(mutationSelectedIds, target);
    } finally {
      _inFlightKanbanTodoIds.removeAll(selected);
      _inFlightTodoMutationIds.removeAll(mutationSelectedIds);
    }
  }

  Future<int> _updateTodosKanbanColumnLocked(
    Set<String> selected,
    String target,
  ) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    await _ensureStorageLoaded();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
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
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
    _notify();
    for (final todo in completed) {
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
      await _timeAudit?.recordTodoCompletion(
        todo,
        completedAt: todo.completedAt,
      );
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
    }
    for (final todo in reopened) {
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
      await _timeAudit?.removeTodoCompletion(
        todo,
        completedAt: todo.completedAt,
      );
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
    }
    await _syncTodoRemindersNow();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return 0;
    return changed;
  }

  Future<bool> scheduleTodoForToday(
    String id, {
    DateTime? now,
    bool waitForReminderSync = true,
  }) async {
    final claimed = _claimInFlightKeys(
      _inFlightScheduleTodayTodoIds,
      [id],
      label: 'todo schedule today',
      duplicateMessage: '待办安排到今天正在进行中，请勿重复提交',
      throwWhenDuplicate: false,
    );
    if (claimed.isEmpty) return false;
    final mutationClaimed = _claimTodoMutationIds([
      id,
    ], label: 'todo schedule today');
    if (mutationClaimed.isEmpty) {
      _inFlightScheduleTodayTodoIds.removeAll(claimed);
      return false;
    }
    try {
      return await _scheduleTodoForTodayLocked(
        id,
        now: now,
        waitForReminderSync: waitForReminderSync,
      );
    } finally {
      _inFlightScheduleTodayTodoIds.removeAll(claimed);
      _inFlightTodoMutationIds.removeAll(mutationClaimed);
    }
  }

  Future<bool> _scheduleTodoForTodayLocked(
    String id, {
    DateTime? now,
    required bool waitForReminderSync,
  }) async {
    await _ensureStorageLoaded();
    final idx = _todos.indexWhere((t) => t.id == id);
    if (idx == -1) return false;
    final todo = _todos[idx];
    if (todo.isCompleted || todo.isArchivedAfterRollover) return false;

    final base = now ?? DateTime.now();
    final today = DateTime(base.year, base.month, base.day);
    final trigger = todo.hasReminder && todo.reminderAt != null
        ? todo.reminderAt
        : todo.dueDate;
    final triggerIsUsableToday =
        trigger != null && _isSameDay(trigger, today) && trigger.isAfter(base);
    final shouldUseFallbackDue = !triggerIsUsableToday;
    final currentDay = DateTime(todo.date.year, todo.date.month, todo.date.day);
    if (currentDay == today &&
        !todo.isArchivedAfterRollover &&
        triggerIsUsableToday) {
      return false;
    }
    final preferredDue = DateTime(
      today.year,
      today.month,
      today.day,
      base.hour,
      base.minute,
    ).add(const Duration(minutes: 30));
    final endOfToday = DateTime(today.year, today.month, today.day, 23, 59, 59);
    final fallbackDue = preferredDue.isBefore(endOfToday)
        ? preferredDue
        : endOfToday;
    final nextDue = shouldUseFallbackDue ? fallbackDue : todo.dueDate;
    final shouldMirrorReminder =
        shouldUseFallbackDue &&
        (todo.hasReminder ||
            todo.reminder.enabled ||
            todo.reminderPlan.enabled);

    _todos[idx] = todo.copyWith(
      date: today,
      dueDate: nextDue,
      isArchivedAfterRollover: false,
      hasReminder: shouldMirrorReminder ? true : null,
      reminderAt: shouldMirrorReminder ? fallbackDue : todo.reminderAt,
      reminder: shouldMirrorReminder
          ? todo.reminder.copyWith(
              enabled: true,
              hour: fallbackDue.hour,
              minute: fallbackDue.minute,
            )
          : null,
    );
    await _saveToStorage();
    _notify();
    if (waitForReminderSync) {
      await _syncTodoRemindersNow();
    } else {
      unawaited(_syncTodoRemindersNow());
    }
    return true;
  }

  bool _isSameDay(DateTime value, DateTime day) =>
      value.year == day.year &&
      value.month == day.month &&
      value.day == day.day;

  Future<void> reorder(List<String> orderedIds) async {
    final key = orderedIds.join('|');
    final claimed = _claimInFlightKeys(
      _inFlightReorderKeys,
      ['all:$key'],
      label: 'todo reorder',
      duplicateMessage: '待办排序正在保存中，请勿重复提交',
      throwWhenDuplicate: false,
    );
    if (claimed.isEmpty) return;
    try {
      await _reorderLocked(orderedIds);
    } finally {
      _inFlightReorderKeys.removeAll(claimed);
    }
  }

  Future<void> _reorderLocked(List<String> orderedIds) async {
    await _ensureStorageLoaded();
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
    final key = orderedIds.join('|');
    final claimed = _claimInFlightKeys(
      _inFlightReorderKeys,
      ['visible:$key'],
      label: 'visible todo reorder',
      duplicateMessage: '待办排序正在保存中，请勿重复提交',
      throwWhenDuplicate: false,
    );
    if (claimed.isEmpty) return 0;
    try {
      return await _reorderVisibleTodosLocked(orderedIds);
    } finally {
      _inFlightReorderKeys.removeAll(claimed);
    }
  }

  Future<int> _reorderVisibleTodosLocked(List<String> orderedIds) async {
    await _ensureStorageLoaded();
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
    final key = '${groupName.trim()}:$workspaceId';
    final claimed = _claimInFlightKeys(
      _inFlightListGroupWorkspaceKeys,
      [key],
      label: 'todo list workspace update',
      duplicateMessage: '清单共享状态正在保存中，请勿重复提交',
      throwWhenDuplicate: false,
    );
    if (claimed.isEmpty) return;
    try {
      await _updateListGroupWorkspaceLocked(
        groupName,
        workspaceId,
        userId: userId,
      );
    } finally {
      _inFlightListGroupWorkspaceKeys.removeAll(claimed);
    }
  }

  Future<void> _updateListGroupWorkspaceLocked(
    String groupName,
    String workspaceId, {
    String? userId,
  }) async {
    await _ensureStorageLoaded();
    final affectedIds = _todos
        .where((todo) => (todo.listGroupName ?? '未分组') == groupName)
        .map((todo) => todo.id)
        .toSet();
    final mutationSelected = _claimTodoMutationIds(
      affectedIds,
      label: 'todo list workspace update',
      allowPartial: true,
    );
    if (mutationSelected.isEmpty) return;
    var mutated = false;
    try {
      for (var i = 0; i < _todos.length; i++) {
        final todo = _todos[i];
        if (!mutationSelected.contains(todo.id)) continue;
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
    } finally {
      _inFlightTodoMutationIds.removeAll(mutationSelected);
    }
  }

  // --- Subtask operations ---

  Future<void> addSubtask(String todoId, String title) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return;
    final key = '$todoId:${cleanTitle.toLowerCase()}';
    if (!_inFlightSubtaskCreateKeys.add(key)) {
      debugPrint('[TodoProvider] duplicate in-flight subtask create skipped');
      throw StateError('子任务正在创建中，请勿重复提交');
    }
    final mutationClaimed = _claimTodoMutationIds([
      todoId,
    ], label: 'subtask create');
    if (mutationClaimed.isEmpty) {
      _inFlightSubtaskCreateKeys.remove(key);
      return;
    }
    try {
      await _addSubtaskLocked(todoId, cleanTitle);
    } finally {
      _inFlightSubtaskCreateKeys.remove(key);
      _inFlightTodoMutationIds.removeAll(mutationClaimed);
    }
  }

  Future<void> _addSubtaskLocked(String todoId, String title) async {
    await _ensureStorageLoaded();
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
    final key = '$todoId:$subtaskId';
    if (!_inFlightSubtaskToggleKeys.add(key)) return;
    final mutationClaimed = _claimTodoMutationIds([
      todoId,
    ], label: 'subtask toggle');
    if (mutationClaimed.isEmpty) {
      _inFlightSubtaskToggleKeys.remove(key);
      return;
    }
    try {
      await _toggleSubtaskLocked(todoId, subtaskId);
    } finally {
      _inFlightSubtaskToggleKeys.remove(key);
      _inFlightTodoMutationIds.removeAll(mutationClaimed);
    }
  }

  Future<void> _toggleSubtaskLocked(String todoId, String subtaskId) async {
    await _ensureStorageLoaded();
    final idx = _todos.indexWhere((t) => t.id == todoId);
    if (idx == -1) return;
    final todo = _todos[idx];
    final sIdx = todo.subtasks.indexWhere((s) => s.id == subtaskId);
    if (sIdx == -1) return;
    final nextSubtasks = <Subtask>[
      for (final subtask in todo.subtasks)
        subtask.id == subtaskId
            ? Subtask(
                id: subtask.id,
                title: subtask.title,
                isCompleted: !subtask.isCompleted,
                sortOrder: subtask.sortOrder,
              )
            : subtask,
    ];
    _todos[idx] = todo.copyWith(subtasks: nextSubtasks);
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
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    await _ensureStorageLoaded();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
    final idx = _todos.indexWhere((t) => t.id == todoId);
    if (idx == -1) return;
    final t = _todos[idx];
    if (t.subtasks.isEmpty) return;

    TodoItem? completedTodo;
    DateTime? removedCompletedAt;
    if (t.autoToggleByChildren) {
      final allDone = t.subtasks.every((s) => s.isCompleted);
      if (allDone && !t.isCompleted) {
        final completedAt = DateTime.now();
        final next = t.copyWith(isCompleted: true, completedAt: completedAt);
        _todos[idx] = next;
        completedTodo = next;
      } else if (!allDone && t.isCompleted) {
        removedCompletedAt = t.completedAt;
        _todos[idx] = t.copyWith(isCompleted: false, completedAt: null);
      }
    }

    await _saveToStorage();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
    _notify();
    if (completedTodo != null) {
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
      await _timeAudit?.recordTodoCompletion(
        completedTodo,
        completedAt: completedTodo.completedAt,
      );
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
    } else if (removedCompletedAt != null) {
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
      await _timeAudit?.removeTodoCompletion(
        t,
        completedAt: removedCompletedAt,
      );
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
    }
    await _syncTodoRemindersNow();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
  }

  Future<void> deleteSubtask(String todoId, String subtaskId) async {
    final key = '$todoId:$subtaskId';
    if (!_inFlightSubtaskDeleteKeys.add(key)) return;
    final mutationClaimed = _claimTodoMutationIds([
      todoId,
    ], label: 'subtask delete');
    if (mutationClaimed.isEmpty) {
      _inFlightSubtaskDeleteKeys.remove(key);
      return;
    }
    try {
      await _deleteSubtaskLocked(todoId, subtaskId);
    } finally {
      _inFlightSubtaskDeleteKeys.remove(key);
      _inFlightTodoMutationIds.removeAll(mutationClaimed);
    }
  }

  Future<void> _deleteSubtaskLocked(String todoId, String subtaskId) async {
    await _ensureStorageLoaded();
    final idx = _todos.indexWhere((t) => t.id == todoId);
    if (idx != -1) {
      final todo = _todos[idx];
      final nextSubtasks = todo.subtasks
          .where((subtask) => subtask.id != subtaskId)
          .toList(growable: false);
      if (nextSubtasks.length == todo.subtasks.length) return;
      _todos[idx] = todo.copyWith(subtasks: nextSubtasks);
      if (nextSubtasks.isEmpty) {
        await _saveToStorage();
        _notify();
        await _syncTodoRemindersNow();
      } else {
        await recomputeParent(todoId);
      }
    }
  }

  Future<void> reorderSubtasks(String todoId, List<String> orderedIds) async {
    final key = '$todoId:${orderedIds.join('|')}';
    final claimed = _claimInFlightKeys(
      _inFlightSubtaskReorderKeys,
      [key],
      label: 'subtask reorder',
      duplicateMessage: '子任务排序正在保存中，请勿重复提交',
      throwWhenDuplicate: false,
    );
    if (claimed.isEmpty) return;
    final mutationClaimed = _claimTodoMutationIds([
      todoId,
    ], label: 'subtask reorder');
    if (mutationClaimed.isEmpty) {
      _inFlightSubtaskReorderKeys.removeAll(claimed);
      return;
    }
    try {
      await _reorderSubtasksLocked(todoId, orderedIds);
    } finally {
      _inFlightSubtaskReorderKeys.removeAll(claimed);
      _inFlightTodoMutationIds.removeAll(mutationClaimed);
    }
  }

  Future<void> _reorderSubtasksLocked(
    String todoId,
    List<String> orderedIds,
  ) async {
    await _ensureStorageLoaded();
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
    final claimed = _claimInFlightKeys(
      _inFlightArchiveKeys,
      [_dateKey(todayStart)],
      label: 'todo archive rollover',
      duplicateMessage: '待办归档正在执行中，请勿重复提交',
      throwWhenDuplicate: false,
    );
    if (claimed.isEmpty) return;
    try {
      await _archivePastCompletionsLocked(todayStart);
    } finally {
      _inFlightArchiveKeys.removeAll(claimed);
    }
  }

  Future<void> _archivePastCompletionsLocked(DateTime todayStart) async {
    await _ensureStorageLoaded();
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
    final claimed = _claimInFlightKeys(
      _inFlightPostponeKeys,
      [_dateKey(todayDay)],
      label: 'todo overdue postpone',
      duplicateMessage: '待办顺延正在执行中，请勿重复提交',
      throwWhenDuplicate: false,
    );
    if (claimed.isEmpty) return;
    try {
      await _postponeOverdueLocked(todayDay);
    } finally {
      _inFlightPostponeKeys.removeAll(claimed);
    }
  }

  Future<void> _postponeOverdueLocked(DateTime todayDay) async {
    await _ensureStorageLoaded();
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

  Set<String> _claimInFlightKeys(
    Set<String> bucket,
    Iterable<String> keys, {
    required String label,
    required String duplicateMessage,
    bool allowPartial = false,
    bool throwWhenDuplicate = true,
  }) {
    final requested = keys.where((key) => key.isNotEmpty).toSet();
    if (requested.isEmpty) return <String>{};

    final claimed = <String>{};
    final duplicates = <String>[];
    for (final key in requested) {
      if (bucket.add(key)) {
        claimed.add(key);
      } else {
        duplicates.add(key);
      }
    }
    if (duplicates.isEmpty) return claimed;

    if (allowPartial && claimed.isNotEmpty) {
      debugPrint(
        '[TodoProvider] ${duplicates.length} duplicate $label request(s) '
        'skipped; ${claimed.length} new request(s) will continue',
      );
      return claimed;
    }

    bucket.removeAll(claimed);
    debugPrint(
      '[TodoProvider] duplicate $label request skipped: '
      '${duplicates.length}/${requested.length} already in-flight',
    );
    if (throwWhenDuplicate) {
      throw StateError(duplicateMessage);
    }
    return <String>{};
  }

  Set<String> _claimTodoMutationIds(
    Iterable<String> ids, {
    required String label,
    bool allowPartial = false,
    bool throwWhenDuplicate = false,
  }) {
    return _claimInFlightKeys(
      _inFlightTodoMutationIds,
      ids,
      label: '$label mutation',
      duplicateMessage: '待办正在保存中，请稍后再试',
      allowPartial: allowPartial,
      throwWhenDuplicate: throwWhenDuplicate,
    );
  }

  bool _isCurrentStorageGeneration(
    int storageGeneration,
    int accountGeneration,
  ) {
    return storageGeneration == _storageGeneration &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        );
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

  String _createInFlightDuplicateKey(TodoItem todo) {
    final title = todo.title.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final dateKey = _dateKey(todo.date);
    final dueKey = todo.dueDate == null
        ? ''
        : todo.dueDate!.millisecondsSinceEpoch.toString();
    final list = (todo.listGroupName ?? '').trim().toLowerCase();
    return [todo.workspaceId, list, title, dateKey, dueKey].join('|');
  }
}

/// 在后台 isolate 中编码待办存储载荷（供 `compute` 调用，必须是顶层函数）。
/// 传入的是模型对象图的拷贝，与发送时刻的内存状态一致。
String _encodeTodoStoragePayload(List<TodoItem> todos) =>
    json.encode(todos.map((e) => e.toJson()).toList());

/// 在后台 isolate 中解码待办存储载荷，保留与主线程路径一致的逐条容错：
/// 坏记录跳过并标记重写，整体不是列表或 JSON 损坏时也标记重写。
({List<TodoItem> items, bool rewrite, bool notAList, String? errorDetail})
_decodeTodoStoragePayload(String data) {
  final parsed = <TodoItem>[];
  var shouldRewrite = false;
  var notAList = false;
  String? errorDetail;
  try {
    final decoded = json.decode(data);
    if (decoded is List) {
      for (var i = 0; i < decoded.length; i++) {
        final raw = decoded[i];
        try {
          if (raw is! Map) {
            shouldRewrite = true;
            continue;
          }
          parsed.add(TodoItem.fromJson(Map<String, dynamic>.from(raw)));
        } catch (e) {
          shouldRewrite = true;
          errorDetail ??= 'skipped invalid todo[$i]: $e';
        }
      }
    } else {
      shouldRewrite = true;
      notAList = true;
    }
  } catch (e) {
    shouldRewrite = true;
    errorDetail = '$e';
  }
  return (
    items: parsed,
    rewrite: shouldRewrite,
    notAList: notAList,
    errorDetail: errorDetail,
  );
}
