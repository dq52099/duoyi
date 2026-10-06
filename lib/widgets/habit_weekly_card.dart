import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/habit_icons.dart';
import '../models/habit.dart';
import '../providers/habit_provider.dart';
import '../services/account_local_data_cleaner.dart';
import 'surface_components.dart';

class HabitWeeklyCard extends StatelessWidget {
  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  const HabitWeeklyCard({super.key});

  void _showDayDetail(BuildContext context, DateTime date) {
    final habitProvider = context.read<HabitProvider>();
    showAppModalSheet<void>(
      context: context,
      builder: (sheetContext) => ChangeNotifierProvider<HabitProvider>.value(
        value: habitProvider,
        child: _HabitWeeklyDayDetailSheet(date: date),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HabitProvider>();
    final data = provider.currentWeekProgress();
    final labels = _weekdayLabels;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayDOW = now.weekday - 1;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = cs.primary;
    final elapsed = todayDOW + 1;
    final weekAverage =
        data.take(elapsed).fold<double>(0, (sum, value) => sum + value) /
        elapsed;
    final activeToday = provider.habits.where((h) => h.isActiveToday()).length;
    final completedToday = provider.habits
        .where((h) => h.isActiveToday() && h.isCompletedToday())
        .length;
    final weekPercent = (weekAverage * 100).round();

    return AppSurfaceCard(
      key: const ValueKey('habit_weekly_overview_card'),
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
      borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(
            primaryColor.withValues(alpha: isDark ? 0.16 : 0.08),
            cs.surface,
          ),
          Color.alphaBlend(
            cs.tertiary.withValues(alpha: isDark ? 0.10 : 0.045),
            cs.surface,
          ),
        ],
      ),
      border: Border.all(
        color: primaryColor.withValues(alpha: isDark ? 0.22 : 0.16),
        width: 0.65,
      ),
      elevation: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                key: const ValueKey('habit_weekly_overview_icon_box'),
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: isDark ? 0.18 : 0.11),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  border: Border.all(
                    color: primaryColor.withValues(alpha: 0.12),
                    width: 0.5,
                  ),
                ),
                child: Icon(
                  Icons.calendar_view_week_rounded,
                  size: 18,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '本周概述',
                      style: appSecondaryRouteTitleTextStyle(context).copyWith(
                        fontSize: 13,
                        fontWeight: DesignTokens.fontWeightRegular,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '今日 $completedToday/$activeToday 达标',
                      style: appSecondaryControlLabelStyle(context).copyWith(
                        fontSize: DesignTokens.fontSizeCaption,
                        color: cs.onSurface.withValues(alpha: 0.58),
                        height: 1.12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: isDark ? 0.26 : 0.70),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: primaryColor.withValues(alpha: 0.14),
                    width: 0.6,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$weekPercent%',
                      key: const ValueKey('habit_weekly_overview_percent'),
                      style: TextStyle(
                        color: primaryColor,
                        fontSize: 15,
                        height: 1.0,
                        fontWeight: DesignTokens.fontWeightRegular,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '进度',
                      style: appSecondaryControlLabelStyle(context).copyWith(
                        fontSize: 10,
                        color: cs.onSurface.withValues(alpha: 0.62),
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              key: const ValueKey('habit_weekly_overview_progress_bar'),
              value: weekAverage.clamp(0.0, 1.0).toDouble(),
              minHeight: 3,
              backgroundColor: cs.surfaceContainerHighest.withValues(
                alpha: isDark ? 0.20 : 0.42,
              ),
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 7),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final val = data[i];
              final isToday = i == todayDOW;
              final isFuture = i > todayDOW;
              final dayDate = DateTime(
                today.year,
                today.month,
                today.day - (todayDOW - i),
              );
              Color bg;
              Color textColor = cs.onSurface;
              Color borderColor = Colors.transparent;

              if (isFuture) {
                bg = cs.surfaceContainerHighest.withValues(
                  alpha: isDark ? 0.15 : 0.34,
                );
                textColor = cs.onSurface.withValues(alpha: 0.36);
                borderColor = cs.outlineVariant.withValues(alpha: 0.12);
              } else if (val >= 1.0) {
                bg = const Color(0xFF2E7D32);
                textColor = Colors.white;
              } else if (val > 0) {
                bg = const Color(0xFFFFB74D);
                textColor = const Color(0xFF2D1F0F);
              } else {
                bg = cs.surface.withValues(alpha: isDark ? 0.28 : 0.70);
                textColor = cs.onSurface.withValues(alpha: 0.52);
                borderColor = cs.outlineVariant.withValues(alpha: 0.18);
              }

              final tooltipMessage = isFuture
                  ? '周${labels[i]} (未开始)'
                  : '周${labels[i]} ${(val * 100).round()}%${isToday ? ' (今天)' : ''}';
              final semanticsLabel = isFuture
                  ? '周${labels[i]}，未开始'
                  : '周${labels[i]}，完成率 ${(val * 100).round()}%${isToday ? '，今天' : ''}';

              return Tooltip(
                message: tooltipMessage,
                child: Semantics(
                  button: true,
                  enabled: !isFuture,
                  label: semanticsLabel,
                  hint: isFuture ? null : '点击查看习惯明细',
                  child: InkResponse(
                    containedInkWell: true,
                    highlightShape: BoxShape.rectangle,
                    borderRadius: BorderRadius.circular(13),
                    onTap: isFuture
                        ? null
                        : () => _showDayDetail(context, dayDate),
                    child: Container(
                      width: 30,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: isToday
                            ? primaryColor.withValues(
                                alpha: isDark ? 0.13 : 0.08,
                              )
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Column(
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              labels[i],
                              style: TextStyle(
                                fontSize: DesignTokens.fontSizeCaption,
                                fontWeight: DesignTokens.fontWeightRegular,
                                color: isToday
                                    ? primaryColor
                                    : cs.onSurface.withValues(alpha: 0.56),
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Container(
                            key: ValueKey('habit_weekly_overview_day_$i'),
                            width: 25,
                            height: 25,
                            decoration: BoxDecoration(
                              color: bg,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isToday
                                    ? primaryColor.withValues(alpha: 0.46)
                                    : borderColor,
                                width: isToday ? 1.05 : 0.55,
                              ),
                              boxShadow: isToday && val > 0
                                  ? [
                                      BoxShadow(
                                        color: bg.withValues(
                                          alpha: isDark ? 0.20 : 0.26,
                                        ),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Padding(
                                  padding: const EdgeInsets.all(2.0),
                                  child: Text(
                                    isFuture ? '-' : '${(val * 100).round()}%',
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      color: textColor,
                                      fontWeight:
                                          DesignTokens.fontWeightRegular,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _HabitWeeklyDayDetailSheet extends StatefulWidget {
  final DateTime date;

  const _HabitWeeklyDayDetailSheet({required this.date});

  @override
  State<_HabitWeeklyDayDetailSheet> createState() =>
      _HabitWeeklyDayDetailSheetState();
}

class _HabitWeeklyDayDetailSheetState
    extends State<_HabitWeeklyDayDetailSheet> {
  late final int _initialGeneration;
  ModalRoute<dynamic>? _ownRoute;
  NavigatorState? _navigator;
  bool _invalidated = false;

  @override
  void initState() {
    super.initState();
    _initialGeneration = AccountLocalDataCleaner.accountDataGeneration;
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _onAccountDataGenerationChanged,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ownRoute = ModalRoute.of(context);
    _navigator = Navigator.of(context);
  }

  @override
  void dispose() {
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _onAccountDataGenerationChanged,
    );
    super.dispose();
  }

  void _onAccountDataGenerationChanged() {
    _invalidateAndClose();
  }

  void _invalidateAndClose() {
    if (_invalidated) return;
    _invalidated = true;
    if (mounted) {
      setState(() {});
    }
    final route = _ownRoute;
    final nav = _navigator;
    if (route != null && nav != null && route.isActive) {
      if (route.isCurrent) {
        nav.pop();
      } else {
        nav.removeRoute(route);
      }
    }
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _habitExistsOnDate(Habit h, DateTime date) {
    final day = _dateOnly(date);
    final start = _dateOnly(h.startDate ?? h.createdAt);
    return !day.isBefore(start);
  }

  @override
  Widget build(BuildContext context) {
    if (_invalidated ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _initialGeneration,
        )) {
      if (!_invalidated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _invalidateAndClose();
        });
      }
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final date = widget.date;
    final weekdayLabel = HabitWeeklyCard._weekdayLabels[date.weekday - 1];
    final dateTitle = '${date.month}月${date.day}日 周$weekdayLabel';

    return Consumer<HabitProvider>(
      builder: (context, provider, child) {
        if (_invalidated ||
            !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
              _initialGeneration,
            )) {
          return const SizedBox.shrink();
        }

        final activeHabits = provider.habits
            .where((h) => _habitExistsOnDate(h, date) && h.activeForDate(date))
            .toList();
        final completedCount = activeHabits
            .where((h) => h.isCompletedForDate(date))
            .length;
        final subtitle = activeHabits.isEmpty
            ? null
            : '达标 $completedCount/${activeHabits.length}';

        return AppModalSheet(
          title: dateTitle,
          subtitle: subtitle,
          maxWidth: 520,
          child: activeHabits.isEmpty
              ? AppSurfaceCard(
                  key: const ValueKey('habit_weekly_day_detail_empty'),
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  child: Center(
                    child: Text(
                      '当天暂无活跃习惯',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: DesignTokens.fontWeightRegular,
                        color: cs.onSurface.withValues(alpha: 0.58),
                      ),
                    ),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final habit in activeHabits)
                      _buildHabitItem(context, habit, isDark, cs),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildHabitItem(
    BuildContext context,
    Habit habit,
    bool isDark,
    ColorScheme cs,
  ) {
    final date = widget.date;
    final isCompleted = habit.isCompletedForDate(date);
    final progress = habit.progressForDate(date);
    final countText = habit.formatCountForDate(date);
    final habitColor = Color(habit.colorValue);

    return AppSurfaceCard(
      key: ValueKey('habit_day_detail_${habit.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: habitColor.withValues(alpha: isDark ? 0.22 : 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  habitDisplayIconFor(habit),
                  size: 16,
                  color: habitColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  habit.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: DesignTokens.fontWeightRegular,
                    color: cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isCompleted
                      ? const Color(
                          0xFF2E7D32,
                        ).withValues(alpha: isDark ? 0.25 : 0.12)
                      : cs.surfaceContainerHighest.withValues(
                          alpha: isDark ? 0.25 : 0.45,
                        ),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                ),
                child: Text(
                  isCompleted ? '已达标' : '未达标',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: DesignTokens.fontWeightRegular,
                    color: isCompleted
                        ? (isDark
                              ? const Color(0xFF81C784)
                              : const Color(0xFF2E7D32))
                        : cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0).toDouble(),
                    minHeight: 4,
                    backgroundColor: cs.surfaceContainerHighest.withValues(
                      alpha: isDark ? 0.20 : 0.42,
                    ),
                    color: isCompleted ? const Color(0xFF2E7D32) : habitColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                countText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: DesignTokens.fontWeightRegular,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
