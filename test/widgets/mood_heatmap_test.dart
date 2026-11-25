import 'dart:io';

import 'package:duoyi/core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/widgets/mood_heatmap.dart';
import 'package:duoyi/widgets/surface_components.dart' show appContrastRatio;

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
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

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

    testWidgets('轴标签与分类心情图例取色自 ColorScheme', (tester) async {
      await pumpHeatmap(tester, Brightness.dark);

      final element = tester.element(find.byType(MoodHeatmap));
      final cs = Theme.of(element).colorScheme;

      final weekdayFinder = find.text('一');
      final weekdayElement = tester.element(weekdayFinder);
      final weekdayWidget = tester.widget<Text>(weekdayFinder);

      expect(weekdayWidget.style?.color, cs.onSurfaceVariant);

      // In this fixture, MoodHeatmap is pumped directly in Scaffold without card wrapper;
      // the weekday axis is painted directly over the Scaffold background.
      // Collect ancestor fill layers leaf-to-root, then composite root-to-leaf:
      final layers = <Color>[];
      weekdayElement.visitAncestorElements((ancestor) {
        if (ancestor.widget case Material(:final color?)) {
          layers.add(color);
        } else if (ancestor.widget case DecoratedBox(:final decoration)) {
          if (decoration is BoxDecoration) {
            final color = decoration.color;
            if (color != null) layers.add(color);
          }
        } else if (ancestor.widget case Scaffold(:final backgroundColor)) {
          if (backgroundColor != null) layers.add(backgroundColor);
          return false; // Stop at nearest enclosing Scaffold
        }
        return true;
      });

      Color effectiveBg = Theme.of(weekdayElement).scaffoldBackgroundColor;
      for (final layer in layers.reversed) {
        effectiveBg = Color.alphaBlend(layer, effectiveBg);
      }
      final weekdayFg =
          weekdayWidget.style?.color ??
          DefaultTextStyle.of(weekdayElement).style.color!;
      final effectiveFg = Color.alphaBlend(weekdayFg, effectiveBg);
      final contrast = appContrastRatio(effectiveFg, effectiveBg);
      expect(
        contrast,
        greaterThanOrEqualTo(4.5),
        reason:
            'Weekday label contrast $contrast must be >= 4.5 on $effectiveBg',
      );

      for (final label in ['超棒', '开心', '平静', '郁闷', '糟糕']) {
        final legendLabel = find.text(label);
        expect(legendLabel, findsOneWidget);
        expect(
          tester.widget<Text>(legendLabel).style?.color,
          cs.onSurfaceVariant,
        );
      }

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      for (final label in ['Great', 'Good', 'Calm', 'Low', 'Terrible']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets(
      'no diary, unset mood and named mood have distinct day meanings',
      (tester) async {
        final today = DateTime(2026, 5, 17);
        String key(DateTime date) =>
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        final entries = <String, DiaryEntry>{
          key(DateTime(2026, 5, 16)): DiaryEntry(date: DateTime(2026, 5, 16)),
          key(today): DiaryEntry(date: today, mood: Mood.awesome),
        };

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: Scaffold(
              body: MoodHeatmap(entriesByDate: entries, weeks: 1, today: today),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final noEntry = tester.getSemantics(
          find.byKey(const ValueKey('heatmap_day_2026-05-15')),
        );
        final noMood = tester.getSemantics(
          find.byKey(const ValueKey('heatmap_day_2026-05-16')),
        );
        final hasMood = tester.getSemantics(
          find.byKey(const ValueKey('heatmap_day_2026-05-17')),
        );
        expect(noEntry.label, contains('无日记'));
        expect(noMood.label, contains('未记录心情'));
        expect(hasMood.label, contains('超棒'));

        final element = tester.element(find.byType(MoodHeatmap));
        final cs = Theme.of(element).colorScheme;
        Set<Color> cellDecorationColors(String date) {
          final cell = find.byKey(ValueKey('heatmap_day_$date'));
          final container = find.descendant(
            of: cell,
            matching: find.byType(Container),
          );
          return tester
              .widgetList<Container>(container)
              .map((widget) => widget.decoration)
              .whereType<BoxDecoration>()
              .map((decoration) => decoration.color)
              .whereType<Color>()
              .toSet();
        }

        expect(
          cellDecorationColors('2026-05-15'),
          contains(cs.surfaceContainerHighest.withValues(alpha: 0.22)),
        );
        expect(
          cellDecorationColors('2026-05-16'),
          contains(
            Color.alphaBlend(cs.onSurface.withValues(alpha: 0.16), cs.surface),
          ),
        );
        expect(
          cellDecorationColors('2026-05-17'),
          contains(moodShades[Brightness.light]!.first),
        );
      },
    );

    testWidgets('open diary callback receives the selected calendar date', (
      tester,
    ) async {
      final today = DateTime(2026, 5, 17);
      final selected = <DateTime>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoodHeatmap(
              entriesByDate: {
                '2026-05-17': DiaryEntry(date: today, mood: Mood.good),
              },
              weeks: 1,
              today: today,
              onOpenDay: selected.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('heatmap_day_2026-05-16')));
      await tester.pumpAndSettle();
      expect(find.text('写日记'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('heatmap_open_day')));
      await tester.pumpAndSettle();
      expect(selected, [DateTime(2026, 5, 16)]);

      await tester.tap(find.byKey(const ValueKey('heatmap_day_2026-05-17')));
      await tester.pumpAndSettle();
      expect(find.text('查看日记'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('heatmap_open_day')));
      await tester.pumpAndSettle();
      expect(selected, [DateTime(2026, 5, 16), today]);
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
