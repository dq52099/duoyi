// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/diary_screen.dart';
import 'package:duoyi/widgets/surface_components.dart'
    show AppSectionHeader, appSurfaceStyleOf;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

class _SummaryScenario {
  final String name;
  final AppLocale locale;
  final Size size;
  final double scale;
  final String initialBrand;
  final String targetBrand;
  final bool expectStacked;
  final bool expectCardMetadataStacked;

  const _SummaryScenario({
    required this.name,
    required this.locale,
    required this.size,
    required this.scale,
    required this.initialBrand,
    required this.targetBrand,
    required this.expectStacked,
    required this.expectCardMetadataStacked,
  });
}

const _scenarios = <_SummaryScenario>[
  _SummaryScenario(
    name: 'en-portrait-320x844-scale2',
    locale: AppLocale.en,
    size: Size(320, 844),
    scale: 2.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    expectStacked: true,
    expectCardMetadataStacked: true,
  ),
  _SummaryScenario(
    name: 'en-landscape-844x390-scale1',
    locale: AppLocale.en,
    size: Size(844, 390),
    scale: 1.0,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    expectStacked: false,
    expectCardMetadataStacked: false,
  ),
  _SummaryScenario(
    name: 'zh-portrait-320x844-scale2',
    locale: AppLocale.zh,
    size: Size(320, 844),
    scale: 2.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    expectStacked: false,
    expectCardMetadataStacked: true,
  ),
];

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
      final file = File('$explicitDir/diary-summary-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void _assertNoWithinWordLineSplits(WidgetTester tester, Finder textFinder) {
  expect(textFinder, findsOneWidget);
  final element = tester.element(textFinder);
  final paragraph = element.renderObject! as RenderParagraph;
  final plainText = paragraph.text.toPlainText();
  final tokens = RegExp(
    r'[A-Za-z0-9%+.,−-]+|[^\x00-\x7F]',
  ).allMatches(plainText);
  for (final match in tokens) {
    final token = match.group(0)!;
    if (token.length <= 1) continue;
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: match.start, extentOffset: match.end),
    );
    expect(boxes, isNotEmpty, reason: 'Every metric token must be laid out');
    final lineTops = boxes.map((box) => box.top.round()).toSet();
    expect(
      lineTops.length,
      lessThanOrEqualTo(1),
      reason:
          'Token "$token" in "$plainText" split across multiple lines: tops=$lineTops',
    );
  }
}

Finder _diaryScrollable() => find
    .byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    )
    .first;

Future<void> _scrollToRecentHeader(WidgetTester tester) async {
  final recentTitleFinder = find.text(I18n.tr('diary.recent.title'));
  if (recentTitleFinder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      recentTitleFinder,
      150.0,
      scrollable: _diaryScrollable(),
      maxScrolls: 50,
    );
  }
  await tester.ensureVisible(recentTitleFinder);
  await tester.pumpAndSettle();
}

Future<void> _scrollToSummary(WidgetTester tester) async {
  final summaryTitleFinder = find.text(I18n.tr('diary.summary.title'));
  if (summaryTitleFinder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      summaryTitleFinder,
      -150.0,
      scrollable: _diaryScrollable(),
      maxScrolls: 50,
    );
  }
  await tester.ensureVisible(summaryTitleFinder);
  await tester.pumpAndSettle();
}

void _assertRecentHeaderRenderedSubtitle(
  WidgetTester tester,
  String expectedSubtitle,
) {
  final headerFinder = find.byWidgetPredicate(
    (widget) =>
        widget is AppSectionHeader &&
        widget.title == I18n.tr('diary.recent.title'),
  );
  expect(headerFinder, findsOneWidget);
  final headerWidget = tester.widget<AppSectionHeader>(headerFinder);
  expect(headerWidget.subtitle, equals(expectedSubtitle));

  final subtitleTexts = find.descendant(
    of: headerFinder,
    matching: find.byType(Text),
  );
  expect(subtitleTexts, findsNWidgets(2));
  final subtitleElement = tester.element(subtitleTexts.at(1));
  final paragraph = subtitleElement.renderObject! as RenderParagraph;
  expect(paragraph.text.toPlainText(), equals(expectedSubtitle));
  _assertNoWithinWordLineSplits(tester, subtitleTexts.at(1));
}

