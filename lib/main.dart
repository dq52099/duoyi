import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show
        AndroidFlutterLocalNotificationsPlugin,
        FlutterLocalNotificationsPlugin,
        IOSFlutterLocalNotificationsPlugin,
        LinuxFlutterLocalNotificationsPlugin,
        MacOSFlutterLocalNotificationsPlugin;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/app_version.dart';
import 'core/account_preference_writes.dart';
import 'core/account_ui_copy.dart';
import 'core/achievements.dart';
import 'core/completion_visibility_policy.dart';
import 'core/crash_guard.dart';
import 'core/design_tokens.dart';
import 'core/daily_digest_presentation.dart';
import 'core/desktop_tokens.dart';
import 'core/i18n.dart';
import 'core/iterable_extensions.dart';
import 'core/local_timezone_resolver.dart';
import 'core/lunar_calendar.dart';
import 'core/platform_info.dart';
import 'core/period_report_presentation.dart';
import 'core/report_engine.dart';
import 'core/smart_todo_draft.dart';
import 'core/web_target.dart';
import 'l10n/generated/app_localizations.dart';
import 'providers/todo_provider.dart';
import 'providers/habit_provider.dart';
import 'providers/pomodoro_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/cloud_sync_provider.dart';
import 'providers/sync_status_presenter.dart';
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
import 'models/goal.dart' show GoalStatus, ReminderKind, ReminderPlan;
import 'models/habit.dart' show Habit, HabitKind;
import 'models/calendar_event.dart' show CalendarEvent;
import 'models/note.dart' show NoteItem;
import 'models/pomodoro.dart' show PomodoroType;
import 'models/todo.dart' show TodoItem, TodoPriorityX;
import 'services/alarm_service.dart';
import 'services/app_access_route_gate.dart';
import 'services/account_local_data_cleaner.dart';
import 'services/auto_archive_coordinator.dart';
import 'services/calendar_sync_service.dart';
import 'services/deep_link_service.dart';
import 'services/daily_digest_reminder_sync.dart';
import 'services/digest_reminder_coordinator.dart';
import 'services/system_tray.dart';
import 'services/home_widget_service.dart';
import 'services/home_widget_push_queue.dart';
import 'services/widget_schedule_projection.dart';
import 'services/widget_habit_progress.dart';
import 'services/widget_publication.dart';
import 'services/widget_publication_client.dart';
import 'services/widget_publication_controller.dart';
import 'services/widget_publication_host.dart';
import 'services/required_storage_startup.dart';
import 'services/widget_quick_todo_action.dart';
import 'services/widget_action_scope.dart';
import 'services/widget_link_dispatch.dart';
import 'services/widget_calendar_link.dart';
import 'services/widget_calendar_route_controller.dart';
import 'services/widget_navigation_request.dart';
import 'services/widget_launch_access.dart';
import 'services/shared_text_import_queue.dart';
import 'services/cloud_sync_notice.dart';
import 'services/widget_action_message.dart';
import 'services/reminder_issue_copy.dart';
import 'services/ai_service.dart';
import 'services/app_update_service.dart';
import 'services/backend_reminder_email_sink.dart';
import 'services/foreground_reminder_popup_sink.dart';
import 'services/holiday_calendar.dart';
import 'services/local_notifications.dart';
import 'services/native_reminder_ringtone.dart';
import 'services/location_geofence_service.dart';
import 'services/notification_permission_exception.dart';
import 'services/notification_status_bar_sync_bridge.dart';
import 'services/notification_status_bar_service.dart';
import 'services/reminder_sinks.dart';
import 'services/reminder_ringtone_settings.dart';
import 'services/reminder_scheduler.dart';
import 'services/web_lifecycle_recovery.dart';
import 'screens/today_screen.dart';
import 'screens/todo_screen.dart';
import 'services/widget_focus_projection.dart';
import 'widgets/achievement_feedback_host.dart';
import 'screens/habit_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/countdown_screen.dart';
import 'screens/widget_schedule_detail_route.dart';
import 'screens/pomodoro_screen.dart';
import 'screens/widget_screen.dart';
import 'screens/mine_screen.dart';
import 'screens/integrations_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/login_screen.dart';
import 'screens/note_screen.dart';
import 'screens/anniversary_screen.dart';
import 'screens/course_schedule_screen.dart';
import 'screens/diary_screen.dart';
import 'screens/goal_edit_screen.dart';
import 'screens/goal_screen.dart';
import 'screens/statistics_screen.dart';
import 'screens/time_audit_screen.dart';
import 'screens/today_detail_router.dart';
import 'widgets/brand_background.dart';
import 'widgets/calendar_event_sheet.dart';
import 'widgets/app_access_layer.dart';
import 'widgets/critical_storage_gate.dart';
import 'widgets/shared_text_import_sheet.dart';
import 'widgets/force_update_gate.dart';
import 'widgets/quick_capture_fab.dart';
import 'widgets/todo_completion_flow.dart';
import 'widgets/widget_quick_todo_dialog.dart';
import 'widgets/widget_habit_check_in_dialog.dart';
import 'widgets/surface_components.dart';
import 'desktop_web/desktop_web_nav.dart';
import 'desktop_web/desktop_web_workspace.dart';

final GlobalKey<MainShellState> mainShellKey = GlobalKey<MainShellState>();
typedef _PendingWidgetLaunch = ({
  Uri uri,
  WidgetNavigationRequest request,
  WidgetLinkOrigin origin,
});
final List<_PendingWidgetLaunch> _pendingWidgetUris = [];
final _widgetNavigationRequests = WidgetNavigationRequests(
  accountGeneration: () => AccountLocalDataCleaner.accountDataGeneration,
);
bool _appAccessBlocked = false;
final _sharedTextImports = SharedTextImportQueue(
  accountGeneration: () => AccountLocalDataCleaner.accountDataGeneration,
  isBlocked: () => _appAccessBlocked,
  isReady: () {
    final context = mainShellKey.currentContext;
    return context != null &&
        context.mounted &&
        !_widgetAccountUnavailable(context.read<AuthProvider>());
  },
  open: _showSharedTextImportSheet,
  onError: (error, stack) =>
      debugPrint('[SharedTextImport] failed: $error\n$stack'),
);

/// Native incoming shares and cold-launch text use the same account-bound queue.
void receiveSharedText(String text, {int? receivedAccountGeneration}) {
  _sharedTextImports.receive(
    text,
    receivedAccountGeneration: receivedAccountGeneration,
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_sharedTextImports.drain());
  });
  WidgetsBinding.instance.ensureVisualUpdate();
}

final _widgetCalendarRoutes = WidgetCalendarRouteController();
final Map<String, DateTime> _recentWidgetActionUris = <String, DateTime>{};
final Set<String> _handledWidgetDeliveries = <String>{};
final Set<String> _inFlightWidgetDeliveries = <String>{};
typedef _ReminderResyncQueue =
    Future<void> Function({Duration delay, String reason});

/// 模块级的提醒调度器实例。
///
/// 在 `main()` 中构造后注入到各 Provider，并被 `_DuoyiAppState` 在
/// `AppLifecycleState.resumed` 检测到时区变化时读取，用于触发提醒重放。
/// 放在顶层是因为 `_DuoyiAppState` 并不持有构造时的闭包引用。
late ReminderScheduler _reminderScheduler;
bool _reminderSchedulerReady = false;
Future<bool> Function({bool force, bool requestIfNeeded})?
_syncNotificationQuickAddDedupedCallback;
VoidCallback? _refreshHomeWidgetsOnRolloverCallback;
_ReminderResyncQueue? _queueFullReminderResyncCallback;
bool _initialExactAlarmGranted = false;
const int _dailyDigestHolidayWindowDays = 14;
const String _notificationStatusBarStartupBuildKey =
    'notification_status_bar_startup_build';

AuthProvider? _digestReminderAuth;
final _digestReminderCoordinator = DigestReminderCoordinator(
  currentAccountGeneration: () => AccountLocalDataCleaner.accountDataGeneration,
  captureEnglish: () => I18n.current == AppLocale.en,
  isAccountAvailable: () =>
      _digestReminderAuth?.isAccountTransitionInProgress != true &&
      _digestReminderAuth?.isLocalAccountDataBlocked != true &&
      !AccountPreferenceWrites.isBoundaryActive,
);

Future<void> _refreshReminderRingtoneChannels() async {
  try {
    await ReminderRingtoneSettings.applyPersistedSettingsToNative();
    await Future.wait([
      LocalNotifications.instance.refreshAndroidRingtoneChannels(),
      AlarmService.instance.refreshAndroidRingtoneChannel(),
    ]);
  } catch (e, st) {
    debugPrint('[ReminderRingtone] channel refresh failed: $e\n$st');
  }
}

Future<void> _startupGuard(
  String label,
  Future<void> Function() task, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  try {
    await task().timeout(timeout);
  } on TimeoutException {
    debugPrint('[startup] $label timed out after ${timeout.inSeconds}s');
  } catch (e, st) {
    debugPrint('[startup] $label failed: $e\n$st');
  }
}

