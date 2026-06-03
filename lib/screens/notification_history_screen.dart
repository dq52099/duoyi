import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/design_tokens.dart';
import '../core/notification_history_policy.dart';
import '../core/platform_info.dart';
import '../core/report_reminder_config.dart';
import '../models/goal.dart' show ReminderKind;
import '../providers/notification_service.dart';
import '../providers/preferences_provider.dart';
import '../services/alarm_service.dart';
import '../services/notification_permission_exception.dart';
import '../services/notification_settings.dart';
import '../services/notification_status_bar_sync_bridge.dart';
import '../services/native_reminder_ringtone.dart';
import '../services/reminder_ringtone_settings.dart';
import '../widgets/app_time_picker.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

enum _NotificationReadFilter { all, unread, read }

class NotificationHistoryScreen extends StatefulWidget {
  final bool markReadOnOpen;

  const NotificationHistoryScreen({super.key, this.markReadOnOpen = true});

  @override
  State<NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState extends State<NotificationHistoryScreen> {
  static const _pageSize = 50;

  final _searchCtrl = TextEditingController();
  NotificationType? _typeFilter;
  _NotificationReadFilter _readFilter = _NotificationReadFilter.all;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    if (widget.markReadOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final service = context.read<NotificationService>();
        if (service.unreadCount > 0) {
          service.markHistorySeen();
        }
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _resetPaging() {
    _page = 0;
  }

  List<NotificationItem> _filteredHistory(List<NotificationItem> history) {
    final query = _searchCtrl.text.trim().toLowerCase();
    return history
        .where((item) {
          if (_typeFilter != null && item.type != _typeFilter) return false;
          if (_readFilter == _NotificationReadFilter.unread && item.isRead) {
            return false;
          }
          if (_readFilter == _NotificationReadFilter.read && !item.isRead) {
            return false;
          }
          if (query.isEmpty) return true;
          return item.title.toLowerCase().contains(query) ||
              item.body.toLowerCase().contains(query) ||
              (item.relatedId ?? '').toLowerCase().contains(query) ||
              _notificationTypeLabel(item.type).toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _confirmClearHistory(int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('清空通知记录？'),
        icon: const Icon(Icons.delete_outline),
        content: Text('将清空当前保留的 $count 条通知记录，已调度的提醒不会被取消。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<NotificationService>().clearHistory();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('通知记录已清空'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<NotificationService>();
    final history = service.history;
    final filteredHistory = _filteredHistory(history);
    final totalPages = filteredHistory.isEmpty
        ? 1
        : ((filteredHistory.length - 1) ~/ _pageSize) + 1;
    final currentPage = _page.clamp(0, totalPages - 1).toInt();
    if (currentPage != _page) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _page = currentPage);
      });
    }
    final pageStart = currentPage * _pageSize;
    final pageEnd = (pageStart + _pageSize)
        .clamp(0, filteredHistory.length)
        .toInt();
    final visibleHistory = filteredHistory.sublist(pageStart, pageEnd);
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;

    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: const Text('通知记录'),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        actions: [
          if (service.unreadCount > 0)
            TextButton.icon(
              onPressed: () => service.markAllHistoryRead(),
              icon: const Icon(Icons.mark_email_read_outlined),
              label: const Text('全部已读'),
            ),
          IconButton(
            tooltip: '清空通知记录',
            onPressed: history.isEmpty
                ? null
                : () => _confirmClearHistory(history.length),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: AppSecondaryControlTheme(
        child: history.isEmpty
            ? const Center(child: Text('暂无通知记录'))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                    child: _NotificationHistoryFilters(
                      searchCtrl: _searchCtrl,
                      typeFilter: _typeFilter,
                      readFilter: _readFilter,
                      historyCount: history.length,
                      filteredCount: filteredHistory.length,
                      page: currentPage + 1,
                      totalPages: totalPages,
                      unreadCount: service.unreadCount,
                      onSearchChanged: (_) => setState(_resetPaging),
                      onClearSearch: () {
                        _searchCtrl.clear();
                        setState(_resetPaging);
                      },
                      onTypeChanged: (type) => setState(() {
                        _typeFilter = type;
                        _resetPaging();
                      }),
                      onReadFilterChanged: (filter) => setState(() {
                        _readFilter = filter;
                        _resetPaging();
                      }),
                    ),
                  ),
                  Expanded(
                    child: filteredHistory.isEmpty
                        ? const EmptyState(
                            icon: Icons.manage_search_outlined,
                            message: '没有匹配的通知记录',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                            itemCount: visibleHistory.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = visibleHistory[index];
                              return _NotificationRecordCard(
                                key: ValueKey('notification_record_${item.id}'),
                                item: item,
                                onToggleRead: () => service.markHistoryItemRead(
                                  item.id,
                                  read: !item.isRead,
                                ),
                              );
                            },
                          ),
                  ),
                  if (filteredHistory.length > _pageSize)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Row(
                        children: [
                          Text(
                            '${pageStart + 1}-$pageEnd / ${filteredHistory.length}',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const Spacer(),
                          IconButton.outlined(
                            tooltip: '上一页',
                            onPressed: currentPage == 0
                                ? null
                                : () => setState(() => _page = currentPage - 1),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            tooltip: '下一页',
                            onPressed: currentPage >= totalPages - 1
                                ? null
                                : () => setState(() => _page = currentPage + 1),
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _NotificationHistoryFilters extends StatelessWidget {
  final TextEditingController searchCtrl;
  final NotificationType? typeFilter;
  final _NotificationReadFilter readFilter;
  final int historyCount;
  final int filteredCount;
  final int page;
  final int totalPages;
  final int unreadCount;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<NotificationType?> onTypeChanged;
  final ValueChanged<_NotificationReadFilter> onReadFilterChanged;

  const _NotificationHistoryFilters({
    required this.searchCtrl,
    required this.typeFilter,
    required this.readFilter,
    required this.historyCount,
    required this.filteredCount,
    required this.page,
    required this.totalPages,
    required this.unreadCount,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onTypeChanged,
    required this.onReadFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchCtrl,
            decoration: InputDecoration(
              hintText: '搜索标题、内容或关联 ID',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchCtrl.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      icon: const Icon(Icons.close),
                      onPressed: onClearSearch,
                    ),
              isDense: true,
            ),
            textInputAction: TextInputAction.search,
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _historyTypeChip('全部', null, typeFilter, onTypeChanged),
                for (final type in NotificationType.values)
                  _historyTypeChip(
                    _notificationTypeLabel(type),
                    type,
                    typeFilter,
                    onTypeChanged,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SegmentedButton<_NotificationReadFilter>(
            segments: const [
              ButtonSegment(
                value: _NotificationReadFilter.all,
                label: Text('全部'),
              ),
              ButtonSegment(
                value: _NotificationReadFilter.unread,
                label: Text('未读'),
              ),
              ButtonSegment(
                value: _NotificationReadFilter.read,
                label: Text('已读'),
              ),
            ],
            selected: {readFilter},
            onSelectionChanged: (values) => onReadFilterChanged(values.single),
          ),
          const SizedBox(height: 8),
          Text(
            filteredCount == historyCount
                ? '共 $historyCount 条 · 未读 $unreadCount 条 · 支持搜索、筛选和分页浏览 · 第 $page / $totalPages 页 · 每页 ${_NotificationHistoryScreenState._pageSize} 条'
                : '已筛出 $filteredCount / $historyCount 条 · 未读 $unreadCount 条 · 第 $page / $totalPages 页',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.58),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyTypeChip(
    String label,
    NotificationType? type,
    NotificationType? selected,
    ValueChanged<NotificationType?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected == type,
        onSelected: (_) => onChanged(type),
      ),
    );
  }
}

class _NotificationRecordCard extends StatelessWidget {
  final NotificationItem item;
  final VoidCallback onToggleRead;

  const _NotificationRecordCard({
    super.key,
    required this.item,
    required this.onToggleRead,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _notificationColor(item.type);
    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      color: item.isRead ? null : cs.primary.withValues(alpha: 0.06),
      border: item.isRead
          ? null
          : Border.all(color: cs.primary.withValues(alpha: 0.22), width: 0.45),
      onTap: item.isRead ? null : onToggleRead,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _notificationIcon(item.type),
                  size: 20,
                  color: color,
                ),
              ),
              if (!item.isRead)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: cs.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.normal,
                        color: cs.onSurface,
                      ),
                    ),
                    AppStatusBadge(
                      label: _notificationTypeLabel(item.type),
                      color: color,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                    ),
                    AppStatusBadge(
                      label: item.isRead ? '已读' : '未读',
                      color: item.isRead ? cs.onSurfaceVariant : cs.error,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                    ),
                  ],
                ),
                if (item.body.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.body,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.66),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  _formatNotificationTime(item.scheduledTime),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.48),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: item.isRead ? '标为未读' : '标为已读',
            onPressed: onToggleRead,
            icon: Icon(
              item.isRead
                  ? Icons.mark_email_unread_outlined
                  : Icons.mark_email_read_outlined,
            ),
          ),
        ],
      ),
    );
  }
}

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  int? _pendingPushCount;
  int? _pendingAlarmCount;
  bool? _exactAlarmGranted;
  Map<String, NotificationChannelStatus>? _channelStatuses;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_refreshStatus());
    });
  }

  Future<void> _refreshStatus() async {
    final service = context.read<NotificationService>();
    setState(() => _busy = true);
    try {
      await service.refreshPermission();
      final pendingIds = await service.pendingIds();
      await AlarmService.instance.init();
      final pendingAlarmIds = await _safePendingAlarmIds();
      final exactAlarmGranted = await AlarmService.instance
          .hasExactAlarmPermission();
      final channelStatuses =
          await NotificationSettings.notificationChannelStatuses(const [
            NotificationService.channelId,
            AlarmService.channelId,
            NativeReminderRingtone.statusChannelId,
            NativeReminderRingtone.fallbackChannelId,
          ]);
      if (!mounted) return;
      setState(() {
        _pendingPushCount = pendingIds.length;
        _pendingAlarmCount = pendingAlarmIds.length;
        _exactAlarmGranted = exactAlarmGranted;
        _channelStatuses = channelStatuses;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<int>> _safePendingAlarmIds() async {
    try {
      return await AlarmService.instance.pendingIds();
    } catch (e, st) {
      debugPrint('[NotificationSettings] pending alarm probe failed: $e\n$st');
      return const <int>[];
    }
  }

  Future<void> _requestPermission() async {
    final granted = await context
        .read<NotificationService>()
        .requestPermission();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(granted ? '通知权限已开启' : '通知权限未开启'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await _refreshStatus();
  }

  Future<void> _requestExactAlarmPermission() async {
    final granted = await AlarmService.instance.requestExactAlarmPermission();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(granted ? '精准闹钟权限已开启' : '精准闹钟权限未开启，闹钟可能延后或降级'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await _refreshStatus();
  }

  Future<void> _setNotificationStatusBarPreference({
    required bool quickAdd,
    required bool value,
  }) async {
    final prefs = context.read<PreferencesProvider>();
    final previousQuickAdd = prefs.notificationQuickAdd;
    final previousTodayProgress = prefs.notificationTodayProgress;
    setState(() => _busy = true);
    try {
      if (quickAdd) {
        await prefs.setNotificationQuickAdd(value);
      } else {
        await prefs.setNotificationTodayProgress(value);
      }
      final synced = await _syncNotificationStatusBarNow();
      if (!mounted) return;
      if (synced) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? I18n.tr('preferences.notification_status_bar.enabled')
                  : I18n.tr('preferences.notification_status_bar.disabled'),
            ),
          ),
        );
        return;
      }
      await prefs.setNotificationQuickAdd(previousQuickAdd);
      await prefs.setNotificationTodayProgress(previousTodayProgress);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            I18n.tr('preferences.notification_status_bar.sync_failed'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _syncNotificationStatusBarNow() async {
    try {
      return await NotificationStatusBarSyncBridge.sync(force: true);
    } on NotificationPermissionDeniedException catch (e) {
      debugPrint('[NotificationSettings] status bar permission denied: $e');
      return false;
    } catch (e, st) {
      debugPrint('[NotificationSettings] status bar sync failed: $e\n$st');
      return false;
    }
  }

  Future<void> _sendTest() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await context.read<NotificationService>().sendTest();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('测试通知已发送'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _refreshStatus();
    } on NotificationPermissionDeniedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('通知权限未开启，无法发送测试通知'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    } catch (e, st) {
      debugPrint('[NotificationSettings] send test failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('测试通知发送失败，请检查通知权限和渠道设置。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendScheduledTest() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await context.read<NotificationService>().sendScheduledTest();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已注册 1 分钟后的定时通知测试'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _refreshStatus();
    } on NotificationPermissionDeniedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('通知权限未开启，无法注册定时测试'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    } catch (e, st) {
      debugPrint('[NotificationSettings] scheduled test failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('定时测试注册失败，请检查通知和精确闹钟权限。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendStrongTest() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AlarmService.instance.showFullScreenTest();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('强提醒测试已启动，可在通知上手动停止响铃'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _refreshStatus();
    } on NotificationPermissionDeniedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('通知权限未开启，强提醒可能没有停止按钮'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    } catch (e, st) {
      debugPrint('[NotificationSettings] strong test failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('强提醒测试启动失败，请检查通知、闹钟和后台运行权限。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSystemSettings([String? channelId]) async {
    final opened =
        (channelId != null &&
            await NotificationSettings.openNotificationChannelSettings(
              channelId,
            )) ||
        await NotificationSettings.openAppNotificationSettings() ||
        await openAppSettings();
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('无法打开系统通知设置'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  NotificationChannelStatus? _channelStatus(String channelId) {
    return _channelStatuses?[channelId];
  }

  String _channelStatusLabel(String channelId) {
    final status = _channelStatus(channelId);
    if (_channelStatuses == null) return _busy ? '检测中' : '未检测';
    if (status == null || !status.exists) return '未创建';
    if (status.isBlocked) return '已关闭';
    if (_channelRequiresSound(channelId) && status.isSilent) return '已静音';
    if (status.isLowImportance) return '提醒弱';
    return '声音正常';
  }

  Color _channelStatusColor(String channelId, ColorScheme cs) {
    final status = _channelStatus(channelId);
    if (_channelStatuses == null || status == null || !status.exists) {
      return cs.onSurfaceVariant;
    }
    if (status.isBlocked) return cs.error;
    if (_channelRequiresSound(channelId) && status.isSilent) {
      return Colors.deepOrange;
    }
    if (status.isLowImportance) return Colors.amber.shade800;
    return Colors.green;
  }

  bool _channelRequiresSound(String channelId) =>
      channelId != NativeReminderRingtone.statusChannelId;

  String _channelSubtitle(String base, String channelId) {
    return '$base · ${_channelStatusLabel(channelId)}';
  }

  Widget _channelStatusTrailing(String channelId, ColorScheme cs) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppStatusBadge(
          label: _channelStatusLabel(channelId),
          color: _channelStatusColor(channelId, cs),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        ),
        const SizedBox(width: 6),
        Icon(
          Icons.chevron_right,
          size: 18,
          color: cs.onSurface.withValues(alpha: 0.38),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();
    final service = context.watch<NotificationService>();
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: const Text('通知设置'),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 52,
      ),
      body: AppSecondaryControlTheme(
        child: SafeArea(
          top: false,
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _refreshStatus,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(
                12,
                16,
                12,
                40 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                AppSurfaceCard(
                  padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.12),
                    width: 0.35,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.notifications_active_outlined,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '通知设置',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontSize: DesignTokens.fontSizeCardTitle,
                                    fontWeight: DesignTokens.fontWeightRegular,
                                  ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '系统权限、提醒时间、铃声和通知记录保留',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.64),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppSettingsSection(
                  title: '系统通知',
                  subtitle: service.permissionGranted ? '通知权限已开启' : '通知权限未开启',
                  children: [
                    AppSettingsTile(
                      icon: service.permissionGranted
                          ? Icons.check_circle_outline
                          : Icons.notifications_off_outlined,
                      color: service.permissionGranted
                          ? Colors.green
                          : Colors.red,
                      title: '通知权限',
                      subtitle: service.permissionGranted
                          ? '系统允许多仪发送提醒'
                          : '开启后才能收到普通通知和提醒',
                      trailing: TextButton(
                        onPressed: _busy ? null : _requestPermission,
                        child: Text(service.permissionGranted ? '重新检查' : '开启'),
                      ),
                    ),
                    AppSettingsTile(
                      icon: Icons.settings_outlined,
                      color: Colors.deepOrange,
                      title: '普通提醒渠道',
                      subtitle: _channelSubtitle(
                        '检查普通通知的声音、横幅和锁屏权限',
                        NotificationService.channelId,
                      ),
                      trailing: _channelStatusTrailing(
                        NotificationService.channelId,
                        cs,
                      ),
                      onTap: () =>
                          _openSystemSettings(NotificationService.channelId),
                    ),
                    AppSettingsTile(
                      icon: Icons.alarm_on_outlined,
                      color: Colors.deepPurple,
                      title: '强提醒渠道',
                      subtitle: _channelSubtitle(
                        '检查闹钟提醒的声音、横幅和全屏展示权限',
                        AlarmService.channelId,
                      ),
                      trailing: _channelStatusTrailing(
                        AlarmService.channelId,
                        cs,
                      ),
                      onTap: () => _openSystemSettings(AlarmService.channelId),
                    ),
                    AppSettingsTile(
                      icon: Icons.alt_route_outlined,
                      color: Colors.indigo,
                      title: '闹钟降级兜底',
                      subtitle: _channelSubtitle(
                        '强提醒或内置铃声注册失败时会改用普通提醒；普通提醒渠道静音，兜底也可能无声',
                        NativeReminderRingtone.fallbackChannelId,
                      ),
                      trailing: _channelStatusTrailing(
                        NativeReminderRingtone.fallbackChannelId,
                        cs,
                      ),
                      onTap: () => _openSystemSettings(
                        NativeReminderRingtone.fallbackChannelId,
                      ),
                    ),
                    AppSettingsTile(
                      icon: Icons.music_note_outlined,
                      color: Colors.pink,
                      title: '内置铃声状态渠道',
                      subtitle: _channelSubtitle(
                        '检查内置铃声前台状态通知是否被静音或屏蔽',
                        NativeReminderRingtone.statusChannelId,
                      ),
                      trailing: _channelStatusTrailing(
                        NativeReminderRingtone.statusChannelId,
                        cs,
                      ),
                      onTap: () => _openSystemSettings(
                        NativeReminderRingtone.statusChannelId,
                      ),
                    ),
                    AppSettingsTile(
                      icon: Icons.notifications_active_outlined,
                      color: cs.primary,
                      title: '立即发送测试通知',
                      subtitle: '验证普通通知渠道是否可见、可响铃',
                      onTap: _busy ? null : _sendTest,
                    ),
                    AppSettingsTile(
                      icon: Icons.schedule_send_outlined,
                      color: Colors.cyan,
                      title: '1 分钟后定时测试',
                      subtitle: '验证系统定时调度链路，到点应收到普通提醒',
                      onTap: _busy ? null : _sendScheduledTest,
                    ),
                    AppSettingsTile(
                      icon: Icons.alarm_on_outlined,
                      color: Colors.deepOrange,
                      title: '测试强提醒铃声',
                      subtitle: '验证闹钟提醒、内置铃声和通知停止按钮',
                      onTap: _busy ? null : _sendStrongTest,
                    ),
                    AppSettingsTile(
                      icon: Icons.schedule,
                      color: Colors.teal,
                      title: '已调度普通提醒',
                      subtitle: _pendingPushCount == null
                          ? '正在读取待触发队列'
                          : '$_pendingPushCount 条待触发',
                      trailing: IconButton(
                        tooltip: '刷新',
                        onPressed: _busy ? null : _refreshStatus,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                      ),
                    ),
                    AppSettingsTile(
                      icon: Icons.alarm_on_outlined,
                      color: Colors.deepPurple,
                      title: '已调度闹钟提醒',
                      subtitle: _pendingAlarmCount == null
                          ? '正在读取强提醒队列'
                          : '$_pendingAlarmCount 条待触发 · ${_exactAlarmGranted == true ? '精准闹钟已开启' : '精准闹钟未开启'}',
                      trailing: TextButton(
                        onPressed: _busy ? null : _requestExactAlarmPermission,
                        child: const Text('精准闹钟'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AppSettingsSection(
                  title: '提醒入口',
                  subtitle: '控制由通知触发的快捷记录和历史保留',
                  children: [
                    if (PlatformInfo.isAndroid) ...[
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        secondary: const Icon(Icons.add_alert_outlined),
                        title: Text(
                          I18n.tr('preferences.notification_quick_add.title'),
                        ),
                        subtitle: Text(
                          I18n.tr(
                            'preferences.notification_quick_add.subtitle',
                          ),
                        ),
                        value: prefs.notificationQuickAdd,
                        onChanged: _busy
                            ? null
                            : (value) => _setNotificationStatusBarPreference(
                                quickAdd: true,
                                value: value,
                              ),
                      ),
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        secondary: const Icon(Icons.today_outlined),
                        title: Text(
                          I18n.tr(
                            'preferences.notification_today_progress.title',
                          ),
                        ),
                        subtitle: Text(
                          I18n.tr(
                            'preferences.notification_today_progress.subtitle',
                          ),
                        ),
                        value: prefs.notificationTodayProgress,
                        onChanged: _busy
                            ? null
                            : (value) => _setNotificationStatusBarPreference(
                                quickAdd: false,
                                value: value,
                              ),
                      ),
                    ] else
                      AppSettingsTile(
                        icon: Icons.notifications_none_outlined,
                        color: Colors.blueGrey,
                        title: I18n.tr(
                          'preferences.notification_status_bar.title',
                        ),
                        subtitle: I18n.tr(
                          'preferences.notification_status_bar.unsupported',
                        ),
                      ),
                    AppSettingsTile(
                      icon: Icons.history_outlined,
                      color: Colors.blueGrey,
                      title: '通知记录',
                      subtitle:
                          '共 ${service.historyCount} 条，未读 ${service.unreadCount} 条',
                      trailing: TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NotificationHistoryScreen(
                              markReadOnOpen: true,
                            ),
                          ),
                        ),
                        child: const Text('查看'),
                      ),
                    ),
                    AppSettingsTile(
                      icon: Icons.inventory_2_outlined,
                      color: Colors.indigo,
                      title: '通知记录保留',
                      subtitle:
                          '最多保留 ${prefs.notificationHistoryLimit} 条历史，调低后会裁剪旧记录',
                      trailing: AppCompactDropdown<int>(
                        value: prefs.notificationHistoryLimit,
                        width: 116,
                        items: [
                          for (final value in NotificationHistoryPolicy.options)
                            DropdownMenuItem(
                              value: value,
                              child: Text('$value 条'),
                            ),
                        ],
                        onChanged: (value) async {
                          if (value == null) return;
                          final prefProvider = context
                              .read<PreferencesProvider>();
                          final notif = context.read<NotificationService>();
                          await prefProvider.setNotificationHistoryLimit(value);
                          await notif.setHistoryLimit(
                            prefProvider.notificationHistoryLimit,
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AppSettingsSection(
                  title: I18n.tr('preferences.section.daily_reminder'),
                  subtitle: I18n.tr(
                    'preferences.section.daily_reminder.subtitle',
                  ),
                  children: [
                    for (var i = 0; i < prefs.dailyReminderSlots.length; i++)
                      _NotificationReminderSlotTile(
                        index: i,
                        slot: prefs.dailyReminderSlots[i],
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const _NotificationRingtoneSection(),
                const SizedBox(height: 12),
                const _ReportReminderSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationReminderSlotTile extends StatefulWidget {
  final int index;
  final DailyReminderSlot slot;

  const _NotificationReminderSlotTile({
    required this.index,
    required this.slot,
  });

  @override
  State<_NotificationReminderSlotTile> createState() =>
      _NotificationReminderSlotTileState();
}

class _NotificationReminderSlotTileState
    extends State<_NotificationReminderSlotTile> {
  bool _saving = false;

  int get index => widget.index;
  DailyReminderSlot get slot => widget.slot;

  String get _title => switch (index) {
    0 => I18n.tr('preferences.daily_reminder.one'),
    1 => I18n.tr('preferences.daily_reminder.two'),
    _ => I18n.tr('preferences.daily_reminder.three'),
  };

  String get _time =>
      I18nDateFormat.timeOfDay(hour: slot.hour, minute: slot.minute);

  Future<void> _save(BuildContext context, DailyReminderSlot next) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final needsReminderCheck =
          next.enabled &&
          (!slot.enabled ||
              slot.hour != next.hour ||
              slot.minute != next.minute ||
              slot.kind != next.kind ||
              !_sameDays(slot.repeatDays, next.repeatDays));
      if (needsReminderCheck) {
        final notif = context.read<NotificationService?>();
        final ready =
            await notif?.ensureReadyForReminder(
              scheduledTime: _nextSlotTrigger(next),
              issueTitle: I18n.tr('preferences.daily_reminder.register_failed'),
              relatedId: 'daily_reminder_$index',
            ) ??
            true;
        if (!context.mounted) return;
        if (!ready) {
          final issue = notif?.lastScheduleIssue;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                issue?.message ??
                    I18n.tr('preferences.daily_reminder.not_ready'),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
      }
      await context.read<PreferencesProvider>().setDailyReminderSlot(
        index,
        next,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.22),
          width: 0.4,
        ),
      ),
      child: ExpansionTile(
        initiallyExpanded: index == 0,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Icon(Icons.notifications_active_outlined, color: cs.primary),
        title: Text(
          _title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.normal,
          ),
        ),
        subtitle: Text(
          slot.enabled
              ? '${_kindLabel(slot.kind)} · $_time · ${_repeatDaysLabel(slot.repeatDays)} · ${_taskScopeText(slot)}'
              : '${I18n.tr('preferences.daily_reminder.disabled')} · $_time',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Switch(
          value: slot.enabled,
          onChanged: _saving
              ? null
              : (value) => _save(context, slot.copyWith(enabled: value)),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
        children: [
          AppSettingsTile(
            icon: Icons.notifications_none_rounded,
            color: Colors.teal,
            title: I18n.tr('preferences.daily_reminder.kind.title'),
            subtitle: _kindDescription(slot.kind),
            trailing: _ReminderKindSelector(
              value: slot.kind,
              enabled: !_saving,
              onChanged: (kind) => _save(
                context,
                slot.copyWith(enabled: kind != ReminderKind.off, kind: kind),
              ),
            ),
          ),
          const SizedBox(height: 6),
          AppSettingsTile(
            icon: Icons.schedule,
            color: Colors.deepOrange,
            title: I18n.tr('preferences.daily_reminder.time'),
            subtitle: I18n.tr('preferences.daily_reminder.time.subtitle'),
            trailing: TextButton(
              onPressed: _saving
                  ? null
                  : () async {
                      final picked = await AppTimePicker.show(
                        context,
                        initialTime: TimeOfDay(
                          hour: slot.hour,
                          minute: slot.minute,
                        ),
                        title:
                            '$_title${I18n.tr('preferences.daily_reminder.time_suffix')}',
                        subtitle: I18n.tr(
                          'preferences.daily_reminder.time_picker.subtitle',
                        ),
                      );
                      if (picked == null || !context.mounted) return;
                      await _save(
                        context,
                        slot.copyWith(hour: picked.hour, minute: picked.minute),
                      );
                    },
              child: Text(_time),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _scopeChip(
                context,
                I18n.tr('preferences.daily_reminder.chip.today_tasks'),
                slot.includeTodayTasks,
                slot.copyWith(includeTodayTasks: !slot.includeTodayTasks),
              ),
              _scopeChip(
                context,
                I18n.tr('preferences.daily_reminder.chip.tomorrow_plan'),
                slot.includeTomorrowPlan,
                slot.copyWith(includeTomorrowPlan: !slot.includeTomorrowPlan),
              ),
              _scopeChip(
                context,
                I18n.tr('preferences.daily_reminder.chip.overdue_tasks'),
                slot.includeOverdue,
                slot.copyWith(includeOverdue: !slot.includeOverdue),
              ),
              _scopeChip(
                context,
                I18n.tr('preferences.daily_reminder.chip.pause_holidays'),
                slot.pauseHolidays,
                slot.copyWith(pauseHolidays: !slot.pauseHolidays),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var day = 1; day <= 7; day++)
                FilterChip(
                  label: Text(_weekdayLabel(day)),
                  selected: slot.repeatDays.contains(day),
                  onSelected: _saving
                      ? null
                      : (_) {
                          final nextDays =
                              slot.repeatDays.contains(day)
                                    ? slot.repeatDays
                                          .where((d) => d != day)
                                          .toList()
                                    : [...slot.repeatDays, day]
                                ..sort();
                          _save(context, slot.copyWith(repeatDays: nextDays));
                        },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _scopeChip(
    BuildContext context,
    String label,
    bool selected,
    DailyReminderSlot next,
  ) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: _saving ? null : (_) => _save(context, next),
    );
  }
}

class _ReminderKindSelector extends StatelessWidget {
  final ReminderKind value;
  final bool enabled;
  final ValueChanged<ReminderKind> onChanged;

  const _ReminderKindSelector({
    required this.value,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SegmentedButton<ReminderKind>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: ReminderKind.push,
          label: Text(I18n.tr('reminder.kind.push')),
        ),
        ButtonSegment(
          value: ReminderKind.popup,
          label: Text(I18n.tr('reminder.kind.popup')),
        ),
        ButtonSegment(
          value: ReminderKind.alarm,
          label: Text(I18n.tr('reminder.kind.alarm')),
        ),
        ButtonSegment(
          value: ReminderKind.off,
          label: Text(I18n.tr('reminder.kind.off')),
        ),
      ],
      selected: {DailyReminderSlot.normalizeKind(value)},
      onSelectionChanged: enabled ? (values) => onChanged(values.single) : null,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStateProperty.all(
          Theme.of(context).textTheme.labelMedium,
        ),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return cs.onSurface;
          return cs.onSurface;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return cs.primary.withValues(alpha: 0.12);
          }
          return cs.surface;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          final color = states.contains(WidgetState.selected)
              ? cs.primary.withValues(alpha: 0.38)
              : cs.outlineVariant.withValues(alpha: 0.45);
          return BorderSide(color: color, width: 0.45);
        }),
      ),
    );
  }
}

String _kindLabel(ReminderKind kind) {
  return switch (DailyReminderSlot.normalizeKind(kind)) {
    ReminderKind.push => I18n.tr('reminder.kind.push'),
    ReminderKind.popup => I18n.tr('reminder.kind.popup'),
    ReminderKind.alarm => I18n.tr('reminder.kind.alarm'),
    ReminderKind.off => I18n.tr('reminder.kind.off'),
    ReminderKind.email => I18n.tr('reminder.kind.push'),
  };
}

String _kindDescription(ReminderKind kind) {
  return switch (DailyReminderSlot.normalizeKind(kind)) {
    ReminderKind.push => I18n.tr(
      'preferences.daily_reminder.kind.push.description',
    ),
    ReminderKind.popup => I18n.tr(
      'preferences.daily_reminder.kind.popup.description',
    ),
    ReminderKind.alarm => I18n.tr(
      'preferences.daily_reminder.kind.alarm.description',
    ),
    ReminderKind.off => I18n.tr(
      'preferences.daily_reminder.kind.off.description',
    ),
    ReminderKind.email => I18n.tr(
      'preferences.daily_reminder.kind.push.description',
    ),
  };
}

bool _sameDays(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

DateTime? _nextSlotTrigger(DailyReminderSlot slot) {
  final now = DateTime.now();
  for (var offset = 0; offset <= 7; offset++) {
    final date = now.add(Duration(days: offset));
    final target = DateTime(
      date.year,
      date.month,
      date.day,
      slot.hour,
      slot.minute,
    );
    if (target.isAfter(now) && slot.repeatDays.contains(target.weekday)) {
      return target;
    }
  }
  return null;
}

class _NotificationRingtoneSection extends StatefulWidget {
  const _NotificationRingtoneSection();

  @override
  State<_NotificationRingtoneSection> createState() =>
      _NotificationRingtoneSectionState();
}

class _NotificationRingtoneSectionState
    extends State<_NotificationRingtoneSection> {
  int _volume = ReminderRingtoneSettings.defaultVolumePercent;
  String _sound = ReminderRingtoneSettings.defaultSound;
  bool _previewing = false;
  final ReminderRingtonePlatformPolicy _policy =
      ReminderRingtoneSettings.platformPolicy;

  @override
  void initState() {
    super.initState();
    if (!_policy.supportsBuiltInSoundPicker) return;
    ReminderRingtoneSettings.loadVolumePercent().then((value) {
      if (mounted) setState(() => _volume = value);
    });
    ReminderRingtoneSettings.loadSound().then((value) {
      if (mounted) setState(() => _sound = value);
    });
  }

  @override
  void dispose() {
    if (_policy.supportsBuiltInSoundPicker) {
      unawaited(ReminderRingtoneSettings.stopPreview());
    }
    super.dispose();
  }

  Future<void> _setVolume(int value) async {
    if (_previewing) return;
    setState(() {
      _volume = value;
      _previewing = true;
    });
    try {
      await _applyRingtoneChange(
        () => ReminderRingtoneSettings.setVolumePercent(value),
        successMessage: '已切换音量并开始试听',
      );
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
    await _reloadRingtoneSettings();
  }

  Future<void> _setSound(String value) async {
    if (_previewing) return;
    final label = ReminderRingtoneSettings.sounds
        .firstWhere(
          (sound) => sound.id == value,
          orElse: () => ReminderRingtoneSettings.sounds.first,
        )
        .label;
    setState(() {
      _sound = value;
      _previewing = true;
    });
    try {
      await _applyRingtoneChange(
        () => ReminderRingtoneSettings.setSound(value),
        successMessage: '已切换为 $label，并开始试听',
      );
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
    await _reloadRingtoneSettings();
  }

  Future<void> _previewCurrentSound() async {
    if (_previewing) return;
    setState(() => _previewing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ReminderRingtoneSettings.previewCurrentSound();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('正在试听当前提醒铃声'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ReminderRingtonePreviewException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(e.message), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _applyRingtoneChange(
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    try {
      await action();
      if (!mounted || successMessage == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ReminderRingtonePreviewException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _reloadRingtoneSettings() async {
    if (!_policy.supportsBuiltInSoundPicker) return;
    final volume = await ReminderRingtoneSettings.loadVolumePercent();
    final sound = await ReminderRingtoneSettings.loadSound();
    if (!mounted) return;
    setState(() {
      _volume = volume;
      _sound = sound;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_policy.supportsBuiltInSoundPicker) {
      return AppSettingsSection(
        title: I18n.tr('preferences.ringtone.section'),
        subtitle: I18n.tr(_policy.sectionSubtitleKey),
        children: [
          AppSettingsTile(
            icon: Icons.notifications_active_outlined,
            color: Colors.orange,
            title: I18n.tr(_policy.tileTitleKey),
            subtitle: I18n.tr(_policy.tileSubtitleKey),
            trailing: const SizedBox.shrink(),
          ),
        ],
      );
    }

    return AppSettingsSection(
      title: I18n.tr('preferences.ringtone.section'),
      subtitle: I18n.tr(_policy.sectionSubtitleKey),
      children: [
        AppSettingsTile(
          icon: Icons.notifications_active_outlined,
          color: Colors.orange,
          title: I18n.tr('preferences.ringtone.sound'),
          subtitle: ReminderRingtoneSettings.sounds
              .firstWhere((sound) => sound.id == _sound)
              .label,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '试听当前铃声',
                onPressed: _previewing ? null : _previewCurrentSound,
                icon: _previewing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.volume_up_outlined),
              ),
              const SizedBox(width: 4),
              AppCompactDropdown<String>(
                value: _sound,
                width: 112,
                items: [
                  for (final sound in ReminderRingtoneSettings.sounds)
                    DropdownMenuItem(value: sound.id, child: Text(sound.label)),
                ],
                onChanged: (value) => value == null ? null : _setSound(value),
              ),
            ],
          ),
        ),
        if (_policy.supportsVolumePresets)
          AppSettingsTile(
            icon: Icons.volume_up_outlined,
            color: Colors.deepOrange,
            title: I18n.tr('preferences.ringtone.volume'),
            subtitle: '${I18n.tr('preferences.ringtone.current')} $_volume%',
            trailing: Wrap(
              spacing: 6,
              children: [
                for (final value in ReminderRingtoneSettings.presets)
                  ChoiceChip(
                    label: Text('$value%'),
                    selected: _volume == value,
                    onSelected: (_) => _setVolume(value),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ReportReminderSection extends StatelessWidget {
  const _ReportReminderSection();

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();
    return AppSettingsSection(
      title: '报告推送',
      subtitle: '按你的节奏提醒查看每日复盘、周报、月报和年报',
      children: [
        _ReportReminderTile(
          title: '每日效率复盘',
          icon: Icons.today_outlined,
          color: Colors.blue,
          config: prefs.dailyReportReminderConfig,
          cadence: _ReportReminderCadence.daily,
        ),
        _ReportReminderTile(
          title: '每周效率周报',
          icon: Icons.summarize_outlined,
          color: Colors.indigo,
          config: prefs.weeklyReportReminderConfig,
          cadence: _ReportReminderCadence.weekly,
        ),
        _ReportReminderTile(
          title: '每月成长月报',
          icon: Icons.calendar_month_outlined,
          color: Colors.teal,
          config: prefs.monthlyReportReminderConfig,
          cadence: _ReportReminderCadence.monthly,
        ),
        _ReportReminderTile(
          title: '每年成长年报',
          icon: Icons.event_available_outlined,
          color: Colors.deepOrange,
          config: prefs.yearlyReportReminderConfig,
          cadence: _ReportReminderCadence.yearly,
        ),
      ],
    );
  }
}

enum _ReportReminderCadence { daily, weekly, monthly, yearly }

class _ReportReminderTile extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color color;
  final ReportReminderConfig config;
  final _ReportReminderCadence cadence;

  const _ReportReminderTile({
    required this.title,
    required this.icon,
    required this.color,
    required this.config,
    required this.cadence,
  });

  @override
  State<_ReportReminderTile> createState() => _ReportReminderTileState();
}

class _ReportReminderTileState extends State<_ReportReminderTile> {
  bool _saving = false;

  String get title => widget.title;
  IconData get icon => widget.icon;
  Color get color => widget.color;
  ReportReminderConfig get config => widget.config;
  _ReportReminderCadence get cadence => widget.cadence;

  String get _time =>
      I18nDateFormat.timeOfDay(hour: config.hour, minute: config.minute);

  String get _subtitle {
    final cadenceText = switch (cadence) {
      _ReportReminderCadence.daily => '每天',
      _ReportReminderCadence.weekly => '每${_weekdayLabel(config.weekday)}',
      _ReportReminderCadence.monthly => '每月 ${config.monthDay} 日',
      _ReportReminderCadence.yearly =>
        '每年 ${config.month} 月 ${config.monthDay} 日',
    };
    final state = config.enabled ? '动态摘要' : '已关闭';
    return '$state · $cadenceText $_time';
  }

  Future<void> _save(BuildContext context, ReportReminderConfig next) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final prefs = context.read<PreferencesProvider>();
      await switch (cadence) {
        _ReportReminderCadence.daily => prefs.setDailyReportReminderConfig(
          next,
        ),
        _ReportReminderCadence.weekly => prefs.setWeeklyReportReminderConfig(
          next,
        ),
        _ReportReminderCadence.monthly => prefs.setMonthlyReportReminderConfig(
          next,
        ),
        _ReportReminderCadence.yearly => prefs.setYearlyReportReminderConfig(
          next,
        ),
      };
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _timeSubtitle {
    return switch (cadence) {
      _ReportReminderCadence.daily => '到点推送今天报告动态摘要',
      _ReportReminderCadence.weekly => '到点推送上一周报告动态摘要',
      _ReportReminderCadence.monthly => '到点推送上月报告动态摘要',
      _ReportReminderCadence.yearly => '到点推送上一年报告动态摘要',
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.28),
          width: 0.45,
        ),
      ),
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: Text(_subtitle),
        trailing: Switch(
          value: config.enabled,
          onChanged: _saving
              ? null
              : (v) => _save(context, config.copyWith(enabled: v)),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          AppSettingsTile(
            icon: Icons.schedule,
            color: color,
            title: '推送时间',
            subtitle: _timeSubtitle,
            trailing: TextButton(
              onPressed: _saving
                  ? null
                  : () async {
                      final picked = await AppTimePicker.show(
                        context,
                        initialTime: TimeOfDay(
                          hour: config.hour,
                          minute: config.minute,
                        ),
                        title: '$title推送时间',
                        subtitle: '修改后会重排下一次报告通知',
                      );
                      if (picked == null || !context.mounted) return;
                      await _save(
                        context,
                        config.copyWith(
                          hour: picked.hour,
                          minute: picked.minute,
                        ),
                      );
                    },
              child: Text(_time),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _cadenceChips(context),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _cadenceChips(BuildContext context) {
    return switch (cadence) {
      _ReportReminderCadence.daily => const <Widget>[],
      _ReportReminderCadence.weekly => [
        for (var day = 1; day <= 7; day++)
          FilterChip(
            label: Text(_weekdayLabel(day)),
            selected: config.weekday == day,
            showCheckmark: false,
            onSelected: _saving
                ? null
                : (_) => _save(context, config.copyWith(weekday: day)),
          ),
      ],
      _ReportReminderCadence.monthly => _monthDayChips(context),
      _ReportReminderCadence.yearly => [
        for (var month = 1; month <= 12; month++)
          FilterChip(
            label: Text('$month 月'),
            selected: config.month == month,
            showCheckmark: false,
            onSelected: _saving
                ? null
                : (_) => _save(context, config.copyWith(month: month)),
          ),
        for (final day in const [1, 5, 10, 15, 20, 25, 28, 31])
          FilterChip(
            label: Text('$day 日'),
            selected: config.monthDay == day,
            showCheckmark: false,
            onSelected: _saving
                ? null
                : (_) => _save(context, config.copyWith(monthDay: day)),
          ),
      ],
    };
  }

  List<Widget> _monthDayChips(BuildContext context) {
    return [
      for (final day in const [1, 5, 10, 15, 20, 25, 28, 31])
        FilterChip(
          label: Text('$day 日'),
          selected: config.monthDay == day,
          showCheckmark: false,
          onSelected: _saving
              ? null
              : (_) => _save(context, config.copyWith(monthDay: day)),
        ),
    ];
  }
}

Color _notificationColor(NotificationType type) {
  return switch (type) {
    NotificationType.todo => Colors.blue,
    NotificationType.habit => Colors.green,
    NotificationType.pomodoro => Colors.red,
    NotificationType.anniversary => Colors.pink,
    NotificationType.location => Colors.teal,
    NotificationType.general => Colors.orange,
  };
}

IconData _notificationIcon(NotificationType type) {
  return switch (type) {
    NotificationType.todo => Icons.checklist,
    NotificationType.habit => Icons.repeat,
    NotificationType.pomodoro => Icons.timer,
    NotificationType.anniversary => Icons.event_available_outlined,
    NotificationType.location => Icons.location_on_outlined,
    NotificationType.general => Icons.notifications_active_outlined,
  };
}

String _notificationTypeLabel(NotificationType type) {
  return switch (type) {
    NotificationType.todo => '待办',
    NotificationType.habit => '习惯',
    NotificationType.pomodoro => '番茄钟',
    NotificationType.anniversary => '纪念日',
    NotificationType.location => '位置',
    NotificationType.general => '系统',
  };
}

String _formatNotificationTime(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

String _repeatDaysLabel(List<int> days) {
  if (days.length == 7) return I18n.tr('repeat.every_day');
  if (days.length == 5 && days.every((day) => day >= 1 && day <= 5)) {
    return I18n.tr('repeat.weekdays');
  }
  return days.map(_weekdayLabel).join('/');
}

String _weekdayLabel(int day) {
  const keys = [
    'weekday.mon',
    'weekday.tue',
    'weekday.wed',
    'weekday.thu',
    'weekday.fri',
    'weekday.sat',
    'weekday.sun',
  ];
  if (day < 1 || day > 7) return I18n.tr('weekday.unknown');
  return I18n.tr(keys[day - 1]);
}

String _taskScopeText(DailyReminderSlot slot) {
  final parts = <String>[
    if (slot.includeTodayTasks)
      I18n.tr('preferences.daily_reminder.scope.today'),
    if (slot.includeTomorrowPlan)
      I18n.tr('preferences.daily_reminder.scope.tomorrow'),
    if (slot.includeOverdue)
      I18n.tr('preferences.daily_reminder.scope.overdue'),
  ];
  if (parts.isEmpty) return I18n.tr('preferences.daily_reminder.scope.none');
  return parts.join('/');
}
