// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/services/android_widget_manager.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandBackground;
import 'package:duoyi/widgets/surface_components.dart'
    show
        AppDialog,
        appSecondaryFilledButtonStyle,
        appSurfaceStyleOf,
        appContrastRatio;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/rendered_control_contrast.dart'
    show expectReadableControl, expectControlTouchTarget;
import '../support/secondary_route_render_probe.dart'
    show RouteProbeNonlinearScaler;
import '../support/weekly_review_screenshot_font.dart'
    show loadWeeklyReviewScreenshotFonts;

class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore(super.data) : super.withData();
  final List<String> modifiedKeys = [];

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    modifiedKeys.add(key);
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    modifiedKeys.add(key);
    return super.remove(key);
  }
}

class _MutableLock extends AppLockProvider {
  bool _locked = false;

  @override
  bool get isLocked => _locked;

  void setLocked(bool value) {
    _locked = value;
    notifyListeners();
  }
}

class _MutableAuthProvider extends AuthProvider {
  int _generation = 0;

  @override
  int get sessionGeneration => _generation;

  void switchAccount() {
    _generation++;
    notifyListeners();
  }
}

class _MutableUpdateService extends AppUpdateService {
  _MutableUpdateService()
    : super(repo: 'dq52099/duoyi', currentVersion: '1.0.0');
}

class _WidgetChannels {
  final List<String> methodCalls = [];
  int supportCalls = 0;
  int canOpenSettingsCalls = 0;
  int openSettingsCalls = 0;
  int pinRequestCalls = 0;

  Future<Object?> handleWidgets(MethodCall call) async {
    methodCalls.add(call.method);
    switch (call.method) {
      case 'canRequestPinWidget':
        supportCalls++;
        return false;
      case 'canOpenWidgetSettings':
        canOpenSettingsCalls++;
        return false;
      case 'openWidgetSettings':
        openSettingsCalls++;
        return false;
      case 'requestPinWidget':
        pinRequestCalls++;
        return 'unsupported_platform';
      case 'applyWidgetDisplayMode':
      case 'refreshAllWidgets':
        return 0;
      case 'clearPinResult':
      case 'cancelPinRequest':
        return null;
      default:
        return null;
    }
  }

  Future<Object?> handlePinResults(MethodCall call) async {
    methodCalls.add('pinResults.${call.method}');
    return null;
  }
}

Future<int> _boundedPumpAndSettle(
  WidgetTester tester, {
  Duration duration = const Duration(milliseconds: 50),
  EnginePhase phase = EnginePhase.sendSemanticsUpdate,
  Duration timeout = const Duration(seconds: 5),
}) {
  return tester.pumpAndSettle(duration, phase, timeout);
}

Future<void> _drainAccountWrites(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.runAsync(() => AccountPreferenceWrites.drain().timeout(timeout));
}

