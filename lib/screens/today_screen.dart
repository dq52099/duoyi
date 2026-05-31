import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/completion_visibility_policy.dart';
import '../core/goal_icons.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/lunar_calendar.dart';
import '../core/quotes.dart';
import '../core/report_engine.dart';
import '../core/smart_schedule_advisor.dart';
import '../models/course_schedule.dart' show CourseItem, ScheduleSettings;
import '../models/todo.dart';
import '../providers/anniversary_provider.dart';
import '../providers/course_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/share_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/time_audit_provider.dart';
import '../providers/todo_provider.dart';
import '../providers/user_provider.dart';
import '../widgets/brand_background.dart';
import '../widgets/surface_components.dart';
import '../widgets/todo_completion_flow.dart';
import 'diary_screen.dart';
import 'habit_screen.dart';
import 'almanac_screen.dart';
import 'goal_edit_screen.dart';
import 'pomodoro_screen.dart';
import 'statistics_screen.dart';
import 'today_detail_router.dart';
import 'todo_screen.dart';

/// 今日概览：登录后展示的聚合首屏。
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = context.watch<ThemeProvider>().brand.strings;

    final todoP = context.watch<TodoProvider>();
    final habitP = context.watch<HabitProvider>();
    final todayFocusCount = context.select<PomodoroProvider, int>(
      (provider) => provider.sessionCountToday,
    );
    final diaryP = context.watch<DiaryProvider>();
    final anniP = context.watch<AnniversaryProvider>();
    final courseP = context.watch<CourseProvider>();
    final goalP = context.watch<GoalProvider>();
    final user = context.watch<UserProvider>();

    final now = DateTime.now();
    final todayKey = DateTime(now.year, now.month, now.day);
    final lunar = LunarCalendar.fromSolar(now);
    final term = LunarCalendar.solarTerm(now);
    final festival =
        LunarCalendar.solarFestival(now) ?? LunarCalendar.lunarFestival(lunar);

    final todayTodos = todoP.visibleTodayTodos(now);
    final todayTodosCount = todayTodos.length;
    final todayTodoCompleted = todayTodos
        .where((todo) => todo.isCompleted)
        .length;
    todayTodos.sort((a, b) {
      if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
      final dueA = a.dueDate;
      final dueB = b.dueDate;
      if (dueA != null && dueB != null) return dueA.compareTo(dueB);
      if (dueA != null) return -1;
      if (dueB != null) return 1;
      return a.quadrant.index.compareTo(b.quadrant.index);
    });

    final todayCourses = courseP.todayCourses
      ..sort((a, b) => a.startSection.compareTo(b.startSection));
    final reminderGroups = _TodayReminderGroups.build(
      todos: todoP.todos,
      courses: todayCourses,
      courseSettings: courseP.settings,
      now: now,
      todayKey: todayKey,
    );
    final todayHabitProgress = habitP.todayCompletionRate;

    // 最近的 3 个纪念日
    final upcomingAnni = [...anniP.items]
      ..sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));
    final soon = upcomingAnni
        .where((a) => a.daysRemaining >= 0)
        .take(3)
        .toList();

    final activeGoals = goalP.activeGoals.take(2).toList();
    final suggestions = SmartScheduleAdvisor.suggestToday(
      todoP.todos,
      now: now,
      limit: 5,
    );
    final showReminderSection =
        !reminderGroups.isEmpty || suggestions.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('${user.profile.greeting}，${user.profile.username}'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          _TodayProductivitySection(
            onTap: () => _go(context, const StatisticsScreen()),
          ),

          const SizedBox(height: 12),

          // 日期卡
          AppSurfaceCard(
            onTap: () => _go(context, AlmanacScreen(initialDate: now)),
            padding: const EdgeInsets.all(16),
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.primary.withValues(alpha: 0.92),
                Color.lerp(
                  cs.primary,
                  cs.secondary,
                  0.28,
                )!.withValues(alpha: 0.78),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${I18n.tr('today.almanac.title')} · ${I18nDateFormat.monthDayWithWeekday(now)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${I18n.tr('calendar.chinese_lunar_calendar')} ${lunar.chineseText}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (term != null)
                            _chip(term, Colors.lightGreenAccent),
                          if (festival != null)
                            _chip(festival, Colors.amberAccent),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${now.day}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.normal,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 今日一言
          _QuoteCard(),

          const SizedBox(height: 10),
          // 四个小指标
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth < 520 ? 2 : 4;
              final aspectRatio = constraints.maxWidth < 520 ? 2.55 : 3.65;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                childAspectRatio: aspectRatio,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  AppMetricCard(
                    title: s.navTodo,
                    value: '${todayTodos.length}',
                    unit: I18n.tr('today.unit.item'),
                    icon: Icons.check_circle_outline,
                    color: cs.primary,
                    onTap: () => _go(context, const TodoScreen()),
                  ),
                  AppMetricCard(
                    title: s.navHabit,
                    value: '${(todayHabitProgress * 100).round()}',
                    unit: '%',
                    icon: Icons.repeat,
                    color: cs.tertiary,
                    onTap: () => _go(context, const HabitScreen()),
                  ),
                  AppMetricCard(
                    title: s.navFocus,
                    value: '$todayFocusCount',
                    unit: I18n.tr('today.unit.times'),
                    icon: Icons.timer,
                    color: Colors.redAccent,
                    onTap: () => _go(
                      context,
                      const PomodoroScreen(useShellBackground: true),
                    ),
                  ),
                  AppMetricCard(
                    title: I18n.tr('today.diary'),
                    value: diaryP.entryForDate(now) == null
                        ? I18n.tr('today.diary.unwritten')
                        : I18n.tr('today.diary.written'),
                    icon: Icons.book_outlined,
                    color: const Color(0xFF26A69A),
                    onTap: () => _go(context, const DiaryScreen()),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 14),

          if (showReminderSection)
            _TodayReminderSection(
              groups: reminderGroups,
              suggestions: suggestions,
              todayKey: todayKey,
              now: now,
              onOpenTodo: (id) => TodayDetailRouter.open(
                context,
                TodaySectionKind.todos,
                id: id,
              ),
              onToggleTodo: (todo) =>
                  completeTodoWithOptionalTimeRecord(context, todo),
              onOpenCourses: () =>
                  TodayDetailRouter.open(context, TodaySectionKind.courses),
              onAddToday: (todo) async {
                final changed = await context
                    .read<TodoProvider>()
                    .scheduleTodoForToday(todo.id, now: now);
                if (!context.mounted || !changed) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${I18n.tr('today.added_prefix')}${todo.title}',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),

          // 今日待办
          if (todayTodos.isNotEmpty || todayTodoCompleted > 0)
            _section(
              I18n.tr('today.todos'),
              subtitle:
                  '$todayTodosCount ${I18n.tr('today.unit.item')} · ${I18n.tr('today.completed')} $todayTodoCompleted',
              onMore: () =>
                  TodayDetailRouter.open(context, TodaySectionKind.todos),
              child: Column(
                children: todayTodos.take(6).map((t) {
                  return _TodayTodoSwipeTile(
                    todo: t,
                    onToggle: () =>
                        completeTodoWithOptionalTimeRecord(context, t),
                    onOpen: () => TodayDetailRouter.open(
                      context,
                      TodaySectionKind.todos,
                      id: t.id,
                    ),
                  );
                }).toList(),
              ),
            ),

          // 今日课程
          if (todayCourses.isNotEmpty)
            _section(
              I18n.tr('today.courses'),
              subtitle:
                  '${todayCourses.length} ${I18n.tr('today.unit.course_section')}',
              onMore: () =>
                  TodayDetailRouter.open(context, TodaySectionKind.courses),
              child: Column(
                children: todayCourses.map((c) {
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(
                        c.colorValue,
                      ).withValues(alpha: 0.2),
                      child: Text(
                        '${c.startSection}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(c.colorValue),
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                    title: Text(c.name),
                    subtitle: Text(
                      '${I18n.tr('today.course.period_prefix')}${c.startSection}-${c.endSection}${I18n.tr('today.course.period_suffix')}${c.location.isEmpty ? '' : ' · ${c.location}'}${c.teacher.isEmpty ? '' : ' · ${c.teacher}'}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () => TodayDetailRouter.open(
                      context,
                      TodaySectionKind.courses,
                    ),
                  );
                }).toList(),
              ),
            ),

          // 近期纪念日
          if (soon.isNotEmpty)
            _section(
              I18n.tr('today.upcoming_anniversaries'),
              onMore: () => TodayDetailRouter.open(
                context,
                TodaySectionKind.anniversaries,
              ),
              child: Column(
                children: soon.map((a) {
                  final d = a.daysRemaining;
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(
                        a.colorValue,
                      ).withValues(alpha: 0.15),
                      child: Text(
                        '$d',
                        style: TextStyle(
                          color: Color(a.colorValue),
                          fontWeight: FontWeight.normal,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    title: Text(a.title),
                    subtitle: Text(
                      d == 0
                          ? I18n.tr('today.anniversary.today')
                          : '${I18n.tr('today.anniversary.days_prefix')}$d ${I18n.tr('unit.day')}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () => TodayDetailRouter.open(
                      context,
                      TodaySectionKind.anniversaries,
                      id: a.id,
                    ),
                  );
                }).toList(),
              ),
            ),

          // 目标进度
          _section(
            activeGoals.isEmpty
                ? I18n.tr('goal.title')
                : I18n.tr('today.active_goals'),
            actionLabel: activeGoals.isEmpty
                ? I18n.tr('goal.new')
                : I18n.tr('today.view'),
            onMore: () => activeGoals.isEmpty
                ? Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const GoalEditScreen()),
                  )
                : TodayDetailRouter.open(context, TodaySectionKind.goals),
            child: activeGoals.isEmpty
                ? ListTile(
                    leading: const Icon(Icons.flag_circle_outlined),
                    title: Text(I18n.tr('goal.new')),
                    subtitle: Text(I18n.tr('today.goal.create.subtitle')),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const GoalEditScreen()),
                    ),
                  )
                : Column(
                    children: activeGoals.map((g) {
                      final p = g.computedProgress;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          goalIconFromName(g.icon),
                          color: Color(g.colorValue),
                          size: 18,
                        ),
                        title: Text(g.title),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: p,
                                minHeight: 5,
                                color: Color(g.colorValue),
                                backgroundColor: Color(
                                  g.colorValue,
                                ).withValues(alpha: 0.15),
                              ),
                            ),
                            Text(
                              '${(p * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                        onTap: () => TodayDetailRouter.open(
                          context,
                          TodaySectionKind.goals,
                          id: g.id,
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _section(
    String title, {
    String? subtitle,
    required Widget child,
    VoidCallback? onMore,
    String? actionLabel,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: AppSurfaceCard(
        margin: const EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(
              builder: (context) {
                final theme = Theme.of(context);
                final cs = theme.colorScheme;
                return AppSectionHeader(
                  title: title,
                  subtitle: subtitle,
                  actionLabel: onMore == null
                      ? null
                      : actionLabel ?? I18n.tr('today.view'),
                  onAction: onMore,
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
                  titleStyle: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    height: 1.25,
                    fontWeight: FontWeight.normal,
                    color: cs.onSurface,
                  ),
                  actionTextStyle: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.normal,
                  ),
                );
              },
            ),
            child,
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.9)),
      ),
    );
  }

  void _go(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BrandRouteSurface(child: screen)),
    );
  }
}

