import '../widgets/app_date_format.dart';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/almanac_locale_format.dart';
import '../core/almanac_ui_copy.dart';
import '../core/app_brand.dart';
import '../core/brand_strings.dart';
import '../core/completion_visibility_policy.dart';
import '../core/design_tokens.dart';
import '../core/desktop_tokens.dart';
import '../core/goal_icons.dart';
import '../core/i18n.dart';
import '../core/calendar_date_navigation.dart';
import '../core/i18n_date_format.dart';
import '../core/lunar_calendar.dart';
import '../core/quotes.dart';
import '../core/report_engine.dart';
import '../core/smart_schedule_advisor.dart';
import '../core/today_ui_copy.dart';
import '../core/todo_board_ui_copy.dart';
import '../core/todo_ui_copy.dart';
import '../core/todo_templates.dart';
import '../models/course_schedule.dart' show CourseItem, ScheduleSettings;
import '../models/todo.dart';
import '../providers/anniversary_provider.dart';
import '../providers/app_lock_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/course_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/share_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/time_audit_provider.dart';
import '../providers/todo_provider.dart';
import '../providers/user_provider.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/app_update_service.dart';
import '../services/holiday_calendar.dart';
import '../services/settings_action_origin.dart';
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

List<TodoItem> _visibleTodayOverviewTodos(
  Iterable<TodoItem> todos,
  DateTime now,
) {
  final today = CompletionVisibilityPolicy.dateOnly(now);
  return todos.where((todo) {
    if (todo.isArchivedAfterRollover) return false;
    if (todo.isCompleted) {
      final completedAt = todo.completedAt;
      return completedAt != null &&
          CompletionVisibilityPolicy.dateOnly(completedAt) == today;
    }
    final due = todo.dueDate;
    if (due == null) return true;
    final dueDay = CompletionVisibilityPolicy.dateOnly(due);
    if (dueDay.isBefore(today)) return false;
    if (CompletionVisibilityPolicy.isDateOnly(due)) return true;
    return !due.isBefore(now);
  }).toList();
}

VoidCallback _todayTodoCompletionAction(BuildContext context, TodoItem todo) {
  final origin = SettingsActionOrigin(context);
  final todos = context.read<TodoProvider>();
  final share = context.read<ShareProvider?>();

  bool isCurrent({bool checkRoute = true, bool checkTodo = true}) =>
      origin.isCurrent(checkRoute: checkRoute) &&
      identical(context.read<TodoProvider>(), todos) &&
      identical(context.read<ShareProvider?>(), share) &&
      (share?.canEdit(todo.workspaceId) ?? true) &&
      (!checkTodo || todos.todos.any((item) => identical(item, todo)));

  return () async {
    if (!isCurrent()) return;
    if (!todo.isCompleted) {
      await completeTodoWithOptionalTimeRecord(
        context,
        todo,
        isAccessAvailable: () => isCurrent(checkRoute: false),
        isFeedbackAvailable: () => isCurrent(checkTodo: false),
      );
      return;
    }
    try {
      final changed = await todos.reopenTodos([todo.id]);
      if (!context.mounted || changed == 0 || !isCurrent(checkTodo: false)) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (_, _, _) =>
                Text(TodoBoardUiCopy.restoredFeedback(todo.title)),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error, stack) {
      debugPrint('[Today] reopen failed: $error\n$stack');
      if (!context.mounted || !isCurrent(checkTodo: false)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (_, _, _) => Text(TodoUiCopy.completionFailedFeedback),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  };
}

/// 今日概览：登录后展示的聚合首屏。
class TodayScreen extends StatelessWidget
    implements LocaleStatePreservingRoute {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final brand = context.select<ThemeProvider, AppBrand>((t) => t.brand);

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
    final showLunar = context.select<PreferencesProvider?, bool>(
      (p) => p?.showLunar ?? true,
    );
    final shareProvider = context.watch<ShareProvider?>();
    context.select<AuthProvider?, Object?>(
      (auth) => (
        auth?.sessionGeneration,
        auth?.isAccountTransitionInProgress,
        auth?.isLocalAccountDataBlocked,
      ),
    );
    context.select<PreferencesProvider?, int?>(
      (prefs) => prefs?.storageGeneration,
    );
    context.select<AppLockProvider?, bool?>((lock) => lock?.isLocked);
    context.select<AppUpdateService?, bool?>((update) => update?.mustUpdate);

    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final s = brand.strings;
        final now = DateTime.now();
        final todayKey = DateTime(now.year, now.month, now.day);
        final lunar = LunarCalendar.fromSolar(now);
        final term = LunarCalendar.solarTerm(now);
        final festival =
            LunarCalendar.solarFestival(now) ??
            LunarCalendar.lunarFestival(lunar);
        final suitable = LunarCalendar.suitable(now);
        final avoid = LunarCalendar.avoid(now);

        final todayTodos = _visibleTodayOverviewTodos(todoP.todos, now);
        final todayTodosCount = todayTodos.length;
        final completedTodayCount = todoP.todos.where((todo) {
          final completedAt = todo.completedAt;
          if (!todo.isCompleted || completedAt == null) return false;
          return completedAt.year == todayKey.year &&
              completedAt.month == todayKey.month &&
              completedAt.day == todayKey.day;
        }).length;
        final noDueTodayTodos = todayTodos.where(
          (todo) => todo.dueDate == null,
        );
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
          datePattern: AppDateFormat.patternOf(context),
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

        // 问候语随主题品牌文案变化（BrandStrings.greetingFor 按时段取词）。
        // 分隔符与用户名兜底跟随 locale：en 下为 "Good afternoon, User"。
        final rawUsername = user.profile.username.trim();
        final displayUsername = rawUsername.isEmpty || rawUsername == '用户'
            ? I18n.tr('profile.default_user')
            : rawUsername;
        final greeting =
            '${s.greetingFor(now)}${I18n.tr('greeting.separator')}$displayUsername';
        final almanacCard = _TodayAlmanacCard(
          now: now,
          lunar: lunar,
          suitable: suitable,
          avoid: avoid,
          term: term,
          festival: festival,
          showLunar: showLunar,
          isHoliday: HolidayCalendar.isHoliday(now),
          isWorkMakeupDay: HolidayCalendar.isWorkMakeupDay(now),
          onTap: () => _go(context, AlmanacScreen(initialDate: now)),
        );
        final productivityCard = _TodayProductivitySection(
          onTap: () => _go(context, const StatisticsScreen()),
        );

        Widget metricsGrid({required bool desktop}) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final theme = Theme.of(context);
              final cs = theme.colorScheme;
              final useTwoColumns =
                  constraints.maxWidth < (desktop ? 640 : 520);
              final crossAxisCount = useTwoColumns ? 2 : 4;
              final aspectRatio = desktop
                  ? (useTwoColumns ? 2.75 : 2.85)
                  : (useTwoColumns ? 2.55 : 3.65);
              // 数值行默认字号已提升到 DesignTokens.fontSizeMd，移动端与桌面端在
              // 缩放字号或中段宽度下按固定宽高比算出的瓦片高度可能不足以容纳“标题+数值”
              // 两行（还要扣掉卡片边距与描边）。这里按当前系统字号缩放换算内容所需高度
              // 给瓦片兜底：在任何宽度和文本缩放档位下均自适应扩高，宽裕时仍按宽高比走，
              // 彻底消除卡片内容竖向溢出。
              final textScaler = MediaQuery.textScalerOf(context);
              final titleFont = desktop ? DesktopTokens.fontSizeCaption : 11.0;
              final valueFont = desktop
                  ? DesktopTokens.fontSizeBody
                  : DesignTokens.fontSizeMd;
              final verticalPadding = desktop ? 24.0 : 20.0;
              final iconBox = desktop ? 32.0 : 28.0;
              final spacing = desktop ? DesktopTokens.cardSpacingMedium : 8.0;
              final totalSpacing = (crossAxisCount - 1) * spacing;
              final textContentHeight =
                  textScaler.scale(titleFont * 1.1) +
                  2 +
                  textScaler.scale(valueFont * (desktop ? 1.08 : 1.1));
              final minTileExtent =
                  verticalPadding + math.max(iconBox, textContentHeight) + 3;
              final naturalTileHeight =
                  ((constraints.maxWidth - totalSpacing) / crossAxisCount) /
                  aspectRatio;
              final tileExtent = math.max(naturalTileHeight, minTileExtent);

              // 桌面端使用更大的字体和图标
              final titleStyle = desktop
                  ? theme.textTheme.bodySmall?.copyWith(
                      fontSize: DesktopTokens.fontSizeCaption,
                      color: cs.onSurface.withValues(
                        alpha: DesktopTokens.opacityTextTertiary,
                      ),
                      fontWeight: FontWeight.normal,
                      height: 1.1,
                    )
                  : null;

              final valueStyle = desktop
                  ? theme.textTheme.titleMedium?.copyWith(
                      fontSize: DesktopTokens.fontSizeBody,
                      color: cs.onSurface.withValues(
                        alpha: DesktopTokens.opacityTextPrimary,
                      ),
                      height: 1.08,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )
                  : null;

              final unitStyle = desktop
                  ? theme.textTheme.bodySmall?.copyWith(
                      fontSize: DesktopTokens.fontSizeCaption,
                      fontWeight: FontWeight.normal,
                      color: cs.onSurface.withValues(
                        alpha: DesktopTokens.opacityTextTertiary,
                      ),
                      height: 1.08,
                    )
                  : null;

              final padding = desktop
                  ? const EdgeInsets.fromLTRB(14, 12, 14, 12)
                  : const EdgeInsets.fromLTRB(12, 10, 12, 10);

              final iconBoxSize = desktop ? 32.0 : 28.0;
              final iconSize = desktop ? 17.0 : 15.0;

              return DefaultTextStyle.merge(
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: aspectRatio,
                  mainAxisExtent: tileExtent,
                  mainAxisSpacing: desktop ? DesktopTokens.cardSpacingMedium : 8,
                  crossAxisSpacing:
                      desktop ? DesktopTokens.cardSpacingMedium : 8,
                  children: [
                  AppMetricCard(
                    title: s.navTodo,
                    value: '${todayTodos.length}',
                    unit: I18n.tr('today.unit.item'),
                    icon: Icons.check_circle_outline,
                    color: cs.primary,
                    onTap: () => _go(context, const TodoScreen()),
                    titleStyle: titleStyle,
                    valueStyle: valueStyle,
                    unitStyle: unitStyle,
                    padding: padding,
                    iconBoxSize: iconBoxSize,
                    iconSize: iconSize,
                  ),
                  AppMetricCard(
                    title: s.navHabit,
                    value: '${(todayHabitProgress * 100).round()}',
                    unit: '%',
                    icon: Icons.repeat,
                    color: cs.tertiary,
                    onTap: () => _go(context, const HabitScreen()),
                    titleStyle: titleStyle,
                    valueStyle: valueStyle,
                    unitStyle: unitStyle,
                    padding: padding,
                    iconBoxSize: iconBoxSize,
                    iconSize: iconSize,
                  ),
                  AppMetricCard(
                    title: s.navFocus,
                    value: '$todayFocusCount',
                    unit: I18n.tr('today.unit.times'),
                    icon: Icons.timer,
                    color: DesignTokens.defaultError,
                    onTap: () => _go(
                      context,
                      const PomodoroScreen(useShellBackground: true),
                    ),
                    titleStyle: titleStyle,
                    valueStyle: valueStyle,
                    unitStyle: unitStyle,
                    padding: padding,
                    iconBoxSize: iconBoxSize,
                    iconSize: iconSize,
                  ),
                  AppMetricCard(
                    title: I18n.tr('today.diary'),
                    value: diaryP.entryForDate(now) == null
                        ? I18n.tr('today.diary.unwritten')
                        : I18n.tr('today.diary.written'),
                    icon: Icons.book_outlined,
                    color: const Color(0xFF26A69A),
                    onTap: () => _go(context, const DiaryScreen()),
                    titleStyle: titleStyle,
                    valueStyle: valueStyle,
                    unitStyle: unitStyle,
                    padding: padding,
                    iconBoxSize: iconBoxSize,
                    iconSize: iconSize,
                  ),
                ],
              ),
              );
            },
          );
        }

        Widget todosSection({int maxItems = 6}) {
          return _section(
            I18n.tr('today.todos'),
            subtitle:
                "$todayTodosCount ${I18n.tr('today.unit.item')} · ${I18n.tr('today.completed')} $completedTodayCount · ${I18n.tr('today.no_due')} ${noDueTodayTodos.length}",
            onMore: () =>
                TodayDetailRouter.open(context, TodaySectionKind.todos),
            child: todayTodos.isEmpty
                ? _TodayTodoEmptyState(
                    onTap: () =>
                        TodayDetailRouter.open(context, TodaySectionKind.todos),
                  )
                : Column(
                    children: todayTodos.take(maxItems).map((t) {
                      return _TodayTodoSwipeTile(
                        key: ValueKey('today_todo_${t.id}'),
                        todo: t,
                        canEdit: shareProvider?.canEdit(t.workspaceId) ?? true,
                        onToggle: _todayTodoCompletionAction(context, t),
                        onOpen: () => TodayDetailRouter.open(
                          context,
                          TodaySectionKind.todos,
                          id: t.id,
                        ),
                      );
                    }).toList(),
                  ),
          );
        }

        Widget? reminderSection() {
          if (!showReminderSection) return null;
          return ValueListenableBuilder<int>(
            valueListenable:
                AccountLocalDataCleaner.accountDataGenerationListenable,
            builder: (sectionContext, boundAccountGeneration, _) {
              return _TodayReminderSection(
                groups: reminderGroups,
                suggestions: suggestions,
                todayKey: todayKey,
                now: now,
                onOpenTodo: (id) => TodayDetailRouter.open(
                  sectionContext,
                  TodaySectionKind.todos,
                  id: id,
                  accountGeneration: boundAccountGeneration,
                ),
                onToggleTodo: (todo) =>
                    _todayTodoCompletionAction(sectionContext, todo),
                onOpenCourses: () => TodayDetailRouter.open(
                  sectionContext,
                  TodaySectionKind.courses,
                ),
                onAddToday: (todo) async {
                  if (AccountLocalDataCleaner.accountDataGeneration !=
                      boundAccountGeneration) {
                    return;
                  }
                  final actionNow = DateTime.now();
                  final changed = await sectionContext
                      .read<TodoProvider>()
                      .scheduleTodoForToday(
                        todo.id,
                        now: actionNow,
                        expectedAccountDataGeneration: boundAccountGeneration,
                      );
                  if (!sectionContext.mounted ||
                      AccountLocalDataCleaner.accountDataGeneration !=
                          boundAccountGeneration ||
                      !changed) {
                    return;
                  }
                  ScaffoldMessenger.of(sectionContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${I18n.tr('today.added_prefix')}${todo.title}',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              );
            },
          );
        }

        Widget? coursesSection() {
          if (todayCourses.isEmpty) return null;
          return _section(
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
                    backgroundColor: Color(c.colorValue).withValues(alpha: 0.2),
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
                  onTap: () =>
                      TodayDetailRouter.open(context, TodaySectionKind.courses),
                );
              }).toList(),
            ),
          );
        }

        Widget? anniversariesSection() {
          if (soon.isEmpty) return null;
          return _section(
            I18n.tr('today.upcoming_anniversaries'),
            onMore: () =>
                TodayDetailRouter.open(context, TodaySectionKind.anniversaries),
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
          );
        }

        Widget goalsSection() {
          return _section(
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
          );
        }

        final isDesktopLayout = MediaQuery.sizeOf(context).width >= 1100;
        final reminder = reminderSection();
        final courses = coursesSection();
        final anniversaries = anniversariesSection();
        final goals = goalsSection();
        if (isDesktopLayout) {
          return _TodayDesktopDashboard(
            greeting: greeting,
            dateText: showLunar
                ? '${I18nDateFormat.monthDayWithWeekday(now)} · ${AlmanacLocaleFormat.formatLunarDate(lunar)}'
                : I18nDateFormat.monthDayWithWeekday(now),
            almanacCard: almanacCard,
            productivityCard: productivityCard,
            metricsGrid: metricsGrid(desktop: true),
            todosSection: todosSection(maxItems: 8),
            reminderSection: reminder,
            quoteCard: _QuoteCard(),
            goalsSection: goals,
            coursesSection: courses,
            anniversariesSection: anniversaries,
          );
        }

        final isUltraNarrow = MediaQuery.sizeOf(context).width < 240;
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(greeting),
            backgroundColor: Colors.transparent,
          ),
          body: ListView(
            key: const ValueKey('today_screen_list'),
            restorationId: 'today_screen_list',
            // Keep the final card clear of the bottom navigation bar and FAB when
            // the mobile Today list is scrolled to its end.
            padding: EdgeInsets.fromLTRB(
              isUltraNarrow ? 4 : 12,
              0,
              isUltraNarrow ? 4 : 12,
              112,
            ),
            children: [
              almanacCard,
              const SizedBox(height: 8),

              productivityCard,

              const SizedBox(height: 8),
              metricsGrid(desktop: false),

              const SizedBox(height: 10),

              todosSection(),
              const SizedBox(height: 10),
              _QuoteCard(),
              ?reminder,
              ?courses,
              ?anniversaries,
              goals,
            ],
          ),
        );
      },
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
      padding: const EdgeInsets.only(top: 2),
      child: AppSurfaceCard(
        margin: const EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.zero,
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
                  padding: const EdgeInsets.fromLTRB(16, 10, 12, 4),
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

/// 桌面端左侧边栏 - 日历、快捷入口
class _TodayDesktopLeftSidebar extends StatelessWidget {
  final DateTime now;

  const _TodayDesktopLeftSidebar({required this.now});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 精简月历
        _CompactMonthCalendar(currentDate: now),
        const SizedBox(height: DesktopTokens.cardSpacing),

        // 快捷入口
        _QuickAccessPanel(),
      ],
    );
  }
}

