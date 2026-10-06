import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/widgets/mood_heatmap.dart';

/// 三套暗色品牌主题（星穹铁道 / 绝区零 / 希卡之石）下，
/// 心情热力图空格与五档心情色、心情统计弹窗行取色必须随主题。
/// 验证截图：evidence/screenshots/mood-dark-theme/。
const Color bannedLegacyEmpty = Color(0xFFEDEDED);

const List<Color> darkMoodShades = [
  Color(0xFF4CAF50), // awesome
  Color(0xFF81C784), // good
  Color(0xFFFFD54F), // okay
  Color(0xFFFFA726), // bad（orange400，与 okay 保持明度差）
  Color(0xFFE57373), // terrible
];

Set<Color> _paintedDecorationColors(WidgetTester tester) {
  return tester
      .widgetList<Container>(find.byType(Container))
      .map((c) {
        final d = c.decoration;
        if (d is BoxDecoration) return d.color;
        return null;
      })
      .whereType<Color>()
      .toSet();
}

/// 与 diary_screen._showMoodStats 一致的弹窗行取色结构。
class _MoodStatsRowSample extends StatelessWidget {
  const _MoodStatsRowSample();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('MoodStats', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final pct in const [0.9, 0.6, 0.35, 0.15, 0.05])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                const SizedBox(
                  width: 52,
                  child: Text('x', style: TextStyle(fontSize: 13)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 10,
                      backgroundColor: cs.surfaceContainerHighest.withValues(
                        alpha: isDark ? 0.12 : 0.22,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${(pct * 100).round()}',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

void main() {
  for (final brand in [AppBrands.starRail, AppBrands.zzz, AppBrands.botw]) {
    testWidgets('${brand.name}（暗色）：热力图与统计行随主题取色', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final today = DateTime.now();
      final base = DateTime(today.year, today.month, today.day);
      String keyOf(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final entries = <String, DiaryEntry>{
        for (final pair in <(int, Mood)>[
          (0, Mood.awesome),
          (1, Mood.good),
          (2, Mood.okay),
          (3, Mood.bad),
          (4, Mood.terrible),
        ])
          keyOf(base.subtract(Duration(days: pair.$1))): DiaryEntry(
            date: base.subtract(Duration(days: pair.$1)),
            content: 'sample',
            mood: pair.$2,
          ),
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: brand.theme,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${brand.name} · MoodHeatmap',
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  MoodHeatmap(entriesByDate: entries),
                  const SizedBox(height: 24),
                  const _MoodStatsRowSample(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final element = tester.element(find.byType(MoodHeatmap));
      final cs = Theme.of(element).colorScheme;
      expect(Theme.of(element).brightness, Brightness.dark);

      final colors = _paintedDecorationColors(tester);
      final empty = cs.surfaceContainerHighest.withValues(alpha: 0.12);
      expect(colors, contains(empty), reason: '${brand.name} 空格应为低透明度容器色');
      expect(colors, isNot(contains(bannedLegacyEmpty)));
      for (final shade in darkMoodShades) {
        expect(colors, contains(shade), reason: '${brand.name} 图例应含暗色档 $shade');
      }

      final sheetContext = tester.element(find.text('MoodStats'));
      final sheetCs = Theme.of(sheetContext).colorScheme;
      final track = sheetCs.surfaceContainerHighest.withValues(alpha: 0.12);
      expect(
        tester
            .widgetList<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .every((bar) => bar.backgroundColor == track),
        isTrue,
        reason: '${brand.name} 统计行进度条轨道应为主题容器色',
      );
    });
  }
}
