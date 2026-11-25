import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/data_settings_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/theme_picker_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

class _VisualRewards extends AchievementProvider {
  @override
  int get coinBalance => 1000;
}

void main() {
  final cases = <({
    String brand,
    String skin,
    Size size,
    double scale,
    String layout,
  })>[
    (
      brand: 'defaultBrand',
      skin: ThemeProvider.defaultCardSkinId,
      size: const Size(390, 844),
      scale: 1.0,
      layout: 'ordinary',
    ),
    (
      brand: 'defaultBrand',
      skin: 'paper_card',
      size: const Size(320, 844),
      scale: 2.0,
      layout: 'narrow_200',
    ),
    (
      brand: 'defaultBrand',
      skin: 'mint_card',
      size: const Size(390, 844),
      scale: 1.0,
      layout: 'ordinary',
    ),
    (
      brand: 'defaultBrand',
      skin: 'starlight_card',
      size: const Size(320, 844),
      scale: 2.0,
      layout: 'narrow_200',
    ),
    (
      brand: 'liquidGlass',
      skin: ThemeProvider.defaultCardSkinId,
      size: const Size(320, 844),
      scale: 2.0,
      layout: 'narrow_200',
    ),
    (
      brand: 'liquidGlass',
      skin: 'paper_card',
      size: const Size(390, 844),
      scale: 1.0,
      layout: 'ordinary',
    ),
    (
      brand: 'liquidGlass',
      skin: 'mint_card',
      size: const Size(320, 844),
      scale: 2.0,
      layout: 'narrow_200',
    ),
    (
      brand: 'liquidGlass',
      skin: 'starlight_card',
      size: const Size(390, 844),
      scale: 1.0,
      layout: 'ordinary',
    ),
  ];

  for (final c in cases) {
    final brand = c.brand;
    final skin = c.skin;
    final layout = c.layout;
    final caseName = 'widget-desc-$brand-$skin-$layout';

    testWidgets('widget theme descriptions are readable $caseName', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'theme_shop_state': jsonEncode({
          'activeBrand': brand,
          'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          'activeCardSkinId': skin,
          'unlockedCardSkinIds': [
            'plain_card',
            'paper_card',
            'mint_card',
            'starlight_card',
          ],
          'activeWidgetBackgroundId': brand,
          'activeWidgetCardSkinId': skin,
        }),
      });

      final theme = ThemeProvider();
      final auth = AuthProvider();
      final rewards = _VisualRewards();
      final capture = GlobalKey();
      final originalShadows = debugDisableShadows;
      final measurements = <Map<String, Object?>>[];
      var retainedScreen = true;

      try {
        await theme.loadFromStorage();
        expect(theme.brand.id, brand);
        expect(theme.activeCardSkin.id, skin);
        expect(theme.activeWidgetBackgroundId, brand);
        expect(theme.activeWidgetCardSkinId, skin);

        await tester.runAsync(loadWeeklyReviewScreenshotFonts);

        debugDisableShadows = false;
        tester.view.physicalSize = c.size;
        tester.view.devicePixelRatio = 1;

        I18n.setLocale(AppLocale.zh);
        final prefs = await SharedPreferences.getInstance();
        final initialPrefs = {for (final k in prefs.getKeys()) k: prefs.get(k)};
        final initialBg = theme.activeWidgetBackgroundId;
        final initialSkin = theme.activeWidgetCardSkinId;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeProvider>.value(value: theme),
              ChangeNotifierProvider<AuthProvider>.value(value: auth),
              ChangeNotifierProvider<AchievementProvider>.value(
                value: rewards,
              ),
            ],
            child: MaterialApp(
              theme: theme.brand.theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(c.scale)),
                child: RepaintBoundary(key: capture, child: child!),
              ),
              home: const BrandRouteSurface(child: ThemePickerScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final retained = tester.element(find.byType(ThemePickerScreen));

        for (final locale in [AppLocale.zh, AppLocale.en]) {
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .jumpTo(0);
          await tester.pumpAndSettle();

          I18n.setLocale(locale);
          await tester.pumpAndSettle();

          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .jumpTo(0);
          await tester.pumpAndSettle();

          retainedScreen =
              retainedScreen &&
              identical(
                tester.element(find.byType(ThemePickerScreen)),
                retained,
              );
          expect(theme.activeWidgetBackgroundId, initialBg);
          expect(theme.activeWidgetCardSkinId, initialSkin);
          expect(
            {for (final k in prefs.getKeys()) k: prefs.get(k)},
            initialPrefs,
          );

          // Scoped finders to avoid collision between section headers and card skin labels
          final noticeHeaderFinder = find.byWidgetPredicate(
            (w) =>
                w is AppSectionHeader &&
                w.title == DataSettingsUiCopy.widgetSyncNoticeTitle,
          );
          final widgetCardFinder = find.ancestor(
            of: find.text(DataSettingsUiCopy.widgetThemeTitle),
            matching: find.byType(AppSurfaceCard),
          );

          final targets = <({
            String id,
            String text,
            Finder finder,
          })>[
            (
              id: 'widget_sync_notice_title',
              text: DataSettingsUiCopy.widgetSyncNoticeTitle,
              finder: find.descendant(
                of: noticeHeaderFinder,
                matching: find.text(DataSettingsUiCopy.widgetSyncNoticeTitle),
              ),
            ),
            (
              id: 'widget_sync_notice_subtitle',
              text: DataSettingsUiCopy.widgetSyncNoticeSubtitle,
              finder: find.descendant(
                of: find.byType(ThemePickerScreen),
                matching: find.text(DataSettingsUiCopy.widgetSyncNoticeSubtitle),
              ),
            ),
            (
              id: 'widget_theme_title',
              text: DataSettingsUiCopy.widgetThemeTitle,
              finder: find.descendant(
                of: widgetCardFinder,
                matching: find.text(DataSettingsUiCopy.widgetThemeTitle),
              ),
            ),
            (
              id: 'widget_theme_subtitle',
              text: DataSettingsUiCopy.widgetThemeSubtitle,
              finder: find.descendant(
                of: widgetCardFinder,
                matching: find.text(DataSettingsUiCopy.widgetThemeSubtitle),
              ),
            ),
            (
              id: 'widget_background_label',
              text: DataSettingsUiCopy.widgetBackgroundLabel,
              finder: find.descendant(
                of: widgetCardFinder,
                matching: find.text(DataSettingsUiCopy.widgetBackgroundLabel),
              ),
            ),
            (
              id: 'widget_card_skin_label',
              text: DataSettingsUiCopy.widgetCardSkinLabel,
              finder: find.descendant(
                of: widgetCardFinder,
                matching: find.text(DataSettingsUiCopy.widgetCardSkinLabel),
              ),
            ),
          ];

          for (final target in targets) {
            final finder = target.finder;
            if (finder.evaluate().isEmpty) {
              await tester.scrollUntilVisible(
                finder,
                300,
                scrollable: find.byType(Scrollable).first,
              );
            }
            expect(finder, findsOneWidget);
            await Scrollable.ensureVisible(
              tester.element(finder),
              alignment: 0.5,
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);

            final render =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final richTextFinder = find.descendant(
              of: finder,
              matching: find.byType(RichText),
            );
            final paragraph = tester.renderObject<RenderParagraph>(
              richTextFinder.evaluate().isNotEmpty ? richTextFinder : finder,
            );

            // Natural line wrap allowed, do not assert intrinsic single-line width
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(paragraph.size.height, greaterThan(0));
            expect(paragraph.size.width, greaterThan(0));

            // Verify layout boxes from getBoxesForSelection covering full text
            final plainText = paragraph.text.toPlainText();
            expect(plainText, isNotEmpty);
            final boxes = paragraph.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: plainText.length),
            );
            expect(boxes, isNotEmpty);
            for (final box in boxes) {
              expect(box.toRect().height, greaterThan(0));
              expect(box.toRect().width, greaterThan(0));
            }

            // Viewport reachability
            final rect = MatrixUtils.transformRect(
              paragraph.getTransformTo(render),
              Offset.zero & paragraph.size,
            );
            expect(rect.top, greaterThanOrEqualTo(0));
            expect(rect.bottom, lessThanOrEqualTo(render.size.height + 1.0));

            final foreground =
                paragraph.text.style?.foreground?.color ??
                paragraph.text.style?.color ??
                Theme.of(tester.element(finder)).colorScheme.onSurface;

            // Pixel capture and sample candidate points
            final raster = (await tester.runAsync(() async {
              final picture = await render.toImage(pixelRatio: 1);
              try {
                final screenshotDir =
                    Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
                if (screenshotDir != null && screenshotDir.trim().isNotEmpty) {
                  final dir = Directory(screenshotDir.trim());
                  if (!dir.existsSync()) {
                    dir.createSync(recursive: true);
                  }
                  final png = await picture.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  if (png != null) {
                    final file = File(
                      '${dir.path}${Platform.pathSeparator}$caseName-${locale.name}-${target.id}.png',
                    );
                    file.writeAsBytesSync(png.buffer.asUint8List());
                  }
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

            // Sampling candidate points outside glyph bounding box
            final candidates = <Offset>[
              Offset(rect.left + rect.width * 0.25, rect.top - 1),
              Offset(rect.left + rect.width * 0.75, rect.top - 1),
              Offset(rect.left + rect.width * 0.25, rect.bottom + 1),
              Offset(rect.left + rect.width * 0.75, rect.bottom + 1),
            ];
            final samples = <Map<String, Object>>[];
            for (final point in candidates) {
              expect(rect.contains(point), isFalse);
              final x = point.dx.floor();
              final py = point.dy.floor();
              expect(
                x,
                inInclusiveRange(0, raster.width - 1),
                reason:
                    'Sample coordinate x=$x is outside capture raster bounds (${raster.width}x${raster.height}) for target ${target.id}',
              );
              expect(
                py,
                inInclusiveRange(0, raster.height - 1),
                reason:
                    'Sample coordinate y=$py is outside capture raster bounds (${raster.width}x${raster.height}) for target ${target.id}',
              );
              final offset = (py * raster.width + x) * 4;
              final data = raster.data;
              expect(data.getUint8(offset + 3), 255);
              final background = Color.fromARGB(
                255,
                data.getUint8(offset),
                data.getUint8(offset + 1),
                data.getUint8(offset + 2),
              );
              final effectiveForeground = Color.alphaBlend(
                foreground,
                background,
              );
              final contrast = appContrastRatio(
                effectiveForeground,
                background,
              );
              samples.add({
                'x': x,
                'y': py,
                'background': background.toARGB32(),
                'contrast': contrast,
              });
            }
            expect(
              samples.length,
              greaterThanOrEqualTo(4),
              reason:
                  'Insufficient valid background samples for target ${target.id}',
            );

            final readable = samples.every(
              (sample) => (sample['contrast']! as double) >= 4.5,
            );
            measurements.add({
              'role': target.id,
              'locale': locale.name,
              'text': target.text,
              'foreground': foreground.toARGB32(),
              'fontSize': paragraph.text.style?.fontSize,
              'scaledFontSize': paragraph.textScaler.scale(
                paragraph.text.style?.fontSize ?? 14.0,
              ),
              'fontWeight': '${paragraph.text.style?.fontWeight}',
              'rect': [rect.left, rect.top, rect.width, rect.height],
              'samples': samples,
              'readable': readable,
            });
          }
        }

        expect(retainedScreen, isTrue);
        expect(measurements.length, 12);
        expect(
          measurements.every((row) => row['readable'] == true),
          isTrue,
          reason: jsonEncode(measurements),
        );
      } finally {
        final measurementsDir =
            Platform.environment['DUOYI_PRIORITY_THEME_MEASUREMENTS_DIR'];
        if (measurementsDir != null && measurementsDir.trim().isNotEmpty) {
          await tester.runAsync(() async {
            final dir = Directory(measurementsDir.trim());
            if (!dir.existsSync()) {
              dir.createSync(recursive: true);
            }
            final file = File(
              '${dir.path}${Platform.pathSeparator}$caseName.json',
            );
            file.writeAsStringSync(
              jsonEncode({
                'case': caseName,
                'brand': brand,
                'skin': skin,
                'layout': layout,
                'retainedScreen': retainedScreen,
                'measurements': measurements,
              }),
            );
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        theme.dispose();
        auth.dispose();
        rewards.dispose();
        tester.view.reset();
        debugDisableShadows = originalShadows;
        I18n.setLocale(AppLocale.zh);
      }
    });
  }
}
