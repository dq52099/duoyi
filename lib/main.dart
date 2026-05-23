import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/app_version.dart';
import 'core/achievements.dart';
import 'core/completion_visibility_policy.dart';
import 'core/i18n.dart';
import 'core/iterable_extensions.dart';
import 'core/local_timezone_resolver.dart';
import 'core/report_engine.dart';
import 'core/smart_date_parser.dart';
import 'core/smart_todo_draft.dart';
import 'l10n/generated/app_localizations.dart';
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
import 'providers/quick_capture_template_provider.dart';
import 'providers/time_audit_provider.dart';
import 'providers/achievement_provider.dart';
import 'providers/custom_focus_sound_provider.dart';
import 'providers/focus_room_provider.dart';
import 'providers/share_provider.dart';
import 'providers/location_reminder_provider.dart';
import 'models/goal.dart' show GoalStatus;
import 'models/habit.dart' show HabitKind;
import 'models/calendar_event.dart'
    show CalendarEvent, CalendarEventType, CalendarEventTypeX;
import 'models/note.dart' show NoteItem;
import 'models/pomodoro.dart' show PomodoroType;
import 'models/todo.dart' show TodoPriorityX;
import 'services/alarm_service.dart';
import 'services/calendar_sync_service.dart';
import 'services/deep_link_service.dart';
import 'services/system_tray.dart';
import 'services/home_widget_service.dart';
import 'services/ai_service.dart';
import 'services/app_update_service.dart';
import 'services/backend_reminder_email_sink.dart';
import 'services/holiday_calendar.dart';
import 'services/local_notifications.dart';
import 'services/location_geofence_service.dart';
import 'services/notification_permission_exception.dart';
import 'services/reminder_ringtone_settings.dart';
import 'services/reminder_scheduler.dart';
import 'screens/today_screen.dart';
import 'screens/todo_screen.dart';
import 'screens/habit_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/pomodoro_screen.dart';
import 'screens/widget_screen.dart';
import 'screens/mine_screen.dart';
import 'screens/integrations_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/search_screen.dart';
import 'screens/note_screen.dart';
import 'screens/statistics_screen.dart';
import 'screens/today_detail_router.dart';
import 'widgets/brand_background.dart';
import 'widgets/quick_capture_fab.dart';
import 'widgets/todo_completion_flow.dart';
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

String _pomodoroPersistedSignature(PomodoroProvider provider) {
  return '${provider.persistedRevision}:${provider.sessions.length}:'
      '${provider.penalties.length}:${provider.sessionCountToday}';
}

String _achievementPersistedSignature(AchievementProvider provider) {
  return '${provider.persistedRevision}:${provider.unlockedCount}:'
      '${provider.coinBalance}:${provider.lifetimeCoins}:'
      '${provider.rewardLedger.length}';
}

String _pomodoroSessionsSignature(PomodoroProvider provider) {
  final buffer = StringBuffer()
    ..write(provider.sessions.length)
    ..write(':')
    ..write(provider.sessionCountToday)
    ..write(':')
    ..write(provider.totalFocusMinutes);
  for (final session in provider.sessions) {
    buffer
      ..write('|')
      ..write(session.id)
      ..write(',')
      ..write(session.type.index)
      ..write(',')
      ..write(session.durationSeconds)
      ..write(',')
      ..write(session.updatedAt.microsecondsSinceEpoch);
  }
  return buffer.toString();
}

