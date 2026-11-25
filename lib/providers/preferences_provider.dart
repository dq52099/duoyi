import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/local_timezone_resolver.dart';
import '../core/i18n_date_format.dart';
import '../core/calendar_date_navigation.dart';
import '../core/account_preference_writes.dart';
import '../core/notification_history_policy.dart';
import '../core/report_reminder_config.dart';
import '../core/web_target.dart';
import '../services/account_local_data_cleaner.dart';
import '../models/goal.dart' show ReminderKind;

class DailyReminderSlot {
  final bool enabled;
  final ReminderKind kind;
  final int hour;
  final int minute;
  final bool includeTodayTasks;
  final bool includeTomorrowPlan;
  final bool includeOverdue;
  final List<int> repeatDays;
  final bool pauseHolidays;

  const DailyReminderSlot({
    this.enabled = false,
    this.kind = ReminderKind.push,
    this.hour = 20,
    this.minute = 0,
    this.includeTodayTasks = true,
    this.includeTomorrowPlan = true,
    this.includeOverdue = true,
    this.repeatDays = const [1, 2, 3, 4, 5, 6, 7],
    this.pauseHolidays = false,
  });

  DailyReminderSlot copyWith({
    bool? enabled,
    ReminderKind? kind,
    int? hour,
    int? minute,
    bool? includeTodayTasks,
    bool? includeTomorrowPlan,
    bool? includeOverdue,
    List<int>? repeatDays,
    bool? pauseHolidays,
  }) {
    final nextKind = normalizeKind(kind ?? this.kind);
    return DailyReminderSlot(
      enabled: nextKind == ReminderKind.off ? false : enabled ?? this.enabled,
      kind: nextKind,
      hour: (hour ?? this.hour).clamp(0, 23),
      minute: (minute ?? this.minute).clamp(0, 59),
      includeTodayTasks: includeTodayTasks ?? this.includeTodayTasks,
      includeTomorrowPlan: includeTomorrowPlan ?? this.includeTomorrowPlan,
      includeOverdue: includeOverdue ?? this.includeOverdue,
      repeatDays: _normalizeDays(repeatDays ?? this.repeatDays),
      pauseHolidays: pauseHolidays ?? this.pauseHolidays,
    );
  }

  static List<int> _normalizeDays(List<int> days) {
    final normalized = days.where((d) => d >= 1 && d <= 7).toSet().toList()
      ..sort();
    return normalized.isEmpty ? const [1, 2, 3, 4, 5, 6, 7] : normalized;
  }

  static ReminderKind normalizeKind(ReminderKind kind) {
    return switch (kind) {
      ReminderKind.push || ReminderKind.popup || ReminderKind.alarm => kind,
      ReminderKind.off => ReminderKind.off,
      ReminderKind.email => ReminderKind.push,
    };
  }

  static ReminderKind parseKind(String? raw) {
    if (raw == null || raw.trim().isEmpty) return ReminderKind.push;
    for (final kind in ReminderKind.values) {
      if (kind.name == raw) return normalizeKind(kind);
    }
    return ReminderKind.push;
  }
}

bool _sameDailyReminderSlot(DailyReminderSlot a, DailyReminderSlot b) {
  final left = a.copyWith();
  final right = b.copyWith();
  return left.enabled == right.enabled &&
      left.kind == right.kind &&
      left.hour == right.hour &&
      left.minute == right.minute &&
      left.includeTodayTasks == right.includeTodayTasks &&
      left.includeTomorrowPlan == right.includeTomorrowPlan &&
      left.includeOverdue == right.includeOverdue &&
      listEquals(left.repeatDays, right.repeatDays) &&
      left.pauseHolidays == right.pauseHolidays;
}

class DailyReminderScheduleSlot {
  final int index;
  final DailyReminderSlot slot;

  const DailyReminderScheduleSlot({required this.index, required this.slot});
}

/// Immutable quiet-hours policy with DST-safe local wall-clock calculation.
@immutable
class QuietHoursPolicy {
  static const int defaultStartMinutes = 22 * 60;
  static const int defaultEndMinutes = 7 * 60;

  final bool enabled;
  final int startMinutes;
  final int endMinutes;
  final bool allowAlarms;
  final bool deferUntilEnd;

  const QuietHoursPolicy({
    this.enabled = false,
    this.startMinutes = defaultStartMinutes,
    this.endMinutes = defaultEndMinutes,
    this.allowAlarms = true,
    this.deferUntilEnd = true,
  });

  static int normalizeMinutes(int minutes) => ((minutes % 1440) + 1440) % 1440;

  QuietHoursPolicy copyWith({
    bool? enabled,
    int? startMinutes,
    int? endMinutes,
    bool? allowAlarms,
    bool? deferUntilEnd,
  }) {
    return QuietHoursPolicy(
      enabled: enabled ?? this.enabled,
      startMinutes: normalizeMinutes(startMinutes ?? this.startMinutes),
      endMinutes: normalizeMinutes(endMinutes ?? this.endMinutes),
      allowAlarms: allowAlarms ?? this.allowAlarms,
      deferUntilEnd: deferUntilEnd ?? this.deferUntilEnd,
    );
  }

  int get startHour => normalizeMinutes(startMinutes) ~/ 60;
  int get startMinute => normalizeMinutes(startMinutes) % 60;
  int get endHour => normalizeMinutes(endMinutes) ~/ 60;
  int get endMinute => normalizeMinutes(endMinutes) % 60;

  bool isMinutesInQuietWindow(int minuteOfDay) {
    if (!enabled) return false;
    final start = normalizeMinutes(startMinutes);
    final end = normalizeMinutes(endMinutes);
    if (start == end) return false;
    final value = normalizeMinutes(minuteOfDay);
    if (start > end) {
      // Midnight wrap, e.g. 22:00 -> 07:00
      return value >= start || value < end;
    }
    return value >= start && value < end;
  }

  bool isWithinQuietHours(DateTime time) {
    if (!enabled) return false;
    final local = time.toLocal();
    return isMinutesInQuietWindow(local.hour * 60 + local.minute);
  }

  /// Computes the next quiet-window end in local wall clock time, handling DST safely.
  DateTime nextQuietEndLocal(DateTime time) {
    final local = time.toLocal();
    final start = normalizeMinutes(startMinutes);
    final end = normalizeMinutes(endMinutes);
    if (!enabled || start == end) return local;
    final targetHour = end ~/ 60;
    final targetMinute = end % 60;
    final currentMinutes = local.hour * 60 + local.minute;
    final crossesMidnight = start > end;
    final dayOffset = crossesMidnight && currentMinutes >= start ? 1 : 0;
    var candidate = DateTime(
      local.year,
      local.month,
      local.day + dayOffset,
      targetHour,
      targetMinute,
    );
    if (!candidate.isAfter(local)) {
      candidate = DateTime(
        local.year,
        local.month,
        local.day + dayOffset + 1,
        targetHour,
        targetMinute,
      );
    }
    return candidate;
  }

  String get digest =>
      '$enabled:${normalizeMinutes(startMinutes)}:${normalizeMinutes(endMinutes)}:$allowAlarms:$deferUntilEnd';

  @override
  bool operator ==(Object other) {
    return other is QuietHoursPolicy &&
        other.enabled == enabled &&
        normalizeMinutes(other.startMinutes) ==
            normalizeMinutes(startMinutes) &&
        normalizeMinutes(other.endMinutes) == normalizeMinutes(endMinutes) &&
        other.allowAlarms == allowAlarms &&
        other.deferUntilEnd == deferUntilEnd;
  }

  @override
  int get hashCode => Object.hash(
    enabled,
    normalizeMinutes(startMinutes),
    normalizeMinutes(endMinutes),
    allowAlarms,
    deferUntilEnd,
  );
}

List<DailyReminderScheduleSlot> effectiveDailyReminderScheduleSlots(
  List<DailyReminderSlot> slots,
) {
  final result = <DailyReminderScheduleSlot>[];
  final claimedDaysByWallClock = <String, Set<int>>{};

  for (var index = 0; index < slots.length; index++) {
    final slot = slots[index];
    final kind = DailyReminderSlot.normalizeKind(slot.kind);
    if (!slot.enabled || kind == ReminderKind.off) continue;

    final repeatDays = DailyReminderSlot._normalizeDays(slot.repeatDays);
    final wallClockKey = '${slot.hour}:${slot.minute}';
    final claimedDays = claimedDaysByWallClock.putIfAbsent(
      wallClockKey,
      () => <int>{},
    );
    final remainingDays = repeatDays
        .where((day) => !claimedDays.contains(day))
        .toList(growable: false);
    if (remainingDays.isEmpty) continue;

    claimedDays.addAll(remainingDays);
    result.add(
      DailyReminderScheduleSlot(
        index: index,
        slot: slot.copyWith(kind: kind, repeatDays: remainingDays),
      ),
    );
  }

  return result;
}

/// 用户个性化偏好(本地)。不涉及服务器配置，每个设备独立。
class PreferencesProvider extends ChangeNotifier {
  static const maxBottomNavTabs = 5;
  static const fixedBottomNavTabs = <int>{6};
  static const mobileDefaultBottomNavTabs = <int>{0, 1, 2, 5, 6};
  static const desktopWebDefaultBottomNavTabs = <int>{0, 1, 2, 3, 6};
  static Set<int> get defaultBottomNavTabs => WebTarget.isDesktopWebBuild
      ? desktopWebDefaultBottomNavTabs
      : mobileDefaultBottomNavTabs;
  static bool isBottomNavTabSupported(int tab) =>
      !(WebTarget.isDesktopWebBuild && tab == 5);
  static int normalizeDefaultTab(int tab) {
    final normalized = tab.clamp(0, 6).toInt();
    return isBottomNavTabSupported(normalized) ? normalized : 3;
  }

