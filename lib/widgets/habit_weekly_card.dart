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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('本周概览', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(7, (i) {
                final val = data[i];
                Color bg;
                if (val >= 1.0) {
                  bg = Colors.green;
                } else if (val > 0) {
                  bg = Colors.orange;
                } else {
                  bg = Colors.grey.shade300;
                }
                if (i == todayDOW) bg = i <= todayDOW ? bg : Theme.of(context).colorScheme.primary.withValues(alpha: 0.3);

                return Column(
                  children: [
                    Text(labels[i], style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    const SizedBox(height: 4),
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                      child: Center(child: Text('${(val * 100).toInt()}%', style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w600))),
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