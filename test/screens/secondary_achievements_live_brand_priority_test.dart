// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/achievements.dart';
import 'package:duoyi/core/achievement_ui_copy.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/achievements_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandRouteSurface;
import 'package:duoyi/widgets/surface_components.dart' show appSurfaceStyleOf;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
}

Object _dialogState(WidgetTester tester, Finder descendant) {
  Element? element = tester.element(descendant);
  while (element != null) {
    if (element is StatefulElement &&
        element.state.runtimeType.toString().contains(
          'AchievementShareDialogState',
        )) {
      return element.state;
    }
    Element? parent;
    element.visitAncestorElements((ancestor) {
      parent = ancestor;
      return false;
    });
    element = parent;
  }
  throw StateError('Achievement share dialog State was not found.');
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

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final explicitDir =
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
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
      final file = File('$explicitDir/achievements-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

const _seedContext = AchievementContext(
  totalTodos: 10,
  completedTodos: 10,
  longestHabitStreak: 5,
  habitCount: 3,
  focusMinutes: 120,
  focusSessions: 4,
  diaryStreak: 2,
  diaryCount: 3,
  goalsTotal: 2,
  goalsAchieved: 1,
  anniversaries: 1,
  courses: 1,
  notes: 2,
  todayCompletedTodos: 3,
);

class _AchievementsLiveBrandScenario {
  final String name;
  final AppLocale locale;
  final Size size;
  final double scale;
  final String initialBrand;
  final String targetBrand;

  const _AchievementsLiveBrandScenario({
    required this.name,
    required this.locale,
    required this.size,
    required this.scale,
    required this.initialBrand,
    required this.targetBrand,
  });
}

const _scenarios = <_AchievementsLiveBrandScenario>[
  _AchievementsLiveBrandScenario(
    name: 'zh-portrait-320x844-defaultBrand',
    locale: AppLocale.zh,
    size: Size(320, 844),
    scale: 2.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
  ),
  _AchievementsLiveBrandScenario(
    name: 'zh-landscape-844x390-liquidGlass',
    locale: AppLocale.zh,
    size: Size(844, 390),
    scale: 1.6,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
  ),
  _AchievementsLiveBrandScenario(
    name: 'en-portrait-320x844-defaultBrand',
    locale: AppLocale.en,
    size: Size(320, 844),
    scale: 2.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
  ),
  _AchievementsLiveBrandScenario(
    name: 'en-landscape-844x390-liquidGlass',
    locale: AppLocale.en,
    size: Size(844, 390),
    scale: 1.6,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
  ),
];

void main() {
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets(
      'achievements live brand priority defaultBrand <-> liquidGlass ${scenario.name}',
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
          throw StateError(
            'Unexpected network call: ${request.method} ${request.url}',
          );
        });

        final clipboardWrites = <String>[];
        var directoryRequests = 0;
        final shares = <Map<Object?, Object?>>[];
        const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
        const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            clipboardWrites.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
        messenger.setMockMethodCallHandler(pathChannel, (call) async {
          directoryRequests++;
          return '/tmp';
        });
        messenger.setMockMethodCallHandler(shareChannel, (call) async {
          shares.add(Map<Object?, Object?>.from(call.arguments as Map));
          return 'synthetic-target';
        });

        AuthProvider? auth;
        UserProvider? userProvider;
        AppLockProvider? lockProvider;
        AchievementProvider? achievementProvider;
        ThemeProvider? theme;
        PreferencesProvider? preferences;

        try {
          I18n.setLocale(scenario.locale);
          debugDisableShadows = false;

          await tester.runAsync(() async {
            preferences = PreferencesProvider();
            theme = ThemeProvider();
            lockProvider = AppLockProvider();
            achievementProvider = AchievementProvider();
            auth = AuthProvider(
              client: ApiClient(
                baseUrl: 'https://duoyi.test',
                token: 'synthetic-token',
                httpClient: transport,
              ),
              initialState: const AuthState(
                userId: 'achievements-synthetic-user',
                username: 'synthetic-achiever',
                displayName: 'Synthetic Achiever',
                email: 'achiever@example.test',
                emailVerified: true,
                token: 'synthetic-token',
              ),
            );
            userProvider = UserProvider();

            await theme!.loadFromStorage().timeout(const Duration(seconds: 5));
            await preferences!.loadFromStorage().timeout(
              const Duration(seconds: 5),
            );
            await lockProvider!.loadFromStorage().timeout(
              const Duration(seconds: 5),
            );
            await achievementProvider!.loadFromStorage().timeout(
              const Duration(seconds: 5),
            );
            await achievementProvider!
                .updateContext(_seedContext)
                .timeout(const Duration(seconds: 5));
            await loadWeeklyReviewScreenshotFonts().timeout(
              const Duration(seconds: 5),
            );
          });

          await _drainAccountWrites(tester);

          expect(theme!.brand.id, scenario.initialBrand);
          expect(theme!.isBrandUnlocked(scenario.targetBrand), isTrue);
          expect(achievementProvider!.unlockedCount, greaterThan(0));

          tester.view.physicalSize = scenario.size;
          tester.view.devicePixelRatio = 1;

          final boundary = GlobalKey();

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme!),
                ChangeNotifierProvider<AuthProvider>.value(value: auth!),
                ChangeNotifierProvider<UserProvider>.value(
                  value: userProvider!,
                ),
                ChangeNotifierProvider<PreferencesProvider>.value(
                  value: preferences!,
                ),
                ChangeNotifierProvider<AchievementProvider>.value(
                  value: achievementProvider!,
                ),
                ChangeNotifierProvider<AppLockProvider>.value(
                  value: lockProvider!,
                ),
              ],
              child: Consumer<ThemeProvider>(
                builder: (context, currentTheme, _) =>
                    ValueListenableBuilder<AppLocale>(
                      valueListenable: I18n.localeListenable,
                      builder: (context, currentLocale, _) => MaterialApp(
                        locale: Locale(
                          currentLocale == AppLocale.en ? 'en' : 'zh',
                        ),
                        supportedLocales: const [Locale('en'), Locale('zh')],
                        localizationsDelegates:
                            GlobalMaterialLocalizations.delegates,
                        theme: currentTheme.brand.theme,
                        builder: (context, child) => MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            textScaler: TextScaler.linear(scenario.scale),
                          ),
                          child: RepaintBoundary(key: boundary, child: child!),
                        ),
                        home: const BrandRouteSurface(
                          remountOnLocaleChange: false,
                          child: AchievementsScreen(),
                        ),
                      ),
                    ),
              ),
            ),
          );

          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          final screenFinder = find.byType(AchievementsScreen);
          expect(screenFinder, findsOneWidget);
          final initialScreenElement = tester.element(screenFinder);
          expect(
            MediaQuery.textScalerOf(initialScreenElement),
            equals(TextScaler.linear(scenario.scale)),
          );

          // 1. Establish meaningful nonzero scroll offset on AchievementsScreen
          final pageScrollableFinder = find.descendant(
            of: find.byType(AchievementsScreen),
            matching: find.byType(Scrollable),
          );
          final scrollState = tester.state<ScrollableState>(
            pageScrollableFinder,
          );
          final scrollPosition = scrollState.position;
          expect(scrollPosition.maxScrollExtent, greaterThan(40.0));
          final targetScrollOffset = (scrollPosition.maxScrollExtent * 0.3)
              .clamp(40.0, 300.0);
          scrollPosition.jumpTo(targetScrollOffset);
          await tester.pump();
          final initialNonzeroOffset = scrollPosition.pixels;
          expect(initialNonzeroOffset, greaterThan(0.0));

          // 2. Open the real AchievementsScreen share dialog via visible share button
          final shareButton = find.byTooltip(
            AchievementUiCopy.text('成就分享图', 'Share achievements'),
          );
          expect(shareButton, findsOneWidget);
          await tester.ensureVisible(shareButton);
          await _boundedPumpAndSettle(tester);
          await tester.tap(shareButton);
          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          final dialogFinder = find.byType(AlertDialog);
          expect(dialogFinder, findsOneWidget);
          final initialDialogElement = tester.element(dialogFinder);
          final initialDialogRoute = ModalRoute.of(initialDialogElement);
          expect(initialDialogRoute, isNotNull);
          final initialDialogState = _dialogState(tester, dialogFinder);
          expect(initialDialogState, isNotNull);

          expect(
            MediaQuery.textScalerOf(initialDialogElement),
            equals(TextScaler.linear(scenario.scale)),
          );

          void assertDialogThemeAndSurface(String expectedBrandId) {
            final currentDialogElement = tester.element(dialogFinder);
            final dialogTheme = Theme.of(currentDialogElement);
            final expectedBrand = AppBrands.byId(expectedBrandId);
            expect(
              dialogTheme.colorScheme.primary,
              equals(expectedBrand.theme.colorScheme.primary),
              reason: 'Dialog Theme.of primary must match $expectedBrandId',
            );
            final style = appSurfaceStyleOf(currentDialogElement);
            if (expectedBrandId == 'liquidGlass') {
              expect(style, equals(AppSurfaceStyle.liquidGlass));
            } else {
              expect(style, equals(AppSurfaceStyle.ios));
              expect(style, isNot(equals(AppSurfaceStyle.liquidGlass)));
            }

            final copyButtonFinder = find.widgetWithText(
              TextButton,
              AchievementUiCopy.text('复制文案', 'Copy text'),
            );
            expect(copyButtonFinder, findsOneWidget);
            final copyElement = tester.element(copyButtonFinder);
            expect(
              Theme.of(copyElement).colorScheme.primary,
              equals(expectedBrand.theme.colorScheme.primary),
              reason:
                  'Target control Theme.of primary must match $expectedBrandId',
            );
          }

          assertDialogThemeAndSurface(scenario.initialBrand);
          expect(clipboardWrites, isEmpty);
          expect(directoryRequests, 0);
          expect(shares, isEmpty);
          expect(recordedRequests, isEmpty);
          await _capture(
            tester,
            boundary,
            '${scenario.name}-01-dialog-initial',
          );

          // 3. Live brand switch to targetBrand while SAME overlay remains mounted
          await tester.runAsync(() async {
            final switched = await theme!.setBrand(scenario.targetBrand);
            expect(switched, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          expect(
            identical(tester.element(dialogFinder), initialDialogElement),
            isTrue,
          );
          expect(
            identical(
              ModalRoute.of(tester.element(dialogFinder)),
              initialDialogRoute,
            ),
            isTrue,
          );
          expect(
            identical(_dialogState(tester, dialogFinder), initialDialogState),
            isTrue,
          );
          assertDialogThemeAndSurface(scenario.targetBrand);

          expect(
            tester.state<ScrollableState>(pageScrollableFinder).position.pixels,
            closeTo(initialNonzeroOffset, 0.01),
            reason:
                'Nonzero scroll offset must be preserved across brand switch',
          );
          expect(clipboardWrites, isEmpty);
          expect(directoryRequests, 0);
          expect(shares, isEmpty);
          await _capture(
            tester,
            boundary,
            '${scenario.name}-02-dialog-${scenario.targetBrand}',
          );

          // 4. Live brand roundtrip back to initialBrand while SAME overlay remains mounted
          await tester.runAsync(() async {
            final reverted = await theme!.setBrand(scenario.initialBrand);
            expect(reverted, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          expect(
            identical(tester.element(dialogFinder), initialDialogElement),
            isTrue,
          );
          expect(
            identical(
              ModalRoute.of(tester.element(dialogFinder)),
              initialDialogRoute,
            ),
            isTrue,
          );
          expect(
            identical(_dialogState(tester, dialogFinder), initialDialogState),
            isTrue,
          );
          assertDialogThemeAndSurface(scenario.initialBrand);

          expect(
            tester.state<ScrollableState>(pageScrollableFinder).position.pixels,
            closeTo(initialNonzeroOffset, 0.01),
            reason:
                'Nonzero scroll offset must be preserved across brand revert',
          );
          expect(clipboardWrites, isEmpty);
          expect(directoryRequests, 0);
          expect(shares, isEmpty);
          await _capture(
            tester,
            boundary,
            '${scenario.name}-03-dialog-reverted-${scenario.initialBrand}',
          );

          // 5. Live locale switch to alternate locale while SAME overlay remains mounted
          final altLocale = scenario.locale == AppLocale.zh
              ? AppLocale.en
              : AppLocale.zh;
          I18n.setLocale(altLocale);
          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          expect(
            identical(tester.element(dialogFinder), initialDialogElement),
            isTrue,
          );
          expect(
            identical(
              ModalRoute.of(tester.element(dialogFinder)),
              initialDialogRoute,
            ),
            isTrue,
          );
          expect(
            identical(_dialogState(tester, dialogFinder), initialDialogState),
            isTrue,
          );

          expect(
            find.text(AchievementUiCopy.text('成就分享图', 'Share achievements')),
            findsOneWidget,
          );
          expect(
            find.text(AchievementUiCopy.text('关闭', 'Close')),
            findsOneWidget,
          );
          expect(
            find.text(AchievementUiCopy.text('复制文案', 'Copy text')),
            findsOneWidget,
          );
          expect(
            find.text(AchievementUiCopy.text('分享 PNG', 'Share PNG')),
            findsOneWidget,
          );
          expect(
            find.text(AchievementUiCopy.text('由多仪生成', 'Created with Duoyi')),
            findsOneWidget,
          );
          expect(clipboardWrites, isEmpty);
          expect(directoryRequests, 0);
          expect(shares, isEmpty);
          await _capture(
            tester,
            boundary,
            '${scenario.name}-04-dialog-altLocale',
          );

          // 6. Live locale switch back to scenario starting locale
          I18n.setLocale(scenario.locale);
          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          expect(
            identical(tester.element(dialogFinder), initialDialogElement),
            isTrue,
          );
          expect(
            identical(
              ModalRoute.of(tester.element(dialogFinder)),
              initialDialogRoute,
            ),
            isTrue,
          );
          expect(
            identical(_dialogState(tester, dialogFinder), initialDialogState),
            isTrue,
          );

          expect(
            find.text(AchievementUiCopy.text('成就分享图', 'Share achievements')),
            findsOneWidget,
          );
          expect(
            find.text(AchievementUiCopy.text('关闭', 'Close')),
            findsOneWidget,
          );
          expect(
            find.text(AchievementUiCopy.text('复制文案', 'Copy text')),
            findsOneWidget,
          );
          expect(
            find.text(AchievementUiCopy.text('分享 PNG', 'Share PNG')),
            findsOneWidget,
          );
          expect(clipboardWrites, isEmpty);
          expect(directoryRequests, 0);
          expect(shares, isEmpty);

          // 7. Exercise a real visible Copy action with mocked clipboard
          final copyButtonFinder = find.widgetWithText(
            TextButton,
            AchievementUiCopy.text('复制文案', 'Copy text'),
          );
          expect(copyButtonFinder, findsOneWidget);
          await tester.ensureVisible(copyButtonFinder);
          await _boundedPumpAndSettle(tester);
          await tester.tap(copyButtonFinder);
          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          expect(
            clipboardWrites.length,
            1,
            reason: 'Explicit copy must output to clipboard exactly once',
          );
          final copiedText = clipboardWrites.single;
          if (scenario.locale == AppLocale.zh) {
            expect(copiedText, contains('# 多仪成就海报'));
            expect(copiedText, contains('已解锁'));
            expect(copiedText, contains('成长等级'));
            expect(copiedText, isNot(contains('# Duoyi achievements')));
          } else {
            expect(copiedText, contains('# Duoyi achievements'));
            expect(copiedText, contains('Unlocked'));
            expect(copiedText, contains('Growth level'));
            expect(copiedText, isNot(contains('# 多仪成就海报')));
          }

          expect(
            find.text(
              AchievementUiCopy.text('成就文案已复制', 'Achievement text copied'),
            ),
            findsOneWidget,
          );
          expect(shares, isEmpty);
          expect(directoryRequests, 0);
          await _capture(tester, boundary, '${scenario.name}-05-dialog-copied');

          // 8. Cancel/close and return to AchievementsScreen
          final beforeCloseOffset = scrollState.position.pixels;
          final closeButtonFinder = find.widgetWithText(
            TextButton,
            AchievementUiCopy.text('关闭', 'Close'),
          );
          expect(closeButtonFinder, findsOneWidget);
          await tester.ensureVisible(closeButtonFinder);
          await _boundedPumpAndSettle(tester);
          await tester.tap(closeButtonFinder);
          await _boundedPumpAndSettle(tester);
          expect(tester.takeException(), isNull);

          expect(find.byType(AlertDialog), findsNothing);
          expect(find.byType(AchievementsScreen), findsOneWidget);
          expect(tester.element(screenFinder), same(initialScreenElement));

          // Reacquire real page Scrollable under AchievementsScreen:
          final returnedScrollableFinder = find.descendant(
            of: find.byType(AchievementsScreen),
            matching: find.byType(Scrollable),
          );
          expect(returnedScrollableFinder, findsOneWidget);
          final returnedScrollState = tester.state<ScrollableState>(
            returnedScrollableFinder,
          );
          final returnedScrollPosition = returnedScrollState.position;

          // ScrollableState survives; Flutter may replace ScrollPosition when
          // inherited dependencies change (ScrollableState.didChangeDependencies).
          expect(
            identical(returnedScrollState, scrollState),
            isTrue,
            reason:
                'ScrollableState must be preserved on return from share dialog',
          );
          expect(
            returnedScrollPosition.pixels,
            closeTo(beforeCloseOffset, 0.01),
          );
          expect(returnedScrollPosition.pixels, greaterThan(0.0));
          expect(
            returnedScrollPosition.pixels,
            closeTo(
              math.min(
                initialNonzeroOffset,
                returnedScrollPosition.maxScrollExtent,
              ),
              0.01,
            ),
            reason:
                'Nonzero scroll offset must be preserved on return from share dialog',
          );
          expect(
            returnedScrollPosition.pixels,
            closeTo(initialNonzeroOffset, 0.01),
            reason:
                'Exact saved bounded scroll offset must be preserved immediately after closing',
          );

          // 9. Visit header/progress and first/last catalog labels through real visible scrolling:
          final headerFinder = find.text(
            AchievementUiCopy.text('你的成就', 'Your achievements'),
          );
          await tester.scrollUntilVisible(
            headerFinder,
            -100,
            scrollable: returnedScrollableFinder,
            maxScrolls: 30,
          );
          await _boundedPumpAndSettle(tester);
          expect(headerFinder.hitTestable(), findsOneWidget);
          expect(
            find
                .text(
                  '${achievementProvider!.unlockedCount} / ${Achievements.all.length}',
                )
                .hitTestable(),
            findsWidgets,
          );

          final firstBadgeTitle = AchievementUiCopy.badgeTitle(
            Achievements.all.first,
          );
          final firstBadgeFinder = find.text(firstBadgeTitle);
          await tester.scrollUntilVisible(
            firstBadgeFinder,
            100,
            scrollable: returnedScrollableFinder,
            maxScrolls: 30,
          );
          await _boundedPumpAndSettle(tester);
          expect(firstBadgeFinder.hitTestable(), findsOneWidget);

          final lastBadgeTitle = AchievementUiCopy.badgeTitle(
            Achievements.all.last,
          );
          final lastBadgeFinder = find.text(lastBadgeTitle);
          await tester.scrollUntilVisible(
            lastBadgeFinder,
            150,
            scrollable: returnedScrollableFinder,
            maxScrolls: 50,
          );
          await _boundedPumpAndSettle(tester);
          expect(lastBadgeFinder.hitTestable(), findsOneWidget);

          // 10. Restore original scroll offset afterwards:
          returnedScrollPosition.jumpTo(initialNonzeroOffset);
          await tester.pump();
          expect(
            returnedScrollPosition.pixels,
            closeTo(initialNonzeroOffset, 0.01),
          );
          await _capture(tester, boundary, '${scenario.name}-06-returned');

          expect(recordedRequests, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          try {
            await _drainAccountWrites(tester);
            await tester.pumpWidget(const SizedBox.shrink());
            await _boundedPumpAndSettle(tester);
          } finally {
            messenger.setMockMethodCallHandler(SystemChannels.platform, null);
            messenger.setMockMethodCallHandler(pathChannel, null);
            messenger.setMockMethodCallHandler(shareChannel, null);
            SharedPreferences.resetStatic();
            SharedPreferencesStorePlatform.instance = previousStore;
            LocalTimezoneResolver.debugSystemTimeZoneReader =
                originalTimeZoneReader;
            auth?.dispose();
            userProvider?.dispose();
            lockProvider?.dispose();
            achievementProvider?.dispose();
            theme?.dispose();
            preferences?.dispose();
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
