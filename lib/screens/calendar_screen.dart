import 'package:flutter/material.dart';
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
import '../models/todo.dart';
import '../widgets/calendar_month_grid.dart';
import '../widgets/calendar_week_strip.dart';
import '../widgets/calendar_day_agenda.dart';
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
            child: const Text('取消'),
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
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _previousMonth() {
    setState(
      () =>
          _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1),
    );
  }

  void _nextMonth() {
    setState(
      () =>
          _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1),
    );
  }

  void _previousWeek() {
    setState(
      () => _selectedDay = _selectedDay.subtract(const Duration(days: 7)),
    );
  }

  void _nextWeek() {
    setState(() => _selectedDay = _selectedDay.add(const Duration(days: 7)));
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

    final dateTypes = calendarProvider.dateEventTypes;
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
        toolbarHeight: 96,
        titleSpacing: 0,
        flexibleSpace: SafeArea(
          child: Column(
            children: [
              // View-specific header
              if (_tabController.index == 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: _previousMonth,
                      ),
                      GestureDetector(
                        onTap: () => setState(() {
                          _selectedDay = DateTime.now();
                          _focusedMonth = DateTime.now();
                        }),
                        child: Text(
                          monthLabel,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _nextMonth,
                      ),
                    ],
                  ),
                ),
              if (_tabController.index == 1)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: _previousWeek,
                      ),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _selectedDay = DateTime.now()),
                        child: Text(
                          weekLabel,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _nextWeek,
                      ),
                    ],
                  ),
                ),
              if (_tabController.index == 2)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '${_selectedDay.year}年${_selectedDay.month}月${_selectedDay.day}日',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              // Tab bar
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: s.calendarTabMonth),
                  Tab(text: s.calendarTabWeek),
                  Tab(text: s.calendarTabDay),
                ],
                labelStyle: const TextStyle(fontWeight: FontWeight.w500),
                indicatorSize: TabBarIndicatorSize.label,
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Month
          Column(
            children: [
              CalendarMonthGrid(
                focusedMonth: _focusedMonth,
                selectedDay: _selectedDay,
                dateEventTypes: dateTypes,
                onDaySelected: (d) => setState(() => _selectedDay = d),
              ),
              const Divider(),
              Expanded(
                child: CalendarDayAgenda(
                  date: _selectedDay,
                  calendarProvider: calendarProvider,
                ),
              ),
            ],
          ),
          // Week
          CalendarWeekStrip(
            selectedDay: _selectedDay,
            dateEventTypes: dateTypes,
            onDaySelected: (d) => setState(() => _selectedDay = d),
          ),
          // Day
          CalendarDayAgenda(
            date: _selectedDay,
            calendarProvider: calendarProvider,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showQuickAddTodo,
        child: const Icon(Icons.add),
      ),
    );
  }
}
