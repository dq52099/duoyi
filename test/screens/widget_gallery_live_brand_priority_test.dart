// ignore_for_file: depend_on_referenced_packages

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

import '../support/widget_polish_screenshot_font.dart';

const _widgetChannel = MethodChannel('duoyi/widgets');
const _narrow = Size(320, 844);
const _tablet = Size(1024, 900);

class _GalleryBrandScenario {
  const _GalleryBrandScenario({
    required this.viewport,
    required this.viewportName,
    required this.textScale,
    required this.locale,
  });

  final Size viewport;
  final String viewportName;
  final double textScale;
  final AppLocale locale;

  String get label => '${locale.name} / $viewportName';
}

const _scenarios = [
  _GalleryBrandScenario(
    viewport: _narrow,
    viewportName: 'narrow-320x844',
    textScale: 1.6,
    locale: AppLocale.zh,
  ),
  _GalleryBrandScenario(
    viewport: _narrow,
    viewportName: 'narrow-320x844',
    textScale: 1.6,
    locale: AppLocale.en,
  ),
  _GalleryBrandScenario(
    viewport: _tablet,
    viewportName: 'tablet-1024x900',
    textScale: 1.0,
    locale: AppLocale.zh,
  ),
  _GalleryBrandScenario(
    viewport: _tablet,
    viewportName: 'tablet-1024x900',
    textScale: 1.0,
    locale: AppLocale.en,
  ),
];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
    AndroidWidgetManager.debugIsAndroidOverride = true;
  });

  tearDown(() {
    I18n.setLocale(AppLocale.zh);
    AndroidWidgetManager.debugIsAndroidOverride = null;
  });

  for (final scenario in _scenarios) {
    testWidgets(
      'gallery live brand priority roundtrip defaultBrand <-> liquidGlass: ${scenario.label}',
      (tester) async {
        I18n.setLocale(scenario.locale);
        final fixture = await _GalleryFixture.mount(
          tester,
          viewport: scenario.viewport,
          textScale: scenario.textScale,
          locale: scenario.locale,
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

        // Verify initial theme and surface contracts
        expect(fixture.theme.brand.id, 'defaultBrand');
        expect(fixture.theme.activeWidgetBackgroundBrand.id, 'defaultBrand');
        expect(fixture.theme.isBrandUnlocked('liquidGlass'), isTrue);
        expect(
          Theme.of(tester.element(screenFinder)).extension<AppSurfaceStyle>(),
          same(AppSurfaceStyle.ios),
        );
        final initialScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(initialScaffold.backgroundColor, isNot(Colors.transparent));

        // 1. Select non-default category (life)
        await _selectCategory(tester, WidgetCategory.life);
        expect(_selectedCategory(tester), {WidgetCategory.life});
        expect(_galleryGroup(DuoyiWidgetKind.todo), findsNothing);
        expect(fixture.preferenceStore.widgetPreferenceWrites, isEmpty);

        // 2. Select non-default display style (detailed)
        await _selectDisplayMode(tester, WidgetDisplayMode.detailed);
        await _drainPreferenceWrites(tester);
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        expect(_selectedDisplayMode(tester), {WidgetDisplayMode.detailed});

        final writesAfterSelection = List<String>.of(
          fixture.preferenceStore.widgetPreferenceWrites,
        );
        expect(writesAfterSelection, isNotEmpty);
        expect(
          writesAfterSelection.toSet(),
          everyElement(
            isIn({
              'flutter.${WidgetDisplayModeSelection.storageKey}',
              'flutter.${WidgetDisplayModeSelection.legacyKey}',
            }),
          ),
        );

        // 3. Scroll to non-zero offset within the filtered category
        await tester.scrollUntilVisible(
          _galleryGroup(DuoyiWidgetKind.diary),
          240,
          scrollable: _galleryScrollable(tester),
          maxScrolls: 50,
        );
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
        expect(_galleryGroup(DuoyiWidgetKind.diary), findsOneWidget);

        final scrollableBeforeSwitch = tester.state<ScrollableState>(
          _galleryScrollable(tester),
        );
        final offsetBeforeSwitch = scrollableBeforeSwitch.position.pixels;
        expect(
          offsetBeforeSwitch,
          greaterThan(0.0),
          reason:
              'Initial gallery state must establish a non-zero scroll offset',
        );

        await _captureIfRequested(
          tester,
          fixture.captureKey,
          'gallery-brand-${scenario.viewportName}-${scenario.locale.name}-01-defaultBrand.png',
        );

        // State 2: Switch brand to liquidGlass via actual ThemeProvider.setBrand
        await tester.runAsync(() async {
          final switched = await fixture.theme.setBrand('liquidGlass');
          expect(switched, isTrue);
        });
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );

        // Invariants after switching to liquidGlass
        expect(fixture.theme.brand.id, 'liquidGlass');
        expect(fixture.theme.activeWidgetBackgroundBrand.id, 'liquidGlass');
        expect(
          Theme.of(tester.element(screenFinder)).extension<AppSurfaceStyle>(),
          same(AppSurfaceStyle.liquidGlass),
        );
        final glassScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(glassScaffold.backgroundColor, Colors.transparent);

        expect(
          tester.state(screenFinder),
          same(initialScreenState),
          reason:
              'WidgetScreen state identity must be retained across brand switch',
        );
        expect(
          ModalRoute.of(tester.element(screenFinder)),
          same(initialRoute),
          reason: 'ModalRoute identity must be retained across brand switch',
        );

        final scrollableStage2 = tester.state<ScrollableState>(
          _galleryScrollable(tester),
        );
        final controllerStage2 =
            scrollableStage2.widget.controller ??
            PrimaryScrollController.of(tester.element(screenFinder));
        expect(
          controllerStage2,
          same(initialController),
          reason:
              'ScrollController identity must be preserved across switch to liquidGlass',
        );
        expect(
          scrollableStage2.position.pixels,
          closeTo(offsetBeforeSwitch, 1.0),
          reason:
              'Non-zero scroll offset must be preserved across switch to liquidGlass',
        );

        await _expectRetainedSelectors(tester, offsetBeforeSwitch);
        expect(_galleryGroup(DuoyiWidgetKind.diary), findsOneWidget);
        expect(_galleryGroup(DuoyiWidgetKind.todo), findsNothing);

        expect(
          fixture.preferenceStore.widgetPreferenceWrites,
          writesAfterSelection,
          reason: 'Switching theme must not write extra widget preferences',
        );

        await _captureIfRequested(
          tester,
          fixture.captureKey,
          'gallery-brand-${scenario.viewportName}-${scenario.locale.name}-02-liquidGlass.png',
        );

        // State 3: Revert brand to defaultBrand via actual ThemeProvider.setBrand
        await tester.runAsync(() async {
          final reverted = await fixture.theme.setBrand('defaultBrand');
          expect(reverted, isTrue);
        });
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );

        // Invariants after reverting to defaultBrand
        expect(fixture.theme.brand.id, 'defaultBrand');
        expect(fixture.theme.activeWidgetBackgroundBrand.id, 'defaultBrand');
        expect(
          Theme.of(tester.element(screenFinder)).extension<AppSurfaceStyle>(),
          same(AppSurfaceStyle.ios),
        );
        final revertedScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(revertedScaffold.backgroundColor, isNot(Colors.transparent));

        expect(
          tester.state(screenFinder),
          same(initialScreenState),
          reason:
              'WidgetScreen state identity must be retained when reverting brand',
        );
        expect(
          ModalRoute.of(tester.element(screenFinder)),
          same(initialRoute),
          reason: 'ModalRoute identity must be retained when reverting brand',
        );

        final scrollableStage3 = tester.state<ScrollableState>(
          _galleryScrollable(tester),
        );
        final controllerStage3 =
            scrollableStage3.widget.controller ??
            PrimaryScrollController.of(tester.element(screenFinder));
        expect(
          controllerStage3,
          same(initialController),
          reason:
              'ScrollController identity must be preserved when reverting to defaultBrand',
        );
        expect(
          scrollableStage3.position.pixels,
          closeTo(offsetBeforeSwitch, 1.0),
          reason:
              'Non-zero scroll offset must be preserved when reverting to defaultBrand',
        );

        await _expectRetainedSelectors(tester, offsetBeforeSwitch);
        expect(_galleryGroup(DuoyiWidgetKind.diary), findsOneWidget);
        expect(_galleryGroup(DuoyiWidgetKind.todo), findsNothing);

        expect(
          fixture.preferenceStore.widgetPreferenceWrites,
          writesAfterSelection,
          reason: 'Reverting theme must not write extra widget preferences',
        );

        await _captureIfRequested(
          tester,
          fixture.captureKey,
          'gallery-brand-${scenario.viewportName}-${scenario.locale.name}-03-reverted-defaultBrand.png',
        );

        expect(tester.takeException(), isNull);
      },
    );
  }
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

