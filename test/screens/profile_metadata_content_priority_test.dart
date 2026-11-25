// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
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

import '../support/secondary_route_render_probe.dart'
    show RouteProbeNonlinearScaler;
import '../support/weekly_review_screenshot_font.dart';

class _ProfileMetadataScenario {
  final String name;
  final Size size;
  final double devicePixelRatio;
  final TextScaler textScaler;
  final String initialBrand;
  final String alternateBrand;
  final AppLocale initialLocale;
  final AppLocale alternateLocale;

  const _ProfileMetadataScenario({
    required this.name,
    required this.size,
    required this.devicePixelRatio,
    required this.textScaler,
    required this.initialBrand,
    required this.alternateBrand,
    required this.initialLocale,
    required this.alternateLocale,
  });
}

const _scenarios = <_ProfileMetadataScenario>[
  // 1. true 320 logical width at textScale 2 - defaultBrand zh
  _ProfileMetadataScenario(
    name: 'portrait-320x844-dpr2-scale2-defaultBrand-zh',
    size: Size(320, 844),
    devicePixelRatio: 2.0,
    textScaler: TextScaler.linear(2.0),
    initialBrand: 'defaultBrand',
    alternateBrand: 'liquidGlass',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
  ),
  // 2. true 320 logical width at textScale 2 - liquidGlass en
  _ProfileMetadataScenario(
    name: 'portrait-320x844-dpr2-scale2-liquidGlass-en',
    size: Size(320, 844),
    devicePixelRatio: 2.0,
    textScaler: TextScaler.linear(2.0),
    initialBrand: 'liquidGlass',
    alternateBrand: 'defaultBrand',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
  ),
  // 3. 844x390 landscape at 100% - liquidGlass zh
  _ProfileMetadataScenario(
    name: 'landscape-844x390-dpr1-scale1-liquidGlass-zh',
    size: Size(844, 390),
    devicePixelRatio: 1.0,
    textScaler: TextScaler.linear(1.0),
    initialBrand: 'liquidGlass',
    alternateBrand: 'defaultBrand',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
  ),
  // 4. 844x390 landscape at 100% - defaultBrand en
  _ProfileMetadataScenario(
    name: 'landscape-844x390-dpr1-scale1-defaultBrand-en',
    size: Size(844, 390),
    devicePixelRatio: 1.0,
    textScaler: TextScaler.linear(1.0),
    initialBrand: 'defaultBrand',
    alternateBrand: 'liquidGlass',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
  ),
  // 5. ordinary 390 at 100% - defaultBrand en
  _ProfileMetadataScenario(
    name: 'portrait-390x844-dpr1-scale1-defaultBrand-en',
    size: Size(390, 844),
    devicePixelRatio: 1.0,
    textScaler: TextScaler.linear(1.0),
    initialBrand: 'defaultBrand',
    alternateBrand: 'liquidGlass',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
  ),
  // 6. wide 1024 at 100% - liquidGlass zh
  _ProfileMetadataScenario(
    name: 'wide-1024x768-dpr1-scale1-liquidGlass-zh',
    size: Size(1024, 768),
    devicePixelRatio: 1.0,
    textScaler: TextScaler.linear(1.0),
    initialBrand: 'liquidGlass',
    alternateBrand: 'defaultBrand',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
  ),
  // 7. representative nonlinear text scaling on true 320 logical width
  _ProfileMetadataScenario(
    name: 'portrait-320x844-dpr2-nonlinear-liquidGlass-en',
    size: Size(320, 844),
    devicePixelRatio: 2.0,
    textScaler: RouteProbeNonlinearScaler(),
    initialBrand: 'liquidGlass',
    alternateBrand: 'defaultBrand',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
  ),
];

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
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'] ??
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
      final file = File('$explicitDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void _assertGlyphsRenderedWithinBounds(
  RenderParagraph paragraph, {
  String? expectedText,
  Finder? cardFinder,
  WidgetTester? tester,
}) {
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: 'Paragraph didExceedMaxLines must be false',
  );
  final plainText = paragraph.text.toPlainText();
  if (expectedText != null) {
    expect(plainText, equals(expectedText));
  }
  expect(plainText, isNotEmpty);

  // 1. Verify actual glyph ink of every non-whitespace token fits within layout bounds
  final tokens = RegExp(r'\S+').allMatches(plainText);
  for (final match in tokens) {
    final tokenBoxes = paragraph.getBoxesForSelection(
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
        lessThanOrEqualTo(paragraph.size.width + 0.5),
        reason:
            'Glyph ink box right must not overflow paragraph layout bounds',
      );
    }
  }

  // 2. Verify full selection advance/trailing whitespace does not clip outside card/viewport
  final fullBoxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: plainText.length),
  );
  expect(
    fullBoxes,
    isNotEmpty,
    reason: 'Full text selection boxes must not be empty',
  );
  if (tester != null && cardFinder != null) {
    final cardRect = tester.getRect(cardFinder);
    for (final box in fullBoxes) {
      final globalBox = Rect.fromPoints(
        paragraph.localToGlobal(Offset(box.left, box.top)),
        paragraph.localToGlobal(Offset(box.right, box.bottom)),
      );
      expect(
        globalBox.right,
        lessThanOrEqualTo(cardRect.right + 0.5),
        reason: 'Selection box right must not clip outside card bounds',
      );
      expect(
        globalBox.left,
        greaterThanOrEqualTo(cardRect.left - 0.5),
        reason: 'Selection box left must not clip outside card bounds',
      );
    }
  }
}

