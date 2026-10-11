import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/calendar_screen.dart';
import 'package:duoyi/screens/habit_screen.dart';
import 'package:duoyi/screens/integrations_screen.dart';
import 'package:duoyi/screens/pomodoro_screen.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/widget_calendar_link.dart';
import 'package:duoyi/services/focus_dnd_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryTodoProvider extends TodoProvider {
  _MemoryTodoProvider([List<TodoItem> todos = const <TodoItem>[]])
    : _fixtureTodos = todos;

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

class _MemoryHabitProvider extends HabitProvider {
  _MemoryHabitProvider([List<Habit> habits = const <Habit>[]])
    : _fixtureHabits = habits;

  final List<Habit> _fixtureHabits;

  @override
  List<Habit> get habits => _fixtureHabits;
}

class _MemoryPomodoroProvider extends PomodoroProvider {
  _MemoryPomodoroProvider({
    PomodoroState? state,
    List<PomodoroSession> sessions = const <PomodoroSession>[],
  }) : _fixtureState =
           state ??
           const PomodoroState(
             remainingSeconds: 1500,
             totalSeconds: 1500,
             isRunning: false,
             type: PomodoroType.focus,
             completedSessions: 0,
           ),
       _fixtureSessions = sessions;

  final PomodoroState _fixtureState;
  final List<PomodoroSession> _fixtureSessions;

  @override
  PomodoroState get state => _fixtureState;

  @override
  List<PomodoroSession> get sessions => _fixtureSessions;

  @override
  Future<FocusDndStatus> refreshFocusDndStatus() async =>
      const FocusDndStatus.unavailable();
}

class _MemoryCalendarProvider extends CalendarProvider {}

class _MemoryAnniversaryProvider extends AnniversaryProvider {}

class _MemoryCountdownProvider extends CountdownProvider {}

class _MemoryCourseProvider extends CourseProvider {}

class _MemoryDiaryProvider extends DiaryProvider {}

class _MemoryGoalProvider extends GoalProvider {}

class _MemoryShareProvider extends ShareProvider {}

class _ReadOnlyShareProvider extends ShareProvider {
  @override
  bool canEdit(String? workspaceId) => false;
}

class _MemoryTimeAuditProvider extends TimeAuditProvider {}

class _MemoryThemeProvider extends ThemeProvider {}

class _MemoryCalendarSyncProvider extends CalendarSyncProvider {}

class _MemoryLocationReminderProvider extends LocationReminderProvider {}

class _MemoryNotificationService extends NotificationService {}

class _MemoryFocusRoomProvider extends FocusRoomProvider {
  @override
  String? get activeRoomId => null;

  @override
  void watchRealtimeRankings({int intervalSeconds = 15}) {}

  @override
  Future<void> loadFocusFriendsAndRanking({bool force = false}) async {}

  @override
  Future<void> loadGlobalRanking({bool force = false}) async {}

  @override
  Future<void> syncRemoteRankings(
    Iterable<PomodoroSession> sessions, {
    String displayName = '我',
    bool active = true,
    bool force = false,
  }) async {}
}

class _MemoryCustomFocusSoundProvider extends CustomFocusSoundProvider {}

class _MemoryAuthProvider extends AuthProvider {}

class _MemoryLocaleProvider extends LocaleProvider {
  AppLocale _selectedLocale = AppLocale.zh;

  @override
  AppLocale get locale => _selectedLocale;

  @override
  Future<void> setLocale(AppLocale locale) async {
    _selectedLocale = locale;
    I18n.setLocale(locale);
    notifyListeners();
  }
}

