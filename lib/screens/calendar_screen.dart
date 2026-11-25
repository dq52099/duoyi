import 'dart:collection';

import '../widgets/app_date_format.dart';
import 'package:flutter/material.dart';
import '../core/almanac_locale_format.dart';
import '../core/almanac_ui_copy.dart';
import '../core/brand_strings.dart';
import '../core/completion_visibility_policy.dart';
import '../core/calendar_date_navigation.dart';
import '../core/calendar_ui_copy.dart';
import '../core/design_tokens.dart';
import '../core/desktop_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/lunar_calendar.dart';
import '../core/main_ui_copy.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/holiday_calendar.dart';
import 'package:provider/provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/todo_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/anniversary_provider.dart';
import '../providers/course_provider.dart';
import '../providers/countdown_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/share_provider.dart';
import '../providers/time_audit_provider.dart';
import '../models/calendar_event.dart';
import '../models/anniversary.dart';
import '../models/countdown.dart';
import '../models/course_schedule.dart';
import '../models/diary_entry.dart';
import '../models/goal.dart';
import '../models/habit.dart';
import '../models/pomodoro.dart';
import '../models/time_entry.dart';
import '../models/todo.dart';
import '../models/workspace.dart';
import '../widgets/calendar_month_grid.dart';
import '../widgets/calendar_week_strip.dart';
import '../widgets/calendar_day_agenda.dart';
import '../widgets/calendar_event_sheet.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/app_time_picker.dart';
import '../widgets/brand_background.dart';
import '../widgets/surface_components.dart';
import 'ai_schedule_screen.dart';
import 'almanac_screen.dart';
import 'goal_edit_screen.dart';
import 'todo_screen.dart';

class CalendarScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  final GlobalKey? todoTabKey;
  final DateTime? initialDate;
  final bool useShellBackground;

  const CalendarScreen({
    super.key,
    this.todoTabKey,
    this.initialDate,
    this.useShellBackground = false,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedMonth = DateTime.now();
  Set<CalendarEventType>? _activeTypes;
  String? _activeProjectKey;
  String? _activeWorkspaceId;
  bool _calendarRebuildScheduled = false;
  Object? _lastCalendarInputSignature;
  late final _CallerLifecycleNotifier _callerLifecycleNotifier;

  @override
  void initState() {
    super.initState();
    _callerLifecycleNotifier = _CallerLifecycleNotifier();
    final initialDate = widget.initialDate;
    if (initialDate != null) {
      _selectedDay = DateTime(
        initialDate.year,
        initialDate.month,
        initialDate.day,
      );
      _focusedMonth = DateTime(initialDate.year, initialDate.month);
    }
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_handleTabControllerChanged);
    I18n.localeListenable.addListener(_onLocaleChanged);
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  void _handleTabControllerChanged() {
    if (!mounted || _tabController.indexIsChanging) return;
    setState(() {});
  }

  @override
  void dispose() {
    _callerLifecycleNotifier.notifyCallerDisposed();
    I18n.localeListenable.removeListener(_onLocaleChanged);
    _tabController.removeListener(_handleTabControllerChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _scheduleCalendarRebuild({
    required TodoProvider todoProvider,
    required HabitProvider habitProvider,
    required PomodoroProvider pomodoroProvider,
    required CalendarProvider calendarProvider,
    required AnniversaryProvider anniversaryProvider,
    required CountdownProvider countdownProvider,
    required CourseProvider courseProvider,
    required DiaryProvider diaryProvider,
    required GoalProvider goalProvider,
    required TimeAuditProvider timeAuditProvider,
    required ColorScheme colorScheme,
  }) {
    if (_calendarRebuildScheduled) return;
    final signature = _calendarInputSignature(
      todoProvider: todoProvider,
      habitProvider: habitProvider,
      pomodoroProvider: pomodoroProvider,
      calendarProvider: calendarProvider,
      anniversaryProvider: anniversaryProvider,
      countdownProvider: countdownProvider,
      courseProvider: courseProvider,
      diaryProvider: diaryProvider,
      goalProvider: goalProvider,
      timeAuditProvider: timeAuditProvider,
      colorScheme: colorScheme,
    );
    if (_lastCalendarInputSignature == signature) return;
    _calendarRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calendarRebuildScheduled = false;
      if (!mounted) return;
      final cs = Theme.of(context).colorScheme;
      final todoProvider = context.read<TodoProvider>();
      final habitProvider = context.read<HabitProvider>();
      final pomodoroProvider = context.read<PomodoroProvider>();
      final calendarProvider = context.read<CalendarProvider>();
      final anniversaryProvider = context.read<AnniversaryProvider>();
      final countdownProvider = context.read<CountdownProvider>();
      final courseProvider = context.read<CourseProvider>();
      final diaryProvider = context.read<DiaryProvider>();
      final goalProvider = context.read<GoalProvider>();
      final timeAuditProvider = context.read<TimeAuditProvider>();
      _lastCalendarInputSignature = _calendarInputSignature(
        todoProvider: todoProvider,
        habitProvider: habitProvider,
        pomodoroProvider: pomodoroProvider,
        calendarProvider: calendarProvider,
        anniversaryProvider: anniversaryProvider,
        countdownProvider: countdownProvider,
        courseProvider: courseProvider,
        diaryProvider: diaryProvider,
        goalProvider: goalProvider,
        timeAuditProvider: timeAuditProvider,
        colorScheme: cs,
      );
      calendarProvider.rebuild(
        todoProvider.todos,
        habitProvider.habits,
        pomodoroProvider.sessions,
        cs,
        anniversaries: anniversaryProvider.items,
        courses: courseProvider.courses,
        courseSettings: courseProvider.settings,
        diaries: diaryProvider.entries,
        countdowns: countdownProvider.items,
        goals: goalProvider.goals,
        timeEntries: timeAuditProvider.entries,
      );
    });
  }

  Object _calendarInputSignature({
    required TodoProvider todoProvider,
    required HabitProvider habitProvider,
    required PomodoroProvider pomodoroProvider,
    required CalendarProvider calendarProvider,
    required AnniversaryProvider anniversaryProvider,
    required CountdownProvider countdownProvider,
    required CourseProvider courseProvider,
    required DiaryProvider diaryProvider,
    required GoalProvider goalProvider,
    required TimeAuditProvider timeAuditProvider,
    required ColorScheme colorScheme,
  }) {
    final now = DateTime.now();
    final todayKey = DateTime(
      now.year,
      now.month,
      now.day,
    ).millisecondsSinceEpoch;
    return Object.hashAll([
      todayKey,
      colorScheme.primary,
      calendarProvider.sourceRevision,
      _todoSignature(todoProvider.todos),
      _habitSignature(habitProvider.habits),
      _pomodoroSignature(pomodoroProvider.sessions),
      _anniversarySignature(anniversaryProvider.items),
      _countdownSignature(countdownProvider.items),
      _courseSignature(courseProvider.courses, courseProvider.settings),
      _diarySignature(diaryProvider.entries),
      _goalSignature(goalProvider.goals),
      _timeEntrySignature(timeAuditProvider.entries),
    ]);
  }

  Object _todoSignature(List<TodoItem> todos) => Object.hashAll([
    todos.length,
    for (final item in todos)
      Object.hash(
        item.id,
        item.title,
        item.date.millisecondsSinceEpoch,
        item.dueDate?.millisecondsSinceEpoch,
        item.isCompleted,
        item.listGroupId,
        item.listGroupName,
        item.workspaceId,
        item.updatedAt.millisecondsSinceEpoch,
      ),
  ]);

  Object _habitSignature(List<Habit> habits) => Object.hashAll([
    habits.length,
    for (final item in habits)
      Object.hash(
        item.id,
        item.name,
        item.colorValue,
        item.kind.index,
        item.targetCount,
        item.unit,
        item.generatedUnitKey,
        item.updatedAt.millisecondsSinceEpoch,
      ),
  ]);

  Object _pomodoroSignature(List<PomodoroSession> sessions) => Object.hashAll([
    sessions.length,
    for (final item in sessions)
      Object.hash(
        item.id,
        item.startTime.millisecondsSinceEpoch,
        item.endTime.millisecondsSinceEpoch,
        item.durationSeconds,
        item.type.index,
        item.taskName,
        item.whiteNoiseSound,
        item.updatedAt.millisecondsSinceEpoch,
      ),
  ]);

  Object _anniversarySignature(List<Anniversary> items) => Object.hashAll([
    items.length,
    for (final item in items)
      Object.hash(
        item.id,
        item.title,
        item.originDate.millisecondsSinceEpoch,
        item.type.index,
        item.calendarType.index,
        item.colorValue,
        item.ignoreYear,
        item.updatedAt.millisecondsSinceEpoch,
      ),
  ]);

  Object _countdownSignature(List<CountdownItem> items) => Object.hashAll([
    items.length,
    for (final item in items)
      Object.hash(
        item.id,
        item.title,
        item.targetDate.millisecondsSinceEpoch,
        item.isPinned,
        item.category,
        item.updatedAt.millisecondsSinceEpoch,
      ),
  ]);

  Object _courseSignature(
    List<CourseItem> courses,
    ScheduleSettings settings,
  ) => Object.hashAll([
    settings.termStart.millisecondsSinceEpoch,
    settings.totalWeeks,
    settings.sessionsPerDay,
    settings.sessionMinutes,
    settings.firstSessionHour,
    settings.firstSessionMinute,
    settings.breakMinutes,
    courses.length,
    for (final item in courses)
      Object.hash(
        item.id,
        item.name,
        item.weekday,
        item.startSection,
        item.sectionCount,
        Object.hashAll(item.weeks),
        item.updatedAt.millisecondsSinceEpoch,
      ),
  ]);

  Object _diarySignature(List<DiaryEntry> entries) => Object.hashAll([
    entries.length,
    for (final item in entries)
      Object.hash(item.id, item.dateKey, item.updatedAt.millisecondsSinceEpoch),
  ]);

  Object _goalSignature(List<GoalItem> goals) => Object.hashAll([
    goals.length,
    for (final item in goals)
      Object.hash(
        item.id,
        item.title,
        item.targetDate?.millisecondsSinceEpoch,
        item.status.index,
        item.colorValue,
        item.autoProgress,
        item.computedProgress,
        item.workspaceId,
        item.updatedAt.millisecondsSinceEpoch,
      ),
  ]);

  Object _timeEntrySignature(List<TimeEntry> entries) => Object.hashAll([
    entries.length,
    for (final item in entries)
      Object.hash(
        item.id,
        item.title,
        item.startAt.millisecondsSinceEpoch,
        item.endAt.millisecondsSinceEpoch,
        item.category.index,
        item.source.index,
        item.sourceId,
        item.updatedAt.millisecondsSinceEpoch,
      ),
  ]);

  void _showQuickAddTodo({_CalendarOriginScope? origin}) {
    final effectiveOrigin = origin ?? _createOriginScope();
    if (!effectiveOrigin.isValid) return;
    showDialog<void>(
      context: context,
      builder: (_) => _QuickAddTodoDialog(origin: effectiveOrigin),
    );
  }

  void _previousMonth() {
    final nextMonth = CalendarDateNavigation.tryShiftMonths(_focusedMonth, -1);
    final nextDay = CalendarDateNavigation.tryShiftMonths(_selectedDay, -1);
    if (nextMonth == null || nextDay == null) return;
    setState(() {
      _focusedMonth = DateTime(nextMonth.year, nextMonth.month);
      _selectedDay = nextDay;
    });
  }

  void _nextMonth() {
    final nextMonth = CalendarDateNavigation.tryShiftMonths(_focusedMonth, 1);
    final nextDay = CalendarDateNavigation.tryShiftMonths(_selectedDay, 1);
    if (nextMonth == null || nextDay == null) return;
    setState(() {
      _focusedMonth = DateTime(nextMonth.year, nextMonth.month);
      _selectedDay = nextDay;
    });
  }

  void _previousWeek() {
    final shifted = CalendarDateNavigation.tryShiftDays(_selectedDay, -7);
    if (shifted == null) return;
    setState(() {
      _selectedDay = shifted;
      _focusedMonth = DateTime(shifted.year, shifted.month);
    });
  }

  void _nextWeek() {
    final shifted = CalendarDateNavigation.tryShiftDays(_selectedDay, 7);
    if (shifted == null) return;
    setState(() {
      _selectedDay = shifted;
      _focusedMonth = DateTime(shifted.year, shifted.month);
    });
  }

  void _previousDay() {
    final shifted = CalendarDateNavigation.tryShiftDays(_selectedDay, -1);
    if (shifted == null) return;
    setState(() {
      _selectedDay = shifted;
      _focusedMonth = DateTime(shifted.year, shifted.month);
    });
  }

  void _nextDay() {
    final shifted = CalendarDateNavigation.tryShiftDays(_selectedDay, 1);
    if (shifted == null) return;
    setState(() {
      _selectedDay = shifted;
      _focusedMonth = DateTime(shifted.year, shifted.month);
    });
  }

  void _previousThreeDays() {
    final shifted = CalendarDateNavigation.tryShiftDays(_selectedDay, -3);
    if (shifted == null) return;
    setState(() {
      _selectedDay = shifted;
      _focusedMonth = DateTime(shifted.year, shifted.month);
    });
  }

  void _nextThreeDays() {
    final shifted = CalendarDateNavigation.tryShiftDays(_selectedDay, 3);
    if (shifted == null) return;
    setState(() {
      _selectedDay = shifted;
      _focusedMonth = DateTime(shifted.year, shifted.month);
    });
  }

  void _previousYear() {
    final nextMonth = CalendarDateNavigation.tryShiftYears(_focusedMonth, -1);
    final nextDay = CalendarDateNavigation.tryShiftYears(_selectedDay, -1);
    if (nextMonth == null || nextDay == null) return;
    setState(() {
      _focusedMonth = DateTime(nextMonth.year, nextMonth.month);
      _selectedDay = nextDay;
    });
  }

  void _nextYear() {
    final nextMonth = CalendarDateNavigation.tryShiftYears(_focusedMonth, 1);
    final nextDay = CalendarDateNavigation.tryShiftYears(_selectedDay, 1);
    if (nextMonth == null || nextDay == null) return;
    setState(() {
      _focusedMonth = DateTime(nextMonth.year, nextMonth.month);
      _selectedDay = nextDay;
    });
  }

  int _monthGridRows(DateTime focusedMonth, int firstDayOfWeek) {
    final firstDay = DateTime.utc(focusedMonth.year, focusedMonth.month, 1);
    final lastDay = DateTime.utc(focusedMonth.year, focusedMonth.month + 1, 0);
    final startOffset = (firstDay.weekday - firstDayOfWeek) % 7;
    return ((startOffset + lastDay.day) / 7).ceil();
  }

  double _monthGridHeightFor(
    BuildContext context,
    double availableHeight,
    int rows,
  ) {
    final minGridHeight = rows >= 6 ? 288.0 : (rows == 5 ? 260.0 : 236.0);
    final preferredGridHeight = rows >= 6 ? 318.0 : (rows == 5 ? 292.0 : 268.0);
    final textScaler = MediaQuery.textScalerOf(context);
    final scale = textScaler.scale(14) / 14;
    if (scale > 1.05) {
      final weekdayHeight = (textScaler.scale(12) * 1.3).clamp(20.0, 48.0);
      final dayNumHeight = (textScaler.scale(13.0) * 1.25).ceilToDouble();
      final subTextHeight = 1.0 + (textScaler.scale(10.0) * 1.3).ceilToDouble();
      final dotsOrBadgeHeight =
          1.0 + 4.0 + 1.0 + (textScaler.scale(10.0) * 1.3).ceilToDouble();
      final minCellHeight =
          dayNumHeight + subTextHeight + dotsOrBadgeHeight + 6.0;
      final minRowSlotHeight = minCellHeight + 4.0;
      final minHeightForScale =
          12.0 + weekdayHeight + 4.0 + (rows * minRowSlotHeight);
      final resolvedMin = minGridHeight > minHeightForScale
          ? minGridHeight
          : minHeightForScale;
      final resolvedPreferred = preferredGridHeight > resolvedMin
          ? preferredGridHeight
          : resolvedMin;
      if (!availableHeight.isFinite) return resolvedPreferred;
      final viewportTarget = availableHeight * 0.46;
      return viewportTarget.clamp(resolvedMin, resolvedPreferred).toDouble();
    }
    if (!availableHeight.isFinite) return preferredGridHeight;
    final viewportTarget = availableHeight * 0.46;
    return viewportTarget.clamp(minGridHeight, preferredGridHeight).toDouble();
  }

  Widget _calendarFilterChip({
    Widget? avatar,
    required Widget label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        avatar: avatar,
        label: label,
        selected: selected,
        onSelected: onSelected,
        showCheckmark: false,
        labelStyle: appSecondaryControlLabelStyle(context),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        side: BorderSide(
          color: selected
              ? cs.primary.withValues(alpha: 0.24)
              : cs.outlineVariant.withValues(alpha: 0.16),
          width: 0.45,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      ),
    );
  }

  Widget _calendarActionChip({
    required Widget avatar,
    required Widget label,
    required VoidCallback onPressed,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        avatar: avatar,
        label: label,
        labelStyle: appSecondaryControlLabelStyle(context),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: 0.16),
          width: 0.45,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        onPressed: onPressed,
      ),
    );
  }

  bool _monthGridShowsLunar(double gridHeight, int rows) {
    if (rows <= 0) return false;
    const monthGridChromeHeight = 36.0;
    final rowHeight = (gridHeight - monthGridChromeHeight) / rows;
    return rowHeight >= 50;
  }

  Widget _calendarFilterStrip({
    required List<_CalendarWorkspaceOption> workspaceOptions,
    required String? effectiveWorkspaceId,
    required List<_CalendarProjectOption> projectOptions,
    required String? effectiveProjectKey,
    required List<TodoItem> workspaceTodos,
  }) {
    return SizedBox(
      key: const ValueKey('calendar_unified_filter_strip'),
      height: 48,
      child: DefaultTextStyle.merge(
        style: appSecondaryControlLabelStyle(context),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            _calendarFilterChip(
              label: Text(CalendarUiCopy.filterAll),
              selected: _activeTypes == null,
              onSelected: (_) => setState(() => _activeTypes = null),
            ),
            if (projectOptions.isNotEmpty) ...[
              const SizedBox(width: 6),
              _calendarFilterChip(
                avatar: const Icon(Icons.folder_outlined, size: 16),
                label: Text(CalendarUiCopy.filterAllProjects),
                selected: effectiveProjectKey == null,
                onSelected: (_) => setState(() => _activeProjectKey = null),
              ),
              for (final option in projectOptions)
                _calendarFilterChip(
                  label: Text('${option.displayName} ${option.count}'),
                  selected: effectiveProjectKey == option.key,
                  onSelected: (_) {
                    setState(() {
                      _activeProjectKey = option.key;
                      if (_activeTypes != null &&
                          !_activeTypes!.contains(CalendarEventType.todo)) {
                        _activeTypes = {CalendarEventType.todo};
                      }
                    });
                  },
                ),
              if (effectiveProjectKey != null)
                _calendarActionChip(
                  avatar: const Icon(Icons.info_outline, size: 16),
                  label: Text(CalendarUiCopy.projectDetailAction),
                  onPressed: () {
                    final option = projectOptions.firstWhere(
                      (item) => item.key == effectiveProjectKey,
                    );
                    _showProjectDetail(
                      context,
                      option,
                      _projectTodos(workspaceTodos, option.key),
                    );
                  },
                ),
            ],
            if (workspaceOptions.isNotEmpty) ...[
              const SizedBox(width: 6),
              _calendarFilterChip(
                avatar: const Icon(Icons.groups_2_outlined, size: 16),
                label: Text(CalendarUiCopy.filterAllWorkspaces),
                selected: effectiveWorkspaceId == null,
                onSelected: (_) => setState(() => _activeWorkspaceId = null),
              ),
              for (final option in workspaceOptions)
                _calendarFilterChip(
                  avatar: Icon(
                    option.isPrivate
                        ? Icons.lock_outline
                        : Icons.groups_2_outlined,
                    size: 16,
                  ),
                  label: Text('${option.displayName} ${option.count}'),
                  selected: effectiveWorkspaceId == option.id,
                  onSelected: (_) {
                    setState(() {
                      _activeWorkspaceId = option.id;
                    });
                  },
                ),
            ],
            for (final type in CalendarEventType.values)
              _calendarFilterChip(
                label: Text(type.label),
                selected: _activeTypes?.contains(type) ?? false,
                onSelected: (selected) {
                  setState(() {
                    if (_activeTypes == null) {
                      _activeTypes = {type};
                    } else if (selected) {
                      _activeTypes = {..._activeTypes!, type};
                    } else {
                      final next = {..._activeTypes!}..remove(type);
                      _activeTypes = next.isEmpty ? null : next;
                    }
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final origin = _createOriginScope();
    final picked = await AppDatePicker.pickSolar(
      context,
      initialDate: _selectedDay,
      firstDate: DateTime(1, 1, 1),
      lastDate: DateTime(9999, 12, 31),
      titleKey: 'calendar.content.date_picker_title',
      subtitleKey: 'calendar.content.date_picker_subtitle',
    );
    if (!origin.isValid) return;
    if (picked == null) return;
    setState(() {
      _selectedDay = picked;
      _focusedMonth = DateTime(picked.year, picked.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    final todoProvider = context.watch<TodoProvider>();
    final habitProvider = context.watch<HabitProvider>();
    context.select<PomodoroProvider, int>(
      (provider) => provider.persistedRevision,
    );
    final pomodoroProvider = context.read<PomodoroProvider>();
    final calendarProvider = context.watch<CalendarProvider>();
    final firstDayOfWeek = context.select<PreferencesProvider?, int>(
      (p) => CalendarDateNavigation.normalizeFirstDayOfWeek(
        p?.firstDayOfWeek ?? 1,
      ),
    );
    final showLunarPref = context.select<PreferencesProvider?, bool>(
      (p) => p?.showLunar ?? true,
    );
    final calendarMenuConfigKey = context.select<PreferencesProvider?, String>(
      (p) {
        final order =
            p?.calendarMenuOrder ?? PreferencesProvider.defaultCalendarMenuOrder;
        final hidden = (p?.calendarMenuHidden.toList() ?? <String>[])..sort();
        return '${order.join(',')}|${hidden.join(',')}';
      },
    );
    final calendarMenuParts = calendarMenuConfigKey.split('|');
    final calendarMenuOrder = calendarMenuParts[0].isEmpty
        ? PreferencesProvider.defaultCalendarMenuOrder
        : calendarMenuParts[0].split(',');
    final calendarMenuHidden = calendarMenuParts.length > 1 &&
            calendarMenuParts[1].isNotEmpty
        ? calendarMenuParts[1].split(',').toSet()
        : const <String>{};
    final anniversaryProvider = context.watch<AnniversaryProvider>();
    final countdownProvider = context.watch<CountdownProvider>();
    final courseProvider = context.watch<CourseProvider>();
    final diaryProvider = context.watch<DiaryProvider>();
    final goalProvider = context.watch<GoalProvider>();
    final shareProvider = context.watch<ShareProvider>();
    final timeAuditProvider = context.watch<TimeAuditProvider>();
    final s = context.select<ThemeProvider, BrandStrings>(
      (t) => t.brand.strings,
    );
    final cs = Theme.of(context).colorScheme;

    _scheduleCalendarRebuild(
      todoProvider: todoProvider,
      habitProvider: habitProvider,
      pomodoroProvider: pomodoroProvider,
      calendarProvider: calendarProvider,
      anniversaryProvider: anniversaryProvider,
      countdownProvider: countdownProvider,
      courseProvider: courseProvider,
      diaryProvider: diaryProvider,
      goalProvider: goalProvider,
      timeAuditProvider: timeAuditProvider,
      colorScheme: cs,
    );

    final workspaceOptions = _workspaceOptions(
      todoProvider.todos,
      goalProvider.goals,
      calendarProvider.localEvents,
      shareProvider.workspaces,
    );
    final effectiveWorkspaceId =
        workspaceOptions.any((option) => option.id == _activeWorkspaceId)
        ? _activeWorkspaceId
        : null;
    final workspaceTodos = _workspaceTodos(
      todoProvider.todos,
      effectiveWorkspaceId,
    );
    final projectOptions = _projectOptions(workspaceTodos);
    final effectiveProjectKey =
        projectOptions.any((option) => option.key == _activeProjectKey)
        ? _activeProjectKey
        : null;
    final hasActiveCalendarFilters =
        _activeTypes != null ||
        effectiveProjectKey != null ||
        effectiveWorkspaceId != null;
    final dateTypes = calendarProvider.filteredDateEventTypes(
      _activeTypes,
      projectKey: effectiveProjectKey,
      workspaceId: effectiveWorkspaceId,
    );
    final dateCounts = calendarProvider.filteredDateEventCounts(
      _activeTypes,
      projectKey: effectiveProjectKey,
      workspaceId: effectiveWorkspaceId,
    );
    final monthLabel = CalendarUiCopy.monthHeader(_focusedMonth);
    final weekSlots = CalendarDateNavigation.weekDays(
      _selectedDay,
      firstDayOfWeek: firstDayOfWeek,
    );
    final nonNullWeekSlots = weekSlots.whereType<DateTime>().toList();
    final weekLabel = nonNullWeekSlots.isEmpty
        ? CalendarUiCopy.unavailable
        : '${I18nDateFormat.monthDay(nonNullWeekSlots.first)} - ${I18nDateFormat.monthDay(nonNullWeekSlots.last)}';
    final threeDaySlots = CalendarDateNavigation.daysFrom(_selectedDay, 3);
    final nonNullThreeDaySlots = threeDaySlots.whereType<DateTime>().toList();
    final threeDayLabel = nonNullThreeDaySlots.isEmpty
        ? CalendarUiCopy.unavailable
        : '${I18nDateFormat.monthDay(nonNullThreeDaySlots.first)} - ${I18nDateFormat.monthDay(nonNullThreeDaySlots.last)}';
    final yearLabel = CalendarUiCopy.yearHeader(_focusedMonth.year);
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.surface
        : Theme.of(context).colorScheme.surfaceContainerLowest;

    return BrandScaffold(
      paintBackground: !widget.useShellBackground,
      appBar: AppBar(
        title: Text(MainUiCopy.calendarTitle),
        titleTextStyle: widget.useShellBackground
            ? null
            : appSecondaryRouteTitleTextStyle(context),
        backgroundColor: widget.useShellBackground
            ? Colors.transparent
            : routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            key: const ValueKey('calendar_open_almanac_button'),
            tooltip: AlmanacUiCopy.openAlmanacLabel,
            icon: const Icon(Icons.auto_stories_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BrandRouteSurface(
                    child: AlmanacScreen(initialDate: _selectedDay),
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: MainUiCopy.calendarBackToToday,
            icon: const Icon(Icons.today_outlined),
            onPressed: () {
              final now = DateTime.now();
              setState(() {
                _selectedDay = now;
                _focusedMonth = DateTime(now.year, now.month);
              });
            },
          ),
          PopupMenuButton<String>(
            tooltip: MainUiCopy.calendarMenu,
            icon: const Icon(Icons.more_horiz),
            onSelected: (value) {
              if (value == 'today') {
                final now = DateTime.now();
                setState(() {
                  _selectedDay = now;
                  _focusedMonth = DateTime(now.year, now.month);
                });
              } else if (value == 'pick') {
                _pickDate();
              } else if (value == 'month') {
                _tabController.animateTo(0);
              } else if (value == 'week') {
                _tabController.animateTo(1);
              } else if (value == 'day') {
                _tabController.animateTo(2);
              } else if (value == 'three_day') {
                _tabController.animateTo(3);
              } else if (value == 'year') {
                _tabController.animateTo(4);
              } else if (value == 'configure') {
                _showCalendarMenuConfigSheet();
              }
            },
            itemBuilder: (context) {
              final visibleItems = calendarMenuOrder
                  .where((item) => !calendarMenuHidden.contains(item))
                  .toList(growable: false);
              final entries = <PopupMenuEntry<String>>[];
              for (var i = 0; i < visibleItems.length; i++) {
                final item = visibleItems[i];
                if (i > 0 &&
                    (item == 'month' ||
                        item == 'week' ||
                        item == 'day' ||
                        item == 'three_day' ||
                        item == 'year') &&
                    (visibleItems[i - 1] == 'today' ||
                        visibleItems[i - 1] == 'pick')) {
                  entries.add(const PopupMenuDivider());
                }
                entries.add(_buildCalendarMenuEntry(item));
              }
              if (entries.isNotEmpty) {
                entries.add(const PopupMenuDivider());
              }
              entries.add(_buildCalendarMenuEntry('configure'));
              return entries;
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _CalendarNavigationHeader(
            tabIndex: _tabController.index,
            monthLabel: monthLabel,
            weekLabel: weekLabel,
            dayLabel: AppDateFormat.date(context, _selectedDay),
            threeDayLabel: threeDayLabel,
            yearLabel: yearLabel,
            onPreviousMonth:
                CalendarDateNavigation.tryShiftMonths(_focusedMonth, -1) !=
                        null &&
                    CalendarDateNavigation.tryShiftMonths(_selectedDay, -1) !=
                        null
                ? _previousMonth
                : null,
            onNextMonth:
                CalendarDateNavigation.tryShiftMonths(_focusedMonth, 1) !=
                        null &&
                    CalendarDateNavigation.tryShiftMonths(_selectedDay, 1) !=
                        null
                ? _nextMonth
                : null,
            onPreviousWeek:
                CalendarDateNavigation.tryShiftDays(_selectedDay, -7) != null
                ? _previousWeek
                : null,
            onNextWeek:
                CalendarDateNavigation.tryShiftDays(_selectedDay, 7) != null
                ? _nextWeek
                : null,
            onPreviousDay:
                CalendarDateNavigation.tryShiftDays(_selectedDay, -1) != null
                ? _previousDay
                : null,
            onNextDay:
                CalendarDateNavigation.tryShiftDays(_selectedDay, 1) != null
                ? _nextDay
                : null,
            onPreviousThreeDays:
                CalendarDateNavigation.tryShiftDays(_selectedDay, -3) != null
                ? _previousThreeDays
                : null,
            onNextThreeDays:
                CalendarDateNavigation.tryShiftDays(_selectedDay, 3) != null
                ? _nextThreeDays
                : null,
            onPreviousYear:
                CalendarDateNavigation.tryShiftYears(_focusedMonth, -1) !=
                        null &&
                    CalendarDateNavigation.tryShiftYears(_selectedDay, -1) !=
                        null
                ? _previousYear
                : null,
            onNextYear:
                CalendarDateNavigation.tryShiftYears(_focusedMonth, 1) !=
                        null &&
                    CalendarDateNavigation.tryShiftYears(_selectedDay, 1) !=
                        null
                ? _nextYear
                : null,
            onPickDate: _pickDate,
          ),
          Material(
            type: appSurfaceStyleOf(context) == AppSurfaceStyle.liquidGlass
                ? MaterialType.transparency
                : MaterialType.canvas,
            color: appSurfaceStyleOf(context) == AppSurfaceStyle.liquidGlass
                ? null
                : cs.surface,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              labelPadding: const EdgeInsets.symmetric(horizontal: 14),
              tabs: [
                Tab(height: 34, text: s.calendarTabMonth),
                Tab(height: 34, text: s.calendarTabWeek),
                Tab(height: 34, text: s.calendarTabDay),
                Tab(height: 34, text: CalendarUiCopy.tabThreeDay),
                Tab(height: 34, text: CalendarUiCopy.tabYear),
              ],
              labelStyle: appSecondaryMenuItemTextStyle(context),
              unselectedLabelStyle: appSecondaryMenuItemTextStyle(context),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: Color.alphaBlend(
                  cs.primary.withValues(alpha: 0.10),
                  cs.surface,
                ),
                borderRadius: BorderRadius.circular(
                  appSurfaceStyleOf(context)?.smallTileRadius ??
                      DesignTokens.radiusControl,
                ),
                border: Border.all(
                  color: cs.primary.withValues(alpha: 0.20),
                  width: 0.45,
                ),
              ),
              labelColor: cs.onSurface,
              unselectedLabelColor: cs.onSurfaceVariant,
            ),
          ),
          _calendarFilterStrip(
            workspaceOptions: workspaceOptions,
            effectiveWorkspaceId: effectiveWorkspaceId,
            projectOptions: projectOptions,
            effectiveProjectKey: effectiveProjectKey,
            workspaceTodos: workspaceTodos,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Month
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWideMonth = constraints.maxWidth >= 900;
                    final monthRows = _monthGridRows(
                      _focusedMonth,
                      firstDayOfWeek,
                    );
                    final baseMonthGridHeight = _monthGridHeightFor(
                      context,
                      constraints.maxHeight,
                      monthRows,
                    );
                    final wideTargetHeight = constraints.maxHeight.isFinite
                        ? (constraints.maxHeight * 0.78)
                              .clamp(320.0, 480.0)
                              .toDouble()
                        : 420.0;
                    final monthGridHeight =
                        isWideMonth && wideTargetHeight > baseMonthGridHeight
                        ? wideTargetHeight
                        : baseMonthGridHeight;
                    final showLunar =
                        showLunarPref &&
                        _monthGridShowsLunar(
                          monthGridHeight,
                          monthRows,
                        );
                    final monthGridCard = AppSurfaceCard(
                      key: const ValueKey('calendar_month_grid_skin_card'),
                      margin: EdgeInsets.zero,
                      padding: EdgeInsets.zero,
                      child: SizedBox(
                        key: const ValueKey('calendar_fixed_month_grid'),
                        height: monthGridHeight,
                        child: CalendarMonthGrid(
                          firstDayOfWeek: firstDayOfWeek,
                          focusedMonth: _focusedMonth,
                          selectedDay: _selectedDay,
                          dateEventTypes: dateTypes,
                          dateEventCounts: dateCounts,
                          showLunar: showLunar,
                          onDaySelected: (d) => setState(() {
                            _selectedDay = d;
                            _focusedMonth = DateTime(d.year, d.month);
                          }),
                        ),
                      ),
                    );
                    final metaStrip = _CalendarMetaStrip(
                      selectedDay: _selectedDay,
                      onOpenAlmanac: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => BrandRouteSurface(
                              child: AlmanacScreen(initialDate: _selectedDay),
                            ),
                          ),
                        );
                      },
                    );
                    final detailAgendaCard = AppSurfaceCard(
                      key: const ValueKey('calendar_month_detail_agenda'),
                      margin: EdgeInsets.zero,
                      padding: EdgeInsets.zero,
                      child: CalendarDayAgenda(
                        date: _selectedDay,
                        calendarProvider: calendarProvider,
                        activeTypes: _activeTypes,
                        projectKey: effectiveProjectKey,
                        workspaceId: effectiveWorkspaceId,
                        hasActiveFilters: hasActiveCalendarFilters,
                        horizontalPadding: 8,
                        scrollable: false,
                        previewLimit: 8,
                      ),
                    );
                    return Scrollbar(
                      key: const ValueKey('calendar_month_global_scrollbar'),
                      child: ListView(
                        key: const ValueKey(
                          'calendar_month_global_scroll_view',
                        ),
                        primary: false,
                        padding: EdgeInsets.fromLTRB(
                          isWideMonth ? 16 : 8,
                          8,
                          isWideMonth ? 16 : 8,
                          16,
                        ),
                        children: isWideMonth
                            ? [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 6,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          monthGridCard,
                                          const SizedBox(height: 8),
                                          metaStrip,
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(flex: 5, child: detailAgendaCard),
                                  ],
                                ),
                              ]
                            : [
                                monthGridCard,
                                const SizedBox(height: 6),
                                metaStrip,
                                Divider(
                                  height: 8,
                                  thickness: 0.5,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant
                                      .withValues(alpha: 0.18),
                                ),
                                detailAgendaCard,
                              ],
                      ),
                    );
                  },
                ),
                // Week
                CalendarWeekStrip(
                  firstDayOfWeek: firstDayOfWeek,
                  selectedDay: _selectedDay,
                  dateEventTypes: dateTypes,
                  calendarProvider: calendarProvider,
                  onDaySelected: (d) => setState(() {
                    _selectedDay = d;
                    _focusedMonth = DateTime(d.year, d.month);
                  }),
                  activeTypes: _activeTypes,
                  projectKey: effectiveProjectKey,
                  workspaceId: effectiveWorkspaceId,
                  hasActiveFilters: hasActiveCalendarFilters,
                ),
                // Day
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: DesktopTokens.reportMaxContentWidth,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                      child: AppSurfaceCard(
                        key: const ValueKey('calendar_day_agenda_skin_card'),
                        padding: EdgeInsets.zero,
                        child: CalendarDayAgenda(
                      date: _selectedDay,
                      calendarProvider: calendarProvider,
                      activeTypes: _activeTypes,
                      projectKey: effectiveProjectKey,
                      workspaceId: effectiveWorkspaceId,
                      hasActiveFilters: hasActiveCalendarFilters,
                      horizontalPadding: 8,
                    ),
                      ),
                    ),
                  ),
                ),
                // Three-day
                _CalendarThreeDayView(
                  key: const ValueKey('calendar_three_day_view'),
                  hasActiveFilters: hasActiveCalendarFilters,
                  startDate: _selectedDay,
                  calendarProvider: calendarProvider,
                  activeTypes: _activeTypes,
                  projectKey: effectiveProjectKey,
                  workspaceId: effectiveWorkspaceId,
                ),
                // Year
                _CalendarYearOverview(
                  key: const ValueKey('calendar_year_overview'),
                  year: _focusedMonth.year,
                  firstDayOfWeek: firstDayOfWeek,
                  selectedDay: _selectedDay,
                  dateEventTypes: dateTypes,
                  onMonthTap: (month) {
                    setState(() {
                      _focusedMonth = DateTime(_focusedMonth.year, month);
                      _selectedDay = DateTime(_focusedMonth.year, month, 1);
                      _tabController.animateTo(0);
                    });
                  },
                  onDayTap: (day) {
                    setState(() {
                      _focusedMonth = DateTime(day.year, day.month);
                      _selectedDay = day;
                      _tabController.animateTo(0);
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'calendar_quick_add_fab',
        tooltip: CalendarUiCopy.quickAddTooltip,
        onPressed: () => _showQuickAddMenu(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  List<_CalendarProjectOption> _projectOptions(List<TodoItem> todos) {
    final options = <_CalendarProjectOption>[];
    for (final todo in todos) {
      final trimmedName = todo.listGroupName?.trim();
      final hasGroupName = trimmedName != null && trimmedName.isNotEmpty;
      final key = todo.listGroupId?.isNotEmpty == true
          ? todo.listGroupId!
          : (hasGroupName ? trimmedName : '');
      final name = hasGroupName ? trimmedName : '';
      final index = options.indexWhere((option) => option.key == key);
      if (index == -1) {
        options.add(_CalendarProjectOption(key: key, name: name, count: 1));
      } else {
        final current = options[index];
        options[index] = _CalendarProjectOption(
          key: current.key,
          name: current.name.isNotEmpty ? current.name : name,
          count: current.count + 1,
        );
      }
    }
    options.sort((a, b) {
      if (a.key.isEmpty) return 1;
      if (b.key.isEmpty) return -1;
      return a.displayName.compareTo(b.displayName);
    });
    return options;
  }

  List<_CalendarWorkspaceOption> _workspaceOptions(
    List<TodoItem> todos,
    List<GoalItem> goals,
    List<CalendarEvent> localEvents,
    List<Workspace> workspaces,
  ) {
    final counts = <String, int>{};
    void addCount(String? rawWorkspaceId) {
      final workspaceId =
          rawWorkspaceId == null || rawWorkspaceId.trim().isEmpty
          ? 'private'
          : rawWorkspaceId.trim();
      counts[workspaceId] = (counts[workspaceId] ?? 0) + 1;
    }

    for (final todo in todos) {
      addCount(todo.workspaceId);
    }
    for (final goal in goals) {
      addCount(goal.workspaceId);
    }
    for (final event in localEvents) {
      addCount(event.workspaceId);
    }
    final options = <_CalendarWorkspaceOption>[];
    final privateCount = counts.remove('private');
    final knownWorkspaceIds = <String>{};
    for (final workspace in workspaces) {
      if (workspace.isPrivate) continue;
      knownWorkspaceIds.add(workspace.id);
    }
    for (final workspace in workspaces) {
      if (workspace.isPrivate) continue;
      options.add(
        _CalendarWorkspaceOption(
          id: workspace.id,
          name: workspace.name,
          count: counts[workspace.id] ?? 0,
          isPrivate: false,
        ),
      );
    }
    for (final entry in counts.entries) {
      if (knownWorkspaceIds.contains(entry.key)) continue;
      Workspace? workspace;
      for (final item in workspaces) {
        if (item.id == entry.key) {
          workspace = item;
          break;
        }
      }
      options.add(
        _CalendarWorkspaceOption(
          id: entry.key,
          name: workspace?.name ?? '',
          count: entry.value,
          isPrivate: false,
          isFallbackShared: workspace == null || workspace.name.isEmpty,
        ),
      );
    }
    if (privateCount != null && privateCount > 0) {
      options.add(
        _CalendarWorkspaceOption(
          id: 'private',
          name: '',
          count: privateCount,
          isPrivate: true,
        ),
      );
    }
    if (!options.any((option) => !option.isPrivate)) {
      return const <_CalendarWorkspaceOption>[];
    }
    options.sort((a, b) {
      if (a.isPrivate && !b.isPrivate) return 1;
      if (!a.isPrivate && b.isPrivate) return -1;
      return a.displayName.compareTo(b.displayName);
    });
    return options;
  }

  List<TodoItem> _projectTodos(List<TodoItem> todos, String projectKey) {
    return todos.where((todo) {
      final trimmedName = todo.listGroupName?.trim();
      final key = todo.listGroupId?.isNotEmpty == true
          ? todo.listGroupId!
          : (trimmedName == null || trimmedName.isEmpty ? '' : trimmedName);
      return key == projectKey;
    }).toList();
  }

  List<TodoItem> _workspaceTodos(List<TodoItem> todos, String? workspaceId) {
    if (workspaceId == null) return todos;
    return todos.where((todo) {
      final todoWorkspaceId = todo.workspaceId.trim().isEmpty
          ? 'private'
          : todo.workspaceId.trim();
      return todoWorkspaceId == workspaceId;
    }).toList();
  }

  _CalendarOriginScope _createOriginScope() {
    return _CalendarOriginScope(
      accountGeneration: AccountLocalDataCleaner.accountDataGeneration,
      selectedDay: _selectedDay,
      activeWorkspaceId: _activeWorkspaceId,
      isCallerActive: () => mounted && !_callerLifecycleNotifier._isDisposed,
      callerAvailabilityListenable: _callerLifecycleNotifier,
    );
  }

  Future<void> _showProjectDetail(
    BuildContext context,
    _CalendarProjectOption option,
    List<TodoItem> todos,
  ) {
    final origin = _createOriginScope();
    return showAppModalSheet<void>(
      context: context,
      builder: (_) =>
          _ProjectDetailSheet(origin: origin, option: option, todos: todos),
    );
  }

  void _showQuickAddMenu(BuildContext context) {
    final routeContext = context;
    final origin = _createOriginScope();
    showAppModalSheet<void>(
      context: context,
      builder: (_) => _QuickAddMenuSheet(
        origin: origin,
        onAiSchedule: () {
          if (!origin.isValid) return;
          Navigator.push(
            routeContext,
            MaterialPageRoute(
              builder: (_) => BrandRouteSurface(
                child: AiScheduleScreen(initialDate: origin.selectedDay),
              ),
            ),
          );
        },
        onNewEvent: () {
          if (!origin.isValid) return;
          showLocalCalendarEventEditor(
            routeContext,
            initialDate: origin.selectedDay,
            workspaceId: origin.activeWorkspaceId,
          );
        },
        onNewTodo: () {
          if (!origin.isValid) return;
          _showQuickAddTodo(origin: origin);
        },
        onQuickAddTimeEntry: () {
          if (!origin.isValid) return;
          _showQuickAddTimeEntry(origin: origin);
        },
        onNewGoal: () {
          if (!origin.isValid) return;
          Navigator.push(
            routeContext,
            MaterialPageRoute(
              builder: (_) => const BrandRouteSurface(child: GoalEditScreen()),
            ),
          );
        },
      ),
    );
  }

  void _showCalendarMenuConfigSheet() {
    final origin = _createOriginScope();
    showAppModalSheet<void>(
      context: context,
      builder: (_) => _CalendarMenuConfigSheet(origin: origin),
    );
  }

  PopupMenuEntry<String> _buildCalendarMenuEntry(String id) {
    return switch (id) {
      'today' => PopupMenuItem(
        value: 'today',
        height: 38,
        child: _LocaleAwareSecondaryMenuText(
          () => MainUiCopy.calendarBackToToday,
        ),
      ),
      'pick' => PopupMenuItem(
        value: 'pick',
        height: 38,
        child: _LocaleAwareSecondaryMenuText(
          () => MainUiCopy.calendarPickDate,
        ),
      ),
      'month' => PopupMenuItem(
        value: 'month',
        height: 38,
        child: _LocaleAwareSecondaryMenuText(
          () => MainUiCopy.calendarViewMonth,
        ),
      ),
      'week' => PopupMenuItem(
        value: 'week',
        height: 38,
        child: _LocaleAwareSecondaryMenuText(
          () => MainUiCopy.calendarViewWeek,
        ),
      ),
      'day' => PopupMenuItem(
        value: 'day',
        height: 38,
        child: _LocaleAwareSecondaryMenuText(
          () => MainUiCopy.calendarViewDay,
        ),
      ),
      'three_day' => PopupMenuItem(
        value: 'three_day',
        height: 38,
        child: _LocaleAwareSecondaryMenuText(
          () => MainUiCopy.calendarViewThreeDay,
        ),
      ),
      'year' => PopupMenuItem(
        value: 'year',
        height: 38,
        child: _LocaleAwareSecondaryMenuText(
          () => MainUiCopy.calendarViewYear,
        ),
      ),
      _ => PopupMenuItem(
        value: 'configure',
        height: 38,
        child: _LocaleAwareSecondaryMenuText(
          () => CalendarUiCopy.isEn ? 'Configure menu' : '配置菜单',
        ),
      ),
    };
  }

  Future<void> _showQuickAddTimeEntry({_CalendarOriginScope? origin}) async {
    final effectiveOrigin = origin ?? _createOriginScope();
    if (!effectiveOrigin.isValid) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _QuickAddTimeEntryDialog(origin: effectiveOrigin),
    );
  }
}

class _CallerLifecycleNotifier implements Listenable {
  final List<VoidCallback> _listeners = [];
  bool _isDisposed = false;

  void notifyCallerDisposed() {
    if (_isDisposed) return;
    _isDisposed = true;
    final copy = List<VoidCallback>.from(_listeners);
    for (final listener in copy) {
      listener();
    }
  }

  @override
  void addListener(VoidCallback listener) {
    if (_isDisposed) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }
}

class _CalendarOriginScope {
  final int accountGeneration;
  final DateTime selectedDay;
  final String? activeWorkspaceId;
  final bool Function() isCallerActive;
  final Listenable? callerAvailabilityListenable;

  const _CalendarOriginScope({
    required this.accountGeneration,
    required this.selectedDay,
    required this.activeWorkspaceId,
    required this.isCallerActive,
    this.callerAvailabilityListenable,
  });

  bool get isValid =>
      isCallerActive() &&
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(accountGeneration);
}

class _CalendarFeedbackErrorText extends StatelessWidget {
  const _CalendarFeedbackErrorText();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) => Text(CalendarUiCopy.saveFailed),
    );
  }
}

class _LocaleAwareText extends StatelessWidget {
  final String Function() textBuilder;

  const _LocaleAwareText(this.textBuilder);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) => Text(textBuilder()),
    );
  }
}

class _LocaleAwareSecondaryMenuText extends StatelessWidget {
  final String Function() textBuilder;

  const _LocaleAwareSecondaryMenuText(this.textBuilder);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) => AppSecondaryMenuText(textBuilder()),
    );
  }
}

