// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/heatmap_calendar.dart';
import 'package:duoyi/core/heatmap_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/app_date_format.dart';
import 'package:duoyi/widgets/calendar_heatmap.dart';
import 'package:duoyi/widgets/habit_heatmap.dart';
import 'package:duoyi/widgets/mood_heatmap.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secondary_route_render_probe.dart'
    show RouteProbeNonlinearScaler;
import '../support/weekly_review_screenshot_font.dart';

class _HeatmapPriorityScenario {
  final String name;
  final String brandId;
  final AppLocale locale;
  final Size size;
  final double scale;
  final double devicePixelRatio;
  final bool isNonlinear;

  const _HeatmapPriorityScenario({
    required this.name,
    required this.brandId,
    required this.locale,
    required this.size,
    required this.scale,
    required this.devicePixelRatio,
    this.isNonlinear = false,
  });
}

const _scenarios = <_HeatmapPriorityScenario>[
  _HeatmapPriorityScenario(
    name: 'zh-portrait-320x844-scale2-dpr2-defaultBrand',
    brandId: 'defaultBrand',
    locale: AppLocale.zh,
    size: Size(320, 844),
    scale: 2.0,
    devicePixelRatio: 2.0,
  ),
  _HeatmapPriorityScenario(
    name: 'en-portrait-320x844-scale2-dpr2-liquidGlass',
    brandId: 'liquidGlass',
    locale: AppLocale.en,
    size: Size(320, 844),
    scale: 2.0,
    devicePixelRatio: 2.0,
  ),
  _HeatmapPriorityScenario(
    name: 'zh-landscape-844x390-scale1-dpr1-liquidGlass',
    brandId: 'liquidGlass',
    locale: AppLocale.zh,
    size: Size(844, 390),
    scale: 1.0,
    devicePixelRatio: 1.0,
  ),
  _HeatmapPriorityScenario(
    name: 'en-landscape-844x390-scale1-dpr1-defaultBrand',
    brandId: 'defaultBrand',
    locale: AppLocale.en,
    size: Size(844, 390),
    scale: 1.0,
    devicePixelRatio: 1.0,
  ),
  _HeatmapPriorityScenario(
    name: 'zh-ordinary-390x844-scale1-dpr1-defaultBrand',
    brandId: 'defaultBrand',
    locale: AppLocale.zh,
    size: Size(390, 844),
    scale: 1.0,
    devicePixelRatio: 1.0,
  ),
  _HeatmapPriorityScenario(
    name: 'en-ordinary-390x844-scale1-dpr1-liquidGlass',
    brandId: 'liquidGlass',
    locale: AppLocale.en,
    size: Size(390, 844),
    scale: 1.0,
    devicePixelRatio: 1.0,
  ),
  _HeatmapPriorityScenario(
    name: 'en-wide-1024x768-scale1-dpr1-defaultBrand',
    brandId: 'defaultBrand',
    locale: AppLocale.en,
    size: Size(1024, 768),
    scale: 1.0,
    devicePixelRatio: 1.0,
  ),
  _HeatmapPriorityScenario(
    name: 'zh-nonlinear-332x844-dpr2-liquidGlass',
    brandId: 'liquidGlass',
    locale: AppLocale.zh,
    size: Size(332, 844),
    scale: 1.9,
    devicePixelRatio: 2.0,
    isNonlinear: true,
  ),
];

