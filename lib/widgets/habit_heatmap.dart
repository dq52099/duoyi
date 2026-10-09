import 'package:flutter/material.dart';

import '../core/heatmap_calendar.dart';
import '../core/heatmap_ui_copy.dart';
import '../core/i18n.dart';
import 'calendar_heatmap.dart';

class HabitHeatmap extends StatelessWidget {
  /// Normalized 0–5 progress or activity levels; these are never event counts.
  final Map<String, int> heatmapData;
  final int weeks;
  final DateTime? today;
  final HeatmapMetric metric;

  const HabitHeatmap({
    super.key,
    required this.heatmapData,
    this.weeks = 12,
    this.today,
    this.metric = HeatmapMetric.progress,
  });

  static Color levelColor(ColorScheme cs, bool isDark, int level) {
    final background = Color.alphaBlend(
      cs.primary.withValues(alpha: isDark ? 0.08 : 0.055),
      cs.surface,
    );
    if (level == 0) return background;
    return Color.lerp(background, cs.primary, 0.18 + level.clamp(1, 5) * 0.16)!;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLocale>(
    valueListenable: I18n.localeListenable,
    builder: (context, locale, _) {
      final copy = HeatmapUiCopy(locale);
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      final dark = theme.brightness == Brightness.dark;
      final window = HeatmapCalendarWindow(weeks: weeks, today: today);
      return CalendarHeatmap(
        window: window,
        title: copy.metricTitle(metric),
        describeDay: (date) => copy.levelLabel(
          metric,
          HeatmapCalendarWindow.level(
            heatmapData[HeatmapCalendarWindow.dateKey(date)],
          ),
        ),
        colorForDay: (date) => levelColor(
          cs,
          dark,
          HeatmapCalendarWindow.level(
            heatmapData[HeatmapCalendarWindow.dateKey(date)],
          ),
        ),
        legend: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  copy.low,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
                for (var level = 0; level <= 5; level++)
                  Tooltip(
                    message: copy.levelLabel(metric, level),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: levelColor(cs, dark, level),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                Text(
                  copy.high,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              metric == HeatmapMetric.activity
                  ? copy.activityHint
                  : copy.progressHint,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    },
  );
}
