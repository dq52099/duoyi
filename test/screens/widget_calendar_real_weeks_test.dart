import 'dart:convert';
import 'dart:io';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

Finder _type(String name) =>
    find.byWidgetPredicate((widget) => widget.runtimeType.toString() == name);

void main() {
  final initialLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      final name = 'calendar-real-weeks-$brand-${platform.name}';
      testWidgets(name, (tester) async {
        final appBrand = brand == 'defaultBrand'
            ? 'liquidGlass'
            : 'defaultBrand';
        SharedPreferences.setMockInitialValues({
          'theme_shop_state': jsonEncode({
            'activeBrand': appBrand,
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
            'activeWidgetBackgroundId': brand,
          }),
        });
        final theme = ThemeProvider();
        final preferences = PreferencesProvider();
        await theme.loadFromStorage();
        await tester.runAsync(loadWeeklyReviewScreenshotFonts);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          theme.dispose();
          preferences.dispose();
        });
        expect(theme.brand.id, appBrand);
        expect(theme.activeWidgetBackgroundBrand.id, brand);
        final boundary = GlobalKey();
        final probe = RouteRenderProbe(tester, boundary, name);
        final measurements = <Map<String, Object?>>[];
        final navHeights = <AppLocale, double>{};
        for (final layout in [
          (name: 'roomy', size: const Size(1000, 720), scale: 1.0),
          (name: 'capacity', size: const Size(414, 844), scale: 1.0),
          (name: 'narrow', size: const Size(320, 844), scale: 1.6),
          (name: 'large', size: const Size(320, 844), scale: 2.0),
          (name: 'landscape', size: const Size(568, 320), scale: 2.0),
          (name: 'nonlinear', size: const Size(332, 844), scale: -1.0),
        ]) {
          tester.view.physicalSize = layout.size;
          for (final mode in WidgetDisplayMode.values) {
            I18n.setLocale(AppLocale.en);
            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                  ChangeNotifierProvider<PreferencesProvider>.value(
                    value: preferences,
                  ),
                ],
                child: ValueListenableBuilder<AppLocale>(
                  valueListenable: I18n.localeListenable,
                  builder: (context, locale, _) => MaterialApp(
                    theme: theme.brand.theme,
                    locale: Locale(locale.name),
                    supportedLocales: const [Locale('en'), Locale('zh')],
                    localizationsDelegates:
                        GlobalMaterialLocalizations.delegates,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: layout.scale < 0
                            ? const RouteProbeNonlinearScaler()
                            : TextScaler.linear(layout.scale),
                      ),
                      child: RepaintBoundary(key: boundary, child: child!),
                    ),
                    home: BrandRouteSurface(
                      remountOnLocaleChange: false,
                      child: Scaffold(
                        body: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: WidgetPreviewCard.calendar(
                            key: const ValueKey('retained-calendar-preview'),
                            displayMode: mode,
                            platformOverride: platform,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final previewElement = tester.element(
              find.byType(WidgetPreviewCard),
            );
            for (final firstDay in [7, 1, 6, 5, 4, 3, 2]) {
              await preferences.setFirstDayOfWeek(firstDay);
              await tester.pumpAndSettle();
              for (final locale in [AppLocale.en, AppLocale.zh]) {
                final prefs = await SharedPreferences.getInstance();
                final stored = {
                  for (final key in prefs.getKeys()) key: prefs.get(key),
                };
                I18n.setLocale(locale);
                await tester.pumpAndSettle();
                expect(
                  tester.element(find.byType(WidgetPreviewCard)),
                  same(previewElement),
                );
                expect({
                  for (final key in prefs.getKeys()) key: prefs.get(key),
                }, stored);
                final scenario =
                    '${layout.name}/${mode.name}/$firstDay/${locale.name}';
                final frame = _type('_WidgetPreviewContentFrame');
                final frameRect = tester.getRect(frame);
                final cells = _type('_WidgetPreviewCalendarCell');
                final cellCount = cells.evaluate().length;
                final dates = <int>[];
                final emptyRows = <int>[];
                Rect? finalRealPart;
                for (var index = 0; index < cellCount; index += 7) {
                  final row = find
                      .ancestor(of: cells.at(index), matching: find.byType(Row))
                      .first;
                  final rowRect = tester.getRect(row);
                  final rowDates = <int>[];
                  for (final textElement
                      in find
                          .descendant(of: row, matching: find.byType(Text))
                          .evaluate()) {
                    final text = textElement.widget as Text;
                    final day = int.tryParse(text.data ?? '');
                    if (day == null) continue;
                    rowDates.add(day);
                    dates.add(day);
                    expect(day, inInclusiveRange(1, 31));
                    final column =
                        (DateTime.utc(2026, 5, day).weekday - firstDay) % 7;
                    expect(
                      tester
                          .getCenter(
                            find.byElementPredicate(
                              (e) => identical(e, textElement),
                            ),
                          )
                          .dx,
                      closeTo(
                        rowRect.left + (column + .5) * rowRect.width / 7,
                        .1,
                      ),
                      reason: scenario,
                    );
                    final paragraph = tester.renderObject<RenderParagraph>(
                      find.descendant(
                        of: find.byElementPredicate(
                          (e) => identical(e, textElement),
                        ),
                        matching: find.byType(RichText),
                      ),
                    );
                    expect(
                      paragraph.didExceedMaxLines,
                      isFalse,
                      reason: scenario,
                    );
                    expect(paragraph.text.style!.fontSize, 10);
                  }
                  if (rowDates.isEmpty) {
                    emptyRows.add(index ~/ 7);
                  } else {
                    finalRealPart = tester.getRect(
                      find
                          .ancestor(of: row, matching: find.byType(SizedBox))
                          .first,
                    );
                  }
                }
                if (emptyRows.isNotEmpty) {
                  probe.errors.add('$scenario empty weeks $emptyRows');
                }
                final realWeeks = firstDay >= 6
                    ? 6
                    : 5; // May 2026 calendar facts.
                final limit = mode == WidgetDisplayMode.compact
                    ? 1
                    : mode == WidgetDisplayMode.standard
                    ? 4
                    : realWeeks;
                if (cellCount ~/ 7 > limit) {
                  probe.errors.add('$scenario has too many weeks');
                }
                expect(dates, orderedEquals([...dates]..sort()));
                expect(dates.toSet().length, dates.length);
                final fallback = find.descendant(
                  of: frame,
                  matching: find.byWidgetPredicate(
                    (w) =>
                        w is Text &&
                        (w.data == WidgetUiCopy.calendarCurrentDate ||
                            w.data == WidgetUiCopy.calendarCurrentDay),
                  ),
                );
                if (cellCount == 0) {
                  expect(fallback, findsOneWidget, reason: scenario);
                } else {
                  expect(dates, contains(17), reason: scenario);
                }
                final nav = find.byKey(
                  const ValueKey('widget_preview_navigation'),
                );
                final hasNav = nav.evaluate().isNotEmpty;
                if (layout.name == 'roomy' &&
                    mode == WidgetDisplayMode.detailed &&
                    firstDay == 7) {
                  expect(
                    dates,
                    orderedEquals(List.generate(31, (index) => index + 1)),
                  );
                  expect(hasNav, isTrue);
                  navHeights[locale] = tester.getSize(nav).height;
                }
                final spare = finalRealPart == null
                    ? 0.0
                    : frameRect.bottom - finalRealPart.bottom;
                final needsNav =
                    mode == WidgetDisplayMode.detailed &&
                    layout.scale == 1 &&
                    dates.length == 31 &&
                    spare + .1 >= navHeights[locale]! + 10;
                if (needsNav && !hasNav) {
                  probe.errors.add(
                    '$scenario hides navigation despite complete month and room',
                  );
                }
                if (hasNav) {
                  expect(
                    tester.getRect(nav).bottom,
                    lessThanOrEqualTo(frameRect.bottom + .1),
                  );
                  for (final label in WidgetUiCopy.previewNavLabels) {
                    expect(
                      find.descendant(of: nav, matching: find.text(label)),
                      findsOneWidget,
                    );
                  }
                }
                measurements.add({
                  'layout': layout.name,
                  'mode': mode.name,
                  'firstDay': firstDay,
                  'locale': locale.name,
                  'dates': dates,
                  'weekRows': cellCount ~/ 7,
                  'emptyRows': emptyRows,
                  'navigation': hasNav,
                  'navigationRequiredBySpace': needsNav,
                  'spareAfterRealMonthPx': spare,
                  'referenceNavigationHeightPx': navHeights[locale],
                  'bodyHeight': frameRect.height,
                  'fallback': cellCount == 0,
                });
                if (mode == WidgetDisplayMode.detailed &&
                    [1, 7].contains(firstDay) &&
                    ['roomy', 'capacity', 'large'].contains(layout.name)) {
                  await probe.capture(
                    '${layout.name}-$firstDay-${locale.name}',
                  );
                }
                expect(tester.takeException(), isNull, reason: scenario);
              }
            }
          }
        }
        final output = Platform.environment['DUOYI_SECONDARY_MEASUREMENTS'];
        if (output != null) {
          await tester.runAsync(() async {
            final file = File('$output/$name.json');
            file.parent.createSync(recursive: true);
            file.writeAsStringSync(
              const JsonEncoder.withIndent('  ').convert({
                'name': name,
                'measurements': measurements,
                'errors': probe.errors,
              }),
            );
          });
        }
        expect(measurements, hasLength(252));
        expect(probe.errors, isEmpty);
      });
    }
  }
}