class _TodayProductivitySection extends StatelessWidget {
  final VoidCallback onTap;

  const _TodayProductivitySection({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final todoP = context.watch<TodoProvider>();
    final habitP = context.watch<HabitProvider>();
    context.select<PomodoroProvider, int>(
      (provider) => provider.persistedRevision,
    );
    final pomoP = context.read<PomodoroProvider>();
    final timeEntries = context.watch<TimeAuditProvider>().entries;

    final now = DateTime.now();
    final todayKey = DateTime(now.year, now.month, now.day);
    final weekStart = todayKey.subtract(Duration(days: todayKey.weekday - 1));
    final weekEnd = todayKey;
    final previousWeekStart = weekStart.subtract(const Duration(days: 7));
    final previousWeekEnd = weekEnd.subtract(const Duration(days: 7));
    final weeklyReport = ReportEngine.buildReport(
      start: weekStart,
      end: weekEnd,
      todos: todoP.todos,
      habits: habitP.habits,
      sessions: pomoP.sessions,
      timeEntries: timeEntries,
    );
    final previousWeeklyReport = ReportEngine.buildReport(
      start: previousWeekStart,
      end: previousWeekEnd,
      todos: todoP.todos,
      habits: habitP.habits,
      sessions: pomoP.sessions,
      timeEntries: timeEntries,
    );
    return _TodayProductivityCard(
      comparison: ReportEngine.compare(
        current: weeklyReport,
        previous: previousWeeklyReport,
      ),
      onTap: onTap,
    );
  }
}

class _TodayProductivityCard extends StatelessWidget {
  final ReportComparison comparison;
  final VoidCallback onTap;