String _pomodoroHomeWidgetSignature(PomodoroProvider provider) {
  final state = provider.state;
  final remaining = state.isRunning ? 'active' : state.remainingSeconds;
  return '${provider.persistedRevision}:${provider.sessionCountToday}:'
      '${state.isRunning}:${state.isCountUp}:${state.type.index}:'
      '${state.totalSeconds}:$remaining';
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
  final quickCaptureTemplateProvider = QuickCaptureTemplateProvider();
  final timeAuditProvider = TimeAuditProvider();
  final achievementProvider = AchievementProvider();
  final customFocusSoundProvider = CustomFocusSoundProvider();
  final focusRoomProvider = FocusRoomProvider();
  final shareProvider = ShareProvider();
  final localeProvider = LocaleProvider();
  final locationReminderProvider = LocationReminderProvider();
  final calendarSyncProvider = CalendarSyncProvider();
  final aiService = AiService();
  final appUpdate = AppUpdateService(
    repo: 'dq52099/duoyi',
    currentVersion: AppVersion.name,
  );

  String firstNonEmptyProfileText(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  authProvider.onAccountProfileChanged = (state) async {
    final name = firstNonEmptyProfileText([
      state.displayName,
      state.username,
      '用户',
    ]);
    await userProvider.updateProfile(
      username: name,
      displayName: state.displayName ?? '',
      email: state.email ?? '',
      emailVerified: state.emailVerified,
      avatarUrl: state.avatar ?? '',
      bio: state.bio ?? '',
    );
  };
  authProvider.onAccountLoggedOut = () =>
      userProvider.clearAccountProfileCache();

  void handleDeepLink(Uri uri) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleWidgetUri(uri, pomodoroProvider);
    });
  }

  void handleSharedText(String text) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showSharedTextImportSheet(text);
    });
  }

  DeepLinkService.onLink = handleDeepLink;
  DeepLinkService.onSharedText = handleSharedText;
  await _startupGuard('deep links', () => DeepLinkService.init());

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
      'quick capture templates storage',
      () => quickCaptureTemplateProvider.loadFromStorage(),
    ),
    _startupGuard(
      'time audit storage',
      () => timeAuditProvider.loadFromStorage(),
    ),
    _startupGuard(
      'achievement storage',
      () => achievementProvider.loadFromStorage(),
    ),
    _startupGuard(
      'custom focus sounds storage',
      () => customFocusSoundProvider.loadFromStorage(),
    ),
    _startupGuard(
      'focus room storage',
      () => focusRoomProvider.loadFromStorage(),
    ),
    _startupGuard('notifications', () => notificationService.init()),
    _startupGuard('system tray', () => systemTray.init()),
    _startupGuard('home widget', () => HomeWidgetService.init()),
    _startupGuard('auth storage', () => authProvider.loadFromStorage()),
    _startupGuard('ai storage', () => aiService.loadFromStorage()),
    _startupGuard('locale storage', () => localeProvider.loadFromStorage()),
    _startupGuard(
      'location reminders storage',
      () => locationReminderProvider.loadFromStorage(),
    ),
    _startupGuard(
      'calendar subscriptions storage',
      () => calendarSyncProvider.loadFromStorage(),
    ),
    _startupGuard(
      'calendar local events',
      () => calendarProvider.loadFromStorage(),
    ),
  ]);

  await _startupGuard('auth profile refresh', () => authProvider.refreshMe());

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
  focusRoomProvider.apiClientGetter = () => authProvider.client;
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
  final reminderScheduler = ReminderScheduler(
    notificationService,
    email: BackendReminderEmailSink(() => authProvider.client),
  );
  _reminderScheduler = reminderScheduler;
  // 注入到 Provider，供 Provider 内部的局部 hook（例如 postponeOverdue、
  // onTimezoneChanged）转发调度请求。
  todoProvider.scheduler = reminderScheduler;
  goalProvider.scheduler = reminderScheduler;
  Future<void> resyncReminders() async {
    // 单条 sync 失败不应中断整轮调度（R2.8 / T-14）。
    Future<void> guarded(String label, Future<void> Function() task) async {
      try {
        await task();
      } catch (e, st) {
        debugPrint('[resyncReminders] $label failed: $e\n$st');
      }
    }

    await guarded(
      'syncTodos',
      () => reminderScheduler.syncTodos(todoProvider.todos),
    );
    await guarded(
      'syncHabits',
      () => reminderScheduler.syncHabits(habitProvider.habits),
    );
    await guarded(
      'syncAnniversaries',
      () => reminderScheduler.syncAnniversaries(anniversaryProvider.items),
    );
    await guarded(
      'syncGoals',
      () => reminderScheduler.syncGoals(goalProvider.goals),
    );
    await guarded(
      'syncCountdowns',
      () => reminderScheduler.syncCountdowns(countdownProvider.items),
    );
  }

  todoProvider.addListener(resyncReminders);
  habitProvider.addListener(resyncReminders);
  anniversaryProvider.addListener(resyncReminders);
  goalProvider.addListener(resyncReminders);
  countdownProvider.addListener(resyncReminders);
  await notificationService.setHistoryLimit(
    preferencesProvider.notificationHistoryLimit,
  );
  preferencesProvider.onAppTimeZoneChanged = resyncReminders;

  Future<void> syncLocationGeofences() async {
    try {
      await LocationGeofenceService.syncReminders(
        locationReminderProvider.reminders,
      );
    } catch (e, st) {
      debugPrint('[location geofence] sync failed: $e\n$st');
    }
  }

  locationReminderProvider.addListener(syncLocationGeofences);
  // ignore: discarded_futures
  syncLocationGeofences();

  // 本地有改动 → 交给云同步侧排队自动同步。
  void markDirty() {
    cloudSyncProvider.markPendingLocalChange();
  }

  todoProvider.addListener(markDirty);
  habitProvider.addListener(markDirty);
  anniversaryProvider.addListener(markDirty);
  goalProvider.addListener(markDirty);
  noteProvider.addListener(markDirty);
  countdownProvider.addListener(markDirty);
  diaryProvider.addListener(markDirty);
  courseProvider.addListener(markDirty);
  var lastPomodoroDirtySignature = _pomodoroPersistedSignature(
    pomodoroProvider,
  );
  void markPomodoroDirtyOnPersistedChange() {
    final next = _pomodoroPersistedSignature(pomodoroProvider);
    if (next == lastPomodoroDirtySignature) return;
    lastPomodoroDirtySignature = next;
    markDirty();
  }

  pomodoroProvider.addListener(markPomodoroDirtyOnPersistedChange);
  timeAuditProvider.addListener(markDirty);
  userProvider.addListener(markDirty);
  locationReminderProvider.addListener(markDirty);
  var lastAchievementDirtySignature = _achievementPersistedSignature(
    achievementProvider,
  );
  void markAchievementDirtyOnPersistedChange() {
    final next = _achievementPersistedSignature(achievementProvider);
    if (next == lastAchievementDirtySignature) return;
    lastAchievementDirtySignature = next;
    markDirty();
  }

  achievementProvider.addListener(markAchievementDirtyOnPersistedChange);
  focusRoomProvider.onLocalChanged = markDirty;
  themeProvider.addListener(markDirty);
  calendarProvider.onLocalEventsChanged = markDirty;
  preferencesProvider.onChangedKeys = cloudSyncProvider.markPreferencesChanged;
  ReminderRingtoneSettings.onChanged = cloudSyncProvider.markPreferencesChanged;
  quickCaptureTemplateProvider.addListener(
    cloudSyncProvider.markQuickCaptureTemplatesChanged,
  );

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
  var lastPomodoroStatsSignature = _pomodoroSessionsSignature(pomodoroProvider);
  void refreshUserStatsOnPomodoroSummaryChange() {
    final next = _pomodoroSessionsSignature(pomodoroProvider);
    if (next == lastPomodoroStatsSignature) return;
    lastPomodoroStatsSignature = next;
    refreshUserStats();
  }

  pomodoroProvider.addListener(refreshUserStatsOnPomodoroSummaryChange);

  bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool isInRange(DateTime date, DateTime start, DateTime end) =>
      !date.isBefore(start) && date.isBefore(end);

  String dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  void refreshAchievements() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final activeDays = <String>{};

    final todayCompletedTodos = todoProvider.todos.where((todo) {
      if (!todo.isCompleted) return false;
      final completedAt = todo.completedAt ?? todo.date;
      return isSameDay(completedAt, today);
    }).length;
    final weeklyCompletedTodos = todoProvider.todos.where((todo) {
      if (!todo.isCompleted) return false;
      final completedAt = todo.completedAt ?? todo.date;
      final inWeek = isInRange(completedAt, weekStart, weekEnd);
      if (inWeek) activeDays.add(dateKey(completedAt));
      return inWeek;
    }).length;

    final todayHabitCheckIns = habitProvider.habits
        .where((habit) => habit.activeForDate(today))
        .fold<int>(0, (sum, habit) => sum + habit.countForDate(today));
    var weeklyHabitCheckIns = 0;
    for (final habit in habitProvider.habits) {
      for (final entry in habit.completions.entries) {
        final date = DateTime.tryParse(entry.key);
        if (date == null || !isInRange(date, weekStart, weekEnd)) continue;
        if (!habit.activeForDate(date)) continue;
        weeklyHabitCheckIns += entry.value;
        if (entry.value > 0) activeDays.add(dateKey(date));
      }
    }

    final focusSessions = pomodoroProvider.sessions.where(
      (session) => session.type == PomodoroType.focus,
    );
    final todayFocusMinutes =
        focusSessions
            .where((session) => isInRange(session.endTime, today, tomorrow))
            .fold<int>(0, (sum, session) => sum + session.durationSeconds) ~/
        60;
    final weeklyFocusMinutes =
        focusSessions
            .where((session) {
              final inWeek = isInRange(session.endTime, weekStart, weekEnd);
              if (inWeek) activeDays.add(dateKey(session.endTime));
              return inWeek;
            })
            .fold<int>(0, (sum, session) => sum + session.durationSeconds) ~/
        60;

    final todayDiaryEntries = diaryProvider.entries
        .where((entry) => isSameDay(entry.date, today))
        .length;
    final weeklyDiaryEntries = diaryProvider.entries.where((entry) {
      final inWeek = isInRange(entry.date, weekStart, weekEnd);
      if (inWeek) activeDays.add(dateKey(entry.date));
      return inWeek;
    }).length;

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
        todayCompletedTodos: todayCompletedTodos,
        todayHabitCheckIns: todayHabitCheckIns,
        todayFocusMinutes: todayFocusMinutes,
        todayDiaryEntries: todayDiaryEntries,
        weeklyCompletedTodos: weeklyCompletedTodos,
        weeklyHabitCheckIns: weeklyHabitCheckIns,
        weeklyFocusMinutes: weeklyFocusMinutes,
        weeklyDiaryEntries: weeklyDiaryEntries,
        weeklyActiveDays: activeDays.length,
      ),
    );
  }

  todoProvider.addListener(refreshAchievements);
  habitProvider.addListener(refreshAchievements);
  var lastPomodoroAchievementSignature = _pomodoroSessionsSignature(
    pomodoroProvider,
  );
  void refreshAchievementsOnPomodoroSummaryChange() {
    final next = _pomodoroSessionsSignature(pomodoroProvider);
    if (next == lastPomodoroAchievementSignature) return;
    lastPomodoroAchievementSignature = next;
    refreshAchievements();
  }

  pomodoroProvider.addListener(refreshAchievementsOnPomodoroSummaryChange);
  diaryProvider.addListener(refreshAchievements);
  goalProvider.addListener(refreshAchievements);
  anniversaryProvider.addListener(refreshAchievements);
  courseProvider.addListener(refreshAchievements);
  noteProvider.addListener(refreshAchievements);
  themeProvider.addListener(refreshAchievements);
  // 初次同步
  await _startupGuard('initial reminder resync', resyncReminders);

  // 启动后异步刷新订阅日历（不阻塞冷启动）。
  // ignore: discarded_futures
  Future.microtask(() => calendarSyncProvider.syncAll());

  // 订阅日历变化 → 写入 CalendarProvider 的外部事件，下次 rebuild 合并显示。
  void onCalendarSyncChange() {
    calendarProvider.setExternalEvents(calendarSyncProvider.allEvents());
  }

  calendarSyncProvider.addListener(onCalendarSyncChange);
  onCalendarSyncChange();
  Future<void> syncDailyDigestReminder() => _syncDailyDigestReminder(
    preferencesProvider,
    notificationService,
    todoProvider,
  );
  Future<void> syncReportDigestReminders() => _syncReportDigestReminders(
    preferencesProvider,
    notificationService,
    todos: todoProvider,
    habits: habitProvider,
    pomodoros: pomodoroProvider,
    timeAudit: timeAuditProvider,
  );
  Timer? reportDigestSyncDebounce;
  void queueReportDigestReminderSync() {
    reportDigestSyncDebounce?.cancel();
    reportDigestSyncDebounce = Timer(const Duration(seconds: 2), () {
      // ignore: discarded_futures
      syncReportDigestReminders();
    });
  }

  Future<void> syncNotificationQuickAdd() =>
      _syncNotificationQuickAdd(preferencesProvider);
  preferencesProvider.addListener(syncDailyDigestReminder);
  preferencesProvider.addListener(syncReportDigestReminders);
  preferencesProvider.addListener(syncNotificationQuickAdd);
  todoProvider.addListener(syncDailyDigestReminder);
  todoProvider.addListener(queueReportDigestReminderSync);
  habitProvider.addListener(queueReportDigestReminderSync);
  var lastPomodoroReportSignature = _pomodoroSessionsSignature(
    pomodoroProvider,
  );
  void queueReportDigestReminderSyncOnPomodoroSummaryChange() {
    final next = _pomodoroSessionsSignature(pomodoroProvider);
    if (next == lastPomodoroReportSignature) return;
    lastPomodoroReportSignature = next;
    queueReportDigestReminderSync();
  }

  pomodoroProvider.addListener(
    queueReportDigestReminderSyncOnPomodoroSummaryChange,
  );
  timeAuditProvider.addListener(queueReportDigestReminderSync);
  await _startupGuard('daily digest reminder', syncDailyDigestReminder);
  await _startupGuard('report digest reminders', syncReportDigestReminders);
  await _startupGuard('notification quick add', syncNotificationQuickAdd);
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
    focusRoomProvider.apiClientGetter = () => authProvider.client;
  });
  if (authProvider.serverConfig.isNotEmpty) {
    aiService.updateFromServerConfig(authProvider.serverConfig);
  }

  cloudSyncProvider.onSynced = (changedCollections) async {
    // 同步完成后服务端回写可能覆盖本地数据；这段 reload 不应被当作"脏改动"。
    await cloudSyncProvider.suppressDirtyMarkWhile(() async {
      final futures = <Future<void>>[];
      var shouldResyncReminders = false;

      if (changedCollections.contains('todos')) {
        futures.add(todoProvider.loadFromStorage());
        shouldResyncReminders = true;
      }
      if (changedCollections.contains('habits')) {
        futures.add(habitProvider.loadFromStorage());
        shouldResyncReminders = true;
      }
      if (changedCollections.contains('pomodoro_sessions') ||
          changedCollections.contains('focus_penalties') ||
          changedCollections.contains('pomodoro_config')) {
        futures.add(pomodoroProvider.loadFromStorage());
      }
      if (changedCollections.contains('countdowns')) {
        futures.add(countdownProvider.loadFromStorage());
        shouldResyncReminders = true;
      }
      if (changedCollections.contains('notes')) {
        futures.add(noteProvider.loadFromStorage());
      }
      if (changedCollections.contains('anniversaries')) {
        futures.add(anniversaryProvider.loadFromStorage());
        shouldResyncReminders = true;
      }
      if (changedCollections.contains('diaries')) {
        futures.add(diaryProvider.loadFromStorage());
      }
      if (changedCollections.contains('goals')) {
        futures.add(goalProvider.loadFromStorage());
        shouldResyncReminders = true;
      }
      if (changedCollections.contains('courses') ||
          changedCollections.contains('course_settings')) {
        futures.add(courseProvider.loadFromStorage());
      }
      if (changedCollections.contains('calendar_events')) {
        futures.add(calendarProvider.loadFromStorage());
        shouldResyncReminders = true;
      }
      if (changedCollections.contains('user_profile')) {
        futures.add(userProvider.loadFromStorage());
      }
      if (changedCollections.contains('time_entries')) {
        futures.add(timeAuditProvider.loadFromStorage());
      }
      if (changedCollections.contains('location_reminders')) {
        futures.add(locationReminderProvider.loadFromStorage());
      }
      if (changedCollections.contains('achievement_states') ||
          changedCollections.contains('virtual_rewards')) {
        futures.add(achievementProvider.loadFromStorage());
      }
      if (changedCollections.contains('focus_rooms')) {
        futures.add(focusRoomProvider.loadFromStorage());
      }
      if (changedCollections.contains('theme_shop_state')) {
        futures.add(themeProvider.loadFromStorage());
      }
      if (changedCollections.contains('preferences')) {
        futures.add(preferencesProvider.loadFromStorage());
        shouldResyncReminders = true;
      }
      if (changedCollections.contains('quick_capture_templates')) {
        futures.add(quickCaptureTemplateProvider.loadFromStorage());
      }

      await Future.wait(futures);

      if (changedCollections.contains('user_profile')) {
        // 云同步回写本地资料后，再拉一次账号资料，保证其它设备改过的
        // 昵称、头像、邮箱验证状态等账号字段能覆盖本地展示缓存。
        await authProvider.refreshMe();
      }
      if (changedCollections.contains('workspace_payloads')) {
        await shareProvider.load();
      }
      if (changedCollections.contains('preferences')) {
        await ReminderRingtoneSettings.applyPersistedSettingsToNative();
      }
      if (changedCollections.contains('location_reminders')) {
        await syncLocationGeofences();
      }
      // 拉取云端后可能覆盖了本地 reminder，也要重跑一次
      if (shouldResyncReminders) {
        await resyncReminders();
      }
    });
  };

  authProvider.addListener(() {
    shareProvider.load();
    if (authProvider.state.isLoggedIn && cloudSyncProvider.config.autoSync) {
      // ignore: discarded_futures
      unawaited(cloudSyncProvider.syncNow());
      cloudSyncProvider.startRemotePolling();
    } else {
      cloudSyncProvider.stopRemotePolling();
    }
  });
  if (authProvider.state.isLoggedIn) {
    shareProvider.load();
  }
  if (authProvider.state.isLoggedIn && cloudSyncProvider.config.autoSync) {
    // ignore: discarded_futures
    unawaited(cloudSyncProvider.syncNow());
    cloudSyncProvider.startRemotePolling();
  }

  Future<void> pushHomeWidgetNow() => _pushHomeWidget(
    todoProvider,
    habitProvider,
    pomodoroProvider,
    calendarProvider,
    countdownProvider,
    timeAuditProvider,
    goalProvider,
    anniversaryProvider,
    courseProvider,
    noteProvider,
    diaryProvider,
    themeProvider,
  );

  Timer? homeWidgetPushDebounce;
  void queueHomeWidgetPush() {
    homeWidgetPushDebounce?.cancel();
    homeWidgetPushDebounce = Timer(const Duration(milliseconds: 800), () {
      // ignore: discarded_futures
      pushHomeWidgetNow();
    });
  }

  notificationService.setStrings(themeProvider.brand.strings);
  themeProvider.addListener(() {
    notificationService.setStrings(themeProvider.brand.strings);
    queueHomeWidgetPush();
  });

  systemTray.onActivate.listen((action) {
    if (action == 'pomodoro_quick_start') pomodoroProvider.startIfIdle();
  });

  void onDataChange() => queueHomeWidgetPush();
  var lastPomodoroHomeWidgetSignature = _pomodoroHomeWidgetSignature(
    pomodoroProvider,
  );
  void onPomodoroHomeWidgetChange() {
    final next = _pomodoroHomeWidgetSignature(pomodoroProvider);
    if (next == lastPomodoroHomeWidgetSignature) return;
    lastPomodoroHomeWidgetSignature = next;
    queueHomeWidgetPush();
  }

  todoProvider.addListener(onDataChange);
  habitProvider.addListener(onDataChange);
  pomodoroProvider.addListener(onPomodoroHomeWidgetChange);
  countdownProvider.addListener(onDataChange);
  timeAuditProvider.addListener(onDataChange);
  goalProvider.addListener(onDataChange);
  anniversaryProvider.addListener(onDataChange);
  courseProvider.addListener(onDataChange);
  noteProvider.addListener(onDataChange);
  diaryProvider.addListener(onDataChange);

  await _startupGuard('initial home widget push', pushHomeWidgetNow);

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
  final initialDeepLink = await _startupValue<Uri>(
    'deep link initial launch',
    () => DeepLinkService.takeInitialLink(),
  );
  final initialOAuthLink = await _startupValue<Uri>(
    'deep link initial oauth',
    () => DeepLinkService.takeInitialOAuthLink(),
  );
  final initialSharedText = await _startupValue<String>(
    'deep link initial shared text',
    () => DeepLinkService.takeInitialSharedText(),
  );
  if (initial != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleWidgetUri(initial, pomodoroProvider);
    });
  }
  if (initialDeepLink != null &&
      initialDeepLink.toString() != initial?.toString()) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleWidgetUri(initialDeepLink, pomodoroProvider);
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
        ChangeNotifierProvider.value(value: quickCaptureTemplateProvider),
        ChangeNotifierProvider.value(value: timeAuditProvider),
        ChangeNotifierProvider.value(value: achievementProvider),
        ChangeNotifierProvider.value(value: customFocusSoundProvider),
        ChangeNotifierProvider.value(value: focusRoomProvider),
        ChangeNotifierProvider.value(value: shareProvider),
        ChangeNotifierProvider.value(value: localeProvider),
        ChangeNotifierProvider.value(value: locationReminderProvider),
        ChangeNotifierProvider.value(value: calendarSyncProvider),
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
  if (initialOAuthLink != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleWidgetUri(initialOAuthLink, pomodoroProvider);
    });
  }
  if (initialSharedText != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showSharedTextImportSheet(initialSharedText);
    });
  }
}

