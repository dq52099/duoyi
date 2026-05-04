import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/todo_provider.dart';
import 'providers/habit_provider.dart';
import 'providers/pomodoro_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/cloud_sync_provider.dart';
import 'providers/calendar_provider.dart';
import 'providers/user_provider.dart';
import 'providers/notification_service.dart';
import 'providers/auth_provider.dart';
import 'services/system_tray.dart';
import 'services/home_widget_service.dart';
import 'services/ai_service.dart';
import 'services/app_update_service.dart';
import 'screens/todo_screen.dart';
import 'screens/habit_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/pomodoro_screen.dart';
import 'screens/mine_screen.dart';
import 'widgets/brand_background.dart';

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
  final aiService = AiService();
  final appUpdate = AppUpdateService(repo: 'dq52099/duoyi', currentVersion: '1.0.0');

  await Future.wait([
    todoProvider.loadFromStorage(),
    habitProvider.loadFromStorage(),
    pomodoroProvider.loadFromStorage(),
    themeProvider.loadFromStorage(),
    cloudSyncProvider.loadFromStorage(),
    userProvider.loadFromStorage(),
    notificationService.init(),
    systemTray.init(),
    HomeWidgetService.init(),
    authProvider.loadFromStorage(),
    aiService.loadFromStorage(),
  ]);

  pomodoroProvider.attachNotifier(notificationService);

  // Brand strings → notifier
  notificationService.setStrings(themeProvider.brand.strings);
  themeProvider.addListener(() {
    notificationService.setStrings(themeProvider.brand.strings);
    _pushHomeWidget(todoProvider, habitProvider, pomodoroProvider, themeProvider);
  });

  // Tray actions
  systemTray.onActivate.listen((action) {
    if (action == 'pomodoro_quick_start') pomodoroProvider.toggleTimer();
  });

  // Push to Android home widget on every data change
  void onDataChange() => _pushHomeWidget(
        todoProvider,
        habitProvider,
        pomodoroProvider,
        themeProvider,
      );
  todoProvider.addListener(onDataChange);
  habitProvider.addListener(onDataChange);
  pomodoroProvider.addListener(onDataChange);

  // Initial push
  await _pushHomeWidget(todoProvider, habitProvider, pomodoroProvider, themeProvider);

  // Listen to home widget taps (deep link routing)
  HomeWidgetService.widgetClickedStream.listen((uri) => _handleWidgetUri(uri, pomodoroProvider));
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
  final activeTodayTodos = t.todos.where((todo) {
    return !todo.isCompleted &&
        todo.date.year == today.year &&
        todo.date.month == today.month &&
        todo.date.day == today.day;
  }).length;
  final habitPercent = (h.todayCompletionRate * 100).round();
  await HomeWidgetService.push(
    todoCount: activeTodayTodos,
    habitPercent: habitPercent,
    pomodoroToday: p.sessionCountToday,
    strings: tp.brand.strings,
  );
}

void _handleWidgetUri(Uri? uri, PomodoroProvider pomodoro) {
  if (uri == null) return;
  if (uri.scheme != 'duoyi') return;

  final state = mainShellKey.currentState;

  if (uri.host == 'tab') {
    final tab = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    final idx = switch (tab) {
      'todo' => 0,
      'habit' => 1,
      'calendar' => 2,
      'focus' => 3,
      'mine' => 4,
      _ => 2,
    };
    state?.navigateTo(idx);
  } else if (uri.host == 'action') {
    final action = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    if (action == 'start_pomodoro') {
      state?.navigateTo(3);
      if (!pomodoro.state.isRunning) pomodoro.toggleTimer();
    }
  }
}

class DuoyiApp extends StatelessWidget {
  const DuoyiApp({super.key});

  @override
  Widget build(BuildContext context) {
    final brand = context.watch<ThemeProvider>().brand;
    return MaterialApp(
      title: brand.strings.appTitle,
      debugShowCheckedModeBanner: false,
      theme: brand.theme,
      home: MainShell(key: mainShellKey),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int _currentIndex = 2; // Calendar is primary

  static final GlobalKey todoKey = GlobalKey();
  static final GlobalKey habitKey = GlobalKey();
  static final GlobalKey calendarKey = GlobalKey();
  static final GlobalKey pomodoroKey = GlobalKey();
  static final GlobalKey mineKey = GlobalKey();

  void navigateTo(int index) => setState(() => _currentIndex = index);

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ThemeProvider>().brand.strings;
    final destinations = [
      NavigationDestination(icon: const Icon(Icons.checklist), selectedIcon: const Icon(Icons.checklist_rounded), label: s.navTodo),
      NavigationDestination(icon: const Icon(Icons.repeat), selectedIcon: const Icon(Icons.repeat_rounded), label: s.navHabit),
      NavigationDestination(icon: const Icon(Icons.calendar_month_outlined), selectedIcon: const Icon(Icons.calendar_month), label: s.navCalendar),
      NavigationDestination(icon: const Icon(Icons.timer_outlined), selectedIcon: const Icon(Icons.timer), label: s.navFocus),
      NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: s.navMine),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BrandBackground(
        child: IndexedStack(
          index: _currentIndex,
          children: [
            TodoScreen(key: todoKey),
            HabitScreen(key: habitKey),
            CalendarScreen(key: calendarKey),
            PomodoroScreen(key: pomodoroKey),
            MineScreen(key: mineKey),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: destinations,
      ),
    );
  }
}
