import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/completion_visibility_policy.dart';
import '../core/design_tokens.dart';
import '../core/goal_icons.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/lunar_calendar.dart';
import '../core/quotes.dart';
import '../core/report_engine.dart';
import '../core/smart_schedule_advisor.dart';
import '../core/todo_templates.dart';
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
    final themeProvider = context.watch<ThemeProvider>();
    final s = themeProvider.brand.strings;

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
    final suitable = LunarCalendar.suitable(now);
    final avoid = LunarCalendar.avoid(now);

    final todayTodos = todoP.visibleTodayTodos(now);
    final todayTodosCount = todayTodos.length;
    final completedTodayCount = todoP.todos.where((todo) {
      final completedAt = todo.completedAt;
      if (!todo.isCompleted || completedAt == null) return false;
      return completedAt.year == todayKey.year &&
          completedAt.month == todayKey.month &&
          completedAt.day == todayKey.day;
    }).length;
    final noDueTodayTodos = todayTodos.where((todo) => todo.dueDate == null);
    todayTodos.sort((a, b) {
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
      todoP.todos.where(
        (todo) => !CompletionVisibilityPolicy.shouldShowInToday(todo, now),
      ),
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
          // 日期卡
          _TodayAlmanacCard(
            now: now,
            lunarText: lunar.chineseText,
            suitable: suitable,
            avoid: avoid,
            term: term,
            festival: festival,
            onTap: () => _go(context, AlmanacScreen(initialDate: now)),
          ),
          const SizedBox(height: 12),

          _TodayProductivitySection(
            onTap: () => _go(context, const StatisticsScreen()),
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

          // 今日待办
          _section(
            I18n.tr('today.todos'),
            subtitle:
                '$todayTodosCount ${I18n.tr('today.unit.item')} · ${I18n.tr('today.completed')} $completedTodayCount · 无截止 ${noDueTodayTodos.length}',
            onMore: () =>
                TodayDetailRouter.open(context, TodaySectionKind.todos),
            child: todayTodos.isEmpty
                ? _TodayTodoEmptyState(
                    onTap: () =>
                        TodayDetailRouter.open(context, TodaySectionKind.todos),
                  )
                : Column(
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
                final actionNow = DateTime.now();
                final changed = await context
                    .read<TodoProvider>()
                    .scheduleTodoForToday(
                      todo.id,
                      now: actionNow,
                      waitForReminderSync: false,
                    );
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
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
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

  void _go(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BrandRouteSurface(child: screen)),
    );
  }
}

class _TodayAlmanacCard extends StatelessWidget {
  final DateTime now;
  final String lunarText;
  final String suitable;
  final String avoid;
  final String? term;
  final String? festival;
  final VoidCallback onTap;

  const _TodayAlmanacCard({
    required this.now,
    required this.lunarText,
    required this.suitable,
    required this.avoid,
    required this.term,
    required this.festival,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final brand = context.watch<ThemeProvider>().brand;
    final radius = BorderRadius.circular(DesignTokens.radiusCard);
    final foreground = isDark ? Colors.white : cs.onSurface;
    final muted = foreground.withValues(alpha: isDark ? 0.74 : 0.68);
    final accent = cs.primary;
    final backgroundAsset = brand.backgroundAsset;

    final fallbackGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.alphaBlend(
          accent.withValues(alpha: isDark ? 0.26 : 0.16),
          cs.surface,
        ),
        Color.alphaBlend(
          cs.secondary.withValues(alpha: isDark ? 0.20 : 0.12),
          cs.surface,
        ),
      ],
    );
    final imageOverlay = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
              Colors.black.withValues(alpha: 0.42),
              cs.surface.withValues(alpha: 0.72),
            ]
          : [
              brand.backgroundOverlay.withValues(alpha: 0.62),
              cs.surface.withValues(alpha: 0.76),
            ],
    );

    return AppSurfaceCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      borderRadius: radius,
      color: Colors.transparent,
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.10)
            : cs.outlineVariant.withValues(alpha: 0.18),
        width: 0.55,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned.fill(
              child: backgroundAsset == null
                  ? DecoratedBox(
                      decoration: BoxDecoration(gradient: fallbackGradient),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final dpr = MediaQuery.devicePixelRatioOf(
                          context,
                        ).clamp(1.0, 3.0);
                        final fallbackSize = MediaQuery.sizeOf(context);
                        final width = constraints.hasBoundedWidth
                            ? constraints.maxWidth
                            : fallbackSize.width;
                        final height = constraints.hasBoundedHeight
                            ? constraints.maxHeight
                            : 180.0;
                        final cacheWidth = (width * dpr).ceil().clamp(1, 2048);
                        final cacheHeight = (height * dpr).ceil().clamp(
                          1,
                          2048,
                        );
                        return Image.asset(
                          backgroundAsset,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          cacheWidth: cacheWidth,
                          cacheHeight: cacheHeight,
                          filterQuality: FilterQuality.low,
                          gaplessPlayback: true,
                        );
                      },
                    ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: imageOverlay),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${I18n.tr('today.almanac.title')} · ${I18nDateFormat.monthDayWithWeekday(now)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                            fontSize: 12.5,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${I18n.tr('calendar.chinese_lunar_calendar')} $lunarText',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: foreground,
                            fontSize: 15.5,
                            height: 1.25,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '宜 $suitable',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: foreground.withValues(alpha: 0.86),
                            fontSize: 12,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '忌 $avoid',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                            fontSize: 12,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (term != null)
                              _TodayCalendarChip(text: term!, color: accent),
                            if (festival != null)
                              _TodayCalendarChip(
                                text: festival!,
                                color: cs.tertiary,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: cs.surface.withValues(alpha: isDark ? 0.22 : 0.58),
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusControl,
                      ),
                      border: Border.all(
                        color: foreground.withValues(
                          alpha: isDark ? 0.12 : 0.10,
                        ),
                        width: 0.55,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${now.day}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: foreground,
                        fontSize: 27,
                        height: 1,
                        fontWeight: FontWeight.normal,
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

class _TodayCalendarChip extends StatelessWidget {
  final String text;
  final Color color;

  const _TodayCalendarChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.16), width: 0.45),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 11,
          color: color,
          height: 1.1,
          fontWeight: FontWeight.normal,
        ),
      ),
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
      borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
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
                          fontSize: 16,
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