  const _TodayProductivityCard({required this.comparison, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scoreDelta = comparison.productivityScore.difference.round();
    final trendColor = _trendColor(cs, comparison.productivityScore.direction);
    return AppSurfaceCard(
      onTap: onTap,
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      borderRadius: BorderRadius.circular(20),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primary.withValues(alpha: 0.1),
              border: Border.all(color: cs.primary.withValues(alpha: 0.24)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  comparison.current.productivityScore.toString(),
                  style: TextStyle(
                    fontSize: 25,
                    height: 1,
                    color: cs.primary,
                    fontWeight: FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  I18n.tr('today.productivity.score'),
                  style: TextStyle(
                    fontSize: 9,
                    color: cs.onSurface.withValues(alpha: 0.58),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        I18n.tr('today.productivity.weekly'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                    Icon(
                      _trendIcon(comparison.productivityScore.direction),
                      color: trendColor,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      scoreDelta == 0
                          ? I18n.tr('today.productivity.flat')
                          : '${scoreDelta > 0 ? '+' : ''}$scoreDelta ${I18n.tr('today.unit.point')}',
                      style: TextStyle(fontSize: 12, color: trendColor),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  I18n.tr('today.productivity.subtitle'),
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.58),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _TodayProductivityPill(
                      label: I18n.tr('today.productivity.completion_rate'),
                      value:
                          '${(comparison.current.todoCompletionRate * 100).round()}%',
                    ),
                    _TodayProductivityPill(
                      label: I18n.tr('nav.focus'),
                      value:
                          '${comparison.current.focusMinutes}${I18n.tr('unit.min')}',
                    ),
                    _TodayProductivityPill(
                      label: I18n.tr('nav.habit'),
                      value:
                          '${comparison.current.habitCheckIns}${I18n.tr('today.unit.times')}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.chevron_right,
            size: 18,
            color: cs.onSurface.withValues(alpha: 0.38),
          ),
        ],
      ),
    );
  }

  Color _trendColor(ColorScheme cs, ReportTrendDirection direction) =>
      switch (direction) {
        ReportTrendDirection.up => const Color(0xFF2E7D32),
        ReportTrendDirection.down => const Color(0xFFC62828),
        ReportTrendDirection.flat => cs.onSurface.withValues(alpha: 0.62),
      };

  IconData _trendIcon(ReportTrendDirection direction) => switch (direction) {
    ReportTrendDirection.up => Icons.trending_up,
    ReportTrendDirection.down => Icons.trending_down,
    ReportTrendDirection.flat => Icons.trending_flat,
  };
}

class _TodayProductivityPill extends StatelessWidget {
  final String label;
  final String value;

  const _TodayProductivityPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurface.withValues(alpha: 0.56),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
          ),
        ],
      ),
    );
  }
}