Future<void> _scrollToRecentCard(WidgetTester tester, String entryId) async {
  final cardFinder = find.byKey(ValueKey('diary_card_$entryId'));
  if (cardFinder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      cardFinder,
      150.0,
      scrollable: _diaryScrollable(),
      maxScrolls: 50,
    );
  }
  await tester.ensureVisible(cardFinder);
  await tester.pumpAndSettle();
}

void _assertDiaryCardMetadataVisibleAndBounded(
  WidgetTester tester,
  DiaryEntry entry, {
  required bool? expectStacked,
}) {
  final cardFinder = find.byKey(ValueKey('diary_card_${entry.id}'));
  expect(cardFinder, findsOneWidget);
  final cardRect = tester.getRect(cardFinder);
  expect(cardRect.width, greaterThan(0));
  expect(cardRect.height, greaterThan(0));

  final scrollableFinder = _diaryScrollable();
  final viewportRect = tester.getRect(scrollableFinder);

  void assertGlyphsVisible(Finder finder, String expected) {
    final paragraph = tester.renderObject<RenderParagraph>(finder);
    expect(paragraph.text.toPlainText(), expected);
    expect(paragraph.didExceedMaxLines, isFalse);
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: expected.length),
    );
    expect(boxes, isNotEmpty);
    for (final box in boxes) {
      final glyph = Rect.fromPoints(
        paragraph.localToGlobal(Offset(box.left, box.top)),
        paragraph.localToGlobal(Offset(box.right, box.bottom)),
      );
      for (final clip in [cardRect, viewportRect]) {
        expect(glyph.left, greaterThanOrEqualTo(clip.left - 1));
        expect(glyph.right, lessThanOrEqualTo(clip.right + 1));
        expect(glyph.top, greaterThanOrEqualTo(clip.top - 1));
        expect(glyph.bottom, lessThanOrEqualTo(clip.bottom + 1));
      }
    }
  }

  Rect? moodRect;
  if (entry.mood != null) {
    final moodFinder = find.descendant(
      of: cardFinder,
      matching: find.text(entry.mood!.emoji),
    );
    expect(moodFinder, findsOneWidget);
    assertGlyphsVisible(moodFinder, entry.mood!.emoji);
    moodRect = tester.getRect(moodFinder);
    expect(moodRect.width, greaterThan(0));
    expect(moodRect.height, greaterThan(0));
    expect(moodRect.left, greaterThanOrEqualTo(cardRect.left - 1.0));
    expect(moodRect.right, lessThanOrEqualTo(cardRect.right + 1.0));
    expect(moodRect.left, greaterThanOrEqualTo(viewportRect.left - 1.0));
    expect(moodRect.right, lessThanOrEqualTo(viewportRect.right + 1.0));
    expect(moodRect.top, greaterThanOrEqualTo(viewportRect.top - 1.0));
    expect(moodRect.bottom, lessThanOrEqualTo(viewportRect.bottom + 1.0));
  }

  Rect? weatherRect;
  if (entry.weather != null) {
    final weatherFinder = find.descendant(
      of: cardFinder,
      matching: find.text(entry.weather!.emoji),
    );
    expect(weatherFinder, findsOneWidget);
    assertGlyphsVisible(weatherFinder, entry.weather!.emoji);
    weatherRect = tester.getRect(weatherFinder);
    expect(weatherRect.width, greaterThan(0));
    expect(weatherRect.height, greaterThan(0));
    expect(weatherRect.left, greaterThanOrEqualTo(cardRect.left - 1.0));
    expect(weatherRect.right, lessThanOrEqualTo(cardRect.right + 1.0));
    expect(weatherRect.left, greaterThanOrEqualTo(viewportRect.left - 1.0));
    expect(weatherRect.right, lessThanOrEqualTo(viewportRect.right + 1.0));
    expect(weatherRect.top, greaterThanOrEqualTo(viewportRect.top - 1.0));
    expect(weatherRect.bottom, lessThanOrEqualTo(viewportRect.bottom + 1.0));
  }

  final timeStr = I18nDateFormat.time(entry.updatedAt);
  final timeFinder = find.descendant(
    of: cardFinder,
    matching: find.text(timeStr),
  );
  expect(timeFinder, findsOneWidget);
  assertGlyphsVisible(timeFinder, timeStr);
  final timeElement = tester.element(timeFinder);
  final timeParagraph = timeElement.renderObject! as RenderParagraph;
  expect(timeParagraph.text.toPlainText(), equals(timeStr));
  expect(
    timeParagraph.didExceedMaxLines,
    isFalse,
    reason: 'Timestamp "$timeStr" must not exceed max lines',
  );

  final timeRect = tester.getRect(timeFinder);
  expect(timeRect.left, greaterThanOrEqualTo(cardRect.left - 1.0));
  expect(
    timeRect.right,
    lessThanOrEqualTo(cardRect.right + 1.0),
    reason:
        'Time string "$timeStr" must be fully bounded within card (cardRight=${cardRect.right}, timeRight=${timeRect.right})',
  );
  expect(timeRect.left, greaterThanOrEqualTo(viewportRect.left - 1.0));
  expect(timeRect.right, lessThanOrEqualTo(viewportRect.right + 1.0));
  expect(timeRect.top, greaterThanOrEqualTo(viewportRect.top - 1.0));
  expect(timeRect.bottom, lessThanOrEqualTo(viewportRect.bottom + 1.0));

  final lastBadgeRect = weatherRect ?? moodRect;
  if (lastBadgeRect != null) {
    if (expectStacked == true) {
      expect(
        timeRect.top,
        greaterThanOrEqualTo(lastBadgeRect.bottom - 1.0),
        reason:
            'In stacked portrait2 layout, timestamp must render below badges (badgeBottom=${lastBadgeRect.bottom}, timeTop=${timeRect.top})',
      );
    } else if (expectStacked == false) {
      expect(
        timeRect.top,
        lessThan(lastBadgeRect.bottom),
        reason:
            'In scale1 wide layout, timestamp must share the same horizontal row as badges',
      );
      expect(
        timeRect.left,
        greaterThanOrEqualTo(lastBadgeRect.right - 1.0),
        reason:
            'In scale1 wide layout, timestamp must be placed to the right of badges',
      );
    } else {
      // Older dates can use a narrower date badge and leave enough space for
      // metadata on one row. Both layouts must keep the complete labels apart.
      final sharesRow = timeRect.top < lastBadgeRect.bottom &&
          timeRect.bottom > lastBadgeRect.top;
      expect(
        sharesRow
            ? timeRect.left >= lastBadgeRect.right
            : timeRect.top >= lastBadgeRect.bottom,
        isTrue,
        reason: 'Date-dependent metadata must remain separated and readable',
      );
    }
  }
}

