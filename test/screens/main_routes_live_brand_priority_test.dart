import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/calendar_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/todo_board_ui_copy.dart';
import 'package:duoyi/models/todo.dart';
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
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/calendar_screen.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

class _MainRoutesPriorityProbe extends RouteRenderProbe {
  _MainRoutesPriorityProbe(super.tester, super.boundary, super.name);

  @override
  Future<void> capture(String stage) async {
    await super.capture(stage);
    final explicitDir =
        Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
    if (explicitDir != null &&
        explicitDir.isNotEmpty &&
        Platform.environment['DUOYI_SECONDARY_SCREENSHOTS'] == null) {
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        try {
          final data =
              (await image.toByteData(format: ui.ImageByteFormat.png))!;
          final file = File('$explicitDir/$name-$stage.png');
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(data.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }
  }
}

Future<List<int>> _samplePoints(
  WidgetTester tester,
  GlobalKey boundaryKey,
  List<Offset> points,
) async {
  return (await tester.runAsync(() async {
    final render =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    try {
      final raw = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return [
        for (final point in points)
          raw.getUint32(
            (point.dy.floor() * image.width + point.dx.floor()) * 4,
          ),
      ];
    } finally {
      image.dispose();
    }
  }))!;
}

Future<void> _ensureVisibleInHeader(
  WidgetTester tester,
  Finder target, {
  double alignment = 0.5,
}) async {
  expect(target, findsOneWidget);
  final element = tester.element(target);
  final vertical = Scrollable.maybeOf(element, axis: Axis.vertical);
  if (vertical != null) {
    await vertical.position.ensureVisible(
      element.findRenderObject()!,
      alignment: alignment,
    );
    await tester.pumpAndSettle();
  }
  final horizontal = Scrollable.maybeOf(element, axis: Axis.horizontal);
  if (horizontal != null) {
    await horizontal.position.ensureVisible(
      element.findRenderObject()!,
      alignment: alignment,
    );
    await tester.pumpAndSettle();
  }
}

class _SyntheticCalendarTodoProvider extends TodoProvider {
  _SyntheticCalendarTodoProvider(this._syntheticTodos);

  final List<TodoItem> _syntheticTodos;

  @override
  List<TodoItem> get todos => _syntheticTodos;
}

class _MemoryTodoProvider extends TodoProvider {
  _MemoryTodoProvider([List<TodoItem> todos = const <TodoItem>[]])
    : _fixtureTodos = List.unmodifiable(todos);

  final List<TodoItem> _fixtureTodos;

  @override
  List<TodoItem> get todos => _fixtureTodos;

  @override
  List<TodoItem> get visibleListTodos => _fixtureTodos
      .where((todo) => !todo.isArchivedAfterRollover)
      .toList(growable: false);

  @override
  List<TodoItem> get overdueTodos =>
      _fixtureTodos.where((todo) => todo.isOverdue).toList(growable: false);
}

class _FixturePreferencesProvider extends PreferencesProvider {
  _FixturePreferencesProvider({this.fixtureShowCompletedTodos = true});

  final bool fixtureShowCompletedTodos;

  @override
  bool get showCompletedTodos => fixtureShowCompletedTodos;
}

const _edgeSamplePoints = [
  Offset(2, 844 * 0.4),
  Offset(320 - 3, 844 * 0.65),
  Offset(2, 844 - 24),
];

class _RoutePriorityScenario {
  const _RoutePriorityScenario({
    required this.routeType,
    required this.locale,
    required this.scaleName,
    required this.scale,
    required this.isNonlinear,
    required this.label,
    required this.probeName,
  });

  final String routeType;
  final AppLocale locale;
  final String scaleName;
  final double scale;
  final bool isNonlinear;
  final String label;
  final String probeName;
}

const _scenarios = [
  _RoutePriorityScenario(
    routeType: 'calendar',
    locale: AppLocale.zh,
    scaleName: 'linear20',
    scale: 2.0,
    isNonlinear: false,
    label: 'calendar zh narrow 320 linear 2.0',
    probeName: 'live-brand-calendar-zh-narrow320-linear20',
  ),
  _RoutePriorityScenario(
    routeType: 'calendar',
    locale: AppLocale.zh,
    scaleName: 'nonlinear',
    scale: -1.0,
    isNonlinear: true,
    label: 'calendar zh narrow 320 nonlinear',
    probeName: 'live-brand-calendar-zh-narrow320-nonlinear',
  ),
  _RoutePriorityScenario(
    routeType: 'calendar',
    locale: AppLocale.en,
    scaleName: 'linear20',
    scale: 2.0,
    isNonlinear: false,
    label: 'calendar en narrow 320 linear 2.0',
    probeName: 'live-brand-calendar-en-narrow320-linear20',
  ),
  _RoutePriorityScenario(
    routeType: 'calendar',
    locale: AppLocale.en,
    scaleName: 'nonlinear',
    scale: -1.0,
    isNonlinear: true,
    label: 'calendar en narrow 320 nonlinear',
    probeName: 'live-brand-calendar-en-narrow320-nonlinear',
  ),
  _RoutePriorityScenario(
    routeType: 'todo',
    locale: AppLocale.zh,
    scaleName: 'linear20',
    scale: 2.0,
    isNonlinear: false,
    label: 'todo zh narrow 320 linear 2.0',
    probeName: 'live-brand-todo-zh-narrow320-linear20',
  ),
  _RoutePriorityScenario(
    routeType: 'todo',
    locale: AppLocale.zh,
    scaleName: 'nonlinear',
    scale: -1.0,
    isNonlinear: true,
    label: 'todo zh narrow 320 nonlinear',
    probeName: 'live-brand-todo-zh-narrow320-nonlinear',
  ),
  _RoutePriorityScenario(
    routeType: 'todo',
    locale: AppLocale.en,
    scaleName: 'linear20',
    scale: 2.0,
    isNonlinear: false,
    label: 'todo en narrow 320 linear 2.0',
    probeName: 'live-brand-todo-en-narrow320-linear20',
  ),
  _RoutePriorityScenario(
    routeType: 'todo',
    locale: AppLocale.en,
    scaleName: 'nonlinear',
    scale: -1.0,
    isNonlinear: true,
    label: 'todo en narrow 320 nonlinear',
    probeName: 'live-brand-todo-en-narrow320-nonlinear',
  ),
];

void main() {
  final initialLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialLocale));