class _CalendarProjectOption {
  final String key;
  final String name;
  final int count;

  const _CalendarProjectOption({
    required this.key,
    required this.name,
    required this.count,
  });

  String get displayName =>
      key.isEmpty || name.isEmpty ? CalendarUiCopy.ungroupedProject : name;
}

class _CalendarWorkspaceOption {
  final String id;
  final String name;
  final int count;
  final bool isPrivate;
  final bool isFallbackShared;

  const _CalendarWorkspaceOption({
    required this.id,
    required this.name,
    required this.count,
    required this.isPrivate,
    this.isFallbackShared = false,
  });

  String get displayName {
    if (isPrivate) return CalendarUiCopy.personalWorkspace;
    if (isFallbackShared || name.isEmpty) return CalendarUiCopy.sharedWorkspace;
    return name;
  }
}

class _QuickAddTodoDialog extends StatefulWidget {
  final _CalendarOriginScope origin;

  const _QuickAddTodoDialog({required this.origin});

  @override
  State<_QuickAddTodoDialog> createState() => _QuickAddTodoDialogState();
}

class _QuickAddTodoDialogState extends State<_QuickAddTodoDialog> {
  late final TextEditingController _titleController;
  late final FocusNode _focusNode;
  bool _submitting = false;
  bool _saved = false;
  ModalRoute<dynamic>? _owningRoute;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _owningRoute ??= ModalRoute.of(context);
  }

  void _dismissOwningDialog() {
    final route = _owningRoute ?? ModalRoute.of(context);
    if (route != null && route.isActive) {
      if (route.isCurrent) {
        route.navigator?.pop();
      } else {
        route.navigator?.removeRoute(route);
      }
    }
  }

  void _showFeedbackError(BuildContext context) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null || !messenger.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: _CalendarFeedbackErrorText()),
    );
  }

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _focusNode = FocusNode();
    I18n.localeListenable.addListener(_onLocaleChanged);
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    _titleController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || _saved) return;
    if (!mounted || !widget.origin.isValid) {
      _dismissOwningDialog();
      return;
    }
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await context.read<TodoProvider>().addTodo(
        TodoItem(
          title: title,
          date: widget.origin.selectedDay,
          workspaceId: widget.origin.activeWorkspaceId ?? 'private',
        ),
        waitForReminderSync: false,
      );
      if (!mounted) return;
      if (!widget.origin.isValid) {
        _saved = true;
        _dismissOwningDialog();
        return;
      }
      _saved = true;
      _dismissOwningDialog();
    } catch (e) {
      if (!mounted) return;
      if (!widget.origin.isValid) {
        _dismissOwningDialog();
        return;
      }
      setState(() => _submitting = false);
      _showFeedbackError(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ThemeProvider>().brand.strings;
    return AppDialog(
      title: Text(
        CalendarUiCopy.quickAddTodoDialogTitle(
          s.calendarQuickAddTitle,
          widget.origin.selectedDay,
        ),
      ),
      content: AppSecondaryControlTheme(
        child: TextField(
          controller: _titleController,
          focusNode: _focusNode,
          enabled: !_submitting && !_saved,
          decoration: InputDecoration(labelText: CalendarUiCopy.todoTitleLabel),
          autofocus: true,
          onSubmitted: (_submitting || _saved) ? null : (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_submitting || _saved) ? null : _dismissOwningDialog,
          child: Text(I18n.tr('action.cancel')),
        ),
        FilledButton(
          onPressed: (_submitting || _saved) ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(I18n.tr('action.add')),
        ),
      ],
    );
  }
}