Future<T?> _startupValue<T>(
  String label,
  Future<T?> Function() task, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  try {
    return await task().timeout(timeout);
  } on TimeoutException {
    debugPrint('[startup] $label timed out after ${timeout.inSeconds}s');
    return null;
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

Future<void> Function()? _ensureHomeWidgetDataReady;

String _pomodoroHomeWidgetSignature(PomodoroProvider provider) =>
    pomodoroWidgetChangeSignature(provider);

String _homeWidgetThemeSignature(ThemeProvider provider) {
  final payload = HomeWidgetThemePayload.fromThemeProvider(provider);
  return '${payload.brandId}:${payload.cardSkinId}:'
      '${payload.backgroundAssetKey}:${payload.dark}:'
      '${payload.background.toARGB32()}:${payload.surface.toARGB32()}:'
      '${payload.cornerRadiusDp}:${payload.borderWidthDp}';
}

String _homeWidgetDataRevisionSignature(
  TodoProvider todoProvider,
  HabitProvider habitProvider,
  PomodoroProvider pomodoroProvider,
  CalendarProvider calendarProvider,
  CountdownProvider countdownProvider,
  TimeAuditProvider timeAuditProvider,
  GoalProvider goalProvider,
  AnniversaryProvider anniversaryProvider,
  CourseProvider courseProvider,
  NoteProvider noteProvider,
  DiaryProvider diaryProvider,
  ThemeProvider themeProvider,
  PreferencesProvider preferencesProvider,
) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return Object.hashAll([
    today.microsecondsSinceEpoch,
    now.timeZoneOffset.inMinutes,
    I18n.current.name,
    _homeWidgetThemeSignature(themeProvider),
    preferencesProvider.firstDayOfWeek,
    _homeWidgetTodoRevision(todoProvider),
    _homeWidgetHabitRevision(habitProvider, today),
    _homeWidgetPomodoroRevision(pomodoroProvider),
    _homeWidgetCalendarRevision(calendarProvider),
    _homeWidgetCountdownRevision(countdownProvider),
    _homeWidgetTimeAuditRevision(timeAuditProvider),
    _homeWidgetGoalRevision(goalProvider),
    _homeWidgetAnniversaryRevision(anniversaryProvider),
    _homeWidgetCourseRevision(courseProvider),
    _homeWidgetNoteRevision(noteProvider),
    _homeWidgetDiaryRevision(diaryProvider),
  ]).toString();
}

int _homeWidgetTodoRevision(TodoProvider provider) {
  return Object.hashAll(
    provider.todos.map((todo) {
      return Object.hashAll([
        todo.id,
        todo.title,
        todo.isCompleted,
        todo.priority.index,
        todo.sortOrder,
        todo.listGroupId,
        todo.listGroupName,
        todo.workspaceId,
        todo.isArchivedAfterRollover,
        todo.date.microsecondsSinceEpoch,
        _dateMicros(todo.dueDate),
        _dateMicros(todo.completedAt),
        todo.updatedAt.microsecondsSinceEpoch,
        todo.reminder.enabled,
        todo.reminder.kind.index,
        todo.reminder.hour,
        todo.reminder.minute,
        todo.reminder.daysBefore,
        _homeWidgetReminderPlanRevision(todo.reminderPlan),
      ]);
    }),
  );
}

int _homeWidgetHabitRevision(HabitProvider provider, DateTime today) {
  final todayKey =
      '${today.year}-${today.month.toString().padLeft(2, '0')}-'
      '${today.day.toString().padLeft(2, '0')}';
  return Object.hashAll(
    provider.habits.map((habit) {
      final todayCompletionUpdatedAt = habit.completionUpdatedAt[todayKey];
      return Object.hashAll([
        habit.id,
        habit.name,
        habit.kind.index,
        habit.colorValue,
        habit.targetCount,
        habit.unit,
        habit.generatedUnitKey,
        habit.currentStreak,
        habit.bestStreak,
        habit.sortOrder,
        habit.weeklyTarget,
        habit.flexTarget,
        habit.flexPeriod?.index,
        habit.activeWeekdays.length,
        Object.hashAll(habit.activeWeekdays),
        _dateMicros(habit.startDate),
        _dateMicros(habit.endDate),
        habit.completions[todayKey] ?? 0,
        _dateMicros(todayCompletionUpdatedAt),
        habit.updatedAt.microsecondsSinceEpoch,
        habit.remind,
        habit.remindHour,
        habit.remindMinute,
        _homeWidgetReminderPlanRevision(habit.reminderPlan),
      ]);
    }),
  );
}

int _homeWidgetPomodoroRevision(PomodoroProvider provider) {
  final state = provider.state;
  return Object.hashAll([
    _pomodoroHomeWidgetSignature(provider),
    provider.config.focusDuration,
    provider.config.shortBreakDuration,
    provider.config.longBreakDuration,
    provider.todayFocusSessions.length,
    provider.totalFocusMinutes,
    Object.hashAll(
      provider.sessions.map(
        (session) => Object.hash(
          session.id,
          session.type.index,
          session.durationSeconds,
          session.updatedAt.microsecondsSinceEpoch,
        ),
      ),
    ),
    state.isRunning && !state.isCountUp ? state.totalSeconds : 0,
  ]);
}

int _homeWidgetCalendarRevision(CalendarProvider provider) {
  return Object.hashAll([
    provider.sourceRevision,
    Object.hashAll(provider.localEvents.map(_homeWidgetCalendarEventRevision)),
    Object.hashAll(provider.events.map(_homeWidgetCalendarEventRevision)),
  ]);
}

int _homeWidgetCountdownRevision(CountdownProvider provider) {
  return Object.hashAll(
    provider.items.map(
      (item) => Object.hash(
        item.id,
        item.title,
        item.targetDate.microsecondsSinceEpoch,
        item.isPinned,
        item.updatedAt.microsecondsSinceEpoch,
      ),
    ),
  );
}

int _homeWidgetTimeAuditRevision(TimeAuditProvider provider) {
  return Object.hashAll(
    provider.entries.map(
      (entry) => Object.hashAll([
        entry.id,
        entry.title,
        entry.startAt.microsecondsSinceEpoch,
        entry.endAt.microsecondsSinceEpoch,
        entry.category.index,
        entry.source.index,
        entry.sourceId,
        entry.updatedAt.microsecondsSinceEpoch,
      ]),
    ),
  );
}

int _homeWidgetGoalRevision(GoalProvider provider) {
  return Object.hashAll(
    provider.activeGoals.map(
      (goal) => Object.hashAll([
        goal.id,
        goal.title,
        goal.status.index,
        goal.sortOrder,
        goal.colorValue,
        goal.autoProgress,
        goal.computedProgress,
        goal.workspaceId,
        _dateMicros(goal.targetDate),
        goal.updatedAt.microsecondsSinceEpoch,
        Object.hashAll(
          goal.milestones.map(
            (milestone) => Object.hash(
              milestone.id,
              milestone.title,
              milestone.isCompleted,
            ),
          ),
        ),
        _homeWidgetReminderPlanRevision(goal.reminderPlan),
      ]),
    ),
  );
}

int _homeWidgetAnniversaryRevision(AnniversaryProvider provider) {
  return Object.hashAll(
    provider.items.map(
      (item) => Object.hashAll([
        item.id,
        item.title,
        item.type.index,
        item.calendarType.index,
        item.colorValue,
        item.isPinned,
        item.originDate.microsecondsSinceEpoch,
        item.lunarYear,
        item.lunarMonth,
        item.lunarDay,
        item.lunarIsLeap,
        item.ignoreYear,
        item.remind,
        item.remindDaysBefore,
        item.remindHour,
        item.remindMinute,
        item.reminderKind.index,
        item.updatedAt.microsecondsSinceEpoch,
      ]),
    ),
  );
}

int _homeWidgetCourseRevision(CourseProvider provider) {
  final settings = provider.settings;
  return Object.hashAll([
    settings.termStart.microsecondsSinceEpoch,
    settings.totalWeeks,
    settings.sessionsPerDay,
    settings.sessionMinutes,
    settings.firstSessionHour,
    settings.firstSessionMinute,
    settings.breakMinutes,
    Object.hashAll(
      provider.courses.map(
        (course) => Object.hashAll([
          course.id,
          course.name,
          course.location,
          course.weekday,
          course.startSection,
          course.sectionCount,
          course.colorValue,
          course.updatedAt.microsecondsSinceEpoch,
          Object.hashAll(course.weeks),
        ]),
      ),
    ),
  ]);
}

int _homeWidgetNoteRevision(NoteProvider provider) {
  return Object.hashAll(
    provider.notes.map(
      (note) => Object.hash(
        note.id,
        note.title,
        note.pinned,
        note.archived,
        note.updatedAt.microsecondsSinceEpoch,
      ),
    ),
  );
}

int _homeWidgetDiaryRevision(DiaryProvider provider) {
  return Object.hashAll(
    provider.entriesByDate.values.map(
      (entry) => Object.hash(
        entry.id,
        entry.title,
        entry.date.microsecondsSinceEpoch,
        entry.updatedAt.microsecondsSinceEpoch,
      ),
    ),
  );
}

int _homeWidgetReminderPlanRevision(ReminderPlan plan) {
  return Object.hashAll([
    plan.enabled,
    Object.hashAll(
      plan.rules.map(
        (rule) => Object.hashAll([
          rule.id,
          rule.enabled,
          rule.type.index,
          rule.kind.index,
          rule.hour,
          rule.minute,
          rule.offsetMinutes,
          Object.hashAll(rule.weekdays),
          rule.vibrate,
          rule.fullScreen,
          rule.snoozeMinutes,
          rule.repeatCount,
        ]),
      ),
    ),
  ]);
}

int _homeWidgetCalendarEventRevision(CalendarEvent event) {
  return Object.hashAll([
    event.id,
    event.title,
    event.date.microsecondsSinceEpoch,
    _dateMicros(event.endDate),
    event.type.index,
    event.color,
    event.isCompleted,
    event.sourceId,
    event.subtitle,
    event.projectId,
    event.projectName,
    event.workspaceId,
    event.note,
    _dateMicros(event.updatedAt),
    event.time == null
        ? null
        : Object.hash(event.time!.hour, event.time!.minute),
  ]);
}

int _dateMicros(DateTime? value) => value?.microsecondsSinceEpoch ?? 0;

Future<void> _runSyncReloadTasksInBatches(
  List<Future<void> Function()> tasks, {
  int batchSize = 1,
  bool continueOnError = false,
  String label = 'sync reload',
}) async {
  for (var i = 0; i < tasks.length; i += batchSize) {
    final end = (i + batchSize).clamp(0, tasks.length);
    if (continueOnError) {
      await Future.wait([
        for (var j = i; j < end; j++)
          () async {
            try {
              await tasks[j]();
            } catch (e, st) {
              debugPrint('[main] $label task#$j failed: $e\n$st');
            }
          }(),
      ]);
    } else {
      await Future.wait([for (var j = i; j < end; j++) tasks[j]()]);
    }
    if (end < tasks.length) {
      await _yieldForNextFrame();
    }
  }
}

Future<void> _yieldForNextFrame([
  Duration delay = const Duration(milliseconds: 32),
]) {
  return Future<void>.delayed(delay);
}

Future<void> _runStartupIdleQueue(
  List<Future<void> Function()> tasks, {
  Duration initialDelay = const Duration(seconds: 12),
  Duration gap = const Duration(seconds: 4),
}) async {
  await Future<void>.delayed(initialDelay);
  for (final task in tasks) {
    await task();
    await Future<void>.delayed(gap);
  }
}

Future<void> _runStartupStaggeredTask(
  String label,
  Future<void> Function() task, {
  required Duration delay,
  Duration timeout = const Duration(seconds: 12),
}) async {
  await Future<void>.delayed(delay);
  await _startupGuard(label, task, timeout: timeout);
}

Future<void> _runStartupStoragePhase(
  String label,
  List<Future<void> Function()> tasks, {
  int batchSize = 1,
}) {
  final startedAt = DateTime.now();
  return _startupGuard(label, () async {
    await _runSyncReloadTasksInBatches(tasks, batchSize: batchSize);
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    debugPrint('[startup] $label completed in ${elapsedMs}ms');
  }, timeout: const Duration(seconds: 18));
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 全局未捕获异常兜底：框架/平台异常摘要落盘本地日志，绝不抛出或弹 UI。
  CrashGuard.install();

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
  _digestReminderAuth = authProvider;
  var lastSuccessfulDigestTransitionRevision =
      authProvider.successfulAccountTransitionRevision;
  final widgetPublicationController = WidgetPublicationController();
  final widgetPublicationHost = WidgetPublicationHost(
    controller: widgetPublicationController,
    onStatus: (message) => debugPrint('[HomeWidget] $message'),
  );
  var homeWidgetPresentationGeneration = 0;
  var homeWidgetCleanupGeneration = 0;
  WidgetDevicePresentation? selectedHomeWidgetPresentation;
  authProvider.onWidgetPublicationAuthorityRevoked = () {
    widgetPublicationController.revoke();
    HomeWidgetService.invalidatePushSignature();
  };
  final countdownProvider = CountdownProvider();
  final noteProvider = NoteProvider();
  final anniversaryProvider = AnniversaryProvider();
  final diaryProvider = DiaryProvider();
  final goalProvider = GoalProvider();
  final courseProvider = CourseProvider();
  final appLockProvider = AppLockProvider();
  final preferencesProvider = PreferencesProvider();
  final autoArchiveCoordinator = AutoArchiveCoordinator();
  final quickCaptureTemplateProvider = QuickCaptureTemplateProvider();
  final timeAuditProvider = TimeAuditProvider();
  final achievementProvider = AchievementProvider();
  final customFocusSoundProvider = CustomFocusSoundProvider();
  final focusRoomProvider = FocusRoomProvider();
  final shareProvider = ShareProvider();
  final localeProvider = LocaleProvider();
  final locationReminderProvider = LocationReminderProvider();
  final calendarSyncProvider = CalendarSyncProvider(authProvider: authProvider);
  final aiService = AiService()
    ..historyAccessAllowed = () =>
        !authProvider.isAccountTransitionInProgress &&
        !authProvider.isLocalAccountDataBlocked;
  final appUpdate = AppUpdateService(
    repo: 'dq52099/duoyi',
    currentVersion: AppVersion.name,
    currentVersionCode: AppVersion.build,
  );
  var cloudSyncStartSerial = 0;
  cloudSyncProvider.localApplyBarrier = (apply) =>
      autoArchiveCoordinator.withAuthoritativeReload(apply);
  cloudSyncProvider.beforeAccountChangeFlush = () async {
    await autoArchiveCoordinator.suspendAndDrain();
    if (!await todoProvider.retryPendingArchiveMutationMarker()) {
      throw AccountLocalDataCleanupBlockedException(
        AccountUiCopy.archiveSyncPending,
      );
    }
  };

  WidgetDevicePresentation widgetPresentation(Map<String, Object> source) {
    final complete = <String, Object>{
      for (final key in WidgetPublication.valueKeys)
        key:
            source[key] ??
            (throw FormatException('Missing widget publication value: $key')),
    };
    return WidgetDevicePresentation(
      locale: I18n.current,
      completeValues: complete,
    );
  }

  WidgetDevicePresentation currentWidgetPresentation() {
    final strings = themeProvider.brand.strings;
    return widgetPresentation({
      ...HomeWidgetService.accountPayloadDefaults,
      ...HomeWidgetThemePayload.fromThemeProvider(themeProvider).payloadValues,
      'widget_first_day_of_week': preferencesProvider.firstDayOfWeek,
      'brand_app_title': strings.appTitle,
      'nav_todo': strings.navTodo,
      'nav_habit': strings.navHabit,
      'nav_calendar': strings.navCalendar,
      'nav_focus': strings.navFocus,
    });
  }

  // Invalidate synchronously, including A -> B -> A before a debounced push.
  void selectCurrentWidgetPresentation() {
    final next = currentWidgetPresentation();
    if (selectedHomeWidgetPresentation?.sameAs(next) == true) return;
    selectedHomeWidgetPresentation = next;
    homeWidgetPresentationGeneration++;
    widgetPublicationController.selectPresentation(next);
    HomeWidgetService.invalidatePushSignature();
  }

  selectCurrentWidgetPresentation();
  themeProvider.addListener(selectCurrentWidgetPresentation);
  localeProvider.addListener(selectCurrentWidgetPresentation);
  preferencesProvider.addListener(selectCurrentWidgetPresentation);

  HomeWidgetService.publicationActionValidator = (uri) async {
    if (_widgetAccountUnavailable(authProvider)) return false;
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    final session = authProvider.sessionGeneration;
    final identity = authProvider.validatedWidgetAccountIdentity;
    if (authProvider.state.isLoggedIn && identity == null) return false;
    return isCurrentWidgetPublicationAction(
      uri: uri,
      workspace: ValidatedWidgetWorkspace(
        binding: identity == null
            ? WidgetWorkspaceBinding(kind: 'guest', key: 'local-device')
            : WidgetWorkspaceBinding(kind: 'account', key: identity),
        accountGeneration: generation,
        isCurrent: () =>
            !_widgetAccountUnavailable(authProvider) &&
            authProvider.sessionGeneration == session &&
            (identity == null
                ? !authProvider.state.isLoggedIn
                : authProvider.validatedWidgetAccountIdentity == identity),
      ),
    );
  };

  Future<void> flushPendingLocalChangesBeforeAccountChange({
    required String reason,
  }) async {
    final account = AccountLocalDataCleaner.accountDataGeneration;
    final session = authProvider.sessionGeneration;
    try {
      final pendingChangesFlushed = await cloudSyncProvider
          .flushPendingLocalChangesBeforeAccountChange(
            timeout: const Duration(seconds: 8),
          );
      if (!pendingChangesFlushed) {
        throw AccountLocalDataCleanupBlockedException(
          '本机还有未上传服务器的改动，已暂停${reason == 'logout' ? '退出登录' : '切换账号'}，避免本地内容被清空。请联网或开启云同步后重试。',
        );
      }
    } catch (_) {
      if (AccountLocalDataCleaner.isCurrentAccountDataGeneration(account) &&
          authProvider.sessionGeneration == session) {
        autoArchiveCoordinator.resumeAfterAccountPreflightFailure();
      }
      rethrow;
    }
  }

  Future<void> clearAccountLocalData({required String reason}) async {
    await AccountLocalDataCleaner.runAccountRetirement(() async {
      debugPrint('[auth] clear local account data reason=$reason');
      final cleanup = ++homeWidgetCleanupGeneration;
      final account = AccountLocalDataCleaner.accountDataGeneration;
      final session = authProvider.sessionGeneration;
      bool isCleanupCurrent() =>
          homeWidgetCleanupGeneration == cleanup &&
          authProvider.sessionGeneration == session &&
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(account);
      await flushPendingLocalChangesBeforeAccountChange(reason: reason);
      if (!isCleanupCurrent()) {
        throw AccountLocalDataCleanupBlockedException(
          AccountUiCopy.accountChanged,
        );
      }
      widgetPublicationController.revoke();
      try {
        Future<bool> clearWidgetCache() {
          HomeWidgetService.resetAccountCache();
          return HomeWidgetService.waitForAccountClear();
        }

        if (HomeWidgetService.usesNativePublication) {
          final result = await widgetPublicationHost.clearForCleanup(
            cleanup: ValidatedWidgetCleanup(
              accountGeneration: account,
              isCurrent: isCleanupCurrent,
            ),
            presentation: currentWidgetPresentation(),
            clearCachedWidgetData: clearWidgetCache,
          );
          if (!result.barrierConfirmed) {
            throw StateError('native widget barrier: ${result.status}');
          }
        } else if (!await clearWidgetCache()) {
          throw StateError('legacy widget storage clear failed');
        }
        if (!isCleanupCurrent()) {
          throw StateError('widget cleanup context superseded');
        }
      } catch (error, stackTrace) {
        debugPrint('[auth] widget cleanup blocked: $error\n$stackTrace');
        Error.throwWithStackTrace(
          const AccountLocalDataCleanupBlockedException(
            '小组件账号数据未能安全清除，请重试切换账号。',
          ),
          stackTrace,
        );
      }
      cloudSyncStartSerial++;
      Object? criticalCleanupError;
      StackTrace? criticalCleanupStackTrace;

      void rememberCriticalFailure(Object error, StackTrace stackTrace) {
        criticalCleanupError ??= error;
        criticalCleanupStackTrace ??= stackTrace;
      }

      void throwIfCriticalCleanupFailed() {
        if (criticalCleanupError == null) return;
        Error.throwWithStackTrace(
          AccountLocalDataCleanupBlockedException(
            '本机账号数据或提醒未能安全清理，已暂停${reason == 'logout' ? '退出登录' : '切换账号'}。请稍后重试。',
          ),
          criticalCleanupStackTrace!,
        );
      }

      Future<void> guarded(
        String label,
        Future<void> Function() task, {
        bool critical = false,
      }) async {
        try {
          await task();
        } catch (e, st) {
          debugPrint('[auth] account cleanup $label failed: $e\n$st');
          if (critical) rememberCriticalFailure(e, st);
        }
      }

      void guardedSync(String label, void Function() task) {
        try {
          task();
        } catch (e, st) {
          debugPrint('[auth] account cleanup $label failed: $e\n$st');
          rememberCriticalFailure(e, st);
        }
      }

      void deleteDetachedLocalFiles(AccountLocalFileCleanup cleanup) {
        unawaited(() async {
          try {
            await cleanup.delete();
          } catch (e, st) {
            debugPrint('[auth] detached account files cleanup failed: $e\n$st');
            await Future<void>.delayed(const Duration(seconds: 2));
            try {
              await cleanup.delete();
            } catch (retryError, retryStack) {
              debugPrint(
                '[auth] detached account files cleanup retry failed: '
                '$retryError\n$retryStack',
              );
            }
          }
        }());
      }

      if (_reminderSchedulerReady) {
        _reminderScheduler.suspendForAccountChange();
      }
      LocationGeofenceService.suspendForAccountChange();
      _digestReminderCoordinator.suspendForAccountChange();
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      try {
        await guarded('cloud sync pause', () async {
          await cloudSyncProvider.suspendForAccountChange();
        }, critical: true);

        await cloudSyncProvider.suppressDirtyMarkWhile(() async {
          await _digestReminderCoordinator.drain();
          if (_reminderSchedulerReady) {
            await guarded('daily digest timers', () async {
              if (!await _cancelDailyDigestReminderIds(
                notificationService,
                baseId: 880017,
                slotCount: 3,
              )) {
                throw StateError('Daily digest cancellation incomplete');
              }
            }, critical: true);
          }
          // Drain running batches and cancel their exact IDs before the global
          // queue sweep, so late registrations cannot survive that sweep.
          if (_reminderSchedulerReady) {
            await guarded(
              'reminder scheduler state',
              _reminderScheduler.resetInMemoryState,
              critical: true,
            );
          }
          await Future.wait<void>([
            guarded(
              'notifications',
              notificationService.cancelAll,
              critical: true,
            ),
            guarded('alarms', AlarmService.instance.cancelAll, critical: true),
            guarded('geofences', () async {
              if (!PlatformInfo.isAndroid) return;
              final result = await LocationGeofenceService.clearReminders();
              if (result.status != 'cleared' || result.scheduledCount != 0) {
                throw StateError(result.message ?? '地理围栏清理失败：${result.status}');
              }
            }, critical: true),
          ]);
          throwIfCriticalCleanupFailed();
          await guarded(
            'cloud sync state',
            cloudSyncProvider.resetForAccountChange,
            critical: true,
          );
          throwIfCriticalCleanupFailed();
          await guarded(
            'account prefs first pass',
            AccountLocalDataCleaner.clearSharedPreferences,
            critical: true,
          );
          guardedSync('todos', todoProvider.resetLocalState);
          guardedSync('habits', habitProvider.resetLocalState);
          guardedSync('pomodoro', pomodoroProvider.resetLocalState);
          await guarded('pomodoro running snapshot', () async {
            if (!await pomodoroProvider.waitForSnapshotWrites()) {
              throw StateError('专注运行状态清理失败');
            }
          }, critical: true);
          guardedSync('countdowns', countdownProvider.resetLocalState);
          await _yieldForNextFrame(const Duration(milliseconds: 16));
          guardedSync('anniversaries', anniversaryProvider.resetLocalState);
          guardedSync('diary', diaryProvider.resetLocalState);
          guardedSync('goals', goalProvider.resetLocalState);
          guardedSync('courses', courseProvider.resetLocalState);
          guardedSync('notes', noteProvider.resetLocalState);
          guardedSync('calendar', calendarProvider.resetLocalState);
          guardedSync('time audit', timeAuditProvider.resetLocalState);
          await _yieldForNextFrame(const Duration(milliseconds: 16));
          guardedSync(
            'location reminders',
            locationReminderProvider.resetLocalState,
          );
          guardedSync('user', userProvider.resetLocalState);
          await guarded(
            'user profile cache',
            () => userProvider.clearAccountProfileCache(),
          );
          guardedSync('theme', themeProvider.resetLocalState);
          guardedSync('achievements', achievementProvider.resetLocalState);
          // 切号清空后，云端 `achievement_states` 尚未回填本地解锁基线。
          // 在此期间抑制成就解锁反馈，等基线恢复（或安全超时）后再放开，
          // 否则早已解锁且已读的成就会被重算成“新解锁”而重复弹窗。
          guardedSync(
            'achievements feedback suppression',
            achievementProvider.suppressUnlockFeedback,
          );
          guardedSync(
            'quick capture templates',
            quickCaptureTemplateProvider.resetLocalState,
          );
          guardedSync(
            'custom focus sounds',
            customFocusSoundProvider.resetLocalState,
          );
          guardedSync('focus rooms', focusRoomProvider.resetLocalState);
          guardedSync('shares', shareProvider.resetLocalState);
          await _yieldForNextFrame(const Duration(milliseconds: 16));
          guardedSync('calendar sync', calendarSyncProvider.resetLocalState);
          guardedSync('ai service', aiService.resetLocalState);
          await guarded(
            'ai history writes',
            aiService.drainPendingHistoryWrites,
            critical: true,
          );
          guardedSync(
            'notification service',
            notificationService.resetLocalState,
          );
          guardedSync('preferences', preferencesProvider.resetLocalState);
          await guarded(
            'preferences reload',
            preferencesProvider.loadFromStorage,
            critical: true,
          );
          unawaited(() async {
            await Future<void>.delayed(const Duration(seconds: 2));
            await guarded(
              'reminder ringtone native settings',
              ReminderRingtoneSettings.applyPersistedSettingsToNative,
            );
          }());

          // Run a second pass after async platform cancellations so a stale sync
          // completion racing with cleanup cannot leave account data behind.
          await guarded(
            'account prefs second pass',
            AccountLocalDataCleaner.clearSharedPreferences,
            critical: true,
          );
          throwIfCriticalCleanupFailed();
          await guarded('account files detach', () async {
            final cleanup =
                await AccountLocalDataCleaner.quarantineLocalFiles();
            deleteDetachedLocalFiles(cleanup);
          }, critical: true);
        });

        unawaited(() async {
          await Future<void>.delayed(const Duration(seconds: 8));
          await guarded('home widget refresh', () async {
            await HomeWidgetService.init();
            final presentationGeneration = homeWidgetPresentationGeneration;
            await _pushHomeWidget(
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
              preferencesProvider,
              isPresentationCurrent: () =>
                  homeWidgetPresentationGeneration == presentationGeneration,
            );
          });
        }());
        throwIfCriticalCleanupFailed();
        // 安全兜底：即便云端基线回填未触发静默刷新（如退出登录、关闭自动同步），
        // 也要在切号窗口后恢复解锁反馈，避免开关永久卡在抑制态。
        // 捕获本轮抑制代次：若 30s 内又发生一次切号，旧定时器不会误恢复新一轮抑制。
        final suppressionGeneration =
            achievementProvider.unlockSuppressionGeneration;
        Future<void>.delayed(const Duration(seconds: 30), () {
          achievementProvider.resumeUnlockFeedback(
            generation: suppressionGeneration,
          );
        });
      } finally {
        cloudSyncProvider.resumeForActiveAccount();
        LocationGeofenceService.resumeForActiveAccount();
        if (_reminderSchedulerReady) {
          _reminderScheduler.resumeForActiveAccount();
        }
      }
    });
  }

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
    final profile = userProvider.profile;
    if (profile.username == name &&
        profile.displayName == (state.displayName ?? '') &&
        profile.email == (state.email ?? '') &&
        profile.emailVerified == state.emailVerified &&
        profile.avatarUrl == (state.avatar ?? '') &&
        profile.bio == (state.bio ?? '')) {
      return;
    }
    await cloudSyncProvider.suppressDirtyMarkWhile(
      () => userProvider.applyAccountSnapshot(
        username: name,
        displayName: state.displayName ?? '',
        email: state.email ?? '',
        emailVerified: state.emailVerified,
        avatarUrl: state.avatar ?? '',
        bio: state.bio ?? '',
      ),
    );
  };
  Object? accountPayloadValue(Map<dynamic, dynamic> data, List<String> keys) {
    for (final key in keys) {
      if (data[key] != null) return data[key];
    }
    for (final wrapperKey in const ['user', 'profile', 'data', 'payload']) {
      final wrapper = data[wrapperKey];
      if (wrapper is Map) {
        final nested = accountPayloadValue(wrapper, keys);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  authProvider.onAccountPayloadChanged = (payload) async {
    final themeState = accountPayloadValue(payload, const [
      'theme_shop_state',
      'themeShopState',
    ]);
    final rewards = accountPayloadValue(payload, const [
      'virtual_rewards',
      'virtualRewards',
      'rewards',
    ]);
    if (themeState is! Map && rewards is! Map) return;
    await cloudSyncProvider.suppressDirtyMarkWhile(() async {
      if (themeState is Map) {
        await themeProvider.applyShopStateFromServer(themeState);
      }
      if (rewards is Map) {
        await achievementProvider.applyRewardsSnapshot(rewards);
      }
    });
  };
  authProvider.onAccountIdentityChanging = (_, _) =>
      clearAccountLocalData(reason: 'account switch');
  authProvider.onBeforeAccountLogout = () =>
      flushPendingLocalChangesBeforeAccountChange(reason: 'logout');
  authProvider.onAccountLoggedOut = () =>
      clearAccountLocalData(reason: 'logout');

  void handleDeepLink(Uri uri) {
    final request = _widgetNavigationRequests.capture();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleWidgetUri(uri, pomodoroProvider, navigationRequest: request);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  DeepLinkService.onLink = handleDeepLink;
  DeepLinkService.onSharedText = receiveSharedText;
  await _startupGuard('deep links', () => DeepLinkService.init());

  final criticalStorageStartup = RequiredStorageStartup();
  Future<void> ensureCriticalLocalStorageStartup() {
    return criticalStorageStartup.ensure(
      isCurrent: () => !AccountPreferenceWrites.isBoundaryActive,
      run: (load) => cloudSyncProvider.suppressDirtyMarkWhile(
        () => _runSyncReloadTasksInBatches([
          // 关键 Provider 必须成功加载，失败后允许显式重试。
          () => load(() => appLockProvider.loadFromStorage()),
          () => load(() => localeProvider.loadFromStorage()),
          () => load(
            () => authProvider.loadFromStorage(refreshServerConfig: false),
          ),
          () => load(() => themeProvider.loadFromStorage()),
          () => load(() => preferencesProvider.loadFromStorage()),
          () => load(() => userProvider.loadFromStorage()),
          () => load(() => cloudSyncProvider.loadFromStorage()),
        ]),
      ),
    );
  }

  await _runStartupStoragePhase('critical local storage', [
    ensureCriticalLocalStorageStartup,
  ]);

  pomodoroProvider.attachPreferences(preferencesProvider, auth: authProvider);

  final reminderStorageStartup = RequiredStorageStartup();
  final deferredStorageStartup = RequiredStorageStartup();
  var reminderProvidersHydrated = false;
  Future<void> ensureReminderProvidersStartup() async {
    await ensureCriticalLocalStorageStartup();
    if (authProvider.isLocalAccountDataBlocked) return Future<void>.value();
    if (!reminderStorageStartup.ready) reminderProvidersHydrated = false;
    final account = AccountLocalDataCleaner.accountDataGeneration;
    final session = authProvider.sessionGeneration;
    bool isCurrent() =>
        !authProvider.isLocalAccountDataBlocked &&
        !authProvider.isAccountTransitionInProgress &&
        !AccountPreferenceWrites.isBoundaryActive &&
        authProvider.sessionGeneration == session &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(account);
    return reminderStorageStartup
        .ensure(
          isCurrent: isCurrent,
          run: (load) => cloudSyncProvider.suppressDirtyMarkWhile(
            () => _runSyncReloadTasksInBatches([
              () => load(() => todoProvider.loadFromStorage()),
              () => load(() => habitProvider.loadFromStorage()),
              () => load(() => pomodoroProvider.loadFromStorage()),
              () => load(() => countdownProvider.loadFromStorage()),
              () => load(() => anniversaryProvider.loadFromStorage()),
              () => load(() => goalProvider.loadFromStorage()),
              () => load(() => timeAuditProvider.loadFromStorage()),
            ]),
          ),
        )
        .then((_) {
          if (reminderStorageStartup.ready && isCurrent()) {
            reminderProvidersHydrated = true;
          }
        });
  }

  var deferredLocalStorageHydrated = false;
  Future<void> ensureDeferredLocalStorageStartup() async {
    await ensureCriticalLocalStorageStartup();
    if (authProvider.isLocalAccountDataBlocked) return Future<void>.value();
    if (!deferredStorageStartup.ready) deferredLocalStorageHydrated = false;
    final account = AccountLocalDataCleaner.accountDataGeneration;
    final session = authProvider.sessionGeneration;
    bool isCurrent() =>
        !authProvider.isLocalAccountDataBlocked &&
        !authProvider.isAccountTransitionInProgress &&
        !AccountPreferenceWrites.isBoundaryActive &&
        authProvider.sessionGeneration == session &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(account);
    // Scope preparation stays outside consumer enrollment and before the
    // deferred-ready fast path. Readonly restoration never adopts legacy rows
    // or initializes a new identity, and OAuth failure must not block ICS.
    final oauthWasReady = calendarSyncProvider.isOAuthReady;
    if (isCurrent() &&
        !oauthWasReady &&
        (authProvider.state.isLoggedIn || authProvider.isGuestWorkspaceReady)) {
      try {
        await calendarSyncProvider.prepareOAuthScope(isCurrent: isCurrent);
      } catch (_) {
        debugPrint('[CalendarSync] OAuth scope is not prepared');
      }
      if (!isCurrent()) return;
      if (calendarSyncProvider.isOAuthReady && deferredStorageStartup.ready) {
        await calendarSyncProvider.loadFromStorage(isCurrent: isCurrent);
        if (!isCurrent()) return;
      }
    }
    return deferredStorageStartup
        .ensure(
          isCurrent: isCurrent,
          run: (load) async {
            await ensureReminderProvidersStartup();
            await cloudSyncProvider.suppressDirtyMarkWhile(
              () => _runSyncReloadTasksInBatches([
                () => load(() => diaryProvider.loadFromStorage()),
                () => load(() => courseProvider.loadFromStorage()),
                () =>
                    load(() => quickCaptureTemplateProvider.loadFromStorage()),
                () => load(() => noteProvider.loadFromStorage()),
                () => load(() => achievementProvider.loadFromStorage()),
                () => load(() => customFocusSoundProvider.loadFromStorage()),
                () => load(() => focusRoomProvider.loadFromStorage()),
                () => load(() => aiService.loadFromStorage()),
                () => load(() => locationReminderProvider.loadFromStorage()),
                () => load(() => calendarSyncProvider.loadFromStorage()),
                () => load(() => calendarProvider.loadFromStorage()),
              ]),
            );
          },
        )
        .then((_) {
          if (deferredStorageStartup.ready && isCurrent()) {
            deferredLocalStorageHydrated = true;
          }
        });
  }

  Future<void>? deferredPlatformStartup;

  _ensureHomeWidgetDataReady = ensureDeferredLocalStorageStartup;

  Future<void>? homeWidgetLaunchStartup;
  Future<void> ensureHomeWidgetLaunchStartup() {
    final existing = homeWidgetLaunchStartup;
    if (existing != null) return existing;
    homeWidgetLaunchStartup = () async {
      final initialized = await HomeWidgetService.init();
      if (!initialized) {
        debugPrint('[HomeWidget] startup init completed with failures');
      }
      if (PlatformInfo.isAndroid) {
        await HomeWidgetService.refreshPublishedWidgets();
      }
    }();
    return homeWidgetLaunchStartup!;
  }

  Future<void> ensureDeferredPlatformStartup() {
    final existing = deferredPlatformStartup;
    if (existing != null) return existing;
    deferredPlatformStartup = () async {
      await _runSyncReloadTasksInBatches([
        () => _startupGuard('notifications', () => notificationService.init()),
        () =>
            _startupGuard('alarm service', () => AlarmService.instance.init()),
        () => _startupGuard('system tray', () => systemTray.init()),
        () => _startupGuard('home widget', ensureHomeWidgetLaunchStartup),
      ]);
      try {
        _initialExactAlarmGranted = await AlarmService.instance
            .hasExactAlarmPermission()
            .timeout(const Duration(seconds: 3));
      } catch (e, st) {
        debugPrint('[startup] exact alarm probe failed: $e\n$st');
        _initialExactAlarmGranted = false;
      }
    }();
    return deferredPlatformStartup!;
  }

  pomodoroProvider.attachNotifier(notificationService);
  pomodoroProvider.attachTimeAudit(timeAuditProvider);
  todoProvider.timeAudit = timeAuditProvider;
  habitProvider.timeAudit = timeAuditProvider;
  goalProvider.timeAudit = timeAuditProvider;
  goalProvider.canEditWorkspace = shareProvider.canEdit;
  todoProvider.canEditWorkspace = shareProvider.canEdit;
  achievementProvider.attachNotificationService(notificationService);
  shareProvider.apiClientGetter = () => authProvider.client;
  shareProvider.userIdGetter = () => authProvider.state.userId;
  focusRoomProvider.apiClientGetter = () => authProvider.client;
  // 让 PomodoroProvider 监听 AppLifecycle，以便在 resumed 时恢复白噪音。
  pomodoroProvider.attachLifecycle();

  // 提醒调度器：监听数据变化，幂等地同步本地通知队列
  final reminderScheduler = ReminderScheduler(
    notificationService,
    email: BackendReminderEmailSink(() => authProvider.client),
    popup: ForegroundReminderPopupSink(
      contextGetter: () => mainShellKey.currentContext,
      onOpenPayload: (payload) {
        final uri = Uri.tryParse(payload);
        if (uri == null) return;
        _handleWidgetUri(
          uri,
          pomodoroProvider,
          origin: WidgetLinkOrigin.internalNotification,
        );
      },
      notificationFallback: notificationService,
    ),
  );
  _reminderScheduler = reminderScheduler;
  _reminderSchedulerReady = true;
  if (authProvider.isLocalAccountDataBlocked) {
    reminderScheduler.suspendForAccountChange();
    LocationGeofenceService.suspendForAccountChange();
    _digestReminderCoordinator.suspendForAccountChange();
  }
  void syncQuietHoursPolicyToSchedulers() {
    final policy = preferencesProvider.quietHoursPolicy;
    reminderScheduler.updateQuietHours(policy);
    notificationService.updateQuietHours(policy);
  }

  syncQuietHoursPolicyToSchedulers();
  // 注入到 Provider，供 Provider 内部的局部 hook（例如 postponeOverdue、
  // onTimezoneChanged）转发调度请求。
  todoProvider.scheduler = reminderScheduler;
  habitProvider.scheduler = reminderScheduler;
  anniversaryProvider.scheduler = reminderScheduler;
  countdownProvider.scheduler = reminderScheduler;
  goalProvider.scheduler = reminderScheduler;
  courseProvider.scheduler = reminderScheduler;
  calendarProvider.scheduler = reminderScheduler;
  var reminderResyncInFlight = false;
  var reminderResyncQueued = false;
  Timer? reminderResyncDebounce;
  Completer<void>? reminderResyncDebounceCompleter;
  String reminderResyncReason = 'startup';
  var startupReminderResyncQueued = false;
  Future<void> Function()? reminderAuxiliaryResync;
  Future<void> resyncReminders() async {
    if (reminderResyncInFlight) {
      reminderResyncQueued = true;
      return;
    }
    reminderResyncInFlight = true;
    // 单条 sync 失败不应中断整轮调度（R2.8 / T-14）。
    Future<void> guarded(String label, Future<void> Function() task) async {
      try {
        await task();
      } catch (e, st) {
        debugPrint('[resyncReminders] $label failed: $e\n$st');
      }
    }

    try {
      await reminderScheduler.runReconciliationBatch((batch) async {
        await guarded(
          'syncTodos',
          () => reminderScheduler.syncTodos(
            todoProvider.todos,
            allowJustMissedOneShotReminders: false,
            batch: batch,
          ),
        );
        await _yieldForNextFrame(const Duration(milliseconds: 16));
        await guarded(
          'syncHabits',
          () =>
              reminderScheduler.syncHabits(habitProvider.habits, batch: batch),
        );
        await _yieldForNextFrame(const Duration(milliseconds: 16));
        await guarded(
          'syncAnniversaries',
          () => reminderScheduler.syncAnniversaries(
            anniversaryProvider.items,
            batch: batch,
          ),
        );
        await _yieldForNextFrame(const Duration(milliseconds: 16));
        await guarded(
          'syncCountdowns',
          () => reminderScheduler.syncCountdowns(
            countdownProvider.items,
            batch: batch,
          ),
        );
        await _yieldForNextFrame(const Duration(milliseconds: 16));
        await guarded(
          'syncGoals',
          () => reminderScheduler.syncGoals(goalProvider.goals, batch: batch),
        );
        await _yieldForNextFrame(const Duration(milliseconds: 16));
        await guarded(
          'syncCourses',
          () => reminderScheduler.syncCourses(
            courseProvider.courses,
            settings: courseProvider.settings,
            batch: batch,
          ),
        );
        await _yieldForNextFrame(const Duration(milliseconds: 16));
        await guarded(
          'syncCalendarEvents',
          () => reminderScheduler.syncCalendarEvents(
            calendarProvider.events,
            batch: batch,
          ),
        );
        await _yieldForNextFrame(const Duration(milliseconds: 16));
        await guarded('syncAuxiliaryReminderSchedules', () async {
          final task = reminderAuxiliaryResync;
          if (task != null) await task();
        });
      });
    } finally {
      reminderResyncInFlight = false;
    }
    if (reminderResyncQueued) {
      reminderResyncQueued = false;
      await resyncReminders();
    }
  }

  Future<void> queueFullReminderResync({
    Duration delay = const Duration(milliseconds: 350),
    String reason = 'manual',
  }) async {
    if (!reminderProvidersHydrated) {
      await ensureReminderProvidersStartup();
    }
    reminderResyncReason = reason;
    reminderResyncDebounce?.cancel();
    final completer = reminderResyncDebounceCompleter ??= Completer<void>();
    reminderResyncDebounce = Timer(delay, () {
      reminderResyncDebounce = null;
      final pending = reminderResyncDebounceCompleter;
      reminderResyncDebounceCompleter = null;
      unawaited(() async {
        try {
          await resyncReminders();
          if (pending != null && !pending.isCompleted) pending.complete();
        } catch (e, st) {
          debugPrint(
            '[queueFullReminderResync] $reminderResyncReason failed: $e\n$st',
          );
          if (pending != null && !pending.isCompleted) {
            pending.completeError(e, st);
          }
        }
      }());
    });
    return completer.future;
  }

  Future<void> queueStartupReminderResync({
    required Duration delay,
    required String reason,
  }) async {
    if (startupReminderResyncQueued) return;
    if (!reminderProvidersHydrated) {
      await ensureReminderProvidersStartup();
    }
    if (startupReminderResyncQueued) return;
    startupReminderResyncQueued = true;
    await queueFullReminderResync(delay: delay, reason: reason);
  }

  _queueFullReminderResyncCallback = queueFullReminderResync;
  goalProvider.reminderResyncRequester = () => queueFullReminderResync(
    delay: Duration.zero,
    reason: 'goal timezone changed',
  );
  await notificationService.setHistoryLimit(
    preferencesProvider.notificationHistoryLimit,
  );
  preferencesProvider.onAppTimeZoneChanged = () => queueFullReminderResync(
    delay: Duration.zero,
    reason: 'app timezone changed',
  );

  Future<void> syncLocationGeofences() async {
    if (!locationReminderProvider.isLoaded) return;
    try {
      await LocationGeofenceService.syncReminders(
        locationReminderProvider.reminders,
      );
    } catch (e, st) {
      debugPrint('[location geofence] sync failed: $e\n$st');
    }
  }

  locationReminderProvider.addListener(syncLocationGeofences);

  // 本地有改动 → 交给云同步侧排队自动同步。
  var mirroringCloudSyncError = false;
  void markDirty() {
    if (mirroringCloudSyncError) return;
    cloudSyncProvider.markPendingLocalChange();
  }

  todoProvider.onLocalMutationPersisted =
      cloudSyncProvider.markUserMutationPendingDurably;
  todoProvider.onArchiveMutationPersisted =
      cloudSyncProvider.markArchiveMutationPendingDurably;
  habitProvider.onLocalMutationPersisted =
      cloudSyncProvider.markUserMutationPending;
  anniversaryProvider.onLocalMutationPersisted =
      cloudSyncProvider.markUserMutationPending;
  countdownProvider.onLocalMutationPersisted =
      cloudSyncProvider.markUserMutationPending;
  goalProvider.onLocalMutationPersisted =
      cloudSyncProvider.markUserMutationPending;
  noteProvider.onLocalMutationPersisted =
      cloudSyncProvider.markUserMutationPending;
  diaryProvider.onLocalMutationPersisted =
      cloudSyncProvider.markUserMutationPending;
  courseProvider.onLocalMutationPersisted =
      cloudSyncProvider.markUserMutationPending;
  timeAuditProvider.onLocalMutationPersisted =
      cloudSyncProvider.markUserMutationPending;
  quickCaptureTemplateProvider.onLocalMutationPersisted =
      cloudSyncProvider.markUserQuickCaptureTemplatesChanged;
  locationReminderProvider.onLocalMutationPersisted =
      cloudSyncProvider.markUserMutationPending;
  userProvider.onLocalMutationPersisted =
      cloudSyncProvider.markUserMutationPending;

  // 单向透传最近的云同步状态到 TodoProvider，使本地优先的保存流程能在
  // 云端同步未完成、不可用或最终失败时给用户显式反馈（完成时清除）。
  // UI 层只读 `todoProvider.cloudSyncNotice`，不直接持有 CloudSyncProvider，
  // 以满足"UI 层不暴露同步入口"的架构守卫。
  TodoCloudSyncNotice? buildTodoCloudSyncNotice() {
    final lastError = cloudSyncProvider.lastError?.trim();
    if (lastError?.isNotEmpty == true) {
      return TodoCloudSyncNotice(
        message: lastError!,
        level: TodoCloudSyncNoticeLevel.error,
      );
    }
    final retryStatus = cloudSyncProvider.syncRetryStatus?.trim();
    if (retryStatus?.isNotEmpty == true) {
      return TodoCloudSyncNotice(
        message: retryStatus!,
        level: TodoCloudSyncNoticeLevel.warning,
      );
    }
    final unavailableStatus = cloudSyncProvider.syncUnavailableStatus?.trim();
    if (cloudSyncProvider.hasPendingChanges &&
        unavailableStatus?.isNotEmpty == true) {
      return TodoCloudSyncNotice(
        message: unavailableStatus!,
        level: TodoCloudSyncNoticeLevel.warning,
      );
    }
    if (cloudSyncProvider.hasPendingChanges &&
        !cloudSyncProvider.config.autoSync) {
      return TodoCloudSyncNotice(
        message: const CloudSyncNotice(
          CloudSyncNoticeKind.automaticSyncOff,
        ).render(),
        level: TodoCloudSyncNoticeLevel.warning,
      );
    }
    final queuedRemotePullStatus = cloudSyncProvider.queuedRemotePullStatus
        ?.trim();
    if (queuedRemotePullStatus?.isNotEmpty == true) {
      return TodoCloudSyncNotice(
        message: queuedRemotePullStatus!,
        level: TodoCloudSyncNoticeLevel.info,
      );
    }
    return null;
  }

  void mirrorCloudSyncError() {
    mirroringCloudSyncError = true;
    try {
      todoProvider.cloudSyncNotice = buildTodoCloudSyncNotice();
    } finally {
      mirroringCloudSyncError = false;
    }
  }

  cloudSyncProvider.addListener(mirrorCloudSyncError);
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
  var lastUserProfileDirtySignature = userProvider.syncSignature();
  void markUserProfileDirtyOnEditableChange() {
    final next = userProvider.syncSignature();
    if (next == lastUserProfileDirtySignature) return;
    lastUserProfileDirtySignature = next;
    markDirty();
  }

  userProvider.addListener(markUserProfileDirtyOnEditableChange);
  var lastAchievementDirtySignature = _achievementPersistedSignature(
    achievementProvider,
  );
  void markAchievementDirtyOnPersistedChange() {
    final next = _achievementPersistedSignature(achievementProvider);
    if (next == lastAchievementDirtySignature) return;
    lastAchievementDirtySignature = next;
    if (achievementProvider.consumeServerConfirmedRewardsChange()) return;
    markDirty();
  }

  achievementProvider.addListener(markAchievementDirtyOnPersistedChange);
  focusRoomProvider.onLocalChanged = cloudSyncProvider.markUserMutationPending;
  themeProvider.addListener(() {
    if (themeProvider.consumeServerConfirmedChange()) return;
    markDirty();
  });
  calendarProvider.onLocalEventsChanged =
      cloudSyncProvider.markUserMutationPending;
  calendarProvider.localEventReminderCanceller =
      notificationService.cancelCalendarReminder;
  preferencesProvider.onChangedKeys = (keys) {
    cloudSyncProvider.markUserPreferencesChanged(keys);
    if (keys.any(PreferencesProvider.quietHoursPreferenceKeys.contains)) {
      syncQuietHoursPolicyToSchedulers();
      unawaited(
        _startupGuard('quiet hours reminder resync', () async {
          await queueFullReminderResync(
            delay: Duration.zero,
            reason: 'quiet hours changed',
          );
        }),
      );
    }
  };
  ReminderRingtoneSettings.onChanged = (keys) {
    cloudSyncProvider.markUserPreferencesChanged(keys);
    if (keys.contains(ReminderRingtoneSettings.soundPreferenceKey) ||
        keys.contains(ReminderRingtoneSettings.volumePreferenceKey)) {
      unawaited(
        _startupGuard('ringtone reminder resync', () async {
          await _refreshReminderRingtoneChannels();
          await queueFullReminderResync(
            delay: Duration.zero,
            reason: 'ringtone settings changed',
          );
        }),
      );
    }
  };

  Timer? userStatsRefreshDebounce;
  void refreshUserStatsNow() {
    userProvider.recalc(
      completedTodos: todoProvider.completedTodos.length,
      totalFocusMinutes: pomodoroProvider.totalFocusMinutes,
      currentStreak: habitProvider.longestCurrentStreak,
      bestStreak: habitProvider.longestBestStreak,
    );
  }

  void queueUserStatsRefresh({
    Duration delay = const Duration(milliseconds: 700),
  }) {
    userStatsRefreshDebounce?.cancel();
    userStatsRefreshDebounce = Timer(delay, refreshUserStatsNow);
  }

  todoProvider.addListener(queueUserStatsRefresh);
  habitProvider.addListener(queueUserStatsRefresh);
  var lastPomodoroStatsSignature = _pomodoroSessionsSignature(pomodoroProvider);
  void refreshUserStatsOnPomodoroSummaryChange() {
    final next = _pomodoroSessionsSignature(pomodoroProvider);
    if (next == lastPomodoroStatsSignature) return;
    lastPomodoroStatsSignature = next;
    queueUserStatsRefresh();
  }

  pomodoroProvider.addListener(refreshUserStatsOnPomodoroSummaryChange);

  bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool isInRange(DateTime date, DateTime start, DateTime end) =>
      !date.isBefore(start) && date.isBefore(end);

  String dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Timer? achievementRefreshDebounce;
  var achievementRefreshInFlight = false;
  var achievementRefreshQueued = false;
  var achievementRefreshQueuedSilent = false;
  String? achievementsCacheDayKey;
  var achievementsTodoDirty = true;
  var achievementsHabitDirty = true;
  var achievementsPomodoroDirty = true;
  var achievementsDiaryDirty = true;
  var cachedTodayCompletedTodos = 0;
  var cachedWeeklyCompletedTodos = 0;
  var cachedTodoActiveDays = <String>{};
  var cachedTodayHabitCheckIns = 0;
  var cachedWeeklyHabitCheckIns = 0;
  var cachedHabitActiveDays = <String>{};
  var cachedTodayFocusMinutes = 0;
  var cachedWeeklyFocusMinutes = 0;
  var cachedPomodoroActiveDays = <String>{};
  String? cachedPomodoroAchievementSig;
  var cachedTodayDiaryEntries = 0;
  var cachedWeeklyDiaryEntries = 0;
  var cachedDiaryActiveDays = <String>{};

  Future<void> refreshAchievementsNow({
    bool silentUnlockFeedback = false,
  }) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final currentDayKey = dateKey(today);
    final forceRecompute =
        silentUnlockFeedback || achievementsCacheDayKey != currentDayKey;
    if (forceRecompute) {
      achievementsCacheDayKey = currentDayKey;
      achievementsTodoDirty = true;
      achievementsHabitDirty = true;
      achievementsPomodoroDirty = true;
      achievementsDiaryDirty = true;
    }

    if (achievementsTodoDirty) {
      final days = <String>{};
      var todayDone = 0;
      var weeklyDone = 0;
      for (final todo in todoProvider.todos) {
        if (!todo.isCompleted) continue;
        final completedAt = todo.completedAt ?? todo.date;
        if (isSameDay(completedAt, today)) todayDone++;
        if (isInRange(completedAt, weekStart, weekEnd)) {
          weeklyDone++;
          days.add(dateKey(completedAt));
        }
      }
      cachedTodayCompletedTodos = todayDone;
      cachedWeeklyCompletedTodos = weeklyDone;
      cachedTodoActiveDays = days;
      achievementsTodoDirty = false;
    }

    if (achievementsHabitDirty) {
      final days = <String>{};
      final todayCheckIns = habitProvider.habits
          .where((habit) => habit.activeForDate(today))
          .fold<int>(0, (sum, habit) => sum + habit.countForDate(today));
      var weeklyCheckIns = 0;
      for (final habit in habitProvider.habits) {
        for (final entry in habit.completions.entries) {
          final date = DateTime.tryParse(entry.key);
          if (date == null || !isInRange(date, weekStart, weekEnd)) continue;
          if (!habit.activeForDate(date)) continue;
          weeklyCheckIns += entry.value;
          if (entry.value > 0) days.add(dateKey(date));
        }
      }
      cachedTodayHabitCheckIns = todayCheckIns;
      cachedWeeklyHabitCheckIns = weeklyCheckIns;
      cachedHabitActiveDays = days;
      achievementsHabitDirty = false;
    }

    final currentPomodoroSig = _pomodoroSessionsSignature(pomodoroProvider);
    if (achievementsPomodoroDirty ||
        cachedPomodoroAchievementSig != currentPomodoroSig) {
      final days = <String>{};
      var todayMinutes = 0;
      var weeklyMinutes = 0;
      for (final session in pomodoroProvider.sessions) {
        if (session.type != PomodoroType.focus) continue;
        if (isInRange(session.endTime, today, tomorrow)) {
          todayMinutes += session.durationSeconds;
        }
        if (isInRange(session.endTime, weekStart, weekEnd)) {
          weeklyMinutes += session.durationSeconds;
          days.add(dateKey(session.endTime));
        }
      }
      cachedTodayFocusMinutes = todayMinutes ~/ 60;
      cachedWeeklyFocusMinutes = weeklyMinutes ~/ 60;
      cachedPomodoroActiveDays = days;
      cachedPomodoroAchievementSig = currentPomodoroSig;
      achievementsPomodoroDirty = false;
    }

    if (achievementsDiaryDirty) {
      final days = <String>{};
      var todayDiaries = 0;
      var weeklyDiaries = 0;
      for (final entry in diaryProvider.entries) {
        if (isSameDay(entry.date, today)) todayDiaries++;
        if (isInRange(entry.date, weekStart, weekEnd)) {
          weeklyDiaries++;
          days.add(dateKey(entry.date));
        }
      }
      cachedTodayDiaryEntries = todayDiaries;
      cachedWeeklyDiaryEntries = weeklyDiaries;
      cachedDiaryActiveDays = days;
      achievementsDiaryDirty = false;
    }

    final activeDays = <String>{
      ...cachedTodoActiveDays,
      ...cachedHabitActiveDays,
      ...cachedPomodoroActiveDays,
      ...cachedDiaryActiveDays,
    };
    final todayCompletedTodos = cachedTodayCompletedTodos;
    final weeklyCompletedTodos = cachedWeeklyCompletedTodos;
    final todayFocusMinutes = cachedTodayFocusMinutes;
    final weeklyFocusMinutes = cachedWeeklyFocusMinutes;

    await achievementProvider.updateContext(
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
        todayHabitCheckIns: cachedTodayHabitCheckIns,
        todayFocusMinutes: todayFocusMinutes,
        todayDiaryEntries: cachedTodayDiaryEntries,
        weeklyCompletedTodos: weeklyCompletedTodos,
        weeklyHabitCheckIns: cachedWeeklyHabitCheckIns,
        weeklyFocusMinutes: weeklyFocusMinutes,
        weeklyDiaryEntries: cachedWeeklyDiaryEntries,
        weeklyActiveDays: activeDays.length,
      ),
      silentUnlockFeedback: silentUnlockFeedback,
    );
  }

  Future<void> runQueuedAchievementRefresh({
    bool silentUnlockFeedback = false,
  }) async {
    if (achievementRefreshInFlight) {
      achievementRefreshQueued = true;
      achievementRefreshQueuedSilent |= silentUnlockFeedback;
      return;
    }
    achievementRefreshInFlight = true;
    try {
      await refreshAchievementsNow(silentUnlockFeedback: silentUnlockFeedback);
    } catch (e, st) {
      debugPrint('[achievements] refresh failed: $e\n$st');
    } finally {
      achievementRefreshInFlight = false;
    }
    if (achievementRefreshQueued) {
      achievementRefreshQueued = false;
      final queuedSilent = achievementRefreshQueuedSilent;
      achievementRefreshQueuedSilent = false;
      achievementRefreshDebounce?.cancel();
      achievementRefreshDebounce = Timer(const Duration(seconds: 2), () {
        unawaited(
          runQueuedAchievementRefresh(silentUnlockFeedback: queuedSilent),
        );
      });
    }
  }

  void refreshAchievements({
    Duration delay = const Duration(seconds: 2),
    bool silentUnlockFeedback = false,
  }) {
    achievementRefreshDebounce?.cancel();
    achievementRefreshDebounce = Timer(delay, () {
      unawaited(
        runQueuedAchievementRefresh(silentUnlockFeedback: silentUnlockFeedback),
      );
    });
  }

  void onTodoAchievementsChanged() {
    achievementsTodoDirty = true;
    refreshAchievements();
  }

  void onHabitAchievementsChanged() {
    achievementsHabitDirty = true;
    refreshAchievements();
  }

  void onDiaryAchievementsChanged() {
    achievementsDiaryDirty = true;
    refreshAchievements();
  }

  todoProvider.addListener(onTodoAchievementsChanged);
  habitProvider.addListener(onHabitAchievementsChanged);
  var lastPomodoroAchievementSignature = _pomodoroSessionsSignature(
    pomodoroProvider,
  );
  void refreshAchievementsOnPomodoroSummaryChange() {
    final next = _pomodoroSessionsSignature(pomodoroProvider);
    if (next == lastPomodoroAchievementSignature) return;
    lastPomodoroAchievementSignature = next;
    achievementsPomodoroDirty = true;
    refreshAchievements();
  }

  pomodoroProvider.addListener(refreshAchievementsOnPomodoroSummaryChange);
  diaryProvider.addListener(onDiaryAchievementsChanged);
  goalProvider.addListener(refreshAchievements);
  anniversaryProvider.addListener(refreshAchievements);
  courseProvider.addListener(refreshAchievements);
  noteProvider.addListener(refreshAchievements);
  themeProvider.addListener(refreshAchievements);
  bool calendarSyncDue() {
    const minStartupSyncInterval = Duration(minutes: 30);
    final now = DateTime.now();
    bool stale(DateTime? lastSyncedAt) =>
        lastSyncedAt == null ||
        now.difference(lastSyncedAt) >= minStartupSyncInterval;
    return calendarSyncProvider.subscriptions.any(
          (sub) => sub.enabled && stale(sub.lastSyncedAt),
        ) ||
        calendarSyncProvider.oauthAccounts.any(
          (account) => account.enabled && stale(account.lastSyncedAt),
        );
  }

  // 启动后延迟刷新订阅日历，且 30 分钟内已同步过的不再抢首屏资源。
  // ignore: discarded_futures
  Future<void>.delayed(const Duration(seconds: 90), () {
    if (calendarSyncDue()) return calendarSyncProvider.syncAll();
  });

  // 订阅日历变化 → 写入 CalendarProvider 的外部事件，下次 rebuild 合并显示。
  void onCalendarSyncChange() {
    calendarProvider.setExternalEvents(calendarSyncProvider.allEvents());
  }

  calendarSyncProvider.addListener(onCalendarSyncChange);
  onCalendarSyncChange();
  Future<DailyDigestReminderResult> syncDailyDigestReminder({
    int? submittedAccountGeneration,
  }) => _syncDailyDigestReminder(
    preferencesProvider,
    notificationService,
    todoProvider,
    submittedAccountGeneration: submittedAccountGeneration,
  );
  Future<void> syncReportDigestReminders({int? submittedAccountGeneration}) =>
      _syncReportDigestReminders(
        preferencesProvider,
        notificationService,
        todos: todoProvider,
        habits: habitProvider,
        pomodoros: pomodoroProvider,
        timeAudit: timeAuditProvider,
        submittedAccountGeneration: submittedAccountGeneration,
      );
  reminderAuxiliaryResync = () async {
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    await syncDailyDigestReminder(submittedAccountGeneration: generation);
    await syncReportDigestReminders(submittedAccountGeneration: generation);
  };
  Timer? reportDigestSyncDebounce;
  void queueReportDigestReminderSync() {
    reportDigestSyncDebounce?.cancel();
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    reportDigestSyncDebounce = Timer(const Duration(seconds: 2), () {
      unawaited(
        _startupGuard(
          'report digest locale/data refresh',
          () =>
              syncReportDigestReminders(submittedAccountGeneration: generation),
        ),
      );
    });
  }

  Future<bool> syncNotificationQuickAdd({
    bool requestIfNeeded = false,
    bool force = false,
  }) => _syncNotificationQuickAdd(
    preferencesProvider,
    todos: todoProvider,
    habits: habitProvider,
    goals: goalProvider,
    requestIfNeeded: requestIfNeeded,
    force: force,
  );

  Timer? dailyDigestSyncDebounce;
  void queueDailyDigestReminderSync() {
    dailyDigestSyncDebounce?.cancel();
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    dailyDigestSyncDebounce = Timer(const Duration(seconds: 2), () {
      unawaited(
        _startupGuard('daily digest locale/data refresh', () async {
          await syncDailyDigestReminder(submittedAccountGeneration: generation);
        }),
      );
    });
  }

  Timer? notificationQuickAddSyncDebounce;
  var notificationQuickAddSyncInFlight = false;
  var notificationQuickAddSyncQueued = false;
  var notificationQuickAddSyncQueuedForce = false;
  var notificationQuickAddSyncQueuedRequestIfNeeded = false;
  Completer<bool>? notificationQuickAddSyncQueuedCompleter;
  var lastNotificationQuickAddSignature = '';
  var lastNotificationQuickAddFailureSignature = '';
  DateTime? lastNotificationQuickAddFailureAt;
  String notificationQuickAddSignature() {
    final todayProgress = preferencesProvider.notificationTodayProgress;
    final progressBody = todayProgress
        ? _todayTaskProgressNotificationBody(
            todoProvider.todos,
            habits: habitProvider,
            goals: goalProvider,
          )
        : '';
    return '${preferencesProvider.notificationQuickAdd}:'
        '$todayProgress:$progressBody';
  }

  Future<bool> syncNotificationQuickAddDeduped({
    bool force = false,
    bool requestIfNeeded = false,
  }) async {
    final signature = notificationQuickAddSignature();
    if (!force && signature == lastNotificationQuickAddSignature) return true;
    final lastFailureAt = lastNotificationQuickAddFailureAt;
    if (!force &&
        signature == lastNotificationQuickAddFailureSignature &&
        lastFailureAt != null &&
        DateTime.now().difference(lastFailureAt) <
            const Duration(seconds: 45)) {
      debugPrint('[NotificationStatusBar] sync skipped during failure backoff');
      return false;
    }
    if (notificationQuickAddSyncInFlight) {
      notificationQuickAddSyncQueued = true;
      notificationQuickAddSyncQueuedForce =
          notificationQuickAddSyncQueuedForce || force;
      notificationQuickAddSyncQueuedRequestIfNeeded =
          notificationQuickAddSyncQueuedRequestIfNeeded || requestIfNeeded;
      final completer = notificationQuickAddSyncQueuedCompleter ??=
          Completer<bool>();
      return completer.future;
    }
    notificationQuickAddSyncInFlight = true;
    var synced = false;
    try {
      synced = await syncNotificationQuickAdd(
        requestIfNeeded: requestIfNeeded,
        force: force,
      );
      final completedSignature = notificationQuickAddSignature();
      if (synced) {
        lastNotificationQuickAddSignature = completedSignature;
        lastNotificationQuickAddFailureSignature = '';
        lastNotificationQuickAddFailureAt = null;
      } else {
        lastNotificationQuickAddFailureSignature = completedSignature;
        lastNotificationQuickAddFailureAt = DateTime.now();
      }
    } finally {
      notificationQuickAddSyncInFlight = false;
    }
    if (notificationQuickAddSyncQueued) {
      notificationQuickAddSyncQueued = false;
      final queuedForce = notificationQuickAddSyncQueuedForce;
      final queuedRequestIfNeeded =
          notificationQuickAddSyncQueuedRequestIfNeeded;
      notificationQuickAddSyncQueuedForce = false;
      notificationQuickAddSyncQueuedRequestIfNeeded = false;
      final queuedCompleter = notificationQuickAddSyncQueuedCompleter;
      notificationQuickAddSyncQueuedCompleter = null;
      lastNotificationQuickAddSignature = '';
      final queuedSynced = await syncNotificationQuickAddDeduped(
        force: queuedForce,
        requestIfNeeded: queuedRequestIfNeeded,
      );
      if (queuedCompleter != null && !queuedCompleter.isCompleted) {
        queuedCompleter.complete(queuedSynced);
      }
      synced = queuedSynced;
    }
    return synced;
  }

  _syncNotificationQuickAddDedupedCallback = syncNotificationQuickAddDeduped;
  NotificationStatusBarSyncBridge.attach(syncNotificationQuickAddDeduped);

  Future<bool> syncNotificationStatusBarOnStartup() async {
    final todayProgress = preferencesProvider.notificationTodayProgress;
    final quickAdd = preferencesProvider.notificationQuickAdd;
    if (!todayProgress && !quickAdd) return syncNotificationQuickAddDeduped();
    final prefs = await SharedPreferences.getInstance();
    final lastBuild = prefs.getInt(_notificationStatusBarStartupBuildKey);
    if (lastBuild != AppVersion.build) {
      await prefs.setInt(
        _notificationStatusBarStartupBuildKey,
        AppVersion.build,
      );
      debugPrint('[NotificationStatusBar] startup force sync after update');
      return syncNotificationQuickAddDeduped(force: true);
    }
    return syncNotificationQuickAddDeduped();
  }

  void queueNotificationQuickAddSync({
    bool allowBeforeDeferredHydration = false,
  }) {
    if (!deferredLocalStorageHydrated && !allowBeforeDeferredHydration) return;
    notificationQuickAddSyncDebounce?.cancel();
    notificationQuickAddSyncDebounce = Timer(const Duration(seconds: 2), () {
      unawaited(syncNotificationQuickAddDeduped());
    });
  }

  void queueNotificationProgressSync() {
    if (!deferredLocalStorageHydrated) return;
    if (!preferencesProvider.notificationTodayProgress) return;
    queueNotificationQuickAddSync();
  }

  VoidCallback? invalidateHomeWidgetDataSignatureHook;
  VoidCallback? queueHomeWidgetPushHook;
  Timer? notificationProgressMidnightTimer;
  void scheduleNotificationProgressMidnightRefresh() {
    notificationProgressMidnightTimer?.cancel();
    final delay = _durationUntilNextLocalDay();
    notificationProgressMidnightTimer = Timer(delay, () {
      if (preferencesProvider.notificationTodayProgress) {
        unawaited(syncNotificationQuickAddDeduped());
      }
      invalidateHomeWidgetDataSignatureHook?.call();
      queueHomeWidgetPushHook?.call();
      scheduleNotificationProgressMidnightRefresh();
    });
  }

  preferencesProvider.addListener(queueDailyDigestReminderSync);
  preferencesProvider.addListener(queueReportDigestReminderSync);
  preferencesProvider.addListener(queueNotificationQuickAddSync);
  todoProvider.addListener(queueNotificationProgressSync);
  habitProvider.addListener(queueNotificationProgressSync);
  goalProvider.addListener(queueNotificationProgressSync);
  todoProvider.addListener(queueDailyDigestReminderSync);
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
  scheduleNotificationProgressMidnightRefresh();
  refreshUserStatsNow();
  refreshAchievements();

  Future<void> runDailyRolloverAfterFirstFrame() async {
    autoArchiveCoordinator.request(recurringGoals: true);
    refreshUserStatsNow();
    refreshAchievements();
    invalidateHomeWidgetDataSignatureHook?.call();
    queueHomeWidgetPushHook?.call();
    await queueStartupReminderResync(
      delay: const Duration(milliseconds: 500),
      reason: 'daily rollover completed',
    );
  }

  // 通知点击后的深链接(打开对应 Tab)
  void handleNotificationPayload(
    String payload, {
    WidgetNavigationRequest? navigationRequest,
  }) {
    if (_shouldStopActiveRingtoneForPayload(payload)) {
      unawaited(NativeReminderRingtone.stopActive());
    }
    final uri = Uri.tryParse(payload);
    if (uri == null) return;
    _handleWidgetUri(
      uri,
      pomodoroProvider,
      origin: WidgetLinkOrigin.internalNotification,
      navigationRequest: navigationRequest,
    );
  }

  LocalNotifications.instance.onTap = handleNotificationPayload;
  AlarmService.instance.onTap = handleNotificationPayload;
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
    // 同步完成后服务端回写可能覆盖本地数据；这段 reload 不应被当作“脏改动”。
    await cloudSyncProvider.suppressDirtyMarkWhile(() async {
      const achievementSyncCollections = <String>{
        'todos',
        'habits',
        'pomodoro_sessions',
        'diaries',
        'goals',
        'anniversaries',
        'courses',
        'notes',
        'theme_shop_state',
        'achievement_states',
        'virtual_rewards',
      };
      final reloadTasks = <Future<void> Function()>[];
      var shouldResyncReminders = false;
      final shouldRefreshAchievementsSilently = changedCollections.any(
        achievementSyncCollections.contains,
      );

      if (changedCollections.contains('todos')) {
        // TodoProvider 平时惰性加载；云同步回写后必须强制重读，
        // 否则内存列表停留在旧快照，下一次本地写入会覆盖同步结果。
        reloadTasks.add(() => todoProvider.loadFromStorage(force: true));
        shouldResyncReminders = true;
      }
      if (changedCollections.contains('habits')) {
        reloadTasks.add(habitProvider.loadFromStorage);
        shouldResyncReminders = true;
      }
      if (changedCollections.contains('pomodoro_sessions') ||
          changedCollections.contains('focus_penalties') ||
          changedCollections.contains('pomodoro_config')) {
        reloadTasks.add(pomodoroProvider.loadFromStorage);
      }
      if (changedCollections.contains('countdowns')) {
        reloadTasks.add(countdownProvider.loadFromStorage);
        shouldResyncReminders = true;
      }
      if (changedCollections.contains('notes')) {
        reloadTasks.add(noteProvider.loadFromStorage);
      }
      if (changedCollections.contains('anniversaries')) {
        reloadTasks.add(anniversaryProvider.loadFromStorage);
        shouldResyncReminders = true;
      }
      if (changedCollections.contains('diaries')) {
        reloadTasks.add(diaryProvider.loadFromStorage);
      }
      if (changedCollections.contains('goals')) {
        reloadTasks.add(goalProvider.loadFromStorage);
        shouldResyncReminders = true;
      }
      if (changedCollections.contains('courses') ||
          changedCollections.contains('course_settings')) {
        reloadTasks.add(courseProvider.loadFromStorage);
      }
      if (changedCollections.contains('calendar_events')) {
        reloadTasks.add(calendarProvider.loadFromStorage);
        shouldResyncReminders = true;
      }
      if (changedCollections.contains('user_profile')) {
        reloadTasks.add(userProvider.loadFromStorage);
      }
      if (changedCollections.contains('time_entries')) {
        reloadTasks.add(timeAuditProvider.loadFromStorage);
      }
      if (changedCollections.contains('location_reminders')) {
        reloadTasks.add(locationReminderProvider.loadFromStorage);
      }
      if (changedCollections.contains('achievement_states') ||
          changedCollections.contains('virtual_rewards')) {
        reloadTasks.add(achievementProvider.loadFromStorage);
      }
      if (changedCollections.contains('focus_rooms')) {
        reloadTasks.add(focusRoomProvider.loadFromStorage);
      }
      if (changedCollections.contains('theme_shop_state')) {
        reloadTasks.add(themeProvider.loadFromStorage);
      }
      if (changedCollections.contains('preferences')) {
        reloadTasks.add(preferencesProvider.loadFromStorage);
        shouldResyncReminders = true;
      }
      if (changedCollections.contains('quick_capture_templates')) {
        reloadTasks.add(quickCaptureTemplateProvider.loadFromStorage);
      }

      await _runSyncReloadTasksInBatches(
        reloadTasks,
        continueOnError: true,
        label: 'cloud sync reload',
      );
      final postReloadTasks = <Future<void> Function()>[];
      if (shouldRefreshAchievementsSilently) {
        postReloadTasks.add(() async {
          achievementRefreshDebounce?.cancel();
          achievementRefreshQueued = false;
          achievementRefreshQueuedSilent = false;
          try {
            await refreshAchievementsNow(silentUnlockFeedback: true);
          } finally {
            // 云端成就基线已静默回填完毕，可恢复正常解锁反馈：
            // 此后真正的新解锁才会弹窗 / 通知。
            achievementProvider.resumeUnlockFeedback();
          }
        });
      }
      final accountCollectionsChanged =
          changedCollections.contains('user_profile') ||
          changedCollections.contains('virtual_rewards');
      if (accountCollectionsChanged) {
        // 云同步回写本地资料后，再拉一次账号资料，保证其它设备改过的
        // 昵称、头像、邮箱验证状态、时光币等账号字段能覆盖本地展示缓存。
        postReloadTasks.add(() async {
          await authProvider.refreshMe(reason: 'cloud_sync_account_snapshot');
        });
      }
      if (changedCollections.contains('workspace_payloads')) {
        postReloadTasks.add(() async {
          unawaited(
            shareProvider.withoutLoadingNotification(
              () => shareProvider.load(force: true),
            ),
          );
        });
      }
      if (changedCollections.contains('preferences')) {
        postReloadTasks.add(() async {
          syncQuietHoursPolicyToSchedulers();
          await ReminderRingtoneSettings.applyPersistedSettingsToNative();
        });
      }
      await _runSyncReloadTasksInBatches(
        postReloadTasks,
        continueOnError: true,
        label: 'cloud sync post reload',
      );
      // 拉取云端后可能覆盖了本地 reminder，也要重跑一次
      if (shouldResyncReminders) {
        unawaited(
          _startupGuard(
            'cloud reminder storage',
            () => queueFullReminderResync(
              delay: const Duration(milliseconds: 2500),
              reason: 'cloud sync changed reminders',
            ),
          ),
        );
      }
    });
  };

  String? currentAuthReminderIdentity() {
    final state = authProvider.state;
    if (!state.isLoggedIn) return null;
    return state.token;
  }

  Future<void> startCloudSyncAfterAuth({
    required String reason,
    Duration delay = const Duration(milliseconds: 1600),
  }) async {
    final serial = ++cloudSyncStartSerial;
    await Future<void>.delayed(delay);
    if (serial != cloudSyncStartSerial) return;
    cloudSyncProvider.resumeForActiveAccount();
    if (!authProvider.state.isLoggedIn || !cloudSyncProvider.config.autoSync) {
      cloudSyncProvider.stopRemotePolling();
      return;
    }
    await _startupGuard(
      'server config before cloud sync',
      () => authProvider.refreshServerConfigFromServer(),
      timeout: const Duration(seconds: 5),
    );
    if (serial != cloudSyncStartSerial) return;
    if (!authProvider.state.isLoggedIn || !cloudSyncProvider.config.autoSync) {
      cloudSyncProvider.stopRemotePolling();
      return;
    }
    if (authProvider.serverConfig['backup_enabled'] == false) {
      cloudSyncProvider.stopRemotePolling();
      return;
    }
    await _startupGuard(
      'cloud sync $reason',
      () => cloudSyncProvider.syncNow(),
      timeout: const Duration(seconds: 12),
    );
    if (serial != cloudSyncStartSerial) return;
    if (authProvider.state.isLoggedIn && cloudSyncProvider.config.autoSync) {
      cloudSyncProvider.startRemotePolling();
    }
  }

  Duration cloudSyncDelayAfterAuth({required bool initialStartup}) {
    if (cloudSyncProvider.hasPendingChanges) {
      return const Duration(milliseconds: 900);
    }
    return initialStartup
        ? const Duration(seconds: 120)
        : const Duration(seconds: 28);
  }

  var lastAuthReminderIdentity = currentAuthReminderIdentity();
  var lastLocalAccountDataBlocked = authProvider.isLocalAccountDataBlocked;
  var digestStorageRecoveryPending = false;
  var digestStorageRecoveryInFlight = false;
  int? digestRecoverySession;
  int? digestRecoveryRevision;
  var observedSuccessfulDigestRevision = lastSuccessfulDigestTransitionRevision;
  var recoveryRetriesRemaining = 1;
  Timer? accountStorageRecoveryRetry;
  late void Function() startAccountStorageRecovery;

  bool canRecoverDigestStorage() =>
      !authProvider.isLocalAccountDataBlocked &&
      !authProvider.isAccountTransitionInProgress &&
      !AccountPreferenceWrites.isBoundaryActive &&
      authProvider.sessionGeneration == digestRecoverySession &&
      authProvider.successfulAccountTransitionRevision ==
          digestRecoveryRevision;

  void observeSuccessfulDigestTransition() {
    final revision = authProvider.successfulAccountTransitionRevision;
    if (authProvider.isAccountTransitionInProgress ||
        authProvider.isLocalAccountDataBlocked ||
        revision == observedSuccessfulDigestRevision) {
      return;
    }
    observedSuccessfulDigestRevision = revision;
    digestRecoveryRevision = revision;
    digestRecoverySession = authProvider.sessionGeneration;
    recoveryRetriesRemaining = 1;
    accountStorageRecoveryRetry?.cancel();
  }

  void resumeDigestAfterSuccessfulAuth() {
    if (digestStorageRecoveryPending || digestStorageRecoveryInFlight) return;
    final revision = authProvider.successfulAccountTransitionRevision;
    if (revision == lastSuccessfulDigestTransitionRevision) return;
    if (_digestReminderCoordinator.resumeForActiveAccount()) {
      lastSuccessfulDigestTransitionRevision = revision;
      queueDailyDigestReminderSync();
      queueReportDigestReminderSync();
    }
  }

  Future<void> restoreAccountStorageAfterRecovery() async {
    if (digestStorageRecoveryInFlight || !canRecoverDigestStorage()) return;
    digestStorageRecoveryInFlight = true;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final sessionGeneration = authProvider.sessionGeneration;
    final identity = currentAuthReminderIdentity();
    var failed = false;
    bool isCurrentRecovery() =>
        !authProvider.isLocalAccountDataBlocked &&
        !authProvider.isAccountTransitionInProgress &&
        !AccountPreferenceWrites.isBoundaryActive &&
        canRecoverDigestStorage() &&
        authProvider.sessionGeneration == sessionGeneration &&
        currentAuthReminderIdentity() == identity &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        );
    Future<void> loadIfCurrent(Future<void> Function() task) async {
      if (isCurrentRecovery()) await task();
    }

    try {
      await AccountPreferenceWrites.waitForBoundary();
      if (!isCurrentRecovery()) return;
      await cloudSyncProvider.suppressDirtyMarkWhile(
        () => _runSyncReloadTasksInBatches([
          () => loadIfCurrent(themeProvider.loadFromStorage),
          () => loadIfCurrent(preferencesProvider.loadFromStorage),
          () => loadIfCurrent(userProvider.loadFromStorage),
          () => loadIfCurrent(cloudSyncProvider.loadFromStorage),
        ]),
      );
      if (!isCurrentRecovery()) return;
      await ensureDeferredLocalStorageStartup();
      if (!isCurrentRecovery()) return;
      syncQuietHoursPolicyToSchedulers();
      reminderScheduler.resumeForActiveAccount();
      LocationGeofenceService.resumeForActiveAccount();
      digestStorageRecoveryPending = false;
      if (_digestReminderCoordinator.resumeForActiveAccount()) {
        lastSuccessfulDigestTransitionRevision =
            authProvider.successfulAccountTransitionRevision;
        queueDailyDigestReminderSync();
        queueReportDigestReminderSync();
      }
    } catch (_) {
      failed = true;
      rethrow;
    } finally {
      digestStorageRecoveryInFlight = false;
      if (digestStorageRecoveryPending && canRecoverDigestStorage()) {
        if (authProvider.sessionGeneration != sessionGeneration) {
          // A newer successful transition superseded this recovery.
          scheduleMicrotask(startAccountStorageRecovery);
        } else if (failed && recoveryRetriesRemaining > 0) {
          recoveryRetriesRemaining--;
          accountStorageRecoveryRetry = Timer(const Duration(seconds: 2), () {
            if (authProvider.sessionGeneration == sessionGeneration) {
              startAccountStorageRecovery();
            }
          });
        }
      }
    }
  }

  startAccountStorageRecovery = () {
    if (!digestStorageRecoveryPending ||
        digestStorageRecoveryInFlight ||
        !canRecoverDigestStorage()) {
      return;
    }
    reminderStorageStartup.invalidate();
    deferredStorageStartup.invalidate();
    reminderProvidersHydrated = false;
    deferredLocalStorageHydrated = false;
    unawaited(
      _startupGuard(
        'account storage recovery',
        restoreAccountStorageAfterRecovery,
      ),
    );
  };

  void queueShareLoadAfterAuth({Duration delay = const Duration(seconds: 6)}) {
    unawaited(() async {
      await Future<void>.delayed(delay);
      if (!authProvider.state.isLoggedIn) return;
      await shareProvider.load(notifyLoading: false);
    }());
  }

  authProvider.addListener(() {
    final localAccountDataBlocked = authProvider.isLocalAccountDataBlocked;
    if (localAccountDataBlocked || authProvider.isAccountTransitionInProgress) {
      _digestReminderCoordinator.suspendForAccountChange();
    }
    if (lastLocalAccountDataBlocked && !localAccountDataBlocked) {
      digestStorageRecoveryPending = true;
    }
    observeSuccessfulDigestTransition();
    startAccountStorageRecovery();
    lastLocalAccountDataBlocked = localAccountDataBlocked;
    resumeDigestAfterSuccessfulAuth();
    final authReminderIdentity = currentAuthReminderIdentity();
    final authChanged = authReminderIdentity != lastAuthReminderIdentity;
    lastAuthReminderIdentity = authReminderIdentity;
    if (!authChanged) return;
    queueShareLoadAfterAuth();
    if (authProvider.state.isLoggedIn) {
      // 提醒重放不能等云同步：登录后 1 分钟内创建/恢复的 popup 和闹钟
      // 需要先把本地 Timer/系统队列补齐；云同步完成后仍会再幂等重放一次。
      unawaited(
        _startupGuard(
          'auth reminder storage',
          () => queueFullReminderResync(
            delay: const Duration(seconds: 8),
            reason: 'auth changed',
          ),
        ),
      );
    }
    if (authProvider.state.isLoggedIn && cloudSyncProvider.config.autoSync) {
      unawaited(
        startCloudSyncAfterAuth(
          reason: 'auth changed',
          delay: cloudSyncDelayAfterAuth(initialStartup: false),
        ),
      );
    } else {
      cloudSyncStartSerial++;
      cloudSyncProvider.stopRemotePolling();
    }
  });
  observeSuccessfulDigestTransition();
  resumeDigestAfterSuccessfulAuth();
  if (authProvider.state.isLoggedIn) {
    queueShareLoadAfterAuth(delay: const Duration(seconds: 8));
  }
  if (authProvider.state.isLoggedIn && cloudSyncProvider.config.autoSync) {
    unawaited(
      startCloudSyncAfterAuth(
        reason: 'initial logged-in startup',
        delay: cloudSyncDelayAfterAuth(initialStartup: true),
      ),
    );
  }
  if (authProvider.state.isLoggedIn) {
    unawaited(
      _startupGuard(
        'initial reminder storage',
        () => queueStartupReminderResync(
          delay: const Duration(seconds: 3),
          reason: 'initial logged-in startup',
        ),
      ),
    );
  }

  Future<bool> pushHomeWidgetNow({bool force = false}) {
    final presentationGeneration = homeWidgetPresentationGeneration;
    return _pushHomeWidget(
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
      preferencesProvider,
      force: force,
      isPresentationCurrent: () =>
          homeWidgetPresentationGeneration == presentationGeneration,
    );
  }

  HomeWidgetService.publicationWriter = (payload, capturedAt) async {
    if (!HomeWidgetService.usesNativePublication ||
        !criticalStorageStartup.ready ||
        !deferredLocalStorageHydrated ||
        !deferredStorageStartup.ready ||
        _widgetAccountUnavailable(authProvider)) {
      return false;
    }
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    final session = authProvider.sessionGeneration;
    final selectedLocale = I18n.current;
    final selectedTheme = _homeWidgetThemeSignature(themeProvider);
    final presentationGeneration = homeWidgetPresentationGeneration;
    final accountIdentity = authProvider.validatedWidgetAccountIdentity;
    if (authProvider.state.isLoggedIn && accountIdentity == null) return false;
    final binding = accountIdentity == null
        ? WidgetWorkspaceBinding(kind: 'guest', key: 'local-device')
        : WidgetWorkspaceBinding(kind: 'account', key: accountIdentity);
    bool isCurrent() =>
        criticalStorageStartup.ready &&
        deferredLocalStorageHydrated &&
        deferredStorageStartup.ready &&
        !_widgetAccountUnavailable(authProvider) &&
        authProvider.sessionGeneration == session &&
        I18n.current == selectedLocale &&
        homeWidgetPresentationGeneration == presentationGeneration &&
        _homeWidgetThemeSignature(themeProvider) == selectedTheme &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation) &&
        (accountIdentity == null
            ? !authProvider.state.isLoggedIn
            : authProvider.validatedWidgetAccountIdentity == accountIdentity);
    final workspace = ValidatedWidgetWorkspace(
      binding: binding,
      accountGeneration: generation,
      isCurrent: isCurrent,
    );
    final presentation = widgetPresentation(payload);
    if (!presentation.sameAs(currentWidgetPresentation()) || !isCurrent()) {
      return false;
    }
    return widgetPublicationHost.publish(
      workspace: workspace,
      presentation: presentation,
      completeValues: payload,
      capturedAt: capturedAt,
      refreshWidgets: HomeWidgetService.refreshPublishedWidgets,
      requestFreshCapture: () => pushHomeWidgetNow(force: true),
      invalidatePushSignature: HomeWidgetService.invalidatePushSignature,
    );
  };

  HomeWidgetService.dashboardDataRefresher = () async {
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    await ensureDeferredLocalStorageStartup();
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation) ||
        _widgetAccountUnavailable(authProvider)) {
      return false;
    }
    return pushHomeWidgetNow(force: true);
  };

  Timer? homeWidgetThemeDebounce;
  String lastHomeWidgetThemeSignature = '';

  String homeWidgetThemeSignature() => _homeWidgetThemeSignature(themeProvider);

  String? cachedHomeWidgetDataSignature;
  DateTime? cachedHomeWidgetSignatureDay;
  int? cachedHomeWidgetSignatureTimezone;
  String? cachedHomeWidgetSignatureLocale;
  String? cachedHomeWidgetSignatureTheme;
  int? cachedHomeWidgetSignatureFirstDay;
  var homeWidgetDataSignatureDirty = true;

  void invalidateHomeWidgetDataSignature() {
    homeWidgetDataSignatureDirty = true;
  }

  String homeWidgetDataRevisionSignature() {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final timezone = now.timeZoneOffset.inMinutes;
    final locale = I18n.current.name;
    final theme = homeWidgetThemeSignature();
    final firstDay = preferencesProvider.firstDayOfWeek;
    if (!homeWidgetDataSignatureDirty &&
        cachedHomeWidgetDataSignature != null &&
        cachedHomeWidgetSignatureDay == day &&
        cachedHomeWidgetSignatureTimezone == timezone &&
        cachedHomeWidgetSignatureLocale == locale &&
        cachedHomeWidgetSignatureTheme == theme &&
        cachedHomeWidgetSignatureFirstDay == firstDay) {
      return cachedHomeWidgetDataSignature!;
    }
    final signature = _homeWidgetDataRevisionSignature(
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
      preferencesProvider,
    );
    cachedHomeWidgetDataSignature = signature;
    cachedHomeWidgetSignatureDay = day;
    cachedHomeWidgetSignatureTimezone = timezone;
    cachedHomeWidgetSignatureLocale = locale;
    cachedHomeWidgetSignatureTheme = theme;
    cachedHomeWidgetSignatureFirstDay = firstDay;
    homeWidgetDataSignatureDirty = false;
    return signature;
  }

  final homeWidgetPushQueue = HomeWidgetPushQueue(
    canPublish: () =>
        deferredLocalStorageHydrated &&
        !_widgetAccountUnavailable(authProvider),
    readSignature: homeWidgetDataRevisionSignature,
    publish: () => pushHomeWidgetNow(),
    onFailure: (error, stack) {
      debugPrint('[HomeWidget] queued push completed with failures: $error');
      if (stack != null) debugPrint('$stack');
    },
  );
  HomeWidgetService.widgetLifecycleChanged = homeWidgetPushQueue.setBackground;

  Future<void> runQueuedHomeWidgetPush() {
    homeWidgetPushQueue.queue();
    return homeWidgetPushQueue.flush();
  }

  void queueHomeWidgetPush() {
    if (!deferredLocalStorageHydrated) return;
    homeWidgetPushQueue.queue();
  }

  invalidateHomeWidgetDataSignatureHook = invalidateHomeWidgetDataSignature;
  queueHomeWidgetPushHook = queueHomeWidgetPush;

  _refreshHomeWidgetsOnRolloverCallback = () {
    invalidateHomeWidgetDataSignature();
    queueHomeWidgetPush();
  };

  String? widgetOwnerSignature() => authProvider.state.isLoggedIn
      ? authProvider.validatedWidgetAccountIdentity
      : _widgetAccountUnavailable(authProvider)
      ? null
      : 'guest';
  var lastWidgetOwnerSignature = widgetOwnerSignature();
  authProvider.addListener(() {
    final current = widgetOwnerSignature();
    if (current == lastWidgetOwnerSignature) return;
    lastWidgetOwnerSignature = current;
    HomeWidgetService.invalidatePushSignature();
    homeWidgetPushQueue.invalidateSignature();
    invalidateHomeWidgetDataSignature();
    if (current != null) queueHomeWidgetPush();
  });

  Future<void> updateHomeWidgetThemeNow({required String reason}) async {
    final signature = homeWidgetThemeSignature();
    if (signature == lastHomeWidgetThemeSignature) return;
    lastHomeWidgetThemeSignature = signature;
    final ok = await HomeWidgetService.updateTheme(
      HomeWidgetThemePayload.fromThemeProvider(themeProvider),
    );
    if (!ok) {
      lastHomeWidgetThemeSignature = '';
      debugPrint('[HomeWidget] theme update failed reason=$reason');
    }
  }

  void queueHomeWidgetThemeUpdate({required String reason}) {
    homeWidgetThemeDebounce?.cancel();
    homeWidgetThemeDebounce = Timer(const Duration(milliseconds: 160), () {
      unawaited(updateHomeWidgetThemeNow(reason: reason));
    });
  }

  // 预约提醒（scheduler 派发）与即时通知共用品牌标题：启动注入一次，
  // 主题切换跟随，避免非 default 主题下两路通知标题不一致。
  // 语言切换也会改变 AppBrand.strings（BrandStrings.forLocale 按 I18n 分发），
  // 因此 localeProvider 变更时同样需要重推，通知/提醒文案才能跟随语言。
  void pushBrandStringsToNotifiers() {
    reminderScheduler.setStrings(themeProvider.brand.strings);
    notificationService.setStrings(themeProvider.brand.strings);
  }

  pushBrandStringsToNotifiers();
  themeProvider.addListener(() {
    invalidateHomeWidgetDataSignature();
    pushBrandStringsToNotifiers();
    queueHomeWidgetThemeUpdate(reason: 'theme provider changed');
    queueHomeWidgetPush();
  });
  localeProvider.addListener(() {
    invalidateHomeWidgetDataSignature();
    pushBrandStringsToNotifiers();
    queueDailyDigestReminderSync();
    queueReportDigestReminderSync();
    // 语言切换同样改变小组件 payload 文案（_pushHomeWidget 走 I18n）与
    // 品牌词条（brand.strings），必须重推小组件数据；主题 payload 与语言
    // 无关，updateHomeWidgetThemeNow 的签名去重会自然跳过写入。
    queueHomeWidgetPush();
  });
  var lastWidgetFirstDayOfWeek = preferencesProvider.firstDayOfWeek;
  var lastWidgetShowLunar = preferencesProvider.showLunar;
  preferencesProvider.addListener(() {
    final nextFirstDay = preferencesProvider.firstDayOfWeek;
    final nextShowLunar = preferencesProvider.showLunar;
    if (nextFirstDay == lastWidgetFirstDayOfWeek &&
        nextShowLunar == lastWidgetShowLunar) {
      return;
    }
    lastWidgetFirstDayOfWeek = nextFirstDay;
    lastWidgetShowLunar = nextShowLunar;
    homeWidgetPushQueue.invalidateSignature();
    invalidateHomeWidgetDataSignature();
    queueHomeWidgetPush();
  });
  unawaited(updateHomeWidgetThemeNow(reason: 'startup theme loaded'));

  systemTray.onActivate.listen((action) {
    if (action == 'pomodoro_quick_start') pomodoroProvider.startIfIdle();
  });

  void onDataChange() {
    invalidateHomeWidgetDataSignature();
    queueHomeWidgetPush();
  }

  var lastPomodoroHomeWidgetSignature = _pomodoroHomeWidgetSignature(
    pomodoroProvider,
  );
  void onPomodoroHomeWidgetChange() {
    final next = _pomodoroHomeWidgetSignature(pomodoroProvider);
    if (next == lastPomodoroHomeWidgetSignature) return;
    lastPomodoroHomeWidgetSignature = next;
    invalidateHomeWidgetDataSignature();
    queueHomeWidgetPush();
  }

  todoProvider.addListener(onDataChange);
  habitProvider.addListener(onDataChange);
  pomodoroProvider.addListener(onPomodoroHomeWidgetChange);
  timeAuditProvider.addListener(onDataChange);
  goalProvider.addListener(onDataChange);
  anniversaryProvider.addListener(onDataChange);
  countdownProvider.addListener(onDataChange);
  courseProvider.addListener(onDataChange);
  noteProvider.addListener(onDataChange);
  diaryProvider.addListener(onDataChange);
  calendarProvider.addListener(onDataChange);

  try {
    HomeWidgetService.widgetClickedStream.listen((uri) {
      if (uri != null) handleDeepLink(uri);
    });
  } catch (e, st) {
    debugPrint('[startup] home widget stream failed: $e\n$st');
  }

  Future<void> runPostFrameStartupTasks() async {
    unawaited(
      Future<void>.delayed(
        const Duration(seconds: 14),
        () => _startupGuard('startup widget storage', () async {
          await ensureDeferredLocalStorageStartup();
          await _drainPendingWidgetBgActions(pomodoroProvider);
          queueHomeWidgetPush();
          queueNotificationQuickAddSync();
        }),
      ),
    );
    unawaited(
      _runStartupStaggeredTask(
        'startup notification launch payloads',
        () async {
          final launchRequest = _widgetNavigationRequests.capture();
          await LocalNotifications.instance.initForLaunchPayload();
          await AlarmService.instance.initForLaunchPayload();
          final initialNotificationPayloads = <String>[];
          final localLaunchPayload = LocalNotifications.instance
              .takeLaunchPayload();
          final alarmLaunchPayload = AlarmService.instance.takeLaunchPayload();
          if (localLaunchPayload != null && localLaunchPayload.isNotEmpty) {
            initialNotificationPayloads.add(localLaunchPayload);
          } else if (alarmLaunchPayload != null &&
              alarmLaunchPayload.isNotEmpty) {
            // Use the alarm mapper only when the shared local mapper could
            // not read a launch response. This prevents quick actions from
            // being dispatched twice with different normalized payloads.
            initialNotificationPayloads.add(alarmLaunchPayload);
          }
          if (initialNotificationPayloads.isNotEmpty) {
            await ensureReminderProvidersStartup();
          }
          for (final payload in initialNotificationPayloads.toSet()) {
            handleNotificationPayload(
              payload,
              navigationRequest: launchRequest,
            );
          }
        },
        delay: const Duration(milliseconds: 2400),
      ),
    );
    unawaited(
      _runStartupStaggeredTask('startup deep links', () async {
        final launchAccount = AccountLocalDataCleaner.accountDataGeneration;
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
        if (initialDeepLink != null && initialDeepLink.toString().isNotEmpty) {
          await ensureReminderProvidersStartup();
          _handleWidgetUri(initialDeepLink, pomodoroProvider);
        }
        if (initialOAuthLink != null) {
          _handleWidgetUri(initialOAuthLink, pomodoroProvider);
        }
        if (initialSharedText != null) {
          receiveSharedText(
            initialSharedText,
            receivedAccountGeneration: launchAccount,
          );
        }
      }, delay: const Duration(milliseconds: 1100)),
    );
    unawaited(
      _runStartupStaggeredTask('home widget initial launch', () async {
        await ensureHomeWidgetLaunchStartup();
        final initial = await _startupValue<Uri>(
          'home widget initial launch',
          () => HomeWidgetService.initialLaunchUri(),
        );
        if (initial != null) {
          await ensureDeferredLocalStorageStartup();
          _handleWidgetUri(initial, pomodoroProvider);
        }
        await _drainPendingWidgetBgActions(pomodoroProvider);
      }, delay: const Duration(seconds: 8)),
    );
    unawaited(
      _runStartupStaggeredTask(
        'deferred platform services',
        ensureDeferredPlatformStartup,
        delay: const Duration(seconds: 65),
        timeout: const Duration(seconds: 18),
      ),
    );
    unawaited(
      _runStartupIdleQueue(
        [
          () => _startupGuard(
            'deferred local storage',
            ensureDeferredLocalStorageStartup,
            timeout: const Duration(seconds: 20),
          ),
          () => _startupGuard(
            'server config refresh',
            () => authProvider.refreshServerConfigFromServer(),
            timeout: const Duration(seconds: 5),
          ),
          () => _startupGuard(
            'auth profile refresh',
            () => authProvider.refreshMe(),
            timeout: const Duration(seconds: 8),
          ),
          () => _startupGuard(
            'initial reminder resync',
            () => queueStartupReminderResync(
              delay: const Duration(seconds: 5),
              reason: 'post-frame startup',
            ),
          ),
          () => _startupGuard('daily digest reminder', syncDailyDigestReminder),
          () => _startupGuard(
            'report digest reminders',
            syncReportDigestReminders,
          ),
          () => _startupGuard(
            'notification quick add',
            syncNotificationStatusBarOnStartup,
          ),
          () => _startupGuard(
            'initial home widget push',
            runQueuedHomeWidgetPush,
          ),
          runDailyRolloverAfterFirstFrame,
        ],
        initialDelay: const Duration(seconds: 75),
        gap: const Duration(seconds: 12),
      ),
    );
  }

  // 首屏关键配置已完成；大数据 Provider、远端刷新和通知重放在首帧后分批执行。
  cloudSyncProvider.dirtyMarkEnabled = true;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: todoProvider),
        ChangeNotifierProvider.value(value: habitProvider),
        ChangeNotifierProvider.value(value: pomodoroProvider),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: cloudSyncProvider),
        // 云同步状态只读展示层：状态卡仅消费状态，无手动触发入口。
        ChangeNotifierProvider.value(
          value: SyncStatusController(source: cloudSyncProvider),
        ),
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
        Provider<ReminderScheduler>.value(value: reminderScheduler),
        Provider<ReminderScheduler?>.value(value: reminderScheduler),
        Provider<DailyDigestReminderSync>.value(
          value: DailyDigestReminderSync(
            registerImmediately: () {
              dailyDigestSyncDebounce?.cancel();
              return syncDailyDigestReminder();
            },
          ),
        ),
        Provider.value(value: systemTray),
      ],
      child: DuoyiApp(
        autoArchiveCoordinator: autoArchiveCoordinator,
        criticalStorageStartup: criticalStorageStartup,
        retryCriticalStorage: ensureCriticalLocalStorageStartup,
      ),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      _startupGuard(
        'startup app update policy',
        () => appUpdate.checkServerPolicyNow(),
        timeout: const Duration(seconds: 6),
      ),
    );
    unawaited(runPostFrameStartupTasks());
  });
}

