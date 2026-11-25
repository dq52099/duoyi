import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

void main() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final width in [320.0, 390.0]) {
        final name = '$brand-${platform.name}-${width.toInt()}';
        testWidgets('preview footer labels remain separated $name', (
          tester,
        ) async {
          SharedPreferences.setMockInitialValues({
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
          final rows = <Map<String, Object?>>[];
          final originalShadows = debugDisableShadows;
          try {
            await theme.loadFromStorage();
            expect(theme.activeWidgetBackgroundBrand.id, brand);
            await tester.runAsync(loadWeeklyReviewScreenshotFonts);
            debugDisableShadows = false;
            tester.view.physicalSize = Size(width, 844);
            tester.view.devicePixelRatio = 1;
            I18n.setLocale(AppLocale.zh);
            final prefs = await SharedPreferences.getInstance();
            final initial = {for (final k in prefs.getKeys()) k: prefs.get(k)};
            await tester.pumpWidget(
              ChangeNotifierProvider<ThemeProvider>.value(
                value: theme,
                child: MaterialApp(
                  theme: theme.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(1.6)),
                    child: RepaintBoundary(key: capture, child: child!),
                  ),
                  home: Scaffold(
                    body: ListView(
                      padding: const EdgeInsets.all(28),
                      children: [
                        WidgetPreviewCard.habit(
                          displayMode: WidgetDisplayMode.detailed,
                          platformOverride: platform,
                        ),
                      ],
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
              expect(
                tester.element(find.byType(WidgetPreviewCard)),
                same(retained),
              );
              expect(tester.takeException(), isNull);
              final nav = find.byKey(
                const ValueKey('widget_preview_navigation'),
              );
              // Narrow previews may omit optional navigation when a complete
              // naturally scaled footer cannot fit after the primary content.
              if (locale == AppLocale.zh || width == 390) {
                expect(nav, findsOneWidget);
              }
              final rects = <Rect>[];
              if (nav.evaluate().isNotEmpty) {
                final bounds = tester.getRect(nav);
                for (final label in WidgetUiCopy.previewNavLabels) {
                  final text = find.descendant(
                    of: nav,
                    matching: find.text(label),
                  );
                  expect(text, findsOneWidget);
                  final paragraph = tester.renderObject<RenderParagraph>(
                    find.descendant(of: text, matching: find.byType(RichText)),
                  );
                  final rect = tester.getRect(text);
                  expect(paragraph.didExceedMaxLines, isFalse);
                  expect(
                    paragraph.getMaxIntrinsicWidth(double.infinity),
                    lessThanOrEqualTo(rect.width + .1),
                  );
                  expect(paragraph.text.style!.fontSize, 11);
                  expect(paragraph.text.style!.fontWeight, FontWeight.normal);
                  expect(paragraph.textScaler.scale(11), closeTo(17.6, .001));
                  expect(bounds.inflate(.1).contains(rect.topLeft), isTrue);
                  expect(bounds.inflate(.1).contains(rect.bottomRight), isTrue);
                  rects.add(rect);
                }
              }
              final gaps = <double>[];
              for (var i = 1; i < rects.length; i++) {
                if ((rects[i].top - rects[i - 1].top).abs() < .1) {
                  gaps.add(rects[i].left - rects[i - 1].right);
                } else {
                  expect(
                    rects[i].top - rects[i - 1].bottom,
                    greaterThanOrEqualTo(3.9),
                  );
                }
              }
              rows.add({
                'locale': locale.name,
                'navigationVisible': rects.isNotEmpty,
                'rects': [
                  for (final r in rects) [r.left, r.top, r.width, r.height],
                ],
                'horizontalGaps': gaps,
              });
              final run = Platform.environment['DUOYI_PREVIEW_NAV_RUN'];
              if (run != null) {
                await tester.runAsync(() async {
                  final boundary =
                      capture.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary;
                  final picture = await boundary.toImage(pixelRatio: 1);
                  try {
                    final png = await picture.toByteData(
                      format: ui.ImageByteFormat.png,
                    );
                    final file = File(
                      'evidence/screenshots/widget-preview-navigation-20261020/$run/$name-${locale.name}.png',
                    );
                    await file.parent.create(recursive: true);
                    await file.writeAsBytes(png!.buffer.asUint8List());
                  } finally {
                    picture.dispose();
                  }
                });
              }
              expect({
                for (final k in prefs.getKeys()) k: prefs.get(k),
              }, initial);
            }
            expect(
              rows.every(
                (row) => (row['horizontalGaps']! as List<double>).every(
                  (gap) => gap >= 3.9,
                ),
              ),
              isTrue,
              reason: jsonEncode(rows),
            );
          } finally {
            final run = Platform.environment['DUOYI_PREVIEW_NAV_RUN'];
            if (run != null) {
              await tester.runAsync(() async {
                final file = File(
                  'evidence/widget-preview-navigation-20261020/$run/$name.json',
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
