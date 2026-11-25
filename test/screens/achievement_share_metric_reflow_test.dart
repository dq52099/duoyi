// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/achievements.dart';
import 'package:duoyi/core/achievement_ui_copy.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/weekly_review_screenshot_font.dart';

Finder _shareText(String text) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text));
Finder _shareTextContaining(Pattern pattern) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.textContaining(pattern),
);

class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore(super.data) : super.withData();
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

int _wordLineCount(RenderParagraph paragraph, String word) {
  final text = paragraph.text.toPlainText();
  final index = text.indexOf(word);
  if (index == -1) {
    fail('Word "$word" not found in text: "$text"');
  }
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: index, extentOffset: index + word.length),
  );
  if (boxes.isEmpty) {
    fail('No layout boxes found for word "$word" in text: "$text"');
  }
  final lineTops = <double>[];
  for (final box in boxes) {
    if (lineTops.every((top) => (top - box.top).abs() > 0.5)) {
      lineTops.add(box.top);
    }
  }
  return lineTops.length;
}

void _assertWordDoesNotSplit(
  WidgetTester tester,
  Finder textFinder,
  String word,
) {
  final richTextFinder = find.descendant(
    of: textFinder,
    matching: find.byType(RichText),
  );
  expect(
    richTextFinder,
    findsOneWidget,
    reason: 'Expected exactly one RichText for "$word"',
  );
  final paragraph = tester.renderObject<RenderParagraph>(richTextFinder);
  final lines = _wordLineCount(paragraph, word);
  expect(
    lines,
    equals(1),
    reason:
        'Word "$word" split across $lines lines in paragraph "${paragraph.text.toPlainText()}"',
  );
}

Future<void> _captureReachableMetrics(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
  AchievementProvider achievements,
) async {
  final labels = I18n.current == AppLocale.en
      ? [
          'Time coins',
          'Lifetime',
          AchievementUiCopy.levelTitle(achievements.growthLevel),
          'Progress',
        ]
      : [
          '时光币',
          '累计',
          AchievementUiCopy.levelTitle(achievements.growthLevel),
          '完成度',
        ];
  for (var i = 0; i < labels.length; i++) {
    final target = _shareText(labels[i]);
    final metric = _metricForLabel(target);
    await tester.ensureVisible(metric);
    await _boundedPumpAndSettle(tester);
    final value = find
        .descendant(of: metric, matching: find.byType(Text))
        .first;
    expect(
      value.hitTestable(),
      findsOneWidget,
      reason: 'Metric value must be visible with its label: ${labels[i]}',
    );
    expect(
      target.hitTestable(),
      findsOneWidget,
      reason:
          'Metric must be reachable through actual dialog scrolling: ${labels[i]}',
    );
    final viewport = find
        .ancestor(of: metric, matching: find.byType(SingleChildScrollView))
        .first;
    final visible = tester.getRect(viewport);
    final actual = tester.getRect(metric);
    expect(actual.top, greaterThanOrEqualTo(visible.top - 0.5));
    expect(actual.bottom, lessThanOrEqualTo(visible.bottom + 0.5));
    for (final word in RegExp(r'[A-Za-z]+').allMatches(labels[i])) {
      _assertWordDoesNotSplit(tester, target, word.group(0)!);
    }
    expect(tester.takeException(), isNull);
    await _capture(tester, boundaryKey, '$name-metric-$i');
  }
}

Finder _metricForLabel(Finder label) => find
    .ancestor(
      of: label,
      matching: find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_AchievementShareMetric',
      ),
    )
    .first;

Widget _buildTestApp({
  required ThemeProvider theme,
  required AuthProvider auth,
  required UserProvider userProvider,
  required PreferencesProvider preferences,
  required AchievementProvider achievementProvider,
  required AppLockProvider lockProvider,
  required GlobalKey boundaryKey,
  required TextScaler textScaler,
  bool isDark = false,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeProvider>.value(value: theme),
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<UserProvider>.value(value: userProvider),
      ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
      ChangeNotifierProvider<AchievementProvider>.value(
        value: achievementProvider,
      ),
      ChangeNotifierProvider<AppLockProvider>.value(value: lockProvider),
    ],
    child: Consumer<ThemeProvider>(
      builder: (context, currentTheme, _) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (context, currentLocale, _) {
          final baseTheme = currentTheme.brand.theme;
          final effectiveTheme = isDark
              ? baseTheme.copyWith(
                  brightness: Brightness.dark,
                  colorScheme: baseTheme.colorScheme.copyWith(
                    brightness: Brightness.dark,
                  ),
                )
              : baseTheme;
          return MaterialApp(
            locale: Locale(currentLocale == AppLocale.en ? 'en' : 'zh'),
            supportedLocales: const [Locale('en'), Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: effectiveTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: RepaintBoundary(key: boundaryKey, child: child!),
            ),
            home: const BrandRouteSurface(
              remountOnLocaleChange: false,
              child: AchievementsScreen(),
            ),
          );
        },
      ),
    ),
  );
}

