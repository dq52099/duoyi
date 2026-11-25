import '../core/i18n.dart';
import '../models/goal.dart' show ReminderKind;
import 'todo_reminder_preflight_copy.dart';

enum NotificationIssueTitle {
  initializationFailed('提醒注册初始化失败', 'Reminder service could not start'),
  registrationFailed('提醒注册失败', 'Reminder not registered'),
  repeatingRegistrationFailed('重复提醒注册失败', 'Repeating reminder not registered'),
  taskRegistrationFailed('待办提醒注册失败', 'Task reminder not registered'),
  habitRegistrationFailed('习惯提醒注册失败', 'Habit reminder not registered'),
  anniversaryRegistrationFailed(
    '纪念日提醒注册失败',
    'Anniversary reminder not registered',
  ),
  aiRegistrationFailed('AI 日程提醒注册失败', 'AI schedule reminder not registered'),
  snoozeRegistrationFailed('稍后提醒注册失败', 'Snoozed reminder not registered'),
  snoozeWarning('稍后提醒注册异常', 'Check snoozed reminder'),
  sendFailed('通知发送失败', 'Notification not sent'),
  testWarning('普通通知测试异常', 'Check notification test'),
  scheduledTestFailed(
    '定时通知测试注册失败',
    'Scheduled notification test not registered',
  ),
  popupTestFailed('定时弹出测试注册失败', 'Scheduled pop-up test not registered'),
  alarmTestFailed('定时闹钟测试注册失败', 'Scheduled alarm test not registered'),
  alarmDegraded('闹钟提醒已降级为普通通知', 'Alarm now uses a regular notification'),
  dailyRegistrationFailed('每日提醒注册失败', 'Daily reminder not scheduled'),
  dailyFallback('每日提醒已退回普通通知', 'Daily reminder uses a regular notification'),
  dailyAlarmUnconfirmed('每日闹钟注册状态未确认', 'Daily alarm registration unconfirmed'),
  registrationDegraded('提醒注册降级', 'Reminder fallback'),
  repeatingRegistrationDegraded('重复提醒注册降级', 'Repeating reminder fallback');

  const NotificationIssueTitle(this.zh, this.en);
  final String zh;
  final String en;

  String render({AppLocale? locale}) =>
      (locale ?? I18n.current) == AppLocale.zh ? zh : en;

  String renderCheckTitle({required AppLocale locale}) {
    final isZh = locale == AppLocale.zh;
    return switch (this) {
      NotificationIssueTitle.registrationFailed =>
        isZh ? '提醒状态需检查' : 'Check reminder status',
      NotificationIssueTitle.repeatingRegistrationFailed =>
        isZh ? '重复提醒状态需检查' : 'Check repeating reminder',
      NotificationIssueTitle.taskRegistrationFailed =>
        isZh ? '待办提醒状态需检查' : 'Check task reminder',
      NotificationIssueTitle.habitRegistrationFailed =>
        isZh ? '习惯提醒状态需检查' : 'Check habit reminder',
      NotificationIssueTitle.anniversaryRegistrationFailed =>
        isZh ? '纪念日提醒状态需检查' : 'Check anniversary reminder',
      NotificationIssueTitle.aiRegistrationFailed =>
        isZh ? 'AI 日程提醒状态需检查' : 'Check AI schedule reminder',
      NotificationIssueTitle.snoozeRegistrationFailed =>
        isZh ? '稍后提醒状态需检查' : 'Check snoozed reminder',
      NotificationIssueTitle.scheduledTestFailed =>
        isZh ? '定时通知测试状态需检查' : 'Check scheduled notification test',
      _ => render(locale: locale),
    };
  }
}

