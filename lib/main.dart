import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/app_version.dart';
import 'providers/todo_provider.dart';
import 'providers/habit_provider.dart';
import 'providers/pomodoro_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/cloud_sync_provider.dart';
import 'providers/calendar_provider.dart';
import 'providers/user_provider.dart';
import 'providers/notification_service.dart';
import 'providers/auth_provider.dart';
import 'providers/countdown_provider.dart';
import 'providers/note_provider.dart';
import 'providers/anniversary_provider.dart';
import 'providers/diary_provider.dart';
import 'providers/goal_provider.dart';
import 'providers/course_provider.dart';
import 'providers/app_lock_provider.dart';
import 'providers/preferences_provider.dart';
import 'models/todo.dart' show TodoPriorityX;
import 'services/system_tray.dart';
import 'services/home_widget_service.dart';
import 'services/ai_service.dart';
import 'services/app_update_service.dart';
import 'services/local_notifications.dart';
import 'services/reminder_scheduler.dart';
import 'screens/today_screen.dart';
import 'screens/todo_screen.dart';
import 'screens/habit_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/pomodoro_screen.dart';
import 'screens/mine_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/search_screen.dart';
import 'widgets/brand_background.dart';
import 'widgets/quick_capture_fab.dart';

final GlobalKey<MainShellState> mainShellKey = GlobalKey<MainShellState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final todoProvider = TodoProvider();
  final habitProvider = HabitProvider();
  final pomodoroProvider = PomodoroProvider();
  final themeProvider = ThemeProvider();
  final cloudSyncProvider = CloudSyncProvider();
  final calendarProvider = CalendarProvider();
  final userProvider = UserProvider();
  final notificationService = NotificationService();
  final systemTray = SystemTrayService();
  final authProvider = AuthProvider();
  final countdownProvider = CountdownProvider();
  final noteProvider = NoteProvider();
  final anniversaryProvider = AnniversaryProvider();
  final diaryProvider = DiaryProvider();
  final goalProvider = GoalProvider();
  final courseProvider = CourseProvider();
  final appLockProvider = AppLockProvider();
  final preferencesProvider = PreferencesProvider();
  final aiService = AiService();
  final appUpdate = AppUpdateService(
    repo: 'dq52099/duoyi',
    currentVersion: AppVersion.name,
  );

  await Future.wait([
    todoProvider.loadFromStorage(),
    habitProvider.loadFromStorage(),
    pomodoroProvider.loadFromStorage(),
    themeProvider.loadFromStorage(),
    cloudSyncProvider.loadFromStorage(),
    userProvider.loadFromStorage(),
    countdownProvider.loadFromStorage(),
    noteProvider.loadFromStorage(),
    anniversaryProvider.loadFromStorage(),
    diaryProvider.loadFromStorage(),
    goalProvider.loadFromStorage(),
    courseProvider.loadFromStorage(),
    appLockProvider.loadFromStorage(),
    preferencesProvider.loadFromStorage(),
    notificationService.init(),
    systemTray.init(),
    HomeWidgetService.init(),
    authProvider.loadFromStorage(),
    aiService.loadFromStorage(),
  ]);

  pomodoroProvider.attachNotifier(notificationService);

  // 提醒调度器：监听数据变化，幂等地同步本地通知队列
  final reminderScheduler = ReminderScheduler(notificationService);
  Future<void> resyncReminders() async {
    await reminderScheduler.syncTodos(todoProvider.todos);
    await reminderScheduler.syncHabits(habitProvider.habits);
    await reminderScheduler.syncAnniversaries(anniversaryProvider.items);
  }

  todoProvider.addListener(resyncReminders);
  habitProvider.addListener(resyncReminders);
  anniversaryProvider.addListener(resyncReminders);
  // 初次同步
  await resyncReminders();

  // 通知点击后的深链接(打开对应 Tab)
  LocalNotifications.instance.onTap = (payload) {
    final uri = Uri.tryParse(payload);
    if (uri == null) return;
    _handleWidgetUri(uri, pomodoroProvider);
  };

  // AI / CloudSync 依赖 AuthProvider 的 ApiClient
  aiService.attachClient(authProvider.client);
  cloudSyncProvider.apiClientGetter = () => authProvider.client;
  cloudSyncProvider.serverConfigGetter = () => authProvider.serverConfig;

  authProvider.onServerConfigChanged = (cfg) {
    aiService.updateFromServerConfig(cfg);
  };
  authProvider.addListener(() {
    aiService.attachClient(authProvider.client);
  });
  if (authProvider.serverConfig.isNotEmpty) {
    aiService.updateFromServerConfig(authProvider.serverConfig);
  }

  cloudSyncProvider.onSynced = () {
    todoProvider.loadFromStorage();
    habitProvider.loadFromStorage();
    pomodoroProvider.loadFromStorage();
    countdownProvider.loadFromStorage();
    noteProvider.loadFromStorage();
    anniversaryProvider.loadFromStorage();
    diaryProvider.loadFromStorage();
    goalProvider.loadFromStorage();
    courseProvider.loadFromStorage();
    userProvider.loadFromStorage();
    // 拉取云端后可能覆盖了本地 reminder，也要重跑一次
    resyncReminders();
  };

  authProvider.addListener(() {
    if (authProvider.state.isLoggedIn && cloudSyncProvider.config.autoSync) {
      cloudSyncProvider.syncNow();
    }
  });
  if (authProvider.state.isLoggedIn && cloudSyncProvider.config.autoSync) {
    cloudSyncProvider.syncNow();
  }

  notificationService.setStrings(themeProvider.brand.strings);
  themeProvider.addListener(() {
    notificationService.setStrings(themeProvider.brand.strings);
    _pushHomeWidget(
      todoProvider,
      habitProvider,
      pomodoroProvider,
      themeProvider,
    );
  });

  systemTray.onActivate.listen((action) {
    if (action == 'pomodoro_quick_start') pomodoroProvider.toggleTimer();
  });

  void onDataChange() => _pushHomeWidget(
    todoProvider,
    habitProvider,
    pomodoroProvider,
    themeProvider,
  );
  todoProvider.addListener(onDataChange);
  habitProvider.addListener(onDataChange);
  pomodoroProvider.addListener(onDataChange);

  await _pushHomeWidget(
    todoProvider,
    habitProvider,
    pomodoroProvider,
    themeProvider,
  );

  HomeWidgetService.widgetClickedStream.listen(
    (uri) => _handleWidgetUri(uri, pomodoroProvider),
  );
  final initial = await HomeWidgetService.initialLaunchUri();
  if (initial != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleWidgetUri(initial, pomodoroProvider);
    });
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: todoProvider),
        ChangeNotifierProvider.value(value: habitProvider),
        ChangeNotifierProvider.value(value: pomodoroProvider),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: cloudSyncProvider),
        ChangeNotifierProvider.value(value: calendarProvider),
        ChangeNotifierProvider.value(value: userProvider),
        ChangeNotifierProvider.value(value: countdownProvider),
        ChangeNotifierProvider.value(value: noteProvider),
        ChangeNotifierProvider.value(value: anniversaryProvider),
        ChangeNotifierProvider.value(value: diaryProvider),
        ChangeNotifierProvider.value(value: goalProvider),
        ChangeNotifierProvider.value(value: courseProvider),
        ChangeNotifierProvider.value(value: appLockProvider),
        ChangeNotifierProvider.value(value: preferencesProvider),
        ChangeNotifierProvider.value(value: notificationService),
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: aiService),
        ChangeNotifierProvider.value(value: appUpdate),
        Provider.value(value: systemTray),
      ],
      child: const DuoyiApp(),
    ),
  );
}

