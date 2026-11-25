import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/lock_settings_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

void main() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final layout in ['ordinary', 'narrow', 'landscape']) {
      final name = '$brand-$layout';
      testWidgets('lock settings guidance is readable $name', (tester) async {
        SharedPreferences.setMockInitialValues({'active_brand': brand});
        final theme = ThemeProvider();
        final lock = AppLockProvider();
        final capture = GlobalKey();
        final originalShadows = debugDisableShadows;
        final measurements = <Map<String, Object?>>[];
        try {
          await theme.loadFromStorage();
          expect(theme.brand.id, brand);
          expect(theme.activeCardSkin.id, ThemeProvider.defaultCardSkinId);
          expect(await lock.setPin('2468'), isTrue);
          final prefs = await SharedPreferences.getInstance();
          final initial = {
            for (final key in prefs.getKeys()) key: prefs.get(key),
          };
          await tester.runAsync(loadWeeklyReviewScreenshotFonts);
          debugDisableShadows = false;
          tester.view.physicalSize = switch (layout) {
            'ordinary' => const Size(390, 844),
            'narrow' => const Size(320, 844),
            _ => const Size(568, 320),
          };
          tester.view.devicePixelRatio = 1;
          final scale = layout == 'ordinary' ? 1.0 : 1.6;
          I18n.setLocale(AppLocale.zh);
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<AppLockProvider>.value(value: lock),
              ],
              child: MaterialApp(
                theme: theme.brand.theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: RepaintBoundary(key: capture, child: child!),
                ),
                home: const BrandRouteSurface(child: LockSettingsScreen()),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final retained = tester.element(find.byType(LockSettingsScreen));
          for (final locale in [AppLocale.zh, AppLocale.en]) {
            tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position
                .jumpTo(0);
            await tester.pumpAndSettle();
            I18n.setLocale(locale);
            await tester.pumpAndSettle();
            for (final key in ['app_lock.hero.subtitle', 'app_lock.tip']) {
              final text = find.text(I18n.tr(key));
              await tester.scrollUntilVisible(
                text,
                200,
                scrollable: find.byType(Scrollable).first,
              );
              await Scrollable.ensureVisible(
                tester.element(text),
                alignment: .5,
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              final boundary =
                  capture.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final paragraph = tester.renderObject<RenderParagraph>(text);
              final rect = MatrixUtils.transformRect(
                paragraph.getTransformTo(boundary),
                Offset.zero & paragraph.size,
              );
              expect(paragraph.didExceedMaxLines, isFalse);
              expect(paragraph.text.toPlainText(), I18n.tr(key));
              expect(paragraph.text.style!.fontWeight, FontWeight.normal);
              final foreground = paragraph.text.style!.color!;
              final raster = (await tester.runAsync(() async {
                final picture = await boundary.toImage(pixelRatio: 1);
                try {
                  final run = Platform.environment['DUOYI_LOCK_CONTRAST_RUN'];
                  if (run != null) {
                    final png = await picture.toByteData(
                      format: ui.ImageByteFormat.png,
                    );
                    final file = File(
                      'evidence/screenshots/lock-settings-contrast-20261020/'
                      '$run/$name-${locale.name}-${key.split('.').last}.png',
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
              final samples = <Map<String, Object>>[];
              for (final fraction in [.2, .8]) {
                for (final y in [rect.top - 2, rect.bottom + 2]) {
                  final point = Offset(rect.left + rect.width * fraction, y);
                  expect(rect.contains(point), isFalse);
                  final x = point.dx.floor();
                  final py = point.dy.floor();
                  expect(x, inInclusiveRange(0, raster.width - 1));
                  expect(py, inInclusiveRange(0, raster.height - 1));
                  final offset = (py * raster.width + x) * 4;
                  final rgba = raster.data;
                  final background = Color.fromARGB(
                    rgba.getUint8(offset + 3),
                    rgba.getUint8(offset),
                    rgba.getUint8(offset + 1),
                    rgba.getUint8(offset + 2),
                  );
                  expect(background.a, 1.0);
                  samples.add({
                    'x': x,
                    'y': py,
                    'background': background.toARGB32(),
                    'contrast': appContrastRatio(
                      background,
                      Color.alphaBlend(foreground, background),
                    ),
                  });
                }
              }
              measurements.add({
                'key': key,
                'locale': locale.name,
                'text': paragraph.text.toPlainText(),
                'foreground': foreground.toARGB32(),
                'fontSize': paragraph.text.style!.fontSize,
                'scaledFontSize': paragraph.textScaler.scale(
                  paragraph.text.style!.fontSize!,
                ),
                'fontWeight': '${paragraph.text.style!.fontWeight}',
                'rect': [rect.left, rect.top, rect.width, rect.height],
                'samples': samples,
                'readable': samples.every(
                  (s) => (s['contrast']! as double) >= 4.5,
                ),
              });
            }
            expect(
              tester.element(find.byType(LockSettingsScreen)),
              same(retained),
            );
            expect(lock.enabled, isTrue);
            expect(lock.autoLockMinutes, 5);
            expect(await lock.verify('2468'), isTrue);
            expect({
              for (final key in prefs.getKeys()) key: prefs.get(key),
            }, initial);
          }
          final run = Platform.environment['DUOYI_LOCK_CONTRAST_RUN'];
          if (run != null) {
            await tester.runAsync(() async {
              final report = File(
                'evidence/lock-settings-contrast-20261020/$run/$name.json',
              );
              await report.parent.create(recursive: true);
              await report.writeAsString(
                const JsonEncoder.withIndent('  ').convert(measurements),
              );
            });
          }
          expect(measurements.length, 4);
          expect(
            measurements.where((m) => m['readable'] != true).toList(),
            isEmpty,
            reason: 'actual card padding contrast must be at least 4.5:1',
          );
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          theme.dispose();
          lock.dispose();
          tester.view.reset();
          debugDisableShadows = originalShadows;
          I18n.setLocale(AppLocale.zh);
          SharedPreferences.setMockInitialValues({});
        }
      });
    }
  }
}
