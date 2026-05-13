import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/app_version.dart';
import 'core/achievements.dart';
import 'core/completion_visibility_policy.dart';
import 'core/local_timezone_resolver.dart';
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
import 'providers/time_audit_provider.dart';
import 'providers/achievement_provider.dart';
import 'providers/share_provider.dart';
import 'models/goal.dart' show GoalStatus;
import 'models/todo.dart' show TodoPriorityX;
import 'services/alarm_service.dart';
import 'services/system_tray.dart';
import 'services/home_widget_service.dart';
import 'services/ai_service.dart';
import 'services/app_update_service.dart';
import 'services/holiday_calendar.dart';
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
import 'screens/today_detail_router.dart';
import 'widgets/brand_background.dart';
import 'widgets/quick_capture_fab.dart';
import 'widgets/surface_components.dart';

final GlobalKey<MainShellState> mainShellKey = GlobalKey<MainShellState>();

/// 模块级的提醒调度器实例。
///
/// 在 `main()` 中构造后注入到各 Provider，并被 `_DuoyiAppState` 在
/// `AppLifecycleState.resumed` 检测到时区变化时读取，用于触发 `resyncAll`。
/// 放在顶层是因为 `_DuoyiAppState` 并不持有构造时的闭包引用。
late ReminderScheduler _reminderScheduler;
bool _initialExactAlarmGranted = false;

Future<void> _startupGuard(String label, Future<void> Function() task) async {
  try {
    await task();
  } catch (e, st) {
    debugPrint('[startup] $label failed: $e\n$st');
  }
}

