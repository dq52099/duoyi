import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/diary_screen.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandBackground;
import 'package:duoyi/widgets/surface_components.dart' show appSurfaceStyleOf;
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
      final file = File('$explicitDir/diary-insights-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _scrollUntilMaterialized(
  WidgetTester tester,
  Finder targetFinder,
  Finder scrollableFinder, {
  double stepDelta = 150.0,
  int maxSteps = 30,
}) async {
  if (targetFinder.evaluate().isNotEmpty) return;

  for (var i = 0; i < maxSteps; i++) {
    if (targetFinder.evaluate().isNotEmpty) break;
    final posBefore = tester
        .state<ScrollableState>(scrollableFinder)
        .position
        .pixels;
    await tester.drag(scrollableFinder, Offset(0, -stepDelta));
    await _boundedPumpAndSettle(tester);
    final posAfter = tester
        .state<ScrollableState>(scrollableFinder)
        .position
        .pixels;
    if ((posAfter - posBefore).abs() < 0.5) break;
  }

  if (targetFinder.evaluate().isEmpty) {
    for (var i = 0; i < maxSteps * 2; i++) {
      if (targetFinder.evaluate().isNotEmpty) break;
      final posBefore = tester
          .state<ScrollableState>(scrollableFinder)
          .position
          .pixels;
      await tester.drag(scrollableFinder, Offset(0, stepDelta));
      await _boundedPumpAndSettle(tester);
      final posAfter = tester
          .state<ScrollableState>(scrollableFinder)
          .position
          .pixels;
      if ((posAfter - posBefore).abs() < 0.5) break;
    }
  }

  expect(
    targetFinder,
    findsOneWidget,
    reason:
        'Target text should be found and materialized in ListView after scrolling',
  );
}