void _assertAllSummaryMetricsPresentAndUnsplit(
  WidgetTester tester,
  DiaryProvider diaries,
) {
  final isEn = I18n.current == AppLocale.en;
  final String expectedTotal = isEn
      ? (diaries.totalCount == 1 ? '1 entry' : '${diaries.totalCount} entries')
      : '${diaries.totalCount} 篇';
  final String expectedMonth = isEn
      ? (diaries.thisMonthCount == 1
          ? '1 entry'
          : '${diaries.thisMonthCount} entries')
      : '${diaries.thisMonthCount} 篇';
  final String expectedStreak = isEn
      ? (diaries.currentStreak == 1
          ? '1 day'
          : '${diaries.currentStreak} days')
      : '${diaries.currentStreak} 天';

  if (isEn && diaries.totalCount == 1) {
    expect(expectedTotal, equals('1 entry'));
    expect(expectedMonth, equals('1 entry'));
    expect(expectedStreak, equals('1 day'));
  }

  final totalTitleFinder = find.text(I18n.tr('diary.summary.total'));
  final monthTitleFinder = find.text(I18n.tr('diary.summary.this_month'));
  final streakTitleFinder = find.text(I18n.tr('diary.summary.streak'));
  Finder valueFor(Finder title, String value) {
    Element? metricColumn;
    tester.element(title).visitAncestorElements((element) {
      if (element.widget is Column) {
        metricColumn = element;
        return false;
      }
      return true;
    });
    expect(metricColumn, isNotNull);
    return find.descendant(
      of: find.byElementPredicate(
        (element) => identical(element, metricColumn),
      ),
      matching: find.text(value),
    );
  }

  final totalValueFinder = valueFor(totalTitleFinder, expectedTotal);
  final monthValueFinder = valueFor(monthTitleFinder, expectedMonth);
  final streakValueFinder = valueFor(streakTitleFinder, expectedStreak);

  _assertNoWithinWordLineSplits(tester, totalTitleFinder);
  _assertNoWithinWordLineSplits(tester, totalValueFinder);
  _assertNoWithinWordLineSplits(tester, monthTitleFinder);
  _assertNoWithinWordLineSplits(tester, monthValueFinder);
  _assertNoWithinWordLineSplits(tester, streakTitleFinder);
  _assertNoWithinWordLineSplits(tester, streakValueFinder);
}

