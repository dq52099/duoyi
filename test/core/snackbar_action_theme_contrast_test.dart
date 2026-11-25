import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/weekly_review_screenshot_font.dart';

double _ratio(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
}

void main() {
  for (final brand in AppBrands.all) {
    testWidgets('Snackbar action is readable and actionable for ${brand.id}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(loadWeeklyReviewScreenshotFonts);
      final boundary = GlobalKey();
      final messenger = GlobalKey<ScaffoldMessengerState>();
      var calls = 0;
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: brand.theme,
            scaffoldMessengerKey: messenger,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: const Scaffold(body: SizedBox.expand()),
          ),
        ),
      );
      messenger.currentState!.showSnackBar(
        SnackBar(
          content: const Text('Please retry.'),
          duration: const Duration(minutes: 1),
          action: SnackBarAction(label: 'Retry', onPressed: () => calls++),
        ),
      );
      await tester.pumpAndSettle();
      final snack = find.byType(SnackBar);
      final action = find.byType(SnackBarAction);
      expect(snack, findsOneWidget);
      expect(action.hitTestable(), findsOneWidget);
      final label = find.descendant(of: action, matching: find.text('Retry'));
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: label, matching: find.byType(RichText)),
      );
      final foreground = paragraph.text.style!.color!;
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(
        paragraph.textSize.width,
        lessThanOrEqualTo(paragraph.size.width + .1),
      );
      expect(
        paragraph.textSize.height,
        lessThanOrEqualTo(paragraph.size.height + .1),
      );
      final surface = find
          .descendant(of: snack, matching: find.byType(Material))
          .first;
      final rect = tester.getRect(surface);
      final materialFill = tester.widget<Material>(surface).color!;
      final image = await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        return render.toImage(pixelRatio: 1);
      });
      expect(image, isNotNull);
      try {
        final rgba = await tester.runAsync(
          () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        final samples = <Map<String, Object>>[];
        for (final point in [
          Offset(rect.left + 4, rect.center.dy),
          Offset(rect.right - 4, rect.center.dy),
        ]) {
          final offset =
              (point.dy.floor() * image!.width + point.dx.floor()) * 4;
          final background = Color.fromARGB(
            rgba!.getUint8(offset + 3),
            rgba.getUint8(offset),
            rgba.getUint8(offset + 1),
            rgba.getUint8(offset + 2),
          );
          final contrast = _ratio(
            Color.alphaBlend(foreground, background),
            background,
          );
          samples.add({
            'x': point.dx,
            'y': point.dy,
            'foreground': foreground
                .toARGB32()
                .toRadixString(16)
                .padLeft(8, '0'),
            'background': background
                .toARGB32()
                .toRadixString(16)
                .padLeft(8, '0'),
            'ratio': contrast,
          });
        }
        final directory =
            Platform.environment['DUOYI_SNACKBAR_ACTION_EVIDENCE_DIR'];
        if (directory != null && directory.isNotEmpty) {
          await tester.runAsync(() async {
            final folder = Directory(directory);
            await folder.create(recursive: true);
            final png = await image!.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '$directory/${brand.id}.png',
            ).writeAsBytes(png!.buffer.asUint8List());
            await File('$directory/${brand.id}.json').writeAsString(
              jsonEncode({
                'brand': brand.id,
                'brightness': brand.theme.brightness.name,
                'width': 320,
                'height': 844,
                'textScale': 2,
                'materialFill': materialFill
                    .toARGB32()
                    .toRadixString(16)
                    .padLeft(8, '0'),
                'minimum': 4.5,
                'samples': samples,
              }),
            );
          });
        }
        // Publish this state before rejecting a color measurement so a failed
        // run retains its actual image and both pixel observations.
        for (final sample in samples) {
          expect(
            sample['background'],
            materialFill.toARGB32().toRadixString(16).padLeft(8, '0'),
            reason: '${brand.id}: samples must be inside the Snackbar fill',
          );
          expect(
            sample['ratio'] as double,
            greaterThanOrEqualTo(4.5),
            reason: '${brand.id}: $foreground on ${sample['background']}',
          );
        }
      } finally {
        image!.dispose();
      }
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
