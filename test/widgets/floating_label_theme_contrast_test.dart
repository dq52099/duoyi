// Shared input themes must keep floating labels readable without state loss.
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

void main() {
  final original = I18n.current;
  tearDown(() => I18n.setLocale(original));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final secondary in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        for (final state in [
          'unfocused',
          'focused',
          'error-unfocused',
          'error-focused',
        ]) {
          final name =
              'floating-$brand-${secondary ? 'secondary' : 'base'}-'
              '$scale-$state';
          testWidgets(name, (tester) async {
            final controller = TextEditingController(text: '17')
              ..selection = const TextSelection(baseOffset: 1, extentOffset: 2);
            final focus = FocusNode();
            addTearDown(() {
              controller.dispose();
              focus.dispose();
            });
            var changes = 0;
            final boundary = await mountPriorityFixture(
              tester,
              auth: AuthProvider(),
              brand: brand,
              locale: AppLocale.en,
              size: const Size(320, 844),
              scale: scale,
              home: ValueListenableBuilder<AppLocale>(
                valueListenable: I18n.localeListenable,
                builder: (context, locale, _) {
                  final field = TextField(
                    key: const ValueKey('subject-field'),
                    controller: controller,
                    focusNode: focus,
                    onChanged: (_) => changes++,
                    decoration: InputDecoration(
                      labelText: locale == AppLocale.en ? 'Amount' : '数量',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      errorText: state.startsWith('error')
                          ? (locale == AppLocale.en ? 'Check amount' : '检查数量')
                          : null,
                    ),
                  );
                  return Scaffold(
                    body: BrandBackground(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: AppSurfaceCard(
                            child: secondary
                                ? AppSecondaryControlTheme(child: field)
                                : field,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
            final finder = find.byKey(const ValueKey('subject-field'));
            final element = tester.element(finder);
            final value = controller.value;
            final focused = state == 'focused' || state == 'error-focused';
            if (focused) focus.requestFocus();
            await tester.pumpAndSettle();
            final probe = RouteRenderProbe(tester, boundary, name);
            for (final stage in ['english', 'chinese', 'english-again']) {
              I18n.setLocale(stage == 'chinese' ? AppLocale.zh : AppLocale.en);
              await tester.pumpAndSettle();
              await probe.text(
                find.text(I18n.current == AppLocale.en ? 'Amount' : '数量'),
                role: '$stage floating label',
                minimumGeometricScale: .749,
              );
              // The nominal scaled font remains under 24px in both cases;
              // native0.75 floating geometry makes it smaller, so4.5 applies.
              expect(probe.rows.last['required'], 4.5);
              expect(tester.element(finder), same(element));
              expect(controller.value, value);
              expect(focus.hasFocus, focused);
              expect(changes, 0);
              if (state.startsWith('error')) {
                expect(
                  find.text(
                    I18n.current == AppLocale.en ? 'Check amount' : '检查数量',
                  ),
                  findsOneWidget,
                );
              }
              await probe.capture(stage);
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            await probe.finish();
          });
        }
      }
    }
  }

  testWidgets('unrelated theme floating label colors remain primary', (
    tester,
  ) async {
    for (final brand in AppBrands.all.where(
      (brand) => brand.id != 'defaultBrand' && brand.id != 'liquidGlass',
    )) {
      final base = brand.theme;
      expect(
        base.inputDecorationTheme.floatingLabelStyle!.color,
        base.colorScheme.primary,
        reason: brand.id,
      );
      Color? nested;
      await tester.pumpWidget(
        MaterialApp(
          theme: base,
          home: AppSecondaryControlTheme(
            child: Builder(
              builder: (context) {
                nested = Theme.of(
                  context,
                ).inputDecorationTheme.floatingLabelStyle!.color;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(nested, base.colorScheme.primary, reason: brand.id);
    }
  });
}
