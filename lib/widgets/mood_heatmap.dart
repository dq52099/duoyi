import 'package:flutter/material.dart';
import '../models/diary_entry.dart';

/// 近 N 周心情热图：每格代表一天，颜色由当天日记的心情决定；无日记则灰色。
class MoodHeatmap extends StatelessWidget {
  final Map<String, DiaryEntry> entriesByDate;
  final int weeks;

  const MoodHeatmap({
    super.key,
    required this.entriesByDate,
    this.weeks = 12,
  });

  Color _colorFor(Mood? m) {
    if (m == null) return const Color(0xFFEDEDED);
    return switch (m) {
      Mood.awesome => const Color(0xFF2E7D32),
      Mood.good => const Color(0xFF66BB6A),
      Mood.okay => const Color(0xFFFFCA28),
      Mood.bad => const Color(0xFFEF6C00),
      Mood.terrible => const Color(0xFFD32F2F),
    };
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // 对齐到周一
    final thisMonday =
        DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final startMonday = thisMonday.subtract(Duration(days: (weeks - 1) * 7));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final cell = ((constraints.maxWidth - 4 - 18) / weeks).clamp(6.0, 14.0);
          return Row(
            children: [
              SizedBox(
                width: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final d in const ['一', '三', '五', '日'])
                      Padding(
                        padding: EdgeInsets.only(top: cell * 0.4),
                        child: Text(d,
                            style: TextStyle(
                                fontSize: 9,
                                color: Colors.grey.shade500)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: List.generate(weeks, (w) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Column(
                        children: List.generate(7, (dow) {
                          final date = startMonday.add(Duration(days: w * 7 + dow));
                          if (date.isAfter(DateTime(now.year, now.month, now.day))) {
                            return SizedBox(width: cell, height: cell);
                          }
                          final key =
                              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                          final entry = entriesByDate[key];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Tooltip(
                              message:
                                  '${date.year}-${date.month}-${date.day} · ${entry?.mood?.label ?? '无记录'}',
                              child: Container(
                                width: cell,
                                height: cell,
                                decoration: BoxDecoration(
                                  color: _colorFor(entry?.mood),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    );
                  }),
                ),
              ),
            ],
          );
        }),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('少',
                style: TextStyle(
                    fontSize: 10, color: Colors.grey.shade600)),
            const SizedBox(width: 4),
            ...Mood.values.map(
              (m) => Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _colorFor(m),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text('多',
                style: TextStyle(
                    fontSize: 10, color: Colors.grey.shade600)),
          ],
        ),
      ],
    );
  }
}
