import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/account_preference_writes.dart';
import '../core/almanac_ui_copy.dart';
import '../core/app_brand.dart';
import '../core/global_search.dart';
import '../core/i18n.dart';
import '../core/smart_todo_draft.dart';
import '../models/calendar_event.dart';
import '../models/diary_entry.dart';
import '../models/goal.dart';
import '../models/habit.dart';
import '../models/note.dart';
import '../providers/anniversary_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/countdown_provider.dart';
import '../providers/course_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/note_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/time_audit_provider.dart';
import '../providers/todo_provider.dart';
import 'desktop_web_nav.dart';
import 'desktop_web_tokens.dart';

/// Test counter incremented only when [GlobalSearch.run] is actually executed
/// by the Desktop Command Palette.
@visibleForTesting
int debugDesktopCommandPaletteSearchCount = 0;

/// Opens the Desktop Web Ctrl/Cmd+K instant command & search modal.
Future<void> showDesktopCommandPalette(
  BuildContext context, {
  required DesktopWebNavController controller,
  DesktopCommandMode initialMode = DesktopCommandMode.search,
  String? initialQuery,
}) {
  final capturedTheme = Theme.of(context);
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierColor: Colors.black.withValues(alpha: 0.36),
    builder: (dialogContext) => Theme(
      data: capturedTheme,
      child: _DesktopCommandPaletteDialog(
        hostContext: context,
        controller: controller,
        initialMode: initialMode,
        initialQuery: initialQuery ?? '',
      ),
    ),
  );
}

/// Opens a clean desktop quick-create dialog for the requested entity type.
Future<void> showDesktopQuickCreateDialog(
  BuildContext context, {
  required DesktopWebNavController navController,
  required DesktopQuickCreateKind kind,
  String initialTitle = '',
}) async {
  if (kind == DesktopQuickCreateKind.focus) {
    final pomodoro = context.read<PomodoroProvider?>();
    if (pomodoro != null) {
      if (initialTitle.trim().isNotEmpty) {
        pomodoro.setTaskName(initialTitle.trim());
      }
      pomodoro.startIfIdle();
    }
    navController.navigateTo(DesktopWebDestination.focus);
    return;
  }

  final capturedTheme = Theme.of(context);
  await showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierColor: Colors.black.withValues(alpha: 0.36),
    builder: (dialogCtx) => Theme(
      data: capturedTheme,
      child: _DesktopQuickCreateDialog(
        hostContext: context,
        navController: navController,
        kind: kind,
        initialTitle: initialTitle,
      ),
    ),
  );
}

class _DesktopQuickCreateDialog extends StatefulWidget {
  final BuildContext hostContext;
  final DesktopWebNavController navController;
  final DesktopQuickCreateKind kind;
  final String initialTitle;

  const _DesktopQuickCreateDialog({
    required this.hostContext,
    required this.navController,
    required this.kind,
    required this.initialTitle,
  });

  @override
  State<_DesktopQuickCreateDialog> createState() =>
      _DesktopQuickCreateDialogState();
}

