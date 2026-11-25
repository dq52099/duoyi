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
import 'package:duoyi/services/widget_display_mode_store.dart';
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

import '../support/weekly_review_screenshot_font.dart';
import '../support/retained_dialog_text_probe.dart';

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
  String currentPinScenario = 'permission_denied';

  Future<Object?> handleWidgets(MethodCall call) async {
    methodCalls.add(call.method);
    switch (call.method) {
      case 'canRequestPinWidget':
        supportCalls++;
        if (currentPinScenario == 'unsupported_launcher') {
          return false;
        }
        return true;
      case 'canOpenWidgetSettings':
        canOpenSettingsCalls++;
        return true;
      case 'openWidgetSettings':
        openSettingsCalls++;
        return true;
      case 'requestPinWidget':
        pinRequestCalls++;
        if (currentPinScenario == 'invalid_widget_id') {
          return 'requested:pin-help-req-$pinRequestCalls';
        }
        return currentPinScenario;
      case 'lastPinResult':
        final args = call.arguments as Map<Object?, Object?>?;
        final reqId =
            args?['requestId']?.toString() ?? 'pin-help-req-$pinRequestCalls';
        return <String, Object>{
          'requestId': reqId,
          'status': 'invalid_widget_id',
          'kind': 'todo',
          'style': 'standard',
        };
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
    return switch (call.method) {
      'beginWait' => 'pin-help-receipt',
      _ => null,
    };
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
      Platform.environment['DUOYI_RETAINED_DIALOG_SCREENSHOT_DIR'];
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
      final file = File('$explicitDir/pin-help-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

class _PinHelpScenario {
  final String name;
  final AppLocale locale;
  final Size size;
  final double scale;
  final String initialBrand;
  final String targetBrand;
  final String pinScenario;
  final DuoyiWidgetKind targetKind;

  const _PinHelpScenario({
    required this.name,
    required this.locale,
    required this.size,
    required this.scale,
    required this.initialBrand,
    required this.targetBrand,
    required this.pinScenario,
    required this.targetKind,
  });
}

const _scenarios = <_PinHelpScenario>[
  _PinHelpScenario(
    name: 'zh-portrait-320x844-defaultBrand-denied',
    locale: AppLocale.zh,
    size: Size(320, 844),
    scale: 2.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    pinScenario: 'permission_denied',
    targetKind: DuoyiWidgetKind.todo,
  ),
  _PinHelpScenario(
    name: 'zh-landscape-844x390-liquidGlass-unsupported',
    locale: AppLocale.zh,
    size: Size(844, 390),
    scale: 1.0,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    pinScenario: 'unsupported_launcher',
    targetKind: DuoyiWidgetKind.habit,
  ),
  _PinHelpScenario(
    name: 'en-portrait-320x844-defaultBrand-confirmation-failure',
    locale: AppLocale.en,
    size: Size(320, 844),
    scale: 2.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    pinScenario: 'invalid_widget_id',
    targetKind: DuoyiWidgetKind.focus,
  ),
  _PinHelpScenario(
    name: 'en-landscape-844x390-liquidGlass-denied',
    locale: AppLocale.en,
    size: Size(844, 390),
    scale: 1.0,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    pinScenario: 'permission_denied',
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

  Future<void> mount(WidgetTester tester, _PinHelpScenario scenario) async {
    channels.currentPinScenario = scenario.pinScenario;
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
      AndroidWidgetManager.debugIsAndroidOverride = true;

      await tester.runAsync(() async {
        prefs = await SharedPreferences.getInstance();
        theme = ThemeProvider();
        preferences = PreferencesProvider();
        lock = _MutableLock();
        auth = _MutableAuthProvider();
        updater = _MutableUpdateService();

        await theme.loadFromStorage().timeout(const Duration(seconds: 5));
        await preferences.loadFromStorage().timeout(const Duration(seconds: 5));
        if (File('assets/fonts/DroidSansFallbackFull.ttf').existsSync() &&
            File('assets/fonts/DejaVuSans.ttf').existsSync()) {
          await loadWeeklyReviewScreenshotFonts().timeout(
            const Duration(seconds: 5),
          );
        }
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
                      textScaler: TextScaler.linear(scenario.scale),
                    ),
                    child: RepaintBoundary(key: boundaryKey, child: child!),
                  ),
                  home: Stack(
                    children: [
                      BrandBackground(
                        child: WidgetScreen(
                          key: const ValueKey('live-brand-widget-screen'),
                          hostPlatform: WidgetHostPlatform.android,
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

void main() {
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets(
      'widget pin help live brand priority defaultBrand <-> liquidGlass ${scenario.name}',
      (tester) async {
        I18n.setLocale(scenario.locale);
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

          // Track original WidgetScreen Element & State from outset
          final screenFinder = find.byType(WidgetScreen);
          expect(screenFinder, findsOneWidget);
          final initialScreenElement = tester.element(screenFinder);
          final initialScreenState = tester.state(screenFinder);

          // 1. Locate the target widget catalog card and its Add/disabled button
          final addControl = find.byKey(ValueKey(scenario.targetKind));
          final scrollable = find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(
            addControl,
            300,
            scrollable: scrollable,
          );
          await _boundedPumpAndSettle(tester);

          final button = find.descendant(
            of: addControl,
            matching: find.byType(FilledButton),
          );
          expect(button, findsOneWidget);

          // Track initiating catalog button State
          final initialButtonState = tester.state(
            find.ancestor(
              of: button,
              matching: find.byWidgetPredicate(
                (w) => w.runtimeType.toString() == '_AddWidgetButton',
              ),
            ),
          );

          final initialButtonLabel =
              scenario.pinScenario == 'unsupported_launcher'
              ? WidgetUiCopy.pinDisabledAction(
                  AndroidWidgetPinResult.unsupportedLauncher,
                )
              : WidgetUiCopy.addWidgetButtonLabel(
                  modeLabel: WidgetDisplayMode.standard.label,
                  launcherRequestLabel:
                      WidgetDisplayMode.standard.launcherRequestLabel,
                );
          expect(
            find.descendant(
              of: button,
              matching: find.text(initialButtonLabel),
            ),
            findsOneWidget,
          );

          // 2. Open real pin help through Add / disabled help
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

          final initialPinCalls = fixture.channels.pinRequestCalls;
          final initialSettingsCalls = fixture.channels.openSettingsCalls;

          String expectedTitle() => switch (scenario.pinScenario) {
            'invalid_widget_id' => WidgetUiCopy.pinConfirmationFailure(
              AndroidWidgetPinFinalStatus.invalidWidgetId,
            ).$1,
            _ => WidgetUiCopy.addDialogTitle,
          };

          String expectedMessage() => switch (scenario.pinScenario) {
            'unsupported_launcher' => WidgetUiCopy.pinHelpMessage(
              AndroidWidgetPinResult.unsupportedLauncher,
            ),
            'invalid_widget_id' => WidgetUiCopy.pinConfirmationFailure(
              AndroidWidgetPinFinalStatus.invalidWidgetId,
            ).$2,
            _ => WidgetUiCopy.pinHelpMessage(
              AndroidWidgetPinResult.permissionDenied,
            ),
          };

          void assertDialogThemeAndSurface(String expectedBrandId) {
            final currentDialogElement = tester.element(dialogFinder);
            final dialogTheme = Theme.of(currentDialogElement);

            // Construct explicit target-brand reference subtree from AppBrands.byId(expectedBrandId).theme
            final refElement = tester.element(
              find.byKey(
                ValueKey('ref_theme_$expectedBrandId'),
                skipOffstage: false,
              ),
            );
            final refTheme = Theme.of(refElement);
            final refStyle = appSecondaryFilledButtonStyle(refElement);

            final expectedPrimary = refTheme.colorScheme.primary;
            final expectedDialogBg =
                refTheme.dialogTheme.backgroundColor ??
                refTheme.colorScheme.surface;
            final expectedButtonBg = refStyle.backgroundColor?.resolve(
              const {},
            );
            final expectedButtonFg = refStyle.foregroundColor?.resolve(
              const {},
            );
            final expectedSurfaceStyle = appSurfaceStyleOf(refElement);

            // 1. Primary color from theme matches independent target brand reference
            expect(
              dialogTheme.colorScheme.primary,
              equals(expectedPrimary),
              reason:
                  'Dialog Theme.of primary must match $expectedBrandId reference',
            );

            // 2. Surface style matches target brand reference
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
              expect(
                actualSurfaceStyle,
                isNot(equals(AppSurfaceStyle.liquidGlass)),
              );
            }

            // 3. Compare actual dialog surface color from rendered AlertDialog Material
            final alertDialogFinder = find.descendant(
              of: dialogFinder,
              matching: find.byType(AlertDialog),
            );
            expect(alertDialogFinder, findsOneWidget);
            final dialogMaterial = tester.widget<Material>(
              find
                  .descendant(
                    of: alertDialogFinder,
                    matching: find.byType(Material),
                  )
                  .first,
            );
            expect(
              dialogMaterial.color,
              equals(expectedDialogBg),
              reason:
                  'Dialog surface Material background must match $expectedBrandId reference',
            );

            // 4. Compare effective button background and foreground against target brand reference
            final gotItFinder = find.descendant(
              of: dialogFinder,
              matching: find.widgetWithText(
                FilledButton,
                WidgetUiCopy.actionGotIt,
              ),
            );
            expect(gotItFinder, findsOneWidget);
            final gotItButton = tester.widget<FilledButton>(gotItFinder);
            final effectiveBtnBg = gotItButton.style?.backgroundColor?.resolve(
              const {},
            );
            final effectiveBtnFg = gotItButton.style?.foregroundColor?.resolve(
              const {},
            );
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

            // 5. Settings button theme primary matches target brand reference
            final settingsFinder = find.descendant(
              of: dialogFinder,
              matching: find.widgetWithText(
                TextButton,
                WidgetUiCopy.actionOpenPermissions,
              ),
            );
            expect(settingsFinder, findsOneWidget);
            final settingsElement = tester.element(settingsFinder);
            expect(
              Theme.of(settingsElement).colorScheme.primary,
              equals(expectedPrimary),
              reason:
                  'Settings button theme primary must match $expectedBrandId reference',
            );
          }

          Future<void> assertActionsReachableAndCompleteWords() async {
            final dialogElement = tester.element(dialogFinder);
            final mediaQuery = MediaQuery.of(dialogElement);
            expect(
              mediaQuery.textScaler,
              equals(TextScaler.linear(scenario.scale)),
              reason: 'Dialog must inherit scenario text scale',
            );

            // 1. Title is scroll-readable and complete
            final titleText = expectedTitle();
            final titleFinder = find.descendant(
              of: dialogFinder,
              matching: find.text(titleText),
            );
            expect(titleFinder, findsOneWidget);
            await Scrollable.ensureVisible(tester.element(titleFinder));
            await tester.pump(const Duration(milliseconds: 50));
            expect(titleFinder.hitTestable(), findsOneWidget);
            final titleParagraph = tester.renderObject<RenderParagraph>(
              titleFinder,
            );
            expect(
              titleParagraph.didExceedMaxLines,
              isFalse,
              reason: 'Title must fit complete words without truncation',
            );

            // 2. Content is scroll-readable and complete
            final messageText = expectedMessage();
            final messageFinder = find.descendant(
              of: dialogFinder,
              matching: find.text(messageText),
            );
            expect(messageFinder, findsOneWidget);
            await Scrollable.ensureVisible(tester.element(messageFinder));
            await tester.pump(const Duration(milliseconds: 50));
            expect(messageFinder.hitTestable(), findsOneWidget);
            final messageParagraph = tester.renderObject<RenderParagraph>(
              messageFinder,
            );
            expect(
              messageParagraph.didExceedMaxLines,
              isFalse,
              reason: 'Content must fit complete words without truncation',
            );

            // 3. Settings / Permissions Action
            final settingsButton = find.descendant(
              of: dialogFinder,
              matching: find.widgetWithText(
                TextButton,
                WidgetUiCopy.actionOpenPermissions,
              ),
            );
            expect(settingsButton, findsOneWidget);
            await Scrollable.ensureVisible(tester.element(settingsButton));
            await tester.pump(const Duration(milliseconds: 50));
            expect(
              settingsButton.hitTestable(),
              findsOneWidget,
              reason: 'Open permissions action must remain hit-testable',
            );
            final settingsText = find.descendant(
              of: settingsButton,
              matching: find.text(WidgetUiCopy.actionOpenPermissions),
            );
            expect(settingsText, findsOneWidget);
            final settingsParagraph = tester.renderObject<RenderParagraph>(
              settingsText,
            );
            expect(
              settingsParagraph.didExceedMaxLines,
              isFalse,
              reason:
                  'Open permissions label must display complete words without truncation',
            );

            // 4. Got It Action
            final gotItButton = find.descendant(
              of: dialogFinder,
              matching: find.widgetWithText(
                FilledButton,
                WidgetUiCopy.actionGotIt,
              ),
            );
            expect(gotItButton, findsOneWidget);
            await Scrollable.ensureVisible(tester.element(gotItButton));
            await tester.pump(const Duration(milliseconds: 50));
            expect(
              gotItButton.hitTestable(),
              findsOneWidget,
              reason: 'Got It action must remain hit-testable',
            );
            final gotItText = find.descendant(
              of: gotItButton,
              matching: find.text(WidgetUiCopy.actionGotIt),
            );
            expect(gotItText, findsOneWidget);
            final gotItParagraph = tester.renderObject<RenderParagraph>(
              gotItText,
            );
            expect(
              gotItParagraph.didExceedMaxLines,
              isFalse,
              reason:
                  'Got It label must display complete words without truncation',
            );

            for (final (finder, label) in [
              (titleFinder, titleText),
              (messageFinder, messageText),
              (settingsText, WidgetUiCopy.actionOpenPermissions),
              (gotItText, WidgetUiCopy.actionGotIt),
            ]) {
              await verifyRetainedDialogText(tester, finder, expected: label);
            }
          }

          void assertSelectionAndCallsUnchanged({
            required int expectedPinCalls,
            required int expectedSettingsCalls,
          }) {
            expect(
              fixture.channels.pinRequestCalls,
              equals(expectedPinCalls),
              reason: 'No duplicate pin calls should be made',
            );
            expect(
              fixture.channels.openSettingsCalls,
              equals(expectedSettingsCalls),
              reason: 'No duplicate settings calls should be made',
            );

            expect(
              WidgetDisplayModeSelection.read(fixture.prefs).mode,
              'standard',
              reason:
                  'Retained help must preserve the durable display selection',
            );
          }

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

          // Initial verification
          assertDialogThemeAndSurface(scenario.initialBrand);
          await assertActionsReachableAndCompleteWords();
          assertSelectionAndCallsUnchanged(
            expectedPinCalls: initialPinCalls,
            expectedSettingsCalls: initialSettingsCalls,
          );
          assertHostStateMaintained();
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

          assertDialogThemeAndSurface(scenario.targetBrand);
          await assertActionsReachableAndCompleteWords();
          assertSelectionAndCallsUnchanged(
            expectedPinCalls: initialPinCalls,
            expectedSettingsCalls: initialSettingsCalls,
          );
          assertHostStateMaintained();
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

          assertDialogThemeAndSurface(scenario.initialBrand);
          await assertActionsReachableAndCompleteWords();
          assertSelectionAndCallsUnchanged(
            expectedPinCalls: initialPinCalls,
            expectedSettingsCalls: initialSettingsCalls,
          );
          assertHostStateMaintained();
          await _capture(
            tester,
            fixture.boundaryKey,
            '${scenario.name}-03-returned-${scenario.initialBrand}',
          );

          // 5. Live locale switch to alternate locale while same overlay remains mounted
          final altLocale = scenario.locale == AppLocale.zh
              ? AppLocale.en
              : AppLocale.zh;
          I18n.setLocale(altLocale);
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
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.text(WidgetUiCopy.actionGotIt),
            ),
            findsOneWidget,
          );

          await assertActionsReachableAndCompleteWords();
          assertSelectionAndCallsUnchanged(
            expectedPinCalls: initialPinCalls,
            expectedSettingsCalls: initialSettingsCalls,
          );
          assertHostStateMaintained();
          await _capture(
            tester,
            fixture.boundaryKey,
            '${scenario.name}-04-locale-${altLocale.name}',
          );

          // 6. Live locale switch back to scenario initial locale
          I18n.setLocale(scenario.locale);
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
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.text(WidgetUiCopy.actionGotIt),
            ),
            findsOneWidget,
          );

          await assertActionsReachableAndCompleteWords();
          assertSelectionAndCallsUnchanged(
            expectedPinCalls: initialPinCalls,
            expectedSettingsCalls: initialSettingsCalls,
          );
          assertHostStateMaintained();
          await _capture(
            tester,
            fixture.boundaryKey,
            '${scenario.name}-05-locale-returned-${scenario.locale.name}',
          );

          // 7. Close dialog via Got It and return to WidgetScreen
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
          final modeSelector = find.byWidgetPredicate(
            (widget) => widget is SegmentedButton<WidgetDisplayMode>,
          );
          await tester.scrollUntilVisible(
            modeSelector,
            -300,
            scrollable: scrollable,
          );
          await _pumpThemeSwitchFrames(tester);
          expect(
            tester
                .widget<SegmentedButton<WidgetDisplayMode>>(modeSelector)
                .selected,
            {WidgetDisplayMode.standard},
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
  }
}
