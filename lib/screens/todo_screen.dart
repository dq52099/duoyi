import '../widgets/app_date_format.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/completion_visibility_policy.dart';
import '../core/account_preference_writes.dart';
import '../core/design_tokens.dart';
import '../core/desktop_tokens.dart';
import '../core/i18n_date_format.dart';
import '../core/iterable_extensions.dart';
import '../core/i18n.dart';
import '../core/main_ui_copy.dart';
import '../core/smart_date_parser.dart';
import '../core/smart_todo_draft.dart';
import '../core/todo_filters.dart';
import '../core/todo_kanban.dart';
import '../core/todo_board_ui_copy.dart';
import '../models/goal.dart'
    show ReminderKind, ReminderPlan, ReminderRule, ReminderRuleType;
import '../models/habit.dart';
import '../models/todo.dart';
import '../models/workspace.dart';
import '../providers/auth_provider.dart';
import '../providers/app_lock_provider.dart';
import '../providers/cloud_sync_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/share_provider.dart';
import '../providers/todo_provider.dart';
import '../providers/notification_service.dart';
import '../providers/preferences_provider.dart';
import '../providers/theme_provider.dart';
import '../services/ai_service.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/api_client.dart';
import '../services/settings_action_origin.dart';
import '../services/app_update_service.dart';
import '../services/app_access_route_gate.dart';
import '../services/reminder_issue_copy.dart' show NotificationIssueTitle;
import '../core/todo_templates.dart';
import '../widgets/brand_background.dart';
import '../widgets/eisenhower_matrix.dart';
import '../widgets/empty_state.dart';
import '../widgets/todo_completion_flow.dart';
import '../widgets/surface_components.dart';
import 'share_screen.dart';
import 'todo_detail_screen.dart'
    show TodoDetailScreen, preflightTodoReminderSave, priorityColor;

Future<void>? _kanbanPreferenceWriteTail;

class TodoScreen extends StatefulWidget implements LocaleStatePreservingRoute {
  const TodoScreen({super.key});

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

enum _TodoViewMode { matrix, list, kanban }

/// 待办页派生数据（过滤 + 分组 + 标签聚合）的 memo 缓存。
/// 这些计算都是 O(n) 且每次 build 都会执行；滚动起手的 setState、
/// 其他 Provider 通知都会触发重建，缓存命中时可整块跳过。
class _TodoDerivedData {
  final List<TodoItem> baseTodos;
  final List<TodoItem> filteredTodos;
  final Map<EisenhowerQuadrant, List<TodoItem>> quadrantGroups;
  final Map<String, List<TodoItem>> listGroups;
  final List<MapEntry<String, List<TodoItem>>> listGroupEntries;
  final Map<String, List<TodoItem>> kanbanGroups;
  final List<String> availableTags;
  final List<String> availableListGroups;
  final int overdueCount;

  const _TodoDerivedData({
    required this.baseTodos,
    required this.filteredTodos,
    required this.quadrantGroups,
    required this.listGroups,
    required this.listGroupEntries,
    required this.kanbanGroups,
    required this.availableTags,
    required this.availableListGroups,
    required this.overdueCount,
  });
}

class _TodoScreenState extends State<TodoScreen> {
  _TodoViewMode _viewMode = _TodoViewMode.matrix;
  TodoFilterState<EisenhowerQuadrant, TodoPriority> _filter =
      const TodoFilterState<EisenhowerQuadrant, TodoPriority>();
  TodoKanbanBoardConfig _kanbanConfig = TodoKanbanBoardConfig.defaults();
  AuthProvider? _kanbanAuth;
  SettingsActionOrigin? _kanbanConfigOrigin;
  int _kanbanLoadSerial = 0;
  int? _kanbanActiveReadSerial;
  bool _kanbanReloadPending = true;
  bool _kanbanLoadFailed = false;
  bool _kanbanReloadQueued = false;
  bool _batchMode = false;
  bool _batchSubmitting = false;
  final ValueNotifier<int> _swipeDismissSerial = ValueNotifier<int>(0);
  final ScrollController _listScrollController = ScrollController();
  final Set<String> _collapsedListGroups = <String>{};
  final Set<String> _selectedTodoIds = <String>{};
  bool _swipeDismissedForGesture = false;
  bool _scrollDismissScheduled = false;
  bool _scrollDismissNeedsRebuild = false;