class _QuoteCard extends StatefulWidget {
  @override
  State<_QuoteCard> createState() => _QuoteCardState();
}

class _TodoTodaySubtitle extends StatelessWidget {
  final TodoItem todo;

  const _TodoTodaySubtitle({required this.todo});

  @override
  Widget build(BuildContext context) {
    final visual = CompletionVisibilityPolicy.visualState(todo);
    final subtasks = todo.subtasks.take(3).toList();
    if (todo.listGroupName == null &&
        subtasks.isEmpty &&
        visual == TodoVisualState.normal) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (visual != TodoVisualState.normal)
            _TodayTodoStatusPill(visual: visual),
          if (visual != TodoVisualState.normal &&
              (todo.listGroupName != null || subtasks.isNotEmpty))
            const SizedBox(height: 3),
          if (todo.listGroupName != null)
            Text(todo.listGroupName!, style: const TextStyle(fontSize: 11)),
          for (final subtask in subtasks)
            Row(
              children: [
                Icon(
                  subtask.isCompleted
                      ? Icons.check_circle_outline
                      : Icons.subdirectory_arrow_right,
                  size: 12,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    subtask.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TodayTodoStatusPill extends StatelessWidget {
  final TodoVisualState visual;

  const _TodayTodoStatusPill({required this.visual});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (label, icon, color) = switch (visual) {
      TodoVisualState.completed => (
        '已完成',
        Icons.check_circle_outline,
        cs.tertiary,
      ),
      TodoVisualState.overdue => ('逾期', Icons.priority_high_rounded, cs.error),
      TodoVisualState.dueSoon => (
        '临期',
        Icons.alarm_outlined,
        Colors.orange.shade700,
      ),
      _ => ('正常', Icons.radio_button_unchecked, cs.onSurfaceVariant),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24), width: 0.7),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }
}

class _TodayTodoSwipeTile extends StatefulWidget {
  final TodoItem todo;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final Widget? leading;
  final String? title;
  final Widget? titleWidget;
  final Color? titleColor;
  final Color? completedTextColor;
  final Widget? subtitle;
  final Widget? trailing;
  final Color? tileBackground;
  final Color? tileBorderColor;
  final bool showStatusDecoration;

  const _TodayTodoSwipeTile({
    required this.todo,
    required this.onToggle,
    required this.onOpen,
    this.leading,
    this.title,
    this.titleWidget,
    this.titleColor,
    this.completedTextColor,
    this.subtitle,
    this.trailing,
    this.tileBackground,
    this.tileBorderColor,
    this.showStatusDecoration = true,
  });

  @override
  State<_TodayTodoSwipeTile> createState() => _TodayTodoSwipeTileState();
}

class _TodayTodoSwipeTileState extends State<_TodayTodoSwipeTile> {
  static const double _swipeActionWidth = 104;
  static const double _swipeOpenThreshold = 30;

  double _swipeOffset = 0;
  bool _dragging = false;

  bool get _swipeOpen => _swipeOffset > 0;
  bool get _swipeActive => _dragging || _swipeOpen;

  @override
  void didUpdateWidget(covariant _TodayTodoSwipeTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.todo.id != oldWidget.todo.id) {
      _swipeOffset = 0;
      _dragging = false;
    }
  }

  void _closeSwipe() {
    if (!_swipeOpen || !mounted) return;
    setState(() => _swipeOffset = 0);
  }

  void _openDetails() {
    _closeSwipe();
    widget.onOpen();
  }

  void _showReadOnlyMessage(String action) {
    _closeSwipe();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('共享空间只读，不能$action'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    _closeSwipe();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AppDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('删除任务？'),
        content: Text('将删除“${widget.todo.title}”，相关时间足迹也会同步移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<TodoProvider>().deleteTodo(widget.todo.id);
    } else {
      _closeSwipe();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final todo = widget.todo;
    final visual = CompletionVisibilityPolicy.visualState(todo);
    final isCompleted = visual == TodoVisualState.completed;
    final isOverdue = visual == TodoVisualState.overdue;
    final isDueSoon = visual == TodoVisualState.dueSoon;
    final statusColor = widget.showStatusDecoration
        ? (isCompleted
              ? cs.tertiary
              : isOverdue
              ? cs.error
              : isDueSoon
              ? Colors.orange.shade700
              : null)
        : null;
    final effectiveTileBackground =
        widget.tileBackground ??
        (statusColor == null
            ? null
            : Color.alphaBlend(
                statusColor.withValues(alpha: isCompleted ? 0.06 : 0.08),
                cs.surface,
              ));
    final effectiveTileBorderColor =
        widget.tileBorderColor ?? statusColor?.withValues(alpha: 0.24);
    final canEdit = context.select<ShareProvider?, bool>(
      (share) => share?.canEdit(todo.workspaceId) ?? true,
    );
    Widget tile = Material(
      color: Colors.transparent,
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        leading:
            widget.leading ??
            Checkbox(
              value: todo.isCompleted,
              shape: const CircleBorder(),
              side: statusColor == null
                  ? null
                  : BorderSide(color: statusColor, width: 1.1),
              checkColor: isCompleted ? cs.onTertiary : null,
              fillColor: statusColor == null
                  ? null
                  : WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return statusColor;
                      }
                      return statusColor.withValues(alpha: 0.10);
                    }),
              onChanged: canEdit
                  ? (_) => widget.onToggle()
                  : (_) => _showReadOnlyMessage('完成任务'),
            ),
        title:
            widget.titleWidget ??
            Text(
              widget.title ?? todo.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: todo.isCompleted
                    ? widget.completedTextColor ??
                          cs.onSurface.withValues(alpha: 0.52)
                    : widget.titleColor ?? (isOverdue ? cs.error : null),
                decoration: todo.isCompleted
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
        subtitle: widget.subtitle ?? _TodoTodaySubtitle(todo: todo),
        trailing: widget.trailing,
        onTap: _swipeOpen ? _closeSwipe : widget.onOpen,
      ),
    );
    if (effectiveTileBackground != null || effectiveTileBorderColor != null) {
      tile = Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: effectiveTileBackground ?? Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: effectiveTileBorderColor ?? Colors.transparent,
            width: 0.7,
          ),
        ),
        child: tile,
      );
    }

    return GestureDetector(
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
                child: Container(
                  alignment: Alignment.centerRight,
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.62),
                  child: SizedBox(
                    width: _swipeActionWidth,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _TodayTodoSwipeButton(
                          key: const ValueKey('today_todo_swipe_detail_button'),
                          icon: Icons.open_in_new,
                          label: '详情',
                          background: cs.primaryContainer.withValues(
                            alpha: 0.60,
                          ),
                          foreground: cs.primary,
                          onTap: _openDetails,
                        ),
                        const SizedBox(width: 8),
                        _TodayTodoSwipeButton(
                          key: const ValueKey('today_todo_swipe_delete_button'),
                          icon: Icons.delete_outline,
                          label: '删除',
                          background: canEdit
                              ? cs.errorContainer.withValues(alpha: 0.64)
                              : cs.surfaceContainerHighest.withValues(
                                  alpha: 0.78,
                                ),
                          foreground: canEdit ? cs.error : cs.onSurfaceVariant,
                          onTap: canEdit
                              ? () => _confirmDelete(context)
                              : () => _showReadOnlyMessage('删除任务'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          AnimatedContainer(
            duration: _dragging
                ? Duration.zero
                : const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(-_swipeOffset, 0, 0),
            child: RepaintBoundary(child: tile),
          ),
        ],
      ),
    );
  }
}

