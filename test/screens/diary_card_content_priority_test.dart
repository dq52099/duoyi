// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/almanac_locale_format.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/core/lunar_calendar.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/diary_screen.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandBackground;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/secondary_route_render_probe.dart'
    show RouteProbeNonlinearScaler;
import '../support/weekly_review_screenshot_font.dart';

class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore(super.data) : super.withData();
  int diaryWrites = 0;

  static bool _isDiaryKey(String key) =>
      key == 'duoyi_diary' ||
      key == 'flutter.duoyi_diary' ||
      key.endsWith('.duoyi_diary');

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (_isDiaryKey(key)) {
      diaryWrites++;
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    if (_isDiaryKey(key)) {
      diaryWrites++;
    }
    return super.remove(key);
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

Finder _diaryScrollable() => find
    .byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    )
    .first;

Future<void> _scrollToCard(WidgetTester tester, String entryId) async {
  final cardFinder = find.byKey(ValueKey('diary_card_$entryId'));
  final scrollableFinder = _diaryScrollable();
  final scrollState = tester.state<ScrollableState>(scrollableFinder);

  // If card is not in tree and we are scrolled down (e.g. after maxScrollExtent step),
  // reset to top so we reliably scan forward from the beginning of the list.
  if (cardFinder.evaluate().isEmpty && scrollState.position.pixels > 0) {
    scrollState.position.jumpTo(0);
    await _boundedPumpAndSettle(tester);
  }

  // Scroll down incrementally until card is mounted
  var scrolls = 0;
  while (cardFinder.evaluate().isEmpty &&
      scrollState.position.pixels < scrollState.position.maxScrollExtent &&
      scrolls < 50) {
    scrolls++;
    final nextPixels = (scrollState.position.pixels + 100.0)
        .clamp(0.0, scrollState.position.maxScrollExtent);
    if (nextPixels == scrollState.position.pixels) break;
    scrollState.position.jumpTo(nextPixels);
    await _boundedPumpAndSettle(tester);
  }

  expect(
    cardFinder,
    findsOneWidget,
    reason: 'Card diary_card_$entryId must be mounted in scrollable',
  );

  // Adjust scroll offset so card top and title are comfortably in view
  final viewportRect = tester.getRect(scrollableFinder);
  final cardRect = tester.getRect(cardFinder);

  if (cardRect.top < viewportRect.top) {
    final delta = cardRect.top - (viewportRect.top + 8.0);
    final targetPixels = (scrollState.position.pixels + delta).clamp(
      scrollState.position.minScrollExtent,
      scrollState.position.maxScrollExtent,
    );
    scrollState.position.jumpTo(targetPixels);
    await _boundedPumpAndSettle(tester);
  } else if (cardRect.top > viewportRect.bottom - 80.0) {
    final delta = cardRect.top - (viewportRect.top + 16.0);
    final targetPixels = (scrollState.position.pixels + delta).clamp(
      scrollState.position.minScrollExtent,
      scrollState.position.maxScrollExtent,
    );
    scrollState.position.jumpTo(targetPixels);
    await _boundedPumpAndSettle(tester);
  }
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
    expect(boxes, isNotEmpty, reason: 'Every token must be laid out');
    final lineTops = boxes.map((box) => box.top.round()).toSet();
    expect(
      lineTops.length,
      lessThanOrEqualTo(1),
      reason:
          'Token "$token" in "$plainText" split across multiple lines: tops=$lineTops',
    );
  }
}

void _assertTitleNoWithinWordLineSplits(
  WidgetTester tester,
  Finder titleFinder,
  Finder cardFinder,
) {
  expect(titleFinder, findsOneWidget);
  final element = tester.element(titleFinder);
  final paragraph = element.renderObject! as RenderParagraph;
  final plainText = paragraph.text.toPlainText();
  final cardRect = tester.getRect(cardFinder);
  final cardContentWidth = cardRect.width - 48.0;

  final tokens = RegExp(r'[A-Za-z0-9%+.,−-]+').allMatches(plainText);
  for (final match in tokens) {
    final token = match.group(0)!;
    if (token.length <= 1) continue;
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: match.start, extentOffset: match.end),
    );
    expect(boxes, isNotEmpty, reason: 'Every token must be laid out');
    final tokenWidth = boxes
        .map((b) => b.toRect().width)
        .reduce((a, b) => a + b);
    if (tokenWidth <= cardContentWidth) {
      final lineTops = boxes.map((box) => box.top.round()).toSet();
      expect(
        lineTops.length,
        lessThanOrEqualTo(1),
        reason:
            'Token "$token" in "$plainText" split across multiple lines: tops=$lineTops',
      );
    }
  }
}