bool _shouldStopActiveRingtoneForPayload(String payload) {
  final uri = Uri.tryParse(payload);
  if (uri == null || uri.scheme != 'duoyi') return false;
  if (uri.queryParameters['confirm'] == '1') return true;
  return uri.host == 'snooze' || uri.host == 'alarm-test';
}

Future<bool> _pushHomeWidget(
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
  PreferencesProvider preferences, {
  bool force = false,
  bool Function()? isPresentationCurrent,
}) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final activeToday = t.visibleTodayTodos(now)
    ..sort((a, b) {
      // 按优先级倒序
      final r = b.priority.rank.compareTo(a.priority.rank);
      if (r != 0) return r;
      return a.sortOrder.compareTo(b.sortOrder);
    });
  final activeTodayTodos = activeToday.length;
  final top3 = activeToday.take(3).map((e) => e.title).toList();
  final top3Ids = activeToday.take(3).map((e) => e.id).toList();
  final activeHabits = h.habits
      .where((habit) => habit.activeForDate(today))
      .toList();
  final completedHabitCount = activeHabits
      .where((habit) => habit.isCompletedForDate(today))
      .length;
  final habitPercent = widgetHabitCompletionPercent(
    activeCount: activeHabits.length,
    completedCount: completedHabitCount,
  );
  final quickCheckHabits =
      activeHabits
          .where(
            (habit) =>
                habit.kind == HabitKind.positive &&
                !habit.isCompletedForDate(today),
          )
          .toList()
        ..sort((a, b) {
          final order = a.sortOrder.compareTo(b.sortOrder);
          if (order != 0) return order;
          return a.createdAt.compareTo(b.createdAt);
        });
  final quickCheckHabit = quickCheckHabits.firstOrNull;
  final todayFocusSessions = p.focusSessionsForDate(today);
  final pomodoroToday = todayFocusSessions.length;
  final focusMinutesToday =
      todayFocusSessions.fold<int>(
        0,
        (sum, session) => sum + session.durationSeconds,
      ) ~/
      60;
  final activeGoalItems = g.activeGoals.take(3).toList();
  final goalHighlights = activeGoalItems
      .map(
        (goal) => '${goal.title} · ${(goal.computedProgress * 100).round()}%',
      )
      .toList();
  final goalHighlightIds = activeGoalItems
      .map((goal) => 'duoyi://goal/${Uri.encodeComponent(goal.id)}')
      .toList();
  final upcomingAnniversaries = <({String label, String deepLink, int days})>[
    for (final item in a.itemsAt(today))
      if (item.daysRemainingForDate(today) >= 0)
        (
          label:
              '${item.title} · ${I18n.tr('widget.days_remaining_prefix')}'
              '${item.daysRemainingForDate(today)}'
              '${I18n.tr('widget.days_remaining_suffix')}',
          deepLink: 'duoyi://anniversary/${Uri.encodeComponent(item.id)}',
          days: item.daysRemainingForDate(today),
        ),
    for (final item in countdowns.items)
      if (item.daysRemainingForDate(today) >= 0)
        (
          label:
              '${item.title} · ${I18n.tr('widget.days_remaining_prefix')}'
              '${item.daysRemainingForDate(today)}'
              '${I18n.tr('widget.days_remaining_suffix')}',
          deepLink: 'duoyi://countdown/${Uri.encodeComponent(item.id)}',
          days: item.daysRemainingForDate(today),
        ),
  ]..sort((x, y) => x.days.compareTo(y.days));
  final topAnniversaryEntries = upcomingAnniversaries.take(2).toList();
  final anniversaryHighlights = topAnniversaryEntries
      .map((entry) => entry.label)
      .toList();
  final anniversaryHighlightIds = topAnniversaryEntries
      .map((entry) => entry.deepLink)
      .toList();

  final upcomingMemorials = <({String label, String deepLink, int days})>[
    for (final item in a.memorials)
      if (item.daysRemainingForDate(today) >= 0)
        (
          label:
              '${item.title} · ${I18n.tr('widget.days_remaining_prefix')}'
              '${item.daysRemainingForDate(today)}'
              '${I18n.tr('widget.days_remaining_suffix')}',
          deepLink: 'duoyi://anniversary/${Uri.encodeComponent(item.id)}',
          days: item.daysRemainingForDate(today),
        ),
    for (final item in countdowns.items)
      if (item.daysRemainingForDate(today) >= 0)
        (
          label:
              '${item.title} · ${I18n.tr('widget.days_remaining_prefix')}'
              '${item.daysRemainingForDate(today)}'
              '${I18n.tr('widget.days_remaining_suffix')}',
          deepLink: 'duoyi://countdown/${Uri.encodeComponent(item.id)}',
          days: item.daysRemainingForDate(today),
        ),
  ]..sort((x, y) => x.days.compareTo(y.days));
  final topMemorialEntries = upcomingMemorials.take(3).toList();
  final memorialHighlights = topMemorialEntries
      .map((entry) => entry.label)
      .toList();
  final memorialHighlightIds = topMemorialEntries
      .map((entry) => entry.deepLink)
      .toList();
  final courseItems = c.coursesOfDate(today).take(3).toList();
  final courseHighlights = courseItems.map((course) {
    final location = course.location.isEmpty ? '' : ' · ${course.location}';
    return '${I18n.tr('widget.course_section_prefix')}'
        '${course.startSection}-${course.endSection}'
        '${I18n.tr('widget.course_section_suffix')}${course.name}$location';
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
      ? I18n.tr('widget.no_schedule_today')
      : "${I18n.tr('widget.today_prefix')}${scheduleHighlights.first}";
  final focusState = p.state;
  final focusTimerEndsAtMillis = p.focusTimerEndsAtMillis;
  final focusTimerLabel = switch (focusState.type) {
    PomodoroType.focus =>
      focusState.isCountUp
          ? I18n.tr('widget.focus_counting_up')
          : I18n.tr('widget.focus_countdown'),
    PomodoroType.shortBreak => I18n.tr('widget.short_break_countdown'),
    PomodoroType.longBreak => I18n.tr('widget.long_break_countdown'),
  };
  final calendarMonthSummary = _homeWidgetCalendarMonthSummary(
    today,
    I18n.current,
    showLunar: preferences.showLunar,
  );
  return HomeWidgetService.push(
    force: force,
    snapshotAt: now,
    firstDayOfWeek: preferences.firstDayOfWeek,
    isPresentationCurrent: isPresentationCurrent,
    todoCount: activeTodayTodos,
    habitPercent: habitPercent,
    habitActiveCount: activeHabits.length,
    pomodoroToday: pomodoroToday,
    focusMinutesToday: focusMinutesToday,
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
    calendarMonthSummary: calendarMonthSummary,
    focusSummary: pomodoroToday == 0
        ? I18n.tr('widget.focus_not_started')
        : "${I18n.tr('widget.focus_today_prefix')}$pomodoroToday"
              "${I18n.tr('widget.focus_today_suffix')}",
    habitSummary: activeHabits.isEmpty
        ? I18n.tr('widget.habit_none_today')
        : habitPercent >= 100
        ? I18n.tr('widget.habit_all_done')
        : "${I18n.tr('widget.habit_progress_prefix')}$habitPercent"
              "${I18n.tr('widget.habit_progress_suffix')}",
    streakSummary:
        "${I18n.tr('widget.streak_prefix')}${h.longestCurrentStreak}"
        "${I18n.tr('widget.streak_suffix')}",
    nextFocusLabel: nextFocusWidgetLabel(p, locale: I18n.current),
    focusTimerCountUp: focusState.isCountUp,
    focusTimerStartedAtMillis: p.focusTimerStartedAtMillis,
    focusTimerRunning: focusState.isRunning,
    focusTimerRemainingSeconds: focusState.remainingSeconds,
    focusTimerTotalSeconds: focusState.totalSeconds,
    focusTimerEndsAtMillis: focusTimerEndsAtMillis,
    focusTimerLabel: focusTimerLabel,
    habitQuickCheckId: quickCheckHabit?.id ?? '',
    habitQuickCheckLabel: quickCheckHabit == null
        ? I18n.tr('widget.habit_view')
        : "${I18n.tr('widget.habit_checkin_prefix')}${quickCheckHabit.name}",
    theme: HomeWidgetThemePayload.fromThemeProvider(tp),
  );
}

String? _homeWidgetCalendarMonthSummary(
  DateTime today,
  AppLocale locale, {
  bool showLunar = true,
}) {
  final nextHoliday = HolidayCalendar.nextHoliday(today);
  String? holidayText;
  if (nextHoliday != null) {
    final days = nextHoliday.daysUntil(today);
    final name = nextHoliday.localizedName(locale);
    if (days == 0) {
      holidayText = locale == AppLocale.en ? '$name today' : '今日$name';
    } else if (days > 0) {
      holidayText = locale == AppLocale.en ? '$name in ${days}d' : '距$name$days天';
    }
  }
  if (locale == AppLocale.en) {
    if (holidayText == null) return null;
    return '${today.month}/${today.day} · $holidayText';
  }
  if (showLunar) {
    final lunar = LunarCalendar.fromSolar(today);
    final term = LunarCalendar.solarTerm(today);
    final parts = <String>[
      '农历${lunar.chineseText}',
      if (term != null && term.isNotEmpty) term,
      ?holidayText,
    ];
    return parts.join(' · ');
  }
  if (holidayText == null) return null;
  return '${today.month}月${today.day}日 · $holidayText';
}

/// Invokes the same action and capture code used by widget delivery.
@visibleForTesting
abstract final class WidgetActionTestAccess {
  static Future<void> checkInHabit(
    HabitProvider habits,
    Habit target,
    WidgetLaunchAccess access,
  ) => _checkInHabitFromWidgetAction(habits, target, access);

  static Future<bool> createQuickTodo(
    BuildContext context,
    TodoItem todo, {
    WidgetLaunchAccess? access,
    bool Function()? isInteractionAvailable,
  }) => _createQuickTodoFromAction(
    context,
    todo,
    access: access,
    isInteractionAvailable: isInteractionAvailable,
  );

  static Future<void> completeTodo(
    BuildContext context,
    TodoProvider todos,
    TodoItem target,
    WidgetLaunchAccess access,
  ) => _completeTodoFromWidgetAction(context, todos, target, access);

  static Future<bool> pushHomeWidget(
    TodoProvider todos,
    HabitProvider habits,
    PomodoroProvider pomodoros,
    CalendarProvider calendar,
    CountdownProvider countdowns,
    TimeAuditProvider timeAudit,
    GoalProvider goals,
    AnniversaryProvider anniversaries,
    CourseProvider courses,
    NoteProvider notes,
    DiaryProvider diaries,
    ThemeProvider theme,
    PreferencesProvider preferences, {
    bool force = false,
    bool Function()? isPresentationCurrent,
  }) => _pushHomeWidget(
    todos,
    habits,
    pomodoros,
    calendar,
    countdowns,
    timeAudit,
    goals,
    anniversaries,
    courses,
    notes,
    diaries,
    theme,
    preferences,
    force: force,
    isPresentationCurrent: isPresentationCurrent,
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
  return homeWidgetScheduleEvents(
    calendar.buildEventsForDateSnapshot(
      today,
      todos.todos,
      habits.habits,
      pomodoros.sessions,
      themeProvider.brand.theme.colorScheme,
      anniversaries: anniversaries.itemsAt(today),
      courses: courses.courses,
      courseSettings: courses.settings,
      diaries: diaries.entries,
      countdowns: countdowns.items,
      goals: goals.goals,
      timeEntries: timeAudit.entries,
      now: today,
    ),
  );
}

String _homeWidgetEventLabel(CalendarEvent event) =>
    homeWidgetScheduleEventLabel(event);

String _homeWidgetEventDeepLink(CalendarEvent event) =>
    homeWidgetScheduleEventDeepLink(event);

Future<DailyDigestReminderResult> _syncDailyDigestReminder(
  PreferencesProvider prefs,
  NotificationService notification,
  TodoProvider todos, {
  int? submittedAccountGeneration,
}) {
  return _digestReminderCoordinator.run<DailyDigestReminderResult>(
    (run) => _syncDailyDigestReminderLocked(prefs, notification, todos, run),
    submittedAccountGeneration: submittedAccountGeneration,
    skippedResult: () => const DailyDigestReminderResult(),
  );
}

Future<DailyDigestReminderResult> _syncDailyDigestReminderLocked(
  PreferencesProvider prefs,
  NotificationService notification,
  TodoProvider todos,
  DigestReminderRun run,
) async {
  const baseId = 880017;
  final cancelled = await _cancelDailyDigestReminderIds(
    notification,
    baseId: baseId,
    slotCount: 3,
  );
  if (!run.isCurrent) return const DailyDigestReminderResult();
  if (!cancelled) {
    debugPrint(
      '[DailyDigest] cancel incomplete; skip scheduling to avoid duplicate delivery',
    );
    notification.recordReminderScheduleIssueWithCopy(
      title: '每日提醒注册失败',
      message: '旧提醒取消不完整，已暂停本次重新注册以避免重复提醒。请稍后重试，或重启应用后重新保存提醒。',
      copy: const ReminderIssueCopy.notification(
        NotificationIssueNotice.dailyCancellationFailed,
        titleCode: NotificationIssueTitle.dailyRegistrationFailed,
      ),
      relatedId: 'daily_reminder',
      blocking: true,
    );
    return const DailyDigestReminderResult(
      issues: [
        DailyDigestReminderIssue(
          title: '每日提醒注册失败',
          message: '旧提醒取消不完整，已暂停本次重新注册以避免重复提醒。请稍后重试，或重启应用后重新保存提醒。',
          copy: ReminderIssueCopy.notification(
            NotificationIssueNotice.dailyCancellationFailed,
            titleCode: NotificationIssueTitle.dailyRegistrationFailed,
          ),
          relatedId: 'daily_reminder',
        ),
      ],
    );
  }

  if (!_isLocalNotificationsPlatformRegistered()) {
    return const DailyDigestReminderResult();
  }
  final now = DateTime.now();
  final scheduleSlots = effectiveDailyReminderScheduleSlots(
    prefs.dailyReminderSlots,
  );
  final copy = DailyDigestPresentation(isEnglish: run.isEnglish);
  final issues = <DailyDigestReminderIssue>[];
  void rememberIssue(_DailyDigestScheduleIssueDraft issue) {
    issues.add(issue.toResultIssue());
  }

  for (final entry in scheduleSlots) {
    if (!run.isCurrent) return const DailyDigestReminderResult();
    final i = entry.index;
    final slot = entry.slot;
    final body = _dailyDigestBody(now, todos, slot, isEnglish: run.isEnglish);

    try {
      final id = baseId + i;
      final title = copy.slotTitle(i);
      final repeatDays = slot.repeatDays;
      if (slot.pauseHolidays) {
        await _scheduleHolidayAwareDailyDigest(
          notification: notification,
          baseId: id,
          title: title,
          body: body,
          locale: run.isEnglish ? AppLocale.en : AppLocale.zh,
          now: now,
          slot: slot,
          slotIndex: i,
          rememberIssue: rememberIssue,
        );
      } else {
        await _scheduleDailyDigestRepeating(
          notification: notification,
          id: id,
          title: title,
          body: body,
          locale: run.isEnglish ? AppLocale.en : AppLocale.zh,
          slot: slot,
          repeatDays: repeatDays,
          now: now,
          slotIndex: i,
          rememberIssue: rememberIssue,
        );
      }
    } on NotificationPermissionDeniedException catch (e) {
      if (!run.isCurrent) return const DailyDigestReminderResult();
      debugPrint('[DailyDigest] notification permission denied: $e');
      rememberIssue(
        _recordDailyDigestScheduleIssue(
          notification,
          slot: slot,
          index: i,
          now: now,
          message: e.message,
          copy: ReminderIssueCopy.notification(
            NotificationIssueNotice.repeatPermissionDenied,
            titleCode: NotificationIssueTitle.dailyRegistrationFailed,
          ),
        ),
      );
    } catch (e, st) {
      if (!run.isCurrent) return const DailyDigestReminderResult();
      debugPrint('[DailyDigest] schedule failed: $e\n$st');
      rememberIssue(
        _recordDailyDigestScheduleIssue(
          notification,
          slot: slot,
          index: i,
          now: now,
          message: '系统调度失败，提醒未确认注册成功：$e',
          copy: ReminderIssueCopy.notification(
            NotificationIssueNotice.dailyScheduleFailed,
            titleCode: NotificationIssueTitle.dailyRegistrationFailed,
            detail: e.toString(),
          ),
        ),
      );
    }
  }
  return DailyDigestReminderResult(issues: List.unmodifiable(issues));
}

class _DailyDigestScheduleIssueDraft {
  final String title;
  final String message;
  final DateTime? scheduledTime;
  final String? relatedId;
  final bool blocking;
  final ReminderIssueCopy? copy;

  const _DailyDigestScheduleIssueDraft({
    required this.title,
    required this.message,
    this.scheduledTime,
    this.relatedId,
    this.blocking = true,
    this.copy,
  });

  void record(NotificationService notification) {
    final localizedCopy = copy;
    if (localizedCopy == null) {
      notification.recordReminderScheduleIssue(
        title: title,
        message: message,
        scheduledTime: scheduledTime,
        relatedId: relatedId,
        blocking: blocking,
      );
    } else {
      notification.recordReminderScheduleIssueWithCopy(
        title: title,
        message: message,
        scheduledTime: scheduledTime,
        relatedId: relatedId,
        blocking: blocking,
        copy: localizedCopy,
      );
    }
  }

  DailyDigestReminderIssue toResultIssue() {
    return DailyDigestReminderIssue(
      title: title,
      message: message,
      scheduledTime: scheduledTime,
      relatedId: relatedId,
      blocking: blocking,
      copy: copy,
    );
  }
}

_DailyDigestScheduleIssueDraft _recordDailyDigestScheduleIssue(
  NotificationService notification, {
  required DailyReminderSlot slot,
  required int index,
  required DateTime now,
  required String message,
  bool blocking = true,
  ReminderIssueCopy? copy,
}) {
  final issue = _DailyDigestScheduleIssueDraft(
    title: '每日提醒注册失败',
    message: message,
    scheduledTime: _nextDailyReminderTime(now, slot),
    relatedId: 'daily_reminder_$index',
    blocking: blocking,
    copy: copy,
  );
  issue.record(notification);
  return issue;
}

_DailyDigestScheduleIssueDraft _recordDailyDigestFallbackIssue(
  NotificationService notification, {
  required DailyReminderSlot slot,
  required int index,
  required DateTime scheduledTime,
  required ReminderKind requestedKind,
  required Object error,
}) {
  final requestedLabel = switch (requestedKind) {
    ReminderKind.popup => '弹出框',
    ReminderKind.alarm => '锁屏闹钟',
    ReminderKind.push => '普通通知',
    ReminderKind.email => '邮件',
    ReminderKind.off => '关闭',
  };
  final issue = _DailyDigestScheduleIssueDraft(
    title: '每日提醒已退回普通通知',
    copy: ReminderIssueCopy.notification(
      NotificationIssueNotice.dailyChannelFallback,
      titleCode: NotificationIssueTitle.dailyFallback,
      requestedKind: requestedKind,
      detail: error.toString(),
    ),
    message:
        '你选择的是$requestedLabel提醒，但该通道没有确认注册成功，已改用普通通知兜底；到点不会按$requestedLabel形式弹出。请在已注册提醒详情确认状态，检查通知、精准闹钟、全屏提醒和后台限制后重新保存。($error)',
    scheduledTime: scheduledTime,
    relatedId: 'daily_reminder_$index',
    blocking: false,
  );
  issue.record(notification);
  return issue;
}

_DailyDigestScheduleIssueDraft _recordDailyDigestAlarmHandoffIssue(
  NotificationService notification, {
  required int index,
  required DateTime? scheduledTime,
  required Object error,
}) {
  final issue = _DailyDigestScheduleIssueDraft(
    title: '每日闹钟注册状态未确认',
    copy: ReminderIssueCopy.notification(
      NotificationIssueNotice.dailyAlarmHandoffFailed,
      titleCode: NotificationIssueTitle.dailyAlarmUnconfirmed,
      detail: error.toString(),
    ),
    message: '闹钟提醒交接失败，已跳过普通通知兜底以避免重复提醒。请在已注册提醒中确认，或重新保存该提醒。($error)',
    scheduledTime: scheduledTime,
    relatedId: 'daily_reminder_$index',
    blocking: false,
  );
  issue.record(notification);
  return issue;
}

bool _isLocalNotificationsPlatformRegistered() {
  if (kIsWeb) return false;
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    return switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        plugin.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>() !=
            null,
      TargetPlatform.iOS =>
        plugin.resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>() !=
            null,
      TargetPlatform.macOS =>
        plugin.resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin>() !=
            null,
      TargetPlatform.linux =>
        plugin.resolvePlatformSpecificImplementation<
                LinuxFlutterLocalNotificationsPlugin>() !=
            null,
      TargetPlatform.windows || TargetPlatform.fuchsia => false,
    };
  } on Error {
    return false;
  } catch (_) {
    return false;
  }
}

