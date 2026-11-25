import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/almanac_locale_format.dart';
import '../../core/almanac_ui_copy.dart';
import '../../core/calendar_date_navigation.dart';
import '../../core/completion_visibility_policy.dart';
import '../../core/goal_icons.dart';
import '../../core/habit_icons.dart';
import '../../core/i18n.dart';
import '../../core/i18n_date_format.dart';
import '../../core/lunar_calendar.dart';
import '../../core/quotes.dart';
import '../../core/report_engine.dart';
import '../../core/smart_todo_draft.dart';
import '../../models/goal.dart';
import '../../models/habit.dart';
import '../../models/pomodoro.dart';
import '../../models/time_entry.dart';
import '../../models/todo.dart';
import '../../providers/diary_provider.dart';
import '../../providers/goal_provider.dart';
import '../../providers/habit_provider.dart';
import '../../providers/pomodoro_provider.dart';
import '../../providers/preferences_provider.dart';
import '../../providers/share_provider.dart';
import '../../providers/time_audit_provider.dart';
import '../../providers/todo_provider.dart';
import '../../services/holiday_calendar.dart';
import '../desktop_web_nav.dart';
import '../desktop_web_tokens.dart';

/// Desktop Today Command Center for Duoyi Web.
///
/// Organizes daily execution into a compact KPI strip, inline quick-add input,
/// a 62% main column (Today checklist, habit check-in strip, active goals),
/// and a 38% right inspector (focus launcher, mini-calendar, lunar/almanac,
/// weekly efficiency ring, and daily quote).
class DesktopTodayView extends StatefulWidget {
  const DesktopTodayView({
    super.key,
    this.controller,
    this.onNavigate,
    this.onOpenTodo,
    this.onStartFocus,
  });

  final DesktopWebNavController? controller;
  final void Function(DesktopWebDestination destination)? onNavigate;
  final void Function(String todoId)? onOpenTodo;
  final void Function({String? taskTitle})? onStartFocus;

  @override
  State<DesktopTodayView> createState() => _DesktopTodayViewState();
}

class _DesktopTodayViewState extends State<DesktopTodayView> {
  final TextEditingController _quickAddController = TextEditingController();
  final FocusNode _quickAddFocusNode = FocusNode();
  bool _quickAddFocused = false;
  TodoPriority _quickPriority = TodoPriority.none;
  bool _showCompletedToday = true;
  late DateTime _calendarMonth;
  late DateTime _selectedCalendarDay;
  int _quoteIndex = DailyQuotes.todayIndex();
  String? _lastTopBarSignature;

  HabitProvider? _observedHabitProvider;
  int _habitRevision = 0;
  GoalProvider? _observedGoalProvider;
  int _goalRevision = 0;
  TimeAuditProvider? _observedTimeAuditProvider;
  int _timeAuditRevision = 0;