void _assertCompleteCardTitle(
  WidgetTester tester,
  Finder cardFinder,
  String expectedTitle,
) {
  final titleFinder = find.descendant(
    of: cardFinder,
    matching: find.text(expectedTitle),
  );
  expect(titleFinder, findsOneWidget);

  final paragraph = tester.renderObject<RenderParagraph>(titleFinder);
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: 'Card title must not be truncated: "$expectedTitle"',
  );
  expect(
    paragraph.text.toPlainText(),
    equals(expectedTitle),
    reason: 'Card title text must be fully preserved',
  );

  final cardRect = tester.getRect(cardFinder);
  final titleRect = tester.getRect(titleFinder);
  final scrollableFinder = _diaryScrollable();
  final viewportRect = tester.getRect(scrollableFinder);

  // Paragraph itself must remain within card bounds
  expect(titleRect.left, greaterThanOrEqualTo(cardRect.left - 1.0));
  expect(titleRect.right, lessThanOrEqualTo(cardRect.right + 1.0));

  // Assess actual visible glyph bounds per non-whitespace word to distinguish
  // rendered glyph bounds from line-box trailing whitespace overhang at wrap points.
  final wordMatches = RegExp(r'\S+').allMatches(expectedTitle);
  expect(wordMatches, isNotEmpty);
  final titleSize = paragraph.size;
  for (final match in wordMatches) {
    final word = match.group(0)!;
    final wordBoxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: match.start, extentOffset: match.end),
    );
    expect(
      wordBoxes,
      isNotEmpty,
      reason: 'Glyphs must be laid out for word "$word"',
    );
    for (final box in wordBoxes) {
      expect(
        box.left,
        greaterThanOrEqualTo(-1.0),
        reason: 'Word "$word" glyph left must stay within layout bounds',
      );
      expect(
        box.right,
        lessThanOrEqualTo(titleSize.width + 1.0),
        reason: 'Word "$word" glyph right must stay within layout bounds',
      );

      final globalLeft = titleRect.left + box.left;
      final globalRight = titleRect.left + box.right;
      expect(
        globalLeft,
        greaterThanOrEqualTo(cardRect.left - 1.0),
        reason: 'Glyph box for "$word" must not clip left of card',
      );
      expect(
        globalRight,
        lessThanOrEqualTo(cardRect.right + 1.0),
        reason: 'Glyph box for "$word" must not clip right of card',
      );
      expect(
        globalLeft,
        greaterThanOrEqualTo(viewportRect.left - 1.0),
        reason: 'Glyph box for "$word" must remain within viewport bounds',
      );
      expect(
        globalRight,
        lessThanOrEqualTo(viewportRect.right + 1.0),
        reason: 'Glyph box for "$word" must remain within viewport bounds',
      );
    }
  }

  _assertTitleNoWithinWordLineSplits(tester, titleFinder, cardFinder);
}

void _assertUnsplitDateBadge(
  WidgetTester tester,
  Finder cardFinder, {
  required String dateText,
  required String lunarText,
}) {
  final dateFinder = find.descendant(
    of: cardFinder,
    matching: find.text(dateText),
  );
  expect(dateFinder, findsOneWidget);

  final lunarFinder = find.descendant(
    of: cardFinder,
    matching: find.text(lunarText),
  );
  expect(lunarFinder, findsOneWidget);

  final badgeFinder = find
      .ancestor(
        of: dateFinder,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).borderRadius != null,
        ),
      )
      .first;
  expect(badgeFinder, findsOneWidget);
  final badgeRect = tester.getRect(badgeFinder);

  final scrollableFinder = _diaryScrollable();
  final viewportRect = tester.getRect(scrollableFinder);

  final dateWidget = tester.widget<Text>(dateFinder);
  expect(dateWidget.style?.fontSize, equals(15.0));

  final lunarWidget = tester.widget<Text>(lunarFinder);
  expect(lunarWidget.style?.fontSize, equals(10.0));

  final expectedScaler = MediaQuery.textScalerOf(tester.element(dateFinder));

  void assertGlyphBoxes(Finder finder, String text) {
    final paragraph = tester.renderObject<RenderParagraph>(finder);
    expect(paragraph.text.toPlainText(), equals(text));
    expect(paragraph.textScaler, equals(expectedScaler));

    final wordMatches = RegExp(r'\S+').allMatches(text);
    expect(wordMatches, isNotEmpty);
    final textRect = tester.getRect(finder);
    for (final match in wordMatches) {
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: match.start, extentOffset: match.end),
      );
      expect(
        boxes,
        isNotEmpty,
        reason: 'Glyphs must be laid out for ${match.group(0)}',
      );
      for (final box in boxes) {
        final globalLeft = textRect.left + box.left;
        final globalRight = textRect.left + box.right;
        expect(
          globalLeft,
          greaterThanOrEqualTo(badgeRect.left - 1.0),
          reason: 'Glyph box left must not clip outside badge',
        );
        expect(
          globalRight,
          lessThanOrEqualTo(badgeRect.right + 1.0),
          reason: 'Glyph box right must not clip outside badge',
        );
        expect(
          globalLeft,
          greaterThanOrEqualTo(viewportRect.left - 1.0),
          reason: 'Glyph box left must be within viewport',
        );
        expect(
          globalRight,
          lessThanOrEqualTo(viewportRect.right + 1.0),
          reason: 'Glyph box right must be within viewport',
        );
      }
    }
    _assertNoWithinWordLineSplits(tester, finder);
  }

  assertGlyphBoxes(dateFinder, dateText);
  assertGlyphBoxes(lunarFinder, lunarText);
}

