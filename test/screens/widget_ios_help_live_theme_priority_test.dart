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
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/android_widget_manager.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandBackground;
import 'package:duoyi/widgets/surface_components.dart'
    show AppDialog, appSecondaryFilledButtonStyle, appSurfaceStyleOf;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/rendered_control_contrast.dart' show expectReadableControl;
import '../support/retained_dialog_text_probe.dart'
    show verifyRetainedDialogText;
import '../support/secondary_route_render_probe.dart'
    show RouteProbeNonlinearScaler;
import '../support/weekly_review_screenshot_font.dart'
    show loadWeeklyReviewScreenshotFonts;

class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore(super.data) : super.withData();
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
      final file = File('$explicitDir/widget-ios-help-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

enum _DismissAction { gotIt, accountInvalidationGotIt }

class _IosHelpScenario {
  final String name;
  final AppLocale initialLocale;
  final AppLocale alternateLocale;
  final String initialBrand;
  final String targetBrand;
  final Size size;
  final TextScaler textScaler;
  final DuoyiWidgetKind targetKind;
  final _DismissAction dismissAction;

  const _IosHelpScenario({
    required this.name,
    required this.initialLocale,
    required this.alternateLocale,
    required this.initialBrand,
    required this.targetBrand,
    required this.size,
    required this.textScaler,
    required this.targetKind,
    this.dismissAction = _DismissAction.gotIt,
  });
}

const _scenarios = <_IosHelpScenario>[
  _IosHelpScenario(
    name: 'zh-portrait-320x844-scale200-defaultBrand',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(320, 844),
    textScaler: TextScaler.linear(2.0),
    targetKind: DuoyiWidgetKind.todo,
    dismissAction: _DismissAction.gotIt,
  ),
  _IosHelpScenario(
    name: 'en-portrait-332x844-nonlinear-liquidGlass',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(332, 844),
    textScaler: RouteProbeNonlinearScaler(),
    targetKind: DuoyiWidgetKind.habit,
    dismissAction: _DismissAction.gotIt,
  ),
  _IosHelpScenario(
    name: 'zh-landscape-844x390-scale100-liquidGlass',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(844, 390),
    textScaler: TextScaler.linear(1.0),
    targetKind: DuoyiWidgetKind.focus,
    dismissAction: _DismissAction.gotIt,
  ),
  _IosHelpScenario(
    name: 'en-portrait-320x844-scale200-defaultBrand-account-invalidation',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(320, 844),
    textScaler: TextScaler.linear(2.0),
    targetKind: DuoyiWidgetKind.calendar,
    dismissAction: _DismissAction.accountInvalidationGotIt,
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

  Future<void> mount(WidgetTester tester, _IosHelpScenario scenario) async {
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
      AndroidWidgetManager.debugIsAndroidOverride = false;

      await tester.runAsync(() async {
        prefs = await SharedPreferences.getInstance();
        theme = ThemeProvider();
        preferences = PreferencesProvider();
        lock = _MutableLock();
        auth = _MutableAuthProvider();
        updater = _MutableUpdateService();

        await theme.loadFromStorage().timeout(const Duration(seconds: 5));
        await preferences.loadFromStorage().timeout(const Duration(seconds: 5));
        await loadWeeklyReviewScreenshotFonts().timeout(
          const Duration(seconds: 5),
        );
      });
      await _drainAccountWrites(tester);
    }

    tester.view.physicalSize = scenario.size;
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
          builder: (context, currentTheme, _) =>
              ValueListenableBuilder<AppLocale>(
                valueListenable: I18n.localeListenable,
                builder: (context, currentLocale, _) => MaterialApp(
                  navigatorKey: navigatorKey,
                  scaffoldMessengerKey: scaffoldMessengerKey,
                  debugShowCheckedModeBanner: false,
                  locale: Locale(currentLocale == AppLocale.en ? 'en' : 'zh'),
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: currentTheme.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: scenario.size,
                      textScaler: scenario.textScaler,
                    ),
                    child: RepaintBoundary(key: boundaryKey, child: child!),
                  ),
                  home: Stack(
                    children: [
                      BrandBackground(
                        child: WidgetScreen(
                          key: const ValueKey('live-brand-widget-screen'),
                          hostPlatform: WidgetHostPlatform.ios,
                          isActive: true,
                          activityRevision: activityRevision,
                        ),
                      ),
                      for (final brand in [
                        AppBrands.defaultBrand,
                        AppBrands.liquidGlass,
                      ])
                        Offstage(
                          offstage: true,
                          child: Theme(
                            data: brand.theme,
                            child: Builder(
                              key: ValueKey('ref_theme_${brand.id}'),
                              builder: (refContext) => const SizedBox.shrink(),
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

  final expectedPrimary = refTheme.colorScheme.primary;
  final expectedDialogBg =
      refTheme.dialogTheme.backgroundColor ?? refTheme.colorScheme.surface;
  final expectedButtonBg = refStyle.backgroundColor?.resolve(const {});
  final expectedButtonFg = refStyle.foregroundColor?.resolve(const {});
  final expectedSurfaceStyle = appSurfaceStyleOf(refElement);

  expect(
    dialogTheme.colorScheme.primary,
    equals(expectedPrimary),
    reason: 'Dialog Theme.of primary must match $expectedBrandId reference',
  );

  final actualSurfaceStyle = appSurfaceStyleOf(currentDialogElement);
  expect(
    actualSurfaceStyle,
    equals(expectedSurfaceStyle),
    reason:
        'Dialog surface style must match $expectedBrandId reference surface style',
  );
  if (expectedBrandId == 'liquidGlass') {
    expect(actualSurfaceStyle, equals(AppSurfaceStyle.liquidGlass));
  } else {
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

  final gotItFinder = find.descendant(
    of: dialogFinder,
    matching: find.widgetWithText(FilledButton, WidgetUiCopy.actionGotIt),
  );
  expect(gotItFinder, findsOneWidget);
  final gotItButton = tester.widget<FilledButton>(gotItFinder);
  final effectiveBtnBg = gotItButton.style?.backgroundColor?.resolve(const {});
  final effectiveBtnFg = gotItButton.style?.foregroundColor?.resolve(const {});
  expect(
    effectiveBtnBg,
    equals(expectedButtonBg),
    reason:
        'Got It button background must match $expectedBrandId reference secondary helper ($expectedButtonBg)',
  );
  expect(
    effectiveBtnFg,
    equals(expectedButtonFg),
    reason:
        'Got It button foreground must match $expectedBrandId reference secondary helper foreground ($expectedButtonFg)',
  );
}

Future<void> _verifyRetainedDialogContentAndScroll(
  WidgetTester tester,
  Finder dialogFinder, {
  required String expectedTitle,
  required String expectedMessage,
  required GlobalKey captureBoundaryKey,
  required String captureName,
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

  final gotItFinder = find.descendant(
    of: dialogFinder,
    matching: find.widgetWithText(FilledButton, WidgetUiCopy.actionGotIt),
  );
  expect(gotItFinder, findsOneWidget);

  // 1. Title paragraph: non-whitespace token glyph boxes must be positive, didExceedMaxLines == false
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

  // 2. Long message paragraph: non-whitespace token glyph boxes must be positive, didExceedMaxLines == false
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
            'Message glyph box for "${token.group(0)}" must have positive width (was ${rect.width})',
      );
      expect(
        rect.height,
        greaterThan(0.0),
        reason:
            'Message glyph box for "${token.group(0)}" must have positive height (was ${rect.height})',
      );
    }
  }

  // Font selection boxes can extend into normal leading. The actual ancestor
  // viewport is the clipping boundary; verify every line there, not just anchors.
  await verifyRetainedDialogText(tester, titleFinder, expected: expectedTitle);
  await verifyRetainedDialogText(
    tester,
    messageFinder,
    expected: expectedMessage,
  );

  // 3. Section-by-section visibility along real scroll offsets and anchors
  // Strictly verifies visible segment boundaries in the real scroll viewport,
  // without asserting viewport containment for off-screen characters.
  final scrollableFinder = find
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

  // Top anchor: scroll offset 0. Title and initial message segment visible in viewport.
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
  await _capture(tester, captureBoundaryKey, '$captureName-top');

  // Mid anchor: scroll offset maxExtent * 0.5 when scrollable. Mid message segment visible in viewport.
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
  await _capture(tester, captureBoundaryKey, '$captureName-middle');

  // Bottom anchor: scroll offset maxExtent. Trailing message segment and Got It action visible in viewport.
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
    gotItFinder.hitTestable(),
    findsOneWidget,
    reason: 'Got It action must be hit-testable at bottom anchor',
  );

  // Keep scroll position at bottom anchor for subsequent action interactions
  scrollPosition.jumpTo(maxExtent);
  await tester.pump(const Duration(milliseconds: 40));
}

void main() {
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets(
      'widget ios manual help retained priority live brand defaultBrand <-> liquidGlass ${scenario.name}',
      (tester) async {
        I18n.setLocale(scenario.initialLocale);
        final originalShadows = debugDisableShadows;
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = originalShadows);

        final initialPrefs = <String, Object>{
          'pref_app_timezone_mode': 'fixed',
          'pref_app_timezone_iana': 'Asia/Shanghai',
          'active_brand': scenario.initialBrand,
          'theme_shop_state': jsonEncode({
            'activeBrand': scenario.initialBrand,
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          }),
          'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          'flutter.pref_app_timezone_mode': 'fixed',
          'flutter.pref_app_timezone_iana': 'Asia/Shanghai',
          'flutter.active_brand': scenario.initialBrand,
          'flutter.theme_shop_state': jsonEncode({
            'activeBrand': scenario.initialBrand,
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          }),
          'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
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
          await fixture.mount(tester, scenario);
          expect(fixture.theme.brand.id, scenario.initialBrand);
          expect(fixture.theme.isBrandUnlocked(scenario.targetBrand), isTrue);

          final screenFinder = find.byType(WidgetScreen);
          expect(screenFinder, findsOneWidget);
          final initialScreenElement = tester.element(screenFinder);
          final initialScreenState = tester.state(screenFinder);

          // 1. Locate widget catalog card and iOS manual help trigger button
          final addControl = find.byKey(ValueKey(scenario.targetKind));
          final catalogScrollable = find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(
            addControl,
            300,
            scrollable: catalogScrollable,
          );
          await _boundedPumpAndSettle(tester);

          final button = find.descendant(
            of: addControl,
            matching: find.byType(FilledButton),
          );
          expect(button, findsOneWidget);

          final initialButtonState = tester.state(
            find.ancestor(
              of: button,
              matching: find.byWidgetPredicate(
                (w) => w.runtimeType.toString() == '_AddWidgetButton',
              ),
            ),
          );

          final expectedButtonLabel = WidgetUiCopy.hostAddAction(
            WidgetHostPlatform.ios,
          );
          expect(
            find.descendant(
              of: button,
              matching: find.text(expectedButtonLabel),
            ),
            findsOneWidget,
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

          // Verify modal contains only "Got It", no Android settings button, and zero platform calls
          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.text(WidgetUiCopy.actionOpenPermissions),
            ),
            findsNothing,
            reason:
                'iOS manual host help modal must not present Android permission action',
          );
          expect(fixture.channels.pinRequestCalls, 0);
          expect(fixture.channels.openSettingsCalls, 0);
          expect(fixture.channels.supportCalls, 0);
          expect(fixture.channels.canOpenSettingsCalls, 0);

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

          // Initial verification: ThemeProvider, AppSurfaceStyle, long text, 44px action
          _assertDialogThemeAndSurface(
            tester,
            dialogFinder,
            scenario.initialBrand,
          );
          await _verifyRetainedDialogContentAndScroll(
            tester,
            dialogFinder,
            expectedTitle: expectedTitle(),
            expectedMessage: expectedMessage(),
            captureBoundaryKey: fixture.boundaryKey,
            captureName: '${scenario.name}-01-opening',
          );
          Finder currentGotItFinder() => find.descendant(
            of: dialogFinder,
            matching: find.widgetWithText(
              FilledButton,
              WidgetUiCopy.actionGotIt,
            ),
          );
          // Shared 3x3 44px touch target and contrast check from rendered_control_contrast.dart
          expectReadableControl(tester, currentGotItFinder());
          assertHostStateMaintained();
          expect(fixture.channels.methodCalls, isEmpty);
          await _capture(
            tester,
            fixture.boundaryKey,
            '${scenario.name}-01-opening',
          );

          // 3. Live brand switch to targetBrand while same overlay remains mounted
          await tester.runAsync(() async {
            final switched = await fixture.theme.setBrand(scenario.targetBrand);
            expect(switched, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          await _pumpThemeSwitchFrames(tester);
          expect(tester.takeException(), isNull);

          expect(
            identical(tester.element(dialogFinder), initialDialogElement),
            isTrue,
            reason: 'Dialog Element must be retained across brand switch',
          );
          expect(
            identical(
              ModalRoute.of(tester.element(dialogFinder)),
              initialDialogRoute,
            ),
            isTrue,
            reason: 'ModalRoute must be retained across brand switch',
          );

          _assertDialogThemeAndSurface(
            tester,
            dialogFinder,
            scenario.targetBrand,
          );
          await _verifyRetainedDialogContentAndScroll(
            tester,
            dialogFinder,
            expectedTitle: expectedTitle(),
            expectedMessage: expectedMessage(),
            captureBoundaryKey: fixture.boundaryKey,
            captureName: '${scenario.name}-02-switched-${scenario.targetBrand}',
          );
          expectReadableControl(tester, currentGotItFinder());
          assertHostStateMaintained();
          expect(fixture.channels.methodCalls, isEmpty);
          await _capture(
            tester,
            fixture.boundaryKey,
            '${scenario.name}-02-switched-${scenario.targetBrand}',
          );

          // 4. Live brand return to initialBrand while same overlay remains mounted
          await tester.runAsync(() async {
            final returned = await fixture.theme.setBrand(
              scenario.initialBrand,
            );
            expect(returned, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          await _pumpThemeSwitchFrames(tester);
          expect(tester.takeException(), isNull);

          expect(
            identical(tester.element(dialogFinder), initialDialogElement),
            isTrue,
            reason: 'Dialog Element must be retained across brand return',
          );
          expect(
            identical(
              ModalRoute.of(tester.element(dialogFinder)),
              initialDialogRoute,
            ),
            isTrue,
            reason: 'ModalRoute must be retained across brand return',
          );

          _assertDialogThemeAndSurface(
            tester,
            dialogFinder,
            scenario.initialBrand,
          );
          await _verifyRetainedDialogContentAndScroll(
            tester,
            dialogFinder,
            expectedTitle: expectedTitle(),
            expectedMessage: expectedMessage(),
            captureBoundaryKey: fixture.boundaryKey,
            captureName:
                '${scenario.name}-03-returned-${scenario.initialBrand}',
          );
          expectReadableControl(tester, currentGotItFinder());
          assertHostStateMaintained();
          expect(fixture.channels.methodCalls, isEmpty);
          await _capture(
            tester,
            fixture.boundaryKey,
            '${scenario.name}-03-returned-${scenario.initialBrand}',
          );

          // 5. Live locale switch to alternate locale while same overlay remains mounted
          I18n.setLocale(scenario.alternateLocale);
          await _pumpThemeSwitchFrames(tester);
          expect(tester.takeException(), isNull);

          expect(
            identical(tester.element(dialogFinder), initialDialogElement),
            isTrue,
            reason: 'Dialog Element must be retained across locale switch',
          );
          expect(
            identical(
              ModalRoute.of(tester.element(dialogFinder)),
              initialDialogRoute,
            ),
            isTrue,
            reason: 'ModalRoute must be retained across locale switch',
          );

          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.text(WidgetUiCopy.actionOpenPermissions),
            ),
            findsNothing,
          );
          _assertDialogThemeAndSurface(
            tester,
            dialogFinder,
            scenario.initialBrand,
          );
          await _verifyRetainedDialogContentAndScroll(
            tester,
            dialogFinder,
            expectedTitle: expectedTitle(),
            expectedMessage: expectedMessage(),
            captureBoundaryKey: fixture.boundaryKey,
            captureName:
                '${scenario.name}-04-locale-${scenario.alternateLocale.name}',
          );
          expectReadableControl(tester, currentGotItFinder());
          assertHostStateMaintained();
          expect(fixture.channels.methodCalls, isEmpty);
          await _capture(
            tester,
            fixture.boundaryKey,
            '${scenario.name}-04-locale-${scenario.alternateLocale.name}',
          );

          // 6. Live locale switch back to initial locale while same overlay remains mounted
          I18n.setLocale(scenario.initialLocale);
          await _pumpThemeSwitchFrames(tester);
          expect(tester.takeException(), isNull);

          expect(
            identical(tester.element(dialogFinder), initialDialogElement),
            isTrue,
            reason: 'Dialog Element must be retained across locale return',
          );
          expect(
            identical(
              ModalRoute.of(tester.element(dialogFinder)),
              initialDialogRoute,
            ),
            isTrue,
            reason: 'ModalRoute must be retained across locale return',
          );

          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.text(WidgetUiCopy.actionOpenPermissions),
            ),
            findsNothing,
          );
          _assertDialogThemeAndSurface(
            tester,
            dialogFinder,
            scenario.initialBrand,
          );
          await _verifyRetainedDialogContentAndScroll(
            tester,
            dialogFinder,
            expectedTitle: expectedTitle(),
            expectedMessage: expectedMessage(),
            captureBoundaryKey: fixture.boundaryKey,
            captureName:
                '${scenario.name}-05-locale-returned-${scenario.initialLocale.name}',
          );
          expectReadableControl(tester, currentGotItFinder());
          assertHostStateMaintained();
          expect(fixture.channels.methodCalls, isEmpty);
          await _capture(
            tester,
            fixture.boundaryKey,
            '${scenario.name}-05-locale-returned-${scenario.initialLocale.name}',
          );

          // 7. Exit handling
          if (scenario.dismissAction ==
              _DismissAction.accountInvalidationGotIt) {
            // Account dataGeneration invalidated representative
            AccountLocalDataCleaner.invalidateInFlightAccountWrites();
            await tester.pump(const Duration(milliseconds: 50));

            final closeGotIt = find.descendant(
              of: dialogFinder,
              matching: find.widgetWithText(
                FilledButton,
                WidgetUiCopy.actionGotIt,
              ),
            );
            await Scrollable.ensureVisible(tester.element(closeGotIt));
            await tester.pump(const Duration(milliseconds: 50));

            expect(
              find.byType(AppDialog),
              findsOneWidget,
              reason:
                  'Account invalidation preserves the retained help until dismissed',
            );
            expect(
              identical(tester.element(dialogFinder), initialDialogElement),
              isTrue,
              reason: 'Account invalidation preserves the same Dialog Element',
            );
            expect(
              fixture.channels.methodCalls,
              isEmpty,
              reason: 'Account invalidation must not produce platform calls',
            );

            // Dismissing this help is independent of account action authority.
            await tester.tap(closeGotIt);
            await _boundedPumpAndSettle(tester);

            expect(
              find.byType(AppDialog),
              findsNothing,
              reason:
                  'Got It must close its own help after account invalidation',
            );
            expect(find.byType(WidgetScreen), findsOneWidget);
            assertHostStateMaintained();
            expect(
              fixture.channels.methodCalls,
              isEmpty,
              reason: 'Dismissal must not produce platform calls',
            );
            expect(tester.takeException(), isNull);
          } else {
            // Standard close via Got It button
            final closeGotIt = find.descendant(
              of: dialogFinder,
              matching: find.widgetWithText(
                FilledButton,
                WidgetUiCopy.actionGotIt,
              ),
            );
            await Scrollable.ensureVisible(tester.element(closeGotIt));
            await tester.pump(const Duration(milliseconds: 50));
            await tester.tap(closeGotIt);
            await _boundedPumpAndSettle(tester);

            expect(find.byType(AppDialog), findsNothing);
            expect(find.byType(WidgetScreen), findsOneWidget);
            assertHostStateMaintained();
            expect(fixture.channels.methodCalls, isEmpty);
            expect(tester.takeException(), isNull);
          }
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
}