Future<void> _pushHomeWidget(
  TodoProvider t,
  HabitProvider h,
  PomodoroProvider p,
  ThemeProvider tp,
) async {
  final today = DateTime.now();
  final activeToday = t.todos.where((todo) {
    return !todo.isCompleted &&
        todo.date.year == today.year &&
        todo.date.month == today.month &&
        todo.date.day == today.day;
  }).toList()
    ..sort((a, b) {
      // 按优先级倒序
      final r = b.priority.rank.compareTo(a.priority.rank);
      if (r != 0) return r;
      return a.sortOrder.compareTo(b.sortOrder);
    });
  final activeTodayTodos = activeToday.length;
  final top3 = activeToday.take(3).map((e) => e.title).toList();
  final habitPercent = (h.todayCompletionRate * 100).round();
  await HomeWidgetService.push(
    todoCount: activeTodayTodos,
    habitPercent: habitPercent,
    pomodoroToday: p.sessionCountToday,
    strings: tp.brand.strings,
    todoTop3: top3,
  );
}

void _handleWidgetUri(Uri? uri, PomodoroProvider pomodoro) {
  if (uri == null) return;
  if (uri.scheme != 'duoyi') return;

  final state = mainShellKey.currentState;

  if (uri.host == 'tab') {
    final tab = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    final idx = switch (tab) {
      'today' => 0,
      'todo' => 1,
      'habit' => 2,
      'calendar' => 3,
      'focus' => 4,
      'mine' => 5,
      _ => 3,
    };
    state?.navigateTo(idx);
  } else if (uri.host == 'action') {
    final action = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    if (action == 'start_pomodoro') {
      state?.navigateTo(4);
      if (!pomodoro.state.isRunning) pomodoro.toggleTimer();
    }
  }
}