Future<bool> _cancelDailyDigestReminderIds(
  NotificationService notification, {
  required int baseId,
  required int slotCount,
}) async {
  if (!_isLocalNotificationsPlatformRegistered()) {
    return true;
  }
  var ok = true;
  for (var slot = 0; slot < slotCount; slot++) {
    final id = baseId + slot;
    ok = await _cancelDailyDigestChannelId(notification, id) && ok;
    for (var derived = 0; derived < _dailyDigestHolidayWindowDays; derived++) {
      ok =
          await _cancelDailyDigestChannelId(notification, id * 100 + derived) &&
          ok;
    }
  }
  return ok;
}

Future<bool> _cancelDailyDigestChannelId(
  NotificationService notification,
  int id,
) async {
  var ok = true;
  Future<void> cancelSafely(
    String label,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e, st) {
      ok = false;
      debugPrint('[DailyDigest] cancel $label failed for $id: $e\n$st');
    }
  }

  await cancelSafely('notification', () => notification.cancel(id));
  await cancelSafely('alarm', () => _reminderScheduler.alarm.cancel(id));
  await cancelSafely('popup', () => _reminderScheduler.popup.cancel(id));
  return ok;
}

Future<void> _scheduleDailyDigestRepeating({
  required NotificationService notification,
  required int id,
  required String title,
  required String body,
  required AppLocale locale,
  required DailyReminderSlot slot,
  required List<int> repeatDays,
  required DateTime now,
  required int slotIndex,
  required void Function(_DailyDigestScheduleIssueDraft issue) rememberIssue,
}) async {
  final weekdays = repeatDays.length == 7 ? null : repeatDays;
  final payload = 'duoyi://tab/today';
  Future<void> schedulePushFallback() => notification.scheduleDaily(
    id: id,
    title: title,
    body: body,
    hour: slot.hour,
    minute: slot.minute,
    weekdays: weekdays,
    payload: payload,
  );

  switch (DailyReminderSlot.normalizeKind(slot.kind)) {
    case ReminderKind.push:
      await schedulePushFallback();
    case ReminderKind.popup:
      try {
        await _reminderScheduler.popup.scheduleRepeating(
          id: id,
          title: title,
          body: body,
          hour: slot.hour,
          minute: slot.minute,
          weekdays: weekdays,
          payload: payload,
        );
      } catch (e, st) {
        debugPrint(
          '[DailyDigest] popup schedule failed, fallback to push: $e\n$st',
        );
        await schedulePushFallback();
        rememberIssue(
          _recordDailyDigestFallbackIssue(
            notification,
            slot: slot,
            index: slotIndex,
            scheduledTime: _nextDailyReminderTime(now, slot),
            requestedKind: ReminderKind.popup,
            error: e,
          ),
        );
      }
    case ReminderKind.alarm:
      try {
        final alarm = _reminderScheduler.alarm;
        if (alarm is AlarmService) {
          await alarm.scheduleDailyFullScreen(
            id: id,
            title: title,
            body: body,
            hour: slot.hour,
            minute: slot.minute,
            weekdays: weekdays,
            payload: payload,
            fullScreen: true,
            vibrate: true,
            snoozeMinutes: 5,
            repeatCount: 0,
            locale: locale,
          );
        } else {
          await _reminderScheduler.alarm.scheduleDailyFullScreen(
            id: id,
            title: title,
            body: body,
            hour: slot.hour,
            minute: slot.minute,
            weekdays: weekdays,
            payload: payload,
            fullScreen: true,
            vibrate: true,
            snoozeMinutes: 5,
            repeatCount: 0,
          );
        }
      } on AlarmQueueHandoffException catch (e) {
        debugPrint(
          '[DailyDigest] alarm schedule handoff failed; skip push fallback to avoid duplicate delivery: $e',
        );
        rememberIssue(
          _recordDailyDigestAlarmHandoffIssue(
            notification,
            index: slotIndex,
            scheduledTime: _nextDailyReminderTime(now, slot),
            error: e,
          ),
        );
      } catch (e, st) {
        debugPrint('[DailyDigest] alarm schedule failed: $e\n$st');
        if (await _dailyDigestAlarmQueueAlreadyOwns(
          notification: notification,
          id: id,
          slotIndex: slotIndex,
          weekdays: weekdays,
          label: 'daily repeating digest',
          scheduledTime: _nextDailyReminderTime(now, slot),
          rememberIssue: rememberIssue,
        )) {
          return;
        }
        debugPrint('[DailyDigest] alarm schedule failed, fallback to push');
        await schedulePushFallback();
        rememberIssue(
          _recordDailyDigestFallbackIssue(
            notification,
            slot: slot,
            index: slotIndex,
            scheduledTime: _nextDailyReminderTime(now, slot),
            requestedKind: ReminderKind.alarm,
            error: e,
          ),
        );
      }
    case ReminderKind.off:
      return;
    case ReminderKind.email:
      await schedulePushFallback();
  }
}

