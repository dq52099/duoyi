// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/services/android_widget_manager.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/services/widget_display_mode_store.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandRouteSurface;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/rendered_control_contrast.dart';
import '../support/secondary_route_render_probe.dart'
    show RouteProbeNonlinearScaler;
import '../support/weekly_review_screenshot_font.dart';

const _widgetChannel = MethodChannel('duoyi/widgets');
const _homeWidgetChannel = MethodChannel('home_widget');

class _SelectorScenario {
  const _SelectorScenario({
    required this.name,
    required this.viewport,
    this.textScale = 1.0,
    required this.dpr,
    this.nonlinear = false,
  });

  final String name;
  final Size viewport;
  final double textScale;
  final double dpr;
  final bool nonlinear;
}

const _contractScenarios = <_SelectorScenario>[
  // Narrow 320 logical width at 200% text scale
  _SelectorScenario(
    name: 'narrow-320x844-scale2',
    viewport: Size(320, 844),
    textScale: 2.0,
    dpr: 2.0,
  ),
  // Landscape 844x390 ordinary
  _SelectorScenario(
    name: 'landscape-844x390',
    viewport: Size(844, 390),
    textScale: 1.0,
    dpr: 2.0,
  ),
  // Ordinary 390x844 portrait
  _SelectorScenario(
    name: 'ordinary-390x844',
    viewport: Size(390, 844),
    textScale: 1.0,
    dpr: 2.0,
  ),
  // Nonlinear scaling scenario at 320 logical width
  _SelectorScenario(
    name: 'nonlinear-320x844',
    viewport: Size(320, 844),
    textScale: 1.0,
    dpr: 2.0,
    nonlinear: true,
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
    AndroidWidgetManager.debugIsAndroidOverride = true;
    HomeWidgetService.supportedForTesting = true;
  });

  tearDown(() {
    I18n.setLocale(AppLocale.zh);
    AndroidWidgetManager.debugIsAndroidOverride = null;
    HomeWidgetService.supportedForTesting = null;
  });

  group('Category and DisplayMode SegmentedButton label readability & completeness matrix', () {
    for (final brand in ['defaultBrand', 'liquidGlass']) {
      for (final locale in [AppLocale.zh, AppLocale.en]) {
        for (final scenario in _contractScenarios) {
          testWidgets(
            'selector readability $brand ${locale.name} ${scenario.name}',
            (tester) async {
              final previousDisableShadows = debugDisableShadows;
              _SelectorFixture? fixture;
              try {
                I18n.setLocale(locale);
                fixture = await _SelectorFixture.mount(
                  tester,
                  viewport: scenario.viewport,
                  dpr: scenario.dpr,
                  textScaler: scenario.nonlinear
                      ? const RouteProbeNonlinearScaler()
                      : TextScaler.linear(scenario.textScale),
                  brandId: brand,
                );

                final screen = find.byType(WidgetScreen);
                expect(screen, findsOneWidget);

                final baseName =
                    'widget-selector-$brand-${locale.name}-${scenario.name}';
                final needsOptionScreenshots =
                    scenario.name == 'narrow-320x844-scale2' ||
                    scenario.name == 'nonlinear-320x844' ||
                    (locale == AppLocale.en && scenario.name == 'ordinary-390x844');

                // 1. Verify Category SegmentedButton complete labels, 44dp targets & viewport/surface containment
                await _expectCategorySelector(tester, fixture.captureKey);

                // 2. Verify DisplayMode SegmentedButton complete labels, 44dp targets & viewport/surface containment,
                // capturing compact & standard when revealed in scenarios where they scroll off
                await _expectDisplayModeSelector(
                  tester,
                  fixture.captureKey,
                  screenshotBaseName: baseName,
                  captureOptions: needsOptionScreenshots,
                );

                // 3. Optional screenshot capture respecting boundary throw contract
                await _captureIfRequested(
                  tester,
                  fixture.captureKey,
                  '$baseName.png',
                );

                expect(tester.takeException(), isNull);
              } finally {
                await fixture?.dispose(tester);
                debugDisableShadows = previousDisableShadows;
              }
            },
          );
        }
      }
    }
  });

  group('SegmentedButton selections and native publication persistence', () {
    testWidgets(
      'category selection updates visible state with zero widget preference writes',
      (tester) async {
        final previousDisableShadows = debugDisableShadows;
        _SelectorFixture? fixture;
        try {
          I18n.setLocale(AppLocale.en);
          fixture = await _SelectorFixture.mount(
            tester,
            viewport: const Size(320, 844),
            dpr: 2.0,
            textScale: 2.0,
            brandId: 'defaultBrand',
          );

          expect(_selectedCategory(tester), {WidgetCategory.all});
          expect(fixture.preferenceStore.widgetPreferenceWrites, isEmpty);

          // Select lifestyle category
          await _selectCategory(tester, WidgetCategory.life);
          expect(_selectedCategory(tester), {WidgetCategory.life});

          await _captureIfRequested(
            tester,
            fixture.captureKey,
            'widget-selector-category-life-selected.png',
          );

          // In-memory filter switch must produce 0 widget preference writes
          expect(fixture.preferenceStore.widgetPreferenceWrites, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture?.dispose(tester);
          debugDisableShadows = previousDisableShadows;
        }
      },
    );

    testWidgets(
      'display mode selection invokes native save and updates persistence',
      (tester) async {
        final previousDisableShadows = debugDisableShadows;
        _SelectorFixture? fixture;
        try {
          I18n.setLocale(AppLocale.en);
          fixture = await _SelectorFixture.mount(
            tester,
            viewport: const Size(320, 844),
            dpr: 2.0,
            textScale: 2.0,
            brandId: 'liquidGlass',
          );

          expect(_selectedDisplayMode(tester), {WidgetDisplayMode.standard});
          final saveAttempt = fixture.homeWidget.watchNextDisplayModeSave();

          await tester.runAsync(() async {
            await _selectDisplayMode(tester, WidgetDisplayMode.detailed);
          });
          await _waitForSaveAttempt(tester, saveAttempt);
          await _drainPreferenceWrites(tester);
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 5),
          );

          expect(_selectedDisplayMode(tester), {WidgetDisplayMode.detailed});
          expect(fixture.homeWidget.displayModeSaveValues, ['detailed']);

          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();
          final selection = WidgetDisplayModeSelection.read(prefs);
          expect(selection.mode, 'detailed');
          expect(selection.pending, isFalse);

          await _captureIfRequested(
            tester,
            fixture.captureKey,
            'widget-selector-display-mode-detailed-saved.png',
          );

          expect(tester.takeException(), isNull);
        } finally {
          await fixture?.dispose(tester);
          debugDisableShadows = previousDisableShadows;
        }
      },
    );
  });
}