Future<T?> _startupValue<T>(String label, Future<T?> Function() task) async {
  try {
    return await task();
  } catch (e, st) {
    debugPrint('[startup] $label failed: $e\n$st');
    return null;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 首帧前初始化本地时区，保证后续 tz.TZDateTime.from(.., tz.local) 正确。
  await _startupGuard('timezone', () => LocalTimezoneResolver.init());

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
  final timeAuditProvider = TimeAuditProvider();
  final achievementProvider = AchievementProvider();
  final shareProvider = ShareProvider();
  final aiService = AiService();
  final appUpdate = AppUpdateService(
    repo: 'dq52099/duoyi',
    currentVersion: AppVersion.name,
  );

  await Future.wait([
    _startupGuard('todo storage', () => todoProvider.loadFromStorage()),
    _startupGuard('habit storage', () => habitProvider.loadFromStorage()),
    _startupGuard('pomodoro storage', () => pomodoroProvider.loadFromStorage()),
    _startupGuard('theme storage', () => themeProvider.loadFromStorage()),
    _startupGuard(
      'cloud sync storage',
      () => cloudSyncProvider.loadFromStorage(),
    ),
    _startupGuard('user storage', () => userProvider.loadFromStorage()),
    _startupGuard(
      'countdown storage',
      () => countdownProvider.loadFromStorage(),
    ),
    _startupGuard('note storage', () => noteProvider.loadFromStorage()),
    _startupGuard(
      'anniversary storage',
      () => anniversaryProvider.loadFromStorage(),
    ),
    _startupGuard('diary storage', () => diaryProvider.loadFromStorage()),
    _startupGuard('goal storage', () => goalProvider.loadFromStorage()),
    _startupGuard('course storage', () => courseProvider.loadFromStorage()),
    _startupGuard('app lock storage', () => appLockProvider.loadFromStorage()),
    _startupGuard(
      'preferences storage',
      () => preferencesProvider.loadFromStorage(),
    ),
    _startupGuard(
      'time audit storage',
      () => timeAuditProvider.loadFromStorage(),
    ),
    _startupGuard(
      'achievement storage',
      () => achievementProvider.loadFromStorage(),
    ),
    _startupGuard('notifications', () => notificationService.init()),
    _startupGuard('system tray', () => systemTray.init()),
    _startupGuard('home widget', () => HomeWidgetService.init()),
    _startupGuard('auth storage', () => authProvider.loadFromStorage()),
    _startupGuard('ai storage', () => aiService.loadFromStorage()),
  ]);

  try {
    _initialExactAlarmGranted = await AlarmService.instance
        .hasExactAlarmPermission();
  } catch (e, st) {
    debugPrint('[startup] exact alarm probe failed: $e\n$st');
    _initialExactAlarmGranted = false;
  }

  pomodoroProvider.attachNotifier(notificationService);
  pomodoroProvider.attachTimeAudit(timeAuditProvider);
  todoProvider.timeAudit = timeAuditProvider;
  habitProvider.timeAudit = timeAuditProvider;
  goalProvider.timeAudit = timeAuditProvider;
  achievementProvider.attachNotificationService(notificationService);
  shareProvider.apiClientGetter = () => authProvider.client;
  shareProvider.userIdGetter = () => authProvider.state.userId;
  // 让 PomodoroProvider 监听 AppLifecycle，以便在 resumed 时恢复白噪音。
  pomodoroProvider.attachLifecycle();

  // 冷启动执行一次 Daily Rollover（归档昨日完成 + 顺延过期 + 派发重复目标）。
  // 须在 ReminderScheduler 初次同步之前，这样调度器拿到的已经是顺延 / 派发后的最新状态。
  await _startupGuard(
    'daily rollover',
    () => CompletionVisibilityPolicy.runDailyRollover(
      todoProvider,
      DateTime.now(),
      goalProvider: goalProvider,
    ),
  );

  // 提醒调度器：监听数据变化，幂等地同步本地通知队列
  final reminderScheduler = ReminderScheduler(notificationService);
  _reminderScheduler = reminderScheduler;
  // 注入到 Provider，供 Provider 内部的局部 hook（例如 postponeOverdue、
  // onTimezoneChanged）转发调度请求。
  todoProvider.scheduler = reminderScheduler;
  goalProvider.scheduler = reminderScheduler;
  Future<void> resyncReminders() async {
    await reminderScheduler.syncTodos(todoProvider.todos);
    await reminderScheduler.syncHabits(habitProvider.habits);
    await reminderScheduler.syncAnniversaries(anniversaryProvider.items);
    await reminderScheduler.syncGoals(goalProvider.goals);
    await reminderScheduler.syncCountdowns(countdownProvider.items);
  }

  todoProvider.addListener(resyncReminders);
  habitProvider.addListener(resyncReminders);
  anniversaryProvider.addListener(resyncReminders);
  goalProvider.addListener(resyncReminders);
  countdownProvider.addListener(resyncReminders);
  // 本地有改动 → 在云同步侧标"有未同步改动"（Req 12.7）。
  void markDirty() => cloudSyncProvider.markPendingLocalChange();
  todoProvider.addListener(markDirty);
  habitProvider.addListener(markDirty);
  anniversaryProvider.addListener(markDirty);
  goalProvider.addListener(markDirty);
  noteProvider.addListener(markDirty);
  countdownProvider.addListener(markDirty);
  diaryProvider.addListener(markDirty);
  courseProvider.addListener(markDirty);
  pomodoroProvider.addListener(markDirty);
  timeAuditProvider.addListener(markDirty);

  void refreshUserStats() {
    userProvider.recalc(
      completedTodos: todoProvider.completedTodos.length,
      totalFocusMinutes: pomodoroProvider.totalFocusMinutes,
      currentStreak: habitProvider.longestCurrentStreak,
      bestStreak: habitProvider.longestBestStreak,
    );
  }

  todoProvider.addListener(refreshUserStats);
  habitProvider.addListener(refreshUserStats);
  pomodoroProvider.addListener(refreshUserStats);

  void refreshAchievements() {
    achievementProvider.updateContext(
      AchievementContext(
        totalTodos: todoProvider.todos.length,
        completedTodos: todoProvider.completedTodos.length,
        longestHabitStreak: habitProvider.longestBestStreak,
        habitCount: habitProvider.habits.length,
        focusMinutes: pomodoroProvider.totalFocusMinutes,
        focusSessions: pomodoroProvider.sessions.length,
        diaryStreak: diaryProvider.currentStreak,
        diaryCount: diaryProvider.entries.length,
        goalsTotal: goalProvider.goals.length,
        goalsAchieved: goalProvider.goals
            .where((g) => g.status == GoalStatus.achieved)
            .length,
        anniversaries: anniversaryProvider.items.length,
        courses: courseProvider.courses.length,
        notes: noteProvider.notes.length,
        themeSwitches: themeProvider.themeSwitchCount,
      ),
    );
  }

  todoProvider.addListener(refreshAchievements);
  habitProvider.addListener(refreshAchievements);
  pomodoroProvider.addListener(refreshAchievements);
  diaryProvider.addListener(refreshAchievements);
  goalProvider.addListener(refreshAchievements);
  anniversaryProvider.addListener(refreshAchievements);
  courseProvider.addListener(refreshAchievements);
  noteProvider.addListener(refreshAchievements);
  themeProvider.addListener(refreshAchievements);
  // 初次同步
  await _startupGuard('initial reminder resync', resyncReminders);
  Future<void> syncDailyDigestReminder() => _syncDailyDigestReminder(
    preferencesProvider,
    notificationService,
    todoProvider,
  );
  preferencesProvider.addListener(syncDailyDigestReminder);
  todoProvider.addListener(syncDailyDigestReminder);
  await _startupGuard('daily digest reminder', syncDailyDigestReminder);
  refreshUserStats();
  refreshAchievements();

  // 通知点击后的深链接(打开对应 Tab)
  void handleNotificationPayload(String payload) {
    final uri = Uri.tryParse(payload);
    if (uri == null) return;
    _handleWidgetUri(uri, pomodoroProvider);
  }

  LocalNotifications.instance.onTap = handleNotificationPayload;
  AlarmService.instance.onTap = handleNotificationPayload;
  final initialNotificationPayloads = <String>[];
  final localLaunchPayload = LocalNotifications.instance.takeLaunchPayload();
  if (localLaunchPayload != null && localLaunchPayload.isNotEmpty) {
    initialNotificationPayloads.add(localLaunchPayload);
  }
  final alarmLaunchPayload = AlarmService.instance.takeLaunchPayload();
  if (alarmLaunchPayload != null && alarmLaunchPayload.isNotEmpty) {
    initialNotificationPayloads.add(alarmLaunchPayload);
  }

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
    // 同步完成后服务端回写可能覆盖本地数据；这段 reload 不应被当作"脏改动"。
    // ignore: discarded_futures
    cloudSyncProvider.suppressDirtyMarkWhile(() async {
      await todoProvider.loadFromStorage();
      await habitProvider.loadFromStorage();
      await pomodoroProvider.loadFromStorage();
      await countdownProvider.loadFromStorage();
      await noteProvider.loadFromStorage();
      await anniversaryProvider.loadFromStorage();
      await diaryProvider.loadFromStorage();
      await goalProvider.loadFromStorage();
      await courseProvider.loadFromStorage();
      await userProvider.loadFromStorage();
      await timeAuditProvider.loadFromStorage();
      await shareProvider.load();
      // 拉取云端后可能覆盖了本地 reminder，也要重跑一次
      await resyncReminders();
    });
  };

  authProvider.addListener(() {
    shareProvider.load();
    if (authProvider.state.isLoggedIn && cloudSyncProvider.config.autoSync) {
      cloudSyncProvider.syncNow();
    }
  });
  if (authProvider.state.isLoggedIn) {
    shareProvider.load();
  }
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

  await _startupGuard(
    'initial home widget push',
    () => _pushHomeWidget(
      todoProvider,
      habitProvider,
      pomodoroProvider,
      themeProvider,
    ),
  );

  try {
    HomeWidgetService.widgetClickedStream.listen(
      (uri) => _handleWidgetUri(uri, pomodoroProvider),
    );
  } catch (e, st) {
    debugPrint('[startup] home widget stream failed: $e\n$st');
  }
  final initial = await _startupValue<Uri>(
    'home widget initial launch',
    () => HomeWidgetService.initialLaunchUri(),
  );
  if (initial != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleWidgetUri(initial, pomodoroProvider);
    });
  }

  // 冷启动所有 loadFromStorage / resyncReminders / _pushHomeWidget 都已完成，
  // 从这一刻起 Provider 的改动才算"用户发起的脏改动"。
  cloudSyncProvider.dirtyMarkEnabled = true;

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
        ChangeNotifierProvider.value(value: timeAuditProvider),
        ChangeNotifierProvider.value(value: achievementProvider),
        ChangeNotifierProvider.value(value: shareProvider),
        ChangeNotifierProvider.value(value: notificationService),
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: aiService),
        ChangeNotifierProvider.value(value: appUpdate),
        Provider.value(value: systemTray),
      ],
      child: const DuoyiApp(),
    ),
  );

  if (initialNotificationPayloads.isNotEmpty) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final payload in initialNotificationPayloads.toSet()) {
        handleNotificationPayload(payload);
      }
    });
  }
}