/// 精简月历 - 当月日历，高亮今日
class _CompactMonthCalendar extends StatelessWidget {
  final DateTime currentDate;

  const _CompactMonthCalendar({required this.currentDate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final now = currentDate;

    // 当月第一天和最后一天
    final firstDay = DateTime.utc(now.year, now.month, 1);
    final lastDay = DateTime.utc(now.year, now.month + 1, 0);

    final firstDayOfWeek = context.select<PreferencesProvider?, int>(
      (p) => CalendarDateNavigation.normalizeFirstDayOfWeek(
        p?.firstDayOfWeek ?? 1,
      ),
    );
    final firstWeekday = (firstDay.weekday - firstDayOfWeek) % 7;

    // 构建日历网格
    final days = <Widget>[];

    // 星期标题
    final weekdays = switch (I18n.current) {
      AppLocale.en => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      AppLocale.zh => const ['一', '二', '三', '四', '五', '六', '日'],
    };
    for (final iso in CalendarDateNavigation.orderedWeekdays(firstDayOfWeek)) {
      final weekday = weekdays[iso - 1];
      days.add(
        Center(
          child: Text(
            weekday,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              fontSize: 11,
            ),
          ),
        ),
      );
    }

    // 填充前面的空格
    for (int i = 0; i < firstWeekday; i++) {
      days.add(const SizedBox.shrink());
    }

    // 填充日期
    for (int day = 1; day <= lastDay.day; day++) {
      final isToday = day == now.day;
      final date = DateTime.utc(now.year, now.month, day);
      final isWeekend =
          date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

      days.add(
        Container(
          alignment: Alignment.center,
          decoration: isToday
              ? BoxDecoration(color: cs.primary, shape: BoxShape.circle)
              : null,
          child: Text(
            '$day',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 13,
              color: isToday
                  ? cs.onPrimary
                  : isWeekend
                  ? cs.onSurfaceVariant.withValues(alpha: 0.5)
                  : cs.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ),
      );
    }

    return AppSurfaceCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 月份标题
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              I18nDateFormat.yearMonth(now),
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: DesktopTokens.fontSizeCardSubtitle,
                color: cs.onSurface.withValues(
                  alpha: DesktopTokens.opacityTextPrimary,
                ),
              ),
            ),
          ),

          // 日历网格
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 7,
            childAspectRatio: 1,
            mainAxisSpacing: 6,
            crossAxisSpacing: 4,
            children: days,
          ),
        ],
      ),
    );
  }
}