// -----------------------------------------------------------------------------
// Assertions & Helpers
// -----------------------------------------------------------------------------

Finder _categorySelector(WidgetTester tester) => find.byWidgetPredicate(
  (widget) => widget is SegmentedButton<WidgetCategory>,
);

Finder _styleSelector(WidgetTester tester) => find.byWidgetPredicate(
  (widget) => widget is SegmentedButton<WidgetDisplayMode>,
);

Set<WidgetCategory> _selectedCategory(WidgetTester tester) => tester
    .widget<SegmentedButton<WidgetCategory>>(_categorySelector(tester))
    .selected;

Set<WidgetDisplayMode> _selectedDisplayMode(WidgetTester tester) => tester
    .widget<SegmentedButton<WidgetDisplayMode>>(_styleSelector(tester))
    .selected;

Finder _galleryScrollable(WidgetTester tester) => find
    .descendant(
      of: find.byType(ListView).first,
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _scrollGalleryUntilVisible(
  WidgetTester tester,
  Finder target, {
  double delta = 240,
}) async {
  final scrollable = tester.state<ScrollableState>(_galleryScrollable(tester));
  if (scrollable.position.pixels != 0) scrollable.position.jumpTo(0);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
  await tester.scrollUntilVisible(
    target,
    delta.abs(),
    scrollable: _galleryScrollable(tester),
  );
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

Future<void> _selectCategory(
  WidgetTester tester,
  WidgetCategory category,
) async {
  final control = _categorySelector(tester);
  await _scrollGalleryUntilVisible(tester, control, delta: -240);
  final expectedText = WidgetUiCopy.categoryLabel(category);
  final label = find.descendant(
    of: control,
    matching: find.text(expectedText),
  );
  await tester.ensureVisible(label);
  final buttonFinder = find
      .ancestor(of: label, matching: find.byType(TextButton))
      .first;
  await tester.ensureVisible(buttonFinder);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
  final segmented = tester.widget<SegmentedButton<WidgetCategory>>(control);
  final segmentedRect = tester.getRect(control);
  final buttonRect = tester.getRect(buttonFinder);
  if (segmented.direction == Axis.vertical) {
    expect(
      buttonRect.width,
      closeTo(segmentedRect.width, 0.5),
      reason: 'Vertical button segment must span full SegmentedButton width',
    );
    expect(
      buttonRect.right,
      closeTo(segmentedRect.right, 0.5),
      reason: 'Vertical button segment right edge must align with outer border',
    );
    await tester.tapAt(Offset(segmentedRect.right - 2.0, buttonRect.center.dy));
  } else {
    await tester.tap(buttonFinder);
  }
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

Future<void> _selectDisplayMode(
  WidgetTester tester,
  WidgetDisplayMode mode,
) async {
  final control = _styleSelector(tester);
  await _scrollGalleryUntilVisible(tester, control, delta: -240);
  final expectedText = '${mode.label} ${mode.launcherRequestLabel}';
  final label = find.descendant(
    of: control,
    matching: find.text(expectedText),
  );
  await tester.ensureVisible(label);
  final segmented = tester.widget<SegmentedButton<WidgetDisplayMode>>(control);
  expect(
    segmented.onSelectionChanged,
    isNotNull,
    reason: 'Display mode selector must finish loading before a user can select',
  );
  final buttonFinder = find
      .ancestor(of: label, matching: find.byType(TextButton))
      .first;
  await tester.ensureVisible(buttonFinder);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
  final segmentedRect = tester.getRect(control);
  final buttonRect = tester.getRect(buttonFinder);
  if (segmented.direction == Axis.vertical) {
    expect(
      buttonRect.width,
      closeTo(segmentedRect.width, 0.5),
      reason: 'Vertical display mode segment must span full SegmentedButton width',
    );
    expect(
      buttonRect.right,
      closeTo(segmentedRect.right, 0.5),
      reason: 'Vertical display mode segment right edge must align with outer border',
    );
    await tester.tapAt(Offset(segmentedRect.right - 2.0, buttonRect.center.dy));
  } else {
    await tester.tap(buttonFinder);
  }
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

Future<void> _expectCategorySelector(
  WidgetTester tester,
  GlobalKey captureKey,
) async {
  final segmentedFinder = _categorySelector(tester);
  await _scrollGalleryUntilVisible(tester, segmentedFinder, delta: -240);
  expect(segmentedFinder, findsOneWidget);

  final segmented = tester.widget<SegmentedButton<WidgetCategory>>(segmentedFinder);
  expect(
    segmented.onSelectionChanged,
    isNotNull,
    reason: 'SegmentedButton<WidgetCategory> must be enabled with onSelectionChanged',
  );

  for (final category in WidgetCategory.values) {
    final expectedLabel = WidgetUiCopy.categoryLabel(category);
    final labelFinder = find.descendant(
      of: segmentedFinder,
      matching: find.text(expectedLabel),
    );
    expect(
      labelFinder,
      findsOneWidget,
      reason: 'Category label "$expectedLabel" must be present',
    );

    final buttonFinder = find
        .ancestor(of: labelFinder, matching: find.byType(TextButton))
        .first;
    expect(buttonFinder.hitTestable(), findsOneWidget, reason: expectedLabel);

    // Scroll/reveal button before geometry evaluation
    await tester.ensureVisible(buttonFinder);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );

    // Complete 3x3 touch target hit test, >= 44dp bounds, tap semantics, and viewport containment
    expectControlTouchTarget(tester, buttonFinder);

    final mergedSegment = find
        .ancestor(of: buttonFinder, matching: find.byType(MergeSemantics))
        .first;
    final semantics = tester.getSemantics(mergedSegment).getSemanticsData();
    expect(semantics.label, contains(expectedLabel));
    expect(semantics.hasAction(SemanticsAction.tap), isTrue);

    final paragraph = tester.renderObject<RenderParagraph>(labelFinder);
    expect(
      paragraph.text.toPlainText(),
      expectedLabel,
      reason: 'Full category label must be rendered without truncation',
    );
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: 'Category label "$expectedLabel" must not exceed max lines',
    );
    expect(
      paragraph.textSize.width,
      lessThanOrEqualTo(paragraph.size.width + 0.1),
      reason: '$expectedLabel must not overflow paragraph bounds horizontally',
    );
    expect(
      paragraph.textSize.height,
      lessThanOrEqualTo(paragraph.size.height + 0.1),
      reason: '$expectedLabel must not overflow paragraph bounds vertically',
    );

    // Fresh geometry evaluated after reveal/scroll
    final renderBoundary =
        captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final screenRect = Rect.fromLTWH(
      0,
      0,
      tester.view.physicalSize.width / tester.view.devicePixelRatio,
      tester.view.physicalSize.height / tester.view.devicePixelRatio,
    );
    final viewportFinder = find.descendant(
      of: _galleryScrollable(tester),
      matching: find.byType(Viewport),
    );
    expect(viewportFinder, findsOneWidget);
    final viewportBox = tester.renderObject<RenderBox>(viewportFinder);
    final viewportRect = MatrixUtils.transformRect(
      viewportBox.getTransformTo(renderBoundary),
      Offset.zero & viewportBox.size,
    );
    final buttonBox = tester.renderObject<RenderBox>(buttonFinder);
    final buttonSurfaceRect = MatrixUtils.transformRect(
      buttonBox.getTransformTo(renderBoundary),
      Offset.zero & buttonBox.size,
    );
    final allowedIntersection =
        screenRect.intersect(viewportRect).intersect(buttonSurfaceRect);

    const epsilon = 0.5;
    final containmentRect = allowedIntersection.inflate(epsilon);

    var codeUnitOffset = 0;
    for (final rune in expectedLabel.runes) {
      final char = String.fromCharCode(rune);
      final charLength = char.length;
      if (char.trim().isNotEmpty) {
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(
            baseOffset: codeUnitOffset,
            extentOffset: codeUnitOffset + charLength,
          ),
        );
        expect(
          boxes,
          isNotEmpty,
          reason: 'Rune "$char" at offset $codeUnitOffset in "$expectedLabel" must have non-empty laid out box',
        );
        for (final box in boxes) {
          expect(
            box.left,
            greaterThanOrEqualTo(-epsilon),
            reason: 'Glyph box left must not extend past paragraph left bound for "$char"',
          );
          expect(
            box.right,
            lessThanOrEqualTo(paragraph.size.width + epsilon),
            reason: 'Glyph box right must not extend past paragraph right bound for "$char"',
          );

          final glyphRect = MatrixUtils.transformRect(
            paragraph.getTransformTo(renderBoundary),
            Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
          );

          // All four sides strictly contained in button surface ∩ ListView viewport ∩ screen
          expect(
            glyphRect.left,
            greaterThanOrEqualTo(containmentRect.left),
            reason: 'Glyph left ${glyphRect.left} must be >= allowed left ${containmentRect.left} for "$char"',
          );
          expect(
            glyphRect.right,
            lessThanOrEqualTo(containmentRect.right),
            reason: 'Glyph right ${glyphRect.right} must be <= allowed right ${containmentRect.right} for "$char"',
          );
          expect(
            glyphRect.top,
            greaterThanOrEqualTo(containmentRect.top),
            reason: 'Glyph top ${glyphRect.top} must be >= allowed top ${containmentRect.top} for "$char"',
          );
          expect(
            glyphRect.bottom,
            lessThanOrEqualTo(containmentRect.bottom),
            reason: 'Glyph bottom ${glyphRect.bottom} must be <= allowed bottom ${containmentRect.bottom} for "$char"',
          );
        }
      }
      codeUnitOffset += charLength;
    }
  }
}

Future<void> _expectDisplayModeSelector(
  WidgetTester tester,
  GlobalKey captureKey, {
  String? screenshotBaseName,
  bool captureOptions = false,
}) async {
  final segmentedFinder = _styleSelector(tester);
  await _scrollGalleryUntilVisible(tester, segmentedFinder, delta: -240);
  expect(segmentedFinder, findsOneWidget);

  var waited = 0;
  while (tester
              .widget<SegmentedButton<WidgetDisplayMode>>(segmentedFinder)
              .onSelectionChanged ==
          null &&
      waited < 20) {
    await tester.pump(const Duration(milliseconds: 50));
    waited++;
  }

  final segmented =
      tester.widget<SegmentedButton<WidgetDisplayMode>>(segmentedFinder);
  expect(
    segmented.onSelectionChanged,
    isNotNull,
    reason:
        'SegmentedButton<WidgetDisplayMode> must be enabled with onSelectionChanged',
  );

  for (final mode in WidgetDisplayMode.values) {
    final expectedLabel = '${mode.label} ${mode.launcherRequestLabel}';
    final labelFinder = find.descendant(
      of: segmentedFinder,
      matching: find.text(expectedLabel),
    );
    expect(
      labelFinder,
      findsOneWidget,
      reason: 'Mode label "$expectedLabel" must be present',
    );

    final buttonFinder = find
        .ancestor(of: labelFinder, matching: find.byType(TextButton))
        .first;
    expect(buttonFinder.hitTestable(), findsOneWidget, reason: expectedLabel);

    // Scroll/reveal button before geometry evaluation
    await tester.ensureVisible(buttonFinder);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );

    // Complete 3x3 touch target hit test, >= 44dp bounds, tap semantics, and viewport containment
    expectControlTouchTarget(tester, buttonFinder);

    final mergedSegment = find
        .ancestor(of: buttonFinder, matching: find.byType(MergeSemantics))
        .first;
    final semantics = tester.getSemantics(mergedSegment).getSemanticsData();
    expect(semantics.label, contains(expectedLabel));
    expect(semantics.hasAction(SemanticsAction.tap), isTrue);

    final paragraph = tester.renderObject<RenderParagraph>(labelFinder);
    expect(
      paragraph.text.toPlainText(),
      expectedLabel,
      reason: 'Full mode label must be rendered without truncation',
    );
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: 'Mode label "$expectedLabel" must not exceed max lines',
    );
    expect(
      paragraph.textSize.width,
      lessThanOrEqualTo(paragraph.size.width + 0.1),
      reason: '$expectedLabel must not overflow paragraph bounds horizontally',
    );
    expect(
      paragraph.textSize.height,
      lessThanOrEqualTo(paragraph.size.height + 0.1),
      reason: '$expectedLabel must not overflow paragraph bounds vertically',
    );

    // Fresh geometry evaluated after reveal/scroll
    final renderBoundary =
        captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final screenRect = Rect.fromLTWH(
      0,
      0,
      tester.view.physicalSize.width / tester.view.devicePixelRatio,
      tester.view.physicalSize.height / tester.view.devicePixelRatio,
    );
    final viewportFinder = find.descendant(
      of: _galleryScrollable(tester),
      matching: find.byType(Viewport),
    );
    expect(viewportFinder, findsOneWidget);
    final viewportBox = tester.renderObject<RenderBox>(viewportFinder);
    final viewportRect = MatrixUtils.transformRect(
      viewportBox.getTransformTo(renderBoundary),
      Offset.zero & viewportBox.size,
    );
    final buttonBox = tester.renderObject<RenderBox>(buttonFinder);
    final buttonSurfaceRect = MatrixUtils.transformRect(
      buttonBox.getTransformTo(renderBoundary),
      Offset.zero & buttonBox.size,
    );
    final allowedIntersection =
        screenRect.intersect(viewportRect).intersect(buttonSurfaceRect);

    const epsilon = 0.5;
    final containmentRect = allowedIntersection.inflate(epsilon);

    var codeUnitOffset = 0;
    for (final rune in expectedLabel.runes) {
      final char = String.fromCharCode(rune);
      final charLength = char.length;
      if (char.trim().isNotEmpty) {
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(
            baseOffset: codeUnitOffset,
            extentOffset: codeUnitOffset + charLength,
          ),
        );
        expect(
          boxes,
          isNotEmpty,
          reason: 'Rune "$char" at offset $codeUnitOffset in "$expectedLabel" must have non-empty laid out box',
        );
        for (final box in boxes) {
          expect(
            box.left,
            greaterThanOrEqualTo(-epsilon),
            reason: 'Glyph box left must not extend past paragraph left bound for "$char"',
          );
          expect(
            box.right,
            lessThanOrEqualTo(paragraph.size.width + epsilon),
            reason: 'Glyph box right must not extend past paragraph right bound for "$char"',
          );

          final glyphRect = MatrixUtils.transformRect(
            paragraph.getTransformTo(renderBoundary),
            Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
          );

          // All four sides strictly contained in button surface ∩ ListView viewport ∩ screen
          expect(
            glyphRect.left,
            greaterThanOrEqualTo(containmentRect.left),
            reason: 'Glyph left ${glyphRect.left} must be >= allowed left ${containmentRect.left} for "$char"',
          );
          expect(
            glyphRect.right,
            lessThanOrEqualTo(containmentRect.right),
            reason: 'Glyph right ${glyphRect.right} must be <= allowed right ${containmentRect.right} for "$char"',
          );
          expect(
            glyphRect.top,
            greaterThanOrEqualTo(containmentRect.top),
            reason: 'Glyph top ${glyphRect.top} must be >= allowed top ${containmentRect.top} for "$char"',
          );
          expect(
            glyphRect.bottom,
            lessThanOrEqualTo(containmentRect.bottom),
            reason: 'Glyph bottom ${glyphRect.bottom} must be <= allowed bottom ${containmentRect.bottom} for "$char"',
          );
        }
      }
      codeUnitOffset += charLength;
    }

    // Capture option screenshot for compact / standard when requested
    if (captureOptions &&
        (mode == WidgetDisplayMode.compact ||
         mode == WidgetDisplayMode.standard) &&
        screenshotBaseName != null) {
      await _captureIfRequested(
        tester,
        captureKey,
        '$screenshotBaseName-${mode.id}.png',
      );
    }
  }
}

