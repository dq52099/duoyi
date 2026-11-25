// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/account_ui_copy.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/profile_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/account_status_chip.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandBackground;
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/retained_dialog_text_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

class _PasswordLiveBrandScenario {
  final String name;
  final AppLocale initialLocale;
  final AppLocale alternateLocale;
  final String initialBrand;
  final String targetBrand;
  final Size size;
  final double scale;
  final double devicePixelRatio;
  final bool shouldSave;

  const _PasswordLiveBrandScenario({
    required this.name,
    required this.initialLocale,
    required this.alternateLocale,
    required this.initialBrand,
    required this.targetBrand,
    required this.size,
    required this.scale,
    required this.devicePixelRatio,
    required this.shouldSave,
  });
}

const _scenarios = <_PasswordLiveBrandScenario>[
  _PasswordLiveBrandScenario(
    name: 'zh-portrait-320x844-dpr2-defaultBrand',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(320, 844),
    scale: 2.0,
    devicePixelRatio: 2.0,
    shouldSave: false,
  ),
  _PasswordLiveBrandScenario(
    name: 'en-portrait-320x844-dpr2-liquidGlass',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(320, 844),
    scale: 2.0,
    devicePixelRatio: 2.0,
    shouldSave: true,
  ),
  _PasswordLiveBrandScenario(
    name: 'zh-landscape-844x390-dpr1-liquidGlass',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(844, 390),
    scale: 1.0,
    devicePixelRatio: 1.0,
    shouldSave: false,
  ),
  _PasswordLiveBrandScenario(
    name: 'en-landscape-844x390-dpr1-defaultBrand',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(844, 390),
    scale: 1.0,
    devicePixelRatio: 1.0,
    shouldSave: true,
  ),
];

Finder _field(String key) => find.byWidgetPredicate(
  (widget) =>
      widget is TextField && widget.decoration?.labelText == I18n.tr(key),
);

Finder _dialogField(String key) =>
    find.descendant(of: find.byType(AppDialog), matching: _field(key));

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

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final explicitDir =
      Platform.environment['DUOYI_RETAINED_DIALOG_SCREENSHOT_DIR'] ??
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
  if (explicitDir == null || explicitDir.isEmpty) return;

  await tester.runAsync(() async {
    Future<void> capture() async {
      final boundary =
          boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) return;
        final file = File('$explicitDir/$name.png');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(data.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    }

    // Start the diagnostic timer in the real-I/O zone, since no fake frames
    // advance while runAsync is waiting for the rasterizer.
    await capture().timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException(
        'Screenshot capture "$name" timed out after 10s',
      ),
    );
  });
}

Future<void> _coverCurrentRoute(WidgetTester tester, {Finder? host}) async {
  Navigator.of(tester.element(host ?? find.byType(ProfileScreen))).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Covered foreground route')),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _returnFromCoveredRoute(WidgetTester tester) async {
  Navigator.of(tester.element(find.text('Covered foreground route'))).pop();
  await _boundedPumpAndSettle(tester);
}

Future<void> _replaceSession(
  WidgetTester tester,
  AuthProvider auth, {
  bool sameUser = false,
}) async {
  await tester.runAsync(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'auth_state',
      jsonEncode(
        AuthState(
          userId: sameUser
              ? 'profile-synthetic-user'
              : 'profile-replacement-user',
          username: 'replacement-user',
          displayName: 'Replacement User',
          email: 'replacement@example.test',
          token: 'synthetic-replacement-token',
        ).toJson(),
      ),
    );
    await auth
        .loadFromStorage(refreshServerConfig: false)
        .timeout(const Duration(seconds: 10));
  });
  await tester.pump(const Duration(milliseconds: 50));
  expect(
    auth.state.userId,
    sameUser ? 'profile-synthetic-user' : 'profile-replacement-user',
  );
}

class _PasswordFixture {
  final _PasswordLiveBrandScenario scenario;
  late final AuthProvider auth;
  late final UserProvider userProvider;
  late final ThemeProvider theme;
  late final PreferencesProvider preferences;
  final GlobalKey boundaryKey = GlobalKey();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final Completer<http.Response> passwordRelease = Completer<http.Response>();
  int passwordCalls = 0;
  final bool autoSucceedPassword;
  bool _disposed = false;

  late bool originalShadows;
  late AppLocale originalLocale;
  late Future<String?> Function()? originalTimeZoneReader;
  late SharedPreferencesStorePlatform previousStore;

  _PasswordFixture({required this.scenario, this.autoSucceedPassword = true});