  static const _kFirstDayOfWeek = 'pref_first_day_of_week';
  static const _kDateFormat = 'pref_date_format';
  static const _kDefaultTab = 'pref_default_tab';
  static const _kHapticFeedback = 'pref_haptic_feedback';
  static const _kShowLunar = 'pref_show_lunar';
  static const _kShowCompletedTodos = 'pref_show_completed_todos';
  static const _kDefaultPomodoroMinutes = 'pref_default_pomodoro_minutes';
  static const _kQuickCaptureFab = 'pref_quick_capture_fab';
  static const _kNotificationQuickAdd = 'pref_notification_quick_add';
  static const _kNotificationTodayProgress = 'pref_notification_today_progress';
  static const _kNotificationHistoryLimit =
      NotificationHistoryPolicy.preferenceKey;
  static const _kAutoArchiveCompletedDays = 'pref_auto_archive_completed_days';
  static const _kDailyReminderEnabled = 'pref_daily_reminder_enabled';
  static const _kDailyReminderKind = 'pref_daily_reminder_kind';
  static const _kDailyReminderHour = 'pref_daily_reminder_hour';
  static const _kDailyReminderMinute = 'pref_daily_reminder_minute';
  static const _kDailyReminderIncludeTodayTasks =
      'pref_daily_reminder_today_tasks';
  static const _kDailyReminderIncludeTomorrowPlan =
      'pref_daily_reminder_tomorrow_plan';
  static const _kDailyReminderIncludeOverdue = 'pref_daily_reminder_overdue';
  static const _kDailyReminderRepeatDays = 'pref_daily_reminder_repeat_days';
  static const _kDailyReminderPauseHolidays =
      'pref_daily_reminder_pause_holidays';
  static const _kDailyReminderSlotPrefix = 'pref_daily_reminder_slot';
  static const _kDailyReportReminder = 'pref_daily_report_reminder';
  static const _kDailyReportReminderHour = 'pref_daily_report_reminder_hour';
  static const _kDailyReportReminderMinute =
      'pref_daily_report_reminder_minute';
  static const _kWeeklyReportReminder = 'pref_weekly_report_reminder';
  static const _kWeeklyReportReminderWeekday =
      'pref_weekly_report_reminder_weekday';
  static const _kWeeklyReportReminderHour = 'pref_weekly_report_reminder_hour';
  static const _kWeeklyReportReminderMinute =
      'pref_weekly_report_reminder_minute';
  static const _kMonthlyReportReminder = 'pref_monthly_report_reminder';
  static const _kMonthlyReportReminderDay = 'pref_monthly_report_reminder_day';
  static const _kMonthlyReportReminderHour =
      'pref_monthly_report_reminder_hour';
  static const _kMonthlyReportReminderMinute =
      'pref_monthly_report_reminder_minute';
  static const _kYearlyReportReminder = 'pref_yearly_report_reminder';
  static const _kYearlyReportReminderMonth =
      'pref_yearly_report_reminder_month';
  static const _kYearlyReportReminderDay = 'pref_yearly_report_reminder_day';
  static const _kYearlyReportReminderHour = 'pref_yearly_report_reminder_hour';
  static const _kYearlyReportReminderMinute =
      'pref_yearly_report_reminder_minute';
  static const _kBottomNavOrder = 'pref_bottom_nav_order';
  static const _kBottomNavVisible = 'pref_bottom_nav_visible';
  static const _kCalendarMenuOrder = 'pref_calendar_menu_order';
  static const _kCalendarMenuHidden = 'pref_calendar_menu_hidden';
  static const _kMineMenuOrder = 'pref_mine_menu_order';
  static const List<String> defaultCalendarMenuOrder = <String>[
    'today',
    'pick',
    'month',
    'week',
    'day',
    'three_day',
    'year',
  ];
  static const List<int> defaultMineMenuOrder = <int>[4, 5, 6, 7, 8, 9];
  static const _kAppTimeZone = LocalTimezoneResolver.preferenceKey;
  static const _kAppTimeZoneMode = LocalTimezoneResolver.modePreferenceKey;
  static const _kQuietHoursEnabled = 'pref_quiet_hours_enabled';
  static const _kQuietHoursStartMinutes = 'pref_quiet_hours_start_minutes';
  static const _kQuietHoursEndMinutes = 'pref_quiet_hours_end_minutes';
  static const _kQuietHoursAllowAlarms = 'pref_quiet_hours_allow_alarms';
  static const _kQuietHoursDeferUntilEnd = 'pref_quiet_hours_defer_until_end';

  static const Set<String> quietHoursPreferenceKeys = <String>{
    _kQuietHoursEnabled,
    _kQuietHoursStartMinutes,
    _kQuietHoursEndMinutes,
    _kQuietHoursAllowAlarms,
    _kQuietHoursDeferUntilEnd,
  };

  Future<void> Function()? onAppTimeZoneChanged;
  void Function(Iterable<String> keys)? onChangedKeys;

  int _firstDayOfWeek = 1; // 1=周一, 7=周日
  String _dateFormat = 'yyyy-MM-dd';
  int _defaultTab = 0; // 0=Today
  bool _haptic = true;
  bool _showLunar = true;
  bool _showCompletedTodos = false;
  int _defaultPomodoroMinutes = 25;
  bool _quickCaptureFab = true;
  bool _notificationQuickAdd = false;
  bool _notificationTodayProgress = false;
  int _notificationHistoryLimit = NotificationHistoryPolicy.defaultLimit;
  int _autoArchiveCompletedDays = 0; // 0=不归档
  bool _dailyReminderEnabled = false;
  ReminderKind _dailyReminderKind = ReminderKind.push;
  int _dailyReminderHour = 20;
  int _dailyReminderMinute = 0;
  bool _dailyReminderIncludeTodayTasks = true;
  bool _dailyReminderIncludeTomorrowPlan = true;
  bool _dailyReminderIncludeOverdue = true;
  List<int> _dailyReminderRepeatDays = const [1, 2, 3, 4, 5, 6, 7];
  bool _dailyReminderPauseHolidays = false;
  List<DailyReminderSlot> _dailyReminderSlots = const [
    DailyReminderSlot(),
    DailyReminderSlot(hour: 8, enabled: false),
    DailyReminderSlot(hour: 22, enabled: false),
  ];
  bool _dailyReportReminder = false;
  int _dailyReportReminderHour = 21;
  int _dailyReportReminderMinute = 30;
  bool _weeklyReportReminder = false;
  int _weeklyReportReminderWeekday = DateTime.monday;
  int _weeklyReportReminderHour = 9;
  int _weeklyReportReminderMinute = 0;
  bool _monthlyReportReminder = false;
  int _monthlyReportReminderDay = 1;
  int _monthlyReportReminderHour = 9;
  int _monthlyReportReminderMinute = 0;
  bool _yearlyReportReminder = false;
  int _yearlyReportReminderMonth = 1;
  int _yearlyReportReminderDay = 1;
  int _yearlyReportReminderHour = 9;
  int _yearlyReportReminderMinute = 0;
  List<int> _bottomNavOrder = const [0, 1, 2, 3, 4, 5, 6];
  Set<int> _bottomNavVisible = defaultBottomNavTabs;
  List<String> _calendarMenuOrder = defaultCalendarMenuOrder;
  Set<String> _calendarMenuHidden = const <String>{};
  List<int> _mineMenuOrder = defaultMineMenuOrder;
  String _appTimeZone = LocalTimezoneResolver.defaultIana;
  bool _followSystemTimeZone = true;
  bool _quietHoursEnabled = false;
  int _quietHoursStartMinutes = QuietHoursPolicy.defaultStartMinutes;
  int _quietHoursEndMinutes = QuietHoursPolicy.defaultEndMinutes;
  bool _quietHoursAllowAlarms = true;
  bool _quietHoursDeferUntilEnd = true;
  int _storageGeneration = 0;
  int _storageReadSerial = 0;
  int? _loadedAccountGeneration;
  int get storageGeneration => _storageGeneration;
  bool get isStorageLoaded =>
      _loadedAccountGeneration != null &&
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(
        _loadedAccountGeneration!,
      );
  Future<void> _preferenceWriteTail = Future<void>.value();

  Future<void> _enqueuePreferenceChange(
    Future<void> Function(AccountPreferenceTransaction transaction) change,
  ) {
    final generation = _storageGeneration;
    return AccountPreferenceWrites.run((token) {
      bool isCurrent() => generation == _storageGeneration && token.isCurrent;
      final write = _preferenceWriteTail.then((_) async {
        if (!isCurrent()) return;
        final p = await SharedPreferences.getInstance();
        if (!isCurrent()) return;
        final transaction = AccountPreferenceTransaction(p, isCurrent);
        final restoreState = _capturePreferenceState();
        try {
          await change(transaction);
        } on AccountPreferenceWriteCanceled {
          if (!transaction.isCommitted) {
            final restoreTimeZone = transaction.changedKeys.any(
              (key) => key == _kAppTimeZoneMode || key == _kAppTimeZone,
            );
            // The boundary is draining this operation before it can clear
            // storage. Restore partial writes even if preflight later aborts.
            await transaction.rollback(canceledBeforeCleanup: true);
            if (generation == _storageGeneration) {
              restoreState();
              if (restoreTimeZone) {
                await LocalTimezoneResolver.applyApplicationTimeZone(
                  _followSystemTimeZone
                      ? LocalTimezoneResolver.followSystemValue
                      : _appTimeZone,
                  isCurrent: () => generation == _storageGeneration,
                );
              }
            }
          }
          return;
        } catch (_) {
          if (!transaction.isCommitted) {
            await transaction.rollback();
            if (isCurrent()) await _readFromStorage();
          }
          rethrow;
        }
      });
      _preferenceWriteTail = write.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      return write;
    });
  }