void _assertBoundedPreview(
  WidgetTester tester,
  Finder cardFinder,
  DiaryEntry entry,
) {
  if (entry.preview.isEmpty) return;
  final previewFinder = find.descendant(
    of: cardFinder,
    matching: find.text(entry.preview),
  );
  expect(previewFinder, findsOneWidget);
  final previewWidget = tester.widget<Text>(previewFinder);
  expect(
    previewWidget.maxLines,
    equals(3),
    reason: 'Body preview is intentionally bounded to 3 lines',
  );
  expect(
    previewWidget.overflow,
    equals(TextOverflow.ellipsis),
    reason: 'Body preview intentionally uses ellipsis for excess content',
  );
}

void _assertCardMetadataBounded(
  WidgetTester tester,
  Finder cardFinder,
  DiaryEntry entry, {
  required bool expectHorizontal,
}) {
  final cardRect = tester.getRect(cardFinder);
  final scrollableFinder = _diaryScrollable();
  final viewportRect = tester.getRect(scrollableFinder);

  Rect? moodRect;
  if (entry.mood != null) {
    final moodFinder = find.descendant(
      of: cardFinder,
      matching: find.text(entry.mood!.emoji),
    );
    expect(moodFinder, findsOneWidget);
    moodRect = tester.getRect(moodFinder);
    expect(moodRect.left, greaterThanOrEqualTo(cardRect.left - 1.0));
    expect(moodRect.right, lessThanOrEqualTo(cardRect.right + 1.0));
  }

  Rect? weatherRect;
  if (entry.weather != null) {
    final weatherFinder = find.descendant(
      of: cardFinder,
      matching: find.text(entry.weather!.emoji),
    );
    expect(weatherFinder, findsOneWidget);
    weatherRect = tester.getRect(weatherFinder);
    expect(weatherRect.left, greaterThanOrEqualTo(cardRect.left - 1.0));
    expect(weatherRect.right, lessThanOrEqualTo(cardRect.right + 1.0));
  }

  final timeStr = I18nDateFormat.time(entry.updatedAt);
  final timeFinder = find.descendant(
    of: cardFinder,
    matching: find.text(timeStr),
  );
  expect(timeFinder, findsOneWidget);
  final timeRect = tester.getRect(timeFinder);
  expect(timeRect.left, greaterThanOrEqualTo(cardRect.left - 1.0));
  expect(timeRect.right, lessThanOrEqualTo(cardRect.right + 1.0));
  expect(timeRect.left, greaterThanOrEqualTo(viewportRect.left - 1.0));
  expect(timeRect.right, lessThanOrEqualTo(viewportRect.right + 1.0));

  final lastBadgeRect = weatherRect ?? moodRect;
  if (lastBadgeRect != null) {
    if (expectHorizontal) {
      expect(
        timeRect.top,
        lessThan(lastBadgeRect.bottom),
        reason:
            'In wide horizontal arrangement, timestamp must share the horizontal row with badges',
      );
      expect(
        timeRect.left,
        greaterThanOrEqualTo(lastBadgeRect.right - 1.0),
        reason:
            'In wide horizontal arrangement, timestamp must render to the right of badges',
      );
    } else {
      expect(timeRect.left, greaterThanOrEqualTo(cardRect.left - 1.0));
      expect(timeRect.right, lessThanOrEqualTo(cardRect.right + 1.0));
    }
  }
}