  Future<void> setUpAsync() async {
    originalLocale = I18n.current;
    originalShadows = debugDisableShadows;
    originalTimeZoneReader = LocalTimezoneResolver.debugSystemTimeZoneReader;
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
    previousStore = SharedPreferencesStorePlatform.instance;

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
    final store = InMemorySharedPreferencesStore.withData({
      for (final entry in initialPrefs.entries)
        if (!entry.key.startsWith('flutter.'))
          'flutter.${entry.key}': entry.value,
    });
    SharedPreferencesStorePlatform.instance = store;

    I18n.setLocale(scenario.initialLocale);
    debugDisableShadows = false;

    // Real AuthProvider with MockClient success & production-like local cleanup callback
    auth = AuthProvider(
      initialState: const AuthState(
        userId: 'profile-synthetic-user',
        username: 'synthetic-user',
        displayName: 'Synthetic user',
        email: 'synthetic@example.test',
        token: 'synthetic-password-token',
      ),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'synthetic-password-token',
        httpClient: MockClient((request) async {
          if (request.method == 'POST' &&
              (request.url.path == '/api/me/password' ||
                  request.url.path == '/api/auth/change-password')) {
            passwordCalls++;
            if (autoSucceedPassword) {
              return http.Response(
                jsonEncode({'status': 'ok'}),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return passwordRelease.future;
          }
          return http.Response('not found', 404);
        }),
      ),
    );

    // Simulated local cleanup callback mirroring main.dart production wiring
    auth.onAccountLoggedOut = () async {
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    };

    userProvider = UserProvider();
    theme = ThemeProvider();
    preferences = PreferencesProvider();

    await theme.loadFromStorage().timeout(const Duration(seconds: 5));
    await preferences.loadFromStorage().timeout(const Duration(seconds: 5));
    await loadWeeklyReviewScreenshotFonts().timeout(const Duration(seconds: 5));

    await userProvider.applyAccountSnapshot(
      username: 'synthetic-user',
      displayName: 'Synthetic user',
      email: 'synthetic@example.test',
      emailVerified: true,
      avatarUrl: 'synthetic-avatar',
      bio: 'Synthetic baseline bio',
    );
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = Size(
      scenario.size.width * scenario.devicePixelRatio,
      scenario.size.height * scenario.devicePixelRatio,
    );
    tester.view.devicePixelRatio = scenario.devicePixelRatio;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
          ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
        ],
        child: AnimatedBuilder(
          animation: Listenable.merge([theme, I18n.localeListenable]),
          builder: (context, _) => MaterialApp(
            navigatorKey: navigatorKey,
            scaffoldMessengerKey: messengerKey,
            debugShowCheckedModeBanner: false,
            locale: Locale(I18n.current == AppLocale.en ? 'en' : 'zh'),
            supportedLocales: const [Locale('en'), Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: theme.brand.theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scenario.scale)),
              child: RepaintBoundary(key: boundaryKey, child: child!),
            ),
            home: Stack(
              children: [
                const BrandBackground(child: ProfileScreen()),
                for (final brand in [
                  AppBrands.defaultBrand,
                  AppBrands.liquidGlass,
                ])
                  Offstage(
                    offstage: true,
                    child: Theme(
                      data: brand.theme,
                      child: Material(
                        type: MaterialType.card,
                        color:
                            brand.theme.dialogTheme.backgroundColor ??
                            brand.theme.colorScheme.surface,
                        child: DefaultTextStyle(
                          style:
                              (brand.theme.textTheme.titleMedium ??
                                      const TextStyle())
                                  .copyWith(
                                    color: brand.theme.colorScheme.onSurface,
                                  ),
                          child: AppSecondaryControlTheme(
                            child: Builder(
                              key: ValueKey('ref_theme_${brand.id}'),
                              builder: (refContext) {
                                return Wrap(
                                  children: [
                                    TextButton(
                                      key: ValueKey('ref_cancel_${brand.id}'),
                                      onPressed: () {},
                                      child: Text(I18n.tr('action.cancel')),
                                    ),
                                    FilledButton(
                                      key: ValueKey('ref_save_${brand.id}'),
                                      onPressed: () {},
                                      style: appSecondaryFilledButtonStyle(
                                        refContext,
                                      ),
                                      child: Text(I18n.tr('action.save')),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await _boundedPumpAndSettle(tester);
  }

  Future<void> openChangePasswordDialog(WidgetTester tester) async {
    final entrance = find.widgetWithText(
      TextButton,
      I18n.tr('profile.change_password'),
    );
    await tester.scrollUntilVisible(
      entrance,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await _boundedPumpAndSettle(tester);
    await tester.tap(entrance);
    await _boundedPumpAndSettle(tester);
    expect(find.byType(AppDialog), findsOneWidget);
  }

  Future<void> dispose(WidgetTester tester) async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _drainAccountWrites(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await _boundedPumpAndSettle(tester);
    } finally {
      tester.view.reset();
      debugDisableShadows = originalShadows;
      I18n.setLocale(originalLocale);
      LocalTimezoneResolver.debugSystemTimeZoneReader = originalTimeZoneReader;
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = previousStore;
      auth.dispose();
      userProvider.dispose();
      theme.dispose();
      preferences.dispose();
    }
  }
}

void main() {
  setUp(() {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() {
    SharedPreferences.resetStatic();
    I18n.setLocale(AppLocale.zh);
  });

  for (final scenario in _scenarios) {
    testWidgets('profile change-password retained live brand priority ${scenario.name}', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final fixture = _PasswordFixture(
        scenario: scenario,
        autoSucceedPassword: scenario.shouldSave,
      );

      try {
        // Asynchronous initialization executed safely within tester.runAsync
        await tester.runAsync(() async {
          await fixture.setUpAsync();
        });

        // 1. Production entry in stable BrandBackground from first frame
        await fixture.pump(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(BrandBackground), findsWidgets);
        expect(find.byType(ProfileScreen), findsOneWidget);

        // Assert actual root RenderBox logical size and actual MediaQuery values
        final rootBox = tester.renderObject<RenderBox>(
          find.byType(MaterialApp),
        );
        expect(
          rootBox.size,
          equals(scenario.size),
          reason:
              'Root RenderBox logical size must equal scenario size ${scenario.size}',
        );
        final rootMedia = MediaQuery.of(
          tester.element(find.byType(ProfileScreen)),
        );
        expect(
          rootMedia.size,
          equals(scenario.size),
          reason:
              'Root MediaQuery size must naturally equal scenario size ${scenario.size}',
        );
        expect(
          rootMedia.devicePixelRatio,
          equals(scenario.devicePixelRatio),
          reason:
              'Root MediaQuery devicePixelRatio must equal scenario DPR ${scenario.devicePixelRatio}',
        );
        expect(
          rootMedia.textScaler,
          equals(TextScaler.linear(scenario.scale)),
          reason:
              'Root MediaQuery textScaler must equal scenario scale ${scenario.scale}',
        );

        // Verify entrance button with complete Latin words, adaptive height and natural wrapping
        final entranceTextFinder = find.text(
          I18n.tr('profile.change_password'),
        );
        await tester.scrollUntilVisible(
          entranceTextFinder,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await _boundedPumpAndSettle(tester);
        expect(entranceTextFinder, findsOneWidget);
        final entranceParagraph = tester.renderObject<RenderParagraph>(
          entranceTextFinder,
        );
        expect(
          entranceParagraph.didExceedMaxLines,
          isFalse,
          reason: 'Entrance button text must not be clipped by maxLines',
        );
        expect(entranceTextFinder.hitTestable(), findsOneWidget);

        // 2. Open actual change-password dialog through production entrance
        await fixture.openChangePasswordDialog(tester);
        expect(tester.takeException(), isNull);

        final dialogFinder = find.byType(AppDialog);
        expect(dialogFinder, findsOneWidget);
        final initialDialogElement = tester.element(dialogFinder);
        final initialDialogRoute = ModalRoute.of(initialDialogElement);
        expect(initialDialogRoute, isNotNull);

        final currentField = _dialogField('profile.current_password');
        final newField = _dialogField('auth.new_password');
        final confirmField = _dialogField('profile.confirm_new_password');
        expect(currentField, findsOneWidget);
        expect(newField, findsOneWidget);
        expect(confirmField, findsOneWidget);

        final currentCtrl = tester.widget<TextField>(currentField).controller!;
        final newCtrl = tester.widget<TextField>(newField).controller!;
        final confirmCtrl = tester.widget<TextField>(confirmField).controller!;

        void assertDialogThemeAndSurface(String expectedBrandId) {
          final currentDialogElement = tester.element(dialogFinder);
          final dialogTheme = Theme.of(currentDialogElement);

          final refThemeElement = tester.element(
            find.byKey(
              ValueKey('ref_theme_$expectedBrandId'),
              skipOffstage: false,
            ),
          );
          final refTheme = Theme.of(refThemeElement);
          final refSaveButton = tester.widget<FilledButton>(
            find.byKey(
              ValueKey('ref_save_$expectedBrandId'),
              skipOffstage: false,
            ),
          );

          final expectedPrimary = refTheme.colorScheme.primary;
          final expectedDialogBg =
              refTheme.dialogTheme.backgroundColor ??
              refTheme.colorScheme.surface;
          final expectedButtonBg = refSaveButton.style?.backgroundColor
              ?.resolve({});
          final expectedButtonFg = refSaveButton.style?.foregroundColor
              ?.resolve({});
          final expectedSurfaceStyle = appSurfaceStyleOf(refThemeElement);

          expect(
            dialogTheme.colorScheme.primary,
            equals(expectedPrimary),
            reason:
                'Dialog Theme.of primary must match $expectedBrandId reference',
          );

          final actualSurfaceStyle = appSurfaceStyleOf(currentDialogElement);
          expect(
            actualSurfaceStyle,
            equals(expectedSurfaceStyle),
            reason:
                'Dialog surface style must match $expectedBrandId reference',
          );
          if (expectedBrandId == 'liquidGlass') {
            expect(actualSurfaceStyle, equals(AppSurfaceStyle.liquidGlass));
          } else {
            expect(
              actualSurfaceStyle,
              isNot(equals(AppSurfaceStyle.liquidGlass)),
            );
          }

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

          final saveFinder = find.descendant(
            of: dialogFinder,
            matching: find.widgetWithText(FilledButton, I18n.tr('action.save')),
          );
          expect(saveFinder, findsOneWidget);
          final saveButton = tester.widget<FilledButton>(saveFinder);
          final effectiveBtnBg = saveButton.style?.backgroundColor?.resolve({});
          final effectiveBtnFg = saveButton.style?.foregroundColor?.resolve({});
          expect(
            effectiveBtnBg,
            equals(expectedButtonBg),
            reason:
                'Save button background must match $expectedBrandId reference ($expectedButtonBg)',
          );
          expect(
            effectiveBtnFg,
            equals(expectedButtonFg),
            reason:
                'Save button foreground must match $expectedBrandId reference ($expectedButtonFg)',
          );

          final cancelFinder = find.descendant(
            of: dialogFinder,
            matching: find.widgetWithText(TextButton, I18n.tr('action.cancel')),
          );
          expect(cancelFinder, findsOneWidget);
          final cancelElement = tester.element(cancelFinder);
          expect(
            Theme.of(cancelElement).colorScheme.primary,
            equals(expectedPrimary),
            reason:
                'Cancel button primary color must match $expectedBrandId reference',
          );
        }

        Future<void> assertLabelsReadableAndCompleteWords() async {
          final dialogElement = tester.element(dialogFinder);
          final mediaQuery = MediaQuery.of(dialogElement);
          expect(
            mediaQuery.textScaler,
            equals(TextScaler.linear(scenario.scale)),
            reason: 'Dialog must inherit scenario text scale',
          );

          final titleFinder = find.descendant(
            of: dialogFinder,
            matching: find.text(I18n.tr('profile.change_password')),
          );
          expect(titleFinder, findsOneWidget);
          final titleParagraph = tester.renderObject<RenderParagraph>(
            titleFinder,
          );
          expect(
            titleParagraph.didExceedMaxLines,
            isFalse,
            reason: 'Title must fit complete words without max-line clipping',
          );

          final cancelFinder = find.descendant(
            of: dialogFinder,
            matching: find.widgetWithText(TextButton, I18n.tr('action.cancel')),
          );
          final cancelTextFinder = find.descendant(
            of: cancelFinder,
            matching: find.text(I18n.tr('action.cancel')),
          );
          expect(cancelTextFinder, findsOneWidget);

          final saveFinder = find.descendant(
            of: dialogFinder,
            matching: find.widgetWithText(FilledButton, I18n.tr('action.save')),
          );
          final saveTextFinder = find.descendant(
            of: saveFinder,
            matching: find.text(I18n.tr('action.save')),
          );
          expect(saveTextFinder, findsOneWidget);

          for (final (finder, label) in [
            (titleFinder, I18n.tr('profile.change_password')),
            (cancelTextFinder, I18n.tr('action.cancel')),
            (saveTextFinder, I18n.tr('action.save')),
          ]) {
            await verifyRetainedDialogText(tester, finder, expected: label);
          }

          // Verify full multiline hints without truncation
          for (final (fieldFinder, key) in [
            (currentField, 'profile.current_password'),
            (newField, 'auth.new_password'),
            (confirmField, 'profile.confirm_new_password'),
          ]) {
            final fieldWidget = tester.widget<TextField>(fieldFinder);
            final expectedHint = I18n.tr(key);
            expect(
              fieldWidget.decoration?.hintText,
              equals(expectedHint),
              reason: '$key hintText must match localized copy',
            );
            expect(
              fieldWidget.decoration?.hintMaxLines,
              greaterThanOrEqualTo(2),
              reason: '$key hintMaxLines must allow multiline wrapping',
            );
            expect(
              fieldWidget.decoration?.floatingLabelBehavior,
              equals(FloatingLabelBehavior.always),
              reason:
                  '$key floatingLabelBehavior must remain always to render hints',
            );
            if (fieldWidget.controller?.text.isEmpty ?? true) {
              final hintFinder = find.descendant(
                of: fieldFinder,
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is Text &&
                      w.data == expectedHint &&
                      w.maxLines == fieldWidget.decoration?.hintMaxLines,
                ),
              );
              expect(hintFinder, findsOneWidget);
              final hintParagraph = tester.renderObject<RenderParagraph>(
                hintFinder,
              );
              expect(
                hintParagraph.didExceedMaxLines,
                isFalse,
                reason: '$key hint must fit without maxLines clipping',
              );
              expect(
                hintParagraph.text.toPlainText(),
                equals(expectedHint),
                reason: '$key hint must display full localized text',
              );
              expect(
                hintParagraph.text.toPlainText(),
                isNot(contains('\u2026')),
                reason: '$key hint must not be ellipsized',
              );
              final dialogRect = tester.getRect(dialogFinder);
              final hintRect = tester.getRect(hintFinder);
              expect(
                hintRect.left,
                greaterThanOrEqualTo(dialogRect.left - 1.0),
                reason: '$key hint must fit inside dialog horizontally',
              );
              expect(
                hintRect.right,
                lessThanOrEqualTo(dialogRect.right + 1.0),
                reason: '$key hint must fit inside dialog horizontally',
              );
            }
          }
        }

        // Initial verification of theme, surface and readability
        assertDialogThemeAndSurface(scenario.initialBrand);
        await assertLabelsReadableAndCompleteWords();
        await _capture(
          tester,
          fixture.boundaryKey,
          '${scenario.name}-01-opening',
        );

        // 3. Synthetic passwords, selection, focus, obscure toggles, and validation error
        const syntheticCurrent = 'SyntheticCurrent1!';
        const syntheticNext = 'NextSynthetic2!';
        const syntheticMismatch = 'MismatchPass3!';
        const draftSelection = TextSelection(baseOffset: 2, extentOffset: 8);

        await tester.tap(currentField);
        await tester.enterText(currentField, syntheticCurrent);
        await tester.enterText(newField, syntheticNext);
        await tester.enterText(confirmField, syntheticMismatch);
        currentCtrl.selection = draftSelection;
        await tester.pump();

        expect(
          tester.widget<TextField>(currentField).obscureText,
          isTrue,
          reason: 'Current password must be obscured by default',
        );
        expect(
          tester.widget<TextField>(newField).obscureText,
          isTrue,
          reason: 'New password must be obscured by default',
        );
        expect(
          tester.widget<TextField>(confirmField).obscureText,
          isTrue,
          reason: 'Confirm password must be obscured by default',
        );

        // Test obscure toggle briefly on current password field
        final obscureToggle = find.descendant(
          of: currentField,
          matching: find.byType(IconButton),
        );
        expect(obscureToggle, findsOneWidget);
        await tester.tap(obscureToggle);
        await tester.pump();
        expect(
          tester.widget<TextField>(currentField).obscureText,
          isFalse,
          reason: 'Password visibility toggled to visible',
        );
        // Toggle back to obscure per credential privacy requirements
        await tester.tap(obscureToggle);
        await tester.pump();
        expect(
          tester.widget<TextField>(currentField).obscureText,
          isTrue,
          reason: 'Password visibility restored to obscure',
        );

        // Trigger validation failure with mismatched password
        final saveButton = find.descendant(
          of: dialogFinder,
          matching: find.widgetWithText(FilledButton, I18n.tr('action.save')),
        );
        await tester.tap(saveButton);
        await _boundedPumpAndSettle(tester);
        final errorFinder = find.text(
          I18n.tr('auth.error.new_password_mismatch'),
        );
        expect(
          errorFinder,
          findsOneWidget,
          reason: 'Validation error text must display on mismatch',
        );
        await verifyRetainedDialogText(
          tester,
          errorFinder,
          expected: I18n.tr('auth.error.new_password_mismatch'),
        );
        expect(fixture.passwordCalls, 0);

        // Repair mismatch so confirm equals next
        await tester.enterText(confirmField, syntheticNext);
        await tester.pump();

        // 4. Live brand roundtrip
        await tester.runAsync(() async {
          final switched = await fixture.theme
              .setBrand(scenario.targetBrand)
              .timeout(
                const Duration(seconds: 5),
                onTimeout: () => throw TimeoutException(
                  'Theme switch to ${scenario.targetBrand} timed out after 5s',
                ),
              );
          expect(switched, isTrue);
          await AccountPreferenceWrites.drain().timeout(
            const Duration(seconds: 5),
          );
        });
        await _boundedPumpAndSettle(tester);
        expect(tester.takeException(), isNull);

        // State, ModalRoute, and controller identity retention across targetBrand
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
          reason: 'Dialog Route must be retained across brand switch',
        );
        expect(currentCtrl.text, syntheticCurrent);
        expect(newCtrl.text, syntheticNext);
        expect(confirmCtrl.text, syntheticNext);
        expect(currentCtrl.selection, draftSelection);
        expect(tester.widget<TextField>(currentField).obscureText, isTrue);

        assertDialogThemeAndSurface(scenario.targetBrand);
        await assertLabelsReadableAndCompleteWords();
        await _capture(
          tester,
          fixture.boundaryKey,
          '${scenario.name}-02-switched-${scenario.targetBrand}',
        );

        // Return brand to initialBrand
        await tester.runAsync(() async {
          final returned = await fixture.theme
              .setBrand(scenario.initialBrand)
              .timeout(
                const Duration(seconds: 5),
                onTimeout: () => throw TimeoutException(
                  'Theme return to ${scenario.initialBrand} timed out after 5s',
                ),
              );
          expect(returned, isTrue);
          await AccountPreferenceWrites.drain().timeout(
            const Duration(seconds: 5),
          );
        });
        await _boundedPumpAndSettle(tester);
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
          reason: 'Dialog Route must be retained across brand return',
        );
        expect(currentCtrl.text, syntheticCurrent);
        expect(newCtrl.text, syntheticNext);
        expect(confirmCtrl.text, syntheticNext);
        expect(currentCtrl.selection, draftSelection);

        assertDialogThemeAndSurface(scenario.initialBrand);
        await assertLabelsReadableAndCompleteWords();
        await _capture(
          tester,
          fixture.boundaryKey,
          '${scenario.name}-03-returned-${scenario.initialBrand}',
        );

        // 5. Live locale roundtrip
        final altLocale = scenario.initialLocale == AppLocale.zh
            ? AppLocale.en
            : AppLocale.zh;
        I18n.setLocale(altLocale);
        await _boundedPumpAndSettle(tester);
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
          reason: 'Dialog Route must be retained across locale switch',
        );
        expect(currentCtrl.text, syntheticCurrent);
        expect(newCtrl.text, syntheticNext);
        expect(confirmCtrl.text, syntheticNext);
        expect(currentCtrl.selection, draftSelection);

        // Check that localized labels updated in place
        expect(
          find.descendant(
            of: dialogFinder,
            matching: find.text(I18n.tr('profile.change_password')),
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
            matching: find.text(I18n.tr('action.save')),
          ),
          findsOneWidget,
        );
        await assertLabelsReadableAndCompleteWords();
        await _capture(
          tester,
          fixture.boundaryKey,
          '${scenario.name}-04-locale-${altLocale.name}',
        );

        // Return locale to initialLocale
        I18n.setLocale(scenario.initialLocale);
        await _boundedPumpAndSettle(tester);
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
          reason: 'Dialog Route must be retained across locale return',
        );
        expect(currentCtrl.text, syntheticCurrent);
        expect(newCtrl.text, syntheticNext);
        expect(confirmCtrl.text, syntheticNext);
        expect(currentCtrl.selection, draftSelection);
        await assertLabelsReadableAndCompleteWords();
        await _capture(
          tester,
          fixture.boundaryKey,
          '${scenario.name}-05-locale-returned-${scenario.initialLocale.name}',
        );

        // 6. Action scope: Cancel vs Save contract
        if (!scenario.shouldSave) {
          final cancelBtn = find.descendant(
            of: dialogFinder,
            matching: find.widgetWithText(TextButton, I18n.tr('action.cancel')),
          );
          await tester.tap(cancelBtn);
          await _boundedPumpAndSettle(tester);
          expect(find.byType(AppDialog), findsNothing);
          expect(fixture.passwordCalls, 0, reason: 'Cancel makes no mutation');
          expect(fixture.auth.state.isLoggedIn, isTrue);
          await _capture(
            tester,
            fixture.boundaryKey,
            '${scenario.name}-06-cancelled',
          );
        } else {
          final saveBtn = find.descendant(
            of: dialogFinder,
            matching: find.widgetWithText(FilledButton, I18n.tr('action.save')),
          );
          final initialGeneration =
              AccountLocalDataCleaner.accountDataGeneration;
          await tester.tap(saveBtn);
          await _drainAccountWrites(tester);
          await _boundedPumpAndSettle(tester);

          // Verified: Mocked success once via production AuthProvider
          expect(
            fixture.passwordCalls,
            1,
            reason: 'Password change requested exactly once via ApiClient',
          );
          expect(find.byType(AppDialog), findsNothing);
          // In production, password change clears local session and logs out user
          expect(fixture.auth.state.isLoggedIn, isFalse);
          expect(
            AccountLocalDataCleaner.accountDataGeneration,
            greaterThan(initialGeneration),
            reason:
                'Account generation must increment upon successful password logout cleanup',
          );
          expect(find.byType(SnackBar), findsOneWidget);

          // Verify _LocalProfileEditor header card contents are fully readable without truncation
          final localHeaderCard = find.ancestor(
            of: find.byKey(const ValueKey('profile_local_header_row')),
            matching: find.byType(AppSurfaceCard),
          );
          expect(localHeaderCard, findsOneWidget);

          final localNameFinder = find.descendant(
            of: localHeaderCard,
            matching: find.text('Synthetic user'),
          );
          expect(localNameFinder, findsOneWidget);
          final localNameParagraph = tester.renderObject<RenderParagraph>(
            localNameFinder,
          );
          expect(
            localNameParagraph.didExceedMaxLines,
            isFalse,
            reason: 'Local profile display name must not exceed maxLines',
          );
          expect(
            localNameParagraph.text.toPlainText(),
            equals('Synthetic user'),
          );
          expect(
            localNameParagraph.text.toPlainText(),
            isNot(contains('\u2026')),
            reason: 'Local profile display name must not elide',
          );

          final localEmailFinder = find.descendant(
            of: localHeaderCard,
            matching: find.text('synthetic@example.test'),
          );
          expect(localEmailFinder, findsOneWidget);
          final localEmailParagraph = tester.renderObject<RenderParagraph>(
            localEmailFinder,
          );
          expect(
            localEmailParagraph.didExceedMaxLines,
            isFalse,
            reason: 'Local profile email must not exceed maxLines',
          );
          expect(
            localEmailParagraph.text.toPlainText(),
            equals('synthetic@example.test'),
          );
          expect(
            localEmailParagraph.text.toPlainText(),
            isNot(contains('\u2026')),
            reason: 'Local profile email must not elide',
          );

          final localBioFinder = find.descendant(
            of: localHeaderCard,
            matching: find.text('Synthetic baseline bio'),
          );
          expect(localBioFinder, findsOneWidget);
          final localBioParagraph = tester.renderObject<RenderParagraph>(
            localBioFinder,
          );
          expect(
            localBioParagraph.didExceedMaxLines,
            isFalse,
            reason: 'Local profile bio must not exceed maxLines',
          );
          expect(
            localBioParagraph.text.toPlainText(),
            equals('Synthetic baseline bio'),
          );
          expect(
            localBioParagraph.text.toPlainText(),
            isNot(contains('\u2026')),
            reason: 'Local profile bio must not elide',
          );

          final chipFinder = find.descendant(
            of: localHeaderCard,
            matching: find.byType(AccountStatusChip),
          );
          expect(chipFinder, findsOneWidget);
          final chipWidget = tester.widget<AccountStatusChip>(chipFinder);
          expect(
            chipWidget.wrapLabel,
            isTrue,
            reason: 'AccountStatusChip must wrapLabel in local profile header',
          );
          final chipTextFinder = find.descendant(
            of: chipFinder,
            matching: find.text(AccountUiCopy.statusLocalMode),
          );
          expect(chipTextFinder, findsOneWidget);
          final chipParagraph = tester.renderObject<RenderParagraph>(
            chipTextFinder,
          );
          expect(
            chipParagraph.didExceedMaxLines,
            isFalse,
            reason: 'AccountStatusChip text must not exceed maxLines',
          );
          expect(
            chipParagraph.text.toPlainText(),
            equals(AccountUiCopy.statusLocalMode),
          );
          expect(
            chipParagraph.text.toPlainText(),
            isNot(contains('\u2026')),
            reason: 'AccountStatusChip text must not elide',
          );

          final loginBtnFinder = find.descendant(
            of: localHeaderCard,
            matching: find.byKey(const ValueKey('profile_local_login_button')),
          );
          expect(loginBtnFinder, findsOneWidget);
          final loginBtnRect = tester.getRect(loginBtnFinder);
          final cardRect = tester.getRect(localHeaderCard);
          expect(
            loginBtnRect.right,
            lessThanOrEqualTo(cardRect.right + 1.0),
            reason: 'Login button must fit inside header card boundaries',
          );

          if (scenario.scale > 1.25 && scenario.size.width < 340) {
            final avatarFinder = find.descendant(
              of: localHeaderCard,
              matching: find.byWidgetPredicate(
                (w) => w is Hero && w.tag == 'profile-avatar-preview',
              ),
            );
            expect(avatarFinder, findsOneWidget);
            final avatarRect = tester.getRect(avatarFinder);
            final nameRect = tester.getRect(localNameFinder);
            expect(
              nameRect.top,
              greaterThanOrEqualTo(avatarRect.bottom - 1.0),
              reason:
                  'Avatar must reflow above user name in narrow scaled viewport',
            );
          } else {
            final avatarFinder = find.descendant(
              of: localHeaderCard,
              matching: find.byWidgetPredicate(
                (w) => w is Hero && w.tag == 'profile-avatar-preview',
              ),
            );
            expect(avatarFinder, findsOneWidget);
            final avatarRect = tester.getRect(avatarFinder);
            final nameRect = tester.getRect(localNameFinder);
            expect(
              nameRect.left,
              greaterThanOrEqualTo(avatarRect.right - 1.0),
              reason:
                  'Avatar must remain to the left of user name in unscaled wide viewport',
            );
          }

          // Capture original -06-saved state before scrolling or snackbar dismissal
          await _capture(
            tester,
            fixture.boundaryKey,
            '${scenario.name}-06-saved',
          );

          // Dismiss the SnackBar and ensure local email label is scrolled into view
          ScaffoldMessenger.of(
            tester.element(localHeaderCard),
          ).hideCurrentSnackBar();
          await _boundedPumpAndSettle(tester);

          final localEmailLabelFinder = find.text(
            I18n.tr('profile.email.local_display'),
          );
          expect(localEmailLabelFinder, findsOneWidget);
          await tester.ensureVisible(localEmailLabelFinder);
          await _boundedPumpAndSettle(tester);

          await _capture(
            tester,
            fixture.boundaryKey,
            '${scenario.name}-07-email-field',
          );

          final localEmailLabelParagraph =
              tester.renderObject<RenderParagraph>(localEmailLabelFinder);
          expect(
            localEmailLabelParagraph.didExceedMaxLines,
            isFalse,
            reason: 'Local profile email field label must not exceed maxLines',
          );
          final labelText = localEmailLabelParagraph.text.toPlainText();
          expect(
            labelText,
            equals(I18n.tr('profile.email.local_display')),
          );

          final editorCard = find.ancestor(
            of: localEmailLabelFinder,
            matching: find.byType(AppSurfaceCard),
          );
          expect(editorCard, findsOneWidget);
          final editorCardRect = tester.getRect(editorCard);

          // Verify token glyph ink boxes fit within layout bounds
          final tokens = RegExp(r'\S+').allMatches(labelText);
          for (final match in tokens) {
            final tokenBoxes = localEmailLabelParagraph.getBoxesForSelection(
              TextSelection(baseOffset: match.start, extentOffset: match.end),
            );
            expect(
              tokenBoxes,
              isNotEmpty,
              reason: 'Glyph boxes for token "${match.group(0)}" must be laid out',
            );
            for (final box in tokenBoxes) {
              expect(
                box.left,
                greaterThanOrEqualTo(-0.5),
                reason: 'Glyph ink box left must not overflow paragraph layout bounds',
              );
              expect(
                box.right,
                lessThanOrEqualTo(localEmailLabelParagraph.size.width + 0.5),
                reason: 'Glyph ink box right must not overflow paragraph layout bounds',
              );
            }
          }

          // Verify full selection boxes fit within card and scrollable viewport bounds
          final fullBoxes = localEmailLabelParagraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: labelText.length),
          );
          expect(
            fullBoxes,
            isNotEmpty,
            reason: 'Full text selection boxes must not be empty',
          );
          if (scenario.scale > 1.25 && scenario.size.width < 340) {
            expect(
              fullBoxes.length,
              greaterThan(1),
              reason:
                  'Email label must wrap to multiple lines in narrow scaled viewport without shrinking',
            );
          }
          final scrollableFinder = find.byType(Scrollable).first;
          final viewportRect = tester.getRect(scrollableFinder);
          for (final box in fullBoxes) {
            final globalBox = Rect.fromPoints(
              localEmailLabelParagraph.localToGlobal(Offset(box.left, box.top)),
              localEmailLabelParagraph.localToGlobal(Offset(box.right, box.bottom)),
            );
            expect(
              globalBox.left,
              greaterThanOrEqualTo(editorCardRect.left - 1.0),
              reason: 'Glyph box left must fit within card',
            );
            expect(
              globalBox.right,
              lessThanOrEqualTo(editorCardRect.right + 1.0),
              reason: 'Glyph box right must fit within card',
            );
            expect(
              globalBox.top,
              greaterThanOrEqualTo(viewportRect.top - 1.0),
              reason: 'Glyph box top must be visible in viewport',
            );
            expect(
              globalBox.bottom,
              lessThanOrEqualTo(viewportRect.bottom + 1.0),
              reason: 'Glyph box bottom must be visible in viewport',
            );
          }

          // Verify email TextField is editable, preserves controller text and email keyboard type
          final emailFieldFinder = find.byKey(
            const ValueKey('profile_local_email_field'),
          );
          expect(emailFieldFinder, findsOneWidget);
          final emailField = tester.widget<TextField>(emailFieldFinder);
          expect(
            emailField.controller?.text,
            equals('synthetic@example.test'),
          );
          expect(
            emailField.keyboardType,
            equals(TextInputType.emailAddress),
          );
          expect(
            emailField.readOnly,
            isFalse,
            reason: 'Local profile email TextField must be editable',
          );

          // Verify emitted SemanticsNode label and textField flag
          final emailSemanticsData =
              tester.getSemantics(emailFieldFinder).getSemanticsData();
          expect(
            emailSemanticsData.label,
            equals(I18n.tr('profile.email.local_display')),
          );
          expect(
            emailSemanticsData.flagsCollection.isTextField,
            isTrue,
            reason: 'Emitted semantics must have isTextField flag',
          );

          // Within narrow English scenario, verify live brand and locale roundtrips in local editor
          if (scenario.scale > 1.25 && scenario.size.width < 340) {
            final profileElement = tester.element(find.byType(ProfileScreen));
            final profileRoute = ModalRoute.of(profileElement);
            final initialEmailCtrl = emailField.controller!;
            final emailSelection = const TextSelection.collapsed(offset: 9);
            initialEmailCtrl.selection = emailSelection;
            await tester.pump();

            // 1. Live brand roundtrip in local editor
            await tester.runAsync(() async {
              final switched = await fixture.theme
                  .setBrand(scenario.targetBrand)
                  .timeout(
                    const Duration(seconds: 5),
                    onTimeout: () => throw TimeoutException(
                      'Theme switch to ${scenario.targetBrand} timed out after 5s',
                    ),
                  );
              expect(switched, isTrue);
              await AccountPreferenceWrites.drain().timeout(
                const Duration(seconds: 5),
              );
            });
            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);

            expect(
              identical(tester.element(find.byType(ProfileScreen)), profileElement),
              isTrue,
              reason: 'ProfileScreen element must be retained across brand switch',
            );
            expect(
              identical(
                ModalRoute.of(tester.element(find.byType(ProfileScreen))),
                profileRoute,
              ),
              isTrue,
              reason: 'ModalRoute must be retained across brand switch',
            );
            expect(initialEmailCtrl.text, equals('synthetic@example.test'));
            expect(initialEmailCtrl.selection, equals(emailSelection));
            expect(fixture.passwordCalls, 1, reason: 'No extra password network mutations');

            // Verify label remains fully readable under targetBrand
            final brandSwitchedLabelFinder = find.text(
              I18n.tr('profile.email.local_display'),
            );
            expect(brandSwitchedLabelFinder, findsOneWidget);
            final brandSwitchedParagraph =
                tester.renderObject<RenderParagraph>(brandSwitchedLabelFinder);
            expect(
              brandSwitchedParagraph.didExceedMaxLines,
              isFalse,
              reason: 'Email label didExceedMaxLines must be false in targetBrand',
            );
            expect(
              brandSwitchedParagraph.text.toPlainText(),
              equals(I18n.tr('profile.email.local_display')),
            );

            // Return brand to initialBrand
            await tester.runAsync(() async {
              final returned = await fixture.theme
                  .setBrand(scenario.initialBrand)
                  .timeout(
                    const Duration(seconds: 5),
                    onTimeout: () => throw TimeoutException(
                      'Theme return to ${scenario.initialBrand} timed out after 5s',
                    ),
                  );
              expect(returned, isTrue);
              await AccountPreferenceWrites.drain().timeout(
                const Duration(seconds: 5),
              );
            });
            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);

            expect(
              identical(tester.element(find.byType(ProfileScreen)), profileElement),
              isTrue,
            );
            expect(
              identical(
                ModalRoute.of(tester.element(find.byType(ProfileScreen))),
                profileRoute,
              ),
              isTrue,
            );
            expect(initialEmailCtrl.text, equals('synthetic@example.test'));
            expect(initialEmailCtrl.selection, equals(emailSelection));
            expect(fixture.passwordCalls, 1);

            // 2. Live locale roundtrip in local editor
            I18n.setLocale(scenario.alternateLocale);
            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);

            expect(
              identical(tester.element(find.byType(ProfileScreen)), profileElement),
              isTrue,
              reason: 'ProfileScreen element must be retained across locale switch',
            );
            expect(
              identical(
                ModalRoute.of(tester.element(find.byType(ProfileScreen))),
                profileRoute,
              ),
              isTrue,
            );
            expect(initialEmailCtrl.text, equals('synthetic@example.test'));
            expect(initialEmailCtrl.selection, equals(emailSelection));
            expect(fixture.passwordCalls, 1);

            // Verify Chinese localized email label
            final altEmailLabel = I18n.tr('profile.email.local_display');
            final altEmailLabelFinder = find.text(altEmailLabel);
            expect(altEmailLabelFinder, findsOneWidget);
            final altParagraph =
                tester.renderObject<RenderParagraph>(altEmailLabelFinder);
            expect(
              altParagraph.didExceedMaxLines,
              isFalse,
              reason: 'Email label didExceedMaxLines must be false in alternateLocale',
            );
            expect(altParagraph.text.toPlainText(), equals(altEmailLabel));
            final altSemanticsData =
                tester.getSemantics(emailFieldFinder).getSemanticsData();
            expect(altSemanticsData.label, equals(altEmailLabel));
            expect(altSemanticsData.flagsCollection.isTextField, isTrue);

            // Return locale to initialLocale
            I18n.setLocale(scenario.initialLocale);
            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);

            expect(
              identical(tester.element(find.byType(ProfileScreen)), profileElement),
              isTrue,
            );
            expect(
              identical(
                ModalRoute.of(tester.element(find.byType(ProfileScreen))),
                profileRoute,
              ),
              isTrue,
            );
            expect(initialEmailCtrl.text, equals('synthetic@example.test'));
            expect(initialEmailCtrl.selection, equals(emailSelection));
            expect(fixture.passwordCalls, 1);

            final restoredEmailLabel = I18n.tr('profile.email.local_display');
            final restoredEmailLabelFinder = find.text(restoredEmailLabel);
            expect(restoredEmailLabelFinder, findsOneWidget);
            final restoredParagraph =
                tester.renderObject<RenderParagraph>(restoredEmailLabelFinder);
            expect(
              restoredParagraph.didExceedMaxLines,
              isFalse,
              reason: 'Email label didExceedMaxLines must be false after returning locale',
            );
            expect(restoredParagraph.text.toPlainText(), equals(restoredEmailLabel));

            final emailElement = tester.element(emailFieldFinder);
            final editableFinder = find.descendant(
              of: emailFieldFinder,
              matching: find.byType(EditableText),
            );
            final emailFocus = tester.widget<EditableText>(editableFinder).focusNode;
            final localGeneration = AccountLocalDataCleaner.accountDataGeneration;
            for (final stage in [
              (brand: 'defaultBrand', locale: AppLocale.en),
              (brand: 'defaultBrand', locale: AppLocale.zh),
              (brand: 'liquidGlass', locale: AppLocale.zh),
              (brand: 'liquidGlass', locale: AppLocale.en),
            ]) {
              if (fixture.theme.brand.id != stage.brand) {
                await tester.runAsync(() async {
                  expect(await fixture.theme.setBrand(stage.brand), isTrue);
                  await AccountPreferenceWrites.drain().timeout(const Duration(seconds: 5));
                });
              }
              I18n.setLocale(stage.locale);
              await _boundedPumpAndSettle(tester);
              final label = find.text(I18n.tr('profile.email.local_display'));
              await tester.ensureVisible(label);
              await _boundedPumpAndSettle(tester);
              expect(tester.element(emailFieldFinder), same(emailElement));
              expect(tester.widget<TextField>(emailFieldFinder).controller, same(initialEmailCtrl));
              expect(tester.widget<EditableText>(editableFinder).focusNode, same(emailFocus));
              expect(initialEmailCtrl.text, 'synthetic@example.test');
              expect(initialEmailCtrl.selection, emailSelection);
              expect(tester.element(find.byType(ProfileScreen)), same(profileElement));
              expect(ModalRoute.of(profileElement), same(profileRoute));
              expect(fixture.passwordCalls, 1);
              expect(AccountLocalDataCleaner.accountDataGeneration, localGeneration);
              final data = tester.getSemantics(emailFieldFinder).getSemanticsData();
              expect(data.label, I18n.tr('profile.email.local_display'));
              expect(data.flagsCollection.isTextField, isTrue);
              final paragraph = tester.renderObject<RenderParagraph>(label);
              expect(paragraph.didExceedMaxLines, isFalse);
              final copy = paragraph.text.toPlainText();
              expect(copy, I18n.tr('profile.email.local_display'));
              final card = tester.getRect(find.ancestor(of: label, matching: find.byType(AppSurfaceCard)));
              final scroll = Scrollable.of(tester.element(label));
              final viewport = tester.getRect(find.byWidget(scroll.widget));
              final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: copy.length));
              expect(boxes, isNotEmpty);
              for (final box in boxes) {
                final topLeft = paragraph.localToGlobal(Offset(box.left, box.top));
                final bottomRight = paragraph.localToGlobal(Offset(box.right, box.bottom));
                expect(topLeft.dx, greaterThanOrEqualTo(card.left - 1));
                expect(bottomRight.dx, lessThanOrEqualTo(card.right + 1));
                expect(topLeft.dy, greaterThanOrEqualTo(viewport.top - 1));
                expect(bottomRight.dy, lessThanOrEqualTo(viewport.bottom + 1));
              }
              for (final word in RegExp(r"[A-Za-z]+(?:['’-][A-Za-z]+)*").allMatches(copy)) {
                final wordBoxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: word.start, extentOffset: word.end));
                expect(wordBoxes, isNotEmpty);
                expect(wordBoxes.map((box) => box.top.round()).toSet(), hasLength(1));
              }
              await _capture(tester, fixture.boundaryKey,
                '${scenario.name}-08-local-email-${stage.brand}-${stage.locale.name}');
            }
          }
        }
      } finally {
        try {
          await fixture.dispose(tester);
        } finally {
          semantics.dispose();
        }
      }
    });
  }

  testWidgets(
    'held password request error is discarded while its dialog route is covered',
    (tester) async {
      final fixture = _PasswordFixture(
        scenario: const _PasswordLiveBrandScenario(
          name: 'held-error-covered',
          initialLocale: AppLocale.zh,
          alternateLocale: AppLocale.en,
          initialBrand: 'defaultBrand',
          targetBrand: 'liquidGlass',
          size: Size(320, 844),
          scale: 2.0,
          devicePixelRatio: 2.0,
          shouldSave: true,
        ),
        autoSucceedPassword: false,
      );
      try {
        await tester.runAsync(() async {
          await fixture.setUpAsync();
        });
        await fixture.pump(tester);
        await fixture.openChangePasswordDialog(tester);

        await tester.enterText(
          _field('profile.current_password'),
          'SyntheticCurrent1!',
        );
        await tester.enterText(_field('auth.new_password'), 'SyntheticNext2!');
        await tester.enterText(
          _field('profile.confirm_new_password'),
          'SyntheticNext2!',
        );
        await tester.pump();

        final saveFinder = find.descendant(
          of: find.byType(AppDialog),
          matching: find.widgetWithText(FilledButton, I18n.tr('action.save')),
        );
        await tester.tap(saveFinder);
        await tester.pump();
        expect(fixture.passwordCalls, 1);

        // Push covering route
        await _coverCurrentRoute(tester, host: find.byType(AppDialog));

        // Complete held request with server error while covered
        fixture.passwordRelease.complete(
          http.Response(
            jsonEncode({'detail': 'Invalid current password'}),
            400,
            headers: {'content-type': 'application/json'},
          ),
        );
        await _boundedPumpAndSettle(tester);
        await _returnFromCoveredRoute(tester);

        expect(
          find.descendant(
            of: find.byType(AppDialog),
            matching: find.byType(AppInfoBanner),
          ),
          findsNothing,
          reason: 'Error while covered must be discarded',
        );
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
  );

  testWidgets(
    'held password request + session replacement cannot mutate replacement user or close covering route',
    (tester) async {
      final fixture = _PasswordFixture(
        scenario: const _PasswordLiveBrandScenario(
          name: 'held-replacement-covered',
          initialLocale: AppLocale.zh,
          alternateLocale: AppLocale.en,
          initialBrand: 'defaultBrand',
          targetBrand: 'liquidGlass',
          size: Size(320, 844),
          scale: 2.0,
          devicePixelRatio: 2.0,
          shouldSave: true,
        ),
        autoSucceedPassword: false,
      );
      try {
        await tester.runAsync(() async {
          await fixture.setUpAsync();
        });
        await fixture.pump(tester);
        await fixture.openChangePasswordDialog(tester);

        await tester.enterText(
          _field('profile.current_password'),
          'SyntheticCurrent1!',
        );
        await tester.enterText(_field('auth.new_password'), 'SyntheticNext2!');
        await tester.enterText(
          _field('profile.confirm_new_password'),
          'SyntheticNext2!',
        );
        await tester.pump();

        final saveFinder = find.descendant(
          of: find.byType(AppDialog),
          matching: find.widgetWithText(FilledButton, I18n.tr('action.save')),
        );
        await tester.tap(saveFinder);
        await tester.pump();
        expect(fixture.passwordCalls, 1);

        // Cover the route with an unrelated foreground page
        await _coverCurrentRoute(tester, host: find.byType(AppDialog));

        // Replace session while request is held
        await _replaceSession(tester, fixture.auth);

        // Complete the held password request
        fixture.passwordRelease.complete(
          http.Response(
            jsonEncode({'status': 'ok'}),
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
        await _boundedPumpAndSettle(tester);

        // The covering route must still be active and not closed
        expect(find.text('Covered foreground route'), findsOneWidget);
        await _returnFromCoveredRoute(tester);

        // Replacement user must not have been mutated or logged out
        expect(fixture.auth.state.userId, 'profile-replacement-user');
        expect(fixture.auth.state.isLoggedIn, isTrue);
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
  );

  testWidgets(
    'retained password dialog submit cannot execute after session replacement',
    (tester) async {
      final fixture = _PasswordFixture(
        scenario: const _PasswordLiveBrandScenario(
          name: 'retained-replacement-submit',
          initialLocale: AppLocale.zh,
          alternateLocale: AppLocale.en,
          initialBrand: 'defaultBrand',
          targetBrand: 'liquidGlass',
          size: Size(320, 844),
          scale: 2.0,
          devicePixelRatio: 2.0,
          shouldSave: true,
        ),
        autoSucceedPassword: true,
      );
      try {
        await tester.runAsync(() async {
          await fixture.setUpAsync();
        });
        await fixture.pump(tester);
        await fixture.openChangePasswordDialog(tester);

        await tester.enterText(
          _field('profile.current_password'),
          'SyntheticCurrent1!',
        );
        await tester.enterText(_field('auth.new_password'), 'SyntheticNext2!');
        await tester.enterText(
          _field('profile.confirm_new_password'),
          'SyntheticNext2!',
        );
        await tester.pump();

        // Replace session before tapping save
        await _replaceSession(tester, fixture.auth);

        final saveFinder = find.descendant(
          of: find.byType(AppDialog),
          matching: find.widgetWithText(FilledButton, I18n.tr('action.save')),
        );
        await tester.tap(saveFinder);
        await _boundedPumpAndSettle(tester);

        expect(fixture.passwordCalls, 0);
        expect(fixture.auth.state.isLoggedIn, isTrue);
        expect(fixture.auth.state.userId, 'profile-replacement-user');
        expect(find.text(AccountUiCopy.accountChanged), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
  );
}
