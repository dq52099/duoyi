// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/export_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
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

class _FixturePreferencesProvider extends PreferencesProvider {
  _FixturePreferencesProvider();
}

class _SyntheticAnniversaries extends AnniversaryProvider {
  _SyntheticAnniversaries(this._items);

  final List<Anniversary> _items;

  @override
  List<Anniversary> get items => _items;
}

class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore(super.data) : super.withData();

  int businessWrites = 0;
  int businessRemoves = 0;
  final List<String> businessWrittenKeys = [];

  static bool _isThemeKey(String key) {
    final clean = key.startsWith('flutter.') ? key.substring(8) : key;
    return clean == 'active_brand' ||
        clean == 'theme_switch_count' ||
        clean == 'theme_shop_state' ||
        clean == 'theme_unlocked_brands' ||
        clean.startsWith('theme_');
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (!_isThemeKey(key)) {
      businessWrites++;
      businessWrittenKeys.add(key);
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    if (!_isThemeKey(key)) {
      businessRemoves++;
    }
    return super.remove(key);
  }
}

class _ExportLiveBrandScenario {
  const _ExportLiveBrandScenario({
    required this.name,
    required this.locale,
    required this.size,
    required this.rangeToSelect,
    required this.testExplicitCopy,
  });

  final String name;
  final AppLocale locale;
  final Size size;
  final String rangeToSelect; // 'anniversary' or 'calendar'
  final bool testExplicitCopy;
}

const _scenarios = [
  _ExportLiveBrandScenario(
    name: 'zh-portrait-320x844-anniversary-copy',
    locale: AppLocale.zh,
    size: Size(320, 844),
    rangeToSelect: 'anniversary',
    testExplicitCopy: true,
  ),
  _ExportLiveBrandScenario(
    name: 'en-portrait-320x844-calendar-nocopy',
    locale: AppLocale.en,
    size: Size(320, 844),
    rangeToSelect: 'calendar',
    testExplicitCopy: false,
  ),
  _ExportLiveBrandScenario(
    name: 'zh-landscape-568x320-calendar-nocopy',
    locale: AppLocale.zh,
    size: Size(568, 320),
    rangeToSelect: 'calendar',
    testExplicitCopy: false,
  ),
  _ExportLiveBrandScenario(
    name: 'en-landscape-568x320-anniversary-copy',
    locale: AppLocale.en,
    size: Size(568, 320),
    rangeToSelect: 'anniversary',
    testExplicitCopy: true,
  ),
];

Future<int> _boundedPumpAndSettle(
  WidgetTester tester, [
  Duration duration = const Duration(milliseconds: 50),
  EnginePhase phase = EnginePhase.sendSemanticsUpdate,
  Duration timeout = const Duration(seconds: 5),
]) {
  return tester.pumpAndSettle(duration, phase, timeout);
}

Future<void> _drainPreferenceWrites(WidgetTester tester) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.runAsync(() async {
    await AccountPreferenceWrites.drain().timeout(
      const Duration(seconds: 5),
      onTimeout: () =>
          throw TimeoutException('AccountPreferenceWrites.drain timed out'),
    );
  });
}

Finder _exportListScrollable() {
  return find
      .descendant(
        of: find.byKey(const PageStorageKey('export_list')),
        matching: find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axis == Axis.vertical,
        ),
      )
      .first;
}

Finder _previewSelectableText() {
  return find
      .descendant(
        of: find.byKey(const PageStorageKey('export_list')),
        matching: find.byType(SelectableText),
      )
      .first;
}

List<bool> _switchValues(WidgetTester tester) {
  return tester
      .widgetList<AppSwitchTile>(find.byType(AppSwitchTile))
      .map((tile) => tile.value)
      .toList();
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await _boundedPumpAndSettle(tester);
  expect(target.hitTestable(), findsOneWidget);
}

