// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
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
import 'package:duoyi/widgets/brand_background.dart' show BrandRouteSurface;
import 'package:duoyi/widgets/surface_components.dart' show appSurfaceStyleOf;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/weekly_review_screenshot_font.dart';

class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore(super.data) : super.withData();

  int profileWrites = 0;
  int authWrites = 0;

  static bool _isProfileKey(String key) =>
      key == 'user_profile' ||
      key == 'flutter.user_profile' ||
      key.endsWith('.user_profile');

  static bool _isAuthKey(String key) =>
      key == 'auth_state' ||
      key == 'flutter.auth_state' ||
      key.endsWith('.auth_state');

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (_isProfileKey(key)) {
      profileWrites++;
    } else if (_isAuthKey(key)) {
      authWrites++;
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    if (_isProfileKey(key)) {
      profileWrites++;
    } else if (_isAuthKey(key)) {
      authWrites++;
    }
    return super.remove(key);
  }
}

Object _profileEditorState(WidgetTester tester, Finder descendant) {
  Element? element = tester.element(descendant);
  while (element != null) {
    if (element is StatefulElement &&
        element.state.runtimeType.toString().endsWith('ProfileEditorState')) {
      return element.state;
    }
    Element? parent;
    element.visitAncestorElements((ancestor) {
      parent = ancestor;
      return false;
    });
    element = parent;
  }
  throw StateError('Profile editor State was not found above the TextField.');
}