  for (final scenario in _scenarios) {
    testWidgets(
      'priority live brand switch defaultBrand <-> liquidGlass ${scenario.label}',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'theme_shop_state': jsonEncode({
            'activeBrand': 'defaultBrand',
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          }),
          'active_brand': 'defaultBrand',
          'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          'pref_show_completed_todos': true,
        });

        I18n.setLocale(scenario.locale);
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final originalShadows = debugDisableShadows;
        debugDisableShadows = false;
        try {
          final theme = ThemeProvider();
        final auth = AuthProvider(
          client: ApiClient(
            baseUrl: 'https://duoyi.test',
            httpClient: MockClient((_) async {
              fail('The route visual fixture must not issue HTTP requests');
            }),
          ),
        );

        await tester.runAsync(() async {
          await theme.loadFromStorage();
          await loadWeeklyReviewScreenshotFonts();
        });

        expect(theme.brand.id, 'defaultBrand');
        expect(theme.isBrandUnlocked('liquidGlass'), isTrue);

        final TextScaler scenarioScaler =
            scenario.isNonlinear
                ? const RouteProbeNonlinearScaler()
                : TextScaler.linear(scenario.scale);

        final boundary = GlobalKey();
        final probe = _MainRoutesPriorityProbe(tester, boundary, scenario.probeName);

        if (scenario.routeType == 'calendar') {
          final initialDate = DateTime(2026, 6, 29);
          final calendarTodo = TodoItem(
            id: 'calendar-synthetic-task',
            title: 'Calendar synthetic task',
            date: initialDate,
            dueDate: initialDate,
            createdAt: DateTime(2026, 6, 29, 9),
          );

          final todoProvider = _SyntheticCalendarTodoProvider([calendarTodo]);
          final habitProvider = HabitProvider();
          final pomodoroProvider = PomodoroProvider();
          final calendarProvider = CalendarProvider();
          final anniversaryProvider = AnniversaryProvider();
          final countdownProvider = CountdownProvider();
          final courseProvider = CourseProvider();
          final diaryProvider = DiaryProvider();
          final goalProvider = GoalProvider();
          final shareProvider = ShareProvider();
          final timeAuditProvider = TimeAuditProvider();
          final preferencesProvider = _FixturePreferencesProvider();

          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            auth.dispose();
            theme.dispose();
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
            preferencesProvider.dispose();
          });

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
                ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
                ChangeNotifierProvider<HabitProvider>.value(value: habitProvider),
                ChangeNotifierProvider<PomodoroProvider>.value(value: pomodoroProvider),
                ChangeNotifierProvider<CalendarProvider>.value(value: calendarProvider),
                ChangeNotifierProvider<AnniversaryProvider>.value(value: anniversaryProvider),
                ChangeNotifierProvider<CountdownProvider>.value(value: countdownProvider),
                ChangeNotifierProvider<CourseProvider>.value(value: courseProvider),
                ChangeNotifierProvider<DiaryProvider>.value(value: diaryProvider),
                ChangeNotifierProvider<GoalProvider>.value(value: goalProvider),
                ChangeNotifierProvider<ShareProvider>.value(value: shareProvider),
                ChangeNotifierProvider<TimeAuditProvider>.value(value: timeAuditProvider),
                ChangeNotifierProvider<PreferencesProvider>.value(value: preferencesProvider),
              ],
              child: AnimatedBuilder(
                animation: Listenable.merge([theme, I18n.localeListenable]),
                builder: (context, _) => MaterialApp(
                  locale: Locale(scenario.locale == AppLocale.en ? 'en' : 'zh'),
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: theme.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: scenarioScaler,
                    ),
                    child: RepaintBoundary(key: boundary, child: child!),
                  ),
                  home: BrandRouteSurface(
                    child: CalendarScreen(initialDate: initialDate),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final calendarFinder = find.byType(CalendarScreen);
          expect(calendarFinder, findsOneWidget);
          final routeStateBefore = tester.state(calendarFinder);
          final modalRouteBefore = ModalRoute.of(tester.element(calendarFinder));
          expect(modalRouteBefore, isNotNull);

          final yearTab = find.descendant(
            of: find.byType(TabBar),
            matching: find.text(CalendarUiCopy.tabYear),
          );
          expect(yearTab, findsOneWidget);
          await Scrollable.ensureVisible(tester.element(yearTab), alignment: 0.5);
          await tester.pumpAndSettle();
          await tester.tap(yearTab);
          await tester.pumpAndSettle();

          final tabControllerBefore = tester.widget<TabBar>(find.byType(TabBar)).controller!;
          expect(tabControllerBefore.index, 4);

          final yearViewFinder = find.byKey(const ValueKey('calendar_year_overview'));
          expect(yearViewFinder, findsOneWidget);
          final yearScrollable = find.descendant(
            of: yearViewFinder,
            matching: find.byType(Scrollable),
          );
          expect(yearScrollable, findsOneWidget);
          final yearScroll = tester.state<ScrollableState>(yearScrollable);

          await tester.drag(yearScrollable, const Offset(0, -180));
          await tester.pumpAndSettle();
          final yearOffsetBefore = yearScroll.position.pixels;
          expect(yearOffsetBefore, greaterThan(0));

          expect((tester.widget(yearViewFinder) as dynamic).selectedDay, equals(initialDate));
          final yearHeaderLabel = CalendarUiCopy.yearHeader(initialDate.year);
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('calendar_navigation_date_button')),
              matching: find.text(yearHeaderLabel),
            ),
            findsOneWidget,
          );

          // State 1: initial defaultBrand
          expect(theme.brand.id, 'defaultBrand');
          final actualDefaultInitialPixels = await _samplePoints(
            tester,
            boundary,
            _edgeSamplePoints,
          );
          for (var i = 0; i < _edgeSamplePoints.length; i++) {
            probe.rows.add({
              'role': 'initial defaultBrand margin $i sample',
              'rgba': actualDefaultInitialPixels[i],
            });
          }
          await probe.capture('01-initial-defaultBrand');

          // State 2: Switch to liquidGlass
          await tester.runAsync(() async {
            final switched = await theme.setBrand('liquidGlass');
            expect(switched, isTrue);
          });
          await tester.pumpAndSettle();

          expect(theme.brand.id, 'liquidGlass');
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getString('active_brand'), 'liquidGlass');

          final activeCs = Theme.of(tester.element(calendarFinder)).colorScheme;
          expect(activeCs.primary, equals(AppBrands.liquidGlass.theme.colorScheme.primary));

          expect(tester.state(calendarFinder), same(routeStateBefore));
          expect(ModalRoute.of(tester.element(calendarFinder)), same(modalRouteBefore));

          final tabControllerStage2 = tester.widget<TabBar>(find.byType(TabBar)).controller!;
          expect(tabControllerStage2, same(tabControllerBefore));
          expect(tabControllerStage2.index, 4);

          final yearScrollStage2 = tester.state<ScrollableState>(yearScrollable);
          expect(yearScrollStage2, same(yearScroll));
          expect(yearScrollStage2.position.pixels, closeTo(yearOffsetBefore, 1.0));
          expect((tester.widget(yearViewFinder) as dynamic).selectedDay, equals(initialDate));

          final actualGlassPixels = await _samplePoints(
            tester,
            boundary,
            _edgeSamplePoints,
          );
          for (var i = 0; i < _edgeSamplePoints.length; i++) {
            probe.rows.add({
              'role': 'applied liquidGlass margin $i sample',
              'rgba': actualGlassPixels[i],
            });
          }
          await probe.capture('02-applied-liquidGlass');

          // State 3: Revert to defaultBrand
          await tester.runAsync(() async {
            final reverted = await theme.setBrand('defaultBrand');
            expect(reverted, isTrue);
          });
          await tester.pumpAndSettle();

          expect(theme.brand.id, 'defaultBrand');
          expect(prefs.getString('active_brand'), 'defaultBrand');

          final revertedCs = Theme.of(tester.element(calendarFinder)).colorScheme;
          expect(revertedCs.primary, equals(AppBrands.defaultBrand.theme.colorScheme.primary));

          expect(tester.state(calendarFinder), same(routeStateBefore));
          expect(ModalRoute.of(tester.element(calendarFinder)), same(modalRouteBefore));

          final tabControllerStage3 = tester.widget<TabBar>(find.byType(TabBar)).controller!;
          expect(tabControllerStage3, same(tabControllerBefore));
          expect(tabControllerStage3.index, 4);

          final yearScrollStage3 = tester.state<ScrollableState>(yearScrollable);
          expect(yearScrollStage3, same(yearScroll));
          expect(yearScrollStage3.position.pixels, closeTo(yearOffsetBefore, 1.0));
          expect((tester.widget(yearViewFinder) as dynamic).selectedDay, equals(initialDate));

          final actualDefaultRevertedPixels = await _samplePoints(
            tester,
            boundary,
            _edgeSamplePoints,
          );
          await probe.capture('03-reverted-defaultBrand');

          for (var i = 0; i < _edgeSamplePoints.length; i++) {
            expect(
              actualDefaultRevertedPixels[i],
              equals(actualDefaultInitialPixels[i]),
              reason: 'Reverting to defaultBrand did not restore solid background at margin point $i',
            );
            expect(
              actualGlassPixels[i],
              isNot(equals(actualDefaultInitialPixels[i])),
              reason: 'liquidGlass margin pixel at point $i should not equal defaultBrand solid background',
            );
            expect(
              actualGlassPixels[i] & 0xFF,
              equals(255),
              reason: 'liquidGlass route margin point $i must remain opaque',
            );
            expect(
              actualGlassPixels[i] >> 8,
              isNot(equals(0)),
              reason: 'liquidGlass route margin point $i must not turn black',
            );
          }

          // Independent BrandBackground reference comparison
          await tester.runAsync(() async {
            await theme.setBrand('liquidGlass');
          });
          final referenceKey = GlobalKey();
          await tester.pumpWidget(
            ChangeNotifierProvider<ThemeProvider>.value(
              value: theme,
              child: MaterialApp(
                theme: theme.brand.theme,
                home: RepaintBoundary(
                  key: referenceKey,
                  child: Material(
                    color: theme.brand.theme.scaffoldBackgroundColor,
                    child: const BrandBackground(child: SizedBox.expand()),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final referenceGlassPixels = await _samplePoints(
            tester,
            referenceKey,
            _edgeSamplePoints,
          );

          for (var i = 0; i < _edgeSamplePoints.length; i++) {
            final equal = actualGlassPixels[i] == referenceGlassPixels[i];
            probe.rows.add({
              'role': 'calendar liquidGlass route margin $i vs reference',
              'actualRGBA': actualGlassPixels[i],
              'referenceRGBA': referenceGlassPixels[i],
              'matchesRealBrandBackground': equal,
            });
            expect(
              actualGlassPixels[i],
              equals(referenceGlassPixels[i]),
              reason: 'Glass backdrop at route margin point $i does not match independent BrandBackground reference',
            );
          }

          await probe.finish();
        } else {
          // Todo scenario
          final baseTime = DateTime(2026, 10, 23, 10, 0);
          final fixtureTodos = <TodoItem>[
            TodoItem(
              id: 'synthetic-pending-1',
              title: 'Synthetic pending task 1',
              dueDate: baseTime.add(const Duration(hours: 2)),
              priority: TodoPriority.high,
              createdAt: baseTime.subtract(const Duration(days: 1)),
              updatedAt: baseTime.subtract(const Duration(days: 1)),
            ),
            TodoItem(
              id: 'synthetic-pending-2',
              title: 'Synthetic pending task 2',
              dueDate: baseTime.add(const Duration(hours: 4)),
              priority: TodoPriority.medium,
              createdAt: baseTime.subtract(const Duration(days: 1)),
              updatedAt: baseTime.subtract(const Duration(days: 1)),
            ),
            for (var i = 0; i < 35; i++)
              TodoItem(
                id: 'synthetic-completed-$i',
                title: 'Synthetic completed task $i',
                isCompleted: true,
                completedAt: baseTime.subtract(Duration(minutes: i * 5)),
                createdAt: baseTime.subtract(const Duration(days: 2)),
                updatedAt: baseTime.subtract(const Duration(days: 2)),
              ),
          ];

          final todoProvider = _MemoryTodoProvider(fixtureTodos);
          final habitProvider = HabitProvider();
          final goalProvider = GoalProvider();
          final shareProvider = ShareProvider();
          final aiService = AiService();
          final preferencesProvider = _FixturePreferencesProvider(fixtureShowCompletedTodos: true);

          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            auth.dispose();
            theme.dispose();
            todoProvider.dispose();
            habitProvider.dispose();
            goalProvider.dispose();
            shareProvider.dispose();
            aiService.dispose();
            preferencesProvider.dispose();
          });

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
                ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
                ChangeNotifierProvider<HabitProvider>.value(value: habitProvider),
                ChangeNotifierProvider<GoalProvider>.value(value: goalProvider),
                ChangeNotifierProvider<ShareProvider>.value(value: shareProvider),
                ChangeNotifierProvider<AiService>.value(value: aiService),
                ChangeNotifierProvider<PreferencesProvider>.value(value: preferencesProvider),
              ],
              child: AnimatedBuilder(
                animation: Listenable.merge([theme, I18n.localeListenable]),
                builder: (context, _) => MaterialApp(
                  locale: Locale(scenario.locale == AppLocale.en ? 'en' : 'zh'),
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: theme.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: scenarioScaler,
                    ),
                    child: RepaintBoundary(key: boundary, child: child!),
                  ),
                  home: const BrandRouteSurface(
                    child: TodoScreen(),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final todoFinder = find.byType(TodoScreen);
          expect(todoFinder, findsOneWidget);
          final routeStateBefore = tester.state(todoFinder);
          final modalRouteBefore = ModalRoute.of(tester.element(todoFinder));
          expect(modalRouteBefore, isNotNull);

          final listSegment = find.descendant(
            of: find.byKey(const ValueKey('todo_view_switcher')),
            matching: find.text(TodoBoardUiCopy.viewList),
          );
          expect(listSegment, findsOneWidget);
          await tester.tap(listSegment);
          await tester.pumpAndSettle();

          final filterCompletedChipText = find.descendant(
            of: find.byType(FilterChip),
            matching: find.text(TodoBoardUiCopy.filterCompleted),
          );
          expect(filterCompletedChipText, findsOneWidget);
          final filterCompletedChip = find.ancestor(
            of: filterCompletedChipText,
            matching: find.byType(FilterChip),
          );
          expect(filterCompletedChip, findsOneWidget);
          await _ensureVisibleInHeader(tester, filterCompletedChip, alignment: 0.5);
          await tester.tap(filterCompletedChip);
          await tester.pumpAndSettle();

          expect(tester.widget<FilterChip>(filterCompletedChip).selected, isTrue);

          final listFinder = find.byKey(const ValueKey('todo_list_scroll'));
          expect(listFinder, findsOneWidget);
          final reorderableList = tester.widget<ReorderableListView>(listFinder);
          final scrollController = reorderableList.scrollController!;

          final todoScrollable = find.descendant(
            of: listFinder,
            matching: find.byType(Scrollable),
          );
          expect(todoScrollable, findsOneWidget);
          final todoScrollState = tester.state<ScrollableState>(todoScrollable);

          await tester.drag(listFinder, const Offset(0, -320));
          await tester.pumpAndSettle();
          final todoOffsetBefore = scrollController.offset;
          expect(todoOffsetBefore, greaterThan(0));
          expect(todoScrollState.position.pixels, greaterThan(0));

          // State 1: initial defaultBrand
          expect(theme.brand.id, 'defaultBrand');
          final actualDefaultInitialPixels = await _samplePoints(
            tester,
            boundary,
            _edgeSamplePoints,
          );
          for (var i = 0; i < _edgeSamplePoints.length; i++) {
            probe.rows.add({
              'role': 'initial defaultBrand margin $i sample',
              'rgba': actualDefaultInitialPixels[i],
            });
          }
          await probe.capture('01-initial-defaultBrand');

          // State 2: Switch to liquidGlass
          await tester.runAsync(() async {
            final switched = await theme.setBrand('liquidGlass');
            expect(switched, isTrue);
          });
          await tester.pumpAndSettle();

          expect(theme.brand.id, 'liquidGlass');
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getString('active_brand'), 'liquidGlass');

          final activeCs = Theme.of(tester.element(todoFinder)).colorScheme;
          expect(activeCs.primary, equals(AppBrands.liquidGlass.theme.colorScheme.primary));

          expect(tester.state(todoFinder), same(routeStateBefore));
          expect(ModalRoute.of(tester.element(todoFinder)), same(modalRouteBefore));

          final reorderableListStage2 = tester.widget<ReorderableListView>(listFinder);
          expect(reorderableListStage2.scrollController, same(scrollController));
          expect(scrollController.offset, closeTo(todoOffsetBefore, 1.0));

          final todoScrollStateStage2 = tester.state<ScrollableState>(todoScrollable);
          expect(todoScrollStateStage2, same(todoScrollState));
          expect(todoScrollStateStage2.position.pixels, closeTo(todoOffsetBefore, 1.0));

          expect(tester.widget<FilterChip>(filterCompletedChip).selected, isTrue);

          final actualGlassPixels = await _samplePoints(
            tester,
            boundary,
            _edgeSamplePoints,
          );
          for (var i = 0; i < _edgeSamplePoints.length; i++) {
            probe.rows.add({
              'role': 'applied liquidGlass margin $i sample',
              'rgba': actualGlassPixels[i],
            });
          }
          await probe.capture('02-applied-liquidGlass');

          // State 3: Revert to defaultBrand
          await tester.runAsync(() async {
            final reverted = await theme.setBrand('defaultBrand');
            expect(reverted, isTrue);
          });
          await tester.pumpAndSettle();

          expect(theme.brand.id, 'defaultBrand');
          expect(prefs.getString('active_brand'), 'defaultBrand');

          final revertedCs = Theme.of(tester.element(todoFinder)).colorScheme;
          expect(revertedCs.primary, equals(AppBrands.defaultBrand.theme.colorScheme.primary));

          expect(tester.state(todoFinder), same(routeStateBefore));
          expect(ModalRoute.of(tester.element(todoFinder)), same(modalRouteBefore));

          final reorderableListStage3 = tester.widget<ReorderableListView>(listFinder);
          expect(reorderableListStage3.scrollController, same(scrollController));
          expect(scrollController.offset, closeTo(todoOffsetBefore, 1.0));

          final todoScrollStateStage3 = tester.state<ScrollableState>(todoScrollable);
          expect(todoScrollStateStage3, same(todoScrollState));
          expect(todoScrollStateStage3.position.pixels, closeTo(todoOffsetBefore, 1.0));

          expect(tester.widget<FilterChip>(filterCompletedChip).selected, isTrue);

          final actualDefaultRevertedPixels = await _samplePoints(
            tester,
            boundary,
            _edgeSamplePoints,
          );
          await probe.capture('03-reverted-defaultBrand');

          for (var i = 0; i < _edgeSamplePoints.length; i++) {
            expect(
              actualDefaultRevertedPixels[i],
              equals(actualDefaultInitialPixels[i]),
              reason: 'Reverting to defaultBrand did not restore solid background at margin point $i',
            );
            expect(
              actualGlassPixels[i],
              isNot(equals(actualDefaultInitialPixels[i])),
              reason: 'liquidGlass margin pixel at point $i should not equal defaultBrand solid background',
            );
            expect(
              actualGlassPixels[i] & 0xFF,
              equals(255),
              reason: 'liquidGlass route margin point $i must remain opaque',
            );
            expect(
              actualGlassPixels[i] >> 8,
              isNot(equals(0)),
              reason: 'liquidGlass route margin point $i must not turn black',
            );
          }

          // Independent BrandBackground reference comparison
          await tester.runAsync(() async {
            await theme.setBrand('liquidGlass');
          });
          final referenceKey = GlobalKey();
          await tester.pumpWidget(
            ChangeNotifierProvider<ThemeProvider>.value(
              value: theme,
              child: MaterialApp(
                theme: theme.brand.theme,
                home: RepaintBoundary(
                  key: referenceKey,
                  child: Material(
                    color: theme.brand.theme.scaffoldBackgroundColor,
                    child: const BrandBackground(child: SizedBox.expand()),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final referenceGlassPixels = await _samplePoints(
            tester,
            referenceKey,
            _edgeSamplePoints,
          );

          for (var i = 0; i < _edgeSamplePoints.length; i++) {
            final equal = actualGlassPixels[i] == referenceGlassPixels[i];
            probe.rows.add({
              'role': 'todo liquidGlass route margin $i vs reference',
              'actualRGBA': actualGlassPixels[i],
              'referenceRGBA': referenceGlassPixels[i],
              'matchesRealBrandBackground': equal,
            });
            expect(
              actualGlassPixels[i],
              equals(referenceGlassPixels[i]),
              reason: 'Glass backdrop at route margin point $i does not match independent BrandBackground reference',
            );
          }

          await probe.finish();
        }
      } finally {
        debugDisableShadows = originalShadows;
      }
    },
  );
  }
}