Future<void> _scheduleHolidayAwareDailyDigest({
  required NotificationService notification,
  required int baseId,
  required String title,
  required String body,
  required AppLocale locale,
  required DateTime now,
  required DailyReminderSlot slot,
  required int slotIndex,
  required void Function(_DailyDigestScheduleIssueDraft issue) rememberIssue,
}) async {
  var cursor = DateTime(now.year, now.month, now.day, slot.hour, slot.minute);
  final isWorkdayDigest =
      slot.repeatDays.isNotEmpty &&
      slot.repeatDays.every(
        (day) => day >= DateTime.monday && day <= DateTime.friday,
      );
  var scheduled = 0;
  for (
    var offset = 0;
    offset < _dailyDigestHolidayWindowDays &&
        scheduled < _dailyDigestHolidayWindowDays;
    offset++
  ) {
    final target = cursor.add(Duration(days: offset));
    if (!target.isAfter(now)) continue;
    final weekdayAllowed =
        slot.repeatDays.contains(target.weekday) ||
        (isWorkdayDigest && HolidayCalendar.isWorkMakeupDay(target));
    final holidayPaused = HolidayCalendar.isHoliday(target);
    if (!weekdayAllowed || holidayPaused) continue;
    await _scheduleDailyDigestOnce(
      notification: notification,
      id: baseId * 100 + scheduled,
      title: title,
      body: body,
      locale: locale,
      when: target,
      slot: slot,
      slotIndex: slotIndex,
      rememberIssue: rememberIssue,
    );
    scheduled++;
  }
  if (scheduled == 0) {
    final target = _nextDailyReminderTime(now, slot);
    final weekdayAllowed =
        slot.repeatDays.contains(target.weekday) ||
        (isWorkdayDigest && HolidayCalendar.isWorkMakeupDay(target));
    final holidayPaused = slot.pauseHolidays && HolidayCalendar.isHoliday(target);
    if (target.isAfter(now) && weekdayAllowed && !holidayPaused) {
      await _scheduleDailyDigestOnce(
        notification: notification,
        id: baseId * 100,
        title: title,
        body: body,
        locale: locale,
        when: target,
        slot: slot,
        slotIndex: slotIndex,
        rememberIssue: rememberIssue,
      );
    }
  }
}

Future<void> _scheduleDailyDigestOnce({
  required NotificationService notification,
  required int id,
  required String title,
  required String body,
  required AppLocale locale,
  required DateTime when,
  required DailyReminderSlot slot,
  required int slotIndex,
  required void Function(_DailyDigestScheduleIssueDraft issue) rememberIssue,
}) async {
  final payload = 'duoyi://tab/today';
  Future<void> schedulePushFallback() => notification.scheduleOnce(
    id: id,
    title: title,
    body: body,
    when: when,
    payload: payload,
  );

  switch (DailyReminderSlot.normalizeKind(slot.kind)) {
    case ReminderKind.push:
      await schedulePushFallback();
    case ReminderKind.popup:
      try {
        await _reminderScheduler.popup.scheduleOnce(
          id: id,
          title: title,
          body: body,
          when: when,
          payload: payload,
        );
      } catch (e, st) {
        debugPrint(
          '[DailyDigest] popup one-shot failed, fallback to push: $e\n$st',
        );
        await schedulePushFallback();
        rememberIssue(
          _recordDailyDigestFallbackIssue(
            notification,
            slot: slot,
            index: slotIndex,
            scheduledTime: when,
            requestedKind: ReminderKind.popup,
            error: e,
          ),
        );
      }
    case ReminderKind.alarm:
      try {
        final alarm = _reminderScheduler.alarm;
        if (alarm is AlarmService) {
          await alarm.scheduleFullScreen(
            id: id,
            title: title,
            body: body,
            when: when,
            payload: payload,
            fullScreen: true,
            vibrate: true,
            snoozeMinutes: 5,
            repeatCount: 0,
            locale: locale,
          );
        } else {
          await _reminderScheduler.alarm.scheduleFullScreen(
            id: id,
            title: title,
            body: body,
            when: when,
            payload: payload,
            fullScreen: true,
            vibrate: true,
            snoozeMinutes: 5,
            repeatCount: 0,
          );
        }
      } on AlarmQueueHandoffException catch (e) {
        debugPrint(
          '[DailyDigest] alarm one-shot handoff failed; skip push fallback to avoid duplicate delivery: $e',
        );
        rememberIssue(
          _recordDailyDigestAlarmHandoffIssue(
            notification,
            index: slotIndex,
            scheduledTime: when,
            error: e,
          ),
        );
      } catch (e, st) {
        debugPrint('[DailyDigest] alarm one-shot failed: $e\n$st');
        if (await _dailyDigestAlarmQueueAlreadyOwns(
          notification: notification,
          id: id,
          slotIndex: slotIndex,
          label: 'daily one-shot digest',
          scheduledTime: when,
          rememberIssue: rememberIssue,
        )) {
          return;
        }
        debugPrint('[DailyDigest] alarm one-shot failed, fallback to push');
        await schedulePushFallback();
        rememberIssue(
          _recordDailyDigestFallbackIssue(
            notification,
            slot: slot,
            index: slotIndex,
            scheduledTime: when,
            requestedKind: ReminderKind.alarm,
            error: e,
          ),
        );
      }
    case ReminderKind.off:
      return;
    case ReminderKind.email:
      await schedulePushFallback();
  }
}

Future<bool> _dailyDigestAlarmQueueAlreadyOwns({
  required NotificationService notification,
  required int id,
  required int slotIndex,
  required String label,
  required DateTime scheduledTime,
  required void Function(_DailyDigestScheduleIssueDraft issue) rememberIssue,
  List<int>? weekdays,
}) async {
  final alarm = _reminderScheduler.alarm;
  if (alarm is! ReminderPendingSink) return false;
  final pendingAlarm = alarm as ReminderPendingSink;
  final expected = _dailyDigestExpectedAlarmIds(id, weekdays);
  final acceptedSets = <Set<int>>[
    <int>{id},
    if (expected.length > 1) expected,
  ];
  try {
    final actual = (await pendingAlarm.pendingIds()).toSet();
    final owns = acceptedSets.any(
      (ids) => ids.isNotEmpty && actual.containsAll(ids),
    );
    if (owns) {
      debugPrint(
        '[DailyDigest] $label alarm queue already registered; skip push fallback to avoid duplicate delivery.',
      );
    }
    return owns;
  } catch (e, st) {
    debugPrint(
      '[DailyDigest] $label pending probe failed; skip push fallback to avoid duplicate delivery: $e\n$st',
    );
    final issue = _DailyDigestScheduleIssueDraft(
      title: '每日闹钟注册状态未确认',
      copy: ReminderIssueCopy.notification(
        NotificationIssueNotice.dailyAlarmQueueUnconfirmed,
        titleCode: NotificationIssueTitle.dailyAlarmUnconfirmed,
        detail: e.toString(),
      ),
      message:
          '闹钟待触发队列读取失败，无法确认锁屏闹钟是否已注册；为避免重复提醒已跳过普通通知兜底。请在系统权限正常后重新保存提醒。($e)',
      relatedId: 'daily_reminder_$slotIndex',
      scheduledTime: scheduledTime,
      blocking: false,
    );
    issue.record(notification);
    rememberIssue(issue);
    return true;
  }
}

Set<int> _dailyDigestExpectedAlarmIds(int id, List<int>? weekdays) {
  final normalized = weekdays == null || weekdays.isEmpty
      ? const <int>[]
      : weekdays.where((w) => w >= 1 && w <= 7).toSet().toList();
  if (normalized.isEmpty) return <int>{id};
  return {for (final weekday in normalized) _dailyDigestSubId(id, weekday)};
}

int _dailyDigestSubId(int base, int weekday) {
  var hash = 0x811c9dc5;
  final key = '$base:$weekday';
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? weekday : hash;
}

DateTime _nextDailyReminderTime(DateTime now, DailyReminderSlot slot) {
  var target = DateTime(now.year, now.month, now.day, slot.hour, slot.minute);
  if (!target.isAfter(now)) target = target.add(const Duration(days: 1));
  final isWorkdayDigest =
      slot.repeatDays.isNotEmpty &&
      slot.repeatDays.every(
        (day) => day >= DateTime.monday && day <= DateTime.friday,
      );

  final maxSearchDays = _dailyDigestHolidayWindowDays * 4;
  for (var i = 0; i < maxSearchDays; i++) {
    final weekdayAllowed =
        slot.repeatDays.contains(target.weekday) ||
        (isWorkdayDigest && HolidayCalendar.isWorkMakeupDay(target));
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
  DailyReminderSlot slot, {
  required bool isEnglish,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));
  final todayCount = todos.visibleTodayTodos(now).length;
  final tomorrowCount = todos.todos.where((t) {
    final d = DateTime(t.date.year, t.date.month, t.date.day);
    return d.isAtSameMomentAs(tomorrow) && !t.isCompleted;
  }).length;
  final overdueCount = todos.todos.where((t) => t.isOverdue).length;

  return DailyDigestPresentation(isEnglish: isEnglish).body(
    todayCount: todayCount,
    tomorrowCount: tomorrowCount,
    overdueCount: overdueCount,
    includeTodayTasks: slot.includeTodayTasks,
    includeTomorrowPlan: slot.includeTomorrowPlan,
    includeOverdue: slot.includeOverdue,
  );
}

Future<void> _syncReportDigestReminders(
  PreferencesProvider prefs,
  NotificationService notification, {
  required TodoProvider todos,
  required HabitProvider habits,
  required PomodoroProvider pomodoros,
  required TimeAuditProvider timeAudit,
  int? submittedAccountGeneration,
}) => _digestReminderCoordinator.run<void>(
  (run) => _syncReportDigestRemindersLocked(
    prefs,
    notification,
    todos: todos,
    habits: habits,
    pomodoros: pomodoros,
    timeAudit: timeAudit,
    run: run,
  ),
  submittedAccountGeneration: submittedAccountGeneration,
  skippedResult: () {},
);

