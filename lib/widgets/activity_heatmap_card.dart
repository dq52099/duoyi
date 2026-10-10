import 'package:flutter/material.dart';

import '../core/heatmap_calendar.dart';
import '../core/heatmap_ui_copy.dart';
import '../core/design_tokens.dart';
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
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.spaceMd,
          DesignTokens.spaceMd,
          DesignTokens.spaceMd,
          DesignTokens.spaceSm,
        ),
        borderRadius: DesignTokens.borderRadiusLg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              copy.activityTitle,
              style: const TextStyle(
                fontSize: DesignTokens.fontSizeBase,
                fontWeight: FontWeight.normal,
              ),
            ),
            const SizedBox(height: DesignTokens.spaceXs),
            Text(
              copy.activitySubtitle,
              style: TextStyle(
                fontSize: DesignTokens.fontSizeCaption,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: DesignTokens.spaceSm),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  copy.activeDays(summary.activeDays),
                  key: const ValueKey('heatmap_active_days'),
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeSecondary,
                    color: cs.primary,
                  ),
                ),
                Text(
                  copy.maximum(summary.maximumLevel),
                  key: const ValueKey('heatmap_maximum_level'),
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeSecondary,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.spaceMd),
            HabitHeatmap(
              heatmapData: heatmapData,
              weeks: weeks,
              today: window.today,
              metric: HeatmapMetric.activity,
              showSummary: false,
            ),
          ],
        ),
      );
    },
  );
}
