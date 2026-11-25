// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/calendar_date_navigation.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secondary_route_render_probe.dart'
    show RouteProbeNonlinearScaler;
import '../support/weekly_review_screenshot_font.dart';

Future<void> _pumpBoundedFrames(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _captureScopeScreenshot(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final enabled =
      Platform.environment['DUOYI_CAPTURE_WIDGET_SCREENSHOT'] == '1' ||
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'] != null;
  if (!enabled) return;

  final baseDir =
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'] ??
      'evidence/screenshots/widget-preview-ordinary-calendar-20261024';

  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError(
        'Cannot capture screenshot "$name": RepaintBoundary render object not found for boundaryKey $boundaryKey',
      );
    }
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError(
          'Cannot capture screenshot "$name": image.toByteData returned null',
        );
      }
      final file = File('$baseDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(byteData.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<GlobalKey> _mountPreviewFixture(
  WidgetTester tester, {
  required String brandId,
  required AppLocale locale,
  required Size viewportSize,
  required TextScaler textScaler,
  required Widget child,
}) async {
  SharedPreferences.setMockInitialValues({
    'active_brand': brandId,
    'first_day_of_week': 1,
  });
  I18n.setLocale(locale);
  tester.view.physicalSize = viewportSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final theme = ThemeProvider();
  final preferences = PreferencesProvider();
  await tester.runAsync(() async {
    await theme.loadFromStorage();
    await loadWeeklyReviewScreenshotFonts();
  });
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    theme.dispose();
    preferences.dispose();
  });

  // Assert actual loaded/committed ThemeProvider brand and activeWidgetBackgroundBrand
  final expectedBrand =
      brandId == 'defaultBrand' ? AppBrands.defaultBrand : AppBrands.liquidGlass;
  expect(
    theme.brand.id,
    equals(expectedBrand.id),
    reason: 'ThemeProvider brand must match expected $brandId',
  );
  expect(
    theme.activeWidgetBackgroundBrand.id,
    equals(expectedBrand.id),
    reason:
        'ThemeProvider activeWidgetBackgroundBrand must match expected $brandId',
  );

  final boundaryKey = GlobalKey();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
      ],
      child: ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (context, currentLocale, _) => MaterialApp(
          locale: Locale(currentLocale == AppLocale.en ? 'en' : 'zh'),
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: theme.brand.theme,
          builder: (context, childWidget) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: textScaler,
            ),
            child: RepaintBoundary(key: boundaryKey, child: childWidget!),
          ),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: SingleChildScrollView(
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _pumpBoundedFrames(tester);

  // Assert Theme.of(actualsurface).primary vs real AppBrands expected
  final surfaceFinder = find.byKey(const ValueKey('widget_preview_surface'));
  expect(surfaceFinder, findsOneWidget);
  final surfaceElement = tester.element(surfaceFinder);
  final surfaceTheme = Theme.of(surfaceElement);
  expect(
    surfaceTheme.colorScheme.primary,
    equals(expectedBrand.theme.colorScheme.primary),
    reason:
        'Actual surface Theme primary color must match real $brandId AppBrand theme primary',
  );

  return boundaryKey;
}

