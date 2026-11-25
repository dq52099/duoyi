import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

Widget _preview(
  WidgetPreviewKind kind,
  WidgetDisplayMode mode,
  TargetPlatform platform,
) => switch (kind) {
  WidgetPreviewKind.todo => WidgetPreviewCard.todo(
    displayMode: mode,
    platformOverride: platform,
  ),
  WidgetPreviewKind.focus => WidgetPreviewCard.focus(
    displayMode: mode,
    platformOverride: platform,
  ),
  WidgetPreviewKind.habit => WidgetPreviewCard.habit(
    displayMode: mode,
    platformOverride: platform,
  ),
  WidgetPreviewKind.calendar => WidgetPreviewCard.calendar(
    displayMode: mode,
    platformOverride: platform,
  ),
  WidgetPreviewKind.schedule => WidgetPreviewCard.schedule(
    displayMode: mode,
    platformOverride: platform,
  ),
  WidgetPreviewKind.goal => WidgetPreviewCard.goal(
    displayMode: mode,
    platformOverride: platform,
  ),
  WidgetPreviewKind.course => WidgetPreviewCard.course(
    displayMode: mode,
    platformOverride: platform,
  ),
  WidgetPreviewKind.note => WidgetPreviewCard.note(
    displayMode: mode,
    platformOverride: platform,
  ),
  WidgetPreviewKind.anniversary => WidgetPreviewCard.anniversary(
    displayMode: mode,
    platformOverride: platform,
  ),
  WidgetPreviewKind.diary => WidgetPreviewCard.diary(
    displayMode: mode,
    platformOverride: platform,
  ),
};

List<String> _metricValues(WidgetPreviewKind kind) => switch (kind) {
  WidgetPreviewKind.todo => [WidgetUiCopy.todoItem1],
  WidgetPreviewKind.focus => const ['2', '50', '25'],
  WidgetPreviewKind.habit => const ['80%'],
  WidgetPreviewKind.calendar => const ['17'],
  WidgetPreviewKind.schedule => [WidgetUiCopy.scheduleItem1],
  WidgetPreviewKind.goal => [WidgetUiCopy.goalItem1],
  WidgetPreviewKind.course => [WidgetUiCopy.courseItem1],
  WidgetPreviewKind.note => [WidgetUiCopy.noteItem1],
  WidgetPreviewKind.anniversary => [WidgetUiCopy.anniversaryItem1],
  WidgetPreviewKind.diary => [WidgetUiCopy.diaryItem1],
};

