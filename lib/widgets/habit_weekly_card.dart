import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 9),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: primaryColor.withValues(alpha: 0.18),
        width: 0.7,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                key: const ValueKey('habit_weekly_overview_icon_box'),
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(
                  Icons.calendar_view_week_rounded,
                  size: 28,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '本周概述',
                      style: appSecondaryRouteTitleTextStyle(
                        context,
                      ).copyWith(fontSize: 19),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '今日 $completedToday/$activeToday 达标',
                      style: appSecondaryControlLabelStyle(
                        context,
                      ).copyWith(color: cs.onSurface.withValues(alpha: 0.62)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
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
                      style: TextStyle(
                        color: primaryColor,
                        fontSize: 24,
                        height: 1.0,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '进度 $weekPercent%',
                      style: appSecondaryControlLabelStyle(
                        context,
                      ).copyWith(color: cs.onSurface.withValues(alpha: 0.62)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              key: const ValueKey('habit_weekly_overview_progress_bar'),
              value: weekAverage.clamp(0.0, 1.0).toDouble(),
              minHeight: 10,
              backgroundColor: primaryColor.withValues(alpha: 0.10),
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 16),
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
                      fontSize: 10.5,
                      fontWeight: FontWeight.normal,
                      color: isToday ? primaryColor : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Container(
                    key: ValueKey('habit_weekly_overview_day_$i'),
                    width: 44,
                    height: 44,
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
                                color: bg.withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        i > todayDOW ? '-' : '${(val * 100).round()}%',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: textColor,
                          fontWeight: FontWeight.normal,
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
