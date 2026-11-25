// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/almanac_locale_format.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/core/lunar_calendar.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/diary_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandRouteSurface;
import 'package:duoyi/widgets/surface_components.dart' show appSurfaceStyleOf;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/weekly_review_screenshot_font.dart';

class _RecordingDiaryProvider extends DiaryProvider {
  int saves = 0;
  @override
  Future<void> addOrUpdate(DiaryEntry entry) async {
    saves++;
    await super.addOrUpdate(entry);
  }
}

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

Future<void> _restoreScrollOffset(
  WidgetTester tester,
  Finder scrollable,
  double targetOffset,
) async {
  final position = tester.state<ScrollableState>(scrollable).position;
  final clamped = targetOffset.clamp(
    position.minScrollExtent,
    position.maxScrollExtent,
  );
  position.jumpTo(clamped);
  await _boundedPumpAndSettle(tester);
  expect(position.pixels, closeTo(clamped, 0.001));
}

Future<void> _scrollTo(
  WidgetTester tester,
  Finder target, {
  Finder? scrollable,
  double delta = 200,
  int maxSteps = 25,
}) async {
  final scroll =
      scrollable ??
      find
          .descendant(
            of: find.byType(DiaryEditScreen),
            matching: find.byType(Scrollable),
          )
          .first;

  if (target.evaluate().isNotEmpty) {
    await Scrollable.ensureVisible(
      tester.element(target.first),
      alignment: 0.5,
    );
    await _boundedPumpAndSettle(tester);
    return;
  }

  // Search downwards first (drag with negative y delta)
  for (var i = 0; i < maxSteps; i++) {
    if (target.evaluate().isNotEmpty) break;
    final posBefore = tester.state<ScrollableState>(scroll).position.pixels;
    await tester.drag(scroll, Offset(0, -delta.abs()));
    await _boundedPumpAndSettle(tester);
    final posAfter = tester.state<ScrollableState>(scroll).position.pixels;
    if ((posAfter - posBefore).abs() < 0.5) {
      break;
    }
  }

  // If still not found, search upwards (drag with positive y delta)
  if (target.evaluate().isEmpty) {
    for (var i = 0; i < maxSteps * 2; i++) {
      if (target.evaluate().isNotEmpty) break;
      final posBefore = tester.state<ScrollableState>(scroll).position.pixels;
      await tester.drag(scroll, Offset(0, delta.abs()));
      await _boundedPumpAndSettle(tester);
      final posAfter = tester.state<ScrollableState>(scroll).position.pixels;
      if ((posAfter - posBefore).abs() < 0.5) {
        break;
      }
    }
  }

  expect(
    target,
    findsWidgets,
    reason:
        'Target widget should be visible after scrolling through lazy ListView',
  );
  await Scrollable.ensureVisible(tester.element(target.first), alignment: 0.5);
  await _boundedPumpAndSettle(tester);
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name, {
  Finder? scrollable,
  double? targetOffset,
}) async {
  final explicitDir =
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
  if (explicitDir == null || explicitDir.isEmpty) return;

  double? originalOffset;
  if (scrollable != null && targetOffset != null) {
    originalOffset = tester.state<ScrollableState>(scrollable).position.pixels;
    await _restoreScrollOffset(tester, scrollable, targetOffset);
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
      final file = File('$explicitDir/diary-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });

  if (scrollable != null && originalOffset != null) {
    await _restoreScrollOffset(tester, scrollable, originalOffset);
  }
}

Future<void> _inspectAllSections({
  required WidgetTester tester,
  required Finder scrollableFinder,
  required TextEditingController contentController,
  required TextEditingController tagController,
  required String expectedBrandId,
  required String expectedDraftContent,
  required TextSelection expectedContentSelection,
  required String expectedDraftTag,
  required TextSelection expectedTagSelection,
  required Mood expectedMood,
  required Weather expectedWeather,
  required DateTime baselineDate,
  required double savedScrollOffset,
}) async {
  // 1. Visit Top section
  await _scrollTo(
    tester,
    find.byIcon(Icons.calendar_today),
    scrollable: scrollableFinder,
  );
  expect(find.byIcon(Icons.calendar_today), findsOneWidget);
  expect(
    find.text(
      AlmanacLocaleFormat.formatLunarDate(
        LunarCalendar.fromSolar(baselineDate),
      ),
    ),
    findsOneWidget,
  );
  expect(find.text(I18n.tr('diary.editor.mood_prompt')), findsOneWidget);

  // 2. Visit Mood section
  await _scrollTo(
    tester,
    find.text(expectedMood.emoji),
    scrollable: scrollableFinder,
  );
  expect(find.text(expectedMood.emoji), findsWidgets);
  final moodContainer = find
      .ancestor(
        of: find.text(expectedMood.emoji),
        matching: find.byType(AnimatedContainer),
      )
      .first;
  final decoration =
      tester.widget<AnimatedContainer>(moodContainer).decoration!
          as BoxDecoration;
  expect(
    (decoration.border! as Border).top.color,
    Theme.of(tester.element(moodContainer)).colorScheme.primary,
  );

  // 3. Visit Weather section
  final weatherFinder = find.byWidgetPredicate(
    (w) =>
        w is FilterChip &&
        w.label is Text &&
        (w.label as Text).data!.contains(expectedWeather.emoji),
  );
  await _scrollTo(tester, weatherFinder, scrollable: scrollableFinder);
  expect(find.text(I18n.tr('diary.editor.weather')), findsOneWidget);
  expect(tester.widget<FilterChip>(weatherFinder).selected, isTrue);

  // 4. Visit Tag field
  final tagFinder = find.byWidgetPredicate(
    (w) => w is TextField && identical(w.controller, tagController),
  );
  await _scrollTo(tester, tagFinder, scrollable: scrollableFinder);
  final tagWidget = tester.widget<TextField>(tagFinder);
  final expectedTagHint = I18n.tr('diary.editor.tag_hint');
  if (tagWidget.decoration?.hintText != null) {
    expect(tagWidget.decoration!.hintText, expectedTagHint);
  } else {
    final prompt = find.descendant(
      of: find.byType(DiaryEditScreen),
      matching: find.text(expectedTagHint),
    );
    expect(prompt, findsOneWidget);
    await _scrollTo(tester, prompt, scrollable: scrollableFinder);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: prompt, matching: find.byType(RichText)),
    );
    expect(paragraph.text.toPlainText(), expectedTagHint);
    expect(paragraph.didExceedMaxLines, isFalse);
  }
  expect(tagController.text, expectedDraftTag);
  expect(tagController.selection, expectedTagSelection);

  // 5. Visit Content field
  final contentFinder = find.byWidgetPredicate(
    (w) => w is TextField && identical(w.controller, contentController),
  );
  await _scrollTo(tester, contentFinder, scrollable: scrollableFinder);
  final contentWidget = tester.widget<TextField>(contentFinder);
  expect(
    contentWidget.decoration?.hintText,
    I18n.tr('diary.editor.content_hint'),
  );
  expect(contentController.text, expectedDraftContent);
  expect(contentController.selection, expectedContentSelection);

  // Assert actual Theme.of on target control
  final targetControlElement = tester.element(contentFinder);
  final expectedBrand = AppBrands.byId(expectedBrandId);
  expect(
    Theme.of(targetControlElement).colorScheme.primary,
    equals(expectedBrand.theme.colorScheme.primary),
  );

  // 6. Restore saved scroll offset
  await _restoreScrollOffset(tester, scrollableFinder, savedScrollOffset);
}

