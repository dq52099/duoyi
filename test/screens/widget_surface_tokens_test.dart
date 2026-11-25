import 'dart:convert';
import 'dart:io';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/services/android_widget_manager.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';

void main() {
  tearDown(() {
    I18n.setLocale(AppLocale.zh);
    AndroidWidgetManager.debugIsAndroidOverride = null;
  });
  for (final brand in AppBrands.all) {
    final priority = ['defaultBrand', 'liquidGlass'].contains(brand.id);
    for (final locale in AppLocale.values) {
      for (final large in [false, if (priority) true]) {
        final name =
            'widget-surface-${brand.id}-${locale.name}-${large ? "large" : "common"}';
        testWidgets(name, (tester) async {
          AndroidWidgetManager.debugIsAndroidOverride = true;
          const channel = MethodChannel('duoyi/widgets');
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            (call) async => switch (call.method) {
              'canRequestPinWidget' || 'canOpenWidgetSettings' => true,
              _ => 0,
            },
          );
          addTearDown(() {
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              channel,
              null,
            );
          });
          final boundary = await mountPriorityFixture(
            tester,
            auth: AuthProvider(),
            brand: brand.id,
            locale: locale,
            size: large ? const Size(320, 844) : const Size(1000, 900),
            scale: large ? 2 : 1,
            home: const BrandRouteSurface(
              child: WidgetScreen(hostPlatform: WidgetHostPlatform.android),
            ),
          );
          final state = tester.state(find.byType(WidgetScreen));
          final prefs = await SharedPreferences.getInstance();
          Map<String, Object?> snapshot() => {
            for (final key in prefs.getKeys()) key: prefs.get(key),
          };
          final before = snapshot();
          final probe = RouteRenderProbe(tester, boundary, name);
          final rows = <Map<String, Object?>>[];
          final capture = priority && large && locale == AppLocale.zh;
          final controlRadius = priority ? 12.0 : 10.0;
          final cardRadius = priority ? 16.0 : 12.0;
          final context = tester.element(find.byType(WidgetScreen));
          expect(
            Theme.of(context).extension<AppSurfaceStyle>(),
            brand.id == 'defaultBrand'
                ? same(AppSurfaceStyle.ios)
                : brand.id == 'liquidGlass'
                ? same(AppSurfaceStyle.liquidGlass)
                : isNull,
          );
          // Read the border used by Flutter's painter, rather than inferring
          // the result from the ThemeExtension alone.
          Future<void> inspectSegment<T>(String role) async {
            final finder = find.byType(SegmentedButton<T>);
            await _reveal(tester, finder);
            final rendered = find.descendant(
              of: finder,
              matching: find.byWidgetPredicate(
                (widget) => widget.runtimeType.toString().startsWith(
                  '_SegmentedButtonRenderWidget<',
                ),
              ),
            );
            expect(rendered, findsOneWidget);
            // Flutter exposes public border fields on a private render type.
            final dynamic render = tester.renderObject(rendered);
            final enabled = render.enabledBorder as RoundedRectangleBorder;
            final disabled = render.disabledBorder as RoundedRectangleBorder;
            for (final border in [enabled, disabled]) {
              expect(
                border.borderRadius.resolve(TextDirection.ltr),
                BorderRadius.circular(controlRadius),
                reason: role,
              );
            }
            rows.add({'role': role, 'radius': controlRadius});
            if (capture) await probe.capture(role);
          }

          await inspectSegment<WidgetDisplayMode>('display');
          final card = find.ancestor(
            of: find.byType(SegmentedButton<WidgetDisplayMode>),
            matching: find.byType(AppSurfaceCard),
          );
          final ink = tester.widget<Ink>(
            find.descendant(of: card, matching: find.byType(Ink)).first,
          );
          final decoration = ink.decoration! as BoxDecoration;
          expect(decoration.borderRadius, BorderRadius.circular(cardRadius));
          if (priority) {
            final style = brand.theme.extension<AppSurfaceStyle>()!;
            expect(decoration.color, style.cardFillColor);
            expect(decoration.border, style.cardBorder);
          }
          rows.add({'role': 'display-card', 'radius': cardRadius});
          final banner = find.ancestor(
            of: find.text(WidgetUiCopy.pinSupportSupportedTitle),
            matching: find.byType(AppSurfaceCard),
          );
          final icon = find.descendant(
            of: banner,
            matching: find.byIcon(Icons.check_circle_outline),
          );
          expect(icon, findsOneWidget);
          final iconContainer = find
              .ancestor(of: icon, matching: find.byType(Container))
              .first;
          await _reveal(tester, iconContainer);
          final iconDecoration =
              tester.widget<Container>(iconContainer).decoration!
                  as BoxDecoration;
          expect(
            iconDecoration.borderRadius,
            BorderRadius.circular(controlRadius),
          );
          rows.add({'role': 'status-icon', 'radius': controlRadius});
          if (capture) await probe.capture('status');
          await inspectSegment<WidgetCategory>('category');
          I18n.setLocale(locale == AppLocale.en ? AppLocale.zh : AppLocale.en);
          await tester.pumpAndSettle();
          await inspectSegment<WidgetCategory>('category-locale');
          await inspectSegment<WidgetDisplayMode>('display-locale');
          expect(tester.state(find.byType(WidgetScreen)), same(state));
          expect(snapshot(), before);
          expect(tester.takeException(), isNull);
          final folder = Platform.environment['DUOYI_WIDGET_SURFACE_REPORTS'];
          if (folder != null) {
            final file = File('$folder/$name.json');
            file.parent.createSync(recursive: true);
            file.writeAsStringSync(
              jsonEncode({'name': name, 'measurements': rows}),
            );
          }
        });
      }
    }
  }
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final scroll = find
      .descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      )
      .first;
  tester.state<ScrollableState>(scroll).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(finder, 180, scrollable: scroll);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}