Future<void> _pumpThemeSwitchFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.runAsync(
    () => AccountPreferenceWrites.drain().timeout(const Duration(seconds: 5)),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final explicitDir =
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
  if (explicitDir == null || explicitDir.isEmpty) return;

  final normalized = explicitDir.replaceAll('\\', '/');
  if (!normalized.startsWith('evidence/screenshots') &&
      !normalized.contains('/evidence/screenshots')) {
    return;
  }

  await tester.runAsync(() async {
    final context = boundaryKey.currentContext;
    if (context == null) {
      throw StateError(
        'Cannot capture screenshot "$name": boundaryKey context is null',
      );
    }
    final boundary = context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError(
        'Cannot capture screenshot "$name": RepaintBoundary render object not found for boundaryKey $boundaryKey',
      );
    }
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError(
          'Cannot capture screenshot "$name": image.toByteData returned null',
        );
      }
      final file = File('$explicitDir/widget-real-dark-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

class _DarkScenario {
  final String name;
  final AppLocale locale;
  final String brandId;
  final Size size;
  final TextScaler textScaler;
  final DuoyiWidgetKind targetKind;

  const _DarkScenario({
    required this.name,
    required this.locale,
    required this.brandId,
    required this.size,
    required this.textScaler,
    required this.targetKind,
  });
}

const _darkScenarios = <_DarkScenario>[
  _DarkScenario(
    name: 'zh-portrait-320x844-scale200-dark',
    locale: AppLocale.zh,
    brandId: 'starRail',
    size: Size(320, 844),
    textScaler: TextScaler.linear(2.0),
    targetKind: DuoyiWidgetKind.todo,
  ),
  _DarkScenario(
    name: 'en-portrait-320x844-scale200-dark',
    locale: AppLocale.en,
    brandId: 'starRail',
    size: Size(320, 844),
    textScaler: TextScaler.linear(2.0),
    targetKind: DuoyiWidgetKind.habit,
  ),
  _DarkScenario(
    name: 'zh-landscape-844x390-scale100-dark',
    locale: AppLocale.zh,
    brandId: 'starRail',
    size: Size(844, 390),
    textScaler: TextScaler.linear(1.0),
    targetKind: DuoyiWidgetKind.focus,
  ),
  _DarkScenario(
    name: 'en-portrait-332x844-nonlinear-zzz-dark',
    locale: AppLocale.en,
    brandId: 'zzz',
    size: Size(332, 844),
    textScaler: RouteProbeNonlinearScaler(),
    targetKind: DuoyiWidgetKind.calendar,
  ),
];

class _Fixture {
  late final SharedPreferences prefs;
  late final ThemeProvider theme;
  late final PreferencesProvider preferences;
  late final _MutableLock lock;
  late final _MutableAuthProvider auth;
  late final _MutableUpdateService updater;
  final channels = _WidgetChannels();
  final navigatorKey = GlobalKey<NavigatorState>();
  final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final boundaryKey = GlobalKey();
  final activityRevision = ValueNotifier(0);
  bool _installed = false;
  bool _disposed = false;

  Future<void> mount(
    WidgetTester tester, {
    required String initialBrand,
    required AppLocale initialLocale,
    required Size size,
    required TextScaler textScaler,
    WidgetHostPlatform hostPlatform = WidgetHostPlatform.ios,
  }) async {
    if (!_installed) {
      _installed = true;

      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('duoyi/widgets'),
        channels.handleWidgets,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('duoyi/widget_pin_results'),
        channels.handlePinResults,
      );
      AndroidWidgetManager.debugIsAndroidOverride =
          hostPlatform == WidgetHostPlatform.android;

      await tester.runAsync(() async {
        prefs = await SharedPreferences.getInstance();
        theme = ThemeProvider();
        preferences = PreferencesProvider();
        lock = _MutableLock();
        auth = _MutableAuthProvider();
        updater = _MutableUpdateService();

        await theme.loadFromStorage().timeout(const Duration(seconds: 5));
        await preferences.loadFromStorage().timeout(const Duration(seconds: 5));

        // Unconditionally load production screenshot fonts without silent fallback
        await loadWeeklyReviewScreenshotFonts().timeout(
          const Duration(seconds: 5),
        );
      });
      await _drainAccountWrites(tester);
    }

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
          ChangeNotifierProvider<AppLockProvider>.value(value: lock),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<AppUpdateService>.value(value: updater),
        ],
        child: Consumer<ThemeProvider>(
          builder:
              (context, currentTheme, _) => ValueListenableBuilder<AppLocale>(
                valueListenable: I18n.localeListenable,
                builder:
                    (context, currentLocale, _) => MaterialApp(
                      navigatorKey: navigatorKey,
                      scaffoldMessengerKey: scaffoldMessengerKey,
                      debugShowCheckedModeBanner: false,
                      locale: Locale(
                        currentLocale == AppLocale.en ? 'en' : 'zh',
                      ),
                      supportedLocales: const [Locale('en'), Locale('zh')],
                      localizationsDelegates:
                          GlobalMaterialLocalizations.delegates,
                      theme: currentTheme.brand.theme,
                      builder:
                          (context, child) => MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              size: size,
                              textScaler: textScaler,
                            ),
                            child: RepaintBoundary(
                              key: boundaryKey,
                              child: child!,
                            ),
                          ),
                      home: Stack(
                        children: [
                          BrandBackground(
                            child: WidgetScreen(
                              key: const ValueKey('live-brand-widget-screen'),
                              hostPlatform: hostPlatform,
                              isActive: true,
                              activityRevision: activityRevision,
                            ),
                          ),
                          for (final brand in [
                            AppBrands.starRail,
                            AppBrands.defaultBrand,
                            AppBrands.liquidGlass,
                            AppBrands.zzz,
                          ])
                            Offstage(
                              offstage: true,
                              child: Theme(
                                data: brand.theme,
                                child: Builder(
                                  key: ValueKey('ref_theme_${brand.id}'),
                                  builder:
                                      (refContext) => const SizedBox.shrink(),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
              ),
        ),
      ),
    );
    await _boundedPumpAndSettle(tester);
  }

  Future<void> dispose(WidgetTester tester) async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _drainAccountWrites(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await _boundedPumpAndSettle(tester);
    } finally {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('duoyi/widgets'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('duoyi/widget_pin_results'),
        null,
      );
      AndroidWidgetManager.debugIsAndroidOverride = null;
      tester.view.reset();
      if (_installed) {
        theme.dispose();
        preferences.dispose();
        lock.dispose();
        auth.dispose();
        updater.dispose();
      }
      activityRevision.dispose();
    }
  }
}

/// Precisely resolves the action button in [AppDialog] corresponding to [WidgetUiCopy.actionGotIt].
/// Avoids forcing [FilledButton] as the only button type, avoiding stale text closures across
/// locale switches and avoiding loose `.first` finders.
Finder _dialogActionFinder(Finder dialogFinder) {
  final targetText = find.descendant(
    of: dialogFinder,
    matching: find.text(WidgetUiCopy.actionGotIt),
  );
  return find.descendant(
    of: dialogFinder,
    matching: find.ancestor(
      of: targetText,
      matching: find.byWidgetPredicate(
        (w) => w is ButtonStyleButton || w is MaterialButton,
      ),
    ),
  );
}

Future<void> _assertReadableTextOnSurface(
  WidgetTester tester, {
  required Finder textFinder,
  required Finder surfaceFinder,
  required GlobalKey boundaryKey,
  required String role,
  Finder? scrollableFinder,
}) async {
  expect(textFinder, findsOneWidget, reason: '$role text must exist');

  // 1. Ensure target is visible in its scrollable before inspecting geometry
  if (scrollableFinder != null) {
    await tester.scrollUntilVisible(
      textFinder,
      80.0,
      scrollable: scrollableFinder,
    );
    final element = tester.element(textFinder);
    await Scrollable.ensureVisible(element, alignment: 0.5);
    await _boundedPumpAndSettle(tester);
  }

  final rich = find.descendant(of: textFinder, matching: find.byType(RichText));
  final target = rich.evaluate().isNotEmpty ? rich : textFinder;
  final paragraph = tester.renderObject<RenderParagraph>(target);

  // Core readability: no truncation / didExceedMaxLines must be false
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '$role didExceedMaxLines must be false (no line truncation)',
  );

  final text = paragraph.text.toPlainText();
  expect(text.trim(), isNotEmpty, reason: '$role text must not be empty');

  // Helper to recompute visible clipping rect: screen ∩ surface ∩ scroll viewport
  Rect computeVisibleClipRect() {
    final renderBoundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final screenRect = Offset.zero & renderBoundary.size;

    final surfaceBox = tester.renderObject<RenderBox>(surfaceFinder);
    final surfaceRect = MatrixUtils.transformRect(
      surfaceBox.getTransformTo(renderBoundary),
      Offset.zero & surfaceBox.size,
    );

    Rect clipRect = screenRect.intersect(surfaceRect);

    if (scrollableFinder != null) {
      final viewportFinder = find.descendant(
        of: scrollableFinder,
        matching: find.byType(Viewport),
      );
      if (viewportFinder.evaluate().isNotEmpty) {
        final viewportBox = tester.renderObject<RenderBox>(
          viewportFinder.first,
        );
        final viewportRect = MatrixUtils.transformRect(
          viewportBox.getTransformTo(renderBoundary),
          Offset.zero & viewportBox.size,
        );
        clipRect = clipRect.intersect(viewportRect);
      }
    }
    return clipRect;
  }

  // Iterate over each non-whitespace character / rune
  var nonWhitespaceGlyphCount = 0;
  int i = 0;
  while (i < text.length) {
    final codeUnit = text.codeUnitAt(i);
    int end = i + 1;
    if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF && end < text.length) {
      end = i + 2;
    }
    final cluster = text.substring(i, end);
    if (cluster.trim().isNotEmpty) {
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: end),
      );
      expect(
        boxes,
        isNotEmpty,
        reason: '$role cluster "$cluster" must yield laid-out glyph box',
      );

      for (final box in boxes) {
        nonWhitespaceGlyphCount++;
        final renderBoundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;

        var glyphRect = MatrixUtils.transformRect(
          paragraph.getTransformTo(renderBoundary),
          box.toRect(),
        );

        var clipRect = computeVisibleClipRect();

        // If the glyph is partially outside the vertical clip rect, scroll to bring it into view
        if (scrollableFinder != null &&
            (glyphRect.top < clipRect.top || glyphRect.bottom > clipRect.bottom)) {
          final scrollState = tester.state<ScrollableState>(scrollableFinder);
          final currentPixels = scrollState.position.pixels;
          final delta = glyphRect.center.dy - clipRect.center.dy;
          final targetPixels = (currentPixels + delta).clamp(
            scrollState.position.minScrollExtent,
            scrollState.position.maxScrollExtent,
          );
          scrollState.position.jumpTo(targetPixels);
          await _boundedPumpAndSettle(tester);

          // Recompute geometry after scrolling
          clipRect = computeVisibleClipRect();
          glyphRect = MatrixUtils.transformRect(
            paragraph.getTransformTo(renderBoundary),
            box.toRect(),
          );
        }

        expect(
          glyphRect.width,
          greaterThan(0.0),
          reason: '$role glyph ($cluster) width must be positive',
        );
        expect(
          glyphRect.height,
          greaterThan(0.0),
          reason: '$role glyph ($cluster) height must be positive',
        );

        // Verify all four edges of the non-blank rune glyphRect are within the visible clip rect
        // (real surface ∩ screen ∩ scroll viewport), without relying on paragraph vertical leading
        // or arbitrary negative thresholds.
        expect(
          glyphRect.left,
          greaterThanOrEqualTo(clipRect.left - 0.01),
          reason:
              '$role glyph ($cluster) left (${glyphRect.left}) must be >= clipRect left (${clipRect.left})',
        );
        expect(
          glyphRect.right,
          lessThanOrEqualTo(clipRect.right + 0.01),
          reason:
              '$role glyph ($cluster) right (${glyphRect.right}) must be <= clipRect right (${clipRect.right})',
        );
        expect(
          glyphRect.top,
          greaterThanOrEqualTo(clipRect.top - 0.01),
          reason:
              '$role glyph ($cluster) top (${glyphRect.top}) must be >= clipRect top (${clipRect.top})',
        );
        expect(
          glyphRect.bottom,
          lessThanOrEqualTo(clipRect.bottom + 0.01),
          reason:
              '$role glyph ($cluster) bottom (${glyphRect.bottom}) must be <= clipRect bottom (${clipRect.bottom})',
        );
      }
    }
    i = end;
  }

  expect(
    nonWhitespaceGlyphCount,
    greaterThan(0),
    reason: '$role must have at least one non-whitespace glyph box',
  );
}