Future<void> _pushHomeWidget(
  TodoProvider t,
  HabitProvider h,
  PomodoroProvider p,
  ThemeProvider tp,
) async {
  final today = DateTime.now();
  final activeToday =
      t.todos.where((todo) {
        return !todo.isCompleted &&
            todo.date.year == today.year &&
            todo.date.month == today.month &&
            todo.date.day == today.day;
      }).toList()..sort((a, b) {
        // 按优先级倒序
        final r = b.priority.rank.compareTo(a.priority.rank);
        if (r != 0) return r;
        return a.sortOrder.compareTo(b.sortOrder);
      });
  final activeTodayTodos = activeToday.length;
  final top3 = activeToday.take(3).map((e) => e.title).toList();
  final top3Ids = activeToday.take(3).map((e) => e.id).toList();
  final habitPercent = (h.todayCompletionRate * 100).round();
  await HomeWidgetService.push(
    todoCount: activeTodayTodos,
    habitPercent: habitPercent,
    pomodoroToday: p.sessionCountToday,
    strings: tp.brand.strings,
    todoTop3: top3,
    todoTop3Ids: top3Ids,
    todayEventSummary: top3.isEmpty ? '今日没有日程' : '今日：${top3.first}',
  );
}

Future<void> _syncDailyDigestReminder(
  PreferencesProvider prefs,
  NotificationService notification,
  TodoProvider todos,
) async {
  const baseId = 880017;
  for (var i = 0; i < 3; i++) {
    await notification.cancel(baseId + i);
  }

  final now = DateTime.now();
  for (var i = 0; i < prefs.dailyReminderSlots.length; i++) {
    final slot = prefs.dailyReminderSlots[i];
    if (!slot.enabled) continue;
    final target = _nextDailyReminderTime(now, slot);
    final body = _dailyDigestBody(now, todos, slot);

    await notification.scheduleOnce(
      id: baseId + i,
      title: '每日提醒${['一', '二', '三'][i]}',
      body: body,
      when: target,
      payload: 'duoyi://tab/today',
    );
  }
}

