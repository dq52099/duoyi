import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/design_tokens.dart';
import '../providers/habit_provider.dart';
import 'surface_components.dart';

class HabitWeeklyCard extends StatelessWidget {
  const HabitWeeklyCard({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HabitProvider>();
    final data = provider.currentWeekProgress();
    final labels = ['一', '二', '三', '四', '五', '六', '日'];
    final todayDOW = DateTime.now().weekday - 1;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
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
                  color: primaryColor.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                ),
                child: Icon(
                  Icons.calendar_view_week_rounded,
                  size: 16,
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
                    const SizedBox(height: 1),
                    Text(
                      '今日 $completedToday/$activeToday 达标',
                      style: appSecondaryControlLabelStyle(context).copyWith(
                        fontSize: DesignTokens.fontSizeCaption,
                        color: cs.onSurface.withValues(alpha: 0.62),
                        height: 1.12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: primaryColor.withValues(alpha: 0.16),
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
                        fontSize: 13,
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
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              key: const ValueKey('habit_weekly_overview_progress_bar'),
              value: weekAverage.clamp(0.0, 1.0).toDouble(),
              minHeight: 3,
              backgroundColor: primaryColor.withValues(alpha: 0.10),
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final val = data[i];
              Color bg;
              Color textColor = Colors.white;

              if (i > todayDOW) {
                bg = Colors.grey.withValues(alpha: 0.1);
                textColor = Colors.grey.shade400;
              } else if (val >= 1.0) {
                bg = const Color(0xFF4CAF50);
              } else if (val > 0) {
                bg = const Color(0xFFFFB74D);
              } else {
                bg = Colors.grey.withValues(alpha: 0.2);
                textColor = Colors.grey.shade600;
              }

              final isToday = i == todayDOW;

              return Column(
                children: [
                  Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: DesignTokens.fontSizeCaption,
                      fontWeight: DesignTokens.fontWeightRegular,
                      color: isToday ? primaryColor : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    key: ValueKey('habit_weekly_overview_day_$i'),
                    width: 25,
                    height: 25,
                    decoration: BoxDecoration(
                      color: bg,
                      shape: BoxShape.circle,
                      border: isToday
                          ? Border.all(
                              color: primaryColor.withValues(alpha: 0.34),
                              width: 0.8,
                            )
                          : null,
                      boxShadow: isToday && val > 0
                          ? [
                              BoxShadow(
                                color: bg.withValues(alpha: 0.22),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        i > todayDOW ? '-' : '${(val * 100).round()}%',
                        style: TextStyle(
                          fontSize: 8.5,
                          color: textColor,
                          fontWeight: DesignTokens.fontWeightRegular,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}
