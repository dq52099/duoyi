// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/lock_settings_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/weekly_review_screenshot_font.dart';

class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore(super.data) : super.withData();

  int lockWrites = 0;
  int themeWrites = 0;
  int otherWrites = 0;

  static bool _isLockKey(String key) {
    final clean = key.startsWith('flutter.') ? key.substring(8) : key;
    return clean.startsWith('app_lock');
  }

  static bool _isThemeKey(String key) {
    final clean = key.startsWith('flutter.') ? key.substring(8) : key;
    return clean == 'active_brand' ||
        clean == 'theme_switch_count' ||
        clean == 'theme_shop_state' ||
        clean == 'theme_unlocked_brands';
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (_isLockKey(key)) {
      lockWrites++;
    } else if (_isThemeKey(key)) {
      themeWrites++;
    } else {
      otherWrites++;
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    if (_isLockKey(key)) {
      lockWrites++;
    } else if (_isThemeKey(key)) {
      themeWrites++;
    } else {
      otherWrites++;
    }
    return super.remove(key);
  }
}

class _ControlledLock extends AppLockProvider {
  int pinSaves = 0;
  int disableCalls = 0;
  int uiVerifyCalls = 0;
  int setAutoLockCalls = 0;

  @override
  Future<bool> setPin(String value) async {
    pinSaves++;
    return super.setPin(value);
  }

  @override
  Future<bool> disable(String value) async {
    disableCalls++;
    return super.disable(value);
  }

  @override
  Future<bool> verify(String value) async {
    uiVerifyCalls++;
    return super.verify(value);
  }

  @override
  Future<void> setAutoLockMinutes(int minutes) async {
    setAutoLockCalls++;
    return super.setAutoLockMinutes(minutes);
  }
}

Future<void> _settleAsyncWork(
  WidgetTester tester, {
  Duration duration = const Duration(milliseconds: 50),
  Duration timeout = const Duration(seconds: 5),
}) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.runAsync(
    () => AccountPreferenceWrites.drain().timeout(const Duration(seconds: 5)),
  );
  await tester.pumpAndSettle(
    duration,
    EnginePhase.sendSemanticsUpdate,
    timeout,
  );
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await _settleAsyncWork(tester);
  expect(target.hitTestable(), findsOneWidget);
}

