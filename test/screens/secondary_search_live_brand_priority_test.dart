// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/diary_screen.dart';
import 'package:duoyi/screens/search_screen.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandRouteSurface;
import 'package:duoyi/widgets/surface_components.dart'
    show AppSurfaceCard, appSurfaceStyleOf;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/weekly_review_screenshot_font.dart';

class _FailingHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw StateError('Unexpected network call attempted during search fixture');
  }
}

class _FixturePreferencesStore extends InMemorySharedPreferencesStore {
  _FixturePreferencesStore(super.data) : super.withData();
}

class _CountingDiaryProvider extends DiaryProvider {
  _CountingDiaryProvider(this.fixtureEntries);

  final List<DiaryEntry> fixtureEntries;
  int entriesReadCount = 0;

  @override
  List<DiaryEntry> get entries {
    entriesReadCount++;
    return fixtureEntries;
  }
}

class _CountingTimeAuditProvider extends TimeAuditProvider {
  _CountingTimeAuditProvider(this.fixtureEntries);

  final List<TimeEntry> fixtureEntries;
  int entriesReadCount = 0;

  @override
  List<TimeEntry> get entries {
    entriesReadCount++;
    return fixtureEntries;
  }
}

class _SyntheticAnniversaryProvider extends AnniversaryProvider {
  _SyntheticAnniversaryProvider(this.fixtureItems);

  final List<Anniversary> fixtureItems;

  @override
  List<Anniversary> get items => fixtureItems;
}

Finder _findPlainText(String text) => find.byWidgetPredicate(
  (widget) =>
      (widget is Text && widget.data == text) ||
      (widget is RichText && widget.text.toPlainText() == text),
);

Future<int> _bounded5s(
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
  String name, {
  Finder? scrollTo,
  Finder? scrollableFinder,
}) async {
  final explicitDir =
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
  final enabled = explicitDir != null && explicitDir.isNotEmpty;
  if (!enabled) return;

  double? originalOffset;
  ScrollableState? scrollable;
  if (scrollTo != null && scrollableFinder != null) {
    if (scrollableFinder.evaluate().isNotEmpty) {
      scrollable = tester.state<ScrollableState>(scrollableFinder);
      originalOffset = scrollable.position.pixels;
      if (scrollTo.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          scrollTo,
          100.0,
          scrollable: scrollableFinder,
          maxScrolls: 30,
        );
        await tester.pump();
      }
      if (scrollTo.evaluate().isNotEmpty) {
        await tester.ensureVisible(scrollTo);
        await tester.pump();
      }
    }
  }

  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final file = File('$explicitDir/search-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });

  if (scrollable != null && originalOffset != null) {
    scrollable.position.jumpTo(originalOffset);
    await tester.pump();
  }
}

Finder _uniqueHitCard(String title) => find.byElementPredicate((element) {
  if (element.widget is! AppSurfaceCard) return false;
  var found = false;
  void inspect(Element child) {
    final widget = child.widget;
    if ((widget is Text && widget.data == title) ||
        (widget is RichText && widget.text.toPlainText() == title)) {
      found = true;
    }
    child.visitChildren(inspect);
  }

  element.visitChildren(inspect);
  return found;
});

Future<void> _inspectAllHitsByRealScroll({
  required WidgetTester tester,
  required Finder scrollableFinder,
  required String expectedSummary,
  required List<({String title, String kindLabel})> expectedHits,
}) async {
  final scrollable = tester.state<ScrollableState>(scrollableFinder);
  final savedOffset = scrollable.position.pixels;

  // 1. Start from known top edge
  scrollable.position.jumpTo(0.0);
  await tester.pump();

  // 2. Inspect localized summary card at the top
  expect(find.text(expectedSummary), findsOneWidget);

  // 3. Visit each result and its kind label by real scroll in ListView order
  for (final hit in expectedHits) {
    // A title and its preview can contain the same authored string. The
    // enclosing result card must still be unique for each expected hit.
    final titleFinder = _findPlainText(hit.title);
    if (titleFinder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        titleFinder.first,
        100.0,
        scrollable: scrollableFinder,
        maxScrolls: 30,
      );
      await tester.pump();
    }
    await tester.ensureVisible(titleFinder.first);
    await tester.pump();

    expect(
      titleFinder,
      findsWidgets,
      reason:
          'Hit title "${hit.title}" must be built and visible when scrolled into view',
    );

    final cardFinder = _uniqueHitCard(hit.title);
    expect(cardFinder, findsOneWidget);

    final kindLabelFinder = find.descendant(
      of: cardFinder,
      matching: find.text(hit.kindLabel),
    );
    expect(
      kindLabelFinder,
      findsOneWidget,
      reason:
          'Hit "${hit.title}" must display per-hit kind label "${hit.kindLabel}"',
    );
  }

  // 4. Restore the measured scroll offset around inspection
  scrollable.position.jumpTo(savedOffset);
  await tester.pump();
  expect(
    scrollable.position.pixels,
    savedOffset,
    reason: 'Scroll offset must be restored after hit inspection',
  );
}