Widget _calendarRouteApp(
  DateTime initialDate, {
  bool useBrandRouteSurface = true,
}) {
  final Widget route = CalendarScreen(initialDate: initialDate);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<TodoProvider>(
        create: (_) => _MemoryTodoProvider(),
      ),
      ChangeNotifierProvider<HabitProvider>(
        create: (_) => _MemoryHabitProvider(),
      ),
      ChangeNotifierProvider<PomodoroProvider>(
        create: (_) => _MemoryPomodoroProvider(),
      ),
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => _MemoryThemeProvider(),
      ),
      ChangeNotifierProvider<CalendarProvider>(
        create: (_) => _MemoryCalendarProvider(),
      ),
      ChangeNotifierProvider<AnniversaryProvider>(
        create: (_) => _MemoryAnniversaryProvider(),
      ),
      ChangeNotifierProvider<CountdownProvider>(
        create: (_) => _MemoryCountdownProvider(),
      ),
      ChangeNotifierProvider<CourseProvider>(
        create: (_) => _MemoryCourseProvider(),
      ),
      ChangeNotifierProvider<DiaryProvider>(
        create: (_) => _MemoryDiaryProvider(),
      ),
      ChangeNotifierProvider<GoalProvider>(
        create: (_) => _MemoryGoalProvider(),
      ),
      ChangeNotifierProvider<ShareProvider>(
        create: (_) => _MemoryShareProvider(),
      ),
      ChangeNotifierProvider<TimeAuditProvider>(
        create: (_) => _MemoryTimeAuditProvider(),
      ),
    ],
    child: MaterialApp(
      home: useBrandRouteSurface ? BrandRouteSurface(child: route) : route,
    ),
  );
}

Widget _todoRouteApp(_MemoryTodoProvider todoProvider) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
      ChangeNotifierProvider<HabitProvider>(
        create: (_) => _MemoryHabitProvider(),
      ),
      ChangeNotifierProvider<GoalProvider>(
        create: (_) => _MemoryGoalProvider(),
      ),
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => _MemoryThemeProvider(),
      ),
      ChangeNotifierProvider<AiService>(create: (_) => AiService()),
      ChangeNotifierProvider<ShareProvider>(
        create: (_) => _ReadOnlyShareProvider(),
      ),
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => _MemoryAuthProvider(),
      ),
    ],
    child: const MaterialApp(home: BrandRouteSurface(child: TodoScreen())),
  );
}

Widget _habitRouteApp(_MemoryHabitProvider habitProvider) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<HabitProvider>.value(value: habitProvider),
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => _MemoryThemeProvider(),
      ),
    ],
    child: const MaterialApp(home: BrandRouteSurface(child: HabitScreen())),
  );
}

Widget _pomodoroRouteApp(_MemoryPomodoroProvider pomodoroProvider) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PomodoroProvider>.value(value: pomodoroProvider),
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => _MemoryThemeProvider(),
      ),
      ChangeNotifierProvider<FocusRoomProvider>(
        create: (_) => _MemoryFocusRoomProvider(),
      ),
      ChangeNotifierProvider<CustomFocusSoundProvider>(
        create: (_) => _MemoryCustomFocusSoundProvider(),
      ),
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => _MemoryAuthProvider(),
      ),
    ],
    child: const MaterialApp(home: BrandRouteSurface(child: PomodoroScreen())),
  );
}

Finder _calendarDateLabel(String text) => find.descendant(
  of: find.byKey(const ValueKey('calendar_navigation_date_button')),
  matching: find.text(text),
);

TabController _calendarTabController(WidgetTester tester) {
  final tabBar = find.descendant(
    of: find.byType(CalendarScreen),
    matching: find.byType(TabBar),
  );
  return tester.widget<TabBar>(tabBar.first).controller!;
}

TabController _integrationsTabController(WidgetTester tester) {
  final tabBar = find.byType(TabBar).first;
  return DefaultTabController.of(tester.element(tabBar));
}

TabBar _routeTabBar(WidgetTester tester, Finder routeFinder) {
  final tabBar = find.descendant(
    of: routeFinder,
    matching: find.byType(TabBar),
  );
  return tester.widget<TabBar>(tabBar.first);
}