void _assertPreviewCardWidth(
  WidgetTester tester, {
  required String brandId,
  required double viewportWidth,
  required WidgetDisplayMode displayMode,
}) {
  final surfaceFinder = find.byKey(const ValueKey('widget_preview_surface'));
  expect(surfaceFinder, findsOneWidget);

  final previewMaxWidth = displayMode.previewMaxWidth;
  final expectedCardWidth =
      viewportWidth < previewMaxWidth ? viewportWidth : previewMaxWidth;
  // Ink includes BoxDecoration.border padding; liquidGlass preview card has 1.0dp border on each side (2.0dp total).
  final outerBorderPadding = brandId == 'liquidGlass' ? 2.0 : 0.0;
  final expectedBodyWidth = expectedCardWidth - 24.0 - outerBorderPadding;

  final surfaceBox = tester.renderObject<RenderBox>(surfaceFinder);
  expect(
    surfaceBox.size.width,
    closeTo(expectedCardWidth, 1e-7),
    reason:
        'Surface width (${surfaceBox.size.width}) must match expected $expectedCardWidth for $brandId on ${viewportWidth}px viewport',
  );

  final contentFrameFinder = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_WidgetPreviewContentFrame',
  );
  expect(
    contentFrameFinder,
    findsOneWidget,
    reason: 'Content frame must exist for width verification',
  );
  final contentBox = tester.renderObject<RenderBox>(contentFrameFinder);
  expect(
    contentBox.size.width,
    closeTo(expectedBodyWidth, 1e-7),
    reason:
        'Content area width (${contentBox.size.width}) must match expected $expectedBodyWidth (outer glass border padding $outerBorderPadding accounted for) for $brandId on ${viewportWidth}px viewport',
  );
}

Future<void> _revealAndAssertReadableParagraph(
  WidgetTester tester, {
  required Finder textFinder,
  required Finder surfaceFinder,
  required GlobalKey boundaryKey,
  required String role,
  Finder? rowFinder,
}) async {
  expect(textFinder, findsOneWidget, reason: '$role must be present (no vacuity)');
  final element = tester.element(textFinder);
  final scrollable = Scrollable.maybeOf(element, axis: Axis.vertical);
  if (scrollable != null) {
    await scrollable.position.ensureVisible(element.findRenderObject()!);
    await _pumpBoundedFrames(tester);
  }
  _assertReadableParagraph(
    tester,
    textFinder: textFinder,
    surfaceFinder: surfaceFinder,
    boundaryKey: boundaryKey,
    role: role,
    rowFinder: rowFinder,
  );
}

