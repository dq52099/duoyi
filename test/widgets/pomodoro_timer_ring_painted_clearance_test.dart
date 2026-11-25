import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/main_ui_copy.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/pomodoro_timer_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import '../support/priority_theme_fixture.dart';

Future<(Uint8List, int)> _pixels(
  WidgetTester tester,
  GlobalKey key, {
  String? imagePath,
}) async {
  return (await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      if (imagePath != null) {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(imagePath);
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(png!.buffer.asUint8List());
      }
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (data!.buffer.asUint8List(), image.width);
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final scale in [1.0, 2.0]) {
        final name = '$brand-${locale.name}-$scale';
        testWidgets('percentage glyphs clear painted progress stroke $name', (
          tester,
        ) async {
          final auth = AuthProvider(
            client: ApiClient(
              baseUrl: 'https://duoyi.test',
              httpClient: MockClient(
                (_) async => fail('No fixture HTTP allowed'),
              ),
            ),
          );
          late Color progressColor;
          final boundary = await mountPriorityFixture(
            tester,
            auth: auth,
            brand: brand,
            locale: locale,
            size: const Size(390, 844),
            scale: scale,
            home: BrandRouteSurface(
              remountOnLocaleChange: false,
              child: Scaffold(
                body: Center(
                  child: Builder(
                    builder: (context) {
                      progressColor = Theme.of(context).colorScheme.primary;
                      return PomodoroTimerRing(
                        progress: 0.5,
                        timeText: '12:30',
                        color: progressColor,
                        size: 172,
                      );
                    },
                  ),
                ),
              ),
            ),
          );
          final layoutError = tester.takeException();
          final images = Platform.environment['DUOYI_TIMER_RING_IMAGES'];
          await _pixels(
            tester,
            boundary,
            imagePath: images == null ? null : '$images/$name.png',
          );
          final label = find.text(MainUiCopy.pomodoroRemainingPercent(50));
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: label, matching: find.byType(RichText)),
          );
          final original = paragraph.text as TextSpan;
          // Change only paint color to recover the exact glyph mask. Font,
          // shaping, layout, scaler, ring and all other pixels stay unchanged.
          paragraph.text = TextSpan(
            text: original.text,
            style: original.style!.copyWith(color: const Color(0xffff00ff)),
            children: original.children,
          );
          await tester.pump();
          final (mask, imageWidth) = await _pixels(tester, boundary);
          paragraph.text = TextSpan(
            text: original.text,
            style: original.style!.copyWith(color: Colors.transparent),
            children: original.children,
          );
          await tester.pump();
          final (underlying, _) = await _pixels(tester, boundary);
          paragraph.text = original;
          await tester.pump();

          final color = progressColor.toARGB32();
          final red = (color >> 16) & 255;
          final green = (color >> 8) & 255;
          final blue = color & 255;
          var glyphPixels = 0;
          final intersections = <Map<String, int>>[];
          for (var i = 0; i < mask.length; i += 4) {
            if (mask[i] < 245 || mask[i + 1] > 10 || mask[i + 2] < 245) {
              continue;
            }
            glyphPixels++;
            if ((underlying[i] - red).abs() <= 5 &&
                (underlying[i + 1] - green).abs() <= 5 &&
                (underlying[i + 2] - blue).abs() <= 5) {
              intersections.add({
                'x': (i ~/ 4) % imageWidth,
                'y': (i ~/ 4) ~/ imageWidth,
              });
            }
          }
          final directory =
              Platform.environment['DUOYI_SECONDARY_MEASUREMENTS'];
          if (directory != null) {
            final file = File('$directory/timer-ring-$name.json');
            file.parent.createSync(recursive: true);
            file.writeAsStringSync(
              jsonEncode({
                'layoutError': layoutError?.toString(),
                'glyphPixels': glyphPixels,
                'paintedProgressIntersections': intersections.length,
                'sampleIntersections': intersections.take(10).toList(),
                'progressColor': color,
                'label': original.toPlainText(),
                'scope':
                    'actual glyphs over painted active stroke;track-only overlap not counted',
              }),
            );
          }
          expect(layoutError, isNull);
          expect(
            glyphPixels,
            greaterThan(30),
            reason: 'Glyph mask must be nonempty',
          );
          expect(
            intersections,
            isEmpty,
            reason: 'Percentage glyphs cover the active progress stroke',
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final mode in [
        (name: 'compact', size: 148.0, progress: 0.5, countUp: false),
        (name: 'tight', size: 126.0, progress: 0.5, countUp: false),
        (name: 'countUp', size: 172.0, progress: 0.5, countUp: true),
        (name: 'zero', size: 172.0, progress: 0.0, countUp: false),
      ]) {
        final name = 'mode-$brand-${locale.name}-${mode.name}';
        testWidgets('unchanged timer modes $name', (tester) async {
          final auth = AuthProvider(
            client: ApiClient(
              baseUrl: 'https://duoyi.test',
              httpClient: MockClient(
                (_) async => fail('No fixture HTTP allowed'),
              ),
            ),
          );
          final boundary = await mountPriorityFixture(
            tester,
            auth: auth,
            brand: brand,
            locale: locale,
            size: const Size(390, 844),
            scale: 2,
            home: BrandRouteSurface(
              remountOnLocaleChange: false,
              child: Scaffold(
                body: Center(
                  child: Builder(
                    builder: (context) => PomodoroTimerRing(
                      progress: mode.progress,
                      timeText: '12:30',
                      color: Theme.of(context).colorScheme.primary,
                      size: mode.size,
                      countUp: mode.countUp,
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(find.text('12:30'), findsOneWidget);
          expect(
            find.text(MainUiCopy.pomodoroRemainingPercent(50)),
            findsNothing,
          );
          expect(
            find.text(MainUiCopy.pomodoroRemainingPercent(0)),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
          final images = Platform.environment['DUOYI_TIMER_RING_IMAGES'];
          await _pixels(
            tester,
            boundary,
            imagePath: images == null ? null : '$images/$name.png',
          );
        });
      }
    }
  }
}
