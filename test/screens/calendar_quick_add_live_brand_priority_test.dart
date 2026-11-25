// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/calendar_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/models/workspace.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/calendar_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/reminder_scheduler.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandBackground;
import 'package:duoyi/widgets/surface_components.dart'
    show AppDialog, AppSecondaryControlTheme, appSurfaceStyleOf;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/retained_dialog_text_probe.dart';
import '../support/weekly_review_screenshot_font.dart';
import '../test_support/recording_reminder_scheduler.dart';

class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore(super.data) : super.withData();

  int todoWrites = 0;
  int todoRemoves = 0;
  final List<String> recordedTodoPayloads = [];

  static bool _isTodoKey(String key) =>
      key == 'todos' || key == 'flutter.todos' || key.endsWith('.todos');

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (_isTodoKey(key)) {
      todoWrites++;
      recordedTodoPayloads.add(value.toString());
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    if (_isTodoKey(key)) {
      todoRemoves++;
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

class _FixtureTodoProvider extends TodoProvider {
  _FixtureTodoProvider({
    List<TodoItem> todos = const <TodoItem>[],
    ReminderScheduler? scheduler,
  }) : _initialTodos = todos {
    if (scheduler != null) this.scheduler = scheduler;
  }

  final List<TodoItem> _initialTodos;
  Completer<void>? addGate;
  final List<TodoItem> addedTodos = <TodoItem>[];
  int addCalls = 0;

  @override
  List<TodoItem> get todos => [..._initialTodos, ...super.todos];

  @override
  Future<void> addTodo(
    TodoItem todo, {
    bool waitForReminderSync = true,
    bool reportReminderScheduleFailure = false,
    bool Function()? canWrite,
  }) async {
    addCalls++;
    addedTodos.add(todo);
    final gate = addGate;
    if (gate != null) await gate.future;
    await super.addTodo(
      todo,
      waitForReminderSync: waitForReminderSync,
      reportReminderScheduleFailure: reportReminderScheduleFailure,
      canWrite: canWrite,
    );
  }
}

class _FixtureHabitProvider extends HabitProvider {
  @override
  List<Habit> get habits => const <Habit>[];
}

class _FixturePomodoroProvider extends PomodoroProvider {
  @override
  List<PomodoroSession> get sessions => const <PomodoroSession>[];
}

class _FixtureShareProvider extends ShareProvider {
  _FixtureShareProvider(this.fixtureWorkspaces);

  final List<Workspace> fixtureWorkspaces;

  @override
  List<Workspace> get workspaces => fixtureWorkspaces;
}

class _FixtureTimeAuditProvider extends TimeAuditProvider {
  final List<TimeEntry> fixtureEntries = <TimeEntry>[];

  @override
  List<TimeEntry> get entries => fixtureEntries;
}

class _QuickAddPriorityScenario {
  final String name;
  final AppLocale initialLocale;
  final AppLocale alternateLocale;
  final String initialBrand;
  final String targetBrand;
  final Size size;
  final double scale;
  final double devicePixelRatio;
  final bool testConfirm;
  final String draftTitle;

  const _QuickAddPriorityScenario({
    required this.name,
    required this.initialLocale,
    required this.alternateLocale,
    required this.initialBrand,
    required this.targetBrand,
    required this.size,
    required this.scale,
    required this.devicePixelRatio,
    required this.testConfirm,
    required this.draftTitle,
  });
}

const _scenarios = <_QuickAddPriorityScenario>[
  _QuickAddPriorityScenario(
    name: 'zh-portrait-320x844-dpr2-defaultBrand',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(320, 844),
    scale: 2.0,
    devicePixelRatio: 2.0,
    testConfirm: false,
    draftTitle: '准备季度产品发布备忘录并与所有移动端负责人同步会议议程',
  ),
  _QuickAddPriorityScenario(
    name: 'en-portrait-320x844-dpr2-liquidGlass',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(320, 844),
    scale: 2.0,
    devicePixelRatio: 2.0,
    testConfirm: true,
    draftTitle:
        'Prepare quarterly product launch notes and sync agenda across all mobile leads',
  ),
  _QuickAddPriorityScenario(
    name: 'zh-landscape-844x390-dpr1-liquidGlass',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(844, 390),
    scale: 1.0,
    devicePixelRatio: 1.0,
    testConfirm: true,
    draftTitle: '整理多端协同组件规范并发布跨平台设计系统文档',
  ),
  _QuickAddPriorityScenario(
    name: 'en-landscape-844x390-dpr1-defaultBrand',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(844, 390),
    scale: 1.0,
    devicePixelRatio: 1.0,
    testConfirm: false,
    draftTitle:
        'Review engineering specifications and coordinate architecture signoff for release',
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
  await tester.runAsync(() => AccountPreferenceWrites.drain().timeout(timeout));
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
      final file = File('$explicitDir/calendar-quick-add-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

class _CalendarQuickAddFixture {
  late final SharedPreferences prefs;
  late final ThemeProvider theme;
  late final PreferencesProvider preferences;
  late final _FixtureTodoProvider todoProvider;
  late final _FixtureHabitProvider habitProvider;
  late final _FixturePomodoroProvider pomodoroProvider;
  late final CalendarProvider calendarProvider;
  late final AnniversaryProvider anniversaryProvider;
  late final CountdownProvider countdownProvider;
  late final CourseProvider courseProvider;
  late final DiaryProvider diaryProvider;
  late final GoalProvider goalProvider;
  late final _FixtureShareProvider shareProvider;
  late final _FixtureTimeAuditProvider timeAuditProvider;
  late final RecordingReminderScheduler scheduler;
  final navigatorKey = GlobalKey<NavigatorState>();
  final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final observer = _RecordingNavigatorObserver();
  final boundaryKey = GlobalKey();
  bool _installed = false;
  bool _disposed = false;

  Future<void> mount({
    required WidgetTester tester,
    required _QuickAddPriorityScenario scenario,
    required DateTime initialDate,
    List<Workspace> workspaces = const <Workspace>[],
  }) async {
    if (!_installed) {
      _installed = true;
      await tester.runAsync(() async {
        scheduler = RecordingReminderScheduler();
        prefs = await SharedPreferences.getInstance();
        theme = ThemeProvider();
        preferences = PreferencesProvider();
        todoProvider = _FixtureTodoProvider(scheduler: scheduler);
        habitProvider = _FixtureHabitProvider();
        pomodoroProvider = _FixturePomodoroProvider();
        calendarProvider = CalendarProvider();
        anniversaryProvider = AnniversaryProvider();
        countdownProvider = CountdownProvider();
        courseProvider = CourseProvider();
        diaryProvider = DiaryProvider();
        goalProvider = GoalProvider();
        shareProvider = _FixtureShareProvider(workspaces);
        timeAuditProvider = _FixtureTimeAuditProvider();

        await theme.loadFromStorage().timeout(const Duration(seconds: 5));
        await preferences.loadFromStorage().timeout(const Duration(seconds: 5));
        await todoProvider.loadFromStorage().timeout(
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
    }

    tester.view.physicalSize = scenario.size * scenario.devicePixelRatio;
    tester.view.devicePixelRatio = scenario.devicePixelRatio;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
          ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
          ChangeNotifierProvider<HabitProvider>.value(value: habitProvider),
          ChangeNotifierProvider<PomodoroProvider>.value(
            value: pomodoroProvider,
          ),
          ChangeNotifierProvider<CalendarProvider>.value(
            value: calendarProvider,
          ),
          ChangeNotifierProvider<AnniversaryProvider>.value(
            value: anniversaryProvider,
          ),
          ChangeNotifierProvider<CountdownProvider>.value(
            value: countdownProvider,
          ),
          ChangeNotifierProvider<CourseProvider>.value(value: courseProvider),
          ChangeNotifierProvider<DiaryProvider>.value(value: diaryProvider),
          ChangeNotifierProvider<GoalProvider>.value(value: goalProvider),
          ChangeNotifierProvider<ShareProvider>.value(value: shareProvider),
          ChangeNotifierProvider<TimeAuditProvider>.value(
            value: timeAuditProvider,
          ),
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
                      size: scenario.size,
                      textScaler: TextScaler.linear(scenario.scale),
                    ),
                    child: RepaintBoundary(key: boundaryKey, child: child!),
                  ),
                  home: Stack(
                    children: [
                      BrandBackground(
                        key: const ValueKey('calendar_outer_brand_background'),
                        child: CalendarScreen(initialDate: initialDate),
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
      if (_installed) {
        theme.dispose();
        preferences.dispose();
        todoProvider.dispose();
        habitProvider.dispose();
        pomodoroProvider.dispose();
        calendarProvider.dispose();
        anniversaryProvider.dispose();
        countdownProvider.dispose();
        courseProvider.dispose();
        diaryProvider.dispose();
        goalProvider.dispose();
        shareProvider.dispose();
        timeAuditProvider.dispose();
      }
    }
  }
}

void main() {
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets(
      'CalendarScreen FAB -> menu -> New task live brand priority ${scenario.name}',
      (tester) async {
        I18n.setLocale(scenario.initialLocale);
        final originalShadows = debugDisableShadows;
        debugDisableShadows = false;
        try {
          final previousTimezoneReader =
              LocalTimezoneResolver.debugSystemTimeZoneReader;
          LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
              'Asia/Shanghai';
          addTearDown(
            () => LocalTimezoneResolver.debugSystemTimeZoneReader =
                previousTimezoneReader,
          );

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
          final prevStore = SharedPreferencesStorePlatform.instance;
          SharedPreferencesStorePlatform.instance = store;
          addTearDown(
            () => SharedPreferencesStorePlatform.instance = prevStore,
          );

          final fixture = _CalendarQuickAddFixture();
          addTearDown(() => fixture.dispose(tester));

          await fixture.mount(
            tester: tester,
            scenario: scenario,
            initialDate: fixedDate,
          );
          expect(fixture.theme.brand.id, scenario.initialBrand);
          expect(fixture.theme.isBrandUnlocked(scenario.targetBrand), isTrue);

          // 1. Assert actual production entry in stable BrandBackground and verified MediaQuery
          expect(find.byType(CalendarScreen), findsOneWidget);
          expect(
            find.byKey(const ValueKey('calendar_outer_brand_background')),
            findsOneWidget,
            reason:
                'Outer BrandBackground wrapper must be present from first frame',
          );
          expect(
            find.byType(BrandBackground),
            findsNWidgets(2),
            reason:
                'Two BrandBackground instances: outer stable wrapper and screen BrandScaffold',
          );

          final media = MediaQuery.of(
            tester.element(find.byType(CalendarScreen)),
          );
          expect(
            media.size.width,
            closeTo(scenario.size.width, 0.001),
            reason: 'Logical width must match scenario specification',
          );
          expect(
            media.size.height,
            closeTo(scenario.size.height, 0.001),
            reason: 'Logical height must match scenario specification',
          );
          expect(
            media.devicePixelRatio,
            closeTo(scenario.devicePixelRatio, 0.001),
            reason: 'Device pixel ratio must match scenario specification',
          );
          expect(
            media.textScaler.scale(10.0),
            closeTo(scenario.scale * 10.0, 0.001),
            reason: 'Text scaler must match scenario specification',
          );

          final baselineTodoWrites = store.todoWrites;
          final baselineTodoRemoves = store.todoRemoves;

          // 2. Open FAB -> menu -> New task
          final fab = find.byType(FloatingActionButton);
          expect(fab, findsOneWidget);
          await tester.tap(fab);
          await _boundedPump(tester);
          expect(tester.takeException(), isNull);

          final newTaskMenuItem = find.text(
            CalendarUiCopy.quickAddNewTodoTitle,
          );
          expect(newTaskMenuItem, findsOneWidget);
          await tester.tap(newTaskMenuItem);
          await _boundedPump(tester);
          expect(tester.takeException(), isNull);

          final dialogFinder = find.byType(AppDialog);
          expect(dialogFinder, findsOneWidget);
          final initialDialogElement = tester.element(dialogFinder);
          final dialogStateFinder = find.byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == '_QuickAddTodoDialog',
          );
          expect(dialogStateFinder, findsOneWidget);
          final initialDialogState = tester.state(dialogStateFinder);
          final initialDialogRoute = ModalRoute.of(initialDialogElement);
          expect(initialDialogRoute, isNotNull);

          // 3. Enter realistic long draft and selection
          final textFieldFinder = find.descendant(
            of: dialogFinder,
            matching: find.byType(TextField),
          );
          expect(textFieldFinder, findsOneWidget);
          await tester.enterText(textFieldFinder, scenario.draftTitle);
          await _boundedPump(tester);

          final initialTextField = tester.widget<TextField>(textFieldFinder);
          final controller = initialTextField.controller!;
          final focusNode = initialTextField.focusNode!;
          const selection = TextSelection(baseOffset: 4, extentOffset: 16);
          controller.selection = selection;
          await _boundedPump(tester);

          expect(controller.text, scenario.draftTitle);
          expect(controller.selection, selection);
          expect(focusNode.hasFocus, isTrue);

          // Reference color assertion helper
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

          // Reachability, bounds, and Latin word wrap probe
          Future<void> assertDialogReachabilityAndBounds(String stage) async {
            final currentStrings = fixture.theme.brand.strings;
            final expectedTitle = CalendarUiCopy.quickAddTodoDialogTitle(
              currentStrings.calendarQuickAddTitle,
              fixedDate,
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

            final cancelLabel = I18n.tr('action.cancel');
            final cancelBtn = find.widgetWithText(TextButton, cancelLabel);
            await tester.ensureVisible(cancelBtn);
            await _boundedPump(tester);
            expect(
              cancelBtn.hitTestable(),
              findsOneWidget,
              reason: '$stage: Cancel action must be hit-testable',
            );
            expect(
              tester.getSize(cancelBtn).height,
              greaterThanOrEqualTo(44.0),
              reason: '$stage: Cancel action height must be at least 44dp',
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

            final addLabel = I18n.tr('action.add');
            final addBtn = find.widgetWithText(FilledButton, addLabel);
            await tester.ensureVisible(addBtn);
            await _boundedPump(tester);
            expect(
              addBtn.hitTestable(),
              findsOneWidget,
              reason: '$stage: Add action must be hit-testable',
            );
            expect(
              tester.getSize(addBtn).height,
              greaterThanOrEqualTo(44.0),
              reason: '$stage: Add action height must be at least 44dp',
            );
            final addText = find.descendant(
              of: addBtn,
              matching: find.byType(Text),
            );
            await verifyRetainedDialogText(tester, addText, expected: addLabel);

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

          expect(controller.text, scenario.draftTitle);
          expect(controller.selection, selection);
          expect(focusNode.hasFocus, isTrue);

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

          expect(controller.text, scenario.draftTitle);
          expect(controller.selection, selection);
          expect(focusNode.hasFocus, isTrue);

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

          expect(controller.text, scenario.draftTitle);
          expect(controller.selection, selection);
          expect(focusNode.hasFocus, isTrue);

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

          expect(controller.text, scenario.draftTitle);
          expect(controller.selection, selection);
          expect(focusNode.hasFocus, isTrue);

          await assertDialogReachabilityAndBounds(
            '5. after roundtrip to initialLocale',
          );
          await _capture(
            tester,
            fixture.boundaryKey,
            '${scenario.name}-05-roundtrip-locale',
          );

          // 8. Action execution: Cancel (zero mutation) vs Submit (captured day/workspace)
          if (!scenario.testConfirm) {
            final cancelBtn = find.widgetWithText(
              TextButton,
              I18n.tr('action.cancel'),
            );
            await tester.ensureVisible(cancelBtn);
            await _boundedPump(tester);
            await tester.tap(cancelBtn);
            await _boundedPump(tester);
            expect(tester.takeException(), isNull);

            // Dialog dismissed cleanly, CalendarScreen remains mounted
            expect(find.byType(AppDialog), findsNothing);
            expect(find.byType(CalendarScreen), findsOneWidget);

            // Assert zero Todo mutations
            expect(
              store.todoWrites,
              equals(baselineTodoWrites),
              reason: 'Cancel must make zero todo storage writes',
            );
            expect(
              store.todoRemoves,
              equals(baselineTodoRemoves),
              reason: 'Cancel must make zero todo storage removes',
            );
            expect(
              fixture.todoProvider.addedTodos,
              isEmpty,
              reason: 'Cancel must not add any todo items',
            );

            await _capture(
              tester,
              fixture.boundaryKey,
              '${scenario.name}-06-cancelled',
            );
          } else {
            final addBtn = find.widgetWithText(
              FilledButton,
              I18n.tr('action.add'),
            );
            await tester.ensureVisible(addBtn);
            await _boundedPump(tester);
            await tester.tap(addBtn);
            await _drainAccountWrites(tester);
            await _boundedPump(tester);
            expect(tester.takeException(), isNull);

            // Dialog dismissed cleanly, CalendarScreen remains mounted
            expect(find.byType(AppDialog), findsNothing);
            expect(find.byType(CalendarScreen), findsOneWidget);

            // Assert one submit exactly once with correct captured day/workspace
            expect(
              fixture.todoProvider.addedTodos.length,
              1,
              reason: 'Submit must add exactly one todo item',
            );
            final submittedTodo = fixture.todoProvider.addedTodos.single;
            expect(
              submittedTodo.title,
              scenario.draftTitle,
              reason: 'Submitted todo must contain the draft title',
            );
            expect(
              submittedTodo.date,
              fixedDate,
              reason:
                  'Submitted todo must capture the exact initial origin day',
            );
            expect(
              submittedTodo.workspaceId,
              'private',
              reason:
                  'Submitted todo must capture private workspace when unassigned',
            );
            expect(
              store.todoWrites,
              greaterThan(baselineTodoWrites),
              reason: 'Submit must persist todo item to storage',
            );

            await _capture(
              tester,
              fixture.boundaryKey,
              '${scenario.name}-06-submitted',
            );
          }
        } finally {
          debugDisableShadows = originalShadows;
        }
      },
    );
  }

  testWidgets(
    'empty input cannot submit and duplicate in-flight submission is prevented',
    (tester) async {
      final previousTimezoneReader =
          LocalTimezoneResolver.debugSystemTimeZoneReader;
      LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
          'Asia/Shanghai';
      addTearDown(
        () => LocalTimezoneResolver.debugSystemTimeZoneReader =
            previousTimezoneReader,
      );

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
      final prevStore = SharedPreferencesStorePlatform.instance;
      SharedPreferencesStorePlatform.instance = store;
      addTearDown(() => SharedPreferencesStorePlatform.instance = prevStore);

      final fixture = _CalendarQuickAddFixture();
      addTearDown(() => fixture.dispose(tester));

      const scenario = _QuickAddPriorityScenario(
        name: 'empty-and-dedup-submit',
        initialLocale: AppLocale.zh,
        alternateLocale: AppLocale.en,
        initialBrand: 'defaultBrand',
        targetBrand: 'liquidGlass',
        size: Size(320, 844),
        scale: 2.0,
        devicePixelRatio: 2.0,
        testConfirm: true,
        draftTitle: 'In-flight dedup task',
      );

      await fixture.mount(
        tester: tester,
        scenario: scenario,
        initialDate: DateTime(2027, 6, 15),
      );

      // Open FAB -> menu -> New task
      await tester.tap(find.byType(FloatingActionButton));
      await _boundedPump(tester);
      await tester.tap(find.text(CalendarUiCopy.quickAddNewTodoTitle));
      await _boundedPump(tester);
      expect(find.byType(AppDialog), findsOneWidget);

      // 1. Empty input cannot submit
      final addBtn = find.widgetWithText(FilledButton, I18n.tr('action.add'));
      await tester.tap(addBtn);
      await tester.pump();
      expect(fixture.todoProvider.addCalls, 0);
      expect(find.byType(AppDialog), findsOneWidget);

      // Whitespace only cannot submit
      await tester.enterText(
        find.descendant(
          of: find.byType(AppDialog),
          matching: find.byType(TextField),
        ),
        '    ',
      );
      await tester.tap(addBtn);
      await tester.pump();
      expect(fixture.todoProvider.addCalls, 0);
      expect(find.byType(AppDialog), findsOneWidget);

      // 2. Prevent duplicate in-flight submission
      final submitGate = Completer<void>();
      fixture.todoProvider.addGate = submitGate;

      await tester.enterText(
        find.descendant(
          of: find.byType(AppDialog),
          matching: find.byType(TextField),
        ),
        'In-flight dedup task',
      );
      await tester.tap(addBtn);
      await tester.pump();
      expect(fixture.todoProvider.addCalls, 1);

      // Submit button is disabled in-flight and shows spinner
      expect(
        find.descendant(
          of: find.byType(AppDialog),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      // Second submit attempt during flight cannot trigger duplicate call
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(fixture.todoProvider.addCalls, 1);

      // Complete flight gate
      submitGate.complete();
      await tester.pump();
      await _drainAccountWrites(tester);
      await _boundedPump(tester);

      expect(find.byType(AppDialog), findsNothing);
      expect(
        fixture.todoProvider.addedTodos.single.title,
        'In-flight dedup task',
      );
      expect(fixture.todoProvider.addCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'held Todo submit across origin invalidation cannot pop unrelated route',
    (tester) async {
      final previousTimezoneReader =
          LocalTimezoneResolver.debugSystemTimeZoneReader;
      LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
          'Asia/Shanghai';
      addTearDown(
        () => LocalTimezoneResolver.debugSystemTimeZoneReader =
            previousTimezoneReader,
      );

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
      final prevStore = SharedPreferencesStorePlatform.instance;
      SharedPreferencesStorePlatform.instance = store;
      addTearDown(() => SharedPreferencesStorePlatform.instance = prevStore);

      final fixture = _CalendarQuickAddFixture();
      addTearDown(() => fixture.dispose(tester));

      const scenario = _QuickAddPriorityScenario(
        name: 'held-origin-invalidation',
        initialLocale: AppLocale.zh,
        alternateLocale: AppLocale.en,
        initialBrand: 'defaultBrand',
        targetBrand: 'liquidGlass',
        size: Size(320, 844),
        scale: 2.0,
        devicePixelRatio: 2.0,
        testConfirm: true,
        draftTitle: 'Held origin invalidation task',
      );

      await fixture.mount(
        tester: tester,
        scenario: scenario,
        initialDate: DateTime(2027, 6, 15),
      );

      // Open FAB -> menu -> New task
      await tester.tap(find.byType(FloatingActionButton));
      await _boundedPump(tester);
      await tester.tap(find.text(CalendarUiCopy.quickAddNewTodoTitle));
      await _boundedPump(tester);
      expect(find.byType(AppDialog), findsOneWidget);

      final submitGate = Completer<void>();
      fixture.todoProvider.addGate = submitGate;

      await tester.enterText(
        find.descendant(
          of: find.byType(AppDialog),
          matching: find.byType(TextField),
        ),
        'Held origin invalidation task',
      );

      final addBtn = find.widgetWithText(FilledButton, I18n.tr('action.add'));
      await tester.tap(addBtn);
      await tester.pump();
      expect(fixture.todoProvider.addCalls, 1);

      // While held in flight, invalidate origin
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();

      // Push an unrelated route on top of the Navigator stack
      final unrelatedRoute = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Unrelated Top Route')),
      );
      fixture.navigatorKey.currentState!.push(unrelatedRoute);
      await tester.pump();
      await _boundedPump(tester);
      expect(unrelatedRoute.isCurrent, isTrue);

      // Release the held submit gate
      submitGate.complete();
      await tester.pump();
      await _boundedPump(tester);

      // Unrelated top route must NOT have been popped
      expect(unrelatedRoute.isCurrent, isTrue);
      expect(find.text('Unrelated Top Route'), findsOneWidget);
      expect(fixture.observer.popped, isNot(contains(unrelatedRoute)));
      expect(fixture.observer.removed, isNot(contains(unrelatedRoute)));
      expect(tester.takeException(), isNull);
    },
  );
}
