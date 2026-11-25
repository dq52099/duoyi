import 'app_date_format.dart';
import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/notification_ui_copy.dart';
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
  final ValueChanged<String> onOpenNotificationChannelSettings;
  final VoidCallback onSendTest;
  final VoidCallback onSendStrongTest;
  final VoidCallback onClearPending;
  final VoidCallback onRequestNotificationPermission;
  final VoidCallback onRequestExactAlarmPermission;
  final VoidCallback onRequestFullScreenIntentPermission;

  const NotificationHealthCard({
    super.key,
    required this.onRefresh,
    required this.onOpenSystemSettings,
    required this.onOpenNotificationChannelSettings,
    required this.onSendTest,
    required this.onSendStrongTest,
    required this.onClearPending,
    required this.onRequestNotificationPermission,
    required this.onRequestExactAlarmPermission,
    required this.onRequestFullScreenIntentPermission,
    this.report,
    this.loading = false,
    this.errorText,
    this.pendingCount,
    this.lastTestAt,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final report = this.report;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: NotificationUiCopy.healthCardTitle,
            subtitle: report != null
                ? NotificationUiCopy.healthReportSummarySubtitle(report)
                : (loading
                      ? NotificationUiCopy.healthCheckingSubtitle
                      : NotificationUiCopy.healthIntroSubtitle),
            actionLabel: NotificationUiCopy.refreshActionShort,
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
              label: NotificationUiCopy.healthCheckFailed,
              color: cs.brightness == Brightness.dark
                  ? DesignTokens.todoOverdueDark
                  : DesignTokens.defaultError,
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
                onRequestFullScreenIntentPermission:
                    onRequestFullScreenIntentPermission,
                onOpenSystemSettings: onOpenSystemSettings,
                onOpenNotificationChannelSettings:
                    onOpenNotificationChannelSettings,
              ),
              const SizedBox(height: 2),
            ],
          ],
          const SizedBox(height: 8),
          AppSettingsTile(
            icon: Icons.notifications_active_outlined,
            color: cs.primary,
            title: NotificationUiCopy.sendTestNowTitle,
            subtitle: lastTestAt == null
                ? NotificationUiCopy.sendTestNowSubtitle
                : NotificationUiCopy.lastTestSubtitle(
                    AppDateFormat.fullDateTime(context, lastTestAt!),
                  ),
            onTap: onSendTest,
          ),
          AppSettingsTile(
            icon: Icons.alarm_on_outlined,
            color: cs.brightness == Brightness.dark
                ? DesignTokens.todoDueSoonDark
                : DesignTokens.todoDueSoon,
            title: NotificationUiCopy.strongTestTitle,
            subtitle: NotificationUiCopy.strongTestSubtitle,
            onTap: onSendStrongTest,
          ),
          if (report == null ||
              report.summaryStatus != PermissionHealthStatus.ok)
            AppSettingsTile(
              icon: Icons.settings_outlined,
              color: cs.brightness == Brightness.dark
                  ? DesignTokens.todoDueSoonDark
                  : DesignTokens.todoDueSoon,
              title: NotificationUiCopy.troubleshootingSettingsTitle,
              subtitle: NotificationUiCopy.troubleshootingSettingsSubtitle,
              onTap: onOpenSystemSettings,
            ),
          AppSettingsTile(
            icon: Icons.schedule,
            color: cs.brightness == Brightness.dark
                ? const Color(0xFF4DB6AC)
                : DesignTokens.defaultAccent,
            title: NotificationUiCopy.scheduledRemindersTitle,
            subtitle: pendingCount == null
                ? NotificationUiCopy.scheduledRemindersLoading
                : NotificationUiCopy.scheduledRemindersCount(pendingCount!),
            trailing: pendingCount == null
                ? null
                : (pendingCount! > 0
                      ? TextButton(
                          onPressed: onClearPending,
                          child: Text(NotificationUiCopy.cancelAllAction),
                        )
                      : Icon(
                          Icons.check_circle,
                          color: cs.brightness == Brightness.dark
                              ? DesignTokens.todoCompletedDark
                              : DesignTokens.defaultSuccess,
                        )),
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
    final title = report == null
        ? (loading
              ? NotificationUiCopy.healthSummaryChecking
              : NotificationUiCopy.healthSummaryUnavailable)
        : NotificationUiCopy.healthSummaryTitle(report!.summaryStatus);
    final subtitle = report == null
        ? (loading
              ? NotificationUiCopy.healthSummaryWaiting
              : NotificationUiCopy.healthSummaryRefreshHint)
        : NotificationUiCopy.healthSummaryChecks(
            report!.checks.length,
            AppDateFormat.fullDateTime(context, report!.checkedAt),
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 0.45),
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
                    fontWeight: FontWeight.normal,
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
  final VoidCallback onRequestFullScreenIntentPermission;
  final VoidCallback onOpenSystemSettings;
  final ValueChanged<String> onOpenNotificationChannelSettings;

  const _HealthCheckTile({
    required this.check,
    required this.onRequestNotificationPermission,
    required this.onRequestExactAlarmPermission,
    required this.onRequestFullScreenIntentPermission,
    required this.onOpenSystemSettings,
    required this.onOpenNotificationChannelSettings,
  });

  @override
  Widget build(BuildContext context) {
    final VoidCallback? action = switch (check.action) {
      PermissionHealthAction.requestNotificationPermission =>
        onRequestNotificationPermission,
      PermissionHealthAction.requestExactAlarmPermission =>
        onRequestExactAlarmPermission,
      PermissionHealthAction.requestFullScreenIntentPermission =>
        onRequestFullScreenIntentPermission,
      PermissionHealthAction.openAppSettings =>
        check.actionChannelIds.isNotEmpty
            ? () => onOpenNotificationChannelSettings(
                check.actionChannelIds.first,
              )
            : onOpenSystemSettings,
      PermissionHealthAction.none => null,
      null => null,
    };
    final trailing = _actionTrailing(context, action);

    final color = _statusColor(check.status, Theme.of(context).colorScheme);
    final icon = check.manual
        ? Icons.tips_and_updates_outlined
        : _statusIcon(check.status);

    return AppSettingsTile(
      icon: icon,
      color: color,
      title: NotificationUiCopy.healthCheckTitle(check),
      subtitle: check.manual
          ? '${NotificationUiCopy.healthCheckSubtitle(check)}${NotificationUiCopy.isEn ? ' · Manual review' : ' · 需要人工确认'}'
          : NotificationUiCopy.healthCheckSubtitle(check),
      trailing: trailing,
    );
  }

  Widget _actionTrailing(BuildContext context, VoidCallback? action) {
    final color = _statusColor(check.status, Theme.of(context).colorScheme);
    if (check.action == PermissionHealthAction.openAppSettings &&
        check.actionChannelIds.length > 1) {
      return PopupMenuButton<String>(
        tooltip: NotificationUiCopy.channelSettingsAction,
        icon: Icon(Icons.tune_outlined, color: color),
        onSelected: onOpenNotificationChannelSettings,
        itemBuilder: (context) => [
          for (final id in check.actionChannelIds)
            PopupMenuItem(
              value: id,
              child: AppSecondaryMenuText(
                NotificationUiCopy.channelDisplayName(id),
              ),
            ),
        ],
      );
    }
    if (action == null) {
      return Icon(_statusTrailingIcon(check.status), color: color);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 112),
      child: TextButton(
        key: const ValueKey('notification_health_action_button'),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: action,
        child: Text(
          NotificationUiCopy.healthActionLabel(check),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

Color _statusColor(PermissionHealthStatus status, ColorScheme cs) {
  final isDark = cs.brightness == Brightness.dark;
  switch (status) {
    case PermissionHealthStatus.ok:
      return isDark
          ? DesignTokens.todoCompletedDark
          : DesignTokens.defaultSuccess;
    case PermissionHealthStatus.warning:
      return isDark ? DesignTokens.todoDueSoonDark : DesignTokens.todoDueSoon;
    case PermissionHealthStatus.blocked:
      return isDark ? DesignTokens.todoOverdueDark : DesignTokens.defaultError;
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