Future<void> _pushHomeWidget(
  TodoProvider t,
  HabitProvider h,
  PomodoroProvider p,
  CalendarProvider cal,
  CountdownProvider countdowns,
  TimeAuditProvider timeAudit,
  GoalProvider g,
  AnniversaryProvider a,
  CourseProvider c,
  NoteProvider n,
  DiaryProvider d,
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
  final quickCheckHabits =
      h.habits
          .where(
            (habit) =>
                habit.kind == HabitKind.positive &&
                habit.isActiveToday() &&
                !habit.isCompletedToday(),
          )
          .toList()
        ..sort((a, b) {
          final order = a.sortOrder.compareTo(b.sortOrder);
          if (order != 0) return order;
          return a.createdAt.compareTo(b.createdAt);
        });
  final quickCheckHabit = quickCheckHabits.firstOrNull;
  final activeGoalItems = g.activeGoals.take(3).toList();
  final goalHighlights = activeGoalItems
      .map(
        (goal) => '${goal.title} · ${(goal.computedProgress * 100).round()}%',
      )
      .toList();
  final goalHighlightIds = activeGoalItems
      .map((goal) => 'duoyi://goal/${Uri.encodeComponent(goal.id)}')
      .toList();
  final anniversaryItems = a.items
      .where((item) => item.daysRemaining >= 0)
      .take(2)
      .toList();
  final anniversaryHighlights = anniversaryItems
      .map((item) => '${item.title} · 还有 ${item.daysRemaining} 天')
      .toList();
  final anniversaryHighlightIds = anniversaryItems
      .map((item) => 'duoyi://anniversary/${Uri.encodeComponent(item.id)}')
      .toList();
  final memorialItems = a.memorials
      .where((item) => item.daysRemaining >= 0)
      .take(3)
      .toList();
  final memorialHighlights = memorialItems
      .map((item) => '${item.title} · 还有 ${item.daysRemaining} 天')
      .toList();
  final memorialHighlightIds = memorialItems
      .map((item) => 'duoyi://anniversary/${Uri.encodeComponent(item.id)}')
      .toList();
  final courseItems = c.todayCourses.take(3).toList();
  final courseHighlights = courseItems.map((course) {
    final location = course.location.isEmpty ? '' : ' · ${course.location}';
    return '${course.startSection}-${course.endSection}节 ${course.name}$location';
  }).toList();
  final courseHighlightIds = courseItems
      .map((course) => 'duoyi://course/${Uri.encodeComponent(course.id)}')
      .toList();
  final noteItems = n.notes.take(3).toList();
  final noteHighlights = noteItems.map((note) => note.title).toList();
  final noteHighlightIds = noteItems
      .map((note) => 'duoyi://note/${Uri.encodeComponent(note.id)}')
      .toList();
  final diaryItems = d.entries.take(3).toList();
  final diaryHighlights = diaryItems.map((entry) {
    return '${entry.date.month}/${entry.date.day} ${entry.title}';
  }).toList();
  final diaryHighlightIds = diaryItems
      .map((entry) => 'duoyi://diary/${Uri.encodeComponent(entry.id)}')
      .toList();
  final calendarEvents = _homeWidgetEventsForToday(
    cal,
    today,
    t,
    h,
    p,
    a,
    c,
    d,
    countdowns,
    g,
    timeAudit,
    tp,
  );
  final scheduleHighlights = calendarEvents
      .take(3)
      .map(_homeWidgetEventLabel)
      .toList();
  final scheduleHighlightIds = calendarEvents
      .take(3)
      .map(_homeWidgetEventDeepLink)
      .toList();
  final todayEventSummary = scheduleHighlights.isEmpty
      ? '今日没有日程'
      : '今日：${scheduleHighlights.first}';
  final focusState = p.state;
  final focusTimerEndsAtMillis = focusState.isRunning && !focusState.isCountUp
      ? DateTime.now()
            .add(Duration(seconds: focusState.remainingSeconds))
            .millisecondsSinceEpoch
      : 0;
  final focusTimerLabel = switch (focusState.type) {
    PomodoroType.focus => focusState.isCountUp ? '正计时专注中' : '专注倒计时',
    PomodoroType.shortBreak => '短休息倒计时',
    PomodoroType.longBreak => '长休息倒计时',
  };
  await HomeWidgetService.push(
    todoCount: activeTodayTodos,
    habitPercent: habitPercent,
    pomodoroToday: p.sessionCountToday,
    strings: tp.brand.strings,
    todoTop3: top3,
    todoTop3Ids: top3Ids,
    goalHighlights: goalHighlights,
    goalHighlightIds: goalHighlightIds,
    anniversaryHighlights: anniversaryHighlights,
    anniversaryHighlightIds: anniversaryHighlightIds,
    courseHighlights: courseHighlights,
    courseHighlightIds: courseHighlightIds,
    noteHighlights: noteHighlights,
    noteHighlightIds: noteHighlightIds,
    memorialHighlights: memorialHighlights,
    memorialHighlightIds: memorialHighlightIds,
    diaryHighlights: diaryHighlights,
    diaryHighlightIds: diaryHighlightIds,
    scheduleHighlights: scheduleHighlights,
    scheduleHighlightIds: scheduleHighlightIds,
    todayEventSummary: todayEventSummary,
    focusSummary: p.sessionCountToday == 0
        ? '今日还未专注'
        : '今日专注 ${p.sessionCountToday} 次',
    habitSummary: habitPercent >= 100 ? '习惯已全部完成' : '习惯完成 $habitPercent%',
    streakSummary: '当前连续 ${h.longestCurrentStreak} 天',
    nextFocusLabel: '${p.config.focusDuration ~/ 60} 分钟专注',
    focusTimerRunning: focusState.isRunning,
    focusTimerRemainingSeconds: focusState.remainingSeconds,
    focusTimerTotalSeconds: focusState.totalSeconds,
    focusTimerEndsAtMillis: focusTimerEndsAtMillis,
    focusTimerLabel: focusTimerLabel,
    habitQuickCheckId: quickCheckHabit?.id ?? '',
    habitQuickCheckLabel: quickCheckHabit == null
        ? '点击进入习惯打卡'
        : '打卡：${quickCheckHabit.name}',
  );
}