class _QuickAddTimeEntryDialog extends StatefulWidget {
  final _CalendarOriginScope origin;

  const _QuickAddTimeEntryDialog({required this.origin});

  @override
  State<_QuickAddTimeEntryDialog> createState() =>
      _QuickAddTimeEntryDialogState();
}

class _QuickAddTimeEntryDialogState extends State<_QuickAddTimeEntryDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late final TextEditingController _durationController;
  late TimeOfDay _startTime;
  TimeEntryCategory _category = TimeEntryCategory.work;
  bool _submitting = false;
  bool _saved = false;
  ModalRoute<dynamic>? _owningRoute;
  bool _originDismissalScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _owningRoute ??= ModalRoute.of(context);
  }

  void _dismissOwningDialog() {
    final route = _owningRoute ?? ModalRoute.of(context);
    if (route != null && route.isActive) {
      if (route.isCurrent) {
        route.navigator?.pop();
      } else {
        route.navigator?.removeRoute(route);
      }
    }
  }

  void _showFeedbackError(BuildContext context) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null || !messenger.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: _CalendarFeedbackErrorText()),
    );
  }

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _noteController = TextEditingController();
    _durationController = TextEditingController(text: '30');
    final now = DateTime.now();
    _startTime = TimeOfDay.fromDateTime(
      _isSameDay(widget.origin.selectedDay, now)
          ? now
          : DateTime(
              widget.origin.selectedDay.year,
              widget.origin.selectedDay.month,
              widget.origin.selectedDay.day,
              9,
            ),
    );
    I18n.localeListenable.addListener(_onLocaleChanged);
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _onOriginChanged,
    );
    widget.origin.callerAvailabilityListenable?.addListener(_onOriginChanged);
  }

  void _onOriginChanged() {
    if (!mounted || widget.origin.isValid || _originDismissalScheduled) return;
    _originDismissalScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _originDismissalScheduled = false;
      if (!mounted || widget.origin.isValid) return;
      _dismissOwningDialog();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _onOriginChanged,
    );
    widget.origin.callerAvailabilityListenable?.removeListener(
      _onOriginChanged,
    );
    _titleController.dispose();
    _noteController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _submit() async {
    if (_submitting || _saved) return;
    if (!mounted || !widget.origin.isValid) {
      _dismissOwningDialog();
      return;
    }
    final title = _titleController.text.trim();
    final minutes = int.tryParse(_durationController.text.trim()) ?? 0;
    if (title.isEmpty || minutes <= 0) return;
    setState(() => _submitting = true);
    try {
      final start = DateTime(
        widget.origin.selectedDay.year,
        widget.origin.selectedDay.month,
        widget.origin.selectedDay.day,
        _startTime.hour,
        _startTime.minute,
      );
      final end = start.add(Duration(minutes: minutes));
      await context.read<TimeAuditProvider>().add(
        TimeEntry(
          title: title,
          startAt: start,
          endAt: end,
          category: _category,
          source: TimeEntrySource.manual,
          note: _noteController.text.trim(),
        ),
      );
      if (!mounted) return;
      if (!widget.origin.isValid) {
        _saved = true;
        _dismissOwningDialog();
        return;
      }
      _saved = true;
      _dismissOwningDialog();
    } catch (e) {
      if (!mounted) return;
      if (!widget.origin.isValid) {
        _dismissOwningDialog();
        return;
      }
      setState(() => _submitting = false);
      _showFeedbackError(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: Text(
        CalendarUiCopy.quickAddTimeEntryDialogTitle(widget.origin.selectedDay),
      ),
      content: AppSecondaryControlTheme(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleController,
                enabled: !_submitting && !_saved,
                decoration: InputDecoration(
                  labelText: CalendarUiCopy.timeEntryTitleLabel,
                  prefixIcon: const Icon(Icons.title, size: 20),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              AppDropdownField<TimeEntryCategory>(
                initialValue: _category,
                labelText: CalendarUiCopy.timeEntryCategoryLabel,
                prefixIcon: const Icon(Icons.label_outline, size: 20),
                enabled: !_submitting && !_saved,
                isInteractionAllowed: () {
                  if (!mounted) return false;
                  if (!widget.origin.isValid) {
                    _dismissOwningDialog();
                    return false;
                  }
                  return !_submitting && !_saved;
                },
                items: [
                  for (final c in TimeEntryCategory.values)
                    DropdownMenuItem(
                      value: c,
                      child: _LocaleAwareText(() => c.label),
                    ),
                ],
                onChanged: (v) {
                  if (!mounted ||
                      !widget.origin.isValid ||
                      _submitting ||
                      _saved) {
                    return;
                  }
                  if (v != null) setState(() => _category = v);
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: Text(CalendarUiCopy.timeEntryStartTimeLabel),
                subtitle: Text(AppTimePicker.format(_startTime)),
                enabled: !_submitting && !_saved,
                onTap: (_submitting || _saved)
                    ? null
                    : () async {
                        if (!mounted || !widget.origin.isValid) {
                          _dismissOwningDialog();
                          return;
                        }
                        final picked = await AppTimePicker.show(
                          context,
                          initialTime: _startTime,
                          titleKey: 'calendar.content.time_picker_start_time',
                          minuteStep: 5,
                        );
                        if (!mounted || !widget.origin.isValid) return;
                        if (picked != null) {
                          setState(() => _startTime = picked);
                        }
                      },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _durationController,
                enabled: !_submitting && !_saved,
                decoration: InputDecoration(
                  labelText: CalendarUiCopy.timeEntryDurationLabel,
                  prefixIcon: const Icon(Icons.timelapse, size: 20),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                enabled: !_submitting && !_saved,
                decoration: InputDecoration(
                  labelText: CalendarUiCopy.timeEntryNoteLabel,
                  prefixIcon: const Icon(Icons.notes_outlined, size: 20),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_submitting || _saved) ? null : _dismissOwningDialog,
          child: Text(I18n.tr('action.cancel')),
        ),
        FilledButton(
          onPressed: (_submitting || _saved) ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(CalendarUiCopy.timeEntrySubmitButton),
        ),
      ],
    );
  }
}

class _QuickAddMenuSheet extends StatefulWidget {
  final _CalendarOriginScope origin;
  final VoidCallback onAiSchedule;
  final VoidCallback onNewEvent;
  final VoidCallback onNewTodo;
  final VoidCallback onQuickAddTimeEntry;
  final VoidCallback onNewGoal;

  const _QuickAddMenuSheet({
    required this.origin,
    required this.onAiSchedule,
    required this.onNewEvent,
    required this.onNewTodo,
    required this.onQuickAddTimeEntry,
    required this.onNewGoal,
  });

  @override
  State<_QuickAddMenuSheet> createState() => _QuickAddMenuSheetState();
}

class _QuickAddMenuSheetState extends State<_QuickAddMenuSheet> {
  ModalRoute<dynamic>? _owningRoute;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _owningRoute ??= ModalRoute.of(context);
  }

  void _dismissOwningSheet() {
    final route = _owningRoute ?? ModalRoute.of(context);
    if (route != null && route.isActive) {
      if (route.isCurrent) {
        route.navigator?.pop();
      } else {
        route.navigator?.removeRoute(route);
      }
    }
  }

  void _handleAction(VoidCallback callback) {
    if (!mounted || !widget.origin.isValid) {
      _dismissOwningSheet();
      return;
    }
    _dismissOwningSheet();
    callback();
  }

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

  @override
  Widget build(BuildContext context) {
    return AppModalSheet(
      title: CalendarUiCopy.quickAddMenuTitle,
      subtitle: CalendarUiCopy.quickAddMenuSubtitle,
      maxWidth: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: Text(CalendarUiCopy.quickAddAiScheduleTitle),
            subtitle: Text(CalendarUiCopy.quickAddAiScheduleSubtitle),
            onTap: () => _handleAction(widget.onAiSchedule),
          ),
          ListTile(
            leading: const Icon(Icons.event_note_outlined),
            title: Text(CalendarUiCopy.quickAddNewEventTitle),
            subtitle: Text(CalendarUiCopy.quickAddNewEventSubtitle),
            onTap: () => _handleAction(widget.onNewEvent),
          ),
          ListTile(
            leading: const Icon(Icons.check_circle_outline),
            title: Text(CalendarUiCopy.quickAddNewTodoTitle),
            onTap: () => _handleAction(widget.onNewTodo),
          ),
          ListTile(
            leading: const Icon(Icons.timelapse_outlined),
            title: Text(CalendarUiCopy.quickAddTimeEntryTitle),
            onTap: () => _handleAction(widget.onQuickAddTimeEntry),
          ),
          ListTile(
            leading: const Icon(Icons.flag_circle_outlined),
            title: Text(CalendarUiCopy.isEn ? 'New goal' : '新建目标'),
            onTap: () => _handleAction(widget.onNewGoal),
          ),
        ],
      ),
    );
  }
}

