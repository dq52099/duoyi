// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/calendar_event_sheet_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/workspace.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandBackground;
import 'package:duoyi/widgets/calendar_event_sheet.dart';
import 'package:duoyi/widgets/surface_components.dart'
    show AppDialog, AppModalSheet, AppSecondaryControlTheme, appSurfaceStyleOf;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/retained_dialog_text_probe.dart';
import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore(super.data) : super.withData();

  int calendarWrites = 0;
  int calendarRemoves = 0;
  final List<String> recordedCalendarPayloads = [];

  static bool _isCalendarKey(String key) =>
      key == 'duoyi_local_calendar_events_v1' ||
      key == 'flutter.duoyi_local_calendar_events_v1' ||
      key.endsWith('.duoyi_local_calendar_events_v1');

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (_isCalendarKey(key)) {
      calendarWrites++;
      recordedCalendarPayloads.add(value.toString());
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    if (_isCalendarKey(key)) {
      calendarRemoves++;
    }
    return super.remove(key);
  }
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];
  final List<Route<dynamic>> popped = <Route<dynamic>>[];
  final List<Route<dynamic>> removed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped.add(route);
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    removed.add(route);
    super.didRemove(route, previousRoute);
  }
}

class _FixtureShareProvider extends ShareProvider {
  _FixtureShareProvider(this.fixtureWorkspaces);

  final List<Workspace> fixtureWorkspaces;

  @override
  List<Workspace> get workspaces => List.unmodifiable(fixtureWorkspaces);

  @override
  WorkspaceRole roleFor(String workspaceId) {
    if (workspaceId.isEmpty || workspaceId == 'private') {
      return WorkspaceRole.owner;
    }
    final userId = userIdGetter?.call();
    for (final workspace in fixtureWorkspaces) {
      if (workspace.id == workspaceId) return workspace.roleFor(userId);
    }
    return WorkspaceRole.viewer;
  }

  @override
  bool canEdit(String? workspaceId) {
    if (workspaceId == null ||
        workspaceId.isEmpty ||
        workspaceId == 'private') {
      return true;
    }
    return roleFor(workspaceId).canEdit;
  }
}

class _LocalEditorScenario {
  final String name;
  final AppLocale initialLocale;
  final AppLocale alternateLocale;
  final String initialBrand;
  final String targetBrand;
  final Size size;
  final TextScaler textScaler;
  final double devicePixelRatio;
  final bool testConfirm;
  final bool isEditMode;
  final bool isAccountGuard;
  final String draftTitle;
  final String draftNote;

  const _LocalEditorScenario({
    required this.name,
    required this.initialLocale,
    required this.alternateLocale,
    required this.initialBrand,
    required this.targetBrand,
    required this.size,
    required this.textScaler,
    required this.devicePixelRatio,
    required this.testConfirm,
    this.isEditMode = false,
    this.isAccountGuard = false,
    required this.draftTitle,
    required this.draftNote,
  });
}

const _scenarios = <_LocalEditorScenario>[
  _LocalEditorScenario(
    name: 'zh-portrait-320x844-dpr2-defaultBrand-cancel',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(320, 844),
    textScaler: TextScaler.linear(2.0),
    devicePixelRatio: 2.0,
    testConfirm: false,
    draftTitle: '年度团队规划与跨平台架构同步会议',
    draftNote: '各业务组负责人准备技术演进路线图与风险分析报告',
  ),
  _LocalEditorScenario(
    name: 'en-landscape-844x390-dpr1-liquidGlass-commit',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(844, 390),
    textScaler: TextScaler.linear(1.0),
    devicePixelRatio: 1.0,
    testConfirm: true,
    draftTitle: 'Quarterly Infrastructure Engineering Review',
    draftNote:
        'Coordinate architecture sign-off and verify performance benchmarks across targets',
  ),
  _LocalEditorScenario(
    name: 'en-ordinary-390x844-dpr2-defaultBrand-edit-existing',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(390, 844),
    textScaler: TextScaler.linear(1.0),
    devicePixelRatio: 2.0,
    testConfirm: true,
    isEditMode: true,
    draftTitle: 'Updated Design System Synchronization Workshop',
    draftNote: 'Refined token documentation and updated mobile UI contracts',
  ),
  _LocalEditorScenario(
    name: 'zh-wide-1024x768-dpr1-liquidGlass-account-guard',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(1024, 768),
    textScaler: TextScaler.linear(1.0),
    devicePixelRatio: 1.0,
    testConfirm: false,
    isAccountGuard: true,
    draftTitle: '跨平台状态持久化与多端对齐验证测试',
    draftNote: '验证多端会话注销与数据清理时对话框拦截表现',
  ),
  _LocalEditorScenario(
    name: 'zh-narrow-332x844-dpr2-defaultBrand-nonlinear',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(332, 844),
    textScaler: RouteProbeNonlinearScaler(),
    devicePixelRatio: 2.0,
    testConfirm: false,
    draftTitle: '非线性文本缩放适配研讨与可访问性验证',
    draftNote: '针对超大字号和动态字号场景执行完整边界布局测试',
  ),
];