class _TodayTodoSwipeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _TodayTodoSwipeButton({
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
              dimension: 38,
              child: Icon(icon, size: 17, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}

enum _TodayReminderKind { todo, course }

class _TodayReminderItem {
  final _TodayReminderKind kind;
  final String id;
  final String title;
  final DateTime time;
  final String subtitle;
  final TodoItem? todo;
  final Color? accentColor;

  const _TodayReminderItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.time,
    required this.subtitle,
    this.todo,
    this.accentColor,
  });
}

class _TodayReminderGroups {
  final List<_TodayReminderItem> dueToday;
  final List<_TodayReminderItem> upcoming;
  final List<_TodayReminderItem> overdue;

  const _TodayReminderGroups({
    required this.dueToday,
    required this.upcoming,
    required this.overdue,
  });

  bool get isEmpty => dueToday.isEmpty && upcoming.isEmpty && overdue.isEmpty;

  static _TodayReminderGroups build({
    required Iterable<TodoItem> todos,
    required Iterable<CourseItem> courses,
    required ScheduleSettings courseSettings,
    required DateTime now,
    required DateTime todayKey,
  }) {
    final dueToday = <_TodayReminderItem>[];
    final upcoming = <_TodayReminderItem>[];
    final overdue = <_TodayReminderItem>[];
    final soonLimit = now.add(const Duration(hours: 6));

    for (final todo in todos) {
      if (todo.isCompleted || todo.isArchivedAfterRollover) continue;
      final trigger = _todoTriggerTime(todo);
      if (trigger == null) continue;
      final item = _TodayReminderItem(
        kind: _TodayReminderKind.todo,
        id: todo.id,
        title: todo.title,
        time: trigger,
        subtitle: _todoReminderSubtitle(todo, trigger, now),
        todo: todo,
      );
      if (trigger.isBefore(now)) {
        overdue.add(item);
      } else if (_sameDay(trigger, todayKey)) {
        dueToday.add(item);
      } else if (trigger.isBefore(soonLimit)) {
        upcoming.add(item);
      }
    }

    for (final course in courses) {
      final start = courseSettings.sectionStart(todayKey, course.startSection);
      final end = courseSettings.sectionEnd(
        todayKey,
        course.startSection,
        course.sectionCount,
      );
      final item = _TodayReminderItem(
        kind: _TodayReminderKind.course,
        id: course.id,
        title: course.name,
        time: start,
        subtitle:
            '${I18n.tr('today.course.period_prefix')}${course.startSection}-${course.endSection}${I18n.tr('today.course.period_suffix')}${course.location.isEmpty ? '' : ' · ${course.location}'}${course.teacher.isEmpty ? '' : ' · ${course.teacher}'}',
        accentColor: Color(course.colorValue),
      );
      if (end.isBefore(now)) {
        overdue.add(item);
      } else if (start.isBefore(now.add(const Duration(minutes: 30)))) {
        dueToday.add(item);
      } else {
        upcoming.add(item);
      }
    }

    int compare(_TodayReminderItem a, _TodayReminderItem b) =>
        a.time.compareTo(b.time);
    dueToday.sort(compare);
    upcoming.sort(compare);
    overdue.sort(compare);

    return _TodayReminderGroups(
      dueToday: dueToday,
      upcoming: upcoming,
      overdue: overdue,
    );
  }

