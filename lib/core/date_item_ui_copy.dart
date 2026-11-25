import '../models/countdown.dart';
import 'i18n.dart';

enum DateItemReminderIssue { serviceUnavailable, registrationFailed }

class DateItemUiCopy {
  DateItemUiCopy._();

  static String _pick(String zh, String en) =>
      I18n.current == AppLocale.zh ? zh : en;
  static String get saving => _pick('正在保存…', 'Saving…');
  static String countdownCategory(CountdownItem item) => item.categoryIsDefault
      ? I18n.tr('countdown.category.default')
      : item.category;
  static String get resetCategory => _pick('恢复默认分类', 'Use default category');
  static String get saveFailed => _pick(
    '未能保存，更改已保留，请重试。',
    'Could not save. Your changes are still here. Please retry.',
  );
  static String get deleteFailed => _pick(
    '未能删除，内容已保留，请重试。',
    'Could not delete. The item is still here. Please retry.',
  );
  static String get pinFailed =>
      _pick('未能更新置顶状态，请重试。', 'Could not update pinning. Please retry.');
  static String get savedReminderWarning => _pick(
    '已保存到本机，但提醒未注册。请检查提醒设置后重试。',
    'Saved on this device, but the reminder was not registered. Check reminder settings and retry.',
  );

  static String reminderIssue(
    DateItemReminderIssue issue, {
    required bool anniversary,
  }) => switch (issue) {
    DateItemReminderIssue.serviceUnavailable => _pick(
      '提醒服务未初始化，未能注册${anniversary ? '纪念日' : '倒数日'}提醒。请重启应用或重新打开提醒设置后再保存。',
      'The reminder service is unavailable. Restart the app or reopen reminder settings, then save the ${anniversary ? 'anniversary' : 'countdown'} again.',
    ),
    DateItemReminderIssue.registrationFailed => _pick(
      '${anniversary ? '纪念日' : '倒数日'}提醒注册失败：请检查通知权限、提醒方式和提醒时间后重新保存。',
      'The ${anniversary ? 'anniversary' : 'countdown'} reminder could not be registered. Check notification permission, reminder type and time, then save again.',
    ),
  };
}
