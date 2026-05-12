import 'package:flutter/material.dart';

import '../services/permission_health_service.dart';
import 'surface_components.dart';

class NotificationHealthCard extends StatelessWidget {
  final NotificationHealthReport? report;
  final bool loading;
  final String? errorText;
  final int? pendingCount;
  final DateTime? lastTestAt;
  final VoidCallback onRefresh;
  final VoidCallback onOpenSystemSettings;
  final VoidCallback onSendTest;
  final VoidCallback onClearPending;
  final VoidCallback onRequestNotificationPermission;
  final VoidCallback onRequestExactAlarmPermission;

  const NotificationHealthCard({
    super.key,
    required this.onRefresh,
    required this.onOpenSystemSettings,
    required this.onSendTest,
    required this.onClearPending,
    required this.onRequestNotificationPermission,
    required this.onRequestExactAlarmPermission,
    this.report,
    this.loading = false,
    this.errorText,
    this.pendingCount,
    this.lastTestAt,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final report = this.report;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: '通知健康检查',
            subtitle:
                report?.summarySubtitle ??
                (loading ? '正在检查系统权限与通知渠道' : '用于排查系统通知和闹钟异常'),
            actionLabel: '刷新',
            actionIcon: Icons.refresh_rounded,
            onAction: onRefresh,
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),
          _SummaryBanner(report: report, loading: loading),
          if (errorText != null) ...[
            const SizedBox(height: 12),
            AppActionTile(
              icon: Icons.error_outline,
              label: '检测失败',
              color: Colors.red,
              subtitle: errorText,
              onTap: onRefresh,
            ),
          ],
          if (report != null) ...[
            const SizedBox(height: 8),
            for (final check in report.checks) ...[
              _HealthCheckTile(
                check: check,
                onRequestNotificationPermission:
                    onRequestNotificationPermission,
                onRequestExactAlarmPermission: onRequestExactAlarmPermission,
                onOpenSystemSettings: onOpenSystemSettings,
              ),
              const SizedBox(height: 2),
            ],
          ],
          const SizedBox(height: 8),
          AppSettingsTile(
            icon: Icons.notifications_active_outlined,
            color: cs.primary,
            title: '发送测试通知',
            subtitle: lastTestAt == null
                ? '触发一条测试通知，并写入通知历史'
                : '上次测试 ${_formatDateTime(lastTestAt!)}',
            onTap: onSendTest,
          ),
          AppSettingsTile(
            icon: Icons.settings_outlined,
            color: Colors.blueGrey,
            title: '系统应用设置',
            subtitle: '检查通知、锁屏、后台和电池限制',
            onTap: onOpenSystemSettings,
          ),
          AppSettingsTile(
            icon: Icons.schedule,
            color: Colors.teal,
            title: '已调度提醒',
            subtitle: pendingCount == null
                ? '正在读取待触发队列'
                : '${pendingCount!} 条待触发',
            trailing: pendingCount == null
                ? null
                : (pendingCount! > 0
                      ? TextButton(
                          onPressed: onClearPending,
                          child: const Text('全部取消'),
                        )
                      : const Icon(Icons.check_circle, color: Colors.green)),
          ),
        ],
      ),
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  final NotificationHealthReport? report;
  final bool loading;

  const _SummaryBanner({required this.report, required this.loading});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = report?.summaryStatus ?? PermissionHealthStatus.unknown;
    final color = _statusColor(status, cs);
    final icon = _statusIcon(status);
    final title = report?.summaryTitle ?? (loading ? '正在检查' : '尚未读取通知健康状态');
    final subtitle = report == null
        ? (loading ? '请稍候，正在读取权限和渠道状态' : '刷新后可查看系统通知健康结果')
        : '${report!.checks.length} 项检查 · ${_formatDateTime(report!.checkedAt)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.66),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthCheckTile extends StatelessWidget {
  final PermissionHealthCheck check;
  final VoidCallback onRequestNotificationPermission;
  final VoidCallback onRequestExactAlarmPermission;
  final VoidCallback onOpenSystemSettings;

  const _HealthCheckTile({
    required this.check,
    required this.onRequestNotificationPermission,
    required this.onRequestExactAlarmPermission,
    required this.onOpenSystemSettings,
  });

  @override
  Widget build(BuildContext context) {
    final action = switch (check.action) {
      PermissionHealthAction.requestNotificationPermission =>
        onRequestNotificationPermission,
      PermissionHealthAction.requestExactAlarmPermission =>
        onRequestExactAlarmPermission,
      PermissionHealthAction.openAppSettings => onOpenSystemSettings,
      null => null,
    };

    final color = _statusColor(check.status, Theme.of(context).colorScheme);
    final icon = check.manual
        ? Icons.tips_and_updates_outlined
        : _statusIcon(check.status);

    return AppSettingsTile(
      icon: icon,
      color: color,
      title: check.title,
      subtitle: check.manual ? '${check.subtitle} · 需要人工确认' : check.subtitle,
      trailing: action == null
          ? Icon(_statusTrailingIcon(check.status), color: color)
          : TextButton(
              onPressed: action,
              child: Text(check.actionLabel ?? '处理'),
            ),
    );
  }
}

Color _statusColor(PermissionHealthStatus status, ColorScheme cs) {
  switch (status) {
    case PermissionHealthStatus.ok:
      return Colors.green;
    case PermissionHealthStatus.warning:
      return Colors.orange;
    case PermissionHealthStatus.blocked:
      return Colors.red;
    case PermissionHealthStatus.unknown:
      return cs.primary;
  }
}

IconData _statusIcon(PermissionHealthStatus status) {
  switch (status) {
    case PermissionHealthStatus.ok:
      return Icons.check_circle_outline;
    case PermissionHealthStatus.warning:
      return Icons.warning_amber_outlined;
    case PermissionHealthStatus.blocked:
      return Icons.error_outline;
    case PermissionHealthStatus.unknown:
      return Icons.help_outline;
  }
}

IconData _statusTrailingIcon(PermissionHealthStatus status) {
  switch (status) {
    case PermissionHealthStatus.ok:
      return Icons.check_circle;
    case PermissionHealthStatus.warning:
      return Icons.info_outline;
    case PermissionHealthStatus.blocked:
      return Icons.priority_high;
    case PermissionHealthStatus.unknown:
      return Icons.help_outline;
  }
}

String _formatDateTime(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  final hh = value.hour.toString().padLeft(2, '0');
  final mm = value.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $hh:$mm';
}