class _DesktopQuickCreateDialogState extends State<_DesktopQuickCreateDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _notesCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle);
    _notesCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(DesktopWebTokens tokens, bool isEn) async {
    final text = _titleCtrl.text.trim();
    if (text.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final hostContext = widget.hostContext;
      final navController = widget.navController;
      switch (widget.kind) {
        case DesktopQuickCreateKind.todo:
          final todoProvider = hostContext.read<TodoProvider?>();
          if (todoProvider != null) {
            final draft = SmartTodoDraftBuilder.fromText(text);
            final item = draft.toTodo();
            if (_notesCtrl.text.trim().isNotEmpty) {
              item.notes = _notesCtrl.text.trim();
            }
            await todoProvider.addTodo(
              item,
              waitForReminderSync: false,
            );
            navController.selectTodo(item.id);
          }
        case DesktopQuickCreateKind.habit:
          final habitProvider = hostContext.read<HabitProvider?>();
          final habitId = 'habit-${now.microsecondsSinceEpoch}';
          if (habitProvider != null) {
            await habitProvider.addHabit(
              Habit(
                id: habitId,
                name: text,
                category: isEn ? 'Daily' : '日常',
              ),
            );
          }
          navController.navigateTo(
            DesktopWebDestination.habit,
            selectedEntityId: habitId,
            selectedEntityKind: SearchKind.habit,
          );
        case DesktopQuickCreateKind.goal:
          final goalProvider = hostContext.read<GoalProvider?>();
          final goal = GoalItem(
            title: text,
            description: _notesCtrl.text.trim(),
          );
          if (goalProvider != null) {
            await goalProvider.add(goal);
          }
          navController.navigateTo(
            DesktopWebDestination.goals,
            selectedEntityId: goal.id,
            selectedEntityKind: SearchKind.goal,
          );
        case DesktopQuickCreateKind.note:
          final noteProvider = hostContext.read<NoteProvider?>();
          final noteId = now.microsecondsSinceEpoch.toString();
          if (noteProvider != null) {
            final content = _notesCtrl.text.trim().isEmpty
                ? text
                : '$text\n${_notesCtrl.text.trim()}';
            await noteProvider.addOrUpdateNotePersisted(
              NoteItem(
                id: noteId,
                content: content,
                createdAt: now,
                updatedAt: now,
              ),
            );
          }
          navController.navigateTo(
            DesktopWebDestination.notes,
            selectedEntityId: noteId,
            selectedEntityKind: SearchKind.note,
          );
        case DesktopQuickCreateKind.diary:
          final diaryProvider = hostContext.read<DiaryProvider?>();
          final entry = DiaryEntry(
            date: DateTime(now.year, now.month, now.day),
            content: _notesCtrl.text.trim().isEmpty
                ? text
                : '$text\n${_notesCtrl.text.trim()}',
          );
          if (diaryProvider != null) {
            await diaryProvider.addOrUpdate(entry);
          }
          navController.navigateTo(
            DesktopWebDestination.diary,
            selectedEntityId: entry.id,
            selectedEntityKind: SearchKind.diary,
          );
        case DesktopQuickCreateKind.calendarEvent:
          final calendarProvider = hostContext.read<CalendarProvider?>();
          final eventDate = DateTime(now.year, now.month, now.day);
          final eventId = 'evt-${now.microsecondsSinceEpoch}';
          if (calendarProvider != null) {
            await calendarProvider.addLocalEvent(
              CalendarEvent(
                id: eventId,
                title: text,
                date: eventDate,
                type: CalendarEventType.event,
                color: tokens.accent,
                note: _notesCtrl.text.trim().isEmpty
                    ? null
                    : _notesCtrl.text.trim(),
              ),
            );
          }
          navController.navigateTo(
            DesktopWebDestination.calendar,
            selectedEntityId: eventId,
            selectedEntityKind: SearchKind.calendarEvent,
            focusedDate: eventDate,
          );
        case DesktopQuickCreateKind.focus:
          break;
      }
      if (mounted) Navigator.of(context).pop();
    } on AccountPreferenceWriteCanceled {
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWebTokens.of(context);
    final isEn = I18n.current == AppLocale.en;
    final kind = widget.kind;
    final (title, hint, icon) = switch (kind) {
      DesktopQuickCreateKind.todo => (
        isEn ? 'Quick Create Task' : '快速新建待办',
        isEn
            ? 'e.g. Review quarterly plan tomorrow 3pm'
            : '例如：明天下午3点整理季度复盘',
        Icons.check_circle_outline,
      ),
      DesktopQuickCreateKind.habit => (
        isEn ? 'Quick Create Habit' : '快速新建习惯',
        isEn ? 'e.g. Read 20 pages daily' : '例如：每天阅读 20 分钟',
        Icons.repeat_rounded,
      ),
      DesktopQuickCreateKind.goal => (
        isEn ? 'Quick Create Goal' : '快速新建目标',
        isEn ? 'e.g. Complete certification Q4' : '例如：完成季度核心项目',
        Icons.flag_outlined,
      ),
      DesktopQuickCreateKind.note => (
        isEn ? 'Quick Note' : '随手记',
        isEn ? 'Capture an idea or snippet...' : '记录此刻的想法或备忘...',
        Icons.edit_note_rounded,
      ),
      DesktopQuickCreateKind.diary => (
        isEn ? 'Quick Diary Entry' : '写日记',
        isEn ? 'How did today go?' : '写下今天的心情与故事...',
        Icons.menu_book_outlined,
      ),
      DesktopQuickCreateKind.calendarEvent => (
        isEn ? 'New Calendar Event' : '新建日程',
        isEn ? 'Event title...' : '日程标题...',
        Icons.event_available_outlined,
      ),
      DesktopQuickCreateKind.focus => (
        isEn ? 'Start Focus' : '开始专注',
        '',
        Icons.timer_outlined,
      ),
    };

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: tokens.elevatedSurface,
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXl),
            border: Border.all(
              color: tokens.hairlineBorder,
              width: DesktopWebTokens.hairlineWidth,
            ),
            boxShadow: tokens.modalShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.success.withValues(
                        alpha: tokens.isDark ? 0.18 : 0.12,
                      ),
                      borderRadius: BorderRadius.circular(
                        DesktopWebTokens.radiusSm,
                      ),
                      border: Border.all(
                        color: tokens.success.withValues(
                          alpha: tokens.isDark ? 0.30 : 0.22,
                        ),
                        width: DesktopWebTokens.hairlineWidth,
                      ),
                    ),
                    child: Icon(icon, size: 17, color: tokens.success),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title, style: tokens.cardTitleStyle),
                  ),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: tokens.textMuted,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('desktop_quick_create_title_field'),
                controller: _titleCtrl,
                autofocus: true,
                readOnly: _saving,
                maxLines:
                    kind == DesktopQuickCreateKind.note ||
                        kind == DesktopQuickCreateKind.diary
                    ? 4
                    : 1,
                textInputAction:
                    kind == DesktopQuickCreateKind.note ||
                        kind == DesktopQuickCreateKind.diary
                    ? TextInputAction.newline
                    : TextInputAction.done,
                onSubmitted: (_) => _submit(tokens, isEn),
                style: tokens.bodyStyle,
                decoration: InputDecoration(hintText: hint),
              ),
              if (kind == DesktopQuickCreateKind.todo ||
                  kind == DesktopQuickCreateKind.goal ||
                  kind == DesktopQuickCreateKind.calendarEvent) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _notesCtrl,
                  readOnly: _saving,
                  maxLines: 2,
                  style: tokens.bodyMutedStyle,
                  decoration: InputDecoration(
                    hintText: isEn ? 'Notes (optional)...' : '补充备注（可选）...',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      isEn ? 'Cancel' : '取消',
                      style: tokens.bodyMutedStyle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('desktop_quick_create_submit'),
                    onPressed: _saving ? null : () => _submit(tokens, isEn),
                    style: FilledButton.styleFrom(
                      backgroundColor: tokens.accent,
                      foregroundColor: tokens.accentForeground,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          DesktopWebTokens.radiusSm,
                        ),
                      ),
                    ),
                    child: Text(isEn ? 'Create' : '创建'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _PaletteCategory {
  instantCreate,
  searchResult,
  quickCreate,
  navigate,
  almanacTool,
  appearance,
}

class _PaletteAction {
  final String id;
  final _PaletteCategory category;
  final String title;
  final String subtitle;
  final IconData icon;
  final String? badge;
  final VoidCallback onExecute;

  const _PaletteAction({
    required this.id,
    required this.category,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.badge,
    required this.onExecute,
  });
}

class _PaletteRow {
  final _PaletteCategory? headerCategory;
  final _PaletteAction? action;
  final int? actionIndex;
  final bool isFirstHeader;

  const _PaletteRow.header(
    _PaletteCategory category, {
    required this.isFirstHeader,
  }) : headerCategory = category,
       action = null,
       actionIndex = null;

  const _PaletteRow.item(
    _PaletteAction this.action,
    int this.actionIndex,
  ) : headerCategory = null,
      isFirstHeader = false;
}

class _DesktopCommandPaletteDialog extends StatefulWidget {
  final BuildContext hostContext;
  final DesktopWebNavController controller;
  final DesktopCommandMode initialMode;
  final String initialQuery;

  const _DesktopCommandPaletteDialog({
    required this.hostContext,
    required this.controller,
    required this.initialMode,
    required this.initialQuery,
  });

  @override
  State<_DesktopCommandPaletteDialog> createState() =>
      _DesktopCommandPaletteDialogState();
}

enum _PaletteFilter { all, jump, create }

const List<String> _almanacKeywords = <String>[
  '万年历',
  '黄历',
  '老黄历',
  '农历',
  '阴历',
  '择吉',
  '吉日',
  '放假',
  '节假日',
  '调休',
  '节气',
  '八字',
  '闰月',
  'almanac',
  'lunar',
  'holiday',
  'auspicious',
  'bazi',
  'solar term',
];

class _DesktopCommandPaletteDialogState
    extends State<_DesktopCommandPaletteDialog> {
  static const Duration _searchDebounceDuration = Duration(milliseconds: 120);

  late final TextEditingController _queryCtrl;
  late final FocusNode _inputFocusNode;
  late final ScrollController _listScrollCtrl;
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};
  late _PaletteFilter _filter;
  Timer? _debounceTimer;
  late String _debouncedQuery;
  String? _cachedSearchQuery;
  List<SearchHit> _cachedSearchHits = const <SearchHit>[];
  String? _cachedActionsQuery;
  _PaletteFilter? _cachedActionsFilter;
  AppLocale? _cachedActionsLocale;
  List<_PaletteAction> _cachedActions = const <_PaletteAction>[];
  List<_PaletteRow> _cachedRows = const <_PaletteRow>[];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _queryCtrl = TextEditingController(text: widget.initialQuery);
    _debouncedQuery = widget.initialQuery.trim();
    _inputFocusNode = FocusNode();
    _listScrollCtrl = ScrollController();
    _filter = widget.initialMode == DesktopCommandMode.quickCreate
        ? _PaletteFilter.create
        : _PaletteFilter.all;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _listScrollCtrl.dispose();
    _inputFocusNode.dispose();
    _queryCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String raw) {
    final trimmed = raw.trim();
    _debounceTimer?.cancel();
    if (trimmed.isEmpty) {
      if (_debouncedQuery.isNotEmpty || _selectedIndex != 0) {
        setState(() {
          _debouncedQuery = '';
          _selectedIndex = 0;
        });
      }
      return;
    }
    _debounceTimer = Timer(_searchDebounceDuration, () {
      if (!mounted) return;
      final latest = _queryCtrl.text.trim();
      if (latest != _debouncedQuery || _selectedIndex != 0) {
        setState(() {
          _debouncedQuery = latest;
          _selectedIndex = 0;
        });
      }
    });
  }

  void _flushPendingQuery() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    final latest = _queryCtrl.text.trim();
    if (latest != _debouncedQuery) {
      _debouncedQuery = latest;
    }
  }

  void _closeAndRun(VoidCallback fn) {
    if (mounted) {
      Navigator.of(context).pop();
    }
    fn();
  }

  void _ensureActionsCached(AppLocale locale) {
    final query = _debouncedQuery;
    if (_cachedActionsQuery == query &&
        _cachedActionsFilter == _filter &&
        _cachedActionsLocale == locale) {
      return;
    }
    final built = _buildActions(locale, query);
    final rows = <_PaletteRow>[];
    _PaletteCategory? currentCategory;
    for (var i = 0; i < built.length; i++) {
      final item = built[i];
      if (item.category != currentCategory) {
        rows.add(
          _PaletteRow.header(
            item.category,
            isFirstHeader: rows.isEmpty,
          ),
        );
        currentCategory = item.category;
      }
      rows.add(_PaletteRow.item(item, i));
    }
    _cachedActionsQuery = query;
    _cachedActionsFilter = _filter;
    _cachedActionsLocale = locale;
    _cachedActions = built;
    _cachedRows = rows;
  }

  List<_PaletteAction> _actionsFor(AppLocale locale) {
    _ensureActionsCached(locale);
    return _cachedActions;
  }

  List<_PaletteRow> _rowsFor(AppLocale locale) {
    _ensureActionsCached(locale);
    return _cachedRows;
  }

  List<_PaletteAction> _buildActions(AppLocale locale, String query) {
    final isEn = locale == AppLocale.en;
    final lowerQuery = query.toLowerCase();
    final actions = <_PaletteAction>[];

    if (query.isNotEmpty && _filter != _PaletteFilter.jump) {
      actions.add(
        _PaletteAction(
          id: 'instant-todo',
          category: _PaletteCategory.instantCreate,
          title: isEn ? 'Create task: "$query"' : '快速创建待办：「$query」',
          subtitle: isEn ? 'Add directly to Todo' : '按智能日期解析并添加到待办',
          icon: Icons.add_task_rounded,
          badge: 'Enter',
          onExecute: () => _closeAndRun(() async {
            final todos = widget.hostContext.read<TodoProvider?>();
            if (todos != null) {
              final draft = SmartTodoDraftBuilder.fromText(query);
              final item = draft.toTodo();
              await todos.addTodo(item, waitForReminderSync: false);
              widget.controller.navigateTo(
                DesktopWebDestination.todo,
                selectedTodoId: item.id,
                selectedEntityId: item.id,
                selectedEntityKind: SearchKind.todo,
              );
            }
          }),
        ),
      );
      actions.add(
        _PaletteAction(
          id: 'instant-note',
          category: _PaletteCategory.instantCreate,
          title: isEn ? 'Save quick note: "$query"' : '保存为随手记：「$query」',
          subtitle: isEn ? 'Create a note immediately' : '立即写入随手记',
          icon: Icons.edit_note_rounded,
          onExecute: () => _closeAndRun(() async {
            final notes = widget.hostContext.read<NoteProvider?>();
            if (notes != null) {
              final now = DateTime.now();
              final noteId = now.microsecondsSinceEpoch.toString();
              await notes.addOrUpdateNotePersisted(
                NoteItem(
                  id: noteId,
                  content: query,
                  createdAt: now,
                  updatedAt: now,
                ),
              );
              widget.controller.navigateTo(
                DesktopWebDestination.notes,
                selectedEntityId: noteId,
                selectedEntityKind: SearchKind.note,
              );
            }
          }),
        ),
      );
    }

    if (query.isNotEmpty && _filter != _PaletteFilter.create) {
      final hits = _runSearchMemoized(query);
      for (final hit in hits) {
        final dest = _destinationForSearchKind(hit.kind);
        actions.add(
          _PaletteAction(
            id: 'search-${hit.kind.name}-${hit.sourceId}',
            category: _PaletteCategory.searchResult,
            title: hit.titleFor(locale),
            subtitle: hit.subtitle?.trim().isNotEmpty == true
                ? '${hit.kindLabel} · ${hit.subtitle}'
                : hit.kindLabel,
            icon: hit.icon,
            badge: dest.localizedLabel(locale),
            onExecute: () => _closeAndRun(() {
              widget.controller.navigateTo(
                dest,
                selectedTodoId:
                    hit.kind == SearchKind.todo ? hit.sourceId : null,
                selectedEntityId: hit.sourceId,
                selectedEntityKind: hit.kind,
                focusedDate: hit.when,
              );
            }),
          ),
        );
      }
    }

    if (_filter != _PaletteFilter.jump) {
      final createCommands = <(DesktopQuickCreateKind, IconData, String, String)>[
        (
          DesktopQuickCreateKind.todo,
          Icons.check_circle_outline,
          isEn ? 'Create Task' : '快速新建待办',
          isEn ? 'Add a new task or reminder' : '添加一条新的待办事项',
        ),
        (
          DesktopQuickCreateKind.habit,
          Icons.repeat_rounded,
          isEn ? 'Create Habit' : '快速新建习惯',
          isEn ? 'Track a daily or weekly habit' : '新建打卡或戒除习惯',
        ),
        (
          DesktopQuickCreateKind.goal,
          Icons.flag_outlined,
          isEn ? 'Create Goal' : '快速新建目标',
          isEn ? 'Define a long-term goal' : '设定一个长期目标',
        ),
        (
          DesktopQuickCreateKind.note,
          Icons.edit_note_rounded,
          isEn ? 'Create Note' : '新建随手记',
          isEn ? 'Capture quick thoughts' : '记录灵感、清单或备忘',
        ),
        (
          DesktopQuickCreateKind.diary,
          Icons.menu_book_outlined,
          isEn ? 'Write Diary Entry' : '快速写日记',
          isEn ? 'Record today’s mood & thoughts' : '记录今天的心情与故事',
        ),
        (
          DesktopQuickCreateKind.calendarEvent,
          Icons.event_available_outlined,
          isEn ? 'Create Calendar Event' : '快速新建日程',
          isEn ? 'Schedule an event on calendar' : '在日历中添加一条新日程',
        ),
        (
          DesktopQuickCreateKind.focus,
          Icons.timer_outlined,
          isEn ? 'Start 25m Focus' : '开始番茄专注',
          isEn ? 'Launch focus timer immediately' : '立即开启一轮专注计时',
        ),
      ];

      for (final (kind, icon, title, subtitle) in createCommands) {
        if (lowerQuery.isEmpty ||
            title.toLowerCase().contains(lowerQuery) ||
            subtitle.toLowerCase().contains(lowerQuery) ||
            kind.name.toLowerCase().contains(lowerQuery)) {
          actions.add(
            _PaletteAction(
              id: 'create-${kind.name}',
              category: _PaletteCategory.quickCreate,
              title: title,
              subtitle: subtitle,
              icon: icon,
              badge: isEn ? 'Create' : '创建',
              onExecute: () => _closeAndRun(() {
                widget.controller.triggerQuickCreate(kind);
              }),
            ),
          );
        }
      }
    }

    if (_filter != _PaletteFilter.create) {
      for (final dest in DesktopWebDestination.values) {
        final zhLabel = dest.localizedLabel(AppLocale.zh);
        final enLabel = dest.localizedLabel(AppLocale.en);
        final section = dest.sectionLabel(locale);
        final extraMatch =
            dest == DesktopWebDestination.almanac &&
            lowerQuery.length >= 2 &&
            _almanacKeywords.any(
              (kw) => kw.contains(lowerQuery) || lowerQuery.contains(kw),
            );
        if (lowerQuery.isEmpty ||
            zhLabel.toLowerCase().contains(lowerQuery) ||
            enLabel.toLowerCase().contains(lowerQuery) ||
            dest.name.toLowerCase().contains(lowerQuery) ||
            extraMatch) {
          actions.add(
            _PaletteAction(
              id: 'nav-${dest.name}',
              category: _PaletteCategory.navigate,
              title: dest.localizedLabel(locale),
              subtitle: isEn ? 'Go to $section' : '跳转至 $section',
              icon: dest.icon,
              badge: isEn ? 'Open' : '前往',
              onExecute: () => _closeAndRun(() {
                widget.controller.navigateTo(dest);
              }),
            ),
          );
        }
      }

      final almanacToolCommands =
          <(String, String, String, IconData, int, List<String>)>[
            (
              'cmd-almanac-auspicious',
              isEn ? 'Almanac · Auspicious Day Finder' : '万年历 · 择吉日查询',
              isEn
                  ? 'Find lucky dates for wedding, moving, opening & travel'
                  : '按结婚、搬家、开业、出行等事项筛选黄道吉日',
              Icons.auto_awesome_outlined,
              1,
              const ['择吉', '吉日', '黄道', '结婚', '搬家', '开业', 'auspicious', 'lucky'],
            ),
            (
              'cmd-almanac-holidays',
              isEn ? 'Almanac · Holiday Schedule & Countdown' : '万年历 · 法定放假安排',
              isEn
                  ? '2024–2027 holiday dates, makeup workdays & leave tips'
                  : '查看 2024–2027 放假安排、调休补班与拼假建议',
              Icons.beach_access_outlined,
              2,
              const ['放假', '节假日', '调休', '补班', '拼假', '倒计时', 'holiday', 'leave'],
            ),
            (
              'cmd-almanac-tools',
              isEn
                  ? 'Almanac · Date Calc, Converter & 24 Solar Terms'
                  : '万年历 · 日期计算 / 公农历互转 / 节气八字',
              isEn
                  ? 'Workday interval, solar/lunar leap converter & BaZi'
                  : '工作日计算、公农历闰月互转、24节气时刻与八字简排',
              Icons.swap_horiz_rounded,
              3,
              const [
                '日期',
                '间隔',
                '工作日',
                '互转',
                '闰月',
                '节气',
                '八字',
                'converter',
                'bazi',
                'term',
              ],
            ),
          ];
      for (final (id, title, subtitle, icon, tabIndex, keywords)
          in almanacToolCommands) {
        if (lowerQuery.isEmpty ||
            title.toLowerCase().contains(lowerQuery) ||
            subtitle.toLowerCase().contains(lowerQuery) ||
            (lowerQuery.length >= 2 &&
                keywords.any(
                  (k) => k.contains(lowerQuery) || lowerQuery.contains(k),
                ))) {
          actions.add(
            _PaletteAction(
              id: id,
              category: _PaletteCategory.almanacTool,
              title: title,
              subtitle: subtitle,
              icon: icon,
              badge: AlmanacUiCopy.openAlmanacLabel,
              onExecute: () => _closeAndRun(() {
                widget.controller.navigateTo(
                  DesktopWebDestination.almanac,
                  almanacTab: tabIndex,
                );
              }),
            ),
          );
        }
      }

      final toggleDarkTitle =
          isEn ? 'Toggle Dark / Light Mode' : '切换深色 / 浅色外观';
      if (lowerQuery.isEmpty ||
          toggleDarkTitle.toLowerCase().contains(lowerQuery) ||
          'dark'.contains(lowerQuery) ||
          'light'.contains(lowerQuery) ||
          '深浅'.contains(lowerQuery)) {
        actions.add(
          _PaletteAction(
            id: 'cmd-toggle-dark',
            category: _PaletteCategory.appearance,
            title: toggleDarkTitle,
            subtitle: isEn
                ? 'Switch desktop workspace brightness'
                : '即时切换桌面工作台深浅模式',
            icon: Icons.brightness_6_outlined,
            badge: isEn ? 'Theme' : '外观',
            onExecute: () => _closeAndRun(() {
              widget.controller.toggleDarkMode(
                Theme.of(widget.hostContext).brightness,
              );
            }),
          ),
        );
      }

      final toggleGlassTitle = isEn
          ? 'Toggle Frosted Glass Mode'
          : '切换毛玻璃 / iOS 默认外观';
      if (lowerQuery.isEmpty ||
          toggleGlassTitle.toLowerCase().contains(lowerQuery) ||
          'glass'.contains(lowerQuery) ||
          '毛玻璃'.contains(lowerQuery)) {
        actions.add(
          _PaletteAction(
            id: 'cmd-toggle-glass',
            category: _PaletteCategory.appearance,
            title: toggleGlassTitle,
            subtitle: isEn
                ? 'Switch between frosted glass and iOS clean surface'
                : '切换液态毛玻璃与默认纯色面板',
            icon: Icons.blur_on_rounded,
            badge: isEn ? 'Surface' : '质感',
            onExecute: () => _closeAndRun(() {
              final tp = widget.hostContext.read<ThemeProvider?>();
              final currentFrosted =
                  widget.controller.frostedOverride ??
                  (tp?.brand.style == BrandStyle.liquidGlass);
              final next = !currentFrosted;
              widget.controller.setFrostedOverride(next);
              if (tp != null) {
                if (next && tp.isBrandUnlocked(AppBrands.liquidGlass.id)) {
                  unawaited(tp.setBrand(AppBrands.liquidGlass.id));
                } else if (!next && tp.brand.id == AppBrands.liquidGlass.id) {
                  unawaited(tp.setBrand(AppBrands.defaultBrand.id));
                }
              }
            }),
          ),
        );
      }
    }

    return actions;
  }

  List<SearchHit> _runSearchMemoized(String query) {
    if (_cachedSearchQuery == query) {
      return _cachedSearchHits;
    }
    final hits = _runSearch(query);
    _cachedSearchQuery = query;
    _cachedSearchHits = hits;
    return hits;
  }

  List<SearchHit> _runSearch(String query) {
    debugDesktopCommandPaletteSearchCount++;
    final todos = widget.hostContext.read<TodoProvider?>()?.todos ?? const [];
    final habits = widget.hostContext.read<HabitProvider?>()?.habits ?? const [];
    final notes = widget.hostContext.read<NoteProvider?>()?.notes ?? const [];
    final diaries =
        widget.hostContext.read<DiaryProvider?>()?.entries ?? const [];
    final anniversaries =
        widget.hostContext.read<AnniversaryProvider?>()?.items ?? const [];
    final countdowns =
        widget.hostContext.read<CountdownProvider?>()?.items ?? const [];
    final goals = widget.hostContext.read<GoalProvider?>()?.goals ?? const [];
    final courses =
        widget.hostContext.read<CourseProvider?>()?.courses ?? const [];
    final calendarEvents =
        widget.hostContext.read<CalendarProvider?>()?.events ?? const [];
    final timeEntries =
        widget.hostContext.read<TimeAuditProvider?>()?.entries ?? const [];
    final pomodoroSessions =
        widget.hostContext.read<PomodoroProvider?>()?.sessions ?? const [];

    return GlobalSearch.run(
      query: query,
      todos: todos,
      habits: habits,
      notes: notes,
      diaries: diaries,
      anniversaries: anniversaries,
      countdowns: countdowns,
      goals: goals,
      courses: courses,
      calendarEvents: calendarEvents,
      timeEntries: timeEntries,
      pomodoroSessions: pomodoroSessions,
      maxPerKind: 4,
    );
  }

  DesktopWebDestination _destinationForSearchKind(SearchKind kind) =>
      switch (kind) {
        SearchKind.todo => DesktopWebDestination.todo,
        SearchKind.habit => DesktopWebDestination.habit,
        SearchKind.note => DesktopWebDestination.notes,
        SearchKind.diary => DesktopWebDestination.diary,
        SearchKind.anniversary => DesktopWebDestination.anniversary,
        SearchKind.countdown => DesktopWebDestination.countdown,
        SearchKind.goal => DesktopWebDestination.goals,
        SearchKind.course => DesktopWebDestination.schedule,
        SearchKind.calendarEvent => DesktopWebDestination.calendar,
        SearchKind.timeEntry => DesktopWebDestination.timeAudit,
        SearchKind.pomodoro => DesktopWebDestination.focus,
      };

  String _categoryLabel(_PaletteCategory category, bool isEn) =>
      switch (category) {
        _PaletteCategory.instantCreate => isEn ? 'Instant Create' : '即时创建',
        _PaletteCategory.searchResult => isEn ? 'Search Results' : '搜索结果',
        _PaletteCategory.quickCreate => isEn ? 'Quick Create' : '快速新建',
        _PaletteCategory.navigate => isEn ? 'Navigate' : '页面导航',
        _PaletteCategory.almanacTool => isEn ? 'Almanac Tools' : '万年历工具',
        _PaletteCategory.appearance => isEn ? 'Appearance' : '外观质感',
      };

  Color _categoryTint(_PaletteCategory category, DesktopWebTokens tokens) =>
      switch (category) {
        _PaletteCategory.instantCreate ||
        _PaletteCategory.quickCreate => tokens.success,
        _PaletteCategory.searchResult => tokens.info,
        _PaletteCategory.navigate => tokens.accent,
        _PaletteCategory.almanacTool ||
        _PaletteCategory.appearance => tokens.warning,
      };

  void _moveSelection(int delta, List<_PaletteAction> actions) {
    if (actions.isEmpty) return;
    final current = _selectedIndex.clamp(0, actions.length - 1);
    final next = (current + delta + actions.length) % actions.length;
    setState(() => _selectedIndex = next);
    _scheduleScrollToSelection(actions, next);
  }

  void _scheduleScrollToSelection(List<_PaletteAction> actions, int index) {
    if (index < 0 || index >= actions.length) return;
    final targetId = actions[index].id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_listScrollCtrl.hasClients) return;
      final pos = _listScrollCtrl.position;
      if (index == 0) {
        if (pos.pixels > pos.minScrollExtent) {
          _listScrollCtrl.jumpTo(pos.minScrollExtent);
        }
        return;
      }
      final ctx = _itemKeys[targetId]?.currentContext;
      if (ctx != null) {
        final ro = ctx.findRenderObject();
        if (ro != null && ro.attached) {
          final viewport = RenderAbstractViewport.maybeOf(ro);
          if (viewport != null) {
            final topOffset = viewport.getOffsetToReveal(ro, 0.0).offset;
            final bottomOffset = viewport.getOffsetToReveal(ro, 1.0).offset;
            if (pos.pixels > topOffset) {
              _listScrollCtrl.jumpTo(
                topOffset.clamp(pos.minScrollExtent, pos.maxScrollExtent),
              );
            } else if (pos.pixels < bottomOffset) {
              _listScrollCtrl.jumpTo(
                bottomOffset.clamp(pos.minScrollExtent, pos.maxScrollExtent),
              );
            }
            return;
          }
        }
      }
      if (actions.length > 1 && pos.maxScrollExtent > 0) {
        final approx = (index / (actions.length - 1)) * pos.maxScrollExtent;
        _listScrollCtrl.jumpTo(
          approx.clamp(pos.minScrollExtent, pos.maxScrollExtent),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWebTokens.of(context);
    final locale = I18n.current;
    final isEn = locale == AppLocale.en;
    final actions = _actionsFor(locale);
    final rows = _rowsFor(locale);
    final clampedIndex = actions.isEmpty
        ? 0
        : _selectedIndex.clamp(0, actions.length - 1);

    _inputFocusNode.onKeyEvent = (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
          actions.isNotEmpty) {
        _moveSelection(1, actions);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
          actions.isNotEmpty) {
        _moveSelection(-1, actions);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    final modalBody = Container(
      key: const ValueKey('desktop_command_palette_modal'),
      decoration: BoxDecoration(
        color: tokens.elevatedSurface,
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXl),
        border: Border.all(
          color: tokens.hairlineBorder,
          width: DesktopWebTokens.hairlineWidth,
        ),
        boxShadow: tokens.modalShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 19, color: tokens.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const ValueKey('desktop_command_palette_input'),
                    controller: _queryCtrl,
                    focusNode: _inputFocusNode,
                    autofocus: true,
                    style: tokens.bodyStyle.copyWith(fontSize: 14.5),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: isEn
                          ? 'Search tasks, habits, notes, or jump anywhere...'
                          : '搜索待办 / 习惯 / 笔记，快速跳转或直接输入创建待办...',
                      hintStyle: tokens.bodyMutedStyle.copyWith(
                        color: tokens.textMuted,
                      ),
                    ),
                    onChanged: _onQueryChanged,
                    onSubmitted: (_) {
                      _flushPendingQuery();
                      final latestActions = _actionsFor(locale);
                      if (latestActions.isNotEmpty) {
                        final idx = _selectedIndex.clamp(
                          0,
                          latestActions.length - 1,
                        );
                        latestActions[idx].onExecute();
                      }
                    },
                  ),
                ),
                const DesktopKeycap(label: 'ESC'),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: DesktopWebTokens.hairlineWidth,
            color: tokens.hairlineBorder,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
            child: Row(
              children: [
                _FilterPill(
                  label: isEn ? 'All' : '全部',
                  selected: _filter == _PaletteFilter.all,
                  onTap: () => setState(() {
                    _flushPendingQuery();
                    _filter = _PaletteFilter.all;
                    _selectedIndex = 0;
                  }),
                ),
                const SizedBox(width: 6),
                _FilterPill(
                  label: isEn ? 'Navigate' : '快速跳转',
                  selected: _filter == _PaletteFilter.jump,
                  onTap: () => setState(() {
                    _flushPendingQuery();
                    _filter = _PaletteFilter.jump;
                    _selectedIndex = 0;
                  }),
                ),
                const SizedBox(width: 6),
                _FilterPill(
                  label: isEn ? 'Create' : '快速创建',
                  selected: _filter == _PaletteFilter.create,
                  onTap: () => setState(() {
                    _flushPendingQuery();
                    _filter = _PaletteFilter.create;
                    _selectedIndex = 0;
                  }),
                ),
              ],
            ),
          ),
          Flexible(
            child: actions.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Text(
                      isEn ? 'No matching commands or items' : '没有匹配的命令或记录',
                      style: tokens.bodyMutedStyle,
                    ),
                  )
                : ListView.builder(
                    controller: _listScrollCtrl,
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                    itemCount: rows.length,
                    itemBuilder: (context, rowIndex) {
                      final row = rows[rowIndex];
                      if (row.headerCategory != null) {
                        final headerText = _categoryLabel(
                          row.headerCategory!,
                          isEn,
                        );
                        return Padding(
                          padding: EdgeInsets.fromLTRB(
                            10,
                            row.isFirstHeader ? 4 : 10,
                            10,
                            4,
                          ),
                          child: Text(
                            headerText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tokens.sectionHeaderStyle.copyWith(
                              color: tokens.textMuted,
                              letterSpacing: 0.4,
                            ),
                          ),
                        );
                      }

                      final item = row.action!;
                      final itemIndex = row.actionIndex!;
                      final selected = itemIndex == clampedIndex;
                      final tint = _categoryTint(item.category, tokens);
                      final itemKey = _itemKeys.putIfAbsent(
                        item.id,
                        GlobalKey.new,
                      );

                      return Padding(
                        key: itemKey,
                        padding: const EdgeInsets.only(bottom: 1),
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            DesktopHoverTile(
                              key: ValueKey('command_item_${item.id}'),
                              selected: selected,
                              onTap: item.onExecute,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: tint.withValues(
                                        alpha: tokens.isDark ? 0.18 : 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        DesktopWebTokens.radiusSm,
                                      ),
                                      border: Border.all(
                                        color: tint.withValues(
                                          alpha: tokens.isDark ? 0.30 : 0.22,
                                        ),
                                        width: DesktopWebTokens.hairlineWidth,
                                      ),
                                    ),
                                    child: Icon(
                                      item.icon,
                                      size: 16,
                                      color: tint,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          item.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: tokens.bodyStyle.copyWith(
                                            fontSize: 13.5,
                                          ),
                                        ),
                                        Text(
                                          item.subtitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: tokens.captionStyle.copyWith(
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (item.badge != null) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: tint.withValues(
                                          alpha: selected
                                              ? (tokens.isDark ? 0.24 : 0.16)
                                              : (tokens.isDark ? 0.14 : 0.09),
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          DesktopWebTokens.radiusXs,
                                        ),
                                        border: Border.all(
                                          color: tint.withValues(
                                            alpha: selected ? 0.38 : 0.20,
                                          ),
                                          width: DesktopWebTokens.hairlineWidth,
                                        ),
                                      ),
                                      child: Text(
                                        item.badge!,
                                        style: tokens.captionStyle.copyWith(
                                          color: tint,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (selected)
                              Positioned(
                                left: 0,
                                top: 8,
                                bottom: 8,
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
                    },
                  ),
          ),
          Divider(
            height: 1,
            thickness: DesktopWebTokens.hairlineWidth,
            color: tokens.hairlineBorder,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                const DesktopKeycap(label: '↑↓'),
                const SizedBox(width: 5),
                Text(
                  isEn ? 'Select' : '选择',
                  style: tokens.captionStyle,
                ),
                const SizedBox(width: 12),
                const DesktopKeycap(label: '↵'),
                const SizedBox(width: 5),
                Text(
                  isEn ? 'Execute' : '执行',
                  style: tokens.captionStyle,
                ),
                const Spacer(),
                const DesktopKeycap(label: 'ESC'),
                const SizedBox(width: 5),
                Text(
                  isEn ? 'Close' : '关闭',
                  style: tokens.captionStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _moveSelection(1, actions),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _moveSelection(-1, actions),
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        alignment: const Alignment(0, -0.35),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 540),
          child: RepaintBoundary(
            child: Builder(
              builder: (_) {
                final blurSigma = kIsWeb
                    ? math.min(
                        tokens.glassBlurSigma,
                        DesktopWebTokens.webChromeBlurSigma,
                      )
                    : tokens.glassBlurSigma;
                if (blurSigma > 0) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(
                      DesktopWebTokens.radiusXl,
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: blurSigma,
                        sigmaY: blurSigma,
                      ),
                      child: modalBody,
                    ),
                  );
                }
                return modalBody;
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWebTokens.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? tokens.accentSoft : tokens.mutedSurface,
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
            border: Border.all(
              color: selected ? tokens.accentBorder : tokens.hairlineBorder,
              width: DesktopWebTokens.hairlineWidth,
            ),
          ),
          child: Text(
            label,
            style: tokens.captionStyle.copyWith(
              color: selected ? tokens.accent : tokens.textSecondary,
              fontSize: 11.5,
            ),
          ),
        ),
      ),
    );
  }
}