Future<void> _expectRangeControls(
  WidgetTester tester,
  List<bool> expected,
) async {
  final position = tester
      .state<ScrollableState>(_exportListScrollable())
      .position;
  final savedOffset = position.pixels;
  position.jumpTo(0);
  await _boundedPumpAndSettle(tester);
  await tester.scrollUntilVisible(
    find.byType(AppSwitchTile).first,
    120,
    scrollable: _exportListScrollable(),
    maxScrolls: 30,
  );
  await _boundedPumpAndSettle(tester);
  expect(_switchValues(tester), expected);
  expect(find.text(I18n.tr('export.include_anniversaries')), findsOneWidget);
  expect(find.text(I18n.tr('export.include_calendar')), findsOneWidget);
  position.jumpTo(
    savedOffset.clamp(position.minScrollExtent, position.maxScrollExtent),
  );
  await _boundedPumpAndSettle(tester);
}

Future<void> _captureScreenshot(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final explicitDir =
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
  if (explicitDir == null || explicitDir.isEmpty) return;

  await tester.runAsync(() async {
    final render =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (render == null) return;
    final image = await render.toImage(pixelRatio: 1);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final file = File('$explicitDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(byteData.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));

  for (final scenario in _scenarios) {
    testWidgets(
      'Settings export live brand priority roundtrip defaultBrand <-> liquidGlass: ${scenario.name}',
      (tester) async {
        final previousShadows = debugDisableShadows;
        final initialLocale = I18n.current;
        final originalSystemTimeZoneReader =
            LocalTimezoneResolver.debugSystemTimeZoneReader;
        final originalNativeTimeZoneReader =
            LocalTimezoneResolver.debugNativeSystemTimeZoneReader;
        final previousStore = SharedPreferencesStorePlatform.instance;

        final anniversaryFixture = Anniversary(
          id: 'birthday-mom',
          title: '妈妈生日',
          originDate: DateTime(2000, 5, 20),
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          type: AnniversaryType.birthday,
          description: '全家聚会',
        );

        final calendarFixture = CalendarEvent(
          id: 'local-event-1',
          title: 'Project Kickoff',
          date: DateTime(2027, 3, 15, 10, 0),
          type: CalendarEventType.event,
          color: Colors.blue,
        );

        final initialPrefs = <String, Object>{
          'active_brand': 'defaultBrand',
          'theme_shop_state': jsonEncode({
            'activeBrand': 'defaultBrand',
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          }),
          'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          'flutter.active_brand': 'defaultBrand',
          'flutter.theme_shop_state': jsonEncode({
            'activeBrand': 'defaultBrand',
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          }),
          'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          LocalTimezoneResolver.modePreferenceKey:
              LocalTimezoneResolver.fixedValue,
          LocalTimezoneResolver.preferenceKey: 'Asia/Shanghai',
          'duoyi_local_calendar_events_v1': [
            jsonEncode(calendarFixture.toJson()),
          ],
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
        LocalTimezoneResolver.debugNativeSystemTimeZoneReader = () async =>
            null;

        final copies = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              final arguments = call.arguments;
              if (arguments is Map && arguments['text'] is String) {
                copies.add(arguments['text'] as String);
              }
            }
            return null;
          },
        );

        final theme = ThemeProvider();
        final auth = AuthProvider(
          client: ApiClient(
            baseUrl: 'https://duoyi.test',
            token: 'synthetic-token',
            httpClient: MockClient((request) async {
              fail(
                'Export screen live brand test must never make external HTTP calls: ${request.url}',
              );
            }),
          ),
          initialState: const AuthState(
            userId: 'synthetic-user',
            username: 'Synthetic User',
            token: 'synthetic-token',
          ),
        );
        final anniversaries = _SyntheticAnniversaries([anniversaryFixture]);
        final calendar = CalendarProvider();
        final todo = TodoProvider();
        final habit = HabitProvider();
        final pomodoro = PomodoroProvider();
        final course = CourseProvider();
        final diary = DiaryProvider();
        final countdown = CountdownProvider();
        final goal = GoalProvider();
        final sync = CalendarSyncProvider();
        final preferences = _FixturePreferencesProvider();

        final boundaryKey = GlobalKey();

        try {
          debugDisableShadows = false;
          I18n.setLocale(scenario.locale);

          tester.view.physicalSize = scenario.size;
          tester.view.devicePixelRatio = 1.0;

          await tester.runAsync(() async {
            await theme.loadFromStorage();
            await calendar.loadFromStorage();
            await loadWeeklyReviewScreenshotFonts();
          });

          await _drainPreferenceWrites(tester);

          // Reset write counters after initial seed & drain
          store.businessWrites = 0;
          store.businessRemoves = 0;
          store.businessWrittenKeys.clear();

          expect(theme.brand.id, 'defaultBrand');
          expect(theme.isBrandUnlocked('liquidGlass'), isTrue);

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
                ChangeNotifierProvider<AnniversaryProvider>.value(
                  value: anniversaries,
                ),
                ChangeNotifierProvider<CalendarProvider>.value(value: calendar),
                ChangeNotifierProvider<TodoProvider>.value(value: todo),
                ChangeNotifierProvider<HabitProvider>.value(value: habit),
                ChangeNotifierProvider<PomodoroProvider>.value(value: pomodoro),
                ChangeNotifierProvider<CourseProvider>.value(value: course),
                ChangeNotifierProvider<DiaryProvider>.value(value: diary),
                ChangeNotifierProvider<CountdownProvider>.value(
                  value: countdown,
                ),
                ChangeNotifierProvider<GoalProvider>.value(value: goal),
                ChangeNotifierProvider<CalendarSyncProvider>.value(value: sync),
                ChangeNotifierProvider<PreferencesProvider>.value(
                  value: preferences,
                ),
              ],
              child: AnimatedBuilder(
                animation: Listenable.merge([theme, I18n.localeListenable]),
                builder: (context, _) => MaterialApp(
                  locale: Locale(I18n.current == AppLocale.en ? 'en' : 'zh'),
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: theme.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(2.0)),
                    child: RepaintBoundary(key: boundaryKey, child: child!),
                  ),
                  home: const BrandRouteSurface(
                    remountOnLocaleChange: false,
                    child: ExportScreen(),
                  ),
                ),
              ),
            ),
          );
          await _boundedPumpAndSettle(tester);

          final screenFinder = find.byType(ExportScreen);
          expect(screenFinder, findsOneWidget);

          // Check initial localized labels
          expect(find.text(I18n.tr('export.title')), findsOneWidget);
          expect(find.text(I18n.tr('export.range.title')), findsOneWidget);
          expect(
            find.text(I18n.tr('export.include_anniversaries')),
            findsOneWidget,
          );
          expect(find.text(I18n.tr('export.include_calendar')), findsOneWidget);

          // Select one export range
          final initialTiles = tester
              .widgetList<AppSwitchTile>(find.byType(AppSwitchTile))
              .toList();
          expect(initialTiles, hasLength(2));
          expect(initialTiles[0].value, isTrue);
          expect(initialTiles[1].value, isTrue);

          if (scenario.rangeToSelect == 'anniversary') {
            // Toggle off calendar (index 1), keeping anniversary
            final toggle = find.descendant(
              of: find.byType(AppSwitchTile).at(1),
              matching: find.byType(Switch),
            );
            await _reveal(tester, toggle);
            await tester.tap(toggle);
          } else {
            // Toggle off anniversary (index 0), keeping calendar
            final toggle = find.descendant(
              of: find.byType(AppSwitchTile).first,
              matching: find.byType(Switch),
            );
            await _reveal(tester, toggle);
            await tester.tap(toggle);
          }
          await _boundedPumpAndSettle(tester);

          final selectedTiles = _switchValues(tester);
          if (scenario.rangeToSelect == 'anniversary') {
            expect(selectedTiles, [true, false]);
          } else {
            expect(selectedTiles, [false, true]);
          }

          // Generate real local document once
          final generateFinder = find.byKey(const ValueKey('export_generate'));
          await tester.scrollUntilVisible(
            generateFinder,
            120,
            scrollable: _exportListScrollable(),
            maxScrolls: 30,
          );
          await _boundedPumpAndSettle(tester);
          expect(generateFinder, findsOneWidget);

          final generateBtn = tester.widget<FilledButton>(generateFinder);
          expect(generateBtn.onPressed, isNotNull);
          await _reveal(tester, generateFinder);
          await tester.tap(generateFinder);
          await _boundedPumpAndSettle(tester);

          // Scroll to preview
          final previewFinder = _previewSelectableText();
          expect(previewFinder, findsOneWidget);
          await tester.scrollUntilVisible(
            previewFinder,
            160,
            scrollable: _exportListScrollable(),
            maxScrolls: 30,
          );
          await _boundedPumpAndSettle(tester);

          final initialIcs = tester.widget<SelectableText>(previewFinder).data!;
          expect(initialIcs, contains('BEGIN:VCALENDAR'));
          expect(initialIcs, contains('END:VCALENDAR'));
          if (scenario.rangeToSelect == 'anniversary') {
            expect(initialIcs, contains('UID:anni_birthday-mom@duoyi'));
            expect(initialIcs, contains('SUMMARY:妈妈生日'));
            expect(initialIcs, isNot(contains('SUMMARY:Project Kickoff')));
          } else {
            expect(initialIcs, contains('UID:local-event-1'));
            expect(initialIcs, contains('SUMMARY:Project Kickoff'));
            expect(initialIcs, isNot(contains('SUMMARY:妈妈生日')));
          }

          // Record baseline state, route, scroll position, and controller identities
          final stateBefore = tester.state(screenFinder);
          final modalRouteBefore = ModalRoute.of(tester.element(screenFinder));
          expect(modalRouteBefore, isNotNull);

          final scrollableState = tester.state<ScrollableState>(
            _exportListScrollable(),
          );
          final scrollControllerBefore =
              scrollableState.widget.controller ??
              PrimaryScrollController.of(tester.element(screenFinder));
          final scrollOffsetBefore = scrollableState.position.pixels;
          expect(scrollOffsetBefore, greaterThan(0.0));

          final rangeSwitchValuesBefore = selectedTiles;
          await _expectRangeControls(tester, rangeSwitchValuesBefore);

          // Ensure preview title and copy button are mounted
          expect(find.text(I18n.tr('export.content.title')), findsOneWidget);
          expect(find.text(I18n.tr('export.copy')), findsOneWidget);

          // Capture initial screenshot
          await _captureScreenshot(
            tester,
            boundaryKey,
            '${scenario.name}-01-initial-defaultBrand',
          );

          // -------------------------------------------------------------
          // Step 1: Live switch from defaultBrand -> liquidGlass
          // -------------------------------------------------------------
          await tester.runAsync(() async {
            final switched = await theme.setBrand('liquidGlass');
            expect(switched, isTrue);
          });
          await _boundedPumpAndSettle(tester);

          expect(theme.brand.id, 'liquidGlass');
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getString('active_brand'), 'liquidGlass');

          // Verify theme & liquidGlass transparent scaffold contract
          final glassCs = Theme.of(tester.element(screenFinder)).colorScheme;
          expect(
            glassCs.primary,
            equals(AppBrands.liquidGlass.theme.colorScheme.primary),
          );
          final glassScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
          expect(glassScaffold.backgroundColor, equals(Colors.transparent));

          // Retain exact screen State, ModalRoute, scroll controller and offset
          expect(tester.state(screenFinder), same(stateBefore));
          expect(
            ModalRoute.of(tester.element(screenFinder)),
            same(modalRouteBefore),
          );
          final glassScrollState = tester.state<ScrollableState>(
            _exportListScrollable(),
          );
          expect(glassScrollState, same(scrollableState));
          final glassScrollController =
              glassScrollState.widget.controller ??
              PrimaryScrollController.of(tester.element(screenFinder));
          expect(glassScrollController, same(scrollControllerBefore));
          expect(
            glassScrollState.position.pixels,
            closeTo(scrollOffsetBefore, 0.01),
          );

          // Retain exact generated bytes and range control values
          final glassIcs = tester
              .widget<SelectableText>(_previewSelectableText())
              .data;
          expect(glassIcs, equals(initialIcs));
          await _expectRangeControls(tester, rangeSwitchValuesBefore);

          // No clipboard writes or business storage writes
          expect(copies, isEmpty);
          expect(store.businessWrites, 0);

          await _captureScreenshot(
            tester,
            boundaryKey,
            '${scenario.name}-02-applied-liquidGlass',
          );

          // -------------------------------------------------------------
          // Step 2: Live switch from liquidGlass -> defaultBrand (roundtrip)
          // -------------------------------------------------------------
          await tester.runAsync(() async {
            final reverted = await theme.setBrand('defaultBrand');
            expect(reverted, isTrue);
          });
          await _boundedPumpAndSettle(tester);

          expect(theme.brand.id, 'defaultBrand');
          expect(prefs.getString('active_brand'), 'defaultBrand');

          final defaultCs = Theme.of(tester.element(screenFinder)).colorScheme;
          expect(
            defaultCs.primary,
            equals(AppBrands.defaultBrand.theme.colorScheme.primary),
          );
          final defaultScaffold = tester.widget<Scaffold>(
            find.byType(Scaffold),
          );
          expect(defaultScaffold.backgroundColor, isNot(Colors.transparent));

          // Retain exact screen State, ModalRoute, scroll controller and offset
          expect(tester.state(screenFinder), same(stateBefore));
          expect(
            ModalRoute.of(tester.element(screenFinder)),
            same(modalRouteBefore),
          );
          final defaultScrollState = tester.state<ScrollableState>(
            _exportListScrollable(),
          );
          expect(defaultScrollState, same(scrollableState));
          final defaultScrollController =
              defaultScrollState.widget.controller ??
              PrimaryScrollController.of(tester.element(screenFinder));
          expect(defaultScrollController, same(scrollControllerBefore));
          expect(
            defaultScrollState.position.pixels,
            closeTo(scrollOffsetBefore, 0.01),
          );

          // Retain exact generated bytes and range control values
          expect(
            tester.widget<SelectableText>(_previewSelectableText()).data,
            equals(initialIcs),
          );
          await _expectRangeControls(tester, rangeSwitchValuesBefore);

          expect(copies, isEmpty);
          expect(store.businessWrites, 0);

          await _captureScreenshot(
            tester,
            boundaryKey,
            '${scenario.name}-03-reverted-defaultBrand',
          );

          // -------------------------------------------------------------
          // Step 3: Live locale switch across roundtrip
          // -------------------------------------------------------------
          final oppositeLocale = scenario.locale == AppLocale.zh
              ? AppLocale.en
              : AppLocale.zh;
          I18n.setLocale(oppositeLocale);
          await _boundedPumpAndSettle(tester);

          // Check updated localized labels
          expect(find.text(I18n.tr('export.title')), findsOneWidget);

          expect(find.text(I18n.tr('export.content.title')), findsOneWidget);
          expect(find.text(I18n.tr('export.copy')), findsOneWidget);

          // Retain state, route, scroll offset, exact bytes, and switches
          expect(tester.state(screenFinder), same(stateBefore));
          expect(
            ModalRoute.of(tester.element(screenFinder)),
            same(modalRouteBefore),
          );
          final oppositeScrollState = tester.state<ScrollableState>(
            _exportListScrollable(),
          );
          expect(oppositeScrollState, same(scrollableState));
          expect(
            oppositeScrollState.position.pixels,
            closeTo(
              scrollOffsetBefore.clamp(
                oppositeScrollState.position.minScrollExtent,
                oppositeScrollState.position.maxScrollExtent,
              ),
              0.01,
            ),
          );
          expect(oppositeScrollState.position.pixels, greaterThan(0));
          expect(
            tester.widget<SelectableText>(_previewSelectableText()).data,
            equals(initialIcs),
          );
          await _expectRangeControls(tester, rangeSwitchValuesBefore);
          expect(copies, isEmpty);
          expect(store.businessWrites, 0);

          await _captureScreenshot(
            tester,
            boundaryKey,
            '${scenario.name}-04-locale-opposite',
          );

          // Switch back to original locale
          final beforeLocaleRestore = oppositeScrollState.position.pixels;
          I18n.setLocale(scenario.locale);
          await _boundedPumpAndSettle(tester);

          expect(find.text(I18n.tr('export.title')), findsOneWidget);

          expect(find.text(I18n.tr('export.content.title')), findsOneWidget);
          expect(find.text(I18n.tr('export.copy')), findsOneWidget);

          expect(tester.state(screenFinder), same(stateBefore));
          expect(
            ModalRoute.of(tester.element(screenFinder)),
            same(modalRouteBefore),
          );
          final restoredScrollState = tester.state<ScrollableState>(
            _exportListScrollable(),
          );
          expect(restoredScrollState, same(scrollableState));
          expect(
            restoredScrollState.position.pixels,
            closeTo(
              beforeLocaleRestore.clamp(
                restoredScrollState.position.minScrollExtent,
                restoredScrollState.position.maxScrollExtent,
              ),
              0.01,
            ),
          );
          expect(
            tester.widget<SelectableText>(_previewSelectableText()).data,
            equals(initialIcs),
          );
          await _expectRangeControls(tester, rangeSwitchValuesBefore);
          expect(copies, isEmpty);
          expect(store.businessWrites, 0);

          // -------------------------------------------------------------
          // Step 4: Explicit Copy action (2 scenarios) or exit without copy (2 scenarios)
          // -------------------------------------------------------------
          if (scenario.testExplicitCopy) {
            final copyBtnFinder = find.byKey(const ValueKey('export_copy'));
            expect(copyBtnFinder, findsOneWidget);
            await tester.ensureVisible(copyBtnFinder);
            await _boundedPumpAndSettle(tester);

            final copyBtn = tester.widget<TextButton>(copyBtnFinder);
            expect(copyBtn.onPressed, isNotNull);
            await _reveal(tester, copyBtnFinder);
            await tester.tap(copyBtnFinder);
            await _boundedPumpAndSettle(tester);

            expect(copies, hasLength(1));
            expect(copies.single, equals(initialIcs));
            expect(find.text(I18n.tr('export.copy.done')), findsOneWidget);
          } else {
            expect(copies, isEmpty);
          }

          // Final invariant assertions
          expect(store.businessWrites, 0);
          expect(store.businessRemoves, 0);
          expect(tester.takeException(), isNull);
        } finally {
          debugDisableShadows = previousShadows;
          I18n.setLocale(initialLocale);
          LocalTimezoneResolver.debugSystemTimeZoneReader =
              originalSystemTimeZoneReader;
          LocalTimezoneResolver.debugNativeSystemTimeZoneReader =
              originalNativeTimeZoneReader;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
          SharedPreferencesStorePlatform.instance = previousStore;
          tester.view.reset();

          await tester.pumpWidget(const SizedBox.shrink());
          await _boundedPumpAndSettle(tester);

          theme.dispose();
          auth.dispose();
          anniversaries.dispose();
          calendar.dispose();
          todo.dispose();
          habit.dispose();
          pomodoro.dispose();
          course.dispose();
          diary.dispose();
          countdown.dispose();
          goal.dispose();
          sync.dispose();
          preferences.dispose();
        }
      },
    );
  }
}