class _ProfileMetadataFixture {
  final _ProfileMetadataScenario scenario;
  final bool emailVerified;
  final bool isLoggedIn;
  AuthProvider? _auth;
  UserProvider? _userProvider;
  ThemeProvider? _theme;
  PreferencesProvider? _preferences;
  http.Client? _httpClient;
  SemanticsHandle? semanticsHandle;
  final GlobalKey boundaryKey = GlobalKey();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  int authCalls = 0;
  bool _disposed = false;

  bool? _originalShadows;
  AppLocale? _originalLocale;
  Future<String?> Function()? _originalTimeZoneReader;
  SharedPreferencesStorePlatform? _previousStore;

  AuthProvider get auth => _auth!;
  UserProvider get userProvider => _userProvider!;
  ThemeProvider get theme => _theme!;
  PreferencesProvider get preferences => _preferences!;
  http.Client get httpClient => _httpClient!;

  static const String longLiteralDisplayName =
      'Literal Long Display Name Synthetic';
  static const String longLiteralUsername =
      'synthetic-account-id-long-identity';
  static const String longLiteralEmail =
      'synthetic-user-priority-account@example.test';
  static const int literalCoins = 128;

  _ProfileMetadataFixture({
    required this.scenario,
    this.emailVerified = true,
    this.isLoggedIn = true,
  });

