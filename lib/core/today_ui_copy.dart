/// Today screen UI localization copy (Task: Today i18n).
library;

import 'i18n.dart';

class TodayUiCopy {
  TodayUiCopy._();

  static bool get isEn => I18n.current == AppLocale.en;
  static bool get isZh => I18n.current == AppLocale.zh;

  // ---------------------------------------------------------------------------
  // Quick Access Panel (快捷入口)
  // ---------------------------------------------------------------------------
  static String get quickAccessTitle => isEn ? 'Quick Access' : '快捷入口';
  static String get quickAccessHabit => isEn ? 'Habit check-in' : '习惯打卡';
  static String get quickAccessPomodoro => isEn ? 'Pomodoro focus' : '番茄专注';
  static String get quickAccessNotes => isEn ? 'Quick note' : '快速笔记';
  static String get quickAccessCalendar => isEn ? 'Schedule' : '日程安排';

  // ---------------------------------------------------------------------------
  // Date Badge (月份徽章)
  // ---------------------------------------------------------------------------
  static String monthBadge(DateTime date, [AppLocale? locale]) {
    final current = locale ?? I18n.current;
    if (current == AppLocale.zh) {
      return '${date.month}月';
    }
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[(date.month - 1).clamp(0, 11)];
  }

  // ---------------------------------------------------------------------------
  // Almanac / Huangli Labels (黄历宜忌标签)
  // ---------------------------------------------------------------------------
  static String get auspiciousLabel => isEn ? 'Fit' : '宜';
  static String get inauspiciousLabel => isEn ? 'Avoid' : '忌';

  // ---------------------------------------------------------------------------
  // Task Semantics & Actions (任务无障碍语义与操作)
  // ---------------------------------------------------------------------------
  static String get markAsIncomplete => isEn ? 'Mark as incomplete' : '标记为未完成';
  static String get markAsComplete => isEn ? 'Mark as complete' : '标记为完成';

  // ---------------------------------------------------------------------------
  // Read-only message feedback (只读消息反馈)
  // ---------------------------------------------------------------------------
  static String readOnlyActionMessage(String action, [AppLocale? locale]) {
    final current = locale ?? I18n.current;
    if (current == AppLocale.zh) {
      return '共享空间只读，不能$action';
    }
    if (action == '完成任务') {
      return 'Shared space is read-only; cannot complete tasks';
    }
    if (action == '删除任务') {
      return 'Shared space is read-only; cannot delete tasks';
    }
    return 'Shared space is read-only; cannot $action';
  }

  // ---------------------------------------------------------------------------
  // Delete confirmation dialog (删除确认弹窗)
  // ---------------------------------------------------------------------------
  static String deleteTaskTitle([AppLocale? locale]) {
    final current = locale ?? I18n.current;
    return current == AppLocale.en ? 'Delete task?' : '删除任务？';
  }

  static String deleteTaskContent(String taskTitle, [AppLocale? locale]) {
    final current = locale ?? I18n.current;
    return current == AppLocale.en
        ? 'Delete "$taskTitle"? Associated time entries will also be removed.'
        : '将删除“$taskTitle”，相关时间足迹也会同步移除。';
  }

  // ---------------------------------------------------------------------------
  // Reminders section (提醒前缀、摘要、分组、数量、逾期、默认收起)
  // ---------------------------------------------------------------------------
  static String get reminderPrefixPast => isEn ? 'Reminder time' : '提醒时间';
  static String get reminderPrefixToday => isEn ? 'Today' : '今日提醒';
  static String get reminderPrefixUpcoming => isEn ? 'Upcoming' : '即将开始';

  static String get reminderHeaderTitle => isEn ? 'Today Reminders' : '今日提醒';
  static String get collapsedByDefault =>
      isEn ? 'Collapsed by default' : '默认收起';

  static String reminderSectionSubtitle({
    required int total,
    required bool hasSuggestions,
    AppLocale? locale,
  }) {
    final current = locale ?? I18n.current;
    if (current == AppLocale.zh) {
      return hasSuggestions
          ? '$total 项提醒 · 今日待提醒 > 即将开始 > 逾期优先处理 > 今日建议'
          : '$total 项 · 今日待提醒 > 即将开始 > 逾期优先处理';
    }
    return hasSuggestions
        ? '$total reminders · Due today > Starting soon > Overdue prioritized > Suggestions'
        : '$total items · Due today > Starting soon > Overdue prioritized';
  }

  static String get reminderGroupDueToday => isEn ? 'Due today' : '今日待提醒事项';
  static String get reminderGroupUpcoming => isEn ? 'Starting soon' : '即将开始事项';
  static String get reminderGroupOverdue => isEn ? 'Overdue' : '已逾期事项';

  static String itemCount(int count, [AppLocale? locale]) {
    final current = locale ?? I18n.current;
    if (current == AppLocale.zh) {
      return '$count 项';
    }
    return count == 1 ? '1 item' : '$count items';
  }

  static String pastStatusMinutes({
    required int minutes,
    required bool isCourse,
    AppLocale? locale,
  }) {
    final current = locale ?? I18n.current;
    if (current == AppLocale.zh) {
      return isCourse ? '已过期 $minutes 分钟' : '已过提醒 $minutes 分钟';
    }
    return isCourse ? '$minutes min past' : '$minutes min past reminder';
  }

  static String pastStatusDays(int days, [AppLocale? locale]) {
    final current = locale ?? I18n.current;
    if (current == AppLocale.zh) {
      return '已逾期 $days 天';
    }
    return '$days d overdue';
  }

  // ---------------------------------------------------------------------------
  // Smart schedule suggestion reasons (今日建议推荐理由)
  // ---------------------------------------------------------------------------
  static const Map<String, String> _suggestionReasonsEn = {
    '已逾期': 'Overdue',
    '3 小时内到期': 'Due within 3 hours',
    '今天到期': 'Due today',
    '明天到期': 'Due tomorrow',
    '计划今天处理': 'Scheduled for today',
    '计划日期已过': 'Past scheduled date',
    '明天计划': 'Scheduled for tomorrow',
    '紧急优先级': 'Urgent priority',
    '高优先级': 'High priority',
    '重要且紧急': 'Important & urgent',
    '重要任务': 'Important task',
  };

  static String formatSuggestionReason(String rawReason, [AppLocale? locale]) {
    final current = locale ?? I18n.current;
    if (current == AppLocale.zh) {
      return rawReason;
    }
    final trimmed = rawReason.trim();
    if (trimmed.isEmpty) return '';
    final tokens = trimmed.split(' · ');
    final localized = tokens.map((token) {
      final t = token.trim();
      return _suggestionReasonsEn[t] ?? t;
    });
    return localized.join(' · ');
  }
}
