import '../core/i18n.dart';

enum TodoReminderPreflightNotice {
  missingDate,
  timeInPast,
  invalidRepeatTime,
  invalidWeeklyRule,
  noDeliverableRule,
}

/// App-owned preflight copy. It carries no permission or blocking decision.
final class TodoReminderPreflightCopy {
  const TodoReminderPreflightCopy(this.notice);

  final TodoReminderPreflightNotice notice;

  String title({AppLocale? locale}) {
    final isZh = (locale ?? I18n.current) == AppLocale.zh;
    return switch (notice) {
      TodoReminderPreflightNotice.invalidRepeatTime =>
        isZh ? '重复提醒注册失败' : 'Repeating reminder not registered',
      TodoReminderPreflightNotice.invalidWeeklyRule =>
        isZh ? '每周提醒注册失败' : 'Weekly reminder not registered',
      _ => isZh ? '待办提醒注册失败' : 'Task reminder not registered',
    };
  }

  String message({AppLocale? locale}) {
    final isZh = (locale ?? I18n.current) == AppLocale.zh;
    return switch (notice) {
      TodoReminderPreflightNotice.missingDate =>
        isZh
            ? '一次性提醒需要截止日期或提醒日期。请先设置未来的日期。'
            : 'A one-time reminder needs a due date or reminder date. Set a future date first.',
      TodoReminderPreflightNotice.timeInPast =>
        isZh
            ? '提醒时间已过去，未注册到系统通知。请把提醒时间改到未来时间。'
            : 'The reminder time has passed and no system notification was registered. Choose a future time.',
      TodoReminderPreflightNotice.invalidRepeatTime =>
        isZh
            ? '重复提醒缺少有效时间，请重新选择提醒时间。'
            : 'The repeating reminder needs a valid time. Select the reminder time again.',
      TodoReminderPreflightNotice.invalidWeeklyRule =>
        isZh
            ? '每周提醒需要有效时间和至少一个星期。请重新选择提醒规则。'
            : 'A weekly reminder needs a valid time and at least one weekday. Select the reminder rule again.',
      TodoReminderPreflightNotice.noDeliverableRule =>
        isZh
            ? '提醒计划没有可注册的规则，请重新设置提醒。'
            : 'The reminder plan has no rules that can be registered. Set up the reminder again.',
    };
  }
}
