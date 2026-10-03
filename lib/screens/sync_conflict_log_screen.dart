import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../providers/cloud_sync_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

class SyncConflictLogScreen extends StatefulWidget {
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
    _load();
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
    return Scaffold(
      backgroundColor: routeBackground,
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
                    const _SyncStatusCard(),
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
  }

  Widget _buildDecisionCard(BuildContext context, SyncMergeDecision item) {
    final cs = Theme.of(context).colorScheme;
    final remote = item.winner == 'remote';
    final color = remote ? cs.primary : Colors.orange;
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      border: Border.all(color: color.withValues(alpha: 0.22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                remote
                    ? Icons.cloud_done_outlined
                    : Icons.phone_android_outlined,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  remote
                      ? I18n.tr('sync_conflict.keep_remote')
                      : I18n.tr('sync_conflict.keep_local'),
                  style: const TextStyle(fontWeight: FontWeight.normal),
                ),
              ),
              Text(
                _formatTime(item.decidedAt),
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
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
              _InfoChip(label: '自动同步', value: status.autoSyncLabel),
              _InfoChip(label: '本机改动', value: status.pendingLabel),
              _InfoChip(label: '同步任务', value: status.syncingLabel),
              _InfoChip(label: '远端拉取', value: status.remotePullLabel),
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
      return const _SyncStatus(
        icon: Icons.sync_disabled_outlined,
        title: '同步状态未接入',
        message: '当前页面只能显示已记录的冲突，未读取到云同步运行状态。',
        autoSyncLabel: '未知',
        pendingLabel: '未知',
        syncingLabel: '未知',
        remotePullLabel: '未知',
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
    final pendingLabel = pendingChanges ? '待上传' : '无待上传';
    final autoSyncLabel = autoSync ? '开启' : '关闭';
    final syncingLabel = syncing ? '同步中' : '空闲';
    final remotePullLabel = queuedRemotePullStatus == null ? '无排队' : '已排队';
    if (unavailableStatus != null) {
      final title = !provider.isCloudSyncV2Enabled
          ? '云同步暂不可用'
          : provider.isSyncSuspended
          ? '云同步已暂停'
          : !provider.hasAuthenticatedClient
          ? '未登录云同步账号'
          : provider.isBackupDisabledByServer
          ? '云端备份已关闭'
          : '云同步暂不可用';
      return _SyncStatus(
        icon: Icons.sync_disabled_outlined,
        title: title,
        message: pendingChanges
            ? '$unavailableStatus 本机改动已保存在本机；恢复云同步条件后才会上传。'
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
        title: pendingChanges ? '本机改动同步未完成' : '云同步上次未完成',
        message: pendingChanges ? '$error\n本机改动已保留，稍后会自动重试。' : error,
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
        title: '远端更新已排队',
        message: queuedRemotePullStatus,
        autoSyncLabel: autoSyncLabel,
        pendingLabel: pendingLabel,
        syncingLabel: syncingLabel,
        remotePullLabel: '已排队',
        hasWarning: true,
      );
    }
    if (syncing) {
      return _SyncStatus(
        icon: Icons.sync_outlined,
        title: '正在同步',
        message: '正在同步本机改动或拉取云端更新，完成后会刷新本机展示。',
        autoSyncLabel: autoSyncLabel,
        pendingLabel: pendingLabel,
        syncingLabel: '同步中',
        remotePullLabel: '无排队',
      );
    }
    if (!autoSync && pendingChanges) {
      return const _SyncStatus(
        icon: Icons.sync_disabled_outlined,
        title: '本机改动未自动上传',
        message: '本机保存已完成；自动同步关闭期间不会上传。重新开启后会继续同步。',
        autoSyncLabel: '关闭',
        pendingLabel: '待上传',
        syncingLabel: '空闲',
        remotePullLabel: '无排队',
        hasWarning: true,
      );
    }
    if (pendingChanges) {
      return _SyncStatus(
        icon: Icons.upload_file_outlined,
        title: '本机改动待上传',
        message: '本机保存已完成，云同步会在后台同步到云端；失败会保留重试，不影响本机数据。',
        autoSyncLabel: autoSyncLabel,
        pendingLabel: '待上传',
        syncingLabel: '空闲',
        remotePullLabel: '无排队',
        hasWarning: true,
      );
    }
    if (retryStatus != null) {
      return _SyncStatus(
        icon: Icons.cloud_sync_outlined,
        title: '云同步等待重试',
        message: autoSync ? retryStatus : '云同步上次未完成；自动同步关闭期间不会重试。重新开启后会继续同步。',
        autoSyncLabel: autoSyncLabel,
        pendingLabel: '无待上传',
        syncingLabel: '空闲',
        remotePullLabel: remotePullLabel,
        hasWarning: true,
      );
    }
    if (realtimeWarning != null) {
      return _SyncStatus(
        icon: Icons.wifi_tethering_error_rounded,
        title: '实时同步使用轮询兜底',
        message: realtimeWarning,
        autoSyncLabel: autoSyncLabel,
        pendingLabel: '无待上传',
        syncingLabel: '空闲',
        remotePullLabel: '无排队',
        hasWarning: true,
      );
    }
    if (!autoSync) {
      return const _SyncStatus(
        icon: Icons.sync_disabled_outlined,
        title: '自动同步已关闭',
        message: '本机数据仍可使用；重新开启自动同步后才会继续上传本机改动和拉取远端更新。',
        autoSyncLabel: '关闭',
        pendingLabel: '无待上传',
        syncingLabel: '空闲',
        remotePullLabel: '无排队',
        hasWarning: true,
      );
    }
    return const _SyncStatus(
      icon: Icons.cloud_done_outlined,
      title: '云同步正常',
      message: '没有待上传改动，也没有等待处理的远端更新。',
      autoSyncLabel: '开启',
      pendingLabel: '无待上传',
      syncingLabel: '空闲',
      remotePullLabel: '无排队',
    );
  }

  Color color(ColorScheme cs) {
    if (hasError) return cs.error;
    if (hasWarning) return Colors.amber.shade800;
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
          Text(
            '字段: $field',
            style: TextStyle(fontSize: 11, color: cs.onTertiaryContainer),
          ),
        ],
      ),
    );
  }
}

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
