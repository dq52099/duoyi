import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/habit_provider.dart';

class HabitWeeklyCard extends StatelessWidget {
  const HabitWeeklyCard({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<HabitProvider>().last7DaysCompletion();
    final labels = ['一', '二', '三', '四', '五', '六', '日'];
    final todayDOW = DateTime.now().weekday - 1;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_view_week, size: 18, color: primaryColor),
                const SizedBox(width: 8),
                const Text(
                  '本周概览',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
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
                        fontSize: 12,
                        fontWeight: isToday
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isToday ? primaryColor : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: bg,
                        shape: BoxShape.circle,
                        border: isToday
                            ? Border.all(color: primaryColor, width: 2)
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
                          i > todayDOW ? '-' : '${(val * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 10,
                            color: textColor,
                            fontWeight: FontWeight.bold,
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
      ),
    );
  }
}
