import '../core/platform_info.dart';
import '../providers/notification_service.dart';
import 'alarm_service.dart';
import 'local_notifications.dart';

enum PermissionHealthStatus { ok, warning, blocked, unknown }

enum PermissionHealthAction {
  requestNotificationPermission,
  requestExactAlarmPermission,
  requestFullScreenIntentPermission,
  openAppSettings,
  none,
}

class PermissionHealthCheck {
  final String id;
  final String title;
  final String subtitle;
  final PermissionHealthStatus status;
  final PermissionHealthAction? action;
  final String? actionLabel;
  final bool manual;

  const PermissionHealthCheck({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.status,
    this.action,
    this.actionLabel,
    this.manual = false,
  });
}

class NotificationHealthReport {
  final bool notificationGranted;
  final bool exactAlarmGranted;
  final bool fullScreenIntentGranted;
  final Set<String>? channelIds;
  final AndroidDeviceInfoLite? androidDevice;
  final bool isAndroid;
  final bool isIOS;
  final DateTime checkedAt;
  final List<PermissionHealthCheck> checks;

  const NotificationHealthReport({
    required this.notificationGranted,
    required this.exactAlarmGranted,
    required this.fullScreenIntentGranted,
    required this.channelIds,
    required this.androidDevice,
    required this.isAndroid,
    required this.isIOS,
    required this.checkedAt,
    required this.checks,
  });

  bool get isXiaomiLike => androidDevice?.isXiaomiLike ?? false;

  bool get hasBlockingIssue =>
      checks.any((check) => check.status == PermissionHealthStatus.blocked);

  bool get hasWarnings =>
      checks.any((check) => check.status == PermissionHealthStatus.warning);

  bool get hasUnknown =>
      checks.any((check) => check.status == PermissionHealthStatus.unknown);

  PermissionHealthStatus get summaryStatus {
    if (hasBlockingIssue) return PermissionHealthStatus.blocked;
    if (hasWarnings) return PermissionHealthStatus.warning;
    if (hasUnknown) return PermissionHealthStatus.unknown;
    return PermissionHealthStatus.ok;
  }

  String get summaryTitle {
    switch (summaryStatus) {
      case PermissionHealthStatus.ok:
        return '通知健康';
      case PermissionHealthStatus.warning:
        return '需要确认';
      case PermissionHealthStatus.blocked:
        return '需要修复';
      case PermissionHealthStatus.unknown:
        return '部分未知';
    }
  }

  String get summarySubtitle {
    if (!isAndroid) {
      return notificationGranted ? '当前平台通知权限正常' : '当前平台通知权限未授权';
    }
    if (hasBlockingIssue) {
      return '存在需要修复的权限或系统开关';
    }
    if (hasWarnings) {
      return isXiaomiLike ? '小米/MIUI 仍需确认后台、锁屏和电池策略' : '仍有系统策略需要人工确认';
    }
    if (hasUnknown) {
      return '部分系统状态无法自动读取';
    }
    return '系统通知、渠道、精准闹钟与弹屏权限均正常';
  }
}

typedef BoolReader = Future<bool> Function();
typedef ChannelIdsReader = Future<Set<String>?> Function();
typedef AndroidDeviceReader = Future<AndroidDeviceInfoLite?> Function();

class PermissionHealthService {
  static final PermissionHealthService instance = PermissionHealthService._();

  final BoolReader _notificationGrantedReader;
  final BoolReader _exactAlarmGrantedReader;
  final BoolReader _fullScreenIntentGrantedReader;
  final bool Function() _isAndroidReader;
  final bool Function() _isIOSReader;
  final AndroidDeviceReader _androidDeviceReader;
  final ChannelIdsReader _channelIdsReader;