void main() {
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets(
      'diary summary responsive metric reflow and live brand priority ${scenario.name}',
      (tester) async {
        final baselineDate = DateTime.now();
        final baselineEntry = DiaryEntry(
          id: 'synthetic-diary-${scenario.name}',
          date: baselineDate,
          content: 'Synthetic baseline diary entry content',
          mood: Mood.good,
          weather: Weather.sunny,
          tags: const ['test-tag'],
        );
        final baselineSerialized = jsonEncode(baselineEntry.toJson());

        final initialPrefs = <String, Object>{
          'active_brand': scenario.initialBrand,
          'theme_shop_state': jsonEncode({
            'activeBrand': scenario.initialBrand,
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          }),
          'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          'duoyi_diary': [baselineSerialized],
          'flutter.active_brand': scenario.initialBrand,
          'flutter.theme_shop_state': jsonEncode({
            'activeBrand': scenario.initialBrand,
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          }),
          'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          'flutter.duoyi_diary': [baselineSerialized],
        };

        SharedPreferences.setMockInitialValues(initialPrefs);

        late DiaryProvider diaries;
        late ThemeProvider theme;
        late PreferencesProvider preferences;

        I18n.setLocale(scenario.locale);

        await tester.runAsync(() async {
          diaries = DiaryProvider();
          theme = ThemeProvider();
          preferences = PreferencesProvider();
          await theme.loadFromStorage();
          await preferences.loadFromStorage();
          await diaries.loadFromStorage();
          await loadWeeklyReviewScreenshotFonts();
        });

        expect(diaries.entries, hasLength(1));
        expect(theme.brand.id, scenario.initialBrand);

        tester.view.physicalSize = scenario.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

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
                      home: const DiaryScreen(),
                    );
                  },
                );
              },
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Verify DiaryScreen is mounted
        expect(find.byType(DiaryScreen), findsOneWidget);
        final originalElement = tester.element(find.byType(DiaryScreen));
        final originalRoute = ModalRoute.of(
          tester.element(find.byType(DiaryScreen)),
        );
        expect(find.text(I18n.tr('diary.title')), findsOneWidget);
        expect(find.text(I18n.tr('diary.summary.title')), findsOneWidget);

        // 1. Initial brand verification
        final initialBrand = AppBrands.byId(scenario.initialBrand);
        final totalTitleFinder = find.text(I18n.tr('diary.summary.total'));
        final monthTitleFinder = find.text(I18n.tr('diary.summary.this_month'));
        expect(
          Theme.of(tester.element(totalTitleFinder)).colorScheme.primary,
          equals(initialBrand.theme.colorScheme.primary),
        );
        expect(
          appSurfaceStyleOf(tester.element(totalTitleFinder)),
          equals(
            scenario.initialBrand == 'liquidGlass'
                ? AppSurfaceStyle.liquidGlass
                : AppSurfaceStyle.ios,
          ),
        );

        // Verify layout geometry arrangement: compact row vs stacked column
        final totalRect = tester.getRect(totalTitleFinder);
        final monthRect = tester.getRect(monthTitleFinder);
        if (scenario.expectStacked) {
          expect(
            monthRect.top,
            greaterThanOrEqualTo(totalRect.bottom),
            reason:
                'Narrow English metrics must reflow into vertically stacked rows',
          );
        } else {
          expect(
            monthRect.top,
            closeTo(totalRect.top, 3.0),
            reason:
                'Wide screen compact metrics must be horizontally aligned in a row',
          );
        }

        // Prove all metrics present and no within-word line splits under initial theme
        _assertAllSummaryMetricsPresentAndUnsplit(tester, diaries);
        await _capture(
          tester,
          boundary,
          '${scenario.name}-01-${scenario.initialBrand}',
        );

        // 2. Live switch to targetBrand on the same mounted route
        await tester.runAsync(() async {
          final switched = await theme.setBrand(scenario.targetBrand);
          expect(switched, isTrue);
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // 3. Target brand verification on the same route
        final targetBrand = AppBrands.byId(scenario.targetBrand);
        expect(theme.brand.id, scenario.targetBrand);
        expect(tester.element(find.byType(DiaryScreen)), same(originalElement));
        expect(
          ModalRoute.of(tester.element(find.byType(DiaryScreen))),
          same(originalRoute),
        );
        expect(
          Theme.of(tester.element(totalTitleFinder)).colorScheme.primary,
          equals(targetBrand.theme.colorScheme.primary),
        );
        expect(
          appSurfaceStyleOf(tester.element(totalTitleFinder)),
          equals(
            scenario.targetBrand == 'liquidGlass'
                ? AppSurfaceStyle.liquidGlass
                : AppSurfaceStyle.ios,
          ),
        );

        // Re-verify layout geometry arrangement after theme switch
        final totalRectAfterSwitch = tester.getRect(totalTitleFinder);
        final monthRectAfterSwitch = tester.getRect(monthTitleFinder);
        if (scenario.expectStacked) {
          expect(
            monthRectAfterSwitch.top,
            greaterThanOrEqualTo(totalRectAfterSwitch.bottom),
            reason: 'Layout reflow must be retained across theme switch',
          );
        } else {
          expect(
            monthRectAfterSwitch.top,
            closeTo(totalRectAfterSwitch.top, 3.0),
            reason: 'Compact layout must be retained across theme switch',
          );
        }

        // Prove all metrics still present and no within-word line splits after theme switch
        _assertAllSummaryMetricsPresentAndUnsplit(tester, diaries);
        await _capture(
          tester,
          boundary,
          '${scenario.name}-02-${scenario.targetBrand}',
        );

        // Verify recent card metadata and bounds under target brand
        await _scrollToRecentCard(tester, baselineEntry.id);
        _assertDiaryCardMetadataVisibleAndBounded(
          tester,
          baselineEntry,
          expectStacked: scenario.expectCardMetadataStacked,
        );
        await _capture(
          tester,
          boundary,
          '${scenario.name}-02b-recent-card-${scenario.targetBrand}',
        );
        await _scrollToSummary(tester);
        expect(find.text(I18n.tr('diary.summary.title')), findsOneWidget);

        await tester.runAsync(() => theme.setBrand(scenario.initialBrand));
        await tester.pumpAndSettle();
        expect(tester.element(find.byType(DiaryScreen)), same(originalElement));
        expect(
          ModalRoute.of(tester.element(find.byType(DiaryScreen))),
          same(originalRoute),
        );
        _assertAllSummaryMetricsPresentAndUnsplit(tester, diaries);
        await _capture(
          tester,
          boundary,
          '${scenario.name}-03-returned-${scenario.initialBrand}',
        );
        expect(tester.takeException(), isNull);

        // Verify recent card metadata and bounds under returned initial brand
        await _scrollToRecentCard(tester, baselineEntry.id);
        _assertDiaryCardMetadataVisibleAndBounded(
          tester,
          baselineEntry,
          expectStacked: scenario.expectCardMetadataStacked,
        );
        await _capture(
          tester,
          boundary,
          '${scenario.name}-04-recent-card-${scenario.initialBrand}',
        );
        await _scrollToSummary(tester);
        expect(find.text(I18n.tr('diary.summary.title')), findsOneWidget);

        // 4. Verify count-dependent singular/plural on real rendered UI across 1, 2, and 4 counts.
        final isEn = scenario.locale == AppLocale.en;

        // --- Count 1 Verification ---
        // Scroll to recent header to bring it into view and assert rendered subtitle.
        await _scrollToRecentHeader(tester);
        _assertRecentHeaderRenderedSubtitle(
          tester,
          isEn ? '1 entry' : '1 篇记录',
        );

        // Return scroll to summary card before asserting summary metrics.
        await _scrollToSummary(tester);
        expect(find.text(I18n.tr('diary.summary.title')), findsOneWidget);
        _assertAllSummaryMetricsPresentAndUnsplit(tester, diaries);

        // --- Count 2 Verification ---
        // Mutate baseline entry date to 60 days ago and add a second 61-day-old entry:
        // totalCount: 2 (2+ plural), thisMonthCount: 0 (0 plural), currentStreak: 0 (0 plural).
        final oldEntry1 = DiaryEntry(
          id: baselineEntry.id,
          date: baselineDate.subtract(const Duration(days: 60)),
          content: 'Synthetic baseline diary entry content',
          mood: Mood.good,
          weather: Weather.sunny,
          tags: const ['test-tag'],
        );
        final oldEntry2 = DiaryEntry(
          id: 'synthetic-diary-old-2-${scenario.name}',
          date: baselineDate.subtract(const Duration(days: 61)),
          content: 'Synthetic secondary old diary entry',
          mood: Mood.okay,
          weather: Weather.cloudy,
          tags: const ['test-tag-2'],
        );
        await tester.runAsync(() async {
          await diaries.addOrUpdate(oldEntry1);
          await diaries.addOrUpdate(oldEntry2);
        });
        await tester.pumpAndSettle();

        expect(diaries.totalCount, 2);
        expect(diaries.thisMonthCount, 0);
        expect(diaries.currentStreak, 0);

        // Summary is at top: assert 2+ total, 0 this-month, and 0 streak metrics
        _assertAllSummaryMetricsPresentAndUnsplit(tester, diaries);

        // Scroll to recent header and assert rendered subtitle at count 2
        await _scrollToRecentHeader(tester);
        _assertRecentHeaderRenderedSubtitle(
          tester,
          isEn ? '2 entries' : '2 篇记录',
        );

        // Verify recent card metadata bounds for oldEntry1
        await _scrollToRecentCard(tester, oldEntry1.id);
        _assertDiaryCardMetadataVisibleAndBounded(
          tester,
          oldEntry1,
          expectStacked: null,
        );

        // Return scroll to summary card
        await _scrollToSummary(tester);
        expect(find.text(I18n.tr('diary.summary.title')), findsOneWidget);

        // --- Count 4 Verification ---
        // Add today and yesterday entries to test consecutive streak of 2 days (2+ plural)
        // and total count of 4 (2+ plural).
        final todayEntry = DiaryEntry(
          id: 'synthetic-diary-today-${scenario.name}',
          date: baselineDate,
          content: 'Today content',
          mood: Mood.good,
          weather: Weather.sunny,
        );
        final yesterdayEntry = DiaryEntry(
          id: 'synthetic-diary-yesterday-${scenario.name}',
          date: baselineDate.subtract(const Duration(days: 1)),
          content: 'Yesterday content',
          mood: Mood.good,
          weather: Weather.sunny,
        );
        await tester.runAsync(() async {
          await diaries.addOrUpdate(todayEntry);
          await diaries.addOrUpdate(yesterdayEntry);
        });
        await tester.pumpAndSettle();

        expect(diaries.totalCount, 4);
        expect(diaries.currentStreak, 2);

        // Summary is at top: assert 4 total (2+) and 2 days streak (2+)
        _assertAllSummaryMetricsPresentAndUnsplit(tester, diaries);

        // Scroll to recent header and assert rendered subtitle at count 4
        await _scrollToRecentHeader(tester);
        _assertRecentHeaderRenderedSubtitle(
          tester,
          isEn ? '4 entries' : '4 篇记录',
        );

        // Verify recent card metadata bounds for todayEntry
        await _scrollToRecentCard(tester, todayEntry.id);
        _assertDiaryCardMetadataVisibleAndBounded(
          tester,
          todayEntry,
          expectStacked: scenario.expectCardMetadataStacked,
        );

        // Return scroll to summary card
        await _scrollToSummary(tester);
        expect(find.text(I18n.tr('diary.summary.title')), findsOneWidget);

        expect(tester.element(find.byType(DiaryScreen)), same(originalElement));
        expect(
          ModalRoute.of(tester.element(find.byType(DiaryScreen))),
          same(originalRoute),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        diaries.dispose();
        theme.dispose();
        preferences.dispose();
      },
    );
  }
}