Future<void> _waitForSaveAttempt(
  WidgetTester tester,
  Future<void> attempt,
) async {
  var waited = 0;
  var completed = false;
  while (waited < 50) {
    await tester.pump(const Duration(milliseconds: 20));
    final done = await tester.runAsync(() async {
      try {
        await attempt.timeout(const Duration(milliseconds: 10));
        return true;
      } on TimeoutException {
        return false;
      }
    });
    if (done == true) {
      completed = true;
      break;
    }
    waited++;
  }
  expect(
    completed,
    isTrue,
    reason: 'Home widget display mode save timed out',
  );
}

Future<void> _drainPreferenceWrites(WidgetTester tester) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.runAsync(
    () => AccountPreferenceWrites.drain().timeout(const Duration(seconds: 5)),
  );
}

Future<void> _captureIfRequested(
  WidgetTester tester,
  GlobalKey key,
  String filename,
) async {
  final directory =
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'] ??
      Platform.environment['DUOYI_RETAINED_DIALOG_SCREENSHOT_DIR'];
  if (directory == null || directory.isEmpty) return;

  var resolvedDir = directory.trim();
  if (resolvedDir.startsWith('/') || resolvedDir.startsWith(r'\')) {
    if (!resolvedDir.contains('evidence/screenshots')) {
      resolvedDir = 'evidence/screenshots/${resolvedDir.split('/').last}';
    }
  } else if (!resolvedDir.startsWith('evidence/screenshots')) {
    resolvedDir = 'evidence/screenshots/$resolvedDir';
  }

  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );

  await tester.runAsync(() async {
    final context = key.currentContext;
    if (context == null) {
      throw StateError(
        'Missing context: context is null for captureKey $key when capturing "$filename"',
      );
    }
    final boundary = context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError(
        'Missing boundary: RepaintBoundary render object not found for captureKey $key when capturing "$filename"',
      );
    }
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError(
          'Encoding error: toByteData returned null when capturing "$filename"',
        );
      }
      final file = File('$resolvedDir/$filename');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

// -----------------------------------------------------------------------------
// Fixture & Test Doubles
// -----------------------------------------------------------------------------

class _SelectorFixture {
  _SelectorFixture._({
    required this.theme,
    required this.channels,
    required this.homeWidget,
    required this.preferenceStore,
    required this.captureKey,
    required this.viewport,
    required this.dpr,
    required this.textScaler,
    required this.previousStore,
    required this.semanticsHandle,
  });

  final ThemeProvider theme;
  final _WidgetChannels channels;
  final _FakeHomeWidget homeWidget;
  final _SelectorPreferenceStore preferenceStore;
  final GlobalKey captureKey;
  final SharedPreferencesStorePlatform previousStore;
  final SemanticsHandle semanticsHandle;
  Size viewport;
  double dpr;
  TextScaler textScaler;
  bool _disposed = false;

  Future<void> dispose(WidgetTester tester) async {
    if (_disposed) return;
    _disposed = true;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    try {
      final screen = find.byType(WidgetScreen);
      if (screen.evaluate().isNotEmpty) {
        ScaffoldMessenger.of(tester.element(screen)).clearSnackBars();
        await tester.pump();
      }
      await _drainPreferenceWrites(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      messenger.setMockMethodCallHandler(_widgetChannel, null);
      messenger.setMockMethodCallHandler(_homeWidgetChannel, null);
      AndroidWidgetManager.debugIsAndroidOverride = null;
      HomeWidgetService.supportedForTesting = null;
      await tester.runAsync(() async {
        HomeWidgetService.resetAccountCache();
        await HomeWidgetService.waitForAccountClear().timeout(
          const Duration(seconds: 5),
        );
      });
      SharedPreferencesStorePlatform.instance = previousStore;
      SharedPreferences.resetStatic();
      tester.view.reset();
      theme.dispose();
      semanticsHandle.dispose();
    }
  }

  static Future<_SelectorFixture> mount(
    WidgetTester tester, {
    required Size viewport,
    double dpr = 1.0,
    TextScaler? textScaler,
    double? textScale,
    String brandId = 'defaultBrand',
  }) async {
    final effectiveTextScaler =
        textScaler ?? TextScaler.linear(textScale ?? 1.0);

    await tester.runAsync(loadWeeklyReviewScreenshotFonts);

    SharedPreferences.resetStatic();
    final preferenceStore = _SelectorPreferenceStore({
      'flutter.active_brand': brandId,
      'flutter.theme_shop_state': jsonEncode({
        'activeBrand': brandId,
        'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
      }),
      'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
      'flutter.${WidgetDisplayModeSelection.storageKey}': jsonEncode({
        'v': 1,
        'mode': 'standard',
        'pending': false,
        'intentId': 'init-intent',
      }),
    });
    final previousStore = SharedPreferencesStorePlatform.instance;
    SharedPreferencesStorePlatform.instance = preferenceStore;

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final channels = _WidgetChannels();
    final homeWidget = _FakeHomeWidget();
    messenger.setMockMethodCallHandler(_widgetChannel, channels.handle);
    messenger.setMockMethodCallHandler(_homeWidgetChannel, homeWidget.handle);

    AndroidWidgetManager.debugIsAndroidOverride = true;
    HomeWidgetService.supportedForTesting = true;

    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = Size(viewport.width * dpr, viewport.height * dpr);

    ThemeProvider? theme;
    SemanticsHandle? semanticsHandle;
    try {
      theme = await tester.runAsync(() async {
        final t = ThemeProvider();
        await t.loadFromStorage();
        return t;
      });

      semanticsHandle = tester.ensureSemantics();

      final fixture = _SelectorFixture._(
        theme: theme!,
        channels: channels,
        homeWidget: homeWidget,
        preferenceStore: preferenceStore,
        captureKey: GlobalKey(),
        viewport: viewport,
        dpr: dpr,
        textScaler: effectiveTextScaler,
        previousStore: previousStore,
        semanticsHandle: semanticsHandle,
      );

      await tester.pumpWidget(fixture._app());
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      return fixture;
    } catch (_) {
      messenger.setMockMethodCallHandler(_widgetChannel, null);
      messenger.setMockMethodCallHandler(_homeWidgetChannel, null);
      AndroidWidgetManager.debugIsAndroidOverride = null;
      HomeWidgetService.supportedForTesting = null;
      SharedPreferencesStorePlatform.instance = previousStore;
      SharedPreferences.resetStatic();
      tester.view.reset();
      theme?.dispose();
      semanticsHandle?.dispose();
      rethrow;
    }
  }

  Widget _app() {
    return ChangeNotifierProvider<ThemeProvider>.value(
      value: theme,
      child: AnimatedBuilder(
        animation: Listenable.merge([theme, I18n.localeListenable]),
        builder: (context, _) {
          final currentLocale = I18n.current;
          final baseTheme = theme.brand.theme;
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: Locale(currentLocale == AppLocale.en ? 'en' : 'zh'),
            supportedLocales: const [Locale('en'), Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: baseTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: textScaler,
              ),
              child: RepaintBoundary(key: captureKey, child: child!),
            ),
            home: const BrandRouteSurface(
              child: WidgetScreen(hostPlatform: WidgetHostPlatform.android),
            ),
          );
        },
      ),
    );
  }
}