/// Evaluates text contrast against the real painted surface layer stack.
/// Layer 0: Root scaffold backgroundColor (e.g. starRail 0xFF080B16).
/// Layer 1..N: Ancestor Material, Ink, and DecoratedBox solid fills.
/// Note: Photo background assets are not evaluated without pixel evidence.
void _assertCompositeContrast(
  WidgetTester tester, {
  required Finder textFinder,
  required Color baseBackground,
  double minContrast = 4.5,
  String? role,
}) {
  final textWidgetFinder = find.descendant(
    of: textFinder,
    matching: find.byType(Text),
  );
  final target =
      textWidgetFinder.evaluate().isNotEmpty
          ? textWidgetFinder.first
          : textFinder;
  final element = tester.element(target);
  final text = tester.widget<Text>(target);
  final foreground =
      DefaultTextStyle.of(element).style.merge(text.style).color!;

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
    }
    return true;
  });

  var backgrounds = <Color>[baseBackground];
  for (final layer in layers.reversed) {
    backgrounds = [
      for (final bg in backgrounds)
        for (final color in layer) Color.alphaBlend(color, bg),
    ];
  }

  for (final bg in backgrounds) {
    final effectiveFg = Color.alphaBlend(foreground, bg);
    final ratio = appContrastRatio(effectiveFg, bg);
    expect(
      ratio,
      greaterThanOrEqualTo(minContrast),
      reason:
          '${role ?? text.data}: contrast ratio ($ratio) for $foreground on $bg must be >= $minContrast',
    );
  }
}