Future<void> _syncReportDigestRemindersLocked(
  PreferencesProvider prefs,
  NotificationService notification, {
  required TodoProvider todos,
  required HabitProvider habits,
  required PomodoroProvider pomodoros,
  required TimeAuditProvider timeAudit,
  required DigestReminderRun run,
}) async {
  const weeklyId = 880020;
  const monthlyId = 880021;
  const yearlyId = 880022;
  const dailyId = 880023;
  if (!_isLocalNotificationsPlatformRegistered()) {
    return;
  }
  await notification.cancel(dailyId);
  await notification.cancel(weeklyId);
  await notification.cancel(monthlyId);
  await notification.cancel(yearlyId);
  if (!run.isCurrent) return;

  final now = DateTime.now();
  final dailyConfig = prefs.dailyReportReminderConfig;
  if (dailyConfig.enabled && run.isCurrent) {
    try {
      final when = dailyConfig.nextDailyReminderTime(now);
      await notification.scheduleOnce(
        id: dailyId,
        title: PeriodReportPresentation.notificationTitleFor(
          PeriodReportKind.daily,
          isEnglish: run.isEnglish,
        ),
        body: _reportDigestNotificationBody(
          kind: PeriodReportKind.daily,
          now: now,
          scheduledFor: when,
          todos: todos,
          habits: habits,
          pomodoros: pomodoros,
          timeAudit: timeAudit,
          isEnglish: run.isEnglish,
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
  if (weeklyConfig.enabled && run.isCurrent) {
    try {
      final when = weeklyConfig.nextWeeklyReminderTime(now);
      await notification.scheduleOnce(
        id: weeklyId,
        title: PeriodReportPresentation.notificationTitleFor(
          PeriodReportKind.weekly,
          isEnglish: run.isEnglish,
        ),
        body: _reportDigestNotificationBody(
          kind: PeriodReportKind.weekly,
          now: now,
          scheduledFor: when,
          todos: todos,
          habits: habits,
          pomodoros: pomodoros,
          timeAudit: timeAudit,
          isEnglish: run.isEnglish,
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
  if (monthlyConfig.enabled && run.isCurrent) {
    try {
      final when = monthlyConfig.nextMonthlyReminderTime(now);
      await notification.scheduleOnce(
        id: monthlyId,
        title: PeriodReportPresentation.notificationTitleFor(
          PeriodReportKind.monthly,
          isEnglish: run.isEnglish,
        ),
        body: _reportDigestNotificationBody(
          kind: PeriodReportKind.monthly,
          now: now,
          scheduledFor: when,
          todos: todos,
          habits: habits,
          pomodoros: pomodoros,
          timeAudit: timeAudit,
          isEnglish: run.isEnglish,
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
  if (yearlyConfig.enabled && run.isCurrent) {
    try {
      final when = yearlyConfig.nextYearlyReminderTime(now);
      await notification.scheduleOnce(
        id: yearlyId,
        title: PeriodReportPresentation.notificationTitleFor(
          PeriodReportKind.yearly,
          isEnglish: run.isEnglish,
        ),
        body: _reportDigestNotificationBody(
          kind: PeriodReportKind.yearly,
          now: now,
          scheduledFor: when,
          todos: todos,
          habits: habits,
          pomodoros: pomodoros,
          timeAudit: timeAudit,
          isEnglish: run.isEnglish,
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
  required bool isEnglish,
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
  return PeriodReportPresentation(
    PeriodReportDigest(
      kind: kind,
      report: report,
      comparison: ReportEngine.compare(
        current: report,
        previous: previousReport,
      ),
      generatedAt: now,
    ),
    isEnglish: isEnglish,
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

void _queuePendingWidgetUri(
  Uri uri,
  String reason,
  WidgetNavigationRequest request, {
  required WidgetLinkOrigin origin,
}) {
  final existingIndex = _pendingWidgetUris.indexWhere(
    (pending) =>
        pending.uri.toString() == uri.toString() && pending.origin == origin,
  );
  if (existingIndex >= 0) {
    _pendingWidgetUris[existingIndex] = (
      uri: uri,
      request: request,
      origin: origin,
    );
    return;
  }
  if (_pendingWidgetUris.length >= 20 &&
      !HomeWidgetService.isReceivedLaunch(uri)) {
    final disposable = _pendingWidgetUris.indexWhere(
      (pending) => !HomeWidgetService.isReceivedLaunch(pending.uri),
    );
    if (disposable < 0) return;
    _pendingWidgetUris.removeAt(disposable);
  }
  _pendingWidgetUris.add((uri: uri, request: request, origin: origin));
  debugPrint('[DeepLink] queued launch: $reason');
}

void _drainPendingWidgetUris(PomodoroProvider pomodoro) {
  if (_pendingWidgetUris.isEmpty || _appAccessBlocked) return;
  final pending = List<_PendingWidgetLaunch>.of(_pendingWidgetUris);
  _pendingWidgetUris.clear();
  for (final launch in pending) {
    _handleWidgetUri(
      launch.uri,
      pomodoro,
      allowQueue: true,
      navigationRequest: launch.request,
      origin: launch.origin,
    );
  }
}

Future<bool> _drainPendingWidgetBgActions(PomodoroProvider pomodoro) async {
  if (kIsWeb) return false;
  try {
    final pendingUris = await HomeWidgetService.drainPendingBgActions();
    if (pendingUris.isEmpty) return false;
    await _ensureHomeWidgetDataReady?.call();
    for (final uri in pendingUris) {
      _handleWidgetUri(uri, pomodoro);
    }
    return true;
  } catch (e, st) {
    debugPrint('[HomeWidget] drainPendingBgActions failed: $e\n$st');
    return false;
  }
}

bool _reserveWidgetActionUri(Uri uri) {
  // The native bridge deduplicates deliveries. Separate user taps can share
  // the same action URL and must each increment a count-based habit.
  if (HomeWidgetService.isReceivedLaunch(uri)) return true;
  final now = DateTime.now();
  _recentWidgetActionUris.removeWhere(
    (_, at) => now.difference(at) > const Duration(seconds: 5),
  );
  final key = uri.toString();
  final last = _recentWidgetActionUris[key];
  if (last != null && now.difference(last) <= const Duration(seconds: 5)) {
    debugPrint('[DeepLink] duplicate widget action skipped');
    return false;
  }
  _recentWidgetActionUris[key] = now;
  return true;
}

bool _isCalendarNavigationUri(Uri uri) =>
    uri.host == 'calendar' ||
    uri.host == 'event' ||
    uri.host == 'pomodoro' ||
    (uri.host == 'tab' && uri.pathSegments.firstOrNull == 'calendar');

void _handleWidgetUri(
  Uri? uri,
  PomodoroProvider pomodoro, {
  int retry = 0,
  bool allowQueue = true,
  bool dataReady = false,
  WidgetNavigationRequest? navigationRequest,
  Uri? receivedUri,
  WidgetLinkOrigin origin = WidgetLinkOrigin.external,
}) {
  if (uri == null) return;
  if (uri.scheme != 'duoyi') return;
  final originalUri = receivedUri ?? uri;
  final request = navigationRequest ?? _widgetNavigationRequests.capture();
  if (!request.isCurrentAccount) {
    unawaited(HomeWidgetService.acknowledgeLaunch(originalUri));
    return;
  }
  if (_isCalendarNavigationUri(uri) && !request.isLatest) {
    unawaited(HomeWidgetService.acknowledgeLaunch(originalUri));
    return;
  }

  if (_appAccessBlocked) {
    _queuePendingWidgetUri(
      originalUri,
      'app access blocked',
      request,
      origin: origin,
    );
    return;
  }

  final state = mainShellKey.currentState;
  final ctx = mainShellKey.currentContext;
  if (ctx != null && _widgetAccountUnavailable(ctx.read<AuthProvider>())) {
    unawaited(HomeWidgetService.acknowledgeLaunch(originalUri));
    return;
  }
  if (state == null && retry < 8) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleWidgetUri(
        uri,
        pomodoro,
        retry: retry + 1,
        allowQueue: allowQueue,
        dataReady: dataReady,
        navigationRequest: request,
        receivedUri: originalUri,
        origin: origin,
      );
    });
    return;
  }
  if (state == null) {
    if (allowQueue) {
      _queuePendingWidgetUri(
        originalUri,
        'main shell not ready after $retry frames',
        request,
        origin: origin,
      );
    } else {
      debugPrint('[DeepLink] dropped launch: main shell not ready');
    }
    return;
  }

  if (!dataReady && WidgetLinkDispatch.requiresHydration(uri)) {
    unawaited(
      _dispatchWidgetUriAfterHydration(uri, pomodoro, request, origin: origin),
    );
    return;
  }

  final receivedLaunch = HomeWidgetService.isReceivedLaunch(originalUri);
  final delivery = receivedLaunch
      ? originalUri.queryParameters['widget_delivery']
      : null;
  if (receivedLaunch &&
      delivery != null &&
      !_handledWidgetDeliveries.add(delivery)) {
    if (!_inFlightWidgetDeliveries.contains(delivery)) {
      unawaited(HomeWidgetService.acknowledgeLaunch(originalUri));
    }
    return;
  }
  if (_handledWidgetDeliveries.length > 4096) {
    _handledWidgetDeliveries.remove(_handledWidgetDeliveries.first);
  }
  if (delivery != null) _inFlightWidgetDeliveries.add(delivery);
  final access = WidgetLaunchAccess(
    uri: originalUri,
    request: request,
    isBlocked: () => _appAccessBlocked,
    requiresLatest: _isCalendarNavigationUri(originalUri),
    isCallerAvailable: () =>
        ctx != null &&
        ctx.mounted &&
        !_widgetAccountUnavailable(ctx.read<AuthProvider>()),
    requeue: (uri, request) {
      if (delivery != null) {
        _handledWidgetDeliveries.remove(delivery);
        _inFlightWidgetDeliveries.remove(delivery);
      }
      _queuePendingWidgetUri(
        uri,
        'locked before deferred interaction',
        request,
        origin: origin,
      );
    },
    acknowledge: (uri) async {
      if (delivery != null) _inFlightWidgetDeliveries.remove(delivery);
      await HomeWidgetService.acknowledgeLaunch(uri);
    },
  );
  try {
    _routeHydratedWidgetUri(uri, pomodoro, state, ctx, request, access);
  } finally {
    access.finishDispatch();
  }
}

void _navigateWidgetSection(
  MainShellState state,
  BuildContext? context,
  int index,
) {
  state.navigateTo(index, allowHidden: true);
  if (context != null && context.mounted) {
    _widgetCalendarRoutes.showSection(Navigator.of(context));
  }
}

void _routeHydratedWidgetUri(
  Uri uri,
  PomodoroProvider pomodoro,
  MainShellState state,
  BuildContext? ctx,
  WidgetNavigationRequest navigationRequest,
  WidgetLaunchAccess access,
) {
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
    _navigateWidgetSection(state, ctx, idx);
  } else if (uri.host == 'oauth' && ctx != null) {
    _navigateWidgetSection(state, ctx, 6);
    access.afterFrame(() {
      final latestContext = mainShellKey.currentContext ?? ctx;
      Navigator.of(latestContext).push(
        MaterialPageRoute(
          builder: (_) => BrandRouteSurface(
            child: IntegrationsScreen(initialOAuthCallbackUri: uri),
          ),
        ),
      );
    });
  } else if (uri.host == 'todo' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (id == null || id.isEmpty) {
      _navigateWidgetSection(state, ctx, 1);
      return;
    }
    _navigateWidgetSection(state, ctx, 1);
    final confirm = uri.queryParameters['confirm'] == '1';
    if (confirm) {
      access.afterFrame(() {
        unawaited(access.run(() => _showTodoCompletePrompt(ctx, id, access)));
      });
    } else {
      // ignore: discarded_futures
      TodayDetailRouter.open(ctx, TodaySectionKind.todos, id: id);
    }
  } else if (uri.host == 'goal' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (id == null || id.isEmpty) {
      _pushHiddenWidgetFallbackRoute(ctx, const GoalScreen(), access);
      return;
    }
    _navigateWidgetSection(state, ctx, 0);
    // ignore: discarded_futures
    TodayDetailRouter.open(ctx, TodaySectionKind.goals, id: id);
  } else if (uri.host == 'habit' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    _navigateWidgetSection(state, ctx, 2);
    if (id == null || id.isEmpty) return;
    final confirm = uri.queryParameters['confirm'] == '1';
    if (confirm) {
      access.afterFrame(() {
        unawaited(access.run(() => _showHabitCheckInPrompt(ctx, id, access)));
      });
    } else {
      // ignore: discarded_futures
      TodayDetailRouter.open(ctx, TodaySectionKind.habits, id: id);
    }
  } else if ((uri.host == 'event' || uri.host == 'pomodoro') && ctx != null) {
    _navigateWidgetSection(state, ctx, uri.host == 'event' ? 3 : 4);
    if (uri.pathSegments.isNotEmpty) {
      access.afterFrame(() {
        unawaited(access.run(() => openWidgetScheduleDetail(ctx, uri, access)));
      });
    }
  } else if (uri.host == 'calendar') {
    state.navigateTo(3, allowHidden: true);
    final date = WidgetCalendarLink.dateFromUri(uri);
    if (date != null && ctx != null) {
      _openWidgetCalendarDate(ctx, date, navigationRequest, access);
    } else if (ctx != null) {
      _widgetCalendarRoutes.showSection(Navigator.of(ctx));
    }
  } else if (uri.host == 'focus') {
    _navigateWidgetSection(state, ctx, 4);
  } else if (uri.host == 'widget') {
    _navigateWidgetSection(state, ctx, 5);
  } else if (uri.host == 'course' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (id == null || id.isEmpty) {
      _pushHiddenWidgetFallbackRoute(ctx, const CourseScheduleScreen(), access);
      return;
    }
    _navigateWidgetSection(state, ctx, 0);
    // ignore: discarded_futures
    TodayDetailRouter.open(ctx, TodaySectionKind.courses, id: id);
  } else if (uri.host == 'anniversary' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (id == null || id.isEmpty) {
      _pushHiddenWidgetFallbackRoute(ctx, const AnniversaryScreen(), access);
      return;
    }
    _navigateWidgetSection(state, ctx, 0);
    // ignore: discarded_futures
    TodayDetailRouter.open(ctx, TodaySectionKind.anniversaries, id: id);
  } else if (uri.host == 'countdown' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    _pushHiddenWidgetFallbackRoute(
      ctx,
      CountdownScreen(initialCountdownId: id),
      access,
    );
  } else if (uri.host == 'note' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (id == null || id.isEmpty) {
      _pushHiddenWidgetFallbackRoute(ctx, const NoteScreen(), access);
    } else {
      _navigateWidgetSection(state, ctx, 0);
      // ignore: discarded_futures
      TodayDetailRouter.open(ctx, TodaySectionKind.notes, id: id);
    }
  } else if (uri.host == 'diary' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (id == null || id.isEmpty) {
      _pushHiddenWidgetFallbackRoute(ctx, const DiaryScreen(), access);
      return;
    }
    _navigateWidgetSection(state, ctx, 0);
    // ignore: discarded_futures
    TodayDetailRouter.open(ctx, TodaySectionKind.diary, id: id);
  } else if (uri.host == 'time-entry' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    _navigateWidgetSection(state, ctx, 6);
    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) =>
            BrandRouteSurface(child: TimeAuditScreen(initialEntryId: id)),
      ),
    );
  } else if (uri.host == 'report' && ctx != null) {
    _navigateWidgetSection(state, ctx, 6);
    access.afterFrame(() {
      final latestContext = mainShellKey.currentContext ?? ctx;
      Navigator.of(latestContext).push(
        MaterialPageRoute(
          builder: (_) => const BrandRouteSurface(child: StatisticsScreen()),
        ),
      );
    });
  } else if (uri.host == 'location' && ctx != null) {
    _navigateWidgetSection(state, ctx, 6);
    access.afterFrame(() {
      final latestContext = mainShellKey.currentContext ?? ctx;
      Navigator.of(latestContext).push(
        MaterialPageRoute(
          builder: (_) => const BrandRouteSurface(child: IntegrationsScreen()),
        ),
      );
    });
  } else if (uri.host == 'snooze' && ctx != null) {
    // 稍后提醒深链：duoyi://snooze/<id>?delay=<minutes>&title=...&body=...&payload=...
    final ns = Provider.of<NotificationService>(ctx, listen: false);
    // ignore: discarded_futures
    ns.handleSnoozeDeepLink(uri);
  } else if (uri.host == 'action') {
    final action = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    if (!_reserveWidgetActionUri(access.uri)) return;
    if (action == 'start_pomodoro') {
      _navigateWidgetSection(state, ctx, 4);
      if (pomodoro.state.isRunning) {
        if (ctx != null) {
          _showWidgetActionFeedback(
            ctx,
            const WidgetActionMessage(WidgetActionNotice.focusRunning),
          );
        }
      } else {
        pomodoro.startIfIdle();
        if (ctx != null) {
          _showWidgetActionFeedback(
            ctx,
            const WidgetActionMessage(WidgetActionNotice.focusStarted),
          );
        }
      }
    } else if (action == 'toggle_pomodoro') {
      _navigateWidgetSection(state, ctx, 4);
      final wasRunning = pomodoro.state.isRunning;
      pomodoro.toggleTimer();
      if (ctx != null && !wasRunning && pomodoro.state.isRunning) {
        _showWidgetActionFeedback(
          ctx,
          const WidgetActionMessage(WidgetActionNotice.focusStarted),
        );
      }
    } else if (action == 'pause_pomodoro') {
      _navigateWidgetSection(state, ctx, 4);
      if (pomodoro.state.isRunning) {
        pomodoro.toggleTimer();
      }
    } else if (action == 'finish_pomodoro' || action == 'stop_pomodoro') {
      _navigateWidgetSection(state, ctx, 4);
      pomodoro.finishCurrentSession();
    } else if (action == 'quick_note' && ctx != null) {
      _navigateWidgetSection(state, ctx, 0);
      access.afterFrame(() {
        final latestContext = mainShellKey.currentContext ?? ctx;
        if (!latestContext.mounted) return;
        Navigator.of(latestContext).push(
          MaterialPageRoute<void>(
            builder: (_) => const BrandRouteSurface(child: NoteEditScreen()),
          ),
        );
      });
    } else if (action == 'quick_diary' && ctx != null) {
      _navigateWidgetSection(state, ctx, 0);
      access.afterFrame(() {
        final latestContext = mainShellKey.currentContext ?? ctx;
        if (!latestContext.mounted) return;
        Navigator.of(latestContext).push(
          MaterialPageRoute<void>(
            builder: (_) => const BrandRouteSurface(child: DiaryEditScreen()),
          ),
        );
      });
    } else if (action == 'quick_goal' && ctx != null) {
      _navigateWidgetSection(state, ctx, 0);
      access.afterFrame(() {
        final latestContext = mainShellKey.currentContext ?? ctx;
        if (!latestContext.mounted) return;
        Navigator.of(latestContext).push(
          MaterialPageRoute<void>(
            builder: (_) => const BrandRouteSurface(child: GoalEditScreen()),
          ),
        );
      });
    } else if (action == 'quick_schedule' && ctx != null) {
      _navigateWidgetSection(state, ctx, 3);
      access.afterFrame(() {
        final latestContext = mainShellKey.currentContext ?? ctx;
        if (!latestContext.mounted) return;
        unawaited(showLocalCalendarEventEditor(latestContext));
      });
    } else if (action == 'refresh_widgets' && ctx != null) {
      access.markActionStarted();
      unawaited(_refreshWidgetsFromAction(ctx, access: access));
    } else if (action == 'quick_todo' && ctx != null) {
      final text = uri.queryParameters['text']?.trim();
      _navigateWidgetSection(state, ctx, 1);
      if (text != null && text.isNotEmpty) {
        final draft = SmartTodoDraftBuilder.fromText(text);
        unawaited(
          access.run(
            () =>
                _createQuickTodoFromAction(ctx, draft.toTodo(), access: access),
          ),
        );
        return;
      }
      access.afterFrame(() {
        unawaited(access.run(() => _showQuickTodoDialog(ctx, access)));
      });
    } else if (action == 'complete_todo' && ctx != null) {
      final id = uri.queryParameters['id'];
      if (id == null || id.isEmpty) return;
      _navigateWidgetSection(state, ctx, 1);
      final todos = Provider.of<TodoProvider>(ctx, listen: false);
      final target = todos.todos.where((todo) => todo.id == id).firstOrNull;
      if (target == null) {
        _showWidgetActionFeedback(
          ctx,
          const WidgetActionMessage(WidgetActionNotice.todoMissing),
        );
        return;
      }
      if (target.isCompleted) {
        _showWidgetActionFeedback(
          ctx,
          WidgetActionMessage(
            WidgetActionNotice.todoAlreadyCompleted,
            subject: target.title,
          ),
        );
        return;
      }
      unawaited(
        access.run(
          () => _completeTodoFromWidgetAction(ctx, todos, target, access),
        ),
      );
    } else if (action == 'checkin_habit' && ctx != null) {
      final id = uri.queryParameters['id'];
      _navigateWidgetSection(state, ctx, 2);
      if (id == null || id.isEmpty) return;
      final habits = Provider.of<HabitProvider>(ctx, listen: false);
      final target = habits.habits.where((habit) => habit.id == id).firstOrNull;
      if (target == null) {
        _showWidgetActionFeedback(
          ctx,
          const WidgetActionMessage(WidgetActionNotice.habitMissing),
        );
        return;
      }
      if (target.kind != HabitKind.positive) {
        _showWidgetActionFeedback(
          ctx,
          const WidgetActionMessage(WidgetActionNotice.habitUnsupported),
        );
        return;
      }
      if (!target.isActiveToday()) {
        _showWidgetActionFeedback(
          ctx,
          WidgetActionMessage(
            WidgetActionNotice.habitNotScheduled,
            subject: target.name,
          ),
        );
        return;
      }
      if (target.isCompletedToday()) {
        _showWidgetActionFeedback(
          ctx,
          WidgetActionMessage(
            WidgetActionNotice.habitAlreadyCompleted,
            subject: target.name,
          ),
        );
        return;
      }
      unawaited(
        access.run(() => _checkInHabitFromWidgetAction(habits, target, access)),
      );
    }
  } else {
    debugPrint('[DeepLink] unsupported entry');
    _navigateWidgetSection(state, ctx, 6);
    if (ctx != null) {
      _showWidgetActionFeedback(
        ctx,
        const WidgetActionMessage(WidgetActionNotice.unknownEntry),
      );
    }
  }
}

void _openWidgetCalendarDate(
  BuildContext context,
  DateTime date,
  WidgetNavigationRequest request,
  WidgetLaunchAccess access,
) {
  final auth = context.read<AuthProvider>();
  final scope = WidgetActionScope(
    isCallerAvailable: () =>
        context.mounted && !_widgetAccountUnavailable(auth) && request.isLatest,
  );
  access.afterFrame(() {
    if (!scope.isCurrent) return;
    final latestContext = mainShellKey.currentContext;
    if (latestContext == null || !latestContext.mounted) return;
    final navigator = Navigator.of(latestContext);
    final route = MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'widget/calendar/date'),
      builder: (_) =>
          BrandRouteSurface(child: CalendarScreen(initialDate: date)),
    );
    _widgetCalendarRoutes.open(navigator, route);
  });
}

void _pushHiddenWidgetFallbackRoute(
  BuildContext context,
  Widget child,
  WidgetLaunchAccess access,
) {
  mainShellKey.currentState?.navigateTo(6, allowHidden: true);
  if (context.mounted) {
    _widgetCalendarRoutes.showSection(Navigator.of(context));
  }
  access.afterFrame(() {
    final latestContext = mainShellKey.currentContext ?? context;
    if (!latestContext.mounted) return;
    Navigator.of(
      latestContext,
    ).push(MaterialPageRoute(builder: (_) => BrandRouteSurface(child: child)));
  });
}

void _showWidgetActionFeedback(
  BuildContext context,
  WidgetActionMessage message,
) {
  WidgetActionScope(
    isCallerAvailable: () =>
        context.mounted &&
        !_appAccessBlocked &&
        !_widgetAccountUnavailable(context.read<AuthProvider>()),
  ).afterFrame(() {
    final latestContext = mainShellKey.currentContext ?? context;
    if (!latestContext.mounted) return;
    ScaffoldMessenger.of(latestContext)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, locale, _) =>
                Text(message.render(locale: locale)),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1400),
        ),
      );
  });
}

void _showWidgetActionFeedbackFromShell(
  WidgetActionMessage message, {
  bool Function()? isCurrentAction,
}) {
  WidgetActionScope(
    isCallerAvailable: () =>
        !_appAccessBlocked && (isCurrentAction?.call() ?? true),
  ).afterFrame(() {
    final latestContext = mainShellKey.currentContext;
    if (latestContext == null || !latestContext.mounted) return;
    ScaffoldMessenger.of(latestContext)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, locale, _) =>
                Text(message.render(locale: locale)),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1400),
        ),
      );
  });
}

Future<bool> _createQuickTodoFromAction(
  BuildContext context,
  TodoItem todo, {
  WidgetLaunchAccess? access,
  bool Function()? isInteractionAvailable,
}) async {
  if (!context.mounted) return false;
  // Bind before permission/preflight awaits. Looking up a provider afterwards
  // could dispatch this old draft into the newly selected account.
  final auth = context.read<AuthProvider>();
  final todos = Provider.of<TodoProvider?>(context, listen: false);
  final result = await runWidgetQuickTodoAction<WidgetActionMessage>(
    isCallerAvailable: () =>
        context.mounted &&
        !_widgetAccountUnavailable(auth) &&
        (isInteractionAvailable?.call() ?? true) &&
        (access?.canProceed ?? !_appAccessBlocked),
    isFeedbackAvailable: () =>
        context.mounted &&
        !_widgetAccountUnavailable(auth) &&
        (access?.canDeliverFeedback ?? !_appAccessBlocked),
    preflight: (feedback) async {
      if (todos == null) {
        debugPrint(
          '[QuickTodoAction] TodoProvider unavailable for action create',
        );
        feedback(
          const WidgetActionMessage(WidgetActionNotice.quickTodoUnavailable),
        );
        return false;
      }
      return _preflightWidgetTodoReminder(
        context,
        todo,
        feedback: feedback,
        isAccessAvailable: () =>
            context.mounted &&
            !_widgetAccountUnavailable(auth) &&
            (isInteractionAvailable?.call() ?? true) &&
            (access?.canProceed ?? !_appAccessBlocked),
      );
    },
    create: () async {
      access?.markActionStarted();
      final waitForReminderSync = _todoNeedsReminderSync(todo);
      final reminderSyncResult = await todos!.addTodoWithResult(
        todo,
        waitForReminderSync: waitForReminderSync,
      );
      final reminderSyncIssue = waitForReminderSync
          ? reminderSyncResult?.issue
          : null;
      return reminderSyncIssue == null
          ? _quickTodoCreatedNotice(todo)
          : WidgetActionMessage(
              WidgetActionNotice.savedReminderIssue,
              detail: reminderSyncIssue,
              syncIssueCopy: reminderSyncResult?.issueCopy,
            );
    },
    feedback: (message, isCurrent) =>
        _showWidgetActionFeedbackFromShell(message, isCurrentAction: isCurrent),
    failureMessage: const WidgetActionMessage(
      WidgetActionNotice.quickTodoFailed,
    ),
    logError: (error, stack) =>
        debugPrint('[QuickTodoAction] create failed: $error\n$stack'),
  );
  return result == WidgetQuickTodoResult.saved;
}

bool _widgetAccountUnavailable(AuthProvider auth) =>
    auth.isLocalAccountDataBlocked || auth.isAccountTransitionInProgress;

Future<void> _dispatchWidgetUriAfterHydration(
  Uri uri,
  PomodoroProvider pomodoro,
  WidgetNavigationRequest navigationRequest, {
  required WidgetLinkOrigin origin,
}) async {
  final generation = AccountLocalDataCleaner.accountDataGeneration;
  final scope = WidgetActionScope(
    isCallerAvailable: () =>
        !_isCalendarNavigationUri(uri) || navigationRequest.isLatest,
  );
  try {
    final result = await WidgetLinkDispatch.resolve(
      uri,
      origin: origin,
      hydrate: () async => await _ensureHomeWidgetDataReady?.call(),
      validate: HomeWidgetService.isCurrentWidgetAction,
      isCurrent: () {
        if (!scope.isCurrent) return false;
        if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          generation,
        )) {
          return false;
        }
        final context = mainShellKey.currentContext;
        return context != null &&
            context.mounted &&
            !_widgetAccountUnavailable(context.read<AuthProvider>());
      },
    );
    if (!scope.isCurrent) {
      await HomeWidgetService.acknowledgeLaunch(uri);
      return;
    }
    if (_appAccessBlocked) {
      // Keep the received envelope and its account/order binding. A validated
      // fallback URI must not replace the original native receipt while locked.
      _queuePendingWidgetUri(
        uri,
        'locked during hydration',
        navigationRequest,
        origin: origin,
      );
      return;
    }
    if (result.stale) {
      _showWidgetActionFeedbackFromShell(
        const WidgetActionMessage(WidgetActionNotice.staleContent),
        isCurrentAction: () => scope.isCurrent,
      );
    }
    if (result.uri != null) {
      _handleWidgetUri(
        result.uri,
        pomodoro,
        dataReady: true,
        navigationRequest: navigationRequest,
        receivedUri: uri,
        origin: origin,
      );
    }
    // A rejected or section-only fallback consumes the original delivery too.
    if (result.uri == null) {
      await HomeWidgetService.acknowledgeLaunch(uri);
    }
  } catch (e, st) {
    debugPrint('[WidgetAction] data preparation failed: $e\n$st');
    if (_appAccessBlocked && scope.isCurrent) {
      _queuePendingWidgetUri(
        uri,
        'locked during hydration',
        navigationRequest,
        origin: origin,
      );
      return;
    }
    _showWidgetActionFeedbackFromShell(
      const WidgetActionMessage(WidgetActionNotice.hydrationFailed),
      isCurrentAction: () => scope.isCurrent,
    );
    await HomeWidgetService.acknowledgeLaunch(uri);
  }
}

