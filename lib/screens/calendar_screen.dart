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
import '../providers/time_audit_provider.dart';
import '../models/calendar_event.dart';
import '../models/time_entry.dart';
import '../models/todo.dart';
import '../widgets/calendar_month_grid.dart';
import '../widgets/calendar_week_strip.dart';
import '../widgets/calendar_day_agenda.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/surface_components.dart';

class CalendarScreen extends StatefulWidget {
  final GlobalKey? todoTabKey;

  const CalendarScreen({super.key, this.todoTabKey});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedMonth = DateTime.now();
  Set<CalendarEventType>? _activeTypes;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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
                  TodoItem(title: titleCtrl.text.trim(), date: _selectedDay),
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
    final timeAuditProvider = context.watch<TimeAuditProvider>();
    final s = context.watch<ThemeProvider>().brand.strings;
    final cs = Theme.of(context).colorScheme;

    // Rebuild calendar events
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

    final dateTypes = calendarProvider.filteredDateEventTypes(_activeTypes);
    final monthLabel = '${_focusedMonth.year}年${_focusedMonth.month}月';
    final weekStart = _selectedDay.subtract(
      Duration(days: _selectedDay.weekday - 1),
    );
    final weekEnd = weekStart.add(const Duration(days: 6));
    final weekLabel =
        '${weekStart.month}/${weekStart.day} - ${weekEnd.month}/${weekEnd.day}';

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
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'today', child: Text('回到今天')),
              PopupMenuItem(value: 'pick', child: Text('选择日期')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'month', child: Text('月视图')),
              PopupMenuItem(value: 'week', child: Text('周视图')),
              PopupMenuItem(value: 'day', child: Text('日视图')),
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
            onPreviousMonth: _previousMonth,
            onNextMonth: _nextMonth,
            onPreviousWeek: _previousWeek,
            onNextWeek: _nextWeek,
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
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Month
                Column(
                  children: [
                    CalendarMonthGrid(
                      focusedMonth: _focusedMonth,
                      selectedDay: _selectedDay,
                      dateEventTypes: dateTypes,
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
                      ),
                    ),
                  ],
                ),
                // Week
                CalendarWeekStrip(
                  selectedDay: _selectedDay,
                  dateEventTypes: dateTypes,
                  onDaySelected: (d) => setState(() {
                    _selectedDay = d;
                    _focusedMonth = DateTime(d.year, d.month);
                  }),
                  activeTypes: _activeTypes,
                ),
                // Day
                CalendarDayAgenda(
                  date: _selectedDay,
                  calendarProvider: calendarProvider,
                  activeTypes: _activeTypes,
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

  void _showQuickAddMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
    final durationCtrl = TextEditingController(text: '30');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text('记录时间 - ${_selectedDay.month}月${_selectedDay.day}日'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: '事项'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: durationCtrl,
              decoration: const InputDecoration(labelText: '时长（分钟）'),
              keyboardType: TextInputType.number,
            ),
          ],
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
      DateTime.now().hour,
      DateTime.now().minute,
    );
    final end = start.add(Duration(minutes: minutes));
    await context.read<TimeAuditProvider>().add(
      TimeEntry(
        title: title,
        startAt: start,
        endAt: end,
        category: TimeEntryCategory.other,
        source: TimeEntrySource.manual,
      ),
    );
  }
}

class _CalendarNavigationHeader extends StatelessWidget {
  final int tabIndex;
  final String monthLabel;
  final String weekLabel;
  final String dayLabel;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onPreviousWeek;
  final VoidCallback onNextWeek;
  final VoidCallback onPickDate;

  const _CalendarNavigationHeader({
    required this.tabIndex,
    required this.monthLabel,
    required this.weekLabel,
    required this.dayLabel,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onPreviousWeek,
    required this.onNextWeek,
    required this.onPickDate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = switch (tabIndex) {
      0 => monthLabel,
      1 => weekLabel,
      _ => dayLabel,
    };
    final previous = switch (tabIndex) {
      0 => onPreviousMonth,
      1 => onPreviousWeek,
      _ => null,
    };
    final next = switch (tabIndex) {
      0 => onNextMonth,
      1 => onNextWeek,
      _ => null,
    };

    return Material(
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              _NavIconButton(
                icon: Icons.chevron_left,
                onPressed: previous,
                tooltip: '上一段',
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: onPickDate,
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: cs.onSurface,
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
              _NavIconButton(
                icon: Icons.chevron_right,
                onPressed: next,
                tooltip: '下一段',
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