  void _triggerSwipeDismiss({bool rebuild = false}) {
    if (!mounted) return;
    if (rebuild) _scrollDismissNeedsRebuild = true;
    if (_scrollDismissScheduled) return;

    final isFrameBusy =
        SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks;

    if (isFrameBusy) {
      _scrollDismissScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollDismissScheduled = false;
        final shouldRebuild = _scrollDismissNeedsRebuild;
        _scrollDismissNeedsRebuild = false;
        if (!mounted) return;
        _swipeDismissSerial.value++;
        if (shouldRebuild) setState(() {});
      });
    } else {
      final shouldRebuild = _scrollDismissNeedsRebuild;
      _scrollDismissNeedsRebuild = false;
      _swipeDismissSerial.value++;
      if (shouldRebuild && mounted) setState(() {});
    }
  }

  _TodoDerivedData? _derived;
  TodoProvider? _derivedProvider;
  PreferencesProvider? _derivedPreferences;
  int? _derivedPreferenceGeneration;
  bool? _derivedShowCompletedTodos;
  int? _derivedRevision;
  TodoFilterState<EisenhowerQuadrant, TodoPriority>? _derivedFilter;
  TodoKanbanBoardConfig? _derivedKanbanConfig;
  int? _derivedMinuteKey;

  _TodoDerivedData _computeDerivedData({
    required TodoProvider todoProvider,
    required int minuteKey,
    required bool showCompletedTodos,
  }) {
    final now = DateTime.now();
    final baseTodos = _filter.includeArchived
        ? todoProvider.todos
        : todoProvider.visibleListTodos;
    final filteredTodos = filterTodos(
      baseTodos,
      effectiveTodoFilter(_filter, showCompletedTodos: showCompletedTodos),
      now: now,
      quadrantOf: (todo) => todo.quadrant,
      priorityOf: (todo) => todo.priority,
      tagsOf: (todo) => todo.tags,
      listGroupNameOf: (todo) => todo.listGroupName,
      dueDateOf: (todo) => todo.dueDate,
      isCompletedOf: (todo) => todo.isCompleted,
      isArchivedAfterRolloverOf: (todo) => todo.isArchivedAfterRollover,
      isInTodayOverviewOf: CompletionVisibilityPolicy.isInTodayOverview,
      titleOf: (todo) => todo.title,
      notesOf: (todo) => todo.notes,
    );
    final sortedTodos = sortTodos(
      filteredTodos,
      _filter.sortOrder,
      dueDateOf: (todo) => todo.dueDate,
      priorityRankOf: (todo) => todo.priority.rank,
      createdAtOf: (todo) => todo.createdAt,
      sortOrderOf: (todo) => todo.sortOrder,
      isCompletedOf: (todo) => todo.isCompleted,
    );
    final quadrantGroups = groupTodosByQuadrant(
      sortedTodos,
      quadrants: EisenhowerQuadrant.values,
      quadrantOf: (todo) => todo.quadrant,
    );
    final listGroups = groupTodosByList(
      sortedTodos,
      (todo) => todo.listGroupName,
    );
    final listGroupEntries = listGroups.entries.toList(growable: false);
    final kanbanGroups = <String, List<TodoItem>>{
      for (final column in _kanbanConfig.columns) column.id: <TodoItem>[],
    };
    for (final todo in sortedTodos) {
      final columnId = _kanbanConfig.normalizeColumnId(todo.kanbanColumnId);
      kanbanGroups.putIfAbsent(columnId, () => <TodoItem>[]).add(todo);
    }
    return _TodoDerivedData(
      baseTodos: baseTodos,
      filteredTodos: sortedTodos,
      quadrantGroups: quadrantGroups,
      listGroups: listGroups,
      listGroupEntries: listGroupEntries,
      kanbanGroups: kanbanGroups,
      availableTags: collectTodoTags(baseTodos, (todo) => todo.tags),
      availableListGroups: collectTodoListGroups(
        baseTodos,
        (todo) => todo.listGroupName,
      ),
      overdueCount: todoProvider.overdueTodos.length,
    );
  }

  _TodoDerivedData _derivedDataFor(
    TodoProvider todoProvider,
    PreferencesProvider? preferences,
  ) {
    // 逾期/今日等时间过滤按分钟粒度失效即可；按帧取 `DateTime.now()` 会让
    // 缓存永远失效。
    final minuteKey = DateTime.now().millisecondsSinceEpoch ~/ 60000;
    final derived = _derived;
    final showCompletedTodos = preferences?.showCompletedTodos ?? true;
    if (derived != null &&
        identical(_derivedProvider, todoProvider) &&
        identical(_derivedPreferences, preferences) &&
        _derivedPreferenceGeneration == preferences?.storageGeneration &&
        _derivedShowCompletedTodos == showCompletedTodos &&
        _derivedRevision == todoProvider.revision &&
        identical(_derivedFilter, _filter) &&
        identical(_derivedKanbanConfig, _kanbanConfig) &&
        _derivedMinuteKey == minuteKey) {
      return derived;
    }
    final computed = _computeDerivedData(
      todoProvider: todoProvider,
      minuteKey: minuteKey,
      showCompletedTodos: showCompletedTodos,
    );
    _derived = computed;
    _derivedProvider = todoProvider;
    _derivedPreferences = preferences;
    _derivedPreferenceGeneration = preferences?.storageGeneration;
    _derivedShowCompletedTodos = showCompletedTodos;
    _derivedRevision = todoProvider.revision;
    _derivedFilter = _filter;
    _derivedKanbanConfig = _kanbanConfig;
    _derivedMinuteKey = minuteKey;
    return computed;
  }

  @override
  void initState() {
    super.initState();
    _listScrollController.addListener(_onListScroll);
    I18n.localeListenable.addListener(_onLocaleChanged);
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _onKanbanAccountBoundary,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthProvider?>();
    context.watch<AppLockProvider?>();
    context.watch<AppUpdateService?>();
    if (!identical(auth, _kanbanAuth)) {
      if (_kanbanConfigOrigin != null || _kanbanActiveReadSerial != null) {
        _clearKanbanForAccountBoundary();
      }
      _kanbanAuth?.removeListener(_onKanbanAuthChanged);
      _kanbanAuth = auth;
      _kanbanAuth?.addListener(_onKanbanAuthChanged);
    }
    if (_kanbanReloadPending) {
      _queueKanbanReload();
    }
  }

  bool get _kanbanAccountAvailable =>
      _kanbanAuth?.isAccountTransitionInProgress != true &&
      _kanbanAuth?.isLocalAccountDataBlocked != true;

  void _clearKanbanForAccountBoundary() {
    if (!mounted) return;
    _kanbanLoadSerial++;
    _kanbanActiveReadSerial = null;
    _kanbanConfigOrigin = null;
    _kanbanReloadPending = true;
    _kanbanLoadFailed = false;
    setState(() => _kanbanConfig = TodoKanbanBoardConfig.defaults());
  }

  void _onKanbanAccountBoundary() {
    _clearKanbanForAccountBoundary();
    _queueKanbanReload();
  }

  void _onKanbanAuthChanged() {
    if (!_kanbanAccountAvailable ||
        _kanbanConfigOrigin?.isCurrent(checkRoute: false) == false) {
      _clearKanbanForAccountBoundary();
    }
    if (_kanbanReloadPending && _kanbanAccountAvailable) _queueKanbanReload();
  }

  void _queueKanbanReload() {
    if (!mounted || _kanbanReloadQueued) return;
    _kanbanReloadQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _kanbanReloadQueued = false;
      if (mounted && _kanbanReloadPending) {
        unawaited(_reloadKanbanAfterBoundary());
      }
    });
  }

  Future<void> _reloadKanbanAfterBoundary() async {
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    await AccountPreferenceWrites.waitForBoundary();
    if (!mounted ||
        !_kanbanReloadPending ||
        !_kanbanAccountAvailable ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
      return;
    }
    final origin = SettingsActionOrigin(context);
    if (!origin.isCurrent(checkRoute: false)) return;
    if (_kanbanActiveReadSerial != null) return;
    final serial = ++_kanbanLoadSerial;
    _kanbanActiveReadSerial = serial;
    try {
      await _loadKanbanConfig(origin, serial);
    } catch (error, stack) {
      debugPrint('[TodoKanban] settings load failed: $error\n$stack');
      if (mounted &&
          serial == _kanbanLoadSerial &&
          origin.isCurrent(checkRoute: false)) {
        setState(() => _kanbanLoadFailed = true);
        if (origin.isCurrent()) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: ValueListenableBuilder<AppLocale>(
                valueListenable: I18n.localeListenable,
                builder: (_, _, _) => Text(TodoBoardUiCopy.kanbanLoadFailed),
              ),
            ),
          );
        }
      }
    } finally {
      if (_kanbanActiveReadSerial == serial) _kanbanActiveReadSerial = null;
    }
  }

  void _onLocaleChanged() {
    _derived = null;
    if (mounted) setState(() {});
  }

  void _onListScroll() {
    if (_listScrollController.hasClients) {
      _triggerSwipeDismiss(rebuild: false);
    }
  }

  Future<void> _loadKanbanConfig(
    SettingsActionOrigin origin,
    int serial,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted ||
        serial != _kanbanLoadSerial ||
        !origin.isCurrent(checkRoute: false)) {
      return;
    }
    final config = TodoKanbanBoardConfig.decode(
      prefs.getString(todoKanbanColumnsPrefsKey),
    );
    if (!mounted) return;
    setState(() {
      _kanbanConfig = config;
      _kanbanConfigOrigin = origin;
      _kanbanReloadPending = false;
      _kanbanLoadFailed = false;
    });
  }

  Future<void> _saveKanbanConfig(
    TodoKanbanBoardConfig config,
    SettingsActionOrigin origin,
  ) async {
    _kanbanLoadSerial++;
    final saved = await AccountPreferenceWrites.runResult<bool>((token) {
      Future<bool> invoke() async {
        bool isCurrent() => mounted && token.isCurrent && origin.isCurrent();
        if (!isCurrent()) return false;
        final prefs = await SharedPreferences.getInstance();
        if (!isCurrent()) return false;
        final transaction = AccountPreferenceTransaction(prefs, isCurrent);
        try {
          await transaction.setString(
            todoKanbanColumnsPrefsKey,
            config.encode(),
          );
          transaction.commit();
          return true;
        } catch (error) {
          // This tracked operation is drained before account cleanup clears keys.
          await transaction.rollback(
            canceledBeforeCleanup: error is AccountPreferenceWriteCanceled,
          );
          return false;
        }
      }

      final previous = _kanbanPreferenceWriteTail;
      final queued = previous == null
          ? Future<bool>.sync(invoke)
          : previous.then<bool>((_) => invoke());
      final tail = queued.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      _kanbanPreferenceWriteTail = tail;
      tail.then<void>((_) {
        if (identical(_kanbanPreferenceWriteTail, tail)) {
          _kanbanPreferenceWriteTail = null;
        }
      });
      return queued;
    }, canceledResult: () => false);
    if (!mounted || !origin.isCurrent()) return;
    if (saved) {
      setState(() => _kanbanConfig = config);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (_, _, _) => Text(TodoBoardUiCopy.kanbanSaveFailed),
          ),
        ),
      );
    }
  }

  void _enterBatchMode({String? todoId, bool switchToList = false}) {
    if (_batchSubmitting) return;
    setState(() {
      _batchMode = true;
      if (switchToList) _viewMode = _TodoViewMode.list;
      if (todoId != null) _selectedTodoIds.add(todoId);
    });
  }

  void _exitBatchMode() {
    setState(() {
      _batchMode = false;
      _selectedTodoIds.clear();
    });
  }

  void _toggleSelection(String todoId) {
    if (_batchSubmitting) return;
    setState(() {
      if (_selectedTodoIds.contains(todoId)) {
        _selectedTodoIds.remove(todoId);
        if (_selectedTodoIds.isEmpty) _batchMode = false;
      } else {
        _batchMode = true;
        _selectedTodoIds.add(todoId);
      }
    });
  }

  void _selectAllVisible(Iterable<String> editableIds) {
    if (_batchSubmitting) return;
    final ids = editableIds.toSet();
    setState(() {
      _batchMode = true;
      if (_selectedTodoIds.containsAll(ids)) {
        _selectedTodoIds.removeAll(ids);
        if (_selectedTodoIds.isEmpty) _batchMode = false;
      } else {
        _selectedTodoIds.addAll(ids);
      }
    });
  }

  void _setFilter(TodoFilterState<EisenhowerQuadrant, TodoPriority> filter) {
    setState(() {
      _filter = filter;
      _batchMode = false;
      _selectedTodoIds.clear();
    });
  }

  void _clearFilter() {
    _setFilter(const TodoFilterState<EisenhowerQuadrant, TodoPriority>());
  }

  @override
  void dispose() {
    _scrollDismissScheduled = false;
    _scrollDismissNeedsRebuild = false;
    _kanbanAuth?.removeListener(_onKanbanAuthChanged);
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _onKanbanAccountBoundary,
    );
    I18n.localeListenable.removeListener(_onLocaleChanged);
    _listScrollController.removeListener(_onListScroll);
    _listScrollController.dispose();
    _swipeDismissSerial.dispose();
    super.dispose();
  }

  bool _dismissSwipeActionsOnScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification ||
        notification is UserScrollNotification ||
        notification is ScrollEndNotification) {
      if (notification is ScrollEndNotification) {
        _swipeDismissedForGesture = false;
        return false;
      }
      if (_swipeDismissedForGesture) return false;
      // Close rows once per gesture. The list itself remains lazy; retaining
      // this single start-time rebuild keeps legacy swipe rows in sync without
      // rebuilding the page on every scroll tick.
      _swipeDismissedForGesture = true;
      _triggerSwipeDismiss(rebuild: true);
    }
    return false;
  }

  Future<void> _completeSelected() async {
    await _runBatchAction(
      (ids) => context.read<TodoProvider>().completeTodos(ids),
      (count) => TodoBoardUiCopy.batchCompleted(count),
    );
  }

  Future<void> _reopenSelected() async {
    await _runBatchAction(
      (ids) => context.read<TodoProvider>().reopenTodos(ids),
      (count) => TodoBoardUiCopy.batchReopened(count),
    );
  }

  Future<void> _moveSelected(EisenhowerQuadrant quadrant) async {
    await _runBatchAction(
      (ids) => context.read<TodoProvider>().updateTodosQuadrant(ids, quadrant),
      (count) => TodoBoardUiCopy.batchMoved(count, _quadrantLabel(quadrant)),
    );
  }

  Future<void> _setSelectedPriority(TodoPriority priority) async {
    await _runBatchAction(
      (ids) => context.read<TodoProvider>().updateTodosPriority(ids, priority),
      (count) => TodoBoardUiCopy.batchPriorityUpdated(count),
    );
  }

  Future<void> _rescheduleSelectedDueDate() async {
    if (_batchSubmitting || _visibleEditableSelection().isEmpty) return;
    final choice = await _showBatchDueDatePickerDialog(context);
    if (choice == null || !mounted) return;
    await _runBatchAction(
      (ids) =>
          context.read<TodoProvider>().rescheduleTodosDueDate(ids, choice.dueDate),
      (count) => I18n.current == AppLocale.en
          ? 'Updated due date for $count tasks'
          : '已调整 $count 个任务的截止日期',
    );
  }

  Future<void> _assignSelectedList(List<String> availableLists) async {
    if (_batchSubmitting || _visibleEditableSelection().isEmpty) return;
    final choice = await _showBatchListPickerDialog(
      context,
      availableLists: availableLists,
    );
    if (choice == null || !mounted) return;
    await _runBatchAction(
      (ids) =>
          context.read<TodoProvider>().assignTodosListGroup(ids, choice.listName),
      (count) => I18n.current == AppLocale.en
          ? 'Updated list for $count tasks'
          : '已更新 $count 个任务的所属清单',
    );
  }

  Future<void> _assignSelectedTags(List<String> availableTags) async {
    if (_batchSubmitting || _visibleEditableSelection().isEmpty) return;
    final tags = await _showBatchTagPickerDialog(
      context,
      availableTags: availableTags,
    );
    if (tags == null || tags.isEmpty || !mounted) return;
    await _runBatchAction(
      (ids) => context.read<TodoProvider>().assignTagsToTodos(ids, tags),
      (count) => I18n.current == AppLocale.en
          ? 'Added tags to $count tasks'
          : '已为 $count 个任务添加标签',
    );
  }

  Future<void> _showKanbanSettings(SettingsActionOrigin origin) async {
    if (!mounted || _kanbanReloadPending || !origin.isCurrent()) return;
    ModalRoute<dynamic>? sheetRoute;
    final next = await showAppModalSheet<TodoKanbanBoardConfig>(
      context: context,
      builder: (sheetContext) {
        sheetRoute = ModalRoute.of(sheetContext);
        return _KanbanSettingsSheet(config: _kanbanConfig);
      },
    );
    await sheetRoute?.completed;
    if (!mounted || next == null || !origin.isCurrent()) return;
    await _saveKanbanConfig(next, origin);
  }

  void _retryKanbanLoad(SettingsActionOrigin origin) {
    if (!mounted || !origin.isCurrent() || !_kanbanLoadFailed) return;
    setState(() => _kanbanLoadFailed = false);
    _queueKanbanReload();
  }

  Future<void> _deleteSelected() async {
    if (_batchSubmitting) return;
    final selectedCount = _visibleEditableSelection().length;
    if (selectedCount == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (context, _, _) => AppDialog(
          icon: const Icon(Icons.delete_outline),
          title: Text(TodoBoardUiCopy.deleteSelectedTasksTitle),
          content: Text(
            TodoBoardUiCopy.deleteSelectedTasksContent(selectedCount),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(TodoBoardUiCopy.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: Text(TodoBoardUiCopy.delete),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    await _runBatchAction(
      (ids) => context.read<TodoProvider>().deleteTodos(ids),
      (count) => TodoBoardUiCopy.batchDeleted(count),
    );
  }

  Future<void> _runBatchAction(
    Future<int> Function(Set<String> ids) action,
    String Function(int count) message,
  ) async {
    if (_batchSubmitting) return;
    final ids = _visibleEditableSelection();
    if (ids.isEmpty) return;
    setState(() => _batchSubmitting = true);
    try {
      final count = await action(ids);
      if (!mounted) return;
      _exitBatchMode();
      _showBatchSnack(() => message(count));
    } finally {
      if (mounted) {
        setState(() => _batchSubmitting = false);
      }
    }
  }

  Set<String> _visibleEditableSelection() {
    if (!mounted) return {};
    final todos = context.read<TodoProvider>();
    final preferences = context.read<PreferencesProvider?>();
    final share = context.read<ShareProvider>();
    return _derivedDataFor(todos, preferences).filteredTodos
        .where(
          (todo) =>
              _selectedTodoIds.contains(todo.id) &&
              share.canEdit(todo.workspaceId),
        )
        .map((todo) => todo.id)
        .toSet();
  }

  void _showBatchSnack(Object message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, _, _) => Text(
            message is ValueGetter<String> ? message() : message.toString(),
          ),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _localSaveSyncMessage(BuildContext context, {String? localSavedText}) {
    final text = localSavedText ?? TodoBoardUiCopy.localSavedText;
    try {
      return context.read<CloudSyncProvider>().localSaveSyncMessage(
        localSavedText: text,
      );
    } on ProviderNotFoundException {
      return text;
    }
  }

  static String _templateDisplayName(String name) {
    if (I18n.current == AppLocale.en) {
      return switch (name) {
        '工作' => 'Work',
        '个人' => 'Personal',
        '学习' => 'Study',
        '购物' => 'Shopping',
        '阅读清单' => 'Reading List',
        '健身' => 'Fitness',
        _ => name,
      };
    }
    return name;
  }

  // 保持单测静态检查兼容：void _showAddDialog()
  void _showAddDialog({EisenhowerQuadrant? initialQuadrant}) {
    final ai = context.read<AiService>();
    final titleCtrl = TextEditingController();
    SmartDateParseResult parsed = SmartDateParseResult.empty;
    // 从象限详情页进入时默认选中该象限；其余入口维持历史默认。
    var quadrant = initialQuadrant ?? EisenhowerQuadrant.notUrgentImportant;
    var priority = TodoPriority.none;
    String groupName = '';
    bool aiBusy = false;
    bool submitting = false;
    List<String> aiSubtasks = [];
    bool aiHasError = false;
    // 手动提醒：用户可显式选择一个提醒时间，不依赖标题 NLP 解析。
    // 解决"新建待办提醒不生效"——之前仅当标题含时间词时才设提醒，
    // 用户不写时间就没有提醒入口。
    bool enableReminder = false;
    TimeOfDay? reminderTime;

    showAppModalSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (ctx, _, _) {
            final s = ctx.read<ThemeProvider>().brand.strings;
            return AppSurfaceCard(
              margin: EdgeInsets.zero,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 24,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              child: AppSecondaryControlTheme(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              ctx,
                            ).colorScheme.onSurface.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        s.todoCreateTitle,
                        style: appSecondaryRouteTitleTextStyle(ctx),
                      ),
                      const SizedBox(height: 20),

                      TextField(
                        controller: titleCtrl,
                        decoration: InputDecoration(
                          hintText: TodoBoardUiCopy.taskHint,
                        ),
                        autofocus: true,
                        onChanged: (v) =>
                            setSt(() => parsed = SmartDateParser.parse(v)),
                      ),
                      if (parsed.isSuccess) ...[
                        const SizedBox(height: 8),
                        _SmartDatePreview(parsed: parsed),
                      ],
                      const SizedBox(height: 12),

                      // AI Action
                      if (ai.enabled)
                        Builder(
                          builder: (chipCtx) {
                            final chipCs = Theme.of(chipCtx).colorScheme;
                            final chipDark =
                                Theme.of(chipCtx).brightness == Brightness.dark;
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: ActionChip(
                                avatar: aiBusy
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        Icons.auto_awesome,
                                        size: 16,
                                        color: chipCs.primary,
                                      ),
                                label: Text(
                                  TodoBoardUiCopy.aiBreakdown,
                                  style: TextStyle(
                                    color: chipCs.primary,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                                backgroundColor: chipCs.primary.withValues(
                                  alpha: chipDark ? 0.18 : 0.10,
                                ),
                                side: BorderSide.none,
                                onPressed: aiBusy
                                    ? null
                                    : () async {
                                        if (titleCtrl.text.trim().isEmpty) {
                                          return;
                                        }
                                        setSt(() {
                                          aiBusy = true;
                                          aiHasError = false;
                                        });
                                        try {
                                          final list = await ai.breakDownTask(
                                            titleCtrl.text.trim(),
                                          );
                                          setSt(() => aiSubtasks = list);
                                        } catch (e) {
                                          setSt(() => aiHasError = true);
                                        } finally {
                                          setSt(() => aiBusy = false);
                                        }
                                      },
                              ),
                            );
                          },
                        ),

                      if (aiHasError)
                        Padding(
                          padding: const EdgeInsets.only(top: 8, left: 4),
                          child: Text(
                            TodoBoardUiCopy.aiBreakdownFailed,
                            style: TextStyle(
                              color: Theme.of(ctx).colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                        ),

                      if (aiSubtasks.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              ctx,
                            ).colorScheme.surface.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: aiSubtasks
                                .map(
                                  (t) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.subdirectory_arrow_right,
                                          size: 14,
                                          color: Theme.of(
                                            ctx,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            t,
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),

                      const SizedBox(height: 20),
                      Text(
                        TodoBoardUiCopy.listType,
                        style: appSecondaryControlLabelStyle(ctx),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: TodoListTemplates.all
                              .map(
                                (t) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    avatar: Icon(
                                      t.icon,
                                      size: 16,
                                      color: t.color,
                                    ),
                                    label: Text(_templateDisplayName(t.name)),
                                    selected: groupName == t.name,
                                    selectedColor: t.color.withValues(
                                      alpha: 0.12,
                                    ),
                                    checkmarkColor: t.color,
                                    labelStyle: TextStyle(
                                      color: groupName == t.name
                                          ? t.color
                                          : null,
                                    ),
                                    onSelected: (sel) => setSt(
                                      () => groupName = sel ? t.name : '',
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),

                      const SizedBox(height: 20),
                      Text(
                        TodoBoardUiCopy.filterQuadrant,
                        style: appSecondaryControlLabelStyle(ctx),
                      ),
                      const SizedBox(height: 12),
                      AppDropdownField<EisenhowerQuadrant>(
                        initialValue: quadrant,
                        labelText: TodoBoardUiCopy.filterQuadrant,
                        onTap: () => FocusScope.of(ctx).unfocus(),
                        items: [
                          DropdownMenuItem(
                            value: EisenhowerQuadrant.urgentImportant,
                            child: ValueListenableBuilder<AppLocale>(
                              valueListenable: I18n.localeListenable,
                              builder: (context, _, _) =>
                                  Text(TodoBoardUiCopy.quadrantQ1WithEmoji),
                            ),
                          ),
                          DropdownMenuItem(
                            value: EisenhowerQuadrant.notUrgentImportant,
                            child: ValueListenableBuilder<AppLocale>(
                              valueListenable: I18n.localeListenable,
                              builder: (context, _, _) =>
                                  Text(TodoBoardUiCopy.quadrantQ2WithEmoji),
                            ),
                          ),
                          DropdownMenuItem(
                            value: EisenhowerQuadrant.urgentNotImportant,
                            child: ValueListenableBuilder<AppLocale>(
                              valueListenable: I18n.localeListenable,
                              builder: (context, _, _) =>
                                  Text(TodoBoardUiCopy.quadrantQ3WithEmoji),
                            ),
                          ),
                          DropdownMenuItem(
                            value: EisenhowerQuadrant.notUrgentNotImportant,
                            child: ValueListenableBuilder<AppLocale>(
                              valueListenable: I18n.localeListenable,
                              builder: (context, _, _) =>
                                  Text(TodoBoardUiCopy.quadrantQ4WithEmoji),
                            ),
                          ),
                        ],
                        onChanged: (v) => setSt(() => quadrant = v!),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        TodoBoardUiCopy.priorityFlag,
                        style: appSecondaryControlLabelStyle(ctx),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final p in TodoPriority.values)
                            ChoiceChip(
                              label: Text(p.label),
                              selected: priority == p,
                              onSelected: (_) => setSt(() => priority = p),
                            ),
                        ],
                      ),

                      const SizedBox(height: 20),
                      Text(
                        TodoBoardUiCopy.reminder,
                        style: appSecondaryControlLabelStyle(ctx),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Switch(
                            value: enableReminder,
                            onChanged: (v) => setSt(() {
                              enableReminder = v;
                              if (v && reminderTime == null) {
                                reminderTime = TimeOfDay.now();
                              }
                            }),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              enableReminder && reminderTime != null
                                  ? TodoBoardUiCopy.reminderAt(
                                      reminderTime!.format(ctx),
                                    )
                                  : TodoBoardUiCopy.noReminder,
                              style: TextStyle(
                                color: enableReminder
                                    ? Theme.of(ctx).colorScheme.primary
                                    : null,
                              ),
                            ),
                          ),
                          if (enableReminder)
                            TextButton.icon(
                              icon: const Icon(Icons.access_time, size: 18),
                              label: Text(
                                reminderTime?.format(ctx) ??
                                    TodoBoardUiCopy.selectTime,
                              ),
                              onPressed: () async {
                                final picked = await showDialog<TimeOfDay>(
                                  context: ctx,
                                  builder: (dialogCtx) =>
                                      ValueListenableBuilder<AppLocale>(
                                        valueListenable: I18n.localeListenable,
                                        builder: (context, locale, _) =>
                                            Localizations.override(
                                              context: dialogCtx,
                                              locale: locale.flutterLocale,
                                              child: TimePickerDialog(
                                                initialTime:
                                                    reminderTime ??
                                                    TimeOfDay.now(),
                                                helpText: TodoBoardUiCopy
                                                    .selectReminderTime,
                                                cancelText:
                                                    TodoBoardUiCopy.cancel,
                                                confirmText: I18n.tr(
                                                  'action.confirm',
                                                ),
                                              ),
                                            ),
                                      ),
                                );
                                if (!ctx.mounted) return;
                                if (picked != null) {
                                  setSt(() => reminderTime = picked);
                                }
                              },
                            ),
                        ],
                      ),

                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: ElevatedButton(
                          onPressed: submitting
                              ? null
                              : () async {
                                  if (titleCtrl.text.trim().isEmpty) return;
                                  setSt(() => submitting = true);
                                  try {
                                    final notificationService = context
                                        .read<NotificationService?>();
                                    final todoProvider = context
                                        .read<TodoProvider>();
                                    final shareProvider = context
                                        .read<ShareProvider>();
                                    final authState = context
                                        .read<AuthProvider>()
                                        .state;
                                    final messenger = ScaffoldMessenger.of(
                                      context,
                                    );
                                    final sub = aiSubtasks
                                        .map((t) => Subtask(title: t))
                                        .toList();
                                    final draft =
                                        SmartTodoDraftBuilder.fromText(
                                          titleCtrl.text.trim(),
                                          defaultReminderKind:
                                              ReminderKind.push,
                                        );
                                    final workspaceId = groupName.isEmpty
                                        ? 'private'
                                        : todoProvider.workspaceForListGroup(
                                                groupName,
                                              ) ??
                                              'private';
                                    if (!shareProvider.canEdit(workspaceId)) {
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content:
                                              ValueListenableBuilder<AppLocale>(
                                                valueListenable:
                                                    I18n.localeListenable,
                                                builder: (context, _, _) =>
                                                    Text(
                                                      TodoBoardUiCopy
                                                          .sharedSpaceReadOnly,
                                                    ),
                                              ),
                                        ),
                                      );
                                      return;
                                    }
                                    var todo = draft.toTodo(
                                      quadrant: quadrant,
                                      priority: priority,
                                      listGroupName: groupName.isEmpty
                                          ? null
                                          : groupName,
                                      workspaceId: workspaceId,
                                      createdBy: authState.userId,
                                      updatedBy: authState.userId,
                                      subtasks: sub,
                                    );
                                    // 手动选择的提醒时间优先于标题 NLP 解析，
                                    // 确保用户即使不在标题里写时间也能设置提醒。
                                    if (enableReminder &&
                                        reminderTime != null) {
                                      final plan = ReminderPlan(
                                        enabled: true,
                                        rules: [
                                          ReminderRule(
                                            type: ReminderRuleType.absolute,
                                            kind: ReminderKind.push,
                                            hour: reminderTime!.hour,
                                            minute: reminderTime!.minute,
                                          ),
                                        ],
                                      );
                                      final legacy = plan
                                          .toLegacyReminderConfig(
                                            fallback: todo.reminder,
                                          );
                                      final now = DateTime.now();
                                      final base = todo.date;
                                      var mirroredAt = DateTime(
                                        base.year,
                                        base.month,
                                        base.day,
                                        reminderTime!.hour,
                                        reminderTime!.minute,
                                      );
                                      if (!mirroredAt.isAfter(now)) {
                                        mirroredAt = mirroredAt.add(
                                          const Duration(days: 1),
                                        );
                                      }
                                      // ignore: deprecated_member_use_from_same_package
                                      todo = todo.copyWith(
                                        reminder: legacy,
                                        reminderPlan: plan,
                                        hasReminder: true,
                                        reminderAt: mirroredAt,
                                      );
                                    }
                                    final hasReminder =
                                        draft.hasReminder ||
                                        (enableReminder &&
                                            reminderTime != null);
                                    if (hasReminder) {
                                      bool ready;
                                      try {
                                        ready = await preflightTodoReminderSave(
                                          ctx,
                                          todo: todo,
                                          notificationService:
                                              notificationService,
                                          issueTitleBuilder: () =>
                                              TodoBoardUiCopy
                                                  .reminderRegisterFailed,
                                          issueTitleCode: NotificationIssueTitle
                                              .taskRegistrationFailed,
                                        );
                                      } catch (error, stackTrace) {
                                        debugPrint(
                                          '[QuickTodoAction] reminder preflight failed: $error\n$stackTrace',
                                        );
                                        if (ctx.mounted) {
                                          messenger.showSnackBar(
                                            SnackBar(
                                              content:
                                                  ValueListenableBuilder<
                                                    AppLocale
                                                  >(
                                                    valueListenable:
                                                        I18n.localeListenable,
                                                    builder: (context, _, _) =>
                                                        Text(
                                                          '${I18n.tr('todo.quick_add.reminder_preflight_failed_prefix')}${userVisibleApiError(error, fallbackMessage: MainUiCopy.todoNotificationNotReady)}',
                                                        ),
                                                  ),
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                        return;
                                      }
                                      if (!ctx.mounted) return;
                                      if (!ready) {
                                        setSt(() => submitting = false);
                                        return;
                                      }
                                    }
                                    try {
                                      final waitForReminderSync = hasReminder;
                                      final reminderSyncResult =
                                          await todoProvider.addTodoWithResult(
                                            todo,
                                            waitForReminderSync:
                                                waitForReminderSync,
                                            reportReminderScheduleFailure:
                                                hasReminder,
                                          );
                                      final scheduleIssue = todoProvider
                                          .lastReminderScheduleIssue;
                                      final reminderSyncIssue =
                                          waitForReminderSync
                                          ? (reminderSyncResult?.issue ??
                                                scheduleIssue)
                                          : null;
                                      if (!mounted || !ctx.mounted) return;
                                      Navigator.pop(ctx);
                                      if (reminderSyncIssue != null) {
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: ValueListenableBuilder<AppLocale>(
                                              valueListenable:
                                                  I18n.localeListenable,
                                              builder: (context, _, _) => Text(
                                                TodoBoardUiCopy.localSavedWithoutReminder(
                                                  reminderSyncIssue,
                                                ),
                                              ),
                                            ),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      } else {
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content:
                                                ValueListenableBuilder<
                                                  AppLocale
                                                >(
                                                  valueListenable:
                                                      I18n.localeListenable,
                                                  builder: (context, _, _) =>
                                                      Text(
                                                        _localSaveSyncMessage(
                                                          context,
                                                          localSavedText:
                                                              TodoBoardUiCopy
                                                                  .localSavedText,
                                                        ),
                                                      ),
                                                ),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    } on StateError catch (e) {
                                      if (!ctx.mounted) return;
                                      final rawMessage = e.message;
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content:
                                              ValueListenableBuilder<AppLocale>(
                                                valueListenable:
                                                    I18n.localeListenable,
                                                builder: (context, _, _) =>
                                                    Text(
                                                      rawMessage.isEmpty
                                                          ? TodoBoardUiCopy
                                                                .createFailed
                                                          : rawMessage,
                                                    ),
                                              ),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    } catch (e) {
                                      if (!ctx.mounted) return;
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content:
                                              ValueListenableBuilder<AppLocale>(
                                                valueListenable:
                                                    I18n.localeListenable,
                                                builder: (context, _, _) =>
                                                    Text(
                                                      userVisibleApiError(
                                                        e,
                                                        fallbackMessage:
                                                            TodoBoardUiCopy
                                                                .createFailed,
                                                      ),
                                                    ),
                                              ),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (ctx.mounted) {
                                      setSt(() => submitting = false);
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                            textStyle: appSecondaryMenuItemTextStyle(ctx),
                          ),
                          child: submitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(TodoBoardUiCopy.addTask),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todoProvider = context.watch<TodoProvider>();
    final preferences = context.watch<PreferencesProvider?>();
    final settingsOrigin = SettingsActionOrigin(context);
    final habitProvider = context.watch<HabitProvider>();
    final goalProvider = context.watch<GoalProvider>();
    final shareProvider = context.watch<ShareProvider>();
    final s = context.watch<ThemeProvider>().brand.strings;
    final now = DateTime.now();
    final cloudSyncNotice = todoProvider.cloudSyncNotice;
    final derived = _derivedDataFor(todoProvider, preferences);
    final baseTodos = derived.baseTodos;
    final filteredTodos = derived.filteredTodos;
    final quadrantGroups = derived.quadrantGroups;
    final listGroups = derived.listGroups;
    final listGroupEntries = derived.listGroupEntries;
    final listRows = <_ListRowEntry>[
      for (final entry in listGroupEntries) ...[
        _ListRowEntry.header(entry.key),
        if (!_collapsedListGroups.contains(entry.key))
          for (final todo in entry.value) _ListRowEntry.todo(entry.key, todo),
      ],
    ];
    final canReorderList =
        !_batchMode &&
        _filter.sortOrder == TodoSortOrder.manual &&
        filteredTodos.length > 1 &&
        filteredTodos.every((todo) => shareProvider.canEdit(todo.workspaceId));
    final kanbanGroups = derived.kanbanGroups;
    final availableTags = derived.availableTags;
    final availableListGroups = derived.availableListGroups;
    final overdueCount = derived.overdueCount;
    final editableVisibleIds = filteredTodos
        .where((todo) => shareProvider.canEdit(todo.workspaceId))
        .map((todo) => todo.id)
        .toList();
    _selectedTodoIds.retainAll(editableVisibleIds);
    final allVisibleSelected =
        editableVisibleIds.isNotEmpty &&
        editableVisibleIds.every(_selectedTodoIds.contains);

    final isWidescreen =
        MediaQuery.widthOf(context) >= DesktopTokens.breakpointTwoColumn;
    final isWidestTier =
        MediaQuery.widthOf(context) >= DesktopTokens.breakpointThreeColumn;
    final viewContent = filteredTodos.isEmpty
        ? _TodoNoMatches(
            onClear: () {
              setState(
                () => _filter =
                    const TodoFilterState<EisenhowerQuadrant, TodoPriority>(),
              );
            },
          )
        : switch (_viewMode) {
            _TodoViewMode.matrix => SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: EisenhowerMatrix(
                quadrantGroups: quadrantGroups,
                fourColumn: isWidestTier,
                onQuadrantTap: (q) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => QuadrantListScreen(
                        quadrant: q,
                        filter: _filter,
                        onCreateTodo: (quadrant) =>
                            _showAddDialog(initialQuadrant: quadrant),
                      ),
                    ),
                  );
                },
                // 长按拖动待办到目标象限，松手即换象限。
                // 与 tile 级入口一致：只读成员不可拖拽换象限。
                canEditTodo: (todo) =>
                    context.read<ShareProvider>().canEdit(todo.workspaceId),
                onTodoQuadrantChanged: (todo, target) {
                  // 投放时点用最新权限复查，防止陈旧快照放行。
                  if (!context.read<ShareProvider>().canEdit(
                    todo.workspaceId,
                  )) {
                    return;
                  }
                  context.read<TodoProvider>().updateTodosQuadrant([
                    todo.id,
                  ], target);
                },
              ),
            ),
            _TodoViewMode.list => NotificationListener<ScrollNotification>(
              onNotification: _dismissSwipeActionsOnScroll,
              child: ValueListenableBuilder<int>(
                valueListenable: _swipeDismissSerial,
                builder: (context, swipeSerial, _) {
                  Widget itemBuilder(BuildContext context, int index) {
                    final row = listRows[index];
                    if (row.isHeader) {
                      return _ListGroupHeader(
                        key: ValueKey('list-header-${row.groupName}'),
                        groupName: row.groupName,
                        todos: listGroups[row.groupName]!,
                        expanded: !_collapsedListGroups.contains(row.groupName),
                        onToggle: () => setState(() {
                          if (_collapsedListGroups.contains(row.groupName)) {
                            _collapsedListGroups.remove(row.groupName);
                          } else {
                            _collapsedListGroups.add(row.groupName);
                          }
                        }),
                      );
                    }
                    final todo = row.todo!;
                    return _TodoTile(
                      key: ValueKey('list-todo-${todo.id}'),
                      todo: todo,
                      showArchived: _filter.includeArchived,
                      batchMode: _batchMode,
                      selected: _selectedTodoIds.contains(todo.id),
                      onToggleSelection: _toggleSelection,
                      onEnterBatchMode: (id) => _enterBatchMode(todoId: id),
                      swipeDismissSerial: swipeSerial,
                      swipeDismissListenable: _swipeDismissSerial,
                      trailing: canReorderList
                          ? ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_indicator),
                            )
                          : null,
                    );
                  }

                  final bottomListPadding = EdgeInsets.only(
                    bottom: _batchMode
                        ? 0.0
                        : 88.0 + MediaQuery.paddingOf(context).bottom,
                  );

                  if (!canReorderList) {
                    return ListView.builder(
                      key: const ValueKey('todo_list_scroll'),
                      controller: _listScrollController,
                      padding: bottomListPadding,
                      // ignore: deprecated_member_use
                      cacheExtent: 640,
                      itemCount: listRows.length,
                      itemBuilder: itemBuilder,
                    );
                  }
                  return ReorderableListView.builder(
                    key: const ValueKey('todo_list_scroll'),
                    scrollController: _listScrollController,
                    padding: bottomListPadding,
                    // ignore: deprecated_member_use
                    cacheExtent: 640,
                    buildDefaultDragHandles: false,
                    itemCount: listRows.length,
                    itemBuilder: itemBuilder,
                    // ignore: deprecated_member_use
                    onReorder: (oldIndex, newIndex) {
                      _reorderFlatListRows(listRows, oldIndex, newIndex);
                    },
                  );
                },
              ),
            ),
            _TodoViewMode.kanban => ValueListenableBuilder<int>(
              valueListenable: _swipeDismissSerial,
              builder: (context, swipeSerial, _) => _TodoKanbanView(
                config: _kanbanConfig,
                kanbanGroups: kanbanGroups,
                batchMode: _batchMode,
                selectedTodoIds: _selectedTodoIds,
                onToggleSelection: _toggleSelection,
                onEnterBatchMode: (id) => _enterBatchMode(todoId: id),
                swipeDismissSerial: swipeSerial,
                onScrollStart: _dismissSwipeActionsOnScroll,
              ),
            ),
          };
    final widescreenBody = Column(
      children: [
        if (cloudSyncNotice != null)
          _TodoCloudSyncNoticeBanner(notice: cloudSyncNotice),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _TodoViewSwitcher(
                      selected: _viewMode,
                      onChanged: (mode) => setState(() => _viewMode = mode),
                    ),
                    Expanded(child: viewContent),
                  ],
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1),
              SizedBox(
                width: DesktopTokens.rightSidebarWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TodoTodaySummaryCard(
                      todos: baseTodos,
                      habits: habitProvider.habits,
                      activeGoalCount: goalProvider.activeGoals.length,
                      now: now,
                      onTodayTap: () => _setFilter(
                        const TodoFilterState(
                          todayOverview: true,
                          completion: TodoCompletionFilter.all,
                        ),
                      ),
                      onOverdueTap: () => _setFilter(
                        const TodoFilterState(
                          due: TodoDueFilter.overdue,
                          completion: TodoCompletionFilter.active,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(
                          bottom: DesignTokens.spaceLg,
                        ),
                        child: _TodoFilterBar(
                          filter: _filter,
                          totalCount: baseTodos.length,
                          filteredCount: filteredTodos.length,
                          availableTags: availableTags,
                          availableListGroups: availableListGroups,
                          onChanged: _setFilter,
                          onClear: _clearFilter,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final textScaler = MediaQuery.textScalerOf(context);
    final screenWidth = MediaQuery.sizeOf(context).width;

    final appBarTitleText = _batchMode
        ? TodoBoardUiCopy.batchModeSelected(_selectedTodoIds.length)
        : s.todoTitle;

    final appBarActions = <Widget>[
      if (_batchMode)
        IconButton(
          tooltip: TodoBoardUiCopy.selectAllTooltip(allVisibleSelected),
          onPressed: editableVisibleIds.isEmpty
              ? null
              : () => _selectAllVisible(editableVisibleIds),
          icon: Icon(
            allVisibleSelected
                ? Icons.deselect_outlined
                : Icons.select_all_outlined,
          ),
        )
      else ...[
        if (_viewMode == _TodoViewMode.kanban)
          IconButton(
            tooltip: _kanbanLoadFailed
                ? TodoBoardUiCopy.kanbanRetryLoadTooltip
                : TodoBoardUiCopy.kanbanColumnSettingsTooltip,
            onPressed: _kanbanReloadPending
                ? _kanbanLoadFailed && _kanbanAccountAvailable
                      ? () => _retryKanbanLoad(settingsOrigin)
                      : null
                : () => _showKanbanSettings(settingsOrigin),
            icon: const Icon(Icons.tune_outlined),
          ),
        IconButton(
          tooltip: TodoBoardUiCopy.batchActionsTooltip,
          onPressed: filteredTodos.isEmpty
              ? null
              : () => _enterBatchMode(switchToList: true),
          icon: const Icon(Icons.checklist_outlined),
        ),
        if (overdueCount > 0)
          TextButton.icon(
            onPressed: () async {
              await context.read<TodoProvider>().postponeOverdue(
                DateTime.now(),
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: ValueListenableBuilder<AppLocale>(
                    valueListenable: I18n.localeListenable,
                    builder: (context, _, _) => Text(
                      TodoBoardUiCopy.postponeOverdueFeedback(overdueCount),
                    ),
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.update_outlined, size: 18),
            label: Text(TodoBoardUiCopy.postponeAction),
          ),
      ],
    ];

    final titleStyle = Theme.of(context).appBarTheme.titleTextStyle ??
        const TextStyle(
          fontSize: DesignTokens.fontSizeMd,
          fontWeight: FontWeight.normal,
        );
    final titlePainter = TextPainter(
      text: TextSpan(
        text: appBarTitleText,
        style: titleStyle,
      ),
      textDirection: Directionality.of(context),
      textScaler: textScaler,
    )..layout();
    final titleWidth = titlePainter.width;
    titlePainter.dispose();

    double estimatedActionsWidth = 0;
    if (_batchMode) {
      estimatedActionsWidth = 48;
    } else {
      if (_viewMode == _TodoViewMode.kanban) estimatedActionsWidth += 48;
      estimatedActionsWidth += 48;
      if (overdueCount > 0) {
        final textTheme = Theme.of(context).textTheme;
        final textButtonThemeStyle = Theme.of(context).textButtonTheme.style;
        final textButtonResolvedStyle =
            textButtonThemeStyle?.textStyle?.resolve(const <WidgetState>{});
        final postponeTextStyle =
            (textTheme.labelLarge ?? const TextStyle(fontSize: 14))
                .merge(textButtonResolvedStyle);
        final postponePainter = TextPainter(
          text: TextSpan(
            text: TodoBoardUiCopy.postponeAction,
            style: postponeTextStyle,
          ),
          textDirection: Directionality.of(context),
          textScaler: textScaler,
        )..layout();
        final buttonPadding =
            textButtonThemeStyle?.padding?.resolve(const <WidgetState>{});
        final buttonPaddingHorizontal = buttonPadding?.horizontal ?? 28.0;
        const iconWidth = 18.0;
        const iconSpacing = 8.0;
        final postponeWidth = postponePainter.width +
            iconWidth +
            iconSpacing +
            buttonPaddingHorizontal;
        postponePainter.dispose();
        estimatedActionsWidth += postponeWidth;
      }
    }

    final leadingSpace = _batchMode ? 48.0 : 16.0;
    final singleRowNeededWidth =
        titleWidth + estimatedActionsWidth + leadingSpace + 16.0;
    final shouldWrapAppBarActions = singleRowNeededWidth > screenWidth;

    final scaledTitleHeight =
        textScaler.scale(DesignTokens.fontSizeMd) + 16.0;
    final effectiveToolbarHeight = scaledTitleHeight > kToolbarHeight
        ? scaledTitleHeight
        : kToolbarHeight;
    final bottomActionsHeight = textScaler.scale(14.0) + 24.0;
    final effectiveBottomHeight =
        bottomActionsHeight > 48.0 ? bottomActionsHeight : 48.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        toolbarHeight: effectiveToolbarHeight,
        leading: _batchMode
            ? IconButton(
                tooltip: TodoBoardUiCopy.exitBatchModeTooltip,
                onPressed: _exitBatchMode,
                icon: const Icon(Icons.close),
              )
            : null,
        title: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: Text(
            appBarTitleText,
            textScaler: textScaler,
          ),
        ),
        actions: shouldWrapAppBarActions ? null : appBarActions,
        bottom: shouldWrapAppBarActions
            ? PreferredSize(
                preferredSize: Size.fromHeight(effectiveBottomHeight),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: appBarActions,
                      ),
                    ),
                  ),
                ),
              )
            : null,
      ),
      body: baseTodos.isEmpty
          ? Column(
              children: [
                if (!_batchMode && cloudSyncNotice != null)
                  _TodoCloudSyncNoticeBanner(notice: cloudSyncNotice),
                Expanded(
                  child: EmptyState(
                    icon: Icons.check_circle_outline,
                    message: s.todoEmpty,
                    actionLabel: s.todoAddAction,
                    onAction: _showAddDialog,
                    minCardHeight: EmptyState.defaultMinCardHeight,
                  ),
                ),
              ],
            )
          : isWidescreen && !_batchMode
          ? widescreenBody
          : LayoutBuilder(
              builder: (context, constraints) => Column(
                children: [
                  if (!_batchMode)
                    _TodoViewSwitcher(
                      selected: _viewMode,
                      onChanged: (mode) => setState(() => _viewMode = mode),
                    ),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * 0.62,
                    ),
                    child: SingleChildScrollView(
                      key: const ValueKey('todo_header_scroll'),
                      child: Column(
                        children: [
                          if (!_batchMode)
                            _TodoTodaySummaryCard(
                              todos: baseTodos,
                              habits: habitProvider.habits,
                              activeGoalCount: goalProvider.activeGoals.length,
                              now: now,
                              onTodayTap: () => _setFilter(
                                const TodoFilterState(
                                  todayOverview: true,
                                  completion: TodoCompletionFilter.all,
                                ),
                              ),
                              onOverdueTap: () => _setFilter(
                                const TodoFilterState(
                                  due: TodoDueFilter.overdue,
                                  completion: TodoCompletionFilter.active,
                                ),
                              ),
                            ),
                          if (!_batchMode && cloudSyncNotice != null)
                            _TodoCloudSyncNoticeBanner(notice: cloudSyncNotice),
                          _TodoFilterBar(
                            filter: _filter,
                            totalCount: baseTodos.length,
                            filteredCount: filteredTodos.length,
                            availableTags: availableTags,
                            availableListGroups: availableListGroups,
                            onChanged: _setFilter,
                            onClear: _clearFilter,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(child: viewContent),
                ],
              ),
            ),
      bottomNavigationBar: _batchMode
          ? _TodoBatchActionBar(
              selectedCount: _selectedTodoIds.length,
              submitting: _batchSubmitting,
              onComplete: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : _completeSelected,
              onReopen: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : _reopenSelected,
              onMove: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : _moveSelected,
              onPriority: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : _setSelectedPriority,
              onRescheduleDueDate: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : _rescheduleSelectedDueDate,
              onAssignList: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : () => _assignSelectedList(availableListGroups),
              onAssignTags: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : () => _assignSelectedTags(availableTags),
              onDelete: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : _deleteSelected,
            )
          : null,
      floatingActionButton: _batchMode
          ? null
          : FloatingActionButton(
              heroTag: 'todo_add_fab',
              onPressed: _showAddDialog,
              child: const Icon(Icons.add),
            ),
    );
  }

  void _reorderFlatListRows(
    List<_ListRowEntry> rows,
    int oldIndex,
    int newIndex,
  ) {
    if (oldIndex < 0 || oldIndex >= rows.length) return;
    final source = rows[oldIndex];
    if (source.isHeader) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex >= rows.length) return;
    final target = rows[newIndex];
    if (target.isHeader || target.groupName != source.groupName) return;

    final groupTodos = rows
        .where((row) => !row.isHeader && row.groupName == source.groupName)
        .map((row) => row.todo!)
        .toList();
    final moved = groupTodos.indexWhere((todo) => todo.id == source.todo!.id);
    final targetIndex = groupTodos.indexWhere(
      (todo) => todo.id == target.todo!.id,
    );
    if (moved < 0 || targetIndex < 0 || moved == targetIndex) return;
    final todo = groupTodos.removeAt(moved);
    final insertAt = targetIndex.clamp(0, groupTodos.length);
    groupTodos.insert(insertAt, todo);
    context.read<TodoProvider>().reorderVisibleTodos(
      groupTodos.map((todo) => todo.id).toList(),
    );
  }
}

class _SmartDatePreview extends StatelessWidget {
  final SmartDateParseResult parsed;

  const _SmartDatePreview({required this.parsed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              TodoBoardUiCopy.detectedDate(
                AppDateFormat.smartDate(
                  context,
                  parsed.dateTime!,
                  includeTime: parsed.hasTimeOfDay,
                ),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: cs.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodoViewSwitcher extends StatelessWidget {
  final _TodoViewMode selected;
  final ValueChanged<_TodoViewMode> onChanged;

  const _TodoViewSwitcher({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labels = [
            TodoBoardUiCopy.viewMatrix,
            TodoBoardUiCopy.viewList,
            TodoBoardUiCopy.viewKanban,
          ];
          final textStyle =
              Theme.of(context).textTheme.labelLarge ??
              const TextStyle(fontSize: 14);
          var labelWidth = 0.0;
          for (final label in labels) {
            final painter = TextPainter(
              text: TextSpan(text: label, style: textStyle),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            if (painter.width > labelWidth) labelWidth = painter.width;
            painter.dispose();
          }
          final showIcons = constraints.maxWidth >= (labelWidth + 46) * 3;
          final horizontalPadding = showIcons ? 8.0 : 4.0;
          final requiredWidth =
              (labelWidth + horizontalPadding * 2 + 4 + (showIcons ? 26 : 0)) *
              3;
          final needsScroll = constraints.maxWidth < requiredWidth;
          Widget label(String value) =>
              Text(value, maxLines: 1, softWrap: false);
          final control = SizedBox(
            width: needsScroll ? requiredWidth : constraints.maxWidth,
            child: SegmentedButton<_TodoViewMode>(
              key: const ValueKey('todo_view_switcher'),
              expandedInsets: EdgeInsets.zero,
              style: ButtonStyle(
                textStyle: WidgetStatePropertyAll(textStyle),
                minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: horizontalPadding),
                ),
              ),
              segments: [
                ButtonSegment(
                  value: _TodoViewMode.matrix,
                  icon: showIcons
                      ? const Icon(Icons.grid_view, size: 18)
                      : null,
                  label: label(labels[0]),
                ),
                ButtonSegment(
                  value: _TodoViewMode.list,
                  icon: showIcons
                      ? const Icon(Icons.view_list_outlined, size: 18)
                      : null,
                  label: label(labels[1]),
                ),
                ButtonSegment(
                  value: _TodoViewMode.kanban,
                  icon: showIcons
                      ? const Icon(Icons.view_kanban_outlined, size: 18)
                      : null,
                  label: label(labels[2]),
                ),
              ],
              selected: {selected},
              showSelectedIcon: false,
              onSelectionChanged: (values) => onChanged(values.first),
            ),
          );
          return needsScroll
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: control,
                )
              : control;
        },
      ),
    );
  }
}

class _TodoTodaySummaryCard extends StatelessWidget {
  final List<TodoItem> todos;
  final List<Habit> habits;
  final int activeGoalCount;
  final DateTime now;
  final VoidCallback? onTodayTap;
  final VoidCallback? onOverdueTap;

  const _TodoTodaySummaryCard({
    required this.todos,
    required this.habits,
    required this.activeGoalCount,
    required this.now,
    this.onTodayTap,
    this.onOverdueTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime(now.year, now.month, now.day);
    final visibleTodos = todos
        .where(
          (todo) => CompletionVisibilityPolicy.shouldShowInToday(todo, now),
        )
        .toList(growable: false);
    final todoCount = visibleTodos.length;
    final todayDone = todos.where((todo) {
      if (!todo.isCompleted) return false;
      final completedAt = todo.completedAt;
      if (completedAt == null) return false;
      return CompletionVisibilityPolicy.dateOnly(completedAt) == today;
    }).length;
    final todayTotal = todayDone + todoCount;
    final overdueCount = todos.where((todo) => todo.isOverdue).length;
    final activeDailyHabits = habits.where((habit) => habit.activeForDate(now));
    final dailyCount = activeDailyHabits.length;
    final dailyDone = activeDailyHabits
        .where((habit) => habit.isCompletedForDate(now))
        .length;
    final dailyRemaining = (dailyCount - dailyDone).clamp(0, dailyCount);
    final remaining = dailyRemaining + todoCount + activeGoalCount;
    final urgentCount = todos
        .where(
          (todo) =>
              !todo.isCompleted &&
              (todo.priority == TodoPriority.urgent ||
                  todo.quadrant == EisenhowerQuadrant.urgentImportant),
        )
        .length;
    final chips = <_TodoSummaryChipData>[
      _TodoSummaryChipData(
        icon: Icons.check_circle_outline,
        label: TodoBoardUiCopy.todaySummaryChipToday,
        value: '$todayDone/$todayTotal',
        color: cs.primary,
        onTap: onTodayTap,
        tooltip: TodoBoardUiCopy.todaySummaryChipFilterTodayTooltip,
      ),
      _TodoSummaryChipData(
        icon: Icons.priority_high_outlined,
        label: TodoBoardUiCopy.todaySummaryChipKey,
        value: '$urgentCount',
        color: DesignTokens.defaultWarning,
      ),
      _TodoSummaryChipData(
        icon: Icons.warning_amber_outlined,
        label: TodoBoardUiCopy.todaySummaryChipOverdue,
        value: '$overdueCount',
        color: cs.error,
        onTap: onOverdueTap,
        tooltip: TodoBoardUiCopy.todaySummaryChipFilterOverdueTooltip,
      ),
    ];

    return AppSurfaceCard(
      key: const ValueKey('todo_today_summary_card'),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      borderRadius: BorderRadius.circular(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 420;
          final header = Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.today_outlined, color: cs.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TodoBoardUiCopy.todayRemainingTasks(remaining),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      TodoBoardUiCopy.todaySummaryBreakdown(
                        dailyRemaining,
                        todoCount,
                        activeGoalCount,
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final chipRow = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips
                .map((chip) => _TodoSummaryChip(data: chip))
                .toList(),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [header, const SizedBox(height: 12), chipRow],
            );
          }
          return Row(
            children: [
              Expanded(child: header),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: chipRow,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TodoCloudSyncNoticeBanner extends StatelessWidget {
  final TodoCloudSyncNotice notice;

  const _TodoCloudSyncNoticeBanner({required this.notice});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isError = notice.level == TodoCloudSyncNoticeLevel.error;
    final isInfo = notice.level == TodoCloudSyncNoticeLevel.info;
    final warningAccent = isDark
        ? const Color(0xFFF2B84B)
        : DesignTokens.defaultWarning;
    final background = isError
        ? cs.errorContainer.withValues(alpha: 0.72)
        : isInfo
        ? cs.primaryContainer.withValues(alpha: 0.64)
        : Color.alphaBlend(
            warningAccent.withValues(alpha: isDark ? 0.16 : 0.10),
            cs.surface,
          );
    final foreground = isError
        ? cs.onErrorContainer
        : isInfo
        ? cs.onPrimaryContainer
        : cs.onSurface;
    final iconColor = isError || isInfo ? foreground : warningAccent;
    final borderColor = isError
        ? cs.error.withValues(alpha: 0.22)
        : isInfo
        ? cs.primary.withValues(alpha: 0.2)
        : warningAccent.withValues(alpha: isDark ? 0.34 : 0.28);
    final icon = isError
        ? Icons.cloud_off_outlined
        : isInfo
        ? Icons.cloud_queue_outlined
        : Icons.sync_problem_outlined;
    final text = switch (notice.level) {
      TodoCloudSyncNoticeLevel.error => TodoBoardUiCopy.syncNoticeError(
        notice.message,
      ),
      TodoCloudSyncNoticeLevel.warning => TodoBoardUiCopy.syncNoticeWarning(
        notice.message,
      ),
      TodoCloudSyncNoticeLevel.info => TodoBoardUiCopy.syncNoticeInfo(
        notice.message,
      ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: foreground,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodoSummaryChipData {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;
  final String? tooltip;

  const _TodoSummaryChipData({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
    this.tooltip,
  });
}

class _TodoSummaryChip extends StatelessWidget {
  final _TodoSummaryChipData data;

  const _TodoSummaryChip({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isInteractive = data.onTap != null;
    final borderRadius = BorderRadius.circular(12);
    final chipBg = Color.alphaBlend(
      data.color.withValues(alpha: isDark ? 0.16 : 0.10),
      cs.surface,
    );
    final chipIconColor = appReadableForeground(chipBg, data.color);

    final chipContent = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: 86,
        maxWidth:
            TodoBoardUiCopy.isEn ||
                MediaQuery.textScalerOf(context).scale(1) > 1.2
            ? 168
            : 118,
      ),
      child: Container(
        constraints: BoxConstraints(minHeight: isInteractive ? 44.0 : 0.0),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        alignment: Alignment.center,
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            Icon(data.icon, size: 15, color: chipIconColor),
            Text(
              data.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.68),
              ),
            ),
            Text(
              data.value,
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.normal,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );

    if (!isInteractive) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: data.color.withValues(alpha: 0.1),
          borderRadius: borderRadius,
          border: Border.all(color: data.color.withValues(alpha: 0.16)),
        ),
        child: chipContent,
      );
    }

    final interactiveChip = Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: data.color.withValues(alpha: 0.1),
          borderRadius: borderRadius,
          border: Border.all(color: data.color.withValues(alpha: 0.16)),
        ),
        child: InkWell(
          onTap: data.onTap,
          borderRadius: borderRadius,
          child: Semantics(
            button: true,
            label: TodoBoardUiCopy.chipSemantics(data.label, data.value),
            child: chipContent,
          ),
        ),
      ),
    );

    if (data.tooltip != null) {
      return Tooltip(message: data.tooltip!, child: interactiveChip);
    }
    return interactiveChip;
  }
}

class _TodoFilterBar extends StatelessWidget {
  final TodoFilterState<EisenhowerQuadrant, TodoPriority> filter;
  final int totalCount;
  final int filteredCount;
  final List<String> availableTags;
  final List<String> availableListGroups;
  final ValueChanged<TodoFilterState<EisenhowerQuadrant, TodoPriority>>
  onChanged;
  final VoidCallback onClear;

  const _TodoFilterBar({
    required this.filter,
    required this.totalCount,
    required this.filteredCount,
    required this.availableTags,
    required this.availableListGroups,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = filter.hasActiveFilters;
    final titleColor = active ? cs.onSurface : cs.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final titleRow = ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.filter_alt_outlined,
                      size: 18,
                      color: titleColor,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        TodoBoardUiCopy.customViewTitle(
                          filteredCount,
                          totalCount,
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          color: titleColor,
                        ),
                      ),
                    ),
                  ],
                ),
              );

              return SizedBox(
                width: constraints.maxWidth,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 4,
                  children: [
                    titleRow,
                    if (active)
                      TextButton.icon(
                        onPressed: onClear,
                        style: TextButton.styleFrom(
                          foregroundColor: cs.onSurface,
                        ),
                        icon: const Icon(Icons.close, size: 16),
                        label: Text(TodoBoardUiCopy.clear),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _TodoSearchAndSortStrip(
            query: filter.query,
            sortOrder: filter.sortOrder,
            onQueryChanged: (q) => onChanged(filter.copyWith(query: q)),
            onSortChanged: (s) => onChanged(filter.copyWith(sortOrder: s)),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (filter.todayOverview) ...[
                  FilterChip(
                    selected: true,
                    showCheckmark: false,
                    avatar: const Icon(Icons.today_outlined, size: 16),
                    label: Text(TodoBoardUiCopy.filterTodayOverview),
                    onSelected: (_) =>
                        onChanged(filter.copyWith(todayOverview: false)),
                    onDeleted: () =>
                        onChanged(filter.copyWith(todayOverview: false)),
                    deleteIcon: const Icon(Icons.close, size: 14),
                  ),
                  const SizedBox(width: 8),
                ],
                _TodoQuickFilterChip(
                  label: TodoBoardUiCopy.filterToday,
                  icon: Icons.today_outlined,
                  selected: filter.due == TodoDueFilter.dueToday,
                  onPressed: () => onChanged(
                    filter.copyWith(
                      todayOverview: false,
                      due: filter.due == TodoDueFilter.dueToday
                          ? TodoDueFilter.all
                          : TodoDueFilter.dueToday,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _TodoQuickFilterChip(
                  label: TodoBoardUiCopy.filterOverdue,
                  icon: Icons.warning_amber_outlined,
                  selected: filter.due == TodoDueFilter.overdue,
                  onPressed: () => onChanged(
                    filter.copyWith(
                      todayOverview: false,
                      due: filter.due == TodoDueFilter.overdue
                          ? TodoDueFilter.all
                          : TodoDueFilter.overdue,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _TodoQuickFilterChip(
                  label: TodoBoardUiCopy.filterNext7Days,
                  icon: Icons.date_range_outlined,
                  selected: filter.due == TodoDueFilter.next7Days,
                  onPressed: () => onChanged(
                    filter.copyWith(
                      todayOverview: false,
                      due: filter.due == TodoDueFilter.next7Days
                          ? TodoDueFilter.all
                          : TodoDueFilter.next7Days,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _TodoQuickFilterChip(
                  label: TodoBoardUiCopy.filterCompleted,
                  icon: Icons.check_circle_outline,
                  selected: filter.completion == TodoCompletionFilter.completed,
                  onPressed: () => onChanged(
                    filter.copyWith(
                      completion:
                          filter.completion == TodoCompletionFilter.completed
                          ? TodoCompletionFilter.all
                          : TodoCompletionFilter.completed,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _TodoQuickFilterChip(
                  label: TodoBoardUiCopy.filterIncludeArchived,
                  icon: Icons.inventory_2_outlined,
                  selected: filter.includeArchived,
                  onPressed: () => onChanged(
                    filter.copyWith(includeArchived: !filter.includeArchived),
                  ),
                ),
                const SizedBox(width: 10),
                _TodoFilterMenu<EisenhowerQuadrant>(
                  icon: Icons.grid_view_outlined,
                  label: filter.quadrant == null
                      ? TodoBoardUiCopy.filterQuadrant
                      : _quadrantLabel(filter.quadrant!),
                  selected: filter.quadrant != null,
                  selectedValue: filter.quadrant,
                  options: [
                    _TodoFilterOption(
                      labelBuilder: () => TodoBoardUiCopy.filterAllQuadrants,
                    ),
                    for (final quadrant in EisenhowerQuadrant.values)
                      _TodoFilterOption(
                        labelBuilder: () => _quadrantLabel(quadrant),
                        value: quadrant,
                      ),
                  ],
                  onSelected: (value) =>
                      onChanged(filter.copyWith(quadrant: value)),
                ),
                const SizedBox(width: 8),
                _TodoFilterMenu<TodoPriority>(
                  icon: Icons.flag_outlined,
                  label: filter.priority == null
                      ? TodoBoardUiCopy.filterPriority
                      : filter.priority!.label,
                  selected: filter.priority != null,
                  selectedValue: filter.priority,
                  options: [
                    _TodoFilterOption(
                      labelBuilder: () => TodoBoardUiCopy.filterAllPriorities,
                    ),
                    for (final priority in TodoPriority.values)
                      _TodoFilterOption(
                        labelBuilder: () => priority.label,
                        value: priority,
                      ),
                  ],
                  onSelected: (value) =>
                      onChanged(filter.copyWith(priority: value)),
                ),
                const SizedBox(width: 8),
                _TodoFilterMenu<TodoDueFilter>(
                  icon: Icons.event_outlined,
                  label: filter.due == TodoDueFilter.all
                      ? TodoBoardUiCopy.filterDate
                      : _dueFilterLabel(filter.due),
                  selected: filter.due != TodoDueFilter.all,
                  selectedValue: filter.due,
                  options: [
                    for (final due in TodoDueFilter.values)
                      _TodoFilterOption(
                        labelBuilder: () => _dueFilterLabel(due),
                        value: due,
                      ),
                  ],
                  onSelected: (value) => onChanged(
                    filter.copyWith(todayOverview: false, due: value),
                  ),
                ),
                const SizedBox(width: 8),
                _TodoFilterMenu<TodoCompletionFilter>(
                  icon: Icons.check_circle_outline,
                  label: filter.completion == TodoCompletionFilter.all
                      ? TodoBoardUiCopy.filterCompletionStatus
                      : _completionFilterLabel(filter.completion),
                  selected: filter.completion != TodoCompletionFilter.all,
                  selectedValue: filter.completion,
                  options: [
                    for (final completion in TodoCompletionFilter.values)
                      _TodoFilterOption(
                        labelBuilder: () => _completionFilterLabel(completion),
                        value: completion,
                      ),
                  ],
                  onSelected: (value) =>
                      onChanged(filter.copyWith(completion: value)),
                ),
                if (availableTags.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _TodoFilterMenu<String>(
                    icon: Icons.sell_outlined,
                    label: filter.tag == null
                        ? TodoBoardUiCopy.filterTag
                        : '#${filter.tag}',
                    selected: filter.tag != null,
                    selectedValue: filter.tag,
                    options: [
                      _TodoFilterOption(
                        labelBuilder: () => TodoBoardUiCopy.filterAllTags,
                      ),
                      for (final tag in availableTags)
                        _TodoFilterOption(label: '#$tag', value: tag),
                    ],
                    onSelected: (value) =>
                        onChanged(filter.copyWith(tag: value)),
                  ),
                ],
                if (availableListGroups.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _TodoFilterMenu<String>(
                    icon: Icons.folder_outlined,
                    label: filter.listGroupName ?? TodoBoardUiCopy.filterList,
                    selected: filter.listGroupName != null,
                    selectedValue: filter.listGroupName,
                    options: [
                      _TodoFilterOption(
                        labelBuilder: () => TodoBoardUiCopy.filterAllLists,
                      ),
                      for (final group in availableListGroups)
                        _TodoFilterOption(label: group, value: group),
                    ],
                    onSelected: (value) =>
                        onChanged(filter.copyWith(listGroupName: value)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodoQuickFilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  const _TodoQuickFilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      showCheckmark: false,
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onSelected: (_) => onPressed(),
    );
  }
}

class _TodoFilterMenu<T> extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final T? selectedValue;
  final List<_TodoFilterOption<T>> options;
  final ValueChanged<T?> onSelected;

  const _TodoFilterMenu({
    required this.icon,
    required this.label,
    required this.selected,
    required this.selectedValue,
    required this.options,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.primary : cs.onSurfaceVariant;

    return PopupMenuButton<_TodoFilterOption<T>>(
      tooltip: label,
      position: PopupMenuPosition.under,
      onSelected: (option) => onSelected(option.value),
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem(
            value: option,
            child: ValueListenableBuilder<AppLocale>(
              valueListenable: I18n.localeListenable,
              builder: (context, _, _) => Row(
                children: [
                  Expanded(
                    child: AppSecondaryMenuText(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (option.value == selectedValue)
                    Icon(Icons.check, size: 16, color: cs.primary),
                ],
              ),
            ),
          ),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.1)
              : cs.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? cs.primary.withValues(alpha: 0.35)
                : cs.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: color),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}

class _TodoFilterOption<T> {
  final String Function() labelBuilder;
  final T? value;

  _TodoFilterOption({
    String? label,
    String Function()? labelBuilder,
    this.value,
  }) : labelBuilder = labelBuilder ?? (() => label ?? '');

  String get label => labelBuilder();
}

class _TodoNoMatches extends StatelessWidget {
  final VoidCallback onClear;

  const _TodoNoMatches({required this.onClear});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt_off_outlined,
              size: 44,
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              TodoBoardUiCopy.noMatchingTasks,
              style: TextStyle(fontSize: 16, color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              TodoBoardUiCopy.adjustFiltersHint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.close, size: 16),
              label: Text(TodoBoardUiCopy.clearFilters),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodoBatchActionBar extends StatelessWidget {
  final int selectedCount;
  final bool submitting;
  final Future<void> Function()? onComplete;
  final Future<void> Function()? onReopen;
  final Future<void> Function(EisenhowerQuadrant quadrant)? onMove;
  final Future<void> Function(TodoPriority priority)? onPriority;
  final Future<void> Function()? onRescheduleDueDate;
  final Future<void> Function()? onAssignList;
  final Future<void> Function()? onAssignTags;
  final Future<void> Function()? onDelete;

  const _TodoBatchActionBar({
    required this.selectedCount,
    required this.submitting,
    required this.onComplete,
    required this.onReopen,
    required this.onMove,
    required this.onPriority,
    this.onRescheduleDueDate,
    this.onAssignList,
    this.onAssignTags,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = selectedCount > 0 && !submitting;
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(
            top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
          ),
          boxShadow: DesignTokens.shadowXs,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    submitting
                        ? TodoBoardUiCopy.batchProcessing
                        : TodoBoardUiCopy.batchSelected(selectedCount),
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.primary,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: enabled ? onComplete : null,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(TodoBoardUiCopy.batchComplete),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: enabled ? onReopen : null,
                  icon: const Icon(Icons.undo_outlined, size: 18),
                  label: Text(TodoBoardUiCopy.batchRestore),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<EisenhowerQuadrant>(
                  tooltip: TodoBoardUiCopy.batchMoveTo,
                  enabled: enabled && onMove != null,
                  onSelected: (quadrant) => onMove?.call(quadrant),
                  itemBuilder: (context) => [
                    for (final quadrant in EisenhowerQuadrant.values)
                      PopupMenuItem(
                        value: quadrant,
                        child: ValueListenableBuilder<AppLocale>(
                          valueListenable: I18n.localeListenable,
                          builder: (context, _, _) => Row(
                            children: [
                              Icon(
                                Icons.circle,
                                size: 10,
                                color: _quadrantColor(quadrant),
                              ),
                              const SizedBox(width: 8),
                              AppSecondaryMenuText(_quadrantLabel(quadrant)),
                            ],
                          ),
                        ),
                      ),
                  ],
                  child: _BatchMenuButton(
                    icon: Icons.drive_file_move_outline,
                    label: TodoBoardUiCopy.batchMoveTo,
                    enabled: enabled && onMove != null,
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<TodoPriority>(
                  tooltip: TodoBoardUiCopy.batchPriority,
                  enabled: enabled && onPriority != null,
                  onSelected: (priority) => onPriority?.call(priority),
                  itemBuilder: (context) => [
                    for (final priority in TodoPriority.values)
                      PopupMenuItem(
                        value: priority,
                        child: ValueListenableBuilder<AppLocale>(
                          valueListenable: I18n.localeListenable,
                          builder: (context, _, _) => Row(
                            children: [
                              Icon(
                                Icons.flag,
                                size: 16,
                                color: priorityColor(priority),
                              ),
                              const SizedBox(width: 8),
                              AppSecondaryMenuText(priority.label),
                            ],
                          ),
                        ),
                      ),
                  ],
                  child: _BatchMenuButton(
                    icon: Icons.flag_outlined,
                    label: TodoBoardUiCopy.batchPriority,
                    enabled: enabled && onPriority != null,
                  ),
                ),
                if (onRescheduleDueDate != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: enabled ? onRescheduleDueDate : null,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(
                      I18n.current == AppLocale.en ? 'Due date' : '改期',
                    ),
                  ),
                ],
                if (onAssignList != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: enabled ? onAssignList : null,
                    icon: const Icon(Icons.folder_outlined, size: 18),
                    label: Text(
                      I18n.current == AppLocale.en ? 'List' : '清单',
                    ),
                  ),
                ],
                if (onAssignTags != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: enabled ? onAssignTags : null,
                    icon: const Icon(Icons.sell_outlined, size: 18),
                    label: Text(
                      I18n.current == AppLocale.en ? 'Tag' : '标签',
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: enabled ? onDelete : null,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(TodoBoardUiCopy.delete),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.error,
                    side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BatchMenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;

  const _BatchMenuButton({
    required this.icon,
    required this.label,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = enabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.38);
    final border = enabled
        ? cs.outline.withValues(alpha: 0.5)
        : cs.outline.withValues(alpha: 0.24);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: appSecondaryControlTextStyle(
              context,
            ).copyWith(color: color, fontWeight: FontWeight.normal),
          ),
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down, size: 18, color: color),
        ],
      ),
    );
  }
}

class _TodoSearchAndSortStrip extends StatefulWidget {
  final String query;
  final TodoSortOrder sortOrder;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<TodoSortOrder> onSortChanged;

  const _TodoSearchAndSortStrip({
    required this.query,
    required this.sortOrder,
    required this.onQueryChanged,
    required this.onSortChanged,
  });

  @override
  State<_TodoSearchAndSortStrip> createState() =>
      _TodoSearchAndSortStripState();
}

class _TodoSearchAndSortStripState extends State<_TodoSearchAndSortStrip> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(covariant _TodoSearchAndSortStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _ctrl.text) {
      _ctrl.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _sortLabel(TodoSortOrder order, bool isEn) => switch (order) {
    TodoSortOrder.manual => isEn ? 'Manual' : '手动',
    TodoSortOrder.dueDate => isEn ? 'Due date' : '截止日',
    TodoSortOrder.priority => isEn ? 'Priority' : '优先级',
    TodoSortOrder.created => isEn ? 'Created' : '创建时间',
  };

  @override
  Widget build(BuildContext context) {
    final isEn = I18n.current == AppLocale.en;
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('todo_mobile_search_field'),
            controller: _ctrl,
            onChanged: widget.onQueryChanged,
            textInputAction: TextInputAction.search,
            style: appSecondaryControlTextStyle(context),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              prefixIcon: const Icon(Icons.search, size: 18),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 34,
                minHeight: 34,
              ),
              suffixIcon: widget.query.isNotEmpty
                  ? IconButton(
                      tooltip: TodoBoardUiCopy.clear,
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        _ctrl.clear();
                        widget.onQueryChanged('');
                      },
                    )
                  : null,
              hintText: isEn ? 'Search tasks, notes, tags...' : '搜索待办、备注或标签...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<TodoSortOrder>(
          key: const ValueKey('todo_mobile_sort_menu'),
          tooltip: isEn ? 'Sort tasks' : '排序方式',
          initialValue: widget.sortOrder,
          onSelected: widget.onSortChanged,
          itemBuilder: (ctx) => [
            for (final order in TodoSortOrder.values)
              PopupMenuItem(
                value: order,
                child: Row(
                  children: [
                    Icon(
                      order == widget.sortOrder
                          ? Icons.check
                          : Icons.sort_outlined,
                      size: 16,
                      color: order == widget.sortOrder
                          ? cs.primary
                          : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    AppSecondaryMenuText(_sortLabel(order, isEn)),
                  ],
                ),
              ),
          ],
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.sortOrder != TodoSortOrder.manual
                    ? cs.primary.withValues(alpha: 0.48)
                    : cs.outlineVariant.withValues(alpha: 0.5),
              ),
              color: widget.sortOrder != TodoSortOrder.manual
                  ? cs.primary.withValues(alpha: 0.08)
                  : Colors.transparent,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.swap_vert,
                  size: 16,
                  color: widget.sortOrder != TodoSortOrder.manual
                      ? cs.primary
                      : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  _sortLabel(widget.sortOrder, isEn),
                  style: appSecondaryControlLabelStyle(context).copyWith(
                    color: widget.sortOrder != TodoSortOrder.manual
                        ? cs.primary
                        : cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BatchDueDateChoice {
  final DateTime? dueDate;
  const _BatchDueDateChoice(this.dueDate);
}

class _BatchListChoice {
  final String? listName;
  const _BatchListChoice(this.listName);
}

Future<_BatchDueDateChoice?> _showBatchDueDatePickerDialog(
  BuildContext context,
) async {
  final isEn = I18n.current == AppLocale.en;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return showDialog<_BatchDueDateChoice>(
    context: context,
    builder: (ctx) => AppDialog(
      title: Text(isEn ? 'Reschedule due date' : '批量调整截止日期'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.today_outlined),
            title: Text(isEn ? 'Today' : '今天'),
            onTap: () => Navigator.of(ctx).pop(_BatchDueDateChoice(today)),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.wb_sunny_outlined),
            title: Text(isEn ? 'Tomorrow' : '明天'),
            onTap: () => Navigator.of(ctx).pop(
              _BatchDueDateChoice(today.add(const Duration(days: 1))),
            ),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.date_range_outlined),
            title: Text(isEn ? 'Next week (+7d)' : '下周 (+7天)'),
            onTap: () => Navigator.of(ctx).pop(
              _BatchDueDateChoice(today.add(const Duration(days: 7))),
            ),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.calendar_month_outlined),
            title: Text(isEn ? 'Pick a date...' : '选择具体日期...'),
            onTap: () async {
              final picked = await showDatePicker(
                context: ctx,
                initialDate: today,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked == null || !ctx.mounted) return;
              Navigator.of(ctx).pop(
                _BatchDueDateChoice(
                  DateTime(picked.year, picked.month, picked.day),
                ),
              );
            },
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.event_busy_outlined),
            title: Text(isEn ? 'Clear due date' : '清除截止日期'),
            onTap: () => Navigator.of(ctx).pop(const _BatchDueDateChoice(null)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(TodoBoardUiCopy.cancel),
        ),
      ],
    ),
  );
}

Future<_BatchListChoice?> _showBatchListPickerDialog(
  BuildContext context, {
  required List<String> availableLists,
}) async {
  final isEn = I18n.current == AppLocale.en;
  final names = <String>{
    ...TodoListTemplates.all.map((t) => t.name),
    for (final raw in availableLists)
      if (raw != ungroupedTodoListName && raw.trim().isNotEmpty) raw.trim(),
  }.toList()..sort();
  final customCtrl = TextEditingController();
  try {
    return await showDialog<_BatchListChoice>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text(isEn ? 'Assign to list' : '批量分配所属清单'),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: customCtrl,
                  decoration: InputDecoration(
                    labelText: isEn ? 'Custom list name' : '输入新清单名',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.check),
                      onPressed: () {
                        final text = customCtrl.text.trim();
                        if (text.isEmpty) return;
                        Navigator.of(ctx).pop(_BatchListChoice(text));
                      },
                    ),
                  ),
                  onSubmitted: (val) {
                    final text = val.trim();
                    if (text.isEmpty) return;
                    Navigator.of(ctx).pop(_BatchListChoice(text));
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.inbox_outlined),
                  title: Text(isEn ? 'Inbox / None' : ungroupedTodoListName),
                  onTap: () =>
                      Navigator.of(ctx).pop(const _BatchListChoice(null)),
                ),
                for (final name in names)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(_TodoScreenState._templateDisplayName(name)),
                    onTap: () =>
                        Navigator.of(ctx).pop(_BatchListChoice(name)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(TodoBoardUiCopy.cancel),
          ),
        ],
      ),
    );
  } finally {
    customCtrl.dispose();
  }
}

Future<List<String>?> _showBatchTagPickerDialog(
  BuildContext context, {
  required List<String> availableTags,
}) async {
  final isEn = I18n.current == AppLocale.en;
  final selected = <String>{};
  final inputCtrl = TextEditingController();
  try {
    return await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AppDialog(
          title: Text(isEn ? 'Assign tags' : '批量添加标签'),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: inputCtrl,
                    decoration: InputDecoration(
                      labelText: isEn
                          ? 'New tags (comma separated)'
                          : '输入新标签（逗号或空格分隔）',
                    ),
                  ),
                  if (availableTags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in availableTags)
                          FilterChip(
                            label: Text('#$tag'),
                            selected: selected.contains(tag),
                            onSelected: (on) => setSt(() {
                              if (on) {
                                selected.add(tag);
                              } else {
                                selected.remove(tag);
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(TodoBoardUiCopy.cancel),
            ),
            FilledButton(
              onPressed: () {
                final combined = <String>{...selected};
                for (final part in inputCtrl.text.split(RegExp(r'[,，\s]+'))) {
                  final trimmed = part.trim();
                  if (trimmed.isNotEmpty) combined.add(trimmed);
                }
                Navigator.of(ctx).pop(combined.toList());
              },
              child: Text(I18n.tr('action.confirm')),
            ),
          ],
        ),
      ),
    );
  } finally {
    inputCtrl.dispose();
  }
}

String _dueFilterLabel(TodoDueFilter filter) {
  return TodoBoardUiCopy.filterDueLabel(filter);
}

String _completionFilterLabel(TodoCompletionFilter filter) {
  return TodoBoardUiCopy.filterCompletionLabel(filter);
}

class _TodoKanbanView extends StatelessWidget {
  final TodoKanbanBoardConfig config;
  final Map<String, List<TodoItem>> kanbanGroups;
  final bool batchMode;
  final Set<String> selectedTodoIds;
  final ValueChanged<String> onToggleSelection;
  final ValueChanged<String> onEnterBatchMode;
  final int swipeDismissSerial;
  final ValueChanged<ScrollNotification> onScrollStart;

  const _TodoKanbanView({
    required this.config,
    required this.kanbanGroups,
    required this.batchMode,
    required this.selectedTodoIds,
    required this.onToggleSelection,
    required this.onEnterBatchMode,
    required this.swipeDismissSerial,
    required this.onScrollStart,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final columns = config.sortedColumns;
    return Column(
      children: [
        if (config.groupMode != TodoKanbanGroupMode.none)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                Icon(Icons.account_tree_outlined, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  TodoBoardUiCopy.kanbanGrouping(config.groupMode.label),
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.66),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              onScrollStart(notification);
              return false;
            },
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              // ignore: deprecated_member_use
              cacheExtent: 560,
              itemCount: columns.length,
              itemBuilder: (context, index) {
                final column = columns[index];
                return _KanbanColumn(
                  key: ValueKey('todo_kanban_board_column_${column.id}'),
                  column: column,
                  columns: columns,
                  groupMode: config.groupMode,
                  todos: kanbanGroups[column.id] ?? const <TodoItem>[],
                  batchMode: batchMode,
                  selectedTodoIds: selectedTodoIds,
                  onToggleSelection: onToggleSelection,
                  onEnterBatchMode: onEnterBatchMode,
                  swipeDismissSerial: swipeDismissSerial,
                  onScrollStart: onScrollStart,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _KanbanGroupedTodos {
  final String label;
  final int sortOrder;
  final List<TodoItem> todos;

  const _KanbanGroupedTodos({
    required this.label,
    required this.sortOrder,
    required this.todos,
  });
}

class _KanbanColumnListEntry {
  final _KanbanGroupedTodos? header;
  final TodoItem? todo;

  const _KanbanColumnListEntry.header(this.header) : todo = null;

  const _KanbanColumnListEntry.todo(this.todo) : header = null;
}

class _KanbanGroupKey {
  final String id;
  final String label;
  final int sortOrder;

  const _KanbanGroupKey({
    required this.id,
    required this.label,
    required this.sortOrder,
  });
}

List<_KanbanGroupedTodos> _groupKanbanTodos(
  List<TodoItem> todos,
  TodoKanbanGroupMode mode,
  DateTime now,
) {
  if (mode == TodoKanbanGroupMode.none) {
    return [
      if (todos.isNotEmpty)
        _KanbanGroupedTodos(label: '', sortOrder: 0, todos: todos),
    ];
  }
  final groups = <String, _KanbanGroupedTodos>{};
  for (final todo in todos) {
    final key = _kanbanGroupKey(todo, mode, now);
    groups.putIfAbsent(
      key.id,
      () => _KanbanGroupedTodos(
        label: key.label,
        sortOrder: key.sortOrder,
        todos: <TodoItem>[],
      ),
    );
    groups[key.id]!.todos.add(todo);
  }
  final result = groups.values.toList();
  result.sort((a, b) {
    final order = a.sortOrder.compareTo(b.sortOrder);
    if (order != 0) return order;
    return a.label.compareTo(b.label);
  });
  return result;
}

_KanbanGroupKey _kanbanGroupKey(
  TodoItem todo,
  TodoKanbanGroupMode mode,
  DateTime now,
) {
  switch (mode) {
    case TodoKanbanGroupMode.priority:
      if (todo.priority == TodoPriority.none) {
        return _KanbanGroupKey(
          id: 'priority_none',
          label: I18n.tr('todo.kanban.no_priority'),
          sortOrder: 50,
        );
      }
      return _KanbanGroupKey(
        id: 'priority_${todo.priority.name}',
        label: todo.priority.label,
        sortOrder: 10 - todo.priority.rank,
      );
    case TodoKanbanGroupMode.dueDate:
      final due = todo.dueDate;
      if (due == null) {
        return _KanbanGroupKey(
          id: 'due_none',
          label: I18n.tr('todo.kanban.no_due'),
          sortOrder: 50,
        );
      }
      final today = DateTime(now.year, now.month, now.day);
      final dueDay = DateTime(due.year, due.month, due.day);
      if (dueDay.isBefore(today)) {
        return _KanbanGroupKey(
          id: 'due_overdue',
          label: I18n.tr('todo.kanban.overdue'),
          sortOrder: 0,
        );
      }
      if (dueDay == today) {
        return _KanbanGroupKey(
          id: 'due_today',
          label: I18n.tr('todo.kanban.today'),
          sortOrder: 10,
        );
      }
      if (dueDay.isBefore(today.add(const Duration(days: 7)))) {
        return _KanbanGroupKey(
          id: 'due_week',
          label: I18n.tr('todo.kanban.within_7_days'),
          sortOrder: 20,
        );
      }
      return _KanbanGroupKey(
        id: 'due_later',
        label: I18n.tr('todo.kanban.later'),
        sortOrder: 30,
      );
    case TodoKanbanGroupMode.tag:
      final tag = todo.tags
          .map((item) => item.trim())
          .firstWhere((item) => item.isNotEmpty, orElse: () => '');
      if (tag.isEmpty) {
        return _KanbanGroupKey(
          id: 'tag_none',
          label: I18n.tr('todo.kanban.no_tag'),
          sortOrder: 9999,
        );
      }
      return _KanbanGroupKey(id: 'tag_$tag', label: tag, sortOrder: 100);
    case TodoKanbanGroupMode.list:
      final listName = todo.listGroupName?.trim() ?? '';
      if (listName.isEmpty) {
        return _KanbanGroupKey(
          id: 'list_default',
          label: I18n.tr('todo.kanban.default_list'),
          sortOrder: 9999,
        );
      }
      return _KanbanGroupKey(
        id: 'list_$listName',
        label: listName,
        sortOrder: 100,
      );
    case TodoKanbanGroupMode.none:
      return const _KanbanGroupKey(id: 'none', label: '', sortOrder: 0);
  }
}

class _KanbanColumn extends StatelessWidget {
  final TodoKanbanColumn column;
  final List<TodoKanbanColumn> columns;
  final TodoKanbanGroupMode groupMode;
  final List<TodoItem> todos;
  final bool batchMode;
  final Set<String> selectedTodoIds;
  final ValueChanged<String> onToggleSelection;
  final ValueChanged<String> onEnterBatchMode;
  final int swipeDismissSerial;
  final ValueChanged<ScrollNotification> onScrollStart;

  const _KanbanColumn({
    super.key,
    required this.column,
    required this.columns,
    required this.groupMode,
    required this.todos,
    required this.batchMode,
    required this.selectedTodoIds,
    required this.onToggleSelection,
    required this.onEnterBatchMode,
    required this.swipeDismissSerial,
    required this.onScrollStart,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = Color(column.colorValue);
    final groupedTodos = _groupKanbanTodos(todos, groupMode, DateTime.now());
    final listEntries = <_KanbanColumnListEntry>[
      for (final group in groupedTodos) ...[
        if (groupMode != TodoKanbanGroupMode.none)
          _KanbanColumnListEntry.header(group),
        for (final todo in group.todos) _KanbanColumnListEntry.todo(todo),
      ],
    ];
    return SizedBox(
      width: 280,
      child: DragTarget<String>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (details) {
          context.read<TodoProvider>().updateTodosKanbanColumn([
            details.data,
          ], column.id);
        },
        builder: (context, candidateData, rejectedData) {
          final hovering = candidateData.isNotEmpty;
          return AppSurfaceCard(
            margin: const EdgeInsets.only(right: 10),
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withValues(alpha: hovering ? 0.58 : 0.22),
              width: hovering ? 1.4 : 1,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        TodoBoardUiCopy.columnTitle(column),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                    AppStatusBadge(label: '${todos.length}', color: color),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: todos.isEmpty
                      ? Center(
                          child: Text(
                            hovering
                                ? TodoBoardUiCopy.kanbanReleaseToMoveHere
                                : TodoBoardUiCopy.kanbanNoTasks,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withValues(alpha: 0.45),
                            ),
                          ),
                        )
                      : NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            onScrollStart(notification);
                            return false;
                          },
                          child: ListView.builder(
                            // ignore: deprecated_member_use
                            cacheExtent: 560,
                            itemCount: listEntries.length,
                            itemBuilder: (context, index) {
                              final entry = listEntries[index];
                              final header = entry.header;
                              if (header != null) {
                                return Padding(
                                  padding: const EdgeInsets.only(
                                    top: 2,
                                    bottom: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          header.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: cs.onSurface.withValues(
                                              alpha: 0.62,
                                            ),
                                            fontWeight: FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                      AppStatusBadge(
                                        label: '${header.todos.length}',
                                        color: color,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              final todo = entry.todo!;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _KanbanTodoCard(
                                  todo: todo,
                                  columns: columns,
                                  color: color,
                                  batchMode: batchMode,
                                  selected: selectedTodoIds.contains(todo.id),
                                  onToggleSelection: onToggleSelection,
                                  onEnterBatchMode: onEnterBatchMode,
                                  swipeDismissSerial: swipeDismissSerial,
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TodoActionOrigin {
  _TodoActionOrigin(this.context, TodoItem todo)
    : authority = SettingsActionOrigin(context),
      todos = context.read<TodoProvider>(),
      share = context.read<ShareProvider?>(),
      id = todo.id,
      title = todo.title,
      workspaceId = todo.workspaceId {
    revision = todos.revision;
  }

  final BuildContext context;
  final SettingsActionOrigin authority;
  final TodoProvider todos;
  final ShareProvider? share;
  final String id;
  final String title;
  final String workspaceId;
  late final int revision;

  bool isCurrent({bool checkRoute = true}) {
    if (!authority.isCurrent(checkRoute: checkRoute)) return false;
    try {
      return identical(context.read<TodoProvider>(), todos) &&
          identical(context.read<ShareProvider?>(), share) &&
          todos.revision == revision &&
          (share?.canEdit(workspaceId) ?? true) &&
          todos.todos.any(
            (todo) => todo.id == id && todo.workspaceId == workspaceId,
          );
    } catch (_) {
      return false;
    }
  }
}

Future<void> _confirmTodoDeletion(
  _TodoActionOrigin origin, {
  required bool Function() isRowCurrent,
}) async {
  bool canDelete({bool checkRoute = true}) =>
      isRowCurrent() && origin.isCurrent(checkRoute: checkRoute);
  if (!canDelete()) return;
  ModalRoute<dynamic>? dialogRoute;
  final confirmed = await showDialog<bool>(
    context: origin.context,
    builder: (dialogContext) {
      final route = ModalRoute.of(dialogContext);
      dialogRoute = route;
      bool canClose() =>
          dialogContext.mounted &&
          route?.isActive == true &&
          route?.isCurrent == true;
      return ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (_, _, _) => AppDialog(
          icon: const Icon(Icons.delete_outline),
          title: Text(TodoBoardUiCopy.deleteTaskDialogTitle),
          content: Text(TodoBoardUiCopy.deleteTaskDialogContent(origin.title)),
          actions: [
            TextButton(
              onPressed: () {
                if (canClose()) Navigator.of(dialogContext).pop(false);
              },
              child: Text(TodoBoardUiCopy.cancel),
            ),
            FilledButton(
              onPressed: () {
                if (canClose() && canDelete(checkRoute: false)) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: Text(TodoBoardUiCopy.delete),
            ),
          ],
        ),
      );
    },
  );
  await dialogRoute?.completed;
  if (confirmed == true && canDelete()) {
    await origin.todos.deleteTodo(origin.id);
  }
}

class _KanbanTodoCard extends StatefulWidget {
  final TodoItem todo;
  final List<TodoKanbanColumn> columns;
  final Color color;
  final bool batchMode;
  final bool selected;
  final ValueChanged<String> onToggleSelection;
  final ValueChanged<String> onEnterBatchMode;
  final int swipeDismissSerial;

  const _KanbanTodoCard({
    required this.todo,
    required this.columns,
    required this.color,
    required this.batchMode,
    required this.selected,
    required this.onToggleSelection,
    required this.onEnterBatchMode,
    required this.swipeDismissSerial,
  });

  @override
  State<_KanbanTodoCard> createState() => _KanbanTodoCardState();
}

class _KanbanTodoCardState extends State<_KanbanTodoCard> {
  static const double _swipeActionWidth = _TodoTileState._swipeActionWidth;
  static const double _swipeOpenThreshold = 36;

  double _swipeOffset = 0;
  bool _dragging = false;

  bool get _swipeOpen => _swipeOffset > 0;
  bool get _swipeActive => _swipeOffset > 0;

  @override
  void didUpdateWidget(covariant _KanbanTodoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.batchMode ||
        widget.todo.id != oldWidget.todo.id ||
        widget.swipeDismissSerial != oldWidget.swipeDismissSerial) {
      _swipeOffset = 0;
      _dragging = false;
    }
  }

  void _closeSwipe() {
    if (!_swipeOpen || !mounted) return;
    setState(() => _swipeOffset = 0);
  }

  Future<void> _openDetails(BuildContext context) async {
    _closeSwipe();
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TodoDetailScreen(
          todoId: widget.todo.id,
          accountGeneration: accountGeneration,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(_TodoActionOrigin origin) async {
    if (!mounted || !origin.isCurrent()) return;
    _closeSwipe();
    await _confirmTodoDeletion(
      origin,
      isRowCurrent: () =>
          mounted &&
          widget.todo.id == origin.id &&
          widget.todo.workspaceId == origin.workspaceId,
    );
  }

  Future<void> _toggleCompletion(BuildContext context) async {
    _closeSwipe();
    await _toggleTodoCompletionFromSwipe(context, widget.todo);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    context.watch<TodoProvider>();
    final todo = widget.todo;
    final deleteOrigin = _TodoActionOrigin(context, todo);
    final canEdit = context.watch<ShareProvider>().canEdit(todo.workspaceId);
    final visual = CompletionVisibilityPolicy.visualState(todo);
    final stateColor = CompletionVisibilityPolicy.colorFor(visual);
    final isCompleted = visual == TodoVisualState.completed;
    final isOverdue = visual == TodoVisualState.overdue;
    final isDueSoon = visual == TodoVisualState.dueSoon;
    final statusColor = isCompleted || isOverdue || isDueSoon
        ? stateColor
        : widget.color;
    final statusBackground = isCompleted || isOverdue || isDueSoon
        ? Color.alphaBlend(
            stateColor.withValues(alpha: isCompleted ? 0.06 : 0.08),
            cs.surfaceContainerHighest,
          )
        : cs.surfaceContainerHighest.withValues(alpha: 0.42);
    final card = Material(
      color: widget.selected
          ? widget.color.withValues(alpha: 0.14)
          : statusBackground,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.batchMode
            ? canEdit
                  ? () => widget.onToggleSelection(todo.id)
                  : null
            : _swipeOpen
            ? _closeSwipe
            : () => _openDetails(context),
        onLongPress: canEdit ? () => widget.onEnterBatchMode(todo.id) : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.batchMode) ...[
                    Checkbox(
                      value: widget.selected,
                      visualDensity: VisualDensity.compact,
                      onChanged: canEdit
                          ? (_) => widget.onToggleSelection(todo.id)
                          : null,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      todo.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: isCompleted
                            ? cs.onSurface.withValues(alpha: 0.54)
                            : isOverdue
                            ? cs.error
                            : cs.onSurface,
                        decoration: isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                  if (canEdit && !widget.batchMode)
                    PopupMenuButton<TodoKanbanColumn>(
                      tooltip: TodoBoardUiCopy.moveToTooltip,
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.more_horiz,
                        size: 18,
                        color: cs.onSurface.withValues(alpha: 0.56),
                      ),
                      onSelected: (column) {
                        if (deleteOrigin.isCurrent() &&
                            widget.todo.id == deleteOrigin.id &&
                            widget.columns.any(
                              (item) => item.id == column.id,
                            )) {
                          deleteOrigin.todos.updateTodosKanbanColumn([
                            deleteOrigin.id,
                          ], column.id);
                        }
                      },
                      itemBuilder: (context) => [
                        for (final column in widget.columns)
                          PopupMenuItem(
                            value: column,
                            enabled: column.id != todo.kanbanColumnId,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 10,
                                  color: Color(column.colorValue),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ValueListenableBuilder<AppLocale>(
                                    valueListenable: I18n.localeListenable,
                                    builder: (_, _, _) => AppSecondaryMenuText(
                                      TodoBoardUiCopy.columnTitle(column),
                                    ),
                                  ),
                                ),
                                if (column.id == todo.kanbanColumnId) ...[
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.check,
                                    size: 16,
                                    color: cs.primary,
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (todo.priority != TodoPriority.none)
                    AppStatusBadge(
                      label: todo.priority.label,
                      color: priorityColor(todo.priority),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                    ),
                  if (todo.dueDate != null)
                    AppStatusBadge(
                      label: I18nDateFormat.compactDateTime(
                        todo.dueDate!,
                        omitTimeWhenMidnight: true,
                      ),
                      color: statusColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                    ),
                  if (isCompleted)
                    AppStatusBadge(
                      label: TodoBoardUiCopy.cardCompletedBadge,
                      color: statusColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                    ),
                  if (isOverdue)
                    AppStatusBadge(
                      label: TodoBoardUiCopy.cardOverdueBadge,
                      color: statusColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                    ),
                  if (isDueSoon)
                    AppStatusBadge(
                      label: TodoBoardUiCopy.cardDueSoonBadge,
                      color: statusColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                    ),
                  if (todo.subtasks.isNotEmpty)
                    AppStatusBadge(
                      label: TodoBoardUiCopy.cardSubtasksBadge(
                        todo.subtasks.where((s) => s.isCompleted).length,
                        todo.subtasks.length,
                      ),
                      color: cs.secondary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!canEdit || widget.batchMode) return card;

    final swipeCard = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => setState(() => _dragging = true),
      onHorizontalDragUpdate: (details) {
        final next = (_swipeOffset - details.delta.dx).clamp(
          0.0,
          _swipeActionWidth,
        );
        if (next == _swipeOffset) return;
        setState(() => _swipeOffset = next);
      },
      onHorizontalDragEnd: (_) {
        final shouldOpen = _swipeOffset >= _swipeOpenThreshold;
        setState(() {
          _dragging = false;
          _swipeOffset = shouldOpen ? _swipeActionWidth : 0;
        });
      },
      onHorizontalDragCancel: () => setState(() {
        _dragging = false;
        _swipeOffset = _swipeOffset >= _swipeOpenThreshold
            ? _swipeActionWidth
            : 0;
      }),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          if (_swipeActive)
            Positioned.fill(
              child: RepaintBoundary(
                child: _TodoInlineSwipeActions(
                  margin: EdgeInsets.zero,
                  onToggleCompletion: () => _toggleCompletion(context),
                  onDelete: () => _confirmDelete(deleteOrigin),
                  completed: todo.isCompleted,
                ),
              ),
            ),
          AnimatedContainer(
            duration: _dragging
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(-_swipeOffset, 0, 0),
            child: RepaintBoundary(child: card),
          ),
        ],
      ),
    );

    return LongPressDraggable<String>(
      data: todo.id,
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Opacity(opacity: 0.92, child: card),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.42, child: swipeCard),
      child: swipeCard,
    );
  }
}

class _KanbanSettingsSheet extends StatefulWidget {
  final TodoKanbanBoardConfig config;

  const _KanbanSettingsSheet({required this.config});

  @override
  State<_KanbanSettingsSheet> createState() => _KanbanSettingsSheetState();
}

class _KanbanSettingsSheetState extends State<_KanbanSettingsSheet> {
  late List<TodoKanbanColumn> _columns;
  late TodoKanbanGroupMode _groupMode;
  SettingsActionOrigin? _sheetOrigin;
  final Map<String, TextEditingController> _nameControllers = {};
  final Map<String, FocusNode> _nameFocusNodes = {};

  static const _palette = [
    0xFF607D8B,
    0xFF1976D2,
    0xFF7B1FA2,
    0xFFD32F2F,
    0xFFF57C00,
    0xFF2E7D32,
    0xFF00897B,
  ];

  @override
  void initState() {
    super.initState();
    _columns = widget.config.sortedColumns;
    _groupMode = widget.config.groupMode;
    for (final column in _columns) {
      _nameControllers[column.id] = TextEditingController(text: column.title);
      _nameFocusNodes[column.id] = FocusNode();
    }
    I18n.localeListenable.addListener(_onLocaleChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sheetOrigin ??= SettingsActionOrigin(context);
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    for (final controller in _nameControllers.values) {
      controller.dispose();
    }
    for (final focus in _nameFocusNodes.values) {
      focus.dispose();
    }
    super.dispose();
  }

  bool _canEdit(SettingsActionOrigin origin, {bool checkRoute = true}) =>
      mounted &&
      _sheetOrigin?.isCurrent(checkRoute: checkRoute) == true &&
      origin.isCurrent(checkRoute: checkRoute);

  void _updateColumn(
    SettingsActionOrigin origin,
    String id, {
    String? title,
    int? colorValue,
  }) {
    if (!_canEdit(origin)) return;
    final index = _columns.indexWhere((item) => item.id == id);
    if (index == -1) return;
    setState(() {
      _columns[index] = _columns[index].copyWith(
        title: title,
        colorValue: colorValue,
      );
    });
  }

  void _moveColumn(SettingsActionOrigin origin, String id, int delta) {
    if (!_canEdit(origin)) return;
    final index = _columns.indexWhere((item) => item.id == id);
    final target = index + delta;
    if (index == -1 || target < 0 || target >= _columns.length) return;
    setState(() {
      final column = _columns.removeAt(index);
      _columns.insert(target, column);
      _renumber();
    });
  }

  void _addColumn(SettingsActionOrigin origin) {
    if (!_canEdit(origin)) return;
    setState(() {
      final id = 'custom_${DateTime.now().microsecondsSinceEpoch}';
      final title = TodoBoardUiCopy.newColumnDefaultTitle;
      _nameControllers[id] = TextEditingController(text: title);
      _nameFocusNodes[id] = FocusNode();
      _columns.add(
        TodoKanbanColumn(
          id: id,
          title: title,
          colorValue: _palette[_columns.length % _palette.length],
          sortOrder: _columns.length,
        ),
      );
    });
  }

  void _renumber() {
    for (var i = 0; i < _columns.length; i++) {
      _columns[i] = _columns[i].copyWith(sortOrder: i);
    }
  }

  Future<void> _deleteColumn(SettingsActionOrigin origin, String id) async {
    if (!_canEdit(origin)) return;
    final index = _columns.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final column = _columns[index];
    if (column.builtIn) return;
    ModalRoute<dynamic>? dialogRoute;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final route = ModalRoute.of(dialogContext);
        dialogRoute = route;
        bool canClose() =>
            dialogContext.mounted &&
            route?.isActive == true &&
            route?.isCurrent == true;
        return ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (_, _, _) => AppDialog(
            icon: const Icon(Icons.delete_outline),
            title: Text(TodoBoardUiCopy.deleteColumnDialogTitle),
            content: Text(
              TodoBoardUiCopy.deleteColumnDialogContent(column.title),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (canClose()) Navigator.of(dialogContext).pop(false);
                },
                child: Text(TodoBoardUiCopy.cancel),
              ),
              FilledButton(
                onPressed: () {
                  if (canClose() && _canEdit(origin, checkRoute: false)) {
                    Navigator.of(dialogContext).pop(true);
                  }
                },
                child: Text(TodoBoardUiCopy.delete),
              ),
            ],
          ),
        );
      },
    );
    await dialogRoute?.completed;
    if (confirmed != true || !_canEdit(origin)) return;
    setState(() {
      final next = TodoKanbanBoardConfig(
        columns: _columns,
        groupMode: _groupMode,
      ).removeColumn(column.id);
      if (next != null) _columns = next.sortedColumns;
    });
  }

  void _save(SettingsActionOrigin origin) {
    if (!_canEdit(origin)) return;
    final normalized = <TodoKanbanColumn>[];
    for (var i = 0; i < _columns.length; i++) {
      final column = _columns[i];
      final title = column.title.trim();
      normalized.add(
        column.copyWith(
          title: title.isEmpty ? TodoBoardUiCopy.untitledColumn : title,
          sortOrder: i,
        ),
      );
    }
    Navigator.pop(
      context,
      TodoKanbanBoardConfig(columns: normalized, groupMode: _groupMode),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final origin = SettingsActionOrigin(context);
    return AppModalSheet(
      title: TodoBoardUiCopy.kanbanSettingsTitle,
      subtitle: TodoBoardUiCopy.kanbanSettingsSubtitle,
      actions: [
        FilledButton(
          onPressed: () => _save(origin),
          style: appSecondaryFilledButtonStyle(context),
          child: Text(TodoBoardUiCopy.save),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppDropdownField<TodoKanbanGroupMode>(
            initialValue: _groupMode,
            isInteractionAllowed: () => _canEdit(origin),
            isSelectionAllowed: () => _canEdit(origin, checkRoute: false),
            decoration: InputDecoration(
              labelText: TodoBoardUiCopy.defaultGroupingLabel,
              helperText: TodoBoardUiCopy.defaultGroupingHelper,
              helperMaxLines: 4,
              isDense: true,
            ),
            items: [
              for (final mode in TodoKanbanGroupMode.values)
                DropdownMenuItem(
                  value: mode,
                  child: ValueListenableBuilder<AppLocale>(
                    valueListenable: I18n.localeListenable,
                    builder: (_, _, _) => Text(mode.label),
                  ),
                ),
            ],
            onChanged: (mode) {
              if (mode == null || !_canEdit(origin)) return;
              setState(() => _groupMode = mode);
            },
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 440),
            child: ListView.separated(
              key: const ValueKey('todo_kanban_settings_columns'),
              shrinkWrap: true,
              itemCount: _columns.length,
              findItemIndexCallback: (key) {
                final index = _columns.indexWhere(
                  (column) =>
                      key == ValueKey('todo_kanban_column_${column.id}'),
                );
                return index == -1 ? null : index;
              },
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final column = _columns[index];
                return AppSurfaceCard(
                  key: ValueKey('todo_kanban_column_${column.id}'),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.circle,
                            color: Color(column.colorValue),
                            size: 14,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              key: ValueKey(
                                'todo_kanban_column_name_${column.id}',
                              ),
                              controller: _nameControllers[column.id],
                              focusNode: _nameFocusNodes[column.id],
                              decoration: InputDecoration(
                                labelText: TodoBoardUiCopy.columnNameLabel,
                                isDense: true,
                              ),
                              onChanged: (value) => _updateColumn(
                                origin,
                                column.id,
                                title: value,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: TodoBoardUiCopy.moveUpTooltip,
                            onPressed: index == 0
                                ? null
                                : () => _moveColumn(origin, column.id, -1),
                            icon: const Icon(Icons.arrow_upward),
                          ),
                          IconButton(
                            tooltip: TodoBoardUiCopy.moveDownTooltip,
                            onPressed: index == _columns.length - 1
                                ? null
                                : () => _moveColumn(origin, column.id, 1),
                            icon: const Icon(Icons.arrow_downward),
                          ),
                          IconButton(
                            tooltip: column.builtIn
                                ? TodoBoardUiCopy.builtInColumnCannotDelete
                                : TodoBoardUiCopy.deleteColumnTooltip,
                            onPressed: column.builtIn
                                ? null
                                : () => _deleteColumn(origin, column.id),
                            icon: Icon(
                              Icons.delete_outline,
                              color: column.builtIn ? null : cs.error,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final value in _palette)
                            InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () => _updateColumn(
                                origin,
                                column.id,
                                colorValue: value,
                              ),
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Color(value),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: column.colorValue == value
                                        ? cs.onSurface
                                        : cs.outlineVariant,
                                    width: column.colorValue == value ? 2 : 1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _addColumn(origin),
            icon: const Icon(Icons.add),
            label: Text(TodoBoardUiCopy.addColumn),
          ),
        ],
      ),
    );
  }
}

Color _quadrantColor(EisenhowerQuadrant q) {
  switch (q) {
    case EisenhowerQuadrant.urgentImportant:
      return const Color(0xFFE53935);
    case EisenhowerQuadrant.notUrgentImportant:
      return const Color(0xFFF6A339);
    case EisenhowerQuadrant.urgentNotImportant:
      return const Color(0xFF42A5F5);
    case EisenhowerQuadrant.notUrgentNotImportant:
      return const Color(0xFF8E8E8E);
  }
}

String _quadrantLabel(EisenhowerQuadrant q) {
  return TodoBoardUiCopy.quadrantLabel(q);
}

String _todoListDisplayName(String groupName, Iterable<TodoItem> todos) =>
    todos.every((todo) => todo.listGroupName?.trim().isNotEmpty != true)
    ? TodoBoardUiCopy.ungroupedListLabel
    : groupName;

class _ListRowEntry {
  final String groupName;
  final TodoItem? todo;
  final bool isHeader;

  const _ListRowEntry.header(this.groupName) : todo = null, isHeader = true;

  const _ListRowEntry.todo(this.groupName, this.todo) : isHeader = false;
}

/// Each rendered opener retains its own provider and group identity.
class _ListGroupShareButton extends StatelessWidget {
  const _ListGroupShareButton({required this.groupName});
  final String groupName;

  @override
  Widget build(BuildContext context) {
    context.watch<AuthProvider?>();
    final origin = _ListGroupShareOrigin(context, groupName);
    return IconButton(
      tooltip: TodoBoardUiCopy.shareListTooltip,
      onPressed: () => _shareTodoListGroup(origin),
      icon: const Icon(Icons.ios_share_outlined),
    );
  }
}

class _ListGroupShareOrigin {
  _ListGroupShareOrigin(this.context, this.groupName)
    : authority = SettingsActionOrigin(context),
      todos = context.read<TodoProvider>(),
      share = context.read<ShareProvider>(),
      auth = context.read<AuthProvider?>(),
      accountGeneration = AccountLocalDataCleaner.accountDataGeneration {
    storageGeneration = todos.storageGeneration;
    userId = auth?.state.userId;
    members = {
      for (final item in todos.todos)
        if ((item.listGroupName ?? ungroupedTodoListName) == groupName)
          item.id: item,
    };
    versions = members.map(
      (id, item) => MapEntry(id, json.encode(item.toJson())),
    );
  }

  final BuildContext context;
  final String groupName;
  final SettingsActionOrigin authority;
  final TodoProvider todos;
  final ShareProvider share;
  final AuthProvider? auth;
  final int accountGeneration;
  late final int storageGeneration;
  late final String? userId;
  late final Map<String, TodoItem> members;
  late final Map<String, String> versions;

  bool isCurrent({bool checkContent = true, bool checkPermissions = true}) {
    if (!authority.isCurrent(checkRoute: false)) return false;
    try {
      if (!identical(context.read<TodoProvider>(), todos) ||
          !identical(context.read<ShareProvider>(), share) ||
          !identical(context.read<AuthProvider?>(), auth) ||
          todos.storageGeneration != storageGeneration ||
          auth?.state.userId != userId ||
          members.isEmpty ||
          (checkPermissions &&
              members.values.any((item) => !share.canEdit(item.workspaceId)))) {
        return false;
      }
      if (!checkContent) return true;
      final current = todos.todos.where(
        (item) => (item.listGroupName ?? ungroupedTodoListName) == groupName,
      );
      return current.length == members.length &&
          current.every(
            (item) =>
                identical(item, members[item.id]) &&
                json.encode(item.toJson()) == versions[item.id],
          );
    } catch (_) {
      return false;
    }
  }

  bool canSelect(String target) =>
      target == 'private' ||
      share.workspaces.any(
        (workspace) =>
            workspace.id == target &&
            !workspace.isPrivate &&
            workspace.roleFor(userId).canEdit,
      );
}

/// A lock, account change or covering route permanently revokes this action.
class _ListGroupShareOperation {
  _ListGroupShareOperation(this.origin)
    : sourceRoute = ModalRoute.of(origin.context) {
    for (final notifier in <ChangeNotifier?>[
      origin.auth,
      origin.todos,
      origin.share,
      origin.authority.preferences,
      origin.context.read<AppLockProvider?>(),
      origin.context.read<AppUpdateService?>(),
    ]) {
      if (notifier == null) continue;
      notifier.addListener(observe);
      notifiers.add(notifier);
    }
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      observe,
    );
    for (final observer in Navigator.of(origin.context).widget.observers) {
      if (observer is AppAccessRouteGate) {
        gates.add(observer);
        observer.routeRevision.addListener(observe);
      }
    }
    sourceRoute?.secondaryAnimation?.addListener(observe);
  }

  final _ListGroupShareOrigin origin;
  final ModalRoute<dynamic>? sourceRoute;
  final notifiers = <ChangeNotifier>[];
  final gates = <AppAccessRouteGate>[];
  ModalBottomSheetRoute<String>? sheetRoute;
  String? target;
  bool expired = false;
  bool handedOff = false;
  bool permissionsReady = false;
  bool disposed = false;

  void observe() {
    isCurrent();
  }

  bool isCurrent() {
    if (expired || disposed) return false;
    final sheet = sheetRoute;
    final covered = gates.any(
      (gate) =>
          !identical(gate.currentRoute, sourceRoute) &&
          !identical(gate.currentRoute, sheet),
    );
    if (!origin.isCurrent(
          checkContent: !handedOff,
          checkPermissions: permissionsReady,
        ) ||
        covered ||
        sourceRoute?.isActive == false ||
        (sheet == null && sourceRoute?.isCurrent == false) ||
        (sheet != null && (sheet.secondaryAnimation?.value ?? 0) > 0) ||
        (target != null && !origin.canSelect(target!))) {
      expired = true;
      // Remove only our obsolete sheet, including when a different route covers
      // it. Scheduling avoids mutating a Navigator during its observer callback.
      final owned = sheetRoute;
      if (owned != null) {
        void close() {
          final navigator = owned.navigator;
          if (owned.isActive && navigator?.mounted == true) {
            navigator!.removeRoute(owned);
          }
        }

        scheduleMicrotask(() {
          if (SchedulerBinding.instance.schedulerPhase ==
              SchedulerPhase.persistentCallbacks) {
            WidgetsBinding.instance.addPostFrameCallback((_) => close());
          } else {
            close();
          }
        });
      }
      return false;
    }
    return true;
  }

  bool select(BuildContext sheetContext, String value) {
    if (!isCurrent() ||
        sheetRoute?.isActive != true ||
        sheetRoute?.isCurrent != true ||
        !sheetContext.mounted ||
        !identical(ModalRoute.of(sheetContext), sheetRoute) ||
        !origin.canSelect(value)) {
      return false;
    }
    target = value;
    Navigator.of(sheetContext).pop(value);
    return true;
  }

  void dispose() {
    disposed = true;
    sourceRoute?.secondaryAnimation?.removeListener(observe);
    sheetRoute?.secondaryAnimation?.removeListener(observe);
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      observe,
    );
    for (final notifier in notifiers) {
      notifier.removeListener(observe);
    }
    for (final gate in gates) {
      gate.routeRevision.removeListener(observe);
    }
  }
}

Future<void> _shareTodoListGroup(_ListGroupShareOrigin origin) async {
  if (!origin.isCurrent(checkPermissions: false) ||
      !origin.authority.isCurrent()) {
    return;
  }
  final context = origin.context;
  final operation = _ListGroupShareOperation(origin);
  try {
    if (origin.auth?.state.isLoggedIn != true) {
      if (operation.isCurrent()) {
        await Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const ShareScreen()));
      }
      return;
    }
    if (origin.share.workspaces.isEmpty) await origin.share.load();
    if (!context.mounted || !operation.isCurrent()) return;
    if (!origin.share.workspaces.any((workspace) => !workspace.isPrivate)) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const ShareScreen()));
      return;
    }
    operation.permissionsReady = true;
    if (!context.mounted || !operation.isCurrent()) return;
    final navigator = Navigator.of(context);
    if (!navigator.mounted) return;
    final route = ModalBottomSheetRoute<String>(
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      requestFocus: false,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      builder: (sheetContext) => ListenableBuilder(
        listenable: Listenable.merge([I18n.localeListenable, origin.share]),
        builder: (_, _) => AppModalSheet(
          title: TodoBoardUiCopy.shareListDialogTitle,
          subtitle: TodoBoardUiCopy.shareListDialogSubtitle(
            _todoListDisplayName(
              origin.groupName,
              origin.members.values.toList(),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_outline),
                title: Text(TodoBoardUiCopy.onlyMyselfVisible),
                onTap: () => operation.select(sheetContext, 'private'),
              ),
              for (final workspace in origin.share.workspaces)
                if (!workspace.isPrivate)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.groups_2_outlined),
                    title: Text(workspace.name),
                    subtitle: Text(
                      TodoBoardUiCopy.workspaceMemberInfo(
                        workspace.members.length,
                        workspace.roleFor(origin.userId).label,
                      ),
                    ),
                    enabled: workspace.roleFor(origin.userId).canEdit,
                    onTap: workspace.roleFor(origin.userId).canEdit
                        ? () => operation.select(sheetContext, workspace.id)
                        : null,
                  ),
            ],
          ),
        ),
      ),
    );
    operation.sheetRoute = route;
    final pickedFuture = navigator.push(route);
    route.secondaryAnimation?.addListener(operation.observe);
    final picked = await pickedFuture;
    await route.completed;
    route.secondaryAnimation?.removeListener(operation.observe);
    operation.sheetRoute = null;
    if (!context.mounted ||
        picked == null ||
        !operation.isCurrent() ||
        operation.target != picked) {
      return;
    }
    // The provider now captures the exact group before its first asynchronous
    // boundary. Its staged patch owns content checks through acknowledgement.
    operation.handedOff = true;
    final saved = await origin.todos.updateListGroupWorkspace(
      origin.groupName,
      picked,
      userId: origin.userId,
      expectedAccountDataGeneration: origin.accountGeneration,
      canWrite: operation.isCurrent,
      expectedGroupMembers: origin.members,
    );
    if (!context.mounted || !saved || !operation.isCurrent()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (_, _, _) => Text(TodoBoardUiCopy.shareStatusUpdated),
        ),
      ),
    );
  } catch (error, stack) {
    debugPrint('[Todo sharing] save failed: $error\n$stack');
    if (context.mounted &&
        operation.isCurrent() &&
        origin.authority.isCurrent()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (_, _, _) => Text(TodoBoardUiCopy.shareStatusSaveFailed),
          ),
        ),
      );
    }
  } finally {
    operation.dispose();
  }
}

/// Kept as its own lazy list row so expanded groups remain virtualized.
class _ListGroupHeader extends StatelessWidget {
  final String groupName;
  final List<TodoItem> todos;
  final bool expanded;
  final VoidCallback onToggle;

  const _ListGroupHeader({
    super.key,
    required this.groupName,
    required this.todos,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final todoProvider = context.watch<TodoProvider>();
    final shareProvider = context.watch<ShareProvider>();
    final workspaceId = todoProvider.workspaceForListGroup(groupName);
    final workspace = workspaceId == null
        ? null
        : shareProvider.workspaces
              .where((candidate) => candidate.id == workspaceId)
              .firstOrNull;
    final displayName = _todoListDisplayName(groupName, todos);
    final isUngrouped = todos.every(
      (todo) => todo.listGroupName?.trim().isNotEmpty != true,
    );

    final leadingWidget = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        expanded ? Icons.expand_less : Icons.expand_more,
        color: cs.primary,
      ),
    );

    final trailingWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (workspace != null)
          Icon(Icons.groups_2_outlined, size: 18, color: cs.primary),
        _ListGroupShareButton(groupName: groupName),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${todos.length}',
            style: TextStyle(
              color: cs.primary,
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
      ],
    );

    final subtitleWidget = workspace == null
        ? null
        : Text(
            TodoBoardUiCopy.sharedWorkspacePrefix(workspace.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );

    // 自定义长组保留原 ellipsis 策略及原 ListTile 结构与几何交互
    if (!isUngrouped) {
      return AppSurfaceCard(
        key: key,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(18),
        child: ListTile(
          leading: leadingWidget,
          title: Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.normal),
          ),
          subtitle: subtitleWidget,
          trailing: trailingWidget,
          onTap: onToggle,
        ),
      );
    }

    final textScaler = MediaQuery.textScalerOf(context);
    final titleStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontSize: 13.0,
          fontWeight: FontWeight.normal,
        ) ??
        const TextStyle(fontSize: 13.0, fontWeight: FontWeight.normal);

    return AppSurfaceCard(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final titlePainter = TextPainter(
            text: TextSpan(text: displayName, style: titleStyle),
            textDirection: Directionality.of(context),
            textScaler: textScaler,
          )..layout();
          final titleWidth = titlePainter.width;
          titlePainter.dispose();

          final trailingWidth =
              (workspace != null ? 18.0 : 0.0) + 48.0 + 32.0;
          final availableTitleWidth =
              constraints.maxWidth - 32.0 - 36.0 - 16.0 - trailingWidth - 16.0;

          final shouldWrapTrailing = titleWidth > availableTitleWidth;

          if (!shouldWrapTrailing) {
            return ListTile(
              leading: leadingWidget,
              title: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.normal),
              ),
              subtitle: subtitleWidget,
              trailing: trailingWidget,
              onTap: onToggle,
            );
          }

          return InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  leadingWidget,
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: titleStyle,
                        ),
                        if (subtitleWidget != null) ...[
                          const SizedBox(height: 2),
                          subtitleWidget,
                        ],
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: trailingWidget,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ListGroupTile extends StatefulWidget {
  final String groupName;
  final List<TodoItem> todos;
  final bool batchMode;
  final Set<String> selectedTodoIds;
  final ValueChanged<String> onToggleSelection;
  final ValueChanged<String> onEnterBatchMode;
  final int swipeDismissSerial;

  const _ListGroupTile({
    required this.groupName,
    required this.todos,
    required this.batchMode,
    required this.selectedTodoIds,
    required this.onToggleSelection,
    required this.onEnterBatchMode,
    required this.swipeDismissSerial,
  });

  @override
  State<_ListGroupTile> createState() => _ListGroupTileState();
}

class _ListGroupTileState extends State<_ListGroupTile> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final todoProvider = context.watch<TodoProvider>();
    final shareProvider = context.watch<ShareProvider>();
    final workspaceId = todoProvider.workspaceForListGroup(widget.groupName);
    final workspace = workspaceId == null
        ? null
        : shareProvider.workspaces
              .where((workspace) => workspace.id == workspaceId)
              .firstOrNull;
    return AppSurfaceCard(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                color: cs.primary,
              ),
            ),
            title: Text(
              _todoListDisplayName(widget.groupName, widget.todos),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.normal),
            ),
            subtitle: workspace == null
                ? null
                : Text(
                    TodoBoardUiCopy.sharedWorkspacePrefix(workspace.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (workspace != null)
                  Icon(Icons.groups_2_outlined, size: 18, color: cs.primary),
                _ListGroupShareButton(groupName: widget.groupName),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${widget.todos.length}',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded) _buildTodoList(context, shareProvider),
        ],
      ),
    );
  }

  Widget _buildTodoList(BuildContext context, ShareProvider shareProvider) {
    final canReorder =
        !widget.batchMode &&
        widget.todos.length > 1 &&
        widget.todos.every((todo) => shareProvider.canEdit(todo.workspaceId));

    if (!canReorder) {
      return Column(
        children: [for (final todo in widget.todos) _buildTodoTile(todo)],
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: widget.todos.length,
      // ignore: deprecated_member_use
      onReorder: _reorderTodos,
      proxyDecorator: (child, index, animation) => Material(
        type: MaterialType.transparency,
        child: ScaleTransition(
          scale: Tween<double>(begin: 1, end: 1.02).animate(animation),
          child: child,
        ),
      ),
      itemBuilder: (context, index) {
        final todo = widget.todos[index];
        return _buildTodoTile(
          todo,
          key: ValueKey('todo-reorder-${todo.id}'),
          trailing: ReorderableDragStartListener(
            index: index,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Tooltip(
                message: TodoBoardUiCopy.dragToReorderTooltip,
                child: Padding(
                  padding: const EdgeInsets.only(left: DesignTokens.spaceXs),
                  child: Icon(
                    Icons.drag_indicator,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTodoTile(TodoItem todo, {Key? key, Widget? trailing}) {
    return _TodoTile(
      key: key,
      todo: todo,
      batchMode: widget.batchMode,
      selected: widget.selectedTodoIds.contains(todo.id),
      onToggleSelection: widget.onToggleSelection,
      onEnterBatchMode: widget.onEnterBatchMode,
      trailing: trailing,
      swipeDismissSerial: widget.swipeDismissSerial,
    );
  }

  Future<void> _reorderTodos(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    if (newIndex > oldIndex) newIndex -= 1;

    final ids = widget.todos.map((todo) => todo.id).toList();
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    await context.read<TodoProvider>().reorderVisibleTodos(ids);
  }
}

class _TodoTile extends StatefulWidget {
  final TodoItem todo;
  final bool showArchived;
  final bool batchMode;
  final bool selected;
  final ValueChanged<String> onToggleSelection;
  final ValueChanged<String> onEnterBatchMode;
  final Widget? trailing;
  final int swipeDismissSerial;
  final ValueListenable<int>? swipeDismissListenable;

  const _TodoTile({
    super.key,
    required this.todo,
    this.showArchived = false,
    required this.batchMode,
    required this.selected,
    required this.onToggleSelection,
    required this.onEnterBatchMode,
    this.trailing,
    this.swipeDismissSerial = 0,
    this.swipeDismissListenable,
  });

  @override
  State<_TodoTile> createState() => _TodoTileState();
}

class _TodoTileState extends State<_TodoTile> {
  static const double _swipeActionWidth = 98;
  static const double _swipeOpenThreshold = 36;

  double _swipeOffset = 0;
  bool _dragging = false;

  bool get _swipeOpen => _swipeOffset > 0;
  bool get _swipeActive => _swipeOffset > 0;

  @override
  void initState() {
    super.initState();
    widget.swipeDismissListenable?.addListener(_closeSwipeFromScroll);
  }

  @override
  void dispose() {
    widget.swipeDismissListenable?.removeListener(_closeSwipeFromScroll);
    super.dispose();
  }

  void _closeSwipeFromScroll() {
    if (!mounted || !_swipeOpen) return;
    setState(() {
      _swipeOffset = 0;
      _dragging = false;
    });
  }

  @override
  void didUpdateWidget(covariant _TodoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.swipeDismissListenable != oldWidget.swipeDismissListenable) {
      oldWidget.swipeDismissListenable?.removeListener(_closeSwipeFromScroll);
      widget.swipeDismissListenable?.addListener(_closeSwipeFromScroll);
    }
    if (widget.batchMode ||
        widget.todo.id != oldWidget.todo.id ||
        widget.swipeDismissSerial != oldWidget.swipeDismissSerial) {
      _swipeOffset = 0;
      _dragging = false;
    }
  }

  void _closeSwipe() {
    if (!_swipeOpen || !mounted) return;
    setState(() => _swipeOffset = 0);
  }

  Future<void> _openDetails(BuildContext context) async {
    _closeSwipe();
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TodoDetailScreen(
          todoId: widget.todo.id,
          accountGeneration: accountGeneration,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(_TodoActionOrigin origin) async {
    if (!mounted || !origin.isCurrent()) return;
    _closeSwipe();
    await _confirmTodoDeletion(
      origin,
      isRowCurrent: () =>
          mounted &&
          widget.todo.id == origin.id &&
          widget.todo.workspaceId == origin.workspaceId,
    );
  }

  Future<void> _toggleCompletion(BuildContext context) async {
    _closeSwipe();
    await _toggleTodoCompletionFromSwipe(context, widget.todo);
  }

  @override
  Widget build(BuildContext context) {
    final todo = widget.todo;
    final visual = CompletionVisibilityPolicy.visualState(todo);
    // Archived rows require the explicit history filter.
    if (visual == TodoVisualState.archived && !widget.showArchived) {
      return const SizedBox.shrink();
    }

    context.watch<TodoProvider>();
    final deleteOrigin = _TodoActionOrigin(context, todo);
    final canEdit = context.watch<ShareProvider>().canEdit(todo.workspaceId);
    final cs = Theme.of(context).colorScheme;
    final qColor = _quadrantColor(todo.quadrant);
    final stateColor = CompletionVisibilityPolicy.colorFor(visual);
    final visualAccentColor = switch (visual) {
      TodoVisualState.completed ||
      TodoVisualState.overdue ||
      TodoVisualState.dueSoon => stateColor,
      _ => qColor,
    };
    final statusBackground = switch (visual) {
      TodoVisualState.completed => Color.alphaBlend(
        stateColor.withValues(alpha: 0.06),
        cs.surface,
      ),
      TodoVisualState.overdue => Color.alphaBlend(
        stateColor.withValues(alpha: 0.08),
        cs.surface,
      ),
      TodoVisualState.dueSoon => Color.alphaBlend(
        stateColor.withValues(alpha: 0.07),
        cs.surface,
      ),
      _ => cs.surface,
    };
    final statusBorder = switch (visual) {
      TodoVisualState.completed ||
      TodoVisualState.overdue ||
      TodoVisualState.dueSoon => Border.all(
        color: stateColor.withValues(alpha: 0.24),
        width: 0.7,
      ),
      _ => null,
    };
    final content = Container(
      margin: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceMd,
        vertical: DesignTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: widget.selected
            ? cs.primary.withValues(alpha: 0.08)
            : statusBackground,
        borderRadius: DesignTokens.borderRadiusMd,
        border: widget.selected
            ? Border.all(color: cs.primary.withValues(alpha: 0.28))
            : statusBorder,
        boxShadow: DesignTokens.shadowXs,
      ),
      child: ClipRRect(
        borderRadius: DesignTokens.borderRadiusMd,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(color: visualAccentColor),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.batchMode
                    ? canEdit
                          ? () => widget.onToggleSelection(todo.id)
                          : null
                    : _swipeOpen
                    ? _closeSwipe
                    : () => _openDetails(context),
                onLongPress: canEdit
                    ? () => widget.onEnterBatchMode(todo.id)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spaceSm + 4,
                    DesignTokens.spaceSm,
                    DesignTokens.spaceSm,
                    DesignTokens.spaceSm,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          top: DesignTokens.spaceXxs,
                        ),
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: Checkbox(
                            value: widget.batchMode
                                ? widget.selected
                                : todo.isCompleted,
                            shape: const CircleBorder(),
                            activeColor: visualAccentColor,
                            onChanged: canEdit
                                ? (_) {
                                    if (widget.batchMode) {
                                      widget.onToggleSelection(todo.id);
                                    } else {
                                      completeTodoWithOptionalTimeRecord(
                                        context,
                                        todo,
                                      );
                                    }
                                  }
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spaceXs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _TitleRow(todo: todo, visual: visual),
                            const SizedBox(height: DesignTokens.spaceXxs),
                            _MetaRow(
                              todo: todo,
                              quadrantColor: qColor,
                              visual: visual,
                            ),
                          ],
                        ),
                      ),
                      if (widget.trailing != null) widget.trailing!,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.batchMode) return content;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification ||
            notification is UserScrollNotification ||
            notification is ScrollUpdateNotification) {
          _closeSwipe();
        }
        return false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: canEdit
            ? (_) => setState(() => _dragging = true)
            : null,
        onHorizontalDragUpdate: canEdit
            ? (details) {
                final next = (_swipeOffset - details.delta.dx).clamp(
                  0.0,
                  _swipeActionWidth,
                );
                if (next == _swipeOffset) return;
                setState(() => _swipeOffset = next);
              }
            : null,
        onHorizontalDragEnd: canEdit
            ? (_) {
                final shouldOpen = _swipeOffset >= _swipeOpenThreshold;
                setState(() {
                  _dragging = false;
                  _swipeOffset = shouldOpen ? _swipeActionWidth : 0;
                });
              }
            : null,
        onHorizontalDragCancel: canEdit
            ? () => setState(() {
                _dragging = false;
                _swipeOffset = _swipeOffset >= _swipeOpenThreshold
                    ? _swipeActionWidth
                    : 0;
              })
            : null,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            if (_swipeActive)
              Positioned.fill(
                child: RepaintBoundary(
                  child: _TodoInlineSwipeActions(
                    margin: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spaceMd,
                      vertical: DesignTokens.spaceSm,
                    ),
                    onToggleCompletion: () => _toggleCompletion(context),
                    onDelete: () => _confirmDelete(deleteOrigin),
                    completed: todo.isCompleted,
                  ),
                ),
              ),
            AnimatedContainer(
              duration: _dragging
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(-_swipeOffset, 0, 0),
              child: RepaintBoundary(child: content),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodoInlineSwipeActions extends StatelessWidget {
  final EdgeInsetsGeometry margin;
  final VoidCallback onToggleCompletion;
  final VoidCallback onDelete;
  final bool completed;

  const _TodoInlineSwipeActions({
    required this.margin,
    required this.onToggleCompletion,
    required this.onDelete,
    required this.completed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.74),
        borderRadius: DesignTokens.borderRadiusMd,
      ),
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: _TodoTileState._swipeActionWidth,
        height: double.infinity,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _TodoInlineSwipeButton(
              key: ValueKey(
                completed
                    ? 'todo_swipe_reopen_button'
                    : 'todo_swipe_complete_button',
              ),
              icon: completed
                  ? Icons.undo_outlined
                  : Icons.check_circle_outline,
              label: completed
                  ? TodoBoardUiCopy.swipeRestore
                  : TodoBoardUiCopy.swipeComplete,
              background:
                  (completed ? cs.tertiaryContainer : cs.secondaryContainer)
                      .withValues(alpha: 0.60),
              foreground: completed ? cs.tertiary : cs.secondary,
              onTap: onToggleCompletion,
            ),
            const SizedBox(width: 6),
            _TodoInlineSwipeButton(
              key: const ValueKey('todo_swipe_delete_button'),
              icon: Icons.delete_outline,
              label: TodoBoardUiCopy.swipeDelete,
              background: cs.errorContainer.withValues(alpha: 0.64),
              foreground: cs.error,
              onTap: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _TodoInlineSwipeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _TodoInlineSwipeButton({
    super.key,
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: background,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 40,
              child: Icon(icon, color: foreground, size: 18),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _toggleTodoCompletionFromSwipe(
  BuildContext context,
  TodoItem todo,
) async {
  if (todo.isCompleted) {
    final count = await context.read<TodoProvider>().reopenTodos([todo.id]);
    if (!context.mounted || count == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (_, _, _) =>
              Text(TodoBoardUiCopy.restoredFeedback(todo.title)),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  await completeTodoWithOptionalTimeRecord(context, todo);
}

/// 标题 + 优先级色点。
class _TitleRow extends StatelessWidget {
  final TodoItem todo;
  final TodoVisualState visual;
  const _TitleRow({required this.todo, required this.visual});

  @override
  Widget build(BuildContext context) {
    final isCompleted = visual == TodoVisualState.completed;
    final baseColor = Theme.of(context).colorScheme.onSurface;
    final titleColor = isCompleted
        ? baseColor.withValues(alpha: DesignTokens.completedTextOpacity)
        : null;

    return Row(
      children: [
        if (todo.priority != TodoPriority.none) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: priorityColor(todo.priority),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: DesignTokens.spaceXs),
        ],
        Expanded(
          child: Text(
            todo.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: DesignTokens.fontSizeBase,
              color: titleColor,
              decoration: isCompleted ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// 元信息行：优先级胶囊、重复、过期、子任务、标签、目标时长、下次提醒、截止日。
class _MetaRow extends StatelessWidget {
  final TodoItem todo;
  final Color quadrantColor;
  final TodoVisualState visual;

  const _MetaRow({
    required this.todo,
    required this.quadrantColor,
    required this.visual,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    Color pillForeground(Color color) => appReadableForeground(
      Color.alphaBlend(
        color.withValues(alpha: isDark ? 0.18 : 0.12),
        cs.surface,
      ),
      color,
    );
    final chips = <Widget>[];
    final shareProvider = context.watch<ShareProvider>();

    if (todo.priority != TodoPriority.none) {
      final c = priorityColor(todo.priority);
      chips.add(
        _MetaPill(
          color: c,
          child: Text(
            todo.priority.label,
            style: TextStyle(
              fontSize: DesignTokens.fontSizeXs,
              color: c,
              fontWeight: DesignTokens.fontWeightRegular,
            ),
          ),
        ),
      );
    }

    if (todo.recurrence.isActive) {
      chips.add(Icon(Icons.repeat, size: 12, color: cs.onSurfaceVariant));
    }

    // 已完成：绿色 "已完成" 徽章。
    if (visual == TodoVisualState.completed) {
      final c = CompletionVisibilityPolicy.colorFor(TodoVisualState.completed);
      final brandId = context.watch<ThemeProvider?>()?.brand.id;
      final isTargetLightBrand = !isDark &&
          (brandId == null ||
              brandId == 'defaultBrand' ||
              brandId == 'liquidGlass');
      final completedForeground =
          isTargetLightBrand ? const Color(0xFF1B5E20) : c;
      chips.add(
        _MetaPill(
          color: c,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 11, color: completedForeground),
              const SizedBox(width: 2),
              Text(
                TodoBoardUiCopy.cardCompletedBadge,
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeXs,
                  color: completedForeground,
                  fontWeight: DesignTokens.fontWeightRegular,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 临期：橙色 "临期" 胶囊 + 闪烁 alarm icon。
    if (visual == TodoVisualState.dueSoon) {
      final c = CompletionVisibilityPolicy.colorFor(TodoVisualState.dueSoon);
      chips.add(
        _MetaPill(
          color: c,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BlinkingIcon(icon: Icons.alarm, color: c, size: 11),
              const SizedBox(width: 2),
              Text(
                TodoBoardUiCopy.badgeDueSoon,
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeXs,
                  color: c,
                  fontWeight: DesignTokens.fontWeightRegular,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 已过期：红色 "过期" 胶囊。沿用已有视觉语义，统一 token 色。
    if (visual == TodoVisualState.overdue) {
      final c = CompletionVisibilityPolicy.colorFor(TodoVisualState.overdue);
      chips.add(
        _MetaPill(
          color: c,
          child: Text(
            TodoBoardUiCopy.badgeOverdue,
            style: TextStyle(
              fontSize: DesignTokens.fontSizeXs,
              color: c,
              fontWeight: DesignTokens.fontWeightRegular,
            ),
          ),
        ),
      );
    }

    if (todo.subtasks.isNotEmpty) {
      chips.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 12,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 2),
            Text(
              '${todo.subtasks.where((s) => s.isCompleted).length}/${todo.subtasks.length}',
              style: TextStyle(
                fontSize: DesignTokens.fontSizeSm,
                color: cs.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
    }

    // 标签：最多展示前 3 个，多出部分以 "+N" 汇总。
    if (todo.tags.isNotEmpty) {
      const maxShown = 3;
      final shown = todo.tags.take(maxShown).toList();
      final tagColor = cs.primary;
      final tagFg = pillForeground(tagColor);
      for (final t in shown) {
        chips.add(
          _MetaPill(
            color: tagColor,
            child: Text(
              '#$t',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                color: tagFg,
              ),
            ),
          ),
        );
      }
      final overflow = todo.tags.length - shown.length;
      if (overflow > 0) {
        final overflowColor = cs.onSurfaceVariant;
        final overflowFg = pillForeground(overflowColor);
        chips.add(
          _MetaPill(
            color: overflowColor,
            child: Text(
              '+$overflow',
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                color: overflowFg,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        );
      }
    }

    // 目标时长
    final tSec = todo.timeTargetSeconds;
    if (tSec != null && tSec > 0) {
      final durationColor = DesignTokens.defaultAccent;
      final durationFg = pillForeground(durationColor);
      chips.add(
        _MetaPill(
          color: durationColor,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_bottom, size: 11, color: durationFg),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  TodoBoardUiCopy.badgeTargetMinutes(tSec ~/ 60),
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeXs,
                    color: durationFg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 下一次提醒。临期状态下把 alarm icon 也闪烁一下，强化提示。
    final r = todo.reminder;
    if (r.enabled && r.hour != null && r.minute != null) {
      final reminderTime = I18nDateFormat.timeOfDay(
        hour: r.hour!,
        minute: r.minute!,
      );
      final icon = r.kind == ReminderKind.alarm
          ? Icons.alarm
          : r.kind == ReminderKind.popup
          ? Icons.open_in_new
          : Icons.notifications;
      final reminderColor = visual == TodoVisualState.dueSoon
          ? CompletionVisibilityPolicy.colorFor(TodoVisualState.dueSoon)
          : DesignTokens.defaultInfo;
      final reminderFg = pillForeground(reminderColor);
      final iconWidget = visual == TodoVisualState.dueSoon
          ? _BlinkingIcon(icon: icon, color: reminderFg, size: 11)
          : Icon(icon, size: 11, color: reminderFg);
      chips.add(
        _MetaPill(
          color: reminderColor,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconWidget,
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  TodoBoardUiCopy.badgeNextReminder(reminderTime),
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeXs,
                    color: reminderFg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (todo.dueDate != null) {
      chips.add(
        _MetaPill(
          color: quadrantColor,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today, size: 10, color: quadrantColor),
              const SizedBox(width: 4),
              Text(
                I18nDateFormat.monthDay(todo.dueDate!),
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeXs,
                  color: quadrantColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (todo.workspaceId != 'private') {
      chips.add(
        _MetaPill(
          color: Theme.of(context).colorScheme.primary,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.groups_2_outlined,
                size: 11,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 2),
              Text(
                TodoBoardUiCopy.badgeShared,
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeXs,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final assigneeName = _assigneeName(shareProvider, todo);
    if (assigneeName != null) {
      final assigneeColor = cs.tertiary;
      final assigneeFg = pillForeground(assigneeColor);
      chips.add(
        _MetaPill(
          color: assigneeColor,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.assignment_ind_outlined,
                size: 11,
                color: assigneeFg,
              ),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  '@$assigneeName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeXs,
                    color: assigneeFg,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: DesignTokens.spaceXs,
      runSpacing: DesignTokens.spaceXxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: chips,
    );
  }

  String? _assigneeName(ShareProvider provider, TodoItem todo) {
    final assigneeId = todo.assigneeId;
    if (assigneeId == null || assigneeId.isEmpty) return null;
    for (final workspace in provider.workspaces) {
      if (workspace.id != todo.workspaceId) continue;
      for (final member in workspace.members) {
        if (member.userId == assigneeId) {
          return member.username.isEmpty ? member.userId : member.username;
        }
      }
    }
    return assigneeId;
  }
}

class _BlinkingIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const _BlinkingIcon({
    required this.icon,
    required this.color,
    this.size = 12,
  });

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: size, color: color.withValues(alpha: 0.92));
}

/// 统一的元信息胶囊（带 12% 底色）。
class _MetaPill extends StatelessWidget {
  final Color color;
  final Widget child;

  const _MetaPill({required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceXs,
          vertical: 1,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: DesignTokens.borderRadiusSm,
        ),
        child: child,
      ),
    );
  }
}

class QuadrantListScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  final EisenhowerQuadrant quadrant;
  final TodoFilterState<EisenhowerQuadrant, TodoPriority>? filter;

  /// 右下角新建入口（由主屏传入，如 _showAddDialog）；null 时无 FAB。
  /// 触发时携带本页象限，新建待办默认落入该象限。
  final ValueChanged<EisenhowerQuadrant>? onCreateTodo;

  const QuadrantListScreen({
    super.key,
    required this.quadrant,
    this.filter,
    this.onCreateTodo,
  });

  @override
  State<QuadrantListScreen> createState() => _QuadrantListScreenState();
}

class _QuadrantListScreenState extends State<QuadrantListScreen> {
  int _swipeDismissSerial = 0;
  bool _scrollDismissScheduled = false;
  bool _batchMode = false;
  bool _batchSubmitting = false;
  final Set<String> _selectedTodoIds = <String>{};

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_onLocaleChanged);
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _enterBatchMode(String todoId) {
    setState(() {
      _batchMode = true;
      _selectedTodoIds.add(todoId);
    });
  }

  void _exitBatchMode() {
    setState(() {
      _batchMode = false;
      _selectedTodoIds.clear();
    });
  }

  void _toggleSelection(String todoId) {
    setState(() {
      if (!_selectedTodoIds.add(todoId)) {
        _selectedTodoIds.remove(todoId);
      }
    });
  }

  void _selectAllVisible(Iterable<String> editableIds) {
    if (_batchSubmitting) return;
    final ids = editableIds.toSet();
    setState(() {
      _batchMode = true;
      if (_selectedTodoIds.containsAll(ids)) {
        _selectedTodoIds.removeAll(ids);
        if (_selectedTodoIds.isEmpty) _batchMode = false;
      } else {
        _selectedTodoIds.addAll(ids);
      }
    });
  }

  Future<void> _runBatchAction(
    Future<int> Function(Set<String> ids) action,
    String Function(int count) message,
  ) async {
    if (_batchSubmitting) return;
    final ids = _visibleEditableSelection();
    if (ids.isEmpty) return;
    setState(() => _batchSubmitting = true);
    try {
      final count = await action(ids);
      if (!mounted) return;
      _exitBatchMode();
      _showBatchSnack(() => message(count));
    } finally {
      if (mounted) {
        setState(() => _batchSubmitting = false);
      }
    }
  }

  void _showBatchSnack(Object message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, _, _) => Text(
            message is ValueGetter<String> ? message() : message.toString(),
          ),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _completeSelected() async {
    await _runBatchAction(
      (ids) => context.read<TodoProvider>().completeTodos(ids),
      (count) => TodoBoardUiCopy.batchCompleted(count),
    );
  }

  Future<void> _reopenSelected() async {
    await _runBatchAction(
      (ids) => context.read<TodoProvider>().reopenTodos(ids),
      (count) => TodoBoardUiCopy.batchReopened(count),
    );
  }

  Future<void> _moveSelected(EisenhowerQuadrant quadrant) async {
    await _runBatchAction(
      (ids) => context.read<TodoProvider>().updateTodosQuadrant(ids, quadrant),
      (count) => TodoBoardUiCopy.batchMoved(
        count,
        TodoBoardUiCopy.quadrantLabel(quadrant),
      ),
    );
  }

  Future<void> _setSelectedPriority(TodoPriority priority) async {
    await _runBatchAction(
      (ids) => context.read<TodoProvider>().updateTodosPriority(ids, priority),
      (count) => TodoBoardUiCopy.batchPriorityUpdated(count),
    );
  }

  Future<void> _rescheduleSelectedDueDate() async {
    if (_batchSubmitting || _visibleEditableSelection().isEmpty) return;
    final choice = await _showBatchDueDatePickerDialog(context);
    if (choice == null || !mounted) return;
    await _runBatchAction(
      (ids) =>
          context.read<TodoProvider>().rescheduleTodosDueDate(ids, choice.dueDate),
      (count) => I18n.current == AppLocale.en
          ? 'Updated due date for $count tasks'
          : '已调整 $count 个任务的截止日期',
    );
  }

  Future<void> _assignSelectedList(List<String> availableLists) async {
    if (_batchSubmitting || _visibleEditableSelection().isEmpty) return;
    final choice = await _showBatchListPickerDialog(
      context,
      availableLists: availableLists,
    );
    if (choice == null || !mounted) return;
    await _runBatchAction(
      (ids) =>
          context.read<TodoProvider>().assignTodosListGroup(ids, choice.listName),
      (count) => I18n.current == AppLocale.en
          ? 'Updated list for $count tasks'
          : '已更新 $count 个任务的所属清单',
    );
  }

  Future<void> _assignSelectedTags(List<String> availableTags) async {
    if (_batchSubmitting || _visibleEditableSelection().isEmpty) return;
    final tags = await _showBatchTagPickerDialog(
      context,
      availableTags: availableTags,
    );
    if (tags == null || tags.isEmpty || !mounted) return;
    await _runBatchAction(
      (ids) => context.read<TodoProvider>().assignTagsToTodos(ids, tags),
      (count) => I18n.current == AppLocale.en
          ? 'Added tags to $count tasks'
          : '已为 $count 个任务添加标签',
    );
  }

  Future<void> _deleteSelected() async {
    if (_batchSubmitting) return;
    final selectedCount = _visibleEditableSelection().length;
    if (selectedCount == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (context, _, _) => AppDialog(
          icon: const Icon(Icons.delete_outline),
          title: Text(TodoBoardUiCopy.deleteSelectedTasksTitle),
          content: Text(
            TodoBoardUiCopy.deleteSelectedTasksContent(selectedCount),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(TodoBoardUiCopy.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: Text(TodoBoardUiCopy.delete),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    await _runBatchAction(
      (ids) => context.read<TodoProvider>().deleteTodos(ids),
      (count) => TodoBoardUiCopy.batchDeleted(count),
    );
  }

  bool _dismissSwipeActionsOnScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification ||
        notification is UserScrollNotification) {
      if (!mounted) return false;
      if (_scrollDismissScheduled) return false;

      final isFrameBusy =
          SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks;

      if (isFrameBusy) {
        _scrollDismissScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollDismissScheduled = false;
          if (mounted) {
            setState(() => _swipeDismissSerial++);
          }
        });
      } else {
        setState(() => _swipeDismissSerial++);
      }
    }
    return false;
  }

  String _title(EisenhowerQuadrant q) {
    return TodoBoardUiCopy.quadrantLabel(q);
  }

  List<TodoItem> _visibleTodos(
    TodoProvider provider,
    PreferencesProvider? preferences,
  ) {
    final filter =
        widget.filter?.copyWith(quadrant: widget.quadrant) ??
        TodoFilterState<EisenhowerQuadrant, TodoPriority>(
          quadrant: widget.quadrant,
        );
    final baseTodos = filter.includeArchived
        ? provider.todos
        : provider.visibleListTodos;
    return filterTodos(
      baseTodos,
      effectiveTodoFilter(
        filter,
        showCompletedTodos: preferences?.showCompletedTodos ?? true,
      ),
      now: DateTime.now(),
      quadrantOf: (todo) => todo.quadrant,
      priorityOf: (todo) => todo.priority,
      tagsOf: (todo) => todo.tags,
      listGroupNameOf: (todo) => todo.listGroupName,
      dueDateOf: (todo) => todo.dueDate,
      isCompletedOf: (todo) => todo.isCompleted,
      isArchivedAfterRolloverOf: (todo) => todo.isArchivedAfterRollover,
      isInTodayOverviewOf: CompletionVisibilityPolicy.isInTodayOverview,
    );
  }

  Set<String> _visibleEditableSelection() {
    if (!mounted) return {};
    final provider = context.read<TodoProvider>();
    final preferences = context.read<PreferencesProvider?>();
    final share = context.read<ShareProvider>();
    return _visibleTodos(provider, preferences)
        .where(
          (todo) =>
              _selectedTodoIds.contains(todo.id) &&
              share.canEdit(todo.workspaceId),
        )
        .map((todo) => todo.id)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final todos = _visibleTodos(
      context.watch<TodoProvider>(),
      context.watch<PreferencesProvider?>(),
    );
    final shareProvider = context.watch<ShareProvider>();
    final editableVisibleIds = todos
        .where((todo) => shareProvider.canEdit(todo.workspaceId))
        .map((todo) => todo.id)
        .toList();
    _selectedTodoIds.retainAll(editableVisibleIds);
    final allVisibleSelected =
        editableVisibleIds.isNotEmpty &&
        editableVisibleIds.every(_selectedTodoIds.contains);
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;

    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : null,
      appBar: AppBar(
        leading: _batchMode
            ? IconButton(
                tooltip: TodoBoardUiCopy.exitBatchModeTooltip,
                onPressed: _exitBatchMode,
                icon: const Icon(Icons.close),
              )
            : null,
        title: Text(
          _batchMode
              ? TodoBoardUiCopy.batchModeSelected(_selectedTodoIds.length)
              : _title(widget.quadrant),
        ),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        actions: [
          if (_batchMode)
            IconButton(
              tooltip: TodoBoardUiCopy.selectAllTooltip(allVisibleSelected),
              onPressed: editableVisibleIds.isEmpty
                  ? null
                  : () => _selectAllVisible(editableVisibleIds),
              icon: Icon(
                allVisibleSelected
                    ? Icons.deselect_outlined
                    : Icons.select_all_outlined,
              ),
            )
          else
            IconButton(
              tooltip: TodoBoardUiCopy.batchManageTooltip,
              icon: const Icon(Icons.checklist_rounded),
              onPressed: todos.isEmpty
                  ? null
                  : () => setState(() => _batchMode = true),
            ),
        ],
      ),
      body: todos.isEmpty
          ? EmptyState(
              icon: Icons.inbox,
              message: TodoBoardUiCopy.quadrantDetailEmpty,
            )
          : NotificationListener<ScrollNotification>(
              onNotification: _dismissSwipeActionsOnScroll,
              child: ListView.builder(
                padding: !_batchMode && widget.onCreateTodo != null
                    ? EdgeInsets.only(
                        bottom: 88.0 + MediaQuery.paddingOf(context).bottom,
                      )
                    : null,
                // ignore: deprecated_member_use
                cacheExtent: 640,
                itemCount: todos.length,
                itemBuilder: (context, index) {
                  final todo = todos[index];
                  return _TodoTile(
                    todo: todo,
                    showArchived: widget.filter?.includeArchived ?? false,
                    batchMode: _batchMode,
                    selected: _selectedTodoIds.contains(todo.id),
                    onToggleSelection: _toggleSelection,
                    onEnterBatchMode: _enterBatchMode,
                    swipeDismissSerial: _swipeDismissSerial,
                  );
                },
              ),
            ),
      bottomNavigationBar: _batchMode
          ? _TodoBatchActionBar(
              selectedCount: _selectedTodoIds.length,
              submitting: _batchSubmitting,
              onComplete: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : _completeSelected,
              onReopen: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : _reopenSelected,
              onMove: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : _moveSelected,
              onPriority: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : _setSelectedPriority,
              onRescheduleDueDate: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : _rescheduleSelectedDueDate,
              onAssignList: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : () => _assignSelectedList(
                      collectTodoListGroups(
                        context.read<TodoProvider>().visibleListTodos,
                        (t) => t.listGroupName,
                      ),
                    ),
              onAssignTags: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : () => _assignSelectedTags(
                      collectTodoTags(
                        context.read<TodoProvider>().visibleListTodos,
                        (t) => t.tags,
                      ),
                    ),
              onDelete: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : _deleteSelected,
            )
          : null,
      floatingActionButton: _batchMode || widget.onCreateTodo == null
          ? null
          : FloatingActionButton(
              heroTag: 'quadrant_todo_add_fab_${widget.quadrant.index}',
              // 在本象限新建：把当前象限带回主屏的新建入口。
              onPressed: () => widget.onCreateTodo!(widget.quadrant),
              child: const Icon(Icons.add),
            ),
    );

    if (!isLiquidGlass) {
      return scaffold;
    }

    final hasBrandSurface =
        context.findAncestorWidgetOfExactType<BrandBackground>() != null ||
        context.findAncestorWidgetOfExactType<BrandRouteSurface>() != null;
    if (hasBrandSurface) {
      return scaffold;
    }
    return Material(
      color: routeBackground,
      child: BrandBackground(child: scaffold),
    );
  }
}
