import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/data_settings_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/theme_picker_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final large in [false, true]) {
        final name =
            'widget-choice-$brand-${locale.name}-${large ? 'large' : 'ordinary'}';
        testWidgets('$name has real44 targets and retains independent choices', (
          tester,
        ) async {
          SharedPreferences.setMockInitialValues({
            'theme_shop_state': jsonEncode({
              'activeBrand': brand,
              'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
              'unlockedCardSkinIds': ['plain_card', 'paper_card'],
            }),
          });
          tester.view.physicalSize = Size(large ? 320 : 390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          I18n.setLocale(locale);
          final theme = ThemeProvider();
          final auth = AuthProvider();
          final rewards = AchievementProvider();
          await theme.loadFromStorage();
          await tester.runAsync(loadWeeklyReviewScreenshotFonts);
          final boundary = GlobalKey();
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            await AccountPreferenceWrites.drain();
            theme.dispose();
            auth.dispose();
            rewards.dispose();
          });
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
                ChangeNotifierProvider<AchievementProvider>.value(
                  value: rewards,
                ),
              ],
              child: Consumer<ThemeProvider>(
                builder: (context, selected, _) =>
                    ValueListenableBuilder<AppLocale>(
                      valueListenable: I18n.localeListenable,
                      builder: (context, currentLocale, _) => MaterialApp(
                        theme: selected.brand.theme,
                        locale: Locale(
                          currentLocale == AppLocale.en ? 'en' : 'zh',
                        ),
                        supportedLocales: const [Locale('en'), Locale('zh')],
                        localizationsDelegates:
                            GlobalMaterialLocalizations.delegates,
                        builder: (context, child) => MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            textScaler: TextScaler.linear(large ? 2 : 1),
                          ),
                          child: RepaintBoundary(key: boundary, child: child!),
                        ),
                        home: const BrandRouteSurface(
                          remountOnLocaleChange: false,
                          child: ThemePickerScreen(),
                        ),
                      ),
                    ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final retained = tester.state(find.byType(ThemePickerScreen));
          final observations = <Map<String, Object?>>[];
          Finder chip(String text) => find.widgetWithText(ChoiceChip, text);
          String skinLabel(String id) =>
              DataSettingsUiCopy.cardSkinName(id, theme.cardSkinById(id).name);

          Future<void> reveal(Finder target) async {
            if (target.evaluate().isEmpty) {
              await tester.scrollUntilVisible(
                target,
                500,
                scrollable: find.byType(Scrollable).first,
                maxScrolls: 100,
              );
            }
            await Scrollable.ensureVisible(
              tester.element(target),
              alignment: .5,
            );
            await tester.pumpAndSettle();
          }

          Future<void> audit(String stage) async {
            for (final label in [
              DataSettingsUiCopy.widgetFollowCurrentTheme,
              AppBrands.byId('defaultBrand').localizedName,
              AppBrands.byId('liquidGlass').localizedName,
              DataSettingsUiCopy.widgetFollowCardSkin,
              skinLabel('plain_card'),
              skinLabel('paper_card'),
            ]) {
              final target = chip(label);
              await reveal(target);
              expect(target, findsOneWidget);
              final box = tester.getSize(target);
              expect(
                box.width,
                greaterThanOrEqualTo(44),
                reason: '$stage $label real width',
              );
              expect(
                box.height,
                greaterThanOrEqualTo(44),
                reason: '$stage $label real height',
              );
              expect(target.hitTestable(), findsOneWidget);
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(of: target, matching: find.byType(RichText)),
              );
              expect(
                paragraph.didExceedMaxLines,
                isFalse,
                reason: '$stage $label truncated',
              );
              expect(paragraph.text.toPlainText(), label);
              observations.add({
                'stage': stage,
                'label': label,
                'width': box.width,
                'height': box.height,
              });
            }
          }

          Future<void> edgeTap(Finder target) async {
            await reveal(target);
            final rect = tester.getRect(target);
            // The bottom edge belongs to RawChip's padded hit box. A decorative
            // outer spacer cannot pass this behavioral selection assertion.
            await tester.tapAt(Offset(rect.center.dx, rect.bottom - 1));
            await tester.pump();
            await AccountPreferenceWrites.drain();
            await tester.pumpAndSettle();
            expect(tester.widget<ChoiceChip>(target).selected, isTrue);
            ScaffoldMessenger.of(
              tester.element(find.byType(ThemePickerScreen)),
            ).removeCurrentSnackBar();
            await tester.pumpAndSettle();
          }

          await audit('initial');
          await edgeTap(chip(AppBrands.byId('liquidGlass').localizedName));
          expect(theme.activeWidgetBackgroundId, 'liquidGlass');
          await edgeTap(chip(skinLabel('paper_card')));
          expect(theme.activeWidgetCardSkinId, 'paper_card');

          I18n.setLocale(locale == AppLocale.zh ? AppLocale.en : AppLocale.zh);
          await tester.pumpAndSettle();
          await theme.setBrand(
            brand == 'defaultBrand' ? 'liquidGlass' : 'defaultBrand',
          );
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(ThemePickerScreen)), same(retained));
          expect(theme.activeWidgetBackgroundId, 'liquidGlass');
          expect(theme.activeWidgetCardSkinId, 'paper_card');
          await audit('mounted-switch');
          final prefs = await SharedPreferences.getInstance();
          final saved =
              jsonDecode(prefs.getString('theme_shop_state')!)
                  as Map<String, dynamic>;
          expect(saved['activeWidgetBackgroundId'], 'liquidGlass');
          expect(saved['activeWidgetCardSkinId'], 'paper_card');
          final reloaded = ThemeProvider();
          addTearDown(reloaded.dispose);
          await reloaded.loadFromStorage();
          expect(reloaded.activeWidgetBackgroundId, 'liquidGlass');
          expect(reloaded.activeWidgetCardSkinId, 'paper_card');
          expect(tester.takeException(), isNull);

          await reveal(chip(DataSettingsUiCopy.widgetFollowCurrentTheme));
          await tester.runAsync(() async {
            final output =
                Platform.environment['DUOYI_PRIORITY_THEME_MEASUREMENTS_DIR'];
            if (output != null && output.isNotEmpty) {
              final file = File('$output/$name.json');
              file.parent.createSync(recursive: true);
              file.writeAsStringSync(
                jsonEncode({'scenario': name, 'targets': observations}),
              );
            }
            final directory =
                Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
            if (directory == null || directory.isEmpty) return;
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await render.toImage(pixelRatio: 1);
            try {
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File('$directory/$name.png');
              file.parent.createSync(recursive: true);
              file.writeAsBytesSync(data!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        });
      }
    }
  }
}