void main() {
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  testWidgets(
    'English 320x844 @ 200% scale - Lifetime, Routine and Progress do not split words',
    (tester) async {
      final originalTimeZoneReader =
          LocalTimezoneResolver.debugSystemTimeZoneReader;
      final previousStore = SharedPreferencesStorePlatform.instance;

      final initialPrefs = <String, Object>{
        'pref_app_timezone_mode': 'fixed',
        'pref_app_timezone_iana': 'Asia/Shanghai',
        'active_brand': 'defaultBrand',
        'theme_shop_state': jsonEncode({
          'activeBrand': 'defaultBrand',
          'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
        }),
        'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
        'flutter.pref_app_timezone_mode': 'fixed',
        'flutter.pref_app_timezone_iana': 'Asia/Shanghai',
        'flutter.active_brand': 'defaultBrand',
        'flutter.theme_shop_state': jsonEncode({
          'activeBrand': 'defaultBrand',
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

      final transport = MockClient((request) async {
        throw StateError(
          'Unexpected network call: ${request.method} ${request.url}',
        );
      });

      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      messenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      messenger.setMockMethodCallHandler(pathChannel, (call) async => '/tmp');
      messenger.setMockMethodCallHandler(
        shareChannel,
        (call) async => 'synthetic-target',
      );

      addTearDown(() {
        LocalTimezoneResolver.debugSystemTimeZoneReader =
            originalTimeZoneReader;
        SharedPreferencesStorePlatform.instance = previousStore;
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        messenger.setMockMethodCallHandler(pathChannel, null);
        messenger.setMockMethodCallHandler(shareChannel, null);
        tester.view.reset();
      });

      I18n.setLocale(AppLocale.en);

      late final PreferencesProvider preferences;
      late final ThemeProvider theme;
      late final AppLockProvider lockProvider;
      late final AchievementProvider achievementProvider;
      late final AuthProvider auth;
      late final UserProvider userProvider;

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
        await theme.loadFromStorage().timeout(const Duration(seconds: 5));
        await preferences.loadFromStorage().timeout(const Duration(seconds: 5));
        await lockProvider.loadFromStorage().timeout(
          const Duration(seconds: 5),
        );
        await achievementProvider.loadFromStorage().timeout(
          const Duration(seconds: 5),
        );
        await achievementProvider
            .updateContext(_seedContext)
            .timeout(const Duration(seconds: 5));
        await loadWeeklyReviewScreenshotFonts().timeout(
          const Duration(seconds: 5),
        );
      });

      await _drainAccountWrites(tester);

      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1.0;
      final boundaryKey = GlobalKey();

      await tester.pumpWidget(
        _buildTestApp(
          theme: theme,
          auth: auth,
          userProvider: userProvider,
          preferences: preferences,
          achievementProvider: achievementProvider,
          lockProvider: lockProvider,
          boundaryKey: boundaryKey,
          textScaler: const TextScaler.linear(2.0),
        ),
      );

      await _boundedPumpAndSettle(tester);
      expect(tester.takeException(), isNull);

      // Open share dialog
      final shareButton = find.byTooltip('Share achievements');
      expect(shareButton, findsOneWidget);
      await tester.ensureVisible(shareButton);
      await _boundedPumpAndSettle(tester);
      await tester.tap(shareButton);
      await _boundedPumpAndSettle(tester);
      expect(tester.takeException(), isNull);

      final dialogFinder = find.byType(AlertDialog);
      expect(dialogFinder, findsOneWidget);

      // Assert all four metric labels and values are present
      expect(_shareText('Time coins'), findsOneWidget);
      expect(_shareText('Lifetime'), findsOneWidget);
      expect(_shareTextContaining('Routine'), findsOneWidget);
      expect(_shareText('Progress'), findsOneWidget);

      final coinBalance = achievementProvider.coinBalance;
      final lifetimeCoins = achievementProvider.lifetimeCoins;
      final growthLevel = achievementProvider.growthLevel;
      final progress = achievementProvider.totalCount == 0
          ? 0.0
          : achievementProvider.unlockedCount / achievementProvider.totalCount;

      expect(_shareText('$coinBalance'), findsWidgets);
      expect(_shareText('$lifetimeCoins'), findsWidgets);
      expect(_shareText('Lv.${growthLevel.level}'), findsOneWidget);
      expect(_shareText('${(progress * 100).round()}%'), findsOneWidget);

      // Prove labels Lifetime, Routine, Progress do not split inside words via RenderParagraph geometry
      _assertWordDoesNotSplit(tester, _shareText('Lifetime'), 'Lifetime');
      _assertWordDoesNotSplit(
        tester,
        _shareTextContaining('Routine'),
        'Routine',
      );
      _assertWordDoesNotSplit(tester, _shareText('Progress'), 'Progress');
      _assertWordDoesNotSplit(tester, _shareText('Time coins'), 'Time');
      _assertWordDoesNotSplit(tester, _shareText('Time coins'), 'coins');

      // Assert no overflow
      expect(tester.takeException(), isNull);

      await _capture(tester, boundaryKey, 'en-320x844-200-defaultBrand');
      await _captureReachableMetrics(
        tester,
        boundaryKey,
        'en-320x844-200-defaultBrand',
        achievementProvider,
      );
    },
  );

  testWidgets(
    'Chinese large text 320x844 @ 200% with opening local brightness override',
    (tester) async {
      final originalTimeZoneReader =
          LocalTimezoneResolver.debugSystemTimeZoneReader;
      final previousStore = SharedPreferencesStorePlatform.instance;

      final initialPrefs = <String, Object>{
        'pref_app_timezone_mode': 'fixed',
        'pref_app_timezone_iana': 'Asia/Shanghai',
        'active_brand': 'liquidGlass',
        'theme_shop_state': jsonEncode({
          'activeBrand': 'liquidGlass',
          'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
        }),
        'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
        'flutter.pref_app_timezone_mode': 'fixed',
        'flutter.pref_app_timezone_iana': 'Asia/Shanghai',
        'flutter.active_brand': 'liquidGlass',
        'flutter.theme_shop_state': jsonEncode({
          'activeBrand': 'liquidGlass',
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

      final transport = MockClient((request) async {
        throw StateError(
          'Unexpected network call: ${request.method} ${request.url}',
        );
      });

      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      messenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      messenger.setMockMethodCallHandler(pathChannel, (call) async => '/tmp');
      messenger.setMockMethodCallHandler(
        shareChannel,
        (call) async => 'synthetic-target',
      );

      addTearDown(() {
        LocalTimezoneResolver.debugSystemTimeZoneReader =
            originalTimeZoneReader;
        SharedPreferencesStorePlatform.instance = previousStore;
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        messenger.setMockMethodCallHandler(pathChannel, null);
        messenger.setMockMethodCallHandler(shareChannel, null);
        tester.view.reset();
      });

      I18n.setLocale(AppLocale.zh);

      late final PreferencesProvider preferences;
      late final ThemeProvider theme;
      late final AppLockProvider lockProvider;
      late final AchievementProvider achievementProvider;
      late final AuthProvider auth;
      late final UserProvider userProvider;

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
        await theme.loadFromStorage().timeout(const Duration(seconds: 5));
        await preferences.loadFromStorage().timeout(const Duration(seconds: 5));
        await lockProvider.loadFromStorage().timeout(
          const Duration(seconds: 5),
        );
        await achievementProvider.loadFromStorage().timeout(
          const Duration(seconds: 5),
        );
        await achievementProvider
            .updateContext(_seedContext)
            .timeout(const Duration(seconds: 5));
        await loadWeeklyReviewScreenshotFonts().timeout(
          const Duration(seconds: 5),
        );
      });

      await _drainAccountWrites(tester);

      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1.0;
      final boundaryKey = GlobalKey();

      await tester.pumpWidget(
        _buildTestApp(
          theme: theme,
          auth: auth,
          userProvider: userProvider,
          preferences: preferences,
          achievementProvider: achievementProvider,
          lockProvider: lockProvider,
          boundaryKey: boundaryKey,
          textScaler: const TextScaler.linear(2.0),
          isDark: true,
        ),
      );

      await _boundedPumpAndSettle(tester);
      expect(tester.takeException(), isNull);

      final shareButton = find.byTooltip('成就分享图');
      expect(shareButton, findsOneWidget);
      await tester.ensureVisible(shareButton);
      await _boundedPumpAndSettle(tester);
      await tester.tap(shareButton);
      await _boundedPumpAndSettle(tester);
      expect(tester.takeException(), isNull);

      final dialogFinder = find.byType(AlertDialog);
      expect(dialogFinder, findsOneWidget);

      // Verify all 4 Chinese labels and values are present
      expect(_shareText('时光币'), findsOneWidget);
      expect(_shareText('累计'), findsOneWidget);
      expect(
        _shareText(
          AchievementUiCopy.levelTitle(achievementProvider.growthLevel),
        ),
        findsOneWidget,
      );
      expect(_shareText('完成度'), findsOneWidget);

      final coinBalance = achievementProvider.coinBalance;
      final lifetimeCoins = achievementProvider.lifetimeCoins;
      final growthLevel = achievementProvider.growthLevel;
      final progress = achievementProvider.totalCount == 0
          ? 0.0
          : achievementProvider.unlockedCount / achievementProvider.totalCount;

      expect(_shareText('$coinBalance'), findsWidgets);
      expect(_shareText('$lifetimeCoins'), findsWidgets);
      expect(_shareText('Lv.${growthLevel.level}'), findsOneWidget);
      expect(_shareText('${(progress * 100).round()}%'), findsOneWidget);

      // Assert no overflow
      expect(tester.takeException(), isNull);

      await _capture(tester, boundaryKey, 'zh-320x844-200-liquidGlass-dark');
      await _captureReachableMetrics(
        tester,
        boundaryKey,
        'zh-320x844-200-liquidGlass-dark',
        achievementProvider,
      );
    },
  );

  testWidgets(
    'Wide normal 844x390 @ 100% scale - compact symmetrical layout without split words',
    (tester) async {
      final originalTimeZoneReader =
          LocalTimezoneResolver.debugSystemTimeZoneReader;
      final previousStore = SharedPreferencesStorePlatform.instance;

      final initialPrefs = <String, Object>{
        'pref_app_timezone_mode': 'fixed',
        'pref_app_timezone_iana': 'Asia/Shanghai',
        'active_brand': 'liquidGlass',
        'theme_shop_state': jsonEncode({
          'activeBrand': 'liquidGlass',
          'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
        }),
        'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
        'flutter.pref_app_timezone_mode': 'fixed',
        'flutter.pref_app_timezone_iana': 'Asia/Shanghai',
        'flutter.active_brand': 'liquidGlass',
        'flutter.theme_shop_state': jsonEncode({
          'activeBrand': 'liquidGlass',
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

      final transport = MockClient((request) async {
        throw StateError(
          'Unexpected network call: ${request.method} ${request.url}',
        );
      });

      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      messenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      messenger.setMockMethodCallHandler(pathChannel, (call) async => '/tmp');
      messenger.setMockMethodCallHandler(
        shareChannel,
        (call) async => 'synthetic-target',
      );

      addTearDown(() {
        LocalTimezoneResolver.debugSystemTimeZoneReader =
            originalTimeZoneReader;
        SharedPreferencesStorePlatform.instance = previousStore;
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        messenger.setMockMethodCallHandler(pathChannel, null);
        messenger.setMockMethodCallHandler(shareChannel, null);
        tester.view.reset();
      });

      I18n.setLocale(AppLocale.en);

      late final PreferencesProvider preferences;
      late final ThemeProvider theme;
      late final AppLockProvider lockProvider;
      late final AchievementProvider achievementProvider;
      late final AuthProvider auth;
      late final UserProvider userProvider;

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
        await theme.loadFromStorage().timeout(const Duration(seconds: 5));
        await preferences.loadFromStorage().timeout(const Duration(seconds: 5));
        await lockProvider.loadFromStorage().timeout(
          const Duration(seconds: 5),
        );
        await achievementProvider.loadFromStorage().timeout(
          const Duration(seconds: 5),
        );
        await achievementProvider
            .updateContext(_seedContext)
            .timeout(const Duration(seconds: 5));
        await loadWeeklyReviewScreenshotFonts().timeout(
          const Duration(seconds: 5),
        );
      });

      await _drainAccountWrites(tester);

      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1.0;
      final boundaryKey = GlobalKey();

      await tester.pumpWidget(
        _buildTestApp(
          theme: theme,
          auth: auth,
          userProvider: userProvider,
          preferences: preferences,
          achievementProvider: achievementProvider,
          lockProvider: lockProvider,
          boundaryKey: boundaryKey,
          textScaler: TextScaler.noScaling,
          isDark: false,
        ),
      );

      await _boundedPumpAndSettle(tester);
      expect(tester.takeException(), isNull);

      final shareButton = find.byTooltip('Share achievements');
      expect(shareButton, findsOneWidget);
      await tester.ensureVisible(shareButton);
      await _boundedPumpAndSettle(tester);
      await tester.tap(shareButton);
      await _boundedPumpAndSettle(tester);
      expect(tester.takeException(), isNull);

      final dialogFinder = find.byType(AlertDialog);
      expect(dialogFinder, findsOneWidget);

      // Verify all 4 labels and values are present
      expect(_shareText('Time coins'), findsOneWidget);
      expect(_shareText('Lifetime'), findsOneWidget);
      expect(_shareTextContaining('Routine'), findsOneWidget);
      expect(_shareText('Progress'), findsOneWidget);

      final coinBalance = achievementProvider.coinBalance;
      final lifetimeCoins = achievementProvider.lifetimeCoins;
      final growthLevel = achievementProvider.growthLevel;
      final progress = achievementProvider.totalCount == 0
          ? 0.0
          : achievementProvider.unlockedCount / achievementProvider.totalCount;

      expect(_shareText('$coinBalance'), findsWidgets);
      expect(_shareText('$lifetimeCoins'), findsWidgets);
      expect(_shareText('Lv.${growthLevel.level}'), findsOneWidget);
      expect(_shareText('${(progress * 100).round()}%'), findsOneWidget);

      // Verify no word splits
      _assertWordDoesNotSplit(tester, _shareText('Lifetime'), 'Lifetime');
      _assertWordDoesNotSplit(
        tester,
        _shareTextContaining('Routine'),
        'Routine',
      );
      _assertWordDoesNotSplit(tester, _shareText('Progress'), 'Progress');

      // Assert no overflow
      expect(tester.takeException(), isNull);

      final coinsBox = tester.getRect(
        _metricForLabel(_shareText('Time coins')),
      );
      final lifetimeBox = tester.getRect(
        _metricForLabel(_shareText('Lifetime')),
      );
      expect(
        lifetimeBox.top,
        closeTo(coinsBox.top, 0.5),
        reason: 'Normal wide poster must retain its compact two-column row',
      );
      expect(
        lifetimeBox.left,
        greaterThanOrEqualTo(coinsBox.right),
        reason: 'Metrics must occupy distinct columns when space permits',
      );

      await _capture(tester, boundaryKey, 'en-844x390-normal-liquidGlass');
      await _captureReachableMetrics(
        tester,
        boundaryKey,
        'en-844x390-normal-liquidGlass',
        achievementProvider,
      );
    },
  );

  testWidgets('Retained share route and metrics across live brand changes', (
    tester,
  ) async {
    final originalTimeZoneReader =
        LocalTimezoneResolver.debugSystemTimeZoneReader;
    final previousStore = SharedPreferencesStorePlatform.instance;

    final initialPrefs = <String, Object>{
      'pref_app_timezone_mode': 'fixed',
      'pref_app_timezone_iana': 'Asia/Shanghai',
      'active_brand': 'defaultBrand',
      'theme_shop_state': jsonEncode({
        'activeBrand': 'defaultBrand',
        'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
      }),
      'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
      'flutter.pref_app_timezone_mode': 'fixed',
      'flutter.pref_app_timezone_iana': 'Asia/Shanghai',
      'flutter.active_brand': 'defaultBrand',
      'flutter.theme_shop_state': jsonEncode({
        'activeBrand': 'defaultBrand',
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

    final transport = MockClient((request) async {
      throw StateError(
        'Unexpected network call: ${request.method} ${request.url}',
      );
    });

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(pathChannel, (call) async => '/tmp');
    messenger.setMockMethodCallHandler(
      shareChannel,
      (call) async => 'synthetic-target',
    );

    addTearDown(() {
      LocalTimezoneResolver.debugSystemTimeZoneReader = originalTimeZoneReader;
      SharedPreferencesStorePlatform.instance = previousStore;
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      messenger.setMockMethodCallHandler(pathChannel, null);
      messenger.setMockMethodCallHandler(shareChannel, null);
      tester.view.reset();
    });

    I18n.setLocale(AppLocale.en);

    late final PreferencesProvider preferences;
    late final ThemeProvider theme;
    late final AppLockProvider lockProvider;
    late final AchievementProvider achievementProvider;
    late final AuthProvider auth;
    late final UserProvider userProvider;

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
      await theme.loadFromStorage().timeout(const Duration(seconds: 5));
      await preferences.loadFromStorage().timeout(const Duration(seconds: 5));
      await lockProvider.loadFromStorage().timeout(const Duration(seconds: 5));
      await achievementProvider.loadFromStorage().timeout(
        const Duration(seconds: 5),
      );
      await achievementProvider
          .updateContext(_seedContext)
          .timeout(const Duration(seconds: 5));
      await loadWeeklyReviewScreenshotFonts().timeout(
        const Duration(seconds: 5),
      );
    });

    await _drainAccountWrites(tester);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    final boundaryKey = GlobalKey();

    await tester.pumpWidget(
      _buildTestApp(
        theme: theme,
        auth: auth,
        userProvider: userProvider,
        preferences: preferences,
        achievementProvider: achievementProvider,
        lockProvider: lockProvider,
        boundaryKey: boundaryKey,
        textScaler: const TextScaler.linear(1.6),
        isDark: false,
      ),
    );

    await _boundedPumpAndSettle(tester);
    expect(tester.takeException(), isNull);

    final shareButton = find.byTooltip('Share achievements');
    expect(shareButton, findsOneWidget);
    await tester.ensureVisible(shareButton);
    await _boundedPumpAndSettle(tester);
    await tester.tap(shareButton);
    await _boundedPumpAndSettle(tester);
    expect(tester.takeException(), isNull);

    final dialogFinder = find.byType(AlertDialog);
    expect(dialogFinder, findsOneWidget);
    final initialElement = tester.element(dialogFinder);
    final initialRoute = ModalRoute.of(initialElement);
    expect(initialRoute, isNotNull);

    expect(_shareText('Time coins'), findsOneWidget);
    expect(_shareText('Lifetime'), findsOneWidget);
    expect(_shareTextContaining('Routine'), findsOneWidget);
    expect(_shareText('Progress'), findsOneWidget);

    // Switch brand to liquidGlass while dialog is mounted
    await tester.runAsync(() async {
      final switched = await theme.setBrand('liquidGlass');
      expect(switched, isTrue);
      await AccountPreferenceWrites.drain().timeout(const Duration(seconds: 5));
    });
    await _boundedPumpAndSettle(tester);
    expect(tester.takeException(), isNull);

    // Verify route and state retention
    expect(identical(tester.element(dialogFinder), initialElement), isTrue);
    expect(
      identical(ModalRoute.of(tester.element(dialogFinder)), initialRoute),
      isTrue,
    );

    expect(_shareText('Time coins'), findsOneWidget);
    expect(_shareText('Lifetime'), findsOneWidget);
    expect(_shareTextContaining('Routine'), findsOneWidget);
    expect(_shareText('Progress'), findsOneWidget);

    _assertWordDoesNotSplit(tester, _shareText('Lifetime'), 'Lifetime');
    _assertWordDoesNotSplit(tester, _shareTextContaining('Routine'), 'Routine');
    _assertWordDoesNotSplit(tester, _shareText('Progress'), 'Progress');

    // Switch brand back to defaultBrand
    await tester.runAsync(() async {
      final reverted = await theme.setBrand('defaultBrand');
      expect(reverted, isTrue);
      await AccountPreferenceWrites.drain().timeout(const Duration(seconds: 5));
    });
    await _boundedPumpAndSettle(tester);
    expect(tester.takeException(), isNull);

    // Verify route retention preserved again
    expect(identical(tester.element(dialogFinder), initialElement), isTrue);
    expect(
      identical(ModalRoute.of(tester.element(dialogFinder)), initialRoute),
      isTrue,
    );

    expect(_shareText('Time coins'), findsOneWidget);
    expect(_shareText('Lifetime'), findsOneWidget);
    expect(_shareTextContaining('Routine'), findsOneWidget);
    expect(_shareText('Progress'), findsOneWidget);

    expect(tester.takeException(), isNull);

    await _capture(tester, boundaryKey, 'brand-switch-retained');
    await _captureReachableMetrics(
      tester,
      boundaryKey,
      'brand-switch-retained',
      achievementProvider,
    );
  });
}