/// 快捷入口面板
class _QuickAccessPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final quickActions = [
      _QuickAction(
        icon: Icons.repeat,
        label: TodayUiCopy.quickAccessHabit,
        color: cs.tertiary,
        onTap: () => Navigator.pushNamed(context, '/habit'),
      ),
      _QuickAction(
        icon: Icons.timer_outlined,
        label: TodayUiCopy.quickAccessPomodoro,
        color: DesignTokens.defaultError,
        onTap: () => Navigator.pushNamed(context, '/pomodoro'),
      ),
      _QuickAction(
        icon: Icons.edit_note_outlined,
        label: TodayUiCopy.quickAccessNotes,
        color: cs.secondary,
        onTap: () => Navigator.pushNamed(context, '/notes'),
      ),
      _QuickAction(
        icon: Icons.calendar_today_outlined,
        label: TodayUiCopy.quickAccessCalendar,
        color: cs.primary,
        onTap: () => Navigator.pushNamed(context, '/calendar'),
      ),
    ];

    return AppSurfaceCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            TodayUiCopy.quickAccessTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: DesktopTokens.fontSizeCardSubtitle,
              color: cs.onSurface.withValues(
                alpha: DesktopTokens.opacityTextPrimary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.25,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: quickActions,
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: DesktopTokens.iconSizeMedium, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: DesktopTokens.fontSizeCaptionSmall,
                color: cs.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayDesktopDashboard extends StatelessWidget {
  final String greeting;
  final String dateText;
  final Widget almanacCard;
  final Widget productivityCard;
  final Widget metricsGrid;
  final Widget todosSection;
  final Widget? reminderSection;
  final Widget quoteCard;
  final Widget goalsSection;
  final Widget? coursesSection;
  final Widget? anniversariesSection;

  const _TodayDesktopDashboard({
    required this.greeting,
    required this.dateText,
    required this.almanacCard,
    required this.productivityCard,
    required this.metricsGrid,
    required this.todosSection,
    required this.reminderSection,
    required this.quoteCard,
    required this.goalsSection,
    required this.coursesSection,
    required this.anniversariesSection,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now(); // 用于左侧边栏日历

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Scrollbar(
          child: SingleChildScrollView(
            key: const ValueKey('today_screen_list'),
            primary: true,
            padding: EdgeInsets.fromLTRB(
              DesktopTokens.pageHorizontalPadding,
              DesktopTokens.pageTopPadding,
              DesktopTokens.pageHorizontalPadding,
              DesktopTokens.pageBottomPadding,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesktopTokens.maxContentWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TodayDesktopHeader(greeting: greeting, dateText: dateText),
                    const SizedBox(height: DesktopTokens.cardSpacing),

                    // 响应式三栏/两栏布局
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final showLeftSidebar =
                            constraints.maxWidth >=
                            DesktopTokens.todayThreeColumnContentBreakpoint;
                        final moveProductivityToRail =
                            constraints.maxWidth >=
                            DesktopTokens.todayTwoColumnContentBreakpoint;
                        final rightSidebarChildren = <Widget>[
                          quoteCard,
                          const SizedBox(height: DesktopTokens.cardSpacing),
                          if (moveProductivityToRail) ...[
                            productivityCard,
                            const SizedBox(height: DesktopTokens.cardSpacing),
                          ],
                          goalsSection,
                          ?coursesSection,
                          ?anniversariesSection,
                        ];

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 左侧边栏（仅在宽度 >= 1400px 时显示）
                            if (showLeftSidebar) ...[
                              SizedBox(
                                width: DesktopTokens.leftSidebarWidth,
                                child: _TodayDesktopLeftSidebar(now: now),
                              ),
                              const SizedBox(
                                width: DesktopTokens.columnSpacing,
                              ),
                            ],

                            // 主内容区
                            Expanded(
                              child: Column(
                                children: [
                                  if (moveProductivityToRail)
                                    almanacCard
                                  else
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        if (constraints.maxWidth < 720) {
                                          return Column(
                                            children: [
                                              almanacCard,
                                              const SizedBox(
                                                height: DesktopTokens
                                                    .cardSpacingMedium,
                                              ),
                                              productivityCard,
                                            ],
                                          );
                                        }
                                        return Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(child: almanacCard),
                                            const SizedBox(
                                              width: DesktopTokens
                                                  .cardSpacingMedium,
                                            ),
                                            SizedBox(
                                              width: 340,
                                              child: productivityCard,
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  const SizedBox(
                                    height: DesktopTokens.cardSpacingMedium,
                                  ),
                                  metricsGrid,
                                  const SizedBox(
                                    height: DesktopTokens.cardSpacing,
                                  ),

                                  todosSection,
                                  ?reminderSection,
                                ],
                              ),
                            ),

                            // 右侧边栏
                            const SizedBox(width: DesktopTokens.columnSpacing),
                            SizedBox(
                              width: DesktopTokens.rightSidebarWidth,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: rightSidebarChildren,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TodayDesktopHeader extends StatelessWidget {
  final String greeting;
  final String dateText;

  const _TodayDesktopHeader({required this.greeting, required this.dateText});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AppSurfaceCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(
        horizontal: DesktopTokens.cardPadding,
        vertical: 16,
      ),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(cs.primary.withValues(alpha: 0.045), cs.surface),
          cs.surface.withValues(alpha: DesktopTokens.opacityCardBackground),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.14),
                width: 0.6,
              ),
            ),
            child: Icon(Icons.wb_sunny_outlined, size: 21, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: DesktopTokens.fontSizePageTitle,
                    height: 1.15,
                    color: cs.onSurface.withValues(
                      alpha: DesktopTokens.opacityTextPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  dateText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: DesktopTokens.fontSizePageSubtitle,
                    color: cs.onSurfaceVariant.withValues(
                      alpha: DesktopTokens.opacityTextSecondary,
                    ),
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.today_outlined,
                size: 17,
                color: cs.primary.withValues(alpha: 0.78),
              ),
              const SizedBox(width: 6),
              Text(
                I18n.tr('nav.today'),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

TextStyle _todayEffectiveTextStyle(BuildContext context, TextStyle? style) {
  final defaultTextStyle = DefaultTextStyle.of(context);
  var effectiveTextStyle = style;
  if (style == null || style.inherit) {
    effectiveTextStyle = defaultTextStyle.style.merge(style);
  }
  if (MediaQuery.boldTextOf(context)) {
    effectiveTextStyle = effectiveTextStyle!.merge(
      const TextStyle(fontWeight: FontWeight.bold),
    );
  }
  final lineHeightScaleFactor =
      MediaQuery.maybeLineHeightScaleFactorOverrideOf(context);
  final letterSpacing = MediaQuery.maybeLetterSpacingOverrideOf(context);
  final wordSpacing = MediaQuery.maybeWordSpacingOverrideOf(context);
  if (lineHeightScaleFactor != null ||
      letterSpacing != null ||
      wordSpacing != null) {
    final overrideTextStyle = TextStyle(
      height: lineHeightScaleFactor,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
    );
    effectiveTextStyle =
        effectiveTextStyle?.merge(overrideTextStyle) ?? overrideTextStyle;
  }
  return effectiveTextStyle ?? const TextStyle();
}

double _measureTodayTextWidth(
  BuildContext context,
  String text,
  TextStyle? style,
) {
  final effectiveStyle = _todayEffectiveTextStyle(context, style);
  final locale = Localizations.maybeLocaleOf(context);
  final painter = TextPainter(
    text: TextSpan(text: text, style: effectiveStyle, locale: locale),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: locale,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

double _overdueBadgeEstimatedWidth(BuildContext context) {
  // Border (1.4) + horizontal padding (12) + icon (10) + gap (2) + text width.
  return 25.4 +
      _measureTodayTextWidthCached(
        context,
        I18n.tr('todo.status.overdue'),
        const TextStyle(fontSize: 10),
      );
}

class _TodayTextMeasureKey {
  final String text;
  final TextStyle style;
  final TextStyle defaultStyle;
  final double textScale;
  final bool boldText;
  final double? lineHeightScaleFactor;
  final double? letterSpacing;
  final double? wordSpacing;
  final TextDirection textDirection;
  final Locale? locale;

  const _TodayTextMeasureKey({
    required this.text,
    required this.style,
    required this.defaultStyle,
    required this.textScale,
    required this.boldText,
    required this.lineHeightScaleFactor,
    required this.letterSpacing,
    required this.wordSpacing,
    required this.textDirection,
    required this.locale,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TodayTextMeasureKey &&
          other.text == text &&
          other.style == style &&
          other.defaultStyle == defaultStyle &&
          other.textScale == textScale &&
          other.boldText == boldText &&
          other.lineHeightScaleFactor == lineHeightScaleFactor &&
          other.letterSpacing == letterSpacing &&
          other.wordSpacing == wordSpacing &&
          other.textDirection == textDirection &&
          other.locale == locale;

  @override
  int get hashCode => Object.hash(
    text,
    style,
    defaultStyle,
    textScale,
    boldText,
    lineHeightScaleFactor,
    letterSpacing,
    wordSpacing,
    textDirection,
    locale,
  );
}

const int _maxTodayTextMeasureCacheEntries = 128;
final LinkedHashMap<_TodayTextMeasureKey, double> _todayTextMeasureCache =
    LinkedHashMap<_TodayTextMeasureKey, double>();

double _measureTodayTextWidthCached(
  BuildContext context,
  String text,
  TextStyle? style,
) {
  final key = _TodayTextMeasureKey(
    text: text,
    style: style ?? const TextStyle(),
    defaultStyle: DefaultTextStyle.of(context).style,
    textScale: MediaQuery.textScalerOf(context).scale(1.0),
    boldText: MediaQuery.boldTextOf(context),
    lineHeightScaleFactor: MediaQuery.maybeLineHeightScaleFactorOverrideOf(
      context,
    ),
    letterSpacing: MediaQuery.maybeLetterSpacingOverrideOf(context),
    wordSpacing: MediaQuery.maybeWordSpacingOverrideOf(context),
    textDirection: Directionality.of(context),
    locale: Localizations.maybeLocaleOf(context),
  );
  final existing = _todayTextMeasureCache.remove(key);
  if (existing != null) {
    _todayTextMeasureCache[key] = existing;
    return existing;
  }
  final width = _measureTodayTextWidth(context, text, style);
  if (_todayTextMeasureCache.length >= _maxTodayTextMeasureCacheEntries) {
    _todayTextMeasureCache.remove(_todayTextMeasureCache.keys.first);
  }
  _todayTextMeasureCache[key] = width;
  return width;
}

class _TodayAlmanacCard extends StatelessWidget {
  final DateTime now;
  final LunarDate lunar;
  final String suitable;
  final String avoid;
  final String? term;
  final String? festival;
  final bool showLunar;
  final bool isHoliday;
  final bool isWorkMakeupDay;
  final VoidCallback onTap;

  const _TodayAlmanacCard({
    required this.now,
    required this.lunar,
    required this.suitable,
    required this.avoid,
    required this.term,
    required this.festival,
    this.showLunar = true,
    this.isHoliday = false,
    this.isWorkMakeupDay = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final brand = context.select<ThemeProvider, AppBrand>((t) => t.brand);
    final radius = BorderRadius.circular(
      appSurfaceStyleOf(context)?.cardRadius ?? DesignTokens.radiusCard,
    );
    final foreground = isDark ? Colors.white : cs.onSurface;
    final muted = foreground.withValues(alpha: isDark ? 0.74 : 0.68);
    final accent = cs.primary;
    final lunarLabel = I18n.current == AppLocale.en
        ? 'Lunar'
        : I18n.tr('calendar.chinese_lunar_calendar');
    final lunarText = AlmanacLocaleFormat.formatLunarDate(lunar);
    final termText = AlmanacLocaleFormat.formatSolarTerm(term);
    final festivalText = AlmanacLocaleFormat.formatFestival(festival);
    final backgroundAsset = brand.backgroundAsset;
    // Keep the calendar surface airy in the default light theme.  The card
    // already has enough separation from its border and date badge; a darker
    // translucent panel made the whole calendar area read like a shadow.
    final panelFill = foreground.withValues(alpha: isDark ? 0.035 : 0.006);
    final panelBorder = foreground.withValues(alpha: isDark ? 0.10 : 0.035);

    final fallbackGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.alphaBlend(
          accent.withValues(alpha: isDark ? 0.12 : 0.020),
          cs.surface,
        ),
        Color.alphaBlend(
          cs.secondary.withValues(alpha: isDark ? 0.09 : 0.010),
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
            : cs.outlineVariant.withValues(alpha: 0.08),
        width: 0.55,
      ),
      elevation: 0,
      boxShadow: const [],
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
              padding: const EdgeInsets.all(15),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: panelFill,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  border: Border.all(color: panelBorder, width: 0.45),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final availableWidth = constraints.maxWidth;
                      final stackDateBadge = availableWidth < 200;
                      final stackYiji = availableWidth < 180;

                      final dateBadge = _TodayDateBadge(
                        date: now,
                        accent: accent,
                        foreground: foreground,
                        muted: muted,
                        isDark: isDark,
                      );
                      final almanacIcon = Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: isDark ? 0.20 : 0.10),
                          borderRadius: BorderRadius.circular(
                            DesignTokens.radiusSm,
                          ),
                        ),
                        child: Icon(
                          Icons.calendar_month_rounded,
                          size: 14,
                          color: accent,
                        ),
                      );
                      final chevron = Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: foreground.withValues(
                            alpha: isDark ? 0.12 : 0.05,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 17,
                          color: foreground.withValues(alpha: 0.62),
                        ),
                      );
                      final almanacTitle = Text(
                        '${I18n.tr('today.almanac.title')} · ${I18nDateFormat.monthDayWithWeekday(now)}',
                        maxLines: stackDateBadge ? null : 1,
                        softWrap: stackDateBadge,
                        overflow: stackDateBadge
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          fontSize: 12.5,
                          height: 1.2,
                        ),
                      );
                      final lunarTitle = Text(
                        showLunar
                            ? '$lunarLabel · $lunarText'
                            : (I18n.current == AppLocale.en
                                  ? 'Daily Almanac'
                                  : '今日黄历'),
                        maxLines: stackDateBadge ? null : 1,
                        softWrap: stackDateBadge,
                        overflow: stackDateBadge
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: foreground,
                          fontSize: 16,
                          height: 1.25,
                          fontWeight: FontWeight.normal,
                        ),
                      );
                      final holidayChipText = isWorkMakeupDay
                          ? AlmanacUiCopy.makeupWorkdayBadge
                          : isHoliday
                          ? AlmanacUiCopy.holidayBadge
                          : null;
                      final holidayChipColor = isWorkMakeupDay
                          ? (isDark
                                ? const Color(0xFFC4B5FD)
                                : const Color(0xFF5B21B6))
                          : (isDark
                                ? const Color(0xFF6EE7B7)
                                : const Color(0xFF0F766E));
                      final chipsWidget = (termText != null ||
                              festivalText != null ||
                              holidayChipText != null)
                          ? Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (holidayChipText != null)
                                  _TodayCalendarChip(
                                    text: holidayChipText,
                                    color: holidayChipColor,
                                  ),
                                if (termText != null)
                                  _TodayCalendarChip(
                                    text: termText,
                                    color: accent,
                                  ),
                                if (festivalText != null)
                                  _TodayCalendarChip(
                                    text: festivalText,
                                    color: cs.tertiary,
                                  ),
                              ],
                            )
                          : null;

                      final fitPreview = _TodayYijiPreview(
                        label: TodayUiCopy.auspiciousLabel,
                        text: suitable,
                        color: DesignTokens.defaultSuccess,
                        foreground: foreground,
                        isDark: isDark,
                      );
                      final avoidPreview = _TodayYijiPreview(
                        label: TodayUiCopy.inauspiciousLabel,
                        text: avoid,
                        color: DesignTokens.defaultError,
                        foreground: foreground,
                        isDark: isDark,
                      );

                      final Widget headerSection;
                      if (stackDateBadge) {
                        headerSection = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (availableWidth >= 102)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [dateBadge, chevron],
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [dateBadge, chevron],
                              ),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                almanacIcon,
                                const SizedBox(width: 7),
                                Expanded(child: almanacTitle),
                              ],
                            ),
                            const SizedBox(height: 8),
                            lunarTitle,
                            if (chipsWidget != null) ...[
                              const SizedBox(height: 9),
                              chipsWidget,
                            ],
                          ],
                        );
                      } else {
                        headerSection = Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            dateBadge,
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      almanacIcon,
                                      const SizedBox(width: 7),
                                      Expanded(child: almanacTitle),
                                      const SizedBox(width: 6),
                                      chevron,
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  lunarTitle,
                                  if (chipsWidget != null) ...[
                                    const SizedBox(height: 9),
                                    chipsWidget,
                                  ],
                                ],
                              ),
                            ),
                          ],
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          headerSection,
                          if (showLunar) ...[
                            const SizedBox(height: 12),
                            if (stackYiji)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  fitPreview,
                                  const SizedBox(height: 8),
                                  avoidPreview,
                                ],
                              )
                            else
                              Row(
                                children: [
                                  Expanded(child: fitPreview),
                                  const SizedBox(width: 8),
                                  Expanded(child: avoidPreview),
                                ],
                              ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayDateBadge extends StatelessWidget {
  final DateTime date;
  final Color accent;
  final Color foreground;
  final Color muted;
  final bool isDark;

  const _TodayDateBadge({
    required this.date,
    required this.accent,
    required this.foreground,
    required this.muted,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 68,
      constraints: const BoxConstraints(minHeight: 76),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: isDark ? 0.08 : 0.035),
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        border: Border.all(
          color: foreground.withValues(alpha: isDark ? 0.12 : 0.065),
          width: 0.55,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 5),
            color: accent.withValues(alpha: isDark ? 0.20 : 0.10),
            child: Text(
              TodayUiCopy.monthBadge(date),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontSize: 11,
                height: 1,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 44,
                  height: 31,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${date.day}',
                      maxLines: 1,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: foreground,
                        fontSize: 30,
                        height: 0.96,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${date.year}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: muted,
                    fontSize: 10,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 128),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 11,
            color: color,
            height: 1.1,
            fontWeight: FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _TodayYijiPreview extends StatelessWidget {
  final String label;
  final String text;
  final Color color;
  final Color foreground;
  final bool isDark;

  const _TodayYijiPreview({
    required this.label,
    required this.text,
    required this.color,
    required this.foreground,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tileFill = color.withValues(alpha: isDark ? 0.17 : 0.075);
    final badgeFill = color.withValues(alpha: isDark ? 0.18 : 0.09);
    final pillBg = Color.alphaBlend(
      badgeFill,
      Color.alphaBlend(tileFill, cs.surface),
    );
    final labelColor = appReadableForeground(pillBg, color);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: tileFill,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.22 : 0.14),
          width: 0.45,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeFill,
              borderRadius: BorderRadius.circular(7),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 11,
                  height: 1,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              _wholeTermPreview(text),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: foreground.withValues(alpha: isDark ? 0.88 : 0.82),
                fontSize: 11.5,
                height: 1.16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _wholeTermPreview(String value) {
  return AlmanacLocaleFormat.formatActivitiesPreview(
    value,
    maxTerms: I18n.current == AppLocale.en ? 2 : 3,
  );
}

class _TodayProductivitySection extends StatefulWidget {
  final VoidCallback onTap;

  const _TodayProductivitySection({required this.onTap});

  @override
  State<_TodayProductivitySection> createState() =>
      _TodayProductivitySectionState();
}

class _TodayProductivitySectionState extends State<_TodayProductivitySection> {
  Object? _cachedSignature;
  ReportComparison? _cachedComparison;

  Object _buildInputSignature({
    required DateTime todayKey,
    required List<TodoItem> todos,
    required List<dynamic> habits,
    required int pomoRevision,
    required List<dynamic> timeEntries,
  }) {
    var todoFp = todos.length;
    for (final t in todos) {
      todoFp = Object.hash(
        todoFp,
        t.id,
        t.updatedAt.millisecondsSinceEpoch,
        t.completedAt?.millisecondsSinceEpoch ?? 0,
      );
    }
    var habitFp = habits.length;
    for (final h in habits) {
      habitFp = Object.hash(
        habitFp,
        h.id,
        h.updatedAt.millisecondsSinceEpoch,
      );
    }
    var timeFp = timeEntries.length;
    for (final e in timeEntries) {
      timeFp = Object.hash(
        timeFp,
        e.id,
        e.updatedAt.millisecondsSinceEpoch,
      );
    }
    return Object.hash(
      todayKey.millisecondsSinceEpoch,
      todoFp,
      habitFp,
      pomoRevision,
      timeFp,
    );
  }

  @override
  Widget build(BuildContext context) {
    final todoP = context.watch<TodoProvider>();
    final habitP = context.watch<HabitProvider>();
    final pomoRevision = context.select<PomodoroProvider, int>(
      (provider) => provider.persistedRevision,
    );
    final pomoP = context.read<PomodoroProvider>();
    final timeEntries = context.watch<TimeAuditProvider>().entries;

    final now = DateTime.now();
    final todayKey = DateTime(now.year, now.month, now.day);
    final sig = _buildInputSignature(
      todayKey: todayKey,
      todos: todoP.todos,
      habits: habitP.habits,
      pomoRevision: pomoRevision,
      timeEntries: timeEntries,
    );
    var comparison = _cachedComparison;
    if (comparison == null || _cachedSignature != sig) {
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
      comparison = ReportEngine.compare(
        current: weeklyReport,
        previous: previousWeeklyReport,
      );
      _cachedSignature = sig;
      _cachedComparison = comparison;
    }
    return _TodayProductivityCard(
      comparison: comparison,
      onTap: widget.onTap,
    );
  }
}

class _TodayProductivityCard extends StatelessWidget {
  static const int _maxMeasureCacheEntries = 64;
  static final LinkedHashMap<_TodayTextMeasureKey, double> _measureCache =
      LinkedHashMap<_TodayTextMeasureKey, double>();

  final ReportComparison comparison;
  final VoidCallback onTap;

  const _TodayProductivityCard({required this.comparison, required this.onTap});

  static double _measureTextWidth(
    BuildContext context,
    String text,
    TextStyle style,
  ) {
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final defaultStyle = DefaultTextStyle.of(context).style;
    final key = _TodayTextMeasureKey(
      text: text,
      style: style,
      defaultStyle: defaultStyle,
      textScale: textScaler.scale(1.0),
      boldText: false,
      lineHeightScaleFactor: null,
      letterSpacing: null,
      wordSpacing: null,
      textDirection: textDirection,
      locale: locale,
    );
    final existing = _measureCache.remove(key);
    if (existing != null) {
      _measureCache[key] = existing;
      return existing;
    }
    final effectiveStyle = defaultStyle.merge(style);
    final painter = TextPainter(
      text: TextSpan(text: text, style: effectiveStyle),
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    if (_measureCache.length >= _maxMeasureCacheEntries) {
      _measureCache.remove(_measureCache.keys.first);
    }
    _measureCache[key] = width;
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final scoreDelta = comparison.productivityScore.difference.round();
    final trendColor = _trendColor(cs, comparison.productivityScore.direction);
    final textScaler = MediaQuery.textScalerOf(context);
    final scoreSize = math.max(60.0, textScaler.scale(40.0) + 20.0);
    final weeklyHeading = I18n.tr('today.productivity.weekly');
    final subtitleText = I18n.tr('today.productivity.subtitle');
    final trendText = scoreDelta == 0
        ? I18n.tr('today.productivity.flat')
        : '${scoreDelta > 0 ? '+' : ''}$scoreDelta ${I18n.tr('today.unit.point')}';

    final headingStyle =
        (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
          fontSize: 16,
          fontWeight: FontWeight.normal,
        );
    final trendStyle = TextStyle(fontSize: 12, color: trendColor);
    final subtitleStyle = TextStyle(
      fontSize: 12,
      color: cs.onSurface.withValues(alpha: 0.58),
    );

    final scoreProgress =
        (comparison.current.productivityScore.clamp(0, 100)) / 100.0;
    final scoreCircle = SizedBox(
      width: scoreSize,
      height: scoreSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: scoreSize,
            height: scoreSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.alphaBlend(
                cs.primary.withValues(alpha: isDark ? 0.16 : 0.09),
                cs.surface,
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: isDark ? 0.16 : 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: CircularProgressIndicator(
              value: scoreProgress,
              strokeWidth: 3.5,
              strokeCap: StrokeCap.round,
              backgroundColor: cs.primary.withValues(alpha: 0.12),
              color: cs.primary,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    comparison.current.productivityScore.toString(),
                    style: TextStyle(
                      fontSize: 22,
                      height: 1,
                      color: cs.primary,
                      fontWeight: FontWeight.normal,
                      fontFeatures: const [FontFeature.tabularFigures()],
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
          ),
        ],
      ),
    );

    final unitSpacer = I18n.current == AppLocale.en ? ' ' : '';
    List<_TodayProductivityPill> buildPills({double? maxWidth}) => [
      _TodayProductivityPill(
        label: I18n.tr('today.productivity.completion_rate'),
        value:
            '${(comparison.current.todoCompletionRate * 100).round()}%',
        maxWidth: maxWidth,
      ),
      _TodayProductivityPill(
        label: I18n.tr('nav.focus'),
        value:
            '${comparison.current.focusMinutes}$unitSpacer${I18n.tr('unit.min')}',
        maxWidth: maxWidth,
      ),
      _TodayProductivityPill(
        label: I18n.tr('nav.habit'),
        value:
            '${comparison.current.habitCheckIns}$unitSpacer${I18n.tr('today.unit.times')}',
        maxWidth: maxWidth,
      ),
    ];

    return AppSurfaceCard(
      onTap: onTap,
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(
            cs.primary.withValues(alpha: isDark ? 0.075 : 0.035),
            cs.surface,
          ),
          Color.alphaBlend(
            trendColor.withValues(alpha: isDark ? 0.070 : 0.030),
            cs.surface,
          ),
        ],
      ),
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: isDark ? 0.16 : 0.20),
        width: 0.55,
      ),
      elevation: 1.5,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          final wideTextWidth =
              availableWidth - scoreSize - 12.0 - 6.0 - 18.0;

          final headingWidth = _measureTextWidth(
            context,
            weeklyHeading,
            headingStyle,
          );
          final trendTextWidth = _measureTextWidth(
            context,
            trendText,
            trendStyle,
          );
          final trendRowWidth = 16.0 + 4.0 + trendTextWidth;
          final minHeadingAndTrendWidth = headingWidth + 8.0 + trendRowWidth;

          final subtitleWords = subtitleText.split(RegExp(r'\s+'));
          var maxSubtitleWordWidth = 0.0;
          for (final word in subtitleWords) {
            final w = _measureTextWidth(context, word, subtitleStyle);
            if (w > maxSubtitleWordWidth) maxSubtitleWordWidth = w;
          }

          final fitsWide = wideTextWidth >= minHeadingAndTrendWidth &&
              wideTextWidth >= maxSubtitleWordWidth;

          if (fitsWide) {
            return Row(
              children: [
                scoreCircle,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              weeklyHeading,
                              style: headingStyle,
                            ),
                          ),
                          Icon(
                            _trendIcon(comparison.productivityScore.direction),
                            color: trendColor,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            trendText,
                            style: trendStyle,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitleText,
                        style: subtitleStyle,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: buildPills(maxWidth: wideTextWidth),
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
            );
          }

          final compactTextWidth =
              availableWidth - scoreSize - 12.0 - 4.0 - 18.0;
          final headingWords = weeklyHeading.split(RegExp(r'\s+'));
          var maxHeadingWordWidth = 0.0;
          for (final word in headingWords) {
            final w = _measureTextWidth(context, word, headingStyle);
            if (w > maxHeadingWordWidth) maxHeadingWordWidth = w;
          }

          final headerSideBySide = compactTextWidth >= maxHeadingWordWidth &&
              compactTextWidth >= trendRowWidth;

          Widget headerSection;
          if (headerSideBySide) {
            headerSection = Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                scoreCircle,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              weeklyHeading,
                              style: headingStyle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: cs.onSurface.withValues(alpha: 0.38),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _trendIcon(comparison.productivityScore.direction),
                            color: trendColor,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            trendText,
                            style: trendStyle,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          } else {
            headerSection = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    scoreCircle,
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: cs.onSurface.withValues(alpha: 0.38),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  weeklyHeading,
                  style: headingStyle,
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _trendIcon(comparison.productivityScore.direction),
                      color: trendColor,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      trendText,
                      style: trendStyle,
                    ),
                  ],
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              headerSection,
              const SizedBox(height: 10),
              Text(
                subtitleText,
                style: subtitleStyle,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: buildPills(maxWidth: availableWidth),
              ),
            ],
          );
        },
      ),
    );
  }

  Color _trendColor(ColorScheme cs, ReportTrendDirection direction) =>
      switch (direction) {
        ReportTrendDirection.up => appReadableForeground(
          cs.surface,
          DesignTokens.defaultSuccess,
        ),
        ReportTrendDirection.down => appReadableForeground(
          cs.surface,
          DesignTokens.defaultError,
        ),
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
  final double? maxWidth;

  const _TodayProductivityPill({
    required this.label,
    required this.value,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget content = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 2,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: cs.onSurface.withValues(alpha: 0.56),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.normal,
          ),
        ),
      ],
    );

    if (maxWidth != null && maxWidth! > 0) {
      content = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!),
        child: content,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.18),
          width: 0.45,
        ),
      ),
      child: content,
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
    final strings = context.select<ThemeProvider, BrandStrings>(
      (t) => t.brand.strings,
    );
    final surfaceStyle = appSurfaceStyleOf(context);
    final tileRadius = BorderRadius.circular(
      surfaceStyle?.smallTileRadius ?? DesignTokens.radiusControl,
    );
    final cardRadius = BorderRadius.circular(
      surfaceStyle?.cardRadius ?? DesignTokens.radiusCard,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrowCard =
            constraints.maxWidth.isFinite && constraints.maxWidth < 260;
        final rightPadding = narrowCard ? 12.0 : 16.0;
        final leftPadding = narrowCard ? 12.0 : 16.0;
        final innerWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth - leftPadding - rightPadding - 22.0 - 1.4
            : double.infinity;
        final stackContent = innerWidth < 160.0;

        final leadingIcon = Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.12),
            borderRadius: tileRadius,
          ),
          child: Icon(Icons.add_task_rounded, size: 19, color: cs.primary),
        );
        final trailingArrow = Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.arrow_forward_rounded,
            size: 16,
            color: cs.primary,
          ),
        );
        final titleText = Text(
          strings.todoAddAction,
          maxLines: stackContent ? null : 1,
          softWrap: stackContent,
          overflow: stackContent ? TextOverflow.visible : TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.normal,
          ),
        );
        final subtitleText = Text(
          I18n.tr('today.todos.empty'),
          maxLines: stackContent ? null : 2,
          softWrap: true,
          overflow: stackContent ? TextOverflow.visible : TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.25,
          ),
        );

        return Padding(
          padding: EdgeInsets.fromLTRB(leftPadding, 0, rightPadding, 10),
          child: InkWell(
            borderRadius: cardRadius,
            onTap: onTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color.alphaBlend(
                      cs.primary.withValues(alpha: 0.075),
                      cs.surface,
                    ),
                    cs.surfaceContainerHighest.withValues(alpha: 0.30),
                  ],
                ),
                borderRadius: cardRadius,
                border: Border.all(
                  color: cs.primary.withValues(alpha: 0.20),
                  width: 0.6,
                ),
              ),
              child: stackContent
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (innerWidth >= 78)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [leadingIcon, trailingArrow],
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [leadingIcon, trailingArrow],
                          ),
                        const SizedBox(height: 10),
                        titleText,
                        const SizedBox(height: 3),
                        subtitleText,
                      ],
                    )
                  : Row(
                      children: [
                        leadingIcon,
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              titleText,
                              const SizedBox(height: 3),
                              subtitleText,
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        trailingArrow,
                      ],
                    ),
            ),
          ),
        );
      },
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
      I18n.tr('today.no_due_date'),
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
        I18n.tr('today.completed'),
        Icons.check_circle_outline,
        cs.tertiary,
      ),
      TodoVisualState.overdue => (
        I18n.tr('todo.status.overdue'),
        Icons.priority_high_rounded,
        cs.error,
      ),
      TodoVisualState.dueSoon => (
        I18n.tr('todo.status.due_soon'),
        Icons.alarm_outlined,
        DesignTokens.defaultWarning,
      ),
      _ => (
        I18n.tr('todo.status.normal'),
        Icons.radio_button_unchecked,
        cs.onSurfaceVariant,
      ),
    };
    final foreground = appReadableForeground(
      Color.alphaBlend(color.withValues(alpha: 0.10), cs.surface),
      color,
    );
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
            Icon(icon, size: 10, color: foreground),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 10, color: foreground)),
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
  static const double width = 44;
  static const double height = 44;
  static const double touchTargetSize = 44;
  static const double statusButtonSize = 24;

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
  final bool allowTitleWrap;

  const _TodayTodoTitleLine({
    required this.todo,
    required this.title,
    required this.completed,
    required this.overdue,
    required this.iconKeyPrefix,
    this.titleColor,
    this.allowTitleWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = titleColor ?? (overdue ? cs.error : cs.onSurface);
    final titleStyle = TextStyle(
      color: effectiveColor,
      decoration: completed ? TextDecoration.lineThrough : null,
      fontWeight: FontWeight.normal,
    );
    final avatar = _TodoTemplateAvatar(
      todo: todo,
      keyPrefix: iconKeyPrefix,
      radius: 10,
      iconSize: 12,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final textScaler = MediaQuery.textScalerOf(context);
        final titleTextWidth = _measureTodayTextWidthCached(
          context,
          title,
          titleStyle,
        );
        final badgeWidth = overdue ? _overdueBadgeEstimatedWidth(context) : 0.0;
        final minTitleReserve = math.min(
          titleTextWidth,
          textScaler.scale(14.0) * 4.0,
        );
        final singleLineFits = !overdue ||
            !maxWidth.isFinite ||
            maxWidth >= 20.0 + 7.0 + minTitleReserve + 6.0 + badgeWidth + 1.0;
        final wrapTitle = allowTitleWrap || !singleLineFits;
        final titleWidget = Text(
          title,
          maxLines: wrapTitle ? null : 1,
          softWrap: wrapTitle,
          overflow: wrapTitle ? TextOverflow.visible : TextOverflow.ellipsis,
          style: titleStyle,
        );
        final titleRow = Row(
          crossAxisAlignment: wrapTitle
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            avatar,
            const SizedBox(width: 7),
            Expanded(child: titleWidget),
            if (overdue && singleLineFits) ...[
              const SizedBox(width: 6),
              _OverdueReminderBadge(color: cs.error),
            ],
          ],
        );
        if (!overdue || singleLineFits) {
          return titleRow;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            titleRow,
            const SizedBox(height: 4),
            _OverdueReminderBadge(color: cs.error),
          ],
        );
      },
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
      label: isCompleted
          ? TodayUiCopy.markAsIncomplete
          : TodayUiCopy.markAsComplete,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? () => onChanged?.call(!isCompleted) : null,
          child: SizedBox(
            width: _TodayTodoLeading.touchTargetSize,
            height: _TodayTodoLeading.touchTargetSize,
            child: Center(
              child: Container(
                width: _TodayTodoLeading.statusButtonSize,
                height: _TodayTodoLeading.statusButtonSize,
                decoration: ShapeDecoration(
                  color: background,
                  shape: CircleBorder(
                    side: BorderSide(
                      color: accent.withValues(
                        alpha: isCompleted ? 0.24 : 0.34,
                      ),
                      width: 0.9,
                    ),
                  ),
                ),
                child: isCompleted
                    ? Icon(Icons.check_rounded, size: 15, color: foreground)
                    : null,
              ),
            ),
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
  final double? trailingLayoutWidth;
  final bool? canEdit;

  const _TodayTodoSwipeTile({
    super.key,
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
    this.trailingLayoutWidth,
    this.canEdit,
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
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, locale, _) =>
              Text(TodayUiCopy.readOnlyActionMessage(action, locale)),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool _canDelete(_TodayTodoDeleteOrigin origin, {bool checkRoute = true}) =>
      mounted &&
      widget.todo.id == origin.id &&
      widget.todo.workspaceId == origin.workspaceId &&
      origin.isCurrent(checkRoute: checkRoute);

  Future<void> _confirmDelete(_TodayTodoDeleteOrigin origin) async {
    if (!_canDelete(origin)) return;
    _closeSwipe();
    ModalRoute<dynamic>? dialogRoute;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        final route = ModalRoute.of(dialogCtx);
        dialogRoute = route;
        bool canClose() =>
            dialogCtx.mounted &&
            route?.isActive == true &&
            route?.isCurrent == true;
        return ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, locale, _) => AppDialog(
            icon: const Icon(Icons.delete_outline),
            title: Text(TodayUiCopy.deleteTaskTitle(locale)),
            content: Text(TodayUiCopy.deleteTaskContent(origin.title, locale)),
            actions: [
              TextButton(
                onPressed: () {
                  if (canClose()) Navigator.of(dialogCtx).pop(false);
                },
                child: Text(I18n.tr('action.cancel')),
              ),
              FilledButton(
                onPressed: () {
                  if (canClose() && _canDelete(origin, checkRoute: false)) {
                    Navigator.of(dialogCtx).pop(true);
                  }
                },
                child: Text(I18n.tr('action.delete')),
              ),
            ],
          ),
        );
      },
    );
    await dialogRoute?.completed;
    if (confirmed == true && _canDelete(origin)) {
      await origin.todos.deleteTodo(origin.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final providedCanEdit = widget.canEdit;
    if (providedCanEdit != null) {
      return _buildWithPermission(context, providedCanEdit);
    }
    return _TodayTodoTilePermissionScope(
      workspaceId: widget.todo.workspaceId,
      builder: (canEdit) => _buildWithPermission(context, canEdit),
    );
  }

  Widget _buildWithPermission(BuildContext context, bool canEdit) {
    final deleteOrigin = _TodayTodoDeleteOrigin(context, widget.todo);
    final toggleTodo = widget.onToggle;
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
            TodoVisualState.dueSoon => appReadableForeground(
              cs.surface,
              DesignTokens.defaultWarning,
            ),
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
    final effectiveTitleColor = todo.isCompleted
        ? widget.completedTextColor ?? cs.onSurface.withValues(alpha: 0.52)
        : widget.titleColor ?? (isOverdue ? cs.error : null);
    final compact = MediaQuery.sizeOf(context).width < 360;
    final leadingWidget =
        widget.leading ??
        _TodayTodoLeading(
          statusColor: statusColor,
          isCompleted: isCompleted,
          completedCheckColor: cs.onTertiary,
          onChanged: canEdit
              ? (_) => toggleTodo()
              : (_) => _showReadOnlyMessage('完成任务'),
        );
    final subtitleWidget = widget.subtitle ?? _TodoTodaySubtitle(todo: todo);
    final trailingWidget = widget.trailing;
    Widget tile = LayoutBuilder(
      builder: (context, constraints) {
        final narrowTile =
            constraints.maxWidth.isFinite && constraints.maxWidth < 210;
        final trailingLayoutWidth = widget.trailingLayoutWidth;
        if (trailingLayoutWidth != null && trailingWidget != null) {
          final horizontalPad = compact ? 16.0 : 24.0;
          final leadingAndGap =
              (widget.leading == null ? _TodayTodoLeading.width : 30.0) + 8.0;
          final minTitleReserve =
              27.0 + MediaQuery.textScalerOf(context).scale(14.0) * 4.5;
          final fitsInline = !narrowTile &&
              (!constraints.maxWidth.isFinite ||
                  (constraints.maxWidth -
                          horizontalPad -
                          leadingAndGap -
                          trailingLayoutWidth) >=
                      minTitleReserve);
          if (!fitsInline) {
            final tileInnerWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth - 18.0
                : double.infinity;
            final canShareLeadingRow =
                narrowTile &&
                (44.0 + 6.0 + trailingLayoutWidth) <= tileInnerWidth;
            final titleWidget = _TodayTodoTitleLine(
              todo: todo,
              title: widget.title ?? todo.title,
              titleColor: effectiveTitleColor,
              completed: todo.isCompleted,
              overdue: widget.showOverdueBadge || isOverdue,
              iconKeyPrefix: widget.iconKeyPrefix,
              allowTitleWrap: true,
            );
            final styledSubtitle = DefaultTextStyle.merge(
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              child: subtitleWidget,
            );
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _swipeOpen ? _closeSwipe : widget.onOpen,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 10, 10),
                  child: narrowTile
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                leadingWidget,
                                if (canShareLeadingRow) trailingWidget,
                              ],
                            ),
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: titleWidget,
                            ),
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: styledSubtitle,
                            ),
                            if (!canShareLeadingRow) ...[
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerRight,
                                child: trailingWidget,
                              ),
                            ],
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                leadingWidget,
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        titleWidget,
                                        const SizedBox(height: 4),
                                        styledSubtitle,
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: trailingWidget,
                            ),
                          ],
                        ),
                ),
              ),
            );
          }
        }
        if (narrowTile) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _swipeOpen ? _closeSwipe : widget.onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          leadingWidget,
                          if (trailingWidget != null)
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 96),
                              child: trailingWidget,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _TodayTodoTitleLine(
                        todo: todo,
                        title: widget.title ?? todo.title,
                        titleColor: effectiveTitleColor,
                        completed: todo.isCompleted,
                        overdue: widget.showOverdueBadge || isOverdue,
                        iconKeyPrefix: widget.iconKeyPrefix,
                        allowTitleWrap: true,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: DefaultTextStyle.merge(
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        child: subtitleWidget,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return Material(
          color: Colors.transparent,
          child: ListTile(
            dense: true,
            visualDensity: VisualDensity.standard,
            contentPadding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
            horizontalTitleGap: 4,
            minLeadingWidth: widget.leading == null
                ? _TodayTodoLeading.width
                : 30,
            leading: leadingWidget,
            title: _TodayTodoTitleLine(
              todo: todo,
              title: widget.title ?? todo.title,
              titleColor: effectiveTitleColor,
              completed: todo.isCompleted,
              overdue: widget.showOverdueBadge || isOverdue,
              iconKeyPrefix: widget.iconKeyPrefix,
            ),
            subtitle: subtitleWidget,
            trailing: trailingWidget == null
                ? null
                : ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: trailingLayoutWidth != null
                          ? math.max(compact ? 72 : 96, trailingLayoutWidth)
                          : (compact ? 72 : 96),
                    ),
                    child: trailingWidget,
                  ),
            onTap: _swipeOpen ? _closeSwipe : widget.onOpen,
          ),
        );
      },
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
                          label: I18n.tr('action.delete'),
                          background: canEdit
                              ? cs.errorContainer.withValues(alpha: 0.64)
                              : cs.surfaceContainerHighest.withValues(
                                  alpha: 0.78,
                                ),
                          foreground: canEdit ? cs.error : cs.onSurfaceVariant,
                          onTap: canEdit
                              ? () => _confirmDelete(deleteOrigin)
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