Finder _todoVerticalListWithController() => find.descendant(
  of: find.byType(TodoScreen),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is ListView &&
        widget.scrollDirection == Axis.vertical &&
        widget.controller != null,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('the five public routes declare the state-preserving marker', () {
    const routes = <Widget>[
      TodoScreen(),
      HabitScreen(),
      CalendarScreen(),
      PomodoroScreen(),
      IntegrationsScreen(),
    ];

    for (final route in routes) {
      expect(route, isA<LocaleStatePreservingRoute>());
    }
  });

  testWidgets(
    'Todo keeps list mode, completion filter and scroll offset through raw locale events',
    (tester) async {
      final fixtureTodos = List.generate(
        40,
        (index) => TodoItem(
          id: 'locale-fixture-$index',
          title: 'Locale fixture task $index',
          isCompleted: index.isEven,
          listGroupName: 'Locale fixture group',
          createdAt: DateTime(2026, 10, 9),
          updatedAt: DateTime(2026, 10, 9),
        ),
      );
      final todoProvider = _MemoryTodoProvider(fixtureTodos);
      await tester.pumpWidget(_todoRouteApp(todoProvider));
      await tester.pumpAndSettle();
      expect(find.text('待办清单'), findsOneWidget);

      await tester.tap(find.text('列表'));
      await tester.pumpAndSettle();
      final completedChip = find.widgetWithText(FilterChip, '已完成');
      await tester.tap(completedChip);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(completedChip).selected, isTrue);
      expect(find.text('自定义视图 · 20/40'), findsOneWidget);
      expect(find.text('Locale fixture task 0'), findsOneWidget);
      expect(find.text('Locale fixture task 1'), findsNothing);

      final listFinder = _todoVerticalListWithController();
      expect(listFinder, findsOneWidget);
      final scrollController = tester.widget<ListView>(listFinder).controller!;
      await tester.drag(listFinder, const Offset(0, -480));
      await tester.pumpAndSettle();
      expect(scrollController.offset, greaterThan(0));

      final routeStateBefore = tester.state(find.byType(TodoScreen));
      final offsetBefore = scrollController.offset;
      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();

        expect(
          find.text(locale == AppLocale.en ? 'To-Do List' : '待办清单'),
          findsOneWidget,
        );
        expect(tester.state(find.byType(TodoScreen)), same(routeStateBefore));
        expect(
          Provider.of<TodoProvider>(
            tester.element(find.byType(TodoScreen)),
            listen: false,
          ),
          same(todoProvider),
        );
        expect(
          tester.widget<ListView>(listFinder).controller,
          same(scrollController),
        );
        expect(tester.widget<FilterChip>(completedChip).selected, isTrue);
        expect(find.text('自定义视图 · 20/40'), findsOneWidget);
        final expectedOffset = offsetBefore
            .clamp(0, scrollController.position.maxScrollExtent)
            .toDouble();
        expect(scrollController.offset, closeTo(expectedOffset, 1.0));
      }

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Habit keeps its built heatmap tab and locale copy after raw events',
    (tester) async {
      final habit = Habit(
        id: 'locale-habit',
        name: 'Locale habit',
        activeWeekdays: [DateTime.now().weekday - 1],
        createdAt: DateTime.now().subtract(const Duration(days: 7)),
      );
      final habitProvider = _MemoryHabitProvider([habit]);
      await tester.pumpWidget(_habitRouteApp(habitProvider));
      await tester.pumpAndSettle();

      final routeFinder = find.byType(HabitScreen);
      final tabBarFinder = find.descendant(
        of: routeFinder,
        matching: find.byType(TabBar),
      );
      final heatmapTab = find
          .descendant(of: tabBarFinder, matching: find.byType(Tab))
          .last;
      await tester.tap(heatmapTab);
      await tester.pumpAndSettle();

      final routeStateBefore = tester.state(routeFinder);
      final tabControllerBefore = _routeTabBar(tester, routeFinder).controller!;
      expect(tabControllerBefore.index, 1);
      expect(find.text('累计打卡热度'), findsOneWidget);

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();

        expect(
          find.text(locale == AppLocale.en ? 'Habits' : '习惯'),
          findsOneWidget,
        );
        if (locale == AppLocale.en) {
          expect(find.text('Cumulative check-in heat'), findsOneWidget);
        } else {
          expect(find.text('累计打卡热度'), findsOneWidget);
        }
        expect(tester.state(routeFinder), same(routeStateBefore));
        expect(
          Provider.of<HabitProvider>(
            tester.element(routeFinder),
            listen: false,
          ),
          same(habitProvider),
        );
        final tabController = _routeTabBar(tester, routeFinder).controller!;
        expect(tabController, same(tabControllerBefore));
        expect(tabController.index, 1);
        expect(habitProvider.habits.single, same(habit));
      }

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Pomodoro keeps its History tab and running provider state through raw locale events',
    (tester) async {
      final start = DateTime.now().subtract(const Duration(minutes: 25));
      final session = PomodoroSession(
        id: 'locale-session',
        startTime: start,
        endTime: start.add(const Duration(minutes: 25)),
        durationSeconds: 1500,
        type: PomodoroType.focus,
        taskName: 'Locale fixture session',
      );
      final sessions = <PomodoroSession>[session];
      const runningState = PomodoroState(
        remainingSeconds: 720,
        totalSeconds: 1500,
        isRunning: true,
        type: PomodoroType.focus,
        completedSessions: 2,
        taskName: 'Current locale fixture',
      );
      final pomodoroProvider = _MemoryPomodoroProvider(
        state: runningState,
        sessions: sessions,
      );
      await tester.pumpWidget(_pomodoroRouteApp(pomodoroProvider));
      await tester.pumpAndSettle();

      final routeFinder = find.byType(PomodoroScreen);
      final tabBarFinder = find.descendant(
        of: routeFinder,
        matching: find.byType(TabBar),
      );
      final historyTab = find
          .descendant(of: tabBarFinder, matching: find.byType(Tab))
          .at(1);
      await tester.tap(historyTab);
      await tester.pumpAndSettle();

      final tabControllerBefore = _routeTabBar(tester, routeFinder).controller!;
      expect(tabControllerBefore.index, 1);
      expect(find.text('Locale fixture session'), findsOneWidget);
      expect(pomodoroProvider.state, same(runningState));
      expect(pomodoroProvider.state.isRunning, isTrue);

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();

        expect(
          find.text(locale == AppLocale.en ? 'Pomodoro Focus' : '番茄专注'),
          findsOneWidget,
        );
        expect(
          Provider.of<PomodoroProvider>(
            tester.element(routeFinder),
            listen: false,
          ),
          same(pomodoroProvider),
        );
        expect(
          tester.widget<TabBar>(tabBarFinder.first).controller,
          same(tabControllerBefore),
        );
        expect(tabControllerBefore.index, 1);
        expect(pomodoroProvider.state, same(runningState));
        expect(pomodoroProvider.state.isRunning, isTrue);
        expect(pomodoroProvider.state.remainingSeconds, 720);
        expect(pomodoroProvider.sessions, same(sessions));
        expect(pomodoroProvider.sessions.single, same(session));
        expect(find.text('Locale fixture session'), findsOneWidget);
      }

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Calendar renders the exact widget civil date and retains it across locales',
    (tester) async {
      final target = WidgetCalendarLink.dateFromUri(
        Uri.parse('duoyi://calendar?date=2024-02-29'),
      );
      expect(target, DateTime(2024, 2, 29));
      await tester.pumpWidget(_calendarRouteApp(target!));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, '日'));
      await tester.pumpAndSettle();
      expect(_calendarDateLabel('2024年2月29日'), findsOneWidget);
      final originalState = tester.state(find.byType(CalendarScreen));
      final originalTabs = _calendarTabController(tester);
      expect(tester.takeException(), isNull);

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(
          _calendarDateLabel(
            locale == AppLocale.en ? 'Feb 29, 2024' : '2024年2月29日',
          ),
          findsOneWidget,
        );
        expect(tester.state(find.byType(CalendarScreen)), same(originalState));
        expect(_calendarTabController(tester), same(originalTabs));
        expect(originalTabs.index, 2);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byTooltip('下一天'));
      await tester.pumpAndSettle();
      expect(_calendarDateLabel('2024年3月1日'), findsOneWidget);
      expect(tester.state(find.byType(CalendarScreen)), same(originalState));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Calendar keeps changed date and selected tab through raw locale events',
    (tester) async {
      final initialDate = DateTime(2026, 10, 8);
      await tester.pumpWidget(_calendarRouteApp(initialDate));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(Tab, '日'));
      await tester.pumpAndSettle();
      expect(_calendarDateLabel('2026年10月8日'), findsOneWidget);

      await tester.tap(find.byTooltip('下一天'));
      await tester.pumpAndSettle();
      expect(_calendarDateLabel('2026年10月9日'), findsOneWidget);

      final routeStateBefore = tester.state(find.byType(CalendarScreen));
      final tabControllerBefore = _calendarTabController(tester);
      expect(tabControllerBefore.index, 2);

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();

      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Day'), findsOneWidget);
      expect(_calendarDateLabel('Oct 9, 2026'), findsOneWidget);
      expect(tester.state(find.byType(CalendarScreen)), same(routeStateBefore));
      expect(_calendarTabController(tester), same(tabControllerBefore));
      expect(_calendarTabController(tester).index, 2);

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();

      expect(find.text('日历'), findsOneWidget);
      expect(_calendarDateLabel('2026年10月9日'), findsOneWidget);
      expect(tester.state(find.byType(CalendarScreen)), same(routeStateBefore));
      expect(_calendarTabController(tester), same(tabControllerBefore));
      expect(_calendarTabController(tester).index, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Calendar refreshes copy and keeps State on a direct route without BrandRouteSurface',
    (tester) async {
      final initialDate = DateTime(2026, 10, 8);
      await tester.pumpWidget(
        _calendarRouteApp(initialDate, useBrandRouteSurface: false),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(Tab, '日'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下一天'));
      await tester.pumpAndSettle();

      final routeStateBefore = tester.state(find.byType(CalendarScreen));
      final tabControllerBefore = _calendarTabController(tester);
      expect(tabControllerBefore.index, 2);
      expect(_calendarDateLabel('2026年10月9日'), findsOneWidget);

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();

      expect(find.text('Calendar'), findsOneWidget);
      expect(_calendarDateLabel('Oct 9, 2026'), findsOneWidget);
      expect(tester.state(find.byType(CalendarScreen)), same(routeStateBefore));
      expect(_calendarTabController(tester), same(tabControllerBefore));
      expect(tabControllerBefore.index, 2);

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();

      expect(find.text('日历'), findsOneWidget);
      expect(_calendarDateLabel('2026年10月9日'), findsOneWidget);
      expect(tester.state(find.byType(CalendarScreen)), same(routeStateBefore));
      expect(_calendarTabController(tester), same(tabControllerBefore));
      expect(tabControllerBefore.index, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Integrations keeps Language tab and controller while changing locale',
    (tester) async {
      final calendarSync = _MemoryCalendarSyncProvider();
      final locationReminders = _MemoryLocationReminderProvider();
      final notifications = _MemoryNotificationService();
      final locale = _MemoryLocaleProvider();
      addTearDown(() {
        calendarSync.dispose();
        locationReminders.dispose();
        notifications.dispose();
        locale.dispose();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>(
              create: (_) => _MemoryThemeProvider(),
            ),
            ChangeNotifierProvider<CalendarSyncProvider>.value(
              value: calendarSync,
            ),
            ChangeNotifierProvider<LocationReminderProvider>.value(
              value: locationReminders,
            ),
            ChangeNotifierProvider<NotificationService>.value(
              value: notifications,
            ),
            ChangeNotifierProvider<LocaleProvider>.value(value: locale),
          ],
          child: const MaterialApp(
            home: BrandRouteSurface(child: IntegrationsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(Tab, '语言'));
      await tester.pumpAndSettle();
      final tabControllerBefore = _integrationsTabController(tester);
      expect(tabControllerBefore.index, 2);

      await tester.tap(find.widgetWithText(ListTile, 'English'));
      await tester.pumpAndSettle();

      expect(locale.locale, AppLocale.en);
      expect(find.text('Extensions'), findsOneWidget);
      expect(find.text('Display language'), findsOneWidget);
      expect(find.text('Simplified Chinese'), findsOneWidget);
      final englishTile = find.widgetWithText(ListTile, 'English');
      expect(
        find.descendant(
          of: englishTile,
          matching: find.byIcon(Icons.radio_button_checked),
        ),
        findsOneWidget,
      );
      expect(_integrationsTabController(tester), same(tabControllerBefore));
      expect(_integrationsTabController(tester).index, 2);

      await tester.tap(find.widgetWithText(ListTile, 'Simplified Chinese'));
      await tester.pumpAndSettle();

      expect(locale.locale, AppLocale.zh);
      expect(find.text('扩展功能'), findsOneWidget);
      expect(find.text('界面语言'), findsOneWidget);
      expect(_integrationsTabController(tester), same(tabControllerBefore));
      expect(_integrationsTabController(tester).index, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
