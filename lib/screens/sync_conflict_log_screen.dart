import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/desktop_web/desktop_embedded_scope.dart';

import '../core/design_tokens.dart' show AppSurfaceStyle, DesignTokens;
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../providers/cloud_sync_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';
import '../widgets/brand_background.dart'
    show BrandBackground, BrandRouteSurface, LocaleStatePreservingRoute;

class SyncConflictLogScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  const SyncConflictLogScreen({super.key});

  @override
  State<SyncConflictLogScreen> createState() => _SyncConflictLogScreenState();
}

class _SyncConflictLogScreenState extends State<SyncConflictLogScreen> {
  var _loading = true;
  var _items = const <SyncMergeDecision>[];

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_localeChanged);
    _load();
  }

  void _localeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_localeChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = prefs.getStringList('sync_merge_decisions') ?? const [];
    final items = rows
        .map((raw) {
          try {
            return SyncMergeDecision.fromJson(
              Map<String, dynamic>.from(json.decode(raw) as Map),
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<SyncMergeDecision>()
        .toList();
    items.sort((a, b) => b.decidedAt.compareTo(a.decidedAt));
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;
    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : routeBackground,
      appBar: AppBar(
        title: Text(I18n.tr('sync_conflict.title')),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppSecondaryControlTheme(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    _SyncStatusCard(),
                    if (_items.isEmpty)
                      EmptyState(
                        icon: Icons.sync_problem_outlined,
                        message: I18n.tr('sync_conflict.empty'),
                      )
                    else
                      for (final item in _items)
                        _buildDecisionCard(context, item),
                  ],
                ),
              ),
      ),
    );

    if (!isLiquidGlass) {
      return scaffold;
    }

    final hasBrandSurface =
        DesktopEmbeddedHostScope.isHosted(context) ||
        context.findAncestorWidgetOfExactType<BrandBackground>() != null ||
        context.findAncestorWidgetOfExactType<BrandRouteSurface>() != null;
    if (hasBrandSurface) {
      return scaffold;
    }
    return Material(
      color: routeBackground,
      child: BrandBackground(child: scaffold),
    );
  }

  Widget _buildDecisionCard(BuildContext context, SyncMergeDecision item) {
    final cs = Theme.of(context).colorScheme;
    final remote = item.winner == 'remote';
    final color = remote ? cs.primary : DesignTokens.defaultWarning;
    final titleText = remote
        ? I18n.tr('sync_conflict.keep_remote')
        : I18n.tr('sync_conflict.keep_local');
    final timeText = _formatTime(item.decidedAt);
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      border: Border.all(color: color.withValues(alpha: 0.22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final textScaler = MediaQuery.textScalerOf(context);
              final direction = Directionality.of(context);
              final defaultStyle = DefaultTextStyle.of(context).style;

              final titleStyle = defaultStyle.merge(
                const TextStyle(fontWeight: FontWeight.normal),
              );
              final titlePainter = TextPainter(
                text: TextSpan(text: titleText, style: titleStyle),
                textDirection: direction,
                textScaler: textScaler,
              )..layout();

              final timeStyle = defaultStyle.merge(
                TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              );
              final timePainter = TextPainter(
                text: TextSpan(text: timeText, style: timeStyle),
                textDirection: direction,
                textScaler: textScaler,
              )..layout();

              const iconWidth = 20.0;
              const iconGap = 8.0;
              const minGap = 8.0;
              final singleLineRowWidth =
                  iconWidth +
                  iconGap +
                  titlePainter.width +
                  minGap +
                  timePainter.width;
              final fitsOnOneRow = constraints.maxWidth >= singleLineRowWidth;

              titlePainter.dispose();
              timePainter.dispose();

              final iconWidget = Icon(
                remote
                    ? Icons.cloud_done_outlined
                    : Icons.phone_android_outlined,
                color: color,
                size: iconWidth,
              );
              final titleWidget = Text(
                titleText,
                style: const TextStyle(fontWeight: FontWeight.normal),
              );
              final timeWidget = Text(
                timeText,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              );

              if (fitsOnOneRow) {
                return Row(
                  children: [
                    iconWidget,
                    const SizedBox(width: iconGap),
                    Expanded(child: titleWidget),
                    const SizedBox(width: minGap),
                    timeWidget,
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      iconWidget,
                      const SizedBox(width: iconGap),
                      Expanded(child: titleWidget),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: iconWidth + iconGap),
                    child: timeWidget,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Text(item.reason, style: TextStyle(color: cs.onSurfaceVariant)),
          if (item.changedFields.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final field in item.changedFields)
                  _FieldChip(field: field),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _InfoChip(
                label: I18n.tr('sync_conflict.type'),
                value: item.itemType,
              ),
              _InfoChip(
                label: I18n.tr('sync_conflict.item'),
                value: item.itemId,
              ),
              if (item.workspaceId.isNotEmpty)
                _InfoChip(
                  label: I18n.tr('sync_conflict.workspace'),
                  value: item.workspaceId,
                ),
              if (item.localUpdatedAt.isNotEmpty)
                _InfoChip(
                  label: I18n.tr('sync_conflict.local'),
                  value: item.localUpdatedAt,
                ),
              if (item.remoteUpdatedAt.isNotEmpty)
                _InfoChip(
                  label: I18n.tr('sync_conflict.remote'),
                  value: item.remoteUpdatedAt,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime value) {
    return I18nDateFormat.shortDateTime(value);
  }
}

class _SyncStatusCard extends StatelessWidget {
  const _SyncStatusCard();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CloudSyncProvider?>();
    final status = _SyncStatus.fromProvider(provider);
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      border: Border.all(color: status.color(cs).withValues(alpha: 0.24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(status.icon, size: 20, color: status.color(cs)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status.title,
                  style: const TextStyle(fontWeight: FontWeight.normal),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            status.message,
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _InfoChip(
                label: _syncText('自动同步', 'Auto sync'),
                value: status.autoSyncLabel,
              ),
              _InfoChip(
                label: _syncText('本机改动', 'Local changes'),
                value: status.pendingLabel,
              ),
              _InfoChip(
                label: _syncText('同步任务', 'Sync task'),
                value: status.syncingLabel,
              ),
              _InfoChip(
                label: _syncText('远端拉取', 'Remote pull'),
                value: status.remotePullLabel,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SyncStatus {
  final IconData icon;
  final String title;
  final String message;
  final String autoSyncLabel;
  final String pendingLabel;
  final String syncingLabel;
  final String remotePullLabel;
  final bool hasError;
  final bool hasWarning;

  const _SyncStatus({
    required this.icon,
    required this.title,
    required this.message,
    required this.autoSyncLabel,
    required this.pendingLabel,
    required this.syncingLabel,
    required this.remotePullLabel,
    this.hasError = false,
    this.hasWarning = false,
  });

  factory _SyncStatus.fromProvider(CloudSyncProvider? provider) {
    if (provider == null) {
      return _SyncStatus(
        icon: Icons.sync_disabled_outlined,
        title: _syncText('同步状态未接入', 'Sync status unavailable'),
        message: _syncText(
          '当前页面只能显示已记录的冲突，未读取到云同步运行状态。',
          'Only saved conflicts are available; live sync status could not be read.',
        ),
        autoSyncLabel: _syncText('未知', 'Unknown'),
        pendingLabel: _syncText('未知', 'Unknown'),
        syncingLabel: _syncText('未知', 'Unknown'),
        remotePullLabel: _syncText('未知', 'Unknown'),
        hasWarning: true,
      );
    }
    final error = provider.lastError;
    final unavailableStatus = provider.syncUnavailableStatus;
    final queuedRemotePullStatus = provider.queuedRemotePullStatus;
    final retryStatus = provider.syncRetryStatus;
    final realtimeWarning = provider.lastRealtimeWarning;
    final autoSync = provider.config.autoSync;
    final pendingChanges = provider.hasPendingChanges;
    final syncing = provider.isSyncing;
    final pendingLabel = pendingChanges
        ? _syncText('待上传', 'Pending upload')
        : _syncText('无待上传', 'No pending uploads');
    final autoSyncLabel = autoSync
        ? _syncText('开启', 'On')
        : _syncText('关闭', 'Off');
    final syncingLabel = syncing
        ? _syncText('同步中', 'Syncing')
        : _syncText('空闲', 'Idle');
    final remotePullLabel = queuedRemotePullStatus == null
        ? _syncText('无排队', 'None queued')
        : _syncText('已排队', 'Queued');
    if (unavailableStatus != null) {
      final title = !provider.isCloudSyncV2Enabled
          ? _syncText('云同步暂不可用', 'Cloud sync unavailable')
          : provider.isSyncSuspended
          ? _syncText('云同步已暂停', 'Cloud sync paused')
          : !provider.hasAuthenticatedClient
          ? _syncText('未登录云同步账号', 'Sign in to cloud sync')
          : provider.isBackupDisabledByServer
          ? _syncText('云端备份已关闭', 'Cloud backup disabled')
          : _syncText('云同步暂不可用', 'Cloud sync unavailable');
      return _SyncStatus(
        icon: Icons.sync_disabled_outlined,
        title: title,
        message: pendingChanges
            ? '$unavailableStatus ${_syncText('本机改动已保存在本机；恢复云同步条件后才会上传。', 'Changes are saved on this device and will upload when cloud sync is available.')}'
            : unavailableStatus,
        autoSyncLabel: autoSyncLabel,
        pendingLabel: pendingLabel,
        syncingLabel: syncingLabel,
        remotePullLabel: remotePullLabel,
        hasWarning: true,
      );
    }
    if (error != null) {
      return _SyncStatus(
        icon: Icons.error_outline,
        title: pendingChanges
            ? _syncText('本机改动同步未完成', 'Local changes not synced')
            : _syncText('云同步上次未完成', 'Last cloud sync incomplete'),
        message: pendingChanges
            ? '$error\n${_syncText('本机改动已保留，稍后会自动重试。', 'Local changes are retained and will retry automatically.')}'
            : error,
        autoSyncLabel: autoSyncLabel,
        pendingLabel: pendingLabel,
        syncingLabel: syncingLabel,
        remotePullLabel: remotePullLabel,
        hasError: true,
      );
    }
    if (queuedRemotePullStatus != null) {
      return _SyncStatus(
        icon: Icons.cloud_queue_outlined,
        title: _syncText('远端更新已排队', 'Remote updates queued'),
        message: queuedRemotePullStatus,
        autoSyncLabel: autoSyncLabel,
        pendingLabel: pendingLabel,
        syncingLabel: syncingLabel,
        remotePullLabel: _syncText('已排队', 'Queued'),
        hasWarning: true,
      );
    }
    if (syncing) {
      return _SyncStatus(
        icon: Icons.sync_outlined,
        title: _syncText('正在同步', 'Syncing'),
        message: _syncText(
          '正在同步本机改动或拉取云端更新，完成后会刷新本机展示。',
          'Uploading local changes or fetching cloud updates. This page will update when sync finishes.',
        ),
        autoSyncLabel: autoSyncLabel,
        pendingLabel: pendingLabel,
        syncingLabel: _syncText('同步中', 'Syncing'),
        remotePullLabel: _syncText('无排队', 'None queued'),
      );
    }
    if (!autoSync && pendingChanges) {
      return _SyncStatus(
        icon: Icons.sync_disabled_outlined,
        title: _syncText('本机改动未自动上传', 'Automatic upload is off'),
        message: _syncText(
          '本机保存已完成；自动同步关闭期间不会上传。重新开启后会继续同步。',
          'Saved on this device. Changes will upload when automatic sync is enabled again.',
        ),
        autoSyncLabel: _syncText('关闭', 'Off'),
        pendingLabel: _syncText('待上传', 'Pending upload'),
        syncingLabel: _syncText('空闲', 'Idle'),
        remotePullLabel: _syncText('无排队', 'None queued'),
        hasWarning: true,
      );
    }
    if (pendingChanges) {
      return _SyncStatus(
        icon: Icons.upload_file_outlined,
        title: _syncText('本机改动待上传', 'Local changes pending upload'),
        message: _syncText(
          '本机保存已完成，云同步会在后台同步到云端；失败会保留重试，不影响本机数据。',
          'Saved on this device. Changes will upload in the background; failed syncs retain local data for retry.',
        ),
        autoSyncLabel: autoSyncLabel,
        pendingLabel: _syncText('待上传', 'Pending upload'),
        syncingLabel: _syncText('空闲', 'Idle'),
        remotePullLabel: _syncText('无排队', 'None queued'),
        hasWarning: true,
      );
    }
    if (retryStatus != null) {
      return _SyncStatus(
        icon: Icons.cloud_sync_outlined,
        title: _syncText('云同步等待重试', 'Cloud sync awaiting retry'),
        message: autoSync
            ? retryStatus
            : _syncText(
                '云同步上次未完成；自动同步关闭期间不会重试。重新开启后会继续同步。',
                'Last sync was incomplete. It will retry when automatic sync is enabled again.',
              ),
        autoSyncLabel: autoSyncLabel,
        pendingLabel: _syncText('无待上传', 'No pending uploads'),
        syncingLabel: _syncText('空闲', 'Idle'),
        remotePullLabel: remotePullLabel,
        hasWarning: true,
      );
    }
    if (realtimeWarning != null) {
      return _SyncStatus(
        icon: Icons.wifi_tethering_error_rounded,
        title: _syncText('实时同步使用轮询兜底', 'Live sync using polling'),
        message: realtimeWarning,
        autoSyncLabel: autoSyncLabel,
        pendingLabel: _syncText('无待上传', 'No pending uploads'),
        syncingLabel: _syncText('空闲', 'Idle'),
        remotePullLabel: _syncText('无排队', 'None queued'),
        hasWarning: true,
      );
    }
    if (!autoSync) {
      return _SyncStatus(
        icon: Icons.sync_disabled_outlined,
        title: _syncText('自动同步已关闭', 'Automatic sync is off'),
        message: _syncText(
          '本机数据仍可使用；重新开启自动同步后才会继续上传本机改动和拉取远端更新。',
          'Local data is available. Enable automatic sync to upload changes and fetch remote updates.',
        ),
        autoSyncLabel: _syncText('关闭', 'Off'),
        pendingLabel: _syncText('无待上传', 'No pending uploads'),
        syncingLabel: _syncText('空闲', 'Idle'),
        remotePullLabel: _syncText('无排队', 'None queued'),
        hasWarning: true,
      );
    }
    return _SyncStatus(
      icon: Icons.cloud_done_outlined,
      title: _syncText('云同步正常', 'Cloud sync up to date'),
      message: _syncText(
        '没有待上传改动，也没有等待处理的远端更新。',
        'No local changes to upload or remote updates waiting to be applied.',
      ),
      autoSyncLabel: _syncText('开启', 'On'),
      pendingLabel: _syncText('无待上传', 'No pending uploads'),
      syncingLabel: _syncText('空闲', 'Idle'),
      remotePullLabel: _syncText('无排队', 'None queued'),
    );
  }

  Color color(ColorScheme cs) {
    if (hasError) return cs.error;
    if (hasWarning) return DesignTokens.defaultWarning;
    return cs.primary;
  }
}

class _FieldChip extends StatelessWidget {
  final String field;

  const _FieldChip({required this.field});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.edit_note_outlined,
            size: 13,
            color: cs.onTertiaryContainer,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '${_syncText('字段', 'Field')}: $field',
              style: TextStyle(fontSize: 11, color: cs.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

String _syncText(String zh, String en) =>
    I18n.current == AppLocale.en ? en : zh;

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
      ),
    );
  }
}
