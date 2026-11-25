// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/services/android_widget_manager.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/services/widget_display_mode_store.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/secondary_route_render_probe.dart'
    show RouteProbeNonlinearScaler;
import '../support/widget_polish_screenshot_font.dart';

const _widgetChannel = MethodChannel('duoyi/widgets');
const _homeWidgetChannel = MethodChannel('home_widget');

class _ControlScenario {
  const _ControlScenario({
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

const _contractScenarios = <_ControlScenario>[
  // true 320 logical width at textScale 2
  _ControlScenario(
    name: 'narrow-320x844-scale2',
    viewport: Size(320, 844),
    textScale: 2.0,
    dpr: 2.0,
  ),
  // 844x390 landscape
  _ControlScenario(
    name: 'landscape-844x390',
    viewport: Size(844, 390),
    textScale: 1.0,
    dpr: 2.0,
  ),
  // ordinary 390 at 100%
  _ControlScenario(
    name: 'ordinary-390x844',
    viewport: Size(390, 844),
    textScale: 1.0,
    dpr: 2.0,
  ),
  // wide 1024 at 100%
  _ControlScenario(
    name: 'tablet-1024x900',
    viewport: Size(1024, 900),
    textScale: 1.0,
    dpr: 1.5,
  ),
  // representative nonlinear text scaling
  _ControlScenario(
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

  group('Category and style selector layout, geometry and complete labels', () {
    for (final brand in ['defaultBrand', 'liquidGlass']) {
      for (final locale in AppLocale.values) {
        for (final scenario in _contractScenarios) {
          testWidgets(
            'controls geometry $brand ${locale.name} ${scenario.name}',
            (tester) async {
              final previousDisableShadows = debugDisableShadows;
              _ControlFixture? fixture;
              try {
                I18n.setLocale(locale);
                fixture = await _ControlFixture.mount(
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

                // Assert view metrics, incoming real media size, and root render box
                expect(tester.view.devicePixelRatio, scenario.dpr);
                expect(
                  tester.view.physicalSize,
                  Size(
                    scenario.viewport.width * scenario.dpr,
                    scenario.viewport.height * scenario.dpr,
                  ),
                );
                expect(
                  MediaQuery.of(tester.element(screen)).size,
                  scenario.viewport,
                  reason:
                      'Media size must naturally derive from physicalSize / DPR without copyWith injection',
                );
                final rootBox = tester.renderObject<RenderBox>(
                  find.byType(Scaffold),
                );
                expect(
                  rootBox.size,
                  scenario.viewport,
                  reason: 'Actual root RenderBox must match logical viewport',
                );

                // Scope Category Selector
                await _expectCategoryControl(tester);

                // Scope WidgetDisplayMode Style Selector
                await _expectDisplayModeControl(
                  tester,
                  hostPlatform: WidgetHostPlatform.android,
                );

                await _captureIfRequested(
                  tester,
                  fixture.captureKey,
                  'widget-control-$brand-${locale.name}-${scenario.name}.png',
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

  group('Selection updates, persistence ordering and queued guards', () {
    testWidgets(
      'category filter updates visible items without writing widget preferences',
      (tester) async {
        final previousDisableShadows = debugDisableShadows;
        _ControlFixture? fixture;
        try {
          fixture = await _ControlFixture.mount(
            tester,
            viewport: const Size(390, 844),
            dpr: 2.0,
            brandId: 'defaultBrand',
          );

          expect(_selectedCategory(tester), {WidgetCategory.all});
          expect(fixture.preferenceStore.widgetPreferenceWrites, isEmpty);

          // Select lifestyle category
          await _selectCategory(tester, WidgetCategory.life);
          expect(_selectedCategory(tester), {WidgetCategory.life});
          expect(
            find.byKey(const ValueKey('widget_gallery_todo')),
            findsNothing,
          );
          await _scrollGalleryUntilVisible(
            tester,
            find.byKey(const ValueKey('widget_gallery_diary')),
          );
          expect(
            find.byKey(const ValueKey('widget_gallery_diary')),
            findsOneWidget,
          );

          // Category selection remains in-memory; no widget preference writes
          expect(fixture.preferenceStore.widgetPreferenceWrites, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture?.dispose(tester);
          debugDisableShadows = previousDisableShadows;
        }
      },
    );

    testWidgets(
      'display mode selection invokes native save and acknowledge in order',
      (tester) async {
        final previousDisableShadows = debugDisableShadows;
        _ControlFixture? fixture;
        try {
          fixture = await _ControlFixture.mount(
            tester,
            viewport: const Size(390, 844),
            dpr: 2.0,
            brandId: 'defaultBrand',
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

          final writes = List<String>.of(
            fixture.preferenceStore.widgetPreferenceWrites,
          );
          expect(writes, isNotEmpty);
          expect(
            writes.toSet(),
            everyElement(
              isIn({
                'flutter.${WidgetDisplayModeSelection.storageKey}',
                'flutter.${WidgetDisplayModeSelection.legacyKey}',
              }),
            ),
          );

          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();
          final selection = WidgetDisplayModeSelection.read(prefs);
          expect(selection.mode, 'detailed');
          expect(selection.pending, isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture?.dispose(tester);
          debugDisableShadows = previousDisableShadows;
        }
      },
    );

    testWidgets(
      'failed native delivery renders pending notice and retry button with 44px target',
      (tester) async {
        final previousDisableShadows = debugDisableShadows;
        _ControlFixture? fixture;
        try {
          fixture = await _ControlFixture.mount(
            tester,
            viewport: const Size(390, 844),
            dpr: 2.0,
            brandId: 'liquidGlass',
          );

          fixture.homeWidget.failNextDisplayModeSave = true;
          final failedAttempt = fixture.homeWidget.watchNextDisplayModeSave();

          await tester.runAsync(() async {
            await _selectDisplayMode(tester, WidgetDisplayMode.detailed);
          });
          await _waitForSaveAttempt(tester, failedAttempt);
          await _settleAsyncWork(tester);

          final retryFinder = find.byKey(
            const ValueKey('widget_style_sync_retry'),
          );
          await _scrollGalleryUntilVisible(tester, retryFinder);
          expect(retryFinder, findsOneWidget);

          final retryButton = tester.widget<TextButton>(retryFinder);
          expect(retryButton.onPressed, isNotNull);
          final buttonSize = tester.getSize(retryFinder);
          expect(
            buttonSize.height,
            greaterThanOrEqualTo(44.0),
            reason: 'Retry button must meet 44px minimum touch target height',
          );

          // Verify pending label
          final pendingNoticeFinder = find.byKey(
            const ValueKey('widget_style_sync_pending'),
          );
          expect(pendingNoticeFinder, findsOneWidget);

          // Verify button foreground resolution
          final context = tester.element(retryFinder);
          final fgColor = _resolveButtonForegroundColor(
            context,
            retryButton,
            {WidgetState.focused},
          );
          expect(fgColor, isNotNull);

          // Tap retry to recover
          final retryAttempt = fixture.homeWidget.watchNextDisplayModeSave();
          await tester.runAsync(() async {
            await tester.tap(retryFinder);
          });
          await _waitForSaveAttempt(tester, retryAttempt);
          await _settleAsyncWork(tester);

          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();
          final selection = WidgetDisplayModeSelection.read(prefs);
          expect(selection.mode, 'detailed');
          expect(selection.pending, isFalse);
          expect(
            find.byKey(const ValueKey('widget_style_sync_retry')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await fixture?.dispose(tester);
          debugDisableShadows = previousDisableShadows;
        }
      },
    );

    testWidgets(
      'load failed state displays error message and reload button with 44px target',
      (tester) async {
        final previousDisableShadows = debugDisableShadows;
        _ControlFixture? fixture;
        try {
          fixture = await _ControlFixture.mount(
            tester,
            viewport: const Size(390, 844),
            dpr: 2.0,
            brandId: 'defaultBrand',
            initialSelectionJson: 'corrupted-data',
          );

          final loadRetryFinder = find.byKey(
            const ValueKey('widget_style_load_retry'),
          );
          await _scrollGalleryUntilVisible(tester, loadRetryFinder);
          expect(loadRetryFinder, findsOneWidget);

          final retryButton = tester.widget<TextButton>(loadRetryFinder);
          expect(retryButton.onPressed, isNotNull);
          final buttonSize = tester.getSize(loadRetryFinder);
          expect(
            buttonSize.height,
            greaterThanOrEqualTo(44.0),
            reason: 'Load retry button must meet 44px minimum touch target',
          );

          final panelColumn = find.ancestor(
            of: loadRetryFinder,
            matching: find.byType(Column),
          ).first;
          expect(
            find.descendant(
              of: panelColumn,
              matching: find.text(WidgetUiCopy.styleLoadFailed),
            ),
            findsOneWidget,
          );

          // Fix the data in storage and tap reload
          final valid = const WidgetDisplayModeSelection(
            mode: 'compact',
            intentId: 'fixed-intent',
            pending: false,
          );
          await tester.runAsync(() async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(
              WidgetDisplayModeSelection.storageKey,
              valid.encode(),
            );
          });

          await tester.tap(loadRetryFinder);
          await _settleAsyncWork(tester);

          await _scrollGalleryUntilVisible(tester, _styleSelector(tester));
          expect(_selectedDisplayMode(tester), {WidgetDisplayMode.compact});
          expect(
            find.byKey(const ValueKey('widget_style_load_retry')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await fixture?.dispose(tester);
          debugDisableShadows = previousDisableShadows;
        }
      },
    );

    testWidgets(
      'queued display mode operation guards against concurrent selection changes',
      (tester) async {
        final previousDisableShadows = debugDisableShadows;
        _ControlFixture? fixture;
        try {
          fixture = await _ControlFixture.mount(
            tester,
            viewport: const Size(390, 844),
            dpr: 2.0,
            brandId: 'defaultBrand',
          );

          late Completer<void> gate;
          late Future<void> gateOperation;
          await tester.runAsync(() async {
            gate = Completer<void>();
            gateOperation =
                WidgetDisplayModeStore.runOperation(() => gate.future);
          });

          final saveAttempt = fixture.homeWidget.watchNextDisplayModeSave();

          await tester.runAsync(() async {
            await _selectDisplayMode(tester, WidgetDisplayMode.detailed);
          });
          await tester.pump(const Duration(milliseconds: 50));

          final segmentedDuringGate =
              tester.widget<SegmentedButton<WidgetDisplayMode>>(
                _styleSelector(tester),
              );
          expect(
            segmentedDuringGate.onSelectionChanged,
            isNull,
            reason:
                'Control must be disabled while display mode operation is queued behind gate',
          );

          // Release queued gate and await gate operation in real zone
          await tester.runAsync(() async {
            gate.complete();
            await gateOperation;
          });

          await _waitForSaveAttempt(tester, saveAttempt);
          await _drainPreferenceWrites(tester);
          await _settleAsyncWork(tester);

          var waited = 0;
          while (tester
                  .widget<SegmentedButton<WidgetDisplayMode>>(
                    _styleSelector(tester),
                  )
                  .onSelectionChanged ==
              null &&
              waited < 20) {
            await tester.pump(const Duration(milliseconds: 50));
            waited++;
          }

          final segmentedAfterGate =
              tester.widget<SegmentedButton<WidgetDisplayMode>>(
                _styleSelector(tester),
              );
          expect(
            segmentedAfterGate.onSelectionChanged,
            isNotNull,
            reason:
                'Control must be re-enabled after queued operation completes',
          );
          expect(_selectedDisplayMode(tester), {WidgetDisplayMode.detailed});
          expect(fixture.homeWidget.displayModeSaveValues, ['detailed']);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture?.dispose(tester);
          debugDisableShadows = previousDisableShadows;
        }
      },
    );
  });

  group('Round trip state, selection, and scroll preservation across theme & locale', () {
    testWidgets(
      'defaultBrand <-> liquidGlass and zh <-> en preserve route, state, selection, and scroll offset',
      (tester) async {
        final previousDisableShadows = debugDisableShadows;
        _ControlFixture? fixture;
        try {
          const viewport = Size(320, 844);
          const dpr = 2.0;
          I18n.setLocale(AppLocale.zh);
          fixture = await _ControlFixture.mount(
            tester,
            viewport: viewport,
            dpr: dpr,
            textScale: 2.0,
            brandId: 'defaultBrand',
          );

          final screenFinder = find.byType(WidgetScreen);
          expect(screenFinder, findsOneWidget);
          final initialScreenState = tester.state(screenFinder);
          final initialRoute = ModalRoute.of(tester.element(screenFinder));
          expect(initialRoute, isNotNull);

          final scrollableFinder = _galleryScrollable(tester);
          final initialScrollableState = tester.state<ScrollableState>(
            scrollableFinder,
          );
          final initialController =
              initialScrollableState.widget.controller ??
              PrimaryScrollController.of(tester.element(screenFinder));
          expect(initialController, isNotNull);

          // 1. Select life category and detailed display mode
          await _selectCategory(tester, WidgetCategory.life);
          expect(_selectedCategory(tester), {WidgetCategory.life});
          await _scrollGalleryUntilVisible(tester, _styleSelector(tester));
          expect(_selectedDisplayMode(tester), {WidgetDisplayMode.standard});

          final saveAttempt = fixture.homeWidget.watchNextDisplayModeSave();
          await tester.runAsync(() async {
            await _selectDisplayMode(tester, WidgetDisplayMode.detailed);
          });
          await _waitForSaveAttempt(tester, saveAttempt);
          await _drainPreferenceWrites(tester);
          await _settleAsyncWork(tester);
          var waited = 0;
          while (tester
                  .widget<SegmentedButton<WidgetDisplayMode>>(
                    _styleSelector(tester),
                  )
                  .onSelectionChanged ==
              null &&
              waited < 20) {
            await tester.pump(const Duration(milliseconds: 50));
            waited++;
          }
          expect(_selectedDisplayMode(tester), {WidgetDisplayMode.detailed});

          final writesAfterSelection = List<String>.of(
            fixture.preferenceStore.widgetPreferenceWrites,
          );

          // 2. Establish non-zero scroll offset
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('widget_gallery_diary')),
            240,
            scrollable: _galleryScrollable(tester),
            maxScrolls: 50,
          );
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 5),
          );
          final scrollableBeforeSwitch = tester.state<ScrollableState>(
            _galleryScrollable(tester),
          );
          final offsetBeforeSwitch = scrollableBeforeSwitch.position.pixels;
          expect(offsetBeforeSwitch, greaterThan(0.0));

          await _captureIfRequested(
            tester,
            fixture.captureKey,
            'widget-control-roundtrip-01-defaultBrand-zh.png',
          );

          // State 2: Switch theme to liquidGlass via ThemeProvider.setBrand
          await tester.runAsync(() async {
            final switched = await fixture!.theme.setBrand('liquidGlass');
            expect(switched, isTrue);
          });
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 5),
          );

          // Immediately assert natural retention BEFORE any test-driven scrolling
          expect(fixture.theme.brand.id, 'liquidGlass');
          expect(
            Theme.of(tester.element(screenFinder)).extension<AppSurfaceStyle>(),
            same(AppSurfaceStyle.liquidGlass),
          );
          expect(
            tester.state(screenFinder),
            same(initialScreenState),
            reason:
                'WidgetScreen state identity must be preserved across brand switch',
          );
          expect(
            ModalRoute.of(tester.element(screenFinder)),
            same(initialRoute),
            reason: 'ModalRoute identity must be preserved across brand switch',
          );

          final scrollableStage2 = tester.state<ScrollableState>(
            _galleryScrollable(tester),
          );
          final controllerStage2 =
              scrollableStage2.widget.controller ??
              PrimaryScrollController.of(tester.element(screenFinder));
          expect(controllerStage2, same(initialController));
          expect(
            scrollableStage2.position.pixels,
            closeTo(offsetBeforeSwitch, 1.0),
            reason:
                'Original scroll offset must be preserved without corrective intervention',
          );
          expect(
            fixture.preferenceStore.widgetPreferenceWrites,
            writesAfterSelection,
            reason:
                'Theme switch must not trigger extra widget preference writes',
          );

          // Test-driven reachability scrolling to verify retained selections
          await _expectRetainedSelections(
            tester,
            expectedCategory: WidgetCategory.life,
            expectedDisplayMode: WidgetDisplayMode.detailed,
          );

          // Separately restore scroll offset back to pre-test state
          await _restoreScrollOffset(tester, offsetBeforeSwitch);

          await _captureIfRequested(
            tester,
            fixture.captureKey,
            'widget-control-roundtrip-02-liquidGlass-zh.png',
          );

          // State 3: Switch locale to en
          I18n.setLocale(AppLocale.en);
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 5),
          );

          // Immediately assert natural retention BEFORE any test-driven scrolling
          expect(
            tester.state(screenFinder),
            same(initialScreenState),
            reason:
                'WidgetScreen state identity must be preserved across locale switch',
          );
          expect(
            ModalRoute.of(tester.element(screenFinder)),
            same(initialRoute),
            reason: 'ModalRoute identity must be preserved across locale switch',
          );

          final scrollableStage3 = tester.state<ScrollableState>(
            _galleryScrollable(tester),
          );
          expect(
            scrollableStage3.position.pixels,
            closeTo(offsetBeforeSwitch, 1.0),
            reason:
                'Original scroll offset must be preserved without corrective intervention',
          );
          expect(
            fixture.preferenceStore.widgetPreferenceWrites,
            writesAfterSelection,
            reason:
                'Locale switch must not trigger extra widget preference writes',
          );

          // Test-driven reachability scrolling to verify retained selections and scoped content
          await _expectRetainedSelections(
            tester,
            expectedCategory: WidgetCategory.life,
            expectedDisplayMode: WidgetDisplayMode.detailed,
          );
          await _expectCategoryControl(tester);
          await _expectDisplayModeControl(
            tester,
            hostPlatform: WidgetHostPlatform.android,
          );

          // Separately restore scroll offset back to pre-test state
          await _restoreScrollOffset(tester, offsetBeforeSwitch);

          await _captureIfRequested(
            tester,
            fixture.captureKey,
            'widget-control-roundtrip-03-liquidGlass-en.png',
          );

          // State 4: Revert brand to defaultBrand and locale to zh
          await tester.runAsync(() async {
            final reverted = await fixture!.theme.setBrand('defaultBrand');
            expect(reverted, isTrue);
          });
          I18n.setLocale(AppLocale.zh);
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 5),
          );

          // Immediately assert natural retention BEFORE any test-driven scrolling
          expect(fixture.theme.brand.id, 'defaultBrand');
          expect(
            tester.state(screenFinder),
            same(initialScreenState),
            reason: 'WidgetScreen state identity preserved on full roundtrip',
          );
          expect(
            ModalRoute.of(tester.element(screenFinder)),
            same(initialRoute),
            reason: 'ModalRoute identity preserved on full roundtrip',
          );

          final scrollableStage4 = tester.state<ScrollableState>(
            _galleryScrollable(tester),
          );
          expect(
            scrollableStage4.position.pixels,
            closeTo(offsetBeforeSwitch, 1.0),
            reason:
                'Original scroll offset must be preserved on complete roundtrip',
          );
          expect(
            fixture.preferenceStore.widgetPreferenceWrites,
            writesAfterSelection,
            reason: 'Roundtrip must not write extra widget preferences',
          );

          await _expectRetainedSelections(
            tester,
            expectedCategory: WidgetCategory.life,
            expectedDisplayMode: WidgetDisplayMode.detailed,
          );

          await _captureIfRequested(
            tester,
            fixture.captureKey,
            'widget-control-roundtrip-04-reverted-defaultBrand-zh.png',
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
  await _scrollGalleryToTop(tester);
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

Future<void> _scrollGalleryToTop(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(_galleryScrollable(tester));
  if (scrollable.position.pixels != 0) scrollable.position.jumpTo(0);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

Future<void> _restoreScrollOffset(
  WidgetTester tester,
  double targetOffset,
) async {
  final scrollable = tester.state<ScrollableState>(_galleryScrollable(tester));
  scrollable.position.jumpTo(targetOffset);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
  expect(scrollable.position.pixels, closeTo(targetOffset, 1.0));
}

Future<void> _selectCategory(
  WidgetTester tester,
  WidgetCategory category,
) async {
  final control = _categorySelector(tester);
  await _scrollGalleryUntilVisible(tester, control, delta: -240);
  final label = find.descendant(
    of: control,
    matching: find.text(WidgetUiCopy.categoryLabel(category)),
  );
  await tester.ensureVisible(label);
  await tester.tap(label);
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
  expect(
    tester.widget<SegmentedButton<WidgetDisplayMode>>(control).onSelectionChanged,
    isNotNull,
    reason: 'Display mode selector must finish loading before a user can select',
  );
  await tester.tap(label);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

Future<void> _expectCategoryControl(
  WidgetTester tester, {
  Axis? expectedDirection,
}) async {
  final segmentedFinder = _categorySelector(tester);
  await _scrollGalleryUntilVisible(tester, segmentedFinder, delta: -240);
  expect(segmentedFinder, findsOneWidget);

  final segmented = tester.widget<SegmentedButton<WidgetCategory>>(
    segmentedFinder,
  );
  expect(
    segmented.onSelectionChanged,
    isNotNull,
    reason:
        'SegmentedButton<WidgetCategory> must be enabled with onSelectionChanged',
  );
  if (expectedDirection != null) {
    expect(
      segmented.direction,
      expectedDirection,
      reason:
          'SegmentedButton<WidgetCategory> direction should match expected axis.',
    );
  }

  for (final category in WidgetCategory.values) {
    final expectedLabel = WidgetUiCopy.categoryLabel(category);
    final labelFinder = find.descendant(
      of: segmentedFinder,
      matching: find.text(expectedLabel),
    );
    expect(
      labelFinder,
      findsOneWidget,
      reason: 'Label $expectedLabel must be present',
    );
    await tester.ensureVisible(labelFinder);
    await tester.pumpAndSettle();

    final buttonFinder = find
        .ancestor(of: labelFinder, matching: find.byType(TextButton))
        .first;
    expect(buttonFinder.hitTestable(), findsOneWidget, reason: expectedLabel);

    final buttonSize = tester.getSize(buttonFinder);
    expect(
      buttonSize.height,
      greaterThanOrEqualTo(44.0),
      reason:
          '$expectedLabel touch target height must be at least 44 logical px',
    );
    expect(
      buttonSize.width,
      greaterThanOrEqualTo(44.0),
      reason:
          '$expectedLabel touch target width must be at least 44 logical px',
    );

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
      reason: 'Category label $expectedLabel must not exceed max lines',
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

    final labelRect = tester.getRect(labelFinder);
    final buttonRect = tester.getRect(buttonFinder);
    expect(
      labelRect.left,
      greaterThanOrEqualTo(buttonRect.left - 0.5),
      reason: '$expectedLabel must fit inside segment horizontally',
    );
    expect(
      labelRect.right,
      lessThanOrEqualTo(buttonRect.right + 0.5),
      reason: '$expectedLabel must fit inside segment horizontally',
    );
  }
}

Future<void> _expectDisplayModeControl(
  WidgetTester tester, {
  Axis? expectedDirection,
  required WidgetHostPlatform hostPlatform,
}) async {
  final segmentedFinder = _styleSelector(tester);
  await _scrollGalleryUntilVisible(tester, segmentedFinder, delta: -240);
  expect(segmentedFinder, findsOneWidget);

  // Check panel title
  final titleFinder = find.text(WidgetUiCopy.stylePanelTitle);
  expect(titleFinder, findsOneWidget);

  var waited = 0;
  while (tester
              .widget<SegmentedButton<WidgetDisplayMode>>(segmentedFinder)
              .onSelectionChanged ==
          null &&
      waited < 20) {
    await tester.pump(const Duration(milliseconds: 50));
    waited++;
  }

  final segmented = tester.widget<SegmentedButton<WidgetDisplayMode>>(
    segmentedFinder,
  );
  expect(
    segmented.onSelectionChanged,
    isNotNull,
    reason:
        'SegmentedButton<WidgetDisplayMode> must be enabled with onSelectionChanged',
  );
  if (expectedDirection != null) {
    expect(
      segmented.direction,
      expectedDirection,
      reason:
          'SegmentedButton<WidgetDisplayMode> direction should match expected axis.',
    );
  }

  for (final mode in WidgetDisplayMode.values) {
    final expectedLabel = hostPlatform == WidgetHostPlatform.android
        ? '${mode.label} ${mode.launcherRequestLabel}'
        : mode.label;
    final labelFinder = find.descendant(
      of: segmentedFinder,
      matching: find.text(expectedLabel),
    );
    expect(
      labelFinder,
      findsOneWidget,
      reason: 'Mode label $expectedLabel must be present',
    );
    await tester.ensureVisible(labelFinder);
    await tester.pumpAndSettle();

    final buttonFinder = find
        .ancestor(of: labelFinder, matching: find.byType(TextButton))
        .first;
    expect(buttonFinder.hitTestable(), findsOneWidget, reason: expectedLabel);

    final buttonSize = tester.getSize(buttonFinder);
    expect(
      buttonSize.height,
      greaterThanOrEqualTo(44.0),
      reason:
          '$expectedLabel touch target height must be at least 44 logical px',
    );
    expect(
      buttonSize.width,
      greaterThanOrEqualTo(44.0),
      reason:
          '$expectedLabel touch target width must be at least 44 logical px',
    );

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
      reason: 'Mode label $expectedLabel must not exceed max lines',
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

    final labelRect = tester.getRect(labelFinder);
    final buttonRect = tester.getRect(buttonFinder);
    expect(
      labelRect.left,
      greaterThanOrEqualTo(buttonRect.left - 0.5),
      reason: '$expectedLabel must fit inside segment horizontally',
    );
    expect(
      labelRect.right,
      lessThanOrEqualTo(buttonRect.right + 0.5),
      reason: '$expectedLabel must fit inside segment horizontally',
    );
  }

  // Check explanatory description text
  final selectedMode = segmented.selected.single;
  final descriptionFinder = find.text(
    WidgetUiCopy.hostStyleDescription(selectedMode.id, hostPlatform),
  );
  expect(descriptionFinder, findsOneWidget);
  final descParagraph = tester.renderObject<RenderParagraph>(descriptionFinder);
  expect(
    descParagraph.didExceedMaxLines,
    isFalse,
    reason: 'Explanatory description text must not exceed max lines',
  );
}

Future<void> _expectRetainedSelections(
  WidgetTester tester, {
  required WidgetCategory expectedCategory,
  required WidgetDisplayMode expectedDisplayMode,
}) async {
  await _scrollGalleryUntilVisible(tester, _categorySelector(tester));
  expect(
    tester
        .widget<SegmentedButton<WidgetCategory>>(_categorySelector(tester))
        .selected,
    {expectedCategory},
    reason: 'Category selection must be retained across state transition',
  );

  await _scrollGalleryUntilVisible(tester, _styleSelector(tester));
  expect(
    tester
        .widget<SegmentedButton<WidgetDisplayMode>>(_styleSelector(tester))
        .selected,
    {expectedDisplayMode},
    reason: 'Display mode selection must be retained across state transition',
  );
}

Color _resolveButtonForegroundColor(
  BuildContext context,
  TextButton button,
  Set<WidgetState> states,
) {
  final explicit = button.style?.foregroundColor?.resolve(states);
  if (explicit != null) return explicit;
  final themeStyle = Theme.of(context).textButtonTheme.style;
  final themed = themeStyle?.foregroundColor?.resolve(states);
  if (themed != null) return themed;
  return Theme.of(context).colorScheme.primary;
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
    reason: 'Signal never arrived: home widget save attempt timed out',
  );
}

Future<void> _settleAsyncWork(WidgetTester tester) async {
  for (var frame = 0; frame < 5; frame++) {
    await tester.pump(const Duration(milliseconds: 30));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
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
  final effectiveDir = directory.contains('evidence/screenshots')
      ? directory
      : 'evidence/screenshots/widget-control-priority-20261024';
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
  await tester.runAsync(() async {
    final context = key.currentContext;
    if (context == null) return;
    final boundary = context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final file = File('$effectiveDir/$filename');
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

class _ControlFixture {
  _ControlFixture._({
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
  final _ControlPreferenceStore preferenceStore;
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
      await _settleAsyncWork(tester);
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

  static Future<_ControlFixture> mount(
    WidgetTester tester, {
    required Size viewport,
    double dpr = 1.0,
    TextScaler? textScaler,
    double? textScale,
    String brandId = 'defaultBrand',
    String? initialSelectionJson,
  }) async {
    final effectiveTextScaler =
        textScaler ?? TextScaler.linear(textScale ?? 1.0);

    await tester.runAsync(loadWidgetPolishScreenshotFonts);

    SharedPreferences.resetStatic();
    final preferenceStore = _ControlPreferenceStore({
      'flutter.active_brand': brandId,
      'flutter.theme_shop_state': jsonEncode({
        'activeBrand': brandId,
        'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
      }),
      'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
      'flutter.${WidgetDisplayModeSelection.storageKey}':
          initialSelectionJson ??
          jsonEncode({
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

      final fixture = _ControlFixture._(
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
    TextTheme withScreenshotFonts(TextTheme text) => text.apply(
      fontFamily: 'DuoyiScreenshotLatin',
      fontFamilyFallback: const ['DuoyiScreenshot'],
    );
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
            theme: baseTheme.copyWith(
              textTheme: withScreenshotFonts(baseTheme.textTheme),
              primaryTextTheme: withScreenshotFonts(baseTheme.primaryTextTheme),
              snackBarTheme: baseTheme.snackBarTheme.copyWith(
                contentTextStyle: baseTheme.snackBarTheme.contentTextStyle
                    ?.copyWith(
                      fontFamily: 'DuoyiScreenshotLatin',
                      fontFamilyFallback: const ['DuoyiScreenshot'],
                    ),
              ),
            ),
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

class _ControlPreferenceStore extends InMemorySharedPreferencesStore {
  _ControlPreferenceStore(super.data) : super.withData();

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
  bool failNextDisplayModeSave = false;
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
          if (failNextDisplayModeSave) {
            failNextDisplayModeSave = false;
            return false;
          }
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