  Future<void> setUpAsync() async {
    _originalLocale = I18n.current;
    _originalShadows = debugDisableShadows;
    _originalTimeZoneReader = LocalTimezoneResolver.debugSystemTimeZoneReader;
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
    _previousStore = SharedPreferencesStorePlatform.instance;

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

    _httpClient = MockClient((request) async {
      authCalls++;
      return http.Response(
        jsonEncode({'status': 'ok'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    _auth = AuthProvider(
      initialState: isLoggedIn
          ? const AuthState(
              userId: 'synthetic-priority-user-id',
              username: longLiteralUsername,
              displayName: longLiteralDisplayName,
              email: longLiteralEmail,
              emailVerified: true,
              coinBalance: literalCoins,
              token: 'synthetic-metadata-priority-token',
            ).copyWith(emailVerified: emailVerified)
          : const AuthState(),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: isLoggedIn ? 'synthetic-metadata-priority-token' : null,
        httpClient: _httpClient,
      ),
    );

    _auth!.onAccountLoggedOut = () async {
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    };

    _userProvider = UserProvider();
    _theme = ThemeProvider();
    _preferences = PreferencesProvider();

    await _theme!.loadFromStorage().timeout(const Duration(seconds: 5));
    await _preferences!.loadFromStorage().timeout(const Duration(seconds: 5));
    await loadWeeklyReviewScreenshotFonts().timeout(const Duration(seconds: 5));

    if (isLoggedIn) {
      await _userProvider!.applyAccountSnapshot(
        username: longLiteralUsername,
        displayName: longLiteralDisplayName,
        email: longLiteralEmail,
        emailVerified: emailVerified,
        avatarUrl: 'synthetic-avatar-image',
        bio: 'Synthetic priority verification biography literal content.',
      );
    } else {
      await _userProvider!.updateProfile(
        username: longLiteralUsername,
        displayName: longLiteralDisplayName,
        email: '',
        emailVerified: false,
        avatarUrl: 'synthetic-avatar-image',
        bio: 'Synthetic priority verification biography literal content.',
      );
    }
  }

  Future<void> pump(WidgetTester tester) async {
    semanticsHandle = tester.ensureSemantics();
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
              ).copyWith(textScaler: scenario.textScaler),
              child: RepaintBoundary(key: boundaryKey, child: child!),
            ),
            home: const BrandBackground(child: ProfileScreen()),
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
      semanticsHandle?.dispose();
      semanticsHandle = null;
      tester.view.reset();
      if (_originalShadows != null) {
        debugDisableShadows = _originalShadows!;
      }
      if (_originalLocale != null) {
        I18n.setLocale(_originalLocale!);
      }
      LocalTimezoneResolver.debugSystemTimeZoneReader =
          _originalTimeZoneReader;
      SharedPreferences.resetStatic();
      if (_previousStore != null) {
        SharedPreferencesStorePlatform.instance = _previousStore!;
      }
      _httpClient?.close();
      _auth?.dispose();
      _userProvider?.dispose();
      _theme?.dispose();
      _preferences?.dispose();
    }
  }
}

void main() {
  setUp(() {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });

  for (final scenario in _scenarios) {
    testWidgets('profile metadata priority layout: ${scenario.name}', (
      tester,
    ) async {
      final fixture = _ProfileMetadataFixture(scenario: scenario);

      try {
        await tester.runAsync(() async {
          await fixture.setUpAsync();
        });

        await fixture.pump(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(BrandBackground), findsWidgets);
        expect(find.byType(ProfileScreen), findsOneWidget);

        // 1. Assert physical and media size
        expect(
          tester.view.physicalSize.width,
          equals(scenario.size.width * scenario.devicePixelRatio),
          reason: 'Physical width must equal logical width * DPR',
        );
        expect(
          tester.view.physicalSize.height,
          equals(scenario.size.height * scenario.devicePixelRatio),
          reason: 'Physical height must equal logical height * DPR',
        );
        expect(
          tester.view.devicePixelRatio,
          equals(scenario.devicePixelRatio),
          reason: 'DPR must equal scenario DPR',
        );

        final media = MediaQuery.of(tester.element(find.byType(ProfileScreen)));
        expect(
          media.size.width,
          equals(scenario.size.width),
          reason: 'MediaQuery width must equal scenario width',
        );
        expect(
          media.size.height,
          equals(scenario.size.height),
          reason: 'MediaQuery height must equal scenario height',
        );
        expect(
          media.devicePixelRatio,
          equals(scenario.devicePixelRatio),
          reason: 'MediaQuery DPR must equal scenario DPR',
        );

        final headerCard = find.byType(AppSurfaceCard).first;
        await tester.ensureVisible(headerCard);

        // 2. Verify HEADER identity info: Display Name
        final nameFinder = find.descendant(
          of: headerCard,
          matching: find.text(_ProfileMetadataFixture.longLiteralDisplayName),
        );
        expect(nameFinder, findsOneWidget);
        await tester.ensureVisible(nameFinder);
        final nameParagraph = tester.renderObject<RenderParagraph>(nameFinder);
        _assertGlyphsRenderedWithinBounds(
          nameParagraph,
          expectedText: _ProfileMetadataFixture.longLiteralDisplayName,
          cardFinder: headerCard,
          tester: tester,
        );

        // 3. Verify HEADER identity info: Email & verification state
        final emailTooltipFinder = find.byTooltip(
          _ProfileMetadataFixture.longLiteralEmail,
        );
        expect(emailTooltipFinder, findsOneWidget);
        final emailTextFinder = find.descendant(
          of: emailTooltipFinder,
          matching: find.byType(Text),
        );
        expect(emailTextFinder, findsOneWidget);
        await tester.ensureVisible(emailTextFinder);
        final emailParagraph =
            tester.renderObject<RenderParagraph>(emailTextFinder);
        _assertGlyphsRenderedWithinBounds(
          emailParagraph,
          cardFinder: headerCard,
          tester: tester,
        );
        final plainEmailText = emailParagraph.text.toPlainText();
        expect(
          plainEmailText,
          contains(_ProfileMetadataFixture.longLiteralEmail),
          reason: 'Full literal email address must remain visible',
        );
        expect(
          plainEmailText,
          contains(I18n.tr('profile.email.verified')),
          reason: 'Email verification status must remain visible',
        );
        expect(
          plainEmailText,
          isNot(contains('\u2026')),
          reason: 'Email and verification must not be ellipsized',
        );

        // 4. Verify Account status chip
        final statusChip = find.byType(AccountStatusChip);
        expect(statusChip, findsOneWidget);
        await tester.ensureVisible(statusChip);

        // 5. Verify Coins metric chip (scoped real Text label + real semantics node)
        final coinsLabel = I18n.tr('profile.coins');
        final coinsText = '$coinsLabel ${_ProfileMetadataFixture.literalCoins}';
        final coinsFinder = find.descendant(
          of: headerCard,
          matching: find.text(coinsText),
        );
        expect(coinsFinder, findsOneWidget);
        await tester.ensureVisible(coinsFinder);
        await _boundedPumpAndSettle(tester);
        final coinsParagraph = tester.renderObject<RenderParagraph>(coinsFinder);
        _assertGlyphsRenderedWithinBounds(
          coinsParagraph,
          expectedText: coinsText,
          cardFinder: headerCard,
          tester: tester,
        );
        final coinsSemantics = tester.getSemantics(coinsFinder).getSemanticsData();
        expect(
          coinsSemantics.label,
          contains(coinsText),
          reason: 'Coins metric accessibility label must contain "$coinsText"',
        );

        // 6. Verify Account ID metric chip (scoped real Text label + real semantics node)
        final accountIdLabel = I18n.tr('profile.account_id');
        final accountIdText =
            '$accountIdLabel ${_ProfileMetadataFixture.longLiteralUsername}';
        final accountIdFinder = find.descendant(
          of: headerCard,
          matching: find.text(accountIdText),
        );
        expect(accountIdFinder, findsOneWidget);
        await tester.ensureVisible(accountIdFinder);
        await _boundedPumpAndSettle(tester);
        final accountIdParagraph =
            tester.renderObject<RenderParagraph>(accountIdFinder);
        _assertGlyphsRenderedWithinBounds(
          accountIdParagraph,
          expectedText: accountIdText,
          cardFinder: headerCard,
          tester: tester,
        );
        final plainAccountId = accountIdParagraph.text.toPlainText();
        expect(plainAccountId, contains(accountIdLabel));
        expect(
          plainAccountId,
          contains(_ProfileMetadataFixture.longLiteralUsername),
          reason: 'Full literal account ID must remain visible in metric chip',
        );
        expect(
          plainAccountId,
          isNot(contains('\u2026')),
          reason: 'Account ID must not be ellipsized',
        );
        final accountIdSemantics =
            tester.getSemantics(accountIdFinder).getSemanticsData();
        expect(
          accountIdSemantics.label,
          contains(accountIdText),
          reason:
              'Account ID metric accessibility label must contain "$accountIdText"',
        );

        // 7. Verify Avatar preview & edit buttons (with real viewport reachability)
        final avatarPreviewFinder = find.byKey(
          const ValueKey('profile_avatar_preview_button'),
        );
        final avatarEditFinder = find.byKey(
          const ValueKey('profile_avatar_edit_button'),
        );
        expect(avatarPreviewFinder, findsOneWidget);
        expect(avatarEditFinder, findsOneWidget);

        final scrollableFinder = find.byType(Scrollable).first;
        await tester.ensureVisible(avatarPreviewFinder);
        await _boundedPumpAndSettle(tester);
        await tester.ensureVisible(avatarEditFinder);
        await _boundedPumpAndSettle(tester);
        final viewport = tester.getRect(scrollableFinder);
        final editRect = tester.getRect(avatarEditFinder);
        expect(
          editRect.width,
          greaterThanOrEqualTo(43.5),
          reason:
              'Avatar edit button touch target width must meet >= 44 standard',
        );
        expect(
          editRect.height,
          greaterThanOrEqualTo(43.5),
          reason:
              'Avatar edit button touch target height must meet >= 44 standard',
        );
        expect(
          editRect.top,
          greaterThanOrEqualTo(viewport.top - 1.0),
          reason:
              'Avatar edit button must be reachable within viewport bounds',
        );
        expect(
          editRect.bottom,
          lessThanOrEqualTo(viewport.bottom + 1.0),
          reason:
              'Avatar edit button must be reachable within viewport bounds',
        );
        expect(
          find.byKey(const ValueKey('profile_avatar_edit_button')).hitTestable(),
          findsOneWidget,
          reason: 'Avatar edit button must be hit-testable in viewport',
        );

        // 8. Verify Reflow vs Normal Row layout
        final isNarrowWithLargeScale =
            scenario.size.width < 340 && scenario.textScaler.scale(1) > 1.25;
        if (isNarrowWithLargeScale) {
          final avatarRect = tester.getRect(avatarPreviewFinder);
          final nameRect = tester.getRect(nameFinder);
          expect(
            nameRect.top,
            greaterThanOrEqualTo(avatarRect.bottom - 1.0),
            reason:
                'Narrow viewport with high scale must naturally reflow avatar above info column',
          );
        } else {
          final avatarRect = tester.getRect(avatarPreviewFinder);
          final nameRect = tester.getRect(nameFinder);
          expect(
            nameRect.left,
            greaterThanOrEqualTo(avatarRect.right - 1.0),
            reason:
                'Normal 390 / wide 1024 layout must keep avatar and info column horizontally aligned in Row',
          );
        }

        // 9. Verify effective chip contrast (assert real Text foreground vs real background)
        final coinsTextWidget = tester.widget<Text>(coinsFinder);
        final renderedFg = coinsTextWidget.style?.color;
        expect(
          renderedFg,
          isNotNull,
          reason: 'Rendered metric chip Text widget must have a styled color',
        );
        final theme = Theme.of(tester.element(find.byType(ProfileScreen)));
        final cs = theme.colorScheme;
        final chipBg = cs.primaryContainer.withValues(alpha: 0.52);
        final surfaceStyle = appSurfaceStyleOf(
          tester.element(find.byType(ProfileScreen)),
        );
        final cardFill = surfaceStyle?.cardFillColor ?? cs.surface;
        final cardBg = Color.alphaBlend(
          cardFill,
          Color.alphaBlend(theme.scaffoldBackgroundColor, cs.surface),
        );
        final compBg = Color.alphaBlend(chipBg, cardBg);
        final ratio = appContrastRatio(compBg, renderedFg!);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason:
              'Actual rendered metric chip Text foreground must meet >= 4.5:1 contrast against composited background',
        );

        // 10. Screenshot header before scrolling away
        await tester.ensureVisible(headerCard);
        await _boundedPumpAndSettle(tester);
        await _capture(
          tester,
          fixture.boundaryKey,
          'profile-metadata-${scenario.name}',
        );

        // 11. Scroll to username guidance helperText and verify
        final usernameFieldFinder = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.labelText == I18n.tr('auth.username'),
        );
        expect(usernameFieldFinder, findsOneWidget);
        await tester.scrollUntilVisible(
          usernameFieldFinder,
          200,
          scrollable: scrollableFinder,
        );
        await tester.ensureVisible(usernameFieldFinder);
        await _boundedPumpAndSettle(tester);

        final usernameField = tester.widget<TextField>(usernameFieldFinder);
        final guidanceText = I18n.tr('profile.username.locked');
        expect(
          usernameField.decoration?.helperText,
          equals(guidanceText),
          reason:
              'InputDecoration.helperText must declare locked username guidance',
        );

        final guidanceFinder = find.text(guidanceText);
        expect(guidanceFinder, findsOneWidget);
        final guidanceParagraph =
            tester.renderObject<RenderParagraph>(guidanceFinder);
        _assertGlyphsRenderedWithinBounds(
          guidanceParagraph,
          expectedText: guidanceText,
        );

        // 12. Verify Change Password Dialog entrance and behavior
        final passwordEntrance = find.widgetWithText(
          TextButton,
          I18n.tr('profile.change_password'),
        );
        await tester.scrollUntilVisible(
          passwordEntrance,
          200,
          scrollable: scrollableFinder,
        );
        await tester.ensureVisible(passwordEntrance);
        await _boundedPumpAndSettle(tester);
        await tester.tap(passwordEntrance);
        await _boundedPumpAndSettle(tester);
        final dialogFinder = find.byType(AppDialog);
        expect(dialogFinder, findsOneWidget);
        for (final key in [
          'profile.current_password',
          'auth.new_password',
          'profile.confirm_new_password',
        ]) {
          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.byWidgetPredicate(
                (w) =>
                    w is TextField && w.decoration?.labelText == I18n.tr(key),
              ),
            ),
            findsOneWidget,
            reason: '$key TextField must be present in change password dialog',
          );
        }
        await tester.tap(
          find.widgetWithText(TextButton, I18n.tr('action.cancel')),
        );
        await _boundedPumpAndSettle(tester);
        expect(find.byType(AppDialog), findsNothing);
        expect(
          fixture.authCalls,
          0,
          reason: 'Password dialog open and cancel must not make any auth calls',
        );

        // 13. Verify route/controller/draft retention across Theme and Locale Round Trips
        expect(fixture.theme.brand.id, scenario.initialBrand);
        expect(I18n.current, scenario.initialLocale);

        // Scroll to nickname field and enter unsaved draft text
        final nicknameFieldFinder = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.labelText == I18n.tr('profile.nickname'),
        );
        await tester.scrollUntilVisible(
          nicknameFieldFinder,
          -200,
          scrollable: scrollableFinder,
        );
        await tester.ensureVisible(nicknameFieldFinder);
        await _boundedPumpAndSettle(tester);

