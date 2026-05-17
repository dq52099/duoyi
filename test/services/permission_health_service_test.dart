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
    expect(notification.actionLabel, '去授权');
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
    final channels = report.checks.firstWhere(
      (check) => check.id == 'notification_channels',
    );
    expect(channels.status, PermissionHealthStatus.warning);
  });

  test('Xiaomi-like 设备会输出人工检查项', () async {
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
    final manualIds = report.checks
        .where((check) => check.manual)
        .map((e) => e.id);
    expect(
      manualIds,
      containsAll(<String>[
        'xiaomi_autostart',
        'xiaomi_background',
        'xiaomi_lockscreen',
        'xiaomi_battery',
      ]),
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
    expect(legacy.subtitle, contains('duoyi_general_alerts_v3'));
    expect(legacy.subtitle, contains('duoyi_alarm'));
  });
}
