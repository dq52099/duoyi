import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/notification_ui_copy.dart';
import 'package:duoyi/models/goal.dart' show ReminderKind;
import 'package:duoyi/providers/notification_service.dart'
    show NotificationScheduleIssue;
import 'package:duoyi/services/reminder_issue_copy.dart';
import 'package:duoyi/services/daily_digest_reminder_sync.dart';
import 'package:duoyi/services/notification_permission_exception.dart';
import 'package:duoyi/services/todo_reminder_preflight_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  test('typed schedule issues render localized meaning and preserve details', () {
    const unconfirmedDetail = 'POST_NOTIFICATIONS query denied / 系统返回=0xD3';
    const degradedDetail = 'AlarmManager rejected request / 全屏通道未就绪';
    const warningDetail = 'NotificationChannel probe failed / 渠道读取异常';
    final cases =
        <
          ({
            String name,
            NotificationScheduleIssue issue,
            String zh,
            String en,
            bool blocking,
          })
        >[
          (
            name: 'permission unconfirmed',
            issue: NotificationScheduleIssue(
              title: '待办提醒注册失败',
              message: '系统通知权限未开启，提醒未确认注册成功。',
              happenedAt: DateTime(2026, 10, 8, 12),
              copy: const ReminderIssueCopy.notification(
                NotificationIssueNotice.oncePermissionUnconfirmed,
                titleCode: NotificationIssueTitle.taskRegistrationFailed,
                detail: unconfirmedDetail,
              ),
            ),
            zh: '待办提醒状态需检查：系统通知权限未开启，提醒未确认注册成功。请开启通知权限后重新保存提醒。($unconfirmedDetail)',
            en: 'Check task reminder: Notifications are disabled, so reminder registration is unconfirmed. Enable notifications and save the reminder again.($unconfirmedDetail)',
            blocking: true,
          ),
          (
            name: 'alarm degraded',
            issue: NotificationScheduleIssue(
              title: '闹钟提醒已降级为普通通知',
              message: '待办提醒注册失败：强提醒或内置铃声注册失败。',
              happenedAt: DateTime(2026, 10, 8, 12),
              copy: const ReminderIssueCopy.notification(
                NotificationIssueNotice.alarmDegraded,
                titleCode: NotificationIssueTitle.alarmDegraded,
                label: '待办提醒注册失败',
                detail: degradedDetail,
              ),
            ),
            zh: '闹钟提醒已降级为普通通知：待办提醒注册失败：强提醒或内置铃声注册失败，已改用普通通知提醒；到点不会弹出强提醒。请检查精准闹钟权限、强提醒渠道、后台限制和普通提醒渠道声音。($degradedDetail)',
            en: 'Alarm now uses a regular notification: 待办提醒注册失败: the strong alert or built-in sound could not be registered, so this reminder uses a regular notification. It will not show a strong alert when due. Check exact alarm permission, the strong alert channel, background restrictions and regular channel sound.($degradedDetail)',
            blocking: true,
          ),
          (
            name: 'channel probe warning',
            issue: NotificationScheduleIssue(
              title: '待办提醒注册失败',
              message: '普通提醒渠道状态无法确认。',
              happenedAt: DateTime(2026, 10, 8, 12),
              blocking: false,
              copy: const ReminderIssueCopy.notification(
                NotificationIssueNotice.channelProbeFailed,
                titleCode: NotificationIssueTitle.taskRegistrationFailed,
                detail: warningDetail,
              ),
            ),
            zh: '待办提醒状态需检查：普通提醒渠道状态无法确认，提醒会继续注册，但到点显示或声音可能受系统设置影响。请检查系统通知设置后重新保存提醒。($warningDetail)',
            en: 'Check task reminder: The regular reminder channel could not be verified. Registration will continue, but system settings may affect display or sound. Check system notification settings, then save the reminder again.($warningDetail)',
            blocking: false,
          ),
        ];

    for (final entry in cases) {
      expect(entry.issue.blocking, entry.blocking, reason: entry.name);
      I18n.setLocale(AppLocale.zh);
      expect(
        NotificationUiCopy.formatScheduleIssue(
          entry.issue,
          fallback: 'unused fallback',
        ),
        entry.zh,
        reason: '${entry.name} Chinese rendering',
      );
      I18n.setLocale(AppLocale.en);
      expect(
        NotificationUiCopy.formatScheduleIssue(
          entry.issue,
          fallback: 'unused fallback',
        ),
        entry.en,
        reason: '${entry.name} English rendering',
      );
    }
  });

  test('typed notification issue keeps custom and empty fallback titles literal', () {
    const copy = ReminderIssueCopy.notification(
      NotificationIssueNotice.channelUnknown,
    );
    final customTitle = NotificationScheduleIssue(
      title: '自定义 / Custom reminder title',
      message: 'legacy raw message',
      happenedAt: DateTime(2026, 10, 8),
      copy: copy,
    );
    final emptyTitle = NotificationScheduleIssue(
      title: '',
      message: 'legacy raw message',
      happenedAt: DateTime(2026, 10, 8),
      copy: copy,
    );

    I18n.setLocale(AppLocale.zh);
    expect(
      NotificationUiCopy.formatScheduleIssue(customTitle, fallback: ''),
      '自定义 / Custom reminder title：普通提醒渠道状态无法确认，提醒会继续注册，但到点显示或声音可能受系统设置影响。请检查系统通知设置后重新保存提醒。',
    );
    expect(
      NotificationUiCopy.formatScheduleIssue(emptyTitle, fallback: ''),
      '：普通提醒渠道状态无法确认，提醒会继续注册，但到点显示或声音可能受系统设置影响。请检查系统通知设置后重新保存提醒。',
    );

    I18n.setLocale(AppLocale.en);
    expect(
      NotificationUiCopy.formatScheduleIssue(customTitle, fallback: ''),
      '自定义 / Custom reminder title: The regular reminder channel could not be verified. Registration will continue, but system settings may affect display or sound. Check system notification settings, then save the reminder again.',
    );
    expect(
      NotificationUiCopy.formatScheduleIssue(emptyTitle, fallback: ''),
      ': The regular reminder channel could not be verified. Registration will continue, but system settings may affect display or sound. Check system notification settings, then save the reminder again.',
    );
  });

  test('preflight copy bridges into schedule issue formatting', () {
    final preflight = ReminderIssueCopy.preflight(
      const TodoReminderPreflightCopy(
        TodoReminderPreflightNotice.invalidWeeklyRule,
      ),
    );
    final issue = NotificationScheduleIssue(
      title: 'legacy preflight title',
      message: 'legacy preflight message',
      happenedAt: DateTime(2026, 10, 8),
      copy: preflight,
    );

    I18n.setLocale(AppLocale.zh);
    expect(
      NotificationUiCopy.formatScheduleIssue(issue, fallback: ''),
      '每周提醒注册失败：每周提醒需要有效时间和至少一个星期。请重新选择提醒规则。',
    );
    I18n.setLocale(AppLocale.en);
    expect(
      NotificationUiCopy.formatScheduleIssue(issue, fallback: ''),
      'Weekly reminder not registered: A weekly reminder needs a valid time and at least one weekday. Select the reminder rule again.',
    );
  });

  test('issues without typed copy keep the legacy formatter behavior', () {
    final permissionIssue = NotificationScheduleIssue(
      title: '待办提醒注册失败',
      message: '系统通知权限未开启，提醒未确认注册成功。请开启通知权限后重新保存提醒。',
      happenedAt: DateTime(2026, 10, 8),
    );
    final unknownIssue = NotificationScheduleIssue(
      title: 'Custom legacy title',
      message: 'opaque service diagnostic: code=0xC1 / retained verbatim',
      happenedAt: DateTime(2026, 10, 8),
    );

    I18n.setLocale(AppLocale.zh);
    expect(
      NotificationUiCopy.formatScheduleIssue(permissionIssue, fallback: ''),
      '待办提醒注册失败：系统通知权限未开启，提醒未确认注册成功。请开启通知权限后重新保存提醒。',
    );
    expect(
      NotificationUiCopy.formatScheduleIssue(unknownIssue, fallback: ''),
      'Custom legacy title：opaque service diagnostic: code=0xC1 / retained verbatim',
    );

    I18n.setLocale(AppLocale.en);
    expect(
      NotificationUiCopy.formatScheduleIssue(permissionIssue, fallback: ''),
      '待办提醒注册失败: Notification permission is disabled. Please enable it in system settings.',
    );
    expect(
      NotificationUiCopy.formatScheduleIssue(unknownIssue, fallback: ''),
      'Custom legacy title: opaque service diagnostic: code=0xC1 / retained verbatim',
    );
  });

  test(
    'daily registration result uses its blocking state in both languages',
    () {
      for (final locale in AppLocale.values) {
        I18n.setLocale(locale);
        for (final blocking in [false, true]) {
          final issue = DailyDigestReminderIssue(
            title: '每日提醒注册失败',
            message: '通知权限未开启',
            blocking: blocking,
          );
          final text = NotificationUiCopy.dailyRegistrationIssue(issue);
          if (locale == AppLocale.en) {
            expect(
              text,
              startsWith(
                blocking
                    ? 'Daily reminder saved, but not scheduled'
                    : 'Daily reminder saved; review delivery settings',
              ),
            );
            expect(text, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
          } else {
            expect(
              text,
              startsWith(blocking ? '每日提醒已保存，但未注册' : '每日提醒已保存，但需要确认'),
            );
            expect(text, contains('通知权限未开启'));
          }
        }
      }
    },
  );

  test(
    'schedule exception resolves typed feedback using the current locale',
    () {
      const issue = NotificationScheduleUnavailableException(
        title: '提醒注册失败',
        message: '旧语言的提示',
        copy: ReminderIssueCopy.notification(
          NotificationIssueNotice.oncePermissionUnconfirmed,
          titleCode: NotificationIssueTitle.taskRegistrationFailed,
        ),
      );
      I18n.setLocale(AppLocale.en);
      final text = NotificationUiCopy.formatScheduleException(issue);
      expect(text, startsWith('Check task reminder: '));
      expect(text, contains('Enable notifications'));
      expect(text, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
    },
  );

  test(
    'typed daily channel fallback follows locale and preserves result metadata',
    () {
      for (final kind in [ReminderKind.popup, ReminderKind.alarm]) {
        final scheduled = DateTime(2026, 10, 13, 10);
        final issue = DailyDigestReminderIssue(
          title: '每日提醒已退回普通通知',
          message: '旧语言的通道说明',
          scheduledTime: scheduled,
          relatedId: 'daily_reminder_1',
          blocking: false,
          copy: ReminderIssueCopy.notification(
            NotificationIssueNotice.dailyChannelFallback,
            titleCode: NotificationIssueTitle.dailyFallback,
            requestedKind: kind,
            detail: 'synthetic-code=0xD4',
          ),
        );
        I18n.setLocale(AppLocale.en);
        final en = NotificationUiCopy.dailyRegistrationIssue(issue);
        expect(
          en,
          contains(kind == ReminderKind.alarm ? 'lock-screen alarm' : 'pop-up'),
        );
        expect(en, contains('now uses a regular notification'));
        expect(en, contains('synthetic-code=0xD4'));
        expect(en, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
        I18n.setLocale(AppLocale.zh);
        final zh = NotificationUiCopy.dailyRegistrationIssue(issue);
        expect(zh, contains(kind == ReminderKind.alarm ? '锁屏闹钟' : '弹出框'));
        expect(zh, contains('已改用普通通知兜底'));
        expect(issue.title, '每日提醒已退回普通通知');
        expect(issue.message, '旧语言的通道说明');
        expect(issue.scheduledTime, same(scheduled));
        expect(issue.relatedId, 'daily_reminder_1');
        expect(issue.blocking, isFalse);
      }
    },
  );
}
