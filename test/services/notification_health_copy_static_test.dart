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
      expect(card, contains('疑难设置入口'));
      expect(card, contains('先按上方检查项逐项确认'));
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
      expect(hint, contains("actionLabel = '通知授权'"));
      expect(hint, contains("actionLabel = '精准闹钟'"));
      expect(hint, contains("actionLabel = '弹屏权限'"));
      expect(hint, isNot(contains("actionLabel = '去授权'")));
    });
  });
}