DateTime _nextDailyReminderTime(DateTime now, DailyReminderSlot slot) {
  var target = DateTime(now.year, now.month, now.day, slot.hour, slot.minute);
  if (!target.isAfter(now)) target = target.add(const Duration(days: 1));

  for (var i = 0; i < 14; i++) {
    final weekdayAllowed = slot.repeatDays.contains(target.weekday);
    final holidayPaused =
        slot.pauseHolidays && HolidayCalendar.isHoliday(target);
    if (weekdayAllowed && !holidayPaused) break;
    target = target.add(const Duration(days: 1));
  }
  return target;
}

String _dailyDigestBody(
  DateTime now,
  TodoProvider todos,
  DailyReminderSlot slot,
) {
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));
  final todayCount = todos.todos.where((t) {
    final d = DateTime(t.date.year, t.date.month, t.date.day);
    return d.isAtSameMomentAs(today) && !t.isCompleted;
  }).length;
  final tomorrowCount = todos.todos.where((t) {
    final d = DateTime(t.date.year, t.date.month, t.date.day);
    return d.isAtSameMomentAs(tomorrow) && !t.isCompleted;
  }).length;
  final overdueCount = todos.todos.where((t) => t.isOverdue).length;

  final pieces = <String>[];
  if (slot.includeTodayTasks) pieces.add('今日 $todayCount 项');
  if (slot.includeTomorrowPlan) pieces.add('明日 $tomorrowCount 项');
  if (slot.includeOverdue) pieces.add('逾期 $overdueCount 项');
  return pieces.isEmpty ? '打开多仪整理任务与计划' : pieces.join(' · ');
}

