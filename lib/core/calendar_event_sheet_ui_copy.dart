/// Calendar event sheet and local event editor UI localization copy.
library;

import 'calendar_ui_copy.dart';
import 'i18n.dart';
import 'i18n_date_format.dart';

class CalendarEventSheetUiCopy {
  CalendarEventSheetUiCopy._();

  static bool get isEn => I18n.current == AppLocale.en;
  static bool get isZh => I18n.current == AppLocale.zh;

  // ---------------------------------------------------------------------------
  // Local event editor dialog
  // ---------------------------------------------------------------------------
  static String editorTitle({required bool isEditing}) => isEditing
      ? (isEn ? 'Edit Event' : '编辑日程')
      : (isEn ? 'New Event' : '新建日程');

  static String get eventTitleLabel => isEn ? 'Event title' : '日程标题';
  static String get allDay => isEn ? 'All-day' : '全天';
  static String get allDaySubtitle => isEn
      ? 'Suitable for holidays, trips, birthdays, etc.'
      : '适合假期、出差、生日等跨天安排';
  static String get startDate => isEn ? 'Start date' : '开始日期';
  static String get endDate => isEn ? 'End date' : '结束日期';
  static String get startTime => isEn ? 'Start time' : '开始时间';
  static String get endTime => isEn ? 'End time' : '结束时间';
  static String get noteLabel => isEn ? 'Notes' : '备注';
  static String get cancel => isEn ? 'Cancel' : '取消';
  static String get save => isEn ? 'Save' : '保存';

  // ---------------------------------------------------------------------------
  // CalendarEventSheet action buttons
  // ---------------------------------------------------------------------------
  static String get actionEdit => isEn ? 'Edit' : '编辑';
  static String get actionDelete => isEn ? 'Delete' : '删除';
  static String get actionComplete => isEn ? 'Done' : '完成';
  static String get actionReschedule => isEn ? 'Reschedule' : '改期';
  static String get actionAdjustTime => isEn ? 'Adjust time' : '调整时间';
  static String get actionOpenDetail => isEn ? 'Details' : '跳转详情';
  static String get actionLogOnce => isEn ? 'Log once' : '记录一次';
  static String get actionCheckIn => isEn ? 'Check-in' : '打卡';
  static String get actionStartFocus => isEn ? 'Focus' : '开始专注';
  static String get actionAdjustStart => isEn ? 'Adjust start' : '调整开始';
  static String get actionAdjustDuration => isEn ? 'Adjust duration' : '调整时长';

  // ---------------------------------------------------------------------------
  // Header row & conflict warning
  // ---------------------------------------------------------------------------
  static String conflictWarning(int count) => isEn
      ? '$count other ${count == 1 ? 'event' : 'events'} at the same time'
      : '同一时间段还有 $count 个事项';

  static String allDaySingle(DateTime date) {
    final formatted = I18nDateFormat.monthDay(date);
    return isEn ? '$formatted All-day' : '$formatted 全天';
  }

  static String allDayRange(DateTime start, DateTime end) {
    final startFormatted = I18nDateFormat.monthDay(start);
    final endFormatted = I18nDateFormat.monthDay(end);
    return isEn
        ? '$startFormatted - $endFormatted All-day'
        : '$startFormatted - $endFormatted 全天';
  }

  // ---------------------------------------------------------------------------
  // Secondary pickers & sheets
  // ---------------------------------------------------------------------------
  static String get rescheduleDateTitle => isEn ? 'Reschedule' : '调整日期';

  static String reminderSyncIssue(String issue) => isEn
      ? 'Date saved locally, but reminder was not registered: $issue'
      : '日期已保存到本机，但提醒未注册：$issue';

  static String get adjustDurationTitle => isEn ? 'Adjust duration' : '调整时长';
  static String get adjustDurationSubtitle =>
      isEn ? 'Keep start time, adjust end time quickly' : '保留开始时间，快速调整结束时间';

  static String durationOption(int minutes) =>
      isEn ? '$minutes min' : '$minutes 分钟';

  static String get adjustStartTimeTitle =>
      isEn ? 'Adjust start time' : '调整开始时间';
  static String get adjustStartTimeSubtitle => isEn
      ? 'Keep current date and duration, update end time'
      : '保留当前日期和时长，自动更新结束时间';

  static String get adjustDueTimeTitle => isEn ? 'Adjust time' : '调整时间';
  static String get adjustDueTimeSubtitle =>
      isEn ? 'Keep current date, only adjust due time' : '保留当前日期，只调整当天截止时间';

  static String get todoSavingBusy =>
      isEn ? 'Task is saving, please try again later' : '待办正在保存中，请稍后重试';

  static String todoReminderSyncIssue(String issue) => isEn
      ? 'Task saved, but reminder not registered: $issue'
      : '待办已保存，但提醒未注册：$issue';

  static String todoSaveFailed(Object error) =>
      isEn ? 'Failed to save task: $error' : '待办保存失败：$error';

  // ---------------------------------------------------------------------------
  // Detail and feedback labels
  // ---------------------------------------------------------------------------
  static String get emptyDescription => isEn ? 'No details' : '暂无详细描述';
  static String get sourceLabel => isEn ? 'Source' : '来源';
  static String get detailsLabel => isEn ? 'Details' : '详情';
  static String get deleteSuccess => isEn ? 'Deleted' : '已删除';
  static String get deleteFailed => isEn ? 'Delete failed' : '删除失败';
  static String get saveFailed => CalendarUiCopy.saveFailed;
  static String get emptyNote => isEn ? 'No notes' : '暂无备注';
  static String itemCount(int count) =>
      isEn ? '$count ${count == 1 ? 'item' : 'items'}' : '$count 项';
  static String get actionCompleteFailed => isEn ? 'Completion failed' : '完成失败';
  static String get actionCheckInFailed => isEn ? 'Check-in failed' : '打卡失败';
}
