import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('通知健康检查文案', () {
    test('HyperOS/MIUI 人工检查分项展示且不重复跳转', () {
      final service = File(
        'lib/services/permission_health_service.dart',
      ).readAsStringSync();
      final card = File(
        'lib/widgets/notification_health_card.dart',
      ).readAsStringSync();
      final hint = File(
        'lib/widgets/reminder_health_hint.dart',
      ).readAsStringSync();
      final copy = File(
        'lib/core/notification_ui_copy.dart',
      ).readAsStringSync();
      final checklist = File(
        'docs/manual-regression-checklist.md',
      ).readAsStringSync();

      for (final id in [
        'xiaomi_autostart_policy',
        'xiaomi_battery_policy',
        'xiaomi_lock_screen_policy',
        'xiaomi_channel_sound_policy',
      ]) {
        expect(service, contains(id));
      }

      for (final title in [
        'HyperOS/MIUI 自启动',
        'HyperOS/MIUI 后台与电池',
        'HyperOS/MIUI 锁屏与横幅',
        'HyperOS/MIUI 渠道声音',
      ]) {
        expect(service, contains(title));
      }

      expect(service, isNot(contains('xiaomi_notification_policy')));
      expect(service, isNot(contains('小米通知策略')));
      expect(service, isNot(contains('后台、锁屏和电池策略')));
      expect(card, contains('NotificationUiCopy.troubleshootingSettingsTitle'));
      expect(
        card,
        contains('NotificationUiCopy.troubleshootingSettingsSubtitle'),
      );
      expect(card, contains('NotificationUiCopy.strongTestTitle'));
      expect(card, contains('NotificationUiCopy.strongTestSubtitle'));
      expect(card, contains('onSendStrongTest'));
      expect(copy, contains("isEn ? 'Test strong reminder sound' : '测试强提醒铃声'"));
      expect(
        copy,
        contains('Verify alarm reminders, built-in sounds, stop actions'),
      );
      expect(copy, contains('验证闹钟提醒、内置铃声和通知停止按钮'));
      expect(copy, contains("isEn ? 'Troubleshooting settings' : '疑难设置入口'"));
      expect(
        copy,
        contains('If the launcher cannot open vendor controls directly'),
      );
      expect(copy, contains('先按上方检查项逐项确认'));
      expect(
        File('lib/screens/notification_history_screen.dart').readAsStringSync(),
        contains('AlarmService.instance.showFullScreenTest()'),
      );
      expect(
        File('lib/screens/preferences_screen.dart').readAsStringSync(),
        isNot(contains('showFullScreenTest')),
      );
      expect(card, isNot(contains('系统通知设置')));
      expect(checklist, contains('这些检查项不出现重复的「去设置」按钮'));

      expect(
        service,
        contains("actionLabel: notificationGranted ? null : '通知授权'"),
      );
      expect(
        service,
        contains(
          "actionLabel: exactRelevant && !exactAlarmGranted ? '精准闹钟' : null",
        ),
      );
      expect(service, contains("? '弹屏权限'"));
      expect(service, contains('notification_channel_sound'));
      expect(service, contains('NativeReminderRingtone.statusChannelId'));
      expect(service, contains('NativeReminderRingtone.fallbackChannelId'));
      expect(service, contains('闹钟兜底通知渠道均已创建'));
      expect(service, contains('闹钟兜底通知'));
      expect(service, contains('actionChannelIds: affectedChannels'));
      expect(service, contains("title: '渠道声音'"));
      expect(service, contains("actionLabel: '渠道设置'"));
      expect(service, contains('SystemNotificationAudioStatus'));
      expect(service, contains("title: '系统闹钟音量'"));
      expect(service, contains("title: '勿扰模式'"));
      expect(service, contains('通知音量为 0'));
      expect(copy, contains('系统闹钟音量和勿扰影响'));
      expect(
        service,
        contains('NotificationSettings.notificationChannelStatuses'),
      );
      expect(card, contains('onOpenNotificationChannelSettings'));
      expect(card, contains('check.actionChannelIds.first'));
      expect(
        File('lib/screens/notification_history_screen.dart').readAsStringSync(),
        contains('NotificationSettings.openNotificationChannelSettings'),
      );
      expect(
        File('lib/screens/notification_history_screen.dart').readAsStringSync(),
        matches(
          RegExp(
            r'_openSystemSettings\(\s*NotificationService\.channelId\s*,?\s*\)',
          ),
        ),
      );
      expect(
        File('lib/screens/notification_history_screen.dart').readAsStringSync(),
        contains('_openSystemSettings([String? channelId])'),
      );
      expect(hint, contains('NotificationUiCopy.notificationPermissionAction'));
      expect(hint, contains('NotificationUiCopy.exactAlarmAction'));
      expect(hint, contains('NotificationUiCopy.fullScreenAction'));
      expect(copy, contains("isEn ? 'Notifications' : '通知授权'"));
      expect(copy, contains("isEn ? 'Exact alarms' : '精准闹钟'"));
      expect(copy, contains("isEn ? 'Full-screen alerts' : '弹屏权限'"));
      expect(hint, isNot(contains("actionLabel = '去授权'")));
    });
  });
}