void _handleWidgetUri(Uri? uri, PomodoroProvider pomodoro) {
  if (uri == null) return;
  if (uri.scheme != 'duoyi') return;

  final state = mainShellKey.currentState;
  final ctx = mainShellKey.currentContext;

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
  } else if (uri.host == 'todo' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (id == null || id.isEmpty) return;
    final confirm = uri.queryParameters['confirm'] == '1';
    if (confirm) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showTodoCompletePrompt(ctx, id);
      });
    } else {
      // ignore: discarded_futures
      TodayDetailRouter.open(ctx, TodaySectionKind.todos, id: id);
    }
  } else if (uri.host == 'goal' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (id == null || id.isEmpty) return;
    // ignore: discarded_futures
    TodayDetailRouter.open(ctx, TodaySectionKind.goals, id: id);
  } else if (uri.host == 'habit' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    state?.navigateTo(2);
    if (id == null || id.isEmpty) return;
    final confirm = uri.queryParameters['confirm'] == '1';
    if (confirm) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showHabitCheckInPrompt(ctx, id);
      });
    } else {
      // ignore: discarded_futures
      TodayDetailRouter.open(ctx, TodaySectionKind.habits, id: id);
    }
  } else if (uri.host == 'countdown') {
    state?.navigateTo(3);
  } else if (uri.host == 'action') {
    final action = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    if (action == 'start_pomodoro') {
      state?.navigateTo(4);
      if (!pomodoro.state.isRunning) pomodoro.toggleTimer();
    } else if (action == 'complete_todo' && ctx != null) {
      final id = uri.queryParameters['id'];
      if (id == null || id.isEmpty) return;
      final todos = Provider.of<TodoProvider>(ctx, listen: false);
      final target = todos.todos.where((todo) => todo.id == id).firstOrNull;
      if (target == null || target.isCompleted) return;
      // ignore: discarded_futures
      todos.toggleTodo(id);
    }
  }
}

