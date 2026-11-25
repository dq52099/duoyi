import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/web_target.dart';
import 'package:duoyi/main.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/calendar_screen.dart';
import 'package:duoyi/screens/mine_screen.dart';
import 'package:duoyi/screens/habit_screen.dart';
import 'package:duoyi/screens/pomodoro_screen.dart';
import 'package:duoyi/screens/today_screen.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _localePreferenceKey = 'duoyi_locale_v1';
const _bottomNavOrderPreferenceKey = 'pref_bottom_nav_order';
const _bottomNavVisiblePreferenceKey = 'pref_bottom_nav_visible';
const _defaultVisibleTabs = <int>[0, 1, 2, 5, 6];

class _StartupProviders {
  final PreferencesProvider preferences;
  final LocaleProvider locale;

  const _StartupProviders({required this.preferences, required this.locale});

  void dispose() {
    preferences.dispose();
    locale.dispose();
  }
}

Future<_StartupProviders> _prepareStartupProviders(
  WidgetTester tester, {
  required int defaultTab,
  AppLocale locale = AppLocale.zh,
  List<int> visibleTabs = _defaultVisibleTabs,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    _localePreferenceKey: locale.storageValue,
    _bottomNavOrderPreferenceKey: List<String>.generate(7, (index) => '$index'),
    _bottomNavVisiblePreferenceKey: visibleTabs
        .map((tab) => tab.toString())
        .toList(),
  });

  late PreferencesProvider preferences;
  late LocaleProvider localeProvider;
  await tester.runAsync(() async {
    preferences = PreferencesProvider();
    localeProvider = LocaleProvider();
    // Match main(): hydrate persistent state before DuoyiApp creates MainShell.
    await preferences.loadFromStorage();
    await localeProvider.loadFromStorage();
    await preferences.setDefaultTab(defaultTab);
    await preferences.loadFromStorage();
  });
  I18n.setLocale(locale);

  expect(
    preferences.defaultTab,
    PreferencesProvider.normalizeDefaultTab(defaultTab),
  );
  expect(preferences.visibleBottomNavTabs, visibleTabs);
  expect(preferences.visibleBottomNavTabs, contains(6));
  return _StartupProviders(preferences: preferences, locale: localeProvider);
}

Widget _duoyiApp(_StartupProviders startup) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => TodoProvider()),
      ChangeNotifierProvider(create: (_) => HabitProvider()),
      ChangeNotifierProvider(create: (_) => PomodoroProvider()),
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => FocusRoomProvider()),
      ChangeNotifierProvider(create: (_) => CustomFocusSoundProvider()),
      ChangeNotifierProvider(create: (_) => CloudSyncProvider()),
      ChangeNotifierProvider(create: (_) => CalendarProvider()),
      ChangeNotifierProvider(create: (_) => UserProvider()),
      ChangeNotifierProvider(create: (_) => CountdownProvider()),
      ChangeNotifierProvider(create: (_) => NoteProvider()),
      ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
      ChangeNotifierProvider(create: (_) => DiaryProvider()),
      ChangeNotifierProvider(create: (_) => GoalProvider()),
      ChangeNotifierProvider(create: (_) => CourseProvider()),
      ChangeNotifierProvider(create: (_) => AppLockProvider()),
      ChangeNotifierProvider<PreferencesProvider>.value(
        value: startup.preferences,
      ),
      ChangeNotifierProvider(create: (_) => AchievementProvider()),
      ChangeNotifierProvider(create: (_) => ShareProvider()),
      ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
      ChangeNotifierProvider(create: (_) => NotificationService()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => AiService()),
      ChangeNotifierProvider<LocaleProvider>.value(value: startup.locale),
      ChangeNotifierProvider(create: (_) => LocationReminderProvider()),
      ChangeNotifierProvider(create: (_) => CalendarSyncProvider()),
      ChangeNotifierProvider(
        create: (_) => AppUpdateService(
          repo: 'dq52099/duoyi',
          currentVersion: AppVersion.name,
        ),
      ),
    ],
    child: const DuoyiApp(),
  );
}