  void Function() _capturePreferenceState() {
    final savedFirstDayOfWeek = _firstDayOfWeek;
    final savedDateFormat = _dateFormat;
    final savedDefaultTab = _defaultTab;
    final savedHaptic = _haptic;
    final savedShowLunar = _showLunar;
    final savedShowCompletedTodos = _showCompletedTodos;
    final savedDefaultPomodoroMinutes = _defaultPomodoroMinutes;
    final savedQuickCaptureFab = _quickCaptureFab;
    final savedNotificationQuickAdd = _notificationQuickAdd;
    final savedNotificationTodayProgress = _notificationTodayProgress;
    final savedNotificationHistoryLimit = _notificationHistoryLimit;
    final savedAutoArchiveCompletedDays = _autoArchiveCompletedDays;
    final savedDailyReminderEnabled = _dailyReminderEnabled;
    final savedDailyReminderKind = _dailyReminderKind;
    final savedDailyReminderHour = _dailyReminderHour;
    final savedDailyReminderMinute = _dailyReminderMinute;
    final savedDailyReminderIncludeTodayTasks = _dailyReminderIncludeTodayTasks;
    final savedDailyReminderIncludeTomorrowPlan =
        _dailyReminderIncludeTomorrowPlan;
    final savedDailyReminderIncludeOverdue = _dailyReminderIncludeOverdue;
    final savedDailyReminderRepeatDays = _dailyReminderRepeatDays;
    final savedDailyReminderPauseHolidays = _dailyReminderPauseHolidays;
    final savedDailyReminderSlots = _dailyReminderSlots;
    final savedDailyReportReminder = _dailyReportReminder;
    final savedDailyReportReminderHour = _dailyReportReminderHour;
    final savedDailyReportReminderMinute = _dailyReportReminderMinute;
    final savedWeeklyReportReminder = _weeklyReportReminder;
    final savedWeeklyReportReminderWeekday = _weeklyReportReminderWeekday;
    final savedWeeklyReportReminderHour = _weeklyReportReminderHour;
    final savedWeeklyReportReminderMinute = _weeklyReportReminderMinute;
    final savedMonthlyReportReminder = _monthlyReportReminder;
    final savedMonthlyReportReminderDay = _monthlyReportReminderDay;
    final savedMonthlyReportReminderHour = _monthlyReportReminderHour;
    final savedMonthlyReportReminderMinute = _monthlyReportReminderMinute;
    final savedYearlyReportReminder = _yearlyReportReminder;
    final savedYearlyReportReminderMonth = _yearlyReportReminderMonth;
    final savedYearlyReportReminderDay = _yearlyReportReminderDay;
    final savedYearlyReportReminderHour = _yearlyReportReminderHour;
    final savedYearlyReportReminderMinute = _yearlyReportReminderMinute;
    final savedBottomNavOrder = _bottomNavOrder;
    final savedBottomNavVisible = _bottomNavVisible;
    final savedCalendarMenuOrder = _calendarMenuOrder;
    final savedCalendarMenuHidden = _calendarMenuHidden;
    final savedMineMenuOrder = _mineMenuOrder;
    final savedAppTimeZone = _appTimeZone;
    final savedFollowSystemTimeZone = _followSystemTimeZone;
    final savedQuietHoursEnabled = _quietHoursEnabled;
    final savedQuietHoursStartMinutes = _quietHoursStartMinutes;
    final savedQuietHoursEndMinutes = _quietHoursEndMinutes;
    final savedQuietHoursAllowAlarms = _quietHoursAllowAlarms;
    final savedQuietHoursDeferUntilEnd = _quietHoursDeferUntilEnd;
    return () {
      _firstDayOfWeek = savedFirstDayOfWeek;
      _dateFormat = savedDateFormat;
      _defaultTab = savedDefaultTab;
      _haptic = savedHaptic;
      _showLunar = savedShowLunar;
      _showCompletedTodos = savedShowCompletedTodos;
      _defaultPomodoroMinutes = savedDefaultPomodoroMinutes;
      _quickCaptureFab = savedQuickCaptureFab;
      _notificationQuickAdd = savedNotificationQuickAdd;
      _notificationTodayProgress = savedNotificationTodayProgress;
      _notificationHistoryLimit = savedNotificationHistoryLimit;
      _autoArchiveCompletedDays = savedAutoArchiveCompletedDays;
      _dailyReminderEnabled = savedDailyReminderEnabled;
      _dailyReminderKind = savedDailyReminderKind;
      _dailyReminderHour = savedDailyReminderHour;
      _dailyReminderMinute = savedDailyReminderMinute;
      _dailyReminderIncludeTodayTasks = savedDailyReminderIncludeTodayTasks;
      _dailyReminderIncludeTomorrowPlan = savedDailyReminderIncludeTomorrowPlan;
      _dailyReminderIncludeOverdue = savedDailyReminderIncludeOverdue;
      _dailyReminderRepeatDays = savedDailyReminderRepeatDays;
      _dailyReminderPauseHolidays = savedDailyReminderPauseHolidays;
      _dailyReminderSlots = savedDailyReminderSlots;
      _dailyReportReminder = savedDailyReportReminder;
      _dailyReportReminderHour = savedDailyReportReminderHour;
      _dailyReportReminderMinute = savedDailyReportReminderMinute;
      _weeklyReportReminder = savedWeeklyReportReminder;
      _weeklyReportReminderWeekday = savedWeeklyReportReminderWeekday;
      _weeklyReportReminderHour = savedWeeklyReportReminderHour;
      _weeklyReportReminderMinute = savedWeeklyReportReminderMinute;
      _monthlyReportReminder = savedMonthlyReportReminder;
      _monthlyReportReminderDay = savedMonthlyReportReminderDay;
      _monthlyReportReminderHour = savedMonthlyReportReminderHour;
      _monthlyReportReminderMinute = savedMonthlyReportReminderMinute;
      _yearlyReportReminder = savedYearlyReportReminder;
      _yearlyReportReminderMonth = savedYearlyReportReminderMonth;
      _yearlyReportReminderDay = savedYearlyReportReminderDay;
      _yearlyReportReminderHour = savedYearlyReportReminderHour;
      _yearlyReportReminderMinute = savedYearlyReportReminderMinute;
      _bottomNavOrder = savedBottomNavOrder;
      _bottomNavVisible = savedBottomNavVisible;
      _calendarMenuOrder = savedCalendarMenuOrder;
      _calendarMenuHidden = savedCalendarMenuHidden;
      _mineMenuOrder = savedMineMenuOrder;
      _appTimeZone = savedAppTimeZone;
      _followSystemTimeZone = savedFollowSystemTimeZone;
      _quietHoursEnabled = savedQuietHoursEnabled;
      _quietHoursStartMinutes = savedQuietHoursStartMinutes;
      _quietHoursEndMinutes = savedQuietHoursEndMinutes;
      _quietHoursAllowAlarms = savedQuietHoursAllowAlarms;
      _quietHoursDeferUntilEnd = savedQuietHoursDeferUntilEnd;
    };
  }

  int get firstDayOfWeek => _firstDayOfWeek;
  String get dateFormat => _dateFormat;
  int get defaultTab => _defaultTab;
  bool get haptic => _haptic;
  bool get showLunar => _showLunar;
  bool get showCompletedTodos => _showCompletedTodos;
  int get defaultPomodoroMinutes => _defaultPomodoroMinutes;
  bool get quickCaptureFab => _quickCaptureFab;
  bool get notificationQuickAdd => _notificationQuickAdd;
  bool get notificationTodayProgress => _notificationTodayProgress;
  int get notificationHistoryLimit => _notificationHistoryLimit;
  int get autoArchiveCompletedDays => _autoArchiveCompletedDays;
  bool get quietHoursEnabled => _quietHoursEnabled;
  int get quietHoursStartMinutes => _quietHoursStartMinutes;
  int get quietHoursEndMinutes => _quietHoursEndMinutes;
  bool get quietHoursAllowAlarms => _quietHoursAllowAlarms;
  bool get quietHoursDeferUntilEnd => _quietHoursDeferUntilEnd;
  QuietHoursPolicy get quietHoursPolicy => QuietHoursPolicy(
    enabled: _quietHoursEnabled,
    startMinutes: _quietHoursStartMinutes,
    endMinutes: _quietHoursEndMinutes,
    allowAlarms: _quietHoursAllowAlarms,
    deferUntilEnd: _quietHoursDeferUntilEnd,
  );
  bool get dailyReminderEnabled => _dailyReminderEnabled;
  int get dailyReminderHour => _dailyReminderHour;
  int get dailyReminderMinute => _dailyReminderMinute;
  bool get dailyReminderIncludeTodayTasks => _dailyReminderIncludeTodayTasks;
  bool get dailyReminderIncludeTomorrowPlan =>
      _dailyReminderIncludeTomorrowPlan;
  bool get dailyReminderIncludeOverdue => _dailyReminderIncludeOverdue;
  List<int> get dailyReminderRepeatDays =>
      List.unmodifiable(_dailyReminderRepeatDays);
  bool get dailyReminderPauseHolidays => _dailyReminderPauseHolidays;
  List<DailyReminderSlot> get dailyReminderSlots =>
      List.unmodifiable(_dailyReminderSlots);
  bool get dailyReportReminder => _dailyReportReminder;
  int get dailyReportReminderHour => _dailyReportReminderHour;
  int get dailyReportReminderMinute => _dailyReportReminderMinute;
  ReportReminderConfig get dailyReportReminderConfig => ReportReminderConfig(
    enabled: _dailyReportReminder,
    hour: _dailyReportReminderHour,
    minute: _dailyReportReminderMinute,
  );
  bool get weeklyReportReminder => _weeklyReportReminder;
  int get weeklyReportReminderWeekday => _weeklyReportReminderWeekday;
  int get weeklyReportReminderHour => _weeklyReportReminderHour;
  int get weeklyReportReminderMinute => _weeklyReportReminderMinute;
  ReportReminderConfig get weeklyReportReminderConfig => ReportReminderConfig(
    enabled: _weeklyReportReminder,
    weekday: _weeklyReportReminderWeekday,
    hour: _weeklyReportReminderHour,
    minute: _weeklyReportReminderMinute,
  );
  bool get monthlyReportReminder => _monthlyReportReminder;
  int get monthlyReportReminderDay => _monthlyReportReminderDay;
  int get monthlyReportReminderHour => _monthlyReportReminderHour;
  int get monthlyReportReminderMinute => _monthlyReportReminderMinute;
  ReportReminderConfig get monthlyReportReminderConfig => ReportReminderConfig(
    enabled: _monthlyReportReminder,
    monthDay: _monthlyReportReminderDay,
    hour: _monthlyReportReminderHour,
    minute: _monthlyReportReminderMinute,
  );
  bool get yearlyReportReminder => _yearlyReportReminder;
  int get yearlyReportReminderMonth => _yearlyReportReminderMonth;
  int get yearlyReportReminderDay => _yearlyReportReminderDay;
  int get yearlyReportReminderHour => _yearlyReportReminderHour;
  int get yearlyReportReminderMinute => _yearlyReportReminderMinute;
  ReportReminderConfig get yearlyReportReminderConfig => ReportReminderConfig(
    enabled: _yearlyReportReminder,
    month: _yearlyReportReminderMonth,
    monthDay: _yearlyReportReminderDay,
    hour: _yearlyReportReminderHour,
    minute: _yearlyReportReminderMinute,
  );
  List<int> get bottomNavOrder => List.unmodifiable(_bottomNavOrder);
  Set<int> get bottomNavVisible => Set.unmodifiable(_bottomNavVisible);
  List<String> get calendarMenuOrder => List.unmodifiable(_calendarMenuOrder);
  Set<String> get calendarMenuHidden => Set.unmodifiable(_calendarMenuHidden);
  List<String> get visibleCalendarMenuItems => _calendarMenuOrder
      .where((item) => !_calendarMenuHidden.contains(item))
      .toList(growable: false);
  List<int> get mineMenuOrder => List.unmodifiable(_mineMenuOrder);
  String get appTimeZone => _appTimeZone;
  bool get followSystemTimeZone => _followSystemTimeZone;
  String get appTimeZoneSelection => _followSystemTimeZone
      ? LocalTimezoneResolver.followSystemValue
      : _appTimeZone;
  List<int> get enabledBottomNavTabs => _bottomNavOrder
      .where((tab) => _bottomNavVisible.contains(tab))
      .toList(growable: false);
  List<int> get visibleBottomNavTabs => normalizedVisibleBottomNavTabs(
    order: _bottomNavOrder,
    visible: _bottomNavVisible,
  );