  PermissionHealthService({
    BoolReader? notificationGrantedReader,
    BoolReader? exactAlarmGrantedReader,
    BoolReader? fullScreenIntentGrantedReader,
    bool Function()? isAndroidReader,
    bool Function()? isIOSReader,
    AndroidDeviceReader? androidDeviceReader,
    ChannelIdsReader? channelIdsReader,
  }) : _notificationGrantedReader =
           notificationGrantedReader ?? _defaultNotificationGranted,
       _exactAlarmGrantedReader =
           exactAlarmGrantedReader ?? _defaultExactAlarmGranted,
       _fullScreenIntentGrantedReader =
           fullScreenIntentGrantedReader ?? _defaultFullScreenIntentGranted,
       _isAndroidReader = isAndroidReader ?? (() => PlatformInfo.isAndroid),
       _isIOSReader = isIOSReader ?? (() => PlatformInfo.isIOS),
       _androidDeviceReader =
           androidDeviceReader ?? PlatformInfo.getAndroidDeviceInfo,
       _channelIdsReader = channelIdsReader ?? _defaultChannelIds;

  PermissionHealthService._()
    : _notificationGrantedReader = _defaultNotificationGranted,
      _exactAlarmGrantedReader = _defaultExactAlarmGranted,
      _fullScreenIntentGrantedReader = _defaultFullScreenIntentGranted,
      _isAndroidReader = (() => PlatformInfo.isAndroid),
      _isIOSReader = (() => PlatformInfo.isIOS),
      _androidDeviceReader = PlatformInfo.getAndroidDeviceInfo,
      _channelIdsReader = _defaultChannelIds;

  static Future<bool> _defaultNotificationGranted() async {
    return LocalNotifications.instance.refreshPermission();
  }

  static Future<bool> _defaultExactAlarmGranted() async {
    return AlarmService.instance.hasExactAlarmPermission();
  }

  static Future<bool> _defaultFullScreenIntentGranted() async {
    return AlarmService.instance.hasFullScreenIntentPermission();
  }

  static Future<Set<String>?> _defaultChannelIds() async {
    final ids = <String>{};

    final local = await LocalNotifications.instance.notificationChannelIds();
    if (local == null) return null;
    ids.addAll(local);

    final alarm = await AlarmService.instance.notificationChannelIds();
    if (alarm == null) return null;
    ids.addAll(alarm);

    return ids;
  }

