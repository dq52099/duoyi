import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/calendar_aggregator.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/today_ui_copy.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/widget_schedule_detail_route.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/widget_launch_access.dart';
import 'package:duoyi/services/widget_navigation_request.dart';
import 'package:duoyi/services/widget_schedule_projection.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/calendar_event_sheet.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/rendered_control_contrast.dart';
import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

const _id = '  record /?#&=% 测试  ';
final _day = DateTime(2023, 3, 22, 9, 15);
const _defaultTailSize = Size(390, 844);

const _knownThemeMetadataKeys = {
  'active_brand',
  'flutter.active_brand',
  'theme_switch_count',
  'flutter.theme_switch_count',
  'theme_shop_state',
  'flutter.theme_shop_state',
};

class _FallbackLayoutScenario {
  final String name;
  final Size size;
  final double scale;
  final double dpr;

  const _FallbackLayoutScenario({
    required this.name,
    required this.size,
    required this.scale,
    required this.dpr,
  });
}

const _priorityLayouts = <_FallbackLayoutScenario>[
  _FallbackLayoutScenario(
    name: 'narrow-scale2-dpr2',
    size: Size(320, 844),
    scale: 2.0,
    dpr: 2.0,
  ),
  _FallbackLayoutScenario(
    name: 'landscape-844x390-dpr1',
    size: Size(844, 390),
    scale: 1.0,
    dpr: 1.0,
  ),
  _FallbackLayoutScenario(
    name: 'ordinary-390-dpr1',
    size: Size(390, 844),
    scale: 1.0,
    dpr: 1.0,
  ),
  _FallbackLayoutScenario(
    name: 'wide-1024-dpr1',
    size: Size(1024, 768),
    scale: 1.0,
    dpr: 1.0,
  ),
  _FallbackLayoutScenario(
    name: 'nonlinear-dpr1',
    size: Size(390, 844),
    scale: -1.0,
    dpr: 1.0,
  ),
];

class _Sessions extends PomodoroProvider {
  int generation = 0;
  List<PomodoroSession> items = [
    PomodoroSession(
      id: _id,
      startTime: _day,
      endTime: _day.add(const Duration(minutes: 25)),
      durationSeconds: 1500,
      type: PomodoroType.focus,
      taskName: 'Published focus',
      tag: 'User tag',
    ),
  ];

  @override
  List<PomodoroSession> get sessions => items;

  @override
  int get storageGeneration => generation;

  @override
  void resetLocalState() {
    generation++;
    items = [];
    notifyListeners();
  }

  void clearRecords() {
    items = [];
    notifyListeners();
  }
}

class _ScheduleFallbackFixture {
  final CalendarProvider originalCalendar;
  late CalendarProvider calendar;
  final _Sessions originalSessions;
  late _Sessions sessions;
  final ThemeProvider theme;
  final FocusRoomProvider rooms;
  final GlobalKey boundary;
  final String host;
  bool blocked;
  int acknowledgements = 0;
  int requeues = 0;
  late WidgetLaunchAccess access;
  final Uri? explicitUri;

  _ScheduleFallbackFixture._({
    required this.host,
    required this.originalCalendar,
    required this.originalSessions,
    required this.theme,
    required this.rooms,
    required this.boundary,
    this.explicitUri,
    this.blocked = false,
  }) {
    calendar = originalCalendar;
    sessions = originalSessions;
  }

