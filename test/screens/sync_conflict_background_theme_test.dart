import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/sync_conflict_log_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/priority_theme_fixture.dart' show priorityLayouts;
import '../support/secondary_route_render_probe.dart'
    show RouteProbeNonlinearScaler;
import '../support/weekly_review_screenshot_font.dart';

enum _Page { sync }

Widget _screen(_Page page) => const SyncConflictLogScreen();

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final brand in ['defaultBrand', 'liquidGlass', 're0', 'starRail']) {
    for (final page in _Page.values) {
      for (final pushed in [false, true]) {
        for (final layout
            in brand == 're0' || brand == 'starRail'
                ? [priorityLayouts[1]]
                : priorityLayouts) {
          final name =
              '$brand-${page.name}-${pushed ? "pushed" : "standalone"}-${layout.name}';
          testWidgets('sync backdrop $name', (tester) async {
            SharedPreferences.setMockInitialValues({'active_brand': brand});
            I18n.setLocale(AppLocale.zh);
            tester.view.physicalSize = layout.size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final theme = ThemeProvider();
            await tester.runAsync(() async {
              await theme.loadFromStorage();
              await loadWeeklyReviewScreenshotFonts();
            });
            addTearDown(() async {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pumpAndSettle();
              theme.dispose();
            });
            final capture = GlobalKey();
            final screen = _screen(page);
            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ],
                child: MaterialApp(
                  theme: theme.brand.theme,
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: layout.scale < 0
                          ? const RouteProbeNonlinearScaler()
                          : TextScaler.linear(layout.scale),
                    ),
                    child: RepaintBoundary(key: capture, child: child!),
                  ),
                  home: pushed
                      ? Builder(
                          builder: (context) => Scaffold(
                            body: TextButton(
                              key: const ValueKey('open_secondary_backdrop'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  // The actual conflict-log entry is a branded pushed route.
                                  builder: (_) =>
                                      BrandRouteSurface(child: screen),
                                ),
                              ),
                              child: const Text('Open synthetic route'),
                            ),
                          ),
                        )
                      : screen,
                ),
              ),
            );
            await tester.pumpAndSettle();
            if (pushed) {
              await tester.tap(
                find.byKey(const ValueKey('open_secondary_backdrop')),
              );
              await tester.pumpAndSettle();
            }
            expect(theme.brand.id, brand);
            final finder = find.byWidget(screen);
            final element = tester.element(finder);
            final stateFinder = finder;
            final state = tester.state(stateFinder);
            final points = [
              for (final f in [.35, .65, .9]) Offset(2, layout.size.height * f),
            ];
            final actual = <String, List<int>>{};
            final backgroundLayers = <String, int>{};
            final errors = <Object>[];
            for (final selected in [AppLocale.zh, AppLocale.en]) {
              I18n.setLocale(selected);
              await tester.pumpAndSettle();
              expect(tester.element(finder), same(element));
              expect(tester.state(stateFinder), same(state));
              actual[selected.name] = await _pixels(tester, capture, points);
              backgroundLayers[selected.name] = find
                  .byType(BrandBackground)
                  .evaluate()
                  .length;
              await _screenshot(tester, capture, '$name-${selected.name}');
              final error = tester.takeException();
              if (error != null) errors.add(error);
            }
            if (pushed) {
              Navigator.of(element).pop();
              await tester.pumpAndSettle();
              expect(
                find.byKey(const ValueKey('open_secondary_backdrop')),
                findsOneWidget,
              );
            }
            final reference = GlobalKey();
            final t = theme.brand.theme;
            final routeBackground = t.brightness == Brightness.dark
                ? t.colorScheme.surface
                : t.colorScheme.surfaceContainerLowest;
            // Independent reference is rendered only AFTER removing the page.
            await tester.pumpWidget(
              ChangeNotifierProvider<ThemeProvider>.value(
                value: theme,
                child: MaterialApp(
                  theme: t,
                  home: RepaintBoundary(
                    key: reference,
                    child: Material(
                      color: routeBackground,
                      child: brand == 'liquidGlass'
                          ? const BrandBackground(child: SizedBox.expand())
                          : const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final expected = await _pixels(tester, reference, points);
            final output =
                Platform.environment['DUOYI_ROUTE_BACKDROP_EVIDENCE'];
            if (output != null) {
              await tester.runAsync(() async {
                final file = File('$output/$name.json');
                file.parent.createSync(recursive: true);
                file.writeAsStringSync(
                  jsonEncode({
                    'name': name,
                    'brand': brand,
                    'page': page.name,
                    'actual': actual,
                    'backgroundLayers': backgroundLayers,
                    'reference': expected,
                    'renderErrors': [for (final error in errors) '$error'],
                    'stateRetained': true,
                    'pushed': pushed,
                  }),
                );
              });
            }
            for (final entry in actual.entries) {
              expect(
                entry.value,
                expected,
                reason: '$name ${entry.key}: preserve route background policy',
              );
            }
            expect(errors, isEmpty, reason: '$name: no rendering errors');
            final expectedLayers = brand == 'liquidGlass' || pushed ? 1 : 0;
            for (final count in backgroundLayers.values) {
              expect(
                count,
                expectedLayers,
                reason: '$name: background is owned once',
              );
            }
          });
        }
      }
    }
  }
}

Future<List<int>> _pixels(
  WidgetTester tester,
  GlobalKey key,
  List<Offset> points,
) async => (await tester.runAsync(() async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return [
      for (final point in points)
        data.getUint32((point.dy.floor() * image.width + point.dx.floor()) * 4),
    ];
  } finally {
    image.dispose();
  }
}))!;

Future<void> _screenshot(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final output = Platform.environment['DUOYI_ROUTE_BACKDROP_SCREENSHOTS'];
  if (output == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File('$output/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
