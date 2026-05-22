import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/platform_info.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/services/alarm_service.dart';
import 'package:duoyi/services/permission_health_service.dart';

void main() {
  test('通知未授权时返回阻断状态', () async {
    final service = PermissionHealthService(
      notificationGrantedReader: () async => false,
      exactAlarmGrantedReader: () async => true,
      fullScreenIntentGrantedReader: () async => true,
      isAndroidReader: () => true,
      isIOSReader: () => false,
      androidDeviceReader: () async => const AndroidDeviceInfoLite(
        manufacturer: 'Samsung',
        brand: 'samsung',
        model: 'SM-S9180',
        sdkInt: 34,
      ),
      channelIdsReader: () async => <String>{
        NotificationService.channelId,
        AlarmService.channelId,
      },
    );

    final report = await service.check();

    expect(report.summaryStatus, PermissionHealthStatus.blocked);
    expect(report.hasBlockingIssue, isTrue);
    final notification = report.checks.firstWhere(
      (check) => check.id == 'notification_permission',
    );
    expect(notification.status, PermissionHealthStatus.blocked);
    expect(notification.actionLabel, '通知授权');
  });

  test('精准闹钟缺失时会阻断闹钟提醒并标出渠道状态', () async {
    final service = PermissionHealthService(
      notificationGrantedReader: () async => true,
      exactAlarmGrantedReader: () async => false,
      fullScreenIntentGrantedReader: () async => true,
      isAndroidReader: () => true,
      isIOSReader: () => false,
      androidDeviceReader: () async => const AndroidDeviceInfoLite(
        manufacturer: 'Google',
        brand: 'google',
        model: 'Pixel 8',
        sdkInt: 34,
      ),
      channelIdsReader: () async => <String>{NotificationService.channelId},
    );

    final report = await service.check();

    expect(report.summaryStatus, PermissionHealthStatus.blocked);
    final exactAlarm = report.checks.firstWhere(
      (check) => check.id == 'exact_alarm_permission',
    );
    expect(exactAlarm.status, PermissionHealthStatus.blocked);
    expect(exactAlarm.actionLabel, '精准闹钟');
    final channels = report.checks.firstWhere(
      (check) => check.id == 'notification_channels',
    );
    expect(channels.status, PermissionHealthStatus.warning);
  });

  test('Xiaomi-like 设备会输出分项人工检查，避免重复无效跳转', () async {
    final service = PermissionHealthService(
      notificationGrantedReader: () async => true,
      exactAlarmGrantedReader: () async => true,
      fullScreenIntentGrantedReader: () async => true,
      isAndroidReader: () => true,
      isIOSReader: () => false,
      androidDeviceReader: () async => const AndroidDeviceInfoLite(
        manufacturer: 'Xiaomi',
        brand: 'xiaomi',
        model: '2210132C',
        sdkInt: 34,
      ),
      channelIdsReader: () async => <String>{
        NotificationService.channelId,
        AlarmService.channelId,
      },
    );

    final report = await service.check();

    expect(report.isXiaomiLike, isTrue);
    expect(report.summaryStatus, PermissionHealthStatus.warning);
    expect(report.summarySubtitle, contains('渠道声音'));
    final manualChecks = report.checks.where((check) => check.manual).toList();
    expect(manualChecks, hasLength(4));
    expect(
      manualChecks.map((check) => check.id),
      containsAll(<String>[
        'xiaomi_autostart_policy',
        'xiaomi_battery_policy',
        'xiaomi_lock_screen_policy',
        'xiaomi_channel_sound_policy',
      ]),
    );
    expect(
      manualChecks.map((check) => check.title),
      containsAll(<String>[
        'HyperOS/MIUI 自启动',
        'HyperOS/MIUI 后台与电池',
        'HyperOS/MIUI 锁屏与横幅',
        'HyperOS/MIUI 渠道声音',
      ]),
    );
    expect(
      manualChecks.every(
        (check) => check.action == PermissionHealthAction.none,
      ),
      isTrue,
    );
  });

  test('弹出屏幕权限缺失时标为阻断状态', () async {
    final service = PermissionHealthService(
      notificationGrantedReader: () async => true,
      exactAlarmGrantedReader: () async => true,
      fullScreenIntentGrantedReader: () async => false,
      isAndroidReader: () => true,
      isIOSReader: () => false,
      androidDeviceReader: () async => const AndroidDeviceInfoLite(
        manufacturer: 'Google',
        brand: 'google',
        model: 'Pixel 8',
        sdkInt: 34,
      ),
      channelIdsReader: () async => <String>{
        NotificationService.channelId,
        AlarmService.channelId,
      },
    );

    final report = await service.check();

    expect(report.summaryStatus, PermissionHealthStatus.blocked);
    final fullScreen = report.checks.firstWhere(
      (check) => check.id == 'full_screen_intent_permission',
    );
    expect(fullScreen.status, PermissionHealthStatus.blocked);
    expect(
      fullScreen.action,
      PermissionHealthAction.requestFullScreenIntentPermission,
    );
    expect(fullScreen.actionLabel, '弹屏权限');
  });

  test('权限处理按钮使用明确文案，避免多个去授权重复出现', () async {
    final service = PermissionHealthService(
      notificationGrantedReader: () async => false,
      exactAlarmGrantedReader: () async => false,
      fullScreenIntentGrantedReader: () async => false,
      isAndroidReader: () => true,
      isIOSReader: () => false,
      androidDeviceReader: () async => const AndroidDeviceInfoLite(
        manufacturer: 'Google',
        brand: 'google',
        model: 'Pixel 8',
        sdkInt: 34,
      ),
      channelIdsReader: () async => <String>{
        NotificationService.channelId,
        AlarmService.channelId,
      },
    );

    final report = await service.check();
    final labels = report.checks
        .map((check) => check.actionLabel)
        .whereType<String>()
        .toList();

    expect(labels, containsAll(<String>['通知授权', '精准闹钟', '弹屏权限']));
    expect(labels, isNot(contains('去授权')));
    expect(labels.toSet(), hasLength(labels.length));
  });

  test('检测到旧通知渠道时提示用户检查声音渠道', () async {
    final service = PermissionHealthService(
      notificationGrantedReader: () async => true,
      exactAlarmGrantedReader: () async => true,
      fullScreenIntentGrantedReader: () async => true,
      isAndroidReader: () => true,
      isIOSReader: () => false,
      androidDeviceReader: () async => const AndroidDeviceInfoLite(
        manufacturer: 'Google',
        brand: 'google',
        model: 'Pixel 8',
        sdkInt: 34,
      ),
      channelIdsReader: () async => <String>{
        NotificationService.channelId,
        AlarmService.channelId,
        'duoyi_general_alerts_v3',
        'duoyi_alarm',
      },
    );

    final report = await service.check();

    final legacy = report.checks.firstWhere(
      (check) => check.id == 'legacy_notification_channels',
    );
    expect(legacy.status, PermissionHealthStatus.warning);
    expect(legacy.manual, isTrue);
    expect(legacy.action, PermissionHealthAction.none);
    expect(legacy.subtitle, contains('duoyi_general_alerts_v3'));
    expect(legacy.subtitle, contains('duoyi_alarm'));
  });
}