enum NotificationIssueNotice {
  initializationFailed,
  channelUnknown,
  channelBlocked,
  channelSilent,
  channelProbeFailed,
  timePassed,
  oncePermissionUnconfirmed,
  oncePermissionDenied,
  onceScheduleFailed,
  repeatPermissionUnconfirmed,
  repeatPermissionDenied,
  repeatScheduleFailed,
  alarmDegraded,
  sendFailed,
  sendPermissionDenied,
  snoozeCancelFailed,
  testPermissionUnconfirmed,
  testPermissionDenied,
  testSendFailed,
  inAppPopupUnavailable,
  popupFallbackUnavailable,
  inAppPopupFailed,
  popupFallbackFailed,
  alarmUnavailable,
  alarmScheduleFailed,
  dailyCancellationFailed,
  dailyScheduleFailed,
  dailyChannelFallback,
  dailyAlarmHandoffFailed,
  dailyAlarmQueueUnconfirmed,
}

/// Presentation metadata; raw diagnostics, severity and scheduling stay separate.
final class ReminderIssueCopy {
  const ReminderIssueCopy.notification(
    this.notice, {
    this.titleCode,
    this.detail,
    this.label = '',
    this.labelCode,
    this.requestedKind,
  }) : preflight = null;

  const ReminderIssueCopy.preflight(this.preflight)
    : notice = null,
      titleCode = null,
      detail = null,
      label = '',
      labelCode = null,
      requestedKind = null;

  final NotificationIssueNotice? notice;
  final NotificationIssueTitle? titleCode;
  final String? detail;
  final String label;
  final NotificationIssueTitle? labelCode;
  final ReminderKind? requestedKind;
  final TodoReminderPreflightCopy? preflight;

  String renderTitle({required String fallback, AppLocale? locale}) {
    final selectedLocale = locale ?? I18n.current;
    if (preflight != null) return preflight!.title(locale: selectedLocale);
    final needsCheckTitle = switch (notice) {
      NotificationIssueNotice.channelUnknown ||
      NotificationIssueNotice.channelBlocked ||
      NotificationIssueNotice.channelSilent ||
      NotificationIssueNotice.channelProbeFailed ||
      NotificationIssueNotice.oncePermissionUnconfirmed ||
      NotificationIssueNotice.repeatPermissionUnconfirmed => true,
      _ => false,
    };
    if (needsCheckTitle && titleCode != null) {
      return titleCode!.renderCheckTitle(locale: selectedLocale);
    }
    return titleCode?.render(locale: selectedLocale) ?? fallback;
  }