Future<void> _assertLastCardReachableAboveFabAtMaxScroll(
  WidgetTester tester, {
  required DiaryProvider diaryProvider,
  required String lastEntryId,
}) async {
  expect(diaryProvider.entries, isNotEmpty);
  expect(
    diaryProvider.entries.last.id,
    equals(lastEntryId),
    reason: 'Verified last entry in descending date sorted order',
  );

  final scrollableFinder = _diaryScrollable();
  final scrollState = tester.state<ScrollableState>(scrollableFinder);

  scrollState.position.jumpTo(scrollState.position.maxScrollExtent);
  await _boundedPumpAndSettle(tester);

  final lastCardFinder = find.byKey(ValueKey('diary_card_$lastEntryId'));
  expect(lastCardFinder, findsOneWidget);
  final lastCardRect = tester.getRect(lastCardFinder);

  final fabFinder = find.byType(FloatingActionButton);
  expect(fabFinder, findsOneWidget);
  final fabRect = tester.getRect(fabFinder);

  expect(
    lastCardRect.bottom,
    lessThanOrEqualTo(fabRect.top + 1.0),
    reason:
        'Last card bottom (${lastCardRect.bottom}) must remain clear above FAB top (${fabRect.top}) at max scroll',
  );

  await tester.tap(lastCardFinder);
  await _boundedPumpAndSettle(tester);
  expect(find.byType(DiaryEditScreen), findsOneWidget);

  Navigator.of(tester.element(find.byType(DiaryEditScreen))).pop();
  await _boundedPumpAndSettle(tester);
  expect(find.byType(DiaryScreen), findsOneWidget);
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
      final file = File('$explicitDir/diary-card-priority-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

class _CardPriorityScenario {
  final String name;
  final Size size;
  final double scale;
  final double dpr;
  final String initialBrand;
  final String targetBrand;
  final AppLocale initialLocale;
  final AppLocale targetLocale;
  final bool expectHorizontalMetadata;

  const _CardPriorityScenario({
    required this.name,
    required this.size,
    required this.scale,
    this.dpr = 1.0,
    required this.initialBrand,
    required this.targetBrand,
    required this.initialLocale,
    required this.targetLocale,
    required this.expectHorizontalMetadata,
  });
}

const _scenarios = <_CardPriorityScenario>[
  _CardPriorityScenario(
    name: 'en-portrait-320x844-scale2',
    size: Size(320, 844),
    scale: 2.0,
    dpr: 1.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    initialLocale: AppLocale.en,
    targetLocale: AppLocale.zh,
    expectHorizontalMetadata: false,
  ),
  _CardPriorityScenario(
    name: 'zh-portrait-320x844-scale2',
    size: Size(320, 844),
    scale: 2.0,
    dpr: 1.0,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    initialLocale: AppLocale.zh,
    targetLocale: AppLocale.en,
    expectHorizontalMetadata: false,
  ),
  _CardPriorityScenario(
    name: 'en-landscape-844x390-scale1',
    size: Size(844, 390),
    scale: 1.0,
    dpr: 1.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    initialLocale: AppLocale.en,
    targetLocale: AppLocale.zh,
    expectHorizontalMetadata: true,
  ),
  _CardPriorityScenario(
    name: 'zh-ordinary-390x844-scale1',
    size: Size(390, 844),
    scale: 1.0,
    dpr: 1.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    initialLocale: AppLocale.zh,
    targetLocale: AppLocale.en,
    expectHorizontalMetadata: true,
  ),
  _CardPriorityScenario(
    name: 'en-wide-1024x768-scale1',
    size: Size(1024, 768),
    scale: 1.0,
    dpr: 1.0,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    initialLocale: AppLocale.en,
    targetLocale: AppLocale.zh,
    expectHorizontalMetadata: true,
  ),
  _CardPriorityScenario(
    name: 'zh-nonlinear-332x844',
    size: Size(332, 844),
    scale: -1.0,
    dpr: 1.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    initialLocale: AppLocale.zh,
    targetLocale: AppLocale.en,
    expectHorizontalMetadata: false,
  ),
];

void main() {
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets('Diary list-card content priority scenario: ${scenario.name}', (
      tester,
    ) async {
      final originalDisableShadows = debugDisableShadows;
      final originalTimeZoneReader =
          LocalTimezoneResolver.debugSystemTimeZoneReader;
      final previousStore = SharedPreferencesStorePlatform.instance;

      DiaryProvider? diaries;
      ThemeProvider? theme;
      PreferencesProvider? preferences;

      try {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final lunarToday = LunarCalendar.fromSolar(today);
        final dateYesterday = today.subtract(const Duration(days: 1));
        final dateOlder = today.subtract(const Duration(days: 2));

        const longTitleEn =
            'A comprehensive journey through morning thoughts, observations, reflections, and evening discoveries';
        const longTitleZh =
            '今天在清晨漫步与傍晚复盘中记录的详尽心得体会与深度思考';

        const longBodyEn =
            'First line of body text.\nSecond line exploring notes.\nThird line with extra detail.\nFourth line ensuring overflow beyond the intentional 3 lines.';
        const longBodyZh =
            '第一行日记正文记录生活细节。\n第二行深入阐述工作体会。\n第三行总结思考与行动。\n第四行确认超出三行故意截断。';

        final entry1 = DiaryEntry(
          id: 'card-entry-1',
          date: today,
          content: scenario.initialLocale == AppLocale.en
              ? '$longTitleEn\n$longBodyEn'
              : '$longTitleZh\n$longBodyZh',
          mood: Mood.good,
          weather: Weather.sunny,
          tags: const ['focus', 'priority'],
        );

        final entry2 = DiaryEntry(
          id: 'card-entry-2',
          date: dateYesterday,
          content: scenario.initialLocale == AppLocale.en
              ? 'Middle diary entry content\nSome brief thoughts.'
              : '中等长度日记记录\n记录日常。',
          mood: Mood.awesome,
          weather: Weather.cloudy,
          tags: const ['life'],
        );

        final entry3 = DiaryEntry(
          id: 'card-entry-3',
          date: dateOlder,
          content: scenario.initialLocale == AppLocale.en
              ? 'Last card for reachability testing\nEnsuring FAB clearance.'
              : '最后一张卡片用于验证触达性\n确保FAB不遮挡。',
          mood: Mood.okay,
          weather: Weather.rain,
          tags: const ['test'],
        );

        final entries = [entry1, entry2, entry3];
        final serialized = entries
            .map((e) => jsonEncode(e.toJson()))
            .toList(growable: false);

        final rawPrefs = <String, Object>{
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

        // Reconcile mock store and cache without dropping prefixed entries
        final storeData = <String, Object>{};
        for (final entry in rawPrefs.entries) {
          final key = entry.key;
          final prefixedKey = key.startsWith('flutter.') ? key : 'flutter.$key';
          storeData[prefixedKey] = entry.value;
        }

        final store = _RecordingPreferencesStore(
          Map<String, Object>.from(storeData),
        );
        SharedPreferencesStorePlatform.instance = store;
        SharedPreferences.setMockInitialValues(storeData);
        SharedPreferencesStorePlatform.instance = store;

        LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
            'Asia/Shanghai';

        I18n.setLocale(scenario.initialLocale);

        // Construct async providers INSIDE tester.runAsync per contract
        await tester.runAsync(() async {
          diaries = DiaryProvider();
          theme = ThemeProvider();
          preferences = PreferencesProvider();
          await theme!.loadFromStorage().timeout(const Duration(seconds: 5));
          await preferences!.loadFromStorage().timeout(
            const Duration(seconds: 5),
          );
          await diaries!.loadFromStorage().timeout(const Duration(seconds: 5));
          await loadWeeklyReviewScreenshotFonts().timeout(
            const Duration(seconds: 5),
          );
        });

        await _drainAccountWrites(tester);

        expect(theme!.brand.id, scenario.initialBrand);
        expect(diaries!.entries.length, entries.length);

        tester.view.devicePixelRatio = scenario.dpr;
        tester.view.physicalSize = scenario.size * scenario.dpr;

        final boundary = GlobalKey();

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeProvider>.value(value: theme!),
              ChangeNotifierProvider<DiaryProvider>.value(value: diaries!),
              ChangeNotifierProvider<PreferencesProvider>.value(
                value: preferences!,
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
                          textScaler: scenario.scale < 0
                              ? const RouteProbeNonlinearScaler()
                              : TextScaler.linear(scenario.scale),
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

        await _boundedPumpAndSettle(tester);
        expect(tester.takeException(), isNull);

        expect(tester.view.physicalSize, scenario.size * scenario.dpr);
        expect(tester.view.devicePixelRatio, scenario.dpr);
        final rootMediaQuery = MediaQuery.of(
          tester.element(find.byType(DiaryScreen)),
        );
        expect(rootMediaQuery.size, scenario.size);

        // 1. Initial State Assertions
        final card1Finder = find.byKey(ValueKey('diary_card_${entry1.id}'));
        await _scrollToCard(tester, entry1.id);

        final expectedTitle1 = scenario.initialLocale == AppLocale.en
            ? longTitleEn
            : longTitleZh;
        _assertCompleteCardTitle(tester, card1Finder, expectedTitle1);

        final expectedDateText1 = '${today.month}/${today.day}';
        final expectedLunarText1 = AlmanacLocaleFormat.formatLunarDay(
          lunarToday,
          scenario.initialLocale,
        );
        _assertUnsplitDateBadge(
          tester,
          card1Finder,
          dateText: expectedDateText1,
          lunarText: expectedLunarText1,
        );

        _assertBoundedPreview(tester, card1Finder, entry1);
        _assertCardMetadataBounded(
          tester,
          card1Finder,
          entry1,
          expectHorizontal: scenario.expectHorizontalMetadata,
        );

        await _capture(tester, boundary, '${scenario.name}-01-initial');

        // 2. FAB reachability at max scroll: verify sorted order, bounds above FAB, and action reachability
        await _assertLastCardReachableAboveFabAtMaxScroll(
          tester,
          diaryProvider: diaries!,
          lastEntryId: entry3.id,
        );
        await _capture(tester, boundary, '${scenario.name}-02-max-scroll');

        // 3. Theme switch roundtrip: initialBrand -> targetBrand
        final originalElement = tester.element(find.byType(DiaryScreen));
        final originalRoute = ModalRoute.of(originalElement);

        await tester.runAsync(() => theme!.setBrand(scenario.targetBrand));
        await _boundedPumpAndSettle(tester);
        expect(tester.element(find.byType(DiaryScreen)), same(originalElement));
        expect(
          ModalRoute.of(tester.element(find.byType(DiaryScreen))),
          same(originalRoute),
        );

        // Verify card content remains intact under target brand
        await _scrollToCard(tester, entry1.id);
        _assertCompleteCardTitle(tester, card1Finder, expectedTitle1);
        _assertUnsplitDateBadge(
          tester,
          card1Finder,
          dateText: expectedDateText1,
          lunarText: expectedLunarText1,
        );
        await _capture(tester, boundary, '${scenario.name}-03-target-brand');

        // 4. Live locale switch: initialLocale -> targetLocale
        I18n.setLocale(scenario.targetLocale);
        await _boundedPumpAndSettle(tester);
        expect(tester.element(find.byType(DiaryScreen)), same(originalElement));

        final expectedLunarTextTargetLocale =
            AlmanacLocaleFormat.formatLunarDay(
              lunarToday,
              scenario.targetLocale,
            );
        _assertUnsplitDateBadge(
          tester,
          card1Finder,
          dateText: expectedDateText1,
          lunarText: expectedLunarTextTargetLocale,
        );
        await _capture(tester, boundary, '${scenario.name}-04-target-locale');

        // 5. Revert brand and locale back to initial
        await tester.runAsync(() => theme!.setBrand(scenario.initialBrand));
        I18n.setLocale(scenario.initialLocale);
        await _boundedPumpAndSettle(tester);
        expect(tester.element(find.byType(DiaryScreen)), same(originalElement));

        _assertCompleteCardTitle(tester, card1Finder, expectedTitle1);
        _assertUnsplitDateBadge(
          tester,
          card1Finder,
          dateText: expectedDateText1,
          lunarText: expectedLunarText1,
        );
        await _capture(tester, boundary, '${scenario.name}-05-reverted');

        // Ensure zero unwanted provider writes occurred during theme/locale switching
        expect(store.diaryWrites, equals(0));
        expect(tester.takeException(), isNull);
      } finally {
        try {
          await tester.pumpWidget(const SizedBox.shrink());
          await _boundedPumpAndSettle(tester);
          await _drainAccountWrites(tester);
        } catch (_) {}
        diaries?.dispose();
        theme?.dispose();
        preferences?.dispose();
        LocalTimezoneResolver.debugSystemTimeZoneReader =
            originalTimeZoneReader;
        SharedPreferencesStorePlatform.instance = previousStore;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        debugDisableShadows = originalDisableShadows;
      }
    });
  }
}