class _TodayTodoTilePermissionScope extends StatelessWidget {
  final String workspaceId;
  final Widget Function(bool canEdit) builder;

  const _TodayTodoTilePermissionScope({
    required this.workspaceId,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final canEdit = context.select<ShareProvider?, bool>(
      (share) => share?.canEdit(workspaceId) ?? true,
    );
    return builder(canEdit);
  }
}

class _TodayTodoDeleteOrigin {
  _TodayTodoDeleteOrigin(this.context, TodoItem todo)
    : authority = SettingsActionOrigin(context),
      todos = context.read<TodoProvider>(),
      share = context.read<ShareProvider?>(),
      id = todo.id,
      title = todo.title,
      workspaceId = todo.workspaceId {
    revision = todos.revision;
  }

  final BuildContext context;
  final SettingsActionOrigin authority;
  final TodoProvider todos;
  final ShareProvider? share;
  final String id;
  final String title;
  final String workspaceId;
  late final int revision;

  bool isCurrent({bool checkRoute = true}) {
    if (!authority.isCurrent(checkRoute: checkRoute)) return false;
    try {
      if (!identical(context.read<TodoProvider>(), todos) ||
          !identical(context.read<ShareProvider?>(), share) ||
          todos.revision != revision ||
          !(share?.canEdit(workspaceId) ?? true)) {
        return false;
      }
      return todos.todos.any(
        (todo) => todo.id == id && todo.workspaceId == workspaceId,
      );
    } catch (_) {
      return false;
    }
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
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 44,
              child: Center(
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: background,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 17, color: foreground),
                ),
              ),
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
    String? datePattern,
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
        subtitle: _todoReminderSubtitle(todo, trigger, now, datePattern),
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
    String? pattern,
  ) {
    final prefix = trigger.isBefore(now)
        ? TodayUiCopy.reminderPrefixPast
        : _sameDay(trigger, DateTime(now.year, now.month, now.day))
        ? TodayUiCopy.reminderPrefixToday
        : TodayUiCopy.reminderPrefixUpcoming;
    final meta = <String>[
      I18nDateFormat.smartDate(trigger, includeTime: true, pattern: pattern),
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
  final VoidCallback Function(TodoItem) onToggleTodo;
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
    final subtitle = TodayUiCopy.reminderSectionSubtitle(
      total: total,
      hasSuggestions: widget.suggestions.isNotEmpty,
    );
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
            LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth;
                final viewLabel = I18n.tr('today.view');
                final titleText = TodayUiCopy.reminderHeaderTitle;
                final subtitleText = _expanded
                    ? subtitle
                    : '$subtitle · ${TodayUiCopy.collapsedByDefault}';
                final titleStyle = theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  height: 1.25,
                  fontWeight: FontWeight.normal,
                );
                final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.56),
                  fontWeight: FontWeight.normal,
                );
                final viewTextStyle = theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.normal,
                );

                final chevronIcon = Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: cs.onSurfaceVariant,
                );

                Widget buildViewButton() => TextButton(
                  onPressed: () =>
                      TodayDetailRouter.open(context, TodaySectionKind.todos),
                  style: TextButton.styleFrom(
                    foregroundColor: cs.primary,
                    textStyle: viewTextStyle,
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    visualDensity: VisualDensity.standard,
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  child: Text(viewLabel),
                );

                final viewButtonWidth = math.max(
                  48.0,
                  24.0 +
                      _measureTodayTextWidthCached(
                        context,
                        viewLabel,
                        viewTextStyle,
                      ) +
                      2.0,
                );
                var maxTitleWordWidth = 0.0;
                for (final word in titleText.split(RegExp(r'\s+'))) {
                  if (word.isEmpty) continue;
                  final w = _measureTodayTextWidthCached(
                    context,
                    word,
                    titleStyle,
                  );
                  if (w > maxTitleWordWidth) {
                    maxTitleWordWidth = w;
                  }
                }
                final requiredWordWidth = maxTitleWordWidth + 4.0;
                const normalHorizontalPadding = 24.0;
                const chevronReserve = 24.0;

                final canFitInlineRow = !availableWidth.isFinite ||
                    (availableWidth -
                            normalHorizontalPadding -
                            chevronReserve -
                            viewButtonWidth) >=
                        math.max(requiredWordWidth, 100.0);

                final titleWidget = Text(
                  TodayUiCopy.reminderHeaderTitle,
                  softWrap: true,
                  style: titleStyle,
                );
                final subtitleWidget = Text(
                  subtitleText,
                  softWrap: true,
                  style: subtitleStyle,
                );
                final titleAndSubtitle = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleWidget,
                    const SizedBox(height: 2),
                    subtitleWidget,
                  ],
                );

                if (canFitInlineRow) {
                  return InkWell(
                    key: const ValueKey('today_reminder_header_toggle'),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(DesignTokens.radiusCard),
                    ),
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Row(
                        children: [
                          chevronIcon,
                          const SizedBox(width: 6),
                          Expanded(child: titleAndSubtitle),
                          buildViewButton(),
                        ],
                      ),
                    ),
                  );
                }

                final canFitChevronBesideTitle =
                    (availableWidth -
                            normalHorizontalPadding -
                            chevronReserve) >=
                        requiredWordWidth;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      key: const ValueKey('today_reminder_header_toggle'),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(DesignTokens.radiusCard),
                      ),
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Padding(
                        padding: canFitChevronBesideTitle
                            ? const EdgeInsets.fromLTRB(16, 12, 8, 4)
                            : const EdgeInsets.fromLTRB(4, 12, 4, 4),
                        child: canFitChevronBesideTitle
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: chevronIcon,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(child: titleAndSubtitle),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  chevronIcon,
                                  const SizedBox(height: 6),
                                  titleAndSubtitle,
                                ],
                              ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        canFitChevronBesideTitle ? 16 : 4,
                        0,
                        canFitChevronBesideTitle ? 8 : 4,
                        4,
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: buildViewButton(),
                      ),
                    ),
                  ],
                );
              },
            ),
            if (_expanded && widget.groups.dueToday.isNotEmpty)
              _ReminderGroupBlock(
                title: TodayUiCopy.reminderGroupDueToday,
                items: widget.groups.dueToday.take(4).toList(),
                now: widget.now,
                onOpenTodo: widget.onOpenTodo,
                onToggleTodo: widget.onToggleTodo,
                onOpenCourses: widget.onOpenCourses,
              ),
            if (_expanded && widget.groups.upcoming.isNotEmpty)
              _ReminderGroupBlock(
                title: TodayUiCopy.reminderGroupUpcoming,
                items: widget.groups.upcoming.take(4).toList(),
                now: widget.now,
                onOpenTodo: widget.onOpenTodo,
                onToggleTodo: widget.onToggleTodo,
                onOpenCourses: widget.onOpenCourses,
              ),
            if (_expanded && widget.groups.overdue.isNotEmpty)
              _ReminderGroupBlock(
                title: TodayUiCopy.reminderGroupOverdue,
                items: widget.groups.overdue.take(4).toList(),
                now: widget.now,
                overdue: true,
                onOpenTodo: widget.onOpenTodo,
                onToggleTodo: widget.onToggleTodo,
                onOpenCourses: widget.onOpenCourses,
              ),
            if (_expanded && widget.suggestions.isNotEmpty)
              _SuggestionSection(
                key: const ValueKey('today_suggestion_section'),
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
  final VoidCallback Function(TodoItem) onToggleTodo;
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final titleStyle = Theme.of(context).textTheme.labelMedium
                      ?.copyWith(
                        color: overdue ? cs.error : cs.onSurface,
                        fontWeight: FontWeight.normal,
                      );
                  final countText = TodayUiCopy.itemCount(items.length);
                  final countStyle = Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant);
                  final icon = Icon(
                    overdue
                        ? Icons.warning_amber_outlined
                        : Icons.notifications_none_outlined,
                    size: 16,
                    color: color,
                  );

                  final titleWidth = _measureTodayTextWidthCached(
                    context,
                    title,
                    titleStyle,
                  );
                  final countWidth = _measureTodayTextWidthCached(
                    context,
                    countText,
                    countStyle,
                  );
                  final badgeWidth = overdue
                      ? 8.0 + _overdueBadgeEstimatedWidth(context)
                      : 0.0;
                  final requiredSingleLineWidth =
                      16.0 +
                      6.0 +
                      titleWidth +
                      badgeWidth +
                      8.0 +
                      countWidth +
                      1.0;

                  if (!constraints.maxWidth.isFinite ||
                      constraints.maxWidth >= requiredSingleLineWidth) {
                    return Row(
                      children: [
                        icon,
                        const SizedBox(width: 6),
                        Text(title, style: titleStyle),
                        if (overdue) ...[
                          const SizedBox(width: 8),
                          _OverdueReminderBadge(color: cs.error),
                        ],
                        const Spacer(),
                        Text(countText, style: countStyle),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          icon,
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              title,
                              softWrap: true,
                              style: titleStyle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (overdue) _OverdueReminderBadge(color: cs.error),
                          Text(countText, style: countStyle),
                        ],
                      ),
                    ],
                  );
                },
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final badgeWidth = _overdueBadgeEstimatedWidth(context);
        final textScaler = MediaQuery.textScalerOf(context);
        final titleWidth = _measureTodayTextWidthCached(
          context,
          title,
          TextStyle(color: color),
        );
        final minTitleReserve = math.min(
          titleWidth,
          textScaler.scale(14.0) * 4.0,
        );
        final singleLineFits = !constraints.maxWidth.isFinite ||
            constraints.maxWidth >= badgeWidth + 6.0 + minTitleReserve + 1.0;
        if (singleLineFits) {
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _OverdueReminderBadge(color: color),
            const SizedBox(height: 4),
            Text(
              title,
              softWrap: true,
              style: TextStyle(color: color),
            ),
          ],
        );
      },
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
            Flexible(
              child: Text(
                I18n.tr('todo.status.overdue'),
                style: TextStyle(fontSize: 10, color: color),
              ),
            ),
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
  final VoidCallback Function(TodoItem) onToggleTodo;
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
      final toggleTodo = onToggleTodo(todo);
      return _TodayTodoSwipeTile(
        key: ValueKey('today_reminder_todo_${todo.id}'),
        todo: todo,
        canEdit: context.read<ShareProvider?>()?.canEdit(todo.workspaceId) ?? true,
        onToggle: toggleTodo,
        onOpen: () => onOpenTodo(item.id),
        leading: _TodayTodoLeading(
          statusColor: overdue
              ? cs.error
              : completed
              ? completedColor
              : _todoTemplateVisual(context, todo).color,
          isCompleted: completed,
          completedCheckColor: overdue ? cs.onError : cs.onTertiary,
          onChanged: (_) => toggleTodo(),
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
      return TodayUiCopy.pastStatusMinutes(
        minutes: minutes,
        isCourse: item.kind == _TodayReminderKind.course,
      );
    }
    return TodayUiCopy.pastStatusDays(days);
  }
}