Future<void> _verifyVisibleTextInViewport(
  WidgetTester tester,
  Finder textFinder,
  Finder scrollableFinder, {
  bool isLatin = false,
}) async {
  await _scrollUntilMaterialized(tester, textFinder, scrollableFinder);

  final rich = find.descendant(of: textFinder, matching: find.byType(RichText));
  final target = rich.evaluate().isEmpty ? textFinder : rich;
  final paragraph = tester.renderObject<RenderParagraph>(target);
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: 'Text must not exceed max lines',
  );

  final plainText = paragraph.text.toPlainText();
  final viewportRect = tester.getRect(scrollableFinder);

  if (isLatin) {
    final matches = RegExp(
      r"[A-Za-z0-9]+(?:['’-][A-Za-z0-9]+)*",
    ).allMatches(plainText);
    for (final match in matches) {
      final wordBoxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: match.start, extentOffset: match.end),
      );
      expect(wordBoxes, isNotEmpty);
      expect(
        wordBoxes.map((box) => box.top.round()).toSet(),
        hasLength(1),
        reason:
            'Latin word "${match.group(0)}" in "$plainText" must remain on one line',
      );
    }
  }

  final fullBoxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: plainText.length),
  );
  expect(fullBoxes, isNotEmpty, reason: 'Boxes should exist for "$plainText"');

  Rect boxGlobal(ui.TextBox b) => Rect.fromPoints(
    paragraph.localToGlobal(Offset(b.left, b.top)),
    paragraph.localToGlobal(Offset(b.right, b.bottom)),
  );

  for (final box in fullBoxes) {
    final currentBox = boxGlobal(box);
    if (currentBox.top < viewportRect.top ||
        currentBox.bottom > viewportRect.bottom) {
      final delta = currentBox.center.dy - viewportRect.center.dy;
      final position = tester.state<ScrollableState>(scrollableFinder).position;
      position.jumpTo(
        (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      await _boundedPumpAndSettle(tester);
    }

    final actualBox = boxGlobal(box);
    expect(
      actualBox.left,
      greaterThanOrEqualTo(viewportRect.left - 1.0),
      reason: 'Glyph box left bound for "$plainText" must be within viewport',
    );
    expect(
      actualBox.right,
      lessThanOrEqualTo(viewportRect.right + 1.0),
      reason: 'Glyph box right bound for "$plainText" must be within viewport',
    );
    expect(
      actualBox.top,
      greaterThanOrEqualTo(viewportRect.top - 1.0),
      reason: 'Glyph box top bound for "$plainText" must be within viewport',
    );
    expect(
      actualBox.bottom,
      lessThanOrEqualTo(viewportRect.bottom + 1.0),
      reason: 'Glyph box bottom bound for "$plainText" must be within viewport',
    );
  }
}

class _InsightItemCheck {
  final String titleZh;
  final String bodyZh;
  final String titleEn;
  final String bodyEn;

  const _InsightItemCheck({
    required this.titleZh,
    required this.bodyZh,
    required this.titleEn,
    required this.bodyEn,
  });
}

class _ScenarioConfig {
  final String name;
  final Size size;
  final double scale;
  final String initialBrand;
  final String targetBrand;
  final AppLocale initialLocale;
  final AppLocale targetLocale;
  final List<DiaryEntry> Function(DateTime today) entriesBuilder;
  final List<_InsightItemCheck> items;

  const _ScenarioConfig({
    required this.name,
    required this.size,
    required this.scale,
    required this.initialBrand,
    required this.targetBrand,
    required this.initialLocale,
    required this.targetLocale,
    required this.entriesBuilder,
    required this.items,
  });
}

final _scenarios = <_ScenarioConfig>[
  // Scenario 1: 320x844 scale 2.0 portrait, defaultBrand <-> liquidGlass, zh <-> en
  // Covers: Overview (dominant mood Good), EmotionTrend (rising), Theme (tags: #压力, #工作, #生活), Streak
  _ScenarioConfig(
    name: 'zh-portrait-320x844-scale2-defaultBrand',
    size: const Size(320, 844),
    scale: 2.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    initialLocale: AppLocale.zh,
    targetLocale: AppLocale.en,
    entriesBuilder: (today) => [
      DiaryEntry(
        id: 's1-e1',
        date: today,
        mood: Mood.good,
        tags: const ['工作', '生活'],
        content: '今天工作推进顺利，晚上散步放松。',
      ),
      DiaryEntry(
        id: 's1-e2',
        date: today.subtract(const Duration(days: 1)),
        mood: Mood.awesome,
        tags: const ['工作'],
        content: '工作会议有结果，状态不错。',
      ),
      DiaryEntry(
        id: 's1-e3',
        date: today.subtract(const Duration(days: 2)),
        mood: Mood.good,
        tags: const ['运动'],
        content: '运动之后睡眠更好。',
      ),
      DiaryEntry(
        id: 's1-e4',
        date: today.subtract(const Duration(days: 16)),
        mood: Mood.bad,
        tags: const ['压力'],
        content: '工作压力比较明显。',
      ),
      DiaryEntry(
        id: 's1-e5',
        date: today.subtract(const Duration(days: 17)),
        mood: Mood.terrible,
        tags: const ['压力'],
        content: '压力很大，睡眠也不好。',
      ),
    ],
    items: const [
      _InsightItemCheck(
        titleZh: '近期心情以开心为主',
        bodyZh: '近 30 天记录 5 篇，其中 5 篇带有心情。',
        titleEn: 'Recent mood is mostly Good',
        bodyEn:
            'Recorded 5 entries in the past 30 days, including 5 entries with mood.',
      ),
      _InsightItemCheck(
        titleZh: '情绪正在回升',
        bodyZh: '最近半月平均心情比前半月更积极，可以留意哪些安排带来了改善。',
        titleEn: 'Mood is improving',
        bodyEn:
            'Average mood in the past half month is more positive than the earlier half. Notice what arrangements brought improvement.',
      ),
      _InsightItemCheck(
        titleZh: '近期主题集中',
        bodyZh: '出现最多的主题是 #压力、#工作、#生活，可作为本月复盘线索。',
        titleEn: 'Recent themes are focused',
        bodyEn:
            'The most frequent themes are #压力, #工作, #生活, which can serve as review clues this month.',
      ),
      _InsightItemCheck(
        titleZh: '记录连续性不错',
        bodyZh: '已连续记录 3 天，适合在每天固定时段做简短复盘。',
        titleEn: 'Consistent writing streak',
        bodyEn:
            'Recorded for 3 consecutive days, ideal for a brief review at a regular time each day.',
      ),
    ],
  ),

  // Scenario 2: 844x390 scale 1.0 landscape, liquidGlass <-> defaultBrand, en <-> zh
  // Covers: Overview (dominant mood Low), EmotionTrend (dipping), Theme (keywords: 复盘), Attention
  _ScenarioConfig(
    name: 'en-landscape-844x390-scale1-liquidGlass',
    size: const Size(844, 390),
    scale: 1.0,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    initialLocale: AppLocale.en,
    targetLocale: AppLocale.zh,
    entriesBuilder: (today) => [
      DiaryEntry(
        id: 's2-e1',
        date: today,
        mood: Mood.bad,
        tags: const [],
        content: '复盘 代码质量 复盘 架构设计。',
      ),
      DiaryEntry(
        id: 's2-e2',
        date: today.subtract(const Duration(days: 2)),
        mood: Mood.terrible,
        tags: const [],
        content: '复盘 项目进展 继续 深度复盘。',
      ),
      DiaryEntry(
        id: 's2-e3',
        date: today.subtract(const Duration(days: 3)),
        mood: Mood.bad,
        tags: const [],
        content: '复盘 系统性能 优化 复盘结果。',
      ),
      DiaryEntry(
        id: 's2-e4',
        date: today.subtract(const Duration(days: 20)),
        mood: Mood.awesome,
        tags: const [],
        content: '之前状态很好。',
      ),
    ],
    items: const [
      _InsightItemCheck(
        titleZh: '近期心情以郁闷为主',
        bodyZh: '近 30 天记录 4 篇，其中 4 篇带有心情。',
        titleEn: 'Recent mood is mostly Low',
        bodyEn:
            'Recorded 4 entries in the past 30 days, including 4 entries with mood.',
      ),
      _InsightItemCheck(
        titleZh: '情绪有走低迹象',
        bodyZh: '最近半月平均心情低于前半月，建议减少高压安排并记录触发原因。',
        titleEn: 'Mood is dipping',
        bodyEn:
            'Average mood in the past half month is lower than the earlier half. Consider reducing high-stress plans and noting triggers.',
      ),
      _InsightItemCheck(
        titleZh: '近期内容线索',
        bodyZh: '日记中反复出现 复盘，适合继续观察。',
        titleEn: 'Recent content clues',
        bodyEn: 'Recurring in your diary: 复盘, worth observing further.',
      ),
      _InsightItemCheck(
        titleZh: '低落心情偏多',
        bodyZh: '近期待关注心情占比 75%，可以标记原因并安排休息。',
        titleEn: 'Low moods are frequent',
        bodyEn:
            'Moods needing attention make up 75% recently. Consider noting causes and planning some rest.',
      ),
    ],
  ),

  // Scenario 3: Overview without mood body and singular count coverage
  _ScenarioConfig(
    name: 'en-portrait-320x844-scale2-no-mood-overview',
    size: const Size(320, 844),
    scale: 2.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    initialLocale: AppLocale.en,
    targetLocale: AppLocale.zh,
    entriesBuilder: (today) => [
      DiaryEntry(
        id: 's3-e1',
        date: today,
        mood: null,
        tags: const [],
        content: '只记录了文字随笔，没有选心情。',
      ),
    ],
    items: const [
      _InsightItemCheck(
        titleZh: '日记记录已开始',
        bodyZh: '近 30 天记录 1 篇，可继续补充心情来生成情绪走势。',
        titleEn: 'Diary journaling has started',
        bodyEn:
            'Recorded 1 entry in the past 30 days, keep adding moods to generate emotional trends.',
      ),
    ],
  ),
];

void main() {
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets('Diary insights live locale priority roundtrip ${scenario.name}', (
      tester,
    ) async {
      await HttpOverrides.runZoned(() async {
        final originalLocale = I18n.current;
        final originalTimeZoneReader =
            LocalTimezoneResolver.debugSystemTimeZoneReader;
        final previousStore = SharedPreferencesStorePlatform.instance;

        // Use current local civil day for screen fixtures so entries fall within 30 days
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final entries = scenario.entriesBuilder(today);

        final serialized = entries
            .map((e) => jsonEncode(e.toJson()))
            .toList(growable: false);

        final initialPrefs = <String, Object>{
          'pref_app_timezone_mode': 'fixed',
          'pref_app_timezone_iana': 'Asia/Shanghai',
          'active_brand': scenario.initialBrand,
          'theme_shop_state': jsonEncode({
            'activeBrand': scenario.initialBrand,
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          }),
          'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          'duoyi_diary': serialized,
          'flutter.pref_app_timezone_mode': 'fixed',
          'flutter.pref_app_timezone_iana': 'Asia/Shanghai',
          'flutter.active_brand': scenario.initialBrand,
          'flutter.theme_shop_state': jsonEncode({
            'activeBrand': scenario.initialBrand,
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          }),
          'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          'flutter.duoyi_diary': serialized,
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

        final diaries = DiaryProvider();
        final theme = ThemeProvider();
        late final PreferencesProvider preferences;

        try {
          I18n.setLocale(scenario.initialLocale);

          await tester.runAsync(() async {
            preferences = PreferencesProvider();
            await theme.loadFromStorage().timeout(const Duration(seconds: 5));
            await preferences.loadFromStorage().timeout(
              const Duration(seconds: 5),
            );
            await diaries.loadFromStorage().timeout(const Duration(seconds: 5));
            await loadWeeklyReviewScreenshotFonts().timeout(
              const Duration(seconds: 5),
            );
          });

          await _drainAccountWrites(tester);

          expect(theme.brand.id, scenario.initialBrand);
          expect(diaries.entries.length, entries.length);

          tester.view.physicalSize = scenario.size;
          tester.view.devicePixelRatio = 1;

          final boundary = GlobalKey();

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<DiaryProvider>.value(value: diaries),
                ChangeNotifierProvider<PreferencesProvider>.value(
                  value: preferences,
                ),
              ],
              child: Consumer<ThemeProvider>(
                builder: (context, currentTheme, _) {
                  return ValueListenableBuilder<AppLocale>(
                    valueListenable: I18n.localeListenable,
                    builder: (context, currentLocale, _) {
                      return MaterialApp(
                        locale: currentLocale.flutterLocale,
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
                        home: const BrandBackground(child: DiaryScreen()),
                      );
                    },
                  );
                },
              ),
            ),
          );

          // 1. Production entry in stable BrandBackground from first frame
          expect(find.byType(BrandBackground), findsWidgets);
          expect(find.byType(DiaryScreen), findsOneWidget);
          await _boundedPumpAndSettle(tester);

          final initialDiaryElement = tester.element(find.byType(DiaryScreen));
          final initialRoute = ModalRoute.of(initialDiaryElement);
          final scrollableFinder = find.byType(Scrollable).first;
          final initialScrollableState = tester.state<ScrollableState>(
            scrollableFinder,
          );

          await _capture(tester, boundary, '${scenario.name}-initial');

          // 2. Establish a known nonzero scroll position where insight card is in view
          final firstTitle = scenario.initialLocale == AppLocale.en
              ? scenario.items.first.titleEn
              : scenario.items.first.titleZh;
          await _scrollUntilMaterialized(
            tester,
            find.text(firstTitle),
            scrollableFinder,
          );
          await _boundedPumpAndSettle(tester);
          final savedNonzeroScroll = initialScrollableState.position.pixels;
          expect(
            savedNonzeroScroll,
            greaterThan(0.0),
            reason:
                'Insight card is below summary, so scroll offset must be nonzero',
          );

          // 3. Scroll each real insight title AND body into actual clipped viewport
          // and verify bounding boxes on all four viewport bounds
          final isInitEn = scenario.initialLocale == AppLocale.en;
          for (final item in scenario.items) {
            final expectedTitle = isInitEn ? item.titleEn : item.titleZh;
            final expectedBody = isInitEn ? item.bodyEn : item.bodyZh;

            await _verifyVisibleTextInViewport(
              tester,
              find.text(expectedTitle),
              scrollableFinder,
              isLatin: isInitEn,
            );
            await _verifyVisibleTextInViewport(
              tester,
              find.text(expectedBody),
              scrollableFinder,
              isLatin: isInitEn,
            );
          }

          // Restore scroll to established nonzero position after probing
          initialScrollableState.position.jumpTo(savedNonzeroScroll);
          await _boundedPumpAndSettle(tester);

          // 4. Independent rendered reference theme check on initial brand
          final initialRefTheme = AppBrands.byId(scenario.initialBrand).theme;
          final initialExpectedSurface = scenario.initialBrand == 'liquidGlass'
              ? AppSurfaceStyle.liquidGlass
              : AppSurfaceStyle.ios;
          expect(
            appSurfaceStyleOf(tester.element(find.byType(DiaryScreen))),
            initialExpectedSurface,
          );
          final initialOverviewIcon = tester.widget<Icon>(
            find.byIcon(Icons.auto_graph_outlined),
          );
          expect(
            initialOverviewIcon.color,
            initialRefTheme.colorScheme.primary,
          );

          // 5. Live locale switch: retains Element, Route, ScrollableState, and nonzero scroll
          I18n.setLocale(scenario.targetLocale);
          await _boundedPumpAndSettle(tester);

          expect(
            identical(
              tester.element(find.byType(DiaryScreen)),
              initialDiaryElement,
            ),
            isTrue,
            reason:
                'DiaryScreen Element must be retained on live locale change',
          );
          expect(
            identical(
              ModalRoute.of(tester.element(find.byType(DiaryScreen))),
              initialRoute,
            ),
            isTrue,
            reason: 'ModalRoute must be retained on live locale change',
          );
          expect(
            identical(
              tester.state<ScrollableState>(scrollableFinder),
              initialScrollableState,
            ),
            isTrue,
            reason: 'ScrollableState must be retained on live locale change',
          );
          expect(
            initialScrollableState.position.pixels,
            closeTo(savedNonzeroScroll, 0.01),
            reason:
                'Nonzero scroll position must be retained on live locale change',
          );

          // Verify switched language items
          final isTargetEn = scenario.targetLocale == AppLocale.en;
          for (final item in scenario.items) {
            final expectedTitle = isTargetEn ? item.titleEn : item.titleZh;
            final expectedBody = isTargetEn ? item.bodyEn : item.bodyZh;

            await _verifyVisibleTextInViewport(
              tester,
              find.text(expectedTitle),
              scrollableFinder,
              isLatin: isTargetEn,
            );
            await _verifyVisibleTextInViewport(
              tester,
              find.text(expectedBody),
              scrollableFinder,
              isLatin: isTargetEn,
            );
          }

          await _capture(tester, boundary, '${scenario.name}-locale-switched');

          // Restore the user scroll position after the explicit text probes
          initialScrollableState.position.jumpTo(savedNonzeroScroll);
          await _boundedPumpAndSettle(tester);

          // 6. Live locale roundtrip back to initial
          I18n.setLocale(scenario.initialLocale);
          await _boundedPumpAndSettle(tester);

          expect(
            identical(
              tester.element(find.byType(DiaryScreen)),
              initialDiaryElement,
            ),
            isTrue,
          );
          expect(
            initialScrollableState.position.pixels,
            closeTo(savedNonzeroScroll, 0.01),
          );

          // 7. Live brand switch via theme.setBrand(String id): await and assert accepted result
          final switchResult = await tester.runAsync(
            () => theme.setBrand(scenario.targetBrand),
          );
          expect(switchResult, isTrue, reason: 'theme.setBrand must succeed');
          expect(theme.brand.id, scenario.targetBrand);
          await _boundedPumpAndSettle(tester);

          expect(
            identical(
              tester.element(find.byType(DiaryScreen)),
              initialDiaryElement,
            ),
            isTrue,
            reason: 'DiaryScreen Element must be retained on live brand change',
          );
          expect(
            identical(
              ModalRoute.of(tester.element(find.byType(DiaryScreen))),
              initialRoute,
            ),
            isTrue,
          );
          expect(
            identical(
              tester.state<ScrollableState>(scrollableFinder),
              initialScrollableState,
            ),
            isTrue,
          );
          expect(
            initialScrollableState.position.pixels,
            closeTo(savedNonzeroScroll, 0.01),
            reason:
                'Nonzero scroll position must be retained on live brand change',
          );

          // Verify independent reference styles for target brand
          final targetRefTheme = AppBrands.byId(scenario.targetBrand).theme;
          final targetExpectedSurface = scenario.targetBrand == 'liquidGlass'
              ? AppSurfaceStyle.liquidGlass
              : AppSurfaceStyle.ios;
          expect(
            appSurfaceStyleOf(tester.element(find.byType(DiaryScreen))),
            targetExpectedSurface,
          );
          final targetOverviewIcon = tester.widget<Icon>(
            find.byIcon(Icons.auto_graph_outlined),
          );
          expect(targetOverviewIcon.color, targetRefTheme.colorScheme.primary);

          await _capture(tester, boundary, '${scenario.name}-brand-switched');

          // 8. Brand roundtrip back to initial brand
          final revertResult = await tester.runAsync(
            () => theme.setBrand(scenario.initialBrand),
          );
          expect(revertResult, isTrue);
          expect(theme.brand.id, scenario.initialBrand);
          await _boundedPumpAndSettle(tester);

          expect(
            identical(
              tester.element(find.byType(DiaryScreen)),
              initialDiaryElement,
            ),
            isTrue,
          );
          expect(
            initialScrollableState.position.pixels,
            closeTo(savedNonzeroScroll, 0.01),
          );

          // 9. Further scroll verification
          await tester.drag(scrollableFinder, const Offset(0, -60));
          await _boundedPumpAndSettle(tester);
          expect(
            initialScrollableState.position.pixels,
            greaterThan(savedNonzeroScroll),
          );

          await _capture(tester, boundary, '${scenario.name}-scrolled');

          // 10. Unmount widget tree before finally cleanup
          await tester.pumpWidget(const SizedBox.shrink());
          await _boundedPumpAndSettle(tester);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await _boundedPumpAndSettle(tester);
          await _drainAccountWrites(tester);
          diaries.dispose();
          theme.dispose();
          preferences.dispose();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          LocalTimezoneResolver.debugSystemTimeZoneReader =
              originalTimeZoneReader;
          SharedPreferencesStorePlatform.instance = previousStore;
          I18n.setLocale(originalLocale);
        }
      });
    });
  }
}