  Future<NotificationHealthReport> check() async {
    final isAndroid = _isAndroidReader();
    final isIOS = _isIOSReader();
    final notificationGranted = await _notificationGrantedReader();
    final exactAlarmGranted = isAndroid
        ? await _exactAlarmGrantedReader()
        : true;
    final fullScreenIntentGranted = isAndroid
        ? await _fullScreenIntentGrantedReader()
        : true;
    final device = isAndroid ? await _androidDeviceReader() : null;
    final channelIds = isAndroid ? await _channelIdsReader() : const <String>{};

    final checks = <PermissionHealthCheck>[
      PermissionHealthCheck(
        id: 'notification_permission',
        title: '系统通知权限',
        subtitle: notificationGranted ? '已授权，提醒可以进入通知中心' : '未授权，提醒不会正常显示',
        status: notificationGranted
            ? PermissionHealthStatus.ok
            : PermissionHealthStatus.blocked,
        action: notificationGranted
            ? null
            : PermissionHealthAction.requestNotificationPermission,
        actionLabel: notificationGranted ? null : '去授权',
      ),
    ];

    if (isAndroid) {
      final sdkInt = device?.sdkInt;
      final exactRelevant = sdkInt == null || sdkInt >= 31;
      checks.add(
        PermissionHealthCheck(
          id: 'exact_alarm_permission',
          title: '精准闹钟权限',
          subtitle: exactRelevant
              ? (exactAlarmGranted ? '已授权，强提醒更可靠' : '未授权，闹钟提醒可能延后或降级')
              : 'Android 12 以下无需单独申请',
          status: exactRelevant
              ? (exactAlarmGranted
                    ? PermissionHealthStatus.ok
                    : PermissionHealthStatus.blocked)
              : PermissionHealthStatus.ok,
          action: exactRelevant && !exactAlarmGranted
              ? PermissionHealthAction.requestExactAlarmPermission
              : null,
          actionLabel: exactRelevant && !exactAlarmGranted ? '去授权' : null,
        ),
      );

      final fullScreenRelevant = sdkInt == null || sdkInt >= 34;
      checks.add(
        PermissionHealthCheck(
          id: 'full_screen_intent_permission',
          title: '弹出屏幕权限',
          subtitle: fullScreenRelevant
              ? (fullScreenIntentGranted
                    ? '已允许，强提醒可弹出确认界面'
                    : '未允许，锁屏或桌面时可能只进入通知栏')
              : 'Android 14 以下通常无需单独申请',
          status: fullScreenRelevant
              ? (fullScreenIntentGranted
                    ? PermissionHealthStatus.ok
                    : PermissionHealthStatus.blocked)
              : PermissionHealthStatus.ok,
          action: fullScreenRelevant && !fullScreenIntentGranted
              ? PermissionHealthAction.requestFullScreenIntentPermission
              : null,
          actionLabel: fullScreenRelevant && !fullScreenIntentGranted
              ? '去授权'
              : null,
        ),
      );

      final channelRelevant = sdkInt == null || sdkInt >= 26;
      if (channelRelevant) {
        final required = <String>{
          NotificationService.channelId,
          AlarmService.channelId,
        };
        final legacy = <String>{
          ...NotificationService.legacyChannelIds,
          ...AlarmService.legacyChannelIds,
        };
        if (channelIds == null) {
          checks.add(
            const PermissionHealthCheck(
              id: 'notification_channels',
              title: '通知渠道',
              subtitle: '无法读取系统通知渠道状态',
              status: PermissionHealthStatus.unknown,
            ),
          );
        } else {
          final missing = required.difference(channelIds);
          final stale = channelIds.intersection(legacy);
          checks.add(
            PermissionHealthCheck(
              id: 'notification_channels',
              title: '通知渠道',
              subtitle: missing.isEmpty
                  ? '通知提醒 / 强提醒渠道均已创建'
                  : '缺少 ${missing.join('、')} 渠道；请先点测试通知让系统创建渠道',
              status: missing.isEmpty
                  ? PermissionHealthStatus.ok
                  : PermissionHealthStatus.warning,
              action: missing.isEmpty ? null : PermissionHealthAction.none,
              actionLabel: missing.isEmpty ? null : '先测试',
            ),
          );
          if (stale.isNotEmpty) {
            checks.add(
              PermissionHealthCheck(
                id: 'legacy_notification_channels',
                title: '旧通知渠道',
                subtitle:
                    '检测到旧渠道 ${stale.join('、')}。新版本已改用新渠道；若仍无声，只需在系统通知设置里检查“多仪 · 通知提醒”和“多仪 · 强提醒”',
                status: PermissionHealthStatus.warning,
                action: PermissionHealthAction.none,
                manual: true,
              ),
            );
          }
        }
      }

      checks.add(
        PermissionHealthCheck(
          id: device?.isXiaomiLike == true
              ? 'xiaomi_notification_policy'
              : 'android_notification_policy',
          title: device?.isXiaomiLike == true ? '小米通知策略' : '后台和电池策略',
          subtitle: device?.isXiaomiLike == true
              ? '确认自启动、后台无限制、锁屏通知和电池优化；这些入口因系统差异无法自动直达'
              : '若定时提醒不稳定，请在系统中允许后台运行并排除电池优化',
          status: PermissionHealthStatus.warning,
          action: PermissionHealthAction.none,
          manual: true,
        ),
      );
    }

    return NotificationHealthReport(
      notificationGranted: notificationGranted,
      exactAlarmGranted: exactAlarmGranted,
      fullScreenIntentGranted: fullScreenIntentGranted,
      channelIds: channelIds,
      androidDevice: device,
      isAndroid: isAndroid,
      isIOS: isIOS,
      checkedAt: DateTime.now(),
      checks: checks,
    );
  }
}
