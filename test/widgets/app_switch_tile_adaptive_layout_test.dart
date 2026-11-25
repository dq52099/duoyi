import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/export_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

void main() {
  final initialLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialLocale));
  for (final brand in [AppBrands.defaultBrand, AppBrands.liquidGlass]) {
    for (final direction in TextDirection.values) {
      final name = 'switch-${brand.id}-${direction.name}';
      testWidgets(name, (tester) async {
        SharedPreferences.setMockInitialValues({'active_brand': brand.id});
        final theme = ThemeProvider();
        await theme.loadFromStorage();
        expect(theme.brand.id, brand.id);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          theme.dispose();
        });
        await tester.runAsync(loadWeeklyReviewScreenshotFonts);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();
        try {
          final boundary = GlobalKey();
          final probe = RouteRenderProbe(tester, boundary, name);
          var value = true;
          var enabled = true;
          var calls = 0;
          var size = const Size(390, 844);
          var scale = 1.0;
          var paddedSwitch = false;
          late StateSetter update;
          await tester.pumpWidget(
            ChangeNotifierProvider<ThemeProvider>.value(
              value: theme,
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return MaterialApp(
                    theme: brand.theme.copyWith(
                      switchTheme: paddedSwitch
                          ? brand.theme.switchTheme.copyWith(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                            )
                          : brand.theme.switchTheme,
                    ),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: scale < 0
                            ? const RouteProbeNonlinearScaler()
                            : TextScaler.linear(scale),
                      ),
                      child: Directionality(
                        textDirection: direction,
                        child: RepaintBoundary(key: boundary, child: child!),
                      ),
                    ),
                    home: ValueListenableBuilder<AppLocale>(
                      valueListenable: I18n.localeListenable,
                      builder: (context, locale, _) => BrandRouteSurface(
                        remountOnLocaleChange: false,
                        child: Scaffold(
                          body: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: AppSurfaceCard(
                              padding: const EdgeInsets.all(16),
                              child: AppSwitchTile(
                                key: const ValueKey('retained-switch'),
                                icon: Icons.cake_outlined,
                                title: I18n.tr('export.include_anniversaries'),
                                subtitle:
                                    ExportUiCopy.current().anniversaryRangeHint,
                                color: Colors.pink,
                                value: value,
                                onChanged: enabled
                                    ? (next) => update(() {
                                        value = next;
                                        calls++;
                                      })
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
          final switchElement = tester.element(find.byType(Switch));
          for (final layout in [
            (
              name: 'common',
              size: const Size(390, 844),
              scale: 1.0,
              padded: false,
            ),
            (
              name: 'narrow',
              size: const Size(320, 844),
              scale: 1.6,
              padded: false,
            ),
            (
              name: 'large',
              size: const Size(320, 844),
              scale: 2.0,
              padded: false,
            ),
            (
              name: 'landscape',
              size: const Size(568, 320),
              scale: 2.0,
              padded: false,
            ),
            (
              name: 'wide',
              size: const Size(1000, 720),
              scale: 1.0,
              padded: false,
            ),
            (
              name: 'nonlinear',
              size: const Size(332, 844),
              scale: -1.0,
              padded: false,
            ),
            (
              name: 'custom-switch',
              size: const Size(390, 844),
              scale: 2.0,
              padded: true,
            ),
          ]) {
            tester.view.physicalSize = layout.size;
            update(() {
              size = layout.size;
              scale = layout.scale;
              paddedSwitch = layout.padded;
            });
            await tester.pumpAndSettle();
            for (final locale in [AppLocale.en, AppLocale.zh]) {
              I18n.setLocale(locale);
              await tester.pumpAndSettle();
              expect(tester.element(find.byType(Switch)), same(switchElement));
              final title = find.text(I18n.tr('export.include_anniversaries'));
              final subtitle = find.text(
                ExportUiCopy.current().anniversaryRangeHint,
              );
              final stage = '${layout.name}-${locale.name}';
              final tileBox = tester.renderObject<RenderBox>(
                find.byType(AppSwitchTile),
              );
              final drySize = tileBox.getDryLayout(
                BoxConstraints.tightFor(width: tileBox.size.width),
              );
              expect(drySize.height, closeTo(tileBox.size.height, .01));
              expect(
                tileBox.getMinIntrinsicHeight(tileBox.size.width).isFinite,
                isTrue,
              );
              expect(
                tileBox.getMaxIntrinsicHeight(tileBox.size.width).isFinite,
                isTrue,
              );
              for (final f in [title, subtitle]) {
                await probe.text(
                  f,
                  role: '$stage label',
                  minimumGeometricScale: 1,
                );
                final p = tester.renderObject<RenderParagraph>(
                  find.descendant(of: f, matching: find.byType(RichText)),
                );
                final text = tester.widget<Text>(f).data!;
                for (final word in RegExp(r'[A-Za-z]+').allMatches(text)) {
                  final boxes = p.getBoxesForSelection(
                    TextSelection(
                      baseOffset: word.start,
                      extentOffset: word.end,
                    ),
                  );
                  if (boxes.map((b) => b.top).toSet().length > 1) {
                    probe.errors.add('$stage splits ${word.group(0)}');
                  }
                }
              }
              final control = find.byType(Switch);
              await probe.reveal(control);
              final rect = tester.getRect(control);
              expect(rect.width, greaterThanOrEqualTo(44));
              expect(rect.height, greaterThanOrEqualTo(44));
              final tileRect = tester.getRect(find.byType(AppSwitchTile));
              final iconRect = tester.getRect(find.byIcon(Icons.cake_outlined));
              final titleRect = tester.getRect(title);
              if (direction == TextDirection.ltr) {
                expect(iconRect.center.dx, lessThan(titleRect.center.dx));
                expect(rect.right, closeTo(tileRect.right - 4, .1));
              } else {
                expect(iconRect.center.dx, greaterThan(titleRect.center.dx));
                expect(rect.left, closeTo(tileRect.left + 4, .1));
              }
              for (final f in [title, subtitle]) {
                expect(rect.overlaps(tester.getRect(f)), isFalse);
              }
              final node = tester.getSemantics(control);
              expect(node.rect.width, greaterThanOrEqualTo(44));
              expect(node.rect.height, greaterThanOrEqualTo(44));
              final oldCalls = calls;
              final oldValue = value;
              await tester.tap(control);
              await tester.pumpAndSettle();
              expect(calls, oldCalls + 1);
              expect(value, !oldValue);
              await probe.reveal(title);
              await tester.tap(title);
              await tester.pumpAndSettle();
              expect(calls, oldCalls + 2);
              expect(value, oldValue);
              update(() => enabled = false);
              await tester.pumpAndSettle();
              expect(tester.widget<Switch>(control).onChanged, isNull);
              await tester.tap(title);
              await tester.pumpAndSettle();
              expect(calls, oldCalls + 2);
              expect(value, oldValue);
              update(() => enabled = true);
              await tester.pumpAndSettle();
              probe.rows.add({
                'role': '$stage switch geometry',
                'width': rect.width,
                'height': rect.height,
                'titleWidth': tester.getSize(title).width,
                'tileHeight': tester.getSize(find.byType(AppSwitchTile)).height,
                'viewportWidth': size.width,
              });
              await probe.capture(stage);
            }
          }
          await probe.finish();
        } finally {
          semantics.dispose();
        }
      });
    }
  }
}