enum _DiaryContractOutcome { discard, save }

class _DiaryLiveBrandScenario {
  final String name;
  final AppLocale locale;
  final Size size;
  final double scale;
  final String initialBrand;
  final String targetBrand;
  final _DiaryContractOutcome outcome;

  const _DiaryLiveBrandScenario({
    required this.name,
    required this.locale,
    required this.size,
    required this.scale,
    required this.initialBrand,
    required this.targetBrand,
    required this.outcome,
  });
}

const _scenarios = <_DiaryLiveBrandScenario>[
  _DiaryLiveBrandScenario(
    name: 'zh-portrait-320x844-defaultBrand-discard',
    locale: AppLocale.zh,
    size: Size(320, 844),
    scale: 2.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    outcome: _DiaryContractOutcome.discard,
  ),
  _DiaryLiveBrandScenario(
    name: 'en-portrait-320x844-liquidGlass-save',
    locale: AppLocale.en,
    size: Size(320, 844),
    scale: 2.0,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    outcome: _DiaryContractOutcome.save,
  ),
  _DiaryLiveBrandScenario(
    name: 'zh-landscape-844x390-defaultBrand-save',
    locale: AppLocale.zh,
    size: Size(844, 390),
    scale: 1.6,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    outcome: _DiaryContractOutcome.save,
  ),
  _DiaryLiveBrandScenario(
    name: 'en-landscape-844x390-liquidGlass-discard',
    locale: AppLocale.en,
    size: Size(844, 390),
    scale: 1.6,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    outcome: _DiaryContractOutcome.discard,
  ),
];

