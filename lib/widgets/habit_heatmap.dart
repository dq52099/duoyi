import 'package:flutter/material.dart';

class HabitHeatmap extends StatelessWidget {
  final Map<String, int> heatmapData; // dateKey -> intensity 0-5
  final int weeks;

  const HabitHeatmap({super.key, required this.heatmapData, this.weeks = 12});

  Color _cellColor(int intensity, Color primary) {
    if (intensity == 0) return primary.withValues(alpha: 0.08);
    final opacities = [0.0, 0.22, 0.36, 0.52, 0.68, 0.9];
    return primary.withValues(alpha: opacities[intensity.clamp(0, 5)]);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: weeks * 7 - 1));
    final columns = weeks;
    final rows = 7;

    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        final cell = ((available - 32 - columns * 2) / columns).clamp(
          11.0,
          18.0,
        );
        final grid = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 28),
                ...List.generate(columns, (c) {
                  final w = startDate.add(Duration(days: c * 7));
                  return SizedBox(
                    width: cell + 2,
                    child: c % 4 == 0
                        ? Text(
                            '${w.month}月',
                            style: TextStyle(
                              fontSize: 9,
                              color: cs.onSurfaceVariant,
                            ),
                          )
                        : const SizedBox(),
                  );
                }),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Column(
                  children: ['一', '', '三', '', '五', '', '日']
                      .map(
                        (s) => SizedBox(
                          height: cell + 2,
                          width: 24,
                          child: s.isEmpty
                              ? null
                              : Center(
                                  child: Text(
                                    s,
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                        ),
                      )
                      .toList(),
                ),
                ...List.generate(columns, (c) {
                  return Column(
                    children: List.generate(rows, (r) {
                      final date = startDate.add(Duration(days: c * 7 + r));
                      final key =
                          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                      final intensity = heatmapData[key] ?? 0;
                      return Tooltip(
                        message:
                            '${date.year}-${date.month}-${date.day} · $intensity 次',
                        child: Container(
                          width: cell,
                          height: cell,
                          margin: const EdgeInsets.all(1),
                          decoration: BoxDecoration(
                            color: _cellColor(intensity, primary),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: cs.outlineVariant.withValues(alpha: 0.28),
                              width: 0.5,
                            ),
                          ),
                        ),
                      );
                    }),
                  );
                }),
              ],
            ),
          ],
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: grid,
        );
      },
    );
  }
}