  static List<int> normalizedVisibleBottomNavTabs({
    required Iterable<int> order,
    required Iterable<int> visible,
  }) {
    final rawTabs = _normalizeNavOrder(
      order,
    ).where((tab) => visible.contains(tab)).toList(growable: false);
    if (rawTabs.isEmpty ||
        !rawTabs.any((tab) => !fixedBottomNavTabs.contains(tab))) {
      return List.unmodifiable(defaultBottomNavTabs);
    }

    final flexibleBudget = maxBottomNavTabs - fixedBottomNavTabs.length;
    final selected = <int>{};
    for (final tab in rawTabs) {
      if (fixedBottomNavTabs.contains(tab)) continue;
      if (selected.length >= flexibleBudget) break;
      selected.add(tab);
    }
    selected.addAll(fixedBottomNavTabs);

    final result = <int>[];
    for (final tab in rawTabs) {
      if (selected.contains(tab) && !result.contains(tab)) result.add(tab);
    }
    for (final tab in fixedBottomNavTabs) {
      if (!result.contains(tab)) result.add(tab);
    }
    while (result.length > maxBottomNavTabs) {
      final removeAt = result.indexWhere(
        (tab) => !fixedBottomNavTabs.contains(tab),
      );
      if (removeAt < 0) break;
      result.removeAt(removeAt);
    }
    return List.unmodifiable(result);
  }

