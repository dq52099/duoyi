import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/notification_ui_copy.dart';
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
    I18n.localeListenable.addListener(_onLocaleChanged);
    _future = PermissionHealthService.instance.check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    I18n.localeListenable.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
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
        final cs = Theme.of(context).colorScheme;
        final isDark = cs.brightness == Brightness.dark;
        if (snap.hasError) {
          return AppActionTile(
            icon: Icons.error_outline,
            label: NotificationUiCopy.reminderHealthLabel,
            color: isDark
                ? DesignTokens.todoOverdueDark
                : DesignTokens.defaultError,
            subtitle: NotificationUiCopy.reminderHealthReadFailed,
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
        String subtitle = NotificationUiCopy.reminderHealthLoading;
        VoidCallback? action;
        String? actionLabel;
        IconData icon = Icons.notifications_outlined;

        if (report != null) {
          if (!notificationGranted) {
            status = PermissionHealthStatus.blocked;
            subtitle = NotificationUiCopy.notificationPermissionMissing;
            action = _handleNotificationPermission;
            actionLabel = NotificationUiCopy.notificationPermissionAction;
            icon = Icons.notifications_off_outlined;
          } else if (alarmKind && !exactGranted) {
            status = PermissionHealthStatus.blocked;
            subtitle = NotificationUiCopy.exactAlarmMissing;
            action = _handleExactAlarmPermission;
            actionLabel = NotificationUiCopy.exactAlarmAction;
            icon = Icons.alarm_off_outlined;
          } else if (alarmKind && !fullScreenIntentGranted) {
            status = PermissionHealthStatus.blocked;
            subtitle = NotificationUiCopy.fullScreenMissing;
            action = _handleFullScreenIntentPermission;
            actionLabel = NotificationUiCopy.fullScreenAction;
            icon = Icons.phonelink_lock_outlined;
          } else if (report.hasWarnings) {
            status = PermissionHealthStatus.warning;
            subtitle = isXiaomi
                ? NotificationUiCopy.xiaomiPolicyWarning
                : NotificationUiCopy.androidPolicyWarning;
            icon = Icons.tips_and_updates_outlined;
          } else if (report.hasUnknown) {
            status = PermissionHealthStatus.unknown;
            subtitle = NotificationUiCopy.unknownPolicyWarning;
            icon = Icons.help_outline;
          } else {
            status = PermissionHealthStatus.ok;
            subtitle = alarmKind
                ? NotificationUiCopy.alarmReadySubtitle
                : NotificationUiCopy.notificationReadySubtitle;
            icon = Icons.notifications_active_outlined;
          }
        }

        final color = switch (status) {
          PermissionHealthStatus.ok =>
            isDark
                ? DesignTokens.todoCompletedDark
                : DesignTokens.defaultSuccess,
          PermissionHealthStatus.warning =>
            isDark ? DesignTokens.todoDueSoonDark : DesignTokens.todoDueSoon,
          PermissionHealthStatus.blocked =>
            isDark ? DesignTokens.todoOverdueDark : DesignTokens.defaultError,
          PermissionHealthStatus.unknown => cs.onSurfaceVariant,
        };

        return AppActionTile(
          icon: icon,
          label: NotificationUiCopy.reminderHealthLabel,
          color: color,
          subtitle: subtitle,
          onTap: widget.onOpenSystemSettings,
          trailing: action == null
              ? Icon(Icons.check_circle, color: color)
              : TextButton(
                  onPressed: action,
                  child: Text(actionLabel ?? NotificationUiCopy.handleAction),
                ),
        );
      },
    );
  }
}