List<CalendarEvent> _homeWidgetEventsForToday(
  CalendarProvider calendar,
  DateTime today,
  TodoProvider todos,
  HabitProvider habits,
  PomodoroProvider pomodoros,
  AnniversaryProvider anniversaries,
  CourseProvider courses,
  DiaryProvider diaries,
  CountdownProvider countdowns,
  GoalProvider goals,
  TimeAuditProvider timeAudit,
  ThemeProvider themeProvider,
) {
  calendar.rebuild(
    todos.todos,
    habits.habits,
    pomodoros.sessions,
    themeProvider.brand.theme.colorScheme,
    anniversaries: anniversaries.items,
    courses: courses.courses,
    courseSettings: courses.settings,
    diaries: diaries.entries,
    countdowns: countdowns.items,
    goals: goals.goals,
    timeEntries: timeAudit.entries,
  );
  final events = calendar.getEventsForDate(today).where((event) {
    if (event.type == CalendarEventType.todo && event.isCompleted) {
      return false;
    }
    return event.sourceId?.trim().isNotEmpty == true;
  }).toList();
  events.sort((a, b) {
    final aTime = a.date;
    final bTime = b.date;
    final timeOrder = aTime.compareTo(bTime);
    if (timeOrder != 0) return timeOrder;
    return a.title.compareTo(b.title);
  });
  return events;
}