Future<void> _captureScopeScreenshot(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final explicitDir =
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
  final captureEnabled =
      Platform.environment['DUOYI_CAPTURE_SETTINGS_LIVE_BRAND_SCREENSHOTS'] ==
          '1' ||
      (explicitDir != null && explicitDir.isNotEmpty);
  if (!captureEnabled) return;

  final targetDir = (explicitDir != null && explicitDir.isNotEmpty)
      ? explicitDir
      : 'evidence/screenshots/settings-live-parallel-20261023';

  // Finish any theme/brand animation before capturing
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();

  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final file = File('$targetDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

class _LockPriorityScenario {
  final String name;
  final AppLocale initialLocale;
  final AppLocale alternateLocale;
  final Size size;
  final TextScaler scaler;
  final bool isExplicitSave;

  const _LockPriorityScenario({
    required this.name,
    required this.initialLocale,
    required this.alternateLocale,
    required this.size,
    required this.scaler,
    required this.isExplicitSave,
  });
}

const _scenarios = <_LockPriorityScenario>[
  _LockPriorityScenario(
    name: 'zh-portrait-320x844-cancel',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    size: Size(320, 844),
    scaler: TextScaler.linear(2.0),
    isExplicitSave: false,
  ),
  _LockPriorityScenario(
    name: 'en-portrait-320x844-save',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    size: Size(320, 844),
    scaler: TextScaler.linear(2.0),
    isExplicitSave: true,
  ),
  _LockPriorityScenario(
    name: 'zh-landscape-568x320-save',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    size: Size(568, 320),
    scaler: TextScaler.linear(2.0),
    isExplicitSave: true,
  ),
  _LockPriorityScenario(
    name: 'en-landscape-568x320-cancel',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    size: Size(568, 320),
    scaler: TextScaler.linear(2.0),
    isExplicitSave: false,
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));

  for (final scenario in _scenarios) {
    testWidgets(
      'LockSettingsScreen PIN dialog live brand priority ${scenario.name}',
      (tester) async {
        final originalShadows = debugDisableShadows;
        final initialLocale = I18n.current;
        SharedPreferencesStorePlatform? originalStore;

        ThemeProvider? theme;
        _ControlledLock? lock;
        PreferencesProvider? preferences;

        try {
          debugDisableShadows = false;

          final rawMockData = <String, Object>{
            'pref_app_timezone_mode': 'fixed',
            'pref_app_timezone_iana': 'Asia/Shanghai',
            'theme_shop_state': jsonEncode({
              'activeBrand': 'defaultBrand',
              'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
              'activeWidgetBackgroundId': ThemeProvider.widgetFollowThemeId,
            }),
            'active_brand': 'defaultBrand',
            'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          };
          SharedPreferences.setMockInitialValues(rawMockData);

          final recordingStore = _RecordingPreferencesStore({
            for (final entry in rawMockData.entries)
              'flutter.${entry.key}': entry.value,
          });
          originalStore = SharedPreferencesStorePlatform.instance;
          SharedPreferencesStorePlatform.instance = recordingStore;

          I18n.setLocale(scenario.initialLocale);

          tester.view.physicalSize = scenario.size;
          tester.view.devicePixelRatio = 1;

          await tester.runAsync(() async {
            theme = ThemeProvider();
            lock = _ControlledLock();
            preferences = PreferencesProvider();
            await theme!.loadFromStorage().timeout(const Duration(seconds: 5));
            await lock!.loadFromStorage().timeout(const Duration(seconds: 5));
            await preferences!.loadFromStorage().timeout(
              const Duration(seconds: 5),
            );
            await loadWeeklyReviewScreenshotFonts().timeout(
              const Duration(seconds: 5),
            );
          });

          expect(theme!.brand.id, 'defaultBrand');
          expect(theme!.isBrandUnlocked('liquidGlass'), isTrue);
          expect(lock!.enabled, isFalse);
          expect(recordingStore.lockWrites, 0);

          final boundaryKey = GlobalKey();

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme!),
                ChangeNotifierProvider<AppLockProvider>.value(value: lock!),
                ChangeNotifierProvider<PreferencesProvider>.value(
                  value: preferences!,
                ),
              ],
              child: Consumer<ThemeProvider>(
                builder: (context, themeProvider, _) {
                  return ValueListenableBuilder<AppLocale>(
                    valueListenable: I18n.localeListenable,
                    builder: (context, locale, _) {
                      return MaterialApp(
                        locale: Locale(locale == AppLocale.en ? 'en' : 'zh'),
                        supportedLocales: const [Locale('en'), Locale('zh')],
                        localizationsDelegates:
                            GlobalMaterialLocalizations.delegates,
                        theme: themeProvider.brand.theme,
                        builder: (context, child) => MediaQuery(
                          data: MediaQuery.of(
                            context,
                          ).copyWith(textScaler: scenario.scaler),
                          child: RepaintBoundary(
                            key: boundaryKey,
                            child: child!,
                          ),
                        ),
                        home: const BrandRouteSurface(
                          remountOnLocaleChange: false,
                          child: LockSettingsScreen(),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          );

          await _settleAsyncWork(tester);
          expect(tester.takeException(), isNull);

          final screenFinder = find.byType(LockSettingsScreen);
          expect(screenFinder, findsOneWidget);

          final screenStateBefore = tester.state(screenFinder);
          final screenRouteBefore = ModalRoute.of(
            tester.element(screenFinder),
          )!;
          expect(screenRouteBefore.isCurrent, isTrue);

          final switchFinder = find.byType(Switch).first;
          await _reveal(tester, switchFinder);
          await tester.tap(switchFinder);
          await _settleAsyncWork(tester);

          final dialogFinder = find.byType(AppDialog);
          expect(dialogFinder, findsOneWidget);

          final expectedSetTitle = scenario.initialLocale == AppLocale.en
              ? 'Set PIN (4-8 digits)'
              : '设置 PIN (4-8 位数字)';
          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.text(expectedSetTitle),
            ),
            findsOneWidget,
          );

          final firstInput = find.descendant(
            of: dialogFinder,
            matching: find.byType(TextField),
          );
          expect(firstInput, findsOneWidget);
          await _reveal(tester, firstInput);
          await tester.enterText(firstInput, '2468');

          final firstConfirmBtn = find.descendant(
            of: dialogFinder,
            matching: find.widgetWithText(
              FilledButton,
              I18n.tr('action.confirm'),
            ),
          );
          await _reveal(tester, firstConfirmBtn);
          await tester.tap(firstConfirmBtn);
          await _settleAsyncWork(tester);

          expect(dialogFinder, findsOneWidget);

          final expectedInitialConfirmTitle =
              scenario.initialLocale == AppLocale.en
              ? 'Enter it again to confirm'
              : '再输一遍确认';
          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.text(expectedInitialConfirmTitle),
            ),
            findsOneWidget,
          );

          final confirmInput = find.descendant(
            of: dialogFinder,
            matching: find.byType(TextField),
          );
          expect(confirmInput, findsOneWidget);
          await _reveal(tester, confirmInput);

          final confirmController = tester
              .widget<TextField>(confirmInput)
              .controller!;
          final dialogRouteBefore = ModalRoute.of(
            tester.element(confirmInput),
          )!;
          expect(dialogRouteBefore, isNot(same(screenRouteBefore)));

          confirmController.value = const TextEditingValue(
            text: '2468',
            selection: TextSelection(baseOffset: 1, extentOffset: 3),
          );
          await tester.pump();

          expect(confirmController.text, '2468');
          expect(
            confirmController.selection,
            const TextSelection(baseOffset: 1, extentOffset: 3),
          );
          expect(lock!.pinSaves, 0);
          expect(recordingStore.lockWrites, 0);

          await _captureScopeScreenshot(
            tester,
            boundaryKey,
            '${scenario.name}-01-confirm-dialog-initial',
          );

          // 1. Live brand switch: defaultBrand -> liquidGlass
          await tester.runAsync(() async {
            final switched = await theme!.setBrand('liquidGlass');
            expect(switched, isTrue);
          });
          await _settleAsyncWork(tester);
          expect(tester.takeException(), isNull);

          expect(theme!.brand.id, 'liquidGlass');
          final prefsInGlass = await SharedPreferences.getInstance();
          expect(prefsInGlass.getString('active_brand'), 'liquidGlass');

          final screenThemeInGlass = Theme.of(tester.element(screenFinder));
          expect(
            Theme.of(tester.element(dialogFinder)).colorScheme.primary,
            AppBrands.liquidGlass.theme.colorScheme.primary,
          );
          expect(
            appSurfaceStyleOf(tester.element(dialogFinder)),
            AppSurfaceStyle.liquidGlass,
          );
          expect(
            screenThemeInGlass.colorScheme.primary,
            AppBrands.liquidGlass.theme.colorScheme.primary,
          );

          // Assert State, ModalRoute, and controller identities are retained across brand switch
          expect(tester.state(screenFinder), same(screenStateBefore));
          expect(
            ModalRoute.of(tester.element(screenFinder)),
            same(screenRouteBefore),
          );
          expect(
            ModalRoute.of(
              tester.element(
                find.descendant(
                  of: dialogFinder,
                  matching: find.byType(TextField),
                ),
              ),
            ),
            same(dialogRouteBefore),
          );
          final controllerInGlass = tester
              .widget<TextField>(
                find.descendant(
                  of: dialogFinder,
                  matching: find.byType(TextField),
                ),
              )
              .controller!;
          expect(controllerInGlass, same(confirmController));
          expect(controllerInGlass.text, '2468');
          expect(
            controllerInGlass.selection,
            const TextSelection(baseOffset: 1, extentOffset: 3),
          );

          // Assert no premature lock writes or saves
          expect(lock!.pinSaves, 0);
          expect(lock!.enabled, isFalse);
          expect(recordingStore.lockWrites, 0);

          await _captureScopeScreenshot(
            tester,
            boundaryKey,
            '${scenario.name}-02-dialog-liquidGlass',
          );

          // 2. Live brand switch: liquidGlass -> defaultBrand
          await tester.runAsync(() async {
            final reverted = await theme!.setBrand('defaultBrand');
            expect(reverted, isTrue);
          });
          await _settleAsyncWork(tester);
          expect(tester.takeException(), isNull);

          expect(theme!.brand.id, 'defaultBrand');
          final prefsInDefault = await SharedPreferences.getInstance();
          expect(prefsInDefault.getString('active_brand'), 'defaultBrand');

          final screenThemeInDefault = Theme.of(tester.element(screenFinder));
          expect(
            Theme.of(tester.element(dialogFinder)).colorScheme.primary,
            AppBrands.defaultBrand.theme.colorScheme.primary,
          );
          expect(
            screenThemeInDefault.colorScheme.primary,
            AppBrands.defaultBrand.theme.colorScheme.primary,
          );

          // Assert State, ModalRoute, and controller identities are retained after reverting
          expect(tester.state(screenFinder), same(screenStateBefore));
          expect(
            ModalRoute.of(tester.element(screenFinder)),
            same(screenRouteBefore),
          );
          expect(
            ModalRoute.of(
              tester.element(
                find.descendant(
                  of: dialogFinder,
                  matching: find.byType(TextField),
                ),
              ),
            ),
            same(dialogRouteBefore),
          );
          final controllerInDefault = tester
              .widget<TextField>(
                find.descendant(
                  of: dialogFinder,
                  matching: find.byType(TextField),
                ),
              )
              .controller!;
          expect(controllerInDefault, same(confirmController));
          expect(controllerInDefault.text, '2468');
          expect(
            controllerInDefault.selection,
            const TextSelection(baseOffset: 1, extentOffset: 3),
          );

          // Still no premature lock writes
          expect(lock!.pinSaves, 0);
          expect(lock!.enabled, isFalse);
          expect(recordingStore.lockWrites, 0);

          await _captureScopeScreenshot(
            tester,
            boundaryKey,
            '${scenario.name}-03-dialog-reverted-defaultBrand',
          );

          // 3. Live locale switch
          I18n.setLocale(scenario.alternateLocale);
          await _settleAsyncWork(tester);
          expect(tester.takeException(), isNull);

          final expectedAlternateConfirmTitle =
              scenario.alternateLocale == AppLocale.en
              ? 'Enter it again to confirm'
              : '再输一遍确认';
          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.text(expectedAlternateConfirmTitle),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.text(I18n.tr('action.cancel')),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.text(I18n.tr('action.confirm')),
            ),
            findsOneWidget,
          );

          // Verify identities, uncommitted draft and selection across live locale switch
          expect(tester.state(screenFinder), same(screenStateBefore));
          expect(
            ModalRoute.of(tester.element(screenFinder)),
            same(screenRouteBefore),
          );
          expect(
            ModalRoute.of(
              tester.element(
                find.descendant(
                  of: dialogFinder,
                  matching: find.byType(TextField),
                ),
              ),
            ),
            same(dialogRouteBefore),
          );
          final controllerInAlternateLocale = tester
              .widget<TextField>(
                find.descendant(
                  of: dialogFinder,
                  matching: find.byType(TextField),
                ),
              )
              .controller!;
          expect(controllerInAlternateLocale, same(confirmController));
          expect(controllerInAlternateLocale.text, '2468');
          expect(
            controllerInAlternateLocale.selection,
            const TextSelection(baseOffset: 1, extentOffset: 3),
          );

          // Still no premature lock writes
          expect(lock!.pinSaves, 0);
          expect(lock!.enabled, isFalse);
          expect(recordingStore.lockWrites, 0);

          await _captureScopeScreenshot(
            tester,
            boundaryKey,
            '${scenario.name}-04-dialog-alternate-locale',
          );

          // 4. Final contract action: explicit Cancel vs explicit Confirm
          if (!scenario.isExplicitSave) {
            final cancelBtn = find.descendant(
              of: dialogFinder,
              matching: find.widgetWithText(
                TextButton,
                I18n.tr('action.cancel'),
              ),
            );
            await _reveal(tester, cancelBtn);
            await tester.tap(cancelBtn);
            await _settleAsyncWork(tester);

            // Dialog popped, route retained and safe
            expect(find.byType(AppDialog), findsNothing);
            expect(screenRouteBefore.isCurrent, isTrue);
            expect(tester.state(screenFinder), same(screenStateBefore));

            // Lock remains disabled, storage unchanged
            expect(lock!.enabled, isFalse);
            expect(lock!.pinSaves, 0);
            expect(recordingStore.lockWrites, 0);

            await _reveal(tester, switchFinder);
            expect(tester.widget<Switch>(switchFinder).value, isFalse);
            expect(find.byType(SnackBar), findsNothing);

            await _captureScopeScreenshot(
              tester,
              boundaryKey,
              '${scenario.name}-05-cancelled-screen',
            );
          } else {
            final confirmBtn = find.descendant(
              of: dialogFinder,
              matching: find.widgetWithText(
                FilledButton,
                I18n.tr('action.confirm'),
              ),
            );
            await _reveal(tester, confirmBtn);
            await tester.tap(confirmBtn);
            await _settleAsyncWork(tester);

            // Dialog popped, route retained and safe
            expect(find.byType(AppDialog), findsNothing);
            expect(screenRouteBefore.isCurrent, isTrue);
            expect(tester.state(screenFinder), same(screenStateBefore));

            // Exactly one intentional save executed
            expect(lock!.pinSaves, 1);
            expect(lock!.enabled, isTrue);
            expect(recordingStore.lockWrites, 2);

            await _reveal(tester, switchFinder);
            expect(tester.widget<Switch>(switchFinder).value, isTrue);
            expect(
              find.text(I18n.tr('app_lock.enabled_message')),
              findsOneWidget,
            );

            await _captureScopeScreenshot(
              tester,
              boundaryKey,
              '${scenario.name}-05-confirmed-screen',
            );
          }

          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle(
            const Duration(milliseconds: 50),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 5),
          );
          debugDisableShadows = originalShadows;
          I18n.setLocale(initialLocale);
          tester.view.reset();
          SharedPreferences.resetStatic();
          if (originalStore != null) {
            SharedPreferencesStorePlatform.instance = originalStore;
          }
          theme?.dispose();
          lock?.dispose();
          preferences?.dispose();
        }
      },
    );
  }
}
