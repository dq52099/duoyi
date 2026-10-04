import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/widgets/mood_heatmap.dart';

/// 空格子不再固定亮灰 #EDEDED，需跟随亮/暗主题取色（仿 habit_heatmap 范式）。
const Color bannedLegacyEmpty = Color(0xFFEDEDED);

const Map<Brightness, List<Color>> moodShades = {
  Brightness.light: [
    Color(0xFF2E7D32), // awesome
    Color(0xFF66BB6A), // good
    Color(0xFFFFCA28), // okay
    Color(0xFFEF6C00), // bad
    Color(0xFFD32F2F), // terrible
  ],
  Brightness.dark: [
    Color(0xFF4CAF50),
    Color(0xFF81C784),
    Color(0xFFFFD54F),
    Color(0xFFFFA726), // bad 用 orange400：与 okay 色相仅差约 10°，需靠明度拉开
    Color(0xFFE57373),
  ],
};

Future<void> pumpHeatmap(WidgetTester tester, Brightness brightness) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness, useMaterial3: true),
      home: const Scaffold(body: MoodHeatmap(entriesByDate: {})),
    ),
  );
  await tester.pump();
}

/// 收集所有带实色装饰的 Container（网格空格 + 图例色块）的颜色集合。
Set<Color> paintedDecorationColors(WidgetTester tester) {
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

void main() {
  group('MoodHeatmap 暗色适配', () {
    testWidgets('亮色主题：空格为中性容器色，图例含五档语义色', (tester) async {
      await pumpHeatmap(tester, Brightness.light);

      final element = tester.element(find.byType(MoodHeatmap));
      final cs = Theme.of(element).colorScheme;
      final colors = paintedDecorationColors(tester);

      final empty = cs.surfaceContainerHighest.withValues(alpha: 0.22);
      expect(colors, contains(empty), reason: '空格应取主题中性容器色');
      expect(colors, isNot(contains(bannedLegacyEmpty)));
      for (final shade in moodShades[Brightness.light]!) {
        expect(colors, contains(shade), reason: '图例应包含亮色档 $shade');
      }
    });

    testWidgets('暗色主题：空格降不透明度不再刺眼，五档切换为暗色档', (tester) async {
      await pumpHeatmap(tester, Brightness.dark);

      final element = tester.element(find.byType(MoodHeatmap));
      final cs = Theme.of(element).colorScheme;
      final colors = paintedDecorationColors(tester);

      final empty = cs.surfaceContainerHighest.withValues(alpha: 0.12);
      expect(colors, contains(empty), reason: '暗色空格应为低不透明度容器色');
      expect(colors, isNot(contains(bannedLegacyEmpty)));
      for (final shade in moodShades[Brightness.dark]!) {
        expect(colors, contains(shade), reason: '图例应包含暗色档 $shade');
      }
      // 亮色档（深语义色）不得再出现在暗色主题下。
      for (final shade in moodShades[Brightness.light]!) {
        expect(colors, isNot(contains(shade)), reason: '暗色下不应残留亮色档 $shade');
      }
    });

    testWidgets('轴标签与图例文字取色自 ColorScheme，而非固定 Colors.grey', (tester) async {
      await pumpHeatmap(tester, Brightness.dark);

      final element = tester.element(find.byType(MoodHeatmap));
      final cs = Theme.of(element).colorScheme;

      expect(
        tester.widget<Text>(find.text('一')).style?.color,
        cs.onSurface.withValues(alpha: 0.45),
      );
      expect(
        tester.widget<Text>(find.text('少')).style?.color,
        cs.onSurface.withValues(alpha: 0.55),
      );
      expect(
        tester.widget<Text>(find.text('多')).style?.color,
        cs.onSurface.withValues(alpha: 0.55),
      );
    });

    testWidgets('带心情的格子按暗色档渲染，无记录日期用空格色', (tester) async {
      final today = DateTime.now();
      final yesterday = DateTime(
        today.year,
        today.month,
        today.day,
      ).subtract(const Duration(days: 1));
      final key =
          '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: Scaffold(
            body: MoodHeatmap(
              entriesByDate: {
                key: DiaryEntry(date: yesterday, mood: Mood.awesome),
              },
            ),
          ),
        ),
      );
      await tester.pump();

      final colors = paintedDecorationColors(tester);
      expect(colors, contains(moodShades[Brightness.dark]!.first));
      expect(
        colors,
        isNot(contains(moodShades[Brightness.light]!.first)),
        reason: '暗色下 awesome 格子应用暗色档而非亮色档',
      );
    });

    test('mood_heatmap.dart 源码守卫：固定亮灰与 Colors.grey 清零，保留暗色分支', () {
      final source = File('lib/widgets/mood_heatmap.dart').readAsStringSync();
      expect(source, isNot(contains('0xFFEDEDED')));
      expect(source, isNot(contains('Colors.grey')));
      expect(source, contains('Brightness.dark'));
      expect(source, contains('surfaceContainerHighest.withValues'));
    });

    test('暗色档相邻两档（okay/bad）保持可分辨的明度差', () {
      // 10px 小色块主要靠明度区分：okay(amber300) 与 bad 色相仅差约 10°，
      // bad 曾用 orange300 与 okay 明度几乎相同（WCAG 亮度差 0.138），
      // 改用 orange400 后差值 ≥0.18。
      final shades = moodShades[Brightness.dark]!;
      final okay = shades[2].computeLuminance();
      final bad = shades[3].computeLuminance();
      expect(
        (okay - bad).abs(),
        greaterThan(0.18),
        reason: '暗色档 okay/bad 明度过近，小色块下难以分辨「一般」与「差」',
      );
    });
  });
}