Future<void> _expectRetainedSelectors(
  WidgetTester tester,
  double restoreOffset,
) async {
  await _scrollGalleryUntilVisible(tester, _categorySelector(tester));
  expect(_selectedCategory(tester), {WidgetCategory.life});
  await _scrollGalleryUntilVisible(tester, _styleSelector(tester));
  expect(_selectedDisplayMode(tester), {WidgetDisplayMode.detailed});
  final state = tester.state<ScrollableState>(_galleryScrollable(tester));
  state.position.jumpTo(restoreOffset);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
  expect(state.position.pixels, closeTo(restoreOffset, 1));
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

Future<void> _selectDisplayMode(
  WidgetTester tester,
  WidgetDisplayMode mode,
) async {
  final control = _styleSelector(tester);
  await _scrollGalleryUntilVisible(tester, control, delta: -240);
  final label = find.descendant(
    of: control,
    matching: find.text('${mode.label} ${mode.launcherRequestLabel}'),
  );
  await tester.ensureVisible(label);
  await tester.tap(label);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

Set<WidgetCategory> _selectedCategory(WidgetTester tester) => tester
    .widget<SegmentedButton<WidgetCategory>>(_categorySelector(tester))
    .selected;

Set<WidgetDisplayMode> _selectedDisplayMode(WidgetTester tester) => tester
    .widget<SegmentedButton<WidgetDisplayMode>>(_styleSelector(tester))
    .selected;

Finder _categorySelector(WidgetTester tester) => find.byWidgetPredicate(
  (widget) => widget is SegmentedButton<WidgetCategory>,
);

Finder _styleSelector(WidgetTester tester) => find.byWidgetPredicate(
  (widget) => widget is SegmentedButton<WidgetDisplayMode>,
);

Finder _galleryGroup(DuoyiWidgetKind kind) =>
    find.byKey(ValueKey('widget_gallery_${kind.name}'));

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

Future<void> _captureIfRequested(
  WidgetTester tester,
  GlobalKey key,
  String filename,
) async {
  final directory =
      Platform.environment['DUOYI_GALLERY_BRAND_SCREENSHOT_DIR'] ??
      Platform.environment['DUOYI_WIDGET_SCREENSHOT_DIR'];
  if (directory == null || directory.isEmpty) return;
  final effectiveDir = directory.contains('evidence/screenshots')
      ? directory
      : 'evidence/screenshots/widget-live-parallel-20261023/gallery-brand';
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

class _GalleryFixture {
  _GalleryFixture._({
    required this.theme,
    required this.channels,
    required this.preferenceStore,
    required this.captureKey,
    required this.viewport,
    required this.textScale,
  });

  final ThemeProvider theme;
  final _WidgetChannels channels;
  final _GalleryPreferenceStore preferenceStore;
  final GlobalKey captureKey;
  final Size viewport;
  final double textScale;

  static Future<_GalleryFixture> mount(
    WidgetTester tester, {
    required Size viewport,
    required double textScale,
    required AppLocale locale,
  }) async {
    await tester.runAsync(loadWidgetPolishScreenshotFonts);
    final preferenceStore = _GalleryPreferenceStore({
      'flutter.active_brand': 'defaultBrand',
      'flutter.theme_shop_state': jsonEncode({
        'activeBrand': 'defaultBrand',
        'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
      }),
      'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
    });
    SharedPreferencesStorePlatform.instance = preferenceStore;

    final theme = ThemeProvider();
    await tester.runAsync(() async {
      await theme.loadFromStorage();
    });

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewport;

    final channels = _WidgetChannels();
    final captureKey = GlobalKey();
    final fixture = _GalleryFixture._(
      theme: theme,
      channels: channels,
      preferenceStore: preferenceStore,
      captureKey: captureKey,
      viewport: viewport,
      textScale: textScale,
    );

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_widgetChannel, channels.handle);

    addTearDown(() async {
      await _drainPreferenceWrites(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      messenger.setMockMethodCallHandler(_widgetChannel, null);
      AndroidWidgetManager.debugIsAndroidOverride = null;
      tester.view.reset();
      theme.dispose();
    });

    await tester.pumpWidget(fixture._app(locale));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    return fixture;
  }

  Widget _app(AppLocale locale) {
    TextTheme withScreenshotFonts(TextTheme text) => text.apply(
      fontFamily: 'DuoyiScreenshotLatin',
      fontFamilyFallback: const ['DuoyiScreenshot'],
    );
    return ChangeNotifierProvider<ThemeProvider>.value(
      value: theme,
      child: AnimatedBuilder(
        animation: Listenable.merge([theme, I18n.localeListenable]),
        builder: (context, _) {
          final baseTheme = theme.brand.theme;
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: Locale(locale == AppLocale.en ? 'en' : 'zh'),
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
                size: viewport,
                textScaler: TextScaler.linear(textScale),
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

class _GalleryPreferenceStore extends InMemorySharedPreferencesStore {
  _GalleryPreferenceStore(super.data) : super.withData();

  final widgetPreferenceWrites = <String>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.startsWith('flutter.duoyi_widget_')) {
      widgetPreferenceWrites.add(key);
    }
    return super.setValue(valueType, key, value);
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
