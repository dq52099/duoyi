/// Calendar day agenda and month grid UI localization copy.
library;

import 'i18n.dart';
import 'calendar_date_navigation.dart';
import 'i18n_date_format.dart';
import 'main_ui_copy.dart';

class CalendarAgendaUiCopy {
  CalendarAgendaUiCopy._();

  static bool get isEn => I18n.current == AppLocale.en;
  static bool get isZh => I18n.current == AppLocale.zh;

  // ---------------------------------------------------------------------------
  // Weekday initials & month grid
  // ---------------------------------------------------------------------------
  static List<String> get weekdayInitials => isEn
      ? const ['M', 'T', 'W', 'T', 'F', 'S', 'S']
      : const ['一', '二', '三', '四', '五', '六', '日'];

  static List<String> weekdayInitialsFor(int firstDayOfWeek) => [
    for (final weekday in CalendarDateNavigation.orderedWeekdays(
      firstDayOfWeek,
    ))
      weekdayInitials[weekday - 1],
  ];

  static String monthEventBadge(int count) =>
      isEn ? '$count ${count == 1 ? 'item' : 'items'}' : '$count项';

  static String daySemanticLabel(
    DateTime date, {
    required bool isToday,
    required bool isSelected,
    required int eventCount,
    required String? subText,
    String? pattern,
  }) {
    if (isEn) {
      final parts = <String>[
        I18nDateFormat.date(date, pattern: pattern),
        if (isToday) 'Today',
        if (isSelected) 'Selected',
        if (subText != null && subText.isNotEmpty) subText,
        eventCount > 0
            ? '$eventCount ${eventCount == 1 ? 'event' : 'events'}'
            : 'No events',
      ];
      return parts.join(', ');
    }
    final parts = <String>[
      I18nDateFormat.date(date, pattern: pattern),
      if (isToday) '今天',
      if (isSelected) '已选中',
      if (subText != null && subText.isNotEmpty) subText,
      eventCount > 0 ? '$eventCount 个事项' : '无事项',
    ];
    return parts.join('，');
  }

  // ---------------------------------------------------------------------------
  // Agenda Section Headers & Badges
  // ---------------------------------------------------------------------------
  static String get anniversarySectionTitle =>
      isEn ? '🎉 Today\'s Anniversaries' : '🎉 今日纪念';

  static String anniversaryCount(int count) =>
      isEn ? 'Time #$count' : '第 $count 次';

  static String get courseSectionTitle =>
      isEn ? '📚 Today\'s Courses' : '📚 今日课程';

  static bool _isToday(DateTime date) {
    final today = DateTime.now();
    return date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
  }

  static String anniversarySectionTitleForDate(DateTime date) => _isToday(date)
      ? anniversarySectionTitle
      : isEn
      ? '🎉 Anniversaries on this day'
      : '🎉 当日纪念';

  static String courseSectionTitleForDate(DateTime date) => _isToday(date)
      ? courseSectionTitle
      : isEn
      ? '📚 Courses on this day'
      : '📚 当日课程';

  static String coursePeriod(int startSection, int endSection) {
    if (isEn) {
      return startSection == endSection
          ? 'Period $startSection'
          : 'Period $startSection-$endSection';
    }
    return startSection == endSection
        ? '第$startSection节'
        : '第$startSection-$endSection节';
  }

  static String get timelineSectionTitle => isEn ? '🕘 Timeline' : '🕘 时间线';

  static String get allDaySectionTitle =>
      isEn ? '📝 All-day / Untimed' : '📝 全天/无时间';

  // ---------------------------------------------------------------------------
  // Overflow and Tooltips
  // ---------------------------------------------------------------------------
  static String overflowNotice(int hiddenCount) => isEn
      ? '$hiddenCount more ${hiddenCount == 1 ? 'item' : 'items'}, switch to Day view for full schedule'
      : '还有 $hiddenCount 项，请切换到日视图查看完整日程';

  static String get timeConflictTooltip => isEn ? 'Time conflict' : '时间冲突';

  // ---------------------------------------------------------------------------
  // Status Badges (completed / overdue)
  // ---------------------------------------------------------------------------
  static String get statusCompleted => MainUiCopy.calendarStatusCompleted;
  static String get statusOverdue => MainUiCopy.calendarStatusOverdue;

  // ---------------------------------------------------------------------------
  // Drag adjustments feedback
  // ---------------------------------------------------------------------------
  static String get dragTaskSavingBusy =>
      isEn ? 'Task is saving, please try again later' : '待办正在保存中，请稍后重试';

  static String dragReminderWarning(String formattedTime, String issue) => isEn
      ? 'Adjusted to $formattedTime, but reminder was not registered: $issue'
      : '已调整到 $formattedTime，但提醒未注册：$issue';

  static String dragTaskSaveFailed(Object error) =>
      isEn ? 'Failed to save task: $error' : '待办保存失败：$error';

  static String dragAdjustSuccess(String formattedTime) =>
      isEn ? 'Adjusted to $formattedTime' : '已调整到 $formattedTime';

  // ---------------------------------------------------------------------------
  // Diary Quick Entry
  // ---------------------------------------------------------------------------
  static String get emptyDiaryPrompt =>
      isEn ? 'Write a diary entry for this day' : '写下这一天的日记';
}
