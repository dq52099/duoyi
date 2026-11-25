// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/services/android_widget_manager.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/widget_polish_screenshot_font.dart';
import '../support/priority_theme_fixture.dart' show priorityLayouts;
import '../support/secondary_route_render_probe.dart';

const _screenshotEnv = 'DUOYI_CAPTURE_WIDGET_LOCALE_SCREENSHOTS';
const _screenshotDirectory = 'evidence/screenshots/widget-style-pin-20261015';
const _displayModeStorageKey = 'flutter.duoyi_widget_display_mode';

const _viewports = <_ViewportSpec>[
  _ViewportSpec('320x844', Size(320, 844)),
  _ViewportSpec('568x320', Size(568, 320)),
];

enum _StyleUiState { loading, failure, updating }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  bool? previousAndroidOverride;
  bool? previousHomeWidgetSupport;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
    previousAndroidOverride = AndroidWidgetManager.debugIsAndroidOverride;
    previousHomeWidgetSupport = HomeWidgetService.supportedForTesting;
    AndroidWidgetManager.debugIsAndroidOverride = true;
    HomeWidgetService.supportedForTesting = null;
  });

  tearDown(() {
    I18n.setLocale(AppLocale.zh);
    AndroidWidgetManager.debugIsAndroidOverride = previousAndroidOverride;
    HomeWidgetService.supportedForTesting = previousHomeWidgetSupport;
  });

  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in priorityLayouts) {
        _priorityStyleCase(
          brand,
          locale,
          layout.name,
          layout.size,
          layout.scale,
        );
      }
      _priorityStyleCase(
        brand,
        locale,
        'pushed',
        const Size(320, 844),
        2,
        pushed: true,
      );
    }
  }

  for (final brand in ['defaultBrand', 're0', 'starRail']) {
    for (final pushed in [false, true]) {
      testWidgets('legacy solid background $brand pushed=$pushed', (
        tester,
      ) async {
        final fixture = await _mount(
          tester,
          viewport: const _ViewportSpec('legacy', Size(390, 844)),
          initialMode: WidgetDisplayMode.standard,
          holdInitialRead: false,
          brandId: brand,
          pushed: pushed,
        );
        expect(fixture.theme.brand.id, brand);
        final expected = fixture.theme.brand.theme.scaffoldBackgroundColor;
        final rgba =
            ((expected.r * 255).round() << 24) |
            ((expected.g * 255).round() << 16) |
            ((expected.b * 255).round() << 8) |
            (expected.a * 255).round();
        final render =
            fixture.screenshotBoundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final actual = await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 1);
          try {
            final data = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            return [
              for (final point in [
                const Offset(2, 180),
                const Offset(387, 700),
              ])
                data.getUint32(
                  (point.dy.toInt() * image.width + point.dx.toInt()) * 4,
                ),
            ];
          } finally {
            image.dispose();
          }
        });
        expect(
          actual,
          everyElement(rgba),
          reason: 'Preserve legacy solid route fill',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final locale in AppLocale.values) {
    for (final viewport in _viewports) {
      for (final state in _StyleUiState.values) {
        testWidgets(
          'widget style ${state.name} is readable in ${locale.name} at ${viewport.name}',
          (tester) async {
            I18n.setLocale(locale);
            final fixture = await _mount(
              tester,
              viewport: viewport,
              initialMode: state == _StyleUiState.failure
                  ? WidgetDisplayMode.detailed
                  : WidgetDisplayMode.standard,
              holdInitialRead: state != _StyleUiState.updating,
            );

            switch (state) {
              case _StyleUiState.loading:
                await _waitFor(tester, fixture.store.readStarted!.future);
                await _pumpFrames(tester);
                await _scrollToPanelState(tester, state);
                _expectPanelStatus(tester, WidgetUiCopy.loadingStyle);
                expect(tester.takeException(), isNull);
                await _expectAddUnavailable(tester, WidgetUiCopy.loadingStyle);
                await _ensureVisibleForScreenshot(tester, state);
                await _capture(tester, fixture, viewport, locale, state);

                await tester.runAsync(() async {
                  await fixture.store.releaseReadWithStoredValues();
                  await Future<void>.delayed(const Duration(milliseconds: 20));
                });
                await _waitForLoaded(tester, WidgetDisplayMode.standard);
                break;

              case _StyleUiState.failure:
                await _waitFor(tester, fixture.store.readStarted!.future);
                await tester.runAsync(() async {
                  fixture.store.failRead(
                    StateError('held initial read failed'),
                  );
                  await Future<void>.delayed(const Duration(milliseconds: 20));
                });
                await _waitForFailure(tester);
                _expectPanelStatus(tester, WidgetUiCopy.styleLoadFailed);
                expect(
                  find.descendant(
                    of: _stylePanelFinder(tester),
                    matching: find.byKey(
                      const ValueKey('widget_style_load_retry'),
                    ),
                  ),
                  findsOneWidget,
                );
                expect(tester.takeException(), isNull);
                await _expectAddUnavailable(
                  tester,
                  WidgetUiCopy.styleLoadFailed,
                );
                await _ensureVisibleForScreenshot(tester, state);
                await _capture(tester, fixture, viewport, locale, state);

                final retry = find.byKey(
                  const ValueKey('widget_style_load_retry'),
                );
                await tester.ensureVisible(retry);
                await tester.tap(retry);
                await tester.pump();
                await _waitForLoaded(tester, WidgetDisplayMode.detailed);
                break;

              case _StyleUiState.updating:
                await _waitForLoaded(tester, WidgetDisplayMode.standard);
                final selector = _styleSelector(tester);
                await tester.runAsync(() async {
                  fixture.store.holdModeWrite();
                  selector.onSelectionChanged!({WidgetDisplayMode.detailed});
                  await fixture.store.modeWriteStarted!.future.timeout(
                    const Duration(seconds: 3),
                  );
                });
                await _pumpFrames(tester);
                expect(_styleSelector(tester).selected, {
                  WidgetDisplayMode.detailed,
                });
                expect(_styleSelector(tester).onSelectionChanged, isNull);
                expect(tester.takeException(), isNull);
                await _expectAddUnavailable(tester, WidgetUiCopy.updatingStyle);
                await _ensureVisibleForScreenshot(tester, state);
                await _capture(tester, fixture, viewport, locale, state);

                await tester.runAsync(() async {
                  fixture.store.modeWriteGate!.complete(true);
                  await AccountPreferenceWrites.drain();
                  await Future<void>.delayed(const Duration(milliseconds: 20));
                });
                await _waitForLoaded(tester, WidgetDisplayMode.detailed);
                break;
            }

            await _expectAddAvailable(
              tester,
              state == _StyleUiState.loading
                  ? WidgetDisplayMode.standard
                  : WidgetDisplayMode.detailed,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final locale in AppLocale.values) {
    for (final viewport in _viewports) {
      testWidgets(
        'widget size guidance is readable in ${locale.name} at ${viewport.name}',
        (tester) async {
          I18n.setLocale(locale);
          final fixture = await _mount(
            tester,
            viewport: viewport,
            initialMode: WidgetDisplayMode.standard,
            holdInitialRead: false,
          );
          for (final mode in WidgetDisplayMode.values) {
            await _scrollToPanel(tester);
            if (_styleSelector(tester).selected.single != mode) {
              _styleSelector(tester).onSelectionChanged!({mode});
              await _waitForLoaded(tester, mode);
            }
            ScaffoldMessenger.of(
              tester.element(find.byType(WidgetScreen)),
            ).removeCurrentSnackBar();
            await _pumpFrames(tester);
            final description = find.text(
              WidgetUiCopy.displayModeDescription(mode.id),
            );
            expect(description, findsOneWidget);
            await tester.ensureVisible(description);
            await _pumpFrames(tester);
            expect(description.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            await _capture(
              tester,
              fixture,
              viewport,
              locale,
              _StyleUiState.loading,
              label: 'guidance-${mode.id}',
            );
          }
          final tips = find.text(WidgetUiCopy.widgetTipsBannerMessage);
          await tester.scrollUntilVisible(
            tips,
            400,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.ensureVisible(tips);
          await _pumpFrames(tester);
          expect(tips.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _capture(
            tester,
            fixture,
            viewport,
            locale,
            _StyleUiState.loading,
            label: 'guidance-tips',
          );
        },
      );
    }
  }
}

void _priorityStyleCase(
  String brand,
  AppLocale locale,
  String layout,
  Size size,
  double scale, {
  bool pushed = false,
}) {
  final name = 'priority-style-$brand-${locale.name}-$layout';
  testWidgets(name, (tester) async {
    I18n.setLocale(locale);
    final fixture = await _mount(
      tester,
      viewport: _ViewportSpec(layout, size),
      initialMode: WidgetDisplayMode.detailed,
      holdInitialRead: true,
      brandId: brand,
      textScale: scale,
      pushed: pushed,
    );
    expect(fixture.theme.brand.id, brand);
    final probe = RouteRenderProbe(tester, fixture.screenshotBoundary, name);
    final retained = tester.state(find.byType(WidgetScreen));
    await _waitFor(tester, fixture.store.readStarted!.future);

    Future<void> measurePanel(String stage) async {
      await _scrollToPanel(tester);
      await probe.capture('$stage-panel');
      final panel = _stylePanelFinder(tester);
      final disabled = _styleSelector(tester).onSelectionChanged == null;
      final texts = tester
          .widgetList<Text>(
            find.descendant(of: panel, matching: find.byType(Text)),
          )
          .toList();
      for (var i = 0; i < texts.length; i++) {
        final text = texts[i];
        final finder = find.byWidget(text);
        final inSelector = find
            .ancestor(of: finder, matching: _styleSelectorFinder())
            .evaluate()
            .isNotEmpty;
        await probe.text(
          finder,
          role: '$stage panel text $i',
          // Disabled segment foregrounds are deliberately muted. Their full
          // label fitting is checked without treating disabled contrast as AA.
          contrast: !(disabled && inSelector),
          minimumGeometricScale: .999,
        );
      }
      await probe.capture('$stage-status');
    }

    Future<void> changeLocaleWithoutWrites(String stage) async {
      final writes = fixture.store.mutations;
      final native = fixture.nativeModeApplies;
      I18n.setLocale(
        I18n.current == AppLocale.zh ? AppLocale.en : AppLocale.zh,
      );
      await _pumpFrames(tester, count: 10);
      expect(tester.state(find.byType(WidgetScreen)), same(retained));
      expect(fixture.store.mutations, writes);
      expect(fixture.nativeModeApplies, native);
      await measurePanel('$stage-live');
    }

    await measurePanel('loading');
    await changeLocaleWithoutWrites('loading');
    await _expectAddUnavailable(tester, WidgetUiCopy.loadingStyle);
    await probe.capture('loading-add');

    await tester.runAsync(() async {
      fixture.store.failRead(StateError('synthetic style read refusal'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await _waitForFailure(tester);
    await measurePanel('failure');
    await _expectAddUnavailable(tester, WidgetUiCopy.styleLoadFailed);
    await _scrollToPanel(tester);
    final retry = find.byKey(const ValueKey('widget_style_load_retry'));
    await tester.ensureVisible(retry);
    await _pumpFrames(tester);
    expect(retry.hitTestable(), findsOneWidget);
    await tester.tap(retry);
    await _waitForLoaded(tester, WidgetDisplayMode.detailed);
    await measurePanel('loaded');
    await _expectAddAvailable(tester, WidgetDisplayMode.detailed);

    await _scrollToPanel(tester);
    final selector = _styleSelector(tester);
    await tester.runAsync(() async {
      fixture.store.holdModeWrite();
      selector.onSelectionChanged!({WidgetDisplayMode.standard});
      await fixture.store.modeWriteStarted!.future.timeout(
        const Duration(seconds: 3),
      );
    });
    await _pumpFrames(tester);
    expect(_styleSelector(tester).selected, {WidgetDisplayMode.standard});
    expect(_styleSelector(tester).onSelectionChanged, isNull);
    await measurePanel('updating');
    await changeLocaleWithoutWrites('updating');
    await _expectAddUnavailable(tester, WidgetUiCopy.updatingStyle);
    await probe.capture('updating-add');
    await tester.runAsync(() async {
      fixture.store.modeWriteGate!.complete(true);
      await AccountPreferenceWrites.drain();
    });
    await _waitForLoaded(tester, WidgetDisplayMode.standard);
    await _expectAddAvailable(tester, WidgetDisplayMode.standard);
    await measurePanel('saved');
    expect(tester.state(find.byType(WidgetScreen)), same(retained));

    // Read the real route's outer margins. After all lifecycle assertions and
    // gates finish, replace it with the real background alone to obtain an
    // independent reference; the reference never sits behind the tested page.
    final points = [
      Offset(2, size.height * .4),
      Offset(size.width - 3, size.height * .65),
      Offset(2, size.height - 24),
    ];
    Future<List<int>> pixels(GlobalKey boundary) async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      return (await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 1);
        try {
          final raw = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          return [
            for (final point in points)
              raw.getUint32(
                (point.dy.floor() * image.width + point.dx.floor()) * 4,
              ),
          ];
        } finally {
          image.dispose();
        }
      }))!;
    }

    final actual = await pixels(fixture.screenshotBoundary);
    final reference = GlobalKey();
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: fixture.theme,
        child: MaterialApp(
          theme: fixture.theme.brand.theme,
          home: RepaintBoundary(
            key: reference,
            child: Material(
              color: fixture.theme.brand.theme.scaffoldBackgroundColor,
              child: const BrandBackground(child: SizedBox.expand()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final expected = await pixels(reference);
    for (var i = 0; i < points.length; i++) {
      final equal = actual[i] == expected[i];
      probe.rows.add({
        'role': 'owned route background $i',
        'actualRGBA': actual[i],
        'referenceRGBA': expected[i],
        'matchesRealBrandBackground': equal,
        'glassReferenceRequired': brand == 'liquidGlass',
      });
      if (brand == 'liquidGlass' && !equal) {
        probe.errors.add('Glass backdrop hidden at route margin $i');
      }
      expect(actual[i] & 0xff, 255, reason: 'Route margin must remain opaque');
      expect(
        actual[i] >> 8,
        isNot(0),
        reason: 'Route margin must not turn black',
      );
    }
    await probe.finish();
  });
}

class _ViewportSpec {
  const _ViewportSpec(this.name, this.size);

  final String name;
  final Size size;
}

class _Fixture {
  _Fixture({
    required this.previousStore,
    required this.store,
    required this.theme,
    required this.screenshotBoundary,
    required this.previousAndroidOverride,
    required this.previousHomeWidgetSupport,
    this.textScale = 1.6,
    this.pushed = false,
  });

  final SharedPreferencesStorePlatform previousStore;
  final _WidgetStyleStore store;
  final ThemeProvider theme;
  final GlobalKey screenshotBoundary;
  final bool? previousAndroidOverride;
  final bool? previousHomeWidgetSupport;
  final double textScale;
  final bool pushed;
  int nativeModeApplies = 0;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
}

Future<_Fixture> _mount(
  WidgetTester tester, {
  required _ViewportSpec viewport,
  required WidgetDisplayMode initialMode,
  required bool holdInitialRead,
  String? brandId,
  double textScale = 1.6,
  bool pushed = false,
}) async {
  final theme = ThemeProvider();
  if (brandId != null) {
    // Theme loading must not consume the deliberately held widget-style read.
    SharedPreferences.setMockInitialValues({'active_brand': brandId});
    await tester.runAsync(theme.loadFromStorage);
    SharedPreferences.setMockInitialValues({});
  }
  final fixture = (await tester.runAsync(
    () async => _Fixture(
      previousStore: SharedPreferencesStorePlatform.instance,
      store: _WidgetStyleStore(
        initialValues: {_displayModeStorageKey: initialMode.id},
      ),
      theme: theme,
      screenshotBoundary: GlobalKey(),
      previousAndroidOverride: AndroidWidgetManager.debugIsAndroidOverride,
      previousHomeWidgetSupport: HomeWidgetService.supportedForTesting,
      textScale: textScale,
      pushed: pushed,
    ),
  ))!;

  SharedPreferencesStorePlatform.instance = fixture.store;
  tester.view.physicalSize = viewport.size;
  tester.view.devicePixelRatio = 1;
  // Keep actual platform fallback metrics in normal tests and screenshots.
  await tester.runAsync(() async {
    if (holdInitialRead) fixture.store.holdNextRead();
    await _loadWidgetStyleFonts();
  });

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(const MethodChannel('duoyi/widgets'), (
    call,
  ) {
    if (call.method == 'applyWidgetDisplayMode') {
      fixture.nativeModeApplies++;
    }
    return _handleWidgetMethod(call);
  });
  addTearDown(() async {
    fixture.store.releaseAllGates();
    await tester.runAsync(() async {
      await AccountPreferenceWrites.drain();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    messenger.setMockMethodCallHandler(
      const MethodChannel('duoyi/widgets'),
      null,
    );
    tester.view.reset();
    fixture.theme.dispose();
    SharedPreferencesStorePlatform.instance = fixture.previousStore;
    AndroidWidgetManager.debugIsAndroidOverride =
        fixture.previousAndroidOverride;
    HomeWidgetService.supportedForTesting = fixture.previousHomeWidgetSupport;
  });

  await tester.pumpWidget(_buildApp(fixture));
  await _pumpFrames(tester);
  if (pushed) {
    await tester.tap(find.text('Open synthetic widget catalog'));
    await _pumpFrames(tester, count: 10);
  }
  if (!holdInitialRead) {
    await _waitForLoaded(tester, initialMode);
  }
  return fixture;
}

Widget _buildApp(_Fixture fixture) {
  return ChangeNotifierProvider<ThemeProvider>.value(
    value: fixture.theme,
    child: MaterialApp(
      navigatorKey: fixture.navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: fixture.theme.brand.theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: fixture.textScale < 0
              ? const RouteProbeNonlinearScaler()
              : TextScaler.linear(fixture.textScale),
        ),
        child: RepaintBoundary(key: fixture.screenshotBoundary, child: child!),
      ),
      home: fixture.pushed
          ? Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BrandRouteSurface(
                        child: WidgetScreen(
                          hostPlatform: WidgetHostPlatform.android,
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open synthetic widget catalog'),
                ),
              ),
            )
          : const WidgetScreen(hostPlatform: WidgetHostPlatform.android),
    ),
  );
}

Future<void> _loadWidgetStyleFonts() async {
  await loadWidgetPolishScreenshotFonts();
  final latin = ByteData.sublistView(
    File('assets/fonts/DejaVuSans.ttf').readAsBytesSync(),
  );
  for (final family in ['sans-serif', 'DejaVu Sans', 'Roboto']) {
    await (FontLoader(family)..addFont(Future.value(latin))).load();
  }
  final chinese = ByteData.sublistView(
    File('assets/fonts/DroidSansFallbackFull.ttf').readAsBytesSync(),
  );
  for (final family in const [
    'PingFang SC',
    'Hiragino Sans GB',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
    'Microsoft YaHei',
    'WenQuanYi Micro Hei',
    'DroidSansFallbackFull',
  ]) {
    await (FontLoader(family)..addFont(Future.value(chinese))).load();
  }
  await PaintingBinding.instance.handleSystemMessage(<String, dynamic>{
    'type': 'fontsChange',
  });
}

Future<Object?> _handleWidgetMethod(MethodCall call) async {
  return switch (call.method) {
    'canRequestPinWidget' || 'canOpenWidgetSettings' => true,
    'applyWidgetDisplayMode' || 'refreshAllWidgets' => 0,
    _ => null,
  };
}

Future<void> _waitFor(WidgetTester tester, Future<void> future) async {
  await tester.runAsync(() => future.timeout(const Duration(seconds: 3)));
  await tester.pump();
}

Future<void> _pumpFrames(WidgetTester tester, {int count = 5}) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
}

Finder _styleSelectorFinder() => find.byWidgetPredicate(
  (widget) => widget is SegmentedButton<WidgetDisplayMode>,
);

SegmentedButton<WidgetDisplayMode> _styleSelector(WidgetTester tester) =>
    tester.widget<SegmentedButton<WidgetDisplayMode>>(_styleSelectorFinder());

Finder _stylePanelFinder(WidgetTester tester) => find
    .ancestor(
      of: find.text(WidgetUiCopy.stylePanelTitle),
      matching: find.byType(AppSurfaceCard),
    )
    .first;

Finder _panelStatusFinder(WidgetTester tester, String status) =>
    find.descendant(of: _stylePanelFinder(tester), matching: find.text(status));

void _expectPanelStatus(WidgetTester tester, String status) {
  expect(_panelStatusFinder(tester, status), findsOneWidget);
}

FilledButton _addButton(WidgetTester tester, DuoyiWidgetKind kind) =>
    tester.widget<FilledButton>(
      find
          .descendant(
            of: find.byKey(ValueKey(kind)),
            matching: find.byType(FilledButton),
          )
          .first,
    );

Finder _addRowFinder(DuoyiWidgetKind kind) => find.byKey(ValueKey(kind));

Finder _addRowTextFinder(DuoyiWidgetKind kind, String text) =>
    find.descendant(of: _addRowFinder(kind), matching: find.text(text));

Future<void> _scrollToPanel(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    _styleSelectorFinder(),
    -240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(_stylePanelFinder(tester));
  await _pumpFrames(tester, count: 2);
}

Future<void> _scrollToAdd(WidgetTester tester, DuoyiWidgetKind kind) async {
  await tester.scrollUntilVisible(
    _addRowFinder(kind),
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(_addRowFinder(kind));
  await _pumpFrames(tester, count: 2);
}

Future<void> _expectAddUnavailable(WidgetTester tester, String status) async {
  const kind = DuoyiWidgetKind.todo;
  await _scrollToAdd(tester, kind);
  expect(_addButton(tester, kind).onPressed, isNull);
  expect(_addRowTextFinder(kind, status), findsOneWidget);
}

Future<void> _expectAddAvailable(
  WidgetTester tester,
  WidgetDisplayMode mode,
) async {
  const kind = DuoyiWidgetKind.todo;
  await _scrollToAdd(tester, kind);
  expect(_addButton(tester, kind).onPressed, isNotNull);
  expect(
    _addRowTextFinder(
      kind,
      WidgetUiCopy.addWidgetButtonLabel(
        modeLabel: mode.label,
        launcherRequestLabel: mode.launcherRequestLabel,
      ),
    ),
    findsOneWidget,
  );
  for (final status in [
    WidgetUiCopy.loadingStyle,
    WidgetUiCopy.styleLoadFailed,
    WidgetUiCopy.updatingStyle,
  ]) {
    expect(_addRowTextFinder(kind, status), findsNothing);
  }
}

Future<void> _waitForLoaded(WidgetTester tester, WidgetDisplayMode mode) async {
  await _scrollToPanel(tester);
  for (var attempt = 0; attempt < 40; attempt++) {
    await _pumpFrames(tester, count: 1);
    final selector = _styleSelector(tester);
    if (selector.selected.single == mode &&
        selector.onSelectionChanged != null &&
        _panelStatusFinder(
          tester,
          WidgetUiCopy.loadingStyle,
        ).evaluate().isEmpty &&
        _panelStatusFinder(
          tester,
          WidgetUiCopy.styleLoadFailed,
        ).evaluate().isEmpty &&
        _panelStatusFinder(
          tester,
          WidgetUiCopy.updatingStyle,
        ).evaluate().isEmpty) {
      return;
    }
  }
  expect(_styleSelector(tester).selected, {mode});
  expect(_styleSelector(tester).onSelectionChanged, isNotNull);
  expect(_panelStatusFinder(tester, WidgetUiCopy.loadingStyle), findsNothing);
  expect(
    _panelStatusFinder(tester, WidgetUiCopy.styleLoadFailed),
    findsNothing,
  );
  expect(_panelStatusFinder(tester, WidgetUiCopy.updatingStyle), findsNothing);
}

Future<void> _waitForFailure(WidgetTester tester) async {
  await _scrollToPanel(tester);
  for (var attempt = 0; attempt < 40; attempt++) {
    await _pumpFrames(tester, count: 1);
    if (_panelStatusFinder(
      tester,
      WidgetUiCopy.styleLoadFailed,
    ).evaluate().isNotEmpty) {
      return;
    }
  }
  expect(
    _panelStatusFinder(tester, WidgetUiCopy.styleLoadFailed),
    findsOneWidget,
  );
}

Future<void> _scrollToPanelState(
  WidgetTester tester,
  _StyleUiState state,
) async {
  await _scrollToPanel(tester);
  final target = switch (state) {
    _StyleUiState.loading => find.text(WidgetUiCopy.loadingStyle).first,
    _StyleUiState.failure => find.byKey(
      const ValueKey('widget_style_load_retry'),
    ),
    _StyleUiState.updating => find.descendant(
      of: find.byKey(const ValueKey(DuoyiWidgetKind.todo)),
      matching: find.text(WidgetUiCopy.updatingStyle),
    ),
  };
  await Scrollable.ensureVisible(
    tester.element(target),
    alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
  );
  await _pumpFrames(tester, count: 2);
}

Future<void> _ensureVisibleForScreenshot(
  WidgetTester tester,
  _StyleUiState state,
) async {
  if (state == _StyleUiState.updating) {
    await _scrollToAdd(tester, DuoyiWidgetKind.todo);
    // Keep some of the matching preview above the operation in the image.
    await tester.drag(find.byType(ListView).first, const Offset(0, 180));
    await _pumpFrames(tester, count: 2);
    await Scrollable.ensureVisible(
      tester.element(
        _addRowTextFinder(DuoyiWidgetKind.todo, WidgetUiCopy.updatingStyle),
      ),
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
    await _pumpFrames(tester, count: 2);
    return;
  }
  await _scrollToPanelState(tester, state);
}

Future<void> _capture(
  WidgetTester tester,
  _Fixture fixture,
  _ViewportSpec viewport,
  AppLocale locale,
  _StyleUiState state, {
  String? label,
}) async {
  expect(tester.getSize(find.byKey(fixture.screenshotBoundary)), viewport.size);
  if (Platform.environment[_screenshotEnv] != '1') return;
  await _pumpFrames(tester, count: 2);
  await tester.runAsync(() async {
    final boundary =
        fixture.screenshotBoundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final directory =
        Platform.environment['DUOYI_WIDGET_SCREENSHOT_DIR'] ??
        _screenshotDirectory;
    final file = File(
      '$directory/${locale.name}-${viewport.name}-${label ?? state.name}.png',
    );
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

class _WidgetStyleStore extends InMemorySharedPreferencesStore {
  _WidgetStyleStore({required Map<String, Object> initialValues})
    : super.withData(initialValues);

  Completer<void>? readStarted;
  Completer<Map<String, Object>>? readGate;
  Completer<void>? modeWriteStarted;
  Completer<bool>? modeWriteGate;
  bool _holdNextRead = false;
  bool _holdNextModeWrite = false;
  int mutations = 0;

  void holdNextRead() {
    readStarted = Completer<void>();
    readGate = Completer<Map<String, Object>>();
    _holdNextRead = true;
  }

  void holdModeWrite() {
    modeWriteStarted = Completer<void>();
    modeWriteGate = Completer<bool>();
    _holdNextModeWrite = true;
  }

  Future<void> releaseReadWithStoredValues() async {
    final values = await super.getAll();
    if (readGate != null && !readGate!.isCompleted) readGate!.complete(values);
  }

  void failRead(Object error) {
    final gate = readGate;
    if (gate != null && !gate.isCompleted) gate.completeError(error);
  }

  void releaseAllGates() {
    final read = readGate;
    if (read != null && !read.isCompleted) read.complete(<String, Object>{});
    final modeWrite = modeWriteGate;
    if (modeWrite != null && !modeWrite.isCompleted) modeWrite.complete(true);
  }

  @override
  Future<Map<String, Object>> getAll() async {
    if (_holdNextRead) {
      _holdNextRead = false;
      readStarted!.complete();
      return readGate!.future;
    }
    return super.getAll();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    mutations++;
    if (key == _displayModeStorageKey && _holdNextModeWrite) {
      _holdNextModeWrite = false;
      modeWriteStarted!.complete();
      if (!await modeWriteGate!.future) return false;
    }
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) {
    mutations++;
    return super.remove(key);
  }

  @override
  Future<bool> clear() {
    mutations++;
    return super.clear();
  }
}