Future<void> _refreshWidgetsFromAction(
  BuildContext context, {
  bool showFeedback = true,
  WidgetLaunchAccess? access,
}) async {
  final generation = AccountLocalDataCleaner.accountDataGeneration;
  final scope = WidgetActionScope(
    isCallerAvailable: () =>
        context.mounted &&
        !_widgetAccountUnavailable(context.read<AuthProvider>()),
  );
  try {
    await _ensureHomeWidgetDataReady?.call();
    if (!context.mounted ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation) ||
        _widgetAccountUnavailable(context.read<AuthProvider>())) {
      return;
    }
    final ok = await HomeWidgetService.refreshDashboardData();
    if (showFeedback) {
      _showWidgetActionFeedbackFromShell(
        ok
            ? const WidgetActionMessage(WidgetActionNotice.refreshSucceeded)
            : const WidgetActionMessage(WidgetActionNotice.refreshFailed),
        isCurrentAction: () =>
            scope.isCurrent &&
            (access?.canDeliverFeedback ?? !_appAccessBlocked),
      );
    }
  } catch (e, st) {
    debugPrint('[WidgetAction] refresh failed: $e\n$st');
    if (showFeedback) {
      _showWidgetActionFeedbackFromShell(
        const WidgetActionMessage(WidgetActionNotice.refreshFailed),
        isCurrentAction: () =>
            scope.isCurrent &&
            (access?.canDeliverFeedback ?? !_appAccessBlocked),
      );
    }
  }
}

Future<void> _checkInHabitFromWidgetAction(
  HabitProvider habits,
  Habit target,
  WidgetLaunchAccess access,
) async {
  if (!access.canProceed) return;
  access.markActionStarted();
  final generation = AccountLocalDataCleaner.accountDataGeneration;
  final today = DateTime.now();
  final id = target.id;
  final before = target.countForDate(today);
  try {
    await habits.incrementHabit(id);
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
      return;
    }
    final latest = habits.habits
        .where((habit) => habit.id == target.id)
        .firstOrNull;
    _showWidgetActionFeedbackFromShell(
      latest != null && latest.countForDate(today) > before
          ? WidgetActionMessage(
              WidgetActionNotice.habitCheckedIn,
              subject: latest.name,
            )
          : const WidgetActionMessage(WidgetActionNotice.habitSaving),
      isCurrentAction: () => access.canDeliverFeedback,
    );
    final context = mainShellKey.currentContext;
    if (context != null && context.mounted) {
      unawaited(_refreshWidgetsFromAction(context, showFeedback: false));
    }
  } catch (e, st) {
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
      return;
    }
    debugPrint('[WidgetAction] habit check-in failed: $e\n$st');
    _showWidgetActionFeedbackFromShell(
      const WidgetActionMessage(WidgetActionNotice.habitCheckInFailed),
      isCurrentAction: () => access.canDeliverFeedback,
    );
  }
}

Future<void> _completeTodoFromWidgetAction(
  BuildContext context,
  TodoProvider todos,
  TodoItem target,
  WidgetLaunchAccess access,
) async {
  if (!access.canProceed) return;
  access.markActionStarted();
  final generation = AccountLocalDataCleaner.accountDataGeneration;
  final title = target.title;
  try {
    final changed = await todos.completeTodos([target.id]);
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
      return;
    }
    if (!context.mounted && mainShellKey.currentContext == null) return;
    if (changed > 0) {
      _showWidgetActionFeedbackFromShell(
        WidgetActionMessage(WidgetActionNotice.todoCompleted, subject: title),
        isCurrentAction: () => access.canDeliverFeedback,
      );
      final latestContext = mainShellKey.currentContext;
      if (latestContext != null && latestContext.mounted) {
        unawaited(
          _refreshWidgetsFromAction(latestContext, showFeedback: false),
        );
      }
      return;
    }
    final latest = todos.todos
        .where((todo) => todo.id == target.id)
        .firstOrNull;
    _showWidgetActionFeedbackFromShell(
      latest?.isCompleted == true
          ? WidgetActionMessage(
              WidgetActionNotice.todoAlreadyCompleted,
              subject: title,
            )
          : const WidgetActionMessage(WidgetActionNotice.todoSaving),
      isCurrentAction: () => access.canDeliverFeedback,
    );
  } catch (e, st) {
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
      return;
    }
    debugPrint('[WidgetAction] complete todo failed: $e\n$st');
    _showWidgetActionFeedbackFromShell(
      const WidgetActionMessage(WidgetActionNotice.todoCompletionFailed),
      isCurrentAction: () => access.canDeliverFeedback,
    );
  }
}

bool _todoNeedsReminderSync(TodoItem todo) {
  try {
    return preflightTodoReminderPlan(todo).hasEnabledPlan;
  } catch (_) {
    return todo.hasReminder ||
        todo.reminder.enabled ||
        todo.reminderPlan.enabled;
  }
}

Future<bool> _preflightWidgetTodoReminder(
  BuildContext context,
  TodoItem todo, {
  required void Function(WidgetActionMessage message) feedback,
  String? issueTitle,
  bool Function()? isAccessAvailable,
}) async {
  final accountScope = WidgetActionScope();
  bool canContinue() =>
      context.mounted &&
      accountScope.isCurrent &&
      (isAccessAvailable?.call() ?? !_appAccessBlocked);
  if (!canContinue()) return false;
  late final TodoReminderPreflightResult preflight;
  try {
    preflight = preflightTodoReminderPlan(todo);
  } catch (e, st) {
    debugPrint('[QuickTodoAction] reminder preflight failed: $e\n$st');
    feedback(
      WidgetActionMessage(
        WidgetActionNotice.reminderConfigurationInvalid,
        issueTitle: issueTitle,
      ),
    );
    return false;
  }
  if (!preflight.hasEnabledPlan) return true;

  final blocking = preflight.blockingIssue;
  if (blocking != null) {
    feedback(
      WidgetActionMessage(
        WidgetActionNotice.reminderIssue,
        subject: blocking.title,
        detail: blocking.message,
        preflightCopy: blocking.copy,
      ),
    );
    return false;
  }

  final usesPush = preflight.kinds.contains(ReminderKind.push);
  final usesPopup = preflight.kinds.contains(ReminderKind.popup);
  final usesAlarm = preflight.kinds.contains(ReminderKind.alarm);
  if (!usesPush && !usesPopup && !usesAlarm) return true;
  final latestContext = mainShellKey.currentContext ?? context;
  if (!latestContext.mounted) return false;
  NotificationService? notification;
  try {
    notification = Provider.of<NotificationService?>(
      latestContext,
      listen: false,
    );
  } catch (e, st) {
    debugPrint('[QuickTodoAction] notification provider unavailable: $e\n$st');
  }
  if (notification != null && (usesPush || usesPopup)) {
    final ready = await notification
        .ensureReadyForReminder(
          scheduledTime: preflight.firstScheduledTime,
          issueTitle:
              issueTitle ??
              (I18n.current == AppLocale.zh
                  ? '待办提醒注册失败'
                  : 'Task reminder not registered'),
          issueTitleCode: issueTitle == null
              ? NotificationIssueTitle.taskRegistrationFailed
              : null,
          relatedId: todo.id,
        )
        .catchError((Object e, StackTrace st) {
          debugPrint(
            '[QuickTodoAction] notification preflight failed: $e\n$st',
          );
          return false;
        });
    if (!canContinue()) return false;
    if (ready) return true;
    final issue = notification.lastScheduleIssue;
    feedback(
      issue == null
          ? WidgetActionMessage(
              WidgetActionNotice.reminderNotRegistered,
              issueTitle: issueTitle,
            )
          : WidgetActionMessage(
              WidgetActionNotice.reminderIssue,
              subject: issue.title,
              detail: issue.message,
              issueCopy: issue.copy,
            ),
    );
    return false;
  }
  if (usesAlarm) {
    final granted = await LocalNotifications.instance
        .ensurePermission()
        .catchError((Object e, StackTrace st) {
          debugPrint(
            '[QuickTodoAction] alarm permission preflight failed: $e\n$st',
          );
          return false;
        });
    if (!canContinue()) return false;
    if (!granted) {
      feedback(
        WidgetActionMessage(
          WidgetActionNotice.alarmPermissionDenied,
          issueTitle: issueTitle,
        ),
      );
      return false;
    }
    // 与待办详情保存保持一致：主动申请精准闹钟 / 全屏 intent 权限，
    // 否则首条闹钟提醒会静默降级，必须先点一次“测试强提醒”才会被授权。
    try {
      final hasExact = await AlarmService.instance.hasExactAlarmPermission();
      if (!canContinue()) return false;
      if (!hasExact) await AlarmService.instance.requestExactAlarmPermission();
      if (!canContinue()) return false;
      final hasFullScreen = await AlarmService.instance
          .hasFullScreenIntentPermission();
      if (!canContinue()) return false;
      if (!hasFullScreen) {
        await AlarmService.instance.requestFullScreenIntentPermission();
      }
      if (!canContinue()) return false;
    } catch (e, st) {
      debugPrint(
        '[QuickTodoAction] alarm exact/fullscreen request failed: $e\n$st',
      );
    }
    return true;
  }
  return true;
}

WidgetActionMessage _quickTodoCreatedNotice(TodoItem todo) {
  var reminderHint = WidgetActionReminderHint.none;
  try {
    if (preflightTodoReminderPlan(todo).hasEnabledPlan) {
      reminderHint = WidgetActionReminderHint.settings;
    }
  } catch (e, st) {
    debugPrint('[QuickTodoAction] created message preflight failed: $e\n$st');
    reminderHint = WidgetActionReminderHint.details;
  }
  var syncState = WidgetActionSyncState.unknown;
  var syncReason = '';
  CloudSyncNotice? syncNotice;
  final context = mainShellKey.currentContext;
  if (context != null && context.mounted) {
    try {
      final sync = context.read<CloudSyncProvider>();
      final status = WidgetActionSyncStatus.fromFacts(
        enabled: sync.isCloudSyncV2Enabled,
        accountTransition: sync.isSyncSuspended,
        authenticated: sync.hasAuthenticatedClient,
        serverDisabled: sync.isBackupDisabledByServer,
        autoSync: sync.config.autoSync,
        retryPending: sync.hasSyncRetryPending,
        pendingChanges: sync.hasPendingChanges,
        retryReason: sync.syncRetryStatus,
        lastError: sync.lastError,
        retryNotice: sync.syncRetryNotice,
        errorNotice: sync.lastErrorNotice,
      );
      syncState = status.state;
      syncNotice = status.notice;
      syncReason = status.notice == null ? status.reason : '';
    } catch (e, st) {
      debugPrint('[CloudSyncStatus] local save message unavailable: $e\n$st');
    }
  }
  return WidgetActionMessage(
    WidgetActionNotice.todoSaved,
    syncState: syncState,
    syncReason: syncReason,
    syncNotice: syncNotice,
    reminderHint: reminderHint,
  );
}

Future<bool> _syncNotificationQuickAdd(
  PreferencesProvider prefs, {
  required TodoProvider todos,
  required HabitProvider habits,
  required GoalProvider goals,
  bool requestIfNeeded = false,
  bool force = false,
}) async {
  final todayProgress = prefs.notificationTodayProgress;
  final progress = todayProgress
      ? _todayTaskProgressNotificationBody(
          todos.todos,
          habits: habits,
          goals: goals,
        )
      : '';
  final plan = buildNotificationStatusBarPlan(
    notificationQuickAdd: prefs.notificationQuickAdd,
    notificationTodayProgress: todayProgress,
    todayProgressBody: progress,
  );
  if (plan.shouldShow) {
    try {
      await LocalNotifications.instance.showQuickAddOngoing(
        title: plan.title,
        body: plan.body,
        enableQuickActions: plan.enableQuickActions,
        requestIfNeeded: requestIfNeeded,
        force: force,
      );
      return true;
    } on NotificationPermissionDeniedException catch (e) {
      debugPrint('[NotificationStatusBar] notification permission denied: $e');
      return false;
    } catch (e, st) {
      debugPrint('[NotificationStatusBar] show failed: $e\n$st');
      return false;
    }
  } else {
    try {
      await LocalNotifications.instance.cancelQuickAddOngoing();
      return true;
    } catch (e, st) {
      debugPrint('[NotificationStatusBar] cancel failed: $e\n$st');
      return false;
    }
  }
}

Duration _durationUntilNextLocalDay() {
  final now = DateTime.now();
  final nextDay = DateTime(now.year, now.month, now.day + 1, 0, 0, 2);
  final delay = nextDay.difference(now);
  return delay.isNegative ? const Duration(seconds: 2) : delay;
}

String _todayTaskProgressNotificationBody(
  List<TodoItem> todos, {
  required HabitProvider habits,
  required GoalProvider goals,
}) {
  final now = DateTime.now();
  final visibleTodos = todos
      .where((todo) => CompletionVisibilityPolicy.shouldShowInToday(todo, now))
      .toList(growable: false);
  final todoCount = visibleTodos.length;
  final dailyCount = habits.habits
      .where(
        (habit) => habit.activeForDate(now) && !habit.isCompletedForDate(now),
      )
      .length;
  final goalCount = goals.activeGoals.length;
  final remaining = dailyCount + todoCount + goalCount;
  return formatNotificationTodayProgressBody(
    remaining: remaining,
    dailyCount: dailyCount,
    todoCount: todoCount,
    goalCount: goalCount,
  );
}

/// Owns exactly one widget form across access overlays and account changes.
Future<T?> _showWidgetActionDialog<T>(
  BuildContext context,
  WidgetLaunchAccess access,
  Widget Function(BuildContext, bool Function()) builder,
) async {
  if (!context.mounted || !access.canProceed) return null;
  final navigator = Navigator.of(context);
  ModalRoute<T>? ownedRoute;
  final accountChanges =
      AccountLocalDataCleaner.accountDataGenerationListenable;
  void discardStaleDialog() {
    final route = ownedRoute;
    if (!access.request.isCurrentAccount &&
        navigator.mounted &&
        route?.isActive == true) {
      navigator.removeRoute(route!);
    }
  }

  access.markInteractionPresented();
  accountChanges.addListener(discardStaleDialog);
  try {
    return await showDialog<T>(
      context: context,
      builder: (dialogContext) {
        ownedRoute = ModalRoute.of<T>(dialogContext);
        bool canSubmit() =>
            dialogContext.mounted &&
            ownedRoute?.isCurrent == true &&
            access.canProceed;
        return builder(dialogContext, canSubmit);
      },
    );
  } finally {
    accountChanges.removeListener(discardStaleDialog);
  }
}

Future<void> _showQuickTodoDialog(
  BuildContext context,
  WidgetLaunchAccess access,
) async {
  await _showWidgetActionDialog<bool>(
    context,
    access,
    (_, canSubmit) => WidgetQuickTodoDialog(
      canSubmit: canSubmit,
      onSubmit: (text) async {
        if (!canSubmit()) return false;
        final draft = SmartTodoDraftBuilder.fromText(text);
        return _createQuickTodoFromAction(
          context,
          draft.toTodo(),
          access: access,
          isInteractionAvailable: canSubmit,
        );
      },
    ),
  );
}

