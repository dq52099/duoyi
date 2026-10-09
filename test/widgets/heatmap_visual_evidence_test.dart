import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/heatmap_calendar.dart';
import 'package:duoyi/core/heatmap_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/widgets/activity_heatmap_card.dart';
import 'package:duoyi/widgets/habit_heatmap.dart';
import 'package:duoyi/widgets/mood_heatmap.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/widget_polish_screenshot_font.dart';

void main() {
  final today = DateTime(2026, 10, 9);
  final data = <String, int>{
    for (var day = 0; day < 364; day++)
      HeatmapCalendarWindow.dateKey(
        HeatmapCalendarWindow.shiftDay(today, -day),
      ): day % 9 == 0
          ? 0
          : day % 6,
  };
  final entries = <String, DiaryEntry>{
    for (var day = 0; day < 84; day++)
      if (day % 3 != 1)
        HeatmapCalendarWindow.dateKey(
          HeatmapCalendarWindow.shiftDay(today, -day),
        ): DiaryEntry(
          id: 'synthetic-$day',
          date: HeatmapCalendarWindow.shiftDay(today, -day),
          mood: day % 8 == 0 ? null : Mood.values[day % 5],
        ),
  };

  for (final scenario in const [
    (width: 390.0, scale: 1.0, locale: AppLocale.zh, dark: false),
    (width: 390.0, scale: 1.0, locale: AppLocale.en, dark: true),
    (width: 320.0, scale: 2.0, locale: AppLocale.en, dark: true),
  ]) {
    for (final kind in ['habit', 'activity', 'mood']) {
      testWidgets('heatmap visual layout $kind / $scenario', (tester) async {
        final capture =
            Platform.environment['DUOYI_CAPTURE_HEATMAP_SCREENSHOT'] == '1';
        if (capture) await tester.runAsync(loadWidgetPolishScreenshotFonts);
        I18n.setLocale(scenario.locale);
        addTearDown(() => I18n.setLocale(AppLocale.zh));
        await tester.binding.setSurfaceSize(Size(scenario.width, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final key = GlobalKey();
        final scheme = ColorScheme.fromSeed(
          seedColor: const Color(0xFF397CEB),
          brightness: scenario.dark ? Brightness.dark : Brightness.light,
        );
        final screenshotTheme = widgetPolishScreenshotTheme();
        final theme = screenshotTheme.copyWith(
          colorScheme: scheme,
          scaffoldBackgroundColor: scheme.surface,
          // A new ColorScheme alone leaves the light fixture's inherited
          // text/icon colors intact. Match the rendered scheme's foregrounds.
          textTheme: screenshotTheme.textTheme.apply(
            bodyColor: scheme.onSurface,
            displayColor: scheme.onSurface,
          ),
          iconTheme: screenshotTheme.iconTheme.copyWith(color: scheme.onSurface),
        );
        final child = switch (kind) {
          'activity' => ActivityHeatmapCard(heatmapData: data, today: today),
          'mood' => AppSurfaceCard(
            padding: const EdgeInsets.all(14),
            child: MoodHeatmap(
              entriesByDate: entries,
              today: today,
              onOpenDay: (_) {},
            ),
          ),
          _ => AppSurfaceCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  HeatmapUiCopy(
                    scenario.locale,
                  ).metricTitle(HeatmapMetric.progress),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                HabitHeatmap(heatmapData: data, today: today),
              ],
            ),
          ),
        };
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(scenario.scale),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: RepaintBoundary(
                    key: key,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (capture) {
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final picture = await boundary.toImage(pixelRatio: 2);
            final bytes = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'evidence/screenshots/heatmaps-20261009/$kind-${scenario.locale.name}-${scenario.width.toInt()}-${scenario.scale}-${scenario.dark ? 'dark' : 'light'}.png',
            );
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(bytes!.buffer.asUint8List());
            picture.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