class _SuggestionSection extends StatefulWidget {
  final List<SmartScheduleSuggestion> suggestions;
  final DateTime todayKey;
  final ValueChanged<String> onOpenTodo;
  final Future<void> Function(TodoItem todo) onAddToday;

  const _SuggestionSection({
    super.key,
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
  final Map<String, int> _addingTodoOpSeqs = <String, int>{};
  int _addingActionSeq = 0;
  final ExpansibleController _expansionController = ExpansibleController();
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _onAccountDataGenerationChanged,
    );
  }

  void _onAccountDataGenerationChanged() {
    if (!mounted) return;
    _addingActionSeq++;
    _addingTodoOpSeqs.clear();
    _addingTodoIds.clear();
    setState(() {});
  }

  @override
  void dispose() {
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _onAccountDataGenerationChanged,
    );
    _expansionController.dispose();
    super.dispose();
  }

  Future<void> _addToday(
    TodoItem todo, {
    required int rowGeneration,
    required Future<void> Function(TodoItem todo) action,
  }) async {
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      rowGeneration,
    )) {
      return;
    }
    if (_addingTodoIds.contains(todo.id)) return;
    final seq = ++_addingActionSeq;
    _addingTodoOpSeqs[todo.id] = seq;
    setState(() => _addingTodoIds.add(todo.id));
    try {
      await action(todo);
    } finally {
      if (mounted && _addingTodoOpSeqs[todo.id] == seq) {
        _addingTodoOpSeqs.remove(todo.id);
        setState(() => _addingTodoIds.remove(todo.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final suggestionsTitle = I18n.tr('today.suggestions');
    final suggestionsSubtitle = _expanded
        ? I18n.tr('today.suggestions.subtitle')
        : '${I18n.tr('today.suggestions.subtitle')} · ${TodayUiCopy.collapsedByDefault}';
    final titleStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.normal,
    );
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurface.withValues(alpha: 0.58),
    );
    final addLabel = I18n.tr('today.add_to_today');
    final addButtonTextStyle =
        theme.textButtonTheme.style?.textStyle?.resolve(
          const <WidgetState>{},
        ) ??
        theme.textTheme.labelLarge;
    final addButtonWidth = math.max(
      56.0,
      _measureTodayTextWidthCached(context, addLabel, addButtonTextStyle) +
          22.0,
    );

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          var maxTitleWordWidth = 0.0;
          for (final word in suggestionsTitle.split(RegExp(r'\s+'))) {
            if (word.isEmpty) continue;
            final w = _measureTodayTextWidthCached(context, word, titleStyle);
            if (w > maxTitleWordWidth) {
              maxTitleWordWidth = w;
            }
          }
          const inlineTilePadding = EdgeInsets.fromLTRB(16, 4, 12, 4);
          const leadingIconSize = 18.0;
          final listTileTheme = ListTileTheme.of(context);
          final effectiveVisualDensity =
              listTileTheme.visualDensity ??
              theme.listTileTheme.visualDensity ??
              theme.visualDensity;
          final horizontalTitleGap =
              listTileTheme.horizontalTitleGap ??
              theme.listTileTheme.horizontalTitleGap ??
              16.0;
          final effectiveTitleGap =
              horizontalTitleGap + effectiveVisualDensity.horizontal * 2.0;
          final minLeadingWidth =
              listTileTheme.minLeadingWidth ??
              theme.listTileTheme.minLeadingWidth ??
              (theme.useMaterial3 ? 24.0 : 40.0);
          final chevronWidth = IconTheme.of(context).size ?? 24.0;
          final leadingReservation = math.max(
            0.0,
            math.max(minLeadingWidth, leadingIconSize) + effectiveTitleGap,
          );
          final trailingReservation = math.max(
            chevronWidth + effectiveTitleGap,
            32.0,
          );
          final inlineOverhead =
              inlineTilePadding.horizontal +
              leadingReservation +
              trailingReservation;
          final reflowHeader = availableWidth.isFinite &&
              (availableWidth - inlineOverhead) < (maxTitleWordWidth + 4.0);
          final leadingSparkIcon = Icon(
            Icons.auto_awesome,
            size: leadingIconSize,
            color: cs.primary.withValues(alpha: 0.72),
          );

          return ExpansionTile(
            key: const PageStorageKey<String>(
              'today_suggestions_expansion_tile',
            ),
            controller: _expansionController,
            initiallyExpanded: _expanded,
            maintainState: true,
            onExpansionChanged: (expanded) {
              setState(() => _expanded = expanded);
            },
            tilePadding: reflowHeader
                ? EdgeInsets.fromLTRB(
                    availableWidth < 240 ? 8 : 14,
                    6,
                    availableWidth < 240 ? 8 : 14,
                    6,
                  )
                : inlineTilePadding,
            childrenPadding: const EdgeInsets.only(bottom: 4),
            leading: reflowHeader ? null : leadingSparkIcon,
            showTrailingIcon: !reflowHeader,
            title: reflowHeader
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          leadingSparkIcon,
                          Icon(
                            _expanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 20,
                            color: cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        suggestionsTitle,
                        softWrap: true,
                        style: titleStyle,
                      ),
                    ],
                  )
                : Text(
                    suggestionsTitle,
                    softWrap: true,
                    style: titleStyle,
                  ),
            subtitle: Text(
              suggestionsSubtitle,
              softWrap: true,
              style: subtitleStyle,
            ),
            children: widget.suggestions.map((suggestion) {
              final t = suggestion.todo;
              final adding = _addingTodoIds.contains(t.id);
              final rowGeneration =
                  AccountLocalDataCleaner.accountDataGeneration;
              final rowAction = widget.onAddToday;
              final onOpenTodo = widget.onOpenTodo;
              final hasAddAction =
                  !_sameDay(t.date, widget.todayKey) &&
                  !t.isArchivedAfterRollover;
              return _TodayTodoSwipeTile(
                key: ValueKey('today_suggestion_todo_${t.id}'),
                todo: t,
                canEdit:
                    context.read<ShareProvider?>()?.canEdit(t.workspaceId) ??
                    true,
                onToggle: () {},
                onOpen: () => onOpenTodo(t.id),
                title: t.title,
                titleColor: cs.onSurface.withValues(alpha: 0.76),
                iconKeyPrefix: 'today_suggestion_template_icon',
                trailingLayoutWidth: hasAddAction ? addButtonWidth : null,
                subtitle: Text(
                  TodayUiCopy.formatSuggestionReason(suggestion.reason),
                  softWrap: true,
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: !hasAddAction
                    ? null
                    : TextButton(
                        key: ValueKey('today_suggestion_add_${t.id}'),
                        onPressed: adding
                            ? null
                            : () => _addToday(
                                t,
                                rowGeneration: rowGeneration,
                                action: rowAction,
                              ),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(56, 44),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          visualDensity: VisualDensity.standard,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: adding
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                addLabel,
                                softWrap: true,
                                textAlign: TextAlign.center,
                              ),
                      ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _QuoteCardState extends State<_QuoteCard> {
  late int _quoteIndex;

  @override
  void initState() {
    super.initState();
    _quoteIndex = DailyQuotes.todayIndex();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = Theme.of(context).colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final text = DailyQuotes.at(_quoteIndex, locale: I18n.current);
    return AppSurfaceCard(
      onTap: () => setState(() => _quoteIndex = DailyQuotes.randomIndex()),
      padding: const EdgeInsets.all(14),
      gradient: LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color.alphaBlend(
            cs.secondary.withValues(alpha: isDark ? 0.08 : 0.04),
            cs.surface,
          ),
          cs.surface,
        ],
      ),
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: isDark ? 0.14 : 0.18),
        width: 0.55,
      ),
      elevation: 1,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.12),
                width: 0.45,
              ),
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
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, height: 1.55),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.36),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.refresh,
              size: 15,
              color: cs.onSurface.withValues(alpha: 0.48),
            ),
          ),
        ],
      ),
    );
  }
}