Future<void> _showTodoCompletePrompt(
  BuildContext context,
  String todoId,
) async {
  if (!context.mounted) return;
  final todos = Provider.of<TodoProvider>(context, listen: false);
  final todo = todos.todos.where((t) => t.id == todoId).firstOrNull;
  final messenger = ScaffoldMessenger.of(context);
  if (todo == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('这个任务不存在或已被删除'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }
  if (todo.isCompleted) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('“${todo.title}”已经完成'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AppDialog(
      icon: const Icon(Icons.task_alt_outlined),
      title: const Text('确认完成任务'),
      content: Text('现在完成“${todo.title}”吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(false),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogCtx).pop(true),
          child: const Text('完成'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await todos.toggleTodo(todoId);
  if (!context.mounted) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text('已完成：${todo.title}'),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

Future<void> _showHabitCheckInPrompt(
  BuildContext context,
  String habitId,
) async {
  if (!context.mounted) return;
  final habits = Provider.of<HabitProvider>(context, listen: false);
  final habit = habits.habits.where((h) => h.id == habitId).firstOrNull;
  final messenger = ScaffoldMessenger.of(context);
  if (habit == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('这个习惯不存在或已被删除'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }
  if (habit.isCompletedToday()) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('“${habit.name}”今天已经完成'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AppDialog(
      icon: const Icon(Icons.check_circle_outline),
      title: const Text('确认打卡'),
      content: Text('现在完成“${habit.name}”吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(false),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogCtx).pop(true),
          child: const Text('完成打卡'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await habits.incrementHabit(habitId);
  if (!context.mounted) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text('已打卡：${habit.name}'),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

extension _FirstOrNullMainX<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) return iterator.current;
    return null;
  }
}

class DuoyiApp extends StatefulWidget {
  const DuoyiApp({super.key});

  @override
  State<DuoyiApp> createState() => _DuoyiAppState();
}

class _DuoyiAppState extends State<DuoyiApp> with WidgetsBindingObserver {
  /// 缓存上一次已知的"本地日"，用于在 resumed 时判定是否跨天。
  /// 初始值写入于 [initState]。
  DateTime? _lastLifecycleDay;

  /// 缓存上一次已知的系统 IANA 时区名。
  ///
  /// 在 [initState] 初始化为 `LocalTimezoneResolver.currentIana`；
  /// 之后每次 `AppLifecycleState.resumed` 都会先刷新时区再与此值比较，
  /// 差异即触发 [ReminderScheduler.resyncAll]（Requirements 8.6 / 8.8）。
  String? _lastIana;
  bool? _lastExactAlarmGranted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = DateTime.now();
    _lastLifecycleDay = DateTime(now.year, now.month, now.day);
    _lastIana = LocalTimezoneResolver.currentIana;
    _lastExactAlarmGranted = _initialExactAlarmGranted;
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
      // 先处理时区变更（可能影响调度），再做跨日 rollover。
      _maybeResyncOnTimezoneChange();
      _maybeRunDailyRolloverOnResume();
      _refreshNotificationPermissionsOnResume();
    }
  }

  /// 检测系统时区在后台是否被修改；若有变化则刷新 `tz.local` 并触发
  /// [ReminderScheduler.resyncAll]，保证壁钟时间不变。
  ///
  /// 对应 Requirements 8.6 / 8.8：
  /// - 8.6：resumed 且 IANA 变化时重新 `tz.setLocalLocation` 并 resync；
  /// - 8.8：resync 后新调度的 `(hour, minute)` 仍等于用户原设定。
  void _maybeResyncOnTimezoneChange() {
    // 从 mainShellKey.currentContext（冷启动早期可能为 null）或当前 context
    // 同步读取 Provider，避免异步 gap 之后再使用 BuildContext。
    final ctx = mainShellKey.currentContext ?? context;
    final todos = Provider.of<TodoProvider>(ctx, listen: false);
    final habits = Provider.of<HabitProvider>(ctx, listen: false);
    final annis = Provider.of<AnniversaryProvider>(ctx, listen: false);
    final goals = Provider.of<GoalProvider>(ctx, listen: false);
    final countdowns = Provider.of<CountdownProvider>(ctx, listen: false);

    final prevIana = _lastIana;

    // ignore: discarded_futures
    Future.microtask(() async {
      try {
        await LocalTimezoneResolver.refresh();
      } catch (_) {
        // 时区刷新失败（例如平台暂时不可用）不应阻断其它 lifecycle 钩子。
        return;
      }
      final currentIana = LocalTimezoneResolver.currentIana;
      if (prevIana != null && prevIana == currentIana) {
        return;
      }
      _lastIana = currentIana;
      try {
        await _reminderScheduler.resyncAll(
          todos: todos.todos,
          habits: habits.habits,
          annis: annis.items,
          goals: goals.goals,
          countdowns: countdowns.items,
        );
      } catch (e, st) {
        debugPrint('[DuoyiApp] resyncAll on timezone change failed: $e\n$st');
      }
    });
  }

  /// 从系统设置返回时刷新通知 / 闹钟权限状态。
  ///
  /// 若通知权限或精准闹钟权限发生变化，则重放一轮提醒调度，保证
  /// 现有提醒使用最新的系统授权状态。
  void _refreshNotificationPermissionsOnResume() {
    final ctx = mainShellKey.currentContext ?? context;
    final notif = Provider.of<NotificationService>(ctx, listen: false);
    final todos = Provider.of<TodoProvider>(ctx, listen: false);
    final habits = Provider.of<HabitProvider>(ctx, listen: false);
    final annis = Provider.of<AnniversaryProvider>(ctx, listen: false);
    final goals = Provider.of<GoalProvider>(ctx, listen: false);
    final countdowns = Provider.of<CountdownProvider>(ctx, listen: false);

    final prevNotifGranted = notif.permissionGranted;
    final prevExactGranted = _lastExactAlarmGranted;

    // ignore: discarded_futures
    Future.microtask(() async {
      try {
        final notifGranted = await notif.refreshPermission();
        final exactGranted = await AlarmService.instance
            .hasExactAlarmPermission();
        _lastExactAlarmGranted = exactGranted;
        final exactChanged =
            prevExactGranted != null && prevExactGranted != exactGranted;
        if (prevNotifGranted == notifGranted && !exactChanged) return;
        await _reminderScheduler.resyncAll(
          todos: todos.todos,
          habits: habits.habits,
          annis: annis.items,
          goals: goals.goals,
          countdowns: countdowns.items,
        );
      } catch (e, st) {
        debugPrint('[DuoyiApp] refresh permission/resync failed: $e\n$st');
      }
    });
  }

  /// 当 App 从后台回到前台时，若"本地日"发生变化则触发一次
  /// [CompletionVisibilityPolicy.runDailyRollover]。
  ///
  /// 调用路径对应 `requirements.md` 3.3：滚动归档必须在进程复用的长时间
  /// 后台场景下也能按时执行。时区刷新由 [_maybeResyncOnTimezoneChange]
  /// 负责，不在这里重复。
  void _maybeRunDailyRolloverOnResume() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last = _lastLifecycleDay;
    _lastLifecycleDay = today;
    if (last != null && last.isAtSameMomentAs(today)) {
      return;
    }

    // 同步读取 TodoProvider / GoalProvider，避免在异步 gap 之后再使用 BuildContext。
    // `DuoyiApp` 是应用根 widget，`mainShellKey` 在冷启动初期可能尚未 attach，
    // 两处都位于 MultiProvider 之下，任一命中即可拿到实例。
    final ctx = mainShellKey.currentContext ?? context;
    final provider = Provider.of<TodoProvider>(ctx, listen: false);
    final goalProv = Provider.of<GoalProvider>(ctx, listen: false);
    final prefs = Provider.of<PreferencesProvider>(ctx, listen: false);
    final notif = Provider.of<NotificationService>(ctx, listen: false);

    // 异步触发，不阻塞 lifecycle 回调。
    // ignore: discarded_futures
    Future.microtask(() async {
      await CompletionVisibilityPolicy.runDailyRollover(
        provider,
        now,
        goalProvider: goalProv,
      );
      await _syncDailyDigestReminder(prefs, notif, provider);
    });
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
    final prefs = context.watch<PreferencesProvider>();
    final visibleTabs = prefs.enabledBottomNavTabs;
    if (!visibleTabs.contains(_currentIndex)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _currentIndex = visibleTabs.first);
      });
    }
    final allDestinations = [
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
    final destinations = visibleTabs.map((i) => allDestinations[i]).toList();
    final selectedNavIndex = visibleTabs.indexOf(_currentIndex);

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
      floatingActionButton: _currentIndex == 0 && prefs.quickCaptureFab
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedNavIndex < 0 ? 0 : selectedNavIndex,
        onDestinationSelected: (i) =>
            setState(() => _currentIndex = visibleTabs[i]),
        destinations: destinations,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }
}