String _homeWidgetEventLabel(CalendarEvent event) {
  final time = event.time == null
      ? ''
      : '${event.time!.hour.toString().padLeft(2, '0')}:'
            '${event.time!.minute.toString().padLeft(2, '0')} ';
  return '$time${event.type.label} · ${event.title}';
}

String _homeWidgetEventDeepLink(CalendarEvent event) {
  final sourceId = event.sourceId?.trim();
  if (sourceId == null || sourceId.isEmpty) return '';
  final id = Uri.encodeComponent(sourceId);
  return switch (event.type) {
    CalendarEventType.todo => 'duoyi://todo/$id',
    CalendarEventType.habit => 'duoyi://habit/$id',
    CalendarEventType.anniversary => 'duoyi://anniversary/$id',
    CalendarEventType.course => 'duoyi://course/$id',
    CalendarEventType.diary => 'duoyi://diary/$id',
    CalendarEventType.goal => 'duoyi://goal/$id',
    CalendarEventType.countdown => 'duoyi://countdown/$id',
    CalendarEventType.event => 'duoyi://calendar',
    CalendarEventType.pomodoro => 'duoyi://focus',
    CalendarEventType.timeEntry => 'duoyi://time-entry/$id',
  };
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

    try {
      await notification.scheduleOnce(
        id: baseId + i,
        title: '每日提醒${['一', '二', '三'][i]}',
        body: body,
        when: target,
        payload: 'duoyi://tab/today',
      );
    } on NotificationPermissionDeniedException catch (e) {
      debugPrint('[DailyDigest] notification permission denied: $e');
    } catch (e, st) {
      debugPrint('[DailyDigest] schedule failed: $e\n$st');
    }
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

Future<void> _syncReportDigestReminders(
  PreferencesProvider prefs,
  NotificationService notification, {
  required TodoProvider todos,
  required HabitProvider habits,
  required PomodoroProvider pomodoros,
  required TimeAuditProvider timeAudit,
}) async {
  const weeklyId = 880020;
  const monthlyId = 880021;
  const yearlyId = 880022;
  const dailyId = 880023;
  await notification.cancel(dailyId);
  await notification.cancel(weeklyId);
  await notification.cancel(monthlyId);
  await notification.cancel(yearlyId);

  final now = DateTime.now();
  final dailyConfig = prefs.dailyReportReminderConfig;
  if (dailyConfig.enabled) {
    try {
      final when = dailyConfig.nextDailyReminderTime(now);
      await notification.scheduleOnce(
        id: dailyId,
        title: '多仪每日复盘已生成',
        body: _reportDigestNotificationBody(
          kind: PeriodReportKind.daily,
          now: now,
          scheduledFor: when,
          todos: todos,
          habits: habits,
          pomodoros: pomodoros,
          timeAudit: timeAudit,
        ),
        when: when,
        payload: 'duoyi://report/daily',
      );
    } on NotificationPermissionDeniedException catch (e) {
      debugPrint('[ReportDigest] daily notification permission denied: $e');
    } catch (e, st) {
      debugPrint('[ReportDigest] daily schedule failed: $e\n$st');
    }
  }

  final weeklyConfig = prefs.weeklyReportReminderConfig;
  if (weeklyConfig.enabled) {
    try {
      final when = weeklyConfig.nextWeeklyReminderTime(now);
      await notification.scheduleOnce(
        id: weeklyId,
        title: '多仪周报已生成',
        body: _reportDigestNotificationBody(
          kind: PeriodReportKind.weekly,
          now: now,
          scheduledFor: when,
          todos: todos,
          habits: habits,
          pomodoros: pomodoros,
          timeAudit: timeAudit,
        ),
        when: when,
        payload: 'duoyi://report/weekly',
      );
    } on NotificationPermissionDeniedException catch (e) {
      debugPrint('[ReportDigest] weekly notification permission denied: $e');
    } catch (e, st) {
      debugPrint('[ReportDigest] weekly schedule failed: $e\n$st');
    }
  }

  final monthlyConfig = prefs.monthlyReportReminderConfig;
  if (monthlyConfig.enabled) {
    try {
      final when = monthlyConfig.nextMonthlyReminderTime(now);
      await notification.scheduleOnce(
        id: monthlyId,
        title: '多仪月报已生成',
        body: _reportDigestNotificationBody(
          kind: PeriodReportKind.monthly,
          now: now,
          scheduledFor: when,
          todos: todos,
          habits: habits,
          pomodoros: pomodoros,
          timeAudit: timeAudit,
        ),
        when: when,
        payload: 'duoyi://report/monthly',
      );
    } on NotificationPermissionDeniedException catch (e) {
      debugPrint('[ReportDigest] monthly notification permission denied: $e');
    } catch (e, st) {
      debugPrint('[ReportDigest] monthly schedule failed: $e\n$st');
    }
  }

  final yearlyConfig = prefs.yearlyReportReminderConfig;
  if (yearlyConfig.enabled) {
    try {
      final when = yearlyConfig.nextYearlyReminderTime(now);
      await notification.scheduleOnce(
        id: yearlyId,
        title: '多仪年度报告已生成',
        body: _reportDigestNotificationBody(
          kind: PeriodReportKind.yearly,
          now: now,
          scheduledFor: when,
          todos: todos,
          habits: habits,
          pomodoros: pomodoros,
          timeAudit: timeAudit,
        ),
        when: when,
        payload: 'duoyi://report/yearly',
      );
    } on NotificationPermissionDeniedException catch (e) {
      debugPrint('[ReportDigest] yearly notification permission denied: $e');
    } catch (e, st) {
      debugPrint('[ReportDigest] yearly schedule failed: $e\n$st');
    }
  }
}

String _reportDigestNotificationBody({
  required PeriodReportKind kind,
  required DateTime now,
  required DateTime scheduledFor,
  required TodoProvider todos,
  required HabitProvider habits,
  required PomodoroProvider pomodoros,
  required TimeAuditProvider timeAudit,
}) {
  final (start, end) = _reportDigestRange(
    kind: kind,
    now: now,
    scheduledFor: scheduledFor,
  );
  final (previousStart, previousEnd) = _previousReportRange(start, end);
  final report = ReportEngine.buildReport(
    start: start,
    end: end,
    todos: todos.todos,
    habits: habits.habits,
    sessions: pomodoros.sessions,
    timeEntries: timeAudit.entries,
  );
  final previousReport = ReportEngine.buildReport(
    start: previousStart,
    end: previousEnd,
    todos: todos.todos,
    habits: habits.habits,
    sessions: pomodoros.sessions,
    timeEntries: timeAudit.entries,
  );
  return PeriodReportDigest(
    kind: kind,
    report: report,
    comparison: ReportEngine.compare(current: report, previous: previousReport),
    generatedAt: now,
  ).notificationBody;
}

(DateTime, DateTime) _reportDigestRange({
  required PeriodReportKind kind,
  required DateTime now,
  required DateTime scheduledFor,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final scheduledDate = DateTime(
    scheduledFor.year,
    scheduledFor.month,
    scheduledFor.day,
  );
  final DateTime start;
  final DateTime completedEnd;
  switch (kind) {
    case PeriodReportKind.daily:
      start = scheduledDate;
      completedEnd = scheduledDate;
    case PeriodReportKind.weekly:
      start = scheduledDate.subtract(const Duration(days: 7));
      completedEnd = scheduledDate.subtract(const Duration(days: 1));
    case PeriodReportKind.monthly:
      start = DateTime(scheduledDate.year, scheduledDate.month - 1);
      completedEnd = DateTime(scheduledDate.year, scheduledDate.month, 0);
    case PeriodReportKind.yearly:
      start = DateTime(scheduledDate.year - 1);
      completedEnd = DateTime(scheduledDate.year - 1, 12, 31);
  }
  final end = completedEnd.isAfter(today) ? today : completedEnd;
  return (start, end.isBefore(start) ? start : end);
}

(DateTime, DateTime) _previousReportRange(DateTime start, DateTime end) {
  final startDate = DateTime(start.year, start.month, start.day);
  final endDate = DateTime(end.year, end.month, end.day);
  final days = endDate.difference(startDate).inDays + 1;
  final previousEnd = startDate.subtract(const Duration(days: 1));
  final previousStart = previousEnd.subtract(Duration(days: days - 1));
  return (previousStart, previousEnd);
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
      'widget' => 5,
      'mine' => 6,
      _ => 3,
    };
    state?.navigateTo(idx);
  } else if (uri.host == 'oauth' && ctx != null) {
    state?.navigateTo(6);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final latestContext = mainShellKey.currentContext ?? ctx;
      Navigator.of(latestContext).push(
        MaterialPageRoute(
          builder: (_) => IntegrationsScreen(initialOAuthCallbackUri: uri),
        ),
      );
    });
  } else if (uri.host == 'todo' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (id == null || id.isEmpty) {
      state?.navigateTo(1);
      return;
    }
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
    if (id == null || id.isEmpty) {
      // ignore: discarded_futures
      TodayDetailRouter.open(ctx, TodaySectionKind.goals);
      return;
    }
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
  } else if (uri.host == 'calendar') {
    state?.navigateTo(3);
  } else if (uri.host == 'focus') {
    state?.navigateTo(4);
  } else if (uri.host == 'course' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    // ignore: discarded_futures
    TodayDetailRouter.open(ctx, TodaySectionKind.courses, id: id);
  } else if (uri.host == 'anniversary' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    // ignore: discarded_futures
    TodayDetailRouter.open(ctx, TodaySectionKind.anniversaries, id: id);
  } else if (uri.host == 'note' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (id == null || id.isEmpty) {
      Navigator.of(
        ctx,
      ).push(MaterialPageRoute(builder: (_) => const NoteScreen()));
    } else {
      // ignore: discarded_futures
      TodayDetailRouter.open(ctx, TodaySectionKind.notes, id: id);
    }
  } else if (uri.host == 'diary' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    // ignore: discarded_futures
    TodayDetailRouter.open(ctx, TodaySectionKind.diary, id: id);
  } else if (uri.host == 'report' && ctx != null) {
    state?.navigateTo(6);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final latestContext = mainShellKey.currentContext ?? ctx;
      Navigator.of(
        latestContext,
      ).push(MaterialPageRoute(builder: (_) => const StatisticsScreen()));
    });
  } else if (uri.host == 'location' && ctx != null) {
    state?.navigateTo(6);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final latestContext = mainShellKey.currentContext ?? ctx;
      Navigator.of(
        latestContext,
      ).push(MaterialPageRoute(builder: (_) => const IntegrationsScreen()));
    });
  } else if (uri.host == 'snooze' && ctx != null) {
    // 稍后提醒深链：duoyi://snooze/<id>?delay=<minutes>&title=...&body=...&payload=...
    final ns = Provider.of<NotificationService>(ctx, listen: false);
    // ignore: discarded_futures
    ns.handleSnoozeDeepLink(uri);
  } else if (uri.host == 'action') {
    final action = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    if (action == 'start_pomodoro') {
      state?.navigateTo(4);
      if (!pomodoro.state.isRunning) pomodoro.toggleTimer();
    } else if (action == 'quick_todo' && ctx != null) {
      final text = uri.queryParameters['text']?.trim();
      state?.navigateTo(1);
      if (text != null && text.isNotEmpty) {
        final draft = SmartTodoDraftBuilder.fromText(text);
        final todos = Provider.of<TodoProvider>(ctx, listen: false);
        // ignore: discarded_futures
        todos.addTodo(draft.toTodo());
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showQuickTodoDialog(ctx);
      });
    } else if (action == 'complete_todo' && ctx != null) {
      final id = uri.queryParameters['id'];
      if (id == null || id.isEmpty) return;
      final todos = Provider.of<TodoProvider>(ctx, listen: false);
      final target = todos.todos.where((todo) => todo.id == id).firstOrNull;
      if (target == null || target.isCompleted) return;
      // ignore: discarded_futures
      completeTodoWithOptionalTimeRecord(ctx, target);
    } else if (action == 'checkin_habit' && ctx != null) {
      final id = uri.queryParameters['id'];
      state?.navigateTo(2);
      if (id == null || id.isEmpty) return;
      final habits = Provider.of<HabitProvider>(ctx, listen: false);
      final target = habits.habits.where((habit) => habit.id == id).firstOrNull;
      if (target == null ||
          target.kind != HabitKind.positive ||
          !target.isActiveToday() ||
          target.isCompletedToday()) {
        return;
      }
      // ignore: discarded_futures
      habits.incrementHabit(id);
    }
  }
}

