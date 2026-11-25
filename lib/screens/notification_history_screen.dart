import '../widgets/app_date_format.dart';
import '../core/i18n_date_format.dart';
import 'dart:async';

import 'package:duoyi/desktop_web/desktop_embedded_scope.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../core/account_preference_writes.dart';
import '../core/i18n.dart';
import '../core/design_tokens.dart';
import '../core/notification_history_policy.dart';
import '../core/notification_ui_copy.dart';
import '../core/platform_info.dart';
import '../core/report_reminder_config.dart';
import '../models/goal.dart' show ReminderKind;
import '../providers/auth_provider.dart';
import '../providers/app_lock_provider.dart';
import '../providers/notification_service.dart';
import '../providers/preferences_provider.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/alarm_service.dart';
import '../services/app_update_service.dart';
import '../services/daily_digest_reminder_sync.dart';
import '../services/local_notifications.dart';
import '../services/notification_permission_exception.dart';
import '../services/notification_settings.dart';
import '../services/notification_status_bar_sync_bridge.dart';
import '../services/native_reminder_ringtone.dart';
import '../services/reminder_ringtone_settings.dart';
import '../services/reminder_scheduler.dart';
import '../widgets/app_time_picker.dart';
import '../widgets/controller_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';
import '../widgets/brand_background.dart'
    show BrandBackground, BrandRouteSurface, LocaleStatePreservingRoute;
import 'calendar_screen.dart';
import 'countdown_screen.dart';
import 'today_detail_router.dart';

enum _NotificationReadFilter { all, unread, read }

const double _notificationSettingsContentMaxWidth = 760;

// Keep the content in the same Stack slot when switching brands, so scroll
// positions and held controls survive. Only glass owns an optional backdrop.
Widget _notificationRouteSurface(
  BuildContext context, {
  required Color routeBackground,
  required Widget child,
}) {
  final isLiquidGlass =
      appSurfaceStyleOf(context) == AppSurfaceStyle.liquidGlass;
  final hasBrandSurface =
      DesktopEmbeddedHostScope.isHosted(context) ||
      context.findAncestorWidgetOfExactType<BrandBackground>() != null ||
      context.findAncestorWidgetOfExactType<BrandRouteSurface>() != null;
  return Material(
    color: isLiquidGlass && hasBrandSurface
        ? Colors.transparent
        : routeBackground,
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (isLiquidGlass && !hasBrandSurface)
          const Positioned.fill(
            child: BrandBackground(child: SizedBox.expand()),
          ),
        child,
      ],
    ),
  );
}

class NotificationHistoryScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  /// 兼容旧路由参数；通知记录现在只通过用户手动操作标记已读。
  final bool markReadOnOpen;

  const NotificationHistoryScreen({super.key, this.markReadOnOpen = false});

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
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _resetPaging() {
    _page = 0;
  }

  /// 通知类型 → 可跳转详情页的 section 映射。
  ///
  /// 只有 todo / habit / anniversary 关联到可打开的详情页；
  /// pomodoro / general / location 没有对应详情页，点击保持"只切换已读"。
  static TodaySectionKind? _relatedSectionKind(NotificationType type) {
    switch (type) {
      case NotificationType.todo:
        return TodaySectionKind.todos;
      case NotificationType.habit:
        return TodaySectionKind.habits;
      case NotificationType.anniversary:
        return TodaySectionKind.anniversaries;
      case NotificationType.pomodoro:
      case NotificationType.general:
      case NotificationType.location:
        return null;
    }
  }

  bool _hasNavigableTarget(NotificationItem item) {
    final kind = _relatedSectionKind(item.type);
    if (kind != null && (item.relatedId?.trim().isNotEmpty ?? false)) {
      return true;
    }
    final rawPayload = item.payload?.trim();
    if (rawPayload == null || rawPayload.isEmpty) return false;
    final uri = Uri.tryParse(rawPayload);
    if (uri == null || uri.scheme != 'duoyi') return false;
    return switch (uri.host) {
      'course' || 'goal' || 'countdown' =>
        uri.pathSegments.isNotEmpty && uri.pathSegments.first.trim().isNotEmpty,
      'calendar' => true,
      _ => false,
    };
  }

  /// 点击卡片打开关联对象详情：先把这条记录标为已读，再跳转。
  ///
  /// - 关联对象已被删除时由 [TodayDetailRouter] 的空态兜底页承接，不会黑屏；
  /// - 已读记录同样可以点击跳转（[NotificationService.markHistoryItemRead]
  ///   对已读记录是幂等空操作）；
  /// - 记录标为已读的 await 前后通过 [AccountLocalDataCleaner.accountDataGeneration]
  ///   防护账号切换，切号后丢弃失效的跳转请求，防止跨账号串门打开上一个账号的对象。
  Future<void> _openRelatedItem(NotificationItem item) async {
    final kind = _relatedSectionKind(item.type);
    final relatedId = item.relatedId;
    final payloadUri = item.payload?.trim().isNotEmpty == true
        ? Uri.tryParse(item.payload!.trim())
        : null;
    final hasRelatedKind =
        kind != null && relatedId != null && relatedId.trim().isNotEmpty;
    final hasPayloadRoute =
        payloadUri != null &&
        payloadUri.scheme == 'duoyi' &&
        (payloadUri.host == 'calendar' ||
            ((payloadUri.host == 'course' ||
                    payloadUri.host == 'goal' ||
                    payloadUri.host == 'countdown') &&
                payloadUri.pathSegments.isNotEmpty &&
                payloadUri.pathSegments.first.trim().isNotEmpty));
    if (!hasRelatedKind && !hasPayloadRoute) return;
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    await context.read<NotificationService>().markHistoryItemRead(
      item.id,
      read: true,
    );
    if (!mounted) return;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
      return;
    }
    if (hasRelatedKind) {
      await TodayDetailRouter.open(context, kind, id: relatedId);
      return;
    }
    final targetId = payloadUri!.pathSegments.isNotEmpty
        ? Uri.decodeComponent(payloadUri.pathSegments.first)
        : '';
    switch (payloadUri.host) {
      case 'course':
        await TodayDetailRouter.open(
          context,
          TodaySectionKind.courses,
          id: targetId,
        );
        return;
      case 'goal':
        await TodayDetailRouter.open(
          context,
          TodaySectionKind.goals,
          id: targetId,
        );
        return;
      case 'calendar':
        final dateStr = payloadUri.queryParameters['date'];
        final date = dateStr == null ? null : DateTime.tryParse(dateStr);
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                BrandRouteSurface(child: CalendarScreen(initialDate: date)),
          ),
        );
        return;
      case 'countdown':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const BrandRouteSurface(child: CountdownScreen()),
          ),
        );
        return;
    }
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
    final route = createControllerDialogRoute<bool>(
      context: context,
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, _, _) => AppDialog(
          title: Text(NotificationUiCopy.confirmClearDialogTitle),
          icon: const Icon(Icons.delete_outline),
          content: Text(
            NotificationUiCopy.confirmClearDialogContent(
              count,
            ), // content: Text('将清空当前保留的 $count 条通知记录，已调度的提醒不会被取消。') // 已调度的提醒不会被取消
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(NotificationUiCopy.clearAction),
            ),
          ],
        ),
      ),
    );
    final confirmed = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<bool>(route);
    if (confirmed != true || !mounted) return;
    await context.read<NotificationService>().clearHistory();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(NotificationUiCopy.historyClearedSnack),
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
    final isLiquidGlass =
        appSurfaceStyleOf(context) == AppSurfaceStyle.liquidGlass;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final hasPager = filteredHistory.length > _pageSize;

    final scaffold = ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) => Scaffold(
        backgroundColor: isLiquidGlass ? Colors.transparent : routeBackground,
        appBar: AppBar(
          title: Text(NotificationUiCopy.notificationHistoryTitle),
          titleTextStyle: appSecondaryRouteTitleTextStyle(context),
          backgroundColor: routeBackground.withValues(alpha: 0.96),
          surfaceTintColor: Colors.transparent,
          actions: [
            if (service.unreadCount > 0)
              IconButton(
                key: const ValueKey(
                  'notification_history_mark_all_read_button',
                ),
                tooltip: NotificationUiCopy.markAllReadTooltip,
                onPressed: () => service.markAllHistoryRead(),
                icon: const Icon(Icons.mark_email_read_outlined),
              ),
            IconButton(
              tooltip: NotificationUiCopy.clearHistoryTooltip,
              onPressed: history.isEmpty
                  ? null
                  : () => _confirmClearHistory(history.length),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: AppSecondaryControlTheme(
          child: history.isEmpty
              ? Center(child: Text(NotificationUiCopy.emptyHistory))
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
                          ? EmptyState(
                              icon: Icons.manage_search_outlined,
                              message: NotificationUiCopy.emptyHistoryFiltered,
                            )
                          : ListView.separated(
                              padding: EdgeInsets.fromLTRB(
                                12,
                                6,
                                12,
                                hasPager ? 12 : 24 + bottomInset,
                              ),
                              itemCount: visibleHistory.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final item = visibleHistory[index];
                                final hasRelatedTarget = _hasNavigableTarget(
                                  item,
                                );
                                return _NotificationRecordCard(
                                  key: ValueKey(
                                    'notification_record_${item.id}',
                                  ),
                                  item: item,
                                  onShowDetails: () =>
                                      _showNotificationRecordDetails(item),
                                  onToggleRead: () =>
                                      service.markHistoryItemRead(
                                        item.id,
                                        read: !item.isRead,
                                      ),
                                  onOpenRelated: hasRelatedTarget
                                      ? () => _openRelatedItem(item)
                                      : null,
                                );
                              },
                            ),
                    ),
                    if (hasPager)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          12,
                          0,
                          12,
                          12 + bottomInset,
                        ),
                        child: Row(
                          children: [
                            Text(
                              '${pageStart + 1}-$pageEnd / ${filteredHistory.length}',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            const Spacer(),
                            IconButton.outlined(
                              tooltip: NotificationUiCopy.pagerPrevTooltip,
                              onPressed: currentPage == 0
                                  ? null
                                  : () =>
                                        setState(() => _page = currentPage - 1),
                              icon: const Icon(Icons.chevron_left),
                            ),
                            const SizedBox(width: 8),
                            IconButton.outlined(
                              tooltip: NotificationUiCopy.pagerNextTooltip,
                              onPressed: currentPage >= totalPages - 1
                                  ? null
                                  : () =>
                                        setState(() => _page = currentPage + 1),
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
    return _notificationRouteSurface(
      context,
      routeBackground: routeBackground,
      child: scaffold,
    );
  }

  Future<void> _showNotificationRecordDetails(NotificationItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _NotificationRecordDetailSheet(item: item),
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
              hintText:
                  NotificationUiCopy.searchHint, // hintText: '搜索标题、内容或关联 ID'
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchCtrl.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: NotificationUiCopy.clearSearchTooltip,
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
                _historyTypeChip(
                  NotificationUiCopy.filterAll,
                  null,
                  typeFilter,
                  onTypeChanged,
                ),
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_NotificationReadFilter>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: _NotificationReadFilter.all,
                  label: Text(NotificationUiCopy.filterAll),
                ),
                ButtonSegment(
                  value: _NotificationReadFilter.unread,
                  label: Text(NotificationUiCopy.filterUnread),
                ),
                ButtonSegment(
                  value: _NotificationReadFilter.read,
                  label: Text(NotificationUiCopy.filterRead),
                ),
              ],
              selected: {readFilter},
              onSelectionChanged: (values) =>
                  onReadFilterChanged(values.single),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            NotificationUiCopy.formatHistorySummary(
              historyCount: historyCount,
              filteredCount: filteredCount,
              unreadCount: unreadCount,
              page: page,
              totalPages: totalPages,
              pageSize: _NotificationHistoryScreenState._pageSize,
            ), // 支持搜索、筛选和分页浏览
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
  final VoidCallback? onShowDetails;
  final VoidCallback onToggleRead;

  /// 非空时点击卡片跳到关联对象详情（todo / habit / anniversary）；
  /// 为空时回退为原有的"点击只切换已读"。
  final VoidCallback? onOpenRelated;

  const _NotificationRecordCard({
    super.key,
    required this.item,
    this.onShowDetails,
    required this.onToggleRead,
    this.onOpenRelated,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _notificationColor(item.type, cs);
    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      color: item.isRead ? null : cs.primary.withValues(alpha: 0.06),
      border: item.isRead
          ? null
          : Border.all(color: cs.primary.withValues(alpha: 0.22), width: 0.45),
      onTap: onOpenRelated ?? (item.isRead ? null : onToggleRead),
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
                      label: item.isRead
                          ? NotificationUiCopy.badgeRead
                          : NotificationUiCopy
                                .badgeUnread, // label: item.isRead ? '已读' : '未读'
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
                  _formatNotificationTime(
                    item.scheduledTime,
                    AppDateFormat.patternOf(context),
                  ),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.48),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onShowDetails != null)
                IconButton(
                  key: ValueKey('notification_record_detail_button_${item.id}'),
                  tooltip: NotificationUiCopy.viewDetailsTooltip,
                  onPressed: onShowDetails,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 32,
                  ),
                  icon: Icon(
                    Icons.info_outline,
                    size: 19,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              IconButton(
                key: ValueKey('notification_record_toggle_read_${item.id}'),
                tooltip: item.isRead
                    ? NotificationUiCopy.markAsUnreadTooltip
                    : NotificationUiCopy.markAsReadTooltip,
                onPressed: onToggleRead,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
                icon: Icon(
                  item.isRead
                      ? Icons.mark_email_unread_outlined
                      : Icons.mark_email_read_outlined,
                  size: 19,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NotificationRecordDetailSheet extends StatelessWidget {
  final NotificationItem item;

  const _NotificationRecordDetailSheet({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final typeColor = _notificationColor(item.type, cs);
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            20 + MediaQuery.paddingOf(context).bottom,
          ),
          child: SingleChildScrollView(
            key: const ValueKey('notification_record_detail_scroll'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _notificationIcon(item.type),
                        size: 21,
                        color: typeColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.normal,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              AppStatusBadge(
                                label: _notificationTypeLabel(item.type),
                                color: typeColor,
                              ),
                              AppStatusBadge(
                                label: item.isRead
                                    ? NotificationUiCopy.badgeRead
                                    : NotificationUiCopy.badgeUnread,
                                color: item.isRead
                                    ? cs.onSurfaceVariant
                                    : cs.error,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (item.body.trim().isNotEmpty)
                  _NotificationRecordDetailLine(
                    label: NotificationUiCopy
                        .detailSheetContentLabel, // _NotificationRecordDetailLine(label: '内容'
                    value: item.body,
                  )
                else
                  _NotificationRecordDetailLine(
                    label: NotificationUiCopy
                        .detailSheetContentLabel, // _NotificationRecordDetailLine(label: '内容'
                    value: NotificationUiCopy.detailSheetNoContent,
                  ),
                _NotificationRecordDetailLine(
                  label: NotificationUiCopy.detailSheetTriggerTime,
                  value: _formatNotificationTime(
                    item.scheduledTime,
                    AppDateFormat.patternOf(context),
                  ),
                ),
                _NotificationRecordDetailLine(
                  label: NotificationUiCopy.detailSheetRecordId,
                  value: item.id,
                ),
                _NotificationRecordDetailLine(
                  label: NotificationUiCopy.detailSheetRelatedItem,
                  value: item.relatedId?.trim().isNotEmpty == true
                      ? item.relatedId!.trim()
                      : NotificationUiCopy.detailSheetNone,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationRecordDetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _NotificationRecordDetailLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.52),
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurface, height: 1.28),
          ),
        ],
      ),
    );
  }
}

class NotificationSettingsScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

ReminderScheduler? _readReminderScheduler(BuildContext context) {
  try {
    final optional = context.read<ReminderScheduler?>();
    if (optional != null) return optional;
  } on ProviderNotFoundException {
    // Older tests and routes may intentionally omit the scheduler.
  }
  try {
    return context.read<ReminderScheduler>();
  } on ProviderNotFoundException {
    return null;
  }
}

AuthProvider? _readAuthProvider(BuildContext context) {
  try {
    final optional = context.read<AuthProvider?>();
    if (optional != null) return optional;
  } on ProviderNotFoundException {
    // Optional in test fixtures and lightweight routes.
  } catch (_) {
    // Gracefully handle missing provider or mock hierarchies.
  }
  try {
    return context.read<AuthProvider>();
  } on ProviderNotFoundException {
    return null;
  } catch (_) {
    return null;
  }
}

String _notificationAccountKey(AuthProvider? auth) {
  final state = auth?.state;
  return '${state?.userId ?? ''}:${state?.token ?? ''}';
}

bool _notificationAccountAvailable(AuthProvider? auth) =>
    !AccountPreferenceWrites.isBoundaryActive &&
    (auth == null ||
        (!auth.isAccountTransitionInProgress &&
            !auth.isLocalAccountDataBlocked));

/// Keeps a picker or save bound to the account that started it, including a
/// transition that returns to the same identity before the operation finishes.
class _NotificationAccountGuard {
  final BuildContext context;
  final AuthProvider? auth;
  final int generation = AccountLocalDataCleaner.accountDataGeneration;
  late final String key;
  bool _valid = true;

  _NotificationAccountGuard(this.context) : auth = _readAuthProvider(context) {
    key = _notificationAccountKey(auth);
    _valid = _notificationAccountAvailable(auth);
    auth?.addListener(_checkAccount);
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _checkAccount,
    );
  }

  void _checkAccount() {
    if (!_notificationAccountAvailable(auth) ||
        key != _notificationAccountKey(auth) ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
      _valid = false;
    }
  }

  bool get isCurrent =>
      _valid &&
      context.mounted &&
      identical(_readAuthProvider(context), auth) &&
      _notificationAccountAvailable(auth) &&
      key == _notificationAccountKey(auth) &&
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation);

  void dispose() {
    _valid = false;
    auth?.removeListener(_checkAccount);
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _checkAccount,
    );
  }
}

/// Retains the providers and session that rendered the history-limit control.
class _NotificationRetentionOrigin {
  _NotificationRetentionOrigin(
    BuildContext context,
    this.preferences,
    this.notifications,
  ) : auth = context.read<AuthProvider?>(),
      lock = context.read<AppLockProvider?>(),
      update = context.read<AppUpdateService?>(),
      route = ModalRoute.of(context),
      accountGeneration = AccountLocalDataCleaner.accountDataGeneration,
      preferenceGeneration = preferences.storageGeneration,
      notificationGeneration = notifications.storageGeneration {
    sessionGeneration = auth?.sessionGeneration;
    wasLoggedIn = auth?.state.isLoggedIn ?? false;
    _userId = _normalize(auth?.state.userId);
    if (wasLoggedIn) {
      try {
        lease = auth!.captureSessionLease();
      } catch (_) {
        leaseFailed = true;
      }
    }
  }

  final PreferencesProvider preferences;
  final NotificationService notifications;
  final AuthProvider? auth;
  final AppLockProvider? lock;
  final AppUpdateService? update;
  final ModalRoute<dynamic>? route;
  final int accountGeneration;
  final int preferenceGeneration;
  final int notificationGeneration;
  late final int? sessionGeneration;
  late final bool wasLoggedIn;
  String? _userId;
  AuthSessionLease? lease;
  bool leaseFailed = false;

  static String? _normalize(String? raw) {
    final value = raw?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  bool isCurrent(BuildContext context, {bool checkRoute = true}) {
    if (!context.mounted ||
        leaseFailed ||
        preferences.storageGeneration != preferenceGeneration ||
        notifications.storageGeneration != notificationGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        ) ||
        (route != null &&
            (!route!.isActive || (checkRoute && !route!.isCurrent)))) {
      return false;
    }
    try {
      if (!identical(context.read<PreferencesProvider>(), preferences) ||
          !identical(context.read<NotificationService>(), notifications) ||
          !identical(context.read<AuthProvider?>(), auth) ||
          !identical(context.read<AppLockProvider?>(), lock) ||
          !identical(context.read<AppUpdateService?>(), update) ||
          lock?.isLocked == true ||
          update?.mustUpdate == true) {
        return false;
      }
      final currentAuth = auth;
      if (currentAuth != null) {
        if (currentAuth.sessionGeneration != sessionGeneration ||
            currentAuth.state.isLoggedIn != wasLoggedIn ||
            currentAuth.isAccountTransitionInProgress ||
            currentAuth.isLocalAccountDataBlocked ||
            (lease != null && !currentAuth.isSessionLeaseCurrent(lease!))) {
          return false;
        }
        final id = _normalize(currentAuth.state.userId);
        if (_userId != null && id != _userId) return false;
        _userId ??= id;
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  int? _pendingPushCount;
  int? _pendingAlarmCount;
  bool? _exactAlarmGranted;
  Map<String, NotificationChannelStatus>? _channelStatuses;
  List<ReminderScheduleSnapshotEntry> _registeredReminders =
      const <ReminderScheduleSnapshotEntry>[];
  Set<int> _registeredReminderSystemQueueIds = <int>{};
  _RegisteredReminderQueueProbe _registeredReminderQueueProbe =
      _RegisteredReminderQueueProbe.loading;
  bool _busy = false;
  int _statusBarPreferenceGeneration = 0;
  int _statusRefreshGeneration = 0;
  int _lastStatusAccountGeneration = 0;
  String? _lastStatusAccountKey;
  int? _lastStatusSessionGeneration;
  AuthProvider? _statusAuth;
  bool _statusBoundaryPending = false;
  int _settingsAccountEpoch = 0;
  bool _historyLimitSaving = false;
  int _historyLimitSeq = 0;

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_onLocaleChanged);
    _lastStatusAccountGeneration =
        AccountLocalDataCleaner.accountDataGeneration;
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _handleStatusAccountBoundary,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_refreshStatus());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = _readAuthProvider(context);
    if (identical(_statusAuth, auth) && _lastStatusAccountKey != null) return;
    final changed = _lastStatusAccountKey != null;
    _statusAuth?.removeListener(_handleStatusAccountChanged);
    _statusAuth = auth;
    _statusAuth?.addListener(_handleStatusAccountChanged);
    _lastStatusAccountKey = _notificationAccountKey(auth);
    _lastStatusSessionGeneration = auth?.sessionGeneration;
    if (changed) _clearStatusForAccountBoundary();
    if (_statusBoundaryPending && _notificationAccountAvailable(auth)) {
      _queueStatusRefresh();
    }
  }

  void _queueStatusRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _statusBoundaryPending) unawaited(_refreshStatus());
    });
  }

  void _handleStatusAccountBoundary() {
    _lastStatusAccountGeneration =
        AccountLocalDataCleaner.accountDataGeneration;
    _clearStatusForAccountBoundary();
    unawaited(_resumeStatusAfterBoundary(_lastStatusAccountGeneration));
  }

  Future<void> _resumeStatusAfterBoundary(int generation) async {
    await AccountPreferenceWrites.waitForBoundary();
    if (!mounted ||
        generation != AccountLocalDataCleaner.accountDataGeneration ||
        !_statusBoundaryPending ||
        !_notificationAccountAvailable(_statusAuth)) {
      return;
    }
    await _refreshStatus();
  }

  void _handleStatusAccountChanged() {
    final key = _notificationAccountKey(_statusAuth);
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    if (key != _lastStatusAccountKey ||
        _statusAuth?.sessionGeneration != _lastStatusSessionGeneration ||
        generation != _lastStatusAccountGeneration ||
        !_notificationAccountAvailable(_statusAuth)) {
      _lastStatusAccountKey = key;
      _lastStatusSessionGeneration = _statusAuth?.sessionGeneration;
      _lastStatusAccountGeneration = generation;
      _clearStatusForAccountBoundary();
    }
    if (_statusBoundaryPending && _notificationAccountAvailable(_statusAuth)) {
      _queueStatusRefresh();
    }
  }

  void _clearStatusForAccountBoundary() {
    if (!mounted) return;
    _statusRefreshGeneration++;
    _statusBarPreferenceGeneration++;
    _historyLimitSeq++;
    _statusBoundaryPending = true;
    setState(() {
      _settingsAccountEpoch++;
      _busy = false;
      _historyLimitSaving = false;
      _pendingPushCount = null;
      _pendingAlarmCount = null;
      _exactAlarmGranted = null;
      _channelStatuses = null;
      _registeredReminders = const [];
      _registeredReminderSystemQueueIds = <int>{};
      _registeredReminderQueueProbe = _RegisteredReminderQueueProbe.loading;
    });
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _setHistoryLimit(
    int target,
    _NotificationRetentionOrigin origin,
  ) async {
    if (!mounted || _historyLimitSaving || !origin.isCurrent(context)) return;
    final seq = ++_historyLimitSeq;
    var preferenceSaved = false;
    bool isCurrent() =>
        mounted && seq == _historyLimitSeq && origin.isCurrent(context);
    setState(() => _historyLimitSaving = true);
    try {
      preferenceSaved = await origin.preferences.saveNotificationHistoryLimit(
        target,
        canWrite: isCurrent,
      );
      if (!mounted || !isCurrent() || !preferenceSaved) return;
      final applied = await origin.notifications.applyHistoryLimit(
        target,
        canWrite: isCurrent,
      );
      if (!mounted || !isCurrent() || !applied) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (_, _, _) =>
                Text(NotificationUiCopy.historyRetentionSaved(target)),
          ),
        ),
      );
    } catch (_) {
      if (!mounted || !isCurrent()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (_, _, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preferenceSaved
                      ? NotificationUiCopy.historyRetentionTrimFailed
                      : NotificationUiCopy.historyRetentionSaveFailed,
                ),
                TextButton(
                  key: const ValueKey('notification_history_limit_retry'),
                  onPressed: () {
                    if (!isCurrent() || _historyLimitSaving) return;
                    ScaffoldMessenger.of(context).removeCurrentSnackBar();
                    _setHistoryLimit(target, origin);
                  },
                  child: Text(NotificationUiCopy.retryAction),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      if (mounted && seq == _historyLimitSeq) {
        setState(() => _historyLimitSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _statusRefreshGeneration++;
    I18n.localeListenable.removeListener(_onLocaleChanged);
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _handleStatusAccountBoundary,
    );
    _statusAuth?.removeListener(_handleStatusAccountChanged);
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    if (!mounted) return;
    if (!_notificationAccountAvailable(_statusAuth)) {
      _clearStatusForAccountBoundary();
      return;
    }
    _statusBoundaryPending = false;
    final refreshGeneration = ++_statusRefreshGeneration;
    final account = _NotificationAccountGuard(context);
    bool isCurrent() =>
        refreshGeneration == _statusRefreshGeneration && account.isCurrent;
    final service = context.read<NotificationService>();
    final scheduler = _readReminderScheduler(context);
    setState(() {
      _busy = true;
      _registeredReminderQueueProbe = _RegisteredReminderQueueProbe.loading;
    });
    try {
      await service.refreshPermission();
      if (!mounted || !isCurrent()) return;
      var queueProbe = _RegisteredReminderQueueProbe.resolved;
      List<int> pendingIds;
      try {
        pendingIds = await LocalNotifications.instance.pendingIdsOrThrow();
      } catch (e, st) {
        debugPrint(
          '[NotificationSettings] pending notification probe failed: $e\n$st',
        );
        pendingIds = const <int>[];
        queueProbe = _RegisteredReminderQueueProbe.failed;
      }
      if (!mounted || !isCurrent()) return;
      await AlarmService.instance.init();
      if (!mounted || !isCurrent()) return;
      List<int> pendingAlarmIds;
      try {
        pendingAlarmIds = await AlarmService.instance.pendingIds();
      } catch (e, st) {
        debugPrint(
          '[NotificationSettings] pending alarm probe failed: $e\n$st',
        );
        pendingAlarmIds = const <int>[];
        queueProbe = _RegisteredReminderQueueProbe.failed;
      }
      if (!mounted || !isCurrent()) return;
      final exactAlarmGranted = await AlarmService.instance
          .hasExactAlarmPermission();
      if (!mounted || !isCurrent()) return;
      final channelStatuses =
          await NotificationSettings.notificationChannelStatuses(const [
            NotificationService.channelId,
            AlarmService.channelId,
            NativeReminderRingtone.statusChannelId,
            NativeReminderRingtone.fallbackChannelId,
          ]);
      if (!mounted || !isCurrent()) return;
      final registeredReminders =
          await scheduler?.registeredRemindersSnapshot() ??
          const <ReminderScheduleSnapshotEntry>[];
      if (!mounted || !isCurrent()) return;
      setState(() {
        _pendingPushCount = pendingIds.length;
        _pendingAlarmCount = pendingAlarmIds.length;
        _exactAlarmGranted = exactAlarmGranted;
        _channelStatuses = channelStatuses;
        _registeredReminders = registeredReminders;
        _registeredReminderSystemQueueIds = <int>{
          ...pendingIds,
          ...pendingAlarmIds,
        };
        _registeredReminderQueueProbe = queueProbe;
      });
    } catch (e, st) {
      debugPrint('[NotificationSettings] refresh status failed: $e\n$st');
      if (!mounted || !isCurrent()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(NotificationUiCopy.statusReadFailed),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (isCurrent()) setState(() => _busy = false);
      account.dispose();
    }
  }

  Future<void> _requestPermission() async {
    try {
      final granted = await context
          .read<NotificationService>()
          .requestPermission();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            granted
                ? NotificationUiCopy.permissionGrantedFeedback
                : NotificationUiCopy.permissionDeniedFeedback,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _refreshStatus();
    } catch (e, st) {
      debugPrint('[NotificationSettings] request permission failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(NotificationUiCopy.permissionRequestFailedFeedback),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _requestExactAlarmPermission() async {
    try {
      final granted = await AlarmService.instance.requestExactAlarmPermission();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            granted
                ? NotificationUiCopy.exactAlarmGrantedFeedback
                : NotificationUiCopy.exactAlarmDeniedFeedback,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _refreshStatus();
    } catch (e, st) {
      debugPrint('[NotificationSettings] exact alarm request failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(NotificationUiCopy.exactAlarmRequestFailedFeedback),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _setNotificationStatusBarPreference({
    required bool quickAdd,
    required bool value,
  }) async {
    final prefs = context.read<PreferencesProvider>();
    final generation = ++_statusBarPreferenceGeneration;
    final previousValue = quickAdd
        ? prefs.notificationQuickAdd
        : prefs.notificationTodayProgress;
    setState(() => _busy = true);
    try {
      if (quickAdd) {
        await prefs.setNotificationQuickAdd(value);
      } else {
        await prefs.setNotificationTodayProgress(value);
      }
      final synced = await _syncNotificationStatusBarNow(
        requestIfNeeded: value,
      );
      if (!mounted) return;
      if (generation != _statusBarPreferenceGeneration) return;
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
      final stillMatchesThisRequest = quickAdd
          ? prefs.notificationQuickAdd == value
          : prefs.notificationTodayProgress == value;
      if (stillMatchesThisRequest) {
        if (quickAdd) {
          await prefs.setNotificationQuickAdd(previousValue);
        } else {
          await prefs.setNotificationTodayProgress(previousValue);
        }
      } else {
        debugPrint(
          '[NotificationSettings] stale status bar sync failure ignored; '
          'latest local preference already changed.',
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            I18n.tr('preferences.notification_status_bar.sync_failed'),
          ),
        ),
      );
    } finally {
      if (mounted && generation == _statusBarPreferenceGeneration) {
        setState(() => _busy = false);
      }
    }
  }

  Future<bool> _syncNotificationStatusBarNow({
    bool requestIfNeeded = false,
  }) async {
    try {
      return await NotificationStatusBarSyncBridge.sync(
        force: true,
        requestIfNeeded: requestIfNeeded,
      );
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
      final service = context.read<NotificationService>();
      final sent = await service.sendTest();
      if (!mounted) return;
      if (!sent) {
        _showScheduleIssueSnack(
          context,
          service.lastScheduleIssue,
          fallback: NotificationUiCopy.testNotificationFailedFallback,
        );
        await _refreshStatus();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(I18n.tr('preferences.notify.test_sent')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _refreshStatus();
    } on NotificationPermissionDeniedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(I18n.tr('preferences.notify.test_permission_denied')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    } catch (e, st) {
      debugPrint('[NotificationSettings] send test failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(NotificationUiCopy.testNotificationError),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendScheduledTest() async {
    final kind = _scheduledTestReminderKind(context);
    await _sendScheduledDiagnostic(
      kind: kind,
      popupInAppOnly: kind != ReminderKind.popup,
    );
  }

  Future<void> _sendScheduledPushTest() {
    return _sendScheduledDiagnostic(kind: ReminderKind.push);
  }

  Future<void> _sendScheduledPopupTest() {
    return _sendScheduledDiagnostic(kind: ReminderKind.popup);
  }

  Future<void> _sendScheduledPopupFallbackTest() {
    return _sendScheduledDiagnostic(
      kind: ReminderKind.popup,
      popupInAppOnly: false,
    );
  }

  Future<void> _sendScheduledAlarmTest() {
    return _sendScheduledDiagnostic(
      kind: ReminderKind.alarm,
      fullScreenAlarm: false,
    );
  }

  Future<void> _sendScheduledFullScreenAlarmTest() {
    return _sendScheduledDiagnostic(kind: ReminderKind.alarm);
  }

  Future<void> _sendScheduledDiagnostic({
    required ReminderKind kind,
    bool fullScreenAlarm = true,
    bool popupInAppOnly = true,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final service = context.read<NotificationService>();
      final scheduler = _readReminderScheduler(context);
      service.clearScheduleIssue();
      if (kind == ReminderKind.push ||
          (kind == ReminderKind.popup &&
              (!popupInAppOnly || scheduler?.popup == null))) {
        final granted = await service.requestPermission();
        if (!granted) {
          throw const NotificationPermissionDeniedException();
        }
      }
      if (kind == ReminderKind.alarm) {
        await AlarmService.instance.init();
        final exactAlarmGranted =
            await AlarmService.instance.hasExactAlarmPermission() ||
            await AlarmService.instance.requestExactAlarmPermission();
        debugPrint(
          '[NotificationSettings] scheduled alarm exact permission: '
          '$exactAlarmGranted',
        );
        if (!exactAlarmGranted) {
          throw NotificationScheduleUnavailableException(
            title: NotificationUiCopy.diagnosticExactAlarmMissingTitle,
            message: NotificationUiCopy.diagnosticExactAlarmMissing,
          );
        }
        if (fullScreenAlarm) {
          final fullScreenGranted =
              await AlarmService.instance.hasFullScreenIntentPermission() ||
              await AlarmService.instance.requestFullScreenIntentPermission();
          debugPrint(
            '[NotificationSettings] scheduled alarm fullscreen permission: '
            '$fullScreenGranted',
          );
          if (!fullScreenGranted) {
            throw NotificationScheduleUnavailableException(
              title: NotificationUiCopy.diagnosticFullScreenMissingTitle,
              message: NotificationUiCopy.diagnosticFullScreenMissing,
            );
          }
        }
      }
      final scheduled = await service.sendScheduledTest(
        reminderKind: kind,
        fullScreenAlarm: fullScreenAlarm,
        popupInAppOnly: popupInAppOnly,
        popup: scheduler?.popup,
        alarm: scheduler?.alarm,
      );
      if (!mounted) return;
      if (!scheduled) {
        _showScheduleIssueSnack(
          context,
          service.lastScheduleIssue,
          fallback: NotificationUiCopy.scheduledTestFallback,
        );
        await _refreshStatus();
        return;
      }
      final issue = service.lastScheduleIssue;
      if (issue != null && !issue.blocking) {
        _showScheduleIssueSnack(
          context,
          issue,
          fallback: NotificationUiCopy.scheduledTestIssueNonBlocking,
        );
        await _refreshStatus();
        return;
      }
      final label = _diagnosticKindLabel(
        kind,
        fullScreenAlarm: fullScreenAlarm,
        popupInAppOnly: popupInAppOnly,
      );
      final foregroundHint = kind == ReminderKind.popup
          ? popupInAppOnly
                ? NotificationUiCopy.foregroundHintInAppOnly
                : NotificationUiCopy.foregroundHintFallback
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            NotificationUiCopy.formatScheduledDiagnosticSuccess(
              label,
              foregroundHint,
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _refreshStatus();
    } on NotificationPermissionDeniedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(NotificationUiCopy.scheduledPermissionDenied),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    } on NotificationScheduleUnavailableException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(NotificationUiCopy.formatScheduleException(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    } catch (e, st) {
      debugPrint('[NotificationSettings] scheduled test failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(NotificationUiCopy.scheduledTestError),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showScheduleIssueSnack(
    BuildContext context,
    NotificationScheduleIssue? issue, {
    required String fallback,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          NotificationUiCopy.formatScheduleIssue(issue, fallback: fallback),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _diagnosticKindLabel(
    ReminderKind kind, {
    bool fullScreenAlarm = true,
    bool popupInAppOnly = true,
  }) => NotificationUiCopy.diagnosticKindLabel(
    DailyReminderSlot.normalizeKind(kind).name,
    fullScreenAlarm: fullScreenAlarm,
    popupInAppOnly: popupInAppOnly,
  );

  ReminderKind _scheduledTestReminderKind(BuildContext context) {
    final prefs = context.read<PreferencesProvider?>();
    final slots = prefs?.dailyReminderSlots ?? const <DailyReminderSlot>[];
    for (final slot in slots) {
      final kind = DailyReminderSlot.normalizeKind(slot.kind);
      if (slot.enabled && kind != ReminderKind.off) return kind;
    }
    return ReminderKind.push;
  }

  Future<void> _sendStrongTest() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final service = context.read<NotificationService>();
      final notificationGranted = await service.requestPermission();
      await AlarmService.instance.init();
      final exactAlarmGranted =
          await AlarmService.instance.hasExactAlarmPermission() ||
          await AlarmService.instance.requestExactAlarmPermission();
      final fullScreenGranted =
          await AlarmService.instance.hasFullScreenIntentPermission() ||
          await AlarmService.instance.requestFullScreenIntentPermission();
      await AlarmService.instance.showFullScreenTest();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _strongTestMessage(
              notificationGranted: notificationGranted,
              exactAlarmGranted: exactAlarmGranted,
              fullScreenGranted: fullScreenGranted,
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _refreshStatus();
    } on NotificationPermissionDeniedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(NotificationUiCopy.strongTestPermissionDenied),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    } catch (e, st) {
      debugPrint('[NotificationSettings] strong test failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(NotificationUiCopy.strongTestError),
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
      SnackBar(
        content: Text(I18n.tr('preferences.notify.open_settings_failed')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _strongTestMessage({
    required bool notificationGranted,
    required bool exactAlarmGranted,
    required bool fullScreenGranted,
  }) => NotificationUiCopy.formatStrongTestMessage(
    notificationGranted: notificationGranted,
    exactAlarmGranted: exactAlarmGranted,
    fullScreenGranted: fullScreenGranted,
  );

  NotificationChannelStatus? _channelStatus(String channelId) {
    return _channelStatuses?[channelId];
  }

  String _channelStatusLabel(String channelId) {
    final status = _channelStatus(channelId);
    return NotificationUiCopy.channelStatusLabel(
      status?.exists ?? false,
      status?.isBlocked ?? false,
      status?.isSilent ?? false,
      status?.isLowImportance ?? false,
      _channelRequiresSound(channelId),
      _busy,
      _channelStatuses != null,
    );
  }

  Color _channelStatusColor(String channelId, ColorScheme cs) {
    final status = _channelStatus(channelId);
    if (_channelStatuses == null || status == null || !status.exists) {
      return cs.onSurfaceVariant;
    }
    if (status.isBlocked) return cs.error;
    if (_channelRequiresSound(channelId) && status.isSilent) {
      return DesignTokens.defaultWarning;
    }
    if (status.isLowImportance) return DesignTokens.defaultWarning;
    return DesignTokens.defaultSuccess;
  }

  bool _channelRequiresSound(String channelId) =>
      channelId != NativeReminderRingtone.statusChannelId;

  String _channelSubtitle(String base, String channelId) {
    return base;
  }

  Widget _channelStatusTrailing(String channelId, ColorScheme cs) {
    return Row(
      key: ValueKey('notification_channel_status_$channelId'),
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

  Color _accessiblePillForeground(
    Color background,
    Color preferred, {
    required bool isDark,
  }) {
    if (appContrastRatio(background, preferred) >= 4.5) {
      return preferred;
    }
    final target = isDark ? Colors.white : const Color(0xFF111827);
    for (var t = 0.1; t <= 0.85; t += 0.05) {
      final candidate = Color.lerp(preferred, target, t)!;
      if (appContrastRatio(background, candidate) >= 4.5) {
        return candidate;
      }
    }
    return appReadableForeground(background, preferred);
  }

  ButtonStyle _settingsTextActionStyle(
    BuildContext context, {
    Color? color,
    bool plain = false,
    bool filled = false,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final tone = color ?? cs.primary;
    final surfaceStyle = appSurfaceStyleOf(context);
    final cardFill = surfaceStyle?.cardFillColor ?? cs.surface;
    final cardBackground = Color.alphaBlend(
      cardFill,
      theme.scaffoldBackgroundColor,
    );
    final Color effectiveBackground;
    final Color backgroundColor;
    final Color foreground;
    if (plain) {
      effectiveBackground = cardBackground;
      backgroundColor = Colors.transparent;
      foreground = surfaceStyle != null
          ? _accessiblePillForeground(
              effectiveBackground,
              tone,
              isDark: isDark,
            )
          : tone;
    } else if (filled) {
      effectiveBackground = tone;
      backgroundColor = tone;
      final preferredFilled = tone == cs.error ? cs.onError : cs.onPrimary;
      foreground = appReadableForeground(
        effectiveBackground,
        preferredFilled,
      );
    } else {
      effectiveBackground = Color.alphaBlend(
        tone.withValues(alpha: 0.10),
        cardBackground,
      );
      backgroundColor = tone.withValues(alpha: 0.10);
      foreground = _accessiblePillForeground(
        effectiveBackground,
        tone,
        isDark: isDark,
      );
    }
    final hasSurfaceStyle = surfaceStyle != null;
    return TextButton.styleFrom(
      visualDensity: hasSurfaceStyle
          ? VisualDensity.standard
          : VisualDensity.compact,
      tapTargetSize: hasSurfaceStyle
          ? MaterialTapTargetSize.padded
          : MaterialTapTargetSize.shrinkWrap,
      minimumSize: hasSurfaceStyle ? const Size(44, 44) : const Size(0, 30),
      padding: hasSurfaceStyle
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
          : const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      foregroundColor: foreground,
      disabledForegroundColor: cs.onSurfaceVariant.withValues(alpha: 0.44),
      backgroundColor: backgroundColor,
      disabledBackgroundColor: plain
          ? Colors.transparent
          : cs.surfaceContainerHighest.withValues(alpha: 0.18),
      shape: const StadiumBorder(),
      textStyle: appSecondaryMenuItemTextStyle(
        context,
      ).copyWith(color: foreground, fontSize: DesignTokens.fontSizeSm),
    );
  }

  Widget _settingsIconAction(
    BuildContext context, {
    required Key key,
    required String tooltip,
    required VoidCallback? onPressed,
    IconData icon = Icons.refresh,
    bool busy = false,
    bool embedded = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    final hasSurfaceStyle = surfaceStyle != null;
    final button = IconButton(
      key: key,
      tooltip: tooltip,
      constraints: hasSurfaceStyle
          ? const BoxConstraints.tightFor(width: 44, height: 44)
          : const BoxConstraints.tightFor(width: 30, height: 30),
      padding: EdgeInsets.zero,
      visualDensity: hasSurfaceStyle
          ? VisualDensity.standard
          : VisualDensity.compact,
      onPressed: onPressed,
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: hasSurfaceStyle ? 18 : 17),
    );
    if (embedded) return button;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.22),
          width: 0.45,
        ),
      ),
      child: button,
    );
  }

  Widget _settingsActionGroup(BuildContext context, List<Widget> children) {
    final cs = Theme.of(context).colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    final hasSurfaceStyle = surfaceStyle != null;
    return Container(
      height: hasSurfaceStyle ? null : 30,
      constraints: hasSurfaceStyle ? const BoxConstraints(minHeight: 44) : null,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.24),
          width: 0.45,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: children,
      ),
    );
  }

  Widget _settingsActionDivider(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    return Container(
      width: 0.6,
      height: surfaceStyle != null ? 20 : 16,
      color: cs.outlineVariant.withValues(alpha: 0.45),
    );
  }

  String _registeredReminderSummary() {
    var queued = 0;
    var partial = 0;
    var missing = 0;
    var unconfirmed = 0;
    for (final entry in _registeredReminders) {
      switch (_settingsQueueStateFor(entry)) {
        case _RegisteredReminderQueueState.queued:
          queued++;
        case _RegisteredReminderQueueState.partial:
          partial++;
        case _RegisteredReminderQueueState.missing:
          missing++;
        case _RegisteredReminderQueueState.unconfirmed:
          unconfirmed++;
      }
    }
    return NotificationUiCopy.registeredSummary(
      total: _registeredReminders.length,
      queued: queued,
      partial: partial,
      unconfirmed: unconfirmed,
      missing: missing,
      busy: _busy,
      probe: _registeredReminderQueueProbe.name,
    );
  }

  _RegisteredReminderQueueState _settingsQueueStateFor(
    ReminderScheduleSnapshotEntry entry,
  ) {
    if (_registeredReminderQueueProbe !=
        _RegisteredReminderQueueProbe.resolved) {
      return _RegisteredReminderQueueState.unconfirmed;
    }
    if (!_entryHasSystemQueueChannel(entry)) {
      return _RegisteredReminderQueueState.unconfirmed;
    }
    if (_entryAcceptedBySystemQueue(entry, _registeredReminderSystemQueueIds)) {
      return _RegisteredReminderQueueState.queued;
    }
    if (_entryHasAnySystemQueueHit(entry, _registeredReminderSystemQueueIds)) {
      return _RegisteredReminderQueueState.partial;
    }
    return _RegisteredReminderQueueState.missing;
  }

  Future<void> _showRegisteredReminderDetails() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const RegisteredRemindersScreen(),
      ),
    );
    if (!mounted) return;
    // 返回后刷新通知设置页上的“已注册提醒”摘要计数。
    await _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();
    final service = context.watch<NotificationService>();
    final retentionOrigin = _NotificationRetentionOrigin(
      context,
      prefs,
      service,
    );
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final isEn = I18n.current == AppLocale.en;
    const heroChannelIds = [
      NotificationService.channelId,
      AlarmService.channelId,
      NativeReminderRingtone.fallbackChannelId,
      NativeReminderRingtone.statusChannelId,
    ];
    final readyChannelCount = heroChannelIds.where((id) {
      final status = _channelStatus(id);
      if (status == null ||
          !status.exists ||
          status.isBlocked ||
          status.isLowImportance) {
        return false;
      }
      if (_channelRequiresSound(id) && status.isSilent) {
        return false;
      }
      return true;
    }).length;
    final allChannelsReady = service.permissionGranted &&
        _channelStatuses != null &&
        readyChannelCount == heroChannelIds.length;
    final heroStatusLabel = !service.permissionGranted
        ? (isEn ? 'Permission needed' : '需要通知权限')
        : _channelStatuses == null
        ? (isEn ? 'Checking channels' : '检测通道中')
        : allChannelsReady
        ? (isEn ? '4 / 4 channels ready' : '4 / 4 通道就绪')
        : (isEn
              ? '$readyChannelCount / ${heroChannelIds.length} channels ready'
              : '$readyChannelCount / ${heroChannelIds.length} 通道就绪');
    final heroStatusColor = !service.permissionGranted
        ? cs.error
        : allChannelsReady
        ? DesignTokens.defaultSuccess
        : _channelStatuses == null
        ? cs.primary
        : DesignTokens.defaultWarning;
    final isLiquidGlass =
        appSurfaceStyleOf(context) == AppSurfaceStyle.liquidGlass;
    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : routeBackground,
      appBar: AppBar(
        title: Text(NotificationUiCopy.settingsTitle),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 52,
      ),
      body: AppSecondaryControlTheme(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            key: const ValueKey('notification_settings_content'),
            constraints: const BoxConstraints(
              maxWidth: _notificationSettingsContentMaxWidth,
            ),
            child: RefreshIndicator(
              onRefresh: _refreshStatus,
              child: CustomScrollView(
                key: const ValueKey('notification_settings_scroll_view'),
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                slivers: [
                  SliverSafeArea(
                    top: false,
                    bottom: true,
                    sliver: SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                      sliver: SliverList.list(
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
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: heroStatusColor.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      appSurfaceStyleOf(
                                            context,
                                          )?.smallTileRadius ??
                                          DesignTokens.radiusControl,
                                    ),
                                  ),
                                  child: Icon(
                                    service.permissionGranted
                                        ? Icons.notifications_active_outlined
                                        : Icons.notifications_off_outlined,
                                    color: heroStatusColor,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            NotificationUiCopy.settingsTitle,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium
                                                ?.copyWith(
                                                  color: cs.onSurfaceVariant,
                                                  fontWeight: DesignTokens
                                                      .fontWeightRegular,
                                                ),
                                          ),
                                          AppStatusBadge(
                                            label: heroStatusLabel,
                                            color: heroStatusColor,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 7,
                                              vertical: 2,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        NotificationUiCopy.settingsHeroSubtitle,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: cs.onSurface.withValues(
                                                alpha: 0.64,
                                              ),
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
                            title: NotificationUiCopy.sectionSystem,
                            subtitle: service.permissionGranted
                                ? NotificationUiCopy.permissionGrantedFeedback
                                : NotificationUiCopy.permissionDeniedFeedback,
                            showDividers: true,
                            children: [
                              AppSettingsTile(
                                key: const ValueKey(
                                  'notification_permission_tile',
                                ),
                                icon: service.permissionGranted
                                    ? Icons.check_circle_outline
                                    : Icons.notifications_off_outlined,
                                color: service.permissionGranted
                                    ? DesignTokens.defaultSuccess
                                    : cs.error,
                                title: NotificationUiCopy.permissionTileTitle,
                                subtitle:
                                    NotificationUiCopy.permissionTileSubtitle(
                                      service.permissionGranted,
                                    ),
                                trailing: TextButton(
                                  style: _settingsTextActionStyle(
                                    context,
                                    color: service.permissionGranted
                                        ? cs.primary
                                        : cs.error,
                                    filled: !service.permissionGranted,
                                  ),
                                  onPressed: _busy ? null : _requestPermission,
                                  child: Text(
                                    service.permissionGranted
                                        ? NotificationUiCopy.checkAgainAction
                                        : NotificationUiCopy.enableAction,
                                  ),
                                ),
                              ),
                              AppSettingsTile(
                                icon: Icons.settings_outlined,
                                color: cs.primary,
                                title: NotificationUiCopy.channelGeneralTitle,
                                subtitle: _channelSubtitle(
                                  NotificationUiCopy.channelGeneralSubtitle,
                                  NotificationService.channelId,
                                ),
                                trailing: _channelStatusTrailing(
                                  NotificationService.channelId,
                                  cs,
                                ),
                                onTap: () => _openSystemSettings(
                                  NotificationService.channelId,
                                ),
                              ),
                              AppSettingsTile(
                                icon: Icons.alarm_on_outlined,
                                color: DesignTokens.defaultWarning,
                                title: NotificationUiCopy.channelAlarmTitle,
                                subtitle: _channelSubtitle(
                                  NotificationUiCopy.channelAlarmSubtitle,
                                  AlarmService.channelId,
                                ),
                                trailing: _channelStatusTrailing(
                                  AlarmService.channelId,
                                  cs,
                                ),
                                onTap: () =>
                                    _openSystemSettings(AlarmService.channelId),
                              ),
                              AppSettingsTile(
                                icon: Icons.alt_route_outlined,
                                color: DesignTokens.defaultAccent,
                                title: NotificationUiCopy.channelFallbackTitle,
                                subtitle: _channelSubtitle(
                                  NotificationUiCopy.channelFallbackSubtitle,
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
                                color: cs.onSurfaceVariant,
                                title: NotificationUiCopy.channelStatusTitle,
                                subtitle: _channelSubtitle(
                                  NotificationUiCopy.channelStatusSubtitle,
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
                            ],
                          ),
                          const SizedBox(height: 12),
                          AppSettingsSection(
                            title: isEn
                                ? 'Diagnostics & Test Triggers'
                                : '诊断与测试触发',
                            subtitle: isEn
                                ? 'Send instant or delayed tests to verify push, popup, and alarm channels'
                                : '即时或延迟发送测试，验证推送、弹窗与闹钟通道',
                            showDividers: true,
                            children: [
                              AppSettingsTile(
                                icon: Icons.notifications_active_outlined,
                                color: cs.primary,
                                title: NotificationUiCopy.testNowTitle,
                                subtitle: NotificationUiCopy.testNowSubtitle,
                                onTap: _busy ? null : _sendTest,
                              ),
                              AppSettingsTile(
                                icon: Icons.schedule_send_outlined,
                                color: DesignTokens.defaultAccent,
                                title:
                                    NotificationUiCopy.testScheduledPushTitle,
                                subtitle: NotificationUiCopy
                                    .testScheduledPushSubtitle,
                                onTap: _busy ? null : _sendScheduledPushTest,
                              ),
                              AppSettingsTile(
                                icon: Icons.open_in_new_outlined,
                                color: cs.primary,
                                title:
                                    NotificationUiCopy.testScheduledPopupTitle,
                                subtitle: NotificationUiCopy
                                    .testScheduledPopupSubtitle,
                                onTap: _busy ? null : _sendScheduledPopupTest,
                              ),
                              AppSettingsTile(
                                icon: Icons.notification_add_outlined,
                                color: DesignTokens.defaultAccent,
                                title: NotificationUiCopy
                                    .testScheduledPopupFallbackTitle,
                                subtitle: NotificationUiCopy
                                    .testScheduledPopupFallbackSubtitle,
                                onTap: _busy
                                    ? null
                                    : _sendScheduledPopupFallbackTest,
                              ),
                              AppSettingsTile(
                                icon: Icons.alarm_outlined,
                                color: DesignTokens.defaultWarning,
                                title:
                                    NotificationUiCopy.testScheduledAlarmTitle,
                                subtitle: NotificationUiCopy
                                    .testScheduledAlarmSubtitle,
                                onTap: _busy ? null : _sendScheduledAlarmTest,
                              ),
                              AppSettingsTile(
                                icon: Icons.fullscreen_outlined,
                                color: cs.error,
                                title: NotificationUiCopy
                                    .testScheduledFullScreenTitle,
                                subtitle: NotificationUiCopy
                                    .testScheduledFullScreenSubtitle,
                                onTap: _busy
                                    ? null
                                    : _sendScheduledFullScreenAlarmTest,
                              ),
                              AppSettingsTile(
                                icon: Icons.rule_folder_outlined,
                                color: cs.onSurfaceVariant,
                                title: NotificationUiCopy
                                    .testScheduledDefaultTitle,
                                subtitle: NotificationUiCopy
                                    .testScheduledDefaultSubtitle,
                                onTap: _busy ? null : _sendScheduledTest,
                              ),
                              AppSettingsTile(
                                icon: Icons.alarm_on_outlined,
                                color: cs.error,
                                title:
                                    NotificationUiCopy.testStrongRingtoneTitle,
                                subtitle: NotificationUiCopy
                                    .testStrongRingtoneSubtitle,
                                onTap: _busy ? null : _sendStrongTest,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          AppSettingsSection(
                            title: isEn ? 'Pending Queue' : '待触发队列',
                            subtitle: isEn
                                ? 'Inspect queued notifications, exact alarms, and registered reminders'
                                : '查看待发送通知、精确闹钟与已登记提醒队列',
                            showDividers: true,
                            children: [
                              AppSettingsTile(
                                key: const ValueKey(
                                  'notification_pending_push_tile',
                                ),
                                icon: Icons.schedule,
                                color: cs.primary,
                                title: NotificationUiCopy.pendingPushTitle,
                                subtitle:
                                    NotificationUiCopy.pendingPushSubtitle(
                                      _pendingPushCount,
                                    ),
                                trailing: _settingsIconAction(
                                  context,
                                  key: const ValueKey(
                                    'notification_pending_push_refresh_button',
                                  ),
                                  tooltip:
                                      NotificationUiCopy.refreshActionShort,
                                  onPressed: _busy ? null : _refreshStatus,
                                  busy: _busy,
                                ),
                              ),
                              AppSettingsTile(
                                key: const ValueKey(
                                  'notification_pending_alarm_tile',
                                ),
                                icon: Icons.alarm_on_outlined,
                                color: DesignTokens.defaultWarning,
                                title: NotificationUiCopy.pendingAlarmTitle,
                                subtitle:
                                    NotificationUiCopy.pendingAlarmSubtitle(
                                      _pendingAlarmCount,
                                      _exactAlarmGranted == true,
                                    ),
                                trailing: TextButton(
                                  key: const ValueKey(
                                    'notification_pending_alarm_exact_button',
                                  ),
                                  style: _settingsTextActionStyle(
                                    context,
                                    color: cs.primary,
                                  ),
                                  onPressed: _busy
                                      ? null
                                      : _requestExactAlarmPermission,
                                  child: Text(
                                    NotificationUiCopy.exactAlarmButton,
                                  ),
                                ),
                              ),
                              AppSettingsTile(
                                key: const ValueKey(
                                  'notification_registered_reminders_tile',
                                ),
                                icon: Icons.fact_check_outlined,
                                color: DesignTokens.defaultAccent,
                                title:
                                    NotificationUiCopy.registeredRemindersTitle,
                                subtitle: _registeredReminderSummary(),
                                trailing: KeyedSubtree(
                                  key: const ValueKey(
                                    'notification_registered_reminders_actions',
                                  ),
                                  child: _settingsActionGroup(context, [
                                    TextButton(
                                      key: const ValueKey(
                                        'notification_registered_reminders_view_button',
                                      ),
                                      style: _settingsTextActionStyle(
                                        context,
                                        plain: true,
                                      ),
                                      onPressed: _showRegisteredReminderDetails,
                                      child: Text(
                                        NotificationUiCopy.viewAction,
                                      ),
                                    ),
                                    _settingsActionDivider(context),
                                    _settingsIconAction(
                                      context,
                                      key: const ValueKey(
                                        'notification_registered_reminders_refresh_button',
                                      ),
                                      tooltip:
                                          NotificationUiCopy.refreshActionShort,
                                      onPressed: _busy ? null : _refreshStatus,
                                      embedded: true,
                                    ),
                                  ]),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          AppSettingsSection(
                            title: NotificationUiCopy.sectionShortcuts,
                            subtitle:
                                NotificationUiCopy.sectionShortcutsSubtitle,
                            showDividers: true,
                            children: [
                              if (PlatformInfo.isAndroid) ...[
                                AppSettingsTile(
                                  key: const ValueKey(
                                    'notification_quick_add_tile',
                                  ),
                                  icon: Icons.add_alert_outlined,
                                  color: cs.primary,
                                  title: I18n.tr(
                                    'preferences.notification_quick_add.title',
                                  ),
                                  subtitle: I18n.tr(
                                    'preferences.notification_quick_add.subtitle',
                                  ),
                                  trailing: _CompactSettingsSwitch(
                                    key: const ValueKey(
                                      'notification_quick_add_switch',
                                    ),
                                    value: prefs.notificationQuickAdd,
                                    onChanged: _busy
                                        ? null
                                        : (value) =>
                                              _setNotificationStatusBarPreference(
                                                quickAdd: true,
                                                value: value,
                                              ),
                                  ),
                                  onTap: _busy
                                      ? null
                                      : () =>
                                            _setNotificationStatusBarPreference(
                                              quickAdd: true,
                                              value:
                                                  !prefs.notificationQuickAdd,
                                            ),
                                ),
                                AppSettingsTile(
                                  key: const ValueKey(
                                    'notification_today_progress_tile',
                                  ),
                                  icon: Icons.today_outlined,
                                  color: DesignTokens.defaultAccent,
                                  title: I18n.tr(
                                    'preferences.notification_today_progress.title',
                                  ),
                                  subtitle: I18n.tr(
                                    'preferences.notification_today_progress.subtitle',
                                  ),
                                  trailing: _CompactSettingsSwitch(
                                    key: const ValueKey(
                                      'notification_today_progress_switch',
                                    ),
                                    value: prefs.notificationTodayProgress,
                                    onChanged: _busy
                                        ? null
                                        : (value) =>
                                              _setNotificationStatusBarPreference(
                                                quickAdd: false,
                                                value: value,
                                              ),
                                  ),
                                  onTap: _busy
                                      ? null
                                      : () =>
                                            _setNotificationStatusBarPreference(
                                              quickAdd: false,
                                              value: !prefs
                                                  .notificationTodayProgress,
                                            ),
                                ),
                              ] else
                                AppSettingsTile(
                                  icon: Icons.notifications_none_outlined,
                                  color: cs.onSurfaceVariant,
                                  title: I18n.tr(
                                    'preferences.notification_status_bar.title',
                                  ),
                                  subtitle: I18n.tr(
                                    'preferences.notification_status_bar.unsupported',
                                  ),
                                ),
                              _NotificationHistoryEntryTile(
                                historyCount: service.historyCount,
                                unreadCount: service.unreadCount,
                                onOpen: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const NotificationHistoryScreen(
                                          markReadOnOpen: false,
                                        ),
                                  ),
                                ),
                              ),
                              AppSettingsTile(
                                key: const ValueKey(
                                  'notification_history_limit_tile',
                                ),
                                icon: Icons.inventory_2_outlined,
                                color: DesignTokens.defaultAccent,
                                title: NotificationUiCopy.historyRetentionTitle,
                                subtitle:
                                    NotificationUiCopy.historyRetentionSubtitle(
                                      prefs.notificationHistoryLimit,
                                    ),
                                trailing: AppCompactDropdown<int>(
                                  key: const ValueKey(
                                    'notification_history_limit_dropdown',
                                  ),
                                  value: prefs.notificationHistoryLimit,
                                  width:
                                      MediaQuery.textScalerOf(
                                        context,
                                      ).scale(112) +
                                      32,
                                  selectedLabel:
                                      NotificationUiCopy.historyRetentionItem(
                                        prefs.notificationHistoryLimit,
                                      ),
                                  isInteractionAllowed: () =>
                                      mounted &&
                                      !_historyLimitSaving &&
                                      retentionOrigin.isCurrent(context),
                                  isSelectionAllowed: () =>
                                      mounted &&
                                      !_historyLimitSaving &&
                                      retentionOrigin.isCurrent(
                                        context,
                                        checkRoute: false,
                                      ),
                                  items: [
                                    for (final value
                                        in NotificationHistoryPolicy.options)
                                      DropdownMenuItem(
                                        value: value,
                                        child: ValueListenableBuilder<AppLocale>(
                                          valueListenable:
                                              I18n.localeListenable,
                                          builder: (_, _, _) => Text(
                                            NotificationUiCopy.historyRetentionItem(
                                              value,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                  onChanged: _historyLimitSaving
                                      ? null
                                      : (value) {
                                          if (value != null) {
                                            _setHistoryLimit(
                                              value,
                                              retentionOrigin,
                                            );
                                          }
                                        },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          AppSettingsSection(
                            title: I18n.tr(
                              'preferences.section.daily_reminder',
                            ),
                            subtitle: I18n.tr(
                              'preferences.section.daily_reminder.subtitle',
                            ),
                            children: [
                              for (
                                var i = 0;
                                i < prefs.dailyReminderSlots.length;
                                i++
                              )
                                _NotificationReminderSlotTile(
                                  key: ValueKey(
                                    'daily-$_settingsAccountEpoch-$i',
                                  ),
                                  index: i,
                                  slot: prefs.dailyReminderSlots[i],
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _NotificationRingtoneSection(),
                          const SizedBox(height: 12),
                          _QuietHoursSection(
                            key: ValueKey(
                              'quiet-hours-$_settingsAccountEpoch',
                            ),
                          ),
                          const SizedBox(height: 12),
                          _ReportReminderSection(
                            key: ValueKey('reports-$_settingsAccountEpoch'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return _notificationRouteSurface(
      context,
      routeBackground: routeBackground,
      child: scaffold,
    );
  }
}

class _RegisteredReminderDetailRow extends StatelessWidget {
  final ReminderScheduleSnapshotEntry entry;
  final _RegisteredReminderQueueState queueState;
  final VoidCallback? onTap;

  const _RegisteredReminderDetailRow({
    required this.entry,
    required this.queueState,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final typeLabel = _registeredReminderTypeLabel(entry.objectType);
    final systemCount = entry.idCount;
    final title = _registeredReminderDisplayTitle(entry, typeLabel);
    final subtitle = _registeredReminderDisplaySubtitle(entry, typeLabel);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        key: ValueKey('registered_reminder_detail_${entry.objectKey}'),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.22),
            width: 0.4,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppStatusBadge(
                  label: typeLabel,
                  color: _registeredReminderTypeColor(entry.objectType, cs),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              NotificationUiCopy.reminderItemPrefix(title),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.normal,
                                    height: 1.16,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          AppStatusBadge(
                            label: _queueStateLabel(queueState),
                            color: _queueStateColor(queueState, cs),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        NotificationUiCopy.summaryPrefix(subtitle),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.52),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              NotificationUiCopy.rulesRegisteredCount(
                                systemCount,
                              ),
                              softWrap: true,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.66),
                                    height: 1.22,
                                  ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: cs.onSurface.withValues(alpha: 0.45),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _RegisteredReminderFilter {
  current,
  all,
  queued,
  partial,
  missing,
  unconfirmed,
}

enum _RegisteredReminderQueueProbe { loading, resolved, failed }

enum _RegisteredReminderQueueState { queued, partial, missing, unconfirmed }

String _queueStateLabel(_RegisteredReminderQueueState state) {
  return switch (state) {
    _RegisteredReminderQueueState.queued => NotificationUiCopy.filterChipQueued,
    _RegisteredReminderQueueState.partial =>
      NotificationUiCopy.filterChipPartial,
    _RegisteredReminderQueueState.missing =>
      NotificationUiCopy.filterChipMissing,
    _RegisteredReminderQueueState.unconfirmed =>
      NotificationUiCopy.filterChipUnconfirmed,
  };
}

Color _queueStateColor(_RegisteredReminderQueueState state, ColorScheme cs) {
  return switch (state) {
    _RegisteredReminderQueueState.queued => DesignTokens.defaultSuccess,
    _RegisteredReminderQueueState.partial => DesignTokens.defaultWarning,
    _RegisteredReminderQueueState.missing => cs.error,
    _RegisteredReminderQueueState.unconfirmed => cs.onSurfaceVariant,
  };
}

String _queueStateSummary(_RegisteredReminderQueueState state) =>
    NotificationUiCopy.queueStateSummary(state.name);

String _queueStateActionHint(_RegisteredReminderQueueState state) =>
    NotificationUiCopy.queueStateActionHint(state.name);

bool _entryHasSystemQueueChannel(ReminderScheduleSnapshotEntry entry) {
  if (entry.kinds.isEmpty) return true;
  return entry.kinds.contains(ReminderKind.push) ||
      entry.kinds.contains(ReminderKind.alarm);
}

List<Set<int>> _entryAcceptedIdSets(ReminderScheduleSnapshotEntry entry) {
  if (entry.acceptedIdSets.isNotEmpty) return entry.acceptedIdSets;
  if (!_entryHasSystemQueueChannel(entry)) return const <Set<int>>[];
  final ids = entry.ids.where((id) => id != 0).toSet();
  if (ids.isEmpty) return const <Set<int>>[];
  return <Set<int>>[Set<int>.unmodifiable(ids)];
}

bool _entryAcceptedBySystemQueue(
  ReminderScheduleSnapshotEntry entry,
  Set<int> systemQueueIds,
) {
  final acceptedSets = _entryAcceptedIdSets(entry);
  return acceptedSets.any(
    (ids) => ids.isNotEmpty && systemQueueIds.containsAll(ids),
  );
}

bool _entryHasAnySystemQueueHit(
  ReminderScheduleSnapshotEntry entry,
  Set<int> systemQueueIds,
) {
  return entry.ids.any(systemQueueIds.contains) ||
      _entryAcceptedIdSets(
        entry,
      ).expand((ids) => ids).any(systemQueueIds.contains);
}

String _idsPreview(List<int> ids) => NotificationUiCopy.idsPreview(ids);

String _acceptedIdSetsPreview(List<Set<int>> groups) =>
    NotificationUiCopy.acceptedIdSetsPreview(groups);

@immutable
class _RegisteredReminderDetailSnapshot {
  final ReminderScheduleSnapshotEntry entry;
  final _RegisteredReminderQueueState queueState;
  final Set<int> systemQueueIds;
  final _RegisteredReminderQueueProbe probeState;

  const _RegisteredReminderDetailSnapshot({
    required this.entry,
    required this.queueState,
    required this.systemQueueIds,
    required this.probeState,
  });
}

class _RegisteredReminderRemovedDetailSheet extends StatelessWidget {
  const _RegisteredReminderRemovedDetailSheet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Row(
          children: [
            Expanded(
              child: Text(
                NotificationUiCopy.detailSheetRemoved,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.72),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: const ValueKey('registered_reminder_removed_close'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(NotificationUiCopy.closeAction),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegisteredReminderDetailSheet extends StatelessWidget {
  final ReminderScheduleSnapshotEntry entry;
  final _RegisteredReminderQueueState queueState;
  final Set<int> systemQueueIds;
  final _RegisteredReminderQueueProbe probeState;
  final VoidCallback? onOpenObject;
  final VoidCallback? onRefresh;

  const _RegisteredReminderDetailSheet({
    required this.entry,
    required this.queueState,
    required this.systemQueueIds,
    required this.probeState,
    this.onOpenObject,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final typeLabel = _registeredReminderTypeLabel(entry.objectType);
    final title = _registeredReminderDisplayTitle(entry, typeLabel);
    final subtitle = _registeredReminderDisplaySubtitle(entry, typeLabel);
    final matchedIds =
        entry.ids.where(systemQueueIds.contains).toList(growable: false)
          ..sort();
    final missingIds =
        entry.ids
            .where((id) => !systemQueueIds.contains(id))
            .toList(growable: false)
          ..sort();
    final acceptedIdSets = _entryAcceptedIdSets(entry);
    final acceptedBySystemQueue = _entryAcceptedBySystemQueue(
      entry,
      systemQueueIds,
    );
    final canCompareSystemQueue =
        probeState == _RegisteredReminderQueueProbe.resolved &&
        _entryHasSystemQueueChannel(entry);
    final probeLabel = NotificationUiCopy.probeLabel(probeState.name);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                AppStatusBadge(
                  label: typeLabel,
                  color: _registeredReminderTypeColor(entry.objectType, cs),
                ),
                const SizedBox(width: 8),
                AppStatusBadge(
                  label: _queueStateLabel(queueState),
                  color: _queueStateColor(queueState, cs),
                ),
                const Spacer(),
                if (onRefresh != null) ...[
                  IconButton(
                    key: const ValueKey('registered_reminder_detail_refresh'),
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: NotificationUiCopy.refreshActionShort,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    onPressed: onRefresh,
                  ),
                  const SizedBox(width: 4),
                ],
                IconButton(
                  key: const ValueKey('registered_reminder_detail_close'),
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: NotificationUiCopy.closeAction,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.normal,
              ),
            ),
            const SizedBox(height: 10),
            _RegisteredReminderInfoLine(
              label: NotificationUiCopy.detailSheetSummary,
              value: subtitle,
            ),
            _RegisteredReminderInfoLine(
              label: NotificationUiCopy.detailSheetCurrentDiagnostic,
              value: _queueStateSummary(queueState),
            ),
            _RegisteredReminderInfoLine(
              label: NotificationUiCopy.detailSheetRecommendation,
              value: _queueStateActionHint(queueState),
            ),
            _RegisteredReminderInfoLine(
              label: NotificationUiCopy.detailSheetSystemProbe,
              value: probeLabel,
            ),
            if (onOpenObject != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const ValueKey('registered_reminder_open_object'),
                  onPressed: onOpenObject,
                  icon: const Icon(Icons.open_in_new_outlined, size: 18),
                  label: Text(
                    queueState == _RegisteredReminderQueueState.queued
                        ? NotificationUiCopy.openObjectAction
                        : NotificationUiCopy.openObjectAndResaveAction,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            ..._channelDetailLines(
              entry,
              matchedIds: matchedIds,
              missingIds: missingIds,
              acceptedBySystemQueue: acceptedBySystemQueue,
              probeState: probeState,
            ),
            const SizedBox(height: 8),
            _RegisteredReminderTechnicalDetails(
              entry: entry,
              matchedIds: matchedIds,
              missingIds: missingIds,
              acceptedIdSets: acceptedIdSets,
              acceptedBySystemQueue: acceptedBySystemQueue,
              canCompareSystemQueue: canCompareSystemQueue,
            ),
          ],
        ),
      ),
    );
  }
}

class _RegisteredReminderTechnicalDetails extends StatelessWidget {
  final ReminderScheduleSnapshotEntry entry;
  final List<int> matchedIds;
  final List<int> missingIds;
  final List<Set<int>> acceptedIdSets;
  final bool acceptedBySystemQueue;
  final bool canCompareSystemQueue;

  const _RegisteredReminderTechnicalDetails({
    required this.entry,
    required this.matchedIds,
    required this.missingIds,
    required this.acceptedIdSets,
    required this.acceptedBySystemQueue,
    required this.canCompareSystemQueue,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final missingLabel = _technicalMissingIdsLabel(
      missingIds: missingIds,
      acceptedBySystemQueue: acceptedBySystemQueue,
      canCompareSystemQueue: canCompareSystemQueue,
    );
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        title: Text(
          NotificationUiCopy.techDetailsTitle,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.72),
            fontWeight: FontWeight.normal,
          ),
        ),
        children: [
          _RegisteredReminderInfoLine(
            label: NotificationUiCopy.techSourceObject,
            value: '${entry.objectType}:${entry.objectId}',
          ),
          _RegisteredReminderInfoLine(
            label: NotificationUiCopy.techRegisteredIds,
            value: _idsPreview(entry.ids),
          ),
          _RegisteredReminderInfoLine(
            label: NotificationUiCopy.techEvaluationIds,
            value: _acceptedIdSetsPreview(acceptedIdSets),
          ),
          _RegisteredReminderInfoLine(
            label: NotificationUiCopy.techSystemHits,
            value: canCompareSystemQueue
                ? matchedIds.isEmpty
                      ? NotificationUiCopy.detailSheetNone
                      : _idsPreview(matchedIds)
                : NotificationUiCopy.filterChipUnconfirmed,
          ),
          _RegisteredReminderInfoLine(
            label: NotificationUiCopy.techMissingIds,
            value: missingLabel,
          ),
        ],
      ),
    );
  }
}

String _technicalMissingIdsLabel({
  required List<int> missingIds,
  required bool acceptedBySystemQueue,
  required bool canCompareSystemQueue,
}) => NotificationUiCopy.techMissingIdsLabel(
  missingIds: missingIds,
  acceptedBySystemQueue: acceptedBySystemQueue,
  canCompareSystemQueue: canCompareSystemQueue,
);

List<Widget> _channelDetailLines(
  ReminderScheduleSnapshotEntry entry, {
  required List<int> matchedIds,
  required List<int> missingIds,
  required bool acceptedBySystemQueue,
  required _RegisteredReminderQueueProbe probeState,
}) {
  final kinds = entry.kinds.isEmpty
      ? const <ReminderKind>{ReminderKind.push}
      : entry.kinds;
  return [
    if (kinds.contains(ReminderKind.push))
      _RegisteredReminderInfoLine(
        label: NotificationUiCopy.channelStandardNotif,
        value: _systemChannelExplanation(
          matchedIds: matchedIds,
          missingIds: missingIds,
          acceptedBySystemQueue: acceptedBySystemQueue,
          probeState: probeState,
          suffix: NotificationUiCopy.channelPushSuffix,
        ),
      ),
    if (kinds.contains(ReminderKind.popup))
      _RegisteredReminderInfoLine(
        label: NotificationUiCopy.channelPopUp,
        value: NotificationUiCopy.channelPopUpExplanation,
      ),
    if (kinds.contains(ReminderKind.alarm))
      _RegisteredReminderInfoLine(
        label: NotificationUiCopy.channelAlarm,
        value: _systemChannelExplanation(
          matchedIds: matchedIds,
          missingIds: missingIds,
          acceptedBySystemQueue: acceptedBySystemQueue,
          probeState: probeState,
          suffix: NotificationUiCopy.channelAlarmSuffix,
        ),
      ),
    if (kinds.contains(ReminderKind.email))
      _RegisteredReminderInfoLine(
        label: NotificationUiCopy.channelEmail,
        value: NotificationUiCopy.channelEmailExplanation,
      ),
  ];
}

String _systemChannelExplanation({
  required List<int> matchedIds,
  required List<int> missingIds,
  required bool acceptedBySystemQueue,
  required _RegisteredReminderQueueProbe probeState,
  required String suffix,
}) => NotificationUiCopy.systemChannelExplanation(
  matchedIds: matchedIds,
  missingIds: missingIds,
  acceptedBySystemQueue: acceptedBySystemQueue,
  probeStateName: probeState.name,
  suffix: suffix,
);

class _RegisteredReminderInfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _RegisteredReminderInfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.82),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 提醒注册状态独立页：支持按系统待触发状态过滤与分页浏览。
///
/// “系统待触发”表示该提醒的系统通知/闹钟有效编号组仍在待触发列表里；
/// “部分待触发”表示只命中了一部分；“需重新保存”表示调度器登记了但系统列表
/// 一个都查不到；“待确认”表示系统列表读取失败，或只有前台弹出/邮件等
/// 通道不能单靠本机系统队列确认。
class RegisteredRemindersScreen extends StatefulWidget {
  final Future<Set<int>> Function()? pendingQueueLoader;
  final String? initialOpenObjectKey;

  const RegisteredRemindersScreen({
    super.key,
    this.pendingQueueLoader,
    this.initialOpenObjectKey,
  });

  @override
  State<RegisteredRemindersScreen> createState() =>
      _RegisteredRemindersScreenState();
}

class _RegisteredRemindersScreenState extends State<RegisteredRemindersScreen> {
  static const _pageSize = 20;

  bool _loading = true;
  bool _snapshotFailed = false;
  List<ReminderScheduleSnapshotEntry> _entries =
      const <ReminderScheduleSnapshotEntry>[];
  Set<int> _systemQueueIds = <int>{};
  _RegisteredReminderQueueProbe _queueProbe =
      _RegisteredReminderQueueProbe.loading;
  _RegisteredReminderFilter _filter = _RegisteredReminderFilter.current;
  int _page = 0;
  int _loadGeneration = 0;
  int _lastAccountDataGeneration = 0;
  String? _lastAccountKey;
  AuthProvider? _authProvider;
  bool _accountBoundaryPending = false;
  bool _initialDetailOpened = false;
  String? _openDetailObjectKey;
  ValueNotifier<_RegisteredReminderDetailSnapshot?>? _openDetailNotifier;

  @override
  void initState() {
    super.initState();
    _lastAccountDataGeneration = AccountLocalDataCleaner.accountDataGeneration;
    I18n.localeListenable.addListener(_onLocaleChanged);
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _handleAccountGenerationChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = _readAuthProvider(context);
    if (_authProvider == auth && _lastAccountKey != null) return;
    final nextKey = _accountKeyFor(auth?.state);
    final nextGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final changed =
        _lastAccountKey != null &&
        (_lastAccountKey != nextKey ||
            _lastAccountDataGeneration != nextGeneration);
    _authProvider?.removeListener(_handleAccountChanged);
    _authProvider = auth;
    _authProvider?.addListener(_handleAccountChanged);
    _lastAccountKey = nextKey;
    _lastAccountDataGeneration = nextGeneration;
    if (changed) _clearForAccountBoundary();
    if (_accountBoundaryPending && auth != null && _accountIsAvailable) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _handleAccountGenerationChanged,
    );
    _authProvider?.removeListener(_handleAccountChanged);
    _authProvider = null;
    _openDetailObjectKey = null;
    _openDetailNotifier = null;
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  static String _accountKeyFor(AuthState? state) {
    if (state == null) return '';
    return '${state.userId ?? ''}:${state.username ?? ''}:${state.token ?? ''}';
  }

  bool get _accountIsAvailable =>
      _authProvider == null ||
      (!_authProvider!.isAccountTransitionInProgress &&
          !_authProvider!.isLocalAccountDataBlocked);

  bool _isCurrentAccount(int generation, String key) =>
      mounted &&
      _accountIsAvailable &&
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation) &&
      key == _accountKeyFor(_authProvider?.state);

  bool _isCurrentLoad(int loadGeneration, int accountGeneration, String key) =>
      loadGeneration == _loadGeneration &&
      _isCurrentAccount(accountGeneration, key);

  void _handleAccountGenerationChanged() {
    _lastAccountDataGeneration = AccountLocalDataCleaner.accountDataGeneration;
    _clearForAccountBoundary();
  }

  void _handleAccountChanged() {
    final nextKey = _accountKeyFor(_authProvider?.state);
    final nextGeneration = AccountLocalDataCleaner.accountDataGeneration;
    if (nextKey != _lastAccountKey ||
        nextGeneration != _lastAccountDataGeneration) {
      _lastAccountKey = nextKey;
      _lastAccountDataGeneration = nextGeneration;
      _clearForAccountBoundary();
    }
    if (!_accountIsAvailable) {
      if (!_accountBoundaryPending) _clearForAccountBoundary();
      return;
    }
    // A failed transition can settle back to the same account key.
    if (_accountBoundaryPending) unawaited(_load());
  }

  void _clearForAccountBoundary() {
    if (!mounted) return;
    _loadGeneration++;
    _accountBoundaryPending = true;
    setState(() {
      _entries = const <ReminderScheduleSnapshotEntry>[];
      _systemQueueIds = <int>{};
      _page = 0;
      _loading = false;
      _snapshotFailed = false;
      _queueProbe = _RegisteredReminderQueueProbe.loading;
    });
    // Keep ownership until the sheet's finally releases its notifier. Detach
    // the object key so the old sheet cannot bind to the next account's row.
    _openDetailObjectKey = null;
    _openDetailNotifier?.value = null;
  }

  Future<void> _load() async {
    if (!mounted) return;
    if (!_accountIsAvailable) {
      if (!_accountBoundaryPending) _clearForAccountBoundary();
      return;
    }
    _accountBoundaryPending = false;
    final accountKey = _accountKeyFor(_authProvider?.state);
    final generation = ++_loadGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    _lastAccountDataGeneration = accountGeneration;
    setState(() {
      _loading = true;
      _snapshotFailed = false;
      _queueProbe = _RegisteredReminderQueueProbe.loading;
    });
    _refreshOpenDetailSnapshot();
    if (!mounted) return;

    final scheduler = _readReminderScheduler(context);
    List<ReminderScheduleSnapshotEntry> entries = const [];
    var snapshotFailed = false;
    try {
      entries =
          await scheduler?.registeredRemindersSnapshot() ??
          const <ReminderScheduleSnapshotEntry>[];
    } catch (e, st) {
      debugPrint('[RegisteredReminders] load snapshot failed: $e\n$st');
      snapshotFailed = true;
    }

    if (!_isCurrentLoad(generation, accountGeneration, accountKey)) return;

    if (snapshotFailed) {
      setState(() {
        _entries = const <ReminderScheduleSnapshotEntry>[];
        _loading = false;
        _snapshotFailed = true;
        _queueProbe = _RegisteredReminderQueueProbe.failed;
        _page = 0;
      });
      _refreshOpenDetailSnapshot();
      return;
    }

    setState(() {
      _entries = entries;
      _loading = false;
      _snapshotFailed = false;
      _page = 0;
    });
    _refreshOpenDetailSnapshot();
    final initialKey = widget.initialOpenObjectKey;
    if (!_initialDetailOpened &&
        initialKey != null &&
        _openDetailNotifier == null) {
      _initialDetailOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isCurrentLoad(generation, accountGeneration, accountKey) ||
            _openDetailNotifier != null) {
          return;
        }
        final matches = _entries.where(
          (entry) => entry.objectKey == initialKey,
        );
        if (matches.isNotEmpty) unawaited(_showEntryDetails(matches.first));
      });
    }
    unawaited(_resolveSystemQueue(generation, accountGeneration, accountKey));
  }

  Future<void> _resolveSystemQueue(
    int generation,
    int accountGeneration,
    String accountKey,
  ) async {
    if (!_isCurrentLoad(generation, accountGeneration, accountKey)) return;
    final customLoader = widget.pendingQueueLoader;
    if (customLoader != null) {
      try {
        final queue = await customLoader();
        if (!_isCurrentLoad(generation, accountGeneration, accountKey)) return;
        setState(() {
          _systemQueueIds = queue;
          _queueProbe = _RegisteredReminderQueueProbe.resolved;
        });
        _refreshOpenDetailSnapshot();
      } catch (e, st) {
        debugPrint('[RegisteredReminders] custom pending ids failed: $e\n$st');
        if (!_isCurrentLoad(generation, accountGeneration, accountKey)) return;
        setState(() {
          _systemQueueIds = <int>{};
          _queueProbe = _RegisteredReminderQueueProbe.failed;
        });
        _refreshOpenDetailSnapshot();
      }
      return;
    }

    final queue = <int>{};
    var queueResolved = true;
    Future<List<int>> guarded(Future<List<int>> Function() read) async {
      try {
        return await read();
      } catch (e, st) {
        debugPrint('[RegisteredReminders] pending ids read failed: $e\n$st');
        queueResolved = false;
        return const <int>[];
      }
    }

    queue.addAll(
      await guarded(() => LocalNotifications.instance.pendingIdsOrThrow()),
    );
    queue.addAll(await guarded(() => AlarmService.instance.pendingIds()));
    if (!_isCurrentLoad(generation, accountGeneration, accountKey)) return;
    setState(() {
      _systemQueueIds = queue;
      _queueProbe = queueResolved
          ? _RegisteredReminderQueueProbe.resolved
          : _RegisteredReminderQueueProbe.failed;
    });
    _refreshOpenDetailSnapshot();
  }

  _RegisteredReminderQueueState _queueStateFor(
    ReminderScheduleSnapshotEntry entry,
  ) {
    if (_queueProbe != _RegisteredReminderQueueProbe.resolved) {
      return _RegisteredReminderQueueState.unconfirmed;
    }
    if (!_entryHasSystemQueueChannel(entry)) {
      return _RegisteredReminderQueueState.unconfirmed;
    }
    if (_entryAcceptedBySystemQueue(entry, _systemQueueIds)) {
      return _RegisteredReminderQueueState.queued;
    }
    if (_entryHasAnySystemQueueHit(entry, _systemQueueIds)) {
      return _RegisteredReminderQueueState.partial;
    }
    return _RegisteredReminderQueueState.missing;
  }

  List<ReminderScheduleSnapshotEntry> get _filtered {
    switch (_filter) {
      case _RegisteredReminderFilter.current:
        return _entries
            .where(
              (entry) =>
                  _queueStateFor(entry) !=
                  _RegisteredReminderQueueState.missing,
            )
            .toList(growable: false);
      case _RegisteredReminderFilter.all:
        return _entries;
      case _RegisteredReminderFilter.queued:
        return _entries
            .where(
              (entry) =>
                  _queueStateFor(entry) == _RegisteredReminderQueueState.queued,
            )
            .toList(growable: false);
      case _RegisteredReminderFilter.partial:
        return _entries
            .where(
              (entry) =>
                  _queueStateFor(entry) ==
                  _RegisteredReminderQueueState.partial,
            )
            .toList(growable: false);
      case _RegisteredReminderFilter.missing:
        return _entries
            .where(
              (entry) =>
                  _queueStateFor(entry) ==
                  _RegisteredReminderQueueState.missing,
            )
            .toList(growable: false);
      case _RegisteredReminderFilter.unconfirmed:
        return _entries
            .where(
              (entry) =>
                  _queueStateFor(entry) ==
                  _RegisteredReminderQueueState.unconfirmed,
            )
            .toList(growable: false);
    }
  }

  void _setFilter(_RegisteredReminderFilter filter) {
    if (_filter == filter) return;
    setState(() {
      _filter = filter;
      _page = 0;
    });
  }

  Future<void> _showEntryDetails(ReminderScheduleSnapshotEntry entry) async {
    if (!mounted ||
        !_accountIsAvailable ||
        _accountBoundaryPending ||
        _openDetailNotifier != null) {
      return;
    }
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final accountKey = _accountKeyFor(_authProvider?.state);
    final objectKey = entry.objectKey;
    final notifier = ValueNotifier<_RegisteredReminderDetailSnapshot?>(
      _detailSnapshotFor(objectKey, fallback: entry),
    );
    _openDetailObjectKey = objectKey;
    _openDetailNotifier = notifier;
    ReminderScheduleSnapshotEntry? targetToOpen;
    try {
      targetToOpen = await showModalBottomSheet<ReminderScheduleSnapshotEntry>(
        context: context,
        isScrollControlled: true,
        showDragHandle: false,
        constraints: const BoxConstraints(maxWidth: 640),
        builder: (sheetContext) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, _, _) =>
              ValueListenableBuilder<_RegisteredReminderDetailSnapshot?>(
                valueListenable: notifier,
                builder: (context, snapshot, _) {
                  if (snapshot == null) {
                    return const _RegisteredReminderRemovedDetailSheet();
                  }
                  return _RegisteredReminderDetailSheet(
                    entry: snapshot.entry,
                    queueState: snapshot.queueState,
                    systemQueueIds: snapshot.systemQueueIds,
                    probeState: snapshot.probeState,
                    onRefresh: _loading ? null : _load,
                    onOpenObject: _canOpenReminderObject(snapshot.entry)
                        ? () => Navigator.of(sheetContext).pop(snapshot.entry)
                        : null,
                  );
                },
              ),
        ),
      );
    } finally {
      if (identical(_openDetailNotifier, notifier)) {
        _openDetailObjectKey = null;
        _openDetailNotifier = null;
      }
      notifier.dispose();
    }

    if (targetToOpen != null &&
        _isCurrentAccount(accountGeneration, accountKey) &&
        !_accountBoundaryPending) {
      await _openReminderObject(targetToOpen);
    }
  }

  bool _canOpenReminderObject(ReminderScheduleSnapshotEntry entry) {
    return _detailKindForReminderObject(entry.objectType) != null;
  }

  Future<void> _openReminderObject(ReminderScheduleSnapshotEntry entry) async {
    final kind = _detailKindForReminderObject(entry.objectType);
    if (kind == null ||
        !mounted ||
        !_accountIsAvailable ||
        _accountBoundaryPending) {
      return;
    }
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final accountKey = _accountKeyFor(_authProvider?.state);
    await TodayDetailRouter.open(context, kind, id: entry.objectId);
    if (!_isCurrentAccount(accountGeneration, accountKey)) return;
    await _load();
  }

  _RegisteredReminderDetailSnapshot? _detailSnapshotFor(
    String objectKey, {
    ReminderScheduleSnapshotEntry? fallback,
  }) {
    ReminderScheduleSnapshotEntry? current;
    for (final entry in _entries) {
      if (entry.objectKey == objectKey) {
        current = entry;
        break;
      }
    }
    if (current == null && _loading) {
      current = fallback;
    }
    if (current == null) return null;
    return _RegisteredReminderDetailSnapshot(
      entry: current,
      queueState: _queueStateFor(current),
      systemQueueIds: Set<int>.unmodifiable(_systemQueueIds),
      probeState: _queueProbe,
    );
  }

  void _refreshOpenDetailSnapshot() {
    if (!mounted) return;
    final objectKey = _openDetailObjectKey;
    final notifier = _openDetailNotifier;
    if (objectKey == null || notifier == null) return;
    notifier.value = _detailSnapshotFor(
      objectKey,
      fallback: notifier.value?.entry,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final isLiquidGlass =
        appSurfaceStyleOf(context) == AppSurfaceStyle.liquidGlass;
    final filtered = _filtered;
    final currentCount = _entries
        .where(
          (entry) =>
              _queueStateFor(entry) != _RegisteredReminderQueueState.missing,
        )
        .length;
    final queuedCount = _entries
        .where(
          (entry) =>
              _queueStateFor(entry) == _RegisteredReminderQueueState.queued,
        )
        .length;
    final partialCount = _entries
        .where(
          (entry) =>
              _queueStateFor(entry) == _RegisteredReminderQueueState.partial,
        )
        .length;
    final missingCount = _entries
        .where(
          (entry) =>
              _queueStateFor(entry) == _RegisteredReminderQueueState.missing,
        )
        .length;
    final unconfirmedCount = _entries
        .where(
          (entry) =>
              _queueStateFor(entry) ==
              _RegisteredReminderQueueState.unconfirmed,
        )
        .length;

    final totalPages = filtered.isEmpty
        ? 1
        : ((filtered.length - 1) ~/ _pageSize) + 1;
    final currentPage = _page.clamp(0, totalPages - 1).toInt();
    if (currentPage != _page) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _page = currentPage);
      });
    }
    final pageStart = currentPage * _pageSize;
    final pageEnd = (pageStart + _pageSize).clamp(0, filtered.length).toInt();
    final visible = filtered.isEmpty
        ? const <ReminderScheduleSnapshotEntry>[]
        : filtered.sublist(pageStart, pageEnd);

    final title = NotificationUiCopy.registeredRemindersTitle;
    final titleStyle = appSecondaryRouteTitleTextStyle(context);
    final titlePainter =
        TextPainter(
          text: TextSpan(text: title, style: titleStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
        )..layout(
          maxWidth:
              (MediaQuery.sizeOf(context).width -
                      32 -
                      48 -
                      (ModalRoute.of(context)?.canPop == true ? 56 : 0))
                  .clamp(1.0, double.infinity),
        );
    final titleLines = titlePainter.computeLineMetrics().length;
    final toolbarHeight = (titlePainter.height + 16).clamp(
      52.0,
      double.infinity,
    );
    titlePainter.dispose();

    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : routeBackground,
      appBar: AppBar(
        title: Text(title, maxLines: titleLines, softWrap: true),
        titleTextStyle: titleStyle,
        titleSpacing: 16,
        backgroundColor: routeBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: toolbarHeight,
        actions: [
          IconButton(
            key: const ValueKey('registered_reminders_refresh'),
            tooltip: NotificationUiCopy.refreshActionShort,
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: CustomScrollView(
                    key: const ValueKey('registered_reminders_scroll_view'),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _filterChip(
                                NotificationUiCopy.filterAll,
                                _RegisteredReminderFilter.all,
                                _entries.length,
                              ),
                              _filterChip(
                                NotificationUiCopy.filterChipCurrent,
                                _RegisteredReminderFilter.current,
                                currentCount,
                              ),
                              _filterChip(
                                NotificationUiCopy.filterChipQueued,
                                _RegisteredReminderFilter.queued,
                                queuedCount,
                              ),
                              _filterChip(
                                NotificationUiCopy.filterChipPartial,
                                _RegisteredReminderFilter.partial,
                                partialCount,
                              ),
                              _filterChip(
                                NotificationUiCopy.filterChipMissing,
                                _RegisteredReminderFilter.missing,
                                missingCount,
                              ),
                              _filterChip(
                                NotificationUiCopy.filterChipUnconfirmed,
                                _RegisteredReminderFilter.unconfirmed,
                                unconfirmedCount,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!_snapshotFailed &&
                          (_queueProbe !=
                                  _RegisteredReminderQueueProbe.resolved ||
                              partialCount > 0 ||
                              missingCount > 0))
                        SliverToBoxAdapter(
                          child: _RegisteredReminderProbeBanner(
                            probe: _queueProbe,
                            partialCount: partialCount,
                            missingCount: missingCount,
                            onRefresh: _loading ? null : _load,
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _statusHint(missingCount: missingCount),
                              key: const ValueKey(
                                'registered_reminders_status_hint',
                              ),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ),
                        ),
                      ),
                      if (_snapshotFailed || filtered.isEmpty)
                        SliverLayoutBuilder(
                          builder: (context, constraints) => SliverToBoxAdapter(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.remainingPaintExtent
                                    .clamp(0.0, double.infinity),
                              ),
                              child: _snapshotFailed
                                  ? EmptyState(
                                      icon: Icons.sync_problem_outlined,
                                      message: NotificationUiCopy
                                          .snapshotFailedMessage,
                                      actionLabel:
                                          NotificationUiCopy.retryAction,
                                      onAction: _load,
                                    )
                                  : EmptyState(
                                      icon: Icons.fact_check_outlined,
                                      message: _emptyMessage(
                                        missingCount: missingCount,
                                      ),
                                      actionLabel:
                                          (_filter ==
                                                  _RegisteredReminderFilter
                                                      .current &&
                                              missingCount > 0)
                                          ? NotificationUiCopy.actionViewMissing
                                          : null,
                                      onAction:
                                          (_filter ==
                                                  _RegisteredReminderFilter
                                                      .current &&
                                              missingCount > 0)
                                          ? () => _setFilter(
                                              _RegisteredReminderFilter.missing,
                                            )
                                          : null,
                                    ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          sliver: SliverList.builder(
                            key: const ValueKey('registered_reminders_list'),
                            itemCount: visible.length,
                            itemBuilder: (context, index) {
                              final entry = visible[index];
                              final state = _queueStateFor(entry);
                              return _RegisteredReminderDetailRow(
                                entry: entry,
                                queueState: state,
                                onTap: () => _showEntryDetails(entry),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                if (filtered.length > _pageSize)
                  _Pager(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    rangeStart: pageStart + 1,
                    rangeEnd: pageEnd,
                    pageSize: _pageSize,
                    total: filtered.length,
                    onPrev: currentPage <= 0
                        ? null
                        : () => setState(() => _page = currentPage - 1),
                    onNext: currentPage >= totalPages - 1
                        ? null
                        : () => setState(() => _page = currentPage + 1),
                  ),
              ],
            ),
    );
    return _notificationRouteSurface(
      context,
      routeBackground: routeBackground,
      child: scaffold,
    );
  }

  Widget _filterChip(
    String label,
    _RegisteredReminderFilter filter,
    int count,
  ) {
    return ChoiceChip(
      key: ValueKey('registered_reminders_filter_${filter.name}'),
      label: Text('$label · $count'),
      selected: _filter == filter,
      onSelected: (_) => _setFilter(filter),
    );
  }

  String _statusHint({required int missingCount}) =>
      NotificationUiCopy.registeredStatusHint(
        filterName: _filter.name,
        missingCount: missingCount,
        accountBoundaryPending: _accountBoundaryPending,
        accountIsAvailable: _accountIsAvailable,
        snapshotFailed: _snapshotFailed,
      );

  String _emptyMessage({required int missingCount}) =>
      NotificationUiCopy.registeredEmptyMessage(
        filterName: _filter.name,
        missingCount: missingCount,
      );
}

class _RegisteredReminderProbeBanner extends StatelessWidget {
  final _RegisteredReminderQueueProbe probe;
  final int partialCount;
  final int missingCount;
  final VoidCallback? onRefresh;

  const _RegisteredReminderProbeBanner({
    required this.probe,
    required this.partialCount,
    required this.missingCount,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isFailed = probe == _RegisteredReminderQueueProbe.failed;
    final isLoading = probe == _RegisteredReminderQueueProbe.loading;
    final hasBroken = partialCount > 0 || missingCount > 0;
    final background = isFailed || hasBroken
        ? cs.errorContainer.withValues(alpha: 0.58)
        : cs.primaryContainer.withValues(alpha: 0.5);
    final foreground = isFailed || hasBroken
        ? cs.onErrorContainer
        : cs.onPrimaryContainer;
    final icon = isFailed || hasBroken
        ? Icons.warning_amber_rounded
        : Icons.hourglass_top_outlined;
    final message = NotificationUiCopy.probeBannerMessage(
      isFailed: isFailed,
      isLoading: isLoading,
      partialCount: partialCount,
      missingCount: missingCount,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: DecoratedBox(
        key: const ValueKey('registered_reminders_queue_banner'),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: foreground.withValues(alpha: 0.16),
            width: 0.6,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: foreground,
                        height: 1.32,
                      ),
                    ),
                  ),
                  if (isFailed)
                    TextButton.icon(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(NotificationUiCopy.retryAction),
                      style: TextButton.styleFrom(
                        foregroundColor: foreground,
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
              if (isLoading) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: 0.48,
                    child: SizedBox(
                      height: 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: foreground.withValues(alpha: 0.38),
                          borderRadius: BorderRadius.circular(
                            DesignTokens.radiusPill,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final int rangeStart;
  final int rangeEnd;
  final int pageSize;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _Pager({
    required this.currentPage,
    required this.totalPages,
    required this.rangeStart,
    required this.rangeEnd,
    required this.pageSize,
    required this.total,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              NotificationUiCopy.pagerFormat(
                pageSize: pageSize,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                total: total,
                currentPage: currentPage + 1,
                totalPages: totalPages,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.6),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const ValueKey('registered_reminders_prev'),
                tooltip: NotificationUiCopy.pagerPrevTooltip,
                constraints: const BoxConstraints.tightFor(
                  width: 38,
                  height: 38,
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                key: const ValueKey('registered_reminders_next'),
                tooltip: NotificationUiCopy.pagerNextTooltip,
                constraints: const BoxConstraints.tightFor(
                  width: 38,
                  height: 38,
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NotificationHistoryEntryTile extends StatelessWidget {
  final int historyCount;
  final int unreadCount;
  final VoidCallback onOpen;

  const _NotificationHistoryEntryTile({
    required this.historyCount,
    required this.unreadCount,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    final cardFill = surfaceStyle?.cardFillColor ?? cs.surface;
    final cardBackground = Color.alphaBlend(
      cardFill,
      theme.scaffoldBackgroundColor,
    );
    final foreground = surfaceStyle != null
        ? appReadableForeground(cardBackground, cs.primary)
        : null;
    final titleStyle = appSecondaryMenuItemTextStyle(
      context,
    ).copyWith(color: cs.onSurface, fontWeight: DesignTokens.fontWeightRegular);
    final subtitleStyle = appSecondaryControlLabelStyle(context).copyWith(
      color: cs.onSurface.withValues(alpha: 0.62),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('notification_history_entry_tile'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.history_outlined,
                  color: cs.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      NotificationUiCopy.historyEntryTitle,
                      key: const ValueKey('notification_history_entry_title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      NotificationUiCopy.historyEntrySubtitle(
                        historyCount,
                        unreadCount,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subtitleStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const ValueKey('notification_history_entry_view_button'),
                style: TextButton.styleFrom(
                  visualDensity: surfaceStyle != null
                      ? VisualDensity.standard
                      : VisualDensity.compact,
                  tapTargetSize: surfaceStyle != null
                      ? MaterialTapTargetSize.padded
                      : MaterialTapTargetSize.shrinkWrap,
                  minimumSize: surfaceStyle != null
                      ? const Size(44, 44)
                      : const Size(0, 30),
                  padding: surfaceStyle != null
                      ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                      : const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  foregroundColor: foreground,
                  textStyle: surfaceStyle != null
                      ? appSecondaryMenuItemTextStyle(
                          context,
                        ).copyWith(color: foreground)
                      : appSecondaryMenuItemTextStyle(context),
                ),
                onPressed: onOpen,
                child: Text(NotificationUiCopy.viewAction),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsExpansionHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget trailing;
  final Key? iconKey;
  final Key? titleKey;
  final Key? subtitleKey;

  const _SettingsExpansionHeader({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.iconKey,
    this.titleKey,
    this.subtitleKey,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              key: iconKey,
              width: 34,
              height: 34,
              child: Center(child: Icon(icon, color: color, size: 22)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    key: titleKey,
                    style: appSecondaryMenuItemTextStyle(context).copyWith(
                      color: cs.onSurface,
                      fontWeight: DesignTokens.fontWeightRegular,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    key: subtitleKey,
                    style: appSecondaryControlLabelStyle(
                      context,
                    ).copyWith(color: cs.onSurface.withValues(alpha: 0.62)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 40,
              child: Align(alignment: Alignment.centerRight, child: trailing),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationReminderSlotTile extends StatefulWidget {
  final int index;
  final DailyReminderSlot slot;

  const _NotificationReminderSlotTile({
    super.key,
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
    final account = _NotificationAccountGuard(context);
    if (!context.mounted || !account.isCurrent) {
      account.dispose();
      return;
    }
    setState(() => _saving = true);
    try {
      final slotChanged = !_sameSlot(slot, next);
      final needsReminderCheck =
          next.enabled &&
          (!slot.enabled ||
              slot.hour != next.hour ||
              slot.minute != next.minute ||
              slot.kind != next.kind ||
              !_sameDays(slot.repeatDays, next.repeatDays));
      if (needsReminderCheck) {
        final ready = await _ensureReminderSlotReady(context, next);
        if (!context.mounted || !account.isCurrent) return;
        if (!ready) return;
      }
      await context.read<PreferencesProvider>().setDailyReminderSlot(
        index,
        next,
      );
      if (!context.mounted || !account.isCurrent || !slotChanged) return;
      await _syncReminderSlotAfterSave(context);
    } catch (e, st) {
      debugPrint('[NotificationSettings] daily settings save failed: $e\n$st');
      if (context.mounted && account.isCurrent) {
        _showSlotSaveError(context, NotificationUiCopy.dailySaveFailed);
      }
    } finally {
      account.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _sameSlot(DailyReminderSlot a, DailyReminderSlot b) {
    return a.enabled == b.enabled &&
        a.kind == b.kind &&
        a.hour == b.hour &&
        a.minute == b.minute &&
        a.includeTodayTasks == b.includeTodayTasks &&
        a.includeTomorrowPlan == b.includeTomorrowPlan &&
        a.includeOverdue == b.includeOverdue &&
        a.pauseHolidays == b.pauseHolidays &&
        _sameDays(a.repeatDays, b.repeatDays);
  }

  Future<void> _syncReminderSlotAfterSave(BuildContext context) async {
    final account = _NotificationAccountGuard(context);
    try {
      if (!context.mounted || !account.isCurrent) return;
      final sync = context.read<DailyDigestReminderSync?>();
      if (sync == null) return;

      final notif = context.read<NotificationService?>();
      notif?.clearScheduleIssue();
      late final DailyDigestReminderResult result;
      try {
        result = await sync.registerImmediately();
      } on NotificationScheduleUnavailableException catch (e) {
        if (!context.mounted || !account.isCurrent) return;
        _showSlotSaveError(
          context,
          NotificationUiCopy.formatScheduleException(e),
        );
        return;
      } catch (e, st) {
        debugPrint(
          '[NotificationSettings] daily reminder sync after save failed: $e\n$st',
        );
        if (!context.mounted || !account.isCurrent) return;
        _showSlotSaveError(context, NotificationUiCopy.dailyRegistrationFailed);
        return;
      }

      if (!context.mounted || !account.isCurrent) return;
      final issue = result.issueForSlot(index);
      if (issue == null) return;
      _showSlotSaveError(
        context,
        NotificationUiCopy.dailyRegistrationIssue(issue),
      );
    } finally {
      account.dispose();
    }
  }

  Future<bool> _ensureReminderSlotReady(
    BuildContext context,
    DailyReminderSlot next,
  ) async {
    final account = _NotificationAccountGuard(context);
    try {
      if (!context.mounted || !account.isCurrent) return false;
      final kind = DailyReminderSlot.normalizeKind(next.kind);
      if (!next.enabled || kind == ReminderKind.off) return true;

      if (kind == ReminderKind.alarm) {
        try {
          await AlarmService.instance.init();
          final exactAlarmGranted =
              await AlarmService.instance.hasExactAlarmPermission() ||
              await AlarmService.instance.requestExactAlarmPermission();
          if (!context.mounted || !account.isCurrent) return false;
          if (!exactAlarmGranted) {
            _showSlotSaveError(
              context,
              NotificationUiCopy.dailyExactAlarmMissing,
            );
            return false;
          }

          final fullScreenGranted =
              await AlarmService.instance.hasFullScreenIntentPermission() ||
              await AlarmService.instance.requestFullScreenIntentPermission();
          if (!context.mounted || !account.isCurrent) return false;
          if (!fullScreenGranted) {
            _showSlotSaveError(
              context,
              NotificationUiCopy.dailyFullScreenMissing,
            );
            return false;
          }
          return true;
        } catch (e, st) {
          debugPrint(
            '[NotificationSettings] daily reminder alarm readiness failed: $e\n$st',
          );
          if (context.mounted && account.isCurrent) {
            _showSlotSaveError(
              context,
              NotificationUiCopy.dailyAlarmPreparationFailed,
            );
          }
          return false;
        }
      }

      final notif = context.read<NotificationService?>();
      final ready =
          await notif?.ensureReadyForReminder(
            scheduledTime: _nextSlotTrigger(next),
            issueTitle: I18n.tr('preferences.daily_reminder.register_failed'),
            relatedId: 'daily_reminder_$index',
          ) ??
          true;
      if (!context.mounted || !account.isCurrent) return false;
      if (!ready) {
        final issue = notif?.lastScheduleIssue;
        _showSlotSaveError(
          context,
          NotificationUiCopy.formatScheduleIssue(
            issue,
            fallback: I18n.tr('preferences.daily_reminder.not_ready'),
          ),
        );
        return false;
      }
      return true;
    } finally {
      account.dispose();
    }
  }

  void _showSlotSaveError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
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
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            collapsedShape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            initiallyExpanded: index == 0,
            tilePadding: EdgeInsets.zero,
            showTrailingIcon: false,
            title: _SettingsExpansionHeader(
              key: ValueKey('daily_reminder_slot_${index}_header'),
              iconKey: ValueKey('daily_reminder_slot_${index}_header_icon'),
              titleKey: ValueKey('daily_reminder_slot_${index}_header_title'),
              subtitleKey: ValueKey(
                'daily_reminder_slot_${index}_header_subtitle',
              ),
              icon: Icons.notifications_active_outlined,
              color: cs.primary,
              title: _title,
              subtitle: slot.enabled
                  ? '${_kindLabel(slot.kind)} · $_time · ${_repeatDaysLabel(slot.repeatDays)} · ${_taskScopeText(slot)}'
                  : '${I18n.tr('preferences.daily_reminder.disabled')} · $_time',
              trailing: _CompactSettingsSwitch(
                key: ValueKey('daily_reminder_slot_${index}_enabled_switch'),
                value: slot.enabled,
                onChanged: _saving
                    ? null
                    : (value) => _save(context, slot.copyWith(enabled: value)),
              ),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            children: [
              _ReminderKindSettingsTile(
                value: slot.kind,
                subtitle: _kindDescription(slot.kind),
                enabled: !_saving,
                onChanged: (kind) => _save(
                  context,
                  slot.copyWith(enabled: kind != ReminderKind.off, kind: kind),
                ),
              ),
              const SizedBox(height: 6),
              AppSettingsTile(
                key: ValueKey('daily_reminder_slot_${index}_time_tile'),
                icon: Icons.schedule,
                color: DesignTokens.defaultWarning,
                title: I18n.tr('preferences.daily_reminder.time'),
                subtitle: I18n.tr('preferences.daily_reminder.time.subtitle'),
                trailing: TextButton(
                  key: ValueKey('daily_reminder_slot_${index}_time_button'),
                  onPressed: _saving
                      ? null
                      : () async {
                          final account = _NotificationAccountGuard(context);
                          try {
                            if (!context.mounted || !account.isCurrent) return;
                            final picked = await AppTimePicker.show(
                              context,
                              initialTime: TimeOfDay(
                                hour: slot.hour,
                                minute: slot.minute,
                              ),
                              titleKey:
                                  'preferences.daily_reminder.${index + 1}.time',
                              subtitleKey:
                                  'preferences.daily_reminder.time_picker.subtitle',
                            );
                            if (picked == null ||
                                !context.mounted ||
                                !account.isCurrent) {
                              return;
                            }
                            await _save(
                              context,
                              slot.copyWith(
                                hour: picked.hour,
                                minute: picked.minute,
                              ),
                            );
                          } finally {
                            account.dispose();
                          }
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
                    slot.copyWith(
                      includeTomorrowPlan: !slot.includeTomorrowPlan,
                    ),
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
                    _compactFilterChip(
                      context,
                      key: ValueKey(
                        'daily_reminder_slot_${index}_weekday_$day',
                      ),
                      label: _weekdayLabel(day),
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
                              _save(
                                context,
                                slot.copyWith(repeatDays: nextDays),
                              );
                            },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scopeChip(
    BuildContext context,
    String label,
    bool selected,
    DailyReminderSlot next,
  ) {
    return _compactFilterChip(
      context,
      label: label,
      selected: selected,
      onSelected: _saving ? null : (_) => _save(context, next),
    );
  }
}

class _ReminderKindSelector extends StatelessWidget {
  final ReminderKind value;
  final bool enabled;
  final ValueChanged<ReminderKind> onChanged;
  static const _options = [
    _ReminderKindOptionSpec(value: ReminderKind.push),
    _ReminderKindOptionSpec(value: ReminderKind.popup),
    _ReminderKindOptionSpec(value: ReminderKind.alarm),
    _ReminderKindOptionSpec(value: ReminderKind.off),
  ];

  const _ReminderKindSelector({
    required this.value,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = DailyReminderSlot.normalizeKind(value);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 64;
        final gap = maxWidth < 340 ? 4.0 : 6.0;
        final theme = Theme.of(context);
        final textScaler = MediaQuery.textScalerOf(context);
        final textDirection = Directionality.of(context);
        final labelStyle =
            theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.normal,
            ) ??
            const TextStyle(fontWeight: FontWeight.normal);

        double measureLabelWidth(String text) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: labelStyle),
            textDirection: textDirection,
            textScaler: textScaler,
            locale: Localizations.maybeLocaleOf(context),
            maxLines: 1,
          );
          try {
            painter.layout();
            return painter.width;
          } finally {
            painter.dispose();
          }
        }

        final optionLabels = [
          for (final option in _options) _kindLabel(option.value),
        ];
        const horizontalPaddingWithBuffer = 10.0;
        final optionMinWidths = [
          for (final label in optionLabels)
            (() {
              final w = measureLabelWidth(label) + horizontalPaddingWithBuffer;
              return w > 44.0 ? w : 44.0;
            })(),
        ];
        final maxOptionMinWidth = optionMinWidths.reduce(
          (curr, next) => curr > next ? curr : next,
        );

        final col4Available = (maxWidth - (3 * gap)) / 4;
        final col2Available = (maxWidth - gap) / 2;

        final int columnCount;
        if (col4Available >= maxOptionMinWidth) {
          columnCount = 4;
        } else if (col2Available >= maxOptionMinWidth) {
          columnCount = 2;
        } else {
          columnCount = 1;
        }

        Widget buildOption(int index) {
          final option = _options[index];
          return _ReminderKindOptionButton(
            key: ValueKey('daily_reminder_kind_${option.value.name}'),
            label: optionLabels[index],
            selected: selected == option.value,
            enabled: enabled,
            onTap: () => onChanged(option.value),
          );
        }

        final Widget content;
        if (columnCount == 4) {
          content = IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _options.length; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  Expanded(child: buildOption(i)),
                ],
              ],
            ),
          );
        } else if (columnCount == 2) {
          content = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: buildOption(0)),
                    SizedBox(width: gap),
                    Expanded(child: buildOption(1)),
                  ],
                ),
              ),
              SizedBox(height: gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: buildOption(2)),
                    SizedBox(width: gap),
                    Expanded(child: buildOption(3)),
                  ],
                ),
              ),
            ],
          );
        } else {
          content = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _options.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                buildOption(i),
              ],
            ],
          );
        }

        return KeyedSubtree(
          key: const ValueKey('daily_reminder_kind_selector_row'),
          child: content,
        );
      },
    );
  }
}

class _ReminderKindOptionSpec {
  final ReminderKind value;

  const _ReminderKindOptionSpec({required this.value});
}

class _ReminderKindSettingsTile extends StatelessWidget {
  final ReminderKind value;
  final String subtitle;
  final bool enabled;
  final ValueChanged<ReminderKind> onChanged;

  const _ReminderKindSettingsTile({
    required this.value,
    required this.subtitle,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: DesignTokens.defaultAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  color: DesignTokens.defaultAccent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      I18n.tr('preferences.daily_reminder.kind.title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: appSecondaryMenuItemTextStyle(context).copyWith(
                        color: cs.onSurface,
                        fontWeight: DesignTokens.fontWeightRegular,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: appSecondaryControlLabelStyle(
                        context,
                      ).copyWith(color: cs.onSurface.withValues(alpha: 0.62)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ReminderKindSelector(
            value: value,
            enabled: enabled,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ReminderKindOptionButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ReminderKindOptionButton({
    super.key,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    final cardFill = surfaceStyle?.cardFillColor ?? cs.surface;
    final cardBackground = Color.alphaBlend(
      cardFill,
      theme.scaffoldBackgroundColor,
    );
    final buttonFill = selected
        ? cs.primary.withValues(alpha: 0.12)
        : cs.surface;
    final effectiveBackground = Color.alphaBlend(buttonFill, cardBackground);
    final preferredForeground = _reminderKindForeground(cs, selected, enabled);
    final foreground = surfaceStyle != null
        ? appReadableForeground(effectiveBackground, preferredForeground)
        : preferredForeground;

    final borderColor = selected
        ? cs.primary.withValues(alpha: 0.42)
        : cs.outlineVariant.withValues(alpha: 0.45);

    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: foreground,
      fontWeight: FontWeight.normal,
    );

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: Material(
        color: buttonFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: borderColor, width: 0.45),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Center(
                child: Text(
                  label,
                  softWrap: true,
                  textAlign: TextAlign.center,
                  style: labelStyle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _reminderKindForeground(ColorScheme cs, bool selected, bool enabled) {
  if (!enabled) return cs.onSurface.withValues(alpha: 0.38);
  if (selected) return cs.onSurface;
  return cs.onSurface.withValues(alpha: 0.76);
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

String _registeredReminderTypeLabel(String objectType) =>
    NotificationUiCopy.registeredReminderTypeLabel(objectType);

String _registeredReminderDisplayTitle(
  ReminderScheduleSnapshotEntry entry,
  String typeLabel,
) {
  final value = entry.title.trim();
  if (value.isNotEmpty) return value;
  return NotificationUiCopy.unSyncedReminderTitle(typeLabel);
}

String _registeredReminderDisplaySubtitle(
  ReminderScheduleSnapshotEntry entry,
  String typeLabel,
) {
  final value = entry.subtitle.trim();
  if (value.isNotEmpty) return value;
  return NotificationUiCopy.unSyncedReminderSubtitle(typeLabel);
}

TodaySectionKind? _detailKindForReminderObject(String objectType) {
  return switch (objectType) {
    'todo' => TodaySectionKind.todos,
    'habit' => TodaySectionKind.habits,
    'goal' => TodaySectionKind.goals,
    'anniversary' => TodaySectionKind.anniversaries,
    'course' => TodaySectionKind.courses,
    'note' => TodaySectionKind.notes,
    'diary' => TodaySectionKind.diary,
    _ => null,
  };
}

Color _registeredReminderTypeColor(String objectType, ColorScheme cs) {
  return switch (objectType) {
    'todo' => cs.primary,
    'goal' => cs.tertiary,
    'habit' => DesignTokens.defaultSuccess,
    'anniversary' => DesignTokens.defaultError,
    'countdown' => DesignTokens.defaultWarning,
    'course' => DesignTokens.defaultInfo,
    'calendar_event' => DesignTokens.defaultAccent,
    'note' => DesignTokens.defaultWarning,
    'diary' => cs.secondary,
    _ => cs.primary,
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

class _CompactSettingsSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _CompactSettingsSwitch({
    super.key,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 30,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Switch(value: value, onChanged: onChanged),
      ),
    );
  }
}

Widget _compactFilterChip(
  BuildContext context, {
  Key? key,
  required String label,
  required bool selected,
  required ValueChanged<bool>? onSelected,
}) {
  final cs = Theme.of(context).colorScheme;
  return FilterChip(
    key: key,
    label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    selected: selected,
    showCheckmark: false,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    labelPadding: const EdgeInsets.symmetric(horizontal: 2),
    labelStyle: appSecondaryControlLabelStyle(context).copyWith(
      color: selected ? cs.onSurface : cs.onSurface.withValues(alpha: 0.72),
      height: 1.0,
    ),
    selectedColor: cs.primary.withValues(alpha: 0.12),
    backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.18),
    side: BorderSide(
      color: selected
          ? cs.primary.withValues(alpha: 0.36)
          : cs.outlineVariant.withValues(alpha: 0.36),
      width: 0.45,
    ),
    onSelected: onSelected,
  );
}

Widget _ringtoneFeedback(ValueGetter<String> message) {
  return ValueListenableBuilder<AppLocale>(
    valueListenable: I18n.localeListenable,
    builder: (context, _, _) => Text(message()),
  );
}

String _ringtoneSoundLabel(String soundId) {
  if (NotificationUiCopy.isEn) {
    switch (soundId) {
      case 'soft':
        return 'Gentle Morning Bell';
      case 'forest':
        return 'Forest Dew';
      case 'silver':
        return 'Silver Chime';
      case 'paper':
        return 'Paper Rustle';
      case 'stream':
        return 'Stream Chime';
      case 'star':
        return 'Starlight Tone';
      case 'marimba':
        return 'Mountain Marimba';
      case 'lull':
        return 'Gentle Chord';
      case 'glass':
        return 'Glass Chime';
      case 'bamboo':
        return 'Bamboo Chime';
      case 'dawn':
        return 'Dawn Marimba';
      case 'wood':
        return 'Wood Fish';
      case 'water':
        return 'Water Drop';
      case 'harp':
        return 'Harp Triad';
      case 'mist':
        return 'Mist Chime';
      case 'pebble':
        return 'Pebble Chime';
      case 'tide':
        return 'Tide Chord';
      case 'chime':
        return 'Apple Classic Chime';
      case 'bell':
        return 'Xiaomi Chime';
      case 'morning':
        return 'Morning Triad';
      case 'pearl':
        return 'Pearl Tone';
      case 'cedar':
        return 'Cedar Chime';
      case 'moon':
        return 'Moonlight Triad';
      case 'cloud':
        return 'Cloud Chime';
      case 'sakura':
        return 'Sakura Chime';
      case 'classic':
        return 'Classic Soft Alarm';
      case 'beep':
        return 'Short Beep';
      case 'alarm':
        return 'Strong Alarm';
    }
  }
  for (final sound in ReminderRingtoneSettings.sounds) {
    if (sound.id == soundId) return sound.label;
  }
  return NotificationUiCopy.isEn
      ? _ringtoneSoundLabel(ReminderRingtoneSettings.defaultSound)
      : ReminderRingtoneSettings.sounds.first.label;
}

String _ringtonePreviewErrorMessage(ReminderRingtonePreviewException e) {
  if (e.reason == 'active_reminder_ringing') {
    return NotificationUiCopy.isEn
        ? 'A reminder is currently ringing. Please dismiss it before previewing.'
        : '当前有提醒正在响铃，请先处理后再试听。';
  }
  if (e.reason == 'platform_channel_failed' ||
      e.reason == 'native_and_flutter_preview_failed' ||
      e.reason == 'unknown') {
    return NotificationUiCopy.isEn
        ? 'Failed to start ringtone preview. Please check system volume or audio restrictions.'
        : '铃声试听启动失败，请检查系统音量或音频播放限制。';
  }
  return NotificationUiCopy.isEn
      ? 'Failed to start ringtone preview. Please check system volume or audio restrictions.'
      : '铃声试听启动失败，请检查系统音量或音频播放限制。';
}

String get _ringtoneSaveFailedMessage => NotificationUiCopy.isEn
    ? 'Failed to save ringtone settings. Please retry.'
    : '铃声设置保存失败，请重试';

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
  int _opSeq = 0;
  int _readSeq = 0;
  final ReminderRingtonePlatformPolicy _policy =
      ReminderRingtoneSettings.platformPolicy;

  @override
  void initState() {
    super.initState();
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _handleAccountDataChanged,
    );
    if (!_policy.supportsBuiltInSoundPicker) return;
    _reloadRingtoneSettings();
  }

  @override
  void dispose() {
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _handleAccountDataChanged,
    );
    if (_policy.supportsBuiltInSoundPicker) {
      unawaited(ReminderRingtoneSettings.stopPreview());
    }
    super.dispose();
  }

  bool _isCurrentOp(int seq, int accountGeneration, int preferenceGeneration) =>
      mounted &&
      seq == _opSeq &&
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(
        accountGeneration,
      ) &&
      preferenceGeneration == AccountPreferenceWrites.generation;

  bool _isCurrentRead(
    int seq,
    int accountGeneration,
    int preferenceGeneration,
  ) =>
      mounted &&
      seq == _readSeq &&
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(
        accountGeneration,
      ) &&
      preferenceGeneration == AccountPreferenceWrites.generation;

  void _handleAccountDataChanged() {
    if (!mounted) return;
    _opSeq++;
    _readSeq++;
    _previewing = false;
    if (_policy.supportsBuiltInSoundPicker) {
      unawaited(ReminderRingtoneSettings.stopPreview());
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() {
      _volume = ReminderRingtoneSettings.defaultVolumePercent;
      _sound = ReminderRingtoneSettings.defaultSound;
    });
    if (_policy.supportsBuiltInSoundPicker) {
      unawaited(_reloadRingtoneSettings());
    }
  }

  Future<void> _setVolume(int value) async {
    if (_previewing) return;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final preferenceGeneration = AccountPreferenceWrites.generation;
    final seq = ++_opSeq;
    _readSeq++;

    setState(() {
      _volume = value;
      _previewing = true;
    });

    try {
      await _applyRingtoneChange(
        () => ReminderRingtoneSettings.setVolumePercent(value),
        seq: seq,
        accountGeneration: accountGeneration,
        preferenceGeneration: preferenceGeneration,
        successMessage: () => NotificationUiCopy.ringtoneVolumeSuccess,
      );
    } finally {
      if (_isCurrentOp(seq, accountGeneration, preferenceGeneration)) {
        setState(() => _previewing = false);
      }
    }

    if (_isCurrentOp(seq, accountGeneration, preferenceGeneration)) {
      await _reloadRingtoneSettings(expectedOpSeq: seq);
    }
  }

  Future<void> _setSound(String value) async {
    if (_previewing) return;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final preferenceGeneration = AccountPreferenceWrites.generation;
    final seq = ++_opSeq;
    _readSeq++;

    setState(() {
      _sound = value;
      _previewing = true;
    });

    try {
      await _applyRingtoneChange(
        () => ReminderRingtoneSettings.setSound(value),
        seq: seq,
        accountGeneration: accountGeneration,
        preferenceGeneration: preferenceGeneration,
        successMessage: () =>
            NotificationUiCopy.ringtoneSoundSuccess(_ringtoneSoundLabel(value)),
      );
    } finally {
      if (_isCurrentOp(seq, accountGeneration, preferenceGeneration)) {
        setState(() => _previewing = false);
      }
    }

    if (_isCurrentOp(seq, accountGeneration, preferenceGeneration)) {
      await _reloadRingtoneSettings(expectedOpSeq: seq);
    }
  }

  Future<void> _previewCurrentSound() async {
    if (_previewing) return;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final preferenceGeneration = AccountPreferenceWrites.generation;
    final seq = ++_opSeq;
    _readSeq++;

    setState(() => _previewing = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ReminderRingtoneSettings.previewCurrentSound();
      if (!mounted ||
          !_isCurrentOp(seq, accountGeneration, preferenceGeneration)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: _ringtoneFeedback(
            () => NotificationUiCopy.ringtonePreviewing,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ReminderRingtonePreviewException catch (e) {
      if (!mounted ||
          !_isCurrentOp(seq, accountGeneration, preferenceGeneration)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: _ringtoneFeedback(() => _ringtonePreviewErrorMessage(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted ||
          !_isCurrentOp(seq, accountGeneration, preferenceGeneration)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: _ringtoneFeedback(
            () => NotificationUiCopy.isEn
                ? 'Failed to start ringtone preview. Please check system volume or audio restrictions.'
                : '铃声试听启动失败，请检查系统音量或音频播放限制。',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (_isCurrentOp(seq, accountGeneration, preferenceGeneration)) {
        setState(() => _previewing = false);
      }
    }
  }

  Future<void> _applyRingtoneChange(
    Future<void> Function() action, {
    required int seq,
    required int accountGeneration,
    required int preferenceGeneration,
    required ValueGetter<String> successMessage,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (!mounted ||
          !_isCurrentOp(seq, accountGeneration, preferenceGeneration)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: _ringtoneFeedback(successMessage),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ReminderRingtonePreviewException catch (e) {
      if (!mounted ||
          !_isCurrentOp(seq, accountGeneration, preferenceGeneration)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: _ringtoneFeedback(() => _ringtonePreviewErrorMessage(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted ||
          !_isCurrentOp(seq, accountGeneration, preferenceGeneration)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: _ringtoneFeedback(() => _ringtoneSaveFailedMessage),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _reloadRingtoneSettings({int? expectedOpSeq}) async {
    if (!_policy.supportsBuiltInSoundPicker) return;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final preferenceGeneration = AccountPreferenceWrites.generation;
    final opSeq = expectedOpSeq ?? _opSeq;
    final seq = ++_readSeq;

    await AccountPreferenceWrites.waitForBoundary();
    if (!_isCurrentRead(seq, accountGeneration, preferenceGeneration) ||
        opSeq != _opSeq) {
      return;
    }

    try {
      final volume = await ReminderRingtoneSettings.loadVolumePercent();
      if (!_isCurrentRead(seq, accountGeneration, preferenceGeneration) ||
          opSeq != _opSeq) {
        return;
      }

      final sound = await ReminderRingtoneSettings.loadSound();
      if (!_isCurrentRead(seq, accountGeneration, preferenceGeneration) ||
          opSeq != _opSeq) {
        return;
      }

      setState(() {
        _volume = volume;
        _sound = sound;
      });
    } catch (_) {
      // Retain existing state if read fails.
    }
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
            color: DesignTokens.defaultWarning,
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
        _RingtoneControlTile(
          icon: Icons.notifications_active_outlined,
          color: DesignTokens.defaultWarning,
          title: I18n.tr('preferences.ringtone.sound'),
          subtitle: _ringtoneSoundLabel(_sound),
          control: _RingtoneSoundControl(
            sound: _sound,
            previewing: _previewing,
            onPreview: _previewCurrentSound,
            onChanged: _setSound,
          ),
        ),
        if (_policy.supportsVolumePresets)
          _RingtoneControlTile(
            icon: Icons.volume_up_outlined,
            color: DesignTokens.defaultError,
            title: I18n.tr('preferences.ringtone.volume'),
            subtitle: '${I18n.tr('preferences.ringtone.current')} $_volume%',
            control: _RingtoneVolumeControl(
              volume: _volume,
              onChanged: _setVolume,
            ),
          ),
      ],
    );
  }
}

class _RingtoneControlTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget control;

  const _RingtoneControlTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.control,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          final targetControlWidth = availableWidth < 360
              ? 116.0
              : (availableWidth * 0.44).clamp(150.0, 220.0).toDouble();
          final maxControlWidth = (availableWidth - 96).clamp(
            0.0,
            availableWidth,
          );
          final controlWidth = targetControlWidth
              .clamp(0.0, maxControlWidth)
              .toDouble();
          final controlBox = SizedBox(
            width: controlWidth,
            height: 40,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: control,
              ),
            ),
          );

          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 54),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: appSecondaryMenuItemTextStyle(context).copyWith(
                          color: cs.onSurface,
                          fontWeight: DesignTokens.fontWeightRegular,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: appSecondaryControlLabelStyle(
                          context,
                        ).copyWith(color: cs.onSurface.withValues(alpha: 0.62)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                controlBox,
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RingtoneSoundControl extends StatelessWidget {
  final String sound;
  final bool previewing;
  final VoidCallback onPreview;
  final ValueChanged<String> onChanged;

  const _RingtoneSoundControl({
    required this.sound,
    required this.previewing,
    required this.onPreview,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 122.0;
        final previewSize = maxWidth < 144 ? 32.0 : 36.0;
        final dropdownWidth = (maxWidth - previewSize - 4)
            .clamp(76.0, 132.0)
            .toDouble();
        return Row(
          key: const ValueKey('notification_ringtone_sound_control'),
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: previewSize,
              height: 32,
              child: IconButton(
                tooltip: NotificationUiCopy.previewSoundTooltip,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: previewing ? null : onPreview,
                icon: previewing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.volume_up_outlined),
              ),
            ),
            const SizedBox(width: 4),
            AppCompactDropdown<String>(
              value: sound,
              width: dropdownWidth,
              items: [
                for (final sound in ReminderRingtoneSettings.sounds)
                  DropdownMenuItem(value: sound.id, child: Text(sound.label)),
              ],
              onChanged: (value) => value == null ? null : onChanged(value),
            ),
          ],
        );
      },
    );
  }
}

class _RingtoneVolumeControl extends StatelessWidget {
  final int volume;
  final ValueChanged<int> onChanged;

  const _RingtoneVolumeControl({required this.volume, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('notification_ringtone_volume_control'),
      height: 32,
      child: Row(
        children: [
          for (var i = 0; i < ReminderRingtoneSettings.presets.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: _RingtoneVolumeButton(
                value: ReminderRingtoneSettings.presets[i],
                selected: volume == ReminderRingtoneSettings.presets[i],
                onTap: () => onChanged(ReminderRingtoneSettings.presets[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RingtoneVolumeButton extends StatelessWidget {
  final int value;
  final bool selected;
  final VoidCallback onTap;

  const _RingtoneVolumeButton({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foreground = selected
        ? cs.onSurface
        : cs.onSurface.withValues(alpha: 0.72);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? cs.primary.withValues(alpha: 0.12) : cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected
                ? cs.primary.withValues(alpha: 0.36)
                : cs.outlineVariant.withValues(alpha: 0.38),
            width: 0.45,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              '$value%',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: appSecondaryControlLabelStyle(
                context,
              ).copyWith(color: foreground, height: 1.0),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuietHoursSection extends StatefulWidget {
  const _QuietHoursSection({super.key});

  @override
  State<_QuietHoursSection> createState() => _QuietHoursSectionState();
}

class _QuietHoursSectionState extends State<_QuietHoursSection> {
  bool _saving = false;

  Future<void> _runUpdate(
    BuildContext context,
    Future<void> Function(PreferencesProvider prefs) update,
  ) async {
    if (_saving) return;
    final account = _NotificationAccountGuard(context);
    if (!context.mounted || !account.isCurrent) {
      account.dispose();
      return;
    }
    setState(() => _saving = true);
    try {
      final prefs = context.read<PreferencesProvider>();
      await update(prefs);
      if (context.mounted && account.isCurrent) {
        try {
          context.read<NotificationService>().updateQuietHours(
            prefs.quietHoursPolicy,
          );
        } catch (_) {}
      }
    } catch (e, st) {
      debugPrint('[NotificationSettings] quiet hours save failed: $e\n$st');
    } finally {
      account.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime(
    BuildContext context, {
    required bool isStart,
    required int currentMinutes,
    required int otherMinutes,
  }) async {
    final isEn = I18n.current == AppLocale.en;
    final initial = TimeOfDay(
      hour: (currentMinutes ~/ 60) % 24,
      minute: currentMinutes % 60,
    );
    final picked = await AppTimePicker.show(
      context,
      initialTime: initial,
      title: isStart
          ? (isEn ? 'Quiet Hours Start' : '免打扰开始时间')
          : (isEn ? 'Quiet Hours End' : '免打扰结束时间'),
      minuteStep: 5,
    );
    if (picked == null || !mounted) return;
    final pickedMinutes = picked.hour * 60 + picked.minute;
    await _runUpdate(
      this.context,
      (prefs) => prefs.setQuietHoursWindow(
        isStart ? pickedMinutes : otherMinutes,
        isStart ? otherMinutes : pickedMinutes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();
    final cs = Theme.of(context).colorScheme;
    final isEn = I18n.current == AppLocale.en;
    final startTime = TimeOfDay(
      hour: (prefs.quietHoursStartMinutes ~/ 60) % 24,
      minute: prefs.quietHoursStartMinutes % 60,
    );
    final endTime = TimeOfDay(
      hour: (prefs.quietHoursEndMinutes ~/ 60) % 24,
      minute: prefs.quietHoursEndMinutes % 60,
    );
    return AppSettingsSection(
      key: const ValueKey('quiet_hours_section'),
      title: isEn ? 'Quiet Hours' : '夜间免打扰',
      subtitle: isEn
          ? 'Defer or silence non-alarm reminders during quiet hours'
          : '在设定时段内延后或静音非紧急提醒',
      children: [
        AppSettingsTile(
          icon: Icons.bedtime_outlined,
          title: isEn ? 'Enable Quiet Hours' : '开启夜间免打扰',
          color: cs.primary,
          subtitle: isEn
              ? '${AppTimePicker.format(startTime)} – ${AppTimePicker.format(endTime)}'
              : '${AppTimePicker.format(startTime)} 至 ${AppTimePicker.format(endTime)}',
          trailing: _CompactSettingsSwitch(
            key: const ValueKey('quiet_hours_enabled_switch'),
            value: prefs.quietHoursEnabled,
            onChanged: _saving
                ? null
                : (v) => _runUpdate(context, (p) => p.setQuietHoursEnabled(v)),
          ),
        ),
        if (prefs.quietHoursEnabled) ...[
          AppSettingsTile(
            key: const ValueKey('quiet_hours_start_tile'),
            icon: Icons.nights_stay_outlined,
            title: isEn ? 'Start Time' : '开始时间',
            color: cs.primary,
            subtitle: AppTimePicker.format(startTime),
            trailing: Icon(
              Icons.chevron_right,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
            onTap: _saving
                ? null
                : () => _pickTime(
                    context,
                    isStart: true,
                    currentMinutes: prefs.quietHoursStartMinutes,
                    otherMinutes: prefs.quietHoursEndMinutes,
                  ),
          ),
          AppSettingsTile(
            key: const ValueKey('quiet_hours_end_tile'),
            icon: Icons.wb_sunny_outlined,
            title: isEn ? 'End Time' : '结束时间',
            color: cs.primary,
            subtitle: AppTimePicker.format(endTime),
            trailing: Icon(
              Icons.chevron_right,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
            onTap: _saving
                ? null
                : () => _pickTime(
                    context,
                    isStart: false,
                    currentMinutes: prefs.quietHoursEndMinutes,
                    otherMinutes: prefs.quietHoursStartMinutes,
                  ),
          ),
          AppSettingsTile(
            icon: Icons.alarm_on_outlined,
            title: isEn ? 'Allow Alarms' : '允许强闹钟穿透',
            color: DesignTokens.defaultWarning,
            subtitle: isEn
                ? 'Full-screen alarm reminders still ring normally'
                : '强提醒闹钟不受免打扰限制，到点照常响铃',
            trailing: _CompactSettingsSwitch(
              key: const ValueKey('quiet_hours_allow_alarms_switch'),
              value: prefs.quietHoursAllowAlarms,
              onChanged: _saving
                  ? null
                  : (v) => _runUpdate(
                      context,
                      (p) => p.setQuietHoursAllowAlarms(v),
                    ),
            ),
          ),
          AppSettingsTile(
            icon: Icons.schedule_send_outlined,
            title: isEn ? 'Defer Until End' : '结束后自动补发',
            color: DesignTokens.defaultAccent,
            subtitle: isEn
                ? 'On: defer to end time; Off: deliver silently'
                : '开启将在免打扰结束后提醒；关闭则在时段内静音投递',
            trailing: _CompactSettingsSwitch(
              key: const ValueKey('quiet_hours_defer_switch'),
              value: prefs.quietHoursDeferUntilEnd,
              onChanged: _saving
                  ? null
                  : (v) => _runUpdate(
                      context,
                      (p) => p.setQuietHoursDeferUntilEnd(v),
                    ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ReportReminderSection extends StatelessWidget {
  const _ReportReminderSection({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();
    final cs = Theme.of(context).colorScheme;
    return AppSettingsSection(
      title: NotificationUiCopy.reportRemindersTitle,
      subtitle: NotificationUiCopy.reportRemindersSubtitle,
      showDividers: true,
      children: [
        _ReportReminderTile(
          title: NotificationUiCopy.reportDailyTitle,
          icon: Icons.today_outlined,
          color: cs.primary,
          config: prefs.dailyReportReminderConfig,
          cadence: _ReportReminderCadence.daily,
        ),
        _ReportReminderTile(
          title: NotificationUiCopy.reportWeeklyTitle,
          icon: Icons.summarize_outlined,
          color: DesignTokens.defaultInfo,
          config: prefs.weeklyReportReminderConfig,
          cadence: _ReportReminderCadence.weekly,
        ),
        _ReportReminderTile(
          title: NotificationUiCopy.reportMonthlyTitle,
          icon: Icons.calendar_month_outlined,
          color: DesignTokens.defaultAccent,
          config: prefs.monthlyReportReminderConfig,
          cadence: _ReportReminderCadence.monthly,
        ),
        _ReportReminderTile(
          title: NotificationUiCopy.reportYearlyTitle,
          icon: Icons.event_available_outlined,
          color: DesignTokens.defaultWarning,
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
      _ReportReminderCadence.daily => NotificationUiCopy.reportCadenceDaily(
        _time,
      ),
      _ReportReminderCadence.weekly => NotificationUiCopy.reportCadenceWeekly(
        _weekdayLabel(config.weekday),
        _time,
      ),
      _ReportReminderCadence.monthly => NotificationUiCopy.reportCadenceMonthly(
        config.monthDay,
        _time,
      ),
      _ReportReminderCadence.yearly => NotificationUiCopy.reportCadenceYearly(
        config.month,
        config.monthDay,
        _time,
      ),
    };
    final state = config.enabled
        ? NotificationUiCopy.reportDynamicSummary
        : NotificationUiCopy.reportOff;
    return '$state · $cadenceText';
  }

  Future<void> _save(BuildContext context, ReportReminderConfig next) async {
    if (_saving) return;
    final account = _NotificationAccountGuard(context);
    if (!context.mounted || !account.isCurrent) {
      account.dispose();
      return;
    }
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
    } catch (e, st) {
      debugPrint('[NotificationSettings] report settings save failed: $e\n$st');
      if (context.mounted && account.isCurrent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(NotificationUiCopy.reportSaveFailed),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      account.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _timeSubtitle {
    return switch (cadence) {
      _ReportReminderCadence.daily =>
        NotificationUiCopy.reportTimeDailySubtitle,
      _ReportReminderCadence.weekly =>
        NotificationUiCopy.reportTimeWeeklySubtitle,
      _ReportReminderCadence.monthly =>
        NotificationUiCopy.reportTimeMonthlySubtitle,
      _ReportReminderCadence.yearly =>
        NotificationUiCopy.reportTimeYearlySubtitle,
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
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            collapsedShape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            tilePadding: EdgeInsets.zero,
            showTrailingIcon: false,
            title: _SettingsExpansionHeader(
              key: ValueKey('report_reminder_${cadence.name}_header'),
              iconKey: ValueKey('report_reminder_${cadence.name}_header_icon'),
              titleKey: ValueKey(
                'report_reminder_${cadence.name}_header_title',
              ),
              subtitleKey: ValueKey(
                'report_reminder_${cadence.name}_header_subtitle',
              ),
              icon: icon,
              color: color,
              title: title,
              subtitle: _subtitle,
              trailing: _CompactSettingsSwitch(
                key: ValueKey('report_reminder_${cadence.name}_enabled_switch'),
                value: config.enabled,
                onChanged: _saving
                    ? null
                    : (v) => _save(context, config.copyWith(enabled: v)),
              ),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              AppSettingsTile(
                icon: Icons.schedule,
                color: color,
                title: NotificationUiCopy.reportNotificationTime,
                subtitle: _timeSubtitle,
                trailing: TextButton(
                  key: ValueKey('report_reminder_time_button_${cadence.name}'),
                  onPressed: _saving
                      ? null
                      : () async {
                          final account = _NotificationAccountGuard(context);
                          try {
                            if (!context.mounted || !account.isCurrent) return;
                            final picked = await AppTimePicker.show(
                              context,
                              initialTime: TimeOfDay(
                                hour: config.hour,
                                minute: config.minute,
                              ),
                              titleKey:
                                  'preferences.report_reminder.${cadence.name}.time',
                              subtitleKey:
                                  'preferences.report_reminder.time.subtitle',
                            );
                            if (picked == null ||
                                !context.mounted ||
                                !account.isCurrent) {
                              return;
                            }
                            await _save(
                              context,
                              config.copyWith(
                                hour: picked.hour,
                                minute: picked.minute,
                              ),
                            );
                          } finally {
                            account.dispose();
                          }
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
        ),
      ),
    );
  }

  List<Widget> _cadenceChips(BuildContext context) {
    return switch (cadence) {
      _ReportReminderCadence.daily => const <Widget>[],
      _ReportReminderCadence.weekly => [
        for (var day = 1; day <= 7; day++)
          _compactFilterChip(
            context,
            key: ValueKey('report_reminder_${cadence.name}_weekday_$day'),
            label: _weekdayLabel(day),
            selected: config.weekday == day,
            onSelected: _saving
                ? null
                : (_) => _save(context, config.copyWith(weekday: day)),
          ),
      ],
      _ReportReminderCadence.monthly => _monthDayChips(context),
      _ReportReminderCadence.yearly => [
        for (var month = 1; month <= 12; month++)
          _compactFilterChip(
            context,
            key: ValueKey('report_reminder_${cadence.name}_month_$month'),
            label: NotificationUiCopy.monthChipLabel(month),
            selected: config.month == month,
            onSelected: _saving
                ? null
                : (_) => _save(context, config.copyWith(month: month)),
          ),
        for (final day in const [1, 5, 10, 15, 20, 25, 28, 31])
          _compactFilterChip(
            context,
            key: ValueKey('report_reminder_${cadence.name}_day_$day'),
            label: NotificationUiCopy.dayChipLabel(day),
            selected: config.monthDay == day,
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
        _compactFilterChip(
          context,
          key: ValueKey('report_reminder_${cadence.name}_day_$day'),
          label: NotificationUiCopy.dayChipLabel(day),
          selected: config.monthDay == day,
          onSelected: _saving
              ? null
              : (_) => _save(context, config.copyWith(monthDay: day)),
        ),
    ];
  }
}

Color _notificationColor(NotificationType type, ColorScheme cs) {
  return switch (type) {
    NotificationType.todo => cs.primary,
    NotificationType.habit => DesignTokens.defaultSuccess,
    NotificationType.pomodoro => DesignTokens.defaultError,
    NotificationType.anniversary => DesignTokens.defaultAccent,
    NotificationType.location => DesignTokens.defaultInfo,
    NotificationType.general => DesignTokens.defaultWarning,
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

String _notificationTypeLabel(NotificationType type) =>
    NotificationUiCopy.notificationTypeLabel(type);

String _formatNotificationTime(DateTime value, String? pattern) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${I18nDateFormat.date(local, pattern: pattern ?? I18nDateFormat.defaultPattern)} ${two(local.hour)}:${two(local.minute)}';
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
