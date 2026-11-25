import '../models/goal.dart';
import '../models/recurrence.dart';
import 'i18n.dart';
import 'i18n_date_format.dart';

/// Presentation only: recommendation payloads keep their stored values.
abstract final class RecommendedGoalsUiCopy {
  static bool get _en => I18n.current == AppLocale.en;
  static String get title => _en ? 'Recommended goals' : '推荐目标';
  static String get add => _en ? 'Add to goals' : '添加到目标列表';
  static String get adding => _en ? 'Adding…' : '正在添加…';
  static String get saved => _en ? 'Added to your goals' : '已添加到目标列表';
  static String get view => _en ? 'View' : '查看';
  static String get saveFailed =>
      _en ? 'Could not add goal. Try again.' : '添加失败，请重试';
  static String get expired => _en
      ? 'Page state changed. Return and reopen this page.'
      : '页面状态已变更，请返回后重新打开';
  static String get back => _en ? 'Back to goals' : '返回目标列表';
  static String get skipHolidays => _en ? 'Skip holidays' : '跳过节假日';
  static String get selectTargetDate => _en ? 'Select target date' : '选择目标日期';
  static String get datePickerTitle => selectTargetDate;

  static String category(GoalCategory category) => switch (category) {
    GoalCategory.recommend => _en ? 'Recommended' : '推荐',
    GoalCategory.health => _en ? 'Health' : '健康',
    GoalCategory.study => _en ? 'Study' : '学习',
    GoalCategory.sport => _en ? 'Exercise' : '运动',
    GoalCategory.emotion => _en ? 'Wellbeing' : '情感',
    GoalCategory.custom => _en ? 'Custom' : '自定义',
  };

  static String empty(GoalCategory value) => _en
      ? 'No recommended goals in ${category(value)} yet'
      : '「${category(value)}」暂无推荐条目';

  static String recurrence(RecurrenceRule rule, GoalScheduling scheduling) {
    final n = rule.interval;
    final base = switch (rule.frequency) {
      RecurrenceFrequency.none => _en ? 'Does not repeat' : '不重复',
      RecurrenceFrequency.daily =>
        _en
            ? (n == 1 ? 'Every day' : 'Every $n days')
            : (n == 1 ? '每天' : '每 $n 天'),
      RecurrenceFrequency.weekly =>
        _en
            ? (n == 1 ? 'Every week' : 'Every $n weeks')
            : (n == 1 ? '每周' : '每 $n 周'),
      RecurrenceFrequency.monthly =>
        _en
            ? (n == 1 ? 'Every month' : 'Every $n months')
            : (n == 1 ? '每月' : '每 $n 月'),
      RecurrenceFrequency.yearly =>
        _en
            ? (n == 1 ? 'Every year' : 'Every $n years')
            : (n == 1 ? '每年' : '每 $n 年'),
    };
    if (scheduling.mode == SchedulingMode.fixed) {
      if (rule.frequency == RecurrenceFrequency.weekly &&
          (scheduling.fixedWeekdays?.isNotEmpty ?? false)) {
        final names = _en
            ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
            : const ['一', '二', '三', '四', '五', '六', '日'];
        final days = ([...scheduling.fixedWeekdays!]..sort())
            .where((day) => day >= 0 && day < 7)
            .map((day) => names[day])
            .join('/');
        if (days.isNotEmpty) return '$base · ${_en ? days : '周$days'}';
      }
      if (rule.frequency == RecurrenceFrequency.monthly &&
          (scheduling.fixedMonthDays?.isNotEmpty ?? false)) {
        final days = ([...scheduling.fixedMonthDays!]..sort()).join('/');
        return _en ? '$base · Days $days' : '$base · $days 日';
      }
      return base;
    }
    final week = scheduling.randomMaxPerWeek;
    if (week != null) {
      return _en
          ? '$base · Random, up to $week/week'
          : '$base · 随机每周最多 $week 次';
    }
    final month = scheduling.randomMaxPerMonth;
    if (month != null) {
      return _en
          ? '$base · Random, up to $month/month'
          : '$base · 随机每月最多 $month 次';
    }
    final gap = scheduling.randomMinGapDays;
    if (gap != null) {
      return _en
          ? '$base · Random, ≥$gap days apart'
          : '$base · 随机，间隔至少 $gap 天';
    }
    return '$base · ${_en ? 'Random' : '随机'}';
  }

  static String duration(int seconds) {
    if (seconds <= 0) return '0s';
    final hours = seconds ~/ 3600;
    final minutes = seconds % 3600 ~/ 60;
    if (hours > 0 && minutes > 0) return '${hours}h ${minutes}min';
    if (hours > 0) return '${hours}h';
    if (minutes > 0) return '${minutes}min';
    return '${seconds % 60}s';
  }

  static String focus(int? seconds) {
    final label = _en ? 'Focus' : '专注';
    return seconds == null || seconds <= 0
        ? label
        : '$label ${duration(seconds)}';
  }

  static String reminder(ReminderConfig reminder) {
    final prefix = switch (reminder.kind) {
      ReminderKind.alarm => _en ? 'Alarm' : '闹钟',
      ReminderKind.popup => _en ? 'Popup' : '弹出框',
      ReminderKind.push => _en ? 'Notification' : '通知',
      ReminderKind.email => _en ? 'Email' : '邮件',
      ReminderKind.off => _en ? 'Off' : '关闭',
    };
    final hour = reminder.hour;
    final minute = reminder.minute;
    return hour == null || minute == null
        ? prefix
        : '$prefix ${I18nDateFormat.timeOfDay(hour: hour, minute: minute)}';
  }
}
