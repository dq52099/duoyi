import 'package:flutter/material.dart';

import '../models/goal.dart' show ReminderKind;
import '../services/permission_health_service.dart';
import 'surface_components.dart';

class ReminderHealthHint extends StatefulWidget {
  final ReminderKind reminderKind;
  final VoidCallback onOpenSystemSettings;
  final Future<void> Function() onRequestNotificationPermission;
  final Future<void> Function() onRequestExactAlarmPermission;
  final Future<void> Function() onRequestFullScreenIntentPermission;

  const ReminderHealthHint({
    super.key,
    required this.reminderKind,
    required this.onOpenSystemSettings,
    required this.onRequestNotificationPermission,
    required this.onRequestExactAlarmPermission,
    required this.onRequestFullScreenIntentPermission,
  });

  @override
  State<ReminderHealthHint> createState() => _ReminderHealthHintState();
}

class _ReminderHealthHintState extends State<ReminderHealthHint>
    with WidgetsBindingObserver {
  late Future<NotificationHealthReport> _future;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = PermissionHealthService.instance.check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _future = PermissionHealthService.instance.check();
    });
  }

  Future<void> _handleNotificationPermission() async {
    await widget.onRequestNotificationPermission();
    await _refresh();
  }

  Future<void> _handleExactAlarmPermission() async {
    await widget.onRequestExactAlarmPermission();
    await _refresh();
  }

  Future<void> _handleFullScreenIntentPermission() async {
    await widget.onRequestFullScreenIntentPermission();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<NotificationHealthReport>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return AppActionTile(
            icon: Icons.error_outline,
            label: '提醒健康',
            color: Colors.red,
            subtitle: '无法读取系统提醒状态',
            onTap: widget.onOpenSystemSettings,
          );
        }

        final report = snap.data;
        final notificationGranted = report?.notificationGranted ?? false;
        final exactGranted = report?.exactAlarmGranted ?? false;
        final fullScreenIntentGranted =
            report?.fullScreenIntentGranted ?? false;
        final isXiaomi = report?.isXiaomiLike ?? false;
        final alarmKind = widget.reminderKind == ReminderKind.alarm;

        PermissionHealthStatus status = PermissionHealthStatus.unknown;
        String subtitle = '正在读取提醒健康状态';
        VoidCallback? action;
        String? actionLabel;
        IconData icon = Icons.notifications_outlined;

        if (report != null) {
          if (!notificationGranted) {
            status = PermissionHealthStatus.blocked;
            subtitle = '系统通知未授权，提醒不会正常显示';
            action = _handleNotificationPermission;
            actionLabel = '通知授权';
            icon = Icons.notifications_off_outlined;
          } else if (alarmKind && !exactGranted) {
            status = PermissionHealthStatus.blocked;
            subtitle = '系统通知已授权，但精准闹钟未开启，强提醒可能延后';
            action = _handleExactAlarmPermission;
            actionLabel = '精准闹钟';
            icon = Icons.alarm_off_outlined;
          } else if (alarmKind && !fullScreenIntentGranted) {
            status = PermissionHealthStatus.blocked;
            subtitle = '弹出屏幕权限未允许，强提醒可能只显示在通知栏';
            action = _handleFullScreenIntentPermission;
            actionLabel = '弹屏权限';
            icon = Icons.phonelink_lock_outlined;
          } else if (report.hasWarnings) {
            status = PermissionHealthStatus.warning;
            subtitle = isXiaomi
                ? 'HyperOS/MIUI 需确认自启动、后台、电池、锁屏、横幅和渠道声音'
                : 'Android 设备还要检查后台和电池限制';
            icon = Icons.tips_and_updates_outlined;
          } else if (report.hasUnknown) {
            status = PermissionHealthStatus.unknown;
            subtitle = '部分系统状态无法自动读取';
            icon = Icons.help_outline;
          } else {
            status = PermissionHealthStatus.ok;
            subtitle = alarmKind ? '系统通知、精准闹钟和弹屏权限均已就绪' : '系统通知已授权，提醒可正常进入通知中心';
            icon = Icons.notifications_active_outlined;
          }
        }

        final color = switch (status) {
          PermissionHealthStatus.ok => Colors.green,
          PermissionHealthStatus.warning => Colors.orange,
          PermissionHealthStatus.blocked => Colors.red,
          PermissionHealthStatus.unknown => Colors.blueGrey,
        };

        return AppActionTile(
          icon: icon,
          label: '提醒健康',
          color: color,
          subtitle: subtitle,
          onTap: widget.onOpenSystemSettings,
          trailing: action == null
              ? Icon(Icons.check_circle, color: color)
              : TextButton(onPressed: action, child: Text(actionLabel ?? '处理')),
        );
      },
    );
  }
}
