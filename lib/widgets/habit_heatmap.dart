import 'package:flutter/material.dart';

import '../core/heatmap_calendar.dart';
import '../core/heatmap_ui_copy.dart';
import '../core/i18n.dart';
import '../core/design_tokens.dart';
import 'calendar_heatmap.dart';

class HabitHeatmap extends StatelessWidget {
  /// Normalized 0–5 progress or activity levels; these are never event counts.
  final Map<String, int> heatmapData;
  final int weeks;
  final DateTime? today;
  final HeatmapMetric metric;
  final bool showSummary;

  const HabitHeatmap({
    super.key,
    required this.heatmapData,
    this.weeks = 12,
    this.today,
    this.metric = HeatmapMetric.progress,
    this.showSummary = true,
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
      final summary = window.summarize(heatmapData);
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
        summary: showSummary
            ? Wrap(
                spacing: DesignTokens.spaceMd,
                runSpacing: DesignTokens.spaceXs,
                children: [
                  Text(
                    copy.activeDays(summary.activeDays),
                    style: TextStyle(
                      fontSize: DesignTokens.fontSizeSecondary,
                      color: cs.primary,
                    ),
                  ),
                  Text(
                    copy.maximum(summary.maximumLevel),
                    style: TextStyle(
                      fontSize: DesignTokens.fontSizeSecondary,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              )
            : null,
        emptyLabel: summary.activeDays == 0
            ? (metric == HeatmapMetric.activity
                  ? copy.emptyActivity
                  : copy.emptyProgress)
            : null,
        legend: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  copy.low,
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeCaption,
                    color: cs.onSurfaceVariant,
                  ),
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
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeCaption,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              metric == HeatmapMetric.activity
                  ? copy.activityHint
                  : copy.progressHint,
              style: TextStyle(
                fontSize: DesignTokens.fontSizeCaption,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    },
  );
}