  static Future<_ScheduleFallbackFixture> create(
    String host, {
    required String brand,
    Uri? explicitUri,
    bool blocked = false,
  }) async {
    final initialPrefs = <String, Object>{
      'active_brand': brand,
      'theme_shop_state': jsonEncode({
        'activeBrand': brand,
        'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
      }),
      'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
      'flutter.active_brand': brand,
      'flutter.theme_shop_state': jsonEncode({
        'activeBrand': brand,
        'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
      }),
      'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
    };
    SharedPreferences.setMockInitialValues(initialPrefs);
    final theme = ThemeProvider();
    final calendar = CalendarProvider();
    final sessions = _Sessions();
    final rooms = FocusRoomProvider();
    try {
      await theme.loadFromStorage();
      await calendar.loadFromStorage();
      await calendar.addLocalEvent(
        CalendarEvent(
          id: _id,
          title: 'Published local event',
          date: _day,
          type: CalendarEventType.event,
          color: Colors.blue,
          sourceId: 'different-source-alias',
          note: 'User note',
        ),
      );
      return _ScheduleFallbackFixture._(
        host: host,
        originalCalendar: calendar,
        originalSessions: sessions,
        theme: theme,
        rooms: rooms,
        boundary: GlobalKey(),
        explicitUri: explicitUri,
        blocked: blocked,
      );
    } catch (_) {
      theme.dispose();
      calendar.dispose();
      sessions.dispose();
      rooms.dispose();
      rethrow;
    }
  }

  Uri get uri {
    if (explicitUri != null) return explicitUri!;
    final event = host == 'event'
        ? calendar.localEvents.single
        : CalendarAggregator.buildEvents(
            todos: const [],
            habits: const [],
            pomodoroSessions: sessions.sessions,
            colorScheme: theme.brand.theme.colorScheme,
          ).single;
    return Uri.parse(homeWidgetScheduleEventDeepLink(event));
  }