Future<void> _syncNotificationQuickAdd(PreferencesProvider prefs) async {
  if (prefs.notificationQuickAdd) {
    try {
      await LocalNotifications.instance.showQuickAddOngoing();
    } on NotificationPermissionDeniedException catch (e) {
      debugPrint('[NotificationQuickAdd] notification permission denied: $e');
    } catch (e, st) {
      debugPrint('[NotificationQuickAdd] show failed: $e\n$st');
    }
  } else {
    try {
      await LocalNotifications.instance.cancel(
        LocalNotifications.quickAddNotificationId,
      );
    } catch (e, st) {
      debugPrint('[NotificationQuickAdd] cancel failed: $e\n$st');
    }
  }
}

Future<void> _showQuickTodoDialog(BuildContext context) async {
  if (!context.mounted) return;
  final ctrl = TextEditingController();
  SmartDateParseResult parsed = SmartDateParseResult.empty;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AppDialog(
        title: const Text('快速待办'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: '一句话描述（如：明天下午3点开会）'),
              onChanged: (value) {
                setState(() => parsed = SmartDateParser.parse(value));
              },
            ),
            if (parsed.isSuccess) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(
                    ctx,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: Theme.of(ctx).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '识别到：${_formatParsedSmartDate(parsed)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(ctx).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(I18n.tr('action.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(I18n.tr('action.add')),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final text = ctrl.text.trim();
  if (text.isEmpty) return;
  final draft = SmartTodoDraftBuilder.fromText(text);
  await context.read<TodoProvider>().addTodo(draft.toTodo());
}

Future<void> _showSharedTextImportSheet(String rawText) async {
  final text = rawText.trim();
  final context = mainShellKey.currentContext;
  if (text.isEmpty || context == null || !context.mounted) return;

  final action = await showAppModalSheet<String>(
    context: context,
    builder: (sheetContext) => AppModalSheet(
      title: '导入分享文本',
      subtitle: '选择保存位置',
      scrollable: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(
                  sheetContext,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(sheetContext).colorScheme.outlineVariant,
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  text,
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (buttonContext, constraints) {
              final compact = constraints.maxWidth < 420;
              final saveNote = OutlinedButton.icon(
                icon: const Icon(Icons.notes_outlined),
                onPressed: () => Navigator.of(buttonContext).pop('note'),
                label: const Text('保存笔记'),
              );
              final createTodo = FilledButton.icon(
                icon: const Icon(Icons.checklist),
                onPressed: () => Navigator.of(buttonContext).pop('todo'),
                label: const Text('创建待办'),
              );
              final cancel = TextButton(
                onPressed: () => Navigator.of(buttonContext).pop(),
                child: Text(I18n.tr('action.cancel')),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    createTodo,
                    const SizedBox(height: 8),
                    saveNote,
                    const SizedBox(height: 4),
                    cancel,
                  ],
                );
              }
              return Row(
                children: [
                  cancel,
                  const Spacer(),
                  Expanded(child: saveNote),
                  const SizedBox(width: 8),
                  Expanded(child: createTodo),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
  if (action == null) return;

  final latestContext = mainShellKey.currentContext;
  if (latestContext == null || !latestContext.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(latestContext);

  if (action == 'todo') {
    final draft = SmartTodoDraftBuilder.fromText(text);
    await latestContext.read<TodoProvider>().addTodo(draft.toTodo());
    mainShellKey.currentState?.navigateTo(1);
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('已创建待办'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  } else if (action == 'note') {
    final now = DateTime.now();
    latestContext.read<NoteProvider>().addOrUpdateNote(
      NoteItem(
        id: now.millisecondsSinceEpoch.toString(),
        content: text,
        createdAt: now,
        updatedAt: now,
      ),
    );
    Navigator.of(
      latestContext,
    ).push(MaterialPageRoute(builder: (_) => const NoteScreen()));
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('已保存笔记'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

String _formatParsedSmartDate(SmartDateParseResult result) {
  final dt = result.dateTime!;
  final date =
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  if (!result.hasTimeOfDay) return date;
  return '$date ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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

  await completeTodoWithOptionalTimeRecord(context, todo);
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
  AchievementProvider? _achievementProvider;
  FocusRoomProvider? _focusRoomProvider;
  AppUpdateService? _appUpdateService;
  DateTime? _lastUpdatePolicyCheckAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = DateTime.now();
    _lastLifecycleDay = DateTime(now.year, now.month, now.day);
    _lastIana = LocalTimezoneResolver.currentIana;
    _lastExactAlarmGranted = _initialExactAlarmGranted;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _checkUpdatePolicy(force: true);
    });
  }

  @override
  void dispose() {
    _achievementProvider?.removeListener(_showAchievementFeedback);
    _focusRoomProvider?.stopRealtimeRankings();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<AchievementProvider>();
    if (_achievementProvider != provider) {
      _achievementProvider?.removeListener(_showAchievementFeedback);
      _achievementProvider = provider;
      provider.addListener(_showAchievementFeedback);
    }
    _focusRoomProvider = context.read<FocusRoomProvider>();
    _appUpdateService = context.read<AppUpdateService>();
  }

  void _showAchievementFeedback() {
    final provider = _achievementProvider;
    if (provider == null) return;
    final unlocked = provider.takeUnlockedFeedback();
    if (unlocked.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      for (final achievement in unlocked) {
        messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                Icon(achievement.icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('解锁成就：${achievement.title}')),
              ],
            ),
          ),
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = context.read<AppLockProvider>();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      lock.onAppLifecycleInactive();
    } else if (state == AppLifecycleState.resumed) {
      lock.onAppLifecycleResume();
      _checkUpdatePolicy();
      _refreshAccountProfileOnResume();
      // 先处理时区变更（可能影响调度），再做跨日 rollover。
      _maybeResyncOnTimezoneChange();
      _maybeRunDailyRolloverOnResume();
      _refreshNotificationPermissionsOnResume();
    }
  }

  /// App 回到前台时刷新账号资料。
  ///
  /// 账号资料保存在后端 users 表，不一定会跟随云同步 payload 变化；这里用
  /// `/api/auth/me` 轻量刷新，避免多设备修改昵称、头像、邮箱验证状态后，本机
  /// 只有重启才更新。
  void _refreshAccountProfileOnResume() {
    final ctx = mainShellKey.currentContext ?? context;
    final auth = Provider.of<AuthProvider>(ctx, listen: false);
    if (!auth.state.isLoggedIn) return;

    // ignore: discarded_futures
    Future.microtask(() async {
      try {
        await auth.refreshMe();
      } catch (e, st) {
        debugPrint('[DuoyiApp] refresh account profile failed: $e\n$st');
      }
    });
  }

  void _checkUpdatePolicy({bool force = false}) {
    final now = DateTime.now();
    final previous = _lastUpdatePolicyCheckAt;
    if (!force &&
        previous != null &&
        now.difference(previous) < const Duration(minutes: 30)) {
      return;
    }
    _lastUpdatePolicyCheckAt = now;
    final updater = _appUpdateService;
    if (updater == null) return;
    if (updater.checking) return;
    // ignore: discarded_futures
    updater.checkNow();
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
    final habitProv = Provider.of<HabitProvider>(ctx, listen: false);
    final pomodoroProv = Provider.of<PomodoroProvider>(ctx, listen: false);
    final timeAuditProv = Provider.of<TimeAuditProvider>(ctx, listen: false);
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
      await _syncReportDigestReminders(
        prefs,
        notif,
        todos: provider,
        habits: habitProv,
        pomodoros: pomodoroProv,
        timeAudit: timeAuditProv,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.watch<ThemeProvider>().brand;
    final lock = context.watch<AppLockProvider>();
    final locale = context.watch<LocaleProvider>();
    return MaterialApp(
      title: brand.strings.appTitle,
      debugShowCheckedModeBanner: false,
      locale: locale.flutterLocale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: brand.theme,
      home: Stack(
        children: [
          MainShell(key: mainShellKey),
          if (lock.isLocked)
            const Positioned.fill(child: Material(child: LockScreen())),
          const _ForceUpdateGate(),
        ],
      ),
    );
  }
}

class _ForceUpdateGate extends StatelessWidget {
  const _ForceUpdateGate();

  @override
  Widget build(BuildContext context) {
    final updater = context.watch<AppUpdateService>();
    if (!updater.mustUpdate) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final notes = updater.latestNotesForDisplay;
    final canInstall = updater.latestUrl != null;

    return Positioned.fill(
      child: PopScope(
        canPop: false,
        child: Material(
          color: colorScheme.surface,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.system_update_alt_outlined,
                        size: 48,
                        color: colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '必须更新后才能继续使用',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '管理员已要求当前版本升级。更新完成前，应用功能会暂时锁定。',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      AppSurfaceCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ForceUpdateInfoRow(
                              label: '当前版本',
                              value: updater.currentVersion,
                            ),
                            _ForceUpdateInfoRow(
                              label: '最新版本',
                              value: updater.latestVersion ?? '未配置',
                            ),
                            if (updater.minimumSupportedVersion != null)
                              _ForceUpdateInfoRow(
                                label: '最低支持版本',
                                value: updater.minimumSupportedVersion!,
                              ),
                            if (updater.latestAssetName != null)
                              _ForceUpdateInfoRow(
                                label: '安装包',
                                value: updater.latestAssetName!,
                              ),
                          ],
                        ),
                      ),
                      if (notes.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          '更新内容',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 180),
                          child: AppSurfaceCard(
                            padding: const EdgeInsets.all(14),
                            child: Scrollbar(
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  notes,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (updater.error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          updater.error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ],
                      if (!canInstall) ...[
                        const SizedBox(height: 12),
                        AppInfoBanner(
                          icon: Icons.link_off_outlined,
                          title: '管理员未配置下载地址',
                          message: '请管理员在后台补充最新版本安装包地址，否则客户端无法完成强制更新。',
                          color: colorScheme.error,
                          margin: EdgeInsets.zero,
                        ),
                      ],
                      if (updater.downloading) ...[
                        const SizedBox(height: 16),
                        LinearProgressIndicator(
                          value: updater.downloadProgress,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          updater.downloadProgress == null
                              ? '正在下载更新包'
                              : '正在下载 ${(updater.downloadProgress! * 100).clamp(0, 100).toStringAsFixed(0)}%',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ] else if (updater.installing) ...[
                        const SizedBox(height: 16),
                        const LinearProgressIndicator(),
                        const SizedBox(height: 6),
                        Text(
                          '正在打开安装器',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: canInstall && !updater.busy
                            ? () async {
                                await updater.downloadAndInstallLatest();
                              }
                            : null,
                        icon: const Icon(Icons.download_for_offline_outlined),
                        label: Text(
                          updater.downloadedFilePath == null ? '下载并安装' : '重新安装',
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
  }
}

class _ForceUpdateInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _ForceUpdateInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
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
  static final GlobalKey widgetKey = GlobalKey();
  static final GlobalKey mineKey = GlobalKey();

  int _coerceTabIndex(int index) {
    final visibleTabs = context
        .read<PreferencesProvider>()
        .enabledBottomNavTabs
        .where((tab) => tab >= 0 && tab < 7)
        .toList(growable: false);
    if (index >= 0 &&
        index < 7 &&
        (visibleTabs.isEmpty || visibleTabs.contains(index))) {
      return index;
    }
    if (visibleTabs.isNotEmpty) return visibleTabs.first;
    return index.clamp(0, 6);
  }

  void navigateTo(int index) {
    if (!mounted) return;
    setState(() => _currentIndex = _coerceTabIndex(index));
  }

  @override
  void initState() {
    super.initState();
    // 延迟一帧再读 PreferencesProvider，避免 initState 中 read 异常
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _coerceTabIndex(
        context.read<PreferencesProvider>().defaultTab,
      );
      if (target != _currentIndex) {
        setState(() => _currentIndex = target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();
    final visibleTabs = prefs.enabledBottomNavTabs
        .where((tab) => tab >= 0 && tab < 7)
        .toList(growable: false);
    final safeVisibleTabs = visibleTabs.isEmpty
        ? const [0, 1, 2, 3, 4, 5, 6]
        : visibleTabs;
    var safeIndex = _currentIndex.clamp(0, 6);
    if (!safeVisibleTabs.contains(safeIndex)) {
      safeIndex = safeVisibleTabs.first;
    }
    if (safeIndex != _currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _currentIndex = safeIndex);
      });
    }
    final allDestinations = [
      NavigationDestination(
        icon: const Icon(Icons.today_outlined),
        selectedIcon: const Icon(Icons.today),
        label: I18n.tr('nav.today'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.checklist),
        selectedIcon: const Icon(Icons.checklist_rounded),
        label: I18n.tr('nav.todo'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.repeat),
        selectedIcon: const Icon(Icons.repeat_rounded),
        label: I18n.tr('nav.habit'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.calendar_month_outlined),
        selectedIcon: const Icon(Icons.calendar_month),
        label: I18n.tr('nav.calendar'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.timer_outlined),
        selectedIcon: const Icon(Icons.timer),
        label: I18n.tr('nav.focus'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.widgets_outlined),
        selectedIcon: const Icon(Icons.widgets_rounded),
        label: I18n.tr('nav.widget'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.person_outline),
        selectedIcon: const Icon(Icons.person),
        label: I18n.tr('nav.mine'),
      ),
    ];
    final selectedNavIndex = safeVisibleTabs.indexOf(safeIndex);
    final updater = context.watch<AppUpdateService>();
    final showUpdateBadge = updater.hasUpdate && !updater.mustUpdate;
    final navDestinations = safeVisibleTabs
        .map((tab) {
          final destination = allDestinations[tab];
          if (tab != 6 || !showUpdateBadge) return destination;
          return NavigationDestination(
            icon: const _BottomNavBadgeIcon(child: Icon(Icons.person_outline)),
            selectedIcon: const _BottomNavBadgeIcon(child: Icon(Icons.person)),
            label: I18n.tr('nav.mine'),
          );
        })
        .toList(growable: false);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BrandBackground(
        child: IndexedStack(
          index: safeIndex,
          children: [
            TodayScreen(key: todayKey),
            TodoScreen(key: todoKey),
            HabitScreen(key: habitKey),
            CalendarScreen(key: calendarKey),
            PomodoroScreen(key: pomodoroKey),
            WidgetScreen(key: widgetKey),
            MineScreen(key: mineKey),
          ],
        ),
      ),
      floatingActionButton: safeIndex == 0 && prefs.quickCaptureFab
          ? const QuickCaptureFab()
          : null,
      appBar: safeIndex == 0
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
            setState(() => _currentIndex = safeVisibleTabs[i]),
        destinations: navDestinations,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }
}

class _BottomNavBadgeIcon extends StatelessWidget {
  final Widget child;

  const _BottomNavBadgeIcon({required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          child,
          Positioned(
            top: 3,
            right: 3,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
