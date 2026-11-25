import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/completion_visibility_policy.dart';
import '../../core/i18n.dart';
import '../../core/i18n_date_format.dart';
import '../../core/smart_todo_draft.dart';
import '../../core/todo_detail_ui_copy.dart';
import '../../core/todo_filters.dart';
import '../../core/todo_kanban.dart';
import '../../core/todo_templates.dart';
import '../../core/todo_ui_copy.dart';
import '../../models/goal.dart' show ReminderKind;
import '../../models/recurrence.dart';
import '../../models/todo.dart';
import '../../providers/preferences_provider.dart';
import '../../providers/share_provider.dart';
import '../../providers/todo_provider.dart';
import '../../widgets/app_date_format.dart';
import '../../widgets/app_date_picker.dart';
import '../../widgets/recurrence_picker.dart';
import '../../widgets/reminder_plan_editor.dart';
import '../desktop_web_nav.dart';
import '../desktop_web_tokens.dart';

enum _TodoSmartFilter { all, today, next7Days, highPriority, completed }

enum _TodoViewMode { list, kanban, matrix }

enum _TodoSortMode { manual, smart, priority, dueDate, createdAt }

/// True 3-pane TickTick/Things-inspired Desktop Todo Workspace.
///
/// Pane 1 (`216px`): Smart filters + user lists + inline list creator.
/// Pane 2 (`Expanded`): Toolbar (`List / Board / Matrix`), persistent inline
/// quick-add bar, and interactive rows / Kanban columns / 2x2 matrix.
/// Pane 3 (`320px`): Live inline task detail editor or structured shortcuts view.
class DesktopTodoView extends StatefulWidget {
  const DesktopTodoView({
    super.key,
    this.controller,
    this.initialSelectedTodoId,
    this.onStartFocus,
  });

  final DesktopWebNavController? controller;
  final String? initialSelectedTodoId;
  final void Function({String? taskTitle})? onStartFocus;

  @override
  State<DesktopTodoView> createState() => _DesktopTodoViewState();
}

class _DesktopTodoDerivedData {
  final List<TodoItem> allTodos;
  final List<String> mergedLists;
  final List<String> availableTags;
  final List<TodoItem> filteredTodos;
  final int allCount;
  final int todayCount;
  final int weekCount;
  final int highCount;
  final int completedCount;
  final Map<String, int> listCounts;
  final Map<String, List<TodoItem>> kanbanGroups;
  final Map<EisenhowerQuadrant, List<TodoItem>> quadrantGroups;

  const _DesktopTodoDerivedData({
    required this.allTodos,
    required this.mergedLists,
    required this.availableTags,
    required this.filteredTodos,
    required this.allCount,
    required this.todayCount,
    required this.weekCount,
    required this.highCount,
    required this.completedCount,
    required this.listCounts,
    required this.kanbanGroups,
    required this.quadrantGroups,
  });
}

class _DesktopTodoViewState extends State<DesktopTodoView> {
  static const String _customListsPrefsKey = 'desktop_todo_custom_lists_v1';

  _TodoSmartFilter _smartFilter = _TodoSmartFilter.all;
  String? _selectedListName;
  String? _selectedTag;
  String _searchQuery = '';
  _TodoViewMode _viewMode = _TodoViewMode.list;
  _TodoSortMode _sortMode = _TodoSortMode.smart;
  bool _showCompletedInList = false;
  bool? _syncedPrefShowCompleted;

  bool _batchMode = false;
  final Set<String> _selectedIds = <String>{};
  bool _batchBusy = false;

  String? _selectedTodoId;
  bool _creatingList = false;
  final TextEditingController _newListController = TextEditingController();
  final FocusNode _newListFocusNode = FocusNode();
  final List<String> _customListNames = <String>[];

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _quickAddController = TextEditingController();
  final FocusNode _quickAddFocusNode = FocusNode();
  bool _quickAddFocused = false;
  TodoPriority _quickAddPriority = TodoPriority.none;
  bool _quickAddToday = false;

  final TextEditingController _titleEditController = TextEditingController();
  final FocusNode _titleEditFocusNode = FocusNode();
  final TextEditingController _notesEditController = TextEditingController();
  final FocusNode _notesEditFocusNode = FocusNode();
  final TextEditingController _subtaskAddController = TextEditingController();
  final TextEditingController _tagInputController = TextEditingController();

  String? _boundTodoId;
  bool _pendingDeleteConfirm = false;
  bool _subtaskSubmitting = false;
  bool _reminderEditorExpanded = false;

  TodoKanbanBoardConfig _kanbanConfig = TodoKanbanBoardConfig.defaults();
  DesktopWebNavController? _attachedController;
  String? _lastTopBarSignature;
  int _customListsVersion = 0;

  _DesktopTodoDerivedData? _derived;
  TodoProvider? _derivedProvider;
  int? _derivedRevision;
  int? _derivedMinuteKey;
  _TodoSmartFilter? _derivedSmartFilter;
  String? _derivedSelectedListName;
  String? _derivedSelectedTag;
  String? _derivedSearchQuery;
  _TodoViewMode? _derivedViewMode;
  _TodoSortMode? _derivedSortMode;
  bool? _derivedShowCompletedInList;
  TodoKanbanBoardConfig? _derivedKanbanConfig;
  int? _derivedCustomListsVersion;

  @override
  void initState() {
    super.initState();
    _selectedTodoId = widget.initialSelectedTodoId;
    _quickAddFocusNode.addListener(_onQuickAddFocusChanged);
    _titleEditFocusNode.addListener(_onTitleFocusChanged);
    _notesEditFocusNode.addListener(_onNotesFocusChanged);
    unawaited(_loadKanbanConfig());
    unawaited(_loadCustomLists());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextController = widget.controller ?? DesktopWebScope.maybeOf(context);
    if (!identical(nextController, _attachedController)) {
      _attachedController?.removeListener(_onControllerChanged);
      _attachedController = nextController;
      _attachedController?.addListener(_onControllerChanged);
      final controllerSelected = nextController?.selectedTodoId;
      if (controllerSelected != null && controllerSelected != _selectedTodoId) {
        _selectedTodoId = controllerSelected;
      }
    }
  }