  _TodayListsCache? _listsCache;
  _TodayReportCache? _reportCache;
  _MiniCalendarCountsCache? _miniCalCountsCache;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _calendarMonth = DateTime(now.year, now.month, 1);
    _selectedCalendarDay = DateTime(now.year, now.month, now.day);
    _quickAddFocusNode.addListener(_handleQuickAddFocusChanged);
  }

  @override
  void dispose() {
    _observedHabitProvider?.removeListener(_onHabitProviderChanged);
    _observedGoalProvider?.removeListener(_onGoalProviderChanged);
    _observedTimeAuditProvider?.removeListener(_onTimeAuditProviderChanged);
    _quickAddFocusNode.removeListener(_handleQuickAddFocusChanged);
    _quickAddController.dispose();
    _quickAddFocusNode.dispose();
    super.dispose();
  }

  void _onHabitProviderChanged() {
    _habitRevision++;
  }

  void _onGoalProviderChanged() {
    _goalRevision++;
  }

  void _onTimeAuditProviderChanged() {
    _timeAuditRevision++;
  }

  void _observeProviders({
    required HabitProvider? habits,
    required GoalProvider? goals,
    required TimeAuditProvider? timeAudit,
  }) {
    if (!identical(_observedHabitProvider, habits)) {
      _observedHabitProvider?.removeListener(_onHabitProviderChanged);
      _observedHabitProvider = habits;
      _observedHabitProvider?.addListener(_onHabitProviderChanged);
      _habitRevision++;
    }
    if (!identical(_observedGoalProvider, goals)) {
      _observedGoalProvider?.removeListener(_onGoalProviderChanged);
      _observedGoalProvider = goals;
      _observedGoalProvider?.addListener(_onGoalProviderChanged);
      _goalRevision++;
    }
    if (!identical(_observedTimeAuditProvider, timeAudit)) {
      _observedTimeAuditProvider?.removeListener(_onTimeAuditProviderChanged);
      _observedTimeAuditProvider = timeAudit;
      _observedTimeAuditProvider?.addListener(_onTimeAuditProviderChanged);
      _timeAuditRevision++;
    }
  }

  void _handleQuickAddFocusChanged() {
    if (!mounted) return;
    final focused = _quickAddFocusNode.hasFocus;
    if (focused != _quickAddFocused) {
      setState(() => _quickAddFocused = focused);
    }
  }

  DesktopWebNavController? get _effectiveController =>
      widget.controller ?? DesktopWebScope.maybeOf(context);

  void _navigate(
    DesktopWebDestination destination, {
    DateTime? focusedDate,
    int? almanacTab,
  }) {
    if (widget.onNavigate != null) {
      if (focusedDate != null) {
        _effectiveController?.focusCalendarDate(focusedDate);
      }
      if (almanacTab != null) {
        _effectiveController?.setAlmanacTab(almanacTab);
      }
      widget.onNavigate!(destination);
      return;
    }
    _effectiveController?.navigateTo(
      destination,
      focusedDate: focusedDate,
      almanacTab: almanacTab,
    );
  }

  void _openTodo(String todoId) {
    if (widget.onOpenTodo != null) {
      widget.onOpenTodo!(todoId);
      return;
    }
    _effectiveController?.navigateTo(
      DesktopWebDestination.todo,
      selectedTodoId: todoId,
    );
  }

  void _launchFocus({
    PomodoroProvider? pomodoro,
    String? taskTitle,
    int minutes = 25,
  }) {
    if (pomodoro != null) {
      final cleanTask = taskTitle?.trim();
      if (cleanTask != null && cleanTask.isNotEmpty) {
        pomodoro.setTaskName(cleanTask);
      }
      final state = pomodoro.state;
      final targetSeconds = minutes * 60;
      if (!state.isRunning) {
        if (pomodoro.effectiveFocusDuration == targetSeconds &&
            state.type == PomodoroType.focus &&
            !state.isCountUp) {
          pomodoro.startIfIdle();
        } else {
          unawaited(() async {
            if (state.isCountUp) {
              pomodoro.setCountUpMode(false);
            }
            await pomodoro.setFocusDuration(targetSeconds);
            if (!mounted) return;
            pomodoro.startIfIdle();
          }());
        }
      }
    }
    if (widget.onStartFocus != null) {
      widget.onStartFocus!(taskTitle: taskTitle);
      return;
    }
    _navigate(DesktopWebDestination.focus);
  }

  T? _watchOptional<T>(BuildContext context) {
    try {
      return Provider.of<T>(context);
    } on ProviderNotFoundException {
      return null;
    }
  }

  T? _readOptional<T>(BuildContext context) {
    try {
      return Provider.of<T>(context, listen: false);
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

  _TodayListsCache _listsFor({
    required DateTime now,
    required int minuteKey,
    required TodoProvider? todoProvider,
    required HabitProvider? habitProvider,
    required GoalProvider? goalProvider,
  }) {
    final todoRevision = todoProvider?.revision ?? -1;
    final cached = _listsCache;
    if (cached != null &&
        cached.minuteKey == minuteKey &&
        identical(cached.todoProvider, todoProvider) &&
        cached.todoRevision == todoRevision &&
        identical(cached.habitProvider, habitProvider) &&
        cached.habitRevision == _habitRevision &&
        identical(cached.goalProvider, goalProvider) &&
        cached.goalRevision == _goalRevision) {
      return cached;
    }

    final allTodos = todoProvider?.todos ?? const <TodoItem>[];
    final todayOverview = allTodos
        .where((t) => CompletionVisibilityPolicy.isInTodayOverview(t, now))
        .toList(growable: false);
    final pendingToday = <TodoItem>[];
    final doneToday = <TodoItem>[];
    for (final t in todayOverview) {
      if (t.isCompleted) {
        doneToday.add(t);
      } else {
        pendingToday.add(t);
      }
    }
    pendingToday.sort((a, b) => _compareTodos(a, b, now));
    doneToday.sort(
      (a, b) =>
          (b.completedAt ?? b.updatedAt).compareTo(a.completedAt ?? a.updatedAt),
    );

    final activeHabits = (habitProvider?.habits ?? const <Habit>[])
        .where((h) => h.isActiveToday())
        .toList(growable: false);
    final completedHabitsCount =
        activeHabits.where((h) => h.isCompletedToday()).length;
    final activeGoals = (goalProvider?.activeGoals ?? const <GoalItem>[])
        .toList(growable: false);

    final built = _TodayListsCache(
      minuteKey: minuteKey,
      todoProvider: todoProvider,
      todoRevision: todoRevision,
      habitProvider: habitProvider,
      habitRevision: _habitRevision,
      goalProvider: goalProvider,
      goalRevision: _goalRevision,
      allTodos: allTodos,
      todayTotal: todayOverview.length,
      pendingToday: List<TodoItem>.unmodifiable(pendingToday),
      doneToday: List<TodoItem>.unmodifiable(doneToday),
      activeHabits: List<Habit>.unmodifiable(activeHabits),
      completedHabitsCount: completedHabitsCount,
      activeGoals: List<GoalItem>.unmodifiable(activeGoals),
    );
    _listsCache = built;
    return built;
  }

  _TodayReportCache _reportsFor({
    required DateTime today,
    required int dayKey,
    required TodoProvider? todoProvider,
    required HabitProvider? habitProvider,
    required PomodoroProvider? pomodoro,
    required int pomodoroPersistedRev,
    required TimeAuditProvider? timeAudit,
  }) {
    final todoRevision = todoProvider?.revision ?? -1;
    final cached = _reportCache;
    if (cached != null &&
        cached.dayKey == dayKey &&
        identical(cached.todoProvider, todoProvider) &&
        cached.todoRevision == todoRevision &&
        identical(cached.habitProvider, habitProvider) &&
        cached.habitRevision == _habitRevision &&
        identical(cached.pomodoro, pomodoro) &&
        cached.pomodoroPersistedRev == pomodoroPersistedRev &&
        identical(cached.timeAudit, timeAudit) &&
        cached.timeAuditRevision == _timeAuditRevision) {
      return cached;
    }

    final weekStart = today.subtract(const Duration(days: 6));
    final prevEnd = weekStart.subtract(const Duration(days: 1));
    final prevStart = prevEnd.subtract(const Duration(days: 6));

    final allTodos = todoProvider?.todos ?? const <TodoItem>[];
    final habits = habitProvider?.habits ?? const <Habit>[];
    final sessions = pomodoro?.sessions ?? const <PomodoroSession>[];
    final timeEntries = timeAudit?.entries ?? const <TimeEntry>[];

    // Single pass computing both current 7-day report and previous 7-day baseline.
    final weekEndExcl = DateTime(today.year, today.month, today.day + 1);
    final prevEndExcl = DateTime(prevEnd.year, prevEnd.month, prevEnd.day + 1);

    bool inWeek(DateTime d) => !d.isBefore(weekStart) && d.isBefore(weekEndExcl);
    bool inPrev(DateTime d) => !d.isBefore(prevStart) && d.isBefore(prevEndExcl);

    var curCreated = 0;
    var curCompleted = 0;
    var prevCreated = 0;
    var prevCompleted = 0;
    for (final t in allTodos) {
      if (inWeek(t.createdAt)) {
        curCreated++;
      } else if (inPrev(t.createdAt)) {
        prevCreated++;
      }
      final c = t.completedAt;
      if (t.isCompleted && c != null) {
        if (inWeek(c)) {
          curCompleted++;
        } else if (inPrev(c)) {
          prevCompleted++;
        }
      }
    }

    var curHabitCheckIns = 0;
    var prevHabitCheckIns = 0;
    var longestStreak = 0;
    for (final h in habits) {
      for (final entry in h.completions.entries) {
        final d = _parseDateKey(entry.key);
        if (d == null) continue;
        if (inWeek(d)) {
          if (h.activeForDate(d)) curHabitCheckIns += entry.value;
        } else if (inPrev(d)) {
          if (h.activeForDate(d)) prevHabitCheckIns += entry.value;
        }
      }
      if (h.currentStreak > longestStreak) {
        longestStreak = h.currentStreak;
      }
    }

    var curFocusSessions = 0;
    var curFocusSeconds = 0;
    var prevFocusSessions = 0;
    var prevFocusSeconds = 0;
    for (final s in sessions) {
      if (s.type != PomodoroType.focus) continue;
      if (inWeek(s.endTime)) {
        curFocusSessions++;
        curFocusSeconds += s.durationSeconds;
      } else if (inPrev(s.endTime)) {
        prevFocusSessions++;
        prevFocusSeconds += s.durationSeconds;
      }
    }

    var curTimeSeconds = 0;
    var prevTimeSeconds = 0;
    final curByCategory = <TimeEntryCategory, int>{};
    final prevByCategory = <TimeEntryCategory, int>{};
    for (final e in timeEntries) {
      if (inWeek(e.startAt)) {
        curTimeSeconds += e.durationSeconds;
        curByCategory[e.category] =
            (curByCategory[e.category] ?? 0) + e.durationSeconds;
      } else if (inPrev(e.startAt)) {
        prevTimeSeconds += e.durationSeconds;
        prevByCategory[e.category] =
            (prevByCategory[e.category] ?? 0) + e.durationSeconds;
      }
    }

    final weeklyReport = PeriodReport(
      start: weekStart,
      end: today,
      todosCreated: curCreated,
      todosCompleted: curCompleted,
      habitCheckIns: curHabitCheckIns,
      longestHabitStreak: longestStreak,
      focusSessions: curFocusSessions,
      focusSeconds: curFocusSeconds,
      timeEntrySeconds: curTimeSeconds,
      timeEntryByCategory: curByCategory,
    );
    final prevReport = PeriodReport(
      start: prevStart,
      end: prevEnd,
      todosCreated: prevCreated,
      todosCompleted: prevCompleted,
      habitCheckIns: prevHabitCheckIns,
      longestHabitStreak: longestStreak,
      focusSessions: prevFocusSessions,
      focusSeconds: prevFocusSeconds,
      timeEntrySeconds: prevTimeSeconds,
      timeEntryByCategory: prevByCategory,
    );
    final comparison = ReportEngine.compare(
      current: weeklyReport,
      previous: prevReport,
    );

    final todayFocusSessions =
        pomodoro?.todayFocusSessions ?? const <PomodoroSession>[];
    final todayFocusMinutes = todayFocusSessions.fold<int>(
      0,
      (sum, s) => sum + (s.durationSeconds ~/ 60),
    );

    final built = _TodayReportCache(
      dayKey: dayKey,
      todoProvider: todoProvider,
      todoRevision: todoRevision,
      habitProvider: habitProvider,
      habitRevision: _habitRevision,
      pomodoro: pomodoro,
      pomodoroPersistedRev: pomodoroPersistedRev,
      timeAudit: timeAudit,
      timeAuditRevision: _timeAuditRevision,
      weeklyReport: weeklyReport,
      efficiencyDelta: comparison.productivityScore.difference.round(),
      todayFocusMinutes: todayFocusMinutes,
      todayFocusSessionsCount: todayFocusSessions.length,
    );
    _reportCache = built;
    return built;
  }

  static DateTime? _parseDateKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  Map<int, int> _miniCalendarTodoCounts({
    required TodoProvider? todoProvider,
    required List<TodoItem> allTodos,
    required DateTime month,
  }) {
    final rev = todoProvider?.revision ?? -1;
    final cached = _miniCalCountsCache;
    if (cached != null &&
        identical(cached.todoProvider, todoProvider) &&
        cached.todoRevision == rev &&
        cached.year == month.year &&
        cached.month == month.month) {
      return cached.countsByDay;
    }
    final counts = <int, int>{};
    for (final t in allTodos) {
      if (t.isCompleted || t.isArchivedAfterRollover) continue;
      final d = t.dueDate;
      if (d != null && d.year == month.year && d.month == month.month) {
        counts[d.day] = (counts[d.day] ?? 0) + 1;
      }
    }
    _miniCalCountsCache = _MiniCalendarCountsCache(
      todoProvider: todoProvider,
      todoRevision: rev,
      year: month.year,
      month: month.month,
      countsByDay: Map<int, int>.unmodifiable(counts),
    );
    return _miniCalCountsCache!.countsByDay;
  }

  void _syncTopBar({
    required AppLocale locale,
    required DateTime now,
    required bool isRunning,
    required PomodoroProvider? pomodoro,
  }) {
    final controller = _effectiveController;
    if (controller == null) return;
    final isEn = locale == AppLocale.en;
    final greeting = _greetingForHour(now.hour, isEn);
    final dateLabel = I18nDateFormat.monthDayWithWeekday(now);
    final sig = '${locale.name}|${now.year}-${now.month}-${now.day}|$greeting|$isRunning';
    if (_lastTopBarSignature == sig) return;
    _lastTopBarSignature = sig;
    controller.setTopBarSpec(
      DesktopWebDestination.today,
      DesktopTopBarSpec(
        title: greeting,
        subtitle: dateLabel,
        actions: [
          _TodayTopBarActionButton(
            icon: isRunning ? Icons.timelapse_rounded : Icons.play_arrow_rounded,
            label: isRunning
                ? (isEn ? 'Focusing' : '专注中')
                : (isEn ? '25m Focus' : '25分钟专注'),
            onTap: () => _launchFocus(pomodoro: pomodoro),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final dayKey = today.year * 10000 + today.month * 100 + today.day;
        final minuteKey = now.millisecondsSinceEpoch ~/ 60000;
        final isEn = locale == AppLocale.en;
        final tokens = DesktopWebTokens.of(context);

        final todoProvider = _watchOptional<TodoProvider>(context);
        final habitProvider = _watchOptional<HabitProvider>(context);
        final goalProvider = _watchOptional<GoalProvider>(context);
        final timeAudit = _watchOptional<TimeAuditProvider>(context);
        final share = _watchOptional<ShareProvider>(context);
        _observeProviders(
          habits: habitProvider,
          goals: goalProvider,
          timeAudit: timeAudit,
        );

        final (pomodoroPersistedRev, isFocusRunning) =
            _selectOptional<PomodoroProvider, (int, bool)>(
              context,
              (p) => (p?.persistedRevision ?? -1, p?.state.isRunning ?? false),
              (-1, false),
            );
        final pomodoro = _readOptional<PomodoroProvider>(context);

        final (firstDayOfWeek, showLunar) =
            _selectOptional<PreferencesProvider, (int, bool)>(
              context,
              (p) => (p?.firstDayOfWeek ?? DateTime.monday, p?.showLunar ?? true),
              (DateTime.monday, true),
            );
        final hasDiaryToday = _selectOptional<DiaryProvider, bool>(
          context,
          (p) => p?.entryForDate(today) != null,
          false,
        );

        _syncTopBar(
          locale: locale,
          now: now,
          isRunning: isFocusRunning,
          pomodoro: pomodoro,
        );

        final lists = _listsFor(
          now: now,
          minuteKey: minuteKey,
          todoProvider: todoProvider,
          habitProvider: habitProvider,
          goalProvider: goalProvider,
        );
        final reports = _reportsFor(
          today: today,
          dayKey: dayKey,
          todoProvider: todoProvider,
          habitProvider: habitProvider,
          pomodoro: pomodoro,
          pomodoroPersistedRev: pomodoroPersistedRev,
          timeAudit: timeAudit,
        );

        final allTodos = lists.allTodos;
        final pendingToday = lists.pendingToday;
        final doneToday = lists.doneToday;
        final activeHabits = lists.activeHabits;
        final completedHabitsCount = lists.completedHabitsCount;
        final activeGoals = lists.activeGoals;
        final weeklyReport = reports.weeklyReport;
        final topTaskTitle =
            pendingToday.isNotEmpty ? pendingToday.first.title : null;

        return ColoredBox(
          color: Colors.transparent,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final horizontalPadding = width >= 1120 ? 28.0 : 16.0;
              final twoColumn = width >= 900;

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  18,
                  horizontalPadding,
                  28,
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: DesktopWebTokens.contentMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_effectiveController == null) ...[
                          _buildStandaloneHeader(
                            tokens: tokens,
                            isEn: isEn,
                            now: now,
                          ),
                          const SizedBox(height: 14),
                        ],
                        _buildKpiStrip(
                          tokens: tokens,
                          isEn: isEn,
                          availableWidth: width - (horizontalPadding * 2),
                          todoDone: doneToday.length,
                          todoTotal: lists.todayTotal,
                          habitDone: completedHabitsCount,
                          habitTotal: activeHabits.length,
                          focusMinutes: reports.todayFocusMinutes,
                          focusSessionsCount: reports.todayFocusSessionsCount,
                          efficiencyScore: weeklyReport.productivityScore,
                          efficiencyDelta: reports.efficiencyDelta,
                        ),
                        const SizedBox(height: 18),
                        if (twoColumn)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 62,
                                child: _buildMainColumn(
                                  tokens: tokens,
                                  isEn: isEn,
                                  now: now,
                                  today: today,
                                  todoProvider: todoProvider,
                                  habitProvider: habitProvider,
                                  pomodoro: pomodoro,
                                  share: share,
                                  pendingToday: pendingToday,
                                  doneToday: doneToday,
                                  activeHabits: activeHabits,
                                  activeGoals: activeGoals,
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                flex: 38,
                                child: _buildInspectorColumn(
                                  tokens: tokens,
                                  isEn: isEn,
                                  locale: locale,
                                  today: today,
                                  todoProvider: todoProvider,
                                  allTodos: allTodos,
                                  pomodoro: pomodoro,
                                  firstDayOfWeek: firstDayOfWeek,
                                  showLunar: showLunar,
                                  weeklyReport: weeklyReport,
                                  topTaskTitle: topTaskTitle,
                                  hasDiaryToday: hasDiaryToday,
                                ),
                              ),
                            ],
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildMainColumn(
                                tokens: tokens,
                                isEn: isEn,
                                now: now,
                                today: today,
                                todoProvider: todoProvider,
                                habitProvider: habitProvider,
                                pomodoro: pomodoro,
                                share: share,
                                pendingToday: pendingToday,
                                doneToday: doneToday,
                                activeHabits: activeHabits,
                                activeGoals: activeGoals,
                              ),
                              const SizedBox(height: 18),
                              _buildInspectorColumn(
                                tokens: tokens,
                                isEn: isEn,
                                locale: locale,
                                today: today,
                                todoProvider: todoProvider,
                                allTodos: allTodos,
                                pomodoro: pomodoro,
                                firstDayOfWeek: firstDayOfWeek,
                                showLunar: showLunar,
                                weeklyReport: weeklyReport,
                                topTaskTitle: topTaskTitle,
                                hasDiaryToday: hasDiaryToday,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildStandaloneHeader({
    required DesktopWebTokens tokens,
    required bool isEn,
    required DateTime now,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_greetingForHour(now.hour, isEn), style: tokens.heroTitleStyle),
              const SizedBox(height: 2),
              Text(
                I18nDateFormat.monthDayWithWeekday(now),
                style: tokens.bodyMutedStyle,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKpiStrip({
    required DesktopWebTokens tokens,
    required bool isEn,
    required double availableWidth,
    required int todoDone,
    required int todoTotal,
    required int habitDone,
    required int habitTotal,
    required int focusMinutes,
    required int focusSessionsCount,
    required int efficiencyScore,
    required int efficiencyDelta,
  }) {
    final todoSub = todoTotal == 0
        ? (isEn ? 'Clear schedule' : '今日暂无待办')
        : (todoDone == todoTotal
              ? (isEn ? 'All cleared' : '已全部完成')
              : (isEn ? '${todoTotal - todoDone} remaining' : '剩余 ${todoTotal - todoDone} 项'));

    final habitPct = habitTotal == 0 ? 0 : ((habitDone / habitTotal) * 100).round();
    final habitSub = habitTotal == 0
        ? (isEn ? 'No active habits' : '暂无活跃习惯')
        : (isEn ? '$habitPct% completion' : '完成率 $habitPct%');

    final focusSub = isEn
        ? '$focusSessionsCount ${focusSessionsCount == 1 ? 'session' : 'sessions'} today'
        : '今日 $focusSessionsCount 次专注';

    final deltaSign = efficiencyDelta > 0 ? '+' : '';
    final effSub = isEn
        ? '${efficiencyDelta == 0 ? 'Steady' : '$deltaSign$efficiencyDelta'} vs last week'
        : (efficiencyDelta == 0 ? '较上周持平' : '较上周 $deltaSign$efficiencyDelta');

    final cards = [
      _KpiCardData(
        icon: Icons.check_circle_outline_rounded,
        iconColor: tokens.accent,
        label: isEn ? "Today's Todos" : '今日待办',
        value: '$todoDone/$todoTotal',
        subtitle: todoSub,
        progress: todoTotal > 0 ? (todoDone / todoTotal).clamp(0.0, 1.0) : 0.0,
        onTap: () => _navigate(DesktopWebDestination.todo),
      ),
      _KpiCardData(
        icon: Icons.repeat_rounded,
        iconColor: tokens.success,
        label: isEn ? 'Habits Checked' : '习惯打卡',
        value: '$habitDone/$habitTotal',
        subtitle: habitSub,
        progress: habitTotal > 0 ? (habitDone / habitTotal).clamp(0.0, 1.0) : 0.0,
        onTap: () => _navigate(DesktopWebDestination.habit),
      ),
      _KpiCardData(
        icon: Icons.timer_outlined,
        iconColor: tokens.info,
        label: isEn ? 'Focus Time' : '今日专注',
        value: isEn ? '${focusMinutes}m' : '$focusMinutes分钟',
        subtitle: focusSub,
        progress: (focusMinutes / 90).clamp(0.0, 1.0),
        onTap: () => _navigate(DesktopWebDestination.focus),
      ),
      _KpiCardData(
        icon: Icons.insights_rounded,
        iconColor: tokens.warning,
        label: isEn ? 'Efficiency' : '效率评分',
        value: '$efficiencyScore',
        valueSuffix: '/100',
        subtitle: effSub,
        progress: (efficiencyScore / 100).clamp(0.0, 1.0),
        onTap: () => _navigate(DesktopWebDestination.stats),
      ),
    ];

    if (availableWidth >= 760) {
      return Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            Expanded(child: _TodayKpiCard(data: cards[i], tokens: tokens)),
            if (i < cards.length - 1) const SizedBox(width: 12),
          ],
        ],
      );
    }

    if (availableWidth >= 460) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: _TodayKpiCard(data: cards[0], tokens: tokens)),
              const SizedBox(width: 12),
              Expanded(child: _TodayKpiCard(data: cards[1], tokens: tokens)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _TodayKpiCard(data: cards[2], tokens: tokens)),
              const SizedBox(width: 12),
              Expanded(child: _TodayKpiCard(data: cards[3], tokens: tokens)),
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          _TodayKpiCard(data: cards[i], tokens: tokens),
          if (i < cards.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildMainColumn({
    required DesktopWebTokens tokens,
    required bool isEn,
    required DateTime now,
    required DateTime today,
    required TodoProvider? todoProvider,
    required HabitProvider? habitProvider,
    required PomodoroProvider? pomodoro,
    required ShareProvider? share,
    required List<TodoItem> pendingToday,
    required List<TodoItem> doneToday,
    required List<Habit> activeHabits,
    required List<GoalItem> activeGoals,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildQuickAddBar(
          tokens: tokens,
          isEn: isEn,
          now: now,
          today: today,
          todoProvider: todoProvider,
        ),
        const SizedBox(height: 16),
        _buildTodayTodoPanel(
          tokens: tokens,
          isEn: isEn,
          now: now,
          todoProvider: todoProvider,
          pomodoro: pomodoro,
          share: share,
          pendingToday: pendingToday,
          doneToday: doneToday,
        ),
        const SizedBox(height: 16),
        _buildTodayHabitsPanel(
          tokens: tokens,
          isEn: isEn,
          habitProvider: habitProvider,
          activeHabits: activeHabits,
        ),
        const SizedBox(height: 16),
        _buildActiveGoalsPanel(
          tokens: tokens,
          isEn: isEn,
          activeGoals: activeGoals,
        ),
      ],
    );
  }

  Widget _buildQuickAddBar({
    required DesktopWebTokens tokens,
    required bool isEn,
    required DateTime now,
    required DateTime today,
    required TodoProvider? todoProvider,
  }) {
    final priorityColor = _priorityColor(_quickPriority, tokens);
    return DesktopPanelCard(
      frosted: tokens.isLiquidGlass,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      border: Border.all(
        color: _quickAddFocused
            ? tokens.accentBorder
            : tokens.hairlineBorder,
        width: DesktopWebTokens.hairlineWidth,
      ),
      child: Row(
        children: [
          Icon(
            Icons.add_circle_outline_rounded,
            size: 20,
            color: _quickAddFocused ? tokens.accent : tokens.textMuted,
          ),
          const SizedBox(width: 10),
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
                    ? "Quick add today's todo, press Enter..."
                    : '快速添加今日待办，按 Enter 创建...',
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
          const SizedBox(width: 8),
          Tooltip(
            message: isEn ? 'Priority' : '优先级',
            child: InkWell(
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
              onTap: () {
                setState(() {
                  _quickPriority = _nextQuickPriority(_quickPriority);
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: _quickPriority == TodoPriority.none
                      ? tokens.mutedSurface
                      : priorityColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
                  border: Border.all(
                    color: _quickPriority == TodoPriority.none
                        ? tokens.hairlineBorder
                        : priorityColor.withValues(alpha: 0.4),
                    width: DesktopWebTokens.hairlineWidth,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.flag_outlined,
                      size: 13,
                      color: _quickPriority == TodoPriority.none
                          ? tokens.textMuted
                          : priorityColor,
                    ),
                    if (_quickPriority != TodoPriority.none) ...[
                      const SizedBox(width: 4),
                      Text(
                        _priorityShortLabel(_quickPriority, isEn),
                        style: tokens.captionStyle.copyWith(color: priorityColor),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
            onTap: () => _submitQuickAdd(
              todoProvider: todoProvider,
              now: now,
              today: today,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: tokens.accentSoft,
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                border: Border.all(
                  color: tokens.accentBorder,
                  width: DesktopWebTokens.hairlineWidth,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isEn ? 'Add' : '创建',
                    style: tokens.captionStyle.copyWith(color: tokens.accent),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.keyboard_return_rounded, size: 13, color: tokens.accent),
                ],
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
    final raw = _quickAddController.text.trim();
    if (raw.isEmpty || todoProvider == null) return;
    final draft = SmartTodoDraftBuilder.fromText(raw, now: now);
    final baseTodo = draft.toTodo(priority: _quickPriority);
    final effectiveDue = draft.dueDate ?? today;
    final todo = baseTodo.copyWith(
      date: today,
      dueDate: effectiveDue,
    );
    _quickAddController.clear();
    setState(() => _quickPriority = TodoPriority.none);
    unawaited(todoProvider.addTodo(todo, waitForReminderSync: false));
  }

  Widget _buildTodayTodoPanel({
    required DesktopWebTokens tokens,
    required bool isEn,
    required DateTime now,
    required TodoProvider? todoProvider,
    required PomodoroProvider? pomodoro,
    required ShareProvider? share,
    required List<TodoItem> pendingToday,
    required List<TodoItem> doneToday,
  }) {
    final overdueCount = pendingToday
        .where((t) => CompletionVisibilityPolicy.visualState(t, now: now) == TodoVisualState.overdue)
        .length;

    return DesktopPanelCard(
      frosted: tokens.isLiquidGlass,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  isEn ? "Today's Tasks" : '今日待办',
                  style: tokens.cardTitleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _CountPill(
                label: '${pendingToday.length}',
                color: tokens.accent,
                tokens: tokens,
              ),
              if (overdueCount > 0) ...[
                const SizedBox(width: 6),
                _CountPill(
                  label: isEn ? '$overdueCount overdue' : '$overdueCount 逾期',
                  color: tokens.danger,
                  tokens: tokens,
                ),
              ],
              const Spacer(),
              _InlineLinkButton(
                label: isEn ? 'Open Workspace' : '进入待办工作区',
                tokens: tokens,
                onTap: () => _navigate(DesktopWebDestination.todo),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (pendingToday.isEmpty && doneToday.isEmpty)
            _buildEmptyTodayTodos(tokens: tokens, isEn: isEn)
          else ...[
            for (var i = 0; i < pendingToday.length; i++) ...[
              _TodayChecklistRow(
                todo: pendingToday[i],
                now: now,
                isEn: isEn,
                tokens: tokens,
                canEdit: share?.canEdit(pendingToday[i].workspaceId) ?? true,
                onToggle: () {
                  todoProvider?.toggleTodo(
                    pendingToday[i].id,
                    recordCompletionTime: false,
                  );
                },
                onOpen: () => _openTodo(pendingToday[i].id),
                onFocus: () => _launchFocus(
                  pomodoro: pomodoro,
                  taskTitle: pendingToday[i].title,
                ),
              ),
              if (i < pendingToday.length - 1)
                Divider(height: 1, thickness: DesktopWebTokens.hairlineWidth, color: tokens.hairlineBorder),
            ],
            if (doneToday.isNotEmpty) ...[
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXs),
                onTap: () => setState(() => _showCompletedToday = !_showCompletedToday),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Row(
                    children: [
                      Icon(
                        _showCompletedToday
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_right_rounded,
                        size: 16,
                        color: tokens.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isEn
                            ? 'Completed today (${doneToday.length})'
                            : '今日已完成 (${doneToday.length})',
                        style: tokens.captionStyle,
                      ),
                    ],
                  ),
                ),
              ),
              if (_showCompletedToday)
                for (var i = 0; i < doneToday.length; i++) ...[
                  _TodayChecklistRow(
                    todo: doneToday[i],
                    now: now,
                    isEn: isEn,
                    tokens: tokens,
                    canEdit: share?.canEdit(doneToday[i].workspaceId) ?? true,
                    onToggle: () {
                      todoProvider?.toggleTodo(
                        doneToday[i].id,
                        recordCompletionTime: false,
                      );
                    },
                    onOpen: () => _openTodo(doneToday[i].id),
                    onFocus: () => _launchFocus(
                      pomodoro: pomodoro,
                      taskTitle: doneToday[i].title,
                    ),
                  ),
                  if (i < doneToday.length - 1)
                    Divider(
                      height: 1,
                      thickness: DesktopWebTokens.hairlineWidth,
                      color: tokens.hairlineBorder,
                    ),
                ],
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyTodayTodos({
    required DesktopWebTokens tokens,
    required bool isEn,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      alignment: Alignment.center,
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
              border: Border.all(
                color: tokens.accentBorder.withValues(alpha: 0.45),
                width: DesktopWebTokens.hairlineWidth,
              ),
            ),
            child: Icon(
              Icons.task_alt_rounded,
              size: 22,
              color: tokens.accent,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            isEn
                ? 'Nothing scheduled for today yet. Use the bar above to add a task.'
                : '今日待办已清空，直接在上方输入框添加一条新任务吧。',
            style: tokens.bodyMutedStyle,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTodayHabitsPanel({
    required DesktopWebTokens tokens,
    required bool isEn,
    required HabitProvider? habitProvider,
    required List<Habit> activeHabits,
  }) {
    final doneCount = activeHabits.where((h) => h.isCompletedToday()).length;
    return DesktopPanelCard(
      frosted: tokens.isLiquidGlass,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  isEn ? "Today's Habits" : '今日习惯打卡',
                  style: tokens.cardTitleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _CountPill(
                label: '$doneCount/${activeHabits.length}',
                color: tokens.success,
                tokens: tokens,
              ),
              const Spacer(),
              _InlineLinkButton(
                label: isEn ? 'Habit Matrix' : '全部习惯',
                tokens: tokens,
                onTap: () => _navigate(DesktopWebDestination.habit),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (activeHabits.isEmpty)
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.success.withValues(
                      alpha: tokens.isDark ? 0.16 : 0.10,
                    ),
                    borderRadius: BorderRadius.circular(
                      DesktopWebTokens.radiusSm,
                    ),
                  ),
                  child: Icon(
                    Icons.repeat_rounded,
                    size: 16,
                    color: tokens.success,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isEn
                        ? 'Build consistent daily routines from Habit templates.'
                        : '暂无今日习惯，可前往习惯看板一键开启模板。',
                    style: tokens.bodyMutedStyle,
                  ),
                ),
                const SizedBox(width: 8),
                _InlineLinkButton(
                  label: isEn ? 'Explore' : '去创建',
                  tokens: tokens,
                  onTap: () => _navigate(DesktopWebDestination.habit),
                ),
              ],
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final habit in activeHabits)
                  _HabitQuickPill(
                    habit: habit,
                    tokens: tokens,
                    onTap: () {
                      habitProvider?.incrementHabit(habit.id);
                    },
                    onUndo: habit.todayCount() > 0
                        ? () => habitProvider?.decrementHabit(habit.id)
                        : null,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildActiveGoalsPanel({
    required DesktopWebTokens tokens,
    required bool isEn,
    required List<GoalItem> activeGoals,
  }) {
    final visibleGoals = activeGoals.take(4).toList(growable: false);
    return DesktopPanelCard(
      frosted: tokens.isLiquidGlass,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  isEn ? 'Active Goals' : '进行中的目标',
                  style: tokens.cardTitleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _CountPill(
                label: '${activeGoals.length}',
                color: tokens.warning,
                tokens: tokens,
              ),
              const Spacer(),
              _InlineLinkButton(
                label: isEn ? 'Manage Goals' : '管理目标',
                tokens: tokens,
                onTap: () => _navigate(DesktopWebDestination.goals),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (visibleGoals.isEmpty)
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.warning.withValues(
                      alpha: tokens.isDark ? 0.16 : 0.11,
                    ),
                    borderRadius: BorderRadius.circular(
                      DesktopWebTokens.radiusSm,
                    ),
                  ),
                  child: Icon(
                    Icons.flag_outlined,
                    size: 16,
                    color: tokens.warning,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isEn
                        ? 'No active goals yet. Set long-term milestones to stay aligned.'
                        : '暂无进行中的目标，前往目标管理设定阶段里程碑。',
                    style: tokens.bodyMutedStyle,
                  ),
                ),
                const SizedBox(width: 8),
                _InlineLinkButton(
                  label: isEn ? 'Set Goal' : '去设定',
                  tokens: tokens,
                  onTap: () => _navigate(DesktopWebDestination.goals),
                ),
              ],
            )
          else
            Column(
              children: [
                for (var i = 0; i < visibleGoals.length; i++) ...[
                  _GoalProgressRow(
                    goal: visibleGoals[i],
                    tokens: tokens,
                    isEn: isEn,
                    onTap: () => _navigate(DesktopWebDestination.goals),
                  ),
                  if (i < visibleGoals.length - 1)
                    Divider(
                      height: 16,
                      thickness: DesktopWebTokens.hairlineWidth,
                      color: tokens.hairlineBorder,
                    ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildInspectorColumn({
    required DesktopWebTokens tokens,
    required bool isEn,
    required AppLocale locale,
    required DateTime today,
    required TodoProvider? todoProvider,
    required List<TodoItem> allTodos,
    required PomodoroProvider? pomodoro,
    required int firstDayOfWeek,
    required bool showLunar,
    required PeriodReport weeklyReport,
    required String? topTaskTitle,
    required bool hasDiaryToday,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFocusLauncherCard(
          tokens: tokens,
          isEn: isEn,
          pomodoro: pomodoro,
          topTaskTitle: topTaskTitle,
        ),
        const SizedBox(height: 14),
        _buildMiniCalendarCard(
          tokens: tokens,
          isEn: isEn,
          today: today,
          todoProvider: todoProvider,
          allTodos: allTodos,
          firstDayOfWeek: firstDayOfWeek,
        ),
        const SizedBox(height: 14),
        _buildAlmanacCard(
          tokens: tokens,
          isEn: isEn,
          locale: locale,
          date: _selectedCalendarDay,
          showLunar: showLunar,
        ),
        const SizedBox(height: 14),
        _buildWeeklyEfficiencyCard(
          tokens: tokens,
          isEn: isEn,
          report: weeklyReport,
        ),
        const SizedBox(height: 14),
        _buildQuoteCard(
          tokens: tokens,
          isEn: isEn,
          locale: locale,
          hasDiaryToday: hasDiaryToday,
        ),
      ],
    );
  }

  Widget _buildFocusLauncherCard({
    required DesktopWebTokens tokens,
    required bool isEn,
    required PomodoroProvider? pomodoro,
    required String? topTaskTitle,
  }) {
    return _TodayFocusLauncherCard(
      tokens: tokens,
      isEn: isEn,
      pomodoro: pomodoro,
      topTaskTitle: topTaskTitle,
      onLaunchFocus: (linkedTask) => _launchFocus(
        pomodoro: pomodoro,
        taskTitle: linkedTask,
      ),
    );
  }

  Widget _buildMiniCalendarCard({
    required DesktopWebTokens tokens,
    required bool isEn,
    required DateTime today,
    required TodoProvider? todoProvider,
    required List<TodoItem> allTodos,
    required int firstDayOfWeek,
  }) {
    final weekdays = CalendarDateNavigation.orderedWeekdays(firstDayOfWeek);
    final monthFirst = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    final firstIndexOffset =
        (monthFirst.weekday - CalendarDateNavigation.normalizeFirstDayOfWeek(firstDayOfWeek)) % 7;
    final daysInMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0).day;
    final totalCells = ((firstIndexOffset + daysInMonth + 6) ~/ 7) * 7;

    final todoCountsByDay = _miniCalendarTodoCounts(
      todoProvider: todoProvider,
      allTodos: allTodos,
      month: _calendarMonth,
    );

    final int selectedCount;
    if (_selectedCalendarDay.year == _calendarMonth.year &&
        _selectedCalendarDay.month == _calendarMonth.month) {
      selectedCount = todoCountsByDay[_selectedCalendarDay.day] ?? 0;
    } else {
      selectedCount = allTodos.where((t) {
        if (t.isArchivedAfterRollover || t.isCompleted) return false;
        final due = t.dueDate;
        if (due == null) return false;
        return due.year == _selectedCalendarDay.year &&
            due.month == _selectedCalendarDay.month &&
            due.day == _selectedCalendarDay.day;
      }).length;
    }

    return DesktopPanelCard(
      frosted: tokens.isLiquidGlass,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  I18nDateFormat.yearMonth(_calendarMonth),
                  style: tokens.cardTitleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              _IconSquareBtn(
                icon: Icons.chevron_left_rounded,
                tokens: tokens,
                onTap: () {
                  setState(() {
                    _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1, 1);
                  });
                },
              ),
              const SizedBox(width: 4),
              InkWell(
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXs),
                onTap: () {
                  setState(() {
                    _calendarMonth = DateTime(today.year, today.month, 1);
                    _selectedCalendarDay = today;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Text(
                    isEn ? 'Today' : '今',
                    style: tokens.captionStyle.copyWith(color: tokens.accent),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _IconSquareBtn(
                icon: Icons.chevron_right_rounded,
                tokens: tokens,
                onTap: () {
                  setState(() {
                    _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 1);
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final wd in weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      _shortWeekdayLabel(wd, isEn),
                      style: tokens.captionStyle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var row = 0; row < totalCells ~/ 7; row++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                children: [
                  for (var col = 0; col < 7; col++)
                    Expanded(
                      child: _buildMiniCalDayCell(
                        tokens: tokens,
                        cellIndex: row * 7 + col,
                        firstIndexOffset: firstIndexOffset,
                        daysInMonth: daysInMonth,
                        today: today,
                        todoCountsByDay: todoCountsByDay,
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Divider(height: 1, thickness: DesktopWebTokens.hairlineWidth, color: tokens.hairlineBorder),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  isEn
                      ? '${I18nDateFormat.monthDay(_selectedCalendarDay)} · $selectedCount due'
                      : '${I18nDateFormat.monthDay(_selectedCalendarDay)} · $selectedCount 项截止',
                  style: tokens.captionStyle,
                ),
              ),
              _InlineLinkButton(
                label: isEn ? 'Calendar' : '完整日历',
                tokens: tokens,
                onTap: () => _navigate(
                  DesktopWebDestination.calendar,
                  focusedDate: _selectedCalendarDay,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniCalDayCell({
    required DesktopWebTokens tokens,
    required int cellIndex,
    required int firstIndexOffset,
    required int daysInMonth,
    required DateTime today,
    required Map<int, int> todoCountsByDay,
  }) {
    final dayNum = cellIndex - firstIndexOffset + 1;
    if (dayNum < 1 || dayNum > daysInMonth) {
      return const SizedBox(height: 28);
    }
    final date = DateTime(_calendarMonth.year, _calendarMonth.month, dayNum);
    final isToday = date == today;
    final isSelected = date == _selectedCalendarDay;
    final hasDot = (todoCountsByDay[dayNum] ?? 0) > 0;

    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXs),
        onTap: () => setState(() => _selectedCalendarDay = date),
        child: Container(
          width: 32,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isToday
                ? tokens.accent
                : (isSelected ? tokens.selectedSurface : Colors.transparent),
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXs),
            border: isSelected && !isToday
                ? Border.all(
                    color: tokens.accentBorder,
                    width: DesktopWebTokens.hairlineWidth,
                  )
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$dayNum',
                style: tokens.captionStyle.copyWith(
                  color: isToday
                      ? tokens.accentForeground
                      : (isSelected ? tokens.accent : tokens.textPrimary),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (hasDot)
                Container(
                  margin: const EdgeInsets.only(top: 1),
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isToday ? tokens.accentForeground : tokens.accent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlmanacCard({
    required DesktopWebTokens tokens,
    required bool isEn,
    required AppLocale locale,
    required DateTime date,
    required bool showLunar,
  }) {
    final lunar = LunarCalendar.tryFromSolar(date) ?? LunarCalendar.fromSolar(date);
    final detail = LunarCalendar.tryAlmanacDetail(date);
    final lunarLabel = AlmanacLocaleFormat.formatLunarDate(lunar, locale);
    final solarTerm = AlmanacLocaleFormat.formatSolarTerm(
      LunarCalendar.solarTerm(date),
      locale,
    );
    final rawFestival =
        LunarCalendar.lunarFestival(lunar) ?? LunarCalendar.solarFestival(date);
    final festival = AlmanacLocaleFormat.formatFestival(rawFestival, locale);
    final yiRaw = detail?.suitable ?? LunarCalendar.suitable(date);
    final jiRaw = detail?.avoid ?? LunarCalendar.avoid(date);
    final yiText = AlmanacLocaleFormat.formatActivitiesPreview(
      yiRaw,
      maxTerms: 3,
      locale: locale,
    );
    final jiText = AlmanacLocaleFormat.formatActivitiesPreview(
      jiRaw,
      maxTerms: 3,
      locale: locale,
    );

    final badge = festival ?? solarTerm;
    final isHoliday = HolidayCalendar.isHoliday(date);
    final isMakeup = !isHoliday && HolidayCalendar.isWorkMakeupDay(date);
    final holidayTitle = HolidayCalendar.holidayName(date, locale: locale);
    final nextHoliday = HolidayCalendar.nextHoliday(date);
    final daysToNext = nextHoliday?.daysUntil(date);

    final String? statusPillLabel;
    final Color statusPillColor;
    if (isHoliday) {
      statusPillLabel = holidayTitle == null
          ? AlmanacUiCopy.holidayTag
          : '${AlmanacUiCopy.holidayTag} · $holidayTitle';
      statusPillColor = tokens.success;
    } else if (isMakeup) {
      statusPillLabel = AlmanacUiCopy.makeupWorkdayBadge;
      statusPillColor = tokens.warning;
    } else if (nextHoliday != null && daysToNext != null) {
      final hName = nextHoliday.localizedName(locale);
      if (daysToNext <= 0) {
        statusPillLabel = isEn ? '$hName ongoing' : '$hName 放假中';
      } else {
        statusPillLabel = isEn
            ? '$hName in ${daysToNext}d'
            : '距$hName $daysToNext天';
      }
      statusPillColor = tokens.accent;
    } else {
      statusPillLabel = null;
      statusPillColor = tokens.accent;
    }

    return DesktopPanelCard(
      key: const ValueKey('desktop_today_almanac_card'),
      frosted: tokens.isLiquidGlass,
      padding: const EdgeInsets.all(14),
      onTap: () => _navigate(
        DesktopWebDestination.almanac,
        focusedDate: date,
        almanacTab: 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.wb_twilight_rounded, size: 15, color: tokens.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  showLunar
                      ? (isEn ? 'Lunar · $lunarLabel' : '农历 $lunarLabel')
                      : (isEn ? 'Daily Almanac' : '今日黄历'),
                  style: tokens.bodyStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                _CountPill(
                  label: badge,
                  color: tokens.warning,
                  tokens: tokens,
                ),
              ],
            ],
          ),
          if (statusPillLabel != null || (showLunar && detail != null)) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (statusPillLabel != null) ...[
                  Flexible(
                    child: _CountPill(
                      label: statusPillLabel,
                      color: statusPillColor,
                      tokens: tokens,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (showLunar && detail != null)
                  Expanded(
                    child: Text(
                      '${AlmanacLocaleFormat.formatTianShenType(detail.tianShenType, locale)} · '
                      '${AlmanacLocaleFormat.formatTianShen(detail.tianShen, locale)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.captionStyle.copyWith(
                        color: detail.isHuangDao
                            ? tokens.success
                            : tokens.textMuted,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                const SizedBox(width: 6),
                Text(
                  isEn ? 'Almanac' : '万年历',
                  style: tokens.captionStyle.copyWith(color: tokens.accent),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: tokens.accent,
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AlmanacTag(
                label: isEn ? 'Fit' : '宜',
                color: tokens.success,
                isEn: isEn,
                tokens: tokens,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  yiText.isEmpty ? (isEn ? 'Steady progress' : '诸事平稳') : yiText,
                  style: tokens.bodyMutedStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AlmanacTag(
                label: isEn ? 'Avoid' : '忌',
                color: tokens.danger,
                isEn: isEn,
                tokens: tokens,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  jiText.isEmpty ? (isEn ? 'Overwork' : '过度劳累') : jiText,
                  style: tokens.bodyMutedStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyEfficiencyCard({
    required DesktopWebTokens tokens,
    required bool isEn,
    required PeriodReport report,
  }) {
    final score = report.productivityScore.clamp(0, 100);
    return DesktopPanelCard(
      frosted: tokens.isLiquidGlass,
      padding: const EdgeInsets.all(14),
      onTap: () => _navigate(DesktopWebDestination.stats),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            height: 70,
            child: CustomPaint(
              painter: _EfficiencyRingPainter(
                progress: score / 100.0,
                trackColor: tokens.textPrimary.withValues(
                  alpha: tokens.isDark ? 0.12 : 0.08,
                ),
                fillColor: tokens.accent,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$score',
                      style: tokens.pageTitleStyle.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      isEn ? 'pts' : '分',
                      style: tokens.captionStyle,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEn ? '7-Day Efficiency' : '本周效率指数',
                  style: tokens.cardTitleStyle,
                ),
                const SizedBox(height: 6),
                Text(
                  isEn
                      ? '${report.todosCompleted} tasks · ${report.focusMinutes}m focus'
                      : '完成 ${report.todosCompleted} 项待办 · 专注 ${report.focusMinutes} 分钟',
                  style: tokens.bodyMutedStyle,
                ),
                const SizedBox(height: 2),
                Text(
                  isEn
                      ? '${report.habitCheckIns} habit check-ins'
                      : '习惯打卡 ${report.habitCheckIns} 次',
                  style: tokens.captionStyle,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: tokens.textMuted),
        ],
      ),
    );
  }

  Widget _buildQuoteCard({
    required DesktopWebTokens tokens,
    required bool isEn,
    required AppLocale locale,
    required bool hasDiaryToday,
  }) {
    final quote = DailyQuotes.at(_quoteIndex, locale: locale);
    return DesktopPanelCard(
      frosted: tokens.isLiquidGlass,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.format_quote_rounded, size: 16, color: tokens.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isEn ? 'Daily Quote' : '每日一句',
                  style: tokens.sectionHeaderStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasDiaryToday)
                InkWell(
                  borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
                  onTap: () => _navigate(DesktopWebDestination.diary),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      isEn ? 'Diary saved' : '今日已记日记',
                      style: tokens.captionStyle.copyWith(color: tokens.success),
                    ),
                  ),
                ),
              _IconSquareBtn(
                icon: Icons.refresh_rounded,
                tokens: tokens,
                onTap: () {
                  setState(() {
                    var next = DailyQuotes.randomIndex();
                    if (next == _quoteIndex && DailyQuotes.quotes.length > 1) {
                      next = (next + 1) % DailyQuotes.quotes.length;
                    }
                    _quoteIndex = next;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(quote, style: tokens.bodyStyle),
        ],
      ),
    );
  }

  static int _compareTodos(TodoItem a, TodoItem b, DateTime now) {
    final stateA = CompletionVisibilityPolicy.visualState(a, now: now);
    final stateB = CompletionVisibilityPolicy.visualState(b, now: now);
    final overdueRankA = stateA == TodoVisualState.overdue ? 0 : 1;
    final overdueRankB = stateB == TodoVisualState.overdue ? 0 : 1;
    if (overdueRankA != overdueRankB) return overdueRankA.compareTo(overdueRankB);

    final prioCmp = b.priority.rank.compareTo(a.priority.rank);
    if (prioCmp != 0) return prioCmp;

    final dueA = a.dueDate;
    final dueB = b.dueDate;
    if (dueA != null && dueB != null) {
      final d = dueA.compareTo(dueB);
      if (d != 0) return d;
    } else if (dueA != null) {
      return -1;
    } else if (dueB != null) {
      return 1;
    }
    return a.sortOrder.compareTo(b.sortOrder);
  }

  static String _greetingForHour(int hour, bool isEn) {
    if (hour < 12) return isEn ? 'Good morning' : '早安，今日清单';
    if (hour < 18) return isEn ? 'Good afternoon' : '午安，专注当下';
    return isEn ? 'Good evening' : '晚安，复盘今日';
  }

  static TodoPriority _nextQuickPriority(TodoPriority current) => switch (current) {
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

  static String _priorityShortLabel(TodoPriority p, bool isEn) => switch (p) {
    TodoPriority.urgent => isEn ? 'Urgent' : '紧急',
    TodoPriority.high => isEn ? 'High' : '高',
    TodoPriority.medium => isEn ? 'Med' : '中',
    TodoPriority.low => isEn ? 'Low' : '低',
    TodoPriority.none => '',
  };

  static String _shortWeekdayLabel(int isoWeekday, bool isEn) {
    if (isEn) {
      return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][isoWeekday - 1];
    }
    return const ['一', '二', '三', '四', '五', '六', '日'][isoWeekday - 1];
  }
}

class _KpiCardData {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String? valueSuffix;
  final String subtitle;
  final double progress;
  final VoidCallback onTap;

  const _KpiCardData({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.valueSuffix,
    required this.subtitle,
    required this.progress,
    required this.onTap,
  });
}

class _TodayKpiCard extends StatelessWidget {
  final _KpiCardData data;
  final DesktopWebTokens tokens;

  const _TodayKpiCard({required this.data, required this.tokens});

  @override
  Widget build(BuildContext context) {
    return DesktopPanelCard(
      frosted: tokens.isLiquidGlass,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: data.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: data.iconColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(data.icon, size: 14, color: data.iconColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  data.label,
                  style: tokens.bodyMutedStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.arrow_outward_rounded, size: 13, color: tokens.textMuted),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  data.value,
                  style: tokens.metricValueStyle.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (data.valueSuffix != null) ...[
                const SizedBox(width: 3),
                Text(data.valueSuffix!, style: tokens.captionStyle),
              ],
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: data.progress,
              minHeight: 3.5,
              backgroundColor: tokens.mutedSurface,
              valueColor: AlwaysStoppedAnimation<Color>(data.iconColor),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.subtitle,
            style: tokens.captionStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _TodayChecklistRow extends StatefulWidget {
  final TodoItem todo;
  final DateTime now;
  final bool isEn;
  final DesktopWebTokens tokens;
  final bool canEdit;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final VoidCallback onFocus;

  const _TodayChecklistRow({
    required this.todo,
    required this.now,
    required this.isEn,
    required this.tokens,
    required this.canEdit,
    required this.onToggle,
    required this.onOpen,
    required this.onFocus,
  });

  @override
  State<_TodayChecklistRow> createState() => _TodayChecklistRowState();
}

class _TodayChecklistRowState extends State<_TodayChecklistRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.todo;
    final tokens = widget.tokens;
    final visual = CompletionVisibilityPolicy.visualState(t, now: widget.now);
    final prioColor = _DesktopTodayViewState._priorityColor(t.priority, tokens);
    final dueColor = switch (visual) {
      TodoVisualState.overdue => tokens.danger,
      TodoVisualState.dueSoon => tokens.warning,
      TodoVisualState.completed || TodoVisualState.archived => tokens.textMuted,
      TodoVisualState.normal => tokens.textSecondary,
    };

    final dueText = t.dueDate == null
        ? null
        : (CompletionVisibilityPolicy.dateOnly(t.dueDate!) ==
                  CompletionVisibilityPolicy.dateOnly(widget.now)
              ? (widget.isEn ? 'Today' : '今天')
              : I18nDateFormat.monthDay(t.dueDate!));

    final listLabel = _localizedTemplateListName(t.listGroupName, widget.isEn);
    final doneSubtasks = t.subtasks.where((s) => s.isCompleted).length;
    final hasSubtasks = t.subtasks.isNotEmpty;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
        onTap: widget.onOpen,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          decoration: BoxDecoration(
            color: _hovered ? tokens.hoverSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
          ),
          child: Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.canEdit ? widget.onToggle : null,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: t.isCompleted ? tokens.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: t.isCompleted
                            ? tokens.accent
                            : (t.priority != TodoPriority.none
                                  ? prioColor
                                  : tokens.strongBorder),
                        width: 1.4,
                      ),
                    ),
                    child: t.isCompleted
                        ? Icon(Icons.check_rounded, size: 13, color: tokens.accentForeground)
                        : null,
                  ),
                ),
              ),
              if (t.priority != TodoPriority.none)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: prioColor,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      style: tokens.bodyStyle.copyWith(
                        color: t.isCompleted ? tokens.textMuted : tokens.textPrimary,
                        decoration: t.isCompleted ? TextDecoration.lineThrough : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasSubtasks || listLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            if (listLabel != null)
                              Flexible(
                                child: Text(
                                  listLabel,
                                  style: tokens.captionStyle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (listLabel != null && hasSubtasks)
                              Text(' · ', style: tokens.captionStyle),
                            if (hasSubtasks)
                              Text(
                                '$doneSubtasks/${t.subtasks.length}',
                                style: tokens.captionStyle,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (dueText != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: visual == TodoVisualState.overdue
                        ? tokens.danger.withValues(alpha: 0.12)
                        : tokens.mutedSurface,
                    borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
                  ),
                  child: Text(
                    visual == TodoVisualState.overdue && !t.isCompleted
                        ? (widget.isEn ? 'Overdue · $dueText' : '逾期 · $dueText')
                        : dueText,
                    style: tokens.captionStyle.copyWith(color: dueColor),
                  ),
                ),
              ],
              if (_hovered && !t.isCompleted) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: widget.isEn ? 'Focus on this' : '开始专注',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: widget.onFocus,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.play_circle_outline_rounded, size: 17, color: tokens.accent),
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

class _HabitQuickPill extends StatefulWidget {
  final Habit habit;
  final DesktopWebTokens tokens;
  final VoidCallback onTap;
  final VoidCallback? onUndo;

  const _HabitQuickPill({
    required this.habit,
    required this.tokens,
    required this.onTap,
    this.onUndo,
  });

  @override
  State<_HabitQuickPill> createState() => _HabitQuickPillState();
}

class _HabitQuickPillState extends State<_HabitQuickPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final habit = widget.habit;
    final tokens = widget.tokens;
    final done = habit.isCompletedToday();
    final color = Color(habit.colorValue);
    final count = habit.todayCount();
    final target = habit.targetCount;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onUndo,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: done
                ? color.withValues(alpha: tokens.isDark ? 0.22 : 0.13)
                : (_hovered ? tokens.hoverSurface : tokens.mutedSurface),
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
            border: Border.all(
              color: done
                  ? color.withValues(alpha: 0.50)
                  : tokens.hairlineBorder,
              width: DesktopWebTokens.hairlineWidth,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                done ? Icons.check_circle_rounded : habitDisplayIconFor(habit),
                size: 16,
                color: done ? color : tokens.textSecondary,
              ),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  habit.name,
                  style: tokens.bodyStyle.copyWith(
                    color: done ? color : tokens.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count/$target',
                style: tokens.captionStyle.copyWith(
                  color: done ? color : tokens.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (habit.currentStreak > 0) ...[
                const SizedBox(width: 5),
                Icon(Icons.local_fire_department_rounded, size: 13, color: tokens.warning),
                Text(
                  '${habit.currentStreak}',
                  style: tokens.captionStyle.copyWith(
                    color: tokens.warning,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

class _GoalProgressRow extends StatelessWidget {
  final GoalItem goal;
  final DesktopWebTokens tokens;
  final bool isEn;
  final VoidCallback onTap;

  const _GoalProgressRow({
    required this.goal,
    required this.tokens,
    required this.isEn,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(goal.colorValue);
    final pct = (goal.computedProgress * 100).round().clamp(0, 100);
    final days = goal.daysRemaining;
    final daysText = days < 0
        ? null
        : (days == 0
              ? (isEn ? 'Due today' : '今天到期')
              : (isEn ? '${days}d left' : '剩余 $days 天'));

    return InkWell(
      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(goalIconFromName(goal.icon), size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    goal.title,
                    style: tokens.bodyStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (daysText != null) ...[
                  Text(daysText, style: tokens.captionStyle),
                  const SizedBox(width: 10),
                ],
                Text(
                  '$pct%',
                  style: tokens.bodyMutedStyle.copyWith(
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: goal.computedProgress,
                minHeight: 5,
                backgroundColor: tokens.mutedSurface,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayTopBarActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _TodayTopBarActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWebTokens.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: tokens.accentSoft,
          borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
          border: Border.all(
            color: tokens.accentBorder,
            width: DesktopWebTokens.hairlineWidth,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: tokens.accent),
            const SizedBox(width: 5),
            Text(label, style: tokens.captionStyle.copyWith(color: tokens.accent)),
          ],
        ),
      ),
    );
  }
}

class _InlineLinkButton extends StatelessWidget {
  final String label;
  final DesktopWebTokens tokens;
  final VoidCallback onTap;

  const _InlineLinkButton({
    required this.label,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXs),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: tokens.captionStyle.copyWith(color: tokens.accent)),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 14, color: tokens.accent),
          ],
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  final String label;
  final Color color;
  final DesktopWebTokens tokens;

  const _CountPill({
    required this.label,
    required this.color,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
      ),
      child: Text(
        label,
        style: tokens.captionStyle.copyWith(
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _AlmanacTag extends StatelessWidget {
  final String label;
  final Color color;
  final bool isEn;
  final DesktopWebTokens tokens;

  const _AlmanacTag({
    required this.label,
    required this.color,
    required this.isEn,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: isEn ? 44 : 24),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: tokens.captionStyle.copyWith(color: color),
        ),
      ),
    );
  }
}

class _IconSquareBtn extends StatelessWidget {
  final IconData icon;
  final DesktopWebTokens tokens;
  final VoidCallback onTap;

  const _IconSquareBtn({
    required this.icon,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXs),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 16, color: tokens.textSecondary),
      ),
    );
  }
}

class _EfficiencyRingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color fillColor;

  _EfficiencyRingPainter({
    required this.progress,
    required this.trackColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, radius, trackPaint);

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _EfficiencyRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.fillColor != fillColor;
}

String? _localizedTemplateListName(String? rawName, bool isEn) {
  if (rawName == null || rawName.trim().isEmpty) return null;
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

class _TodayListsCache {
  final int minuteKey;
  final TodoProvider? todoProvider;
  final int todoRevision;
  final HabitProvider? habitProvider;
  final int habitRevision;
  final GoalProvider? goalProvider;
  final int goalRevision;
  final List<TodoItem> allTodos;
  final int todayTotal;
  final List<TodoItem> pendingToday;
  final List<TodoItem> doneToday;
  final List<Habit> activeHabits;
  final int completedHabitsCount;
  final List<GoalItem> activeGoals;

  const _TodayListsCache({
    required this.minuteKey,
    required this.todoProvider,
    required this.todoRevision,
    required this.habitProvider,
    required this.habitRevision,
    required this.goalProvider,
    required this.goalRevision,
    required this.allTodos,
    required this.todayTotal,
    required this.pendingToday,
    required this.doneToday,
    required this.activeHabits,
    required this.completedHabitsCount,
    required this.activeGoals,
  });
}

class _TodayReportCache {
  final int dayKey;
  final TodoProvider? todoProvider;
  final int todoRevision;
  final HabitProvider? habitProvider;
  final int habitRevision;
  final PomodoroProvider? pomodoro;
  final int pomodoroPersistedRev;
  final TimeAuditProvider? timeAudit;
  final int timeAuditRevision;
  final PeriodReport weeklyReport;
  final int efficiencyDelta;
  final int todayFocusMinutes;
  final int todayFocusSessionsCount;

  const _TodayReportCache({
    required this.dayKey,
    required this.todoProvider,
    required this.todoRevision,
    required this.habitProvider,
    required this.habitRevision,
    required this.pomodoro,
    required this.pomodoroPersistedRev,
    required this.timeAudit,
    required this.timeAuditRevision,
    required this.weeklyReport,
    required this.efficiencyDelta,
    required this.todayFocusMinutes,
    required this.todayFocusSessionsCount,
  });
}

class _MiniCalendarCountsCache {
  final TodoProvider? todoProvider;
  final int todoRevision;
  final int year;
  final int month;
  final Map<int, int> countsByDay;

  const _MiniCalendarCountsCache({
    required this.todoProvider,
    required this.todoRevision,
    required this.year,
    required this.month,
    required this.countsByDay,
  });
}

class _TodayFocusLauncherCard extends StatelessWidget {
  final DesktopWebTokens tokens;
  final bool isEn;
  final PomodoroProvider? pomodoro;
  final String? topTaskTitle;
  final ValueChanged<String?> onLaunchFocus;

  const _TodayFocusLauncherCard({
    required this.tokens,
    required this.isEn,
    required this.pomodoro,
    required this.topTaskTitle,
    required this.onLaunchFocus,
  });

  @override
  Widget build(BuildContext context) {
    try {
      context.select<PomodoroProvider?, (bool, int, String?, String?)>(
        (p) => (
          p?.state.isRunning ?? false,
          (p?.state.isRunning ?? false)
              ? 0
              : (p?.state.remainingSeconds ?? (25 * 60)),
          p?.state.taskName,
          p?.state.type.name,
        ),
      );
    } on ProviderNotFoundException {
      // Optional provider in standalone widget tests.
    }

    Widget buildCard() {
      final state = pomodoro?.state;
      final isRunning = state?.isRunning ?? false;
      final activeSeconds = state?.remainingSeconds ?? (25 * 60);
      final mins = (activeSeconds ~/ 60).toString().padLeft(2, '0');
      final secs = (activeSeconds % 60).toString().padLeft(2, '0');
      final linkedTask = (state?.taskName?.trim().isNotEmpty ?? false)
          ? state!.taskName!
          : topTaskTitle;

      return DesktopPanelCard(
        frosted: tokens.isLiquidGlass,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 17, color: tokens.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isEn ? 'Deep Focus' : '即时专注',
                    style: tokens.cardTitleStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$mins:$secs',
                  style: tokens.pageTitleStyle.copyWith(
                    color: tokens.accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            if (linkedTask != null) ...[
              const SizedBox(height: 8),
              Text(
                isEn ? 'Next: $linkedTask' : '当前关联：$linkedTask',
                style: tokens.bodyMutedStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
              onTap: () => onLaunchFocus(linkedTask),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: tokens.accent,
                  borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isRunning
                          ? Icons.open_in_new_rounded
                          : Icons.play_arrow_rounded,
                      size: 18,
                      color: tokens.accentForeground,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        isRunning
                            ? (isEn ? 'Open Focus Studio' : '进入专注计时 ($mins:$secs)')
                            : (isEn ? 'Start 25m Focus' : '开始 25 分钟专注'),
                        style: tokens.bodyStyle.copyWith(
                          color: tokens.accentForeground,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

    if (pomodoro == null) return buildCard();
    return ValueListenableBuilder<int>(
      valueListenable: pomodoro!.timerTicks,
      builder: (context, _, _) => buildCard(),
    );
  }
}
