import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/goal_icons.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/lunar_calendar.dart';
import '../core/quotes.dart';
import '../core/report_engine.dart';
import '../core/smart_schedule_advisor.dart';
import '../models/todo.dart';
import '../providers/anniversary_provider.dart';
import '../providers/course_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/pomodoro_provider.dart';
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
    context.select<PomodoroProvider, int>(
      (provider) => provider.persistedRevision,
    );
    final pomoP = context.read<PomodoroProvider>();
    final diaryP = context.watch<DiaryProvider>();
    final timeAuditP = context.watch<TimeAuditProvider>();
    final anniP = context.watch<AnniversaryProvider>();
    final courseP = context.watch<CourseProvider>();
    final goalP = context.watch<GoalProvider>();
    final user = context.watch<UserProvider>();

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
      timeEntries: timeAuditP.entries,
    );
    final previousWeeklyReport = ReportEngine.buildReport(
      start: previousWeekStart,
      end: previousWeekEnd,
      todos: todoP.todos,
      habits: habitP.habits,
      sessions: pomoP.sessions,
      timeEntries: timeAuditP.entries,
    );
    final weeklyComparison = ReportEngine.compare(
      current: weeklyReport,
      previous: previousWeeklyReport,
    );
    final lunar = LunarCalendar.fromSolar(now);
    final term = LunarCalendar.solarTerm(now);
    final festival =
        LunarCalendar.solarFestival(now) ?? LunarCalendar.lunarFestival(lunar);

    var todayTodosCount = 0;
    final todayTodos = <TodoItem>[];
    var todayTodoCompleted = 0;
    for (final todo in todoP.todos) {
      final d = DateTime(todo.date.year, todo.date.month, todo.date.day);
      if (d != todayKey) continue;
      todayTodosCount++;
      if (todo.isCompleted) {
        todayTodoCompleted++;
      }
      todayTodos.add(todo);
    }
    todayTodos.sort((a, b) {
      if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
      return a.quadrant.index.compareTo(b.quadrant.index);
    });

    final todayCourses = courseP.todayCourses
      ..sort((a, b) => a.startSection.compareTo(b.startSection));
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('${user.profile.greeting}，${user.profile.username}'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
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
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${I18n.tr('calendar.chinese_lunar_calendar')} ${lunar.chineseText}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
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
                      fontWeight: FontWeight.w400,
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
                    value: '${pomoP.sessionCountToday}',
                    unit: I18n.tr('today.unit.times'),
                    icon: Icons.timer,
                    color: Colors.redAccent,
                    onTap: () => _go(context, const PomodoroScreen()),
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

          _TodayProductivityCard(
            comparison: weeklyComparison,
            onTap: () => _go(context, const StatisticsScreen()),
          ),

          const SizedBox(height: 10),

          if (suggestions.isNotEmpty)
            _section(
              I18n.tr('today.suggestions'),
              subtitle: I18n.tr('today.suggestions.subtitle'),
              onMore: () =>
                  TodayDetailRouter.open(context, TodaySectionKind.todos),
              child: Column(
                children: suggestions.map((suggestion) {
                  final t = suggestion.todo;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.auto_awesome,
                      size: 18,
                      color: cs.primary,
                    ),
                    title: Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      suggestion.reason,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing:
                        _isSameDay(t.date, todayKey) ||
                            t.isArchivedAfterRollover
                        ? null
                        : TextButton(
                            onPressed: () async {
                              final changed = await context
                                  .read<TodoProvider>()
                                  .scheduleTodoForToday(t.id, now: now);
                              if (!context.mounted || !changed) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${I18n.tr('today.added_prefix')}${t.title}',
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            child: Text(I18n.tr('today.add_to_today')),
                          ),
                    onTap: () => TodayDetailRouter.open(
                      context,
                      TodaySectionKind.todos,
                      id: t.id,
                    ),
                  );
                }).toList(),
              ),
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
                  return ListTile(
                    dense: true,
                    leading: Checkbox(
                      value: t.isCompleted,
                      shape: const CircleBorder(),
                      onChanged: (_) =>
                          completeTodoWithOptionalTimeRecord(context, t),
                    ),
                    title: Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        decoration: t.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        color: t.isCompleted
                            ? cs.onSurface.withValues(alpha: 0.52)
                            : null,
                      ),
                    ),
                    subtitle: _TodoTodaySubtitle(todo: t),
                    onTap: () => TodayDetailRouter.open(
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
                          fontWeight: FontWeight.w400,
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
                          fontWeight: FontWeight.w400,
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
                    fontWeight: FontWeight.w400,
                    color: cs.onSurface,
                  ),
                  actionTextStyle: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w400,
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

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _go(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BrandRouteSurface(child: screen)),
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      borderRadius: BorderRadius.circular(18),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
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
                    fontSize: 22,
                    height: 1,
                    color: cs.primary,
                    fontWeight: FontWeight.w400,
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
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
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
                    fontSize: 11,
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
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
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
    final subtasks = todo.subtasks.take(3).toList();
    if (todo.listGroupName == null && subtasks.isEmpty) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