        final initialNicknameController =
            tester.widget<TextField>(nicknameFieldFinder).controller;
        expect(initialNicknameController, isNotNull);
        const draftNickname = 'Synthetic Draft Nickname Retention';
        await tester.enterText(nicknameFieldFinder, draftNickname);
        await _boundedPumpAndSettle(tester);
        expect(initialNicknameController!.text, equals(draftNickname));

        // Switch brand
        await tester.runAsync(() async {
          final switched =
              await fixture.theme.setBrand(scenario.alternateBrand);
          expect(switched, isTrue);
          await AccountPreferenceWrites.drain().timeout(
            const Duration(seconds: 5),
          );
        });
        await _boundedPumpAndSettle(tester);
        expect(fixture.theme.brand.id, scenario.alternateBrand);

        // Switch locale
        I18n.setLocale(scenario.alternateLocale);
        await _boundedPumpAndSettle(tester);
        expect(I18n.current, scenario.alternateLocale);

        // Switch back brand
        await tester.runAsync(() async {
          final returned =
              await fixture.theme.setBrand(scenario.initialBrand);
          expect(returned, isTrue);
          await AccountPreferenceWrites.drain().timeout(
            const Duration(seconds: 5),
          );
        });
        await _boundedPumpAndSettle(tester);
        expect(fixture.theme.brand.id, scenario.initialBrand);

