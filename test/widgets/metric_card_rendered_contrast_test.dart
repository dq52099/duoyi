import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/stats_overview_cards.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

TextStyle? _spanStyle(
  InlineSpan span,
  String text, [
  TextStyle inherited = const TextStyle(),
]) {
  final style = inherited.merge(span.style);
  if (span is! TextSpan) return null;
  if (span.text == text) return style;
  for (final child in span.children ?? const <InlineSpan>[]) {
    final match = _spanStyle(child, text, style);
    if (match != null) return match;
  }
  return null;
}

void main() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final caller in ['today', 'mine']) {
        final name = '$caller-$brand-${locale.name}';
        testWidgets('metric title and unit contrast on rendered card $name', (
          tester,
        ) async {
          final originalLocale = I18n.current;
          SharedPreferences.setMockInitialValues({'active_brand': brand});
          I18n.setLocale(locale);
          final theme = ThemeProvider();
          final boundary = GlobalKey();
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            theme.dispose();
            tester.view.reset();
            I18n.setLocale(originalLocale);
          });
          await tester.runAsync(() async {
            await theme.loadFromStorage();
            await loadWeeklyReviewScreenshotFonts();
          });
          final title = I18n.tr(
            caller == 'today' ? 'nav.todo' : 'mine.stats.focus',
          );
          final unit = I18n.tr(
            caller == 'today' ? 'today.unit.item' : 'unit.minute',
          );
          await tester.pumpWidget(
            ChangeNotifierProvider<ThemeProvider>.value(
              value: theme,
              child: MaterialApp(
                theme: theme.brand.theme,
                builder: (context, child) =>
                    RepaintBoundary(key: boundary, child: child!),
                home: Scaffold(
                  body: BrandBackground(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: 177,
                          child: caller == 'today'
                              ? AppMetricCard(
                                  title: title,
                                  value: '3',
                                  unit: unit,
                                  icon: Icons.check_circle_outline,
                                  color: theme.brand.theme.colorScheme.primary,
                                  onTap: () {},
                                )
                              : StatsOverviewCard(
                                  title: title,
                                  titleMaxLines: null,
                                  value: '75',
                                  unit: unit,
                                  icon: Icons.timer,
                                  color: const Color(0xFFA23535),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(theme.brand.id, brand);
          final card = find.byType(AppMetricCard);
          final titleParagraph = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.descendant(of: card, matching: find.text(title)),
              matching: find.byType(RichText),
            ),
          );
          final richValue = tester
              .renderObjectList<RenderParagraph>(
                find.descendant(of: card, matching: find.byType(RichText)),
              )
              .singleWhere(
                (paragraph) => paragraph.text.toPlainText().endsWith(unit),
              );
          final unitStyle = _spanStyle(richValue.text, ' $unit')!;
          final foregrounds = {
            'title': titleParagraph.text.style!.color!,
            'unit': unitStyle.foreground?.color ?? unitStyle.color!,
          };
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final cardRect = MatrixUtils.transformRect(
            tester.renderObject<RenderBox>(card).getTransformTo(render),
            Offset.zero & tester.getSize(card),
          );
          final textRect = MatrixUtils.transformRect(
            titleParagraph.getTransformTo(render),
            Offset.zero & titleParagraph.size,
          );
          final capture = await tester.runAsync(() async {
            final picture = await render.toImage();
            try {
              return (
                pixels: (await picture.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!,
                width: picture.width,
                png: await picture.toByteData(format: ui.ImageByteFormat.png),
              );
            } finally {
              picture.dispose();
            }
          });
          final observations = <Map<String, Object>>[];
          for (final y in [cardRect.top + 5, cardRect.bottom - 5]) {
            for (final fraction in [0.25, 0.75]) {
              final point = Offset(
                textRect.left + textRect.width * fraction,
                y,
              );
              expect(textRect.contains(point), isFalse);
              expect(cardRect.contains(point), isTrue);
              final offset =
                  (point.dy.floor() * capture!.width + point.dx.floor()) * 4;
              final bytes = capture.pixels;
              expect(bytes.getUint8(offset + 3), 255);
              final background = Color.fromARGB(
                255,
                bytes.getUint8(offset),
                bytes.getUint8(offset + 1),
                bytes.getUint8(offset + 2),
              );
              for (final foreground in foregrounds.entries) {
                observations.add({
                  'role': foreground.key,
                  'foreground': foreground.value.toARGB32(),
                  'backgroundPixel': background.toARGB32(),
                  'sampleX': point.dx,
                  'sampleY': point.dy,
                  'contrast': appContrastRatio(
                    Color.alphaBlend(foreground.value, background),
                    background,
                  ),
                });
              }
            }
          }
          final measurements =
              Platform.environment['DUOYI_SECONDARY_MEASUREMENTS'];
          if (measurements != null) {
            final file = File('$measurements/metric-$name.json');
            file.parent.createSync(recursive: true);
            file.writeAsStringSync(
              jsonEncode({
                'caller': caller,
                'brand': brand,
                'locale': locale.name,
                'title': title,
                'unit': unit,
                'observations': observations,
              }),
            );
          }
          final screenshots = Platform.environment['DUOYI_METRIC_IMAGES'];
          if (screenshots != null) {
            final file = File('$screenshots/$name.png');
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(capture!.png!.buffer.asUint8List());
          }
          expect(tester.takeException(), isNull);
          for (final observation in observations) {
            expect(
              observation['contrast'] as double,
              greaterThanOrEqualTo(4.5),
              reason: '$name ${observation['role']} on real card pixel',
            );
          }
        });
      }
    }
  }
}
