import 'package:flutter/material.dart';
import '../core/heatmap_calendar.dart';
import '../core/heatmap_ui_copy.dart';
import '../core/i18n.dart';
import 'calendar_heatmap.dart';
import '../models/diary_entry.dart';

/// 近 N 周心情热图：每格代表一天，颜色由当天日记的心情决定；无日记则中性灰。
class MoodHeatmap extends StatelessWidget {
  final Map<String, DiaryEntry> entriesByDate;
  final int weeks;
  final DateTime? today;
  final ValueChanged<DateTime>? onOpenDay;

  const MoodHeatmap({
    super.key,
    required this.entriesByDate,
    this.weeks = 12,
    this.today,
    this.onOpenDay,
  });

  /// 五档心情语义色：亮色档沿用既有取值；暗色档换用更亮的同色相档，
  /// 避免暗色主题下沿用亮色档的深色值在深背景上发闷、难以分辨。
  Color _moodColor(Mood m, bool isDark) {
    if (!isDark) {
      return switch (m) {
        Mood.awesome => const Color(0xFF2E7D32),
        Mood.good => const Color(0xFF66BB6A),
        Mood.okay => const Color(0xFFFFCA28),
        Mood.bad => const Color(0xFFEF6C00),
        Mood.terrible => const Color(0xFFD32F2F),
      };
    }
    return switch (m) {
      Mood.awesome => const Color(0xFF4CAF50),
      Mood.good => const Color(0xFF81C784),
      // bad 用 orange400 而非 orange300：与 okay(amber300) 色相只差约 10°，
      // 10px 小色块主要靠明度区分，300 档两档明度几乎相同难以分辨。
      Mood.okay => const Color(0xFFFFD54F),
      Mood.bad => const Color(0xFFFFA726),
      Mood.terrible => const Color(0xFFE57373),
    };
  }

  /// 空格取主题中性容器色，跟随亮暗主题，不再固定亮灰刺眼。
  Color _emptyColor(ColorScheme cs, bool isDark) {
    return cs.surfaceContainerHighest.withValues(alpha: isDark ? 0.12 : 0.22);
  }

  Color _colorFor(Mood? m, ColorScheme cs, bool isDark) {
    if (m == null) return _emptyColor(cs, isDark);
    return _moodColor(m, isDark);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLocale>(
    valueListenable: I18n.localeListenable,
    builder: (context, locale, _) {
      final copy = HeatmapUiCopy(locale);
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
      final window = HeatmapCalendarWindow(weeks: weeks, today: today);
      DiaryEntry? entryFor(DateTime day) =>
          entriesByDate[HeatmapCalendarWindow.dateKey(day)];
      String describe(DateTime day) {
        final entry = entryFor(day);
        if (entry == null) return copy.noEntry;
        return entry.mood == null ? copy.noMood : copy.mood(entry.mood!);
      }

      final noMoodColor = Color.alphaBlend(
        cs.onSurface.withValues(alpha: 0.16),
        cs.surface,
      );
      Color colorFor(DateTime day) {
        final entry = entryFor(day);
        return entry == null
            ? _emptyColor(cs, isDark)
            : entry.mood == null
            ? noMoodColor
            : _moodColor(entry.mood!, isDark);
      }

      Widget sample(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.24),
                width: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            copy.moodTitle,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.normal),
          ),
          const SizedBox(height: 6),
          CalendarHeatmap(
            window: window,
            title: copy.moodTitle,
            describeDay: describe,
            colorForDay: colorFor,
            onOpenDay: onOpenDay,
            openDayLabel: (day) =>
                entryFor(day) == null ? copy.writeDiary : copy.openDiary,
            legend: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    sample(_emptyColor(cs, isDark), copy.noEntry),
                    sample(noMoodColor, copy.noMood),
                    for (final mood in Mood.values)
                      sample(_colorFor(mood, cs, isDark), copy.mood(mood)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  copy.moodHint,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