Finder _field(String key) => find.byWidgetPredicate(
  (widget) =>
      widget is TextField && widget.decoration?.labelText == I18n.tr(key),
);

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
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
  final enabled =
      (explicitDir != null && explicitDir.isNotEmpty) ||
      Platform.environment['DUOYI_CAPTURE_SETTINGS_SCREENSHOT'] == '1';
  if (!enabled) return;

  final targetDir = (explicitDir != null && explicitDir.isNotEmpty)
      ? explicitDir
      : 'evidence/screenshots/settings-live-parallel-20261023';

  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final file = File('$targetDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

enum _ProfileContractOutcome { discard, save }

class _ProfileLiveBrandScenario {
  final String name;
  final AppLocale locale;
  final Size size;
  final double scale;
  final String initialBrand;
  final String targetBrand;
  final _ProfileContractOutcome outcome;

  const _ProfileLiveBrandScenario({
    required this.name,
    required this.locale,
    required this.size,
    required this.scale,
    required this.initialBrand,
    required this.targetBrand,
    required this.outcome,
  });
}

const _scenarios = <_ProfileLiveBrandScenario>[
  _ProfileLiveBrandScenario(
    name: 'zh-portrait-320x844-discard',
    locale: AppLocale.zh,
    size: Size(320, 844),
    scale: 2.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    outcome: _ProfileContractOutcome.discard,
  ),
  _ProfileLiveBrandScenario(
    name: 'en-portrait-320x844-save',
    locale: AppLocale.en,
    size: Size(320, 844),
    scale: 2.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    outcome: _ProfileContractOutcome.save,
  ),
  _ProfileLiveBrandScenario(
    name: 'zh-landscape-568x320-save',
    locale: AppLocale.zh,
    size: Size(568, 320),
    scale: 2.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    outcome: _ProfileContractOutcome.save,
  ),
  _ProfileLiveBrandScenario(
    name: 'en-landscape-568x320-discard',
    locale: AppLocale.en,
    size: Size(568, 320),
    scale: 2.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    outcome: _ProfileContractOutcome.discard,
  ),
];

void main() {
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets(
      'profile live brand priority defaultBrand <-> liquidGlass ${scenario.name}',
      (tester) async {
        final originalLocale = I18n.current;
        final originalShadows = debugDisableShadows;
        final originalTimeZoneReader =
            LocalTimezoneResolver.debugSystemTimeZoneReader;
        final previousStore = SharedPreferencesStorePlatform.instance;

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
        LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
            'Asia/Shanghai';

        final recordedRequests = <http.Request>[];
        final transport = MockClient((request) async {
          recordedRequests.add(request);
          if (request.url.path == '/api/me/profile') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'user_id': 'profile-synthetic-user',
                'username': 'synthetic-account',
                'email': 'synthetic@example.test',
                'email_verified': true,
                'display_name':
                    body['display_name'] ??
                    body['displayName'] ??
                    'synthetic-account',
                'bio': body['bio'] ?? '',
                'avatar': 'synthetic-avatar',
                'coin_balance': 100,
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('not found', 404);
        });

        final auth = AuthProvider(
          client: ApiClient(
            baseUrl: 'https://duoyi.test',
            token: 'synthetic-token',
            httpClient: transport,
          ),
          initialState: const AuthState(
            userId: 'profile-synthetic-user',
            username: 'synthetic-account',
            displayName: 'Synthetic baseline name',
            email: 'synthetic@example.test',
            emailVerified: true,
            avatar: 'synthetic-avatar',
            bio: 'Synthetic baseline bio',
            token: 'synthetic-token',
            coinBalance: 100,
          ),
        );

        final userProvider = UserProvider();
        final theme = ThemeProvider();
        late final PreferencesProvider preferences;

        try {
          I18n.setLocale(scenario.locale);
          debugDisableShadows = false;

          await tester.runAsync(() async {
            preferences = PreferencesProvider();
            await theme.loadFromStorage().timeout(const Duration(seconds: 5));
            await preferences.loadFromStorage().timeout(
              const Duration(seconds: 5),
            );
            await loadWeeklyReviewScreenshotFonts().timeout(
              const Duration(seconds: 5),
            );
          });

          await userProvider.applyAccountSnapshot(
            username: 'synthetic-account',
            displayName: 'Synthetic baseline name',
            email: 'synthetic@example.test',
            emailVerified: true,
            avatarUrl: 'synthetic-avatar',
            bio: 'Synthetic baseline bio',
          );

          await _drainAccountWrites(tester);

          expect(theme.brand.id, scenario.initialBrand);
          expect(theme.isBrandUnlocked(scenario.targetBrand), isTrue);

          final baselineProfileWrites = store.profileWrites;
          final baselineAuthWrites = store.authWrites;
          final baselineAccountGeneration =
              AccountLocalDataCleaner.accountDataGeneration;

          void assertZeroBusinessWrites(String stage) {
            expect(
              recordedRequests.length,
              0,
              reason: '$stage: expected zero API requests',
            );
            expect(
              store.profileWrites,
              baselineProfileWrites,
              reason:
                  '$stage: expected zero user_profile writes (actual=${store.profileWrites}, baseline=$baselineProfileWrites)',
            );
            expect(
              store.authWrites,
              baselineAuthWrites,
              reason:
                  '$stage: expected zero auth_state writes (actual=${store.authWrites}, baseline=$baselineAuthWrites)',
            );
            expect(
              AccountLocalDataCleaner.accountDataGeneration,
              baselineAccountGeneration,
              reason: '$stage: expected account generation to be preserved',
            );
            expect(
              userProvider.profile.displayName,
              'Synthetic baseline name',
              reason:
                  '$stage: expected userProvider displayName to remain baseline',
            );
            expect(
              auth.state.displayName,
              'Synthetic baseline name',
              reason:
                  '$stage: expected auth.state.displayName to remain baseline',
            );
          }

          tester.view.physicalSize = scenario.size;
          tester.view.devicePixelRatio = 1;

          final boundary = GlobalKey();

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
                ChangeNotifierProvider<UserProvider>.value(value: userProvider),
                ChangeNotifierProvider<PreferencesProvider>.value(
                  value: preferences,
                ),
              ],
              child: AnimatedBuilder(
                animation: Listenable.merge([theme, I18n.localeListenable]),
                builder: (context, _) => MaterialApp(
                  locale: Locale(scenario.locale == AppLocale.en ? 'en' : 'zh'),
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: theme.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scenario.scale)),
                    child: RepaintBoundary(key: boundary, child: child!),
                  ),
                  home: Builder(
                    builder: (context) => Scaffold(
                      body: Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const BrandRouteSurface(
                                remountOnLocaleChange: false,
                                child: ProfileScreen(),
                              ),
                            ),
                          ),
                          child: const Text('Open profile'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          // 1. Open the mounted ProfileScreen
          await tester.tap(find.text('Open profile'));
          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          final profileFinder = find.byType(ProfileScreen);
          expect(profileFinder, findsOneWidget);
          expect(find.byType(BrandRouteSurface), findsOneWidget);
          expect(find.text(I18n.tr('profile.title')), findsOneWidget);
          expect(find.text(I18n.tr('action.save')), findsOneWidget);

          final nameField = _field('profile.nickname');
          expect(nameField, findsOneWidget);

          final initialEditorState = _profileEditorState(tester, nameField);
          final initialModalRoute = ModalRoute.of(tester.element(nameField));
          expect(initialModalRoute, isNotNull);

          final initialController = tester
              .widget<TextField>(nameField)
              .controller!;
          expect(initialController.text, 'Synthetic baseline name');

          assertZeroBusinessWrites('1. after route open');
          await _capture(tester, boundary, '${scenario.name}-01-initial');

          // 2. Enter uncommitted draft into display-name
          final draftText = 'Draft name ${scenario.name}';
          const draftSelection = TextSelection(baseOffset: 2, extentOffset: 8);

          await tester.ensureVisible(nameField);
          await _boundedPumpAndSettle(tester);
          await tester.tap(nameField);
          await tester.enterText(nameField, draftText);
          initialController.selection = draftSelection;
          await tester.pump();

          expect(initialController.text, draftText);
          expect(initialController.selection, draftSelection);
          FocusManager.instance.primaryFocus?.unfocus();

          assertZeroBusinessWrites('2. after draft edit');
          await _capture(tester, boundary, '${scenario.name}-02-draft');

          // 3. Live brand switch to targetBrand (liquidGlass)
          await tester.runAsync(() async {
            final switched = await theme.setBrand(scenario.targetBrand);
            expect(switched, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          expect(theme.brand.id, scenario.targetBrand);
          final prefsAfterSwitch = await SharedPreferences.getInstance();
          expect(
            prefsAfterSwitch.getString('active_brand'),
            scenario.targetBrand,
          );

          final switchedElement = tester.element(profileFinder);
          final switchedTheme = Theme.of(switchedElement);
          final expectedBrand = AppBrands.byId(scenario.targetBrand);
          expect(
            switchedTheme.colorScheme.primary,
            equals(expectedBrand.theme.colorScheme.primary),
          );
          expect(
            appSurfaceStyleOf(switchedElement),
            equals(AppSurfaceStyle.liquidGlass),
          );

          // Assert State, ModalRoute, and controller identity retention
          expect(
            identical(
              _profileEditorState(tester, nameField),
              initialEditorState,
            ),
            isTrue,
            reason:
                'State identity must be preserved across liquidGlass switch',
          );
          expect(
            identical(
              ModalRoute.of(tester.element(nameField)),
              initialModalRoute,
            ),
            isTrue,
            reason:
                'ModalRoute identity must be preserved across liquidGlass switch',
          );
          expect(
            identical(
              tester.widget<TextField>(nameField).controller,
              initialController,
            ),
            isTrue,
            reason:
                'TextEditingController identity must be preserved across liquidGlass switch',
          );
          expect(initialController.text, draftText);
          expect(initialController.selection, draftSelection);

          assertZeroBusinessWrites(
            '3. after brand switch to ${scenario.targetBrand}',
          );
          await _capture(tester, boundary, '${scenario.name}-03-liquidGlass');

          // 4. Live locale switch and verification
          final altLocale = scenario.locale == AppLocale.zh
              ? AppLocale.en
              : AppLocale.zh;
          I18n.setLocale(altLocale);
          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          // Verify localized labels updated in place
          expect(find.text(I18n.tr('profile.title')), findsOneWidget);
          expect(find.text(I18n.tr('action.save')), findsOneWidget);
          final altNameField = _field('profile.nickname');
          expect(altNameField, findsOneWidget);

          expect(
            identical(
              _profileEditorState(tester, altNameField),
              initialEditorState,
            ),
            isTrue,
            reason:
                'State identity must be preserved across live locale change',
          );
          expect(
            identical(
              ModalRoute.of(tester.element(altNameField)),
              initialModalRoute,
            ),
            isTrue,
            reason:
                'ModalRoute identity must be preserved across live locale change',
          );
          expect(
            identical(
              tester.widget<TextField>(altNameField).controller,
              initialController,
            ),
            isTrue,
            reason:
                'TextEditingController identity must be preserved across live locale change',
          );
          expect(initialController.text, draftText);
          expect(initialController.selection, draftSelection);

          assertZeroBusinessWrites('4. after switch to alternative locale');

          // Switch locale back to scenario original locale
          I18n.setLocale(scenario.locale);
          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);
          expect(find.text(I18n.tr('profile.title')), findsOneWidget);
          expect(find.text(I18n.tr('action.save')), findsOneWidget);
          assertZeroBusinessWrites('5. after switch back to initial locale');

          // 5. Live brand roundtrip back to initialBrand (defaultBrand)
          await tester.runAsync(() async {
            final reverted = await theme.setBrand(scenario.initialBrand);
            expect(reverted, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          expect(theme.brand.id, scenario.initialBrand);
          final prefsAfterRevert = await SharedPreferences.getInstance();
          expect(
            prefsAfterRevert.getString('active_brand'),
            scenario.initialBrand,
          );

          final revertedElement = tester.element(profileFinder);
          final revertedTheme = Theme.of(revertedElement);
          final expectedRevertedBrand = AppBrands.byId(scenario.initialBrand);
          expect(
            revertedTheme.colorScheme.primary,
            equals(expectedRevertedBrand.theme.colorScheme.primary),
          );
          expect(
            appSurfaceStyleOf(revertedElement),
            isNot(equals(AppSurfaceStyle.liquidGlass)),
          );

          expect(
            identical(
              _profileEditorState(tester, nameField),
              initialEditorState,
            ),
            isTrue,
            reason:
                'State identity must be preserved across defaultBrand revert',
          );
          expect(
            identical(
              ModalRoute.of(tester.element(nameField)),
              initialModalRoute,
            ),
            isTrue,
            reason:
                'ModalRoute identity must be preserved across defaultBrand revert',
          );
          expect(
            identical(
              tester.widget<TextField>(nameField).controller,
              initialController,
            ),
            isTrue,
            reason:
                'TextEditingController identity must be preserved across defaultBrand revert',
          );
          expect(initialController.text, draftText);
          expect(initialController.selection, draftSelection);

          assertZeroBusinessWrites(
            '6. after brand roundtrip back to ${scenario.initialBrand}',
          );
          await _capture(
            tester,
            boundary,
            '${scenario.name}-04-reverted-defaultBrand',
          );

          // 6. Explicit outcome: Discard vs Save
          if (scenario.outcome == _ProfileContractOutcome.discard) {
            final back = find.byType(BackButton);
            expect(back, findsOneWidget);
            await tester.tap(back);
            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);

            expect(find.byType(ProfileScreen), findsNothing);
            expect(find.text('Open profile'), findsOneWidget);

            // Discard contract: zero writes to server API or local stores
            assertZeroBusinessWrites('7. after confirming discard');

            final storedProfile = (await SharedPreferences.getInstance())
                .getString('user_profile');
            expect(storedProfile, isNotNull);
            final storedJson =
                jsonDecode(storedProfile!) as Map<String, dynamic>;
            expect(storedJson['displayName'], 'Synthetic baseline name');

            await _capture(tester, boundary, '${scenario.name}-05-discarded');
          } else {
            // Save contract: verify zero storage writes until explicit Save
            assertZeroBusinessWrites('7. pre-save check');

            final saveButton = find.widgetWithText(
              FilledButton,
              I18n.tr('action.save'),
            );
            expect(saveButton, findsOneWidget);
            await tester.tap(saveButton);
            await _drainAccountWrites(tester);
            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);

            // Verified: API request committed exactly ONCE via production path
            expect(
              recordedRequests.length,
              1,
              reason: 'Explicit save must commit exactly once via API',
            );
            final req = recordedRequests.single;
            expect(req.url.path, '/api/me/profile');
            expect(req.method, isIn(['PATCH', 'POST', 'PUT']));
            final payload = jsonDecode(req.body) as Map<String, dynamic>;
            expect(payload['display_name'], draftText);

            // Verified: feedback announcement displayed
            expect(find.text(I18n.tr('profile.updated')), findsWidgets);

            // Verified: in-memory state updated
            expect(auth.state.displayName, draftText);
            expect(userProvider.profile.displayName, draftText);

            // Verified: local store writes occurred exactly for this save
            expect(
              store.profileWrites,
              greaterThan(baselineProfileWrites),
              reason: 'Explicit save must persist user_profile to local store',
            );
            expect(
              store.authWrites,
              greaterThan(baselineAuthWrites),
              reason: 'Explicit save must persist auth_state to local store',
            );

            // Verified: stored user_profile JSON payload matches draft
            final storedProfile = (await SharedPreferences.getInstance())
                .getString('user_profile');
            expect(storedProfile, isNotNull);
            final storedJson =
                jsonDecode(storedProfile!) as Map<String, dynamic>;
            expect(storedJson['displayName'], draftText);

            // Verified: account data generation preserved
            expect(
              AccountLocalDataCleaner.accountDataGeneration,
              baselineAccountGeneration,
              reason:
                  'Explicit save must preserve synthetic account generation',
            );

            // Dismiss screen via BackButton
            final back = find.byType(BackButton);
            expect(back, findsOneWidget);
            await tester.tap(back);
            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);

            expect(find.byType(ProfileScreen), findsNothing);
            expect(find.text('Open profile'), findsOneWidget);

            await _capture(tester, boundary, '${scenario.name}-05-saved');
          }

          expect(tester.takeException(), isNull);
        } finally {
          try {
            await _drainAccountWrites(tester);
            await tester.pumpWidget(const SizedBox.shrink());
            await _boundedPumpAndSettle(tester);
          } finally {
            SharedPreferences.resetStatic();
            SharedPreferencesStorePlatform.instance = previousStore;
            LocalTimezoneResolver.debugSystemTimeZoneReader =
                originalTimeZoneReader;
            auth.dispose();
            userProvider.dispose();
            theme.dispose();
            preferences.dispose();
            transport.close();
            tester.view.reset();
            debugDisableShadows = originalShadows;
            I18n.setLocale(originalLocale);
          }
        }
      },
    );
  }
}