  String renderMessage({required String fallback, AppLocale? locale}) {
    final selectedLocale = locale ?? I18n.current;
    if (preflight != null) return preflight!.message(locale: selectedLocale);
    final isZh = selectedLocale == AppLocale.zh;
    String pick(String zh, String en) => isZh ? zh : en;
    final reasonLabel = labelCode?.render(locale: selectedLocale) ?? label;
    final requestedChannel = switch (requestedKind) {
      ReminderKind.popup => pick('弹出框', 'pop-up'),
      ReminderKind.alarm => pick('锁屏闹钟', 'lock-screen alarm'),
      ReminderKind.push => pick('普通通知', 'regular notification'),
      ReminderKind.email => pick('邮件', 'email'),
      _ => pick('所选通道', 'selected channel'),
    };
    final text = switch (notice) {
      NotificationIssueNotice.dailyCancellationFailed => pick(
        '旧提醒取消不完整，已暂停本次重新注册以避免重复提醒。请稍后重试，或重启应用后重新保存提醒。',
        'Some previous reminders could not be canceled. Rescheduling was paused to avoid duplicates. Retry later, or restart the app and save the reminder again.',
      ),
      NotificationIssueNotice.dailyScheduleFailed => pick(
        '系统调度失败，提醒未确认注册成功。请检查通知、精准闹钟和后台运行权限后重新保存提醒。',
        'Scheduling failed and reminder registration is unconfirmed. Check notification, exact alarm and background permissions, then save the reminder again.',
      ),
      NotificationIssueNotice.dailyChannelFallback => pick(
        '你选择的是$requestedChannel提醒，但该通道没有确认注册成功，已改用普通通知兜底；到点不会按$requestedChannel形式弹出。请在已注册提醒详情确认状态，检查通知、精准闹钟、全屏提醒和后台限制后重新保存。',
        'The $requestedChannel reminder was not confirmed, so it now uses a regular notification. It will not appear as a $requestedChannel when due. Review its registration details and notification, exact alarm, full-screen and background permissions, then save it again.',
      ),
      NotificationIssueNotice.dailyAlarmHandoffFailed => pick(
        '闹钟提醒交接失败，已跳过普通通知兜底以避免重复提醒。请在已注册提醒中确认，或重新保存该提醒。',
        'Alarm handoff failed. The regular notification fallback was skipped to avoid duplicates. Check registered reminders, or save this reminder again.',
      ),
      NotificationIssueNotice.dailyAlarmQueueUnconfirmed => pick(
        '闹钟待触发队列读取失败，无法确认锁屏闹钟是否已注册；为避免重复提醒已跳过普通通知兜底。请在系统权限正常后重新保存提醒。',
        'The pending alarm queue could not be read, so lock-screen alarm registration is unconfirmed. The regular notification fallback was skipped to avoid duplicates. Check system permissions, then save the reminder again.',
      ),
      NotificationIssueNotice.initializationFailed => pick(
        '系统通知初始化失败，提醒暂时无法注册。请检查通知权限、通知渠道和系统后台限制后重新保存提醒。',
        'System notifications could not start, so reminders cannot be registered right now. Check notification permission, channels and background restrictions, then save the reminder again.',
      ),
      NotificationIssueNotice.channelUnknown ||
      NotificationIssueNotice.channelProbeFailed => pick(
        '普通提醒渠道状态无法确认，提醒会继续注册，但到点显示或声音可能受系统设置影响。请检查系统通知设置后重新保存提醒。',
        'The regular reminder channel could not be verified. Registration will continue, but system settings may affect display or sound. Check system notification settings, then save the reminder again.',
      ),
      NotificationIssueNotice.channelBlocked => pick(
        '普通提醒渠道已关闭，提醒已注册但到点可能不会显示。请在系统通知设置里开启“多仪 · 通知提醒”。',
        'The regular reminder channel is off. The reminder is registered but may not appear when due. Turn on “多仪 · 通知提醒” in system notification settings.',
      ),
      NotificationIssueNotice.channelSilent => pick(
        '普通提醒渠道声音已关闭，提醒已注册但到点可能无声。请在系统通知设置里恢复“多仪 · 通知提醒”的声音。',
        'Sound is off for the regular reminder channel. The reminder is registered but may be silent when due. Restore sound for “多仪 · 通知提醒” in system notification settings.',
      ),
      NotificationIssueNotice.timePassed => pick(
        '提醒时间已过去，未注册到系统通知。请把提醒时间改到未来时间。',
        'The reminder time has passed and no system notification was registered. Choose a future time.',
      ),
      NotificationIssueNotice.oncePermissionUnconfirmed => pick(
        '系统通知权限未开启，提醒未确认注册成功。请开启通知权限后重新保存提醒。',
        'Notifications are disabled, so reminder registration is unconfirmed. Enable notifications and save the reminder again.',
      ),
      NotificationIssueNotice.oncePermissionDenied => pick(
        '系统通知权限未开启，提醒未注册。请开启通知权限后重新保存提醒。',
        'Notifications are disabled and the reminder was not registered. Enable notifications and save the reminder again.',
      ),
      NotificationIssueNotice.onceScheduleFailed => pick(
        '系统通知注册失败，请检查通知权限、精确闹钟权限和系统通知渠道设置后重新保存提醒。',
        'The system notification could not be registered. Check notification permission, exact alarm permission and channel settings, then save the reminder again.',
      ),
      NotificationIssueNotice.repeatPermissionUnconfirmed => pick(
        '系统通知权限未开启，重复提醒未确认注册成功。请开启通知权限后重新保存提醒。',
        'Notifications are disabled, so repeating reminder registration is unconfirmed. Enable notifications and save the reminder again.',
      ),
      NotificationIssueNotice.repeatPermissionDenied => pick(
        '系统通知权限未开启，重复提醒未注册。请开启通知权限后重新保存提醒。',
        'Notifications are disabled and the repeating reminder was not registered. Enable notifications and save the reminder again.',
      ),
      NotificationIssueNotice.repeatScheduleFailed => pick(
        '重复提醒注册失败，请检查通知权限、精确闹钟权限和系统通知渠道设置后重新保存提醒。',
        'The repeating reminder could not be registered. Check notification permission, exact alarm permission and channel settings, then save the reminder again.',
      ),
      NotificationIssueNotice.alarmDegraded => pick(
        '$reasonLabel：强提醒或内置铃声注册失败，已改用普通通知提醒；到点不会弹出强提醒。请检查精准闹钟权限、强提醒渠道、后台限制和普通提醒渠道声音。',
        '$reasonLabel: the strong alert or built-in sound could not be registered, so this reminder uses a regular notification. It will not show a strong alert when due. Check exact alarm permission, the strong alert channel, background restrictions and regular channel sound.',
      ),
      NotificationIssueNotice.sendFailed => pick(
        '系统通知发送失败，请检查通知权限和通知渠道设置后重试。',
        'The system notification could not be sent. Check notification permission and channel settings, then retry.',
      ),
      NotificationIssueNotice.sendPermissionDenied => pick(
        '系统通知权限未开启，通知未发送。请开启通知权限后重试。',
        'Notifications are disabled and the notification was not sent. Enable notifications and retry.',
      ),
      NotificationIssueNotice.snoozeCancelFailed => pick(
        '旧提醒取消失败，仍会尝试重新注册稍后提醒。若稍后收到重复提醒，请重新保存原提醒。',
        'The previous reminder could not be canceled. The app will still try to register the snoozed reminder. If you receive a duplicate, save the original reminder again.',
      ),
      NotificationIssueNotice.testPermissionUnconfirmed => pick(
        '测试通知已请求发送，但系统通知权限未开启，真机可能看不到通知或没有声音。请开启系统通知权限后再测试。',
        'The test notification was requested, but notifications are disabled; it may not appear or make a sound on your device. Enable notifications and test again.',
      ),
      NotificationIssueNotice.testPermissionDenied => pick(
        '系统通知权限未开启，测试通知未发送。请开启系统通知权限后再测试。',
        'Notifications are disabled and the test notification was not sent. Enable notifications and test again.',
      ),
      NotificationIssueNotice.testSendFailed => pick(
        '测试通知发送失败，请检查系统通知权限和通知渠道设置。',
        'The test notification could not be sent. Check notification permission and channel settings.',
      ),
      NotificationIssueNotice.inAppPopupUnavailable => pick(
        '应用内弹出通道未初始化，未注册普通通知兜底。请保持应用前台后重试。',
        'The in-app pop-up channel is not initialized and no regular notification fallback was registered. Keep the app in the foreground and retry.',
      ),
      NotificationIssueNotice.popupFallbackUnavailable => pick(
        '应用内弹出通道未初始化，无法注册弹出提醒和普通通知兜底。请重启应用后重试。',
        'The in-app pop-up channel is not initialized. Neither the pop-up nor its regular notification fallback can be registered. Restart the app and retry.',
      ),
      NotificationIssueNotice.inAppPopupFailed => pick(
        '应用内弹出测试未注册，且不会退回普通通知。请保持应用前台后重试。',
        'The in-app pop-up test was not registered and will not fall back to a regular notification. Keep the app in the foreground and retry.',
      ),
      NotificationIssueNotice.popupFallbackFailed => pick(
        '弹出兜底测试未注册，普通通知兜底也不可用。请检查通知权限和通知渠道后重试。',
        'The pop-up fallback test was not registered and its regular notification fallback is unavailable. Check notification permission and channels, then retry.',
      ),
      NotificationIssueNotice.alarmUnavailable => pick(
        '闹钟通道未初始化，未注册普通通知兜底。请重启应用后再测试，或重新保存提醒触发提醒服务初始化。',
        'The alarm channel is not initialized and no regular notification fallback was registered. Restart before testing, or save a reminder again to initialize the service.',
      ),
      NotificationIssueNotice.alarmScheduleFailed => pick(
        '闹钟提醒注册失败，请检查通知权限、精准闹钟权限和强提醒渠道设置。',
        'The alarm reminder could not be registered. Check notification permission, exact alarm permission and strong alert channel settings.',
      ),
      null => fallback,
    };
    return detail == null ? text : '$text($detail)';
  }
}
