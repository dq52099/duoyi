import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 用户个性化偏好(本地)。不涉及服务器配置，每个设备独立。
class PreferencesProvider extends ChangeNotifier {
  static const _kFirstDayOfWeek = 'pref_first_day_of_week';
  static const _kDateFormat = 'pref_date_format';
  static const _kDefaultTab = 'pref_default_tab';
  static const _kHapticFeedback = 'pref_haptic_feedback';
  static const _kShowLunar = 'pref_show_lunar';
  static const _kShowCompletedTodos = 'pref_show_completed_todos';
  static const _kDefaultPomodoroMinutes = 'pref_default_pomodoro_minutes';
  static const _kQuickCaptureFab = 'pref_quick_capture_fab';
  static const _kAutoArchiveCompletedDays = 'pref_auto_archive_completed_days';
  static const _kDailyReminderEnabled = 'pref_daily_reminder_enabled';
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

  int _firstDayOfWeek = 1; // 1=周一, 7=周日
  String _dateFormat = 'yyyy-MM-dd';
  int _defaultTab = 0; // 0=Today
  bool _haptic = true;
  bool _showLunar = true;
  bool _showCompletedTodos = false;
  int _defaultPomodoroMinutes = 25;
  bool _quickCaptureFab = true;
  int _autoArchiveCompletedDays = 0; // 0=不归档
  bool _dailyReminderEnabled = false;
  int _dailyReminderHour = 20;
  int _dailyReminderMinute = 0;
  bool _dailyReminderIncludeTodayTasks = true;
  bool _dailyReminderIncludeTomorrowPlan = true;
  bool _dailyReminderIncludeOverdue = true;
  List<int> _dailyReminderRepeatDays = const [1, 2, 3, 4, 5, 6, 7];
  bool _dailyReminderPauseHolidays = false;

  int get firstDayOfWeek => _firstDayOfWeek;
  String get dateFormat => _dateFormat;
  int get defaultTab => _defaultTab;
  bool get haptic => _haptic;
  bool get showLunar => _showLunar;
  bool get showCompletedTodos => _showCompletedTodos;
  int get defaultPomodoroMinutes => _defaultPomodoroMinutes;
  bool get quickCaptureFab => _quickCaptureFab;
  int get autoArchiveCompletedDays => _autoArchiveCompletedDays;
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

  String formatDate(DateTime d) {
    final y = d.year.toString();
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    switch (_dateFormat) {
      case 'MM/dd/yyyy':
        return '$m/$dd/$y';
      case 'dd/MM/yyyy':
        return '$dd/$m/$y';
      case 'yyyy年M月d日':
        return '${d.year}年${d.month}月${d.day}日';
      case 'yyyy-MM-dd':
      default:
        return '$y-$m-$dd';
    }
  }

  Future<void> loadFromStorage() async {
    final p = await SharedPreferences.getInstance();
    _firstDayOfWeek = p.getInt(_kFirstDayOfWeek) ?? 1;
    _dateFormat = p.getString(_kDateFormat) ?? 'yyyy-MM-dd';
    _defaultTab = p.getInt(_kDefaultTab) ?? 0;
    _haptic = p.getBool(_kHapticFeedback) ?? true;
    _showLunar = p.getBool(_kShowLunar) ?? true;
    _showCompletedTodos = p.getBool(_kShowCompletedTodos) ?? false;
    _defaultPomodoroMinutes = p.getInt(_kDefaultPomodoroMinutes) ?? 25;
    _quickCaptureFab = p.getBool(_kQuickCaptureFab) ?? true;
    _autoArchiveCompletedDays = p.getInt(_kAutoArchiveCompletedDays) ?? 0;
    _dailyReminderEnabled = p.getBool(_kDailyReminderEnabled) ?? false;
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
    notifyListeners();
  }

  Future<void> setFirstDayOfWeek(int value) async {
    _firstDayOfWeek = value.clamp(1, 7);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kFirstDayOfWeek, _firstDayOfWeek);
    notifyListeners();
  }

  Future<void> setDateFormat(String format) async {
    _dateFormat = format;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDateFormat, format);
    notifyListeners();
  }

  Future<void> setDefaultTab(int tab) async {
    _defaultTab = tab;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kDefaultTab, tab);
    notifyListeners();
  }

  Future<void> setHaptic(bool value) async {
    _haptic = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kHapticFeedback, value);
    notifyListeners();
  }

  Future<void> setShowLunar(bool value) async {
    _showLunar = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kShowLunar, value);
    notifyListeners();
  }

  Future<void> setShowCompletedTodos(bool value) async {
    _showCompletedTodos = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kShowCompletedTodos, value);
    notifyListeners();
  }

  Future<void> setDefaultPomodoroMinutes(int value) async {
    _defaultPomodoroMinutes = value.clamp(5, 180);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kDefaultPomodoroMinutes, _defaultPomodoroMinutes);
    notifyListeners();
  }

  Future<void> setQuickCaptureFab(bool value) async {
    _quickCaptureFab = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kQuickCaptureFab, value);
    notifyListeners();
  }

  Future<void> setAutoArchiveCompletedDays(int days) async {
    _autoArchiveCompletedDays = days.clamp(0, 365);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kAutoArchiveCompletedDays, _autoArchiveCompletedDays);
    notifyListeners();
  }

  Future<void> setDailyReminderEnabled(bool value) async {
    _dailyReminderEnabled = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDailyReminderEnabled, value);
    notifyListeners();
  }

  Future<void> setDailyReminderTime(int hour, int minute) async {
    _dailyReminderHour = hour.clamp(0, 23);
    _dailyReminderMinute = minute.clamp(0, 59);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kDailyReminderHour, _dailyReminderHour);
    await p.setInt(_kDailyReminderMinute, _dailyReminderMinute);
    notifyListeners();
  }

  Future<void> setDailyReminderIncludeTodayTasks(bool value) async {
    _dailyReminderIncludeTodayTasks = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDailyReminderIncludeTodayTasks, value);
    notifyListeners();
  }

  Future<void> setDailyReminderIncludeTomorrowPlan(bool value) async {
    _dailyReminderIncludeTomorrowPlan = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDailyReminderIncludeTomorrowPlan, value);
    notifyListeners();
  }

  Future<void> setDailyReminderIncludeOverdue(bool value) async {
    _dailyReminderIncludeOverdue = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDailyReminderIncludeOverdue, value);
    notifyListeners();
  }

  Future<void> setDailyReminderRepeatDays(List<int> days) async {
    final normalized = days.where((d) => d >= 1 && d <= 7).toSet().toList()
      ..sort();
    _dailyReminderRepeatDays = normalized.isEmpty
        ? const [1, 2, 3, 4, 5, 6, 7]
        : normalized;
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
      _kDailyReminderRepeatDays,
      _dailyReminderRepeatDays.map((d) => d.toString()).toList(),
    );
    notifyListeners();
  }

  Future<void> setDailyReminderPauseHolidays(bool value) async {
    _dailyReminderPauseHolidays = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDailyReminderPauseHolidays, value);
    notifyListeners();
  }
}
