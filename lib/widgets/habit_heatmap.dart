import 'package:flutter/material.dart';

class HabitHeatmap extends StatelessWidget {
  final Map<String, int> heatmapData; // dateKey -> intensity 0-5
  final int weeks;

  const HabitHeatmap({super.key, required this.heatmapData, this.weeks = 12});

  Color _cellColor(int intensity, Color primary) {
    if (intensity == 0) return Colors.grey.shade200;
    final opacities = [0.0, 0.2, 0.35, 0.5, 0.65, 0.85];
    return primary.withValues(alpha: opacities[intensity.clamp(0, 5)]);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: weeks * 7 - 1));
    final columns = weeks;
    final rows = 7;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 28),
              ...List.generate(columns, (c) {
                final w = startDate.add(Duration(days: c * 7));
                return SizedBox(
                  width: 16,
                  child: c % 4 == 0
                      ? Text('${w.month}月', style: const TextStyle(fontSize: 9))
                      : const SizedBox(),
                );
              }),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Column(
                children: ['一', '', '三', '', '五', '', '日'].map((s) => SizedBox(
                      height: 14, width: 24,
                      child: s.isEmpty ? null : Center(child: Text(s, style: const TextStyle(fontSize: 9)))),
                ).toList(),
              ),
              ...List.generate(columns, (c) {
                return Column(
                  children: List.generate(rows, (r) {
                    final date = startDate.add(Duration(days: c * 7 + r));
                    final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                    final intensity = heatmapData[key] ?? 0;
                    return Container(
                      width: 14, height: 14, margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: _cellColor(intensity, primary),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}