class _SelectorPreferenceStore extends InMemorySharedPreferencesStore {
  _SelectorPreferenceStore(super.data) : super.withData();

  final widgetPreferenceWrites = <String>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.startsWith('flutter.duoyi_widget_')) {
      widgetPreferenceWrites.add(key);
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (key.startsWith('flutter.duoyi_widget_')) {
      widgetPreferenceWrites.add(key);
    }
    return super.remove(key);
  }
}

class _WidgetChannels {
  int supportChecks = 0;
  int openSettings = 0;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'canRequestPinWidget':
        supportChecks++;
        return true;
      case 'canOpenWidgetSettings':
        return true;
      case 'openWidgetSettings':
        openSettings++;
        return true;
      case 'applyWidgetDisplayMode':
      case 'refreshAllWidgets':
        return 0;
      default:
        return null;
    }
  }
}

class _FakeHomeWidget {
  final Map<String, Object?> values = <String, Object?>{
    'widget_display_mode': 'standard',
  };
  final List<Object?> displayModeSaveValues = <Object?>[];
  Completer<void>? _nextDisplayModeSave;

  Future<void> watchNextDisplayModeSave() {
    final next = Completer<void>();
    _nextDisplayModeSave = next;
    return next.future;
  }

  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments as Map?;
    switch (call.method) {
      case 'setAppGroupId':
        return true;
      case 'getWidgetData':
        return values[args?['id']?.toString()];
      case 'saveWidgetData':
        final key = args?['id']?.toString();
        final value = args?['data'];
        if (key == 'widget_display_mode') {
          displayModeSaveValues.add(value);
          final waiter = _nextDisplayModeSave;
          _nextDisplayModeSave = null;
          if (waiter != null && !waiter.isCompleted) waiter.complete();
        }
        if (key != null) values[key] = value;
        return true;
      case 'updateWidget':
        return null;
      default:
        return null;
    }
  }
}