  static bool _sameDay(DateTime value, DateTime day) =>
      value.year == day.year &&
      value.month == day.month &&
      value.day == day.day;

  static DateTime? _todoTriggerTime(TodoItem todo) {
    if (todo.hasReminder && todo.reminderAt != null) return todo.reminderAt;
    return todo.dueDate;
  }

  static String _todoReminderSubtitle(
    TodoItem todo,
    DateTime trigger,
    DateTime now,
  ) {
    final prefix = trigger.isBefore(now)
        ? '提醒时间'
        : _sameDay(trigger, DateTime(now.year, now.month, now.day))
        ? '今日提醒'
        : '即将开始';
    final meta = <String>[
      I18nDateFormat.smartDate(trigger, includeTime: true),
      if (todo.listGroupName != null && todo.listGroupName!.isNotEmpty)
        todo.listGroupName!,
    ];
    return '$prefix · ${meta.join(' · ')}';
  }
}

class _TodayReminderSection extends StatelessWidget {
  final _TodayReminderGroups groups;
  final List<SmartScheduleSuggestion> suggestions;
  final DateTime todayKey;
  final DateTime now;
  final ValueChanged<String> onOpenTodo;
  final ValueChanged<TodoItem> onToggleTodo;
  final VoidCallback onOpenCourses;
  final Future<void> Function(TodoItem todo) onAddToday;

  const _TodayReminderSection({
    required this.groups,
    required this.suggestions,
    required this.todayKey,
    required this.now,
    required this.onOpenTodo,
    required this.onToggleTodo,
    required this.onOpenCourses,
    required this.onAddToday,
  });