void main() {
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets('diary live brand priority defaultBrand <-> liquidGlass ${scenario.name}', (
      tester,
    ) async {
      final recordedRequests = <String>[];
      await HttpOverrides.runZoned(
        () async {
          final originalLocale = I18n.current;
          final originalShadows = debugDisableShadows;
          final originalTimeZoneReader =
              LocalTimezoneResolver.debugSystemTimeZoneReader;
          final previousStore = SharedPreferencesStorePlatform.instance;

          final baselineDate = DateTime(2026, 5, 20);
          final baselineEntry = DiaryEntry(
            id: 'synthetic-diary-${scenario.name}',
            date: baselineDate,
            content: 'Synthetic baseline diary content for ${scenario.name}',
            mood: Mood.good,
            weather: Weather.sunny,
            tags: const ['original-tag'],
          );
          final baselineSerialized = jsonEncode(baselineEntry.toJson());

          final initialPrefs = <String, Object>{
            'pref_app_timezone_mode': 'fixed',
            'pref_app_timezone_iana': 'Asia/Shanghai',
            'active_brand': scenario.initialBrand,
            'theme_shop_state': jsonEncode({
              'activeBrand': scenario.initialBrand,
              'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
            }),
            'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
            'duoyi_diary': [baselineSerialized],
            'flutter.pref_app_timezone_mode': 'fixed',
            'flutter.pref_app_timezone_iana': 'Asia/Shanghai',
            'flutter.active_brand': scenario.initialBrand,
            'flutter.theme_shop_state': jsonEncode({
              'activeBrand': scenario.initialBrand,
              'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
            }),
            'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
            'flutter.duoyi_diary': [baselineSerialized],
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

          final diaries = _RecordingDiaryProvider();
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
              await diaries.loadFromStorage().timeout(
                const Duration(seconds: 5),
              );
              await loadWeeklyReviewScreenshotFonts().timeout(
                const Duration(seconds: 5),
              );
            });

            await _drainAccountWrites(tester);

            expect(theme.brand.id, scenario.initialBrand);
            expect(theme.isBrandUnlocked(scenario.targetBrand), isTrue);
            expect(diaries.entries.length, 1);
            expect(diaries.entries.first.id, baselineEntry.id);
            expect(diaries.entries.first.content, baselineEntry.content);

            final baselineDiaryWrites = store.diaryWrites;
            final baselineAccountGeneration =
                AccountLocalDataCleaner.accountDataGeneration;

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
                            child: RepaintBoundary(
                              key: boundary,
                              child: child!,
                            ),
                          ),
                          home: Builder(
                            builder: (context) => Scaffold(
                              body: Center(
                                child: TextButton(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => BrandRouteSurface(
                                        remountOnLocaleChange: false,
                                        child: DiaryEditScreen(
                                          entry: baselineEntry,
                                        ),
                                      ),
                                    ),
                                  ),
                                  child: const Text('Open diary editor'),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            );

            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);

            // 1. Open the mounted DiaryEditScreen
            await tester.tap(find.text('Open diary editor'));
            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);

            final editorFinder = find.byType(DiaryEditScreen);
            expect(editorFinder, findsOneWidget);
            expect(find.byType(BrandRouteSurface), findsOneWidget);
            expect(find.text(I18n.tr('diary.title')), findsOneWidget);
            expect(
              find.widgetWithIcon(IconButton, Icons.check),
              findsOneWidget,
            );

            final initialEditorState = tester.state(editorFinder);
            final initialModalRoute = ModalRoute.of(
              tester.element(editorFinder),
            );
            expect(initialModalRoute, isNotNull);

            final scrollableFinder = find
                .descendant(of: editorFinder, matching: find.byType(Scrollable))
                .first;

            // Scroll through lazy ListView to bring tag and content fields into view
            await _scrollTo(
              tester,
              find.byIcon(Icons.tag),
              scrollable: scrollableFinder,
            );
            final contentFieldInitialFinder = find.byWidgetPredicate(
              (w) => w is TextField && w.maxLines == 12,
            );
            await _scrollTo(
              tester,
              contentFieldInitialFinder,
              scrollable: scrollableFinder,
            );

            // Capture stable controllers from the mounted TextFields
            expect(contentFieldInitialFinder, findsOneWidget);
            final contentController = tester
                .widget<TextField>(contentFieldInitialFinder)
                .controller!;
            expect(contentController.text, baselineEntry.content);

            final tagFieldInitialFinder = find.byWidgetPredicate(
              (w) => w is TextField && w.decoration?.prefixIcon is Icon,
            );
            await _scrollTo(
              tester,
              tagFieldInitialFinder,
              scrollable: scrollableFinder,
            );
            expect(tagFieldInitialFinder, findsOneWidget);
            final tagController = tester
                .widget<TextField>(tagFieldInitialFinder)
                .controller!;
            expect(tagController.text, '');

            // Verify initial Theme and AppSurfaceStyle
            final initialEditorElement = tester.element(editorFinder);
            final initialTargetControlElement = tester.element(
              contentFieldInitialFinder,
            );
            final initialExpectedBrand = AppBrands.byId(scenario.initialBrand);
            expect(
              Theme.of(initialTargetControlElement).colorScheme.primary,
              equals(initialExpectedBrand.theme.colorScheme.primary),
            );
            expect(
              appSurfaceStyleOf(initialEditorElement),
              equals(
                scenario.initialBrand == 'liquidGlass'
                    ? AppSurfaceStyle.liquidGlass
                    : AppSurfaceStyle.ios,
              ),
            );
            expect(recordedRequests, isEmpty);
            expect(store.diaryWrites, baselineDiaryWrites);
            expect(diaries.saves, 0);
            await _capture(tester, boundary, '${scenario.name}-01-initial');

            // 2. Enter uncommitted draft into content, tag, mood, weather, and establish scroll offset
            final draftContentText = 'Draft content ${scenario.name}';
            const draftContentSelection = TextSelection(
              baseOffset: 2,
              extentOffset: 7,
            );
            final draftTagText = 'draft-tag';
            const draftTagSelection = TextSelection(
              baseOffset: 0,
              extentOffset: 4,
            );

            final contentField = find.byWidgetPredicate(
              (w) =>
                  w is TextField && identical(w.controller, contentController),
            );
            await _scrollTo(tester, contentField, scrollable: scrollableFinder);
            expect(contentField.hitTestable(), findsOneWidget);
            await tester.tap(contentField);
            await tester.enterText(contentField, draftContentText);
            contentController.selection = draftContentSelection;
            await tester.pump();

            final tagField = find.byWidgetPredicate(
              (w) => w is TextField && identical(w.controller, tagController),
            );
            await _scrollTo(tester, tagField, scrollable: scrollableFinder);
            expect(tagField.hitTestable(), findsOneWidget);
            await tester.tap(tagField);
            await tester.enterText(tagField, draftTagText);
            tagController.selection = draftTagSelection;
            await tester.pump();

            FocusManager.instance.primaryFocus?.unfocus();
            await _boundedPumpAndSettle(tester);

            // Choose mood (Mood.awesome 😄)
            final moodAwesomeEmoji = Mood.awesome.emoji;
            await _scrollTo(
              tester,
              find.text(moodAwesomeEmoji),
              scrollable: scrollableFinder,
            );
            await tester.tap(find.text(moodAwesomeEmoji));
            await _boundedPumpAndSettle(tester);

            // Choose weather (Weather.rain 🌧️)
            final weatherRainChip = find.byWidgetPredicate(
              (w) =>
                  w is FilterChip &&
                  w.label is Text &&
                  (w.label as Text).data!.contains(Weather.rain.emoji),
            );
            await _scrollTo(
              tester,
              weatherRainChip,
              scrollable: scrollableFinder,
            );
            await tester.tap(weatherRainChip);
            await _boundedPumpAndSettle(tester);
            expect(tester.widget<FilterChip>(weatherRainChip).selected, isTrue);

            // Scroll ListView to establish meaningful nonzero scroll offset
            await tester.drag(scrollableFinder, const Offset(0, -100));
            await _boundedPumpAndSettle(tester);
            final savedScrollOffset = tester
                .state<ScrollableState>(scrollableFinder)
                .position
                .pixels;
            expect(
              savedScrollOffset,
              greaterThan(0),
              reason: 'Must establish meaningful nonzero scroll offset',
            );

            // Inspect draft across sections and restore saved offset
            await _inspectAllSections(
              tester: tester,
              scrollableFinder: scrollableFinder,
              contentController: contentController,
              tagController: tagController,
              expectedBrandId: scenario.initialBrand,
              expectedDraftContent: draftContentText,
              expectedContentSelection: draftContentSelection,
              expectedDraftTag: draftTagText,
              expectedTagSelection: draftTagSelection,
              expectedMood: Mood.awesome,
              expectedWeather: Weather.rain,
              baselineDate: baselineDate,
              savedScrollOffset: savedScrollOffset,
            );

            expect(
              tester.state<ScrollableState>(scrollableFinder).position.pixels,
              savedScrollOffset,
            );
            expect(recordedRequests, isEmpty);
            expect(store.diaryWrites, baselineDiaryWrites);
            expect(diaries.saves, 0);
            await _capture(tester, boundary, '${scenario.name}-02-draft');

            // 3. Live brand switch to targetBrand
            await tester.runAsync(() async {
              final switched = await theme.setBrand(scenario.targetBrand);
              expect(switched, isTrue);
              await AccountPreferenceWrites.drain().timeout(
                const Duration(seconds: 5),
              );
            });
            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);

            // Retain exact nonzero scroll offset immediately after theme switch
            final scrollOffsetAfterBrandSwitch = tester
                .state<ScrollableState>(scrollableFinder)
                .position
                .pixels;
            expect(
              scrollOffsetAfterBrandSwitch,
              savedScrollOffset,
              reason: 'Exact retained nonzero scroll offset on theme switch',
            );

            expect(theme.brand.id, scenario.targetBrand);
            final prefsAfterSwitch = await SharedPreferences.getInstance();
            expect(
              prefsAfterSwitch.getString('active_brand'),
              scenario.targetBrand,
            );

            // Assert State, ModalRoute, and surface style
            expect(
              identical(tester.state(editorFinder), initialEditorState),
              isTrue,
              reason: 'State identity must be preserved across brand switch',
            );
            expect(
              identical(
                ModalRoute.of(tester.element(editorFinder)),
                initialModalRoute,
              ),
              isTrue,
              reason:
                  'ModalRoute identity must be preserved across brand switch',
            );
            expect(
              appSurfaceStyleOf(tester.element(editorFinder)),
              equals(
                scenario.targetBrand == 'liquidGlass'
                    ? AppSurfaceStyle.liquidGlass
                    : AppSurfaceStyle.ios,
              ),
            );

            // Inspect sections under new brand and restore saved offset
            await _inspectAllSections(
              tester: tester,
              scrollableFinder: scrollableFinder,
              contentController: contentController,
              tagController: tagController,
              expectedBrandId: scenario.targetBrand,
              expectedDraftContent: draftContentText,
              expectedContentSelection: draftContentSelection,
              expectedDraftTag: draftTagText,
              expectedTagSelection: draftTagSelection,
              expectedMood: Mood.awesome,
              expectedWeather: Weather.rain,
              baselineDate: baselineDate,
              savedScrollOffset: savedScrollOffset,
            );

            expect(
              tester.state<ScrollableState>(scrollableFinder).position.pixels,
              savedScrollOffset,
            );
            expect(recordedRequests, isEmpty);
            expect(store.diaryWrites, baselineDiaryWrites);
            expect(diaries.saves, 0);
            await _capture(
              tester,
              boundary,
              '${scenario.name}-03-switchedBrand',
            );

            // 4. Live locale switch to alternative locale and back
            final altLocale = scenario.locale == AppLocale.zh
                ? AppLocale.en
                : AppLocale.zh;
            I18n.setLocale(altLocale);
            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);
            final localizedPosition = tester
                .state<ScrollableState>(scrollableFinder)
                .position;
            expect(
              localizedPosition.pixels,
              closeTo(
                savedScrollOffset.clamp(
                  localizedPosition.minScrollExtent,
                  localizedPosition.maxScrollExtent,
                ),
                0.01,
              ),
            );

            expect(find.text(I18n.tr('diary.title')), findsOneWidget);
            expect(
              identical(tester.state(editorFinder), initialEditorState),
              isTrue,
              reason: 'State identity must be preserved across locale switch',
            );
            expect(
              identical(
                ModalRoute.of(tester.element(editorFinder)),
                initialModalRoute,
              ),
              isTrue,
              reason:
                  'ModalRoute identity must be preserved across locale switch',
            );

            // Inspect relocalized UI in alternative locale
            await _inspectAllSections(
              tester: tester,
              scrollableFinder: scrollableFinder,
              contentController: contentController,
              tagController: tagController,
              expectedBrandId: scenario.targetBrand,
              expectedDraftContent: draftContentText,
              expectedContentSelection: draftContentSelection,
              expectedDraftTag: draftTagText,
              expectedTagSelection: draftTagSelection,
              expectedMood: Mood.awesome,
              expectedWeather: Weather.rain,
              baselineDate: baselineDate,
              savedScrollOffset: savedScrollOffset,
            );

            expect(recordedRequests, isEmpty);
            expect(store.diaryWrites, baselineDiaryWrites);
            expect(diaries.saves, 0);

            // Switch locale back to scenario original locale
            I18n.setLocale(scenario.locale);
            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);
            final localeBackPosition = tester
                .state<ScrollableState>(scrollableFinder)
                .position;
            expect(
              localeBackPosition.pixels,
              closeTo(
                savedScrollOffset.clamp(
                  localeBackPosition.minScrollExtent,
                  localeBackPosition.maxScrollExtent,
                ),
                0.01,
              ),
            );

            expect(find.text(I18n.tr('diary.title')), findsOneWidget);
            expect(
              identical(tester.state(editorFinder), initialEditorState),
              isTrue,
            );
            expect(
              identical(
                ModalRoute.of(tester.element(editorFinder)),
                initialModalRoute,
              ),
              isTrue,
            );

            // Inspect relocalized UI in restored locale
            await _inspectAllSections(
              tester: tester,
              scrollableFinder: scrollableFinder,
              contentController: contentController,
              tagController: tagController,
              expectedBrandId: scenario.targetBrand,
              expectedDraftContent: draftContentText,
              expectedContentSelection: draftContentSelection,
              expectedDraftTag: draftTagText,
              expectedTagSelection: draftTagSelection,
              expectedMood: Mood.awesome,
              expectedWeather: Weather.rain,
              baselineDate: baselineDate,
              savedScrollOffset: savedScrollOffset,
            );

            expect(
              tester.state<ScrollableState>(scrollableFinder).position.pixels,
              savedScrollOffset,
            );
            expect(recordedRequests, isEmpty);
            expect(store.diaryWrites, baselineDiaryWrites);
            expect(diaries.saves, 0);

            // 5. Live brand roundtrip back to initialBrand
            await tester.runAsync(() async {
              final reverted = await theme.setBrand(scenario.initialBrand);
              expect(reverted, isTrue);
              await AccountPreferenceWrites.drain().timeout(
                const Duration(seconds: 5),
              );
            });
            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);

            // Retain exact nonzero scroll offset immediately after theme revert
            final scrollOffsetAfterBrandRevert = tester
                .state<ScrollableState>(scrollableFinder)
                .position
                .pixels;
            expect(
              scrollOffsetAfterBrandRevert,
              savedScrollOffset,
              reason: 'Exact retained nonzero scroll offset on theme revert',
            );

            expect(theme.brand.id, scenario.initialBrand);
            final prefsAfterRevert = await SharedPreferences.getInstance();
            expect(
              prefsAfterRevert.getString('active_brand'),
              scenario.initialBrand,
            );

            // Assert State, ModalRoute, and reverted surface style
            expect(
              identical(tester.state(editorFinder), initialEditorState),
              isTrue,
              reason:
                  'State identity must be preserved across brand revert roundtrip',
            );
            expect(
              identical(
                ModalRoute.of(tester.element(editorFinder)),
                initialModalRoute,
              ),
              isTrue,
              reason:
                  'ModalRoute identity must be preserved across brand revert roundtrip',
            );
            expect(
              appSurfaceStyleOf(tester.element(editorFinder)),
              equals(
                scenario.initialBrand == 'liquidGlass'
                    ? AppSurfaceStyle.liquidGlass
                    : AppSurfaceStyle.ios,
              ),
            );

            // Inspect sections under reverted brand
            await _inspectAllSections(
              tester: tester,
              scrollableFinder: scrollableFinder,
              contentController: contentController,
              tagController: tagController,
              expectedBrandId: scenario.initialBrand,
              expectedDraftContent: draftContentText,
              expectedContentSelection: draftContentSelection,
              expectedDraftTag: draftTagText,
              expectedTagSelection: draftTagSelection,
              expectedMood: Mood.awesome,
              expectedWeather: Weather.rain,
              baselineDate: baselineDate,
              savedScrollOffset: savedScrollOffset,
            );

            expect(
              tester.state<ScrollableState>(scrollableFinder).position.pixels,
              savedScrollOffset,
            );
            expect(recordedRequests, isEmpty);
            expect(store.diaryWrites, baselineDiaryWrites);
            expect(diaries.saves, 0);
            await _capture(
              tester,
              boundary,
              '${scenario.name}-04-revertedBrand',
            );

            // 6. Explicit outcome: Discard vs Save
            if (scenario.outcome == _DiaryContractOutcome.discard) {
              final backButton = find.byType(BackButton);
              expect(backButton, findsOneWidget);
              await tester.ensureVisible(backButton);
              await _boundedPumpAndSettle(tester);
              await tester.tap(backButton);
              await _drainAccountWrites(tester);
              await _boundedPumpAndSettle(tester);
              expect(tester.takeException(), isNull);

              expect(find.byType(DiaryEditScreen), findsNothing);
              expect(find.text('Open diary editor'), findsOneWidget);

              // Discard contract: zero writes to server API or local stores
              expect(recordedRequests, isEmpty);
              expect(store.diaryWrites, baselineDiaryWrites);
              expect(diaries.saves, 0);

              // Source entry preserved byte-for-byte
              expect(jsonEncode(baselineEntry.toJson()), baselineSerialized);
              expect(
                baselineEntry.content,
                'Synthetic baseline diary content for ${scenario.name}',
              );
              expect(baselineEntry.mood, Mood.good);
              expect(baselineEntry.weather, Weather.sunny);
              expect(baselineEntry.tags, const ['original-tag']);

              // Provider in-memory state unchanged
              expect(diaries.entries.length, 1);
              expect(
                diaries.entries.first.content,
                'Synthetic baseline diary content for ${scenario.name}',
              );
              expect(diaries.entries.first.mood, Mood.good);
              expect(diaries.entries.first.weather, Weather.sunny);
              expect(diaries.entries.first.tags, const ['original-tag']);

              // Persisted SharedPreferences unchanged
              final storedList = (await SharedPreferences.getInstance())
                  .getStringList('duoyi_diary');
              expect(storedList, isNotNull);
              expect(storedList!.length, 1);
              expect(storedList.first, baselineSerialized);

              // Account data generation preserved
              expect(
                AccountLocalDataCleaner.accountDataGeneration,
                baselineAccountGeneration,
              );
              await _capture(tester, boundary, '${scenario.name}-05-discarded');
            } else {
              // Save contract
              expect(recordedRequests, isEmpty);
              expect(store.diaryWrites, baselineDiaryWrites);
              expect(diaries.saves, 0);

              final saveButton = find.widgetWithIcon(IconButton, Icons.check);
              expect(saveButton, findsOneWidget);
              await tester.ensureVisible(saveButton);
              await _boundedPumpAndSettle(tester);
              await tester.tap(saveButton);
              await _drainAccountWrites(tester);
              await _boundedPumpAndSettle(tester);
              expect(tester.takeException(), isNull);

              expect(find.byType(DiaryEditScreen), findsNothing);
              expect(find.text('Open diary editor'), findsOneWidget);

              // Zero network requests
              expect(recordedRequests, isEmpty);

              // Verified: local store writes occurred exactly for this save
              expect(
                store.diaryWrites,
                baselineDiaryWrites + 1,
                reason: 'Explicit save must persist duoyi_diary to local store',
              );

              expect(diaries.saves, 1);

              // Verified: in-memory provider state updated with draft
              expect(diaries.entries.length, 1);
              final updatedEntry = diaries.entries.first;
              expect(updatedEntry.id, baselineEntry.id);
              expect(updatedEntry.content, draftContentText);
              expect(updatedEntry.mood, Mood.awesome);
              expect(updatedEntry.weather, Weather.rain);
              expect(updatedEntry.tags, const ['original-tag']);

              // Verified: persisted SharedPreferences updated with draft
              final storedList = (await SharedPreferences.getInstance())
                  .getStringList('duoyi_diary');
              expect(storedList, isNotNull);
              expect(storedList!.length, 1);
              final storedJson =
                  jsonDecode(storedList.first) as Map<String, dynamic>;
              expect(storedJson['id'], baselineEntry.id);
              expect(storedJson['content'], draftContentText);
              expect(storedJson['mood'], Mood.awesome.index);
              expect(storedJson['weather'], Weather.rain.index);
              expect(storedJson['tags'], const ['original-tag']);

              // Source entry byte-for-byte check (not mutated in place)
              expect(jsonEncode(baselineEntry.toJson()), baselineSerialized);

              // Account data generation preserved
              expect(
                AccountLocalDataCleaner.accountDataGeneration,
                baselineAccountGeneration,
              );
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
              diaries.dispose();
              theme.dispose();
              preferences.dispose();
              tester.view.reset();
              debugDisableShadows = originalShadows;
              I18n.setLocale(originalLocale);
            }
          }
        },
        createHttpClient: (_) {
          recordedRequests.add('HTTP client creation');
          throw StateError('Unexpected network client during diary fixture');
        },
      );
    });
  }
}