  @override
  void didUpdateWidget(covariant DesktopTodoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSelectedTodoId != oldWidget.initialSelectedTodoId &&
        widget.initialSelectedTodoId != null) {
      _selectTodo(widget.initialSelectedTodoId, syncController: false);
    }
  }

  @override
  void dispose() {
    _attachedController?.removeListener(_onControllerChanged);
    _quickAddFocusNode.removeListener(_onQuickAddFocusChanged);
    _titleEditFocusNode.removeListener(_onTitleFocusChanged);
    _notesEditFocusNode.removeListener(_onNotesFocusChanged);
    _newListController.dispose();
    _newListFocusNode.dispose();
    _searchController.dispose();
    _quickAddController.dispose();
    _quickAddFocusNode.dispose();
    _titleEditController.dispose();
    _titleEditFocusNode.dispose();
    _notesEditController.dispose();
    _notesEditFocusNode.dispose();
    _subtaskAddController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomLists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_customListsPrefsKey);
      if (!mounted || saved == null || saved.isEmpty) return;
      setState(() {
        var added = false;
        for (final name in saved) {
          final trimmed = name.trim();
          if (trimmed.isNotEmpty && !_customListNames.contains(trimmed)) {
            _customListNames.add(trimmed);
            added = true;
          }
        }
        if (added) _customListsVersion++;
      });
    } catch (_) {
      // Ignore preference read errors gracefully.
    }
  }

  Future<void> _saveCustomLists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _customListsPrefsKey,
        List<String>.of(_customListNames),
      );
    } catch (_) {
      // Ignore preference write errors gracefully.
    }
  }

  Future<void> _loadKanbanConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(todoKanbanColumnsPrefsKey);
      if (!mounted || raw == null || raw.trim().isEmpty) return;
      setState(() {
        _kanbanConfig = TodoKanbanBoardConfig.decode(raw);
      });
    } catch (_) {
      // Fallback safely to built-in default columns when preferences are unavailable.
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final fromController = _attachedController?.selectedTodoId;
    if (fromController != null && fromController != _selectedTodoId) {
      _selectTodo(fromController, syncController: false);
    }
  }

  void _onQuickAddFocusChanged() {
    if (!mounted) return;
    if (_quickAddFocusNode.hasFocus != _quickAddFocused) {
      setState(() => _quickAddFocused = _quickAddFocusNode.hasFocus);
    }
  }

  void _onTitleFocusChanged() {
    if (!_titleEditFocusNode.hasFocus) {
      _commitInspectorTitle();
    }
  }

  void _onNotesFocusChanged() {
    if (!_notesEditFocusNode.hasFocus) {
      _commitInspectorNotes();
    }
  }

  void _selectTodo(String? todoId, {bool syncController = true}) {
    if (_selectedTodoId != null && _selectedTodoId != todoId) {
      _commitInspectorTitle();
      _commitInspectorNotes();
    }
    setState(() {
      _selectedTodoId = todoId;
      _pendingDeleteConfirm = false;
    });
    if (syncController) {
      _attachedController?.selectTodo(todoId);
    }
  }

  T? _watchOptional<T>(BuildContext context) {
    try {
      return Provider.of<T>(context);
    } on ProviderNotFoundException {
      return null;
    }
  }

  R _selectOptional<T extends Object, R>(
    BuildContext context,
    R Function(T? provider) selector,
    R fallback,
  ) {
    try {
      return context.select<T?, R>(selector);
    } on ProviderNotFoundException {
      return fallback;
    }
  }

  _DesktopTodoDerivedData _derivedDataFor(
    TodoProvider? todoProvider,
    DateTime now,
    DateTime today,
    int minuteKey,
  ) {
    final revision = todoProvider?.revision ?? -1;
    final cached = _derived;
    if (cached != null &&
        identical(_derivedProvider, todoProvider) &&
        _derivedRevision == revision &&
        _derivedMinuteKey == minuteKey &&
        _derivedSmartFilter == _smartFilter &&
        _derivedSelectedListName == _selectedListName &&
        _derivedSelectedTag == _selectedTag &&
        _derivedSearchQuery == _searchQuery &&
        _derivedViewMode == _viewMode &&
        _derivedSortMode == _sortMode &&
        _derivedShowCompletedInList == _showCompletedInList &&
        identical(_derivedKanbanConfig, _kanbanConfig) &&
        _derivedCustomListsVersion == _customListsVersion) {
      return cached;
    }

    final allTodos = todoProvider?.todos ?? const <TodoItem>[];
    final mergedLists = _collectListNames(todoProvider);
    final availableTags = collectTodoTags(
      allTodos.where((t) => !t.isArchivedAfterRollover),
      (t) => t.tags,
    );
    final filteredTodos = _filterAndSortTodos(allTodos, now, today);

    final weekEnd = today.add(const Duration(days: 6));
    var allCount = 0;
    var todayCount = 0;
    var weekCount = 0;
    var highCount = 0;
    var completedCount = 0;
    final listCounts = <String, int>{};

    for (final t in allTodos) {
      if (t.isArchivedAfterRollover) continue;
      if (t.isCompleted) {
        completedCount++;
      } else {
        allCount++;
        final due = t.dueDate;
        if (due != null) {
          final d = CompletionVisibilityPolicy.dateOnly(due);
          if (!d.isBefore(today) && !d.isAfter(weekEnd)) {
            weekCount++;
          }
        }
        if (t.priority == TodoPriority.high ||
            t.priority == TodoPriority.urgent) {
          highCount++;
        }
        final listName = t.listGroupName;
        if (listName != null) {
          listCounts[listName] = (listCounts[listName] ?? 0) + 1;
        }
      }
      if (CompletionVisibilityPolicy.shouldShowInToday(t, now)) {
        todayCount++;
      }
    }

    final kanbanCols = _kanbanConfig.columns;
    final kanbanGroups = <String, List<TodoItem>>{
      for (final c in kanbanCols) c.id: <TodoItem>[],
    };
    final quadrantGroups = <EisenhowerQuadrant, List<TodoItem>>{
      for (final q in EisenhowerQuadrant.values) q: <TodoItem>[],
    };
    for (final t in filteredTodos) {
      final colId = _effectiveKanbanColumnId(t, kanbanCols);
      kanbanGroups.putIfAbsent(colId, () => <TodoItem>[]).add(t);
      quadrantGroups[t.quadrant]!.add(t);
    }

    final computed = _DesktopTodoDerivedData(
      allTodos: allTodos,
      mergedLists: List<String>.unmodifiable(mergedLists),
      availableTags: List<String>.unmodifiable(availableTags),
      filteredTodos: List<TodoItem>.unmodifiable(filteredTodos),
      allCount: allCount,
      todayCount: todayCount,
      weekCount: weekCount,
      highCount: highCount,
      completedCount: completedCount,
      listCounts: Map<String, int>.unmodifiable(listCounts),
      kanbanGroups: kanbanGroups.map(
        (k, v) => MapEntry(k, List<TodoItem>.unmodifiable(v)),
      ),
      quadrantGroups: quadrantGroups.map(
        (k, v) => MapEntry(k, List<TodoItem>.unmodifiable(v)),
      ),
    );
    _derived = computed;
    _derivedProvider = todoProvider;
    _derivedRevision = revision;
    _derivedMinuteKey = minuteKey;
    _derivedSmartFilter = _smartFilter;
    _derivedSelectedListName = _selectedListName;
    _derivedSelectedTag = _selectedTag;
    _derivedSearchQuery = _searchQuery;
    _derivedViewMode = _viewMode;
    _derivedSortMode = _sortMode;
    _derivedShowCompletedInList = _showCompletedInList;
    _derivedKanbanConfig = _kanbanConfig;
    _derivedCustomListsVersion = _customListsVersion;
    return computed;
  }

  TodoItem? _findSelectedTodo(List<TodoItem> todos) {
    final id = _selectedTodoId;
    if (id == null) return null;
    for (final t in todos) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _syncInspectorControllers(TodoItem? todo) {
    if (todo == null) {
      if (_boundTodoId != null) {
        _boundTodoId = null;
        _titleEditController.clear();
        _notesEditController.clear();
        _tagInputController.clear();
        _reminderEditorExpanded = false;
      }
      return;
    }
    if (_boundTodoId != todo.id) {
      _boundTodoId = todo.id;
      _titleEditController.text = todo.title;
      _notesEditController.text = todo.notes;
      _subtaskAddController.clear();
      _tagInputController.clear();
      _reminderEditorExpanded = false;
      return;
    }
    if (!_titleEditFocusNode.hasFocus && _titleEditController.text != todo.title) {
      _titleEditController.text = todo.title;
    }
    if (!_notesEditFocusNode.hasFocus && _notesEditController.text != todo.notes) {
      _notesEditController.text = todo.notes;
    }
  }

  void _commitInspectorTitle() {
    if (!mounted) return;
    final provider = _safeReadTodoProvider();
    if (provider == null) return;
    final todo = _findSelectedTodo(provider.todos);
    if (todo == null) return;
    final nextTitle = _titleEditController.text.trim();
    if (nextTitle.isEmpty) {
      _titleEditController.text = todo.title;
      return;
    }
    if (nextTitle == todo.title) return;
    unawaited(
      provider.updateTodoWithResult(
        todo.id,
        todo.copyWith(title: nextTitle),
        waitForReminderSync: false,
      ),
    );
  }

  void _commitInspectorNotes() {
    if (!mounted) return;
    final provider = _safeReadTodoProvider();
    if (provider == null) return;
    final todo = _findSelectedTodo(provider.todos);
    if (todo == null) return;
    final nextNotes = _notesEditController.text;
    if (nextNotes == todo.notes) return;
    unawaited(
      provider.updateTodoWithResult(
        todo.id,
        todo.copyWith(notes: nextNotes),
        waitForReminderSync: false,
      ),
    );
  }

  TodoProvider? _safeReadTodoProvider() {
    try {
      return Provider.of<TodoProvider>(context, listen: false);
    } on ProviderNotFoundException {
      return null;
    }
  }

  void _syncTopBar(AppLocale locale, String filterTitle, int count) {
    final controller = _attachedController;
    if (controller == null) return;
    final isEn = locale == AppLocale.en;
    final subtitle = isEn ? '$count items' : '$count 项待办';
    final sig = '${locale.name}|$filterTitle|$count';
    if (_lastTopBarSignature == sig) return;
    _lastTopBarSignature = sig;
    controller.setTopBarSpec(
      DesktopWebDestination.todo,
      DesktopTopBarSpec(
        title: isEn ? 'Tasks' : '待办',
        breadcrumb: filterTitle,
        subtitle: subtitle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefShowCompleted = _selectOptional<PreferencesProvider, bool>(
      context,
      (prefs) => prefs?.showCompletedTodos ?? false,
      false,
    );
    if (_syncedPrefShowCompleted != prefShowCompleted) {
      _syncedPrefShowCompleted = prefShowCompleted;
      _showCompletedInList = prefShowCompleted;
    }

    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final minuteKey = now.millisecondsSinceEpoch ~/ 60000;
        final isEn = locale == AppLocale.en;
        final tokens = DesktopWebTokens.of(context);

        final todoProvider = _watchOptional<TodoProvider>(context);
        final share = _watchOptional<ShareProvider>(context);
        final datePattern = AppDateFormat.patternOf(context);
        final derived = _derivedDataFor(todoProvider, now, today, minuteKey);
        final allTodos = derived.allTodos;
        final mergedLists = derived.mergedLists;
        final availableTags = derived.availableTags;
        final selectedTodo = _findSelectedTodo(allTodos);
        _syncInspectorControllers(selectedTodo);

        final filteredTodos = derived.filteredTodos;
        final visibleEditableIds = filteredTodos
            .where((t) => share?.canEdit(t.workspaceId) ?? true)
            .map((t) => t.id)
            .toSet();
        _selectedIds.retainAll(visibleEditableIds);
        final filterTitle = _activeFilterTitle(isEn);
        _syncTopBar(locale, filterTitle, filteredTodos.length);

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final boundedHeight = constraints.hasBoundedHeight;
            final compactPanes = width < 980;
            final veryNarrow = width < 780;

            final pane1Width = veryNarrow
                ? 176.0
                : (compactPanes ? 184.0 : DesktopWebTokens.paneListWidth);
            final pane3Width = compactPanes ? 276.0 : DesktopWebTokens.paneInspectorWidth;

            Widget body = Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (width >= 580)
                  SizedBox(
                    width: pane1Width,
                    child: _buildSidebarPane(
                      tokens: tokens,
                      isEn: isEn,
                      derived: derived,
                      listNames: mergedLists,
                    ),
                  ),
                Expanded(
                  child: _buildCenterPane(
                    tokens: tokens,
                    isEn: isEn,
                    now: now,
                    today: today,
                    datePattern: datePattern,
                    filterTitle: filterTitle,
                    todoProvider: todoProvider,
                    share: share,
                    derived: derived,
                    showNarrowListPicker: width < 580,
                    listNames: mergedLists,
                    availableTags: availableTags,
                  ),
                ),
                if (!veryNarrow)
                  SizedBox(
                    width: pane3Width,
                    child: _buildInspectorPane(
                      tokens: tokens,
                      isEn: isEn,
                      today: today,
                      datePattern: datePattern,
                      todoProvider: todoProvider,
                      share: share,
                      selectedTodo: selectedTodo,
                      availableLists: mergedLists,
                      availableTags: availableTags,
                      showCloseButton: false,
                    ),
                  ),
              ],
            );

            if (veryNarrow && selectedTodo != null) {
              body = Stack(
                children: [
                  body,
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => _selectTodo(null),
                      child: ColoredBox(color: Colors.black.withValues(alpha: 0.25)),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Material(
                      color: tokens.panelSurface,
                      child: SizedBox(
                        width: (width * 0.85).clamp(260.0, 320.0),
                        child: _buildInspectorPane(
                          tokens: tokens,
                          isEn: isEn,
                          today: today,
                          datePattern: datePattern,
                          todoProvider: todoProvider,
                          share: share,
                          selectedTodo: selectedTodo,
                          availableLists: mergedLists,
                          availableTags: availableTags,
                          showCloseButton: true,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            if (!boundedHeight) {
              return SizedBox(height: 760, child: body);
            }
            return body;
          },
        );
      },
    );
  }

  List<String> _collectListNames(TodoProvider? provider) {
    final names = <String>{};
    if (provider != null) {
      names.addAll(provider.listGroupNames);
    }
    names.addAll(_customListNames);
    final sorted = names.toList()..sort();
    return sorted;
  }

  String _activeFilterTitle(bool isEn) {
    if (_selectedListName != null) {
      return _localizedListName(_selectedListName!, isEn);
    }
    return switch (_smartFilter) {
      _TodoSmartFilter.all => isEn ? 'All Todos' : '全部待办',
      _TodoSmartFilter.today => isEn ? 'Today' : '今天',
      _TodoSmartFilter.next7Days => isEn ? 'Next 7 Days' : '最近 7 天',
      _TodoSmartFilter.highPriority => isEn ? 'High Priority' : '高优先级',
      _TodoSmartFilter.completed => isEn ? 'Completed' : '已完成',
    };
  }

  List<TodoItem> _filterAndSortTodos(
    List<TodoItem> allTodos,
    DateTime now,
    DateTime today,
  ) {
    final weekEnd = today.add(const Duration(days: 6));
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    final list = allTodos.where((t) {
      if (t.isArchivedAfterRollover) return false;
      if (_selectedTag != null && !t.tags.contains(_selectedTag)) {
        return false;
      }
      if (normalizedQuery.isNotEmpty) {
        final inTitle = t.title.toLowerCase().contains(normalizedQuery);
        final inNotes = t.notes.toLowerCase().contains(normalizedQuery);
        final inList = (t.listGroupName ?? '').toLowerCase().contains(normalizedQuery);
        final inTags = t.tags.any((tag) => tag.toLowerCase().contains(normalizedQuery));
        if (!inTitle && !inNotes && !inList && !inTags) {
          return false;
        }
      }
      if (_selectedListName != null) {
        if ((t.listGroupName ?? '') != _selectedListName) return false;
        if (!_showCompletedInList && t.isCompleted && _viewMode == _TodoViewMode.list) {
          return false;
        }
        return true;
      }
      switch (_smartFilter) {
        case _TodoSmartFilter.all:
          if (t.isCompleted && !_showCompletedInList && _viewMode == _TodoViewMode.list) {
            return false;
          }
          return true;
        case _TodoSmartFilter.today:
          if (_showCompletedInList) {
            return CompletionVisibilityPolicy.isInTodayOverview(t, now);
          }
          return CompletionVisibilityPolicy.shouldShowInToday(t, now);
        case _TodoSmartFilter.next7Days:
          if (t.isCompleted && !_showCompletedInList && _viewMode == _TodoViewMode.list) {
            return false;
          }
          final due = t.dueDate;
          if (due == null) return false;
          final dueOnly = CompletionVisibilityPolicy.dateOnly(due);
          return !dueOnly.isBefore(today) && !dueOnly.isAfter(weekEnd);
        case _TodoSmartFilter.highPriority:
          if (t.isCompleted && !_showCompletedInList && _viewMode == _TodoViewMode.list) {
            return false;
          }
          return t.priority == TodoPriority.high || t.priority == TodoPriority.urgent;
        case _TodoSmartFilter.completed:
          return t.isCompleted;
      }
    }).toList();

    if (_sortMode == _TodoSortMode.manual) {
      list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return list;
    }

    list.sort((a, b) {
      switch (_sortMode) {
        case _TodoSortMode.manual:
          return a.sortOrder.compareTo(b.sortOrder);
        case _TodoSortMode.smart:
          if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
          final p = b.priority.rank.compareTo(a.priority.rank);
          if (p != 0) return p;
          if (a.dueDate != null && b.dueDate != null) {
            final d = a.dueDate!.compareTo(b.dueDate!);
            if (d != 0) return d;
          } else if (a.dueDate != null) {
            return -1;
          } else if (b.dueDate != null) {
            return 1;
          }
          return a.sortOrder.compareTo(b.sortOrder);
        case _TodoSortMode.priority:
          final p = b.priority.rank.compareTo(a.priority.rank);
          return p != 0 ? p : a.sortOrder.compareTo(b.sortOrder);
        case _TodoSortMode.dueDate:
          if (a.dueDate != null && b.dueDate != null) {
            return a.dueDate!.compareTo(b.dueDate!);
          }
          if (a.dueDate != null) return -1;
          if (b.dueDate != null) return 1;
          return a.sortOrder.compareTo(b.sortOrder);
        case _TodoSortMode.createdAt:
          return b.createdAt.compareTo(a.createdAt);
      }
    });

    return list;
  }

  Widget _buildSidebarPane({
    required DesktopWebTokens tokens,
    required bool isEn,
    required _DesktopTodoDerivedData derived,
    required List<String> listNames,
  }) {
    final allCount = derived.allCount;
    final todayCount = derived.todayCount;
    final weekCount = derived.weekCount;
    final highCount = derived.highCount;
    final completedCount = derived.completedCount;

    return Container(
      decoration: BoxDecoration(
        color: tokens.sidebarBackground,
        border: Border(
          right: BorderSide(
            color: tokens.hairlineBorder,
            width: DesktopWebTokens.hairlineWidth,
          ),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              isEn ? 'SMART VIEWS' : '智能视图',
              style: tokens.sectionHeaderStyle,
            ),
          ),
          const SizedBox(height: 4),
          _SmartFilterTile(
            icon: Icons.inbox_rounded,
            label: isEn ? 'All Todos' : '全部待办',
            count: allCount,
            selected: _selectedListName == null && _smartFilter == _TodoSmartFilter.all,
            tokens: tokens,
            onTap: () => setState(() {
              _selectedListName = null;
              _smartFilter = _TodoSmartFilter.all;
            }),
          ),
          _SmartFilterTile(
            icon: Icons.wb_sunny_outlined,
            label: isEn ? 'Today' : '今天',
            count: todayCount,
            selected: _selectedListName == null && _smartFilter == _TodoSmartFilter.today,
            tokens: tokens,
            onTap: () => setState(() {
              _selectedListName = null;
              _smartFilter = _TodoSmartFilter.today;
            }),
          ),
          _SmartFilterTile(
            icon: Icons.date_range_outlined,
            label: isEn ? 'Next 7 Days' : '最近 7 天',
            count: weekCount,
            selected: _selectedListName == null && _smartFilter == _TodoSmartFilter.next7Days,
            tokens: tokens,
            onTap: () => setState(() {
              _selectedListName = null;
              _smartFilter = _TodoSmartFilter.next7Days;
            }),
          ),
          _SmartFilterTile(
            icon: Icons.flag_outlined,
            label: isEn ? 'High Priority' : '高优先级',
            count: highCount,
            selected: _selectedListName == null && _smartFilter == _TodoSmartFilter.highPriority,
            tokens: tokens,
            onTap: () => setState(() {
              _selectedListName = null;
              _smartFilter = _TodoSmartFilter.highPriority;
            }),
          ),
          _SmartFilterTile(
            icon: Icons.check_circle_outline_rounded,
            label: isEn ? 'Completed' : '已完成',
            count: completedCount,
            selected: _selectedListName == null && _smartFilter == _TodoSmartFilter.completed,
            tokens: tokens,
            onTap: () => setState(() {
              _selectedListName = null;
              _smartFilter = _TodoSmartFilter.completed;
            }),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, thickness: DesktopWebTokens.hairlineWidth, color: tokens.hairlineBorder),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isEn ? 'LISTS' : '我的清单',
                    style: tokens.sectionHeaderStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: () {
                    setState(() => _creatingList = true);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _newListFocusNode.requestFocus();
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      isEn ? '+ New List' : '+ 新建清单',
                      style: tokens.captionStyle.copyWith(color: tokens.accent),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_creatingList)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: tokens.panelSurface,
                  borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                  border: Border.all(color: tokens.accentBorder, width: 1.0),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newListController,
                        focusNode: _newListFocusNode,
                        style: tokens.bodyMutedStyle.copyWith(color: tokens.textPrimary),
                        textInputAction: TextInputAction.done,
                        onSubmitted: _submitNewList,
                        decoration: InputDecoration(
                          hintText: isEn ? 'List name...' : '输入清单名...',
                          hintStyle: tokens.captionStyle,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => _submitNewList(_newListController.text),
                      child: Icon(Icons.check_rounded, size: 15, color: tokens.accent),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () {
                        _newListController.clear();
                        setState(() => _creatingList = false);
                      },
                      child: Icon(Icons.close_rounded, size: 15, color: tokens.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          if (listNames.isEmpty && !_creatingList)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tpl in TodoListTemplates.all.take(3))
                    InkWell(
                      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
                      onTap: () {
                        setState(() {
                          if (!_customListNames.contains(tpl.name)) {
                            _customListNames.add(tpl.name);
                            _customListsVersion++;
                          }
                          _selectedListName = tpl.name;
                        });
                        unawaited(_saveCustomLists());
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: tokens.mutedSurface,
                          borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: tpl.color,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '+ ${_localizedListName(tpl.name, isEn)}',
                              style: tokens.captionStyle,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          for (final name in listNames)
            _ListSidebarTile(
              label: _localizedListName(name, isEn),
              dotColor: _colorForListName(name, tokens),
              count: derived.listCounts[name] ?? 0,
              selected: _selectedListName == name,
              tokens: tokens,
              onTap: () => setState(() => _selectedListName = name),
            ),
        ],
      ),
    );
  }

  void _submitNewList(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      setState(() => _creatingList = false);
      return;
    }
    setState(() {
      if (!_customListNames.contains(trimmed)) {
        _customListNames.add(trimmed);
        _customListsVersion++;
      }
      _selectedListName = trimmed;
      _creatingList = false;
      _newListController.clear();
    });
    unawaited(_saveCustomLists());
  }

  Widget _buildCenterPane({
    required DesktopWebTokens tokens,
    required bool isEn,
    required DateTime now,
    required DateTime today,
    required String? datePattern,
    required String filterTitle,
    required TodoProvider? todoProvider,
    required ShareProvider? share,
    required _DesktopTodoDerivedData derived,
    required bool showNarrowListPicker,
    required List<String> listNames,
    required List<String> availableTags,
  }) {
    final filteredTodos = derived.filteredTodos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCenterToolbar(
          tokens: tokens,
          isEn: isEn,
          filterTitle: filterTitle,
          count: filteredTodos.length,
          showNarrowListPicker: showNarrowListPicker,
          listNames: listNames,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _buildCenterQuickAddBar(
            tokens: tokens,
            isEn: isEn,
            now: now,
            today: today,
            todoProvider: todoProvider,
          ),
        ),
        if (availableTags.isNotEmpty || _selectedTag != null)
          _buildTagFilterStrip(
            tokens: tokens,
            isEn: isEn,
            availableTags: availableTags,
          ),
        if (_batchMode)
          _buildDesktopBatchBar(
            tokens: tokens,
            isEn: isEn,
            today: today,
            todoProvider: todoProvider,
            share: share,
            filteredTodos: filteredTodos,
            availableLists: listNames,
            availableTags: availableTags,
          ),
        Expanded(
          child: switch (_viewMode) {
            _TodoViewMode.list => _buildListMode(
              tokens: tokens,
              isEn: isEn,
              now: now,
              today: today,
              datePattern: datePattern,
              todoProvider: todoProvider,
              share: share,
              todos: filteredTodos,
            ),
            _TodoViewMode.kanban => _buildKanbanMode(
              tokens: tokens,
              isEn: isEn,
              now: now,
              datePattern: datePattern,
              todoProvider: todoProvider,
              share: share,
              kanbanGroups: derived.kanbanGroups,
            ),
            _TodoViewMode.matrix => _buildMatrixMode(
              tokens: tokens,
              todoProvider: todoProvider,
              share: share,
              quadrantGroups: derived.quadrantGroups,
            ),
          },
        ),
      ],
    );
  }

  Widget _buildTagFilterStrip({
    required DesktopWebTokens tokens,
    required bool isEn,
    required List<String> availableTags,
  }) {
    return Padding(
      key: const ValueKey('desktop_todo_tag_filter_strip'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _InspectorPill(
              label: isEn ? 'All tags' : '全部标签',
              selected: _selectedTag == null,
              color: tokens.accent,
              tokens: tokens,
              onTap: () => setState(() => _selectedTag = null),
            ),
            for (final tag in availableTags) ...[
              const SizedBox(width: 6),
              _InspectorPill(
                label: '#$tag',
                selected: _selectedTag == tag,
                color: tokens.accent,
                tokens: tokens,
                onTap: () => setState(
                  () => _selectedTag = _selectedTag == tag ? null : tag,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopBatchBar({
    required DesktopWebTokens tokens,
    required bool isEn,
    required DateTime today,
    required TodoProvider? todoProvider,
    required ShareProvider? share,
    required List<TodoItem> filteredTodos,
    required List<String> availableLists,
    required List<String> availableTags,
  }) {
    final editableIds = filteredTodos
        .where((t) => share?.canEdit(t.workspaceId) ?? true)
        .map((t) => t.id)
        .toList();
    final activeIds = _selectedIds.where(editableIds.contains).toSet();
    final allSelected =
        editableIds.isNotEmpty && activeIds.length == editableIds.length;
    final hasSel = activeIds.isNotEmpty && !_batchBusy && todoProvider != null;

    Future<void> runBatch(Future<int> Function(Set<String> ids) op) async {
      if (!hasSel) return;
      setState(() => _batchBusy = true);
      try {
        await op(activeIds);
        if (!mounted) return;
        setState(() => _selectedIds.clear());
      } finally {
        if (mounted) setState(() => _batchBusy = false);
      }
    }

    final listOptions = <String>{
      ...TodoListTemplates.all.map((t) => t.name),
      ...availableLists,
    }.toList()..sort();

    return Container(
      key: const ValueKey('desktop_todo_batch_bar'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.selectedSurface,
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
        border: Border.all(
          color: tokens.accentBorder,
          width: DesktopWebTokens.hairlineWidth,
        ),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
            ),
            child: Text(
              isEn ? '${activeIds.length} selected' : '已选 ${activeIds.length} 项',
              style: tokens.captionStyle.copyWith(
                color: tokens.accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _InspectorPill(
            label: allSelected
                ? (isEn ? 'Deselect all' : '取消全选')
                : (isEn ? 'Select all' : '全选'),
            selected: allSelected,
            color: tokens.accent,
            tokens: tokens,
            onTap: editableIds.isEmpty
                ? null
                : () => setState(() {
                    if (allSelected) {
                      _selectedIds.clear();
                    } else {
                      _selectedIds.addAll(editableIds);
                    }
                  }),
          ),
          _InspectorPill(
            label: isEn ? 'Complete' : '完成',
            selected: false,
            color: tokens.success,
            tokens: tokens,
            onTap: hasSel ? () => runBatch(todoProvider.completeTodos) : null,
          ),
          _InspectorPill(
            label: isEn ? 'Reopen' : '恢复',
            selected: false,
            color: tokens.info,
            tokens: tokens,
            onTap: hasSel ? () => runBatch(todoProvider.reopenTodos) : null,
          ),
          PopupMenuButton<TodoPriority>(
            enabled: hasSel,
            tooltip: isEn ? 'Batch priority' : '批量优先级',
            onSelected: (p) {
              final provider = todoProvider;
              if (provider == null) return;
              runBatch((ids) => provider.updateTodosPriority(ids, p));
            },
            itemBuilder: (ctx) => [
              for (final p in TodoPriority.values)
                PopupMenuItem(value: p, child: Text(p.label)),
            ],
            child: _InspectorPill(
              label: isEn ? 'Priority ▾' : '优先级 ▾',
              selected: false,
              color: tokens.warning,
              tokens: tokens,
              onTap: null,
            ),
          ),
          PopupMenuButton<String>(
            enabled: hasSel,
            tooltip: isEn ? 'Reschedule due date' : '批量改期',
            onSelected: (choice) async {
              final provider = todoProvider;
              if (provider == null) return;
              if (choice == 'today') {
                await runBatch(
                  (ids) => provider.rescheduleTodosDueDate(ids, today),
                );
              } else if (choice == 'tomorrow') {
                await runBatch(
                  (ids) => provider.rescheduleTodosDueDate(
                    ids,
                    today.add(const Duration(days: 1)),
                  ),
                );
              } else if (choice == 'next_week') {
                await runBatch(
                  (ids) => provider.rescheduleTodosDueDate(
                    ids,
                    today.add(const Duration(days: 7)),
                  ),
                );
              } else if (choice == 'clear') {
                await runBatch(
                  (ids) => provider.rescheduleTodosDueDate(ids, null),
                );
              } else if (choice == 'pick') {
                final picked = await AppDatePicker.pickSolar(
                  context,
                  initialDate: today,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  title: isEn ? 'Pick due date' : '选择截止日期',
                );
                if (picked != null && mounted) {
                  await runBatch(
                    (ids) => provider.rescheduleTodosDueDate(
                      ids,
                      DateTime(picked.year, picked.month, picked.day),
                    ),
                  );
                }
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'today',
                child: Text(isEn ? 'Today' : '今天'),
              ),
              PopupMenuItem(
                value: 'tomorrow',
                child: Text(isEn ? 'Tomorrow' : '明天'),
              ),
              PopupMenuItem(
                value: 'next_week',
                child: Text(isEn ? 'Next Week' : '下周'),
              ),
              PopupMenuItem(
                value: 'pick',
                child: Text(isEn ? 'Pick date...' : '选择日期...'),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Text(isEn ? 'Clear due date' : '清除日期'),
              ),
            ],
            child: _InspectorPill(
              label: isEn ? 'Due date ▾' : '改期 ▾',
              selected: false,
              color: tokens.accent,
              tokens: tokens,
              onTap: null,
            ),
          ),
          PopupMenuButton<String>(
            enabled: hasSel,
            tooltip: isEn ? 'Assign list' : '分配清单',
            onSelected: (name) {
              final provider = todoProvider;
              if (provider == null) return;
              runBatch(
                (ids) => provider.assignTodosListGroup(
                  ids,
                  name.isEmpty ? null : name,
                ),
              );
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: '',
                child: Text(isEn ? 'Inbox / None' : '未分组'),
              ),
              for (final name in listOptions)
                PopupMenuItem(
                  value: name,
                  child: Text(_localizedListName(name, isEn)),
                ),
            ],
            child: _InspectorPill(
              label: isEn ? 'List ▾' : '清单 ▾',
              selected: false,
              color: tokens.textSecondary,
              tokens: tokens,
              onTap: null,
            ),
          ),
          _InspectorPill(
            label: isEn ? 'Add tag' : '加标签',
            selected: false,
            color: tokens.accent,
            tokens: tokens,
            onTap: hasSel
                ? () async {
                    final tag = await _promptDesktopBatchTag(
                      isEn: isEn,
                      availableTags: availableTags,
                    );
                    if (tag != null && tag.isNotEmpty) {
                      await runBatch(
                        (ids) => todoProvider.assignTagsToTodos(ids, tag),
                      );
                    }
                  }
                : null,
          ),
          _InspectorPill(
            label: isEn ? 'Delete' : '删除',
            selected: false,
            color: tokens.danger,
            tokens: tokens,
            onTap: hasSel
                ? () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(isEn ? 'Delete selected tasks' : '删除所选待办'),
                        content: Text(
                          isEn
                              ? 'Delete ${activeIds.length} selected tasks?'
                              : '确认删除所选的 ${activeIds.length} 项待办吗？',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: Text(isEn ? 'Cancel' : '取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: Text(isEn ? 'Delete' : '删除'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await runBatch(todoProvider.deleteTodos);
                    }
                  }
                : null,
          ),
          _InspectorPill(
            label: isEn ? 'Done' : '完成选择',
            selected: false,
            color: tokens.textMuted,
            tokens: tokens,
            onTap: () => setState(() {
              _batchMode = false;
              _selectedIds.clear();
            }),
          ),
        ],
      ),
    );
  }

  Future<List<String>?> _promptDesktopBatchTag({
    required bool isEn,
    required List<String> availableTags,
  }) async {
    final picked = <String>{};
    final ctrl = TextEditingController();
    try {
      return await showDialog<List<String>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: Text(isEn ? 'Assign tags' : '批量添加标签'),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: ctrl,
                    decoration: InputDecoration(
                      labelText: isEn ? 'New tags (comma separated)' : '新标签（逗号分隔）',
                    ),
                  ),
                  if (availableTags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final t in availableTags)
                          FilterChip(
                            label: Text('#$t'),
                            selected: picked.contains(t),
                            onSelected: (v) => setSt(() {
                              if (v) {
                                picked.add(t);
                              } else {
                                picked.remove(t);
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(isEn ? 'Cancel' : '取消'),
              ),
              FilledButton(
                onPressed: () {
                  final out = <String>{...picked};
                  for (final part in ctrl.text.split(RegExp(r'[,，\s]+'))) {
                    final trimmed = part.trim();
                    if (trimmed.isNotEmpty) out.add(trimmed);
                  }
                  Navigator.of(ctx).pop(out.toList());
                },
                child: Text(isEn ? 'Confirm' : '确认'),
              ),
            ],
          ),
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  Widget _buildCenterToolbar({
    required DesktopWebTokens tokens,
    required bool isEn,
    required String filterTitle,
    required int count,
    required bool showNarrowListPicker,
    required List<String> listNames,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: tokens.hairlineBorder,
            width: DesktopWebTokens.hairlineWidth,
          ),
        ),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showNarrowListPicker)
                PopupMenuButton<String>(
                  tooltip: isEn ? 'Switch list' : '切换清单',
                  icon: Icon(Icons.menu_rounded, size: 18, color: tokens.textPrimary),
                  onSelected: (value) {
                    setState(() {
                      if (value.startsWith('filter:')) {
                        _selectedListName = null;
                        _smartFilter = _TodoSmartFilter.values.byName(value.substring(7));
                      } else if (value.startsWith('list:')) {
                        _selectedListName = value.substring(5);
                      }
                    });
                  },
                  itemBuilder: (context) => [
                    for (final f in _TodoSmartFilter.values)
                      PopupMenuItem(
                        value: 'filter:${f.name}',
                        child: Text(_smartFilterLabel(f, isEn)),
                      ),
                    for (final name in listNames)
                      PopupMenuItem(
                        value: 'list:$name',
                        child: Text(_localizedListName(name, isEn)),
                      ),
                  ],
                ),
              Text(filterTitle, style: tokens.pageTitleStyle),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: tokens.mutedSurface,
                  borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
                ),
                child: Text(
                  '$count',
                  style: tokens.captionStyle.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 170,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: tokens.mutedSurface,
                    borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                    border: Border.all(
                      color: tokens.hairlineBorder,
                      width: DesktopWebTokens.hairlineWidth,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, size: 14, color: tokens.textMuted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('desktop_todo_search_field'),
                          controller: _searchController,
                          style: tokens.captionStyle.copyWith(color: tokens.textPrimary),
                          onChanged: (v) => setState(() => _searchQuery = v),
                          decoration: InputDecoration(
                            hintText: isEn ? 'Search tasks...' : '搜索待办...',
                            hintStyle: tokens.captionStyle.copyWith(color: tokens.textMuted),
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(vertical: 4),
                          ),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        InkWell(
                          onTap: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          child: Icon(Icons.close_rounded, size: 13, color: tokens.textMuted),
                        ),
                    ],
                  ),
                ),
              ),
              _ViewModeSwitcher(
                mode: _viewMode,
                tokens: tokens,
                isEn: isEn,
                onChanged: (next) => setState(() => _viewMode = next),
              ),
              Tooltip(
                message: isEn ? 'Batch select' : '批量操作',
                child: InkWell(
                  key: const ValueKey('desktop_todo_batch_toggle'),
                  borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                  onTap: () => setState(() {
                    _batchMode = !_batchMode;
                    if (!_batchMode) _selectedIds.clear();
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: _batchMode ? tokens.selectedSurface : tokens.mutedSurface,
                      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                      border: Border.all(
                        color: _batchMode ? tokens.accentBorder : tokens.hairlineBorder,
                        width: DesktopWebTokens.hairlineWidth,
                      ),
                    ),
                    child: Icon(
                      Icons.checklist_rounded,
                      size: 15,
                      color: _batchMode ? tokens.accent : tokens.textSecondary,
                    ),
                  ),
                ),
              ),
              if (_selectedListName != null || _smartFilter != _TodoSmartFilter.completed)
                Tooltip(
                  message: isEn ? 'Show completed' : '显示已完成',
                  child: InkWell(
                    key: const ValueKey('desktop_todo_show_completed_toggle'),
                    borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                    onTap: () => setState(() => _showCompletedInList = !_showCompletedInList),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: _showCompletedInList ? tokens.selectedSurface : tokens.mutedSurface,
                        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                        border: Border.all(
                          color: _showCompletedInList ? tokens.accentBorder : tokens.hairlineBorder,
                          width: DesktopWebTokens.hairlineWidth,
                        ),
                      ),
                      child: Icon(
                        Icons.done_all_rounded,
                        size: 15,
                        color: _showCompletedInList ? tokens.accent : tokens.textSecondary,
                      ),
                    ),
                  ),
                ),
              PopupMenuButton<_TodoSortMode>(
                tooltip: isEn ? 'Sort order' : '排序方式',
                initialValue: _sortMode,
                onSelected: (mode) => setState(() => _sortMode = mode),
                itemBuilder: (context) => [
                  for (final m in _TodoSortMode.values)
                    PopupMenuItem(
                      value: m,
                      child: Row(
                        children: [
                          Icon(
                            m == _sortMode ? Icons.check_rounded : Icons.sort_rounded,
                            size: 15,
                            color: m == _sortMode ? tokens.accent : tokens.textMuted,
                          ),
                          const SizedBox(width: 8),
                          Text(_sortModeLabel(m, isEn), style: tokens.bodyStyle),
                        ],
                      ),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(
                    color: tokens.mutedSurface,
                    borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                    border: Border.all(
                      color: tokens.hairlineBorder,
                      width: DesktopWebTokens.hairlineWidth,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.swap_vert_rounded, size: 15, color: tokens.textSecondary),
                      const SizedBox(width: 4),
                      Text(_sortModeLabel(_sortMode, isEn), style: tokens.captionStyle),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCenterQuickAddBar({
    required DesktopWebTokens tokens,
    required bool isEn,
    required DateTime now,
    required DateTime today,
    required TodoProvider? todoProvider,
  }) {
    final prioColor = _priorityColor(_quickAddPriority, tokens);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.panelSurface,
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
        border: Border.all(
          color: _quickAddFocused ? tokens.accentBorder : tokens.hairlineBorder,
          width: _quickAddFocused ? 1.0 : DesktopWebTokens.hairlineWidth,
        ),
        boxShadow: tokens.cardShadow,
      ),
      child: Row(
        children: [
          Icon(
            Icons.add_rounded,
            size: 19,
            color: _quickAddFocused ? tokens.accent : tokens.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _quickAddController,
              focusNode: _quickAddFocusNode,
              style: tokens.bodyStyle,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submitQuickAdd(
                todoProvider: todoProvider,
                now: now,
                today: today,
              ),
              decoration: InputDecoration(
                hintText: isEn
                    ? 'Add a todo, press Enter to add to current list...'
                    : '输入待办标题，Enter 添加到当前清单...',
                hintStyle: tokens.bodyMutedStyle.copyWith(color: tokens.textMuted),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: isEn ? 'Due today' : '设为今天',
            child: InkWell(
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
              onTap: () => setState(() => _quickAddToday = !_quickAddToday),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _quickAddToday ? tokens.accentSoft : tokens.mutedSurface,
                  borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
                ),
                child: Icon(
                  Icons.today_outlined,
                  size: 14,
                  color: _quickAddToday ? tokens.accent : tokens.textMuted,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: isEn ? 'Priority' : '优先级',
            child: InkWell(
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
              onTap: () {
                setState(() => _quickAddPriority = _nextPriority(_quickAddPriority));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _quickAddPriority == TodoPriority.none
                      ? tokens.mutedSurface
                      : prioColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
                ),
                child: Icon(
                  Icons.flag_outlined,
                  size: 14,
                  color: _quickAddPriority == TodoPriority.none ? tokens.textMuted : prioColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
            onTap: () => _submitQuickAdd(
              todoProvider: todoProvider,
              now: now,
              today: today,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: tokens.accentSoft,
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                border: Border.all(
                  color: tokens.accentBorder,
                  width: DesktopWebTokens.hairlineWidth,
                ),
              ),
              child: Text(
                isEn ? 'Enter' : '添加',
                style: tokens.captionStyle.copyWith(color: tokens.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _submitQuickAdd({
    required TodoProvider? todoProvider,
    required DateTime now,
    required DateTime today,
  }) {
    final text = _quickAddController.text.trim();
    if (text.isEmpty || todoProvider == null) return;
    final draft = SmartTodoDraftBuilder.fromText(text, now: now);
    final listName = _selectedListName;
    final workspaceId = listName == null
        ? 'private'
        : (todoProvider.workspaceForListGroup(listName) ?? 'private');

    var effectivePriority = _quickAddPriority;
    if (listName == null &&
        _smartFilter == _TodoSmartFilter.highPriority &&
        effectivePriority == TodoPriority.none) {
      effectivePriority = TodoPriority.high;
    }

    var effectiveDue = draft.dueDate;
    if (effectiveDue == null &&
        (_quickAddToday ||
            (listName == null &&
                (_smartFilter == _TodoSmartFilter.today ||
                    _smartFilter == _TodoSmartFilter.next7Days)))) {
      effectiveDue = today;
    }

    final todo = draft
        .toTodo(
          priority: effectivePriority,
          listGroupName: listName,
          workspaceId: workspaceId,
          quadrant: effectivePriority == TodoPriority.urgent ||
                  effectivePriority == TodoPriority.high
              ? EisenhowerQuadrant.urgentImportant
              : EisenhowerQuadrant.notUrgentImportant,
        )
        .copyWith(date: today, dueDate: effectiveDue);

    _quickAddController.clear();
    setState(() {
      _quickAddPriority = TodoPriority.none;
      _quickAddToday = false;
      if (listName == null && _smartFilter == _TodoSmartFilter.completed) {
        _smartFilter = _TodoSmartFilter.all;
      }
      _selectedTodoId = todo.id;
    });
    _attachedController?.selectTodo(todo.id);
    unawaited(todoProvider.addTodo(todo, waitForReminderSync: false));
  }

  Widget _buildListMode({
    required DesktopWebTokens tokens,
    required bool isEn,
    required DateTime now,
    required DateTime today,
    required String? datePattern,
    required TodoProvider? todoProvider,
    required ShareProvider? share,
    required List<TodoItem> todos,
  }) {
    if (todos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 36, color: tokens.textMuted),
              const SizedBox(height: 10),
              Text(
                isEn ? 'No tasks in this view' : '当前视图暂无待办',
                style: tokens.cardTitleStyle,
              ),
              const SizedBox(height: 4),
              Text(
                isEn
                    ? 'Use the quick-add input above and press Enter.'
                    : '在上方输入框键入标题并按 Enter 即可立即创建。',
                style: tokens.bodyMutedStyle,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: todos.length,
      separatorBuilder: (context, index) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final t = todos[index];
        final canEdit = share?.canEdit(t.workspaceId) ?? true;
        return _DesktopTodoRow(
          todo: t,
          selected: t.id == _selectedTodoId,
          batchMode: _batchMode,
          batchSelected: _selectedIds.contains(t.id),
          now: now,
          today: today,
          datePattern: datePattern,
          isEn: isEn,
          tokens: tokens,
          canEdit: canEdit,
          onSelect: () => _selectTodo(t.id),
          onToggleBatchSelect: canEdit
              ? () => setState(() {
                  if (!_selectedIds.remove(t.id)) {
                    _selectedIds.add(t.id);
                  }
                })
              : null,
          onToggle: () {
            todoProvider?.toggleTodo(t.id, recordCompletionTime: false);
          },
          onScheduleToday: () {
            if (!canEdit) return;
            todoProvider?.updateTodoWithResult(
              t.id,
              t.copyWith(dueDate: today),
              waitForReminderSync: false,
            );
          },
          onFocus: () => _launchFocusForTodo(t.title),
          onDelete: () {
            if (!canEdit) return;
            if (_selectedTodoId == t.id) _selectTodo(null);
            todoProvider?.deleteTodo(t.id);
          },
        );
      },
    );
  }

  Widget _buildKanbanMode({
    required DesktopWebTokens tokens,
    required bool isEn,
    required DateTime now,
    required String? datePattern,
    required TodoProvider? todoProvider,
    required ShareProvider? share,
    required Map<String, List<TodoItem>> kanbanGroups,
  }) {
    final columns = _kanbanConfig.columns;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: SizedBox(
            height: (constraints.maxHeight - 24).clamp(240.0, 2000.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < columns.length; i++) ...[
                  _buildKanbanColumn(
                    column: columns[i],
                    allColumns: columns,
                    todos: kanbanGroups[columns[i].id] ?? const <TodoItem>[],
                    tokens: tokens,
                    isEn: isEn,
                    now: now,
                    datePattern: datePattern,
                    todoProvider: todoProvider,
                    share: share,
                  ),
                  if (i < columns.length - 1) const SizedBox(width: 12),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _effectiveKanbanColumnId(TodoItem t, List<TodoKanbanColumn> cols) {
    if (cols.any((c) => c.id == t.kanbanColumnId)) return t.kanbanColumnId;
    if (t.isCompleted) return defaultKanbanDoneColumnId;
    return cols.isEmpty ? defaultKanbanPendingColumnId : cols.first.id;
  }

  Widget _buildKanbanColumn({
    required TodoKanbanColumn column,
    required List<TodoKanbanColumn> allColumns,
    required List<TodoItem> todos,
    required DesktopWebTokens tokens,
    required bool isEn,
    required DateTime now,
    required String? datePattern,
    required TodoProvider? todoProvider,
    required ShareProvider? share,
  }) {
    final colColor = Color(column.colorValue);
    final title = _localizedKanbanTitle(column, isEn);

    return DragTarget<String>(
      onAcceptWithDetails: (details) {
        todoProvider?.updateTodosKanbanColumn([details.data], column.id);
      },
      builder: (context, candidates, rejected) {
        final draggingOver = candidates.isNotEmpty;
        return Container(
          width: 268,
          decoration: BoxDecoration(
            color: draggingOver
                ? tokens.accentSoft
                : tokens.mutedSurface,
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusLg),
            border: Border.all(
              color: draggingOver ? tokens.accentBorder : tokens.hairlineBorder,
              width: draggingOver ? 1.2 : DesktopWebTokens.hairlineWidth,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: tokens.bodyStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: tokens.panelSurface,
                        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
                      ),
                      child: Text(
                        '${todos.length}',
                        style: tokens.captionStyle.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
                  itemCount: todos.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final t = todos[index];
                    final canEdit = share?.canEdit(t.workspaceId) ?? true;
                    final card = _KanbanTodoCard(
                      todo: t,
                      selected: t.id == _selectedTodoId,
                      tokens: tokens,
                      isEn: isEn,
                      now: now,
                      datePattern: datePattern,
                      canEdit: canEdit,
                      allColumns: allColumns,
                      currentColumnId: column.id,
                      onTap: () => _selectTodo(t.id),
                      onToggle: () {
                        todoProvider?.toggleTodo(t.id, recordCompletionTime: false);
                      },
                      onMoveColumn: (nextColId) {
                        todoProvider?.updateTodosKanbanColumn([t.id], nextColId);
                      },
                    );
                    if (!canEdit) return card;
                    return Draggable<String>(
                      data: t.id,
                      feedback: Material(
                        color: Colors.transparent,
                        child: SizedBox(width: 248, child: Opacity(opacity: 0.9, child: card)),
                      ),
                      childWhenDragging: Opacity(opacity: 0.35, child: card),
                      child: card,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMatrixMode({
    required DesktopWebTokens tokens,
    required TodoProvider? todoProvider,
    required ShareProvider? share,
    required Map<EisenhowerQuadrant, List<TodoItem>> quadrantGroups,
  }) {
    final q1 = quadrantGroups[EisenhowerQuadrant.urgentImportant] ?? const <TodoItem>[];
    final q2 = quadrantGroups[EisenhowerQuadrant.notUrgentImportant] ?? const <TodoItem>[];
    final q3 = quadrantGroups[EisenhowerQuadrant.urgentNotImportant] ?? const <TodoItem>[];
    final q4 = quadrantGroups[EisenhowerQuadrant.notUrgentNotImportant] ?? const <TodoItem>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 520) {
            return ListView(
              children: [
                _buildQuadrantPanel(
                  quadrant: EisenhowerQuadrant.urgentImportant,
                  title: TodoDetailUiCopy.quadrantQ1,
                  color: tokens.danger,
                  todos: q1,
                  tokens: tokens,
                  todoProvider: todoProvider,
                  share: share,
                  height: 220,
                ),
                const SizedBox(height: 10),
                _buildQuadrantPanel(
                  quadrant: EisenhowerQuadrant.notUrgentImportant,
                  title: TodoDetailUiCopy.quadrantQ2,
                  color: tokens.info,
                  todos: q2,
                  tokens: tokens,
                  todoProvider: todoProvider,
                  share: share,
                  height: 220,
                ),
                const SizedBox(height: 10),
                _buildQuadrantPanel(
                  quadrant: EisenhowerQuadrant.urgentNotImportant,
                  title: TodoDetailUiCopy.quadrantQ3,
                  color: tokens.warning,
                  todos: q3,
                  tokens: tokens,
                  todoProvider: todoProvider,
                  share: share,
                  height: 220,
                ),
                const SizedBox(height: 10),
                _buildQuadrantPanel(
                  quadrant: EisenhowerQuadrant.notUrgentNotImportant,
                  title: TodoDetailUiCopy.quadrantQ4,
                  color: tokens.textMuted,
                  todos: q4,
                  tokens: tokens,
                  todoProvider: todoProvider,
                  share: share,
                  height: 220,
                ),
              ],
            );
          }

          return Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _buildQuadrantPanel(
                        quadrant: EisenhowerQuadrant.urgentImportant,
                        title: TodoDetailUiCopy.quadrantQ1,
                        color: tokens.danger,
                        todos: q1,
                        tokens: tokens,
                        todoProvider: todoProvider,
                        share: share,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildQuadrantPanel(
                        quadrant: EisenhowerQuadrant.notUrgentImportant,
                        title: TodoDetailUiCopy.quadrantQ2,
                        color: tokens.info,
                        todos: q2,
                        tokens: tokens,
                        todoProvider: todoProvider,
                        share: share,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _buildQuadrantPanel(
                        quadrant: EisenhowerQuadrant.urgentNotImportant,
                        title: TodoDetailUiCopy.quadrantQ3,
                        color: tokens.warning,
                        todos: q3,
                        tokens: tokens,
                        todoProvider: todoProvider,
                        share: share,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildQuadrantPanel(
                        quadrant: EisenhowerQuadrant.notUrgentNotImportant,
                        title: TodoDetailUiCopy.quadrantQ4,
                        color: tokens.textMuted,
                        todos: q4,
                        tokens: tokens,
                        todoProvider: todoProvider,
                        share: share,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildQuadrantPanel({
    required EisenhowerQuadrant quadrant,
    required String title,
    required Color color,
    required List<TodoItem> todos,
    required DesktopWebTokens tokens,
    required TodoProvider? todoProvider,
    required ShareProvider? share,
    double? height,
  }) {
    return DragTarget<String>(
      onAcceptWithDetails: (details) {
        todoProvider?.updateTodosQuadrant([details.data], quadrant);
      },
      builder: (context, candidates, rejected) {
        final activeDrop = candidates.isNotEmpty;
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: activeDrop ? color.withValues(alpha: 0.12) : tokens.panelSurface,
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusLg),
            border: Border.all(
              color: activeDrop ? color : tokens.hairlineBorder,
              width: activeDrop ? 1.2 : DesktopWebTokens.hairlineWidth,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(DesktopWebTokens.radiusLg),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        title,
                        style: tokens.bodyMutedStyle.copyWith(color: color),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${todos.length}',
                      style: tokens.captionStyle.copyWith(
                        color: color,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: todos.isEmpty
                    ? Center(
                        child: Text(TodoUiCopy.eisenhowerEmpty, style: tokens.captionStyle),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(8),
                        itemCount: todos.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final t = todos[index];
                          final canEdit = share?.canEdit(t.workspaceId) ?? true;
                          final item = DesktopHoverTile(
                            selected: t.id == _selectedTodoId,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            onTap: () => _selectTodo(t.id),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: canEdit
                                      ? () => todoProvider?.toggleTodo(
                                          t.id,
                                          recordCompletionTime: false,
                                        )
                                      : null,
                                  child: Icon(
                                    t.isCompleted
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                    size: 16,
                                    color: t.isCompleted ? tokens.accent : color,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    t.title,
                                    style: tokens.bodyMutedStyle.copyWith(
                                      color: t.isCompleted ? tokens.textMuted : tokens.textPrimary,
                                      decoration: t.isCompleted ? TextDecoration.lineThrough : null,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (!canEdit) return item;
                          return Draggable<String>(
                            data: t.id,
                            feedback: Material(
                              color: Colors.transparent,
                              child: Container(
                                width: 200,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: tokens.elevatedSurface,
                                  borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                                  border: Border.all(color: tokens.accentBorder),
                                ),
                                child: Text(t.title, style: tokens.bodyStyle, maxLines: 1),
                              ),
                            ),
                            childWhenDragging: Opacity(opacity: 0.35, child: item),
                            child: item,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInspectorPane({
    required DesktopWebTokens tokens,
    required bool isEn,
    required DateTime today,
    required String? datePattern,
    required TodoProvider? todoProvider,
    required ShareProvider? share,
    required TodoItem? selectedTodo,
    required List<String> availableLists,
    required List<String> availableTags,
    required bool showCloseButton,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: tokens.panelSurface.withValues(alpha: tokens.isLiquidGlass ? 0.58 : 0.85),
        border: Border(
          left: BorderSide(
            color: tokens.hairlineBorder,
            width: DesktopWebTokens.hairlineWidth,
          ),
        ),
      ),
      child: selectedTodo == null
          ? _buildEmptyInspector(tokens: tokens, isEn: isEn)
          : _buildTaskInspector(
              todo: selectedTodo,
              tokens: tokens,
              isEn: isEn,
              today: today,
              datePattern: datePattern,
              todoProvider: todoProvider,
              share: share,
              availableLists: availableLists,
              availableTags: availableTags,
              showCloseButton: showCloseButton,
            ),
    );
  }

  Widget _buildEmptyInspector({
    required DesktopWebTokens tokens,
    required bool isEn,
  }) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 18),
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.accentSoft,
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
          ),
          child: Icon(Icons.edit_note_rounded, size: 24, color: tokens.accent),
        ),
        const SizedBox(height: 14),
        Text(
          isEn ? 'Select a task to inspect' : '选择一项待办查看与编辑',
          style: tokens.cardTitleStyle,
        ),
        const SizedBox(height: 6),
        Text(
          isEn
              ? 'Click any task in List, Board, or Matrix view to edit title, notes, priority, due date, list, or subtasks inline.'
              : '在列表、看板或四象限中点击任意任务，即可在此直接修改标题、备注、优先级、截止日与子任务。',
          style: tokens.bodyMutedStyle,
        ),
        const SizedBox(height: 22),
        Text(
          isEn ? 'KEYBOARD SHORTCUTS' : '快捷键指南',
          style: tokens.sectionHeaderStyle,
        ),
        const SizedBox(height: 10),
        _ShortcutGuideRow(
          keycap: '⌘K',
          description: isEn ? 'Command palette & search' : '全局搜索与快捷创建',
          tokens: tokens,
        ),
        const SizedBox(height: 8),
        _ShortcutGuideRow(
          keycap: 'Enter',
          description: isEn ? 'Quick-add into current list' : '快速添加到当前清单',
          tokens: tokens,
        ),
        const SizedBox(height: 8),
        _ShortcutGuideRow(
          keycap: 'Drag',
          description: isEn ? 'Move cards across columns/quadrants' : '拖拽调整看板列或象限',
          tokens: tokens,
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.mutedSurface,
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
            border: Border.all(
              color: tokens.hairlineBorder,
              width: DesktopWebTokens.hairlineWidth,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEn ? 'Smart Quick-Add Tips' : '智能创建小贴士',
                style: tokens.bodyStyle,
              ),
              const SizedBox(height: 4),
              Text(
                isEn
                    ? 'Try natural date phrases like "tomorrow 3pm Review slides" to auto-schedule.'
                    : '输入 “明天下午3点 写周报” 可自动识别日期与提醒时间。',
                style: tokens.captionStyle,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTaskInspector({
    required TodoItem todo,
    required DesktopWebTokens tokens,
    required bool isEn,
    required DateTime today,
    required String? datePattern,
    required TodoProvider? todoProvider,
    required ShareProvider? share,
    required List<String> availableLists,
    required List<String> availableTags,
    required bool showCloseButton,
  }) {
    final canEdit = share?.canEdit(todo.workspaceId) ?? true;
    final tomorrow = today.add(const Duration(days: 1));
    final nextWeek = today.add(const Duration(days: 7));
    final currentDueOnly = todo.dueDate == null
        ? null
        : CompletionVisibilityPolicy.dateOnly(todo.dueDate!);

    final selectableLists = <String>{
      ...TodoListTemplates.all.map((e) => e.name),
      ...availableLists,
    }.toList()..sort();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Row(
          children: [
            Flexible(
              child: InkWell(
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                onTap: canEdit
                    ? () => todoProvider?.toggleTodo(todo.id, recordCompletionTime: false)
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: todo.isCompleted ? tokens.success.withValues(alpha: 0.14) : tokens.mutedSurface,
                    borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                    border: Border.all(
                      color: todo.isCompleted ? tokens.success.withValues(alpha: 0.45) : tokens.hairlineBorder,
                      width: DesktopWebTokens.hairlineWidth,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        todo.isCompleted ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        size: 15,
                        color: todo.isCompleted ? tokens.success : tokens.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          todo.isCompleted
                              ? (isEn ? 'Completed' : '已完成')
                              : (isEn ? 'Mark Done' : '标记完成'),
                          style: tokens.captionStyle.copyWith(
                            color: todo.isCompleted ? tokens.success : tokens.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Spacer(),
            Tooltip(
              message: isEn ? 'Start Focus' : '开始专注',
              child: InkWell(
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                onTap: () => _launchFocusForTodo(todo.title),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.play_circle_outline_rounded, size: 18, color: tokens.accent),
                ),
              ),
            ),
            if (canEdit)
              Tooltip(
                message: isEn ? 'Delete task' : '删除待办',
                child: InkWell(
                  borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                  onTap: () => setState(() => _pendingDeleteConfirm = !_pendingDeleteConfirm),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.delete_outline_rounded, size: 18, color: tokens.danger),
                  ),
                ),
              ),
            if (showCloseButton)
              InkWell(
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                onTap: () => _selectTodo(null),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.close_rounded, size: 18, color: tokens.textMuted),
                ),
              ),
          ],
        ),
        if (_pendingDeleteConfirm && canEdit) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: tokens.danger.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
              border: Border.all(color: tokens.danger.withValues(alpha: 0.35), width: DesktopWebTokens.hairlineWidth),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isEn ? 'Delete this task?' : '确认删除该待办？',
                    style: tokens.captionStyle.copyWith(color: tokens.danger),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _pendingDeleteConfirm = false),
                  child: Text(TodoDetailUiCopy.cancel, style: tokens.captionStyle),
                ),
                TextButton(
                  onPressed: () {
                    final id = todo.id;
                    _selectTodo(null);
                    todoProvider?.deleteTodo(id);
                  },
                  child: Text(
                    isEn ? 'Delete' : '删除',
                    style: tokens.captionStyle.copyWith(color: tokens.danger),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (!canEdit) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: tokens.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
            ),
            child: Text(
              TodoDetailUiCopy.sharedSpaceReadOnlyError,
              style: tokens.captionStyle.copyWith(color: tokens.warning),
            ),
          ),
        ],
        const SizedBox(height: 14),
        TextField(
          controller: _titleEditController,
          focusNode: _titleEditFocusNode,
          enabled: canEdit,
          style: tokens.pageTitleStyle,
          maxLines: null,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _commitInspectorTitle(),
          decoration: InputDecoration(
            hintText: TodoDetailUiCopy.taskTitleLabel,
            hintStyle: tokens.bodyMutedStyle,
            filled: true,
            fillColor: tokens.mutedSurface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
              borderSide: BorderSide(color: tokens.hairlineBorder, width: DesktopWebTokens.hairlineWidth),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
              borderSide: BorderSide(color: tokens.hairlineBorder, width: DesktopWebTokens.hairlineWidth),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
              borderSide: BorderSide(color: tokens.accentBorder, width: 1.0),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _notesEditController,
          focusNode: _notesEditFocusNode,
          enabled: canEdit,
          style: tokens.bodyMutedStyle.copyWith(color: tokens.textPrimary),
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            hintText: isEn ? 'Add notes or details...' : '添加备注或细节...',
            hintStyle: tokens.captionStyle,
            filled: true,
            fillColor: tokens.mutedSurface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
              borderSide: BorderSide(color: tokens.hairlineBorder, width: DesktopWebTokens.hairlineWidth),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
              borderSide: BorderSide(color: tokens.hairlineBorder, width: DesktopWebTokens.hairlineWidth),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
              borderSide: BorderSide(color: tokens.accentBorder, width: 1.0),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          TodoDetailUiCopy.prioritySection.toUpperCase(),
          style: tokens.sectionHeaderStyle,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in TodoPriority.values)
              _InspectorPill(
                label: p.label,
                selected: todo.priority == p,
                color: _priorityColor(p, tokens),
                tokens: tokens,
                onTap: canEdit
                    ? () {
                        todoProvider?.updateTodoWithResult(
                          todo.id,
                          todo.copyWith(priority: p),
                          waitForReminderSync: false,
                        );
                      }
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              TodoDetailUiCopy.dueDateTileTitle.toUpperCase(),
              style: tokens.sectionHeaderStyle,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                todo.dueDate == null
                    ? TodoDetailUiCopy.dueDateNotSet
                    : I18nDateFormat.date(todo.dueDate!, pattern: datePattern),
                style: tokens.captionStyle.copyWith(
                  color: todo.dueDate != null ? tokens.accent : tokens.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _InspectorPill(
              label: isEn ? 'Today' : '今天',
              selected: currentDueOnly == today,
              color: tokens.accent,
              tokens: tokens,
              onTap: canEdit
                  ? () => todoProvider?.updateTodoWithResult(
                      todo.id,
                      todo.copyWith(dueDate: today),
                      waitForReminderSync: false,
                    )
                  : null,
            ),
            _InspectorPill(
              label: isEn ? 'Tomorrow' : '明天',
              selected: currentDueOnly == tomorrow,
              color: tokens.info,
              tokens: tokens,
              onTap: canEdit
                  ? () => todoProvider?.updateTodoWithResult(
                      todo.id,
                      todo.copyWith(dueDate: tomorrow),
                      waitForReminderSync: false,
                    )
                  : null,
            ),
            _InspectorPill(
              label: isEn ? 'Next Week' : '下周',
              selected: currentDueOnly == nextWeek,
              color: tokens.success,
              tokens: tokens,
              onTap: canEdit
                  ? () => todoProvider?.updateTodoWithResult(
                      todo.id,
                      todo.copyWith(dueDate: nextWeek),
                      waitForReminderSync: false,
                    )
                  : null,
            ),
            _InspectorPill(
              label: TodoDetailUiCopy.clear,
              selected: false,
              color: tokens.textMuted,
              tokens: tokens,
              onTap: canEdit && todo.dueDate != null
                  ? () => todoProvider?.updateTodoWithResult(
                      todo.id,
                      todo.copyWith(dueDate: null),
                      waitForReminderSync: false,
                    )
                  : null,
            ),
            if (canEdit)
              InkWell(
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
                onTap: () async {
                  final picked = await AppDatePicker.pickSolar(
                    context,
                    initialDate: todo.dueDate ?? today,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                    title: isEn ? 'Pick due date' : '选择截止日期',
                  );
                  if (picked == null || !mounted) return;
                  unawaited(
                    todoProvider?.updateTodoWithResult(
                      todo.id,
                      todo.copyWith(dueDate: DateTime(picked.year, picked.month, picked.day)),
                      waitForReminderSync: false,
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: tokens.mutedSurface,
                    borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
                    border: Border.all(
                      color: tokens.hairlineBorder,
                      width: DesktopWebTokens.hairlineWidth,
                    ),
                  ),
                  child: Icon(Icons.calendar_today_outlined, size: 13, color: tokens.textSecondary),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          isEn ? 'LIST' : '所属清单',
          style: tokens.sectionHeaderStyle,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _InspectorPill(
              label: isEn ? 'Inbox / None' : '未分组',
              selected: todo.listGroupName == null || todo.listGroupName!.isEmpty,
              color: tokens.textSecondary,
              tokens: tokens,
              onTap: canEdit
                  ? () => todoProvider?.updateTodoWithResult(
                      todo.id,
                      todo.copyWith(listGroupName: null),
                      waitForReminderSync: false,
                    )
                  : null,
            ),
            for (final listName in selectableLists)
              _InspectorPill(
                label: _localizedListName(listName, isEn),
                selected: todo.listGroupName == listName,
                color: _colorForListName(listName, tokens),
                tokens: tokens,
                onTap: canEdit
                    ? () => todoProvider?.updateTodoWithResult(
                        todo.id,
                        todo.copyWith(listGroupName: listName),
                        waitForReminderSync: false,
                      )
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          TodoDetailUiCopy.quadrantLabel.toUpperCase(),
          style: tokens.sectionHeaderStyle,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _InspectorPill(
              label: isEn ? 'Q1 Do' : 'Q1 紧急重要',
              selected: todo.quadrant == EisenhowerQuadrant.urgentImportant,
              color: tokens.danger,
              tokens: tokens,
              onTap: canEdit
                  ? () => todoProvider?.updateTodosQuadrant([todo.id], EisenhowerQuadrant.urgentImportant)
                  : null,
            ),
            _InspectorPill(
              label: isEn ? 'Q2 Plan' : 'Q2 重要不紧急',
              selected: todo.quadrant == EisenhowerQuadrant.notUrgentImportant,
              color: tokens.info,
              tokens: tokens,
              onTap: canEdit
                  ? () => todoProvider?.updateTodosQuadrant([todo.id], EisenhowerQuadrant.notUrgentImportant)
                  : null,
            ),
            _InspectorPill(
              label: isEn ? 'Q3 Delegate' : 'Q3 紧急不重要',
              selected: todo.quadrant == EisenhowerQuadrant.urgentNotImportant,
              color: tokens.warning,
              tokens: tokens,
              onTap: canEdit
                  ? () => todoProvider?.updateTodosQuadrant([todo.id], EisenhowerQuadrant.urgentNotImportant)
                  : null,
            ),
            _InspectorPill(
              label: isEn ? 'Q4 Later' : 'Q4 不紧急不重要',
              selected: todo.quadrant == EisenhowerQuadrant.notUrgentNotImportant,
              color: tokens.textMuted,
              tokens: tokens,
              onTap: canEdit
                  ? () => todoProvider?.updateTodosQuadrant([todo.id], EisenhowerQuadrant.notUrgentNotImportant)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          isEn ? 'TAGS' : '标签',
          style: tokens.sectionHeaderStyle,
        ),
        const SizedBox(height: 8),
        if (todo.tags.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in todo.tags)
                InputChip(
                  visualDensity: VisualDensity.compact,
                  label: Text('#$tag', style: tokens.captionStyle),
                  onDeleted: canEdit
                      ? () {
                          final next = todo.tags.where((e) => e != tag).toList();
                          unawaited(
                            todoProvider?.updateTodoWithResult(
                              todo.id,
                              todo.copyWith(tags: next),
                              waitForReminderSync: false,
                            ),
                          );
                        }
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (canEdit) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('desktop_todo_inspector_tag_field'),
                  controller: _tagInputController,
                  style: tokens.bodyMutedStyle.copyWith(color: tokens.textPrimary),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (raw) => _addInspectorTag(todo, todoProvider, raw),
                  decoration: InputDecoration(
                    hintText: isEn ? '+ Add tag...' : '+ 添加标签...',
                    hintStyle: tokens.captionStyle,
                    filled: true,
                    fillColor: tokens.mutedSurface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                      borderSide: BorderSide(
                        color: tokens.hairlineBorder,
                        width: DesktopWebTokens.hairlineWidth,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                      borderSide: BorderSide(
                        color: tokens.hairlineBorder,
                        width: DesktopWebTokens.hairlineWidth,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                      borderSide: BorderSide(color: tokens.accentBorder, width: 1.0),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                onTap: () => _addInspectorTag(todo, todoProvider, _tagInputController.text),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: tokens.mutedSurface,
                    borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                  ),
                  child: Icon(Icons.add_rounded, size: 15, color: tokens.accent),
                ),
              ),
            ],
          ),
          if (availableTags.any((t) => !todo.tags.contains(t))) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in availableTags.where((t) => !todo.tags.contains(t)).take(6))
                  _InspectorPill(
                    label: '+ #$t',
                    selected: false,
                    color: tokens.textSecondary,
                    tokens: tokens,
                    onTap: () => _addInspectorTag(todo, todoProvider, t),
                  ),
              ],
            ),
          ],
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              isEn ? 'RECURRENCE' : '重复规则',
              style: tokens.sectionHeaderStyle,
            ),
            const Spacer(),
            if (canEdit && todo.recurrence.isActive)
              InkWell(
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                onTap: () => unawaited(
                  todoProvider?.updateTodoWithResult(
                    todo.id,
                    todo.copyWith(recurrence: const RecurrenceRule()),
                    waitForReminderSync: false,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    TodoDetailUiCopy.clear,
                    style: tokens.captionStyle.copyWith(color: tokens.textMuted),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          key: const ValueKey('desktop_todo_inspector_recurrence_btn'),
          borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
          onTap: canEdit
              ? () async {
                  final nextRule = await RecurrencePicker.show(
                    context,
                    initial: todo.recurrence,
                  );
                  if (nextRule == null || !mounted) return;
                  unawaited(
                    todoProvider?.updateTodoWithResult(
                      todo.id,
                      todo.copyWith(recurrence: nextRule),
                      waitForReminderSync: false,
                    ),
                  );
                }
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: todo.recurrence.isActive ? tokens.selectedSurface : tokens.mutedSurface,
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
              border: Border.all(
                color: todo.recurrence.isActive ? tokens.accentBorder : tokens.hairlineBorder,
                width: DesktopWebTokens.hairlineWidth,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.repeat_rounded,
                  size: 15,
                  color: todo.recurrence.isActive ? tokens.accent : tokens.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    todo.recurrence.isActive
                        ? todo.recurrence.displayLabel(datePattern: datePattern)
                        : (isEn ? 'Does not repeat' : '不重复'),
                    style: tokens.captionStyle.copyWith(
                      color: todo.recurrence.isActive ? tokens.accent : tokens.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (canEdit)
                  Icon(Icons.chevron_right_rounded, size: 16, color: tokens.textMuted),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              isEn ? 'REMINDER PLAN' : '提醒计划',
              style: tokens.sectionHeaderStyle,
            ),
            const Spacer(),
            if (canEdit)
              InkWell(
                key: const ValueKey('desktop_todo_inspector_reminder_toggle'),
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                onTap: () => setState(() => _reminderEditorExpanded = !_reminderEditorExpanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    _reminderEditorExpanded
                        ? (isEn ? 'Collapse' : '收起')
                        : (isEn ? 'Edit' : '编辑'),
                    style: tokens.captionStyle.copyWith(color: tokens.accent),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (!_reminderEditorExpanded)
          InkWell(
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
            onTap: canEdit
                ? () => setState(() => _reminderEditorExpanded = true)
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: todo.reminderPlan.enabled ? tokens.selectedSurface : tokens.mutedSurface,
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                border: Border.all(
                  color: todo.reminderPlan.enabled ? tokens.accentBorder : tokens.hairlineBorder,
                  width: DesktopWebTokens.hairlineWidth,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    todo.reminderPlan.enabled
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_none_outlined,
                    size: 15,
                    color: todo.reminderPlan.enabled ? tokens.accent : tokens.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reminderPlanSummary(todo.reminderPlan),
                      style: tokens.captionStyle.copyWith(
                        color: todo.reminderPlan.enabled ? tokens.accent : tokens.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tokens.mutedSurface,
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
              border: Border.all(
                color: tokens.hairlineBorder,
                width: DesktopWebTokens.hairlineWidth,
              ),
            ),
            child: ReminderPlanEditor(
              plan: todo.reminderPlan,
              showHeader: false,
              hasAnchorDate: todo.dueDate != null,
              defaultKind: ReminderKind.push,
              onChanged: (nextPlan) {
                final legacy = nextPlan.toLegacyReminderConfig(
                  fallback: todo.reminder,
                );
                final anyActive =
                    nextPlan.enabled && nextPlan.rules.any((r) => r.enabled);
                unawaited(
                  todoProvider?.updateTodoWithResult(
                    todo.id,
                    todo.copyWith(
                      reminderPlan: nextPlan,
                      reminder: legacy,
                      hasReminder: anyActive,
                    ),
                    waitForReminderSync: false,
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              isEn ? 'SUBTASKS' : '子任务',
              style: tokens.sectionHeaderStyle,
            ),
            const Spacer(),
            if (todo.subtasks.isNotEmpty)
              Text(
                '${todo.subtasks.where((s) => s.isCompleted).length}/${todo.subtasks.length}',
                style: tokens.captionStyle.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final sub in todo.subtasks)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                GestureDetector(
                  onTap: canEdit
                      ? () => todoProvider?.toggleSubtask(todo.id, sub.id)
                      : null,
                  child: Icon(
                    sub.isCompleted
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 16,
                    color: sub.isCompleted ? tokens.accent : tokens.textMuted,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sub.title,
                    style: tokens.bodyMutedStyle.copyWith(
                      color: sub.isCompleted ? tokens.textMuted : tokens.textPrimary,
                      decoration: sub.isCompleted ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                if (canEdit)
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => todoProvider?.deleteSubtask(todo.id, sub.id),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.close_rounded, size: 14, color: tokens.textMuted),
                    ),
                  ),
              ],
            ),
          ),
        if (canEdit)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _subtaskAddController,
                    style: tokens.bodyMutedStyle.copyWith(color: tokens.textPrimary),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submitNewSubtask(todo.id, todoProvider),
                    decoration: InputDecoration(
                      hintText: isEn ? '+ Add subtask...' : '+ 添加子任务...',
                      hintStyle: tokens.captionStyle,
                      filled: true,
                      fillColor: tokens.mutedSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                        borderSide: BorderSide(color: tokens.hairlineBorder, width: DesktopWebTokens.hairlineWidth),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                        borderSide: BorderSide(color: tokens.hairlineBorder, width: DesktopWebTokens.hairlineWidth),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                        borderSide: BorderSide(color: tokens.accentBorder, width: 1.0),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                  onTap: () => _submitNewSubtask(todo.id, todoProvider),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: tokens.mutedSurface,
                      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                    ),
                    child: Icon(Icons.add_rounded, size: 15, color: tokens.accent),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 18),
        Divider(height: 1, thickness: DesktopWebTokens.hairlineWidth, color: tokens.hairlineBorder),
        const SizedBox(height: 10),
        Text(
          isEn
              ? 'Updated ${I18nDateFormat.smartDate(todo.updatedAt, includeTime: true, pattern: datePattern)}'
              : '更新于 ${I18nDateFormat.smartDate(todo.updatedAt, includeTime: true, pattern: datePattern)}',
          style: tokens.captionStyle,
        ),
      ],
    );
  }

  void _addInspectorTag(
    TodoItem todo,
    TodoProvider? provider,
    String rawTag,
  ) {
    final trimmed = rawTag.trim();
    if (trimmed.isEmpty || provider == null) return;
    _tagInputController.clear();
    if (todo.tags.contains(trimmed)) return;
    final next = <String>[...todo.tags, trimmed];
    unawaited(
      provider.updateTodoWithResult(
        todo.id,
        todo.copyWith(tags: next),
        waitForReminderSync: false,
      ),
    );
  }

  Future<void> _submitNewSubtask(String todoId, TodoProvider? provider) async {
    if (_subtaskSubmitting || provider == null) return;
    final title = _subtaskAddController.text.trim();
    if (title.isEmpty) return;
    _subtaskSubmitting = true;
    _subtaskAddController.clear();
    try {
      await provider.addSubtask(todoId, title);
    } catch (_) {
      // Ignore duplicate rapid in-flight submissions cleanly.
    } finally {
      _subtaskSubmitting = false;
    }
  }

  void _launchFocusForTodo(String title) {
    if (widget.onStartFocus != null) {
      widget.onStartFocus!(taskTitle: title);
      return;
    }
    _attachedController?.navigateTo(DesktopWebDestination.focus);
  }

  static TodoPriority _nextPriority(TodoPriority current) => switch (current) {
    TodoPriority.none => TodoPriority.medium,
    TodoPriority.medium => TodoPriority.high,
    TodoPriority.high => TodoPriority.urgent,
    _ => TodoPriority.none,
  };

  static Color _priorityColor(TodoPriority p, DesktopWebTokens tokens) => switch (p) {
    TodoPriority.urgent => tokens.danger,
    TodoPriority.high => tokens.warning,
    TodoPriority.medium => tokens.info,
    TodoPriority.low => tokens.success,
    TodoPriority.none => tokens.textMuted,
  };

  static Color _colorForListName(String name, DesktopWebTokens tokens) {
    for (final tpl in TodoListTemplates.all) {
      if (tpl.name == name) return tpl.color;
    }
    final palette = [
      tokens.accent,
      tokens.info,
      tokens.success,
      tokens.warning,
      const Color(0xFF9C6ADE),
      const Color(0xFF2CB1BC),
    ];
    return palette[name.hashCode.abs() % palette.length];
  }

  static String _localizedListName(String rawName, bool isEn) {
    if (!isEn) return rawName;
    return switch (rawName) {
      '工作' => 'Work',
      '个人' => 'Personal',
      '学习' => 'Study',
      '购物' => 'Shopping',
      '阅读清单' => 'Reading List',
      '健身' => 'Fitness',
      _ => rawName,
    };
  }

  static String _smartFilterLabel(_TodoSmartFilter filter, bool isEn) => switch (filter) {
    _TodoSmartFilter.all => isEn ? 'All Todos' : '全部待办',
    _TodoSmartFilter.today => isEn ? 'Today' : '今天',
    _TodoSmartFilter.next7Days => isEn ? 'Next 7 Days' : '最近 7 天',
    _TodoSmartFilter.highPriority => isEn ? 'High Priority' : '高优先级',
    _TodoSmartFilter.completed => isEn ? 'Completed' : '已完成',
  };

  static String _sortModeLabel(_TodoSortMode mode, bool isEn) => switch (mode) {
    _TodoSortMode.manual => isEn ? 'Manual' : '手动排序',
    _TodoSortMode.smart => isEn ? 'Smart' : '智能排序',
    _TodoSortMode.priority => isEn ? 'Priority' : '优先级',
    _TodoSortMode.dueDate => isEn ? 'Due Date' : '截止日期',
    _TodoSortMode.createdAt => isEn ? 'Created' : '创建时间',
  };

  static String _localizedKanbanTitle(TodoKanbanColumn column, bool isEn) {
    if (!column.builtIn) return column.title;
    return switch (column.id) {
      defaultKanbanPendingColumnId => isEn ? 'To Do' : '待办',
      defaultKanbanInProgressColumnId => isEn ? 'In Progress' : '进行中',
      defaultKanbanDoneColumnId => isEn ? 'Done' : '已完成',
      _ => column.title,
    };
  }
}

class _SidebarNavTileShell extends StatelessWidget {
  final Widget leading;
  final String label;
  final int count;
  final bool selected;
  final DesktopWebTokens tokens;
  final VoidCallback onTap;

  const _SidebarNavTileShell({
    required this.leading,
    required this.label,
    required this.count,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          DesktopHoverTile(
            selected: selected,
            onTap: onTap,
            padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    style: tokens.navItemStyle.copyWith(
                      color: selected ? tokens.accent : tokens.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (count > 0)
                  Text(
                    '$count',
                    style: tokens.captionStyle.copyWith(
                      color: selected ? tokens.accent : tokens.textMuted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
          if (selected)
            Positioned(
              left: 3,
              top: 7,
              bottom: 7,
              child: IgnorePointer(
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: tokens.accent,
                    borderRadius: BorderRadius.circular(
                      DesktopWebTokens.radiusPill,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SmartFilterTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final DesktopWebTokens tokens;
  final VoidCallback onTap;

  const _SmartFilterTile({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _SidebarNavTileShell(
      leading: Icon(
        icon,
        size: 16,
        color: selected ? tokens.accent : tokens.textSecondary,
      ),
      label: label,
      count: count,
      selected: selected,
      tokens: tokens,
      onTap: onTap,
    );
  }
}

class _ListSidebarTile extends StatelessWidget {
  final String label;
  final Color dotColor;
  final int count;
  final bool selected;
  final DesktopWebTokens tokens;
  final VoidCallback onTap;

  const _ListSidebarTile({
    required this.label,
    required this.dotColor,
    required this.count,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _SidebarNavTileShell(
      leading: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
      ),
      label: label,
      count: count,
      selected: selected,
      tokens: tokens,
      onTap: onTap,
    );
  }
}

class _ViewModeSwitcher extends StatelessWidget {
  final _TodoViewMode mode;
  final DesktopWebTokens tokens;
  final bool isEn;
  final ValueChanged<_TodoViewMode> onChanged;

  const _ViewModeSwitcher({
    required this.mode,
    required this.tokens,
    required this.isEn,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: tokens.mutedSurface,
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
        border: Border.all(
          color: tokens.hairlineBorder,
          width: DesktopWebTokens.hairlineWidth,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            selected: mode == _TodoViewMode.list,
            label: isEn ? 'List' : '列表',
            onTap: () => onChanged(_TodoViewMode.list),
          ),
          _segment(
            selected: mode == _TodoViewMode.kanban,
            label: isEn ? 'Board' : '看板',
            onTap: () => onChanged(_TodoViewMode.kanban),
          ),
          _segment(
            selected: mode == _TodoViewMode.matrix,
            label: isEn ? 'Matrix' : '四象限',
            onTap: () => onChanged(_TodoViewMode.matrix),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required bool selected,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? tokens.panelSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: selected
              ? Border.all(color: tokens.hairlineBorder, width: DesktopWebTokens.hairlineWidth)
              : null,
        ),
        child: Text(
          label,
          style: tokens.captionStyle.copyWith(
            color: selected ? tokens.accent : tokens.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _DesktopTodoRow extends StatefulWidget {
  final TodoItem todo;
  final bool selected;
  final bool batchMode;
  final bool batchSelected;
  final DateTime now;
  final DateTime today;
  final String? datePattern;
  final bool isEn;
  final DesktopWebTokens tokens;
  final bool canEdit;
  final VoidCallback onSelect;
  final VoidCallback? onToggleBatchSelect;
  final VoidCallback onToggle;
  final VoidCallback onScheduleToday;
  final VoidCallback onFocus;
  final VoidCallback onDelete;

  const _DesktopTodoRow({
    required this.todo,
    required this.selected,
    this.batchMode = false,
    this.batchSelected = false,
    required this.now,
    required this.today,
    this.datePattern,
    required this.isEn,
    required this.tokens,
    required this.canEdit,
    required this.onSelect,
    this.onToggleBatchSelect,
    required this.onToggle,
    required this.onScheduleToday,
    required this.onFocus,
    required this.onDelete,
  });

  @override
  State<_DesktopTodoRow> createState() => _DesktopTodoRowState();
}

class _DesktopTodoRowState extends State<_DesktopTodoRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.todo;
    final tokens = widget.tokens;
    final visual = CompletionVisibilityPolicy.visualState(t, now: widget.now);
    final prioColor = _DesktopTodoViewState._priorityColor(t.priority, tokens);
    final dueColor = switch (visual) {
      TodoVisualState.overdue => tokens.danger,
      TodoVisualState.dueSoon => tokens.warning,
      TodoVisualState.completed || TodoVisualState.archived => tokens.textMuted,
      TodoVisualState.normal => tokens.textSecondary,
    };

    final dueText = t.dueDate == null
        ? null
        : (CompletionVisibilityPolicy.dateOnly(t.dueDate!) == widget.today
              ? (widget.isEn ? 'Today' : '今天')
              : I18nDateFormat.date(t.dueDate!, pattern: widget.datePattern));

    final listLabel = t.listGroupName == null
        ? null
        : _DesktopTodoViewState._localizedListName(t.listGroupName!, widget.isEn);
    final hasSubtasks = t.subtasks.isNotEmpty;
    final doneSubtasks = t.subtasks.where((s) => s.isCompleted).length;
    final isHighlighted = widget.batchMode ? widget.batchSelected : widget.selected;
    final boxChecked = widget.batchMode ? widget.batchSelected : t.isCompleted;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.batchMode
            ? (widget.onToggleBatchSelect ?? widget.onSelect)
            : widget.onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isHighlighted
                ? tokens.selectedSurface
                : (_hovered ? tokens.hoverSurface : tokens.panelSurface),
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
            border: Border.all(
              color: isHighlighted ? tokens.accentBorder : tokens.hairlineBorder,
              width: DesktopWebTokens.hairlineWidth,
            ),
          ),
          child: Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.batchMode
                    ? widget.onToggleBatchSelect
                    : (widget.canEdit ? widget.onToggle : null),
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 130),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: boxChecked ? tokens.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: boxChecked
                            ? tokens.accent
                            : (t.priority != TodoPriority.none ? prioColor : tokens.strongBorder),
                        width: 1.4,
                      ),
                    ),
                    child: boxChecked
                        ? Icon(Icons.check_rounded, size: 13, color: tokens.accentForeground)
                        : null,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (t.priority != TodoPriority.none)
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 7),
                            decoration: BoxDecoration(shape: BoxShape.circle, color: prioColor),
                          ),
                        Expanded(
                          child: Text(
                            t.title,
                            style: tokens.bodyStyle.copyWith(
                              color: t.isCompleted ? tokens.textMuted : tokens.textPrimary,
                              decoration: t.isCompleted ? TextDecoration.lineThrough : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (t.notes.trim().isNotEmpty ||
                        hasSubtasks ||
                        t.tags.isNotEmpty ||
                        t.recurrence.isActive ||
                        t.reminderPlan.enabled)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          children: [
                            if (t.recurrence.isActive) ...[
                              Icon(Icons.repeat_rounded, size: 12, color: tokens.accent),
                              const SizedBox(width: 4),
                            ],
                            if (t.reminderPlan.enabled) ...[
                              Icon(Icons.notifications_active_outlined, size: 12, color: tokens.accent),
                              const SizedBox(width: 4),
                            ],
                            if (hasSubtasks) ...[
                              Icon(Icons.checklist_rounded, size: 12, color: tokens.textMuted),
                              const SizedBox(width: 3),
                              Text(
                                '$doneSubtasks/${t.subtasks.length}',
                                style: tokens.captionStyle.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              if (t.tags.isNotEmpty || t.notes.trim().isNotEmpty)
                                const SizedBox(width: 8),
                            ],
                            for (final tag in t.tags.take(2)) ...[
                              Container(
                                margin: const EdgeInsets.only(right: 5),
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: tokens.accentSoft,
                                  borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
                                ),
                                child: Text(
                                  '#$tag',
                                  style: tokens.captionStyle.copyWith(color: tokens.accent, fontSize: 10),
                                ),
                              ),
                            ],
                            if (t.notes.trim().isNotEmpty)
                              Expanded(
                                child: Text(
                                  t.notes.trim().replaceAll('\n', ' '),
                                  style: tokens.captionStyle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (t.priority == TodoPriority.urgent || t.priority == TodoPriority.high)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: prioColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
                    ),
                    child: Text(
                      t.priority.label,
                      style: tokens.captionStyle.copyWith(color: prioColor),
                    ),
                  ),
                ),
              if (listLabel != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: tokens.mutedSurface,
                      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _DesktopTodoViewState._colorForListName(
                              t.listGroupName!,
                              tokens,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 110),
                          child: Text(
                            listLabel,
                            style: tokens.captionStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (dueText != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: visual == TodoVisualState.overdue
                        ? tokens.danger.withValues(alpha: 0.12)
                        : tokens.mutedSurface,
                    borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
                  ),
                  child: Text(
                    dueText,
                    style: tokens.captionStyle.copyWith(
                      color: dueColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              if (_hovered) ...[
                const SizedBox(width: 6),
                if (!t.isCompleted)
                  Tooltip(
                    message: widget.isEn ? 'Start Focus' : '开始专注',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(5),
                      onTap: widget.onFocus,
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(Icons.play_arrow_rounded, size: 16, color: tokens.accent),
                      ),
                    ),
                  ),
                if (widget.canEdit &&
                    (t.dueDate == null ||
                        CompletionVisibilityPolicy.dateOnly(t.dueDate!) != widget.today))
                  Tooltip(
                    message: widget.isEn ? 'Due today' : '设为今天',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(5),
                      onTap: widget.onScheduleToday,
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(Icons.today_outlined, size: 15, color: tokens.textSecondary),
                      ),
                    ),
                  ),
                if (widget.canEdit)
                  Tooltip(
                    message: widget.isEn ? 'Delete' : '删除',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(5),
                      onTap: widget.onDelete,
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(Icons.delete_outline_rounded, size: 15, color: tokens.danger),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _KanbanTodoCard extends StatelessWidget {
  final TodoItem todo;
  final bool selected;
  final DesktopWebTokens tokens;
  final bool isEn;
  final DateTime now;
  final String? datePattern;
  final bool canEdit;
  final List<TodoKanbanColumn> allColumns;
  final String currentColumnId;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final ValueChanged<String> onMoveColumn;

  const _KanbanTodoCard({
    required this.todo,
    required this.selected,
    required this.tokens,
    required this.isEn,
    required this.now,
    this.datePattern,
    required this.canEdit,
    required this.allColumns,
    required this.currentColumnId,
    required this.onTap,
    required this.onToggle,
    required this.onMoveColumn,
  });

  @override
  Widget build(BuildContext context) {
    final prioColor = _DesktopTodoViewState._priorityColor(todo.priority, tokens);
    final visual = CompletionVisibilityPolicy.visualState(todo, now: now);
    final dueColor = switch (visual) {
      TodoVisualState.overdue => tokens.danger,
      TodoVisualState.dueSoon => tokens.warning,
      TodoVisualState.completed || TodoVisualState.archived => tokens.textMuted,
      TodoVisualState.normal => tokens.textSecondary,
    };
    final hasSubtasks = todo.subtasks.isNotEmpty;
    final doneSubtasks = todo.subtasks.where((s) => s.isCompleted).length;
    return InkWell(
      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? tokens.selectedSurface : tokens.panelSurface,
          borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
          border: Border.all(
            color: selected ? tokens.accentBorder : tokens.hairlineBorder,
            width: DesktopWebTokens.hairlineWidth,
          ),
          boxShadow: tokens.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: canEdit ? onToggle : null,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8, top: 2),
                    child: Icon(
                      todo.isCompleted
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 16,
                      color: todo.isCompleted ? tokens.accent : prioColor,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    todo.title,
                    style: tokens.bodyStyle.copyWith(
                      color: todo.isCompleted ? tokens.textMuted : tokens.textPrimary,
                      decoration: todo.isCompleted ? TextDecoration.lineThrough : null,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (canEdit && allColumns.length > 1)
                  PopupMenuButton<String>(
                    tooltip: isEn ? 'Move column' : '移动到列',
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.more_horiz_rounded, size: 15, color: tokens.textMuted),
                    onSelected: onMoveColumn,
                    itemBuilder: (context) => [
                      for (final c in allColumns)
                        if (c.id != currentColumnId)
                          PopupMenuItem(
                            value: c.id,
                            child: Text(
                              _DesktopTodoViewState._localizedKanbanTitle(c, isEn),
                              style: tokens.bodyStyle,
                            ),
                          ),
                    ],
                  ),
              ],
            ),
            if (todo.dueDate != null || todo.listGroupName != null || hasSubtasks)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (todo.dueDate != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: visual == TodoVisualState.overdue
                              ? tokens.danger.withValues(alpha: 0.12)
                              : tokens.mutedSurface,
                          borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
                        ),
                        child: Text(
                          I18nDateFormat.date(todo.dueDate!, pattern: datePattern),
                          style: tokens.captionStyle.copyWith(
                            color: dueColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    if (todo.listGroupName != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: tokens.mutedSurface,
                          borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
                        ),
                        child: Text(
                          _DesktopTodoViewState._localizedListName(todo.listGroupName!, isEn),
                          style: tokens.captionStyle,
                        ),
                      ),
                    if (hasSubtasks)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: tokens.mutedSurface,
                          borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
                        ),
                        child: Text(
                          '$doneSubtasks/${todo.subtasks.length}',
                          style: tokens.captionStyle.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InspectorPill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final DesktopWebTokens tokens;
  final VoidCallback? onTap;

  const _InspectorPill({
    required this.label,
    required this.selected,
    required this.color,
    required this.tokens,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.16) : tokens.mutedSurface,
          borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.45) : tokens.hairlineBorder,
            width: DesktopWebTokens.hairlineWidth,
          ),
        ),
        child: Text(
          label,
          style: tokens.captionStyle.copyWith(
            color: selected ? color : tokens.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ShortcutGuideRow extends StatelessWidget {
  final String keycap;
  final String description;
  final DesktopWebTokens tokens;

  const _ShortcutGuideRow({
    required this.keycap,
    required this.description,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DesktopKeycap(label: keycap),
        const SizedBox(width: 10),
        Expanded(child: Text(description, style: tokens.bodyMutedStyle)),
      ],
    );
  }
}