void _assertDialogThemeAndSurface(
  WidgetTester tester,
  Finder dialogFinder,
  String expectedBrandId,
) {
  final currentDialogElement = tester.element(dialogFinder);
  final dialogTheme = Theme.of(currentDialogElement);

  final refElement = tester.element(
    find.byKey(ValueKey('ref_theme_$expectedBrandId'), skipOffstage: false),
  );
  final refTheme = Theme.of(refElement);
  final refStyle = appSecondaryFilledButtonStyle(refElement);

  final expectedBrightness = refTheme.brightness;
  final expectedPrimary = refTheme.colorScheme.primary;
  final expectedDialogBg =
      refTheme.dialogTheme.backgroundColor ?? refTheme.colorScheme.surface;
  final expectedButtonBg = refStyle.backgroundColor?.resolve(const {});
  final expectedButtonFg = refStyle.foregroundColor?.resolve(const {});
  final expectedSurfaceStyle = appSurfaceStyleOf(refElement);

  // Assert brightness explicitly tracks the brand's production brightness
  expect(
    dialogTheme.brightness,
    equals(expectedBrightness),
    reason:
        'Dialog Theme brightness must match $expectedBrandId ($expectedBrightness)',
  );
  expect(
    dialogTheme.colorScheme.primary,
    equals(expectedPrimary),
    reason:
        'Dialog Theme primary must match $expectedBrandId ($expectedPrimary)',
  );

  final actualSurfaceStyle = appSurfaceStyleOf(currentDialogElement);
  expect(
    actualSurfaceStyle,
    equals(expectedSurfaceStyle),
    reason: 'Dialog surface style must match $expectedBrandId reference',
  );
  if (expectedBrandId == 'liquidGlass') {
    expect(actualSurfaceStyle, equals(AppSurfaceStyle.liquidGlass));
  } else if (expectedBrandId == 'defaultBrand') {
    expect(actualSurfaceStyle, equals(AppSurfaceStyle.ios));
    expect(actualSurfaceStyle, isNot(equals(AppSurfaceStyle.liquidGlass)));
  }

  final alertDialogFinder = find.descendant(
    of: dialogFinder,
    matching: find.byType(AlertDialog),
  );
  expect(alertDialogFinder, findsOneWidget);
  final dialogMaterial = tester.widget<Material>(
    find
        .descendant(of: alertDialogFinder, matching: find.byType(Material))
        .first,
  );
  expect(
    dialogMaterial.color,
    equals(expectedDialogBg),
    reason:
        'Dialog surface Material background must match $expectedBrandId reference',
  );

  final actionBtnFinder = _dialogActionFinder(dialogFinder);
  expect(actionBtnFinder, findsOneWidget);
  final actionWidget = tester.widget(actionBtnFinder);
  final ButtonStyle? actionStyle =
      actionWidget is ButtonStyleButton ? actionWidget.style : null;
  final effectiveBtnBg = actionStyle?.backgroundColor?.resolve(const {});
  final effectiveBtnFg = actionStyle?.foregroundColor?.resolve(const {});
  if (expectedButtonBg != null) {
    expect(
      effectiveBtnBg,
      equals(expectedButtonBg),
      reason:
          'Action button background must match $expectedBrandId reference secondary helper ($expectedButtonBg)',
    );
  }
  if (expectedButtonFg != null) {
    expect(
      effectiveBtnFg,
      equals(expectedButtonFg),
      reason:
          'Action button foreground must match $expectedBrandId reference secondary helper foreground ($expectedButtonFg)',
    );
  }
}

