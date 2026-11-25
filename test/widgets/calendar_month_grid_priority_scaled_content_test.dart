// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/calendar_agenda_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/widgets/calendar_month_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/weekly_review_screenshot_font.dart';

class _MonthGridScenario {
  final String name;
  final AppLocale locale;
  final String brandId;
  final Size size;
  final double scale;
  final double devicePixelRatio;
  final bool showLunar;

  const _MonthGridScenario({
    required this.name,
    required this.locale,
    required this.brandId,
    required this.size,
    required this.scale,
    required this.devicePixelRatio,
    this.showLunar = true,
  });
}

const _scenarios = <_MonthGridScenario>[
  _MonthGridScenario(
    name: 'zh-portrait-320x844-dpr2-defaultBrand',
    locale: AppLocale.zh,
    brandId: 'defaultBrand',
    size: Size(320, 844),
    scale: 2.0,
    devicePixelRatio: 2.0,
    showLunar: true,
  ),
  _MonthGridScenario(
    name: 'en-portrait-320x844-dpr2-liquidGlass',
    locale: AppLocale.en,
    brandId: 'liquidGlass',
    size: Size(320, 844),
    scale: 2.0,
    devicePixelRatio: 2.0,
    showLunar: false,
  ),
  _MonthGridScenario(
    name: 'zh-landscape-844x390-dpr1-liquidGlass',
    locale: AppLocale.zh,
    brandId: 'liquidGlass',
    size: Size(844, 390),
    scale: 1.0,
    devicePixelRatio: 1.0,
    showLunar: true,
  ),
  _MonthGridScenario(
    name: 'en-landscape-844x390-dpr1-defaultBrand',
    locale: AppLocale.en,
    brandId: 'defaultBrand',
    size: Size(844, 390),
    scale: 1.0,
    devicePixelRatio: 1.0,
    showLunar: false,
  ),
];

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final explicitDir =
      Platform.environment['DUOYI_RETAINED_DIALOG_SCREENSHOT_DIR'] ??
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
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
      final file = File('$explicitDir/calendar-month-grid-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  setUpAll(() async {
    if (File('assets/fonts/DroidSansFallbackFull.ttf').existsSync() &&
        File('assets/fonts/DejaVuSans.ttf').existsSync()) {
      await loadWeeklyReviewScreenshotFonts();
    }
  });

  for (final scenario in _scenarios) {
    testWidgets('CalendarMonthGrid priority scaled content ${scenario.name}', (
      tester,
    ) async {
      I18n.setLocale(scenario.locale);
      final brand = scenario.brandId == 'liquidGlass'
          ? AppBrands.liquidGlass
          : AppBrands.defaultBrand;

      final boundaryKey = GlobalKey();
      tester.view.physicalSize = scenario.size * scenario.devicePixelRatio;
      tester.view.devicePixelRatio = scenario.devicePixelRatio;
      addTearDown(() => tester.view.reset());

      DateTime? selectedDate;
      final focusedMonth = DateTime(2027, 6, 1); // 5-week month
      final initialSelected = DateTime(2027, 6, 15);
      final today = DateTime.now();

      final dateEventTypes = <String, List<CalendarEventType>>{
        '2027-06-10': [CalendarEventType.todo],
        '2027-06-15': [
          CalendarEventType.todo,
          CalendarEventType.event,
          CalendarEventType.habit,
        ],
        '2027-06-20': [CalendarEventType.event, CalendarEventType.anniversary],
      };
      final dateEventCounts = <String, int>{
        '2027-06-10': 1,
        '2027-06-15': 3,
        '2027-06-20': 2,
      };

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: Locale(scenario.locale == AppLocale.en ? 'en' : 'zh'),
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: brand.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              size: scenario.size,
              textScaler: TextScaler.linear(scenario.scale),
            ),
            child: RepaintBoundary(key: boundaryKey, child: child!),
          ),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: scenario.size.width - 24,
                child: CalendarMonthGrid(
                  focusedMonth: focusedMonth,
                  selectedDay: initialSelected,
                  dateEventTypes: dateEventTypes,
                  dateEventCounts: dateEventCounts,
                  showLunar: scenario.showLunar,
                  onDaySelected: (d) => selectedDate = d,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 1. Verify full numeric civil dates (1..30 for June 2027)
      for (var day = 1; day <= 30; day++) {
        final dayFinder = find.text('$day');
        expect(
          dayFinder,
          findsOneWidget,
          reason: 'Day $day must be present in June 2027 grid',
        );
      }

      // 2. Verify weekday initials row
      final weekdayInitials = CalendarAgendaUiCopy.weekdayInitialsFor(
        DateTime.monday,
      );
      for (final initial in weekdayInitials) {
        expect(find.text(initial), findsAtLeastNWidgets(1));
      }

      // 3. Verify event count badge on day with count > 1
      // '2027-06-15' has 3 events
      final badgeText = CalendarAgendaUiCopy.monthEventBadge(3);
      final badgeFinder = find.text(badgeText);
      expect(badgeFinder, findsOneWidget);
      expect(tester.takeException(), isNull);

      // 4. Verify day callback interaction
      final day18Finder = find.text('18');
      expect(day18Finder, findsOneWidget);
      await tester.tap(day18Finder);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(selectedDate, equals(DateTime(2027, 6, 18)));

      // 5. Verify today state if in current month
      final isCurrentMonth =
          today.year == focusedMonth.year && today.month == focusedMonth.month;
      if (isCurrentMonth) {
        expect(find.text('${today.day}'), findsOneWidget);
      }

      await _capture(tester, boundaryKey, '${scenario.name}-5weeks');
    });

    testWidgets(
      'CalendarMonthGrid 6-week month and tight bounded scrolling ${scenario.name}',
      (tester) async {
        I18n.setLocale(scenario.locale);
        final brand = scenario.brandId == 'liquidGlass'
            ? AppBrands.liquidGlass
            : AppBrands.defaultBrand;

        final boundaryKey = GlobalKey();
        tester.view.physicalSize = scenario.size * scenario.devicePixelRatio;
        tester.view.devicePixelRatio = scenario.devicePixelRatio;
        addTearDown(() => tester.view.reset());

        DateTime? tappedDate;
        // August 2027 spans 6 weeks (Aug 1 is Sunday)
        final focusedMonth = DateTime(2027, 8, 1);
        final initialSelected = DateTime(2027, 8, 15);

        final dateEventTypes = <String, List<CalendarEventType>>{
          '2027-08-01': [CalendarEventType.todo, CalendarEventType.event],
          '2027-08-31': [CalendarEventType.diary],
        };
        final dateEventCounts = <String, int>{'2027-08-01': 2, '2027-08-31': 1};

        // Mount inside a tight bounded box (height: 220) to exercise bounded scrolling
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: Locale(scenario.locale == AppLocale.en ? 'en' : 'zh'),
            supportedLocales: const [Locale('en'), Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: brand.theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                size: scenario.size,
                textScaler: TextScaler.linear(scenario.scale),
              ),
              child: RepaintBoundary(key: boundaryKey, child: child!),
            ),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: scenario.size.width - 24,
                  height: 220,
                  child: CalendarMonthGrid(
                    focusedMonth: focusedMonth,
                    selectedDay: initialSelected,
                    dateEventTypes: dateEventTypes,
                    dateEventCounts: dateEventCounts,
                    showLunar: scenario.showLunar,
                    onDaySelected: (d) => tappedDate = d,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Day 1 must be present
        expect(find.text('1'), findsOneWidget);

        // Tap day 1
        await tester.tap(find.text('1'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tappedDate, equals(DateTime(2027, 8, 1)));

        // Verify pinned weekday initials are visible and hit-testable before scrolling
        final weekdayInitials = CalendarAgendaUiCopy.weekdayInitialsFor(
          DateTime.monday,
        );
        for (final initial in weekdayInitials) {
          expect(find.text(initial).hitTestable(), findsAtLeastNWidgets(1));
        }

        // If bounded height is tight, scrolling down allows reaching day 31
        final day31Finder = find.text('31');
        if (find.byType(Scrollable).evaluate().isNotEmpty) {
          await tester.scrollUntilVisible(
            day31Finder,
            50,
            scrollable: find.byType(Scrollable),
          );
        }
        expect(day31Finder.hitTestable(), findsOneWidget);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(day31Finder, findsOneWidget);

        // Pinned weekday initials remain visible and hit-testable after scrolling down to week 6
        for (final initial in weekdayInitials) {
          expect(find.text(initial).hitTestable(), findsAtLeastNWidgets(1));
        }

        await _capture(tester, boundaryKey, '${scenario.name}-6weeks-bounded');
      },
    );

    testWidgets(
      'CalendarMonthGrid event-before-lunar priority monotonicity across bounded transitional heights ${scenario.name}',
      (tester) async {
        I18n.setLocale(scenario.locale);
        final brand = scenario.brandId == 'liquidGlass'
            ? AppBrands.liquidGlass
            : AppBrands.defaultBrand;

        tester.view.physicalSize = scenario.size * scenario.devicePixelRatio;
        tester.view.devicePixelRatio = scenario.devicePixelRatio;
        addTearDown(() => tester.view.reset());

        final focusedMonth = DateTime(2027, 6, 1);
        final selectedDay = DateTime(2027, 6, 15);

        // Day 15 has 2 events
        final dateEventTypes = <String, List<CalendarEventType>>{
          '2027-06-15': [CalendarEventType.todo, CalendarEventType.event],
        };
        final dateEventCounts = <String, int>{'2027-06-15': 2};

        // Test across multiple transitional bounded heights: tight (240), medium (320), full (520)
        for (final testHeight in [
          240.0,
          320.0,
          scenario.size.height > 544 ? 520.0 : scenario.size.height - 24,
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: Locale(scenario.locale == AppLocale.en ? 'en' : 'zh'),
              supportedLocales: const [Locale('en'), Locale('zh')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: brand.theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: scenario.size,
                  textScaler: TextScaler.linear(scenario.scale),
                ),
                child: child!,
              ),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: scenario.size.width - 24,
                    height: testHeight,
                    child: CalendarMonthGrid(
                      focusedMonth: focusedMonth,
                      selectedDay: selectedDay,
                      dateEventTypes: dateEventTypes,
                      dateEventCounts: dateEventCounts,
                      showLunar: scenario.showLunar,
                      onDaySelected: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // Day 15 numeric date is always visible
          expect(
            find.text('15'),
            findsOneWidget,
            reason: 'Day 15 must always be visible at height $testHeight',
          );

          // Priority monotonicity contract: Event indicators are never suppressed by lunar subtext
          final badgeFinder = find.text(
            CalendarAgendaUiCopy.monthEventBadge(2),
          );
          final selectedCell = find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.button == true &&
                widget.properties.selected == true,
          );
          expect(selectedCell, findsOneWidget);
          final eventDots = find.descendant(
            of: selectedCell,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.constraints?.maxWidth == 4 &&
                  widget.constraints?.maxHeight == 4,
            ),
          );
          expect(
            badgeFinder.evaluate().isNotEmpty ||
                eventDots.evaluate().isNotEmpty,
            isTrue,
            reason: 'Scheduled event indicator must survive height $testHeight',
          );
          final scrollable = find.byType(Scrollable);
          if (scrollable.evaluate().isNotEmpty) {
            await tester.ensureVisible(find.text('15'));
            await tester.pumpAndSettle();
          }
          expect(find.text('15').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}
