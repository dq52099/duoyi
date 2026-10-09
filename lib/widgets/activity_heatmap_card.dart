import 'package:flutter/material.dart';

import '../core/heatmap_calendar.dart';
import '../core/heatmap_ui_copy.dart';
import '../core/i18n.dart';
import 'habit_heatmap.dart';
import 'surface_components.dart';

class ActivityHeatmapCard extends StatelessWidget {
  static const int weeks = 52;
  final Map<String, int> heatmapData;
  final DateTime? today;

  const ActivityHeatmapCard({super.key, required this.heatmapData, this.today});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLocale>(
    valueListenable: I18n.localeListenable,
    builder: (context, locale, _) {
      final copy = HeatmapUiCopy(locale);
      final cs = Theme.of(context).colorScheme;
      final window = HeatmapCalendarWindow(weeks: weeks, today: today);
      final summary = window.summarize(heatmapData);
      return AppSurfaceCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              copy.activityTitle,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.normal,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              copy.activitySubtitle,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  copy.activeDays(summary.activeDays),
                  key: const ValueKey('heatmap_active_days'),
                  style: TextStyle(fontSize: 12, color: cs.primary),
                ),
                Text(
                  copy.maximum(summary.maximumLevel),
                  key: const ValueKey('heatmap_maximum_level'),
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 10),
            HabitHeatmap(
              heatmapData: heatmapData,
              weeks: weeks,
              today: window.today,
              metric: HeatmapMetric.activity,
            ),
          ],
        ),
      );
    },
  );
}