Future<void> _showSharedTextImportSheet(SharedTextImportRequest request) async {
  final context = mainShellKey.currentContext;
  if (!request.canProceed || context == null || !context.mounted) {
    request.defer();
    return;
  }
  // Bind providers before the modal and all permission waits.
  final auth = context.read<AuthProvider>();
  final todos = context.read<TodoProvider>();
  final notes = context.read<NoteProvider>();
  final navigator = Navigator.of(context);
  final originRoute =
      context
          .findAncestorStateOfType<_DuoyiAppState>()
          ?._accessRoutes
          .currentRoute ??
      ModalRoute.of(context);
  ModalRoute<SharedTextImportChoice>? sheetRoute;
  bool isAvailable() =>
      context.mounted && request.canProceed && !_widgetAccountUnavailable(auth);
  void discardOldAccountSheet() {
    final route = sheetRoute;
    if (!request.isCurrentAccount &&
        navigator.mounted &&
        route?.isActive == true) {
      navigator.removeRoute(route!);
    }
  }

  final accountChanges =
      AccountLocalDataCleaner.accountDataGenerationListenable;
  accountChanges.addListener(discardOldAccountSheet);
  SharedTextImportChoice? action;
  try {
    action = await showAppModalSheet<SharedTextImportChoice>(
      context: context,
      builder: (sheetContext) {
        sheetRoute ??= ModalRoute.of<SharedTextImportChoice>(sheetContext);
        if (!request.isCurrentAccount) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => discardOldAccountSheet(),
          );
        }
        return SharedTextImportSheet(
          text: request.text,
          canChoose: isAvailable,
        );
      },
    );
  } finally {
    accountChanges.removeListener(discardOldAccountSheet);
  }
  if (action == null || !request.isCurrentAccount) return;
  if (!isAvailable()) {
    request.defer();
    return;
  }

  bool canDeliver() =>
      context.mounted &&
      request.canDeliverFeedback &&
      !_widgetAccountUnavailable(auth) &&
      (originRoute?.isCurrent ?? true);
  void feedback(WidgetActionMessage message, {bool allowRetry = false}) {
    if (!context.mounted || !canDeliver()) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: ValueListenableBuilder(
            valueListenable: I18n.localeListenable,
            builder: (_, locale, _) => Row(
              children: [
                Expanded(child: Text(message.render(locale: locale))),
                if (allowRetry)
                  TextButton(
                    onPressed: () {
                      if (!canDeliver() || !request.retry()) return;
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      unawaited(_sharedTextImports.drain());
                    },
                    child: Text(locale == AppLocale.en ? 'Retry' : '重试'),
                  ),
              ],
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  try {
    if (action == SharedTextImportChoice.todo) {
      final todo = SmartTodoDraftBuilder.fromText(request.text).toTodo();
      if (!context.mounted) return;
      final ready = await _preflightWidgetTodoReminder(
        context,
        todo,
        feedback: feedback,
        isAccessAvailable: isAvailable,
      );
      if (!isAvailable()) {
        request.defer();
        return;
      }
      if (!ready) return;
      request.markActionStarted();
      final waitForReminderSync = _todoNeedsReminderSync(todo);
      final result = await todos.addTodoWithResult(
        todo,
        waitForReminderSync: waitForReminderSync,
      );
      if (!context.mounted || !canDeliver()) return;
      mainShellKey.currentState?.navigateTo(1, allowHidden: true);
      feedback(
        result?.issue == null
            ? _quickTodoCreatedNotice(todo)
            : WidgetActionMessage(
                WidgetActionNotice.savedReminderIssue,
                detail: result!.issue!,
                syncIssueCopy: result.issueCopy,
              ),
      );
    } else {
      final now = DateTime.now();
      request.markActionStarted();
      await notes.addOrUpdateNotePersisted(
        NoteItem(
          id: request.noteId,
          content: request.text,
          createdAt: now,
          updatedAt: now,
        ),
      );
      if (!context.mounted || !canDeliver()) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => const BrandRouteSurface(child: NoteScreen()),
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder(
            valueListenable: I18n.localeListenable,
            builder: (_, locale, _) =>
                Text(locale == AppLocale.zh ? '已保存笔记' : 'Note saved'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  } catch (error, stack) {
    debugPrint('[SharedTextImport] create failed: $error\n$stack');
    feedback(
      const WidgetActionMessage(WidgetActionNotice.sharedImportFailed),
      allowRetry: action == SharedTextImportChoice.note,
    );
  }
}

Future<void> _showTodoCompletePrompt(
  BuildContext context,
  String todoId,
  WidgetLaunchAccess access,
) async {
  if (!context.mounted || !access.canProceed) return;
  final todos = context.read<TodoProvider>();
  final todo = todos.todos.where((t) => t.id == todoId).firstOrNull;
  if (todo == null || todo.isCompleted) {
    _showWidgetActionFeedbackFromShell(
      todo == null
          ? const WidgetActionMessage(WidgetActionNotice.todoMissing)
          : WidgetActionMessage(
              WidgetActionNotice.todoAlreadyCompleted,
              subject: todo.title,
            ),
      isCurrentAction: () => access.canDeliverFeedback,
    );
    return;
  }
  access.markInteractionPresented();
  await completeTodoWithOptionalTimeRecord(
    context,
    todo,
    isAccessAvailable: () => access.canProceed,
    isFeedbackAvailable: () => access.canDeliverFeedback,
    onActionStarted: access.markActionStarted,
  );
}

Future<void> _showHabitCheckInPrompt(
  BuildContext context,
  String habitId,
  WidgetLaunchAccess access,
) async {
  if (!context.mounted || !access.canProceed) return;
  final habits = context.read<HabitProvider>();
  final habit = habits.habits.where((h) => h.id == habitId).firstOrNull;
  WidgetActionMessage? unavailable(Habit? item) {
    if (item == null) {
      return const WidgetActionMessage(WidgetActionNotice.habitMissing);
    }
    if (item.kind != HabitKind.positive) {
      return const WidgetActionMessage(WidgetActionNotice.habitUnsupported);
    }
    if (!item.isActiveToday()) {
      return WidgetActionMessage(
        WidgetActionNotice.habitNotScheduled,
        subject: item.name,
      );
    }
    if (item.isCompletedToday()) {
      return WidgetActionMessage(
        WidgetActionNotice.habitAlreadyCompleted,
        subject: item.name,
      );
    }
    return null;
  }

  void feedback(WidgetActionMessage message) =>
      _showWidgetActionFeedbackFromShell(
        message,
        isCurrentAction: () => access.canDeliverFeedback,
      );
  final issue = unavailable(habit);
  if (issue != null) {
    feedback(issue);
    return;
  }
  final confirmed = await _showWidgetActionDialog<bool>(
    context,
    access,
    (_, canSubmit) =>
        WidgetHabitCheckInDialog(habit: habit!, canSubmit: canSubmit),
  );
  if (confirmed != true || !context.mounted || !access.canProceed) return;
  final current = habits.habits.where((h) => h.id == habitId).firstOrNull;
  final currentIssue = unavailable(current);
  if (currentIssue != null) {
    feedback(currentIssue);
    return;
  }
  await _checkInHabitFromWidgetAction(habits, current!, access);
}

class DuoyiApp extends StatefulWidget {
  const DuoyiApp({
    super.key,
    this.autoArchiveCoordinator,
    this.criticalStorageStartup,
    this.retryCriticalStorage,
  });
  final AutoArchiveCoordinator? autoArchiveCoordinator;
  final RequiredStorageStartup? criticalStorageStartup;
  final Future<void> Function()? retryCriticalStorage;

  @override
  State<DuoyiApp> createState() => _DuoyiAppState();
}

class _DuoyiAppState extends State<DuoyiApp> with WidgetsBindingObserver {
  final _defaultArchiveCoordinator = AutoArchiveCoordinator();
  AutoArchiveCoordinator? _autoArchiveCoordinator;
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _accessRoutes = AppAccessRouteGate();
  AppLockProvider? _appLockProvider;
  AuthProvider? _authProvider;
  bool _shareDrainScheduled = false;
  bool _hasOpenedHome = false;
  bool _criticalStorageAdmitted = false;

  /// 缓存上一次已知的"本地日"，用于在 resumed 时判定是否跨天。
  /// 初始值写入于 [initState]。
  DateTime? _lastLifecycleDay;

  /// 缓存上一次已知的系统 IANA 时区名。
  ///
  /// 在 [initState] 初始化为 `LocalTimezoneResolver.currentIana`；
  /// 之后每次 `AppLifecycleState.resumed` 都会先刷新时区再与此值比较，
  /// 差异即排队重放提醒（Requirements 8.6 / 8.8）。
  String? _lastIana;
  bool? _lastExactAlarmGranted;
  FocusRoomProvider? _focusRoomProvider;
  AppUpdateService? _appUpdateService;
  DateTime? _lastUpdatePolicyCheckAt;
  DateTime? _lastAccountProfileRefreshAt;
  Timer? _updatePolicyCheckTimer;

  @override
  void initState() {
    super.initState();
    _criticalStorageAdmitted = widget.criticalStorageStartup?.ready ?? true;
    widget.criticalStorageStartup?.addListener(_criticalStorageChanged);
    WidgetsBinding.instance.addObserver(this);
    WebLifecycleRecovery.install();
    final now = DateTime.now();
    _lastLifecycleDay = DateTime(now.year, now.month, now.day);
    _lastIana = LocalTimezoneResolver.currentIana;
    _lastExactAlarmGranted = _initialExactAlarmGranted;
    _lastUpdatePolicyCheckAt = null;
    _lastAccountProfileRefreshAt = now;
  }

  @override
  void dispose() {
    widget.criticalStorageStartup?.removeListener(_criticalStorageChanged);
    _autoArchiveCoordinator?.dispose();
    _defaultArchiveCoordinator.dispose();
    _appLockProvider?.removeListener(_syncRootAccess);
    _authProvider?.removeListener(_scheduleSharedImportDrain);
    _appUpdateService?.removeListener(_syncRootAccess);
    _accessRoutes.dispose();
    _appAccessBlocked = false;
    _focusRoomProvider?.stopRealtimeRankings();
    _updatePolicyCheckTimer?.cancel();
    WebLifecycleRecovery.uninstall();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DuoyiApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.criticalStorageStartup,
      widget.criticalStorageStartup,
    )) {
      oldWidget.criticalStorageStartup?.removeListener(_criticalStorageChanged);
      widget.criticalStorageStartup?.addListener(_criticalStorageChanged);
      _criticalStorageAdmitted = widget.criticalStorageStartup?.ready ?? true;
      _syncRootAccess();
    }
  }

  void _criticalStorageChanged() {
    if (!mounted) return;
    // This is initial startup admission. After hydration, the existing account
    // transition and app-lock gates own access without replacing open drafts.
    _criticalStorageAdmitted |= widget.criticalStorageStartup?.ready ?? true;
    _syncRootAccess();
    setState(() {});
  }

  void _retryCriticalStorage() {
    final retry = widget.retryCriticalStorage;
    if (retry == null || widget.criticalStorageStartup?.busy == true) return;
    unawaited(_startupGuard('retry critical local storage', retry));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _focusRoomProvider = context.read<FocusRoomProvider>();
    final lock = context.read<AppLockProvider>();
    if (_appLockProvider != lock) {
      _appLockProvider?.removeListener(_syncRootAccess);
      _appLockProvider = lock;
      lock.addListener(_syncRootAccess);
    }
    final updater = context.read<AppUpdateService>();
    if (_appUpdateService != updater) {
      _appUpdateService?.removeListener(_syncRootAccess);
      _appUpdateService = updater;
      updater.addListener(_syncRootAccess);
    }
    final auth = context.read<AuthProvider>();
    if (_authProvider != auth) {
      _authProvider?.removeListener(_scheduleSharedImportDrain);
      _authProvider = auth;
      auth.addListener(_scheduleSharedImportDrain);
    }
    _syncRootAccess();
  }

  void _scheduleSharedImportDrain() {
    if (!mounted || _shareDrainScheduled) return;
    _shareDrainScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shareDrainScheduled = false;
      if (mounted && !_appAccessBlocked) unawaited(_sharedTextImports.drain());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _syncRootAccess() {
    final blocked =
        !_criticalStorageAdmitted ||
        (_appLockProvider?.isLocked ?? false) ||
        (_appUpdateService?.mustUpdate ?? false);
    final wasBlocked = _accessRoutes.isBlocked;
    _appAccessBlocked = blocked;
    _accessRoutes.setBlocked(blocked);
    if (wasBlocked && !blocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _appAccessBlocked) return;
        _drainPendingWidgetUris(context.read<PomodoroProvider>());
        unawaited(_sharedTextImports.drain());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_criticalStorageAdmitted) return;
    final lock = context.read<AppLockProvider>();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      lock.onAppLifecycleInactive();
      HomeWidgetService.setAppInBackground(true);
    } else if (state == AppLifecycleState.resumed) {
      WebLifecycleRecovery.onAppResumed();
      HomeWidgetService.setAppInBackground(false);
      lock.onAppLifecycleResume();
      _checkUpdatePolicy(force: true);
      _refreshAccountProfileOnResume();
      // 先处理时区变更（可能影响调度），再做跨日 rollover。
      _maybeResyncOnTimezoneChange();
      _maybeRunDailyRolloverOnResume();
      _refreshNotificationProgressOnResume();
      _refreshNotificationPermissionsOnResume();
      unawaited(_refreshWidgetsOnResume(context));
    }
  }

  Future<void> _refreshWidgetsOnResume(BuildContext context) async {
    final pomodoro = context.read<PomodoroProvider>();
    final drained = await _drainPendingWidgetBgActions(pomodoro);
    if (drained || !context.mounted) return;
    await _refreshWidgetsFromAction(context, showFeedback: false);
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
    final now = DateTime.now();
    final previous = _lastAccountProfileRefreshAt;
    if (previous != null &&
        now.difference(previous) < const Duration(minutes: 10)) {
      return;
    }
    _lastAccountProfileRefreshAt = now;

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
    if (!force && _updatePolicyCheckTimer?.isActive == true) return;
    // 首帧之后尽快刷新强更策略；同一轮生命周期只保留一个待执行任务。
    _updatePolicyCheckTimer?.cancel();
    _updatePolicyCheckTimer = Timer(
      force ? Duration.zero : const Duration(seconds: 2),
      () {
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
        updater.checkServerPolicyNow();
      },
    );
  }

  /// 检测系统时区在后台是否被修改；若有变化则刷新 `tz.local` 并排队
  /// 重放提醒，保证壁钟时间不变。
  ///
  /// 对应 Requirements 8.6 / 8.8：
  /// - 8.6：resumed 且 IANA 变化时重新 `tz.setLocalLocation` 并 resync；
  /// - 8.8：resync 后新调度的 `(hour, minute)` 仍等于用户原设定。
  void _maybeResyncOnTimezoneChange() {
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
      if (mounted) _autoArchiveCoordinator?.onResume();
      try {
        await _queueFullReminderResyncCallback?.call(
          delay: Duration.zero,
          reason: 'system timezone changed',
        );
      } catch (e, st) {
        debugPrint(
          '[DuoyiApp] reminder resync on timezone change failed: $e\n$st',
        );
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
        await _queueFullReminderResyncCallback?.call(
          delay: Duration.zero,
          reason: 'notification permission changed',
        );
      } catch (e, st) {
        debugPrint('[DuoyiApp] refresh permission/resync failed: $e\n$st');
      }
    });
  }

  /// Archives may need a same-day retry; digest replay still follows day changes.
  void _maybeRunDailyRolloverOnResume() {
    _autoArchiveCoordinator?.onResume();
    if (context.read<AuthProvider>().isLocalAccountDataBlocked) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last = _lastLifecycleDay;
    _lastLifecycleDay = today;
    if (last != null && last.isAtSameMomentAs(today)) {
      return;
    }
    _refreshHomeWidgetsOnRolloverCallback?.call();

    // 同步读取 TodoProvider / GoalProvider，避免在异步 gap 之后再使用 BuildContext。
    // `DuoyiApp` 是应用根 widget，`mainShellKey` 在冷启动初期可能尚未 attach，
    // 两处都位于 MultiProvider 之下，任一命中即可拿到实例。
    final ctx = mainShellKey.currentContext ?? context;
    final provider = Provider.of<TodoProvider>(ctx, listen: false);
    final habitProv = Provider.of<HabitProvider>(ctx, listen: false);
    final pomodoroProv = Provider.of<PomodoroProvider>(ctx, listen: false);
    final timeAuditProv = Provider.of<TimeAuditProvider>(ctx, listen: false);
    final prefs = Provider.of<PreferencesProvider>(ctx, listen: false);
    final notif = Provider.of<NotificationService>(ctx, listen: false);
    final generation = AccountLocalDataCleaner.accountDataGeneration;

    // 异步触发，不阻塞 lifecycle 回调。
    // ignore: discarded_futures
    Future.microtask(() async {
      await _syncDailyDigestReminder(
        prefs,
        notif,
        provider,
        submittedAccountGeneration: generation,
      );
      await _syncReportDigestReminders(
        prefs,
        notif,
        todos: provider,
        habits: habitProv,
        pomodoros: pomodoroProv,
        timeAudit: timeAuditProv,
        submittedAccountGeneration: generation,
      );
    }).catchError((Object error, StackTrace stack) {
      debugPrint('[DailyRollover] digest refresh failed: $error\n$stack');
    });
  }

  void _refreshNotificationProgressOnResume() {
    // ignore: discarded_futures
    Future.microtask(() async {
      await _syncNotificationQuickAddDedupedCallback?.call(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final archive = widget.autoArchiveCoordinator ?? _defaultArchiveCoordinator;
    if (!identical(_autoArchiveCoordinator, archive)) {
      _autoArchiveCoordinator?.dispose();
      _autoArchiveCoordinator = archive;
    }
    if (_criticalStorageAdmitted) {
      archive.bind(
        todos: context.select<TodoProvider, TodoProvider>((source) => source),
        preferences: context.select<PreferencesProvider, PreferencesProvider>(
          (source) => source,
        ),
        auth: context.select<AuthProvider, AuthProvider>((source) => source),
        goals: context.select<GoalProvider, GoalProvider>((source) => source),
      );
    }
    final brand = context.watch<ThemeProvider>().brand;
    final lock = context.watch<AppLockProvider>();
    final locale = context.watch<LocaleProvider>();
    final accountDataBlocked = context.select<AuthProvider, bool>(
      (auth) => auth.isLocalAccountDataBlocked,
    );
    final mustUpdate = context.select<AppUpdateService, bool>(
      (updater) => updater.mustUpdate,
    );
    // A cold forced update defers the app home. Later policy changes cover the
    // existing Navigator so open routes, dialogs and form drafts survive.
    if (!mustUpdate && _criticalStorageAdmitted) _hasOpenedHome = true;
    return MaterialApp(
      title: brand.strings.appTitle,
      debugShowCheckedModeBanner: false,
      locale: locale.flutterLocale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: brand.theme,
      navigatorKey: _navigatorKey,
      navigatorObservers: [_accessRoutes],
      builder: (context, child) => AppAccessLayer(
        locked: _criticalStorageAdmitted && lock.isLocked,
        mustUpdate: mustUpdate,
        routes: _accessRoutes,
        lockOverlay: const LockScreen(),
        updateOverlay: const ForceUpdateGate(),
        child: AchievementFeedbackHost(child: child!),
      ),
      home: !_criticalStorageAdmitted
          ? CriticalStorageGate(
              busy: widget.criticalStorageStartup?.busy ?? false,
              failed: widget.criticalStorageStartup?.failed ?? false,
              onRetry: _retryCriticalStorage,
            )
          : !_hasOpenedHome
          ? const SizedBox.shrink()
          : accountDataBlocked
          ? const LoginScreen()
          : MainShell(key: mainShellKey),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @visibleForTesting
  static bool? debugUseDesktopWebWorkspace;

  static bool shouldUseDesktopWebWorkspace(double width) =>
      (debugUseDesktopWebWorkspace ?? kIsWeb) && width >= 960;

  @override
  State<MainShell> createState() => MainShellState();
}

typedef _MainShellPreferencesSlice = ({
  String bottomNavOrder,
  String bottomNavVisible,
  bool quickCaptureFab,
});

class MainShellState extends State<MainShell> {
  static const _tabCount = 7;
  static const _fallbackVisibleTabs = <int>[0, 1, 2, 6];

  int _currentIndexValue = 0; // Today first
  int _navigationRevision = 0;
  final ValueNotifier<int> _widgetActivityRevision = ValueNotifier(0);
  late final DesktopWebNavController _desktopNavController =
      DesktopWebNavController(
        initialDestination: DesktopWebDestinationX.fromLegacyTabIndex(
          _currentIndexValue,
        ),
      );

  int get _currentIndex => _currentIndexValue;

  set _currentIndex(int value) {
    // Same-value navigation is still a newer intent, including ABA sequences.
    _navigationRevision++;
    if (value == _currentIndexValue) return;
    if (_currentIndexValue == 5 || value == 5) {
      _widgetActivityRevision.value++;
    }
    _currentIndexValue = value;
  }

  bool _allowHiddenCurrentIndex = false;
  bool _hasExplicitNavigation = false;
  bool _didSeedDesktopDefaultDestination = false;
  final Set<int> _builtTabs = <int>{0};

  static final GlobalKey todayKey = GlobalKey();
  static final GlobalKey todoKey = GlobalKey();
  static final GlobalKey habitKey = GlobalKey();
  static final GlobalKey calendarKey = GlobalKey();
  static final GlobalKey pomodoroKey = GlobalKey();
  static final GlobalKey widgetKey = GlobalKey();
  static final GlobalKey mineKey = GlobalKey();

  List<int> _parseNavTabs(String encoded) {
    if (encoded.isEmpty) return const <int>[];
    return encoded
        .split(',')
        .map(int.tryParse)
        .whereType<int>()
        .toList(growable: false);
  }

  List<int> _visibleBottomNavTabs(PreferencesProvider prefs) {
    return _normalizeVisibleBottomNavTabs(prefs.visibleBottomNavTabs);
  }

  List<int> _visibleBottomNavTabsForSlice(_MainShellPreferencesSlice prefs) {
    final visibleTabs = PreferencesProvider.normalizedVisibleBottomNavTabs(
      order: _parseNavTabs(prefs.bottomNavOrder),
      visible: _parseNavTabs(prefs.bottomNavVisible),
    );
    return _normalizeVisibleBottomNavTabs(visibleTabs);
  }

  List<int> _normalizeVisibleBottomNavTabs(List<int> tabs) {
    final result = tabs
        .where((tab) => tab >= 0 && tab < _tabCount)
        .toList(growable: false);
    final visible = result.length < 2 ? _fallbackVisibleTabs : result;
    return WebTarget.isDesktopWebBuild
        ? _desktopWebVisibleBottomNavTabs(visible)
        : List.unmodifiable(visible);
  }

  List<int> _desktopWebVisibleBottomNavTabs(List<int> tabs) {
    final next = <int>[];
    for (final tab in tabs) {
      if (tab == 5) continue;
      if (!next.contains(tab)) next.add(tab);
    }
    if (!next.contains(3)) {
      final mineIndex = next.indexOf(6);
      next.insert(mineIndex >= 0 ? mineIndex : next.length, 3);
    }
    while (next.length > PreferencesProvider.maxBottomNavTabs) {
      final removeAt = next.lastIndexWhere((tab) => tab != 3 && tab != 6);
      if (removeAt < 0) break;
      next.removeAt(removeAt);
    }
    return List.unmodifiable(next);
  }

  int _coerceTabIndex(int index) {
    final visibleTabs = _visibleBottomNavTabs(
      context.read<PreferencesProvider>(),
    );
    if (index >= 0 &&
        index < _tabCount &&
        (visibleTabs.isEmpty || visibleTabs.contains(index))) {
      return index;
    }
    if (visibleTabs.isNotEmpty) return visibleTabs.first;
    return index.clamp(0, _tabCount - 1);
  }

  void navigateTo(int index, {bool allowHidden = false}) {
    if (!mounted) return;
    final target = allowHidden
        ? index.clamp(0, _tabCount - 1)
        : _coerceTabIndex(index);
    setState(() {
      _currentIndex = target;
      _builtTabs.add(target);
      _allowHiddenCurrentIndex = allowHidden;
      _hasExplicitNavigation = true;
    });
    _desktopNavController.navigateTo(
      DesktopWebDestinationX.fromLegacyTabIndex(target),
    );
  }

  DesktopWebDestination _resolveDefaultDesktopDestination(
    BuildContext context,
  ) {
    final preferences = context.read<PreferencesProvider?>();
    final target = PreferencesProvider.normalizeDefaultTab(
      preferences?.defaultTab ?? _currentIndexValue,
    );
    return DesktopWebDestinationX.fromLegacyTabIndex(target);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didSeedDesktopDefaultDestination) return;
    _didSeedDesktopDefaultDestination = true;
    if (_hasExplicitNavigation) return;
    final desktopTarget = _resolveDefaultDesktopDestination(context);
    if (_desktopNavController.destination != desktopTarget) {
      _desktopNavController.navigateTo(desktopTarget);
    }
  }

  @override
  void initState() {
    super.initState();
    // 延迟一帧再读 PreferencesProvider，避免 initState 中 read 异常
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _drainPendingWidgetUris(context.read<PomodoroProvider>());
      unawaited(_sharedTextImports.drain());
      if (_hasExplicitNavigation) return;
      final preferences = context.read<PreferencesProvider>();
      final target = PreferencesProvider.normalizeDefaultTab(
        preferences.defaultTab,
      );
      setState(() {
        _currentIndex = target;
        _builtTabs.add(target);
        _allowHiddenCurrentIndex = !_visibleBottomNavTabs(
          preferences,
        ).contains(target);
      });
      final desktopTarget = DesktopWebDestinationX.fromLegacyTabIndex(target);
      if (_desktopNavController.destination != desktopTarget) {
        _desktopNavController.navigateTo(desktopTarget);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context
        .select<PreferencesProvider, _MainShellPreferencesSlice>((provider) {
          final visible = provider.bottomNavVisible.toList()..sort();
          return (
            bottomNavOrder: provider.bottomNavOrder.join(','),
            bottomNavVisible: visible.join(','),
            quickCaptureFab: provider.quickCaptureFab,
          );
        });
    // 底导航标签随主题品牌文案变化（BrandStrings.nav*）。
    final brand = context.watch<ThemeProvider>().brand.strings;
    final safeVisibleTabs = _visibleBottomNavTabsForSlice(prefs);
    var safeIndex = _currentIndex.clamp(0, _tabCount - 1);
    if (!safeVisibleTabs.contains(safeIndex) && !_allowHiddenCurrentIndex) {
      safeIndex = safeVisibleTabs.first;
    }
    _builtTabs.add(safeIndex);
    if (safeIndex != _currentIndex) {
      final revision = _navigationRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            revision == _navigationRevision &&
            !_allowHiddenCurrentIndex) {
          final visibleTabs = _visibleBottomNavTabs(
            context.read<PreferencesProvider>(),
          );
          if (visibleTabs.contains(_currentIndex)) return;
          final target = visibleTabs.first;
          setState(() {
            _currentIndex = target;
            _builtTabs.add(target);
            _allowHiddenCurrentIndex = false;
          });
        }
      });
    }
    final allDestinations = [
      NavigationDestination(
        icon: const Icon(Icons.today_outlined),
        selectedIcon: const Icon(Icons.today),
        label: brand.navToday,
      ),
      NavigationDestination(
        icon: const Icon(Icons.checklist),
        selectedIcon: const Icon(Icons.checklist_rounded),
        label: brand.navTodo,
      ),
      NavigationDestination(
        icon: const Icon(Icons.repeat),
        selectedIcon: const Icon(Icons.repeat_rounded),
        label: brand.navHabit,
      ),
      NavigationDestination(
        icon: const Icon(Icons.calendar_month_outlined),
        selectedIcon: const Icon(Icons.calendar_month),
        label: brand.navCalendar,
      ),
      NavigationDestination(
        icon: const Icon(Icons.timer_outlined),
        selectedIcon: const Icon(Icons.timer),
        label: brand.navFocus,
      ),
      NavigationDestination(
        icon: const Icon(Icons.widgets_outlined),
        selectedIcon: const Icon(Icons.widgets_rounded),
        label: brand.navWidget,
      ),
      NavigationDestination(
        icon: const Icon(Icons.person_outline),
        selectedIcon: const Icon(Icons.person),
        label: brand.navMine,
      ),
    ];
    final selectedNavIndex = safeVisibleTabs.indexOf(safeIndex);
    final showingHiddenTab =
        _allowHiddenCurrentIndex && !safeVisibleTabs.contains(safeIndex);
    final updateHasUpdate = context.select<AppUpdateService, bool>(
      (updater) => updater.hasUpdate,
    );
    final navDestinations = safeVisibleTabs
        .map((tab) {
          final destination = allDestinations[tab];
          if (tab != 6) return destination;
          return NavigationDestination(
            icon: _MainShellNotificationBadgeIcon(
              showUpdate: updateHasUpdate,
              child: const Icon(Icons.person_outline),
            ),
            selectedIcon: _MainShellNotificationBadgeIcon(
              showUpdate: updateHasUpdate,
              child: const Icon(Icons.person),
            ),
            label: brand.navMine,
          );
        })
        .toList(growable: false);

    // 宽屏外壳按运行时视口宽度分派；tab 集过滤仍按桌面 Web 构建档位处理。
    return LayoutBuilder(
      builder: (context, constraints) {
        if (MainShell.shouldUseDesktopWebWorkspace(constraints.maxWidth)) {
          return DesktopWebWorkspace(
            key: const ValueKey('desktop_web_workspace'),
            initialDestination: _desktopNavController.destination,
            controller: _desktopNavController,
          );
        }
        if (WebTarget.isWidescreenLayout(constraints.maxWidth)) {
          return _buildDesktopWebShell(
            context: context,
            quickCaptureFab: prefs.quickCaptureFab,
            safeIndex: safeIndex,
            safeVisibleTabs: safeVisibleTabs,
            selectedNavIndex: selectedNavIndex,
            showingHiddenTab: showingHiddenTab,
            destinations: navDestinations,
          );
        }
        return _buildMobileShell(
          quickCaptureFab: prefs.quickCaptureFab,
          safeIndex: safeIndex,
          safeVisibleTabs: safeVisibleTabs,
          selectedNavIndex: selectedNavIndex,
          showingHiddenTab: showingHiddenTab,
          destinations: navDestinations,
        );
      },
    );
  }

  Widget _buildMobileShell({
    required bool quickCaptureFab,
    required int safeIndex,
    required List<int> safeVisibleTabs,
    required int selectedNavIndex,
    required bool showingHiddenTab,
    required List<NavigationDestination> destinations,
  }) {
    // 底部导航"液态玻璃"：仅注册了 AppSurfaceStyle（默认主题）时启用——
    // 半透明底色由 navigationBarTheme 档位控制，模糊在此包 BackdropFilter，
    // 其余 7 套主题（navBarBlurSigma=0）保持原样，不引入模糊开销。
    final navBarBlurSigma = appSurfaceStyleOf(context)?.navBarBlurSigma ?? 0;
    final navBar = NavigationBar(
      selectedIndex: selectedNavIndex < 0 ? 0 : selectedNavIndex,
      onDestinationSelected: (i) => setState(() {
        _currentIndex = safeVisibleTabs[i];
        _builtTabs.add(_currentIndex);
        _allowHiddenCurrentIndex = false;
        _hasExplicitNavigation = true;
      }),
      destinations: destinations,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    );
    // 液态玻璃需要真实内容垫在导航条下：Scaffold 默认（extendBody=false）
    // 的 body 不延伸到 bottomNavigationBar 之下，BackdropFilter 无内容可
    // 模糊，半透明白底色只能合成在根背景上呈灰条。仅对玻璃主题开启
    // extendBody，让 BrandBackground 铺到条下；页面内容用与导航条等高的
    // 内层 Padding 避让，并把 Scaffold 因 extendBody 对 body 提升的
    // MediaQuery bottom padding/viewInsets 归零——不延伸时 Scaffold 对 body
    // 的基线本就是移除这两个 bottom 值（bottomNavigationBar 槽位
    // removeBottomPadding、resizeToAvoidBottomInset 时 removeBottomInset），
    // 归零后屏内 SafeArea/滚动尾部 padding/键盘消费者与 7 套非玻璃主题一致。
    // 隐藏页返回条（不透明）与其余 7 套主题不延伸，观感不变。
    final glassNavBarActive = navBarBlurSigma > 0 && !showingHiddenTab;
    // web 渲染器下 BackdropFilter 逐帧回读像素、开销显著高于原生：模糊
    // 降到轻量档（毛玻璃观感保留、像素回读量减半），原生保持全档。
    final navBarBlurEffectiveSigma =
        WebTarget.shouldReduceNavBarBlur &&
            navBarBlurSigma > DesignTokens.navBarWebBlurSigma
        ? DesignTokens.navBarWebBlurSigma
        : navBarBlurSigma;
    final rootMediaQuery = MediaQuery.of(context);
    // NavigationBar 结构为 Material > SafeArea > SizedBox(height)，
    // 总高 = navigationBarTheme.height + 系统底部 inset。
    final navBarTotalHeight =
        (NavigationBarTheme.of(context).height ?? 80.0) +
        rootMediaQuery.padding.bottom;
    final tabStack = IndexedStack(
      index: safeIndex,
      children: List.generate(
        _tabCount,
        (tab) => _builtTabs.contains(tab)
            ? _buildTab(tab, safeVisibleTabs, safeIndex)
            : _LazyTabPlaceholder(tab: tab),
      ),
    );
    final outlinedNavBar = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.22),
            width: 0.5,
          ),
        ),
      ),
      child: navBar,
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: glassNavBarActive,
      body: glassNavBarActive
          ? MediaQuery(
              // 对齐不延伸时的 Scaffold body 基线：两个 bottom 值归零，而非
              // 还原为系统原值。系统 inset 已由导航条内部 SafeArea 消费
              // （条高 = height + inset），也含在内层 Padding 里；若还原成
              // 系统原值，屏内 SafeArea/滚动尾部 padding 会在其上再多避让
              // 一次 inset（如批量操作条与导航条之间露出背景空条）。
              data: rootMediaQuery.copyWith(
                padding: rootMediaQuery.padding.copyWith(bottom: 0),
                viewInsets: rootMediaQuery.viewInsets.copyWith(bottom: 0),
              ),
              child: BrandBackground(
                child: Padding(
                  padding: EdgeInsets.only(bottom: navBarTotalHeight),
                  child: tabStack,
                ),
              ),
            )
          : BrandBackground(child: tabStack),
      floatingActionButton:
          safeIndex == 0 &&
              quickCaptureFab &&
              MediaQuery.sizeOf(context).width < 1200
          ? const QuickCaptureFab()
          : null,
      bottomNavigationBar: showingHiddenTab
          ? _HiddenTabReturnBar(
              onClose: () => setState(() {
                _currentIndex = safeVisibleTabs.contains(6)
                    ? 6
                    : safeVisibleTabs.first;
                _builtTabs.add(_currentIndex);
                _allowHiddenCurrentIndex = false;
                _hasExplicitNavigation = true;
              }),
            )
          : glassNavBarActive
          ? ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: navBarBlurEffectiveSigma,
                  sigmaY: navBarBlurEffectiveSigma,
                ),
                child: outlinedNavBar,
              ),
            )
          : outlinedNavBar,
    );
  }

  Widget _buildDesktopWebShell({
    required BuildContext context,
    required bool quickCaptureFab,
    required int safeIndex,
    required List<int> safeVisibleTabs,
    required int selectedNavIndex,
    required bool showingHiddenTab,
    required List<NavigationDestination> destinations,
  }) {
    final appTitle = AppLocalizations.of(context).appTitle;
    final content = IndexedStack(
      index: safeIndex,
      children: List.generate(
        _tabCount,
        (tab) => _builtTabs.contains(tab)
            ? _buildTab(tab, safeVisibleTabs, safeIndex)
            : _LazyTabPlaceholder(tab: tab),
      ),
    );
    final body = showingHiddenTab
        ? Column(
            children: [
              _HiddenTabReturnBar(
                onClose: () => setState(() {
                  _currentIndex = safeVisibleTabs.contains(6)
                      ? 6
                      : safeVisibleTabs.first;
                  _builtTabs.add(_currentIndex);
                  _allowHiddenCurrentIndex = false;
                  _hasExplicitNavigation = true;
                }),
              ),
              Expanded(child: content),
            ],
          )
        : content;

    // rail 几何一次算清（浮岛卡面四周各留 DesignTokens.spaceMd 一圈）：
    // 内容列宽 = 窗口 - rail 卡宽 - 2×spaceMd，超过 maxContentWidth 后由
    // Center 两侧留白；FAB 右距据此贴住内容列右缘。
    final windowWidth = MediaQuery.widthOf(context);
    final railExtended = windowWidth >= DesktopTokens.railExtendedBreakpoint;
    final railWidth = railExtended
        ? DesktopTokens.railExtendedWidth
        : DesktopTokens.railCompactWidth;
    final contentSpare =
        windowWidth -
        railWidth -
        DesignTokens.spaceMd * 2 -
        DesktopTokens.maxContentWidth;
    // Scaffold endFloat 已自带 16px 右缘边距（kFloatingActionButtonMargin），
    // FAB 右缘距窗右 = 16 + fabRightInset。宽屏下内容列距窗右 contentSpare/2，
    // 贴缘即 fabRightInset = contentSpare/2 - 16；留白不足（≤16）时归零，
    // 右距与移动壳一致（恰为 endFloat 的 16px）。
    final double contentRightGap = contentSpare > 0 ? contentSpare / 2 : 0.0;
    final double fabRightInset = contentRightGap > 16
        ? contentRightGap - 16
        : 0.0;

    final surfaceStyle = appSurfaceStyleOf(context);
    final railBlurSigma = WebTarget.shouldReduceNavBarBlur
        ? (surfaceStyle != null && surfaceStyle.navBarBlurSigma > 0
              ? DesignTokens.navBarWebBlurSigma
              : 0.0)
        : (surfaceStyle?.navBarBlurSigma ?? 0.0);
    final railCard = AppSurfaceCard(
      margin: railBlurSigma > 0
          ? EdgeInsets.zero
          : const EdgeInsets.all(DesignTokens.spaceMd),
      padding: EdgeInsets.zero,
      child: SafeArea(
        right: false,
        child: NavigationRail(
          selectedIndex: selectedNavIndex < 0 ? null : selectedNavIndex,
          onDestinationSelected: (i) => setState(() {
            _currentIndex = safeVisibleTabs[i];
            _builtTabs.add(_currentIndex);
            _allowHiddenCurrentIndex = false;
            _hasExplicitNavigation = true;
          }),
          extended: railExtended,
          minExtendedWidth: DesktopTokens.railExtendedWidth,
          backgroundColor: Colors.transparent,
          leading: _DesktopRailHeader(
            appTitle: appTitle,
            extended: railExtended,
          ),
          destinations: destinations
              .map(
                (destination) => NavigationRailDestination(
                  icon: Tooltip(
                    message: destination.label,
                    child: destination.icon,
                  ),
                  selectedIcon: Tooltip(
                    message: destination.label,
                    child: destination.selectedIcon,
                  ),
                  label: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
    final Widget desktopRail = railBlurSigma > 0
        ? Padding(
            padding: const EdgeInsets.all(DesignTokens.spaceMd),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                surfaceStyle?.cardRadius ?? DesignTokens.radiusCardIos,
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: railBlurSigma,
                  sigmaY: railBlurSigma,
                ),
                child: railCard,
              ),
            ),
          )
        : railCard;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BrandBackground(
        child: Row(
          children: [
            desktopRail,
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  key: const ValueKey('desktop_web_body_max_width'),
                  constraints: const BoxConstraints(
                    maxWidth: DesktopTokens.maxContentWidth,
                  ),
                  child: SizedBox(width: double.infinity, child: body),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: safeIndex == 0 && quickCaptureFab
          ? Padding(
              padding: EdgeInsets.only(right: fabRightInset),
              child: const QuickCaptureFab(),
            )
          : null,
    );
  }

  Widget _buildTab(int tab, List<int> safeVisibleTabs, int activeIndex) {
    return switch (tab) {
      0 => TodayScreen(key: todayKey),
      1 => TodoScreen(key: todoKey),
      2 => HabitScreen(key: habitKey),
      3 => CalendarScreen(key: calendarKey, useShellBackground: true),
      4 => PomodoroScreen(key: pomodoroKey, useShellBackground: true),
      5 => WidgetScreen(
        key: widgetKey,
        isActive: tab == activeIndex,
        activityRevision: _widgetActivityRevision,
      ),
      6 => MineScreen(
        key: mineKey,
        useShellBackground: true,
        visibleBottomNavTabs: safeVisibleTabs,
      ),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  void dispose() {
    _desktopNavController.dispose();
    _widgetActivityRevision.dispose();
    super.dispose();
  }
}

class _DesktopRailHeader extends StatelessWidget {
  final String appTitle;
  final bool extended;

  const _DesktopRailHeader({required this.appTitle, required this.extended});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: cs.onSurface,
      fontSize: 15,
      fontWeight: DesignTokens.fontWeightRegular,
      letterSpacing: 0.2,
    );
    final brandMark = _DuoyiBrandMark(size: extended ? 32 : 34);

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 14, 12, extended ? 12 : 10),
      child: extended
          ? SizedBox(
              width: 172,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      brandMark,
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          appTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: cs.outlineVariant.withValues(alpha: 0.24),
                  ),
                ],
              ),
            )
          : Tooltip(message: appTitle, child: brandMark),
    );
  }
}

class _DuoyiBrandMark extends StatelessWidget {
  final double size;

  const _DuoyiBrandMark({this.size = 32});

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cachePx = (size * dpr).round().clamp(32, 384);
    return Image.asset(
      'assets/logo/duoyi_logo_192.png',
      width: size,
      height: size,
      cacheWidth: cachePx,
      cacheHeight: cachePx,
      gaplessPlayback: true,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}

class _LazyTabPlaceholder extends StatelessWidget {
  final int tab;

  const _LazyTabPlaceholder({required this.tab});

  @override
  Widget build(BuildContext context) {
    return SizedBox.shrink(key: ValueKey('lazy-tab-$tab'));
  }
}

class _HiddenTabReturnBar extends StatelessWidget {
  final VoidCallback onClose;

  const _HiddenTabReturnBar({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) => _buildLocalized(context),
    );
  }

  Widget _buildLocalized(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface.withValues(alpha: 0.96),
      elevation: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  I18n.current == AppLocale.en ? 'Hidden feature' : '隐藏应用',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onClose,
                icon: const Icon(Icons.keyboard_return_rounded, size: 18),
                label: Text(
                  I18n.current == AppLocale.en ? 'Back to Me' : '返回我的',
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  visualDensity: VisualDensity.standard,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: appSecondaryMenuItemTextStyle(context),
                ),
              ),
            ],
          ),
        ),
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
                  width: 0.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MainShellNotificationBadgeIcon extends StatelessWidget {
  final Widget child;
  final bool showUpdate;

  const _MainShellNotificationBadgeIcon({
    required this.child,
    required this.showUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnread = context.select<NotificationService, bool>(
      (service) => service.hasUnreadHistory,
    );
    return (hasUnread || showUpdate)
        ? _BottomNavBadgeIcon(child: child)
        : child;
  }
}
