import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/platform_info.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/services/alarm_service.dart';
import 'package:duoyi/services/local_notifications.dart';
import 'package:duoyi/services/native_reminder_ringtone.dart';
import 'package:duoyi/services/notification_settings.dart';
import 'package:duoyi/services/permission_health_service.dart';

Future<SystemNotificationAudioStatus?> _okAudioStatus() async =>
    const SystemNotificationAudioStatus(
      alarmVolume: 5,
      alarmMaxVolume: 10,
      notificationVolume: 5,
      notificationMaxVolume: 10,
      ringVolume: 5,
      ringMaxVolume: 10,
      dndSupported: true,
      interruptionFilter: 1,
      notificationPolicyAccessGranted: false,
    );

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
      systemAudioStatusReader: _okAudioStatus,
      channelIdsReader: () async => <String>{
        NotificationService.channelId,
        AlarmService.channelId,
        NativeReminderRingtone.statusChannelId,
        NativeReminderRingtone.fallbackChannelId,
        LocalNotifications.quickAddChannelId,
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
      systemAudioStatusReader: _okAudioStatus,
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
      systemAudioStatusReader: _okAudioStatus,
      channelIdsReader: () async => <String>{
        NotificationService.channelId,
        AlarmService.channelId,
        NativeReminderRingtone.statusChannelId,
        NativeReminderRingtone.fallbackChannelId,
        LocalNotifications.quickAddChannelId,
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
      systemAudioStatusReader: _okAudioStatus,
      channelIdsReader: () async => <String>{
        NotificationService.channelId,
        AlarmService.channelId,
        NativeReminderRingtone.statusChannelId,
        NativeReminderRingtone.fallbackChannelId,
        LocalNotifications.quickAddChannelId,
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
      systemAudioStatusReader: _okAudioStatus,
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
      systemAudioStatusReader: _okAudioStatus,
      channelIdsReader: () async => <String>{
        NotificationService.channelId,
        AlarmService.channelId,
        NativeReminderRingtone.statusChannelId,
        NativeReminderRingtone.fallbackChannelId,
        LocalNotifications.quickAddChannelId,
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

  test('通知渠道静音时不会误报健康', () async {
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
      systemAudioStatusReader: _okAudioStatus,
      channelIdsReader: () async => <String>{
        NotificationService.channelId,
        AlarmService.channelId,
        NativeReminderRingtone.statusChannelId,
        NativeReminderRingtone.fallbackChannelId,
        LocalNotifications.quickAddChannelId,
      },
      channelStatusesReader: (_) async => const {
        NotificationService.channelId: NotificationChannelStatus(
          exists: true,
          importance: 4,
          hasSound: false,
        ),
        AlarmService.channelId: NotificationChannelStatus(
          exists: true,
          importance: 4,
          hasSound: true,
        ),
        NativeReminderRingtone.statusChannelId: NotificationChannelStatus(
          exists: true,
          importance: 2,
          hasSound: false,
        ),
        NativeReminderRingtone.fallbackChannelId: NotificationChannelStatus(
          exists: true,
          importance: 4,
          hasSound: true,
        ),
      },
    );

    final report = await service.check();

    expect(report.summaryStatus, PermissionHealthStatus.warning);
    final sound = report.checks.firstWhere(
      (check) => check.id == 'notification_channel_sound',
    );
    expect(sound.title, '渠道声音');
    expect(sound.subtitle, contains('已静音 普通提醒'));
    expect(sound.actionLabel, '渠道设置');
    expect(sound.actionChannelIds, contains(NotificationService.channelId));
  });

  test('通知渠道优先级过低时提示打开横幅和声音入口', () async {
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
      systemAudioStatusReader: _okAudioStatus,
      channelIdsReader: () async => <String>{
        NotificationService.channelId,
        AlarmService.channelId,
        NativeReminderRingtone.statusChannelId,
        NativeReminderRingtone.fallbackChannelId,
        LocalNotifications.quickAddChannelId,
      },
      channelStatusesReader: (_) async => const {
        NotificationService.channelId: NotificationChannelStatus(
          exists: true,
          importance: 2,
          hasSound: true,
        ),
        AlarmService.channelId: NotificationChannelStatus(
          exists: true,
          importance: 4,
          hasSound: true,
        ),
        NativeReminderRingtone.statusChannelId: NotificationChannelStatus(
          exists: true,
          importance: 2,
          hasSound: false,
        ),
        NativeReminderRingtone.fallbackChannelId: NotificationChannelStatus(
          exists: true,
          importance: 4,
          hasSound: true,
        ),
      },
    );

    final report = await service.check();

    expect(report.summaryStatus, PermissionHealthStatus.warning);
    final sound = report.checks.firstWhere(
      (check) => check.id == 'notification_channel_sound',
    );
    expect(sound.subtitle, contains('优先级过低 普通提醒'));
    expect(sound.subtitle, contains('声音、横幅和锁屏显示'));
    expect(sound.actionChannelIds, contains(NotificationService.channelId));
  });

  test('原生闹钟派发失败会进入通知健康诊断', () async {
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
      systemAudioStatusReader: _okAudioStatus,
      channelIdsReader: () async => <String>{
        NotificationService.channelId,
        AlarmService.channelId,
        NativeReminderRingtone.statusChannelId,
        NativeReminderRingtone.fallbackChannelId,
        LocalNotifications.quickAddChannelId,
      },
      nativeReminderIssueReader: () async => NativeReminderDeliveryIssue(
        id: 42,
        reason: 'fallback_notification_permission_denied',
        message: '系统通知权限关闭，前台铃声服务失败后无法展示兜底通知。',
        timestamp: DateTime.fromMillisecondsSinceEpoch(123),
      ),
    );

    final report = await service.check();

    expect(report.summaryStatus, PermissionHealthStatus.warning);
    final nativeIssue = report.checks.firstWhere(
      (check) => check.id == 'native_reminder_delivery',
    );
    expect(nativeIssue.title, '闹钟响铃诊断');
    expect(nativeIssue.subtitle, contains('无法展示兜底通知'));
    expect(nativeIssue.actionLabel, '系统设置');
    expect(nativeIssue.manual, isTrue);
  });

  test('闹钟兜底通知渠道缺失或静音时会进入健康诊断', () async {
    final missingService = PermissionHealthService(
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
      systemAudioStatusReader: _okAudioStatus,
      channelIdsReader: () async => <String>{
        NotificationService.channelId,
        AlarmService.channelId,
        NativeReminderRingtone.statusChannelId,
        LocalNotifications.quickAddChannelId,
      },
    );

    final missingReport = await missingService.check();
    final channels = missingReport.checks.firstWhere(
      (check) => check.id == 'notification_channels',
    );
    expect(channels.status, PermissionHealthStatus.warning);
    expect(
      channels.subtitle,
      contains(NativeReminderRingtone.fallbackChannelId),
    );

    final mutedService = PermissionHealthService(
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
      systemAudioStatusReader: _okAudioStatus,
      channelIdsReader: () async => <String>{
        NotificationService.channelId,
        AlarmService.channelId,
        NativeReminderRingtone.statusChannelId,
        NativeReminderRingtone.fallbackChannelId,
        LocalNotifications.quickAddChannelId,
      },
      channelStatusesReader: (_) async => const {
        NotificationService.channelId: NotificationChannelStatus(
          exists: true,
          importance: 4,
          hasSound: true,
        ),
        AlarmService.channelId: NotificationChannelStatus(
          exists: true,
          importance: 4,
          hasSound: true,
        ),
        NativeReminderRingtone.statusChannelId: NotificationChannelStatus(
          exists: true,
          importance: 2,
          hasSound: false,
        ),
        NativeReminderRingtone.fallbackChannelId: NotificationChannelStatus(
          exists: true,
          importance: 4,
          hasSound: false,
        ),
      },
    );

    final mutedReport = await mutedService.check();
    final sound = mutedReport.checks.firstWhere(
      (check) => check.id == 'notification_channel_sound',
    );
    expect(sound.subtitle, contains('闹钟兜底通知'));
    expect(
      sound.actionChannelIds,
      contains(NativeReminderRingtone.fallbackChannelId),
    );
  });

  test('通知栏快捷入口渠道纳入健康检查但低优先级不误报', () async {
    final missingService = PermissionHealthService(
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
      systemAudioStatusReader: _okAudioStatus,
      channelIdsReader: () async => <String>{
        NotificationService.channelId,
        AlarmService.channelId,
        NativeReminderRingtone.statusChannelId,
        NativeReminderRingtone.fallbackChannelId,
      },
    );

    final missingReport = await missingService.check();
    final missingChannels = missingReport.checks.firstWhere(
      (check) => check.id == 'notification_channels',
    );
    expect(missingChannels.status, PermissionHealthStatus.warning);
    expect(
      missingChannels.subtitle,
      contains(LocalNotifications.quickAddChannelId),
    );

    final lowService = PermissionHealthService(
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
      systemAudioStatusReader: _okAudioStatus,
      channelIdsReader: () async => <String>{
        NotificationService.channelId,
        AlarmService.channelId,
        NativeReminderRingtone.statusChannelId,
        NativeReminderRingtone.fallbackChannelId,
        LocalNotifications.quickAddChannelId,
      },
      channelStatusesReader: (_) async => const {
        LocalNotifications.quickAddChannelId: NotificationChannelStatus(
          exists: true,
          importance: 2,
          hasSound: false,
        ),
      },
    );

    final lowReport = await lowService.check();
    final channelSoundChecks = lowReport.checks.where(
      (check) => check.id == 'notification_channel_sound',
    );
    expect(channelSoundChecks, isEmpty);
  });

  test('系统闹钟音量为 0 或勿扰开启时会进入健康诊断', () async {
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
      systemAudioStatusReader: () async => const SystemNotificationAudioStatus(
        alarmVolume: 0,
        alarmMaxVolume: 10,
        notificationVolume: 0,
        notificationMaxVolume: 10,
        ringVolume: 3,
        ringMaxVolume: 10,
        dndSupported: true,
        interruptionFilter: 2,
        notificationPolicyAccessGranted: false,
      ),
      channelIdsReader: () async => <String>{
        NotificationService.channelId,
        AlarmService.channelId,
        NativeReminderRingtone.statusChannelId,
        NativeReminderRingtone.fallbackChannelId,
        LocalNotifications.quickAddChannelId,
      },
    );

    final report = await service.check();

    expect(report.summaryStatus, PermissionHealthStatus.blocked);
    final alarmVolume = report.checks.firstWhere(
      (check) => check.id == 'system_alarm_volume',
    );
    expect(alarmVolume.title, '系统闹钟音量');
    expect(alarmVolume.subtitle, contains('闹钟音量为 0'));
    final notificationVolume = report.checks.firstWhere(
      (check) => check.id == 'system_notification_volume',
    );
    expect(notificationVolume.subtitle, contains('通知音量为 0'));
    final dnd = report.checks.firstWhere(
      (check) => check.id == 'system_dnd_mode',
    );
    expect(dnd.title, '勿扰模式');
    expect(dnd.subtitle, contains('勿扰模式'));
  });
}
