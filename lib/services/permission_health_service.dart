import 'package:flutter/foundation.dart';

import '../core/platform_info.dart';
import '../providers/notification_service.dart';
import 'alarm_service.dart';
import 'local_notifications.dart';
import 'native_reminder_ringtone.dart';
import 'notification_settings.dart';

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
  final List<String> actionChannelIds;
  final bool manual;

  const PermissionHealthCheck({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.status,
    this.action,
    this.actionLabel,
    this.actionChannelIds = const <String>[],
    this.manual = false,
  });
}

class NotificationHealthReport {
  final bool notificationGranted;
  final bool exactAlarmGranted;
  final bool fullScreenIntentGranted;
  final Set<String>? channelIds;
  final Map<String, NotificationChannelStatus>? channelStatuses;
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
    this.channelStatuses,
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
      return isXiaomiLike
          ? 'HyperOS/MIUI 仍需确认自启动、后台、电池、锁屏、横幅和渠道声音'
          : '仍有系统策略需要人工确认';
    }
    if (hasUnknown) {
      return '部分系统状态无法自动读取';
    }
    return '系统通知、渠道、精准闹钟与弹屏权限均正常';
  }
}

typedef BoolReader = Future<bool> Function();
typedef ChannelIdsReader = Future<Set<String>?> Function();
typedef ChannelStatusesReader =
    Future<Map<String, NotificationChannelStatus>?> Function(
      Iterable<String> channelIds,
    );
typedef AndroidDeviceReader = Future<AndroidDeviceInfoLite?> Function();
typedef NativeReminderIssueReader =
    Future<NativeReminderDeliveryIssue?> Function();
typedef SystemAudioStatusReader =
    Future<SystemNotificationAudioStatus?> Function();

class PermissionHealthService {
  static final PermissionHealthService instance = PermissionHealthService._();

  final BoolReader _notificationGrantedReader;
  final BoolReader _exactAlarmGrantedReader;
  final BoolReader _fullScreenIntentGrantedReader;
  final bool Function() _isAndroidReader;
  final bool Function() _isIOSReader;
  final AndroidDeviceReader _androidDeviceReader;
  final ChannelIdsReader _channelIdsReader;
  final ChannelStatusesReader _channelStatusesReader;
  final NativeReminderIssueReader _nativeReminderIssueReader;
  final SystemAudioStatusReader _systemAudioStatusReader;

  PermissionHealthService({
    BoolReader? notificationGrantedReader,
    BoolReader? exactAlarmGrantedReader,
    BoolReader? fullScreenIntentGrantedReader,
    bool Function()? isAndroidReader,
    bool Function()? isIOSReader,
    AndroidDeviceReader? androidDeviceReader,
    ChannelIdsReader? channelIdsReader,
    ChannelStatusesReader? channelStatusesReader,
    NativeReminderIssueReader? nativeReminderIssueReader,
    SystemAudioStatusReader? systemAudioStatusReader,
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
       _channelIdsReader = channelIdsReader ?? _defaultChannelIds,
       _channelStatusesReader =
           channelStatusesReader ??
           NotificationSettings.notificationChannelStatuses,
       _nativeReminderIssueReader =
           nativeReminderIssueReader ??
           NativeReminderRingtone.lastDeliveryIssue,
       _systemAudioStatusReader =
           systemAudioStatusReader ?? NotificationSettings.systemAudioStatus;

  PermissionHealthService._()
    : _notificationGrantedReader = _defaultNotificationGranted,
      _exactAlarmGrantedReader = _defaultExactAlarmGranted,
      _fullScreenIntentGrantedReader = _defaultFullScreenIntentGranted,
      _isAndroidReader = (() => PlatformInfo.isAndroid),
      _isIOSReader = (() => PlatformInfo.isIOS),
      _androidDeviceReader = PlatformInfo.getAndroidDeviceInfo,
      _channelIdsReader = _defaultChannelIds,
      _channelStatusesReader = NotificationSettings.notificationChannelStatuses,
      _nativeReminderIssueReader = NativeReminderRingtone.lastDeliveryIssue,
      _systemAudioStatusReader = NotificationSettings.systemAudioStatus;

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
    Set<String>? channelIds = const <String>{};
    if (isAndroid) {
      try {
        channelIds = await _channelIdsReader();
      } catch (e, st) {
        channelIds = null;
        debugPrint(
          '[PermissionHealthService] notification channel list probe failed: '
          '$e\n$st',
        );
      }
    }
    Map<String, NotificationChannelStatus>? channelStatuses;
    Object? channelStatusProbeError;

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
        actionLabel: notificationGranted ? null : '通知授权',
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
          actionLabel: exactRelevant && !exactAlarmGranted ? '精准闹钟' : null,
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
              ? '弹屏权限'
              : null,
        ),
      );

