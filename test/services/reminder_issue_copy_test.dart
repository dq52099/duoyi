import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/services/reminder_issue_copy.dart';
import 'package:duoyi/services/todo_reminder_preflight_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  test('all notification notices match canonical bilingual producer copy', () {
    // These Chinese strings are the stable copy emitted by NotificationService;
    // exception text is supplied separately through ReminderIssueCopy.detail.
    final expected = <NotificationIssueNotice, (String, String)>{
      NotificationIssueNotice.initializationFailed: (
        '系统通知初始化失败，提醒暂时无法注册。请检查通知权限、通知渠道和系统后台限制后重新保存提醒。',
        'System notifications could not start, so reminders cannot be registered right now. Check notification permission, channels and background restrictions, then save the reminder again.',
      ),
      NotificationIssueNotice.channelUnknown: (
        '普通提醒渠道状态无法确认，提醒会继续注册，但到点显示或声音可能受系统设置影响。请检查系统通知设置后重新保存提醒。',
        'The regular reminder channel could not be verified. Registration will continue, but system settings may affect display or sound. Check system notification settings, then save the reminder again.',
      ),
      NotificationIssueNotice.channelBlocked: (
        '普通提醒渠道已关闭，提醒已注册但到点可能不会显示。请在系统通知设置里开启“多仪 · 通知提醒”。',
        'The regular reminder channel is off. The reminder is registered but may not appear when due. Turn on “多仪 · 通知提醒” in system notification settings.',
      ),
      NotificationIssueNotice.channelSilent: (
        '普通提醒渠道声音已关闭，提醒已注册但到点可能无声。请在系统通知设置里恢复“多仪 · 通知提醒”的声音。',
        'Sound is off for the regular reminder channel. The reminder is registered but may be silent when due. Restore sound for “多仪 · 通知提醒” in system notification settings.',
      ),
      NotificationIssueNotice.channelProbeFailed: (
        '普通提醒渠道状态无法确认，提醒会继续注册，但到点显示或声音可能受系统设置影响。请检查系统通知设置后重新保存提醒。',
        'The regular reminder channel could not be verified. Registration will continue, but system settings may affect display or sound. Check system notification settings, then save the reminder again.',
      ),
      NotificationIssueNotice.timePassed: (
        '提醒时间已过去，未注册到系统通知。请把提醒时间改到未来时间。',
        'The reminder time has passed and no system notification was registered. Choose a future time.',
      ),
      NotificationIssueNotice.oncePermissionUnconfirmed: (
        '系统通知权限未开启，提醒未确认注册成功。请开启通知权限后重新保存提醒。',
        'Notifications are disabled, so reminder registration is unconfirmed. Enable notifications and save the reminder again.',
      ),
      NotificationIssueNotice.oncePermissionDenied: (
        '系统通知权限未开启，提醒未注册。请开启通知权限后重新保存提醒。',
        'Notifications are disabled and the reminder was not registered. Enable notifications and save the reminder again.',
      ),
      NotificationIssueNotice.onceScheduleFailed: (
        '系统通知注册失败，请检查通知权限、精确闹钟权限和系统通知渠道设置后重新保存提醒。',
        'The system notification could not be registered. Check notification permission, exact alarm permission and channel settings, then save the reminder again.',
      ),
      NotificationIssueNotice.repeatPermissionUnconfirmed: (
        '系统通知权限未开启，重复提醒未确认注册成功。请开启通知权限后重新保存提醒。',
        'Notifications are disabled, so repeating reminder registration is unconfirmed. Enable notifications and save the reminder again.',
      ),
      NotificationIssueNotice.repeatPermissionDenied: (
        '系统通知权限未开启，重复提醒未注册。请开启通知权限后重新保存提醒。',
        'Notifications are disabled and the repeating reminder was not registered. Enable notifications and save the reminder again.',
      ),
      NotificationIssueNotice.repeatScheduleFailed: (
        '重复提醒注册失败，请检查通知权限、精确闹钟权限和系统通知渠道设置后重新保存提醒。',
        'The repeating reminder could not be registered. Check notification permission, exact alarm permission and channel settings, then save the reminder again.',
      ),
      NotificationIssueNotice.alarmDegraded: (
        '提醒注册降级：强提醒或内置铃声注册失败，已改用普通通知提醒；到点不会弹出强提醒。请检查精准闹钟权限、强提醒渠道、后台限制和普通提醒渠道声音。',
        '提醒注册降级: the strong alert or built-in sound could not be registered, so this reminder uses a regular notification. It will not show a strong alert when due. Check exact alarm permission, the strong alert channel, background restrictions and regular channel sound.',
      ),
      NotificationIssueNotice.sendFailed: (
        '系统通知发送失败，请检查通知权限和通知渠道设置后重试。',
        'The system notification could not be sent. Check notification permission and channel settings, then retry.',
      ),
      NotificationIssueNotice.sendPermissionDenied: (
        '系统通知权限未开启，通知未发送。请开启通知权限后重试。',
        'Notifications are disabled and the notification was not sent. Enable notifications and retry.',
      ),
      NotificationIssueNotice.snoozeCancelFailed: (
        '旧提醒取消失败，仍会尝试重新注册稍后提醒。若稍后收到重复提醒，请重新保存原提醒。',
        'The previous reminder could not be canceled. The app will still try to register the snoozed reminder. If you receive a duplicate, save the original reminder again.',
      ),
      NotificationIssueNotice.testPermissionUnconfirmed: (
        '测试通知已请求发送，但系统通知权限未开启，真机可能看不到通知或没有声音。请开启系统通知权限后再测试。',
        'The test notification was requested, but notifications are disabled; it may not appear or make a sound on your device. Enable notifications and test again.',
      ),
      NotificationIssueNotice.testPermissionDenied: (
        '系统通知权限未开启，测试通知未发送。请开启系统通知权限后再测试。',
        'Notifications are disabled and the test notification was not sent. Enable notifications and test again.',
      ),
      NotificationIssueNotice.testSendFailed: (
        '测试通知发送失败，请检查系统通知权限和通知渠道设置。',
        'The test notification could not be sent. Check notification permission and channel settings.',
      ),
      NotificationIssueNotice.inAppPopupUnavailable: (
        '应用内弹出通道未初始化，未注册普通通知兜底。请保持应用前台后重试。',
        'The in-app pop-up channel is not initialized and no regular notification fallback was registered. Keep the app in the foreground and retry.',
      ),
      NotificationIssueNotice.popupFallbackUnavailable: (
        '应用内弹出通道未初始化，无法注册弹出提醒和普通通知兜底。请重启应用后重试。',
        'The in-app pop-up channel is not initialized. Neither the pop-up nor its regular notification fallback can be registered. Restart the app and retry.',
      ),
      NotificationIssueNotice.inAppPopupFailed: (
        '应用内弹出测试未注册，且不会退回普通通知。请保持应用前台后重试。',
        'The in-app pop-up test was not registered and will not fall back to a regular notification. Keep the app in the foreground and retry.',
      ),
      NotificationIssueNotice.popupFallbackFailed: (
        '弹出兜底测试未注册，普通通知兜底也不可用。请检查通知权限和通知渠道后重试。',
        'The pop-up fallback test was not registered and its regular notification fallback is unavailable. Check notification permission and channels, then retry.',
      ),
      NotificationIssueNotice.alarmUnavailable: (
        '闹钟通道未初始化，未注册普通通知兜底。请重启应用后再测试，或重新保存提醒触发提醒服务初始化。',
        'The alarm channel is not initialized and no regular notification fallback was registered. Restart before testing, or save a reminder again to initialize the service.',
      ),
      NotificationIssueNotice.alarmScheduleFailed: (
        '闹钟提醒注册失败，请检查通知权限、精准闹钟权限和强提醒渠道设置。',
        'The alarm reminder could not be registered. Check notification permission, exact alarm permission and strong alert channel settings.',
      ),
      NotificationIssueNotice.dailyCancellationFailed: (
        '旧提醒取消不完整，已暂停本次重新注册以避免重复提醒。请稍后重试，或重启应用后重新保存提醒。',
        'Some previous reminders could not be canceled. Rescheduling was paused to avoid duplicates. Retry later, or restart the app and save the reminder again.',
      ),
      NotificationIssueNotice.dailyScheduleFailed: (
        '系统调度失败，提醒未确认注册成功。请检查通知、精准闹钟和后台运行权限后重新保存提醒。',
        'Scheduling failed and reminder registration is unconfirmed. Check notification, exact alarm and background permissions, then save the reminder again.',
      ),
      NotificationIssueNotice.dailyChannelFallback: (
        '你选择的是所选通道提醒，但该通道没有确认注册成功，已改用普通通知兜底；到点不会按所选通道形式弹出。请在已注册提醒详情确认状态，检查通知、精准闹钟、全屏提醒和后台限制后重新保存。',
        'The selected channel reminder was not confirmed, so it now uses a regular notification. It will not appear as a selected channel when due. Review its registration details and notification, exact alarm, full-screen and background permissions, then save it again.',
      ),
      NotificationIssueNotice.dailyAlarmHandoffFailed: (
        '闹钟提醒交接失败，已跳过普通通知兜底以避免重复提醒。请在已注册提醒中确认，或重新保存该提醒。',
        'Alarm handoff failed. The regular notification fallback was skipped to avoid duplicates. Check registered reminders, or save this reminder again.',
      ),
      NotificationIssueNotice.dailyAlarmQueueUnconfirmed: (
        '闹钟待触发队列读取失败，无法确认锁屏闹钟是否已注册；为避免重复提醒已跳过普通通知兜底。请在系统权限正常后重新保存提醒。',
        'The pending alarm queue could not be read, so lock-screen alarm registration is unconfirmed. The regular notification fallback was skipped to avoid duplicates. Check system permissions, then save the reminder again.',
      ),
    };

    expect(expected.keys.toSet(), NotificationIssueNotice.values.toSet());
    for (final entry in expected.entries) {
      final label = entry.key == NotificationIssueNotice.alarmDegraded
          ? '提醒注册降级'
          : '';
      final copy = ReminderIssueCopy.notification(entry.key, label: label);
      expect(
        copy.renderMessage(fallback: 'unused fallback', locale: AppLocale.zh),
        entry.value.$1,
        reason: '${entry.key.name} canonical Chinese producer copy',
      );
      expect(
        copy.renderMessage(fallback: 'unused fallback', locale: AppLocale.en),
        entry.value.$2,
        reason: '${entry.key.name} English rendering',
      );
    }
  });

  test('all title codes render their canonical Chinese and English titles', () {
    final expected = <NotificationIssueTitle, (String, String)>{
      NotificationIssueTitle.initializationFailed: (
        '提醒注册初始化失败',
        'Reminder service could not start',
      ),
      NotificationIssueTitle.registrationFailed: (
        '提醒注册失败',
        'Reminder not registered',
      ),
      NotificationIssueTitle.repeatingRegistrationFailed: (
        '重复提醒注册失败',
        'Repeating reminder not registered',
      ),
      NotificationIssueTitle.taskRegistrationFailed: (
        '待办提醒注册失败',
        'Task reminder not registered',
      ),
      NotificationIssueTitle.habitRegistrationFailed: (
        '习惯提醒注册失败',
        'Habit reminder not registered',
      ),
      NotificationIssueTitle.anniversaryRegistrationFailed: (
        '纪念日提醒注册失败',
        'Anniversary reminder not registered',
      ),
      NotificationIssueTitle.aiRegistrationFailed: (
        'AI 日程提醒注册失败',
        'AI schedule reminder not registered',
      ),
      NotificationIssueTitle.snoozeRegistrationFailed: (
        '稍后提醒注册失败',
        'Snoozed reminder not registered',
      ),
      NotificationIssueTitle.snoozeWarning: (
        '稍后提醒注册异常',
        'Check snoozed reminder',
      ),
      NotificationIssueTitle.sendFailed: ('通知发送失败', 'Notification not sent'),
      NotificationIssueTitle.testWarning: (
        '普通通知测试异常',
        'Check notification test',
      ),
      NotificationIssueTitle.scheduledTestFailed: (
        '定时通知测试注册失败',
        'Scheduled notification test not registered',
      ),
      NotificationIssueTitle.popupTestFailed: (
        '定时弹出测试注册失败',
        'Scheduled pop-up test not registered',
      ),
      NotificationIssueTitle.alarmTestFailed: (
        '定时闹钟测试注册失败',
        'Scheduled alarm test not registered',
      ),
      NotificationIssueTitle.alarmDegraded: (
        '闹钟提醒已降级为普通通知',
        'Alarm now uses a regular notification',
      ),
      NotificationIssueTitle.dailyRegistrationFailed: (
        '每日提醒注册失败',
        'Daily reminder not scheduled',
      ),
      NotificationIssueTitle.dailyFallback: (
        '每日提醒已退回普通通知',
        'Daily reminder uses a regular notification',
      ),
      NotificationIssueTitle.dailyAlarmUnconfirmed: (
        '每日闹钟注册状态未确认',
        'Daily alarm registration unconfirmed',
      ),
      NotificationIssueTitle.registrationDegraded: (
        '提醒注册降级',
        'Reminder fallback',
      ),
      NotificationIssueTitle.repeatingRegistrationDegraded: (
        '重复提醒注册降级',
        'Repeating reminder fallback',
      ),
    };

    expect(expected.keys.toSet(), NotificationIssueTitle.values.toSet());
    for (final entry in expected.entries) {
      final copy = ReminderIssueCopy.notification(null, titleCode: entry.key);
      expect(
        copy.renderTitle(fallback: 'unused fallback', locale: AppLocale.zh),
        entry.value.$1,
        reason: '${entry.key.name} Chinese title',
      );
      expect(
        copy.renderTitle(fallback: 'unused fallback', locale: AppLocale.en),
        entry.value.$2,
        reason: '${entry.key.name} English title',
      );
    }
  });

  test('all check-state notices use neutral localized titles', () {
    final expectedNotices =
        <NotificationIssueNotice, (NotificationIssueTitle, String, String)>{
          NotificationIssueNotice.channelUnknown: (
            NotificationIssueTitle.taskRegistrationFailed,
            '待办提醒状态需检查',
            'Check task reminder',
          ),
          NotificationIssueNotice.channelBlocked: (
            NotificationIssueTitle.registrationFailed,
            '提醒状态需检查',
            'Check reminder status',
          ),
          NotificationIssueNotice.channelSilent: (
            NotificationIssueTitle.habitRegistrationFailed,
            '习惯提醒状态需检查',
            'Check habit reminder',
          ),
          NotificationIssueNotice.channelProbeFailed: (
            NotificationIssueTitle.scheduledTestFailed,
            '定时通知测试状态需检查',
            'Check scheduled notification test',
          ),
          NotificationIssueNotice.oncePermissionUnconfirmed: (
            NotificationIssueTitle.taskRegistrationFailed,
            '待办提醒状态需检查',
            'Check task reminder',
          ),
          NotificationIssueNotice.repeatPermissionUnconfirmed: (
            NotificationIssueTitle.repeatingRegistrationFailed,
            '重复提醒状态需检查',
            'Check repeating reminder',
          ),
        };
    expect(expectedNotices.keys.toSet(), <NotificationIssueNotice>{
      NotificationIssueNotice.channelUnknown,
      NotificationIssueNotice.channelBlocked,
      NotificationIssueNotice.channelSilent,
      NotificationIssueNotice.channelProbeFailed,
      NotificationIssueNotice.oncePermissionUnconfirmed,
      NotificationIssueNotice.repeatPermissionUnconfirmed,
    });

    for (final entry in expectedNotices.entries) {
      final copy = ReminderIssueCopy.notification(
        entry.key,
        titleCode: entry.value.$1,
      );
      expect(
        copy.renderTitle(fallback: 'unused fallback', locale: AppLocale.zh),
        entry.value.$2,
        reason: '${entry.key.name} owned check title in Chinese',
      );
      expect(
        copy.renderTitle(fallback: 'unused fallback', locale: AppLocale.en),
        entry.value.$3,
        reason: '${entry.key.name} owned check title in English',
      );
    }

    final expectedCheckTitles = <NotificationIssueTitle, (String, String)>{
      NotificationIssueTitle.registrationFailed: (
        '提醒状态需检查',
        'Check reminder status',
      ),
      NotificationIssueTitle.repeatingRegistrationFailed: (
        '重复提醒状态需检查',
        'Check repeating reminder',
      ),
      NotificationIssueTitle.taskRegistrationFailed: (
        '待办提醒状态需检查',
        'Check task reminder',
      ),
      NotificationIssueTitle.habitRegistrationFailed: (
        '习惯提醒状态需检查',
        'Check habit reminder',
      ),
      NotificationIssueTitle.anniversaryRegistrationFailed: (
        '纪念日提醒状态需检查',
        'Check anniversary reminder',
      ),
      NotificationIssueTitle.aiRegistrationFailed: (
        'AI 日程提醒状态需检查',
        'Check AI schedule reminder',
      ),
      NotificationIssueTitle.snoozeRegistrationFailed: (
        '稍后提醒状态需检查',
        'Check snoozed reminder',
      ),
      NotificationIssueTitle.scheduledTestFailed: (
        '定时通知测试状态需检查',
        'Check scheduled notification test',
      ),
    };
    for (final entry in expectedCheckTitles.entries) {
      expect(
        entry.key.renderCheckTitle(locale: AppLocale.zh),
        entry.value.$1,
        reason: '${entry.key.name} neutral Chinese title',
      );
      expect(
        entry.key.renderCheckTitle(locale: AppLocale.en),
        entry.value.$2,
        reason: '${entry.key.name} neutral English title',
      );
    }
  });

  test('raw exception details keep mixed text, empty text, and whitespace', () {
    const rawDetail = 'Alarm API v2 / 锁屏调度失败：code=ALARM_42\npermission denied';
    final mixed = ReminderIssueCopy.notification(
      NotificationIssueNotice.onceScheduleFailed,
      detail: rawDetail,
    );

    expect(mixed.detail, rawDetail);
    expect(
      mixed.renderMessage(fallback: '', locale: AppLocale.zh),
      '系统通知注册失败，请检查通知权限、精确闹钟权限和系统通知渠道设置后重新保存提醒。($rawDetail)',
    );
    expect(
      mixed.renderMessage(fallback: '', locale: AppLocale.en),
      'The system notification could not be registered. Check notification permission, exact alarm permission and channel settings, then save the reminder again.($rawDetail)',
    );

    const emptyDetail = '';
    final empty = ReminderIssueCopy.notification(
      NotificationIssueNotice.sendFailed,
      detail: emptyDetail,
    );
    expect(empty.detail, emptyDetail);
    expect(
      empty.renderMessage(fallback: '', locale: AppLocale.zh),
      '系统通知发送失败，请检查通知权限和通知渠道设置后重试。()',
    );

    const whitespaceDetail = ' \t\n  ';
    final whitespace = ReminderIssueCopy.notification(
      NotificationIssueNotice.testSendFailed,
      detail: whitespaceDetail,
    );
    expect(whitespace.detail, whitespaceDetail);
    expect(
      whitespace.renderMessage(fallback: '', locale: AppLocale.en),
      'The test notification could not be sent. Check notification permission and channel settings.($whitespaceDetail)',
    );
  });

  test('custom fallback titles stay literal without a title code', () {
    const fallbacks = <String>[
      'Custom “Night Shift” / 标题',
      '',
      ' \t\n ',
      'Task reminder not registered',
      '待办提醒注册失败',
    ];

    for (final fallback in fallbacks) {
      final copy = ReminderIssueCopy.notification(
        NotificationIssueNotice.channelUnknown,
      );
      for (final locale in AppLocale.values) {
        expect(
          copy.renderTitle(fallback: fallback, locale: locale),
          fallback,
          reason: 'fallback stays literal in ${locale.name}',
        );
      }
    }

    const rawMessage = '原样的服务诊断 / service diagnostic';
    const messageCopy = ReminderIssueCopy.notification(null);
    expect(
      messageCopy.renderMessage(fallback: rawMessage, locale: AppLocale.en),
      rawMessage,
    );
  });

  test('alarm reason labels are literal unless an owned label code is set', () {
    const literalLabel = '待办提醒注册失败';
    const literal = ReminderIssueCopy.notification(
      NotificationIssueNotice.alarmDegraded,
      label: literalLabel,
    );
    expect(
      literal.renderMessage(fallback: '', locale: AppLocale.en),
      startsWith('$literalLabel: the strong alert'),
    );

    const owned = ReminderIssueCopy.notification(
      NotificationIssueNotice.alarmDegraded,
      label: 'literal label should be superseded',
      labelCode: NotificationIssueTitle.taskRegistrationFailed,
    );
    expect(
      owned.renderMessage(fallback: '', locale: AppLocale.zh),
      startsWith('待办提醒注册失败：强提醒或内置铃声注册失败'),
    );
    expect(
      owned.renderMessage(fallback: '', locale: AppLocale.en),
      startsWith('Task reminder not registered: the strong alert'),
    );
  });

  test('preflight copy bridge forwards both localized title and message', () {
    final expected = <TodoReminderPreflightNotice, (String, String, String, String)>{
      TodoReminderPreflightNotice.missingDate: (
        '待办提醒注册失败',
        '一次性提醒需要截止日期或提醒日期。请先设置未来的日期。',
        'Task reminder not registered',
        'A one-time reminder needs a due date or reminder date. Set a future date first.',
      ),
      TodoReminderPreflightNotice.timeInPast: (
        '待办提醒注册失败',
        '提醒时间已过去，未注册到系统通知。请把提醒时间改到未来时间。',
        'Task reminder not registered',
        'The reminder time has passed and no system notification was registered. Choose a future time.',
      ),
      TodoReminderPreflightNotice.invalidRepeatTime: (
        '重复提醒注册失败',
        '重复提醒缺少有效时间，请重新选择提醒时间。',
        'Repeating reminder not registered',
        'The repeating reminder needs a valid time. Select the reminder time again.',
      ),
      TodoReminderPreflightNotice.invalidWeeklyRule: (
        '每周提醒注册失败',
        '每周提醒需要有效时间和至少一个星期。请重新选择提醒规则。',
        'Weekly reminder not registered',
        'A weekly reminder needs a valid time and at least one weekday. Select the reminder rule again.',
      ),
      TodoReminderPreflightNotice.noDeliverableRule: (
        '待办提醒注册失败',
        '提醒计划没有可注册的规则，请重新设置提醒。',
        'Task reminder not registered',
        'The reminder plan has no rules that can be registered. Set up the reminder again.',
      ),
    };

    expect(expected.keys.toSet(), TodoReminderPreflightNotice.values.toSet());
    for (final entry in expected.entries) {
      final bridge = ReminderIssueCopy.preflight(
        TodoReminderPreflightCopy(entry.key),
      );
      expect(
        bridge.renderTitle(fallback: 'unused title', locale: AppLocale.zh),
        entry.value.$1,
      );
      expect(
        bridge.renderMessage(fallback: 'unused message', locale: AppLocale.zh),
        entry.value.$2,
      );
      expect(
        bridge.renderTitle(fallback: 'unused title', locale: AppLocale.en),
        entry.value.$3,
      );
      expect(
        bridge.renderMessage(fallback: 'unused message', locale: AppLocale.en),
        entry.value.$4,
      );
    }
  });

  test('explicit locale rendering does not mutate global I18n locale', () {
    final notification = ReminderIssueCopy.notification(
      NotificationIssueNotice.timePassed,
      titleCode: NotificationIssueTitle.taskRegistrationFailed,
    );
    final preflight = ReminderIssueCopy.preflight(
      const TodoReminderPreflightCopy(
        TodoReminderPreflightNotice.invalidWeeklyRule,
      ),
    );

    I18n.setLocale(AppLocale.en);
    expect(
      notification.renderTitle(fallback: '', locale: AppLocale.zh),
      '待办提醒注册失败',
    );
    expect(
      preflight.renderMessage(fallback: '', locale: AppLocale.zh),
      '每周提醒需要有效时间和至少一个星期。请重新选择提醒规则。',
    );
    expect(I18n.current, AppLocale.en);
    expect(I18n.localeListenable.value, AppLocale.en);

    I18n.setLocale(AppLocale.zh);
    expect(
      notification.renderMessage(fallback: '', locale: AppLocale.en),
      'The reminder time has passed and no system notification was registered. Choose a future time.',
    );
    expect(
      preflight.renderTitle(fallback: '', locale: AppLocale.en),
      'Weekly reminder not registered',
    );
    expect(I18n.current, AppLocale.zh);
    expect(I18n.localeListenable.value, AppLocale.zh);
  });

  test('unconfirmed, failed, and channel warning copy stay distinct', () {
    final unconfirmed = ReminderIssueCopy.notification(
      NotificationIssueNotice.oncePermissionUnconfirmed,
    );
    final denied = ReminderIssueCopy.notification(
      NotificationIssueNotice.oncePermissionDenied,
    );
    final failed = ReminderIssueCopy.notification(
      NotificationIssueNotice.onceScheduleFailed,
    );
    final channelWarning = ReminderIssueCopy.notification(
      NotificationIssueNotice.channelUnknown,
    );

    final zh = <String>[
      unconfirmed.renderMessage(fallback: '', locale: AppLocale.zh),
      denied.renderMessage(fallback: '', locale: AppLocale.zh),
      failed.renderMessage(fallback: '', locale: AppLocale.zh),
      channelWarning.renderMessage(fallback: '', locale: AppLocale.zh),
    ];
    final en = <String>[
      unconfirmed.renderMessage(fallback: '', locale: AppLocale.en),
      denied.renderMessage(fallback: '', locale: AppLocale.en),
      failed.renderMessage(fallback: '', locale: AppLocale.en),
      channelWarning.renderMessage(fallback: '', locale: AppLocale.en),
    ];

    expect(zh.toSet(), hasLength(4));
    expect(en.toSet(), hasLength(4));
    expect(zh[0], contains('未确认注册成功'));
    expect(zh[1], contains('提醒未注册。'));
    expect(zh[2], contains('系统通知注册失败'));
    expect(zh[3], contains('提醒会继续注册'));
    expect(en[0], contains('registration is unconfirmed'));
    expect(en[1], contains('was not registered'));
    expect(en[2], contains('could not be registered'));
    expect(en[3], contains('Registration will continue'));
  });
}