class DuoyiApp extends StatefulWidget {
  const DuoyiApp({super.key});

  @override
  State<DuoyiApp> createState() => _DuoyiAppState();
}

class _DuoyiAppState extends State<DuoyiApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = context.read<AppLockProvider>();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      lock.onAppLifecycleInactive();
    } else if (state == AppLifecycleState.resumed) {
      lock.onAppLifecycleResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.watch<ThemeProvider>().brand;
    final lock = context.watch<AppLockProvider>();
    return MaterialApp(
      title: brand.strings.appTitle,
      debugShowCheckedModeBanner: false,
      theme: brand.theme,
      home: Stack(
        children: [
          MainShell(key: mainShellKey),
          if (lock.isLocked)
            const Positioned.fill(child: Material(child: LockScreen())),
        ],
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int _currentIndex = 0; // Today first

  static final GlobalKey todayKey = GlobalKey();
  static final GlobalKey todoKey = GlobalKey();
  static final GlobalKey habitKey = GlobalKey();
  static final GlobalKey calendarKey = GlobalKey();
  static final GlobalKey pomodoroKey = GlobalKey();
  static final GlobalKey mineKey = GlobalKey();

  void navigateTo(int index) => setState(() => _currentIndex = index);

  @override
  void initState() {
    super.initState();
    // 延迟一帧再读 PreferencesProvider，避免 initState 中 read 异常
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prefs = context.read<PreferencesProvider>();
      if (prefs.defaultTab != _currentIndex &&
          prefs.defaultTab >= 0 &&
          prefs.defaultTab < 6) {
        setState(() => _currentIndex = prefs.defaultTab);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ThemeProvider>().brand.strings;
    final destinations = [
      const NavigationDestination(
        icon: Icon(Icons.today_outlined),
        selectedIcon: Icon(Icons.today),
        label: '今日',
      ),
      NavigationDestination(
        icon: const Icon(Icons.checklist),
        selectedIcon: const Icon(Icons.checklist_rounded),
        label: s.navTodo,
      ),
      NavigationDestination(
        icon: const Icon(Icons.repeat),
        selectedIcon: const Icon(Icons.repeat_rounded),
        label: s.navHabit,
      ),
      NavigationDestination(
        icon: const Icon(Icons.calendar_month_outlined),
        selectedIcon: const Icon(Icons.calendar_month),
        label: s.navCalendar,
      ),
      NavigationDestination(
        icon: const Icon(Icons.timer_outlined),
        selectedIcon: const Icon(Icons.timer),
        label: s.navFocus,
      ),
      NavigationDestination(
        icon: const Icon(Icons.person_outline),
        selectedIcon: const Icon(Icons.person),
        label: s.navMine,
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BrandBackground(
        child: IndexedStack(
          index: _currentIndex,
          children: [
            TodayScreen(key: todayKey),
            TodoScreen(key: todoKey),
            HabitScreen(key: habitKey),
            CalendarScreen(key: calendarKey),
            PomodoroScreen(key: pomodoroKey),
            MineScreen(key: mineKey),
          ],
        ),
      ),
      floatingActionButton: (_currentIndex == 0 || _currentIndex == 5) &&
              context.watch<PreferencesProvider>().quickCaptureFab
          ? const QuickCaptureFab()
          : null,
      appBar: _currentIndex == 0
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              toolbarHeight: 0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SearchScreen()),
                  ),
                ),
              ],
            )
          : null,
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 64,
          elevation: 0,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surface.withValues(alpha: 0.95),
          indicatorColor: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: 0.15),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              );
            }
            return const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return IconThemeData(
                color: Theme.of(context).colorScheme.primary,
                size: 24,
              );
            }
            return const IconThemeData(color: Colors.grey, size: 24);
          }),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: destinations,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
      ),
    );
  }
}