class _TodayTodoEmptyState extends StatelessWidget {
  final VoidCallback onTap;

  const _TodayTodoEmptyState({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.56),
              width: 0.7,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.checklist_rtl_outlined, size: 17, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '今天暂无待办，点击查看或添加任务',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.normal,
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

class _TodoTodaySubtitle extends StatelessWidget {
  final TodoItem todo;

  const _TodoTodaySubtitle({required this.todo});

  @override
  Widget build(BuildContext context) {
    final visual = CompletionVisibilityPolicy.visualState(todo);
    final subtasks = todo.subtasks.take(3).toList();
    final hasNoDueDate = todo.dueDate == null;
    if (todo.listGroupName == null &&
        subtasks.isEmpty &&
        visual == TodoVisualState.normal &&
        !hasNoDueDate) {
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
          if (hasNoDueDate) const _TodayNoDueDateLabel(),
          if ((visual != TodoVisualState.normal || hasNoDueDate) &&
              (todo.listGroupName != null || subtasks.isNotEmpty))
            const SizedBox(height: 3),
          if (todo.listGroupName != null) _TodoListTemplateLabel(todo: todo),
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

class _TodayNoDueDateLabel extends StatelessWidget {
  const _TodayNoDueDateLabel();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      '无截止日期',
      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
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

class _TodoTemplateVisual {
  final IconData icon;
  final Color color;
  final String key;

  const _TodoTemplateVisual({
    required this.icon,
    required this.color,
    required this.key,
  });
}

TodoListTemplate? _todoListTemplateFor(String? name) {
  final target = name?.trim();
  if (target == null || target.isEmpty) return null;
  for (final template in TodoListTemplates.all) {
    if (template.name == target) return template;
  }
  return null;
}

_TodoTemplateVisual _todoTemplateVisual(BuildContext context, TodoItem todo) {
  final template = _todoListTemplateFor(todo.listGroupName);
  if (template != null) {
    return _TodoTemplateVisual(
      icon: template.icon,
      color: template.color,
      key: template.name,
    );
  }
  return _TodoTemplateVisual(
    icon: _todoQuadrantIcon(todo.quadrant),
    color: _todoQuadrantColor(todo.quadrant),
    key: 'quadrant_${todo.quadrant.index}',
  );
}

IconData _todoQuadrantIcon(EisenhowerQuadrant quadrant) {
  return switch (quadrant) {
    EisenhowerQuadrant.urgentImportant => Icons.priority_high_outlined,
    EisenhowerQuadrant.notUrgentImportant => Icons.flag_outlined,
    EisenhowerQuadrant.urgentNotImportant => Icons.bolt_outlined,
    EisenhowerQuadrant.notUrgentNotImportant => Icons.checklist_rounded,
  };
}

Color _todoQuadrantColor(EisenhowerQuadrant quadrant) {
  return switch (quadrant) {
    EisenhowerQuadrant.urgentImportant => const Color(0xFFE53935),
    EisenhowerQuadrant.notUrgentImportant => const Color(0xFFF6A339),
    EisenhowerQuadrant.urgentNotImportant => const Color(0xFF42A5F5),
    EisenhowerQuadrant.notUrgentNotImportant => const Color(0xFF8E8E8E),
  };
}

class _TodoListTemplateLabel extends StatelessWidget {
  final TodoItem todo;

  const _TodoListTemplateLabel({required this.todo});

  @override
  Widget build(BuildContext context) {
    final label = todo.listGroupName?.trim();
    if (label == null || label.isEmpty) return const SizedBox.shrink();
    final template = _todoListTemplateFor(label);
    final cs = Theme.of(context).colorScheme;
    final color = template?.color ?? cs.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          template?.icon ?? Icons.folder_outlined,
          key: ValueKey('today_todo_list_icon_${template?.name ?? 'custom'}'),
          size: 11,
          color: color,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: color),
          ),
        ),
      ],
    );
  }
}

class _TodoTemplateAvatar extends StatelessWidget {
  final TodoItem todo;
  final String keyPrefix;
  final double radius;
  final double iconSize;