Future<void> _pumpDuoyiApp(
  WidgetTester tester,
  _StartupProviders startup,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_duoyiApp(startup));
  await tester.pumpAndSettle();
}

String _backToMineLabel(AppLocale locale) =>
    locale == AppLocale.en ? 'Back to Me' : '返回我的';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
    WebTarget.debugDesktopWebBuild = false;
  });

  tearDown(() {
    I18n.setLocale(AppLocale.zh);
    WebTarget.debugDesktopWebBuild = null;
  });

  testWidgets('中文：保存的小组件默认入口隐藏时，启动仍打开小组件并显示返回我的', (tester) async {
    final startup = await _prepareStartupProviders(
      tester,
      defaultTab: 5,
      visibleTabs: const [0, 1, 2, 6],
    );
    addTearDown(startup.dispose);
    await _pumpDuoyiApp(tester, startup);

    expect(find.byType(WidgetScreen), findsOneWidget);
    expect(find.text(_backToMineLabel(AppLocale.zh)), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets(
    'English: saved hidden widget default opens the widget page with its return bar',
    (tester) async {
      final startup = await _prepareStartupProviders(
        tester,
        defaultTab: 5,
        locale: AppLocale.en,
        visibleTabs: const [0, 1, 2, 6],
      );
      addTearDown(startup.dispose);
      await _pumpDuoyiApp(tester, startup);

      expect(find.byType(WidgetScreen), findsOneWidget);
      expect(find.text(_backToMineLabel(AppLocale.en)), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    },
  );

  testWidgets('中文：保存的日历默认入口隐藏时，启动仍打开日历并显示返回我的', (tester) async {
    final startup = await _prepareStartupProviders(
      tester,
      defaultTab: 3,
      visibleTabs: const [0, 1, 2, 5, 6],
    );
    addTearDown(startup.dispose);
    await _pumpDuoyiApp(tester, startup);

    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(find.text(_backToMineLabel(AppLocale.zh)), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets(
    'English: saved hidden calendar default opens the calendar page with its return bar',
    (tester) async {
      final startup = await _prepareStartupProviders(
        tester,
        defaultTab: 3,
        locale: AppLocale.en,
        visibleTabs: const [0, 1, 2, 5, 6],
      );
      addTearDown(startup.dispose);
      await _pumpDuoyiApp(tester, startup);

      expect(find.byType(CalendarScreen), findsOneWidget);
      expect(find.text(_backToMineLabel(AppLocale.en)), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    },
  );

  testWidgets('隐藏初始 tab 且只显示待办和我的时，默认小组件仍在冷启动打开', (tester) async {
    final startup = await _prepareStartupProviders(
      tester,
      defaultTab: 5,
      visibleTabs: const [1, 6],
    );
    addTearDown(startup.dispose);
    await _pumpDuoyiApp(tester, startup);

    expect(find.byType(WidgetScreen), findsOneWidget);
    expect(find.text(_backToMineLabel(AppLocale.zh)), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('可见的待办默认 tab 启动后被隐藏时仍回退到可见页', (tester) async {
    final startup = await _prepareStartupProviders(
      tester,
      defaultTab: 1,
      visibleTabs: _defaultVisibleTabs,
    );
    addTearDown(startup.dispose);
    await _pumpDuoyiApp(tester, startup);

    expect(find.byType(TodoScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.runAsync(
      () => startup.preferences.setBottomNavVisible(1, false),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TodoScreen), findsNothing);
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text(_backToMineLabel(AppLocale.zh)), findsNothing);
  });

  testWidgets('返回我的会恢复真实底导航并选中我的', (tester) async {
    final startup = await _prepareStartupProviders(
      tester,
      defaultTab: 0,
      visibleTabs: const [0, 1, 2, 6],
    );
    addTearDown(startup.dispose);
    await _pumpDuoyiApp(tester, startup);

    tester
        .state<MainShellState>(find.byType(MainShell))
        .navigateTo(5, allowHidden: true);
    await tester.pumpAndSettle();
    expect(find.byType(WidgetScreen), findsOneWidget);
    expect(find.text(_backToMineLabel(AppLocale.zh)), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(find.text(_backToMineLabel(AppLocale.zh)));
    await tester.pumpAndSettle();

    expect(find.byType(MineScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text(_backToMineLabel(AppLocale.zh)), findsNothing);
    final navigationBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(
      navigationBar.selectedIndex,
      startup.preferences.visibleBottomNavTabs.indexOf(6),
    );
    expect(
      navigationBar.destinations.whereType<NavigationDestination>().map(
        (destination) => destination.label,
      ),
      contains('我的'),
    );
  });

  testWidgets('保存的可见待办 tab 1 正常成为启动页并保留导航栏', (tester) async {
    final startup = await _prepareStartupProviders(
      tester,
      defaultTab: 1,
      visibleTabs: _defaultVisibleTabs,
    );
    addTearDown(startup.dispose);
    await _pumpDuoyiApp(tester, startup);

    expect(find.byType(TodoScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    final navigationBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(
      navigationBar.selectedIndex,
      startup.preferences.visibleBottomNavTabs.indexOf(1),
    );
    expect(
      navigationBar.destinations.whereType<NavigationDestination>().map(
        (destination) => destination.label,
      ),
      contains('待办'),
    );
  });

  testWidgets('首帧默认回调前的显式隐藏日历导航不会被默认页或旧回退覆盖', (tester) async {
    final startup = await _prepareStartupProviders(
      tester,
      defaultTab: 5,
      visibleTabs: const [1, 6],
    );
    addTearDown(startup.dispose);

    // A startup deep-link dispatcher can navigate after MainShell mounts but
    // before MainShell's own post-frame default-tab callback runs.
    tester.binding.addPostFrameCallback((_) {
      tester
          .state<MainShellState>(find.byType(MainShell))
          .navigateTo(3, allowHidden: true);
    });
    await _pumpDuoyiApp(tester, startup);

    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(find.text(_backToMineLabel(AppLocale.zh)), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
  for (final entry in <int, Type>{
    0: TodayScreen,
    2: HabitScreen,
    4: PomodoroScreen,
  }.entries) {
    testWidgets(
      'hidden default ${entry.key} opens its own page and preserves return navigation',
      (tester) async {
        final startup = await _prepareStartupProviders(
          tester,
          defaultTab: entry.key,
          visibleTabs: const [1, 6],
        );
        addTearDown(startup.dispose);
        await _pumpDuoyiApp(tester, startup);
        expect(find.byType(entry.value), findsOneWidget);
        expect(find.text(_backToMineLabel(AppLocale.zh)), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'same-frame ABA explicit navigation defeats the old initial fallback',
    (tester) async {
      final startup = await _prepareStartupProviders(
        tester,
        defaultTab: 5,
        visibleTabs: const [1, 6],
      );
      addTearDown(startup.dispose);
      tester.binding.addPostFrameCallback((_) {
        final shell = tester.state<MainShellState>(find.byType(MainShell));
        shell.navigateTo(0, allowHidden: true);
        shell.navigateTo(1);
        shell.navigateTo(0, allowHidden: true);
      });
      await _pumpDuoyiApp(tester, startup);
      expect(find.byType(TodayScreen), findsOneWidget);
      expect(find.text(_backToMineLabel(AppLocale.zh)), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'desktop retains its supported calendar fallback for saved widget default',
    (tester) async {
      WebTarget.debugDesktopWebBuild = true;
      final startup = await _prepareStartupProviders(
        tester,
        defaultTab: 5,
        visibleTabs: const [0, 1, 2, 3, 6],
      );
      addTearDown(startup.dispose);
      expect(startup.preferences.defaultTab, 3);
      await _pumpDuoyiApp(tester, startup);
      expect(find.byType(CalendarScreen), findsOneWidget);
      expect(find.byType(WidgetScreen), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
