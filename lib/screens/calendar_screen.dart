import 'package:flutter/material.dart';
import '../core/i18n.dart';
import 'package:provider/provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/todo_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/anniversary_provider.dart';
import '../providers/course_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/countdown_provider.dart';
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
import '../widgets/surface_components.dart';
import 'todo_screen.dart';

class CalendarScreen extends StatefulWidget {
  final GlobalKey? todoTabKey;
  final DateTime? initialDate;

  const CalendarScreen({super.key, this.todoTabKey, this.initialDate});

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

  @override
  void initState() {
    super.initState();
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
  }

  void _handleTabControllerChanged() {
    if (!mounted || _tabController.indexIsChanging) return;
    setState(() {});
  }

  @override
  void dispose() {
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
    required CourseProvider courseProvider,
    required DiaryProvider diaryProvider,
    required CountdownProvider countdownProvider,
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
      courseProvider: courseProvider,
      diaryProvider: diaryProvider,
      countdownProvider: countdownProvider,
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
      final courseProvider = context.read<CourseProvider>();
      final diaryProvider = context.read<DiaryProvider>();
      final countdownProvider = context.read<CountdownProvider>();
      final goalProvider = context.read<GoalProvider>();
      final timeAuditProvider = context.read<TimeAuditProvider>();
      _lastCalendarInputSignature = _calendarInputSignature(
        todoProvider: todoProvider,
        habitProvider: habitProvider,
        pomodoroProvider: pomodoroProvider,
        calendarProvider: calendarProvider,
        anniversaryProvider: anniversaryProvider,
        courseProvider: courseProvider,
        diaryProvider: diaryProvider,
        countdownProvider: countdownProvider,
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
    required CourseProvider courseProvider,
    required DiaryProvider diaryProvider,
    required CountdownProvider countdownProvider,
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
      _courseSignature(courseProvider.courses, courseProvider.settings),
      _diarySignature(diaryProvider.entries),
      _countdownSignature(countdownProvider.items),
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

  Object _countdownSignature(List<CountdownItem> items) => Object.hashAll([
    items.length,
    for (final item in items)
      Object.hash(
        item.id,
        item.title,
        item.targetDate.millisecondsSinceEpoch,
        item.isPinned,
        item.updatedAt.millisecondsSinceEpoch,
      ),
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

  void _showQuickAddTodo() {
    final s = context.read<ThemeProvider>().brand.strings;
    final titleCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text(
          '${s.calendarQuickAddTitle} - ${_selectedDay.month}月${_selectedDay.day}日',
        ),
        content: TextField(
          controller: titleCtrl,
          decoration: const InputDecoration(labelText: '任务名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(I18n.tr('action.cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (titleCtrl.text.trim().isNotEmpty) {
                context.read<TodoProvider>().addTodo(
                  TodoItem(
                    title: titleCtrl.text.trim(),
                    date: _selectedDay,
                    workspaceId: _activeWorkspaceId ?? 'private',
                  ),
                );
                Navigator.pop(ctx);
              }
            },
            child: Text(I18n.tr('action.add')),
          ),
        ],
      ),
    );
  }

  void _previousMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
      _selectedDay = _clampSelectedDayToFocusedMonth();
    });
  }

  void _nextMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
      _selectedDay = _clampSelectedDayToFocusedMonth();
    });
  }

  void _previousWeek() {
    setState(() {
      _selectedDay = _selectedDay.subtract(const Duration(days: 7));
      _focusedMonth = DateTime(_selectedDay.year, _selectedDay.month);
    });
  }

  void _nextWeek() {
    setState(() {
      _selectedDay = _selectedDay.add(const Duration(days: 7));
      _focusedMonth = DateTime(_selectedDay.year, _selectedDay.month);
    });
  }

  void _previousDay() {
    setState(() {
      _selectedDay = _selectedDay.subtract(const Duration(days: 1));
      _focusedMonth = DateTime(_selectedDay.year, _selectedDay.month);
    });
  }

  void _nextDay() {
    setState(() {
      _selectedDay = _selectedDay.add(const Duration(days: 1));
      _focusedMonth = DateTime(_selectedDay.year, _selectedDay.month);
    });
  }

  void _previousThreeDays() {
    setState(() {
      _selectedDay = _selectedDay.subtract(const Duration(days: 3));
      _focusedMonth = DateTime(_selectedDay.year, _selectedDay.month);
    });
  }

  void _nextThreeDays() {
    setState(() {
      _selectedDay = _selectedDay.add(const Duration(days: 3));
      _focusedMonth = DateTime(_selectedDay.year, _selectedDay.month);
    });
  }

  void _previousYear() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year - 1, _focusedMonth.month);
      final targetYear = _selectedDay.year - 1;
      final lastDay = DateTime(targetYear, _selectedDay.month + 1, 0).day;
      final day = _selectedDay.day.clamp(1, lastDay);
      _selectedDay = DateTime(targetYear, _selectedDay.month, day);
    });
  }

  void _nextYear() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year + 1, _focusedMonth.month);
      final targetYear = _selectedDay.year + 1;
      final lastDay = DateTime(targetYear, _selectedDay.month + 1, 0).day;
      final day = _selectedDay.day.clamp(1, lastDay);
      _selectedDay = DateTime(targetYear, _selectedDay.month, day);
    });
  }

  DateTime _clampSelectedDayToFocusedMonth() {
    final lastDay = DateTime(
      _focusedMonth.year,
      _focusedMonth.month + 1,
      0,
    ).day;
    final day = _selectedDay.day.clamp(1, lastDay);
    return DateTime(_focusedMonth.year, _focusedMonth.month, day);
  }

  Future<void> _pickDate() async {
    final picked = await AppDatePicker.pickSolar(
      context,
      initialDate: _selectedDay,
      firstDate: DateTime(1900),
      lastDate: DateTime(2099, 12, 31),
      title: '选择日期',
      subtitle: '手动跳转到指定日期',
    );
    if (!mounted) return;
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
    final pomodoroProvider = context.watch<PomodoroProvider>();
    final calendarProvider = context.watch<CalendarProvider>();
    final anniversaryProvider = context.watch<AnniversaryProvider>();
    final courseProvider = context.watch<CourseProvider>();
    final diaryProvider = context.watch<DiaryProvider>();
    final countdownProvider = context.watch<CountdownProvider>();
    final goalProvider = context.watch<GoalProvider>();
    final shareProvider = context.watch<ShareProvider>();
    final timeAuditProvider = context.watch<TimeAuditProvider>();
    final s = context.watch<ThemeProvider>().brand.strings;
    final cs = Theme.of(context).colorScheme;

    _scheduleCalendarRebuild(
      todoProvider: todoProvider,
      habitProvider: habitProvider,
      pomodoroProvider: pomodoroProvider,
      calendarProvider: calendarProvider,
      anniversaryProvider: anniversaryProvider,
      courseProvider: courseProvider,
      diaryProvider: diaryProvider,
      countdownProvider: countdownProvider,
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
    final dateTypes = calendarProvider.filteredDateEventTypes(
      _activeTypes,
      projectKey: effectiveProjectKey,
      workspaceId: effectiveWorkspaceId,
    );
    final monthLabel = '${_focusedMonth.year}年${_focusedMonth.month}月';
    final weekStart = _selectedDay.subtract(
      Duration(days: _selectedDay.weekday - 1),
    );
    final weekEnd = weekStart.add(const Duration(days: 6));
    final weekLabel =
        '${weekStart.month}/${weekStart.day} - ${weekEnd.month}/${weekEnd.day}';
    final threeDayEnd = _selectedDay.add(const Duration(days: 2));
    final threeDayLabel =
        '${_selectedDay.year}年${_selectedDay.month}/${_selectedDay.day} - ${threeDayEnd.month}/${threeDayEnd.day}';
    final yearLabel = '${_focusedMonth.year} 年';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('日历'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '日历菜单',
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
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'today', child: Text('回到今天')),
              PopupMenuItem(value: 'pick', child: Text('选择日期')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'month', child: Text('月视图')),
              PopupMenuItem(value: 'week', child: Text('周视图')),
              PopupMenuItem(value: 'day', child: Text('日视图')),
              PopupMenuItem(value: 'three_day', child: Text('三日视图')),
              PopupMenuItem(value: 'year', child: Text('年视图')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _CalendarNavigationHeader(
            tabIndex: _tabController.index,
            monthLabel: monthLabel,
            weekLabel: weekLabel,
            dayLabel:
                '${_selectedDay.year}年${_selectedDay.month}月${_selectedDay.day}日',
            threeDayLabel: threeDayLabel,
            yearLabel: yearLabel,
            onPreviousMonth: _previousMonth,
            onNextMonth: _nextMonth,
            onPreviousWeek: _previousWeek,
            onNextWeek: _nextWeek,
            onPreviousDay: _previousDay,
            onNextDay: _nextDay,
            onPreviousThreeDays: _previousThreeDays,
            onNextThreeDays: _nextThreeDays,
            onPreviousYear: _previousYear,
            onNextYear: _nextYear,
            onPickDate: _pickDate,
          ),
          Material(
            color: cs.surface,
            child: TabBar(
              controller: _tabController,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              tabs: [
                Tab(text: s.calendarTabMonth),
                Tab(text: s.calendarTabWeek),
                Tab(text: s.calendarTabDay),
                const Tab(text: '三日'),
                const Tab(text: '年'),
              ],
              labelStyle: const TextStyle(fontWeight: FontWeight.w400),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              labelColor: cs.onPrimaryContainer,
              unselectedLabelColor: cs.onSurfaceVariant,
            ),
          ),
          // Type filter chips
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: const Text('全部'),
                    selected: _activeTypes == null,
                    onSelected: (_) => setState(() => _activeTypes = null),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                for (final type in CalendarEventType.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
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
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
          if (workspaceOptions.isNotEmpty)
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      avatar: const Icon(Icons.groups_2_outlined, size: 16),
                      label: const Text('全部空间'),
                      selected: effectiveWorkspaceId == null,
                      onSelected: (_) =>
                          setState(() => _activeWorkspaceId = null),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  for (final option in workspaceOptions)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        avatar: Icon(
                          option.isPrivate
                              ? Icons.lock_outline
                              : Icons.groups_2_outlined,
                          size: 16,
                        ),
                        label: Text('${option.name} ${option.count}'),
                        selected: effectiveWorkspaceId == option.id,
                        onSelected: (_) {
                          setState(() {
                            _activeWorkspaceId = option.id;
                          });
                        },
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),
          if (projectOptions.isNotEmpty)
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      avatar: const Icon(Icons.folder_outlined, size: 16),
                      label: const Text('全部项目'),
                      selected: effectiveProjectKey == null,
                      onSelected: (_) =>
                          setState(() => _activeProjectKey = null),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  for (final option in projectOptions)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text('${option.name} ${option.count}'),
                        selected: effectiveProjectKey == option.key,
                        onSelected: (_) {
                          setState(() {
                            _activeProjectKey = option.key;
                            if (_activeTypes != null &&
                                !_activeTypes!.contains(
                                  CalendarEventType.todo,
                                )) {
                              _activeTypes = {CalendarEventType.todo};
                            }
                          });
                        },
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  if (effectiveProjectKey != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        avatar: const Icon(Icons.info_outline, size: 16),
                        label: const Text('项目详情'),
                        visualDensity: VisualDensity.compact,
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
                    ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Month
                LayoutBuilder(
                  builder: (context, constraints) {
                    final showLunar = constraints.maxHeight >= 390;
                    return Column(
                      children: [
                        CalendarMonthGrid(
                          focusedMonth: _focusedMonth,
                          selectedDay: _selectedDay,
                          dateEventTypes: dateTypes,
                          showLunar: showLunar,
                          onDaySelected: (d) => setState(() {
                            _selectedDay = d;
                            _focusedMonth = DateTime(d.year, d.month);
                          }),
                        ),
                        Divider(
                          height: 1,
                          thickness: 0.5,
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.35),
                        ),
                        Expanded(
                          child: CalendarDayAgenda(
                            date: _selectedDay,
                            calendarProvider: calendarProvider,
                            activeTypes: _activeTypes,
                            projectKey: effectiveProjectKey,
                            workspaceId: effectiveWorkspaceId,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                // Week
                CalendarWeekStrip(
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
                ),
                // Day
                CalendarDayAgenda(
                  date: _selectedDay,
                  calendarProvider: calendarProvider,
                  activeTypes: _activeTypes,
                  projectKey: effectiveProjectKey,
                  workspaceId: effectiveWorkspaceId,
                ),
                // Three-day
                _CalendarThreeDayView(
                  key: const ValueKey('calendar_three_day_view'),
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
                  selectedDay: _selectedDay,
                  dateEventTypes: dateTypes,
                  onMonthTap: (month) {
                    setState(() {
                      _focusedMonth = DateTime(_focusedMonth.year, month);
                      _selectedDay = DateTime(_focusedMonth.year, month, 1);
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
        onPressed: () => _showQuickAddMenu(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  List<_CalendarProjectOption> _projectOptions(List<TodoItem> todos) {
    final options = <_CalendarProjectOption>[];
    for (final todo in todos) {
      final trimmedName = todo.listGroupName?.trim();
      final name = trimmedName == null || trimmedName.isEmpty
          ? '未分组'
          : trimmedName;
      final key = todo.listGroupId?.isNotEmpty == true
          ? todo.listGroupId!
          : (trimmedName == null || trimmedName.isEmpty ? '' : trimmedName);
      final index = options.indexWhere((option) => option.key == key);
      if (index == -1) {
        options.add(_CalendarProjectOption(key: key, name: name, count: 1));
      } else {
        final current = options[index];
        options[index] = _CalendarProjectOption(
          key: current.key,
          name: current.name,
          count: current.count + 1,
        );
      }
    }
    options.sort((a, b) {
      if (a.key.isEmpty) return 1;
      if (b.key.isEmpty) return -1;
      return a.name.compareTo(b.name);
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
          name: workspace?.name ?? '共享空间',
          count: entry.value,
          isPrivate: false,
        ),
      );
    }
    if (privateCount != null && privateCount > 0) {
      options.add(
        _CalendarWorkspaceOption(
          id: 'private',
          name: '个人空间',
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
      return a.name.compareTo(b.name);
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

  Future<void> _showProjectDetail(
    BuildContext context,
    _CalendarProjectOption option,
    List<TodoItem> todos,
  ) async {
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);
    final completed = todos.where((todo) => todo.isCompleted).length;
    final overdue = todos.where((todo) => todo.isOverdue).length;
    final todayCount = todos.where((todo) {
      final d = DateTime(todo.date.year, todo.date.month, todo.date.day);
      return d == todayKey;
    }).length;
    await showAppModalSheet<void>(
      context: context,
      builder: (_) => AppModalSheet(
        title: '项目详情',
        subtitle: option.name,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: _ProjectStat(label: '总数', value: '${todos.length}'),
                ),
                Expanded(
                  child: _ProjectStat(label: '完成', value: '$completed'),
                ),
                Expanded(
                  child: _ProjectStat(label: '逾期', value: '$overdue'),
                ),
                Expanded(
                  child: _ProjectStat(label: '今日', value: '$todayCount'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (todos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text('这个项目暂无任务'),
              )
            else
              ...todos
                  .take(8)
                  .map(
                    (todo) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        todo.isCompleted
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 18,
                      ),
                      title: Text(
                        todo.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${todo.date.month}/${todo.date.day}${todo.priority != TodoPriority.none ? ' · ${todo.priority.label}' : ''}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TodoScreen()),
                  );
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('打开待办'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showQuickAddMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.event_note_outlined),
              title: const Text('新建日程'),
              subtitle: const Text('支持全天和多日安排'),
              onTap: () {
                Navigator.pop(ctx);
                showLocalCalendarEventEditor(
                  context,
                  initialDate: _selectedDay,
                  workspaceId: _activeWorkspaceId,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('新建待办'),
              onTap: () {
                Navigator.pop(ctx);
                _showQuickAddTodo();
              },
            ),
            ListTile(
              leading: const Icon(Icons.timelapse_outlined),
              title: const Text('记录一段时间'),
              onTap: () {
                Navigator.pop(ctx);
                _showQuickAddTimeEntry();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showQuickAddTimeEntry() async {
    final titleCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final durationCtrl = TextEditingController(text: '30');
    var category = TimeEntryCategory.work;
    final now = DateTime.now();
    var startTime = TimeOfDay.fromDateTime(
      _isSameDate(_selectedDay, now)
          ? now
          : DateTime(
              _selectedDay.year,
              _selectedDay.month,
              _selectedDay.day,
              9,
            ),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AppDialog(
          title: Text('记录时间 - ${_selectedDay.month}月${_selectedDay.day}日'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: '事项',
                    prefixIcon: Icon(Icons.title, size: 20),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                AppDropdownField<TimeEntryCategory>(
                  initialValue: category,
                  labelText: '分类',
                  prefixIcon: const Icon(Icons.label_outline, size: 20),
                  items: [
                    for (final c in TimeEntryCategory.values)
                      DropdownMenuItem(value: c, child: Text(c.label)),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => category = v);
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: const Text('开始时间'),
                  subtitle: Text(AppTimePicker.format(startTime)),
                  onTap: () async {
                    final picked = await AppTimePicker.show(
                      ctx,
                      initialTime: startTime,
                      title: '开始时间',
                      minuteStep: 5,
                    );
                    if (picked != null) {
                      setDialogState(() => startTime = picked);
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: durationCtrl,
                  decoration: const InputDecoration(
                    labelText: '时长（分钟）',
                    prefixIcon: Icon(Icons.timelapse, size: 20),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: '备注',
                    prefixIcon: Icon(Icons.notes_outlined, size: 20),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('记录'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final title = titleCtrl.text.trim();
    final minutes = int.tryParse(durationCtrl.text.trim()) ?? 0;
    if (title.isEmpty || minutes <= 0) return;
    if (!mounted) return;
    final start = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
      startTime.hour,
      startTime.minute,
    );
    final end = start.add(Duration(minutes: minutes));
    await context.read<TimeAuditProvider>().add(
      TimeEntry(
        title: title,
        startAt: start,
        endAt: end,
        category: category,
        source: TimeEntrySource.manual,
        note: noteCtrl.text.trim(),
      ),
    );
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
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
}

class _CalendarWorkspaceOption {
  final String id;
  final String name;
  final int count;
  final bool isPrivate;

  const _CalendarWorkspaceOption({
    required this.id,
    required this.name,
    required this.count,
    required this.isPrivate,
  });
}

class _ProjectStat extends StatelessWidget {
  final String label;
  final String value;

  const _ProjectStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w400,
            color: cs.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ],
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
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onPreviousWeek;
  final VoidCallback onNextWeek;
  final VoidCallback onPreviousDay;
  final VoidCallback onNextDay;
  final VoidCallback onPreviousThreeDays;
  final VoidCallback onNextThreeDays;
  final VoidCallback onPreviousYear;
  final VoidCallback onNextYear;
  final VoidCallback onPickDate;

  const _CalendarNavigationHeader({
    required this.tabIndex,
    required this.monthLabel,
    required this.weekLabel,
    required this.dayLabel,
    required this.threeDayLabel,
    required this.yearLabel,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onPreviousWeek,
    required this.onNextWeek,
    required this.onPreviousDay,
    required this.onNextDay,
    required this.onPreviousThreeDays,
    required this.onNextThreeDays,
    required this.onPreviousYear,
    required this.onNextYear,
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
      0 => '上一月',
      1 => '上一周',
      2 => '上一天',
      3 => '前三天',
      4 => '上一年',
      _ => '上一段',
    };
    final nextTooltip = switch (tabIndex) {
      0 => '下一月',
      1 => '下一周',
      2 => '下一天',
      3 => '后三天',
      4 => '下一年',
      _ => '下一段',
    };

    return Material(
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              _NavIconButton(
                icon: Icons.chevron_left,
                onPressed: previous,
                tooltip: previousTooltip,
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 8,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 180),
                  child: FilledButton.tonalIcon(
                    onPressed: onPickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    style: FilledButton.styleFrom(
                      foregroundColor: cs.onSecondaryContainer,
                      backgroundColor: cs.secondaryContainer.withValues(
                        alpha: 0.72,
                      ),
                      minimumSize: const Size.fromHeight(46),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.55),
                        ),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _NavIconButton(
                icon: Icons.chevron_right,
                onPressed: next,
                tooltip: nextTooltip,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  const _NavIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: IconButton(
        tooltip: tooltip,
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

  const _CalendarThreeDayView({
    super.key,
    required this.startDate,
    required this.calendarProvider,
    this.activeTypes,
    this.projectKey,
    this.workspaceId,
  });

  @override
  Widget build(BuildContext context) {
    final days = List.generate(
      3,
      (index) => startDate.add(Duration(days: index)),
    );
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
                  ),
                ),
                if (i != days.length - 1)
                  VerticalDivider(
                    width: 1,
                    thickness: 0.5,
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.45),
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
                  width: 340,
                  child: _ThreeDayLane(
                    date: day,
                    calendarProvider: calendarProvider,
                    activeTypes: activeTypes,
                    projectKey: projectKey,
                    workspaceId: workspaceId,
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
  final DateTime date;
  final CalendarProvider calendarProvider;
  final Set<CalendarEventType>? activeTypes;
  final String? projectKey;
  final String? workspaceId;

  const _ThreeDayLane({
    required this.date,
    required this.calendarProvider,
    this.activeTypes,
    this.projectKey,
    this.workspaceId,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final events = calendarProvider.getEventsForDate(
      date,
      activeTypes: activeTypes,
      projectKey: projectKey,
      workspaceId: workspaceId,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.view_column_outlined, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${date.month}月${date.day}日 周${_weekdayLabel(date.weekday)}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              Text(
                '${events.length} 项',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Expanded(
          child: CalendarDayAgenda(
            date: date,
            calendarProvider: calendarProvider,
            activeTypes: activeTypes,
            projectKey: projectKey,
          ),
        ),
      ],
    );
  }
}

String _weekdayLabel(int weekday) {
  return switch (weekday) {
    DateTime.monday => '一',
    DateTime.tuesday => '二',
    DateTime.wednesday => '三',
    DateTime.thursday => '四',
    DateTime.friday => '五',
    DateTime.saturday => '六',
    DateTime.sunday => '日',
    _ => '',
  };
}

class _CalendarYearOverview extends StatelessWidget {
  final int year;
  final DateTime selectedDay;
  final Map<String, List<CalendarEventType>> dateEventTypes;
  final void Function(int month) onMonthTap;

  const _CalendarYearOverview({
    super.key,
    required this.year,
    required this.selectedDay,
    required this.dateEventTypes,
    required this.onMonthTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final months = List.generate(12, (i) => i + 1);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: months.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.28,
      ),
      itemBuilder: (context, index) {
        final month = months[index];
        final monthDays = _monthDays(year, month);
        final eventCount = monthDays.fold<int>(0, (sum, d) {
          final key =
              '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          return sum + (dateEventTypes[key]?.length ?? 0);
        });
        final isSelected =
            selectedDay.year == year && selectedDay.month == month;

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onMonthTap(month),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? cs.primaryContainer
                  : cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? cs.primary
                    : cs.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$month 月',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  eventCount == 0 ? '本月暂无事项' : '$eventCount 个事项',
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected
                        ? cs.onPrimaryContainer.withValues(alpha: 0.78)
                        : cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    for (final t in CalendarEventType.values.take(4))
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: _MonthDot(
                          color: _colorFor(t, cs),
                          filled: eventCount > 0,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<DateTime> _monthDays(int year, int month) {
    final count = DateTime(year, month + 1, 0).day;
    return List.generate(count, (i) => DateTime(year, month, i + 1));
  }

  Color _colorFor(CalendarEventType t, ColorScheme cs) {
    switch (t) {
      case CalendarEventType.event:
        return const Color(0xFF5B6EE1);
      case CalendarEventType.todo:
        return cs.primary;
      case CalendarEventType.habit:
        return cs.tertiary;
      case CalendarEventType.pomodoro:
        return Colors.red;
      case CalendarEventType.anniversary:
        return const Color(0xFFE91E63);
      case CalendarEventType.course:
        return const Color(0xFF42A5F5);
      case CalendarEventType.diary:
        return const Color(0xFF26A69A);
      case CalendarEventType.countdown:
        return Colors.orange;
      case CalendarEventType.goal:
        return const Color(0xFFFFA726);
      case CalendarEventType.timeEntry:
        return const Color(0xFF78909C);
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
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: filled
            ? color.withValues(alpha: 0.7)
            : color.withValues(alpha: 0.25),
        shape: BoxShape.circle,
      ),
    );
  }
}
