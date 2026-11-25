/// Calendar UI localization copy (Task: calendar content locale).
library;

import 'i18n.dart';
import 'i18n_date_format.dart';

class CalendarUiCopy {
  CalendarUiCopy._();

  static bool get isEn => I18n.current == AppLocale.en;
  static bool get isZh => I18n.current == AppLocale.zh;

  // ---------------------------------------------------------------------------
  // Tabs & Navigation
  // ---------------------------------------------------------------------------
  static String get tabThreeDay => isEn ? '3-Day' : '三日';
  static String get tabYear => isEn ? 'Year' : '年';

  static String yearHeader(int year) => isEn ? '$year' : '$year 年';

  static String monthHeader(DateTime date) => I18nDateFormat.yearMonth(date);

  // ---------------------------------------------------------------------------
  // Filter strip & Options
  // ---------------------------------------------------------------------------
  static String get filterAll => isEn ? 'All' : '全部';
  static String get filterAllProjects => isEn ? 'All projects' : '全部项目';
  static String get filterAllWorkspaces => isEn ? 'All spaces' : '全部空间';
  static String get projectDetailAction => isEn ? 'Project details' : '项目详情';
  static String get ungroupedProject => isEn ? 'Ungrouped' : '未分组';
  static String get personalWorkspace => isEn ? 'Personal space' : '个人空间';
  static String get sharedWorkspace => isEn ? 'Shared space' : '共享空间';

  // ---------------------------------------------------------------------------
  // Tooltips & Actions
  // ---------------------------------------------------------------------------
  static String get quickAddTooltip => isEn ? 'Add to calendar' : '添加到日历';

  // ---------------------------------------------------------------------------
  // Quick add menu
  // ---------------------------------------------------------------------------
  static String get quickAddMenuTitle => isEn ? 'Create' : '新建';
  static String get quickAddMenuSubtitle =>
      isEn ? 'Choose what to add to calendar' : '选择要添加到日历的内容';
  static String get quickAddAiScheduleTitle =>
      isEn ? 'AI schedule creation' : 'AI 创建日程';
  static String get quickAddAiScheduleSubtitle => isEn
      ? 'Recognize natural language and create events or tasks'
      : '识别自然语言，确认后写入日程或待办';
  static String get quickAddNewEventTitle => isEn ? 'New event' : '新建日程';
  static String get quickAddNewEventSubtitle =>
      isEn ? 'Supports all-day and multi-day events' : '支持全天和多日安排';
  static String get quickAddNewTodoTitle => isEn ? 'New task' : '新建待办';
  static String get quickAddTimeEntryTitle => isEn ? 'Log time' : '记录一段时间';

  // ---------------------------------------------------------------------------
  // Quick add todo dialog
  // ---------------------------------------------------------------------------
  static String quickAddTodoDialogTitle(String brandTitle, DateTime date) {
    return '$brandTitle - ${I18nDateFormat.monthDay(date)}';
  }

  static String get todoTitleLabel => isEn ? 'Task title' : '任务名称';

  // ---------------------------------------------------------------------------
  // Quick add time entry dialog
  // ---------------------------------------------------------------------------
  static String quickAddTimeEntryDialogTitle(DateTime date) {
    return isEn
        ? 'Log time - ${I18nDateFormat.monthDay(date)}'
        : '记录时间 - ${date.month}月${date.day}日';
  }

  static String get timeEntryTitleLabel => isEn ? 'Title' : '事项';
  static String get timeEntryCategoryLabel => isEn ? 'Category' : '分类';
  static String get timeEntryStartTimeLabel => isEn ? 'Start time' : '开始时间';
  static String get timeEntryDurationLabel =>
      isEn ? 'Duration (minutes)' : '时长（分钟）';
  static String get timeEntryNoteLabel => isEn ? 'Notes' : '备注';
  static String get timeEntrySubmitButton => isEn ? 'Log' : '记录';

  // ---------------------------------------------------------------------------
  // Project detail sheet
  // ---------------------------------------------------------------------------
  static String get projectDetailSheetTitle =>
      isEn ? 'Project details' : '项目详情';
  static String get projectStatTotal => isEn ? 'Total' : '总数';
  static String get projectStatCompleted => isEn ? 'Done' : '完成';
  static String get projectStatOverdue => isEn ? 'Overdue' : '逾期';
  static String get projectStatToday => isEn ? 'Today' : '今日';
  static String get projectEmptyTasks =>
      isEn ? 'No tasks in this project' : '这个项目暂无任务';
  static String get openTodoScreenButton => isEn ? 'Open Tasks' : '打开待办';

  // ---------------------------------------------------------------------------
  // 3-Day lane
  // ---------------------------------------------------------------------------
  static String threeDayLaneHeader(DateTime date) {
    if (isEn) {
      return '${I18nDateFormat.monthDay(date)} · ${_enWeekdayShort(date.weekday)}';
    }
    return '${date.month}月${date.day}日 周${_weekdayLabel(date.weekday)}';
  }

  static String laneItemCount(int count) {
    if (isEn) {
      return '$count ${count == 1 ? 'item' : 'items'}';
    }
    return '$count 项';
  }

  // ---------------------------------------------------------------------------
  // Year overview
  // ---------------------------------------------------------------------------
  static String yearMonthTitle(int month) {
    if (isEn) {
      return _enMonth(month);
    }
    return '$month 月';
  }

  static String yearMonthEventCount(int count) {
    if (isEn) {
      return count == 0
          ? 'No events this month'
          : '$count ${count == 1 ? 'event' : 'events'}';
    }
    return count == 0 ? '本月暂无事项' : '$count 个事项';
  }

  // ---------------------------------------------------------------------------
  // Feedback
  // ---------------------------------------------------------------------------
  static String get saveFailed => isEn ? 'Save failed' : '保存失败';

  // ---------------------------------------------------------------------------
  // Private date helpers
  // ---------------------------------------------------------------------------
  static String get unavailable => isEn ? 'Unavailable' : '不可用';
  static String get lunarUnavailable =>
      isEn ? 'Lunar unavailable' : '农历不可用';

  static String _weekdayLabel(int weekday) {
    return switch (weekday) {
      DateTime.monday => '一',
      DateTime.tuesday => '二',
      DateTime.wednesday => '三',
      DateTime.thursday => '四',
      DateTime.friday => '五',
      DateTime.saturday => '六',
      DateTime.sunday => '日',
      _ => '',
    };
  }

  static String _enWeekdayShort(int weekday) {
    return switch (weekday) {
      DateTime.monday => 'Mon',
      DateTime.tuesday => 'Tue',
      DateTime.wednesday => 'Wed',
      DateTime.thursday => 'Thu',
      DateTime.friday => 'Fri',
      DateTime.saturday => 'Sat',
      DateTime.sunday => 'Sun',
      _ => '',
    };
  }

  static String _enMonth(int month) => switch (month) {
    1 => 'Jan',
    2 => 'Feb',
    3 => 'Mar',
    4 => 'Apr',
    5 => 'May',
    6 => 'Jun',
    7 => 'Jul',
    8 => 'Aug',
    9 => 'Sep',
    10 => 'Oct',
    11 => 'Nov',
    12 => 'Dec',
    _ => '',
  };
}