        // Switch back locale
        I18n.setLocale(scenario.initialLocale);
        await _boundedPumpAndSettle(tester);
        expect(I18n.current, scenario.initialLocale);

        // Verify controller instance and unsaved draft text are retained across switches
        final retainedNicknameField = tester.widget<TextField>(
          find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                identical(w.controller, initialNicknameController),
          ),
        );
        expect(
          retainedNicknameField.controller,
          same(initialNicknameController),
          reason:
              'TextEditingController instance must be retained across brand and locale switches',
        );
        expect(
          retainedNicknameField.controller!.text,
          equals(draftNickname),
          reason:
              'Draft input text must be retained across brand and locale switches',
        );

        // Scroll back to top to verify avatar reachability and header identity content intact
        final scrollPosition =
            tester.state<ScrollableState>(scrollableFinder).position;
        if (scrollPosition.pixels > 0) {
          scrollPosition.jumpTo(0);
          await _boundedPumpAndSettle(tester);
        }
        await tester.ensureVisible(headerCard);
        await _boundedPumpAndSettle(tester);
        await tester.ensureVisible(avatarPreviewFinder);
        await _boundedPumpAndSettle(tester);
        await tester.ensureVisible(avatarEditFinder);
        await _boundedPumpAndSettle(tester);

        expect(
          avatarEditFinder.hitTestable(),
          findsOneWidget,
          reason:
              'Avatar edit button must remain reachable and hit-testable after theme round trips',
        );

        // Header live preview renders retained draftNickname
        final headerDraftFinder = find.descendant(
          of: headerCard,
          matching: find.text(draftNickname),
        );
        expect(
          headerDraftFinder,
          findsOneWidget,
          reason:
              'Header live preview must render retained draft nickname after round trips',
        );
        await tester.ensureVisible(headerDraftFinder);
        await _boundedPumpAndSettle(tester);
        final draftParagraph =
            tester.renderObject<RenderParagraph>(headerDraftFinder);
        _assertGlyphsRenderedWithinBounds(
          draftParagraph,
          expectedText: draftNickname,
          cardFinder: headerCard,
          tester: tester,
        );
        final draftSemantics =
            tester.getSemantics(headerDraftFinder).getSemanticsData();
        expect(
          draftSemantics.label,
          contains(draftNickname),
          reason:
              'Header live preview semantics label must contain "$draftNickname"',
        );

        // Header email and tooltip remain intact
        expect(
          find.byTooltip(_ProfileMetadataFixture.longLiteralEmail),
          findsOneWidget,
        );

        // Underlying auth and userProvider states remain unchanged (no save performed)
        expect(
          fixture.auth.state.displayName,
          equals(_ProfileMetadataFixture.longLiteralDisplayName),
          reason:
              'Underlying auth state displayName must remain unchanged without saving',
        );
        expect(
          fixture.auth.state.username,
          equals(_ProfileMetadataFixture.longLiteralUsername),
          reason:
              'Underlying auth state username must remain unchanged without saving',
        );
        expect(
          fixture.auth.state.email,
          equals(_ProfileMetadataFixture.longLiteralEmail),
          reason:
              'Underlying auth state email must remain unchanged without saving',
        );
        expect(
          fixture.userProvider.profile.displayName,
          equals(_ProfileMetadataFixture.longLiteralDisplayName),
          reason:
              'Underlying userProvider profile displayName must remain unchanged without saving',
        );

        // 14. Verify NO unintended network/auth calls occurred
        expect(
          fixture.authCalls,
          0,
          reason:
              'Viewing profile metadata, dialog cancellation, and theme/locale switches must produce 0 network calls',
        );
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  testWidgets('profile header displays unverified email status completely', (
    tester,
  ) async {
    final scenario = _scenarios.first;
    final fixture = _ProfileMetadataFixture(
      scenario: scenario,
      emailVerified: false,
    );

    try {
      await tester.runAsync(() async {
        await fixture.setUpAsync();
      });

      await fixture.pump(tester);
      expect(tester.takeException(), isNull);

      final headerCard = find.byType(AppSurfaceCard).first;
      await tester.ensureVisible(headerCard);
      await _boundedPumpAndSettle(tester);

      final emailTooltipFinder = find.byTooltip(
        _ProfileMetadataFixture.longLiteralEmail,
      );
      expect(emailTooltipFinder, findsOneWidget);
      final emailTextFinder = find.descendant(
        of: emailTooltipFinder,
        matching: find.byType(Text),
      );
      expect(emailTextFinder, findsOneWidget);
      await tester.ensureVisible(emailTextFinder);
      await _boundedPumpAndSettle(tester);

      final emailParagraph =
          tester.renderObject<RenderParagraph>(emailTextFinder);
      _assertGlyphsRenderedWithinBounds(
        emailParagraph,
        cardFinder: headerCard,
        tester: tester,
      );
      final plainEmailText = emailParagraph.text.toPlainText();
      expect(
        plainEmailText,
        contains(_ProfileMetadataFixture.longLiteralEmail),
      );
      expect(plainEmailText, contains(I18n.tr('profile.email.unverified')));
      expect(plainEmailText, isNot(contains('\u2026')));
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets(
    'local profile editor displays guidance and retains locked username',
    (tester) async {
      final scenario = _scenarios[1]; // liquidGlass en
      final fixture = _ProfileMetadataFixture(
        scenario: scenario,
        isLoggedIn: false,
      );

      try {
        await tester.runAsync(() async {
          await fixture.setUpAsync();
        });

        await fixture.pump(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(ProfileScreen), findsOneWidget);

        final usernameFieldFinder = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.labelText == I18n.tr('profile.local_nickname'),
        );
        expect(usernameFieldFinder, findsOneWidget);
        await tester.ensureVisible(usernameFieldFinder);
        await _boundedPumpAndSettle(tester);
        final usernameField = tester.widget<TextField>(usernameFieldFinder);
        final guidanceText = I18n.tr('profile.username.locked');
        expect(
          usernameField.decoration?.helperText,
          equals(guidanceText),
          reason:
              'InputDecoration.helperText must declare locked username guidance in local profile editor',
        );

        final guidanceFinder = find.text(guidanceText);
        expect(guidanceFinder, findsOneWidget);
        final guidanceParagraph =
            tester.renderObject<RenderParagraph>(guidanceFinder);
        _assertGlyphsRenderedWithinBounds(
          guidanceParagraph,
          expectedText: guidanceText,
        );

        expect(
          usernameField.controller?.text,
          equals(_ProfileMetadataFixture.longLiteralUsername),
          reason: 'Local profile editor must retain locked username',
        );
        expect(
          usernameField.readOnly,
          isTrue,
          reason: 'Username field must remain locked and read-only',
        );
      } finally {
        await fixture.dispose(tester);
      }
    },
  );
}