class _SearchLiveBrandScenario {
  final String name;
  final AppLocale locale;
  final Size size;
  final double scale;
  final String initialBrand;
  final String targetBrand;

  const _SearchLiveBrandScenario({
    required this.name,
    required this.locale,
    required this.size,
    required this.scale,
    required this.initialBrand,
    required this.targetBrand,
  });
}

const _scenarios = <_SearchLiveBrandScenario>[
  _SearchLiveBrandScenario(
    name: 'zh-portrait-320x844-defaultBrand',
    locale: AppLocale.zh,
    size: Size(320, 844),
    scale: 2.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
  ),
  _SearchLiveBrandScenario(
    name: 'en-portrait-320x844-liquidGlass',
    locale: AppLocale.en,
    size: Size(320, 844),
    scale: 2.0,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
  ),
  _SearchLiveBrandScenario(
    name: 'zh-landscape-844x390-defaultBrand',
    locale: AppLocale.zh,
    size: Size(844, 390),
    scale: 1.6,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
  ),
  _SearchLiveBrandScenario(
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
      'secondary search live brand priority ${scenario.name} ${scenario.initialBrand} <-> ${scenario.targetBrand}',
      (tester) async {
        final originalLocale = I18n.current;
        final originalShadows = debugDisableShadows;
        final originalTimeZoneReader =
            LocalTimezoneResolver.debugSystemTimeZoneReader;
        final previousStore = SharedPreferencesStorePlatform.instance;
        final originalHttpOverrides = HttpOverrides.current;

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
        final store = _FixturePreferencesStore({
          for (final entry in initialPrefs.entries)
            if (!entry.key.startsWith('flutter.'))
              'flutter.${entry.key}': entry.value,
        });
        SharedPreferencesStorePlatform.instance = store;
        LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
            'Asia/Shanghai';
        HttpOverrides.global = _FailingHttpOverrides();

        final date = DateTime(2026, 10, 20);
        final targetDiary = DiaryEntry(
          id: 'synthetic-target-diary',
          date: date,
          content: 'review target diary content\nsecond line of diary content',
          tags: ['review'],
        );
        final secondaryDiary = DiaryEntry(
          id: 'synthetic-extra-diary',
          date: DateTime(2026, 10, 19),
          content: 'review additional notes for list height and scrolling',
          tags: ['review'],
        );
        final fixtureDiaries = [targetDiary, secondaryDiary];
        final diaryProvider = _CountingDiaryProvider(fixtureDiaries);

        final fixtureTimeEntries = [
          TimeEntry(
            id: 'synthetic-review-time',
            title: 'review planning session',
            note: 'review time tracking subtitle notes',
            startAt: DateTime(2026, 10, 20, 9),
            endAt: DateTime(2026, 10, 20, 10),
          ),
        ];
        final timeAuditProvider = _CountingTimeAuditProvider(
          fixtureTimeEntries,
        );

        final fixtureAnniversaries = [
          Anniversary(
            id: 'synthetic-review-anniversary',
            title: 'review milestone anniversary',
            originDate: DateTime(2026, 10, 1),
          ),
        ];
        final anniversaryProvider = _SyntheticAnniversaryProvider(
          fixtureAnniversaries,
        );

        final todoProvider = TodoProvider();
        final habitProvider = HabitProvider();
        final noteProvider = NoteProvider();
        final countdownProvider = CountdownProvider();
        final goalProvider = GoalProvider();
        final courseProvider = CourseProvider();
        final calendarProvider = CalendarProvider();
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

          await _drainAccountWrites(tester);

          expect(theme.brand.id, scenario.initialBrand);
          expect(theme.isBrandUnlocked(scenario.targetBrand), isTrue);

          tester.view.physicalSize = scenario.size;
          tester.view.devicePixelRatio = 1;

          final boundary = GlobalKey();

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<PreferencesProvider>.value(
                  value: preferences,
                ),
                ChangeNotifierProvider<DiaryProvider>.value(
                  value: diaryProvider,
                ),
                ChangeNotifierProvider<TimeAuditProvider>.value(
                  value: timeAuditProvider,
                ),
                ChangeNotifierProvider<AnniversaryProvider>.value(
                  value: anniversaryProvider,
                ),
                ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
                ChangeNotifierProvider<HabitProvider>.value(
                  value: habitProvider,
                ),
                ChangeNotifierProvider<NoteProvider>.value(value: noteProvider),
                ChangeNotifierProvider<CountdownProvider>.value(
                  value: countdownProvider,
                ),
                ChangeNotifierProvider<GoalProvider>.value(value: goalProvider),
                ChangeNotifierProvider<CourseProvider>.value(
                  value: courseProvider,
                ),
                ChangeNotifierProvider<CalendarProvider>.value(
                  value: calendarProvider,
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
                        home: Builder(
                          builder: (context) => Scaffold(
                            body: Center(
                              child: TextButton(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const BrandRouteSurface(
                                      remountOnLocaleChange: false,
                                      child: SearchScreen(),
                                    ),
                                  ),
                                ),
                                child: const Text('Open search'),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
              ),
            ),
          );

          await _bounded5s(tester);
          expect(tester.takeException(), isNull);

          // 1. Open the mounted SearchScreen
          await tester.tap(find.text('Open search'));
          await _bounded5s(tester);
          expect(tester.takeException(), isNull);

          final searchFinder = find.byType(SearchScreen);
          expect(searchFinder, findsOneWidget);
          expect(find.byType(BrandRouteSurface), findsOneWidget);
          expect(find.text(I18n.tr('search.empty')), findsOneWidget);

          final initialSearchState = tester.state(searchFinder);
          final initialModalRoute = ModalRoute.of(tester.element(searchFinder));
          expect(initialModalRoute, isNotNull);

          final searchField = find.byType(TextField);
          expect(searchField, findsOneWidget);
          final initialController = tester
              .widget<TextField>(searchField)
              .controller!;
          expect(initialController.text, isEmpty);

          Finder stableFieldFinder() => find.descendant(
            of: searchFinder,
            matching: find.byType(TextField),
          );

          void assertRealBrandStyle(String expectedBrandId, String stage) {
            final searchElement = tester.element(searchFinder);
            final currentTheme = Theme.of(searchElement);
            final expectedBrand = AppBrands.byId(expectedBrandId);
            expect(
              currentTheme.colorScheme.primary,
              equals(expectedBrand.theme.colorScheme.primary),
              reason: '$stage: ColorScheme.primary must match $expectedBrandId',
            );

            final surfaceStyle = appSurfaceStyleOf(searchElement);
            if (expectedBrandId == 'liquidGlass') {
              expect(
                surfaceStyle,
                equals(AppSurfaceStyle.liquidGlass),
                reason: '$stage: appSurfaceStyleOf must equal liquidGlass',
              );
            } else {
              expect(
                surfaceStyle,
                equals(AppSurfaceStyle.ios),
                reason:
                    '$stage: appSurfaceStyleOf must equal ios for defaultBrand',
              );
            }
          }

          assertRealBrandStyle(scenario.initialBrand, '1. initial brand');
          await _capture(tester, boundary, '${scenario.name}-01-initial');

          // 2. Populate search results with draft query 'review'
          const queryText = 'review';
          const draftSelection = TextSelection(baseOffset: 1, extentOffset: 5);

          await tester.enterText(stableFieldFinder(), queryText);
          await tester.pump(const Duration(milliseconds: 200));
          await _bounded5s(tester);
          expect(tester.takeException(), isNull);

          initialController.selection = draftSelection;
          await tester.pump();

          expect(initialController.text, queryText);
          expect(initialController.selection, draftSelection);

          final textScaler = MediaQuery.textScalerOf(
            tester.element(searchFinder),
          );
          expect(
            textScaler.scale(10.0),
            closeTo(scenario.scale * 10.0, 0.001),
            reason: 'Text scaler must match scenario scale without reduction',
          );

          final baselineDiaryReads = diaryProvider.entriesReadCount;
          final baselineTimeReads = timeAuditProvider.entriesReadCount;
          expect(baselineDiaryReads, greaterThanOrEqualTo(1));
          expect(baselineTimeReads, greaterThanOrEqualTo(1));

          final scrollableFinder = find.descendant(
            of: searchFinder,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            ),
          );
          expect(scrollableFinder, findsOneWidget);
          final scrollableState = tester.state<ScrollableState>(
            scrollableFinder,
          );
          final maxExtent = scrollableState.position.maxScrollExtent;
          expect(
            maxExtent,
            greaterThan(10.0),
            reason: 'Populated search results must produce a scrollable list',
          );
          final establishedScrollOffset = (maxExtent * 0.45).clamp(12.0, 48.0);
          scrollableState.position.jumpTo(establishedScrollOffset);
          await tester.pump();
          expect(scrollableState.position.pixels, establishedScrollOffset);

          String summaryTextFor(AppLocale locale) {
            final prefix = I18n.trForLocale(
              'search.results.summary_prefix',
              locale,
            );
            final middle = I18n.trForLocale(
              'search.results.summary_middle',
              locale,
            );
            final suffix = I18n.trForLocale(
              'search.results.summary_suffix',
              locale,
            );
            return '$prefix$queryText${middle}4$suffix';
          }

          List<({String title, String kindLabel})> expectedHitsFor(
            AppLocale locale,
          ) => [
            (
              title: 'review target diary content',
              kindLabel: I18n.trForLocale('search.kind.diary', locale),
            ),
            (
              title: 'review additional notes for list height and scrolling',
              kindLabel: I18n.trForLocale('search.kind.diary', locale),
            ),
            (
              title: 'review milestone anniversary',
              kindLabel: I18n.trForLocale('search.kind.anniversary', locale),
            ),
            (
              title: 'review planning session',
              kindLabel: I18n.trForLocale('search.kind.time_entry', locale),
            ),
          ];

          // Visit each result and its kind label by real scroll from a known edge;
          // inspect all 4 hit data and localized summary, restoring measured offset.
          await _inspectAllHitsByRealScroll(
            tester: tester,
            scrollableFinder: scrollableFinder,
            expectedSummary: summaryTextFor(scenario.locale),
            expectedHits: expectedHitsFor(scenario.locale),
          );

          assertRealBrandStyle(scenario.initialBrand, '2. after populated');
          await _capture(
            tester,
            boundary,
            '${scenario.name}-02-populated',
            scrollTo: _findPlainText('review target diary content'),
            scrollableFinder: scrollableFinder,
          );

          // 3. Live theme switch to targetBrand (defaultBrand <-> liquidGlass)
          await tester.runAsync(() async {
            final switched = await theme.setBrand(scenario.targetBrand);
            expect(switched, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          await _bounded5s(tester);
          expect(tester.takeException(), isNull);

          expect(theme.brand.id, scenario.targetBrand);
          final prefsAfterSwitch = await SharedPreferences.getInstance();
          expect(
            prefsAfterSwitch.getString('active_brand'),
            scenario.targetBrand,
          );

          assertRealBrandStyle(
            scenario.targetBrand,
            '3. after targetBrand switch',
          );

          // Assert State, ModalRoute, controller identity, draft & selection retention
          expect(
            identical(tester.state(searchFinder), initialSearchState),
            isTrue,
            reason:
                'State identity must be preserved across live brand switch to ${scenario.targetBrand}',
          );
          expect(
            identical(
              ModalRoute.of(tester.element(searchFinder)),
              initialModalRoute,
            ),
            isTrue,
            reason:
                'ModalRoute identity must be preserved across live brand switch to ${scenario.targetBrand}',
          );
          expect(
            identical(
              tester.widget<TextField>(stableFieldFinder()).controller,
              initialController,
            ),
            isTrue,
            reason:
                'TextEditingController identity must be preserved across live brand switch',
          );
          expect(initialController.text, queryText);
          expect(initialController.selection, draftSelection);

          // Assert exact nonzero scroll offset retention across brand switch
          final scrollPixelsAfterSwitch = tester
              .state<ScrollableState>(scrollableFinder)
              .position
              .pixels;
          expect(
            scrollPixelsAfterSwitch,
            equals(establishedScrollOffset),
            reason:
                'Exact nonzero scroll offset must be preserved across brand switch',
          );

          // Assert counted provider access (no query rerun on theme switch)
          expect(
            diaryProvider.entriesReadCount,
            baselineDiaryReads,
            reason:
                'No diary query rerun must occur on brand switch to ${scenario.targetBrand}',
          );
          expect(
            timeAuditProvider.entriesReadCount,
            baselineTimeReads,
            reason:
                'No time audit query rerun must occur on brand switch to ${scenario.targetBrand}',
          );

          // Inspect all 4 hits and summary by real scroll, restoring measured offset
          await _inspectAllHitsByRealScroll(
            tester: tester,
            scrollableFinder: scrollableFinder,
            expectedSummary: summaryTextFor(scenario.locale),
            expectedHits: expectedHitsFor(scenario.locale),
          );

          await _capture(
            tester,
            boundary,
            '${scenario.name}-03-targetBrand',
            scrollTo: _findPlainText('review target diary content'),
            scrollableFinder: scrollableFinder,
          );

          // 4. Live theme roundtrip back to initialBrand
          await tester.runAsync(() async {
            final reverted = await theme.setBrand(scenario.initialBrand);
            expect(reverted, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          await _bounded5s(tester);
          expect(tester.takeException(), isNull);

          expect(theme.brand.id, scenario.initialBrand);
          final prefsAfterRevert = await SharedPreferences.getInstance();
          expect(
            prefsAfterRevert.getString('active_brand'),
            scenario.initialBrand,
          );

          assertRealBrandStyle(
            scenario.initialBrand,
            '4. after initialBrand revert',
          );

          expect(
            identical(tester.state(searchFinder), initialSearchState),
            isTrue,
            reason:
                'State identity must be preserved across live brand roundtrip to ${scenario.initialBrand}',
          );
          expect(
            identical(
              ModalRoute.of(tester.element(searchFinder)),
              initialModalRoute,
            ),
            isTrue,
            reason:
                'ModalRoute identity must be preserved across live brand roundtrip',
          );
          expect(
            identical(
              tester.widget<TextField>(stableFieldFinder()).controller,
              initialController,
            ),
            isTrue,
            reason:
                'TextEditingController identity must be preserved across brand roundtrip',
          );
          expect(initialController.text, queryText);
          expect(initialController.selection, draftSelection);

          final scrollPixelsAfterRevert = tester
              .state<ScrollableState>(scrollableFinder)
              .position
              .pixels;
          expect(
            scrollPixelsAfterRevert,
            equals(establishedScrollOffset),
            reason:
                'Exact nonzero scroll offset must be preserved across brand revert',
          );

          expect(
            diaryProvider.entriesReadCount,
            baselineDiaryReads,
            reason: 'No diary query rerun on brand revert',
          );
          expect(
            timeAuditProvider.entriesReadCount,
            baselineTimeReads,
            reason: 'No time audit query rerun on brand revert',
          );

          await _inspectAllHitsByRealScroll(
            tester: tester,
            scrollableFinder: scrollableFinder,
            expectedSummary: summaryTextFor(scenario.locale),
            expectedHits: expectedHitsFor(scenario.locale),
          );

          await _capture(
            tester,
            boundary,
            '${scenario.name}-04-revertedBrand',
            scrollTo: _findPlainText('review target diary content'),
            scrollableFinder: scrollableFinder,
          );

          // 5. Live locale switch to alternative locale
          final altLocale = scenario.locale == AppLocale.zh
              ? AppLocale.en
              : AppLocale.zh;
          I18n.setLocale(altLocale);
          await _bounded5s(tester);
          expect(tester.takeException(), isNull);

          expect(
            identical(tester.state(searchFinder), initialSearchState),
            isTrue,
            reason: 'State identity preserved across live locale change',
          );
          expect(
            identical(
              ModalRoute.of(tester.element(searchFinder)),
              initialModalRoute,
            ),
            isTrue,
            reason: 'ModalRoute identity preserved across live locale change',
          );
          expect(
            identical(
              tester.widget<TextField>(stableFieldFinder()).controller,
              initialController,
            ),
            isTrue,
            reason: 'Controller identity preserved across live locale change',
          );
          expect(initialController.text, queryText);
          expect(initialController.selection, draftSelection);

          // Observe normal locale scroll clamping within valid extent
          final scrollPosAfterLocale = tester
              .state<ScrollableState>(scrollableFinder)
              .position;
          expect(
            scrollPosAfterLocale.pixels,
            inInclusiveRange(0.0, scrollPosAfterLocale.maxScrollExtent),
            reason: 'Scroll offset must respect normal locale scroll clamping',
          );

          expect(
            diaryProvider.entriesReadCount,
            baselineDiaryReads,
            reason: 'No diary query rerun on locale switch',
          );
          expect(
            timeAuditProvider.entriesReadCount,
            baselineTimeReads,
            reason: 'No time audit query rerun on locale switch',
          );

          // Inspect relocalized summary and hits by real scroll
          await _inspectAllHitsByRealScroll(
            tester: tester,
            scrollableFinder: scrollableFinder,
            expectedSummary: summaryTextFor(altLocale),
            expectedHits: expectedHitsFor(altLocale),
          );

          await _capture(
            tester,
            boundary,
            '${scenario.name}-05-altLocale',
            scrollTo: _findPlainText('review target diary content'),
            scrollableFinder: scrollableFinder,
          );

          // 6. Live locale switch back to scenario original locale
          I18n.setLocale(scenario.locale);
          await _bounded5s(tester);
          expect(tester.takeException(), isNull);

          expect(
            identical(tester.state(searchFinder), initialSearchState),
            isTrue,
            reason: 'State identity preserved across locale revert',
          );
          expect(
            identical(
              ModalRoute.of(tester.element(searchFinder)),
              initialModalRoute,
            ),
            isTrue,
            reason: 'ModalRoute identity preserved across locale revert',
          );
          expect(
            identical(
              tester.widget<TextField>(stableFieldFinder()).controller,
              initialController,
            ),
            isTrue,
            reason: 'Controller identity preserved across locale revert',
          );
          expect(initialController.text, queryText);
          expect(initialController.selection, draftSelection);

          final scrollPosAfterLocaleRevert = tester
              .state<ScrollableState>(scrollableFinder)
              .position;
          expect(
            scrollPosAfterLocaleRevert.pixels,
            inInclusiveRange(0.0, scrollPosAfterLocaleRevert.maxScrollExtent),
            reason:
                'Scroll offset must respect normal locale scroll clamping on revert',
          );

          expect(
            diaryProvider.entriesReadCount,
            baselineDiaryReads,
            reason: 'No diary query rerun on locale revert',
          );
          expect(
            timeAuditProvider.entriesReadCount,
            baselineTimeReads,
            reason: 'No time audit query rerun on locale revert',
          );

          await _inspectAllHitsByRealScroll(
            tester: tester,
            scrollableFinder: scrollableFinder,
            expectedSummary: summaryTextFor(scenario.locale),
            expectedHits: expectedHitsFor(scenario.locale),
          );

          await _capture(
            tester,
            boundary,
            '${scenario.name}-06-revertedLocale',
            scrollTo: _findPlainText('review target diary content'),
            scrollableFinder: scrollableFinder,
          );

          // 7. Visible result navigation to synthetic diary entry and back
          final targetTitleFinder = _findPlainText(
            'review target diary content',
          );
          if (targetTitleFinder.evaluate().isEmpty) {
            tester
                .state<ScrollableState>(scrollableFinder)
                .position
                .jumpTo(0.0);
            await tester.pump();
          }
          await tester.ensureVisible(targetTitleFinder);
          await _bounded5s(tester);

          final diaryCardFinder = find
              .ancestor(
                of: targetTitleFinder,
                matching: find.byType(AppSurfaceCard),
              )
              .first;

          await tester.ensureVisible(diaryCardFinder);
          await _bounded5s(tester);
          await tester.tap(diaryCardFinder);
          await _bounded5s(tester);
          expect(tester.takeException(), isNull);

          final diaryScreenFinder = find.byType(DiaryScreen);
          expect(diaryScreenFinder, findsOneWidget);

          // Verify real theme and surface style inside open screen overlay
          final diaryElement = tester.element(diaryScreenFinder);
          final diaryTheme = Theme.of(diaryElement);
          final expectedBrand = AppBrands.byId(scenario.initialBrand);
          expect(
            diaryTheme.colorScheme.primary,
            equals(expectedBrand.theme.colorScheme.primary),
            reason: 'DiaryScreen Theme.of primary must match active brand',
          );

          final diarySurfaceStyle = appSurfaceStyleOf(diaryElement);
          if (scenario.initialBrand == 'liquidGlass') {
            expect(
              diarySurfaceStyle,
              equals(AppSurfaceStyle.liquidGlass),
              reason: 'DiaryScreen appSurfaceStyleOf must equal liquidGlass',
            );
          } else {
            expect(
              diarySurfaceStyle,
              equals(AppSurfaceStyle.ios),
              reason:
                  'DiaryScreen appSurfaceStyleOf must equal ios for defaultBrand',
            );
          }

          await _capture(tester, boundary, '${scenario.name}-07-diaryScreen');

          // Navigate back via BackButton
          final backButtonFinder = find.descendant(
            of: diaryScreenFinder,
            matching: find.byType(BackButton),
          );
          if (backButtonFinder.evaluate().isNotEmpty) {
            await tester.ensureVisible(backButtonFinder.first);
            await _bounded5s(tester);
            await tester.tap(backButtonFinder.first);
          } else {
            await tester.pageBack();
          }
          await _bounded5s(tester);
          expect(tester.takeException(), isNull);

          expect(find.byType(DiaryScreen), findsNothing);
          expect(searchFinder, findsOneWidget);

          // Assert retained query, controller, and populated results after returning
          expect(
            identical(tester.state(searchFinder), initialSearchState),
            isTrue,
            reason:
                'SearchScreen state identity must be preserved after returning from DiaryScreen',
          );
          final returnedField = stableFieldFinder();
          expect(returnedField, findsOneWidget);
          expect(initialController.text, queryText);

          // Assert time audit provider read count remained unchanged throughout navigation
          expect(
            timeAuditProvider.entriesReadCount,
            baselineTimeReads,
            reason:
                'Search query must not rerun from result navigation and back',
          );

          // Inspect all 4 hits and summary by real scroll after returning
          await _inspectAllHitsByRealScroll(
            tester: tester,
            scrollableFinder: scrollableFinder,
            expectedSummary: summaryTextFor(scenario.locale),
            expectedHits: expectedHitsFor(scenario.locale),
          );

          await _capture(
            tester,
            boundary,
            '${scenario.name}-08-returned',
            scrollTo: _findPlainText('review target diary content'),
            scrollableFinder: scrollableFinder,
          );
          expect(tester.takeException(), isNull);
        } finally {
          try {
            await _drainAccountWrites(tester);
            await tester.pumpWidget(const SizedBox.shrink());
            await _bounded5s(tester);
          } finally {
            SharedPreferences.resetStatic();
            SharedPreferencesStorePlatform.instance = previousStore;
            LocalTimezoneResolver.debugSystemTimeZoneReader =
                originalTimeZoneReader;
            HttpOverrides.global = originalHttpOverrides;

            diaryProvider.dispose();
            timeAuditProvider.dispose();
            anniversaryProvider.dispose();
            todoProvider.dispose();
            habitProvider.dispose();
            noteProvider.dispose();
            countdownProvider.dispose();
            goalProvider.dispose();
            courseProvider.dispose();
            calendarProvider.dispose();
            theme.dispose();
            preferences.dispose();

            tester.view.reset();
            debugDisableShadows = originalShadows;
            I18n.setLocale(originalLocale);
          }
        }
      },
    );
  }
}