  @override
  Widget build(BuildContext context) {
    final total =
        groups.dueToday.length + groups.upcoming.length + groups.overdue.length;
    final subtitle = suggestions.isEmpty
        ? '$total 项 · 今日待提醒 > 即将开始 > 逾期优先处理'
        : '$total 项提醒 · 今日待提醒 > 即将开始 > 逾期优先处理 > 今日建议';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: AppSurfaceCard(
        margin: const EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSectionHeader(
              title: '今日提醒',
              subtitle: subtitle,
              actionLabel: I18n.tr('today.view'),
              onAction: () =>
                  TodayDetailRouter.open(context, TodaySectionKind.todos),
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
              titleStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 14,
                height: 1.25,
                fontWeight: FontWeight.normal,
              ),
              actionTextStyle: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.normal),
            ),
            if (groups.dueToday.isNotEmpty)
              _ReminderGroupBlock(
                title: '今日待提醒事项',
                items: groups.dueToday.take(4).toList(),
                now: now,
                onOpenTodo: onOpenTodo,
                onToggleTodo: onToggleTodo,
                onOpenCourses: onOpenCourses,
              ),
            if (groups.upcoming.isNotEmpty)
              _ReminderGroupBlock(
                title: '即将开始事项',
                items: groups.upcoming.take(4).toList(),
                now: now,
                onOpenTodo: onOpenTodo,
                onToggleTodo: onToggleTodo,
                onOpenCourses: onOpenCourses,
              ),
            if (groups.overdue.isNotEmpty)
              _ReminderGroupBlock(
                title: '已逾期事项',
                items: groups.overdue.take(4).toList(),
                now: now,
                overdue: true,
                onOpenTodo: onOpenTodo,
                onToggleTodo: onToggleTodo,
                onOpenCourses: onOpenCourses,
              ),
            if (suggestions.isNotEmpty)
              _SuggestionSection(
                suggestions: suggestions,
                todayKey: todayKey,
                onOpenTodo: onOpenTodo,
                onAddToday: onAddToday,
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _ReminderGroupBlock extends StatelessWidget {
  final String title;
  final List<_TodayReminderItem> items;
  final DateTime now;
  final bool overdue;
  final ValueChanged<String> onOpenTodo;
  final ValueChanged<TodoItem> onToggleTodo;
  final VoidCallback onOpenCourses;

  const _ReminderGroupBlock({
    required this.title,
    required this.items,
    required this.now,
    required this.onOpenTodo,
    required this.onToggleTodo,
    required this.onOpenCourses,
    this.overdue = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = overdue ? cs.error : cs.primary;
    final backgroundColor = overdue
        ? Color.alphaBlend(
            cs.error.withValues(alpha: 0.10),
            cs.surfaceContainerHighest,
          )
        : cs.surfaceContainerHighest.withValues(alpha: 0.28);
    final borderColor = overdue
        ? cs.error.withValues(alpha: 0.38)
        : color.withValues(alpha: 0.1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: overdue ? 0.9 : 0.7),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 2),
              child: Row(
                children: [
                  Icon(
                    overdue
                        ? Icons.warning_amber_outlined
                        : Icons.notifications_none_outlined,
                    size: 16,
                    color: color,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: overdue ? cs.error : cs.onSurface,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  if (overdue) ...[
                    const SizedBox(width: 8),
                    _OverdueReminderBadge(color: cs.error),
                  ],
                  const Spacer(),
                  Text(
                    '${items.length} 项',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            ...items.map(
              (item) => _TodayReminderTile(
                item: item,
                now: now,
                overdue: overdue,
                onOpenTodo: onOpenTodo,
                onToggleTodo: onToggleTodo,
                onOpenCourses: onOpenCourses,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverdueReminderTitle extends StatelessWidget {
  final String title;
  final Color color;
  final bool completed;

  const _OverdueReminderTitle({
    required this.title,
    required this.color,
    this.completed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _OverdueReminderBadge(color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              decoration: completed ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _OverdueReminderBadge extends StatelessWidget {
  final Color color;

  const _OverdueReminderBadge({required this.color});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 0.7),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.priority_high_rounded, size: 10, color: color),
            const SizedBox(width: 2),
            Text('逾期', style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }
}

class _TodayReminderTile extends StatelessWidget {
  final _TodayReminderItem item;
  final DateTime now;
  final bool overdue;
  final ValueChanged<String> onOpenTodo;
  final ValueChanged<TodoItem> onToggleTodo;
  final VoidCallback onOpenCourses;

  const _TodayReminderTile({
    required this.item,
    required this.now,
    required this.overdue,
    required this.onOpenTodo,
    required this.onToggleTodo,
    required this.onOpenCourses,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final todo = item.todo;
    final isTodo = item.kind == _TodayReminderKind.todo;
    final overdueTitleColor = cs.error;
    final overdueSubtitleColor = cs.error.withValues(alpha: 0.86);
    final overdueBackground = Color.alphaBlend(
      cs.error.withValues(alpha: 0.08),
      cs.surface,
    );
    final overdueBorder = cs.error.withValues(alpha: 0.26);
    final accent = item.accentColor ?? (overdue ? cs.error : cs.primary);
    final title = overdue
        ? _OverdueReminderTitle(title: item.title, color: overdueTitleColor)
        : Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: cs.onSurface),
          );
    Widget tile = ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: isTodo
          ? Checkbox(
              value: todo?.isCompleted ?? false,
              shape: const CircleBorder(),
              onChanged: todo == null ? null : (_) => onToggleTodo(todo),
              side: overdue ? BorderSide(color: cs.error, width: 1.2) : null,
              checkColor: overdue ? cs.onError : null,
              fillColor: overdue
                  ? WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return cs.error;
                      }
                      return cs.error.withValues(alpha: 0.10);
                    })
                  : null,
            )
          : CircleAvatar(
              radius: 13,
              backgroundColor: accent.withValues(alpha: overdue ? 0.18 : 0.14),
              child: Icon(Icons.menu_book_outlined, size: 14, color: accent),
            ),
      title: title,
      subtitle: Text(
        overdue
            ? '${item.subtitle} · ${_pastStatusLabel(item, now)}'
            : item.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: overdue ? overdueSubtitleColor : cs.onSurfaceVariant,
        ),
      ),
      trailing: Text(
        I18nDateFormat.time(item.time),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: overdue ? overdueTitleColor : cs.onSurfaceVariant,
        ),
      ),
      onTap: isTodo ? () => onOpenTodo(item.id) : onOpenCourses,
    );
    if (overdue && !isTodo) {
      tile = Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: overdueBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: overdueBorder, width: 0.7),
        ),
        child: tile,
      );
    }
    if (!isTodo || todo == null) return tile;
    return _TodayTodoSwipeTile(
      todo: todo,
      onToggle: () => onToggleTodo(todo),
      onOpen: () => onOpenTodo(item.id),
      title: item.title,
      titleWidget: overdue
          ? _OverdueReminderTitle(
              title: item.title,
              color: overdueTitleColor,
              completed: todo.isCompleted,
            )
          : null,
      titleColor: overdue ? overdueTitleColor : null,
      subtitle: Text(
        overdue
            ? '${item.subtitle} · ${_pastStatusLabel(item, now)}'
            : item.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: overdue ? overdueSubtitleColor : cs.onSurfaceVariant,
        ),
      ),
      trailing: Text(
        I18nDateFormat.time(item.time),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: overdue ? overdueTitleColor : cs.onSurfaceVariant,
        ),
      ),
      completedTextColor: overdue ? overdueTitleColor : null,
      tileBackground: overdue ? overdueBackground : null,
      tileBorderColor: overdue ? overdueBorder : null,
      showStatusDecoration: overdue,
    );
  }

