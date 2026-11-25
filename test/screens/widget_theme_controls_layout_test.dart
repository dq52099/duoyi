// ignore_for_file: depend_on_referenced_packages
import 'dart:ui' as ui;
import 'dart:async';

import 'package:duoyi/core/account_preference_writes.dart';
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

import '../support/priority_theme_fixture.dart' show priorityLayouts;
import '../support/secondary_route_render_probe.dart';
import '../support/widget_polish_screenshot_font.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in [
        ...priorityLayouts,
        (name: 'standalone', size: const Size(320, 844), scale: 2.0),
      ]) {
        testWidgets(
          'widget theme controls $brand ${locale.name} ${layout.name}',
          (tester) async {
            SharedPreferences.setMockInitialValues({
              'active_brand': brand,
              'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
            });
            I18n.setLocale(locale);
            tester.view.physicalSize = layout.size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final theme = _CountedTheme();
            final auth = AuthProvider();
            final rewards = AchievementProvider();
            await theme.loadFromStorage();
            await tester.runAsync(loadWidgetPolishScreenshotFonts);
            final boundary = GlobalKey();
            final base = theme.brand.theme;
            final visualTheme = base.copyWith(
              textTheme: base.textTheme.apply(
                fontFamily: 'DuoyiScreenshotLatin',
                fontFamilyFallback: const ['DuoyiScreenshot'],
              ),
            );
            addTearDown(() async {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pumpAndSettle();
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
                child: MaterialApp(
                  theme: visualTheme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: layout.scale < 0
                          ? const RouteProbeNonlinearScaler()
                          : TextScaler.linear(layout.scale),
                    ),
                    child: RepaintBoundary(key: boundary, child: child!),
                  ),
                  home: layout.name == 'standalone'
                      ? const ThemePickerScreen()
                      : Builder(
                          builder: (context) => Scaffold(
                            body: TextButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const BrandRouteSurface(
                                    child: ThemePickerScreen(),
                                  ),
                                ),
                              ),
                              child: const Text('Open themes'),
                            ),
                          ),
                        ),
                ),
              ),
            );
            if (layout.name != 'standalone') {
              await tester.tap(find.text('Open themes'));
            }
            await tester.pumpAndSettle();
            final retained = tester.state(find.byType(ThemePickerScreen));
            final name = 'widget-theme-$brand-${locale.name}-${layout.name}';
            final probe = RouteRenderProbe(tester, boundary, name);

            Finder chip(String label) => find.widgetWithText(ChoiceChip, label);
            Future<void> reveal(Finder finder) async {
              if (finder.evaluate().isEmpty) {
                await tester.scrollUntilVisible(
                  finder,
                  600,
                  maxScrolls: 100,
                  scrollable: find.byType(Scrollable).first,
                );
              }
              await probe.reveal(finder);
            }

            Future<void> measure(String stage) async {
              for (final label in [
                DataSettingsUiCopy.widgetThemeTitle,
                DataSettingsUiCopy.widgetThemeSubtitle,
                DataSettingsUiCopy.widgetBackgroundLabel,
                DataSettingsUiCopy.widgetCardSkinLabel,
              ]) {
                final section = find
                    .ancestor(
                      of: find.text(DataSettingsUiCopy.widgetThemeTitle),
                      matching: find.byType(AppSurfaceCard),
                    )
                    .first;
                final finder = find.descendant(
                  of: section,
                  matching: find.text(label),
                );
                await reveal(finder);
                await probe.text(
                  finder,
                  role: '$stage section',
                  minimumGeometricScale: .999,
                );
              }
              for (final choice
                  in tester
                      .widgetList<ChoiceChip>(find.byType(ChoiceChip))
                      .toList()) {
                final finder = find.descendant(
                  of: find.byWidget(choice),
                  matching: find.byType(Text),
                );
                await probe.text(
                  finder,
                  role: '$stage choice selected=${choice.selected}',
                  minimumGeometricScale: .999,
                );
              }
              await reveal(chip(DataSettingsUiCopy.widgetFollowCurrentTheme));
              await probe.capture(stage);
            }

            final follow = chip(DataSettingsUiCopy.widgetFollowCurrentTheme);
            await reveal(follow);
            expect(
              tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)),
              hasLength(5),
            );
            final prefs = await SharedPreferences.getInstance();
            Map<String, Object?> snapshot() => {
              for (final key in prefs.getKeys()) key: prefs.get(key),
            };
            final beforeLocale = snapshot();
            await measure('initial');
            I18n.setLocale(
              locale == AppLocale.zh ? AppLocale.en : AppLocale.zh,
            );
            await tester.pumpAndSettle();
            expect(
              tester.state(find.byType(ThemePickerScreen)),
              same(retained),
            );
            expect(snapshot(), beforeLocale);
            expect(theme.backgroundWrites, isEmpty);
            expect(theme.skinWrites, isEmpty);
            await measure('locale');

            // These are existing unlocked options. Exercise real ThemeProvider
            // persistence without purchases, authentication or a native host.
            final backgroundGate = Completer<void>();
            theme.backgroundGate = backgroundGate;
            addTearDown(() {
              if (!backgroundGate.isCompleted) backgroundGate.complete();
            });
            final named = chip(
              I18n.current == AppLocale.en ? 'Liquid Glass' : '液态玻璃',
            );
            await reveal(named);
            await tester.tap(named);
            await tester.pump();
            final progress = find.byType(LinearProgressIndicator);
            expect(progress, findsOneWidget);
            final progressRect = tester.getRect(progress);
            expect(progressRect.top, greaterThanOrEqualTo(0));
            expect(progressRect.bottom, lessThanOrEqualTo(layout.size.height));
            final widgetSection = find
                .ancestor(
                  of: find.text(DataSettingsUiCopy.widgetThemeTitle),
                  matching: find.byType(AppSurfaceCard),
                )
                .first;
            final widgetChoices = find.descendant(
              of: widgetSection,
              matching: find.byType(ChoiceChip),
            );
            expect(
              tester
                  .widgetList<ChoiceChip>(widgetChoices)
                  .every((choice) => choice.onSelected == null),
              isTrue,
            );
            await tester.ensureVisible(
              chip(DataSettingsUiCopy.widgetFollowCurrentTheme),
            );
            await tester.pump();
            await tester.tap(chip(DataSettingsUiCopy.widgetFollowCurrentTheme));
            await tester.pump();
            expect(theme.backgroundWrites, ['liquidGlass']);
            await probe.capture('saving');
            theme.backgroundGate = null;
            backgroundGate.complete();
            await AccountPreferenceWrites.drain();
            await tester.pumpAndSettle();
            expect(theme.activeWidgetBackgroundId, 'liquidGlass');
            expect(theme.backgroundWrites, ['liquidGlass']);
            ScaffoldMessenger.of(
              tester.element(find.byType(ThemePickerScreen)),
            ).removeCurrentSnackBar();
            await tester.pumpAndSettle();
            final plain = chip(
              I18n.current == AppLocale.en ? 'Plain Card' : '素净卡片',
            );
            await reveal(plain);
            await tester.tap(plain);
            await AccountPreferenceWrites.drain();
            await tester.pumpAndSettle();
            expect(theme.activeWidgetCardSkinId, 'plain_card');
            expect(theme.skinWrites, ['plain_card']);
            ScaffoldMessenger.of(
              tester.element(find.byType(ThemePickerScreen)),
            ).removeCurrentSnackBar();
            await tester.pumpAndSettle();
            final followAgain = chip(
              DataSettingsUiCopy.widgetFollowCurrentTheme,
            );
            await reveal(followAgain);
            await tester.tap(followAgain);
            await AccountPreferenceWrites.drain();
            await tester.pumpAndSettle();
            expect(
              theme.activeWidgetBackgroundId,
              ThemeProvider.widgetFollowThemeId,
            );
            expect(theme.backgroundWrites, ['liquidGlass', 'follow_theme']);
            expect(theme.brand.id, brand);
            ScaffoldMessenger.of(
              tester.element(find.byType(ThemePickerScreen)),
            ).removeCurrentSnackBar();
            await tester.pumpAndSettle();
            await measure('saved');
            final persisted = ThemeProvider();
            await persisted.loadFromStorage();
            expect(
              persisted.activeWidgetBackgroundId,
              ThemeProvider.widgetFollowThemeId,
            );
            expect(persisted.activeWidgetCardSkinId, 'plain_card');
            expect(persisted.brand.id, brand);
            persisted.dispose();

            final points = [
              Offset(2, layout.size.height * .4),
              Offset(layout.size.width - 3, layout.size.height * .65),
              Offset(2, layout.size.height - 24),
            ];
            Future<List<int>> pixels(GlobalKey key) async {
              final render =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              return (await tester.runAsync(() async {
                final image = await render.toImage(pixelRatio: 1);
                try {
                  final raw = (await image.toByteData(
                    format: ui.ImageByteFormat.rawRgba,
                  ))!;
                  return [
                    for (final point in points)
                      raw.getUint32(
                        (point.dy.floor() * image.width + point.dx.floor()) * 4,
                      ),
                  ];
                } finally {
                  image.dispose();
                }
              }))!;
            }

            final actual = await pixels(boundary);
            final reference = GlobalKey();
            // The independent reference replaces the unmounted real route; it
            // never supplies a background underneath the page under test.
            await tester.pumpWidget(
              ChangeNotifierProvider<ThemeProvider>.value(
                value: theme,
                child: MaterialApp(
                  theme: visualTheme,
                  home: RepaintBoundary(
                    key: reference,
                    child: Material(
                      color: base.scaffoldBackgroundColor,
                      child: const BrandBackground(child: SizedBox.expand()),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final expected = await pixels(reference);
            for (var i = 0; i < points.length; i++) {
              probe.rows.add({
                'role': 'route background $i',
                'actualRGBA': actual[i],
                'referenceRGBA': expected[i],
                'matchesRealBrandBackground': actual[i] == expected[i],
              });
              if (brand == 'liquidGlass' && actual[i] != expected[i]) {
                probe.errors.add('Glass background hidden at margin $i');
              }
              expect(actual[i] & 255, 255);
              expect(actual[i] >> 8, isNot(0));
            }
            await probe.finish();
          },
        );
      }
    }
  }
}

class _CountedTheme extends ThemeProvider {
  final backgroundWrites = <String>[];
  final skinWrites = <String>[];
  Completer<void>? backgroundGate;

  @override
  Future<bool> setWidgetBackgroundBrand(String id) async {
    backgroundWrites.add(id);
    final gate = backgroundGate;
    if (gate != null) await gate.future;
    return super.setWidgetBackgroundBrand(id);
  }

  @override
  Future<bool> setWidgetCardSkin(String id) {
    skinWrites.add(id);
    return super.setWidgetCardSkin(id);
  }
}