void _assertReadableParagraph(
  WidgetTester tester, {
  required Finder textFinder,
  required Finder surfaceFinder,
  required GlobalKey boundaryKey,
  required String role,
  Finder? rowFinder,
}) {
  expect(textFinder, findsOneWidget, reason: '$role must be present (no vacuity)');
  final richTextFinder = find.descendant(
    of: textFinder,
    matching: find.byType(RichText),
  );
  final paragraph = tester.renderObject<RenderParagraph>(
    richTextFinder.evaluate().isNotEmpty ? richTextFinder : textFinder,
  );

  // 1. Must not exceed maxLines (real RenderParagraph didExceedMaxLines geometry assertion)
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '$role didExceedMaxLines must be false (no line truncation)',
  );

  final text = paragraph.text.toPlainText();
  expect(text, isNotEmpty, reason: '$role text must not be empty');

  final renderBoundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final surfaceBox = tester.renderObject<RenderBox>(surfaceFinder);
  final surfaceRect = MatrixUtils.transformRect(
    surfaceBox.getTransformTo(renderBoundary),
    Offset.zero & surfaceBox.size,
  );

  RenderBox? rowBox;
  Rect? rowRect;
  if (rowFinder != null) {
    rowBox = tester.renderObject<RenderBox>(rowFinder);
    rowRect = MatrixUtils.transformRect(
      rowBox.getTransformTo(renderBoundary),
      Offset.zero & rowBox.size,
    );
  }

  // 2. Verify token glyph ink boxes fit within layout bounds
  final tokens = RegExp(r'\S+').allMatches(text);
  expect(
    tokens,
    isNotEmpty,
    reason: '$role must contain non-whitespace tokens to lay out',
  );
  for (final match in tokens) {
    final tokenBoxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: match.start, extentOffset: match.end),
    );
    expect(
      tokenBoxes,
      isNotEmpty,
      reason: '$role glyph boxes for token "${match.group(0)}" must be laid out',
    );
    for (final box in tokenBoxes) {
      expect(
        box.top,
        greaterThanOrEqualTo(-0.5),
        reason:
            '$role token "${match.group(0)}" glyph box top ${box.top} must be inside paragraph allocated height',
      );
      expect(
        box.bottom,
        lessThanOrEqualTo(paragraph.size.height + 0.5),
        reason:
            '$role token "${match.group(0)}" glyph box bottom ${box.bottom} must be inside paragraph allocated height ${paragraph.size.height}',
      );
      expect(
        box.left,
        greaterThanOrEqualTo(-0.5),
        reason:
            '$role token "${match.group(0)}" glyph box left ${box.left} must be inside paragraph allocated width',
      );
      expect(
        box.right,
        lessThanOrEqualTo(paragraph.size.width + 0.5),
        reason:
            '$role token "${match.group(0)}" glyph box right ${box.right} must be inside paragraph allocated width ${paragraph.size.width}',
      );

      final glyphRect = MatrixUtils.transformRect(
        paragraph.getTransformTo(renderBoundary),
        Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
      );
      expect(
        surfaceRect.inflate(0.5).contains(glyphRect.topLeft),
        isTrue,
        reason:
            '$role glyph top-left $glyphRect must be within painted surface $surfaceRect',
      );
      expect(
        surfaceRect.inflate(0.5).contains(glyphRect.bottomRight),
        isTrue,
        reason:
            '$role glyph bottom-right $glyphRect must be within painted surface $surfaceRect',
      );

      if (rowRect != null) {
        expect(
          rowRect.inflate(0.5).contains(glyphRect.topLeft),
          isTrue,
          reason: '$role glyph top-left must be within allocated row bounds $rowRect',
        );
        expect(
          rowRect.inflate(0.5).contains(glyphRect.bottomRight),
          isTrue,
          reason: '$role glyph bottom-right must be within allocated row bounds $rowRect',
        );
      }
    }
  }

  // 3. Full text selection boxes must not be empty and must fit within painted surface bounds
  final fullBoxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  expect(
    fullBoxes,
    isNotEmpty,
    reason: '$role full text selection boxes must not be empty',
  );
  for (final box in fullBoxes) {
    expect(
      box.top,
      greaterThanOrEqualTo(-0.5),
      reason:
          '$role selection box top ${box.top} must be inside paragraph allocated height',
    );
    expect(
      box.bottom,
      lessThanOrEqualTo(paragraph.size.height + 0.5),
      reason:
          '$role selection box bottom ${box.bottom} must be inside paragraph allocated height ${paragraph.size.height}',
    );
    final fullBoxRect = MatrixUtils.transformRect(
      paragraph.getTransformTo(renderBoundary),
      Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
    );
    expect(
      surfaceRect.inflate(1.0).contains(fullBoxRect.topLeft),
      isTrue,
      reason:
          '$role selection top-left $fullBoxRect must be within painted surface $surfaceRect',
    );
    expect(
      surfaceRect.inflate(1.0).contains(fullBoxRect.bottomRight),
      isTrue,
      reason:
          '$role selection bottom-right $fullBoxRect must be within painted surface $surfaceRect',
    );
  }
}

Future<void> _assertReadableScheduleBody(
  WidgetTester tester, {
  required GlobalKey boundaryKey,
  required Finder surfaceFinder,
  required String brandId,
  required AppLocale locale,
  required String scenario,
}) async {
  // Line 1: scheduleItem1
  final item1Finder = find.text(WidgetUiCopy.scheduleItem1);
  expect(item1Finder, findsOneWidget, reason: 'Schedule line 1 must exist ($scenario)');
  await _revealAndAssertReadableParagraph(
    tester,
    textFinder: item1Finder,
    surfaceFinder: surfaceFinder,
    boundaryKey: boundaryKey,
    role: 'Schedule line 1 ($scenario)',
  );

  // Line 2: scheduleItem2
  final item2Finder = find.text(WidgetUiCopy.scheduleItem2);
  expect(item2Finder, findsOneWidget, reason: 'Schedule line 2 must exist ($scenario)');
  await _revealAndAssertReadableParagraph(
    tester,
    textFinder: item2Finder,
    surfaceFinder: surfaceFinder,
    boundaryKey: boundaryKey,
    role: 'Schedule line 2 ($scenario)',
  );
}