  const _TodoTemplateAvatar({
    required this.todo,
    required this.keyPrefix,
    this.radius = 14,
    this.iconSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    final visual = _todoTemplateVisual(context, todo);
    return CircleAvatar(
      key: ValueKey('${keyPrefix}_${visual.key}'),
      radius: radius,
      backgroundColor: visual.color.withValues(alpha: 0.13),
      child: Icon(visual.icon, size: iconSize, color: visual.color),
    );
  }
}

class _TodayTodoLeading extends StatelessWidget {
  static const double width = 30;
  static const double height = 28;
  static const double statusButtonSize = 22;

  final Color? statusColor;
  final bool isCompleted;
  final Color? completedCheckColor;
  final ValueChanged<bool?>? onChanged;

  const _TodayTodoLeading({
    required this.statusColor,
    required this.isCompleted,
    required this.completedCheckColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Center(
        child: _TodayTodoStatusToggle(
          color: statusColor,
          isCompleted: isCompleted,
          completedCheckColor: completedCheckColor,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _TodayTodoTitleLine extends StatelessWidget {
  final TodoItem todo;
  final String title;
  final Color? titleColor;
  final bool completed;
  final bool overdue;
  final String iconKeyPrefix;

  const _TodayTodoTitleLine({
    required this.todo,
    required this.title,
    required this.completed,
    required this.overdue,
    required this.iconKeyPrefix,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = titleColor ?? (overdue ? cs.error : cs.onSurface);
    return Row(
      children: [
        _TodoTemplateAvatar(
          todo: todo,
          keyPrefix: iconKeyPrefix,
          radius: 10,
          iconSize: 12,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: effectiveColor,
              decoration: completed ? TextDecoration.lineThrough : null,
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
        if (overdue) ...[
          const SizedBox(width: 6),
          _OverdueReminderBadge(color: cs.error),
        ],
      ],
    );
  }
}

class _TodayTodoStatusToggle extends StatelessWidget {
  final Color? color;
  final bool isCompleted;
  final Color? completedCheckColor;
  final ValueChanged<bool?>? onChanged;

  const _TodayTodoStatusToggle({
    required this.color,
    required this.isCompleted,
    required this.completedCheckColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = color ?? cs.primary;
    final background = isCompleted
        ? accent
        : Color.alphaBlend(accent.withValues(alpha: 0.08), cs.surface);
    final foreground = completedCheckColor ?? cs.onPrimary;
    final enabled = onChanged != null;
    return Semantics(
      button: true,
      checked: isCompleted,
      label: isCompleted ? '标记为未完成' : '标记为完成',
      child: Material(
        color: background,
        shape: CircleBorder(
          side: BorderSide(
            color: accent.withValues(alpha: isCompleted ? 0.24 : 0.34),
            width: 0.9,
          ),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? () => onChanged?.call(!isCompleted) : null,
          child: SizedBox(
            width: _TodayTodoLeading.statusButtonSize,
            height: _TodayTodoLeading.statusButtonSize,
            child: isCompleted
                ? Icon(Icons.check_rounded, size: 14, color: foreground)
                : null,
          ),
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
  final Color? titleColor;
  final Color? completedTextColor;
  final Widget? subtitle;
  final Widget? trailing;
  final Color? tileBackground;
  final Color? tileBorderColor;
  final bool showStatusDecoration;
  final String iconKeyPrefix;
  final bool showOverdueBadge;

  const _TodayTodoSwipeTile({
    required this.todo,
    required this.onToggle,
    required this.onOpen,
    this.leading,
    this.title,
    this.titleColor,
    this.completedTextColor,
    this.subtitle,
    this.trailing,
    this.tileBackground,
    this.tileBorderColor,
    this.showStatusDecoration = true,
    this.iconKeyPrefix = 'today_todo_template_icon',
    this.showOverdueBadge = false,
  });

  @override
  State<_TodayTodoSwipeTile> createState() => _TodayTodoSwipeTileState();
}

class _TodayTodoSwipeTileState extends State<_TodayTodoSwipeTile> {
  static const double _swipeActionWidth = 56;
  static const double _swipeOpenThreshold = 30;

  double _swipeOffset = 0;
  bool _dragging = false;

  bool get _swipeOpen => _swipeOffset > 0;
  bool get _swipeActive => _swipeOffset > 0;

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
    final templateVisual = _todoTemplateVisual(context, todo);
    final statusColor = widget.showStatusDecoration
        ? switch (visual) {
            TodoVisualState.completed => cs.tertiary,
            TodoVisualState.overdue => cs.error,
            TodoVisualState.dueSoon => Colors.orange.shade700,
            TodoVisualState.normal => templateVisual.color,
            TodoVisualState.archived => cs.outline,
          }
        : null;
    final backgroundAlpha = switch (visual) {
      TodoVisualState.completed => 0.06,
      TodoVisualState.overdue => 0.09,
      TodoVisualState.dueSoon => 0.07,
      TodoVisualState.normal => 0.035,
      TodoVisualState.archived => 0.04,
    };
    final borderAlpha = switch (visual) {
      TodoVisualState.completed => 0.24,
      TodoVisualState.overdue => 0.30,
      TodoVisualState.dueSoon => 0.24,
      TodoVisualState.normal => 0.16,
      TodoVisualState.archived => 0.18,
    };
    final effectiveTileBackground =
        widget.tileBackground ??
        (statusColor == null
            ? null
            : Color.alphaBlend(
                statusColor.withValues(alpha: backgroundAlpha),
                cs.surface,
              ));
    final effectiveTileBorderColor =
        widget.tileBorderColor ?? statusColor?.withValues(alpha: borderAlpha);
    final canEdit = context.select<ShareProvider?, bool>(
      (share) => share?.canEdit(todo.workspaceId) ?? true,
    );
    final effectiveTitleColor = todo.isCompleted
        ? widget.completedTextColor ?? cs.onSurface.withValues(alpha: 0.52)
        : widget.titleColor ?? (isOverdue ? cs.error : null);
    Widget tile = Material(
      color: Colors.transparent,
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        horizontalTitleGap: 4,
        minLeadingWidth: widget.leading == null ? _TodayTodoLeading.width : 30,
        leading:
            widget.leading ??
            _TodayTodoLeading(
              statusColor: statusColor,
              isCompleted: isCompleted,
              completedCheckColor: cs.onTertiary,
              onChanged: canEdit
                  ? (_) => widget.onToggle()
                  : (_) => _showReadOnlyMessage('完成任务'),
            ),
        title: _TodayTodoTitleLine(
          todo: todo,
          title: widget.title ?? todo.title,
          titleColor: effectiveTitleColor,
          completed: todo.isCompleted,
          overdue: widget.showOverdueBadge || isOverdue,
          iconKeyPrefix: widget.iconKeyPrefix,
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
  final bool completed;

  const _TodayReminderItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.time,
    required this.subtitle,
    this.todo,
    this.accentColor,
    this.completed = false,
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
    final completedToday = <_TodayReminderItem>[];
    final soonLimit = now.add(const Duration(hours: 6));

    for (final todo in todos) {
      if (todo.isArchivedAfterRollover) continue;
      final trigger = _todoTriggerTime(todo);
      if (trigger == null) continue;
      final item = _TodayReminderItem(
        kind: _TodayReminderKind.todo,
        id: todo.id,
        title: todo.title,
        time: trigger,
        subtitle: _todoReminderSubtitle(todo, trigger, now),
        todo: todo,
        completed: todo.isCompleted,
      );
      if (todo.isCompleted) {
        if (_sameDay(todo.completedAt ?? trigger, todayKey)) {
          completedToday.add(item);
        }
      } else if (trigger.isBefore(now)) {
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
    completedToday.sort(compare);

    return _TodayReminderGroups(
      dueToday: [...dueToday, ...completedToday],
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

class _TodayReminderSection extends StatefulWidget {
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
  State<_TodayReminderSection> createState() => _TodayReminderSectionState();
}

class _TodayReminderSectionState extends State<_TodayReminderSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final total =
        widget.groups.dueToday.length +
        widget.groups.upcoming.length +
        widget.groups.overdue.length;
    final subtitle = widget.suggestions.isEmpty
        ? '$total 项 · 今日待提醒 > 即将开始 > 逾期优先处理'
        : '$total 项提醒 · 今日待提醒 > 即将开始 > 逾期优先处理 > 今日建议';
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: AppSurfaceCard(
        key: const ValueKey('today_reminder_section_collapsed_by_default'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              key: const ValueKey('today_reminder_header_toggle'),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(DesignTokens.radiusCard),
              ),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '今日提醒',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              height: 1.25,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _expanded ? subtitle : '$subtitle · 默认收起',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withValues(alpha: 0.56),
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => TodayDetailRouter.open(
                        context,
                        TodaySectionKind.todos,
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: cs.primary,
                        textStyle: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.normal,
                        ),
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(I18n.tr('today.view')),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded && widget.groups.dueToday.isNotEmpty)
              _ReminderGroupBlock(
                title: '今日待提醒事项',
                items: widget.groups.dueToday.take(4).toList(),
                now: widget.now,
                onOpenTodo: widget.onOpenTodo,
                onToggleTodo: widget.onToggleTodo,
                onOpenCourses: widget.onOpenCourses,
              ),
            if (_expanded && widget.groups.upcoming.isNotEmpty)
              _ReminderGroupBlock(
                title: '即将开始事项',
                items: widget.groups.upcoming.take(4).toList(),
                now: widget.now,
                onOpenTodo: widget.onOpenTodo,
                onToggleTodo: widget.onToggleTodo,
                onOpenCourses: widget.onOpenCourses,
              ),
            if (_expanded && widget.groups.overdue.isNotEmpty)
              _ReminderGroupBlock(
                title: '已逾期事项',
                items: widget.groups.overdue.take(4).toList(),
                now: widget.now,
                overdue: true,
                onOpenTodo: widget.onOpenTodo,
                onToggleTodo: widget.onToggleTodo,
                onOpenCourses: widget.onOpenCourses,
              ),
            if (_expanded && widget.suggestions.isNotEmpty)
              _SuggestionSection(
                suggestions: widget.suggestions,
                todayKey: widget.todayKey,
                onOpenTodo: widget.onOpenTodo,
                onAddToday: widget.onAddToday,
              ),
            SizedBox(height: _expanded ? 4 : 8),
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

  const _OverdueReminderTitle({required this.title, required this.color});

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
            style: TextStyle(color: color),
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
    final completed = item.completed || (todo?.isCompleted ?? false);
    final overdueTitleColor = cs.error;
    final overdueSubtitleColor = cs.error.withValues(alpha: 0.86);
    final completedColor = const Color(0xFF4CAF50);
    final completedBackground = Color.alphaBlend(
      completedColor.withValues(alpha: 0.08),
      cs.surface,
    );
    final completedBorder = completedColor.withValues(alpha: 0.22);
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
            style: TextStyle(
              color: completed ? completedColor : cs.onSurface,
              decoration: completed ? TextDecoration.lineThrough : null,
            ),
          );
    if (isTodo && todo != null) {
      return _TodayTodoSwipeTile(
        todo: todo,
        onToggle: () => onToggleTodo(todo),
        onOpen: () => onOpenTodo(item.id),
        leading: _TodayTodoLeading(
          statusColor: overdue
              ? cs.error
              : completed
              ? completedColor
              : _todoTemplateVisual(context, todo).color,
          isCompleted: completed,
          completedCheckColor: overdue ? cs.onError : cs.onTertiary,
          onChanged: (_) => onToggleTodo(todo),
        ),
        title: item.title,
        titleColor: overdue
            ? overdueTitleColor
            : completed
            ? completedColor
            : null,
        iconKeyPrefix: 'today_reminder_template_icon',
        showOverdueBadge: overdue,
        subtitle: Text(
          overdue
              ? '${item.subtitle} · ${_pastStatusLabel(item, now)}'
              : item.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: overdue
                ? overdueSubtitleColor
                : completed
                ? completedColor.withValues(alpha: 0.82)
                : cs.onSurfaceVariant,
          ),
        ),
        trailing: Text(
          I18nDateFormat.time(item.time),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: overdue
                ? overdueTitleColor
                : completed
                ? completedColor
                : cs.onSurfaceVariant,
          ),
        ),
        completedTextColor: overdue
            ? overdueTitleColor
            : completed
            ? completedColor
            : null,
        tileBackground: overdue
            ? overdueBackground
            : completed
            ? completedBackground
            : null,
        tileBorderColor: overdue
            ? overdueBorder
            : completed
            ? completedBorder
            : null,
        showStatusDecoration: true,
      );
    }
    Widget tile = ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: const SizedBox(width: 4),
      minLeadingWidth: 4,
      horizontalTitleGap: 4,
      title: Row(
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: accent.withValues(alpha: overdue ? 0.18 : 0.14),
            child: Icon(Icons.menu_book_outlined, size: 12, color: accent),
          ),
          const SizedBox(width: 7),
          Expanded(child: title),
        ],
      ),
      subtitle: Text(
        overdue
            ? '${item.subtitle} · ${_pastStatusLabel(item, now)}'
            : item.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: overdue
              ? overdueSubtitleColor
              : completed
              ? completedColor.withValues(alpha: 0.82)
              : cs.onSurfaceVariant,
        ),
      ),
      trailing: Text(
        I18nDateFormat.time(item.time),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: overdue
              ? overdueTitleColor
              : completed
              ? completedColor
              : cs.onSurfaceVariant,
        ),
      ),
      onTap: onOpenCourses,
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
    return tile;
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

class _SuggestionSection extends StatefulWidget {
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
  State<_SuggestionSection> createState() => _SuggestionSectionState();
}

class _SuggestionSectionState extends State<_SuggestionSection> {
  final Set<String> _addingTodoIds = <String>{};

  Future<void> _addToday(TodoItem todo) async {
    if (_addingTodoIds.contains(todo.id)) return;
    setState(() => _addingTodoIds.add(todo.id));
    try {
      await widget.onAddToday(todo);
    } finally {
      if (mounted) setState(() => _addingTodoIds.remove(todo.id));
    }
  }

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
        children: widget.suggestions.map((suggestion) {
          final t = suggestion.todo;
          final adding = _addingTodoIds.contains(t.id);
          return _TodayTodoSwipeTile(
            todo: t,
            onToggle: () {},
            onOpen: () => widget.onOpenTodo(t.id),
            title: t.title,
            titleColor: cs.onSurface.withValues(alpha: 0.76),
            iconKeyPrefix: 'today_suggestion_template_icon',
            subtitle: Text(
              suggestion.reason,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
            trailing:
                _sameDay(t.date, widget.todayKey) || t.isArchivedAfterRollover
                ? null
                : SizedBox(
                    width: 74,
                    height: 30,
                    child: TextButton(
                      key: ValueKey('today_suggestion_add_${t.id}'),
                      onPressed: adding ? null : () => _addToday(t),
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: adding
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                I18n.tr('today.add_to_today'),
                                maxLines: 1,
                              ),
                            ),
                    ),
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
      borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
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
