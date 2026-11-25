// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
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

Future<void> _captureBoundedHeightScreenshot(
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
      'evidence/screenshots/widget-preview-height-contract-20261024';

  await tester.runAsync(() async {
    final context = boundaryKey.currentContext;
    if (context == null) {
      throw StateError(
        'missing boundary: BuildContext not found for screenshot "$name"',
      );
    }
    final boundary = context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError(
        'missing boundary: RenderRepaintBoundary not found for "$name"',
      );
    }
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError(
          'encoding: failed to encode PNG for screenshot "$name"',
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

Future<GlobalKey> _mountDynamicBoundedFixture(
  WidgetTester tester, {
  required String brandId,
  required AppLocale locale,
  required Size viewportSize,
  required TextScaler textScaler,
  required ValueNotifier<double> heightNotifier,
  required Widget childCard,
}) async {
  SharedPreferences.setMockInitialValues({'active_brand': brandId});
  I18n.setLocale(locale);
  tester.view.physicalSize = viewportSize;
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

  // Verify actual committed ThemeProvider brand matches target brand.
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
              child: ValueListenableBuilder<double>(
                valueListenable: heightNotifier,
                builder: (context, currentHeight, _) => SizedBox(
                  width: 320,
                  height: currentHeight,
                  child: childCard,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _pumpBoundedFrames(tester);

  // Assert actual surface Theme primary color matches real AppBrand theme primary.
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

// Measure the entire rendered row, including its control, row padding, and
// containing slot. The text paragraph alone does not describe row height.
({Rect rect, double bottomInset}) _measureRow(
  WidgetTester tester, Finder textFinder, RenderBox surface,
) {
  final rowFinder = find.ancestor(of: textFinder, matching: find.byType(Row)).first;
  RenderBox row = tester.renderObject<RenderBox>(rowFinder);
  while (row.parent != null &&
      !(row.parent is RenderFlex &&
          (row.parent! as RenderFlex).direction == Axis.vertical)) {
    row = row.parent! as RenderBox;
  }
  final column = row.parent! as RenderFlex;
  final rowRect = MatrixUtils.transformRect(
    row.getTransformTo(surface), Offset.zero & row.size,
  );
  final columnRect = MatrixUtils.transformRect(
    column.getTransformTo(surface), Offset.zero & column.size,
  );
  final inset = surface.size.height - columnRect.bottom;
  expect(inset, greaterThanOrEqualTo(0));
  return (rect: rowRect, bottomInset: inset);
}

void _assertReadableParagraph(
  WidgetTester tester, {
  required Finder textFinder,
  required Finder surfaceFinder,
  required GlobalKey boundaryKey,
  required String role,
}) {
  expect(textFinder, findsOneWidget, reason: '$role must be present (no vacuity)');
  final rich = find.descendant(of: textFinder, matching: find.byType(RichText));
  final paragraph = tester.renderObject<RenderParagraph>(rich);
  expect(paragraph.didExceedMaxLines, isFalse, reason: '$role must not truncate');
  final text = paragraph.text.toPlainText();
  expect(text.trim(), isNotEmpty);
  final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final surface = tester.renderObject<RenderBox>(surfaceFinder);
  final surfaceRect = MatrixUtils.transformRect(
    surface.getTransformTo(boundary), Offset.zero & surface.size,
  );
  final screen = Offset.zero & boundary.size;
  final visible = surfaceRect.intersect(screen);
  var offset = 0;
  var count = 0;
  for (final rune in text.runes) {
    final glyph = String.fromCharCode(rune);
    final start = offset;
    offset += glyph.length;
    if (glyph.trim().isEmpty) continue;
    count++;
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: offset),
    );
    expect(boxes, isNotEmpty, reason: '$role missing glyph $glyph');
    for (final box in boxes) {
      // Font selection boxes can extend into normal leading outside the
      // paragraph's allocated height. The surface and viewport actually clip.
      expect(box.left, greaterThanOrEqualTo(-0.5), reason: '$role $glyph');
      expect(box.right, lessThanOrEqualTo(paragraph.size.width + 0.5), reason: '$role $glyph');
      final rect = MatrixUtils.transformRect(
        paragraph.getTransformTo(boundary),
        Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
      );
      expect(visible.inflate(0.5).contains(rect.topLeft), isTrue,
        reason: '$role $glyph top-left $rect outside actual clip $visible');
      expect(visible.inflate(0.5).contains(rect.bottomRight), isTrue,
        reason: '$role $glyph bottom-right $rect outside actual clip $visible');
    }
  }
  expect(count, greaterThan(0));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WidgetPreviewBoundedHeightPriorityTest - Measured Geometry Derived Boundaries', () {
    testWidgets(
      'Boundary 1: Schedule derived below-primary boundary omits item 1 without RenderFlex overflow once header is accommodated (defaultBrand, zh, iOS, 320px, 200%)',
      (tester) async {
        final heightNotifier = ValueNotifier<double>(600.0);
        addTearDown(heightNotifier.dispose);

        final boundaryKey = await _mountDynamicBoundedFixture(
          tester,
          brandId: 'defaultBrand',
          locale: AppLocale.zh,
          viewportSize: const Size(320, 600),
          textScaler: const TextScaler.linear(2.0),
          heightNotifier: heightNotifier,
          childCard: WidgetPreviewCard.schedule(
            displayMode: WidgetDisplayMode.standard,
            platformOverride: TargetPlatform.iOS,
          ),
        );

        // 1. Initial measurement at ample height (600): extract independent geometric references.
        final surfaceFinder = find.byKey(const ValueKey('widget_preview_surface'));
        expect(surfaceFinder, findsOneWidget);
        final initialSurfaceBox = tester.renderObject<RenderBox>(surfaceFinder);

        final initialItem1Finder = find.text(WidgetUiCopy.scheduleItem1);
        expect(initialItem1Finder, findsOneWidget);
        final item1Geometry = _measureRow(tester, initialItem1Finder, initialSurfaceBox);
        final item1Rect = item1Geometry.rect;

        final headerBottom = item1Rect.top;
        // The fixed header plus container insets requires at most headerBottom + item1Geometry.bottomInset.
        // Deriving a height between (headerBottom + 15.0) and (item1Rect.bottom + item1Geometry.bottomInset)
        // guarantees that the header is fully accommodated with spare space (0 overflow),
        // while remaining body height is strictly less than item 1's required height.
        final derivedHeight = (headerBottom + item1Geometry.bottomInset + (item1Rect.height * 0.35)).ceilToDouble();

        expect(
          derivedHeight,
          greaterThan(headerBottom + item1Geometry.bottomInset),
          reason: 'Derived boundary must leave positive vertical room for the fixed header',
        );
        expect(
          derivedHeight,
          lessThan(item1Rect.bottom + item1Geometry.bottomInset),
          reason: 'Derived boundary must be strictly smaller than item 1 accommodation threshold',
        );

        // 2. Transition the exact same card element to the derived tight bounded height.
        heightNotifier.value = derivedHeight;
        await _pumpBoundedFrames(tester);

        // 3. Verify zero RenderFlex overflow and strict surface clamping.
        expect(
          tester.takeException(),
          isNull,
          reason: 'Header fits cleanly and body must omit item 1 without RenderFlex overflow',
        );

        final clampedSurfaceBox = tester.renderObject<RenderBox>(surfaceFinder);
        expect(
          clampedSurfaceBox.size.height,
          equals(derivedHeight),
          reason: 'Card surface must strictly match derived bounded height',
        );

        // 4. Content assertions: item 1 must be omitted (no bypassing maxHeight to force-fit).
        expect(
          find.text(WidgetUiCopy.scheduleItem1),
          findsNothing,
          reason: 'Schedule item 1 must be omitted when remaining body height < primaryHeight',
        );
        expect(
          find.text(WidgetUiCopy.scheduleItem2),
          findsNothing,
          reason: 'Schedule item 2 must be omitted when height is insufficient',
        );
        expect(
          find.byKey(const ValueKey('widget_preview_navigation')),
          findsNothing,
          reason: 'Navigation must be omitted when height is insufficient',
        );

        await _captureBoundedHeightScreenshot(
          tester,
          boundaryKey,
          'schedule_derived_below_primary_${derivedHeight.toInt()}px_defaultBrand_zh_ios_200pct',
        );
      },
    );

    testWidgets(
      'Boundary 2: Todo derived first-fit boundary accommodates item 1 and omits over-height item 2 and navigation (defaultBrand, zh, iOS, 320px, 200%)',
      (tester) async {
        final heightNotifier = ValueNotifier<double>(600.0);
        addTearDown(heightNotifier.dispose);

        final boundaryKey = await _mountDynamicBoundedFixture(
          tester,
          brandId: 'defaultBrand',
          locale: AppLocale.zh,
          viewportSize: const Size(320, 600),
          textScaler: const TextScaler.linear(2.0),
          heightNotifier: heightNotifier,
          childCard: WidgetPreviewCard.todo(
            displayMode: WidgetDisplayMode.standard,
            platformOverride: TargetPlatform.iOS,
          ),
        );

        // 1. Initial measurement at ample height (600).
        final surfaceFinder = find.byKey(const ValueKey('widget_preview_surface'));
        expect(surfaceFinder, findsOneWidget);
        final initialSurfaceBox = tester.renderObject<RenderBox>(surfaceFinder);

        final initialItem1Finder = find.text(WidgetUiCopy.todoItem1);
        expect(initialItem1Finder, findsOneWidget);
        final item1Geometry = _measureRow(tester, initialItem1Finder, initialSurfaceBox);
        final item1Rect = item1Geometry.rect;

        final initialItem2Finder = find.text(WidgetUiCopy.todoItem2);
        expect(initialItem2Finder, findsOneWidget);
        final item2Geometry = _measureRow(tester, initialItem2Finder, initialSurfaceBox);
        final item2Rect = item2Geometry.rect;

        // Item 1 requires item1Rect.bottom + item1Geometry.bottomInset insets; item 2 requires item2Rect.bottom + item2Geometry.bottomInset.
        final derivedHeight = (item1Rect.bottom + item1Geometry.bottomInset + 0.5).ceilToDouble();

        expect(
          derivedHeight,
          greaterThanOrEqualTo(item1Rect.bottom + item1Geometry.bottomInset),
          reason: 'Derived boundary must provide sufficient height to accommodate item 1',
        );
        expect(
          derivedHeight,
          lessThan(item2Rect.bottom + item2Geometry.bottomInset),
          reason: 'Derived boundary must be strictly below item 2 threshold',
        );

        // 2. Transition to derived first-fit height.
        heightNotifier.value = derivedHeight;
        await _pumpBoundedFrames(tester);

        expect(tester.takeException(), isNull);

        final clampedSurfaceBox = tester.renderObject<RenderBox>(surfaceFinder);
        expect(clampedSurfaceBox.size.height, equals(derivedHeight));

        // 3. Item 1 is fully visible and readable.
        final todoItem1Finder = find.text(WidgetUiCopy.todoItem1);
        _assertReadableParagraph(
          tester,
          textFinder: todoItem1Finder,
          surfaceFinder: surfaceFinder,
          boundaryKey: boundaryKey,
          role: 'Todo item 1 at measured first-fit boundary ${derivedHeight.toInt()}px',
        );

        // 4. Over-height item 2 and navigation are omitted.
        expect(
          find.text(WidgetUiCopy.todoItem2),
          findsNothing,
          reason: 'Todo item 2 must be omitted when remaining height cannot accommodate it',
        );
        expect(
          find.byKey(const ValueKey('widget_preview_navigation')),
          findsNothing,
          reason: 'Navigation must be omitted when remaining height cannot fit footer',
        );

        await _captureBoundedHeightScreenshot(
          tester,
          boundaryKey,
          'todo_derived_fit_item1_${derivedHeight.toInt()}px_defaultBrand_zh_ios_200pct',
        );
      },
    );

    testWidgets(
      'Boundary 3: Course derived first-fit boundary accommodates item 1 and omits item 2 on Android without overflow (liquidGlass, en, Android, 320px, 200%)',
      (tester) async {
        final heightNotifier = ValueNotifier<double>(600.0);
        addTearDown(heightNotifier.dispose);

        final boundaryKey = await _mountDynamicBoundedFixture(
          tester,
          brandId: 'liquidGlass',
          locale: AppLocale.en,
          viewportSize: const Size(320, 600),
          textScaler: const TextScaler.linear(2.0),
          heightNotifier: heightNotifier,
          childCard: WidgetPreviewCard.course(
            displayMode: WidgetDisplayMode.standard,
            platformOverride: TargetPlatform.android,
          ),
        );

        // 1. Initial measurement at ample height (600).
        final surfaceFinder = find.byKey(const ValueKey('widget_preview_surface'));
        expect(surfaceFinder, findsOneWidget);
        final initialSurfaceBox = tester.renderObject<RenderBox>(surfaceFinder);

        final initialItem1Finder = find.text(WidgetUiCopy.courseItem1);
        expect(initialItem1Finder, findsOneWidget);
        final item1Geometry = _measureRow(tester, initialItem1Finder, initialSurfaceBox);
        final item1Rect = item1Geometry.rect;

        final initialItem2Finder = find.text(WidgetUiCopy.courseItem2);
        expect(initialItem2Finder, findsOneWidget);
        final item2Geometry = _measureRow(tester, initialItem2Finder, initialSurfaceBox);
        final item2Rect = item2Geometry.rect;

        final derivedHeight = (item1Rect.bottom + item1Geometry.bottomInset + 0.5).ceilToDouble();

        expect(
          derivedHeight,
          greaterThanOrEqualTo(item1Rect.bottom + item1Geometry.bottomInset),
          reason: 'Derived boundary must provide sufficient height to accommodate course item 1',
        );
        expect(
          derivedHeight,
          lessThan(item2Rect.bottom + item2Geometry.bottomInset),
          reason: 'Derived boundary must be strictly below course item 2 threshold',
        );

        // 2. Transition to derived first-fit height.
        heightNotifier.value = derivedHeight;
        await _pumpBoundedFrames(tester);

        expect(tester.takeException(), isNull);

        final clampedSurfaceBox = tester.renderObject<RenderBox>(surfaceFinder);
        expect(clampedSurfaceBox.size.height, equals(derivedHeight));

        // 3. Item 1 is fully visible and readable.
        final courseItem1Finder = find.text(WidgetUiCopy.courseItem1);
        _assertReadableParagraph(
          tester,
          textFinder: courseItem1Finder,
          surfaceFinder: surfaceFinder,
          boundaryKey: boundaryKey,
          role: 'Course item 1 at measured first-fit boundary ${derivedHeight.toInt()}px',
        );

        // 4. Item 2 is omitted.
        expect(
          find.text(WidgetUiCopy.courseItem2),
          findsNothing,
          reason: 'Course item 2 must be omitted when exceeding maxHeight',
        );
        expect(
          find.byKey(const ValueKey('widget_preview_navigation')),
          findsNothing,
          reason: 'Navigation must not appear on Android standard mode or under tight height',
        );

        await _captureBoundedHeightScreenshot(
          tester,
          boundaryKey,
          'course_derived_fit_item1_${derivedHeight.toInt()}px_liquidGlass_en_android_200pct',
        );
      },
    );

    testWidgets(
      'Boundary 4: Note derived content-fit boundary accommodates items 1 and 2 but omits navigation under RouteProbeNonlinearScaler (liquidGlass, zh, iOS, 332px, nonlinear)',
      (tester) async {
        final heightNotifier = ValueNotifier<double>(600.0);
        addTearDown(heightNotifier.dispose);

        final boundaryKey = await _mountDynamicBoundedFixture(
          tester,
          brandId: 'liquidGlass',
          locale: AppLocale.zh,
          viewportSize: const Size(332, 600),
          textScaler: const RouteProbeNonlinearScaler(),
          heightNotifier: heightNotifier,
          childCard: WidgetPreviewCard.note(
            displayMode: WidgetDisplayMode.standard,
            platformOverride: TargetPlatform.iOS,
          ),
        );

        // 1. Initial measurement at ample height (600).
        final surfaceFinder = find.byKey(const ValueKey('widget_preview_surface'));
        expect(surfaceFinder, findsOneWidget);
        final initialSurfaceBox = tester.renderObject<RenderBox>(surfaceFinder);

        final initialItem1Finder = find.text(WidgetUiCopy.noteItem1);
        expect(initialItem1Finder, findsOneWidget);

        final initialItem2Finder = find.text(WidgetUiCopy.noteItem2);
        expect(initialItem2Finder, findsOneWidget);
        final item2Geometry = _measureRow(tester, initialItem2Finder, initialSurfaceBox);
        final item2Rect = item2Geometry.rect;

        final initialNavFinder = find.byKey(const ValueKey('widget_preview_navigation'));
        expect(initialNavFinder, findsOneWidget);
        final initialNavBox = tester.renderObject<RenderBox>(initialNavFinder);
        final navRect = MatrixUtils.transformRect(
          initialNavBox.getTransformTo(initialSurfaceBox),
          Offset.zero & initialNavBox.size,
        );

        // Accommodates item 2 plus insets, but stays strictly below navigation requirement.
        final derivedHeight = (item2Rect.bottom + item2Geometry.bottomInset + 0.5).ceilToDouble();

        expect(
          derivedHeight,
          greaterThanOrEqualTo(item2Rect.bottom + item2Geometry.bottomInset),
          reason: 'Derived boundary must accommodate both note items 1 and 2',
        );
        expect(
          derivedHeight,
          lessThan(navRect.bottom + 12.0),
          reason: 'Derived boundary must be strictly below navigation threshold',
        );

        // 2. Transition to derived content-fit height.
        heightNotifier.value = derivedHeight;
        await _pumpBoundedFrames(tester);

        expect(tester.takeException(), isNull);

        final clampedSurfaceBox = tester.renderObject<RenderBox>(surfaceFinder);
        expect(clampedSurfaceBox.size.height, equals(derivedHeight));

        // 3. Both Note lines 1 and 2 fit within the allocated height.
        final noteItem1Finder = find.text(WidgetUiCopy.noteItem1);
        _assertReadableParagraph(
          tester,
          textFinder: noteItem1Finder,
          surfaceFinder: surfaceFinder,
          boundaryKey: boundaryKey,
          role: 'Note item 1 under nonlinear scaler at ${derivedHeight.toInt()}px',
        );

        final noteItem2Finder = find.text(WidgetUiCopy.noteItem2);
        _assertReadableParagraph(
          tester,
          textFinder: noteItem2Finder,
          surfaceFinder: surfaceFinder,
          boundaryKey: boundaryKey,
          role: 'Note item 2 under nonlinear scaler at ${derivedHeight.toInt()}px',
        );

        expect(
          find.text(WidgetUiCopy.noteItem3),
          findsNothing,
          reason: 'Note item 3 is outside standard mode density scope',
        );

        // 4. Navigation is omitted due to insufficient remaining space.
        expect(
          find.byKey(const ValueKey('widget_preview_navigation')),
          findsNothing,
          reason: 'Navigation must be omitted when remaining height < navigation.heightFor + 10',
        );

        await _captureBoundedHeightScreenshot(
          tester,
          boundaryKey,
          'note_derived_fit_items1_2_${derivedHeight.toInt()}px_liquidGlass_zh_ios_nonlinear',
        );
      },
    );

    testWidgets(
      'Boundary 5: Diary detailed mode derived two-fit boundary accommodates items 1 and 2 but omits item 3 (defaultBrand, en, iOS, 320px, 200%)',
      (tester) async {
        final heightNotifier = ValueNotifier<double>(600.0);
        addTearDown(heightNotifier.dispose);

        final boundaryKey = await _mountDynamicBoundedFixture(
          tester,
          brandId: 'defaultBrand',
          locale: AppLocale.en,
          viewportSize: const Size(320, 600),
          textScaler: const TextScaler.linear(2.0),
          heightNotifier: heightNotifier,
          childCard: WidgetPreviewCard.diary(
            displayMode: WidgetDisplayMode.detailed,
            platformOverride: TargetPlatform.iOS,
          ),
        );

        // 1. Initial measurement at ample height (600).
        final surfaceFinder = find.byKey(const ValueKey('widget_preview_surface'));
        expect(surfaceFinder, findsOneWidget);
        final initialSurfaceBox = tester.renderObject<RenderBox>(surfaceFinder);

        final initialItem1Finder = find.text(WidgetUiCopy.diaryItem1);
        expect(initialItem1Finder, findsOneWidget);

        final initialItem2Finder = find.text(WidgetUiCopy.diaryItem2);
        expect(initialItem2Finder, findsOneWidget);
        final item2Geometry = _measureRow(tester, initialItem2Finder, initialSurfaceBox);
        final item2Rect = item2Geometry.rect;

        final initialItem3Finder = find.text(WidgetUiCopy.diaryItem3);
        expect(initialItem3Finder, findsOneWidget);
        final item3Geometry = _measureRow(tester, initialItem3Finder, initialSurfaceBox);
        final item3Rect = item3Geometry.rect;

        final derivedHeight = (item2Rect.bottom + item2Geometry.bottomInset + 0.5).ceilToDouble();

        expect(
          derivedHeight,
          greaterThanOrEqualTo(item2Rect.bottom + item2Geometry.bottomInset),
          reason: 'Derived boundary must provide sufficient height for diary items 1 and 2',
        );
        expect(
          derivedHeight,
          lessThan(item3Rect.bottom + item3Geometry.bottomInset),
          reason: 'Derived boundary must be strictly below diary item 3 threshold',
        );

        // 2. Transition to derived two-fit height.
        heightNotifier.value = derivedHeight;
        await _pumpBoundedFrames(tester);

        expect(tester.takeException(), isNull);

        final clampedSurfaceBox = tester.renderObject<RenderBox>(surfaceFinder);
        expect(clampedSurfaceBox.size.height, equals(derivedHeight));

        // 3. Items 1 and 2 are fully visible and readable.
        final diaryItem1Finder = find.text(WidgetUiCopy.diaryItem1);
        _assertReadableParagraph(
          tester,
          textFinder: diaryItem1Finder,
          surfaceFinder: surfaceFinder,
          boundaryKey: boundaryKey,
          role: 'Diary detailed item 1 at ${derivedHeight.toInt()}px',
        );

        final diaryItem2Finder = find.text(WidgetUiCopy.diaryItem2);
        _assertReadableParagraph(
          tester,
          textFinder: diaryItem2Finder,
          surfaceFinder: surfaceFinder,
          boundaryKey: boundaryKey,
          role: 'Diary detailed item 2 at ${derivedHeight.toInt()}px',
        );

        // 4. Over-height item 3 is omitted.
        expect(
          find.text(WidgetUiCopy.diaryItem3),
          findsNothing,
          reason: 'Diary detailed item 3 must be omitted when exceeding remaining height',
        );
        expect(
          find.byKey(const ValueKey('widget_preview_navigation')),
          findsNothing,
          reason: 'Navigation must be omitted when not all candidates fit',
        );

        await _captureBoundedHeightScreenshot(
          tester,
          boundaryKey,
          'diary_detailed_derived_fit_items1_2_${derivedHeight.toInt()}px_defaultBrand_en_ios_200pct',
        );
      },
    );

    testWidgets(
      'Boundary 6: Schedule standard mode displays both items AND navigation once derived navigation threshold is satisfied (liquidGlass, en, iOS, 320px, 200%)',
      (tester) async {
        final heightNotifier = ValueNotifier<double>(600.0);
        addTearDown(heightNotifier.dispose);

        final boundaryKey = await _mountDynamicBoundedFixture(
          tester,
          brandId: 'liquidGlass',
          locale: AppLocale.en,
          viewportSize: const Size(320, 600),
          textScaler: const TextScaler.linear(2.0),
          heightNotifier: heightNotifier,
          childCard: WidgetPreviewCard.schedule(
            displayMode: WidgetDisplayMode.standard,
            platformOverride: TargetPlatform.iOS,
          ),
        );

        // 1. Initial measurement at ample height (600).
        final surfaceFinder = find.byKey(const ValueKey('widget_preview_surface'));
        expect(surfaceFinder, findsOneWidget);
        final initialSurfaceBox = tester.renderObject<RenderBox>(surfaceFinder);

        final initialItem1Finder = find.text(WidgetUiCopy.scheduleItem1);
        expect(initialItem1Finder, findsOneWidget);

        final initialItem2Finder = find.text(WidgetUiCopy.scheduleItem2);
        expect(initialItem2Finder, findsOneWidget);

        final initialNavFinder = find.byKey(const ValueKey('widget_preview_navigation'));
        expect(initialNavFinder, findsOneWidget);
        final initialNavBox = tester.renderObject<RenderBox>(initialNavFinder);
        final navRect = MatrixUtils.transformRect(
          initialNavBox.getTransformTo(initialSurfaceBox),
          Offset.zero & initialNavBox.size,
        );

        // Derived height provides sufficient room for both content lines and the navigation bar.
        final derivedHeight = (navRect.bottom + 16.0).ceilToDouble();

        expect(
          derivedHeight,
          greaterThanOrEqualTo(navRect.bottom + 14.0),
          reason: 'Derived boundary must satisfy full content and navigation threshold',
        );

        // 2. Transition to derived navigation-fit height.
        heightNotifier.value = derivedHeight;
        await _pumpBoundedFrames(tester);

        expect(tester.takeException(), isNull);

        final clampedSurfaceBox = tester.renderObject<RenderBox>(surfaceFinder);
        // Align keeps the natural card height when the imposed cap is larger.
        expect(clampedSurfaceBox.size.height, lessThanOrEqualTo(derivedHeight));

        // 3. Both schedule items 1 and 2 fit.
        final scheduleItem1Finder = find.text(WidgetUiCopy.scheduleItem1);
        _assertReadableParagraph(
          tester,
          textFinder: scheduleItem1Finder,
          surfaceFinder: surfaceFinder,
          boundaryKey: boundaryKey,
          role: 'Schedule item 1 with navigation (liquidGlass, en, iOS)',
        );

        final scheduleItem2Finder = find.text(WidgetUiCopy.scheduleItem2);
        _assertReadableParagraph(
          tester,
          textFinder: scheduleItem2Finder,
          surfaceFinder: surfaceFinder,
          boundaryKey: boundaryKey,
          role: 'Schedule item 2 with navigation (liquidGlass, en, iOS)',
        );

        // 4. Navigation is present.
        final navFinder = find.byKey(const ValueKey('widget_preview_navigation'));
        expect(
          navFinder,
          findsOneWidget,
          reason: 'Navigation must appear when all content fits and sufficient height remains',
        );

        // 5. Verify each individual navigation item label is readable.
        for (final label in WidgetUiCopy.previewNavLabels) {
          final labelFinder = find.descendant(
            of: navFinder,
            matching: find.text(label),
          );
          expect(
            labelFinder,
            findsOneWidget,
            reason: 'Navigation label "$label" must be rendered',
          );
          _assertReadableParagraph(
            tester,
            textFinder: labelFinder,
            surfaceFinder: surfaceFinder,
            boundaryKey: boundaryKey,
            role: 'Navigation label "$label"',
          );
        }

        await _captureBoundedHeightScreenshot(
          tester,
          boundaryKey,
          'schedule_standard_derived_with_nav_${derivedHeight.toInt()}px_liquidGlass_en_ios_200pct',
        );
      },
    );
  });
}