  Future<void> setCalendarMenuItemVisible(String item, bool visible) {
    return _enqueuePreferenceChange((transaction) async {
      if (!defaultCalendarMenuOrder.contains(item)) return;
      final next = {..._calendarMenuHidden};
      if (visible) {
        next.remove(item);
      } else {
        if (defaultCalendarMenuOrder.length - next.length <= 1 &&
            !next.contains(item)) {
          return;
        }
        next.add(item);
      }
      _calendarMenuHidden = _normalizeCalendarMenuHidden(next);
      final p = await transaction.getPreferences();
      await p.setStringList(
        _kCalendarMenuHidden,
        _calendarMenuHidden.toList()..sort(),
      );
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kCalendarMenuHidden]);
    });
  }

  Future<void> moveCalendarMenuItem(String item, int delta) {
    return _enqueuePreferenceChange((transaction) async {
      final list = [..._calendarMenuOrder];
      final index = list.indexOf(item);
      if (index < 0) return;
      final nextIndex = (index + delta).clamp(0, list.length - 1);
      if (nextIndex == index) return;
      list.removeAt(index);
      list.insert(nextIndex, item);
      _calendarMenuOrder = _normalizeCalendarMenuOrder(list);
      final p = await transaction.getPreferences();
      await p.setStringList(_kCalendarMenuOrder, _calendarMenuOrder);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kCalendarMenuOrder]);
    });
  }

  Future<void> resetCalendarMenuConfig() {
    return _enqueuePreferenceChange((transaction) async {
      _calendarMenuOrder = defaultCalendarMenuOrder;
      _calendarMenuHidden = const <String>{};
      final p = await transaction.getPreferences();
      await p.setStringList(_kCalendarMenuOrder, _calendarMenuOrder);
      await p.setStringList(_kCalendarMenuHidden, const <String>[]);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kCalendarMenuOrder, _kCalendarMenuHidden]);
    });
  }

  static List<String> _normalizeCalendarMenuOrder(Iterable<String>? source) {
    final result = <String>[];
    for (final item in source ?? const <String>[]) {
      if (defaultCalendarMenuOrder.contains(item) && !result.contains(item)) {
        result.add(item);
      }
    }
    for (final item in defaultCalendarMenuOrder) {
      if (!result.contains(item)) result.add(item);
    }
    return List.unmodifiable(result);
  }

  static Set<String> _normalizeCalendarMenuHidden(Iterable<String>? source) {
    final result = <String>{};
    for (final item in source ?? const <String>[]) {
      if (defaultCalendarMenuOrder.contains(item)) {
        result.add(item);
      }
    }
    if (result.length >= defaultCalendarMenuOrder.length) {
      return const <String>{};
    }
    return Set.unmodifiable(result);
  }

  Future<void> moveMineMenuGroup(int groupIndex, int delta) {
    return _enqueuePreferenceChange((transaction) async {
      final list = [..._mineMenuOrder];
      final index = list.indexOf(groupIndex);
      if (index < 0) return;
      final nextIndex = (index + delta).clamp(0, list.length - 1);
      if (nextIndex == index) return;
      list.removeAt(index);
      list.insert(nextIndex, groupIndex);
      _mineMenuOrder = _normalizeMineMenuOrder(list);
      final p = await transaction.getPreferences();
      await p.setStringList(
        _kMineMenuOrder,
        _mineMenuOrder.map((v) => v.toString()).toList(),
      );
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kMineMenuOrder]);
    });
  }

  Future<void> resetMineMenuOrder() {
    return _enqueuePreferenceChange((transaction) async {
      _mineMenuOrder = defaultMineMenuOrder;
      final p = await transaction.getPreferences();
      await p.setStringList(
        _kMineMenuOrder,
        _mineMenuOrder.map((v) => v.toString()).toList(),
      );
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kMineMenuOrder]);
    });
  }

  static List<int> _normalizeMineMenuOrder(Iterable<int>? source) {
    final result = <int>[];
    for (final group in source ?? const <int>[]) {
      if (defaultMineMenuOrder.contains(group) && !result.contains(group)) {
        result.add(group);
      }
    }
    for (final group in defaultMineMenuOrder) {
      if (!result.contains(group)) result.add(group);
    }
    return List.unmodifiable(result);
  }

  String formatDate(DateTime d) => I18nDateFormat.date(d, pattern: _dateFormat);

  void resetLocalState() {
    _storageGeneration++;
    _storageReadSerial++;
    _loadedAccountGeneration = null;
    _applyDefaults();
    notifyListeners();
  }

  void _applyDefaults() {
    _firstDayOfWeek = 1;
    _dateFormat = 'yyyy-MM-dd';
    _defaultTab = 0;
    _haptic = true;
    _showLunar = true;
    _showCompletedTodos = false;
    _defaultPomodoroMinutes = 25;
    _quickCaptureFab = true;
    _notificationQuickAdd = false;
    _notificationTodayProgress = false;
    _notificationHistoryLimit = NotificationHistoryPolicy.defaultLimit;
    _autoArchiveCompletedDays = 0;
    _dailyReminderEnabled = false;
    _dailyReminderKind = ReminderKind.push;
    _dailyReminderHour = 20;
    _dailyReminderMinute = 0;
    _dailyReminderIncludeTodayTasks = true;
    _dailyReminderIncludeTomorrowPlan = true;
    _dailyReminderIncludeOverdue = true;
    _dailyReminderRepeatDays = const [1, 2, 3, 4, 5, 6, 7];
    _dailyReminderPauseHolidays = false;
    _dailyReminderSlots = const [
      DailyReminderSlot(),
      DailyReminderSlot(hour: 8, enabled: false),
      DailyReminderSlot(hour: 22, enabled: false),
    ];
    _dailyReportReminder = false;
    _dailyReportReminderHour = 21;
    _dailyReportReminderMinute = 30;
    _weeklyReportReminder = false;
    _weeklyReportReminderWeekday = DateTime.monday;
    _weeklyReportReminderHour = 9;
    _weeklyReportReminderMinute = 0;
    _monthlyReportReminder = false;
    _monthlyReportReminderDay = 1;
    _monthlyReportReminderHour = 9;
    _monthlyReportReminderMinute = 0;
    _yearlyReportReminder = false;
    _yearlyReportReminderMonth = 1;
    _yearlyReportReminderDay = 1;
    _yearlyReportReminderHour = 9;
    _yearlyReportReminderMinute = 0;
    _bottomNavOrder = const [0, 1, 2, 3, 4, 5, 6];
    _bottomNavVisible = defaultBottomNavTabs;
    _calendarMenuOrder = defaultCalendarMenuOrder;
    _calendarMenuHidden = const <String>{};
    _mineMenuOrder = defaultMineMenuOrder;
    _followSystemTimeZone = true;
    _appTimeZone = LocalTimezoneResolver.currentIana;
    _quietHoursEnabled = false;
    _quietHoursStartMinutes = QuietHoursPolicy.defaultStartMinutes;
    _quietHoursEndMinutes = QuietHoursPolicy.defaultEndMinutes;
    _quietHoursAllowAlarms = true;
    _quietHoursDeferUntilEnd = true;
  }

  Future<void> loadFromStorage() {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final serial = ++_storageReadSerial;
    _loadedAccountGeneration = null;
    notifyListeners();
    final read = _preferenceWriteTail.then(
      (_) => _readFromStorage(
        generation: generation,
        accountGeneration: accountGeneration,
        serial: serial,
      ),
    );
    _preferenceWriteTail = read.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return read;
  }

  // Error recovery already owns the write tail; it must read directly.
  Future<void> _readFromStorage({
    int? generation,
    int? accountGeneration,
    int? serial,
  }) async {
    generation ??= _storageGeneration;
    accountGeneration ??= AccountLocalDataCleaner.accountDataGeneration;
    serial ??= ++_storageReadSerial;
    bool isCurrent() =>
        generation == _storageGeneration &&
        serial == _storageReadSerial &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration!,
        );
    if (!isCurrent()) return;
    _loadedAccountGeneration = null;
    final p = await SharedPreferences.getInstance();
    if (!isCurrent()) return;
    _firstDayOfWeek = CalendarDateNavigation.normalizeFirstDayOfWeek(
      p.getInt(_kFirstDayOfWeek) ?? 1,
    );
    final storedDateFormat = p.get(_kDateFormat);
    _dateFormat = I18nDateFormat.normalizePattern(
      storedDateFormat is String ? storedDateFormat : null,
    );
    _followSystemTimeZone =
        (p.getString(_kAppTimeZoneMode) ??
            LocalTimezoneResolver.followSystemValue) !=
        LocalTimezoneResolver.fixedValue;
    await LocalTimezoneResolver.applyApplicationTimeZone(
      _followSystemTimeZone
          ? LocalTimezoneResolver.followSystemValue
          : (p.getString(_kAppTimeZone) ?? LocalTimezoneResolver.defaultIana),
      isCurrent: isCurrent,
    );
    if (!isCurrent()) return;
    _appTimeZone = LocalTimezoneResolver.currentIana;
    final storedOrder = p.getStringList(_kBottomNavOrder);
    final storedVisible = p.getStringList(_kBottomNavVisible);
    final isOldBottomNavConfig =
        (storedOrder == null || !storedOrder.contains('6')) &&
        (storedVisible == null || !storedVisible.contains('6'));
    final storedDefaultTab = p.getInt(_kDefaultTab) ?? 0;
    _defaultTab = normalizeDefaultTab(
      isOldBottomNavConfig && storedDefaultTab == 5 ? 6 : storedDefaultTab,
    );
    _haptic = p.getBool(_kHapticFeedback) ?? true;
    _showLunar = p.getBool(_kShowLunar) ?? true;
    _showCompletedTodos = p.getBool(_kShowCompletedTodos) ?? false;
    _defaultPomodoroMinutes = (p.getInt(_kDefaultPomodoroMinutes) ?? 25).clamp(
      5,
      180,
    );
    _quickCaptureFab = p.getBool(_kQuickCaptureFab) ?? true;
    _notificationQuickAdd = p.getBool(_kNotificationQuickAdd) ?? false;
    _notificationTodayProgress =
        p.getBool(_kNotificationTodayProgress) ?? false;
    _notificationHistoryLimit = NotificationHistoryPolicy.normalize(
      p.getInt(_kNotificationHistoryLimit),
    );
    _autoArchiveCompletedDays = (p.getInt(_kAutoArchiveCompletedDays) ?? 0)
        .clamp(0, 365);
    _dailyReminderEnabled = p.getBool(_kDailyReminderEnabled) ?? false;
    _dailyReminderKind = DailyReminderSlot.parseKind(
      p.getString(_kDailyReminderKind),
    );
    if (_dailyReminderKind == ReminderKind.off) {
      _dailyReminderEnabled = false;
    }
    _dailyReminderHour = p.getInt(_kDailyReminderHour) ?? 20;
    _dailyReminderMinute = p.getInt(_kDailyReminderMinute) ?? 0;
    _dailyReminderIncludeTodayTasks =
        p.getBool(_kDailyReminderIncludeTodayTasks) ?? true;
    _dailyReminderIncludeTomorrowPlan =
        p.getBool(_kDailyReminderIncludeTomorrowPlan) ?? true;
    _dailyReminderIncludeOverdue =
        p.getBool(_kDailyReminderIncludeOverdue) ?? true;
    _dailyReminderRepeatDays =
        p
            .getStringList(_kDailyReminderRepeatDays)
            ?.map(int.tryParse)
            .whereType<int>()
            .where((d) => d >= 1 && d <= 7)
            .toList() ??
        const [1, 2, 3, 4, 5, 6, 7];
    if (_dailyReminderRepeatDays.isEmpty) {
      _dailyReminderRepeatDays = const [1, 2, 3, 4, 5, 6, 7];
    }
    _dailyReminderPauseHolidays =
        p.getBool(_kDailyReminderPauseHolidays) ?? false;
    _dailyReminderSlots = List.generate(3, (i) {
      if (i == 0) {
        return DailyReminderSlot(
          enabled: _dailyReminderEnabled,
          kind: _dailyReminderKind,
          hour: _dailyReminderHour,
          minute: _dailyReminderMinute,
          includeTodayTasks: _dailyReminderIncludeTodayTasks,
          includeTomorrowPlan: _dailyReminderIncludeTomorrowPlan,
          includeOverdue: _dailyReminderIncludeOverdue,
          repeatDays: _dailyReminderRepeatDays,
          pauseHolidays: _dailyReminderPauseHolidays,
        );
      }
      final prefix = '$_kDailyReminderSlotPrefix${i + 1}';
      final kind = DailyReminderSlot.parseKind(p.getString('${prefix}_kind'));
      return DailyReminderSlot(
        enabled:
            kind != ReminderKind.off &&
            (p.getBool('${prefix}_enabled') ?? false),
        kind: kind,
        hour: p.getInt('${prefix}_hour') ?? (i == 1 ? 8 : 22),
        minute: p.getInt('${prefix}_minute') ?? 0,
        includeTodayTasks: p.getBool('${prefix}_today') ?? true,
        includeTomorrowPlan: p.getBool('${prefix}_tomorrow') ?? true,
        includeOverdue: p.getBool('${prefix}_overdue') ?? true,
        repeatDays: DailyReminderSlot._normalizeDays(
          p
                  .getStringList('${prefix}_repeat_days')
                  ?.map(int.tryParse)
                  .whereType<int>()
                  .toList() ??
              const [1, 2, 3, 4, 5, 6, 7],
        ),
        pauseHolidays: p.getBool('${prefix}_pause_holidays') ?? false,
      );
    });
    _dailyReportReminder = p.getBool(_kDailyReportReminder) ?? false;
    _dailyReportReminderHour = (p.getInt(_kDailyReportReminderHour) ?? 21)
        .clamp(0, 23);
    _dailyReportReminderMinute = (p.getInt(_kDailyReportReminderMinute) ?? 30)
        .clamp(0, 59);
    _weeklyReportReminder = p.getBool(_kWeeklyReportReminder) ?? false;
    _weeklyReportReminderWeekday =
        (p.getInt(_kWeeklyReportReminderWeekday) ?? DateTime.monday).clamp(
          1,
          7,
        );
    _weeklyReportReminderHour = (p.getInt(_kWeeklyReportReminderHour) ?? 9)
        .clamp(0, 23);
    _weeklyReportReminderMinute = (p.getInt(_kWeeklyReportReminderMinute) ?? 0)
        .clamp(0, 59);
    _monthlyReportReminder = p.getBool(_kMonthlyReportReminder) ?? false;
    _monthlyReportReminderDay = (p.getInt(_kMonthlyReportReminderDay) ?? 1)
        .clamp(1, 31);
    _monthlyReportReminderHour = (p.getInt(_kMonthlyReportReminderHour) ?? 9)
        .clamp(0, 23);
    _monthlyReportReminderMinute =
        (p.getInt(_kMonthlyReportReminderMinute) ?? 0).clamp(0, 59);
    _yearlyReportReminder = p.getBool(_kYearlyReportReminder) ?? false;
    _yearlyReportReminderMonth = (p.getInt(_kYearlyReportReminderMonth) ?? 1)
        .clamp(1, 12);
    _yearlyReportReminderDay = (p.getInt(_kYearlyReportReminderDay) ?? 1).clamp(
      1,
      31,
    );
    _yearlyReportReminderHour = (p.getInt(_kYearlyReportReminderHour) ?? 9)
        .clamp(0, 23);
    _yearlyReportReminderMinute = (p.getInt(_kYearlyReportReminderMinute) ?? 0)
        .clamp(0, 59);
    _bottomNavOrder = _normalizeNavOrder(
      storedOrder?.map(int.tryParse).whereType<int>(),
    );
    _bottomNavVisible = _normalizeNavVisible(
      storedVisible?.map(int.tryParse).whereType<int>(),
      order: _bottomNavOrder,
    );
    _calendarMenuOrder = _normalizeCalendarMenuOrder(
      p.getStringList(_kCalendarMenuOrder),
    );
    _calendarMenuHidden = _normalizeCalendarMenuHidden(
      p.getStringList(_kCalendarMenuHidden),
    );
    _mineMenuOrder = _normalizeMineMenuOrder(
      p.getStringList(_kMineMenuOrder)?.map(int.tryParse).whereType<int>(),
    );
    _quietHoursEnabled = p.getBool(_kQuietHoursEnabled) ?? false;
    _quietHoursStartMinutes = QuietHoursPolicy.normalizeMinutes(
      p.getInt(_kQuietHoursStartMinutes) ??
          QuietHoursPolicy.defaultStartMinutes,
    );
    _quietHoursEndMinutes = QuietHoursPolicy.normalizeMinutes(
      p.getInt(_kQuietHoursEndMinutes) ?? QuietHoursPolicy.defaultEndMinutes,
    );
    _quietHoursAllowAlarms = p.getBool(_kQuietHoursAllowAlarms) ?? true;
    _quietHoursDeferUntilEnd = p.getBool(_kQuietHoursDeferUntilEnd) ?? true;
    if (!isCurrent()) return;
    _loadedAccountGeneration = accountGeneration;
    notifyListeners();
  }

  void _notifyPreferenceKeys(Iterable<String> keys) {
    final cleanKeys = keys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toSet();
    if (cleanKeys.isNotEmpty) {
      onChangedKeys?.call(cleanKeys);
    }
    notifyListeners();
  }

  List<String> _dailyReminderSlotKeys(int index) {
    if (index == 0) {
      return const [
        _kDailyReminderEnabled,
        _kDailyReminderKind,
        _kDailyReminderHour,
        _kDailyReminderMinute,
        _kDailyReminderIncludeTodayTasks,
        _kDailyReminderIncludeTomorrowPlan,
        _kDailyReminderIncludeOverdue,
        _kDailyReminderRepeatDays,
        _kDailyReminderPauseHolidays,
      ];
    }
    final prefix = '$_kDailyReminderSlotPrefix${index + 1}';
    return [
      '${prefix}_enabled',
      '${prefix}_kind',
      '${prefix}_hour',
      '${prefix}_minute',
      '${prefix}_today',
      '${prefix}_tomorrow',
      '${prefix}_overdue',
      '${prefix}_repeat_days',
      '${prefix}_pause_holidays',
    ];
  }

  Future<void> setFirstDayOfWeek(int value) {
    return _enqueuePreferenceChange((transaction) async {
      _firstDayOfWeek = value.clamp(1, 7);
      final p = await transaction.getPreferences();
      await p.setInt(_kFirstDayOfWeek, _firstDayOfWeek);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kFirstDayOfWeek]);
    });
  }

  Future<void> setAppTimeZone(String value) {
    return _enqueuePreferenceChange((transaction) async {
      final next = value == LocalTimezoneResolver.followSystemValue
          ? LocalTimezoneResolver.followSystemValue
          : value == 'UTC' || value.isEmpty
          ? LocalTimezoneResolver.defaultIana
          : value;
      _followSystemTimeZone = next == LocalTimezoneResolver.followSystemValue;
      await LocalTimezoneResolver.persistApplicationTimeZone(transaction, next);
      await LocalTimezoneResolver.applyApplicationTimeZone(
        next,
        isCurrent: () {
          transaction.ensureCurrent();
          return true;
        },
      );
      transaction.ensureCurrent();
      _appTimeZone = LocalTimezoneResolver.currentIana;
      // Keep committed preferences when a reminder resync fails partway.
      transaction.commit();
      _notifyPreferenceKeys(const [_kAppTimeZoneMode, _kAppTimeZone]);
      await onAppTimeZoneChanged?.call();
    });
  }

  Future<void> setDailyReminderSlot(int index, DailyReminderSlot slot) {
    return _enqueuePreferenceChange((transaction) async {
      if (index < 0 || index >= 3) return;
      final normalizedSlot = slot.copyWith();
      if (_sameDailyReminderSlot(_dailyReminderSlots[index], normalizedSlot)) {
        return;
      }
      final next = [..._dailyReminderSlots];
      next[index] = normalizedSlot;
      _dailyReminderSlots = List.unmodifiable(next);

      if (index == 0) {
        _dailyReminderEnabled = normalizedSlot.enabled;
        _dailyReminderKind = normalizedSlot.kind;
        _dailyReminderHour = normalizedSlot.hour;
        _dailyReminderMinute = normalizedSlot.minute;
        _dailyReminderIncludeTodayTasks = normalizedSlot.includeTodayTasks;
        _dailyReminderIncludeTomorrowPlan = normalizedSlot.includeTomorrowPlan;
        _dailyReminderIncludeOverdue = normalizedSlot.includeOverdue;
        _dailyReminderRepeatDays = DailyReminderSlot._normalizeDays(
          normalizedSlot.repeatDays,
        );
        _dailyReminderPauseHolidays = normalizedSlot.pauseHolidays;
      }

      final p = await transaction.getPreferences();
      final prefix = index == 0
          ? null
          : '$_kDailyReminderSlotPrefix${index + 1}';
      if (index == 0) {
        await p.setBool(_kDailyReminderEnabled, normalizedSlot.enabled);
        await p.setString(_kDailyReminderKind, normalizedSlot.kind.name);
        await p.setInt(_kDailyReminderHour, normalizedSlot.hour);
        await p.setInt(_kDailyReminderMinute, normalizedSlot.minute);
        await p.setBool(
          _kDailyReminderIncludeTodayTasks,
          normalizedSlot.includeTodayTasks,
        );
        await p.setBool(
          _kDailyReminderIncludeTomorrowPlan,
          normalizedSlot.includeTomorrowPlan,
        );
        await p.setBool(
          _kDailyReminderIncludeOverdue,
          normalizedSlot.includeOverdue,
        );
        await p.setStringList(
          _kDailyReminderRepeatDays,
          DailyReminderSlot._normalizeDays(
            normalizedSlot.repeatDays,
          ).map((d) => d.toString()).toList(),
        );
        await p.setBool(
          _kDailyReminderPauseHolidays,
          normalizedSlot.pauseHolidays,
        );
      } else {
        await p.setBool('${prefix}_enabled', normalizedSlot.enabled);
        await p.setString('${prefix}_kind', normalizedSlot.kind.name);
        await p.setInt('${prefix}_hour', normalizedSlot.hour);
        await p.setInt('${prefix}_minute', normalizedSlot.minute);
        await p.setBool('${prefix}_today', normalizedSlot.includeTodayTasks);
        await p.setBool(
          '${prefix}_tomorrow',
          normalizedSlot.includeTomorrowPlan,
        );
        await p.setBool('${prefix}_overdue', normalizedSlot.includeOverdue);
        await p.setStringList(
          '${prefix}_repeat_days',
          DailyReminderSlot._normalizeDays(
            normalizedSlot.repeatDays,
          ).map((d) => d.toString()).toList(),
        );
        await p.setBool(
          '${prefix}_pause_holidays',
          normalizedSlot.pauseHolidays,
        );
      }
      transaction.ensureCurrent();
      _notifyPreferenceKeys(_dailyReminderSlotKeys(index));
    });
  }

  Future<void> setWeeklyReportReminder(bool value) {
    return _enqueuePreferenceChange((transaction) async {
      _weeklyReportReminder = value;
      final p = await transaction.getPreferences();
      await p.setBool(_kWeeklyReportReminder, value);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kWeeklyReportReminder]);
    });
  }

  Future<void> setDailyReportReminder(bool value) {
    return _enqueuePreferenceChange((transaction) async {
      _dailyReportReminder = value;
      final p = await transaction.getPreferences();
      await p.setBool(_kDailyReportReminder, value);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kDailyReportReminder]);
    });
  }

  Future<void> setDailyReportReminderConfig(ReportReminderConfig config) {
    return _enqueuePreferenceChange((transaction) async {
      final nextEnabled = config.enabled;
      final nextHour = config.hour.clamp(0, 23);
      final nextMinute = config.minute.clamp(0, 59);
      if (_dailyReportReminder == nextEnabled &&
          _dailyReportReminderHour == nextHour &&
          _dailyReportReminderMinute == nextMinute) {
        return;
      }
      _dailyReportReminder = nextEnabled;
      _dailyReportReminderHour = nextHour;
      _dailyReportReminderMinute = nextMinute;
      final p = await transaction.getPreferences();
      await p.setBool(_kDailyReportReminder, _dailyReportReminder);
      await p.setInt(_kDailyReportReminderHour, _dailyReportReminderHour);
      await p.setInt(_kDailyReportReminderMinute, _dailyReportReminderMinute);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [
        _kDailyReportReminder,
        _kDailyReportReminderHour,
        _kDailyReportReminderMinute,
      ]);
    });
  }

  Future<void> setWeeklyReportReminderConfig(ReportReminderConfig config) {
    return _enqueuePreferenceChange((transaction) async {
      final nextEnabled = config.enabled;
      final nextWeekday = config.weekday.clamp(1, 7);
      final nextHour = config.hour.clamp(0, 23);
      final nextMinute = config.minute.clamp(0, 59);
      if (_weeklyReportReminder == nextEnabled &&
          _weeklyReportReminderWeekday == nextWeekday &&
          _weeklyReportReminderHour == nextHour &&
          _weeklyReportReminderMinute == nextMinute) {
        return;
      }
      _weeklyReportReminder = nextEnabled;
      _weeklyReportReminderWeekday = nextWeekday;
      _weeklyReportReminderHour = nextHour;
      _weeklyReportReminderMinute = nextMinute;
      final p = await transaction.getPreferences();
      await p.setBool(_kWeeklyReportReminder, _weeklyReportReminder);
      await p.setInt(
        _kWeeklyReportReminderWeekday,
        _weeklyReportReminderWeekday,
      );
      await p.setInt(_kWeeklyReportReminderHour, _weeklyReportReminderHour);
      await p.setInt(_kWeeklyReportReminderMinute, _weeklyReportReminderMinute);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [
        _kWeeklyReportReminder,
        _kWeeklyReportReminderWeekday,
        _kWeeklyReportReminderHour,
        _kWeeklyReportReminderMinute,
      ]);
    });
  }

  Future<void> setMonthlyReportReminder(bool value) {
    return _enqueuePreferenceChange((transaction) async {
      _monthlyReportReminder = value;
      final p = await transaction.getPreferences();
      await p.setBool(_kMonthlyReportReminder, value);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kMonthlyReportReminder]);
    });
  }

  Future<void> setMonthlyReportReminderConfig(ReportReminderConfig config) {
    return _enqueuePreferenceChange((transaction) async {
      final nextEnabled = config.enabled;
      final nextDay = config.monthDay.clamp(1, 31);
      final nextHour = config.hour.clamp(0, 23);
      final nextMinute = config.minute.clamp(0, 59);
      if (_monthlyReportReminder == nextEnabled &&
          _monthlyReportReminderDay == nextDay &&
          _monthlyReportReminderHour == nextHour &&
          _monthlyReportReminderMinute == nextMinute) {
        return;
      }
      _monthlyReportReminder = nextEnabled;
      _monthlyReportReminderDay = nextDay;
      _monthlyReportReminderHour = nextHour;
      _monthlyReportReminderMinute = nextMinute;
      final p = await transaction.getPreferences();
      await p.setBool(_kMonthlyReportReminder, _monthlyReportReminder);
      await p.setInt(_kMonthlyReportReminderDay, _monthlyReportReminderDay);
      await p.setInt(_kMonthlyReportReminderHour, _monthlyReportReminderHour);
      await p.setInt(
        _kMonthlyReportReminderMinute,
        _monthlyReportReminderMinute,
      );
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [
        _kMonthlyReportReminder,
        _kMonthlyReportReminderDay,
        _kMonthlyReportReminderHour,
        _kMonthlyReportReminderMinute,
      ]);
    });
  }

  Future<void> setYearlyReportReminder(bool value) {
    return _enqueuePreferenceChange((transaction) async {
      _yearlyReportReminder = value;
      final p = await transaction.getPreferences();
      await p.setBool(_kYearlyReportReminder, value);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kYearlyReportReminder]);
    });
  }

  Future<void> setYearlyReportReminderConfig(ReportReminderConfig config) {
    return _enqueuePreferenceChange((transaction) async {
      final nextEnabled = config.enabled;
      final nextMonth = config.month.clamp(1, 12);
      final nextDay = config.monthDay.clamp(1, 31);
      final nextHour = config.hour.clamp(0, 23);
      final nextMinute = config.minute.clamp(0, 59);
      if (_yearlyReportReminder == nextEnabled &&
          _yearlyReportReminderMonth == nextMonth &&
          _yearlyReportReminderDay == nextDay &&
          _yearlyReportReminderHour == nextHour &&
          _yearlyReportReminderMinute == nextMinute) {
        return;
      }
      _yearlyReportReminder = nextEnabled;
      _yearlyReportReminderMonth = nextMonth;
      _yearlyReportReminderDay = nextDay;
      _yearlyReportReminderHour = nextHour;
      _yearlyReportReminderMinute = nextMinute;
      final p = await transaction.getPreferences();
      await p.setBool(_kYearlyReportReminder, _yearlyReportReminder);
      await p.setInt(_kYearlyReportReminderMonth, _yearlyReportReminderMonth);
      await p.setInt(_kYearlyReportReminderDay, _yearlyReportReminderDay);
      await p.setInt(_kYearlyReportReminderHour, _yearlyReportReminderHour);
      await p.setInt(_kYearlyReportReminderMinute, _yearlyReportReminderMinute);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [
        _kYearlyReportReminder,
        _kYearlyReportReminderMonth,
        _kYearlyReportReminderDay,
        _kYearlyReportReminderHour,
        _kYearlyReportReminderMinute,
      ]);
    });
  }

  Future<void> setBottomNavVisible(int tab, bool visible) {
    return _enqueuePreferenceChange((transaction) async {
      if (tab < 0 || tab > 6) return;
      if (!isBottomNavTabSupported(tab)) return;
      if (fixedBottomNavTabs.contains(tab) && !visible) return;
      if (visible &&
          !_bottomNavVisible.contains(tab) &&
          _bottomNavVisible.length >= maxBottomNavTabs) {
        return;
      }
      final next = {..._bottomNavVisible};
      if (visible) {
        next.add(tab);
      } else if (next.length > 2) {
        next.remove(tab);
      }
      _bottomNavVisible = _normalizeNavVisible(next, order: _bottomNavOrder);
      final p = await transaction.getPreferences();
      await p.setStringList(
        _kBottomNavVisible,
        _bottomNavVisible.map((v) => v.toString()).toList(),
      );
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kBottomNavVisible]);
    });
  }

  Future<void> moveBottomNavTab(int tab, int delta) {
    return _enqueuePreferenceChange((transaction) async {
      final list = [..._bottomNavOrder];
      final index = list.indexOf(tab);
      if (index < 0) return;
      final nextIndex = (index + delta).clamp(0, list.length - 1);
      if (nextIndex == index) return;
      list.removeAt(index);
      list.insert(nextIndex, tab);
      _bottomNavOrder = _normalizeNavOrder(list);
      final p = await transaction.getPreferences();
      await p.setStringList(
        _kBottomNavOrder,
        _bottomNavOrder.map((v) => v.toString()).toList(),
      );
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kBottomNavOrder]);
    });
  }

  static List<int> _normalizeNavOrder(Iterable<int>? source) {
    final result = <int>[];
    for (final tab in source ?? const <int>[]) {
      if (tab >= 0 &&
          tab <= 6 &&
          isBottomNavTabSupported(tab) &&
          !result.contains(tab)) {
        result.add(tab);
      }
    }
    for (var i = 0; i < 7; i++) {
      if (isBottomNavTabSupported(i) && !result.contains(i)) result.add(i);
    }
    return List.unmodifiable(result);
  }

  static Set<int> _normalizeNavVisible(
    Iterable<int>? source, {
    Iterable<int>? order,
  }) {
    final orderList = _normalizeNavOrder(order);
    final result = <int>{};
    for (final tab in source ?? const <int>[]) {
      if (tab >= 0 && tab <= 6 && isBottomNavTabSupported(tab)) {
        result.add(tab);
      }
    }
    if (source == null) {
      result.addAll(defaultBottomNavTabs);
    } else if (!result.any((tab) => !fixedBottomNavTabs.contains(tab))) {
      result.addAll(orderList);
    }
    result.addAll(fixedBottomNavTabs);

    final visible = <int>{};
    for (final tab in orderList) {
      if (fixedBottomNavTabs.contains(tab) || !result.contains(tab)) continue;
      if (visible.length >= maxBottomNavTabs - fixedBottomNavTabs.length) {
        break;
      }
      visible.add(tab);
    }
    visible.addAll(fixedBottomNavTabs);
    return Set.unmodifiable(visible);
  }

  Future<void> setDateFormat(String format) {
    return _enqueuePreferenceChange((transaction) async {
      final normalized = I18nDateFormat.normalizePattern(format);
      _dateFormat = normalized;
      final p = await transaction.getPreferences();
      await p.setString(_kDateFormat, normalized);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kDateFormat]);
    });
  }

  Future<void> setDefaultTab(int tab) {
    return _enqueuePreferenceChange((transaction) async {
      final normalized = normalizeDefaultTab(tab);
      _defaultTab = normalized;
      final p = await transaction.getPreferences();
      await p.setInt(_kDefaultTab, normalized);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kDefaultTab]);
    });
  }

  Future<void> setHaptic(bool value) {
    return _enqueuePreferenceChange((transaction) async {
      _haptic = value;
      final p = await transaction.getPreferences();
      await p.setBool(_kHapticFeedback, value);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kHapticFeedback]);
    });
  }

  Future<void> setShowLunar(bool value) {
    return _enqueuePreferenceChange((transaction) async {
      _showLunar = value;
      final p = await transaction.getPreferences();
      await p.setBool(_kShowLunar, value);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kShowLunar]);
    });
  }

  Future<void> setShowCompletedTodos(bool value) {
    return _enqueuePreferenceChange((transaction) async {
      _showCompletedTodos = value;
      final p = await transaction.getPreferences();
      await p.setBool(_kShowCompletedTodos, value);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kShowCompletedTodos]);
    });
  }

  Future<void> setDefaultPomodoroMinutes(int value) {
    return _enqueuePreferenceChange((transaction) async {
      final nextValue = value.clamp(5, 180);
      if (nextValue == _defaultPomodoroMinutes) return;
      final generation = _storageGeneration;
      final p = await transaction.getPreferences();
      if (generation != _storageGeneration) return;
      final saved = await p.setInt(_kDefaultPomodoroMinutes, nextValue);
      if (generation != _storageGeneration) return;
      if (!saved) {
        await p.reload();
        throw StateError('Preference persistence failed');
      }
      _defaultPomodoroMinutes = nextValue;
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kDefaultPomodoroMinutes]);
    });
  }

  Future<void> setQuickCaptureFab(bool value) {
    return _enqueuePreferenceChange((transaction) async {
      _quickCaptureFab = value;
      final p = await transaction.getPreferences();
      await p.setBool(_kQuickCaptureFab, value);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kQuickCaptureFab]);
    });
  }

  Future<void> setNotificationQuickAdd(bool value) {
    return _enqueuePreferenceChange((transaction) async {
      _notificationQuickAdd = value;
      final p = await transaction.getPreferences();
      await p.setBool(_kNotificationQuickAdd, value);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kNotificationQuickAdd]);
    });
  }

  Future<void> setNotificationTodayProgress(bool value) {
    return _enqueuePreferenceChange((transaction) async {
      _notificationTodayProgress = value;
      final p = await transaction.getPreferences();
      await p.setBool(_kNotificationTodayProgress, value);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kNotificationTodayProgress]);
    });
  }

  Future<void> setNotificationHistoryLimit(int value) async {
    await saveNotificationHistoryLimit(value);
  }

  /// Returns false for canceled writes; completion alone is not a save ACK.
  Future<bool> saveNotificationHistoryLimit(
    int value, {
    bool Function()? canWrite,
  }) async {
    final next = NotificationHistoryPolicy.normalize(value);
    var committed = false;
    await _enqueuePreferenceChange((transaction) async {
      if (!(canWrite?.call() ?? true)) {
        throw const AccountPreferenceWriteCanceled();
      }
      final p = await transaction.getPreferences();
      await p.setInt(_kNotificationHistoryLimit, next);
      if (!(canWrite?.call() ?? true)) {
        throw const AccountPreferenceWriteCanceled();
      }
      transaction.commit();
      committed = true;
      _notificationHistoryLimit = next;
      _notifyPreferenceKeys(const [_kNotificationHistoryLimit]);
    });
    return committed;
  }

  Future<void> setAutoArchiveCompletedDays(int days) {
    return _enqueuePreferenceChange((transaction) async {
      final nextValue = days.clamp(0, 365);
      if (nextValue == _autoArchiveCompletedDays) return;
      final generation = _storageGeneration;
      final p = await transaction.getPreferences();
      if (generation != _storageGeneration) return;
      final saved = await p.setInt(_kAutoArchiveCompletedDays, nextValue);
      if (generation != _storageGeneration) return;
      if (!saved) {
        await p.reload();
        throw StateError('Preference persistence failed');
      }
      _autoArchiveCompletedDays = nextValue;
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kAutoArchiveCompletedDays]);
    });
  }

  Future<void> setDailyReminderEnabled(bool value) {
    return _enqueuePreferenceChange((transaction) async {
      final currentSlot = _dailyReminderSlots[0];
      final nextSlot = value && currentSlot.kind == ReminderKind.off
          ? currentSlot.copyWith(enabled: true, kind: ReminderKind.push)
          : currentSlot.copyWith(enabled: value);
      _dailyReminderEnabled = nextSlot.enabled;
      _dailyReminderKind = nextSlot.kind;
      _dailyReminderSlots = _replaceSlot(0, nextSlot);

      final changedKeys = <String>[_kDailyReminderEnabled];
      if (nextSlot.kind != currentSlot.kind) {
        changedKeys.add(_kDailyReminderKind);
      }

      final p = await transaction.getPreferences();
      await p.setBool(_kDailyReminderEnabled, nextSlot.enabled);
      if (nextSlot.kind != currentSlot.kind) {
        await p.setString(_kDailyReminderKind, nextSlot.kind.name);
      }
      transaction.ensureCurrent();
      _notifyPreferenceKeys(changedKeys);
    });
  }

  Future<void> setDailyReminderTime(int hour, int minute) {
    return _enqueuePreferenceChange((transaction) async {
      _dailyReminderHour = hour.clamp(0, 23);
      _dailyReminderMinute = minute.clamp(0, 59);
      _dailyReminderSlots = _replaceSlot(
        0,
        _dailyReminderSlots[0].copyWith(
          hour: _dailyReminderHour,
          minute: _dailyReminderMinute,
        ),
      );
      final p = await transaction.getPreferences();
      await p.setInt(_kDailyReminderHour, _dailyReminderHour);
      await p.setInt(_kDailyReminderMinute, _dailyReminderMinute);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kDailyReminderHour, _kDailyReminderMinute]);
    });
  }

  Future<void> setDailyReminderIncludeTodayTasks(bool value) {
    return _enqueuePreferenceChange((transaction) async {
      _dailyReminderIncludeTodayTasks = value;
      _dailyReminderSlots = _replaceSlot(
        0,
        _dailyReminderSlots[0].copyWith(includeTodayTasks: value),
      );
      final p = await transaction.getPreferences();
      await p.setBool(_kDailyReminderIncludeTodayTasks, value);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kDailyReminderIncludeTodayTasks]);
    });
  }

  Future<void> setDailyReminderIncludeTomorrowPlan(bool value) {
    return _enqueuePreferenceChange((transaction) async {
      _dailyReminderIncludeTomorrowPlan = value;
      _dailyReminderSlots = _replaceSlot(
        0,
        _dailyReminderSlots[0].copyWith(includeTomorrowPlan: value),
      );
      final p = await transaction.getPreferences();
      await p.setBool(_kDailyReminderIncludeTomorrowPlan, value);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kDailyReminderIncludeTomorrowPlan]);
    });
  }

  Future<void> setDailyReminderIncludeOverdue(bool value) {
    return _enqueuePreferenceChange((transaction) async {
      _dailyReminderIncludeOverdue = value;
      _dailyReminderSlots = _replaceSlot(
        0,
        _dailyReminderSlots[0].copyWith(includeOverdue: value),
      );
      final p = await transaction.getPreferences();
      await p.setBool(_kDailyReminderIncludeOverdue, value);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kDailyReminderIncludeOverdue]);
    });
  }

  Future<void> setDailyReminderRepeatDays(List<int> days) {
    return _enqueuePreferenceChange((transaction) async {
      final normalized = days.where((d) => d >= 1 && d <= 7).toSet().toList()
        ..sort();
      _dailyReminderRepeatDays = normalized.isEmpty
          ? const [1, 2, 3, 4, 5, 6, 7]
          : normalized;
      _dailyReminderSlots = _replaceSlot(
        0,
        _dailyReminderSlots[0].copyWith(repeatDays: _dailyReminderRepeatDays),
      );
      final p = await transaction.getPreferences();
      await p.setStringList(
        _kDailyReminderRepeatDays,
        _dailyReminderRepeatDays.map((d) => d.toString()).toList(),
      );
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kDailyReminderRepeatDays]);
    });
  }

  Future<void> setDailyReminderPauseHolidays(bool value) {
    return _enqueuePreferenceChange((transaction) async {
      _dailyReminderPauseHolidays = value;
      _dailyReminderSlots = _replaceSlot(
        0,
        _dailyReminderSlots[0].copyWith(pauseHolidays: value),
      );
      final p = await transaction.getPreferences();
      await p.setBool(_kDailyReminderPauseHolidays, value);
      transaction.ensureCurrent();
      _notifyPreferenceKeys(const [_kDailyReminderPauseHolidays]);
    });
  }

  Future<void> setQuietHours({
    bool? enabled,
    int? startMinutes,
    int? endMinutes,
    bool? allowAlarms,
    bool? deferUntilEnd,
  }) {
    return _enqueuePreferenceChange((transaction) async {
      final changedKeys = <String>[];
      final p = await transaction.getPreferences();
      if (enabled != null && enabled != _quietHoursEnabled) {
        _quietHoursEnabled = enabled;
        await p.setBool(_kQuietHoursEnabled, enabled);
        changedKeys.add(_kQuietHoursEnabled);
      }
      if (startMinutes != null) {
        final normalized = QuietHoursPolicy.normalizeMinutes(startMinutes);
        if (normalized != _quietHoursStartMinutes) {
          _quietHoursStartMinutes = normalized;
          await p.setInt(_kQuietHoursStartMinutes, normalized);
          changedKeys.add(_kQuietHoursStartMinutes);
        }
      }
      if (endMinutes != null) {
        final normalized = QuietHoursPolicy.normalizeMinutes(endMinutes);
        if (normalized != _quietHoursEndMinutes) {
          _quietHoursEndMinutes = normalized;
          await p.setInt(_kQuietHoursEndMinutes, normalized);
          changedKeys.add(_kQuietHoursEndMinutes);
        }
      }
      if (allowAlarms != null && allowAlarms != _quietHoursAllowAlarms) {
        _quietHoursAllowAlarms = allowAlarms;
        await p.setBool(_kQuietHoursAllowAlarms, allowAlarms);
        changedKeys.add(_kQuietHoursAllowAlarms);
      }
      if (deferUntilEnd != null && deferUntilEnd != _quietHoursDeferUntilEnd) {
        _quietHoursDeferUntilEnd = deferUntilEnd;
        await p.setBool(_kQuietHoursDeferUntilEnd, deferUntilEnd);
        changedKeys.add(_kQuietHoursDeferUntilEnd);
      }
      transaction.ensureCurrent();
      if (changedKeys.isNotEmpty) {
        _notifyPreferenceKeys(changedKeys);
      }
    });
  }

  Future<void> setQuietHoursEnabled(bool value) =>
      setQuietHours(enabled: value);

  Future<void> setQuietHoursWindow(int startMinutes, int endMinutes) =>
      setQuietHours(startMinutes: startMinutes, endMinutes: endMinutes);

  Future<void> setQuietHoursAllowAlarms(bool value) =>
      setQuietHours(allowAlarms: value);

  Future<void> setQuietHoursDeferUntilEnd(bool value) =>
      setQuietHours(deferUntilEnd: value);

  List<DailyReminderSlot> _replaceSlot(int index, DailyReminderSlot slot) {
    final next = [..._dailyReminderSlots];
    next[index] = slot;
    return List.unmodifiable(next);
  }
}
