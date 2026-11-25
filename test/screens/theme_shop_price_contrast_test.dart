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
    String focus,
    String avatar,
    String skin,
    String layout,
  })>[
    for (final brand in ['defaultBrand', 'liquidGlass'])
      for (final layout in ['ordinary', 'narrow', 'landscape'])
        (
          brand: brand,
          focus: ThemeProvider.defaultFocusBackdropId,
          avatar: ThemeProvider.defaultAvatarFrameId,
          skin: ThemeProvider.defaultCardSkinId,
          layout: layout,
        ),
    for (final brand in ['defaultBrand', 'liquidGlass'])
      for (final skin in ['paper_card', 'mint_card'])
        (
          brand: brand,
          focus: ThemeProvider.defaultFocusBackdropId,
          avatar: ThemeProvider.defaultAvatarFrameId,
          skin: skin,
          layout: 'narrow',
        ),
    for (final brand in ['defaultBrand', 'liquidGlass'])
      (
        brand: brand,
        focus: 'morning_focus',
        avatar: 'golden_frame',
        skin: ThemeProvider.defaultCardSkinId,
        layout: 'narrow',
      ),
    for (final brand in ['defaultBrand', 'liquidGlass'])
      (
        brand: brand,
        focus: ThemeProvider.defaultFocusBackdropId,
        avatar: ThemeProvider.defaultAvatarFrameId,
        skin: 'starlight_card',
        layout: 'narrow',
      ),
  ];
  for (final c in cases) {
    final brand = c.brand;
    final focus = c.focus;
    final avatar = c.avatar;
    final skin = c.skin;
    final layout = c.layout;
    final name = focus != ThemeProvider.defaultFocusBackdropId ||
            avatar != ThemeProvider.defaultAvatarFrameId
        ? '$brand-$focus-$avatar-$layout'
        : skin == ThemeProvider.defaultCardSkinId
        ? '$brand-$layout'
        : '$brand-$skin-$layout';
    testWidgets('shop prices are readable $name', (tester) async {
      SharedPreferences.setMockInitialValues({
        'theme_shop_state': jsonEncode({
          'activeBrand': brand,
          'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          'activeFocusBackdropId': focus,
          'unlockedFocusBackdropIds': [
            ThemeProvider.defaultFocusBackdropId,
            if (focus != ThemeProvider.defaultFocusBackdropId) focus,
          ],
          'activeAvatarFrameId': avatar,
          'unlockedAvatarFrameIds': [
            ThemeProvider.defaultAvatarFrameId,
            if (avatar != ThemeProvider.defaultAvatarFrameId) avatar,
          ],
          'activeCardSkinId': skin,
          'unlockedCardSkinIds': [
            ThemeProvider.defaultCardSkinId,
            if (skin != ThemeProvider.defaultCardSkinId) skin,
          ],
        }),
      });
      final theme = ThemeProvider();
      final auth = AuthProvider();
      final rewards = _VisualRewards();
      final capture = GlobalKey();
      final originalShadows = debugDisableShadows;
      final measurements = <Map<String, Object?>>[];
      try {
        await theme.loadFromStorage();
        expect(theme.brand.id, brand);
        expect(theme.activeFocusBackdrop.id, focus);
        expect(theme.activeAvatarFrame.id, avatar);
        expect(theme.activeCardSkin.id, skin);
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
        final prefs = await SharedPreferences.getInstance();
        final initial = {for (final k in prefs.getKeys()) k: prefs.get(k)};
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
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(key: capture, child: child!),
              ),
              home: const BrandRouteSurface(child: ThemePickerScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final retained = tester.element(find.byType(ThemePickerScreen));
        final expectedTargetCount = 1 +
            8 +
            (focus == ThemeProvider.defaultFocusBackdropId ? 5 : 4) +
            (avatar == ThemeProvider.defaultAvatarFrameId ? 4 : 3) +
            (skin == ThemeProvider.defaultCardSkinId ? 4 : 3);
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
          final targets =
              <
                ({
                  String family,
                  String id,
                  String title,
                  int? cost,
                  bool selected,
                })
              >[
                (
                  family: 'balance',
                  id: 'balance',
                  title: DataSettingsUiCopy.coinCount(1000),
                  cost: null,
                  selected: false,
                ),
                for (final b in theme.brands.where(
                  (b) =>
                      b.id == theme.brand.id || !theme.isBrandUnlocked(b.id),
                ))
                  (
                    family: 'brand',
                    id: b.id,
                    title: b.localizedName,
                    cost: theme.brandCost(b.id),
                    selected: b.id == theme.brand.id,
                  ),
                for (final b in theme.focusBackdrops.where(
                  (b) =>
                      b.id == theme.activeFocusBackdrop.id ||
                      !theme.isFocusBackdropUnlocked(b.id),
                ))
                  (
                    family: 'focus',
                    id: b.id,
                    title: DataSettingsUiCopy.focusBackdropName(b.id, b.name),
                    cost: b.cost,
                    selected: b.id == theme.activeFocusBackdrop.id,
                  ),
                for (final b in theme.avatarFrames.where(
                  (b) =>
                      b.id == theme.activeAvatarFrame.id ||
                      !theme.isAvatarFrameUnlocked(b.id),
                ))
                  (
                    family: 'avatar',
                    id: b.id,
                    title: DataSettingsUiCopy.avatarFrameName(b.id, b.name),
                    cost: b.cost,
                    selected: b.id == theme.activeAvatarFrame.id,
                  ),
                for (final b in theme.cardSkins.where(
                  (b) =>
                      b.id == theme.activeCardSkin.id ||
                      !theme.isCardSkinUnlocked(b.id),
                ))
                  (
                    family: 'card',
                    id: b.id,
                    title: DataSettingsUiCopy.cardSkinName(b.id, b.name),
                    cost: b.cost,
                    selected: b.id == theme.activeCardSkin.id,
                  ),
              ];
          expect(targets.length, expectedTargetCount);
          final optionRowFinder = find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_ThemeOptionRow',
          );
          for (final target in targets) {
            final title = switch (target.family) {
              'balance' => find.text(target.title),
              'brand' => find.byKey(ValueKey('theme_card_bg_${target.id}')),
              _ => find.descendant(
                of: optionRowFinder,
                matching: find.text(target.title),
              ),
            };
            await tester.scrollUntilVisible(
              title,
              300,
              scrollable: find.byType(Scrollable).first,
            );
            final row = find.ancestor(
              of: title,
              matching: optionRowFinder,
            );
            final text = target.family == 'balance'
                ? title
                : find.descendant(
                    of: row,
                    matching: target.selected
                        ? find.byIcon(Icons.check_circle)
                        : find.text(
                            DataSettingsUiCopy.coinCost(target.cost!),
                          ),
                  );
            expect(text, findsOneWidget);
            await Scrollable.ensureVisible(
              tester.element(text),
              alignment: .5,
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final render =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            Rect inImage(RenderBox box) => MatrixUtils.transformRect(
              box.getTransformTo(render),
              Offset.zero & box.size,
            );
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: text, matching: find.byType(RichText)),
            );
            final rect = inImage(paragraph);
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(
              paragraph.getMaxIntrinsicWidth(double.infinity),
              lessThanOrEqualTo(rect.width + .1),
            );
            if (!target.selected) {
              expect(paragraph.text.style!.fontWeight, FontWeight.normal);
            }
            final foreground =
                paragraph.text.style?.foreground?.color ??
                paragraph.text.style!.color!;
            final candidates = <Offset>[];
            if (target.cost != null && !target.selected) {
              final owner = find
                  .ancestor(of: text, matching: find.byType(Container))
                  .first;
              final bounds = inImage(tester.renderObject<RenderBox>(owner));
              for (final fraction in [.3, .7]) {
                candidates.add(
                  Offset(
                    rect.left + rect.width * fraction,
                    (bounds.top + rect.top) / 2,
                  ),
                );
                candidates.add(
                  Offset(
                    rect.left + rect.width * fraction,
                    (bounds.bottom + rect.bottom) / 2,
                  ),
                );
              }
            } else {
              candidates.addAll([
                Offset(rect.center.dx, rect.top - 3),
                Offset(rect.center.dx, rect.bottom + 3),
              ]);
            }
            final pixels = (await tester.runAsync(() async {
              final picture = await render.toImage(pixelRatio: 1);
              try {
                final run = Platform.environment['DUOYI_THEME_PRICE_RUN'];
                if (run != null &&
                    const [
                      'balance',
                      're0',
                      'morning_focus',
                      'golden_frame',
                      'paper_card',
                      'mint_card',
                      'starlight_card',
                      'plain_card',
                    ].contains(target.id)) {
                  final png = await picture.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  final file = File(
                    'evidence/screenshots/theme-shop-price-20261020/$run/$name-${locale.name}-${target.id}.png',
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
            for (final point in candidates) {
              expect(rect.contains(point), isFalse);
              final x = point.dx.floor();
              final y = point.dy.floor();
              expect(x, inInclusiveRange(0, pixels.width - 1));
              expect(y, inInclusiveRange(0, pixels.height - 1));
              final i = (y * pixels.width + x) * 4;
              final data = pixels.data;
              expect(data.getUint8(i + 3), 255);
              final bg = Color.fromARGB(
                255,
                data.getUint8(i),
                data.getUint8(i + 1),
                data.getUint8(i + 2),
              );
              samples.add({
                'x': x,
                'y': y,
                'background': bg.toARGB32(),
                'contrast': appContrastRatio(
                  Color.alphaBlend(foreground, bg),
                  bg,
                ),
              });
            }
            measurements.add({
              'family': target.family,
              'id': target.id,
              'locale': locale.name,
              'role': target.selected
                  ? 'selected_icon'
                  : target.family == 'balance'
                  ? 'balance'
                  : 'price',
              'text': target.selected
                  ? 'check_circle'
                  : tester.widget<Text>(text).data,
              'foreground': foreground.toARGB32(),
              'fontSize': paragraph.text.style!.fontSize,
              'scaledFontSize': paragraph.textScaler.scale(
                paragraph.text.style!.fontSize!,
              ),
              'fontWeight': paragraph.text.style!.fontWeight.toString(),
              'rect': [rect.left, rect.top, rect.width, rect.height],
              'samples': samples,
              'readable': samples.every(
                (s) =>
                    (s['contrast']! as double) >=
                    (target.selected ? 3.0 : 4.5),
              ),
            });
            expect(
              tester.element(find.byType(ThemePickerScreen)),
              same(retained),
            );
            expect({
              for (final k in prefs.getKeys()) k: prefs.get(k),
            }, initial);
          }
        }
        final expectedMeasurementCount = expectedTargetCount * 2;
        expect(measurements.length, expectedMeasurementCount);
        expect(
          measurements.every((row) => row['readable'] == true),
          isTrue,
          reason: jsonEncode(measurements),
        );
      } finally {
        final run = Platform.environment['DUOYI_THEME_PRICE_RUN'];
        if (run != null) {
          await tester.runAsync(() async {
            final file = File(
              'evidence/theme-shop-price-20261020/$run/$name.json',
            );
            await file.parent.create(recursive: true);
            await file.writeAsString(jsonEncode(measurements));
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