void main() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final mode in WidgetDisplayMode.values) {
        for (final narrow in [false, true]) {
          final name =
              '$brand-${platform.name}-${mode.name}-${narrow ? 'narrow' : 'ordinary'}';
          testWidgets('preview metric contrast $name', (tester) async {
            // Deliberately use the other app brand: previews must honor the
            // independently selected widget palette, not the surrounding app.
            SharedPreferences.setMockInitialValues({
              'active_brand': brand == 'defaultBrand'
                  ? 'liquidGlass'
                  : 'defaultBrand',
              'theme_shop_state': jsonEncode({
                'activeBrand': brand == 'defaultBrand'
                    ? 'liquidGlass'
                    : 'defaultBrand',
                'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
                'activeWidgetBackgroundId': brand,
              }),
            });
            final theme = ThemeProvider();
            final capture = GlobalKey();
            final originalShadows = debugDisableShadows;
            final rows = <Map<String, Object?>>[];
            try {
              await theme.loadFromStorage();
              expect(theme.activeWidgetBackgroundBrand.id, brand);
              await tester.runAsync(loadWeeklyReviewScreenshotFonts);
              debugDisableShadows = false;
              tester.view.physicalSize = Size(narrow ? 320 : 390, 844);
              tester.view.devicePixelRatio = 1;
              final prefs = await SharedPreferences.getInstance();
              final initial = {
                for (final key in prefs.getKeys()) key: prefs.get(key),
              };
              for (final kind in WidgetPreviewKind.values) {
                I18n.setLocale(AppLocale.zh);
                final preview = _preview(kind, mode, platform);
                await tester.pumpWidget(
                  ChangeNotifierProvider<ThemeProvider>.value(
                    value: theme,
                    child: MaterialApp(
                      theme: theme.brand.theme,
                      builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          textScaler: TextScaler.linear(narrow ? 1.6 : 1),
                        ),
                        child: RepaintBoundary(key: capture, child: child!),
                      ),
                      home: Scaffold(
                        body: ListView(
                          padding: const EdgeInsets.all(28),
                          children: [preview],
                        ),
                      ),
                    ),
                  ),
                );
                await tester.pumpAndSettle();
                final retained = tester.element(find.byType(WidgetPreviewCard));
                for (final locale in [AppLocale.zh, AppLocale.en]) {
                  I18n.setLocale(locale);
                  await tester.pumpAndSettle();
                  final surface = find.byKey(
                    const ValueKey('widget_preview_surface'),
                  );
                  final paragraphs = find.descendant(
                    of: surface,
                    matching: find.byType(Text),
                  );
                  final values = paragraphs.evaluate().where((element) {
                    final text = element.widget as Text;
                    return _metricValues(kind).contains(text.data);
                  }).toList();
                  if (kind != WidgetPreviewKind.habit ||
                      mode == WidgetDisplayMode.detailed && !narrow) {
                    expect(
                      values,
                      isNotEmpty,
                      reason:
                          '$brand/$platform/$mode/$kind/$locale must expose a measured content value',
                    );
                  }
                  final render =
                      capture.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary;
                  Rect inImage(RenderBox box) => MatrixUtils.transformRect(
                    box.getTransformTo(render),
                    Offset.zero & box.size,
                  );
                  final surfaceRect = inImage(
                    tester.renderObject<RenderBox>(surface),
                  );
                  final allTextRects = paragraphs
                      .evaluate()
                      .map(
                        (element) => inImage(
                          tester.renderObject<RenderParagraph>(
                            find.descendant(
                              of: find.byWidget(element.widget),
                              matching: find.byType(RichText),
                            ),
                          ),
                        ),
                      )
                      .toList();
                  final pixels = (await tester.runAsync(() async {
                    final picture = await render.toImage(pixelRatio: 1);
                    try {
                      if (narrow &&
                          Platform.environment['DUOYI_CAPTURE_PREVIEW_METRICS'] ==
                              '1') {
                        final png = await picture.toByteData(
                          format: ui.ImageByteFormat.png,
                        );
                        final run =
                            Platform.environment['DUOYI_PREVIEW_METRICS_RUN'] ??
                            'current';
                        final file = File(
                          'evidence/screenshots/widget-preview-metrics-20261020/$run/$name-${kind.name}-${locale.name}.png',
                        );
                        await file.parent.create(recursive: true);
                        await file.writeAsBytes(png!.buffer.asUint8List());
                      }
                      return (
                        data: (await picture.toByteData(
                          format: ui.ImageByteFormat.rawRgba,
                        ))!,
                        width: picture.width,
                        height: picture.height,
                      );
                    } finally {
                      picture.dispose();
                    }
                  }))!;
                  final nav = find.byKey(
                    const ValueKey('widget_preview_navigation'),
                  );
                  if (nav.evaluate().isNotEmpty) {
                    final payload = HomeWidgetThemePayload.fromThemeProvider(
                      theme,
                    );
                    final navBackground = Color.alphaBlend(
                      payload.navBackground,
                      payload.background,
                    );
                    for (final label in WidgetUiCopy.previewNavLabels) {
                      final labelFinder = find.descendant(
                        of: nav,
                        matching: find.text(label),
                      );
                      expect(labelFinder, findsOneWidget);
                      final paragraph = tester.renderObject<RenderParagraph>(
                        find.descendant(
                          of: labelFinder,
                          matching: find.byType(RichText),
                        ),
                      );
                      final foreground = paragraph.text.style!.color!;
                      expect(
                        appContrastRatio(navBackground, foreground),
                        greaterThanOrEqualTo(4.5),
                        reason:
                            '$brand/$platform/$mode/$kind/$locale nav label $label',
                      );
                    }
                  }
                  final metrics = <Map<String, Object?>>[];
                  for (final element in values) {
                    final text = find.byWidget(element.widget);
                    final paragraph = tester.renderObject<RenderParagraph>(
                      find.descendant(
                        of: text,
                        matching: find.byType(RichText),
                      ),
                    );
                    final rect = inImage(paragraph);
                    expect(
                      surfaceRect.contains(rect.topLeft) &&
                          surfaceRect.contains(
                            rect.bottomRight - const Offset(.01, .01),
                          ),
                      isTrue,
                    );
                    final foreground =
                        paragraph.text.style?.foreground?.color ??
                        paragraph.text.style!.color!;
                    final candidates = <Offset>[];
                    if (kind == WidgetPreviewKind.calendar) {
                      // Use the selected date's own solid fill, not root padding.
                      final cell = find
                          .ancestor(
                            of: text,
                            matching: find.byType(DecoratedBox),
                          )
                          .first;
                      final cellRect = inImage(
                        tester.renderObject<RenderBox>(cell),
                      );
                      for (final fraction in [.4, .6]) {
                        candidates.add(
                          Offset(
                            cellRect.left + cellRect.width * fraction,
                            (cellRect.top + rect.top) / 2,
                          ),
                        );
                        candidates.add(
                          Offset(
                            cellRect.left + cellRect.width * fraction,
                            (rect.bottom + cellRect.bottom) / 2,
                          ),
                        );
                      }
                    } else {
                      candidates.addAll(
                        [
                          Offset(rect.center.dx, rect.top - 3),
                          Offset(rect.center.dx, rect.bottom + 3),
                          Offset(rect.left - 3, rect.center.dy),
                          Offset(rect.right + 3, rect.center.dy),
                        ].where(
                          (point) =>
                              surfaceRect.deflate(2).contains(point) &&
                              !allTextRects.any(
                                (other) => other.contains(point),
                              ),
                        ),
                      );
                    }
                    expect(candidates.length, greaterThanOrEqualTo(2));
                    final samples = <Map<String, Object>>[];
                    for (final point in candidates) {
                      expect(rect.contains(point), isFalse);
                      final x = point.dx.floor();
                      final y = point.dy.floor();
                      expect(x, inInclusiveRange(0, pixels.width - 1));
                      expect(y, inInclusiveRange(0, pixels.height - 1));
                      final index = (y * pixels.width + x) * 4;
                      expect(pixels.data.getUint8(index + 3), 255);
                      final background = Color.fromARGB(
                        255,
                        pixels.data.getUint8(index),
                        pixels.data.getUint8(index + 1),
                        pixels.data.getUint8(index + 2),
                      );
                      samples.add({
                        'x': x,
                        'y': y,
                        'background': background.toARGB32(),
                        'contrast': appContrastRatio(
                          Color.alphaBlend(foreground, background),
                          background,
                        ),
                      });
                    }
                    metrics.add({
                      'value': (element.widget as Text).data,
                      'foreground': foreground.toARGB32(),
                      'fontSize': paragraph.text.style!.fontSize,
                      'scaledFontSize': paragraph.textScaler.scale(
                        paragraph.text.style!.fontSize!,
                      ),
                      'fontWeight': paragraph.text.style!.fontWeight.toString(),
                      'rect': [rect.left, rect.top, rect.width, rect.height],
                      'samples': samples,
                      'readable': samples.every(
                        (sample) => (sample['contrast']! as double) >= 4.5,
                      ),
                    });
                  }
                  rows.add({
                    'kind': kind.name,
                    'locale': locale.name,
                    'renderedValues': metrics,
                  });
                  expect(
                    tester.element(find.byType(WidgetPreviewCard)),
                    same(retained),
                  );
                  expect(tester.takeException(), isNull);
                  expect({
                    for (final key in prefs.getKeys()) key: prefs.get(key),
                  }, initial);
                }
              }
              expect(
                rows.every(
                  (row) => (row['renderedValues']! as List).every(
                    (metric) => metric['readable'] == true,
                  ),
                ),
                isTrue,
                reason: jsonEncode(rows),
              );
            } finally {
              final run = Platform.environment['DUOYI_PREVIEW_METRICS_RUN'];
              if (run != null) {
                await tester.runAsync(() async {
                  final file = File(
                    'evidence/widget-preview-metric-contrast-20261020/$run/$name.json',
                  );
                  await file.parent.create(recursive: true);
                  await file.writeAsString(jsonEncode(rows));
                });
              }
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pumpAndSettle();
              theme.dispose();
              tester.view.reset();
              debugDisableShadows = originalShadows;
              I18n.setLocale(AppLocale.zh);
            }
          });
        }
      }
    }
  }
}