Future<int> _boundedPump(
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
  await tester.runAsync(
    () => AccountPreferenceWrites.drain().timeout(timeout, onTimeout: () {}),
  );
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
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final file = File('$explicitDir/calendar-local-editor-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

class _CalendarLocalEditorHost extends StatelessWidget {
  final DateTime initialDate;
  final CalendarEvent? existingEvent;
  final String? workspaceId;

  const _CalendarLocalEditorHost({
    required this.initialDate,
    this.existingEvent,
    this.workspaceId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calendar Local Editor Host')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              key: const ValueKey('open_create_local_event_button'),
              onPressed: () => showLocalCalendarEventEditor(
                context,
                initialDate: initialDate,
                workspaceId: workspaceId,
              ),
              child: const Text('Open Create Local Event'),
            ),
            const SizedBox(height: 12),
            if (existingEvent != null)
              ElevatedButton(
                key: const ValueKey('open_edit_local_event_button'),
                onPressed: () => showLocalCalendarEventEditor(
                  context,
                  event: existingEvent,
                  workspaceId: workspaceId,
                ),
                child: const Text('Open Edit Local Event'),
              ),
            const SizedBox(height: 12),
            ElevatedButton(
              key: const ValueKey('open_unauthorized_workspace_button'),
              onPressed: () => showLocalCalendarEventEditor(
                context,
                workspaceId: 'readonly_workspace',
              ),
              child: const Text('Open Unauthorized Workspace'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarLocalEditorFixture {
  SharedPreferences? prefs;
  ThemeProvider? _theme;
  PreferencesProvider? _preferences;
  CalendarProvider? _calendarProvider;
  _FixtureShareProvider? _shareProvider;

  ThemeProvider get theme => _theme!;
  PreferencesProvider get preferences => _preferences!;
  CalendarProvider get calendarProvider => _calendarProvider!;
  _FixtureShareProvider get shareProvider => _shareProvider!;

  final navigatorKey = GlobalKey<NavigatorState>();
  final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final observer = _RecordingNavigatorObserver();
  final boundaryKey = GlobalKey();
  bool _installed = false;
  bool _disposed = false;

  Future<void> mount({
    required WidgetTester tester,
    required _LocalEditorScenario scenario,
    required DateTime initialDate,
    CalendarEvent? existingEvent,
    List<Workspace> workspaces = const <Workspace>[],
  }) async {
    if (!_installed) {
      _installed = true;
      try {
        await tester.runAsync(() async {
          prefs = await SharedPreferences.getInstance();
          final t = ThemeProvider();
          _theme = t;
          final p = PreferencesProvider();
          _preferences = p;
          final c = CalendarProvider();
          _calendarProvider = c;
          final s = _FixtureShareProvider(workspaces);
          _shareProvider = s;

          await t.loadFromStorage().timeout(const Duration(seconds: 5));
          await p.loadFromStorage().timeout(const Duration(seconds: 5));
          await c.loadFromStorage().timeout(
            const Duration(seconds: 5),
          );
          if (File('assets/fonts/DroidSansFallbackFull.ttf').existsSync() &&
              File('assets/fonts/DejaVuSans.ttf').existsSync()) {
            await loadWeeklyReviewScreenshotFonts().timeout(
              const Duration(seconds: 5),
            );
          }
        });
        await _drainAccountWrites(tester);
      } catch (_) {
        await dispose(tester);
        rethrow;
      }
    }

    tester.view.physicalSize = scenario.size * scenario.devicePixelRatio;
    tester.view.devicePixelRatio = scenario.devicePixelRatio;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
          ChangeNotifierProvider<CalendarProvider>.value(
            value: calendarProvider,
          ),
          ChangeNotifierProvider<ShareProvider>.value(value: shareProvider),
        ],
        child: Consumer<ThemeProvider>(
          builder: (context, currentTheme, _) =>
              ValueListenableBuilder<AppLocale>(
                valueListenable: I18n.localeListenable,
                builder: (context, currentLocale, _) => MaterialApp(
                  navigatorKey: navigatorKey,
                  scaffoldMessengerKey: scaffoldMessengerKey,
                  navigatorObservers: [observer],
                  debugShowCheckedModeBanner: false,
                  locale: Locale(currentLocale == AppLocale.en ? 'en' : 'zh'),
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: currentTheme.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: scenario.textScaler,
                    ),
                    child: RepaintBoundary(key: boundaryKey, child: child!),
                  ),
                  home: Stack(
                    children: [
                      BrandBackground(
                        key: const ValueKey(
                          'calendar_local_editor_brand_background',
                        ),
                        child: _CalendarLocalEditorHost(
                          initialDate: initialDate,
                          existingEvent: existingEvent,
                          workspaceId: null,
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
                                builder: (refContext) => FilledButton(
                                  key: ValueKey('ref_filled_${brand.id}'),
                                  onPressed: () {},
                                  child: const Text('Ref'),
                                ),
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
    );
    await _boundedPump(tester);
  }

  Future<void> dispose(WidgetTester tester) async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _drainAccountWrites(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await _boundedPump(tester);
    } finally {
      tester.view.reset();
      _theme?.dispose();
      _theme = null;
      _preferences?.dispose();
      _preferences = null;
      _calendarProvider?.dispose();
      _calendarProvider = null;
      _shareProvider?.dispose();
      _shareProvider = null;
    }
  }
}

void main() {
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets(
      'Calendar Local Event Editor modal live priority MD contract ${scenario.name}',
      (tester) async {
        I18n.setLocale(scenario.initialLocale);
        final originalShadows = debugDisableShadows;
        debugDisableShadows = false;
        final prevStore = SharedPreferencesStorePlatform.instance;
        final fixture = _CalendarLocalEditorFixture();
        try {
          final fixedDate = DateTime(2027, 6, 15);
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

          CalendarEvent? existingFixtureEvent;
          if (scenario.isEditMode) {
            existingFixtureEvent = CalendarEvent(
              id: 'local_fixture_event_001',
              title: 'Initial Architectural Review',
              date: DateTime(2027, 6, 15, 10, 0),
              endDate: DateTime(2027, 6, 15, 11, 30),
              type: CalendarEventType.event,
              color: const Color(0xFF26A69A),
              time: const TimeOfDay(hour: 10, minute: 0),
              note: 'Initial review notes to be updated',
              workspaceId: 'private',
            );
          }

          final fixedCreatedAt = DateTime(2027, 1, 1);
          final fixtureWorkspaces = <Workspace>[
            Workspace(
              id: 'readonly_workspace',
              name: 'Readonly Workspace',
              ownerUserId: 'owner_user_999',
              isPrivate: false,
              createdAt: fixedCreatedAt,
              updatedAt: fixedCreatedAt,
              members: const <WorkspaceMember>[],
            ),
          ];

          await fixture.mount(
            tester: tester,
            scenario: scenario,
            initialDate: fixedDate,
            existingEvent: existingFixtureEvent,
            workspaces: fixtureWorkspaces,
          );

          if (scenario.isEditMode && existingFixtureEvent != null) {
            await tester.runAsync(
              () =>
                  fixture.calendarProvider.addLocalEvent(existingFixtureEvent!),
            );
            await _drainAccountWrites(tester);
          }

          expect(fixture.theme.brand.id, scenario.initialBrand);
          expect(fixture.theme.isBrandUnlocked(scenario.targetBrand), isTrue);

          // 1. Assert host entry, BrandBackground, real incoming MediaQuery, root RenderBox size and physicalSize/DPR
          final hostFinder = find.byType(_CalendarLocalEditorHost);
          expect(hostFinder, findsOneWidget);
          expect(
            find.byKey(
              const ValueKey('calendar_local_editor_brand_background'),
            ),
            findsOneWidget,
            reason:
                'Host BrandBackground wrapper must be present from first frame',
          );

          final media = MediaQuery.of(tester.element(hostFinder));
          expect(
            media.size.width,
            closeTo(scenario.size.width, 0.001),
            reason:
                'Real incoming MediaQuery width must match scenario logical width',
          );
          expect(
            media.size.height,
            closeTo(scenario.size.height, 0.001),
            reason:
                'Real incoming MediaQuery height must match scenario logical height',
          );
          expect(
            media.devicePixelRatio,
            closeTo(scenario.devicePixelRatio, 0.001),
            reason:
                'Real incoming MediaQuery devicePixelRatio must match scenario specification',
          );
          expect(
            tester.view.physicalSize.width,
            closeTo(scenario.size.width * scenario.devicePixelRatio, 0.001),
            reason: 'Physical width must equal logical width * DPR',
          );
          expect(
            tester.view.physicalSize.height,
            closeTo(scenario.size.height * scenario.devicePixelRatio, 0.001),
            reason: 'Physical height must equal logical height * DPR',
          );
          expect(
            tester.view.devicePixelRatio,
            closeTo(scenario.devicePixelRatio, 0.001),
            reason: 'View DPR must match scenario DPR',
          );

          final hostBox = tester.renderObject(hostFinder) as RenderBox;
          expect(
            hostBox.size.width,
            closeTo(scenario.size.width, 0.001),
            reason:
                'Root host RenderBox width must match scenario logical width',
          );
          expect(
            hostBox.size.height,
            closeTo(scenario.size.height, 0.001),
            reason:
                'Root host RenderBox height must match scenario logical height',
          );

          // Test workspace permission guard: read-only workspace caller rejected
          final unauthorizedBtn = find.byKey(
            const ValueKey('open_unauthorized_workspace_button'),
          );
          expect(unauthorizedBtn, findsOneWidget);
          await tester.ensureVisible(unauthorizedBtn);
          await _boundedPump(tester);
          expect(unauthorizedBtn.hitTestable(), findsOneWidget);
          await tester.tap(unauthorizedBtn);
          await _boundedPump(tester);
          expect(
            find.byType(AppDialog),
            findsNothing,
            reason:
                'Unauthorized workspace caller must not open local event editor dialog',
          );

          final baselineCalendarWrites = store.calendarWrites;
          final baselineCalendarRemoves = store.calendarRemoves;

          // 2. Open local event editor via existing public entry
          if (scenario.isEditMode) {
            final editBtn = find.byKey(
              const ValueKey('open_edit_local_event_button'),
            );
            expect(editBtn, findsOneWidget);
            await tester.ensureVisible(editBtn);
            await _boundedPump(tester);
            expect(editBtn.hitTestable(), findsOneWidget);
            await tester.tap(editBtn);
          } else {
            final createBtn = find.byKey(
              const ValueKey('open_create_local_event_button'),
            );
            expect(createBtn, findsOneWidget);
            await tester.ensureVisible(createBtn);
            await _boundedPump(tester);
            expect(createBtn.hitTestable(), findsOneWidget);
            await tester.tap(createBtn);
          }
          await _boundedPump(tester);
          expect(tester.takeException(), isNull);

          final dialogFinder = find.byType(AppDialog);
          expect(dialogFinder, findsOneWidget);
          final initialDialogElement = tester.element(dialogFinder);
          final dialogStateFinder = find.byWidgetPredicate(
            (widget) =>
                widget.runtimeType.toString() == '_LocalEventEditorDialog',
          );
          expect(dialogStateFinder, findsOneWidget);
          final initialDialogState = tester.state(dialogStateFinder);
          final initialDialogRoute = ModalRoute.of(initialDialogElement);
          expect(initialDialogRoute, isNotNull);

          // 3. Inspect controllers, draft input, and selection using stable controller identity
          final titleFieldFinder = find
              .descendant(of: dialogFinder, matching: find.byType(TextField))
              .first;
          expect(titleFieldFinder, findsOneWidget);
          final noteFieldFinder = find
              .descendant(of: dialogFinder, matching: find.byType(TextField))
              .last;
          expect(noteFieldFinder, findsOneWidget);

          final titleWidget = tester.widget<TextField>(titleFieldFinder);
          final titleCtrl = titleWidget.controller!;
          final noteWidget = tester.widget<TextField>(noteFieldFinder);
          final noteCtrl = noteWidget.controller!;

          if (scenario.isEditMode) {
            expect(titleCtrl.text, 'Initial Architectural Review');
            expect(noteCtrl.text, 'Initial review notes to be updated');
          }

          // Enter long realistic draft title and note
          await tester.enterText(titleFieldFinder, scenario.draftTitle);
          await _boundedPump(tester);
          await tester.enterText(noteFieldFinder, scenario.draftNote);
          await _boundedPump(tester);

          const selection = TextSelection(baseOffset: 3, extentOffset: 12);
          titleCtrl.selection = selection;
          await _boundedPump(tester);

          expect(titleCtrl.text, scenario.draftTitle);
          expect(titleCtrl.selection, selection);
          expect(noteCtrl.text, scenario.draftNote);

          // In commit scenario, exercise actual changes to date, time, and color
          if (scenario.testConfirm && !scenario.isEditMode) {
            // Exercise actual date picker interaction
            final startDateTile = find.widgetWithText(
              ListTile,
              CalendarEventSheetUiCopy.startDate,
            );
            expect(startDateTile, findsOneWidget);
            await tester.ensureVisible(startDateTile);
            await _boundedPump(tester);
            expect(startDateTile.hitTestable(), findsOneWidget);
            await tester.tap(startDateTile);
            await _boundedPump(tester);

            final dateModalFinder = find.byType(AppModalSheet);
            expect(dateModalFinder, findsOneWidget);

            final confirmDateBtn = find.descendant(
              of: dateModalFinder,
              matching: find.widgetWithText(
                FilledButton,
                I18n.tr('action.confirm'),
              ),
            );
            expect(confirmDateBtn, findsOneWidget);
            await tester.ensureVisible(confirmDateBtn);
            await _boundedPump(tester);
            expect(confirmDateBtn.hitTestable(), findsOneWidget);
            final dateBtnRect = tester.getRect(confirmDateBtn);
            expect(dateBtnRect.top, greaterThanOrEqualTo(0.0));
            expect(dateBtnRect.bottom, lessThanOrEqualTo(scenario.size.height));
            await tester.tap(confirmDateBtn);
            await _boundedPump(tester);
            expect(find.byType(AppModalSheet), findsNothing);

            // Toggle all-day switch to false to reveal time pickers
            final switchFinder = find.descendant(
              of: dialogFinder,
              matching: find.byType(SwitchListTile),
            );
            expect(switchFinder, findsOneWidget);
            await tester.ensureVisible(switchFinder);
            await _boundedPump(tester);
            expect(switchFinder.hitTestable(), findsOneWidget);
            await tester.tap(switchFinder);
            await _boundedPump(tester);

            // Exercise actual time picker interaction
            final startTimeTile = find.widgetWithText(
              ListTile,
              CalendarEventSheetUiCopy.startTime,
            );
            expect(startTimeTile, findsOneWidget);
            await tester.ensureVisible(startTimeTile);
            await _boundedPump(tester);
            expect(startTimeTile.hitTestable(), findsOneWidget);
            await tester.tap(startTimeTile);
            await _boundedPump(tester);

            final timeModalFinder = find.byType(AppModalSheet);
            expect(timeModalFinder, findsOneWidget);

            final confirmTimeBtn = find.descendant(
              of: timeModalFinder,
              matching: find.widgetWithText(
                FilledButton,
                I18n.tr('action.confirm'),
              ),
            );
            expect(confirmTimeBtn, findsOneWidget);
            await tester.ensureVisible(confirmTimeBtn);
            await _boundedPump(tester);
            expect(confirmTimeBtn.hitTestable(), findsOneWidget);
            final timeBtnRect = tester.getRect(confirmTimeBtn);
            expect(timeBtnRect.top, greaterThanOrEqualTo(0.0));
            expect(timeBtnRect.bottom, lessThanOrEqualTo(scenario.size.height));
            await tester.tap(confirmTimeBtn);
            await _boundedPump(tester);
            expect(find.byType(AppModalSheet), findsNothing);

            // Pick an independent color choice
            final colorChoiceFinder = find.byWidgetPredicate(
              (w) =>
                  w.runtimeType.toString() == '_ColorChoice' &&
                  (w as dynamic).color == const Color(0xFF26A69A),
            );
            if (colorChoiceFinder.evaluate().isNotEmpty) {
              await tester.ensureVisible(colorChoiceFinder);
              await _boundedPump(tester);
              expect(colorChoiceFinder.hitTestable(), findsOneWidget);
              await tester.tap(colorChoiceFinder);
              await _boundedPump(tester);
            }
          }

          // Reference color and style assertion helper
          void assertBrandStyle(String expectedBrandId, String stage) {
            final currentDialogElement = tester.element(find.byType(AppDialog));
            final currentTheme = Theme.of(currentDialogElement);

            final refContext = tester.element(
              find.byKey(
                ValueKey('ref_theme_$expectedBrandId'),
                skipOffstage: false,
              ),
            );
            final refTheme = Theme.of(refContext);
            final refFilledStyle = FilledButtonTheme.of(refContext).style!;
            final expectedSurfaceStyle = appSurfaceStyleOf(refContext);

            expect(
              currentTheme.colorScheme.primary,
              equals(refTheme.colorScheme.primary),
              reason:
                  '$stage: ColorScheme.primary must match independent reference $expectedBrandId',
            );
            expect(
              currentTheme.colorScheme.surface,
              equals(refTheme.colorScheme.surface),
              reason:
                  '$stage: ColorScheme.surface must match independent reference $expectedBrandId',
            );

            final surfaceStyle = appSurfaceStyleOf(currentDialogElement);
            expect(
              surfaceStyle,
              equals(expectedSurfaceStyle),
              reason:
                  '$stage: AppSurfaceStyle must match independent reference $expectedBrandId',
            );

            final actualFilledBtn = tester.widget<FilledButton>(
              find.descendant(
                of: find.byType(AppDialog),
                matching: find.byType(FilledButton),
              ),
            );
            final actualFilledMaterial = tester.widget<Material>(
              find.descendant(
                of: find.descendant(
                  of: find.byType(AppDialog),
                  matching: find.byType(FilledButton),
                ),
                matching: find.byType(Material),
              ),
            );

            expect(
              actualFilledMaterial.color,
              equals(refFilledStyle.backgroundColor?.resolve({})),
              reason:
                  '$stage: FilledButton background color must match independent reference $expectedBrandId',
            );
            expect(
              actualFilledMaterial.shape,
              equals(
                refFilledStyle.shape
                    ?.resolve({})
                    ?.copyWith(
                      side: refFilledStyle.side?.resolve({}) ?? BorderSide.none,
                    ),
              ),
              reason:
                  '$stage: FilledButton shape must match independent reference $expectedBrandId',
            );
            final actualFilledContext = tester.element(
              find.descendant(
                of: find.byType(AppDialog),
                matching: find.byType(FilledButton),
              ),
            );
            final resolvedBackground =
                actualFilledBtn.style?.backgroundColor?.resolve(const {}) ??
                actualFilledBtn
                    .themeStyleOf(actualFilledContext)
                    ?.backgroundColor
                    ?.resolve(const {}) ??
                actualFilledBtn
                    .defaultStyleOf(actualFilledContext)
                    .backgroundColor
                    ?.resolve(const {});
            expect(
              resolvedBackground,
              equals(refFilledStyle.backgroundColor?.resolve(const {})),
            );
          }

          // Reachability, bounds, and text verification probe
          Future<void> assertDialogReachabilityAndBounds(String stage) async {
            final expectedTitle = CalendarEventSheetUiCopy.editorTitle(
              isEditing: scenario.isEditMode,
            );
            final titleFinder = find.descendant(
              of: find.byType(AppDialog),
              matching: find.text(expectedTitle),
            );
            expect(
              titleFinder,
              findsOneWidget,
              reason: '$stage: Title text must be present',
            );
            await verifyRetainedDialogText(
              tester,
              titleFinder,
              expected: expectedTitle,
            );

            final cancelLabel = CalendarEventSheetUiCopy.cancel;
            final cancelBtn = find.descendant(
              of: find.byType(AppDialog),
              matching: find.widgetWithText(TextButton, cancelLabel),
            );
            await tester.ensureVisible(cancelBtn);
            await _boundedPump(tester);
            expect(
              cancelBtn.hitTestable(),
              findsOneWidget,
              reason: '$stage: Cancel action must be hit-testable',
            );
            expect(
              tester.getSize(cancelBtn).height,
              greaterThanOrEqualTo(34.0),
              reason: '$stage: Cancel action height must be at least 34dp',
            );
            final cancelText = find.descendant(
              of: cancelBtn,
              matching: find.byType(Text),
            );
            await verifyRetainedDialogText(
              tester,
              cancelText,
              expected: cancelLabel,
            );

            final saveLabel = CalendarEventSheetUiCopy.save;
            final saveBtn = find.descendant(
              of: find.byType(AppDialog),
              matching: find.widgetWithText(FilledButton, saveLabel),
            );
            await tester.ensureVisible(saveBtn);
            await _boundedPump(tester);
            expect(
              saveBtn.hitTestable(),
              findsOneWidget,
              reason: '$stage: Save action must be hit-testable',
            );
            expect(
              tester.getSize(saveBtn).height,
              greaterThanOrEqualTo(34.0),
              reason: '$stage: Save action height must be at least 34dp',
            );
            final saveText = find.descendant(
              of: saveBtn,
              matching: find.byType(Text),
            );
            await verifyRetainedDialogText(
              tester,
              saveText,
              expected: saveLabel,
            );

            expect(tester.takeException(), isNull, reason: stage);
          }

          assertBrandStyle(scenario.initialBrand, '1. initial brand');
          await assertDialogReachabilityAndBounds('1. initial dialog');
          await _capture(
            tester,
            fixture.boundaryKey,
            '${scenario.name}-01-initial-dialog',
          );

          // 4. Live brand switch to targetBrand
          await tester.runAsync(() async {
            final switched = await fixture.theme.setBrand(scenario.targetBrand);
            expect(switched, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 3),
              onTimeout: () {},
            );
          });
          await _boundedPump(tester);
          expect(tester.takeException(), isNull);
          expect(fixture.theme.brand.id, scenario.targetBrand);

          expect(find.byType(AppDialog), findsOneWidget);
          expect(
            tester.element(find.byType(AppDialog)),
            same(initialDialogElement),
            reason:
                'Dialog Element identity must be preserved across live brand switch',
          );
          expect(
            tester.state(dialogStateFinder),
            same(initialDialogState),
            reason:
                'Dialog State identity must be preserved across live brand switch',
          );
          expect(
            ModalRoute.of(tester.element(find.byType(AppDialog))),
            same(initialDialogRoute),
            reason:
                'Dialog ModalRoute identity must be preserved across live brand switch',
          );

          expect(titleCtrl.text, scenario.draftTitle);
          expect(titleCtrl.selection, selection);
          expect(noteCtrl.text, scenario.draftNote);

          assertBrandStyle(
            scenario.targetBrand,
            '2. after switch to ${scenario.targetBrand}',
          );
          await assertDialogReachabilityAndBounds(
            '2. after targetBrand switch',
          );
          await _capture(
            tester,
            fixture.boundaryKey,
            '${scenario.name}-02-target-brand',
          );

          // 5. Live brand roundtrip back to initialBrand
          await tester.runAsync(() async {
            final reverted = await fixture.theme.setBrand(
              scenario.initialBrand,
            );
            expect(reverted, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 3),
              onTimeout: () {},
            );
          });
          await _boundedPump(tester);
          expect(tester.takeException(), isNull);
          expect(fixture.theme.brand.id, scenario.initialBrand);

          expect(find.byType(AppDialog), findsOneWidget);
          expect(
            tester.element(find.byType(AppDialog)),
            same(initialDialogElement),
            reason:
                'Dialog Element identity must be preserved across live brand roundtrip',
          );
          expect(
            tester.state(dialogStateFinder),
            same(initialDialogState),
            reason:
                'Dialog State identity must be preserved across live brand roundtrip',
          );
          expect(
            ModalRoute.of(tester.element(find.byType(AppDialog))),
            same(initialDialogRoute),
            reason:
                'Dialog ModalRoute identity must be preserved across live brand roundtrip',
          );

          expect(titleCtrl.text, scenario.draftTitle);
          expect(titleCtrl.selection, selection);
          expect(noteCtrl.text, scenario.draftNote);

          assertBrandStyle(
            scenario.initialBrand,
            '3. after roundtrip to ${scenario.initialBrand}',
          );
          await assertDialogReachabilityAndBounds('3. after brand roundtrip');
          await _capture(
            tester,
            fixture.boundaryKey,
            '${scenario.name}-03-roundtrip-brand',
          );

          // 6. Live locale switch to alternateLocale
          I18n.setLocale(scenario.alternateLocale);
          await _boundedPump(tester);
          expect(tester.takeException(), isNull);

          expect(find.byType(AppDialog), findsOneWidget);
          expect(
            tester.element(find.byType(AppDialog)),
            same(initialDialogElement),
            reason:
                'Dialog Element identity must be preserved across live locale change',
          );
          expect(
            tester.state(dialogStateFinder),
            same(initialDialogState),
            reason:
                'Dialog State identity must be preserved across live locale change',
          );
          expect(
            ModalRoute.of(tester.element(find.byType(AppDialog))),
            same(initialDialogRoute),
            reason:
                'Dialog ModalRoute identity must be preserved across live locale change',
          );

          expect(titleCtrl.text, scenario.draftTitle);
          expect(titleCtrl.selection, selection);
          expect(noteCtrl.text, scenario.draftNote);

          await assertDialogReachabilityAndBounds(
            '4. after switch to alternateLocale',
          );
          await _capture(
            tester,
            fixture.boundaryKey,
            '${scenario.name}-04-alternate-locale',
          );

          // 7. Live locale roundtrip back to initialLocale
          I18n.setLocale(scenario.initialLocale);
          await _boundedPump(tester);
          expect(tester.takeException(), isNull);

          expect(find.byType(AppDialog), findsOneWidget);
          expect(
            tester.element(find.byType(AppDialog)),
            same(initialDialogElement),
            reason:
                'Dialog Element identity must be preserved across live locale roundtrip',
          );
          expect(
            tester.state(dialogStateFinder),
            same(initialDialogState),
            reason:
                'Dialog State identity must be preserved across live locale roundtrip',
          );
          expect(
            ModalRoute.of(tester.element(find.byType(AppDialog))),
            same(initialDialogRoute),
            reason:
                'Dialog ModalRoute identity must be preserved across live locale roundtrip',
          );

          expect(titleCtrl.text, scenario.draftTitle);
          expect(titleCtrl.selection, selection);
          expect(noteCtrl.text, scenario.draftNote);

          await assertDialogReachabilityAndBounds(
            '5. after roundtrip to initialLocale',
          );
          await _capture(
            tester,
            fixture.boundaryKey,
            '${scenario.name}-05-roundtrip-locale',
          );

          // 8. Account generation guard test: established authorization produces zero writes
          if (scenario.isAccountGuard) {
            final oldAccountGen = AccountLocalDataCleaner.accountDataGeneration;
            AccountLocalDataCleaner.invalidateInFlightAccountWrites();
            expect(
              AccountLocalDataCleaner.accountDataGeneration,
              greaterThan(oldAccountGen),
              reason: 'Account generation must be incremented',
            );
            await _boundedPump(tester);

            // Established authorization: dialog is not artificially auto-dismissed
            expect(
              find.byType(AppDialog),
              findsOneWidget,
              reason:
                  'Established dialog remains mounted until user action or route disposal',
            );

            // User taps Save after account changed
            final saveBtn = find.descendant(
              of: find.byType(AppDialog),
              matching: find.widgetWithText(
                FilledButton,
                CalendarEventSheetUiCopy.save,
              ),
            );
            await tester.ensureVisible(saveBtn);
            await _boundedPump(tester);
            expect(saveBtn.hitTestable(), findsOneWidget);
            await tester.tap(saveBtn);
            await _drainAccountWrites(tester);
            await _boundedPump(tester);

            // showLocalCalendarEventEditor detects changed generation and discards stale draft
            expect(
              store.calendarWrites,
              equals(baselineCalendarWrites),
              reason:
                  'Stale account generation commit must make exactly zero calendar storage writes',
            );
            expect(
              store.calendarRemoves,
              equals(baselineCalendarRemoves),
              reason:
                  'Stale account generation commit must make zero calendar storage removes',
            );
            expect(
              fixture.calendarProvider.localEvents,
              isEmpty,
              reason:
                  'Stale account generation must not mutate local events collection',
            );
            expect(
              find.byType(AppDialog),
              findsNothing,
              reason: 'Dialog pops cleanly when user submits',
            );
            await _capture(
              tester,
              fixture.boundaryKey,
              '${scenario.name}-06-account-guarded',
            );
            return;
          }

          // 9. Action execution: Cancel (zero writes) vs Submit (exactly one business persistence write)
          if (!scenario.testConfirm) {
            final cancelBtn = find.descendant(
              of: find.byType(AppDialog),
              matching: find.widgetWithText(
                TextButton,
                CalendarEventSheetUiCopy.cancel,
              ),
            );
            await tester.ensureVisible(cancelBtn);
            await _boundedPump(tester);
            expect(cancelBtn.hitTestable(), findsOneWidget);
            await tester.tap(cancelBtn);
            await _boundedPump(tester);
            expect(tester.takeException(), isNull);

            // Dialog dismissed cleanly, host remains mounted
            expect(find.byType(AppDialog), findsNothing);
            expect(find.byType(_CalendarLocalEditorHost), findsOneWidget);

            // Assert exactly zero calendar mutations
            expect(
              store.calendarWrites,
              equals(baselineCalendarWrites),
              reason: 'Cancel must make exactly zero calendar storage writes',
            );
            expect(
              store.calendarRemoves,
              equals(baselineCalendarRemoves),
              reason: 'Cancel must make zero calendar storage removes',
            );
            if (!scenario.isEditMode) {
              expect(
                fixture.calendarProvider.localEvents,
                isEmpty,
                reason: 'Cancel must not add any local event items',
              );
            }

            await _capture(
              tester,
              fixture.boundaryKey,
              '${scenario.name}-06-cancelled',
            );
          } else {
            final saveBtn = find.descendant(
              of: find.byType(AppDialog),
              matching: find.widgetWithText(
                FilledButton,
                CalendarEventSheetUiCopy.save,
              ),
            );
            await tester.ensureVisible(saveBtn);
            await _boundedPump(tester);
            expect(saveBtn.hitTestable(), findsOneWidget);
            await tester.tap(saveBtn);
            await _drainAccountWrites(tester);
            await _boundedPump(tester);
            expect(tester.takeException(), isNull);

            // Dialog dismissed cleanly, host remains mounted
            expect(find.byType(AppDialog), findsNothing);
            expect(find.byType(_CalendarLocalEditorHost), findsOneWidget);

            // Assert exactly one business persistence operation
            if (scenario.isEditMode) {
              expect(
                fixture.calendarProvider.localEvents.length,
                1,
                reason: 'Edit must update existing local event',
              );
              final updated = fixture.calendarProvider.localEvents.single;
              expect(updated.id, 'local_fixture_event_001');
              expect(updated.title, scenario.draftTitle);
              expect(updated.note, scenario.draftNote);
              expect(
                store.calendarWrites,
                equals(baselineCalendarWrites + 1),
                reason:
                    'Submit edit must perform exactly one business persistence operation',
              );
              expect(
                store.calendarRemoves,
                equals(baselineCalendarRemoves),
                reason: 'Submit edit must perform zero storage removes',
              );
            } else {
              expect(
                fixture.calendarProvider.localEvents.length,
                1,
                reason: 'Submit must add exactly one local event item',
              );
              final submitted = fixture.calendarProvider.localEvents.single;
              expect(
                submitted.title,
                scenario.draftTitle,
                reason: 'Submitted event must contain the draft title',
              );
              expect(
                submitted.note,
                scenario.draftNote,
                reason: 'Submitted event must contain the draft note',
              );
              expect(
                submitted.color,
                const Color(0xFF26A69A),
                reason: 'Submitted event must capture selected color choice',
              );
              expect(
                submitted.time,
                isNotNull,
                reason:
                    'Submitted event must capture picked time when allDay is false',
              );
              expect(
                store.calendarWrites,
                equals(baselineCalendarWrites + 1),
                reason:
                    'Submit create must perform exactly one business persistence operation',
              );
              expect(
                store.calendarRemoves,
                equals(baselineCalendarRemoves),
                reason: 'Submit create must perform zero storage removes',
              );
            }

            await _capture(
              tester,
              fixture.boundaryKey,
              '${scenario.name}-06-submitted',
            );
          }
        } finally {
          await fixture.dispose(tester);
          SharedPreferencesStorePlatform.instance = prevStore;
          debugDisableShadows = originalShadows;
          I18n.setLocale(initialGlobalLocale);
        }
      },
    );
  }

  // Isolated defect test: Empty-title submit retains dialog and draft instead of dismissing.
  // Fails on frozen product (failing-original) due to Navigator.pop(context, null).
  // Passes on current product (passing-current) due to validation return.
  testWidgets(
    'Local calendar event editor preserves dialog and retains draft on empty title submit',
    (tester) async {
      I18n.setLocale(AppLocale.zh);
      final originalShadows = debugDisableShadows;
      debugDisableShadows = false;
      final prevStore = SharedPreferencesStorePlatform.instance;
      final fixture = _CalendarLocalEditorFixture();
      try {
        final initialPrefs = <String, Object>{
          'pref_app_timezone_mode': 'fixed',
          'pref_app_timezone_iana': 'Asia/Shanghai',
          'active_brand': 'defaultBrand',
          'theme_shop_state': jsonEncode({
            'activeBrand': 'defaultBrand',
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          }),
          'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          'flutter.active_brand': 'defaultBrand',
        };
        SharedPreferences.setMockInitialValues(initialPrefs);
        final store = _RecordingPreferencesStore({
          for (final entry in initialPrefs.entries)
            if (!entry.key.startsWith('flutter.'))
              'flutter.${entry.key}': entry.value,
        });
        SharedPreferencesStorePlatform.instance = store;

        const scenario = _LocalEditorScenario(
          name: 'empty-title-validation-isolation',
          initialLocale: AppLocale.zh,
          alternateLocale: AppLocale.en,
          initialBrand: 'defaultBrand',
          targetBrand: 'liquidGlass',
          size: Size(390, 844),
          textScaler: TextScaler.linear(1.0),
          devicePixelRatio: 2.0,
          testConfirm: false,
          draftTitle: '',
          draftNote: '保留的草稿备注内容',
        );

        await fixture.mount(
          tester: tester,
          scenario: scenario,
          initialDate: DateTime(2027, 6, 15),
        );

        final baselineCalendarWrites = store.calendarWrites;

        // Open local event editor
        final createBtn = find.byKey(
          const ValueKey('open_create_local_event_button'),
        );
        expect(createBtn, findsOneWidget);
        await tester.ensureVisible(createBtn);
        await _boundedPump(tester);
        expect(createBtn.hitTestable(), findsOneWidget);
        await tester.tap(createBtn);
        await _boundedPump(tester);

        final dialogFinder = find.byType(AppDialog);
        expect(dialogFinder, findsOneWidget);

        final titleFieldFinder = find
            .descendant(of: dialogFinder, matching: find.byType(TextField))
            .first;
        final noteFieldFinder = find
            .descendant(of: dialogFinder, matching: find.byType(TextField))
            .last;

        final noteWidget = tester.widget<TextField>(noteFieldFinder);
        final noteCtrl = noteWidget.controller!;

        // Fill note but leave title empty
        await tester.enterText(noteFieldFinder, '保留的草稿备注内容');
        await _boundedPump(tester);
        await tester.enterText(titleFieldFinder, '');
        await _boundedPump(tester);

        final saveBtn = find.descendant(
          of: dialogFinder,
          matching: find.widgetWithText(
            FilledButton,
            CalendarEventSheetUiCopy.save,
          ),
        );
        await tester.ensureVisible(saveBtn);
        await _boundedPump(tester);
        expect(saveBtn.hitTestable(), findsOneWidget);
        await tester.tap(saveBtn);
        await _boundedPump(tester);

        // Verification: Dialog must remain visible; draft note retained; zero writes.
        // On frozen product: Navigator.pop was called, so find.byType(AppDialog) is empty -> FAILS.
        // On current product: returns early without popping -> PASSES.
        expect(
          find.byType(AppDialog),
          findsOneWidget,
          reason:
              'Dialog must NOT be dismissed when Save is pressed with empty title (validation & draft retention)',
        );
        expect(
          noteCtrl.text,
          equals('保留的草稿备注内容'),
          reason:
              'Draft note must be retained on empty title validation rejection',
        );
        expect(
          store.calendarWrites,
          equals(baselineCalendarWrites),
          reason: 'Zero storage writes on empty title validation rejection',
        );

        // Cleanly dismiss dialog with Cancel
        final cancelBtn = find.descendant(
          of: dialogFinder,
          matching: find.widgetWithText(
            TextButton,
            CalendarEventSheetUiCopy.cancel,
          ),
        );
        await tester.ensureVisible(cancelBtn);
        await _boundedPump(tester);
        expect(cancelBtn.hitTestable(), findsOneWidget);
        await tester.tap(cancelBtn);
        await _boundedPump(tester);
        expect(find.byType(AppDialog), findsNothing);
      } finally {
        await fixture.dispose(tester);
        SharedPreferencesStorePlatform.instance = prevStore;
        debugDisableShadows = originalShadows;
        I18n.setLocale(initialGlobalLocale);
      }
    },
  );

  // Isolated test for covered route & safe picker callback guards
  testWidgets(
    'Local calendar event editor preserves routes and handles picker callbacks safely when covered',
    (tester) async {
      I18n.setLocale(AppLocale.zh);
      final originalShadows = debugDisableShadows;
      debugDisableShadows = false;
      final prevStore = SharedPreferencesStorePlatform.instance;
      final fixture = _CalendarLocalEditorFixture();
      try {
        final initialPrefs = <String, Object>{
          'pref_app_timezone_mode': 'fixed',
          'pref_app_timezone_iana': 'Asia/Shanghai',
          'active_brand': 'defaultBrand',
          'theme_shop_state': jsonEncode({
            'activeBrand': 'defaultBrand',
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          }),
          'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          'flutter.active_brand': 'defaultBrand',
        };
        SharedPreferences.setMockInitialValues(initialPrefs);
        final store = _RecordingPreferencesStore({
          for (final entry in initialPrefs.entries)
            if (!entry.key.startsWith('flutter.'))
              'flutter.${entry.key}': entry.value,
        });
        SharedPreferencesStorePlatform.instance = store;

        const scenario = _LocalEditorScenario(
          name: 'covered-route-guard-isolation',
          initialLocale: AppLocale.zh,
          alternateLocale: AppLocale.en,
          initialBrand: 'defaultBrand',
          targetBrand: 'liquidGlass',
          size: Size(390, 844),
          textScaler: TextScaler.linear(1.0),
          devicePixelRatio: 2.0,
          testConfirm: false,
          draftTitle: 'Covered Route Test',
          draftNote: 'Notes',
        );

        await fixture.mount(
          tester: tester,
          scenario: scenario,
          initialDate: DateTime(2027, 6, 15),
        );

        final baselineCalendarWrites = store.calendarWrites;

        // Open local event editor
        final createBtn = find.byKey(
          const ValueKey('open_create_local_event_button'),
        );
        expect(createBtn, findsOneWidget);
        await tester.ensureVisible(createBtn);
        await _boundedPump(tester);
        expect(createBtn.hitTestable(), findsOneWidget);
        await tester.tap(createBtn);
        await _boundedPump(tester);

        final dialogFinder = find.byType(AppDialog);
        expect(dialogFinder, findsOneWidget);
        final dialogElement = tester.element(dialogFinder);
        final dialogRoute = ModalRoute.of(dialogElement);
        expect(dialogRoute?.isCurrent, isTrue);

        // Open date picker to cover the dialog
        final startDateTile = find.widgetWithText(
          ListTile,
          CalendarEventSheetUiCopy.startDate,
        );
        expect(startDateTile, findsOneWidget);
        await tester.ensureVisible(startDateTile);
        await _boundedPump(tester);
        expect(startDateTile.hitTestable(), findsOneWidget);
        await tester.tap(startDateTile);
        await _boundedPump(tester);

        final dateModalFinder = find.byType(AppModalSheet);
        expect(dateModalFinder, findsOneWidget);
        expect(
          dialogRoute?.isCurrent,
          isFalse,
          reason: 'Dialog is covered while date picker is open',
        );

        // Cancel the date picker
        final cancelPickerBtn = find.descendant(
          of: dateModalFinder,
          matching: find.widgetWithText(
            TextButton,
            I18n.tr('action.cancel'),
          ),
        );
        expect(cancelPickerBtn, findsOneWidget);
        await tester.ensureVisible(cancelPickerBtn);
        await _boundedPump(tester);
        expect(cancelPickerBtn.hitTestable(), findsOneWidget);
        await tester.tap(cancelPickerBtn);
        await _boundedPump(tester);

        expect(find.byType(AppModalSheet), findsNothing);
        expect(
          dialogRoute?.isCurrent,
          isTrue,
          reason: 'Dialog is current again after date picker is dismissed',
        );

        // Cancel dialog
        final cancelBtn = find.descendant(
          of: dialogFinder,
          matching: find.widgetWithText(
            TextButton,
            CalendarEventSheetUiCopy.cancel,
          ),
        );
        await tester.ensureVisible(cancelBtn);
        await _boundedPump(tester);
        expect(cancelBtn.hitTestable(), findsOneWidget);
        await tester.tap(cancelBtn);
        await _boundedPump(tester);

        expect(find.byType(AppDialog), findsNothing);
        expect(
          store.calendarWrites,
          equals(baselineCalendarWrites),
          reason: 'Zero calendar writes on cancel',
        );
      } finally {
        await fixture.dispose(tester);
        SharedPreferencesStorePlatform.instance = prevStore;
        debugDisableShadows = originalShadows;
        I18n.setLocale(initialGlobalLocale);
      }
    },
  );
}