      final channelRelevant = sdkInt == null || sdkInt >= 26;
      if (channelRelevant) {
        final required = <String>{
          NotificationService.channelId,
          AlarmService.channelId,
          NativeReminderRingtone.statusChannelId,
          NativeReminderRingtone.fallbackChannelId,
          LocalNotifications.quickAddChannelId,
        };
        final legacy = <String>{
          ...NotificationService.legacyChannelIds,
          ...AlarmService.legacyChannelIds,
          ...NativeReminderRingtone.legacyChannelIds,
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
          try {
            channelStatuses = await _channelStatusesReader(required);
          } catch (e, st) {
            channelStatusProbeError = e;
            debugPrint(
              '[PermissionHealthService] notification channel status probe failed: '
              '$e\n$st',
            );
          }
          checks.add(
            PermissionHealthCheck(
              id: 'notification_channels',
              title: '通知渠道',
              subtitle: missing.isEmpty
                  ? '通知提醒 / 强提醒 / 内置铃声状态 / 通知栏快捷入口渠道均已创建；闹钟兜底通知渠道均已创建'
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
                    '检测到旧渠道 ${stale.join('、')}。新版本会改用新渠道并尝试清理旧渠道；若仍无声，请检查“多仪 · 通知提醒”“多仪 · 强提醒”和“闹钟兜底通知”的声音、横幅和锁屏权限',
                status: PermissionHealthStatus.warning,
                action: PermissionHealthAction.none,
                manual: true,
              ),
            );
          }
          if (channelStatusProbeError != null) {
            checks.add(
              PermissionHealthCheck(
                id: 'notification_channel_status',
                title: '通知渠道状态',
                subtitle:
                    '无法读取系统通知渠道声音/静音状态，请打开系统通知设置确认普通提醒、强提醒和闹钟兜底通知均未关闭。($channelStatusProbeError)',
                status: PermissionHealthStatus.unknown,
                action: PermissionHealthAction.openAppSettings,
                actionLabel: '系统设置',
                actionChannelIds: required.toList(growable: false),
              ),
            );
          }
          final muted = <String>[];
          final blocked = <String>[];
          final lowImportance = <String>[];
          for (final entry in (channelStatuses ?? {}).entries) {
            if (entry.key == LocalNotifications.quickAddChannelId) {
              continue;
            }
            final status = entry.value;
            if (!status.exists) continue;
            if (status.isBlocked) {
              blocked.add(entry.key);
            } else if (status.isSilent &&
                entry.key != NativeReminderRingtone.statusChannelId) {
              muted.add(entry.key);
            } else if (status.isLowImportance &&
                entry.key != NativeReminderRingtone.statusChannelId) {
              lowImportance.add(entry.key);
            }
          }
          final affectedChannels = <String>{
            ...blocked,
            ...muted,
            ...lowImportance,
          }.toList(growable: false);
          if (blocked.isNotEmpty ||
              muted.isNotEmpty ||
              lowImportance.isNotEmpty) {
            checks.add(
              PermissionHealthCheck(
                id: 'notification_channel_sound',
                title: '渠道声音',
                subtitle: [
                  if (blocked.isNotEmpty)
                    '已关闭 ${_channelNames(blocked).join('、')}',
                  if (muted.isNotEmpty) '已静音 ${_channelNames(muted).join('、')}',
                  if (lowImportance.isNotEmpty)
                    '优先级过低 ${_channelNames(lowImportance).join('、')}',
                  '请打开对应渠道的声音、横幅和锁屏显示',
                ].join('；'),
                status: blocked.isNotEmpty
                    ? PermissionHealthStatus.blocked
                    : PermissionHealthStatus.warning,
                action: PermissionHealthAction.openAppSettings,
                actionLabel: '渠道设置',
                actionChannelIds: affectedChannels,
              ),
            );
          }
        }
      }

      final audioStatus = await _systemAudioStatusReader();
      if (audioStatus == null) {
        checks.add(
          const PermissionHealthCheck(
            id: 'system_audio_status',
            title: '系统音量与勿扰',
            subtitle: '无法自动读取闹钟音量、通知音量或勿扰状态；若无声请在系统音量面板和勿扰模式中确认',
            status: PermissionHealthStatus.unknown,
            manual: true,
          ),
        );
      } else {
        checks.addAll(_audioHealthChecks(audioStatus));
      }

      checks.addAll(_manualAndroidPolicyChecks(device));

      final nativeIssue = await _nativeReminderIssueReader();
      if (nativeIssue != null && nativeIssue.message.trim().isNotEmpty) {
        checks.add(
          PermissionHealthCheck(
            id: 'native_reminder_delivery',
            title: '闹钟响铃诊断',
            subtitle: nativeIssue.message,
            status: PermissionHealthStatus.warning,
            action: PermissionHealthAction.openAppSettings,
            actionLabel: '系统设置',
            manual: true,
          ),
        );
      }
    }

    return NotificationHealthReport(
      notificationGranted: notificationGranted,
      exactAlarmGranted: exactAlarmGranted,
      fullScreenIntentGranted: fullScreenIntentGranted,
      channelIds: channelIds,
      channelStatuses: channelStatuses,
      androidDevice: device,
      isAndroid: isAndroid,
      isIOS: isIOS,
      checkedAt: DateTime.now(),
      checks: checks,
    );
  }

  List<PermissionHealthCheck> _audioHealthChecks(
    SystemNotificationAudioStatus status,
  ) {
    final checks = <PermissionHealthCheck>[];
    if (status.alarmMuted) {
      checks.add(
        const PermissionHealthCheck(
          id: 'system_alarm_volume',
          title: '系统闹钟音量',
          subtitle: '闹钟音量为 0，内置强提醒使用闹钟音频通道，可能只震动或完全无声',
          status: PermissionHealthStatus.blocked,
          action: PermissionHealthAction.openAppSettings,
          actionLabel: '系统设置',
          manual: true,
        ),
      );
    } else if (status.alarmPercent <= 20) {
      checks.add(
        PermissionHealthCheck(
          id: 'system_alarm_volume',
          title: '系统闹钟音量',
          subtitle: '当前闹钟音量约 ${status.alarmPercent}%，若提醒太轻请调高系统闹钟音量',
          status: PermissionHealthStatus.warning,
          action: PermissionHealthAction.none,
          manual: true,
        ),
      );
    }

    if (status.notificationMuted || status.ringMuted) {
      checks.add(
        PermissionHealthCheck(
          id: 'system_notification_volume',
          title: '系统通知/铃声音量',
          subtitle: [
            if (status.notificationMuted) '通知音量为 0',
            if (status.ringMuted) '铃声音量为 0',
            '普通通知和兜底提示可能无声，请在系统音量面板调高',
          ].join('；'),
          status: PermissionHealthStatus.warning,
          action: PermissionHealthAction.openAppSettings,
          actionLabel: '系统设置',
          manual: true,
        ),
      );
    }

    if (status.dndActive) {
      checks.add(
        PermissionHealthCheck(
          id: 'system_dnd_mode',
          title: '勿扰模式',
          subtitle: status.notificationPolicyAccessGranted
              ? '系统勿扰模式正在开启，通知和闹钟渠道可能被拦截；请允许多仪绕过勿扰或临时关闭勿扰'
              : '系统勿扰模式可能正在开启，且多仪没有勿扰策略访问权限；请检查勿扰模式、闹钟例外和通知例外',
          status: PermissionHealthStatus.warning,
          action: PermissionHealthAction.openAppSettings,
          actionLabel: '勿扰设置',
          manual: true,
        ),
      );
    }

    if (checks.isEmpty) {
      checks.add(
        PermissionHealthCheck(
          id: 'system_audio_status',
          title: '系统音量与勿扰',
          subtitle:
              '闹钟音量约 ${status.alarmPercent}%，通知音量约 ${status.notificationPercent}%，未检测到勿扰拦截',
          status: PermissionHealthStatus.ok,
        ),
      );
    }
    return checks;
  }

  List<PermissionHealthCheck> _manualAndroidPolicyChecks(
    AndroidDeviceInfoLite? device,
  ) {
    if (device?.isXiaomiLike == true) {
      return const [
        PermissionHealthCheck(
          id: 'xiaomi_autostart_policy',
          title: 'HyperOS/MIUI 自启动',
          subtitle: '安全中心或应用管理中允许多仪自启动，避免重启后提醒不恢复',
          status: PermissionHealthStatus.warning,
          action: PermissionHealthAction.none,
          manual: true,
        ),
        PermissionHealthCheck(
          id: 'xiaomi_battery_policy',
          title: 'HyperOS/MIUI 后台与电池',
          subtitle: '把多仪设为后台无限制，关闭省电策略对闹钟和白噪音的限制',
          status: PermissionHealthStatus.warning,
          action: PermissionHealthAction.none,
          manual: true,
        ),
        PermissionHealthCheck(
          id: 'xiaomi_lock_screen_policy',
          title: 'HyperOS/MIUI 锁屏与横幅',
          subtitle: '通知管理中允许锁屏通知、横幅通知、悬浮通知、声音和振动',
          status: PermissionHealthStatus.warning,
          action: PermissionHealthAction.none,
          manual: true,
        ),
        PermissionHealthCheck(
          id: 'xiaomi_channel_sound_policy',
          title: 'HyperOS/MIUI 渠道声音',
          subtitle: '分别检查“多仪 · 通知提醒”和“多仪 · 强提醒”渠道，不要设为静音',
          status: PermissionHealthStatus.warning,
          action: PermissionHealthAction.none,
          manual: true,
        ),
      ];
    }
    return const [
      PermissionHealthCheck(
        id: 'android_notification_policy',
        title: '后台和电池策略',
        subtitle: '若定时提醒不稳定，请在系统中允许后台运行并排除电池优化',
        status: PermissionHealthStatus.warning,
        action: PermissionHealthAction.none,
        manual: true,
      ),
    ];
  }

  List<String> _channelNames(Iterable<String> channelIds) {
    return channelIds.map(_channelName).toList(growable: false);
  }

  String _channelName(String channelId) {
    switch (channelId) {
      case NotificationService.channelId:
        return '普通提醒';
      case AlarmService.channelId:
        return '强提醒';
      case NativeReminderRingtone.fallbackChannelId:
        return '闹钟兜底通知';
      case NativeReminderRingtone.statusChannelId:
        return '内置铃声状态';
      case LocalNotifications.quickAddChannelId:
        return '通知栏快捷入口';
    }
    return channelId;
  }
}