Future<void> _verifyRetainedDialogContentAndScroll(
  WidgetTester tester,
  Finder dialogFinder, {
  required String expectedTitle,
  required String expectedMessage,
}) async {
  final titleFinder = find.descendant(
    of: dialogFinder,
    matching: find.text(expectedTitle),
  );
  expect(titleFinder, findsOneWidget);

  final messageFinder = find.descendant(
    of: dialogFinder,
    matching: find.text(expectedMessage),
  );
  expect(messageFinder, findsOneWidget);

  final actionBtnFinder = _dialogActionFinder(dialogFinder);
  expect(actionBtnFinder, findsOneWidget);

  final titleRich = find.descendant(
    of: titleFinder,
    matching: find.byType(RichText),
  );
  final titleParagraph = tester.renderObject<RenderParagraph>(
    titleRich.evaluate().isEmpty ? titleFinder : titleRich,
  );
  expect(titleParagraph.text.toPlainText(), equals(expectedTitle));
  expect(
    titleParagraph.didExceedMaxLines,
    isFalse,
    reason: 'Title must fit without exceeding max lines',
  );
  final titleTokens = RegExp(r'\S+').allMatches(expectedTitle).toList();
  expect(
    titleTokens,
    isNotEmpty,
    reason: 'Title must contain non-whitespace tokens',
  );
  for (final token in titleTokens) {
    final tokenBoxes = titleParagraph.getBoxesForSelection(
      TextSelection(baseOffset: token.start, extentOffset: token.end),
    );
    expect(
      tokenBoxes,
      isNotEmpty,
      reason:
          'Title token "${token.group(0)}" must yield non-empty glyph boxes',
    );
    for (final box in tokenBoxes) {
      final rect = box.toRect();
      expect(
        rect.width,
        greaterThan(0.0),
        reason: 'Title glyph box must have positive width',
      );
      expect(
        rect.height,
        greaterThan(0.0),
        reason: 'Title glyph box must have positive height',
      );
    }
  }

  final messageRich = find.descendant(
    of: messageFinder,
    matching: find.byType(RichText),
  );
  final messageParagraph = tester.renderObject<RenderParagraph>(
    messageRich.evaluate().isEmpty ? messageFinder : messageRich,
  );
  expect(messageParagraph.text.toPlainText(), equals(expectedMessage));
  expect(
    messageParagraph.didExceedMaxLines,
    isFalse,
    reason: 'Message must fit without truncation',
  );
  final messageTokens = RegExp(r'\S+').allMatches(expectedMessage).toList();
  expect(
    messageTokens,
    isNotEmpty,
    reason: 'Message must contain non-whitespace tokens',
  );
  for (final token in messageTokens) {
    final tokenBoxes = messageParagraph.getBoxesForSelection(
      TextSelection(baseOffset: token.start, extentOffset: token.end),
    );
    expect(
      tokenBoxes,
      isNotEmpty,
      reason:
          'Message token "${token.group(0)}" must yield non-empty glyph boxes',
    );
    for (final box in tokenBoxes) {
      final rect = box.toRect();
      expect(
        rect.width,
        greaterThan(0.0),
        reason:
            'Message glyph box for "${token.group(0)}" must have positive width',
      );
      expect(
        rect.height,
        greaterThan(0.0),
        reason:
            'Message glyph box for "${token.group(0)}" must have positive height',
      );
    }
  }

  // Section-by-section visibility along real scroll offsets and anchors
  final scrollableFinder =
      find
          .descendant(of: dialogFinder, matching: find.byType(Scrollable))
          .first;
  final scrollState = tester.state<ScrollableState>(scrollableFinder);
  final scrollPosition = scrollState.position;
  final maxExtent = scrollPosition.maxScrollExtent;
  final viewportRect = tester.getRect(find.byWidget(scrollState.widget));

  Rect globalBox(ui.TextBox box) => Rect.fromPoints(
    messageParagraph.localToGlobal(Offset(box.left, box.top)),
    messageParagraph.localToGlobal(Offset(box.right, box.bottom)),
  );

  // Top anchor: scroll offset 0. Title and initial message segment visible in viewport
  scrollPosition.jumpTo(0.0);
  await tester.pump(const Duration(milliseconds: 40));
  expect(
    titleFinder.hitTestable(),
    findsOneWidget,
    reason: 'Title section must be hit-testable at top anchor',
  );
  final firstTokenBoxes = messageParagraph.getBoxesForSelection(
    TextSelection(
      baseOffset: messageTokens.first.start,
      extentOffset: messageTokens.first.end,
    ),
  );
  expect(firstTokenBoxes, isNotEmpty);
  final firstTokenRect = globalBox(firstTokenBoxes.first);
  expect(
    firstTokenRect.top,
    greaterThanOrEqualTo(viewportRect.top - 0.5),
    reason: 'Initial token top must be within viewport at top anchor',
  );
  expect(
    firstTokenRect.bottom,
    lessThanOrEqualTo(viewportRect.bottom + 0.5),
    reason: 'Initial token bottom must be within viewport at top anchor',
  );

  // Mid anchor: scroll offset maxExtent * 0.5 when scrollable
  if (maxExtent > 0.0) {
    scrollPosition.jumpTo(maxExtent * 0.5);
    await tester.pump(const Duration(milliseconds: 40));
    expect(
      messageFinder.hitTestable(),
      findsOneWidget,
      reason: 'Long message body must be hit-testable at mid anchor',
    );
    final midToken = messageTokens[messageTokens.length ~/ 2];
    final midTokenBoxes = messageParagraph.getBoxesForSelection(
      TextSelection(baseOffset: midToken.start, extentOffset: midToken.end),
    );
    expect(midTokenBoxes, isNotEmpty);
    final midTokenRect = globalBox(midTokenBoxes.first);
    expect(
      midTokenRect.top,
      greaterThanOrEqualTo(viewportRect.top - 0.5),
      reason: 'Mid token top must be within viewport at mid anchor',
    );
    expect(
      midTokenRect.bottom,
      lessThanOrEqualTo(viewportRect.bottom + 0.5),
      reason: 'Mid token bottom must be within viewport at mid anchor',
    );
  }

  // Bottom anchor: scroll offset maxExtent
  scrollPosition.jumpTo(maxExtent);
  await tester.pump(const Duration(milliseconds: 40));
  final lastTokenBoxes = messageParagraph.getBoxesForSelection(
    TextSelection(
      baseOffset: messageTokens.last.start,
      extentOffset: messageTokens.last.end,
    ),
  );
  expect(lastTokenBoxes, isNotEmpty);
  final lastTokenRect = globalBox(lastTokenBoxes.last);
  expect(
    lastTokenRect.top,
    greaterThanOrEqualTo(viewportRect.top - 0.5),
    reason: 'Trailing token top must be within viewport at bottom anchor',
  );
  expect(
    lastTokenRect.bottom,
    lessThanOrEqualTo(viewportRect.bottom + 0.5),
    reason: 'Trailing token bottom must be within viewport at bottom anchor',
  );
  expect(
    actionBtnFinder.hitTestable(),
    findsOneWidget,
    reason: 'Action button must be hit-testable at bottom anchor',
  );

  scrollPosition.jumpTo(maxExtent);
  await tester.pump(const Duration(milliseconds: 40));
}