  String _pastStatusLabel(_TodayReminderItem item, DateTime now) {
    final trigger = item.time;
    final triggerDay = DateTime(trigger.year, trigger.month, trigger.day);
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(triggerDay).inDays;
    if (days <= 0) {
      final minutes = now.difference(trigger).inMinutes.clamp(1, 999);
      return item.kind == _TodayReminderKind.course
          ? '已过期 $minutes 分钟'
          : '已过提醒 $minutes 分钟';
    }
    return '已逾期 $days 天';
  }
}

class _SuggestionSection extends StatelessWidget {
  final List<SmartScheduleSuggestion> suggestions;
  final DateTime todayKey;
  final ValueChanged<String> onOpenTodo;
  final Future<void> Function(TodoItem todo) onAddToday;

  const _SuggestionSection({
    required this.suggestions,
    required this.todayKey,
    required this.onOpenTodo,
    required this.onAddToday,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        maintainState: true,
        tilePadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
        childrenPadding: const EdgeInsets.only(bottom: 4),
        leading: Icon(
          Icons.auto_awesome,
          size: 18,
          color: cs.primary.withValues(alpha: 0.72),
        ),
        title: Text(
          I18n.tr('today.suggestions'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.normal,
          ),
        ),
        subtitle: Text(
          '${I18n.tr('today.suggestions.subtitle')} · 默认收起',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.58),
          ),
        ),
        children: suggestions.map((suggestion) {
          final t = suggestion.todo;
          return _TodayTodoSwipeTile(
            todo: t,
            onToggle: () {},
            onOpen: () => onOpenTodo(t.id),
            leading: Icon(
              Icons.auto_awesome,
              size: 18,
              color: cs.primary.withValues(alpha: 0.66),
            ),
            title: t.title,
            titleColor: cs.onSurface.withValues(alpha: 0.76),
            subtitle: Text(
              suggestion.reason,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
            trailing: _sameDay(t.date, todayKey) || t.isArchivedAfterRollover
                ? null
                : TextButton(
                    onPressed: () => onAddToday(t),
                    child: Text(I18n.tr('today.add_to_today')),
                  ),
          );
        }).toList(),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _QuoteCardState extends State<_QuoteCard> {
  late String _text;

  @override
  void initState() {
    super.initState();
    _text = DailyQuotes.today();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      onTap: () => setState(() => _text = DailyQuotes.random()),
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.format_quote,
              color: cs.primary.withValues(alpha: 0.7),
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _text,
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
          ),
          Icon(Icons.refresh, size: 16, color: Colors.grey.shade500),
        ],
      ),
    );
  }
}