Future<void> _captureIfRequested(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final explicitDir =
      Platform.environment['DUOYI_RETAINED_DIALOG_SCREENSHOT_DIR'] ??
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'] ??
      (Platform.environment['DUOYI_CAPTURE_HEATMAP_SCREENSHOT'] == '1'
          ? 'evidence/screenshots/heatmap-priority'
          : null);
  if (explicitDir == null || explicitDir.isEmpty) return;

  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final file = File('$explicitDir/heatmap-axis-content-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _revealVertical(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  final element = tester.element(finder);
  final scrollable = Scrollable.maybeOf(element, axis: Axis.vertical);
  if (scrollable != null) {
    await scrollable.position.ensureVisible(
      element.findRenderObject()!,
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
  } else {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }
}

Future<void> _revealAndTap(WidgetTester tester, Finder finder) async {
  await _revealVertical(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _revealCell(WidgetTester tester, Finder cellFinder) async {
  expect(cellFinder, findsOneWidget);
  final element = tester.element(cellFinder);
  final vScroll = Scrollable.maybeOf(element, axis: Axis.vertical);
  if (vScroll != null) {
    await vScroll.position.ensureVisible(
      element.findRenderObject()!,
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
  }
  final hScroll = Scrollable.maybeOf(element, axis: Axis.horizontal);
  if (hScroll != null) {
    await hScroll.position.ensureVisible(
      element.findRenderObject()!,
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
  }
}

List<Color> _resolveCompositedBackgrounds(Element element, ThemeData theme) {
  final layers = <List<Color>>[];
  void addDecoration(Decoration? decoration) {
    if (decoration is! BoxDecoration) return;
    final layer = <List<Color>>[];
    if (decoration.color case final color?) layer.add([color]);
    if (decoration.gradient case final gradient?) layer.add(gradient.colors);
    layers.addAll(layer.reversed);
  }

  element.visitAncestorElements((ancestor) {
    switch (ancestor.widget) {
      case Material(:final color):
        if (color != null) layers.add([color]);
      case Ink(:final decoration):
        addDecoration(decoration);
      case DecoratedBox(:final decoration):
        addDecoration(decoration);
      case Scaffold(:final backgroundColor):
        if (backgroundColor != null) layers.add([backgroundColor]);
    }
    return true;
  });
  var backgrounds = <Color>[
    theme.scaffoldBackgroundColor,
    theme.colorScheme.surface,
  ];
  for (final layer in layers.reversed) {
    backgrounds = [
      for (final bg in backgrounds)
        for (final color in layer) Color.alphaBlend(color, bg),
    ];
  }
  return backgrounds;
}

void _verifyParagraphGeometry(
  WidgetTester tester,
  Finder textFinder, {
  Rect? clipViewport,
  String? role,
}) {
  final richTextFinder = tester.any(textFinder) &&
          tester.widget(textFinder.first) is RichText
      ? textFinder
      : find.descendant(
          of: textFinder,
          matching: find.byType(RichText),
        );
  expect(
    richTextFinder,
    findsAtLeastNWidgets(1),
    reason: '$role must contain RichText',
  );
  final paragraph = tester.renderObject<RenderParagraph>(richTextFinder.first);
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '$role didExceedMaxLines must be false',
  );

  final fullSelection = TextSelection(
    baseOffset: 0,
    extentOffset: paragraph.text.toPlainText().length,
  );
  final boxes = paragraph.getBoxesForSelection(fullSelection);
  expect(
    boxes,
    isNotEmpty,
    reason: '$role selection boxes must not be empty',
  );

  final paragraphLocalBounds = (Offset.zero & paragraph.size).inflate(0.1);
  for (final box in boxes) {
    final rect = box.toRect();
    expect(
      paragraphLocalBounds.contains(rect.topLeft),
      isTrue,
      reason: '$role box topLeft $rect within bounds $paragraphLocalBounds',
    );
    expect(
      paragraphLocalBounds.contains(rect.bottomRight),
      isTrue,
      reason: '$role box bottomRight $rect within bounds $paragraphLocalBounds',
    );
  }

  expect(
    paragraph.textSize.width,
    lessThanOrEqualTo(paragraph.size.width + 0.1),
    reason: '$role textSize.width <= size.width',
  );
  expect(
    paragraph.textSize.height,
    lessThanOrEqualTo(paragraph.size.height + 0.1),
    reason: '$role textSize.height <= size.height',
  );

  if (clipViewport != null) {
    final globalTransform = paragraph.getTransformTo(null);
    final globalRect = MatrixUtils.transformRect(
      globalTransform,
      Offset.zero & paragraph.size,
    );
    final intersection = globalRect.intersect(clipViewport);
    expect(
      intersection.width,
      greaterThan(0),
      reason: '$role must intersect visible viewport width',
    );
    expect(
      intersection.height,
      greaterThan(0),
      reason: '$role must intersect visible viewport height',
    );
  }
}

void main() {
  final initialGlobalLocale = I18n.current;

  setUpAll(() async {
    if (File('assets/fonts/DroidSansFallbackFull.ttf').existsSync() &&
        File('assets/fonts/DejaVuSans.ttf').existsSync()) {
      await loadWeeklyReviewScreenshotFonts();
    }
  });

  final testToday = DateTime(2026, 10, 9);
  final habitData = <String, int>{
    for (var day = 0; day < 84; day++)
      HeatmapCalendarWindow.dateKey(
        HeatmapCalendarWindow.shiftDay(testToday, -day),
      ): day % 5 == 0 ? 0 : (day % 5),
  };

  final diaryEntries = <String, DiaryEntry>{
    for (var day = 0; day < 84; day++)
      if (day % 3 != 1)
        HeatmapCalendarWindow.dateKey(
          HeatmapCalendarWindow.shiftDay(testToday, -day),
        ): DiaryEntry(
          id: 'synthetic-$day',
          date: HeatmapCalendarWindow.shiftDay(testToday, -day),
          mood: Mood.values[day % Mood.values.length],
        ),
  };

  for (final scenario in _scenarios) {
    testWidgets(
      'CalendarHeatmap axis content and geometry ${scenario.name}',
      (tester) async {
        final previousShadows = debugDisableShadows;
        debugDisableShadows = false;
        ThemeProvider? themeProvider;
        PreferencesProvider? preferencesProvider;
        try {
          I18n.setLocale(scenario.locale);
          SharedPreferences.setMockInitialValues({
            'active_brand': scenario.brandId,
            'pref_date_format': 'yyyy-MM-dd',
          });

          await tester.runAsync(() async {
            themeProvider = ThemeProvider();
            await themeProvider!.loadFromStorage();
            preferencesProvider = PreferencesProvider();
            await preferencesProvider!.loadFromStorage();
          });

          final boundaryKey = GlobalKey();
          tester.view.physicalSize = scenario.size * scenario.devicePixelRatio;
          tester.view.devicePixelRatio = scenario.devicePixelRatio;

          final textScaler = scenario.isNonlinear
              ? const RouteProbeNonlinearScaler()
              : TextScaler.linear(scenario.scale);

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(
                  value: themeProvider!,
                ),
                ChangeNotifierProvider<PreferencesProvider>.value(
                  value: preferencesProvider!,
                ),
              ],
              child: Consumer<ThemeProvider>(
                builder: (context, theme, _) => MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: Locale(scenario.locale == AppLocale.en ? 'en' : 'zh'),
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: theme.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: textScaler,
                    ),
                    child: RepaintBoundary(key: boundaryKey, child: child!),
                  ),
                  home: Scaffold(
                    backgroundColor: theme.brand.theme.colorScheme.surface,
                    body: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: AppSurfaceCard(
                          padding: const EdgeInsets.all(14),
                          child: HabitHeatmap(
                            heatmapData: habitData,
                            today: testToday,
                            weeks: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // 1. Verify root media size contract.
          final media = tester.element(find.byType(HabitHeatmap));
          final mediaData = MediaQuery.of(media);
          expect(mediaData.size.width, equals(scenario.size.width));
          expect(mediaData.size.height, equals(scenario.size.height));

          final rootViewport = Offset.zero & scenario.size;

          // 2. Verify date-range label is rendered respecting real AppDateFormat prefs.
          final copy = HeatmapUiCopy(scenario.locale);
          final window = HeatmapCalendarWindow(weeks: 12, today: testToday);
          final expectedPattern = AppDateFormat.readPattern(
            tester.element(find.byType(HabitHeatmap)),
          ) ?? preferencesProvider!.dateFormat;
          final expectedRangeText = copy.range(
            window.start,
            window.today,
            pattern: expectedPattern,
          );
          final rangeFinder = find.text(expectedRangeText);
          expect(rangeFinder, findsOneWidget);
          _verifyParagraphGeometry(
            tester,
            rangeFinder,
            clipViewport: rootViewport,
            role: 'Date range label',
          );

          // 3. Verify weekday labels: odd days present, contrast readable on surface, bounds fit.
          for (final day in [1, 3, 5, 7]) {
            final weekdayText = copy.weekday(day);
            final weekdayFinder = find.text(weekdayText);
            expect(
              weekdayFinder,
              findsAtLeastNWidgets(1),
              reason: 'Weekday $weekdayText must be present',
            );

            _verifyParagraphGeometry(
              tester,
              weekdayFinder.first,
              clipViewport: rootViewport,
              role: 'Weekday $weekdayText',
            );

            final weekdayParagraph = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: weekdayFinder.first,
                matching: find.byType(RichText),
              ),
            );
            final fg = weekdayParagraph.text.style?.color ??
                DefaultTextStyle.of(
                  tester.element(weekdayFinder.first),
                ).style.color!;
            final paintedBackgrounds = _resolveCompositedBackgrounds(
              tester.element(weekdayFinder.first),
              themeProvider!.brand.theme,
            );
            for (final bg in paintedBackgrounds) {
              final effectiveFg = Color.alphaBlend(fg, bg);
              final contrast = appContrastRatio(effectiveFg, bg);
              expect(
                contrast,
                greaterThanOrEqualTo(4.5),
                reason: 'Weekday $weekdayText contrast $contrast on $bg',
              );
            }
          }

          // 4. Verify horizontal grid SingleChildScrollView and month header.
          final scrollFinder = find.byKey(const ValueKey('heatmap_scroll'));
          expect(scrollFinder, findsOneWidget);
          final scrollWidget = tester.widget<SingleChildScrollView>(
            scrollFinder,
          );
          final scrollController = scrollWidget.controller!;
          final maxScroll = scrollController.position.maxScrollExtent;

          // Initial scroll lands at maxScrollExtent (end scroll edge).
          expect(
            scrollController.offset,
            equals(maxScroll),
            reason: 'Initial scroll must land at maxScrollExtent',
          );

          final scrollRender = tester.renderObject<RenderBox>(scrollFinder);
          final scrollGlobalRect = MatrixUtils.transformRect(
            scrollRender.getTransformTo(null),
            Offset.zero & scrollRender.size,
          );

          // Verify reachable month at end scroll edge (October 2026):
          final latestMonthText = copy.month(DateTime(2026, 10));
          final latestMonthFinder = find.text(latestMonthText);
          expect(latestMonthFinder, findsOneWidget);
          _verifyParagraphGeometry(
            tester,
            latestMonthFinder,
            clipViewport: scrollGlobalRect,
            role: 'End reachable month $latestMonthText',
          );

          // Capture end boundary state if requested.
          await _captureIfRequested(tester, boundaryKey, '${scenario.name}-end');

          // 5. Verify month labels at start scroll edge:
          scrollController.jumpTo(0.0);
          await tester.pumpAndSettle();
          expect(scrollController.offset, equals(0.0));

          // Start month (July) must NOT be suppressed and must be reachable at offset 0.
          final julMonthText = copy.month(DateTime(2026, 7));
          final julFinder = find.text(julMonthText);
          expect(
            julFinder,
            findsOneWidget,
            reason: 'Starting month $julMonthText must not be suppressed',
          );
          _verifyParagraphGeometry(
            tester,
            julFinder,
            clipViewport: scrollGlobalRect,
            role: 'Start reachable month $julMonthText',
          );

          final julRender = tester.renderObject<RenderBox>(julFinder);
          final julTopLeft = julRender.localToGlobal(
            Offset.zero,
            ancestor: scrollRender,
          );
          expect(
            julTopLeft.dx,
            greaterThanOrEqualTo(0.0),
            reason: 'Start month $julMonthText must be positioned within bounds at offset 0',
          );

          // Next month (August) must not collide with July.
          final augMonthText = copy.month(DateTime(2026, 8));
          final augFinder = find.text(augMonthText);
          expect(augFinder, findsOneWidget);
          _verifyParagraphGeometry(
            tester,
            augFinder,
            clipViewport: scrollGlobalRect,
            role: 'Reachable month $augMonthText',
          );

          final augRender = tester.renderObject<RenderBox>(augFinder);
          final augTopLeft = augRender.localToGlobal(
            Offset.zero,
            ancestor: scrollRender,
          );
          expect(
            augTopLeft.dx,
            greaterThanOrEqualTo(julTopLeft.dx + julRender.size.width + 4.0),
            reason: '$augMonthText must not overlap $julMonthText',
          );

          // Capture start boundary state if requested.
          await _captureIfRequested(tester, boundaryKey, '${scenario.name}-start');

          // 6. Verify cell count according to real window contract.
          // In a 12-week window ending on Friday 2026-10-09, active days = elapsedDays (82).
          expect(window.elapsedDays, equals(82));
          final cellSemantics = find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('heatmap_day_'),
          );
          expect(
            cellSemantics,
            findsNWidgets(window.elapsedDays),
            reason: 'Active day cell count must match window contract (${window.elapsedDays})',
          );

          // Future dates in that week (e.g. Saturday 2026-10-10) are placeholders without heatmap_day_ key.
          final futureSaturday = HeatmapCalendarWindow.shiftDay(testToday, 1);
          expect(
            find.byKey(
              ValueKey(
                'heatmap_day_${HeatmapCalendarWindow.dateKey(futureSaturday)}',
              ),
            ),
            findsNothing,
            reason: 'Future day placeholders must not contain active day keys',
          );

          // 7. Verify day selection and navigation controls using real scrolling.
          final previousDayFinder = find.byKey(
            const ValueKey('heatmap_previous_day'),
          );
          final nextDayFinder = find.byKey(const ValueKey('heatmap_next_day'));
          final todayFinder = find.byKey(const ValueKey('heatmap_today'));
          final selectedDateFinder = find.byKey(
            const ValueKey('heatmap_selected_date'),
          );

          expect(previousDayFinder, findsOneWidget);
          expect(nextDayFinder, findsOneWidget);
          expect(todayFinder, findsOneWidget);
          expect(selectedDateFinder, findsOneWidget);

          // Verify selected date button stays on one line when it fits full available card content width.
          await _revealVertical(tester, selectedDateFinder);
          _verifyParagraphGeometry(
            tester,
            selectedDateFinder,
            role: 'Selected date label',
          );
          final selectedDateRichTextFinder = find.descendant(
            of: selectedDateFinder,
            matching: find.byType(RichText),
          );
          expect(selectedDateRichTextFinder, findsAtLeastNWidgets(1));
          final selectedDateRichText = tester.renderObject<RenderParagraph>(
            selectedDateRichTextFinder.first,
          );
          final dateTextPainter = TextPainter(
            text: selectedDateRichText.text,
            textDirection: Directionality.of(
              tester.element(selectedDateFinder),
            ),
            textScaler: MediaQuery.textScalerOf(
              tester.element(selectedDateFinder),
            ),
          )..layout();
          final naturalDateWidth = dateTextPainter.width;
          dateTextPainter.dispose();

          final availableCardContentWidth =
              tester.getSize(find.byType(HabitHeatmap)).width;
          if (naturalDateWidth <= availableCardContentWidth - 16.0) {
            final fullSelection = TextSelection(
              baseOffset: 0,
              extentOffset: selectedDateRichText.text.toPlainText().length,
            );
            final boxes = selectedDateRichText.getBoxesForSelection(fullSelection);
            final distinctLineTops = <double>[];
            for (final box in boxes) {
              if (!distinctLineTops.any((top) => (top - box.top).abs() < 1.0)) {
                distinctLineTops.add(box.top);
              }
            }
            expect(
              distinctLineTops.length,
              equals(1),
              reason:
                  'Formatted selected date "${selectedDateRichText.text.toPlainText()}" '
                  'selection boxes must lie on a single line (distinct line tops: $distinctLineTops) '
                  'when natural width ($naturalDateWidth) fits available card content width ($availableCardContentWidth)',
            );

            final renderedPainter = TextPainter(
              text: selectedDateRichText.text,
              textDirection: Directionality.of(
                tester.element(selectedDateFinder),
              ),
              textScaler: MediaQuery.textScalerOf(
                tester.element(selectedDateFinder),
              ),
            )..layout(maxWidth: selectedDateRichText.size.width);
            final lineMetrics = renderedPainter.computeLineMetrics();
            expect(
              lineMetrics.length,
              equals(1),
              reason:
                  'Formatted selected date "${selectedDateRichText.text.toPlainText()}" '
                  'must stay on one line when natural width ($naturalDateWidth) fits '
                  'available card content width ($availableCardContentWidth)',
            );
            renderedPainter.dispose();
          }

          // Next day button is disabled on today.
          final nextButtonWidget = tester.widget<IconButton>(nextDayFinder);
          expect(nextButtonWidget.onPressed, isNull);

          // Reach previous day button with real vertical scrolling before tap.
          await _revealAndTap(tester, previousDayFinder);
          final nextButtonAfter = tester.widget<IconButton>(nextDayFinder);
          expect(nextButtonAfter.onPressed, isNotNull);

          // Reach today button with real vertical scrolling to restore today.
          await _revealAndTap(tester, todayFinder);
          expect(tester.widget<IconButton>(nextDayFinder).onPressed, isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          preferencesProvider?.dispose();
          themeProvider?.dispose();
          tester.view.reset();
          SharedPreferences.setMockInitialValues({});
          I18n.setLocale(initialGlobalLocale);
          debugDisableShadows = previousShadows;
        }
      },
    );
  }

  testWidgets(
    'CalendarHeatmap preserves manual scroll and selection across live brand and locale round trips',
    (tester) async {
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      ThemeProvider? themeProvider;
      PreferencesProvider? preferencesProvider;
      try {
        I18n.setLocale(AppLocale.zh);
        SharedPreferences.setMockInitialValues({
          'active_brand': 'defaultBrand',
          'pref_date_format': 'yyyy-MM-dd',
        });

        await tester.runAsync(() async {
          themeProvider = ThemeProvider();
          await themeProvider!.loadFromStorage();
          preferencesProvider = PreferencesProvider();
          await preferencesProvider!.loadFromStorage();
        });

        final boundaryKey = GlobalKey();
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;

        final testDay = DateTime(2026, 10, 9);
        DateTime? openedDate;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeProvider>.value(
                value: themeProvider!,
              ),
              ChangeNotifierProvider<PreferencesProvider>.value(
                value: preferencesProvider!,
              ),
            ],
            child: Consumer<ThemeProvider>(
              builder: (context, theme, _) => ValueListenableBuilder<AppLocale>(
                valueListenable: I18n.localeListenable,
                builder: (context, currentLocale, _) => MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: Locale(currentLocale == AppLocale.en ? 'en' : 'zh'),
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: theme.brand.theme,
                  builder: (context, child) => RepaintBoundary(
                    key: boundaryKey,
                    child: child!,
                  ),
                  home: Scaffold(
                    body: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: AppSurfaceCard(
                          padding: const EdgeInsets.all(14),
                          child: CalendarHeatmap(
                            window: HeatmapCalendarWindow(
                              weeks: 12,
                              today: testDay,
                            ),
                            title: 'Test Heatmap',
                            describeDay: (d) =>
                                'Day ${HeatmapCalendarWindow.dateKey(d)}',
                            colorForDay: (d) => Colors.green,
                            legend: const Text('Legend'),
                            onOpenDay: (d) => openedDate = d,
                            openDayLabel: (d) =>
                                'Open ${HeatmapCalendarWindow.dateKey(d)}',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _captureIfRequested(tester, boundaryKey, 'live-initial');

        final scrollFinder = find.byKey(const ValueKey('heatmap_scroll'));
        final controller =
            tester.widget<SingleChildScrollView>(scrollFinder).controller!;
        final initialMax = controller.position.maxScrollExtent;
        expect(controller.offset, equals(initialMax));

        // Manually scroll to mid position.
        final targetOffset = (initialMax * 0.4).clamp(10.0, initialMax - 10.0);
        controller.jumpTo(targetOffset);
        await tester.pumpAndSettle();

        // Select target cell (2026-09-15) using real scrolling to ensure it is visible.
        final targetDayKey = 'heatmap_day_2026-09-15';
        final targetDayFinder = find.byKey(ValueKey(targetDayKey));
        await _revealCell(tester, targetDayFinder);
        final postSelectionOffset = controller.offset;

        await tester.tap(targetDayFinder);
        await tester.pumpAndSettle();
        expect(
          controller.offset,
          closeTo(postSelectionOffset, 0.5),
          reason: 'Manual offset must be retained after selection tap',
        );
        expect(
          find.byKey(const ValueKey('heatmap_selected_detail')),
          findsOneWidget,
        );
        expect(find.text('Day 2026-09-15'), findsOneWidget);
        await _captureIfRequested(tester, boundaryKey, 'live-selected');

        // 1. Live theme switch: defaultBrand -> liquidGlass
        await tester.runAsync(() async {
          await themeProvider!.setBrand(AppBrands.liquidGlass.id);
        });
        await tester.pumpAndSettle();

        // Verify controller identity and retained manual horizontal position.
        final controllerAfterTheme =
            tester.widget<SingleChildScrollView>(scrollFinder).controller!;
        expect(
          identical(controllerAfterTheme, controller),
          isTrue,
          reason: 'ScrollController identity must be preserved across rebuilds',
        );
        expect(
          controllerAfterTheme.offset,
          closeTo(postSelectionOffset, 1.0),
          reason: 'Scroll offset must be preserved after theme switch',
        );
        expect(
          find.text('Day 2026-09-15'),
          findsOneWidget,
          reason: 'Selected day detail must be preserved after theme switch',
        );
        await _captureIfRequested(tester, boundaryKey, 'live-theme-switched');

        // 2. Live locale switch: zh -> en
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();

        final controllerAfterLocale =
            tester.widget<SingleChildScrollView>(scrollFinder).controller!;
        expect(
          identical(controllerAfterLocale, controller),
          isTrue,
          reason: 'ScrollController identity must be preserved across locale switch',
        );
        expect(
          controllerAfterLocale.offset,
          closeTo(postSelectionOffset, 1.0),
          reason: 'Scroll offset must be preserved after locale switch',
        );
        expect(
          find.text('Day 2026-09-15'),
          findsOneWidget,
          reason: 'Selected day detail must be preserved after locale switch',
        );
        // English weekday label check
        expect(find.text('Mon'), findsAtLeastNWidgets(1));
        await _captureIfRequested(tester, boundaryKey, 'live-locale-switched');

        // 3. Route state and date picker contract
        final route = ModalRoute.of(tester.element(scrollFinder));
        expect(route?.isCurrent, isTrue, reason: 'Heatmap route is active');

        final selectedDateButton = find.byKey(
          const ValueKey('heatmap_selected_date'),
        );
        await _revealAndTap(tester, selectedDateButton);
        final sheetFinder = find.byType(AppModalSheet);
        expect(sheetFinder, findsOneWidget);
        expect(
          ModalRoute.of(tester.element(sheetFinder)),
          isA<ModalBottomSheetRoute>(),
        );
        expect(
          route?.isCurrent,
          isFalse,
          reason: 'Date picker sheet route is pushed',
        );

        // Cancel date picker sheet
        final cancelFinder = find.descendant(
          of: sheetFinder,
          matching: find.text(I18n.tr('action.cancel')),
        );
        expect(cancelFinder, findsOneWidget);
        await _revealAndTap(tester, cancelFinder);
        expect(find.byType(AppModalSheet), findsNothing);
        expect(
          route?.isCurrent,
          isTrue,
          reason: 'Heatmap route is restored after cancel',
        );
        expect(find.text('Day 2026-09-15'), findsOneWidget);
        expect(
          controller.offset,
          closeTo(postSelectionOffset, 1.0),
          reason: 'Scroll offset must remain preserved after date picker cancel',
        );

        // 4. Open day button contract
        final openDayButton = find.byKey(const ValueKey('heatmap_open_day'));
        await _revealAndTap(tester, openDayButton);
        expect(openedDate, equals(DateTime(2026, 9, 15)));

        // 5. Keyboard navigation contract
        // Re-tap selected Sep 15 cell to restore user focus to the grid and assert Sep 15 is selected.
        await _revealCell(tester, targetDayFinder);
        await tester.tap(targetDayFinder);
        await tester.pumpAndSettle();

        final gridFocusFinder = find.byKey(const ValueKey('heatmap_grid_focus'));
        expect(gridFocusFinder, findsOneWidget);
        final gridFocus = tester.widget<Focus>(gridFocusFinder);
        expect(gridFocus.focusNode, isNotNull);
        if (!gridFocus.focusNode!.hasFocus) {
          gridFocus.focusNode!.requestFocus();
          await tester.pumpAndSettle();
        }
        expect(
          gridFocus.focusNode!.hasFocus,
          isTrue,
          reason: 'Grid focus node must have focus before key events',
        );
        expect(
          find.text('Day 2026-09-15'),
          findsOneWidget,
          reason: 'Sep 15 must remain established before arrow navigation',
        );

        // Arrow down moves +1 day (Sep 15 is Tuesday -> Sep 16 Wednesday)
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(find.text('Day 2026-09-16'), findsOneWidget);

        // Arrow up moves -1 day (Sep 16 Wednesday -> Sep 15 Tuesday)
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(find.text('Day 2026-09-15'), findsOneWidget);

        // End key moves to today (Oct 9)
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pumpAndSettle();
        expect(find.text('Day 2026-10-09'), findsOneWidget);

        // Home key moves to window start (Jul 20)
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pumpAndSettle();
        expect(find.text('Day 2026-07-20'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        preferencesProvider?.dispose();
        themeProvider?.dispose();
        tester.view.reset();
        SharedPreferences.setMockInitialValues({});
        I18n.setLocale(initialGlobalLocale);
        debugDisableShadows = previousShadows;
      }
    },
  );

  testWidgets('MoodHeatmap wrapper works seamlessly with CalendarHeatmap', (
    tester,
  ) async {
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    ThemeProvider? themeProvider;
    PreferencesProvider? preferencesProvider;
    try {
      I18n.setLocale(AppLocale.en);
      SharedPreferences.setMockInitialValues({
        'active_brand': 'defaultBrand',
        'pref_date_format': 'yyyy-MM-dd',
      });
      await tester.runAsync(() async {
        themeProvider = ThemeProvider();
        await themeProvider!.loadFromStorage();
        preferencesProvider = PreferencesProvider();
        await preferencesProvider!.loadFromStorage();
      });

      final boundaryKey = GlobalKey();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;

      DateTime? openedMoodDay;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>.value(
              value: themeProvider!,
            ),
            ChangeNotifierProvider<PreferencesProvider>.value(
              value: preferencesProvider!,
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('en'),
            supportedLocales: const [Locale('en'), Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: themeProvider!.brand.theme,
            builder: (context, child) => RepaintBoundary(
              key: boundaryKey,
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: AppSurfaceCard(
                    padding: const EdgeInsets.all(14),
                    child: MoodHeatmap(
                      entriesByDate: diaryEntries,
                      today: testToday,
                      weeks: 12,
                      onOpenDay: (d) => openedMoodDay = d,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MoodHeatmap), findsOneWidget);
      expect(find.byType(CalendarHeatmap), findsOneWidget);

      // Check legend items inside legend Wrap
      final legendWrap = find.descendant(
        of: find.byType(CalendarHeatmap),
        matching: find.byType(Wrap),
      );
      expect(legendWrap, findsAtLeastNWidgets(1));
      for (final mood in Mood.values) {
        final label = I18n.tr('diary.mood.${mood.name}');
        expect(
          find.descendant(of: legendWrap.first, matching: find.text(label)),
          findsOneWidget,
          reason: 'Legend wrap must contain authentic legend entry for $label',
        );
      }
      expect(
        find.descendant(
          of: legendWrap.first,
          matching: find.text(HeatmapUiCopy(AppLocale.en).noEntry),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: legendWrap.first,
          matching: find.text(HeatmapUiCopy(AppLocale.en).noMood),
        ),
        findsOneWidget,
      );

      // Verify selected day detail reflects today's mood (awesome -> Great)
      final selectedDetailFinder = find.byKey(
        const ValueKey('heatmap_selected_detail'),
      );
      expect(selectedDetailFinder, findsOneWidget);
      final selectedDetailWidget = tester.widget<Text>(selectedDetailFinder);
      expect(
        selectedDetailWidget.data,
        equals(I18n.tr('diary.mood.awesome')),
        reason: 'Selected day detail text must display today mood',
      );
      _verifyParagraphGeometry(
        tester,
        selectedDetailFinder,
        role: 'Selected detail text',
      );

      // Verify today cell semantics is selected
      final todayKey = HeatmapCalendarWindow.dateKey(testToday);
      final todayCellFinder = find.byKey(ValueKey('heatmap_day_$todayKey'));
      expect(todayCellFinder, findsOneWidget);
      final todaySemantics = tester.getSemantics(todayCellFinder);
      expect(todaySemantics.flagsCollection.isSelected.toBoolOrNull(), isTrue);

      // Verify cell count according to real window contract: elapsedDays (82).
      final window = HeatmapCalendarWindow(weeks: 12, today: testToday);
      final moodCells = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('heatmap_day_'),
      );
      expect(moodCells, findsNWidgets(window.elapsedDays));

      // Open day action for mood
      final openDayButton = find.byKey(const ValueKey('heatmap_open_day'));
      await _revealAndTap(tester, openDayButton);
      expect(openedMoodDay, equals(testToday));

      await _captureIfRequested(tester, boundaryKey, 'mood-wrapper');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      preferencesProvider?.dispose();
      themeProvider?.dispose();
      tester.view.reset();
      SharedPreferences.setMockInitialValues({});
      I18n.setLocale(initialGlobalLocale);
      debugDisableShadows = previousShadows;
    }
  });
}