Future<void> _assertReadableCalendarBody(
  WidgetTester tester, {
  required GlobalKey boundaryKey,
  required Finder surfaceFinder,
  required String brandId,
  required AppLocale locale,
  required String scenario,
}) async {
  final monthHeaderStr = WidgetUiCopy.calendarMonthHeader(2026, 5);
  final monthHeaderFinder = find.text(monthHeaderStr);

  if (monthHeaderFinder.evaluate().isNotEmpty) {
    // 1. Month Header
    await _revealAndAssertReadableParagraph(
      tester,
      textFinder: monthHeaderFinder,
      surfaceFinder: surfaceFinder,
      boundaryKey: boundaryKey,
      role: 'Calendar month header ($scenario)',
    );

    // 2. Today Button / Chip
    final todayFinder = find.text(WidgetUiCopy.calendarToday);
    await _revealAndAssertReadableParagraph(
      tester,
      textFinder: todayFinder,
      surfaceFinder: surfaceFinder,
      boundaryKey: boundaryKey,
      role: 'Calendar today chip ($scenario)',
    );

    // 3. Weekday labels row
    final weekLabels = [
      for (final iso in CalendarDateNavigation.orderedWeekdays(1))
        WidgetUiCopy.calendarWeekLabels[iso - 1],
    ];
    final firstWeekdayFinder = find.text(weekLabels.first);
    expect(
      firstWeekdayFinder,
      findsWidgets,
      reason: 'First weekday label must exist in weekday row ($scenario)',
    );
    final weekdayRowFinder = find.ancestor(
      of: firstWeekdayFinder.first,
      matching: find.byType(Row),
    ).first;
    expect(
      weekdayRowFinder,
      findsOneWidget,
      reason: 'Weekday row must exist ($scenario)',
    );

    final weekdayTexts = find.descendant(
      of: weekdayRowFinder,
      matching: find.byType(Text),
    );
    expect(
      weekdayTexts.evaluate().length,
      equals(7),
      reason: 'Weekday row must display exactly 7 day labels ($scenario)',
    );
    for (var i = 0; i < 7; i++) {
      _assertReadableParagraph(
        tester,
        textFinder: weekdayTexts.at(i),
        surfaceFinder: surfaceFinder,
        boundaryKey: boundaryKey,
        role: 'Calendar weekday label #$i (${weekLabels[i]}) ($scenario)',
      );
    }

    // 4. Rendered calendar day cells:
    final dayCellFinder = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_WidgetPreviewCalendarCell',
    );
    final cellCount = dayCellFinder.evaluate().length;
    expect(
      cellCount,
      greaterThanOrEqualTo(7),
      reason: 'Calendar must display at least one week row ($scenario)',
    );

    // Day 17 is today (currentWeekIndex has highest priority), so day 17 is guaranteed
    // to be rendered if any week is displayed.
    final day17Finder = find.text('17');
    expect(
      day17Finder,
      findsOneWidget,
      reason: 'Today day 17 must be present in visible weeks ($scenario)',
    );
    await _revealAndAssertReadableParagraph(
      tester,
      textFinder: day17Finder,
      surfaceFinder: surfaceFinder,
      boundaryKey: boundaryKey,
      role: 'Calendar today day 17 cell ($scenario)',
    );

    // For every non-empty day cell rendered, assert valid day number and readable paragraph
    final cellTexts = find.descendant(
      of: dayCellFinder,
      matching: find.byType(Text),
    );
    var renderedDayCount = 0;
    for (var i = 0; i < cellTexts.evaluate().length; i++) {
      final textWidget = tester.widget<Text>(cellTexts.at(i));
      final textData = textWidget.data ?? '';
      if (textData.isEmpty) continue;
      final dayNumber = int.tryParse(textData);
      expect(
        dayNumber,
        isNotNull,
        reason: 'Day cell text "$textData" must be a valid integer ($scenario)',
      );
      expect(
        dayNumber,
        inInclusiveRange(1, 31),
        reason: 'Day cell "$textData" must be in May 1..31 ($scenario)',
      );
      renderedDayCount++;
      _assertReadableParagraph(
        tester,
        textFinder: cellTexts.at(i),
        surfaceFinder: surfaceFinder,
        boundaryKey: boundaryKey,
        role: 'Calendar day $dayNumber cell ($scenario)',
      );
    }
    expect(
      renderedDayCount,
      greaterThanOrEqualTo(7),
      reason: 'At least 7 days must be rendered in visible weeks ($scenario)',
    );
  } else {
    // Fallback mode when cells do not fit or height is constrained
    final fullDateFinder = find.text(WidgetUiCopy.calendarCurrentDate);
    final compactDateFinder = find.text(WidgetUiCopy.calendarCurrentDay);
    final fallbackFinder =
        fullDateFinder.evaluate().isNotEmpty ? fullDateFinder : compactDateFinder;
    expect(
      fallbackFinder,
      findsOneWidget,
      reason: 'Calendar fallback date must be present ($scenario)',
    );
    await _revealAndAssertReadableParagraph(
      tester,
      textFinder: fallbackFinder,
      surfaceFinder: surfaceFinder,
      boundaryKey: boundaryKey,
      role: 'Calendar fallback date ($scenario)',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final initialLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialLocale));

  group('WidgetPreviewOrdinaryCalendarPriorityTest - Schedule Ordinary and Landscape', () {
    for (final brandId in ['defaultBrand', 'liquidGlass']) {
      for (final locale in [AppLocale.zh, AppLocale.en]) {
        testWidgets(
          'Schedule readable at ordinary scale 1.0 in $brandId $locale',
          (tester) async {
            final platform =
                brandId == 'defaultBrand' ? TargetPlatform.iOS : TargetPlatform.android;
            const viewportSize = Size(390, 844);

            final boundary = await _mountPreviewFixture(
              tester,
              brandId: brandId,
              locale: locale,
              viewportSize: viewportSize,
              textScaler: const TextScaler.linear(1.0),
              child: WidgetPreviewCard.schedule(
                displayMode: WidgetDisplayMode.standard,
                platformOverride: platform,
              ),
            );

            _assertPreviewCardWidth(
              tester,
              brandId: brandId,
              viewportWidth: viewportSize.width,
              displayMode: WidgetDisplayMode.standard,
            );

            final surfaceFinder = find.byKey(
              const ValueKey('widget_preview_surface'),
            );
            expect(surfaceFinder, findsOneWidget);

            await _assertReadableScheduleBody(
              tester,
              boundaryKey: boundary,
              surfaceFinder: surfaceFinder,
              brandId: brandId,
              locale: locale,
              scenario: 'Schedule ordinary ($brandId, $locale, ${platform.name})',
            );

            await _captureScopeScreenshot(
              tester,
              boundary,
              'schedule_ordinary_${brandId}_${locale.name}_${platform.name}',
            );
          },
        );

        testWidgets(
          'Schedule readable in landscape layout in $brandId $locale',
          (tester) async {
            final platform =
                brandId == 'defaultBrand' ? TargetPlatform.android : TargetPlatform.iOS;
            const viewportSize = Size(844, 390);

            final boundary = await _mountPreviewFixture(
              tester,
              brandId: brandId,
              locale: locale,
              viewportSize: viewportSize,
              textScaler: const TextScaler.linear(1.0),
              child: WidgetPreviewCard.schedule(
                displayMode: WidgetDisplayMode.standard,
                platformOverride: platform,
              ),
            );

            _assertPreviewCardWidth(
              tester,
              brandId: brandId,
              viewportWidth: viewportSize.width,
              displayMode: WidgetDisplayMode.standard,
            );

            final surfaceFinder = find.byKey(
              const ValueKey('widget_preview_surface'),
            );
            expect(surfaceFinder, findsOneWidget);

            await _assertReadableScheduleBody(
              tester,
              boundaryKey: boundary,
              surfaceFinder: surfaceFinder,
              brandId: brandId,
              locale: locale,
              scenario: 'Schedule landscape ($brandId, $locale, ${platform.name})',
            );

            await _captureScopeScreenshot(
              tester,
              boundary,
              'schedule_landscape_${brandId}_${locale.name}_${platform.name}',
            );
          },
        );
      }
    }
  });

  group('WidgetPreviewOrdinaryCalendarPriorityTest - Calendar Scaled Representations', () {
    for (final brandId in ['defaultBrand', 'liquidGlass']) {
      for (final locale in [AppLocale.zh, AppLocale.en]) {
        testWidgets(
          'Calendar readable at 320x844 with 200% text scale in $brandId $locale',
          (tester) async {
            final platform =
                brandId == 'defaultBrand' ? TargetPlatform.iOS : TargetPlatform.android;
            const viewportSize = Size(320, 844);

            final boundary = await _mountPreviewFixture(
              tester,
              brandId: brandId,
              locale: locale,
              viewportSize: viewportSize,
              textScaler: const TextScaler.linear(2.0),
              child: WidgetPreviewCard.calendar(
                displayMode: WidgetDisplayMode.standard,
                platformOverride: platform,
              ),
            );

            _assertPreviewCardWidth(
              tester,
              brandId: brandId,
              viewportWidth: viewportSize.width,
              displayMode: WidgetDisplayMode.standard,
            );

            final surfaceFinder = find.byKey(
              const ValueKey('widget_preview_surface'),
            );
            expect(surfaceFinder, findsOneWidget);

            await _assertReadableCalendarBody(
              tester,
              boundaryKey: boundary,
              surfaceFinder: surfaceFinder,
              brandId: brandId,
              locale: locale,
              scenario: 'Calendar 320x844 200% ($brandId, $locale, ${platform.name})',
            );

            await _captureScopeScreenshot(
              tester,
              boundary,
              'calendar_320x844_200pct_${brandId}_${locale.name}_${platform.name}',
            );
          },
        );

        testWidgets(
          'Calendar readable under RouteProbeNonlinearScaler in $brandId $locale',
          (tester) async {
            final platform =
                brandId == 'defaultBrand' ? TargetPlatform.android : TargetPlatform.iOS;
            const viewportSize = Size(332, 844);

            final boundary = await _mountPreviewFixture(
              tester,
              brandId: brandId,
              locale: locale,
              viewportSize: viewportSize,
              textScaler: const RouteProbeNonlinearScaler(),
              child: WidgetPreviewCard.calendar(
                displayMode: WidgetDisplayMode.standard,
                platformOverride: platform,
              ),
            );

            _assertPreviewCardWidth(
              tester,
              brandId: brandId,
              viewportWidth: viewportSize.width,
              displayMode: WidgetDisplayMode.standard,
            );

            final surfaceFinder = find.byKey(
              const ValueKey('widget_preview_surface'),
            );
            expect(surfaceFinder, findsOneWidget);

            await _assertReadableCalendarBody(
              tester,
              boundaryKey: boundary,
              surfaceFinder: surfaceFinder,
              brandId: brandId,
              locale: locale,
              scenario: 'Calendar 332 nonlinear ($brandId, $locale, ${platform.name})',
            );

            await _captureScopeScreenshot(
              tester,
              boundary,
              'calendar_332_nonlinear_${brandId}_${locale.name}_${platform.name}',
            );
          },
        );
      }
    }
  });
}