void main() {
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  group('WidgetScreen Gallery Real Dark Theme Coverage', () {
    for (final scenario in _darkScenarios) {
      testWidgets(
        'widget screen gallery dark theme layout and readability: ${scenario.name}',
        (tester) async {
          I18n.setLocale(scenario.locale);
          final originalShadows = debugDisableShadows;
          debugDisableShadows = false;
          addTearDown(() => debugDisableShadows = originalShadows);

          final initialPrefs = <String, Object>{
            'pref_app_timezone_mode': 'fixed',
            'pref_app_timezone_iana': 'Asia/Shanghai',
            'active_brand': scenario.brandId,
            'theme_shop_state': jsonEncode({
              'activeBrand': scenario.brandId,
              'unlockedBrandIds': [
                'defaultBrand',
                'liquidGlass',
                'starRail',
                'zzz',
              ],
            }),
            'theme_unlocked_brands': [
              'defaultBrand',
              'liquidGlass',
              'starRail',
              'zzz',
            ],
            'flutter.active_brand': scenario.brandId,
            'flutter.theme_shop_state': jsonEncode({
              'activeBrand': scenario.brandId,
              'unlockedBrandIds': [
                'defaultBrand',
                'liquidGlass',
                'starRail',
                'zzz',
              ],
            }),
            'flutter.theme_unlocked_brands': [
              'defaultBrand',
              'liquidGlass',
              'starRail',
              'zzz',
            ],
          };
          SharedPreferences.setMockInitialValues(initialPrefs);
          final store = _RecordingPreferencesStore({
            for (final entry in initialPrefs.entries)
              if (!entry.key.startsWith('flutter.'))
                'flutter.${entry.key}': entry.value,
          });
          SharedPreferencesStorePlatform.instance = store;

          final fixture = _Fixture();

          try {
            await fixture.mount(
              tester,
              initialBrand: scenario.brandId,
              initialLocale: scenario.locale,
              size: scenario.size,
              textScaler: scenario.textScaler,
              hostPlatform: WidgetHostPlatform.ios,
            );

            // Assert real loaded production theme is dark directly from brand.theme
            expect(fixture.theme.brand.id, equals(scenario.brandId));
            expect(
              fixture.theme.brand.theme.brightness,
              equals(Brightness.dark),
            );
            final currentTheme = Theme.of(
              tester.element(find.byType(WidgetScreen)),
            );
            expect(currentTheme.brightness, equals(Brightness.dark));

            // Verify payload consistency directly against the dark ThemeProvider
            final payload = HomeWidgetThemePayload.fromThemeProvider(
              fixture.theme,
            );
            final cs = fixture.theme.brand.theme.colorScheme;
            expect(payload.dark, isTrue);
            expect(payload.primary, equals(cs.primary));
            expect(payload.text, equals(cs.onSurface));

            final screenFinder = find.byType(WidgetScreen);
            expect(screenFinder, findsOneWidget);

            // Locate and reveal target catalog item card using real scrolling
            final cardFinder = find.byKey(
              ValueKey('widget_gallery_${scenario.targetKind.name}'),
            );
            final galleryScrollable =
                find
                    .descendant(
                      of: find.byType(ListView).first,
                      matching: find.byType(Scrollable),
                    )
                    .first;
            await tester.scrollUntilVisible(
              cardFinder,
              200.0,
              scrollable: galleryScrollable,
            );
            final cardElement = tester.element(cardFinder);
            await Scrollable.ensureVisible(cardElement, alignment: 0.3);
            await _boundedPumpAndSettle(tester);
            expect(cardFinder, findsOneWidget);

            // Locate tile title and subtitle in catalog tile
            final catalogTileFinder = find.descendant(
              of: cardFinder,
              matching: find.byWidgetPredicate(
                (w) => w.runtimeType.toString() == '_WidgetCatalogTile',
              ),
            );
            expect(catalogTileFinder, findsOneWidget);

            final titleFinder = find.descendant(
              of: catalogTileFinder,
              matching: find.text(
                WidgetUiCopy.catalogTitle(scenario.targetKind),
              ),
            );
            final subtitleFinder = find.descendant(
              of: catalogTileFinder,
              matching: find.text(
                WidgetUiCopy.catalogSubtitle(scenario.targetKind),
              ),
            );

            // Real scroll & recomputed geometry assertion for title
            await _assertReadableTextOnSurface(
              tester,
              textFinder: titleFinder,
              surfaceFinder: cardFinder,
              boundaryKey: fixture.boundaryKey,
              role: '${scenario.targetKind.name} tile title',
              scrollableFinder: galleryScrollable,
            );

            // Real scroll & recomputed geometry assertion for subtitle
            await _assertReadableTextOnSurface(
              tester,
              textFinder: subtitleFinder,
              surfaceFinder: cardFinder,
              boundaryKey: fixture.boundaryKey,
              role: '${scenario.targetKind.name} tile subtitle',
              scrollableFinder: galleryScrollable,
            );

            // Contrast against real solid card surface container (AppSurfaceCard on scaffoldBackgroundColor)
            _assertCompositeContrast(
              tester,
              textFinder: titleFinder,
              baseBackground: currentTheme.scaffoldBackgroundColor,
              role: '${scenario.targetKind.name} title contrast',
            );

            // Verify preview card surface presence
            final previewSurfaceFinder = find.descendant(
              of: cardFinder,
              matching: find.byKey(const ValueKey('widget_preview_surface')),
            );
            expect(previewSurfaceFinder, findsOneWidget);

            // Locate action button, scroll to reveal it, and execute full shared helpers
            final addControl = find.byKey(ValueKey(scenario.targetKind));
            expect(addControl, findsOneWidget);
            final button = find.descendant(
              of: addControl,
              matching: find.byType(FilledButton),
            );
            expect(button, findsOneWidget);

            await tester.scrollUntilVisible(
              button,
              80.0,
              scrollable: galleryScrollable,
            );
            final buttonElement = tester.element(button);
            await Scrollable.ensureVisible(buttonElement, alignment: 0.5);
            await _boundedPumpAndSettle(tester);

            // Complete shared helpers: 44dp hit target + readable control contrast
            expectControlTouchTarget(tester, button);
            expectReadableControl(tester, button);

            // Verify zero unexpected native calls during gallery inspection
            expect(fixture.channels.pinRequestCalls, equals(0));
            expect(fixture.channels.openSettingsCalls, equals(0));

            await _capture(
              tester,
              fixture.boundaryKey,
              '${scenario.name}-gallery',
            );
          } finally {
            try {
              await fixture.dispose(tester);
            } finally {
              debugDisableShadows = originalShadows;
            }
          }
        },
      );
    }
  });

  group('WidgetScreen High-Value Modal Layer Retained Across Themes & Locales', () {
    testWidgets(
      'widget screen host help dialog retained live across starRail (dark) -> defaultBrand (light) -> liquidGlass (light) -> starRail (dark) and locale switches',
      (tester) async {
        I18n.setLocale(AppLocale.zh);
        final originalShadows = debugDisableShadows;
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = originalShadows);

        final initialPrefs = <String, Object>{
          'pref_app_timezone_mode': 'fixed',
          'pref_app_timezone_iana': 'Asia/Shanghai',
          'active_brand': 'starRail',
          'theme_shop_state': jsonEncode({
            'activeBrand': 'starRail',
            'unlockedBrandIds': [
              'defaultBrand',
              'liquidGlass',
              'starRail',
              'zzz',
            ],
          }),
          'theme_unlocked_brands': [
            'defaultBrand',
            'liquidGlass',
            'starRail',
            'zzz',
          ],
          'flutter.pref_app_timezone_mode': 'fixed',
          'flutter.pref_app_timezone_iana': 'Asia/Shanghai',
          'flutter.active_brand': 'starRail',
          'flutter.theme_shop_state': jsonEncode({
            'activeBrand': 'starRail',
            'unlockedBrandIds': [
              'defaultBrand',
              'liquidGlass',
              'starRail',
              'zzz',
            ],
          }),
          'flutter.theme_unlocked_brands': [
            'defaultBrand',
            'liquidGlass',
            'starRail',
            'zzz',
          ],
        };
        SharedPreferences.setMockInitialValues(initialPrefs);
        final store = _RecordingPreferencesStore({
          for (final entry in initialPrefs.entries)
            if (!entry.key.startsWith('flutter.'))
              'flutter.${entry.key}': entry.value,
        });
        SharedPreferencesStorePlatform.instance = store;

        final fixture = _Fixture();

        try {
          await fixture.mount(
            tester,
            initialBrand: 'starRail',
            initialLocale: AppLocale.zh,
            size: const Size(320, 844),
            textScaler: const TextScaler.linear(2.0),
            hostPlatform: WidgetHostPlatform.ios,
          );

          expect(fixture.theme.brand.id, equals('starRail'));
          expect(fixture.theme.brand.theme.brightness, equals(Brightness.dark));

          final screenFinder = find.byType(WidgetScreen);
          expect(screenFinder, findsOneWidget);
          final initialScreenElement = tester.element(screenFinder);
          final initialScreenState = tester.state(screenFinder);

          // 1. Locate widget catalog card and iOS manual help trigger button
          final targetKind = DuoyiWidgetKind.todo;
          final addControl = find.byKey(ValueKey(targetKind));
          final catalogScrollable =
              find
                  .descendant(
                    of: find.byType(ListView).first,
                    matching: find.byType(Scrollable),
                  )
                  .first;
          await tester.scrollUntilVisible(
            addControl,
            200.0,
            scrollable: catalogScrollable,
          );
          await _boundedPumpAndSettle(tester);

          final button = find.descendant(
            of: addControl,
            matching: find.byType(FilledButton),
          );
          expect(button, findsOneWidget);
          expectControlTouchTarget(tester, button);

          final initialButtonState = tester.state(
            find.ancestor(
              of: button,
              matching: find.byWidgetPredicate(
                (w) => w.runtimeType.toString() == '_AddWidgetButton',
              ),
            ),
          );

          // 2. Open real iOS manual help modal
          await Scrollable.ensureVisible(
            tester.element(button),
            alignment: 0.35,
          );
          await _boundedPumpAndSettle(tester);
          await tester.tap(button);
          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          final dialogFinder = find.byType(AppDialog);
          expect(dialogFinder, findsOneWidget);
          final initialDialogElement = tester.element(dialogFinder);
          final initialDialogRoute = ModalRoute.of(initialDialogElement);
          expect(initialDialogRoute, isNotNull);

          // Dynamic action button resolver that evaluates under current locale and matches ButtonStyleButton
          Finder actionButton() => _dialogActionFinder(dialogFinder);

          // Verify modal contains only the action button, no Android permission action, zero platform calls
          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.text(WidgetUiCopy.actionOpenPermissions),
            ),
            findsNothing,
          );
          expect(fixture.channels.pinRequestCalls, equals(0));
          expect(fixture.channels.openSettingsCalls, equals(0));
          expect(fixture.channels.supportCalls, equals(0));

          String expectedTitle() =>
              WidgetUiCopy.hostHelpTitle(WidgetHostPlatform.ios);
          String expectedMessage() =>
              WidgetUiCopy.hostHelpMessage(WidgetHostPlatform.ios);

          void assertHostStateMaintained() {
            expect(
              tester.element(screenFinder),
              same(initialScreenElement),
              reason: 'WidgetScreen Element must be retained',
            );
            expect(
              tester.state(screenFinder),
              same(initialScreenState),
              reason: 'WidgetScreen State must be retained',
            );
            expect(
              tester.state(
                find.ancestor(
                  of: button,
                  matching: find.byWidgetPredicate(
                    (w) => w.runtimeType.toString() == '_AddWidgetButton',
                  ),
                ),
              ),
              same(initialButtonState),
              reason: 'Initiating _AddWidgetButton State must be retained',
            );
          }

          // Initial verification in starRail (dark)
          _assertDialogThemeAndSurface(tester, dialogFinder, 'starRail');
          await _verifyRetainedDialogContentAndScroll(
            tester,
            dialogFinder,
            expectedTitle: expectedTitle(),
            expectedMessage: expectedMessage(),
          );
          expectReadableControl(tester, actionButton());
          expectControlTouchTarget(tester, actionButton());
          assertHostStateMaintained();
          expect(fixture.channels.methodCalls, isEmpty);
          await _capture(tester, fixture.boundaryKey, '01-starRail-dark');

          // 3. Live switch: starRail (dark) -> defaultBrand (light)
          await tester.runAsync(() async {
            final switched = await fixture.theme.setBrand('defaultBrand');
            expect(switched, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          await _pumpThemeSwitchFrames(tester);
          expect(tester.takeException(), isNull);

          // Route, State, Element retained
          expect(
            identical(tester.element(dialogFinder), initialDialogElement),
            isTrue,
            reason: 'Dialog Element retained across starRail -> defaultBrand',
          );
          expect(
            identical(
              ModalRoute.of(tester.element(dialogFinder)),
              initialDialogRoute,
            ),
            isTrue,
            reason: 'ModalRoute retained across starRail -> defaultBrand',
          );
          assertHostStateMaintained();

          // Production theme brightness dynamically tracked to defaultBrand (light)
          _assertDialogThemeAndSurface(tester, dialogFinder, 'defaultBrand');
          await _verifyRetainedDialogContentAndScroll(
            tester,
            dialogFinder,
            expectedTitle: expectedTitle(),
            expectedMessage: expectedMessage(),
          );
          expectReadableControl(tester, actionButton());
          expect(fixture.channels.methodCalls, isEmpty);
          await _capture(tester, fixture.boundaryKey, '02-defaultBrand-light');

          // 4. Live switch: defaultBrand (light) -> liquidGlass (light)
          await tester.runAsync(() async {
            final switched = await fixture.theme.setBrand('liquidGlass');
            expect(switched, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          await _pumpThemeSwitchFrames(tester);
          expect(tester.takeException(), isNull);

          // Route, State, Element retained
          expect(
            identical(tester.element(dialogFinder), initialDialogElement),
            isTrue,
            reason: 'Dialog Element retained across defaultBrand -> liquidGlass',
          );
          expect(
            identical(
              ModalRoute.of(tester.element(dialogFinder)),
              initialDialogRoute,
            ),
            isTrue,
            reason: 'ModalRoute retained across defaultBrand -> liquidGlass',
          );
          assertHostStateMaintained();

          // Production theme brightness dynamically tracked to liquidGlass (light, frosted surface)
          _assertDialogThemeAndSurface(tester, dialogFinder, 'liquidGlass');
          await _verifyRetainedDialogContentAndScroll(
            tester,
            dialogFinder,
            expectedTitle: expectedTitle(),
            expectedMessage: expectedMessage(),
          );
          expectReadableControl(tester, actionButton());
          expect(fixture.channels.methodCalls, isEmpty);
          await _capture(tester, fixture.boundaryKey, '03-liquidGlass-light');

          // 5. Live switch: liquidGlass (light) -> starRail (dark)
          await tester.runAsync(() async {
            final switched = await fixture.theme.setBrand('starRail');
            expect(switched, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          await _pumpThemeSwitchFrames(tester);
          expect(tester.takeException(), isNull);

          // Route, State, Element retained
          expect(
            identical(tester.element(dialogFinder), initialDialogElement),
            isTrue,
            reason: 'Dialog Element retained across liquidGlass -> starRail',
          );
          expect(
            identical(
              ModalRoute.of(tester.element(dialogFinder)),
              initialDialogRoute,
            ),
            isTrue,
            reason: 'ModalRoute retained across liquidGlass -> starRail',
          );
          assertHostStateMaintained();

          // Production theme brightness returned to dark
          _assertDialogThemeAndSurface(tester, dialogFinder, 'starRail');
          await _verifyRetainedDialogContentAndScroll(
            tester,
            dialogFinder,
            expectedTitle: expectedTitle(),
            expectedMessage: expectedMessage(),
          );
          expectReadableControl(tester, actionButton());
          expect(fixture.channels.methodCalls, isEmpty);
          await _capture(
            tester,
            fixture.boundaryKey,
            '04-returned-starRail-dark',
          );

          // 6. Live locale switch: zh -> en while dialog open
          I18n.setLocale(AppLocale.en);
          await _pumpThemeSwitchFrames(tester);
          expect(tester.takeException(), isNull);

          expect(
            identical(tester.element(dialogFinder), initialDialogElement),
            isTrue,
            reason: 'Dialog Element retained across locale switch to en',
          );
          expect(
            identical(
              ModalRoute.of(tester.element(dialogFinder)),
              initialDialogRoute,
            ),
            isTrue,
            reason: 'ModalRoute retained across locale switch to en',
          );
          assertHostStateMaintained();
          _assertDialogThemeAndSurface(tester, dialogFinder, 'starRail');
          await _verifyRetainedDialogContentAndScroll(
            tester,
            dialogFinder,
            expectedTitle: expectedTitle(),
            expectedMessage: expectedMessage(),
          );
          expectReadableControl(tester, actionButton());
          expectControlTouchTarget(tester, actionButton());
          expect(fixture.channels.methodCalls, isEmpty);

          // 7. Live locale switch back: en -> zh while dialog open
          I18n.setLocale(AppLocale.zh);
          await _pumpThemeSwitchFrames(tester);
          expect(tester.takeException(), isNull);

          expect(
            identical(tester.element(dialogFinder), initialDialogElement),
            isTrue,
            reason: 'Dialog Element retained across locale return to zh',
          );
          expect(
            identical(
              ModalRoute.of(tester.element(dialogFinder)),
              initialDialogRoute,
            ),
            isTrue,
            reason: 'ModalRoute retained across locale return to zh',
          );
          assertHostStateMaintained();
          _assertDialogThemeAndSurface(tester, dialogFinder, 'starRail');
          await _verifyRetainedDialogContentAndScroll(
            tester,
            dialogFinder,
            expectedTitle: expectedTitle(),
            expectedMessage: expectedMessage(),
          );
          expectReadableControl(tester, actionButton());
          expectControlTouchTarget(tester, actionButton());
          expect(fixture.channels.methodCalls, isEmpty);

          // 8. Dismiss dialog via Got It action - verify zero unexpected native platform calls
          final closeAction = actionButton();
          await Scrollable.ensureVisible(tester.element(closeAction));
          await tester.pump(const Duration(milliseconds: 50));
          await tester.tap(closeAction);
          await _boundedPumpAndSettle(tester);

          expect(
            find.byType(AppDialog),
            findsNothing,
            reason: 'Dialog must be dismissed after Got It',
          );
          expect(
            find.byType(WidgetScreen),
            findsOneWidget,
            reason: 'WidgetScreen must remain mounted',
          );
          assertHostStateMaintained();

          // Zero unexpected native writes / platform calls
          expect(
            fixture.channels.methodCalls,
            isEmpty,
            reason: 'Closing dialog must produce zero native platform calls',
          );
          expect(
            fixture.channels.pinRequestCalls,
            equals(0),
            reason: 'No native pin requests during dismissal',
          );
          expect(
            fixture.channels.openSettingsCalls,
            equals(0),
            reason: 'No native settings requests during dismissal',
          );
          expect(tester.takeException(), isNull);
        } finally {
          try {
            await fixture.dispose(tester);
          } finally {
            debugDisableShadows = originalShadows;
          }
        }
      },
    );
  });
}