class _CalendarMenuConfigSheet extends StatefulWidget {
  final _CalendarOriginScope origin;

  const _CalendarMenuConfigSheet({required this.origin});

  @override
  State<_CalendarMenuConfigSheet> createState() =>
      _CalendarMenuConfigSheetState();
}

class _CalendarMenuConfigSheetState extends State<_CalendarMenuConfigSheet> {
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

  String _labelFor(String item) {
    return switch (item) {
      'today' => MainUiCopy.calendarBackToToday,
      'pick' => MainUiCopy.calendarPickDate,
      'month' => MainUiCopy.calendarViewMonth,
      'week' => MainUiCopy.calendarViewWeek,
      'day' => MainUiCopy.calendarViewDay,
      'three_day' => MainUiCopy.calendarViewThreeDay,
      'year' => MainUiCopy.calendarViewYear,
      _ => item,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isEn = CalendarUiCopy.isEn;
    final prefs = context.watch<PreferencesProvider?>();
    final order =
        prefs?.calendarMenuOrder ??
        PreferencesProvider.defaultCalendarMenuOrder;
    final hidden = prefs?.calendarMenuHidden ?? const <String>{};
    final visibleCount = order.where((item) => !hidden.contains(item)).length;
    final cs = Theme.of(context).colorScheme;

    return AppModalSheet(
      title: isEn ? 'Configure menu' : '配置菜单',
      subtitle: isEn
          ? 'Show, hide, or reorder calendar menu items'
          : '显示、隐藏或调整日历菜单项顺序',
      maxWidth: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < order.length; i++) ...[
            Builder(
              builder: (context) {
                final item = order[i];
                final isVisible = !hidden.contains(item);
                final canHide = !(isVisible && visibleCount <= 1);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Checkbox(
                        key: ValueKey('calendar_menu_toggle_$item'),
                        value: isVisible,
                        onChanged: prefs == null || !canHide
                            ? null
                            : (value) {
                                if (!widget.origin.isValid || value == null) {
                                  return;
                                }
                                prefs.setCalendarMenuItemVisible(item, value);
                              },
                      ),
                      Expanded(
                        child: Text(
                          _labelFor(item),
                          softWrap: true,
                          style: appSecondaryMenuItemTextStyle(context),
                        ),
                      ),
                      IconButton(
                        key: ValueKey('calendar_menu_up_$item'),
                        tooltip: isEn ? 'Move up' : '上移',
                        icon: const Icon(Icons.arrow_upward, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: prefs == null || i == 0
                            ? null
                            : () {
                                if (!widget.origin.isValid) return;
                                prefs.moveCalendarMenuItem(item, -1);
                              },
                      ),
                      IconButton(
                        key: ValueKey('calendar_menu_down_$item'),
                        tooltip: isEn ? 'Move down' : '下移',
                        icon: const Icon(Icons.arrow_downward, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: prefs == null || i == order.length - 1
                            ? null
                            : () {
                                if (!widget.origin.isValid) return;
                                prefs.moveCalendarMenuItem(item, 1);
                              },
                      ),
                    ],
                  ),
                );
              },
            ),
            if (i < order.length - 1)
              Divider(
                height: 1,
                color: cs.outlineVariant.withValues(alpha: 0.14),
              ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: const ValueKey('calendar_menu_reset_button'),
                onPressed: prefs == null
                    ? null
                    : () {
                        if (!widget.origin.isValid) return;
                        prefs.resetCalendarMenuConfig();
                      },
                child: Text(isEn ? 'Reset' : '恢复默认'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: appSecondaryFilledButtonStyle(context),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(isEn ? 'Done' : '完成'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectDetailSheet extends StatefulWidget {
  final _CalendarOriginScope origin;
  final _CalendarProjectOption option;
  final List<TodoItem> todos;

  const _ProjectDetailSheet({
    required this.origin,
    required this.option,
    required this.todos,
  });

  @override
  State<_ProjectDetailSheet> createState() => _ProjectDetailSheetState();
}

class _ProjectDetailSheetState extends State<_ProjectDetailSheet> {
  ModalRoute<dynamic>? _owningRoute;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _owningRoute ??= ModalRoute.of(context);
  }

  void _dismissOwningSheet() {
    final route = _owningRoute ?? ModalRoute.of(context);
    if (route != null && route.isActive) {
      if (route.isCurrent) {
        route.navigator?.pop();
      } else {
        route.navigator?.removeRoute(route);
      }
    }
  }

  void _openTodoScreen() {
    if (!mounted || !widget.origin.isValid) {
      _dismissOwningSheet();
      return;
    }
    _dismissOwningSheet();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BrandRouteSurface(child: TodoScreen()),
      ),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);
    final completed = widget.todos.where((todo) => todo.isCompleted).length;
    final overdue = widget.todos.where((todo) => todo.isOverdue).length;
    final todayCount = widget.todos.where((todo) {
      final d = DateTime(todo.date.year, todo.date.month, todo.date.day);
      return d == todayKey;
    }).length;

    return AppModalSheet(
      title: CalendarUiCopy.projectDetailSheetTitle,
      subtitle: widget.option.displayName,
      maxWidth: 860,
      scrollable: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sheetHeight = (MediaQuery.sizeOf(context).height * 0.68).clamp(
            360.0,
            680.0,
          );
          return SizedBox(
            height: sheetHeight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = constraints.maxWidth >= 640
                        ? (constraints.maxWidth - 36) / 4
                        : (constraints.maxWidth - 12) / 2;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: itemWidth,
                          child: _ProjectStat(
                            label: CalendarUiCopy.projectStatTotal,
                            value: '${widget.todos.length}',
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _ProjectStat(
                            label: CalendarUiCopy.projectStatCompleted,
                            value: '$completed',
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _ProjectStat(
                            label: CalendarUiCopy.projectStatOverdue,
                            value: '$overdue',
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _ProjectStat(
                            label: CalendarUiCopy.projectStatToday,
                            value: '$todayCount',
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: widget.todos.isEmpty
                      ? Center(child: Text(CalendarUiCopy.projectEmptyTasks))
                      : Scrollbar(
                          child: ListView.separated(
                            key: const ValueKey(
                              'calendar_project_detail_scroll_region',
                            ),
                            primary: false,
                            padding: EdgeInsets.zero,
                            itemCount: widget.todos.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final todo = widget.todos[index];
                              final visual =
                                  CompletionVisibilityPolicy.visualState(todo);
                              final isCompleted =
                                  visual == TodoVisualState.completed;
                              final isOverdue =
                                  visual == TodoVisualState.overdue;
                              final statusColor = isCompleted
                                  ? Theme.of(context).colorScheme.tertiary
                                  : isOverdue
                                  ? Theme.of(context).colorScheme.error
                                  : null;
                              return ListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  isCompleted
                                      ? Icons.check_circle
                                      : isOverdue
                                      ? Icons.priority_high_rounded
                                      : Icons.radio_button_unchecked,
                                  size: 18,
                                  color: statusColor,
                                ),
                                title: Text(
                                  todo.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isCompleted
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant
                                        : isOverdue
                                        ? Theme.of(context).colorScheme.error
                                        : null,
                                    decoration: isCompleted
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                subtitle: Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      '${todo.date.month}/${todo.date.day}${todo.priority != TodoPriority.none ? ' · ${todo.priority.label}' : ''}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    if (statusColor != null)
                                      Text(
                                        isCompleted
                                            ? MainUiCopy.calendarStatusCompleted
                                            : MainUiCopy.calendarStatusOverdue,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: statusColor,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: _openTodoScreen,
                    icon: const Icon(Icons.open_in_new),
                    label: Text(CalendarUiCopy.openTodoScreenButton),
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

class _ProjectStat extends StatelessWidget {
  final String label;
  final String value;

  const _ProjectStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    return AppSurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(
        surfaceStyle?.smallTileRadius ?? DesignTokens.radiusControl,
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.normal,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _CalendarNavigationHeader extends StatelessWidget {
  final int tabIndex;
  final String monthLabel;
  final String weekLabel;
  final String dayLabel;
  final String threeDayLabel;
  final String yearLabel;
  final VoidCallback? onPreviousMonth;
  final VoidCallback? onNextMonth;
  final VoidCallback? onPreviousWeek;
  final VoidCallback? onNextWeek;
  final VoidCallback? onPreviousDay;
  final VoidCallback? onNextDay;
  final VoidCallback? onPreviousThreeDays;
  final VoidCallback? onNextThreeDays;
  final VoidCallback? onPreviousYear;
  final VoidCallback? onNextYear;
  final VoidCallback onPickDate;

  const _CalendarNavigationHeader({
    required this.tabIndex,
    required this.monthLabel,
    required this.weekLabel,
    required this.dayLabel,
    required this.threeDayLabel,
    required this.yearLabel,
    this.onPreviousMonth,
    this.onNextMonth,
    this.onPreviousWeek,
    this.onNextWeek,
    this.onPreviousDay,
    this.onNextDay,
    this.onPreviousThreeDays,
    this.onNextThreeDays,
    this.onPreviousYear,
    this.onNextYear,
    required this.onPickDate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = switch (tabIndex) {
      0 => monthLabel,
      1 => weekLabel,
      2 => dayLabel,
      3 => threeDayLabel,
      4 => yearLabel,
      _ => dayLabel,
    };
    final previous = switch (tabIndex) {
      0 => onPreviousMonth,
      1 => onPreviousWeek,
      2 => onPreviousDay,
      3 => onPreviousThreeDays,
      4 => onPreviousYear,
      _ => null,
    };
    final next = switch (tabIndex) {
      0 => onNextMonth,
      1 => onNextWeek,
      2 => onNextDay,
      3 => onNextThreeDays,
      4 => onNextYear,
      _ => null,
    };
    final previousTooltip = switch (tabIndex) {
      0 => MainUiCopy.calendarPrevMonth,
      1 => MainUiCopy.calendarPrevWeek,
      2 => MainUiCopy.calendarPrevDay,
      3 => MainUiCopy.calendarPrevThreeDays,
      4 => MainUiCopy.calendarPrevYear,
      _ => MainUiCopy.calendarPrevDay,
    };
    final nextTooltip = switch (tabIndex) {
      0 => MainUiCopy.calendarNextMonth,
      1 => MainUiCopy.calendarNextWeek,
      2 => MainUiCopy.calendarNextDay,
      3 => MainUiCopy.calendarNextThreeDays,
      4 => MainUiCopy.calendarNextYear,
      _ => MainUiCopy.calendarNextDay,
    };

    final isLiquidGlass =
        appSurfaceStyleOf(context) == AppSurfaceStyle.liquidGlass;
    return Material(
      type: isLiquidGlass ? MaterialType.transparency : MaterialType.canvas,
      color: isLiquidGlass ? null : cs.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 390;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 5 : 8,
              5,
              compact ? 5 : 8,
              6,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: compact ? 62 : 68),
              child: DecoratedBox(
                key: const ValueKey('calendar_navigation_header_bar'),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(
                    appSurfaceStyleOf(context)?.cardRadius ??
                        DesignTokens.radiusCard,
                  ),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.10),
                    width: 0.45,
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.all(compact ? 4 : 5),
                  child: Row(
                    children: [
                      _NavIconButton(
                        icon: Icons.chevron_left,
                        onPressed: previous,
                        tooltip: previousTooltip,
                        dimension: 48,
                      ),
                      SizedBox(width: compact ? 3 : 4),
                      Expanded(
                        child: FilledButton(
                          key: const ValueKey(
                            'calendar_navigation_date_button',
                          ),
                          onPressed: onPickDate,
                          style: FilledButton.styleFrom(
                            foregroundColor: cs.onSurface,
                            backgroundColor: Color.alphaBlend(
                              cs.primary.withValues(alpha: 0.10),
                              cs.surface,
                            ),
                            minimumSize: compact
                                ? const Size(0, 52)
                                : const Size(double.infinity, 56),
                            padding: EdgeInsets.symmetric(
                              horizontal: compact ? 8 : 14,
                              vertical: 4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                appSurfaceStyleOf(context)?.smallTileRadius ??
                                    DesignTokens.radiusControl,
                              ),
                              side: BorderSide(
                                color: cs.primary.withValues(alpha: 0.10),
                                width: 0.45,
                              ),
                            ),
                            textStyle: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  fontSize: compact ? 12.5 : 13.5,
                                  fontWeight: FontWeight.normal,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                  height: 1.15,
                                ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!compact) ...[
                                const Icon(
                                  Icons.calendar_month_outlined,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Flexible(
                                child: Text(label, textAlign: TextAlign.center),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: compact ? 3 : 4),
                      _NavIconButton(
                        icon: Icons.chevron_right,
                        onPressed: next,
                        tooltip: nextTooltip,
                        dimension: 48,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NavIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double dimension;

  const _NavIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.dimension = 44,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: dimension,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        iconSize: dimension <= 34 ? 19 : 20,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          fixedSize: Size.square(dimension),
          minimumSize: Size.square(dimension),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
  }
}

class _CalendarThreeDayView extends StatelessWidget {
  final DateTime startDate;
  final CalendarProvider calendarProvider;
  final Set<CalendarEventType>? activeTypes;
  final String? projectKey;
  final String? workspaceId;
  final bool hasActiveFilters;

  const _CalendarThreeDayView({
    super.key,
    required this.startDate,
    required this.calendarProvider,
    this.activeTypes,
    this.projectKey,
    this.workspaceId,
    required this.hasActiveFilters,
  });

  @override
  Widget build(BuildContext context) {
    final days = CalendarDateNavigation.daysFrom(startDate, 3);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < days.length; i++) ...[
                Expanded(
                  child: _ThreeDayLane(
                    date: days[i],
                    calendarProvider: calendarProvider,
                    activeTypes: activeTypes,
                    projectKey: projectKey,
                    workspaceId: workspaceId,
                    hasActiveFilters: hasActiveFilters,
                  ),
                ),
                if (i != days.length - 1)
                  VerticalDivider(
                    width: 1,
                    thickness: 0.5,
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.16),
                  ),
              ],
            ],
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final day in days)
                SizedBox(
                  width: constraints.maxWidth < 390
                      ? constraints.maxWidth
                      : 380,
                  child: _ThreeDayLane(
                    date: day,
                    calendarProvider: calendarProvider,
                    activeTypes: activeTypes,
                    projectKey: projectKey,
                    workspaceId: workspaceId,
                    hasActiveFilters: hasActiveFilters,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ThreeDayLane extends StatelessWidget {
  final DateTime? date;
  final CalendarProvider calendarProvider;
  final Set<CalendarEventType>? activeTypes;
  final String? projectKey;
  final String? workspaceId;
  final bool hasActiveFilters;

  const _ThreeDayLane({
    required this.date,
    required this.calendarProvider,
    this.activeTypes,
    this.projectKey,
    this.workspaceId,
    required this.hasActiveFilters,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final targetDate = date;
    if (targetDate == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSurfaceCard(
            key: const ValueKey('calendar_three_day_lane_unavailable_header'),
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            borderRadius: BorderRadius.circular(
              appSurfaceStyleOf(context)?.cardRadius ?? DesignTokens.radiusCard,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.view_column_outlined,
                  size: 16,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.38),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    CalendarUiCopy.unavailable,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.normal,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.38),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AppSurfaceCard(
              key: const ValueKey('calendar_three_day_lane_unavailable_body'),
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              padding: EdgeInsets.zero,
              borderRadius: BorderRadius.circular(
                appSurfaceStyleOf(context)?.cardRadius ??
                    DesignTokens.radiusCard,
              ),
              child: Center(
                child: Text(
                  CalendarUiCopy.unavailable,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.38),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    final events = calendarProvider.getEventsForDate(
      targetDate,
      activeTypes: activeTypes,
      projectKey: projectKey,
      workspaceId: workspaceId,
    );
    final cardRadius = BorderRadius.circular(
      appSurfaceStyleOf(context)?.cardRadius ?? DesignTokens.radiusCard,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSurfaceCard(
          key: ValueKey(
            'calendar_three_day_lane_skin_${targetDate.toIso8601String()}',
          ),
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          borderRadius: cardRadius,
          child: Row(
            children: [
              Icon(Icons.view_column_outlined, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  CalendarUiCopy.threeDayLaneHeader(targetDate),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                CalendarUiCopy.laneItemCount(events.length),
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: AppSurfaceCard(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            padding: EdgeInsets.zero,
            borderRadius: cardRadius,
            child: CalendarDayAgenda(
              date: targetDate,
              calendarProvider: calendarProvider,
              activeTypes: activeTypes,
              projectKey: projectKey,
              workspaceId: workspaceId,
              hasActiveFilters: hasActiveFilters,
              horizontalPadding: 8,
            ),
          ),
        ),
      ],
    );
  }
}

enum _CalendarSemanticTone {
  holiday,
  makeup,
  event,
  anniversary,
  course,
  diary,
  countdown,
  goal,
  timeEntry,
}

Color _calendarToneColor(
  ColorScheme cs,
  bool isDark,
  _CalendarSemanticTone tone,
) {
  return switch (tone) {
    _CalendarSemanticTone.holiday =>
      isDark ? const Color(0xFF4DB6AC) : DesignTokens.defaultAccent,
    _CalendarSemanticTone.makeup =>
      isDark ? const Color(0xFFB39DDB) : const Color(0xFF5E35B1),
    _CalendarSemanticTone.event =>
      isDark ? const Color(0xFF8C9EFF) : const Color(0xFF4B5ED7),
    _CalendarSemanticTone.anniversary =>
      isDark ? const Color(0xFFF48FB1) : const Color(0xFFD81B60),
    _CalendarSemanticTone.course =>
      isDark ? const Color(0xFF64B5F6) : DesignTokens.defaultInfo,
    _CalendarSemanticTone.diary =>
      isDark ? const Color(0xFF4DB6AC) : DesignTokens.defaultAccent,
    _CalendarSemanticTone.countdown =>
      isDark ? const Color(0xFFFFB74D) : DesignTokens.defaultWarning,
    _CalendarSemanticTone.goal =>
      isDark ? const Color(0xFFFFCC80) : DesignTokens.defaultWarning,
    _CalendarSemanticTone.timeEntry => cs.onSurfaceVariant,
  };
}

class _CalendarMetaStrip extends StatelessWidget {
  final DateTime selectedDay;
  final VoidCallback onOpenAlmanac;

  const _CalendarMetaStrip({
    required this.selectedDay,
    required this.onOpenAlmanac,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isoWeek = LunarCalendar.isoWeekNumber(selectedDay);
    var xingZuo = '';
    try {
      xingZuo = AlmanacLocaleFormat.formatXingZuo(
        LunarCalendar.xingZuo(selectedDay),
      );
    } catch (_) {}
    final isHoliday = HolidayCalendar.isHoliday(selectedDay);
    final isMakeup = HolidayCalendar.isWorkMakeupDay(selectedDay);
    final holidayName = isHoliday ? HolidayCalendar.holidayName(selectedDay) : null;
    final fillColor = Color.alphaBlend(
      cs.primary.withValues(alpha: isDark ? 0.08 : 0.045),
      cs.surface,
    );

    return AppSurfaceCard(
      key: const ValueKey('calendar_month_meta_strip'),
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      borderRadius: BorderRadius.circular(
        surfaceStyle?.cardRadius ?? DesignTokens.radiusCard,
      ),
      color: fillColor,
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: 0.16),
        width: 0.45,
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _metaPill(
                context,
                text: AlmanacUiCopy.isoWeekBadge(isoWeek),
                color: cs.primary,
                surfaceBg: fillColor,
              ),
              if (xingZuo.isNotEmpty)
                _metaPill(
                  context,
                  text: xingZuo,
                  color: cs.secondary,
                  surfaceBg: fillColor,
                ),
              if (isHoliday)
                _metaPill(
                  context,
                  text: holidayName != null && holidayName.isNotEmpty
                      ? '${AlmanacUiCopy.holidayTag} · $holidayName'
                      : AlmanacUiCopy.holidayBadge,
                  color: _calendarToneColor(
                    cs,
                    isDark,
                    _CalendarSemanticTone.holiday,
                  ),
                  surfaceBg: fillColor,
                ),
              if (isMakeup)
                _metaPill(
                  context,
                  text: AlmanacUiCopy.makeupWorkdayBadge,
                  color: _calendarToneColor(
                    cs,
                    isDark,
                    _CalendarSemanticTone.makeup,
                  ),
                  surfaceBg: fillColor,
                ),
            ],
          ),
          InkWell(
            key: const ValueKey('calendar_meta_open_almanac_chip'),
            borderRadius: BorderRadius.circular(999),
            onTap: onOpenAlmanac,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: cs.primary.withValues(alpha: 0.24),
                  width: 0.45,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_stories_outlined,
                    size: 13,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    AlmanacUiCopy.fullAlmanacAndAuspiciousAction,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.primary,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaPill(
    BuildContext context, {
    required String text,
    required Color color,
    required Color surfaceBg,
  }) {
    final cs = Theme.of(context).colorScheme;
    final pillBg = Color.alphaBlend(color.withValues(alpha: 0.10), surfaceBg);
    final readableColor = appReadableForeground(
      pillBg,
      Color.lerp(color, cs.onSurface, 0.22) ?? color,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: readableColor,
          fontWeight: FontWeight.normal,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _YearOverviewMonthData {
  final int month;
  final int firstWeekday;
  final List<DateTime> days;
  final List<String> dateKeys;
  final List<bool> isHoliday;
  final List<bool> isMakeup;
  final List<bool> isWeekend;

  const _YearOverviewMonthData({
    required this.month,
    required this.firstWeekday,
    required this.days,
    required this.dateKeys,
    required this.isHoliday,
    required this.isMakeup,
    required this.isWeekend,
  });
}

class _CalendarYearOverview extends StatelessWidget {
  static const int _maxYearCacheEntries = 8;
  static final LinkedHashMap<(int, int), List<_YearOverviewMonthData>>
  _yearCache = LinkedHashMap<(int, int), List<_YearOverviewMonthData>>();

  static List<_YearOverviewMonthData> _yearDataFor(int year) {
    final key = (year, HolidayCalendar.cacheVersion);
    final existing = _yearCache.remove(key);
    if (existing != null) {
      _yearCache[key] = existing;
      return existing;
    }
    final months = List<_YearOverviewMonthData>.generate(12, (idx) {
      final month = idx + 1;
      final count = DateTime(year, month + 1, 0).day;
      final days = List<DateTime>.generate(
        count,
        (i) => DateTime(year, month, i + 1),
        growable: false,
      );
      final monthPad = month.toString().padLeft(2, '0');
      final dateKeys = List<String>.generate(
        count,
        (i) => '$year-$monthPad-${(i + 1).toString().padLeft(2, '0')}',
        growable: false,
      );
      final isHoliday = List<bool>.generate(
        count,
        (i) => HolidayCalendar.isHoliday(days[i]),
        growable: false,
      );
      final isMakeup = List<bool>.generate(
        count,
        (i) => HolidayCalendar.isWorkMakeupDay(days[i]),
        growable: false,
      );
      final isWeekend = List<bool>.generate(
        count,
        (i) =>
            days[i].weekday == DateTime.saturday ||
            days[i].weekday == DateTime.sunday,
        growable: false,
      );
      return _YearOverviewMonthData(
        month: month,
        firstWeekday: days.first.weekday,
        days: days,
        dateKeys: dateKeys,
        isHoliday: isHoliday,
        isMakeup: isMakeup,
        isWeekend: isWeekend,
      );
    }, growable: false);
    final immutable = List<_YearOverviewMonthData>.unmodifiable(months);
    if (_yearCache.length >= _maxYearCacheEntries) {
      _yearCache.remove(_yearCache.keys.first);
    }
    _yearCache[key] = immutable;
    return immutable;
  }

  final int year;
  final int firstDayOfWeek;
  final DateTime selectedDay;
  final Map<String, List<CalendarEventType>> dateEventTypes;
  final void Function(int month) onMonthTap;
  final ValueChanged<DateTime>? onDayTap;

  const _CalendarYearOverview({
    super.key,
    required this.year,
    required this.firstDayOfWeek,
    required this.selectedDay,
    required this.dateEventTypes,
    required this.onMonthTap,
    this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final yearMonths = _yearDataFor(year);
    final textScaler = MediaQuery.textScalerOf(context);
    final scale = textScaler.scale(14) / 14;
    final now = DateTime.now();
    final weekdayInitials = AlmanacUiCopy.weekdayInitials;
    final orderedWeekdays = CalendarDateNavigation.orderedWeekdays(
      firstDayOfWeek,
    ).map((weekday) => weekdayInitials[weekday - 1]).toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isEnlargedNarrow = constraints.maxWidth < 360 && scale > 1.25;
        final crossAxisCount = isEnlargedNarrow
            ? 1
            : (constraints.maxWidth >= 920
                  ? 3
                  : (constraints.maxWidth >= 360 ? 2 : 1));
        final cardInnerWidth =
            ((constraints.maxWidth -
                        24.0 -
                        (crossAxisCount - 1) * 10.0) /
                    crossAxisCount -
                20.0)
                .clamp(40.0, double.infinity);
        final textDirection = Directionality.of(context);
        final locale = Localizations.maybeLocaleOf(context);
        double measureHeaderWidth(String text, double fontSize) {
          final painter = TextPainter(
            text: TextSpan(
              text: text,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.normal,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            textScaler: textScaler,
            textDirection: textDirection,
            locale: locale,
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        var maxMonthTitleWidth = 0.0;
        for (var m = 1; m <= 12; m++) {
          final w = measureHeaderWidth(CalendarUiCopy.yearMonthTitle(m), 15);
          if (w > maxMonthTitleWidth) maxMonthTitleWidth = w;
        }
        final emptyCountWidth = measureHeaderWidth(
          CalendarUiCopy.yearMonthEventCount(0),
          10.5,
        );
        final needsSecondHeaderLine =
            isEnlargedNarrow ||
            (maxMonthTitleWidth + 6.0 + emptyCountWidth) > cardInnerWidth;
        final headerHeight = textScaler.scale(15) * 1.3 + 4.0;
        final countHeight = textScaler.scale(10.5) * 1.3 + 2.0;
        final weekdayRowHeight = textScaler.scale(9.5) * 1.25 + 4.0;
        final dayRowHeight =
            (textScaler.scale(10) * 1.25 + 7.0).clamp(18.0, 28.0).toDouble();
        final mainAxisExtent =
            (22.0 +
                    headerHeight +
                    (needsSecondHeaderLine ? (countHeight + 2.0) : 0.0) +
                    4.0 +
                    weekdayRowHeight +
                    4.0 +
                    dayRowHeight * 6.0 +
                    8.0)
                .clamp(192.0, 368.0)
                .toDouble();

        final surfaceStyle = appSurfaceStyleOf(context);
        final selectedFill = Color.alphaBlend(
          cs.primary.withValues(alpha: isDark ? 0.20 : 0.13),
          cs.surface,
        );
        final selectedText = cs.onSurface;
        final holidayTone = _calendarToneColor(
          cs,
          isDark,
          _CalendarSemanticTone.holiday,
        );
        final makeupTone = _calendarToneColor(
          cs,
          isDark,
          _CalendarSemanticTone.makeup,
        );

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          itemCount: yearMonths.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: mainAxisExtent,
          ),
          itemBuilder: (context, index) {
            final monthData = yearMonths[index];
            final month = monthData.month;
            final monthDays = monthData.days;
            final monthKeys = monthData.dateKeys;
            var eventCount = 0;
            for (final key in monthKeys) {
              eventCount += dateEventTypes[key]?.length ?? 0;
            }
            final isSelected =
                selectedDay.year == year && selectedDay.month == month;
            final leadingOffset =
                (monthData.firstWeekday - firstDayOfWeek + 7) % 7;

            final cardFill = isSelected
                ? selectedFill
                : Color.alphaBlend(
                    surfaceStyle?.cardFillColor ?? cs.surface,
                    cs.surface,
                  );

            return RepaintBoundary(
              child: AppSurfaceCard(
                padding: EdgeInsets.zero,
                borderRadius: BorderRadius.circular(
                  surfaceStyle?.cardRadius ?? DesignTokens.radiusCard,
                ),
                color: isSelected ? selectedFill : null,
                border: Border.all(
                  color: isSelected
                      ? cs.primary.withValues(alpha: 0.34)
                      : cs.outlineVariant.withValues(alpha: 0.14),
                  width: 0.45,
                ),
                onTap: () => onMonthTap(month),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 2,
                          children: [
                            Text(
                              CalendarUiCopy.yearMonthTitle(month),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.normal,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                color: isSelected ? selectedText : cs.onSurface,
                              ),
                            ),
                            Text(
                              CalendarUiCopy.yearMonthEventCount(eventCount),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                color: isSelected
                                    ? selectedText.withValues(alpha: 0.72)
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          for (final wd in orderedWeekdays)
                            Expanded(
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    wd,
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: cs.onSurfaceVariant.withValues(
                                        alpha: 0.70,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Expanded(
                        child: Column(
                          children: List.generate(6, (row) {
                            return Expanded(
                              child: Row(
                                children: List.generate(7, (col) {
                                  final slot = row * 7 + col;
                                  final dayNum = slot - leadingOffset + 1;
                                  if (dayNum < 1 || dayNum > monthDays.length) {
                                    return const Expanded(
                                      child: SizedBox.shrink(),
                                    );
                                  }
                                  final dayIdx = dayNum - 1;
                                  final day = monthDays[dayIdx];
                                  final key = monthKeys[dayIdx];
                                  final dayTypes =
                                      dateEventTypes[key] ??
                                      const <CalendarEventType>[];
                                  final isToday =
                                      day.year == now.year &&
                                      day.month == now.month &&
                                      day.day == now.day;
                                  final isSelectedDay =
                                      day.year == selectedDay.year &&
                                      day.month == selectedDay.month &&
                                      day.day == selectedDay.day;
                                  final isHoliday =
                                      monthData.isHoliday[dayIdx];
                                  final isMakeup = monthData.isMakeup[dayIdx];
                                  final isWeekend =
                                      monthData.isWeekend[dayIdx];
                                  final dotColor = dayTypes.isNotEmpty
                                      ? _colorFor(
                                          dayTypes.first,
                                          cs,
                                          isDark: isDark,
                                        )
                                      : null;
                                  Color textColor = cs.onSurface.withValues(
                                    alpha: isWeekend ? 0.62 : 0.88,
                                  );
                                  BoxDecoration? cellDeco;
                                  if (isToday) {
                                    cellDeco = BoxDecoration(
                                      color: cs.primary,
                                      shape: BoxShape.circle,
                                    );
                                    textColor = cs.onPrimary;
                                  } else if (isSelectedDay) {
                                    cellDeco = BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.16),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: cs.primary.withValues(
                                          alpha: 0.50,
                                        ),
                                        width: 0.45,
                                      ),
                                    );
                                    textColor = selectedText;
                                  } else if (isHoliday) {
                                    final fill = holidayTone.withValues(
                                      alpha: 0.13,
                                    );
                                    cellDeco = BoxDecoration(
                                      color: fill,
                                      borderRadius: BorderRadius.circular(
                                        DesignTokens.radiusXs,
                                      ),
                                    );
                                    textColor = appReadableForeground(
                                      Color.alphaBlend(fill, cardFill),
                                      holidayTone,
                                    );
                                  } else if (isMakeup) {
                                    final fill = makeupTone.withValues(
                                      alpha: 0.12,
                                    );
                                    cellDeco = BoxDecoration(
                                      color: fill,
                                      borderRadius: BorderRadius.circular(
                                        DesignTokens.radiusXs,
                                      ),
                                    );
                                    textColor = appReadableForeground(
                                      Color.alphaBlend(fill, cardFill),
                                      makeupTone,
                                    );
                                  }

                                  return Expanded(
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(
                                        DesignTokens.radiusSm,
                                      ),
                                      onTap: () {
                                        if (onDayTap != null) {
                                          onDayTap!(day);
                                        } else {
                                          onMonthTap(month);
                                        }
                                      },
                                      child: Container(
                                        margin: const EdgeInsets.all(0.5),
                                        decoration: cellDeco,
                                        alignment: Alignment.center,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                '$dayNum',
                                                maxLines: 1,
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  color: textColor,
                                                  fontWeight: FontWeight.normal,
                                                  fontFeatures: const [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            if (dotColor != null && !isToday)
                                              Positioned(
                                                bottom: 1,
                                                child: _MonthDot(
                                                  color: dotColor,
                                                  filled: true,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Color _colorFor(CalendarEventType t, ColorScheme cs, {required bool isDark}) {
    switch (t) {
      case CalendarEventType.event:
        return _calendarToneColor(cs, isDark, _CalendarSemanticTone.event);
      case CalendarEventType.todo:
        return cs.primary;
      case CalendarEventType.habit:
        return cs.tertiary;
      case CalendarEventType.pomodoro:
        return DesignTokens.defaultError;
      case CalendarEventType.anniversary:
        return _calendarToneColor(
          cs,
          isDark,
          _CalendarSemanticTone.anniversary,
        );
      case CalendarEventType.course:
        return _calendarToneColor(cs, isDark, _CalendarSemanticTone.course);
      case CalendarEventType.diary:
        return _calendarToneColor(cs, isDark, _CalendarSemanticTone.diary);
      case CalendarEventType.countdown:
        return _calendarToneColor(
          cs,
          isDark,
          _CalendarSemanticTone.countdown,
        );
      case CalendarEventType.goal:
        return _calendarToneColor(cs, isDark, _CalendarSemanticTone.goal);
      case CalendarEventType.timeEntry:
        return _calendarToneColor(
          cs,
          isDark,
          _CalendarSemanticTone.timeEntry,
        );
    }
  }
}

class _MonthDot extends StatelessWidget {
  final Color color;
  final bool filled;

  const _MonthDot({required this.color, required this.filled});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(
        color: filled
            ? color.withValues(alpha: 0.78)
            : color.withValues(alpha: 0.25),
        shape: BoxShape.circle,
      ),
    );
  }
}