  Widget app({
    required double scale,
    required AppLocale locale,
    required Size expectedSize,
  }) => MultiProvider(
    providers: [
      ChangeNotifierProvider<CalendarProvider>.value(value: calendar),
      ChangeNotifierProvider<PomodoroProvider>.value(value: sessions),
      ChangeNotifierProvider<ThemeProvider>.value(value: theme),
      ChangeNotifierProvider<FocusRoomProvider>.value(value: rooms),
    ],
    child: Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (context, currentLocale, _) => MaterialApp(
          theme: themeProvider.brand.theme,
          locale: Locale(currentLocale == AppLocale.en ? 'en' : 'zh'),
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            expect(media.size, expectedSize);
            return MediaQuery(
              data: media.copyWith(
                textScaler: scale < 0
                    ? const RouteProbeNonlinearScaler()
                    : TextScaler.linear(scale),
              ),
              child: RepaintBoundary(key: boundary, child: child!),
            );
          },
          home: BrandRouteSurface(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Builder(
                builder: (context) => Stack(
                  children: [
                    Center(
                      child: TextButton(
                        key: const ValueKey('open-fallback'),
                        onPressed: () {
                          final targetUri = uri;
                          access = WidgetLaunchAccess(
                            uri: targetUri,
                            request: WidgetNavigationRequests(
                              accountGeneration: () =>
                                  AccountLocalDataCleaner.accountDataGeneration,
                            ).capture(),
                            isBlocked: () => blocked,
                            requeue: (_, _) => requeues++,
                            acknowledge: (_) async {
                              acknowledgements++;
                            },
                          );
                          access.afterFrame(() {
                            unawaited(
                              access.run(
                                () => openWidgetScheduleDetail(
                                  context,
                                  targetUri,
                                  access,
                                ),
                              ),
                            );
                          });
                          access.finishDispatch();
                        },
                        child: const Text('Open fallback'),
                      ),
                    ),
                    for (final brand in [
                      AppBrands.defaultBrand,
                      AppBrands.liquidGlass,
                    ])
                      Offstage(
                        offstage: true,
                        child: Theme(
                          data: brand.theme,
                          child: AppSecondaryControlTheme(
                            child: Builder(
                              key: ValueKey('ref_theme_${brand.id}'),
                              builder: (refContext) => const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> open(
    WidgetTester tester, {
    required double scale,
    required AppLocale locale,
    required Size expectedSize,
  }) async {
    await tester.pumpWidget(
      app(scale: scale, locale: locale, expectedSize: expectedSize),
    );
    await tester.tap(find.byKey(const ValueKey('open-fallback')));
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    originalCalendar.dispose();
    if (!identical(calendar, originalCalendar)) calendar.dispose();
    originalSessions.dispose();
    if (!identical(sessions, originalSessions)) sessions.dispose();
    theme.dispose();
    rooms.dispose();
    I18n.setLocale(AppLocale.zh);
  }
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final explicitDir =
      Platform.environment['DUOYI_RETAINED_DIALOG_SCREENSHOT_DIR'] ??
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
  if (explicitDir == null || explicitDir.isEmpty) return;

  await tester.runAsync(() async {
    final context = boundaryKey.currentContext;
    if (context == null) return;
    final boundary = context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final file = File('$explicitDir/widget-schedule-fallback-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
}

void _assertCompleteText(
  WidgetTester tester,
  Finder textFinder, {
  required String role,
}) {
  expect(textFinder, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: textFinder, matching: find.byType(RichText)),
  );
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '$role exceeded max lines',
  );
  expect(
    paragraph.textSize.width <= paragraph.size.width + 0.5,
    isTrue,
    reason:
        '$role width ${paragraph.textSize.width} exceeds box ${paragraph.size.width}',
  );
  expect(
    paragraph.textSize.height <= paragraph.size.height + 0.5,
    isTrue,
    reason:
        '$role height ${paragraph.textSize.height} exceeds box ${paragraph.size.height}',
  );
}

Future<void> _verifyCoveredCloseGuard({
  required WidgetTester tester,
  required GlobalKey boundaryKey,
}) async {
  final closeFinder = find.widgetWithText(
    FilledButton,
    I18n.tr('action.close'),
  );
  expect(closeFinder, findsOneWidget);
  expectReadableControl(tester, closeFinder);
  expectControlTouchTarget(tester, closeFinder);

  final closeCallback = tester.widget<FilledButton>(closeFinder).onPressed!;
  final sheetRoute = ModalRoute.of(tester.element(closeFinder))!;
  expect(sheetRoute.isCurrent, isTrue);

  final coveringKey = UniqueKey();
  final coveringRoute = MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      body: Center(child: Text('unrelated-covering-route', key: coveringKey)),
    ),
  );
  unawaited(Navigator.of(tester.element(closeFinder)).push(coveringRoute));
  await tester.pumpAndSettle();

  expect(find.byKey(coveringKey), findsOneWidget);
  expect(coveringRoute.isCurrent, isTrue);
  expect(sheetRoute.isCurrent, isFalse);

  // Stale/covered close callback must NOT pop the unrelated covering route!
  closeCallback();
  await tester.pumpAndSettle();

  expect(find.byKey(coveringKey), findsOneWidget);
  expect(coveringRoute.isCurrent, isTrue);
  expect(sheetRoute.isCurrent, isFalse);
  expect(tester.takeException(), isNull);

  // Pop covering route normally.
  Navigator.of(tester.element(find.byKey(coveringKey))).pop();
  await tester.pumpAndSettle();

  expect(find.byKey(coveringKey), findsNothing);
  expect(sheetRoute.isCurrent, isTrue);

  // Normal close for owning route pops the fallback sheet cleanly.
  final normalCloseFinder = find.widgetWithText(
    FilledButton,
    I18n.tr('action.close'),
  );
  expect(normalCloseFinder, findsOneWidget);
  await tester.tap(normalCloseFinder);
  await tester.pumpAndSettle();

  expect(find.byType(AppModalSheet), findsNothing);
  expect(sheetRoute.isActive, isFalse);

  // Invoking the stale callback after the sheet was closed must not pop root or throw.
  closeCallback();
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('open-fallback')), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void _assertRenderedBrandAppearance(
  WidgetTester tester, {
  required String expectedBrandId,
}) {
  final sheetElement = tester.element(find.byType(AppModalSheet));
  final currentTheme = Theme.of(sheetElement);
  final expectedBrand = AppBrands.byId(expectedBrandId);

  expect(
    currentTheme.colorScheme.primary,
    equals(expectedBrand.theme.colorScheme.primary),
    reason: 'ColorScheme.primary must match brand $expectedBrandId',
  );

  final surfaceStyle = appSurfaceStyleOf(sheetElement);
  final expectedSurfaceStyle = expectedBrand.theme.extension<AppSurfaceStyle>();
  expect(
    surfaceStyle?.cardFillColor,
    equals(expectedSurfaceStyle?.cardFillColor),
    reason: 'AppSurfaceStyle cardFillColor must match brand $expectedBrandId',
  );

  final buttonFinder = find.widgetWithText(
    FilledButton,
    I18n.tr('action.close'),
  );
  expect(buttonFinder, findsOneWidget);
  final buttonWidget = tester.widget<FilledButton>(buttonFinder);
  final buttonElement = tester.element(buttonFinder);
  final actualButtonMaterial = tester.widget<Material>(
    find.descendant(of: buttonFinder, matching: find.byType(Material)),
  );
  // ignore: invalid_use_of_protected_member
  final defaultButtonStyle = buttonWidget.defaultStyleOf(buttonElement);

  final refElement = tester.element(
    find.byKey(
      ValueKey('ref_theme_$expectedBrandId'),
      skipOffstage: false,
    ),
  );
  final refSecondaryStyle = appSecondaryFilledButtonStyle(refElement);
  final refThemeStyle = FilledButtonTheme.of(refElement).style;

  final expectedButtonColor =
      buttonWidget.style?.backgroundColor?.resolve(const <WidgetState>{}) ??
      refThemeStyle?.backgroundColor?.resolve(const <WidgetState>{}) ??
      refSecondaryStyle.backgroundColor?.resolve(const <WidgetState>{}) ??
      defaultButtonStyle.backgroundColor?.resolve(const <WidgetState>{}) ??
      expectedBrand.theme.colorScheme.primary;
  expect(
    actualButtonMaterial.color,
    equals(expectedButtonColor),
    reason:
        'FilledButton Material color must render brand $expectedBrandId color',
  );
}

Future<void> _verifyThemeAndLocaleRoundTrip({
  required WidgetTester tester,
  required _ScheduleFallbackFixture fixture,
  required AppLocale initialLocale,
  required String initialBrand,
  required bool isMissing,
}) async {
  final alternateLocale = initialLocale == AppLocale.zh
      ? AppLocale.en
      : AppLocale.zh;
  final alternateBrand = initialBrand == 'defaultBrand'
      ? 'liquidGlass'
      : 'defaultBrand';

  final sheetElementBefore = tester.element(find.byType(AppModalSheet));

  // 1. Switch locale
  I18n.setLocale(alternateLocale);
  await tester.pumpAndSettle();

  expect(tester.element(find.byType(AppModalSheet)), same(sheetElementBefore));
  expect(find.text(TodayUiCopy.detailTitle('events')), findsOneWidget);
  expect(
    find.text(
      isMissing
          ? TodayUiCopy.detailMissing('events')
          : TodayUiCopy.detailSourceChanged,
    ),
    findsOneWidget,
  );
  expect(find.text(I18n.tr('action.close')), findsOneWidget);

  // 2. Switch theme brand inside runAsync and assert reactive rendered brand colors
  await tester.runAsync(() async {
    final switched = await fixture.theme.setBrand(alternateBrand);
    expect(switched, isTrue);
  });
  await tester.pumpAndSettle();

  expect(tester.element(find.byType(AppModalSheet)), same(sheetElementBefore));
  expect(fixture.theme.brand.id, alternateBrand);
  _assertRenderedBrandAppearance(tester, expectedBrandId: alternateBrand);

  // 3. Round trip back to initialBrand
  await tester.runAsync(() async {
    final reverted = await fixture.theme.setBrand(initialBrand);
    expect(reverted, isTrue);
  });
  await tester.pumpAndSettle();

  expect(tester.element(find.byType(AppModalSheet)), same(sheetElementBefore));
  expect(fixture.theme.brand.id, initialBrand);
  _assertRenderedBrandAppearance(tester, expectedBrandId: initialBrand);

  // 4. Round trip back to initialLocale
  I18n.setLocale(initialLocale);
  await tester.pumpAndSettle();

  expect(tester.element(find.byType(AppModalSheet)), same(sheetElementBefore));
  expect(find.text(TodayUiCopy.detailTitle('events')), findsOneWidget);
  expect(
    find.text(
      isMissing
          ? TodayUiCopy.detailMissing('events')
          : TodayUiCopy.detailSourceChanged,
    ),
    findsOneWidget,
  );
  expect(find.text(I18n.tr('action.close')), findsOneWidget);
}

void _assertPersistenceImmutability({
  required SharedPreferences prefs,
  required String initialBrand,
  required Map<String, Object?> beforePrefs,
}) {
  // 1. active_brand returns to initialBrand
  expect(
    prefs.getString('active_brand'),
    equals(initialBrand),
    reason: 'active_brand must return to $initialBrand',
  );
  if (prefs.containsKey('flutter.active_brand')) {
    expect(
      prefs.getString('flutter.active_brand'),
      equals(initialBrand),
      reason: 'flutter.active_brand must return to $initialBrand',
    );
  }

  // 2. Theme metadata values are valid
  if (prefs.containsKey('theme_switch_count')) {
    expect(
      prefs.getInt('theme_switch_count'),
      greaterThanOrEqualTo(2),
      reason: 'theme_switch_count must reflect roundtrip switches',
    );
  }
  if (prefs.containsKey('theme_shop_state')) {
    final decoded =
        jsonDecode(prefs.getString('theme_shop_state')!)
            as Map<String, dynamic>;
    expect(
      decoded['activeBrand'],
      equals(initialBrand),
      reason: 'theme_shop_state activeBrand must return to $initialBrand',
    );
  }
  if (prefs.containsKey('flutter.theme_shop_state')) {
    final decoded =
        jsonDecode(prefs.getString('flutter.theme_shop_state')!)
            as Map<String, dynamic>;
    expect(
      decoded['activeBrand'],
      equals(initialBrand),
      reason:
          'flutter.theme_shop_state activeBrand must return to $initialBrand',
    );
  }

  // 3. Every other key is strictly unchanged
  final nonThemeBefore = {
    for (final entry in beforePrefs.entries)
      if (!_knownThemeMetadataKeys.contains(entry.key)) entry.key: entry.value,
  };
  final nonThemeAfter = {
    for (final key in prefs.getKeys())
      if (!_knownThemeMetadataKeys.contains(key)) key: prefs.get(key),
  };
  expect(
    nonThemeAfter,
    equals(nonThemeBefore),
    reason: 'All non-theme persistence keys must remain completely unchanged',
  );
}

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final host in ['event', 'pomodoro']) {
        for (final layout in _priorityLayouts) {
          final testName =
              'missing fallback $brand-${locale.name}-$host-${layout.name}';
          testWidgets(testName, (tester) async {
            _ScheduleFallbackFixture? fixture;
            final shadows = debugDisableShadows;
            tester.view.physicalSize = layout.size * layout.dpr;
            tester.view.devicePixelRatio = layout.dpr;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            I18n.setLocale(locale);

            try {
              debugDisableShadows = false;
              await tester.runAsync(() async {
                await loadWeeklyReviewScreenshotFonts();
                fixture = await _ScheduleFallbackFixture.create(
                  host,
                  brand: brand,
                  explicitUri: Uri.parse(
                    'duoyi://$host/missing-fallback-object-id',
                  ),
                );
              });
              final activeFixture = fixture!;

              expect(
                tester.view.physicalSize / tester.view.devicePixelRatio,
                layout.size,
              );
              final prefs = await SharedPreferences.getInstance();
              final beforeKeys = prefs.getKeys().toSet();
              final beforePrefs = {for (final k in beforeKeys) k: prefs.get(k)};
              final initialCalendarEvents = List<CalendarEvent>.of(
                activeFixture.calendar.localEvents,
              );
              final initialSessions = List<PomodoroSession>.of(
                activeFixture.sessions.sessions,
              );
              final initialStorageGeneration =
                  activeFixture.sessions.storageGeneration;
              final initialAccountGeneration =
                  AccountLocalDataCleaner.accountDataGeneration;

              await activeFixture.open(
                tester,
                scale: layout.scale,
                locale: locale,
                expectedSize: layout.size,
              );

              expect(find.byType(AppModalSheet), findsOneWidget);
              expect(find.byType(CalendarEventSheet), findsNothing);

              final titleFinder = find.text(TodayUiCopy.detailTitle('events'));
              final bodyFinder = find.text(TodayUiCopy.detailMissing('events'));
              final actionFinder = find.widgetWithText(
                FilledButton,
                I18n.tr('action.close'),
              );

              _assertCompleteText(tester, titleFinder, role: 'title');
              _assertCompleteText(tester, bodyFinder, role: 'body');
              _assertCompleteText(tester, actionFinder, role: 'close-action');

              await _capture(
                tester,
                activeFixture.boundary,
                'missing-$brand-${locale.name}-$host-${layout.name}',
              );

              await _verifyThemeAndLocaleRoundTrip(
                tester: tester,
                fixture: activeFixture,
                initialLocale: locale,
                initialBrand: brand,
                isMissing: true,
              );

              expect(activeFixture.access.canProceed, isTrue);

              await _verifyCoveredCloseGuard(
                tester: tester,
                boundaryKey: activeFixture.boundary,
              );

              expect(activeFixture.access.canProceed, isFalse);
              expect(activeFixture.access.canDeliverFeedback, isTrue);
              expect(activeFixture.acknowledgements, 1);
              expect(activeFixture.requeues, 0);

              // Strict business record immutability
              expect(
                activeFixture.calendar.localEvents.length,
                equals(initialCalendarEvents.length),
              );
              expect(
                activeFixture.sessions.sessions.length,
                equals(initialSessions.length),
              );
              expect(
                activeFixture.sessions.storageGeneration,
                equals(initialStorageGeneration),
              );
              expect(
                AccountLocalDataCleaner.isCurrentAccountDataGeneration(
                  initialAccountGeneration,
                ),
                isTrue,
              );

              // Strict persistence immutability without rewriting
              _assertPersistenceImmutability(
                prefs: prefs,
                initialBrand: brand,
                beforePrefs: beforePrefs,
              );

              expect(tester.takeException(), isNull);
            } finally {
              tester.view.resetPhysicalSize();
              tester.view.resetDevicePixelRatio();
              debugDisableShadows = shadows;
              await fixture?.dispose(tester);
            }
          });

          final sourceChangedTestName =
              'sourceChanged fallback $brand-${locale.name}-$host-${layout.name}';
          testWidgets(sourceChangedTestName, (tester) async {
            _ScheduleFallbackFixture? fixture;
            final shadows = debugDisableShadows;
            tester.view.physicalSize = layout.size * layout.dpr;
            tester.view.devicePixelRatio = layout.dpr;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            I18n.setLocale(locale);

            try {
              debugDisableShadows = false;
              await tester.runAsync(() async {
                await loadWeeklyReviewScreenshotFonts();
                fixture = await _ScheduleFallbackFixture.create(
                  host,
                  brand: brand,
                );
              });
              final activeFixture = fixture!;

              expect(
                tester.view.physicalSize / tester.view.devicePixelRatio,
                layout.size,
              );
              final prefs = await SharedPreferences.getInstance();
              final beforeKeys = prefs.getKeys().toSet();
              final beforePrefs = {for (final k in beforeKeys) k: prefs.get(k)};
              final initialCalendarEvents = List<CalendarEvent>.of(
                activeFixture.calendar.localEvents,
              );
              final initialSessions = List<PomodoroSession>.of(
                activeFixture.sessions.sessions,
              );
              final initialStorageGeneration =
                  activeFixture.sessions.storageGeneration;

              await activeFixture.open(
                tester,
                scale: layout.scale,
                locale: locale,
                expectedSize: layout.size,
              );

              // Initially, valid object opens CalendarEventSheet without fallback text
              expect(find.byType(CalendarEventSheet), findsOneWidget);
              expect(find.text(TodayUiCopy.detailSourceChanged), findsNothing);

              // Account generation invalidation triggers sourceChanged
              AccountLocalDataCleaner.invalidateInFlightAccountWrites();
              await tester.pumpAndSettle();

              expect(find.byType(CalendarEventSheet), findsNothing);
              expect(find.byType(AppModalSheet), findsOneWidget);

              final titleFinder = find.text(TodayUiCopy.detailTitle('events'));
              final bodyFinder = find.text(TodayUiCopy.detailSourceChanged);
              final actionFinder = find.widgetWithText(
                FilledButton,
                I18n.tr('action.close'),
              );

              _assertCompleteText(tester, titleFinder, role: 'title');
              _assertCompleteText(tester, bodyFinder, role: 'body');
              _assertCompleteText(tester, actionFinder, role: 'close-action');

              await _capture(
                tester,
                activeFixture.boundary,
                'sourceChanged-$brand-${locale.name}-$host-${layout.name}',
              );

              await _verifyThemeAndLocaleRoundTrip(
                tester: tester,
                fixture: activeFixture,
                initialLocale: locale,
                initialBrand: brand,
                isMissing: false,
              );

              expect(activeFixture.access.request.isCurrentAccount, isFalse);
              expect(activeFixture.access.canProceed, isFalse);
              expect(activeFixture.access.canDeliverFeedback, isFalse);

              await _verifyCoveredCloseGuard(
                tester: tester,
                boundaryKey: activeFixture.boundary,
              );

              expect(activeFixture.access.request.isCurrentAccount, isFalse);
              expect(activeFixture.access.canProceed, isFalse);
              expect(activeFixture.access.canDeliverFeedback, isFalse);
              expect(activeFixture.acknowledgements, 1);
              expect(activeFixture.requeues, 0);

              // Strict business record immutability
              expect(
                activeFixture.calendar.localEvents.length,
                equals(initialCalendarEvents.length),
              );
              expect(
                activeFixture.sessions.sessions.length,
                equals(initialSessions.length),
              );
              expect(
                activeFixture.sessions.storageGeneration,
                equals(initialStorageGeneration),
              );

              // Strict persistence immutability without rewriting
              _assertPersistenceImmutability(
                prefs: prefs,
                initialBrand: brand,
                beforePrefs: beforePrefs,
              );

              expect(tester.takeException(), isNull);
            } finally {
              tester.view.resetPhysicalSize();
              tester.view.resetDevicePixelRatio();
              debugDisableShadows = shadows;
              await fixture?.dispose(tester);
            }
          });
        }
      }
    }
  }

  for (final host in ['event', 'pomodoro']) {
    testWidgets(
      '$host delete transition presents missing fallback and guards covered close',
      (tester) async {
        _ScheduleFallbackFixture? fixture;
        final shadows = debugDisableShadows;
        tester.view.physicalSize = _defaultTailSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        try {
          debugDisableShadows = false;
          await tester.runAsync(() async {
            await loadWeeklyReviewScreenshotFonts();
            fixture = await _ScheduleFallbackFixture.create(
              host,
              brand: 'defaultBrand',
            );
          });
          final activeFixture = fixture!;

          await activeFixture.open(
            tester,
            scale: 1.0,
            locale: AppLocale.zh,
            expectedSize: _defaultTailSize,
          );
          expect(find.byType(CalendarEventSheet), findsOneWidget);

          if (host == 'event') {
            await tester.runAsync(() async {
              await activeFixture.calendar.deleteLocalEvent(_id);
            });
          } else {
            activeFixture.sessions.clearRecords();
          }
          await tester.pumpAndSettle();

          expect(find.byType(CalendarEventSheet), findsNothing);
          expect(find.byType(AppModalSheet), findsOneWidget);
          expect(
            find.text(TodayUiCopy.detailMissing('events')),
            findsOneWidget,
          );

          await _verifyCoveredCloseGuard(
            tester: tester,
            boundaryKey: activeFixture.boundary,
          );
          expect(activeFixture.acknowledgements, 1);
          expect(activeFixture.requeues, 0);
          expect(tester.takeException(), isNull);
        } finally {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          debugDisableShadows = shadows;
          await fixture?.dispose(tester);
        }
      },
    );

    testWidgets(
      '$host provider replacement presents sourceChanged fallback and guards covered close',
      (tester) async {
        _ScheduleFallbackFixture? fixture;
        final shadows = debugDisableShadows;
        tester.view.physicalSize = _defaultTailSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        try {
          debugDisableShadows = false;
          await tester.runAsync(() async {
            await loadWeeklyReviewScreenshotFonts();
            fixture = await _ScheduleFallbackFixture.create(
              host,
              brand: 'defaultBrand',
            );
          });
          final activeFixture = fixture!;

          await activeFixture.open(
            tester,
            scale: 1.0,
            locale: AppLocale.zh,
            expectedSize: _defaultTailSize,
          );
          expect(find.byType(CalendarEventSheet), findsOneWidget);

          if (host == 'event') {
            await tester.runAsync(() async {
              final replacementCalendar = CalendarProvider();
              await replacementCalendar.loadFromStorage();
              activeFixture.calendar = replacementCalendar;
            });
          } else {
            await tester.runAsync(() async {
              activeFixture.sessions = _Sessions();
            });
          }
          await tester.pumpWidget(
            activeFixture.app(
              scale: 1.0,
              locale: AppLocale.zh,
              expectedSize: _defaultTailSize,
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(CalendarEventSheet), findsNothing);
          expect(find.byType(AppModalSheet), findsOneWidget);
          expect(find.text(TodayUiCopy.detailSourceChanged), findsOneWidget);

          await _verifyCoveredCloseGuard(
            tester: tester,
            boundaryKey: activeFixture.boundary,
          );
          expect(activeFixture.acknowledgements, 1);
          expect(activeFixture.requeues, 0);
          expect(tester.takeException(), isNull);
        } finally {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          debugDisableShadows = shadows;
          await fixture?.dispose(tester);
        }
      },
    );

    if (host == 'pomodoro') {
      testWidgets(
        'pomodoro storage reset presents sourceChanged fallback and guards covered close',
        (tester) async {
          _ScheduleFallbackFixture? fixture;
          final shadows = debugDisableShadows;
          tester.view.physicalSize = _defaultTailSize;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          try {
            debugDisableShadows = false;
            await tester.runAsync(() async {
              await loadWeeklyReviewScreenshotFonts();
              fixture = await _ScheduleFallbackFixture.create(
                host,
                brand: 'defaultBrand',
              );
            });
            final activeFixture = fixture!;

            await activeFixture.open(
              tester,
              scale: 1.0,
              locale: AppLocale.zh,
              expectedSize: _defaultTailSize,
            );
            expect(find.byType(CalendarEventSheet), findsOneWidget);

            activeFixture.sessions.resetLocalState();
            await tester.pumpAndSettle();

            expect(find.byType(CalendarEventSheet), findsNothing);
            expect(find.byType(AppModalSheet), findsOneWidget);
            expect(find.text(TodayUiCopy.detailSourceChanged), findsOneWidget);

            await _verifyCoveredCloseGuard(
              tester: tester,
              boundaryKey: activeFixture.boundary,
            );
            expect(activeFixture.acknowledgements, 1);
            expect(activeFixture.requeues, 0);
            expect(tester.takeException(), isNull);
          } finally {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
            debugDisableShadows = shadows;
            await fixture?.dispose(tester);
          }
        },
      );
    }

    testWidgets(
      '$host blocked launch access requeues without presenting fallback sheet',
      (tester) async {
        _ScheduleFallbackFixture? fixture;
        final shadows = debugDisableShadows;
        tester.view.physicalSize = _defaultTailSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        try {
          debugDisableShadows = false;
          await tester.runAsync(() async {
            await loadWeeklyReviewScreenshotFonts();
            fixture = await _ScheduleFallbackFixture.create(
              host,
              brand: 'defaultBrand',
              explicitUri: Uri.parse('duoyi://$host/blocked-item-id'),
              blocked: true,
            );
          });
          final activeFixture = fixture!;

          await activeFixture.open(
            tester,
            scale: 1.0,
            locale: AppLocale.zh,
            expectedSize: _defaultTailSize,
          );

          expect(find.byType(AppModalSheet), findsNothing);
          expect(find.byType(CalendarEventSheet), findsNothing);
          expect(activeFixture.requeues, 1);
          expect(activeFixture.acknowledgements, 0);
          expect(tester.takeException(), isNull);
        } finally {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          debugDisableShadows = shadows;
          await fixture?.dispose(tester);
        }
      },
    );
  }
}
