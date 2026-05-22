import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/app_config.dart';
import '../core/i18n_date_format.dart';
import '../providers/auth_provider.dart';
import '../services/admin_api.dart';
import '../services/api_client.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

/// 管理员后台 — 仅当 AuthProvider.state.isAdmin == true 时可进入。
class AdminScreen extends StatefulWidget {
  final int initialTabIndex;

  const AdminScreen({super.key, this.initialTabIndex = 0});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 9,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 8),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.state.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('管理员后台')),
        body: const EmptyState(icon: Icons.lock, message: '仅管理员可访问'),
      );
    }
    final api = AdminApi(auth.client);

    return Scaffold(
      appBar: AppBar(
        title: const Text('管理员后台'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          labelPadding: const EdgeInsets.symmetric(horizontal: 6),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          indicator: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          labelColor: Theme.of(context).colorScheme.onPrimaryContainer,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
          tabs: const [
            Tab(
              height: 44,
              child: _AdminTabLabel(icon: Icons.dashboard_outlined, text: '概览'),
            ),
            Tab(
              height: 44,
              child: _AdminTabLabel(icon: Icons.tune, text: '全站设置'),
            ),
            Tab(
              height: 44,
              child: _AdminTabLabel(icon: Icons.auto_awesome, text: 'AI 配置'),
            ),
            Tab(
              height: 44,
              child: _AdminTabLabel(icon: Icons.cloud_outlined, text: '云端备份'),
            ),
            Tab(
              height: 44,
              child: _AdminTabLabel(icon: Icons.people_outline, text: '用户'),
            ),
            Tab(
              height: 44,
              child: _AdminTabLabel(icon: Icons.campaign_outlined, text: '公告'),
            ),
            Tab(
              height: 44,
              child: _AdminTabLabel(icon: Icons.feedback_outlined, text: '反馈'),
            ),
            Tab(
              height: 44,
              child: _AdminTabLabel(icon: Icons.vpn_key_outlined, text: '邀请码'),
            ),
            Tab(
              height: 44,
              child: _AdminTabLabel(
                icon: Icons.receipt_long_outlined,
                text: '日志',
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _DashboardTab(api: api),
          _SettingsTab(api: api),
          _AiSettingsTab(api: api),
          _BackupSettingsTab(api: api),
          _UsersTab(api: api, selfId: auth.state.userId),
          _AnnouncementsTab(api: api),
          _FeedbackTab(api: api),
          _InvitesTab(api: api),
          _AuditLogTab(api: api),
        ],
      ),
    );
  }
}

class _AdminTabLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _AdminTabLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

// ====================================================================
// 概览
// ====================================================================

class _DashboardTab extends StatefulWidget {
  final AdminApi api;
  const _DashboardTab({required this.api});
  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  Map<String, dynamic>? _stats;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _stats = await widget.api.stats();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_stats == null) {
      return Center(child: Text(_error ?? '加载失败'));
    }
    final users = _stats!['users'] as Map? ?? {};
    final fb = _stats!['feedback'] as Map? ?? {};
    final ann = _stats!['announcements'] as Map? ?? {};
    final inv = _stats!['invites'] as Map? ?? {};
    final series = (_stats!['registration_series'] as List?)?.cast<Map>() ?? [];
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          AppInfoBanner(
            icon: Icons.verified_outlined,
            color: Colors.indigo,
            title: '客户端连接',
            message: AppConfig.bakedServerUrl.isEmpty
                ? '相对路径 (同域反代)'
                : AppConfig.bakedServerUrl,
            margin: const EdgeInsets.only(bottom: 12),
          ),
          _GridCards([
            _Kpi('总用户', '${users['total'] ?? 0}', Icons.people, Colors.blue),
            _Kpi(
              '管理员',
              '${users['admin'] ?? 0}',
              Icons.shield,
              Colors.deepOrange,
            ),
            _Kpi('已禁用', '${users['disabled'] ?? 0}', Icons.block, Colors.red),
            _Kpi(
              '今日新增',
              '${users['new_today'] ?? 0}',
              Icons.person_add_alt,
              Colors.green,
            ),
            _Kpi(
              '7 日活跃',
              '${users['active_7d'] ?? 0}',
              Icons.trending_up,
              Colors.teal,
            ),
            _Kpi(
              '在线',
              '${users['online'] ?? _stats!['tokens_online'] ?? 0}',
              Icons.wifi_tethering,
              Colors.cyan,
            ),
            _Kpi(
              '邮箱未验证',
              '${users['unverified_email'] ?? 0}',
              Icons.mark_email_unread_outlined,
              Colors.amber,
            ),
            _Kpi(
              '待处理反馈',
              '${fb['open'] ?? 0}',
              Icons.chat_bubble_outline,
              Colors.orange,
            ),
            _Kpi(
              '处理中反馈',
              '${fb['in_progress'] ?? 0}',
              Icons.pending_actions_outlined,
              Colors.deepPurple,
            ),
            _Kpi(
              '反馈总数',
              '${fb['total'] ?? 0}',
              Icons.forum_outlined,
              Colors.grey,
            ),
            _Kpi(
              '公告(已发)',
              '${ann['published'] ?? 0}',
              Icons.campaign,
              Colors.indigo,
            ),
            _Kpi(
              '邀请码已用',
              '${inv['used'] ?? 0} / ${inv['total'] ?? 0}',
              Icons.vpn_key,
              Colors.purple,
            ),
          ]),
          const SizedBox(height: 14),
          AppSurfaceCard(
            padding: const EdgeInsets.all(14),
            child: Padding(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '近 7 天注册',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (series.isEmpty)
                    Text(
                      '暂无注册',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.58),
                      ),
                    ),
                  ...series.map((row) {
                    final count = ((row['count'] as num?) ?? 0).toDouble();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 90,
                            child: Text(
                              row['date'].toString(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.68),
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: (count / 10).clamp(0.0, 1.0),
                                minHeight: 8,
                                backgroundColor: cs.surfaceContainerHighest,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${row['count']}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Kpi {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  const _Kpi(this.title, this.value, this.icon, this.color);
}

class _GridCards extends StatelessWidget {
  final List<_Kpi> items;
  const _GridCards(this.items);
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = Theme.of(context).colorScheme;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 2.4,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: items
          .map(
            (k) => AppSurfaceCard(
              padding: const EdgeInsets.all(12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: k.color.withValues(alpha: 0.16)),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: k.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(k.icon, color: k.color, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          k.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.62),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        Text(
                          k.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

const int _adminPageSize = 20;
const List<int> _adminPageSizeOptions = [20, 50, 100];

String _adminStatusLabel(String value) {
  switch (value) {
    case 'open':
      return '待处理';
    case 'in_progress':
      return '处理中';
    case 'resolved':
      return '已解决';
    case 'closed':
      return '已关闭';
    case 'published':
      return '已发布';
    case 'draft':
      return '草稿';
    case 'used':
      return '已使用';
    case 'unused':
      return '未使用';
    case 'admin':
      return '管理员';
    case 'disabled':
      return '已禁用';
    case 'active':
      return '可登录';
    case 'normal':
      return '普通用户';
    case 'online':
      return '在线';
    case 'offline':
      return '离线';
    case 'unverified_email':
      return '邮箱未验证';
    case 'verified_email':
      return '邮箱已验证';
    case 'no_email':
      return '未绑定邮箱';
    case 'has_feedback':
      return '有反馈';
    case 'info':
      return '普通';
    case 'warning':
      return '重要';
    case 'critical':
      return '紧急';
    default:
      return value.isEmpty ? '全部' : value;
  }
}

String _adminUserSortLabel(String value) {
  switch (value) {
    case 'last_active_desc':
      return '最近活跃优先';
    case 'last_login_desc':
      return '最近登录优先';
    case 'feedback_desc':
      return '反馈较多优先';
    case 'username_asc':
      return '用户名 A-Z';
    case 'email_asc':
      return '邮箱 A-Z';
    default:
      return '最新注册优先';
  }
}

String _adminAnnouncementSortLabel(String value) {
  switch (value) {
    case 'updated_desc':
      return '最近更新优先';
    case 'title_asc':
      return '标题 A-Z';
    case 'level_desc':
      return '紧急程度优先';
    default:
      return '最新创建优先';
  }
}

String _adminFeedbackSortLabel(String value) {
  switch (value) {
    case 'updated_desc':
      return '最近处理优先';
    case 'status_asc':
      return '待处理优先';
    case 'user_asc':
      return '用户 A-Z';
    default:
      return '最新反馈优先';
  }
}

String _adminInviteSortLabel(String value) {
  switch (value) {
    case 'used_desc':
      return '最近使用优先';
    case 'code_asc':
      return '邀请码 A-Z';
    case 'note_asc':
      return '备注 A-Z';
    default:
      return '最新生成优先';
  }
}

String _adminAuditSortLabel(String value) {
  switch (value) {
    case 'actor_asc':
      return '管理员 A-Z';
    case 'action_asc':
      return '操作类型 A-Z';
    case 'target_asc':
      return '对象 A-Z';
    default:
      return '最新操作优先';
  }
}

String _adminBackupSortLabel(String value) {
  switch (value) {
    case 'username_asc':
      return '用户名 A-Z';
    case 'size_desc':
      return '备份体积从大到小';
    case 'size_asc':
      return '备份体积从小到大';
    case 'version_desc':
      return '同步版本较高优先';
    default:
      return '最近同步优先';
  }
}

String _adminServerBackupSortLabel(String value) {
  switch (value) {
    case 'size_desc':
      return '文件从大到小';
    case 'size_asc':
      return '文件从小到大';
    case 'status_asc':
      return '状态 A-Z';
    case 'filename_asc':
      return '文件名 A-Z';
    default:
      return '最新生成优先';
  }
}

String _auditActionLabel(String value) {
  switch (value) {
    case 'user.update':
      return '更新用户';
    case 'user.delete':
      return '删除用户';
    case 'announcement.create':
      return '创建公告';
    case 'announcement.update':
      return '更新公告';
    case 'announcement.delete':
      return '删除公告';
    case 'feedback.reply':
      return '回复反馈';
    case 'feedback.delete':
      return '删除反馈';
    case 'invite.create':
      return '生成邀请码';
    case 'invite.delete':
      return '删除邀请码';
    default:
      return value.isEmpty ? '全部操作' : value;
  }
}

String _feedbackCategoryLabel(String value) {
  switch (value) {
    case 'feature':
      return '功能建议';
    case 'bug':
      return '问题反馈';
    case 'wish':
      return '愿望清单';
    case 'other':
      return '其他';
    default:
      return value.isEmpty ? '全部分类' : value;
  }
}

String _adminPageSummary(AdminPage? page) {
  if (page == null) return '正在加载本页数据';
  if (page.total <= 0) return '0 条';
  final start = page.offset + 1;
  final end = page.offset + page.items.length;
  return '第 $start-$end 条 / 共 ${page.total} 条';
}

String _adminPageNumber(AdminPage? page) {
  if (page == null) return '第 -/- 页';
  if (page.total <= 0) return '第 0/0 页';
  final safeLimit = page.limit <= 0 ? _adminPageSize : page.limit;
  final current = (page.offset ~/ safeLimit) + 1;
  final totalPages = ((page.total + safeLimit - 1) ~/ safeLimit).clamp(
    1,
    999999,
  );
  return '第 $current/$totalPages 页';
}

int _adminTotalPages(AdminPage? page, int pageSize) {
  if (page == null || page.total <= 0) return 0;
  final safeLimit = pageSize <= 0 ? _adminPageSize : pageSize;
  return ((page.total + safeLimit - 1) ~/ safeLimit).clamp(1, 999999);
}

int _previousAdminOffset(int offset, [int pageSize = _adminPageSize]) {
  return offset <= pageSize ? 0 : offset - pageSize;
}

int _offsetAfterAdminDelete({
  required int offset,
  required int itemCount,
  int pageSize = _adminPageSize,
}) {
  if (itemCount == 1 && offset > 0) {
    return _previousAdminOffset(offset, pageSize);
  }
  return offset;
}

String _adminErrorMessage(Object error, String target) {
  final text = error is ApiException ? error.message : error.toString();
  return '无法加载$target：$text';
}

Future<bool> _confirmAdminDangerAction({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = '删除',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AppDialog(
      title: Text(title),
      icon: const Icon(Icons.warning_amber_outlined),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}

class _AdminErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _AdminErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 40,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重新加载'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminPaginationBar extends StatelessWidget {
  final Key? barKey;
  final AdminPage? page;
  final bool loading;
  final int pageSize;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<int>? onJumpToPage;
  final ValueChanged<int>? onPageSizeChanged;

  const _AdminPaginationBar({
    this.barKey,
    required this.page,
    required this.loading,
    this.pageSize = _adminPageSize,
    required this.onPrevious,
    required this.onNext,
    this.onJumpToPage,
    this.onPageSizeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final canPrevious = !loading && (page?.offset ?? 0) > 0;
    final canNext = !loading && (page?.hasMore ?? false);
    final totalPages = _adminTotalPages(page, pageSize);
    final canPickPage =
        onJumpToPage != null && totalPages > 1 && totalPages <= 200;
    final currentPage = totalPages <= 0 || page == null
        ? 0
        : (page!.offset ~/ (page!.limit <= 0 ? pageSize : page!.limit)) + 1;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      key: barKey,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final summary = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _adminPageSummary(page),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.68),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _adminPageNumber(page),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.52),
                ),
              ),
            ],
          );
          final pageSizePicker = onPageSizeChanged == null
              ? const SizedBox.shrink()
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '每页',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.68),
                      ),
                    ),
                    const SizedBox(width: 6),
                    DropdownButton<int>(
                      value: pageSize,
                      underline: const SizedBox.shrink(),
                      isDense: true,
                      items: _adminPageSizeOptions
                          .map(
                            (v) =>
                                DropdownMenuItem(value: v, child: Text('$v')),
                          )
                          .toList(),
                      onChanged: loading || onPageSizeChanged == null
                          ? null
                          : (v) {
                              if (v != null) onPageSizeChanged!(v);
                            },
                    ),
                  ],
                );
          final navigation = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onJumpToPage != null && totalPages > 1) ...[
                Tooltip(
                  message: '跳到第一页',
                  child: IconButton(
                    onPressed: canPrevious ? () => onJumpToPage!(1) : null,
                    icon: const Icon(Icons.first_page),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Tooltip(
                message: '上一页',
                child: OutlinedButton.icon(
                  onPressed: canPrevious ? onPrevious : null,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('上一页'),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: '下一页',
                child: FilledButton.tonalIcon(
                  onPressed: canNext ? onNext : null,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('下一页'),
                ),
              ),
              if (onJumpToPage != null && totalPages > 1) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: '跳到最后一页',
                  child: IconButton(
                    onPressed: canNext ? () => onJumpToPage!(totalPages) : null,
                    icon: const Icon(Icons.last_page),
                  ),
                ),
              ],
            ],
          );
          final pageJump = !canPickPage
              ? const SizedBox.shrink()
              : DropdownButton<int>(
                  value: currentPage.clamp(1, totalPages).toInt(),
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  items: List.generate(totalPages > 200 ? 200 : totalPages, (
                    index,
                  ) {
                    final pageNo = index + 1;
                    return DropdownMenuItem(
                      value: pageNo,
                      child: Text('$pageNo/$totalPages'),
                    );
                  }),
                  onChanged: loading
                      ? null
                      : (value) {
                          if (value != null) onJumpToPage!(value);
                        },
                );
          if (constraints.maxWidth < 520) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: summary),
                    pageJump,
                    if (canPickPage) const SizedBox(width: 8),
                    pageSizePicker,
                  ],
                ),
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: navigation),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: summary),
              pageJump,
              if (canPickPage) const SizedBox(width: 12),
              pageSizePicker,
              const SizedBox(width: 12),
              navigation,
            ],
          );
        },
      ),
    );
  }
}

// ====================================================================
// 全站设置
// ====================================================================

class _SettingsTab extends StatefulWidget {
  final AdminApi api;
  const _SettingsTab({required this.api});
  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  Map<String, dynamic> _data = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  final _msgCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _data = await widget.api.getSettings();
      _msgCtrl.text = (_data['maintenance_message'] ?? '').toString();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _set(String key, dynamic value) async {
    setState(() => _saving = true);
    try {
      await widget.api.updateSettings(
        inviteCodeRequired: key == 'invite_code_required' ? value : null,
        registrationEnabled: key == 'registration_enabled' ? value : null,
        registrationEmailRequired: key == 'registration_email_required'
            ? value
            : null,
        maintenanceMode: key == 'maintenance_mode' ? value : null,
        maintenanceMessage: key == 'maintenance_message' ? value : null,
      );
      _data[key] = value;
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppSettingsSection(
          title: '账户与注册',
          subtitle: '控制新用户入口与邀请码策略',
          children: [
            AppSwitchTile(
              icon: Icons.person_add_alt_1_outlined,
              color: Colors.green,
              value: _data['registration_enabled'] == true,
              title: '允许注册',
              subtitle: '关闭后新用户无法注册，现有用户仍可登录',
              onChanged: _saving
                  ? null
                  : (v) => _set('registration_enabled', v),
            ),
            AppSwitchTile(
              icon: Icons.vpn_key_outlined,
              color: Colors.purple,
              value: _data['invite_code_required'] == true,
              title: '注册需要邀请码',
              subtitle: '只有带邀请码才能注册',
              onChanged: _saving
                  ? null
                  : (v) => _set('invite_code_required', v),
            ),
            AppSwitchTile(
              icon: Icons.mark_email_read_outlined,
              color: Colors.teal,
              value: _data['registration_email_required'] == true,
              title: '注册需要邮箱验证',
              subtitle: '新账号必须填写邮箱并通过验证码后才能创建',
              onChanged: _saving
                  ? null
                  : (v) => _set('registration_email_required', v),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppSettingsSection(
          title: '维护模式',
          subtitle: '控制同步服务与客户端提示',
          children: [
            AppSwitchTile(
              icon: Icons.construction_outlined,
              color: Colors.orange,
              value: _data['maintenance_mode'] == true,
              title: '启用维护模式',
              subtitle: '开启后 /api/sync 拒绝服务；客户端登录页会提示',
              onChanged: _saving ? null : (v) => _set('maintenance_mode', v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _msgCtrl,
              decoration: const InputDecoration(
                labelText: '维护公告文字',
                hintText: '将在客户端登录/同步报错时展示',
                prefixIcon: Icon(Icons.campaign_outlined),
              ),
              onEditingComplete: () =>
                  _set('maintenance_message', _msgCtrl.text.trim()),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppInfoBanner(
          icon: Icons.info_outline,
          color: cs.primary,
          title: '服务器地址',
          message: '服务器地址在 APK / Web 构建时就已锁定，运行期不可修改。如需切换后端，请重新构建并分发新版本。',
        ),
      ],
    );
  }
}

// ====================================================================
// AI 配置
// ====================================================================

class _AiSettingsTab extends StatefulWidget {
  final AdminApi api;
  const _AiSettingsTab({required this.api});
  @override
  State<_AiSettingsTab> createState() => _AiSettingsTabState();
}

class _AiSettingsTabState extends State<_AiSettingsTab> {
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  String? _testResult;
  Color _testColor = Colors.grey;
  String? _error;
  bool _enabled = false;
  final _baseCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _quotaCtrl = TextEditingController(text: '0');
  bool _keyMasked = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    _quotaCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.getSettings();
      _enabled = data['ai_enabled'] == true;
      _baseCtrl.text = (data['ai_base_url'] ?? '').toString();
      _keyCtrl.text = (data['ai_api_key'] ?? '').toString();
      _keyMasked = (data['ai_api_key_set'] == true);
      _modelCtrl.text = (data['ai_model'] ?? '').toString();
      _quotaCtrl.text = (((data['ai_daily_quota'] as num?) ?? 0).toInt())
          .toString();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final newKey = _keyCtrl.text.trim();
      final submitKey = (_keyMasked && newKey.contains('***')) ? null : newKey;
      final payload = <String, Object?>{
        'ai_enabled': _enabled,
        'ai_base_url': _baseCtrl.text.trim(),
        'ai_model': _modelCtrl.text.trim(),
        'ai_daily_quota': int.tryParse(_quotaCtrl.text.trim()) ?? 0,
      };
      if (submitKey != null) {
        payload['ai_api_key'] = submitKey;
      }
      await widget.api.client.patch('/api/admin/settings', payload);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('AI 配置已保存')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final res = await widget.api.testAi();
      setState(() {
        _testResult = '✅ 模型 ${res['model']} 可达，回复: ${res['sample']}';
        _testColor = Colors.green;
      });
    } on ApiException catch (e) {
      setState(() {
        _testResult = '❌ ${e.message}';
        _testColor = Colors.red;
      });
    } catch (e) {
      setState(() {
        _testResult = '❌ $e';
        _testColor = Colors.red;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppSettingsSection(
          title: 'AI 功能',
          subtitle: '所有请求经后端代理，前端不暴露密钥',
          children: [
            AppSwitchTile(
              icon: Icons.auto_awesome,
              color: cs.primary,
              value: _enabled,
              title: '启用 AI 功能',
              subtitle: '关闭后所有用户都无法使用 AI 拆解/回顾',
              onChanged: (v) => setState(() => _enabled = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _baseCtrl,
              decoration: const InputDecoration(
                labelText: 'Base URL (OpenAI 兼容网关)',
                hintText: 'https://api.openai.com',
                helperText: '路径后自动加 /v1/chat/completions',
                prefixIcon: Icon(Icons.link_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _keyCtrl,
              decoration: InputDecoration(
                labelText: 'API Key',
                helperText: _keyMasked ? '已配置（显示为掩码，保持不动即不修改）' : '尚未配置',
                prefixIcon: const Icon(Icons.key_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _modelCtrl,
              decoration: const InputDecoration(
                labelText: '模型名称',
                hintText: 'gpt-4o-mini / claude-3-haiku-20240307',
                prefixIcon: Icon(Icons.memory_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _quotaCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '每用户每日调用上限',
                helperText: '0 = 不限',
                prefixIcon: Icon(Icons.speed_outlined),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? '保存中…' : '保存'),
                ),
                OutlinedButton.icon(
                  icon: _testing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check),
                  label: const Text('测试连接'),
                  onPressed: _testing ? null : _test,
                ),
              ],
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _testColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _testColor.withValues(alpha: 0.18)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _testColor == Colors.green
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      color: _testColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _testResult!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.74),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        AppInfoBanner(
          icon: Icons.security_outlined,
          color: Colors.teal,
          title: '安全代理',
          message: '所有用户的 AI 请求都通过后端 /api/ai/chat 代理，前端永远拿不到 API Key。',
        ),
      ],
    );
  }
}

// ====================================================================
// 云端备份
// ====================================================================

class _BackupSettingsTab extends StatefulWidget {
  final AdminApi api;
  const _BackupSettingsTab({required this.api});
  @override
  State<_BackupSettingsTab> createState() => _BackupSettingsTabState();
}

class _BackupSettingsTabState extends State<_BackupSettingsTab> {
  bool _loading = true;
  bool _saving = false;
  bool _runningServerBackup = false;
  bool _testingReminderEmail = false;
  bool _testingAccountEmail = false;
  bool _exportingBackups = false;
  bool _exportingServerBackups = false;
  String? _error;

  bool _backupEnabled = true;
  bool _serverBackupEnabled = true;
  bool _openlistEnabled = false;
  bool _backupEmailEnabled = false;
  bool _reminderEmailEnabled = false;
  bool _accountEmailEnabled = true;
  bool _emailAutoSwitchEnabled = false;
  bool _accountSmtpUseSsl = true;
  String _emailPrimaryProvider = 'claw163';
  String _emailBackupProvider = 'resend';
  String _emailActiveSlot = 'primary';
  final _maxSizeCtrl = TextEditingController(text: '2048');
  final _intervalCtrl = TextEditingController(text: '30');
  final _retainCtrl = TextEditingController(text: '0');
  final _serverIntervalCtrl = TextEditingController(text: '720');
  final _serverRetainCtrl = TextEditingController(text: '14');
  final _openlistUrlCtrl = TextEditingController();
  final _openlistPublicUrlCtrl = TextEditingController();
  final _openlistUserCtrl = TextEditingController();
  final _openlistPasswordCtrl = TextEditingController();
  final _openlistPathCtrl = TextEditingController(text: '/duoyi-backups');
  final _emailToCtrl = TextEditingController();
  final _emailFromCtrl = TextEditingController();
  final _smtpHostCtrl = TextEditingController();
  final _smtpPortCtrl = TextEditingController(text: '465');
  final _smtpUserCtrl = TextEditingController();
  final _smtpPasswordCtrl = TextEditingController();
  final _reminderEmailToCtrl = TextEditingController();
  final _reminderEmailFromCtrl = TextEditingController();
  final _reminderSmtpHostCtrl = TextEditingController();
  final _reminderSmtpPortCtrl = TextEditingController(text: '465');
  final _reminderSmtpUserCtrl = TextEditingController();
  final _reminderSmtpPasswordCtrl = TextEditingController();
  final _emailSenderNameCtrl = TextEditingController(text: '多仪');
  final _openclawMailUserCtrl = TextEditingController();
  final _openclawMailKeyCtrl = TextEditingController();
  final _resendBaseUrlCtrl = TextEditingController();
  final _resendApiKeyCtrl = TextEditingController();
  final _resendFromCtrl = TextEditingController();
  final _systemNoticeEmailCtrl = TextEditingController();
  final _accountSmtpHostCtrl = TextEditingController();
  final _accountSmtpPortCtrl = TextEditingController(text: '465');
  final _accountSmtpUserCtrl = TextEditingController();
  final _accountSmtpPasswordCtrl = TextEditingController();
  bool _openlistPasswordMasked = false;
  bool _smtpPasswordMasked = false;
  bool _reminderSmtpPasswordMasked = false;
  bool _openclawMailKeyMasked = false;
  bool _resendApiKeyMasked = false;
  bool _accountSmtpPasswordMasked = false;

  List<Map<String, dynamic>> _backups = [];
  List<Map<String, dynamic>> _serverBackups = [];
  AdminPage? _backupPage;
  AdminPage? _serverBackupPage;
  int _backupOffset = 0;
  int _serverBackupOffset = 0;
  int _backupPageSize = _adminPageSize;
  int _serverBackupPageSize = _adminPageSize;
  String _backupQuery = '';
  String _serverBackupQuery = '';
  String _backupStatus = '';
  String _serverBackupStatus = '';
  String _backupSort = 'updated_desc';
  String _serverBackupSort = 'created_desc';
  final _backupSearchCtrl = TextEditingController();
  final _serverBackupSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _maxSizeCtrl.dispose();
    _intervalCtrl.dispose();
    _retainCtrl.dispose();
    _serverIntervalCtrl.dispose();
    _serverRetainCtrl.dispose();
    _openlistUrlCtrl.dispose();
    _openlistPublicUrlCtrl.dispose();
    _openlistUserCtrl.dispose();
    _openlistPasswordCtrl.dispose();
    _openlistPathCtrl.dispose();
    _emailToCtrl.dispose();
    _emailFromCtrl.dispose();
    _smtpHostCtrl.dispose();
    _smtpPortCtrl.dispose();
    _smtpUserCtrl.dispose();
    _smtpPasswordCtrl.dispose();
    _reminderEmailToCtrl.dispose();
    _reminderEmailFromCtrl.dispose();
    _reminderSmtpHostCtrl.dispose();
    _reminderSmtpPortCtrl.dispose();
    _reminderSmtpUserCtrl.dispose();
    _reminderSmtpPasswordCtrl.dispose();
    _emailSenderNameCtrl.dispose();
    _openclawMailUserCtrl.dispose();
    _openclawMailKeyCtrl.dispose();
    _resendBaseUrlCtrl.dispose();
    _resendApiKeyCtrl.dispose();
    _resendFromCtrl.dispose();
    _systemNoticeEmailCtrl.dispose();
    _accountSmtpHostCtrl.dispose();
    _accountSmtpPortCtrl.dispose();
    _accountSmtpUserCtrl.dispose();
    _accountSmtpPasswordCtrl.dispose();
    _backupSearchCtrl.dispose();
    _serverBackupSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({
    int? backupOffset,
    int? serverBackupOffset,
    int? backupPageSize,
    int? serverBackupPageSize,
    String? backupQuery,
    String? serverBackupQuery,
    String? backupStatus,
    String? serverBackupStatus,
    String? backupSort,
    String? serverBackupSort,
  }) async {
    final nextBackupOffset = backupOffset ?? _backupOffset;
    final nextServerBackupOffset = serverBackupOffset ?? _serverBackupOffset;
    final nextBackupPageSize = backupPageSize ?? _backupPageSize;
    final nextServerBackupPageSize =
        serverBackupPageSize ?? _serverBackupPageSize;
    final nextBackupQuery = backupQuery ?? _backupQuery;
    final nextServerBackupQuery = serverBackupQuery ?? _serverBackupQuery;
    final nextBackupStatus = backupStatus ?? _backupStatus;
    final nextServerBackupStatus = serverBackupStatus ?? _serverBackupStatus;
    final nextBackupSort = backupSort ?? _backupSort;
    final nextServerBackupSort = serverBackupSort ?? _serverBackupSort;
    _backupOffset = nextBackupOffset;
    _serverBackupOffset = nextServerBackupOffset;
    _backupPageSize = nextBackupPageSize;
    _serverBackupPageSize = nextServerBackupPageSize;
    _backupQuery = nextBackupQuery;
    _serverBackupQuery = nextServerBackupQuery;
    _backupStatus = nextBackupStatus;
    _serverBackupStatus = nextServerBackupStatus;
    _backupSort = nextBackupSort;
    _serverBackupSort = nextServerBackupSort;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.getSettings();
      _backupEnabled = data['backup_enabled'] != false;
      _maxSizeCtrl.text =
          (((data['backup_max_size_kb'] as num?) ?? 2048).toInt()).toString();
      _intervalCtrl.text =
          (((data['backup_interval_minutes'] as num?) ?? 30).toInt())
              .toString();
      _retainCtrl.text = (((data['backup_retain_days'] as num?) ?? 0).toInt())
          .toString();
      _serverBackupEnabled = data['server_backup_enabled'] != false;
      _serverIntervalCtrl.text =
          (((data['server_backup_interval_minutes'] as num?) ?? 720).toInt())
              .toString();
      _serverRetainCtrl.text =
          (((data['server_backup_retain_days'] as num?) ?? 14).toInt())
              .toString();
      _openlistEnabled = data['openlist_backup_enabled'] == true;
      _openlistUrlCtrl.text = (data['openlist_webdav_url'] ?? '').toString();
      _openlistPublicUrlCtrl.text = (data['openlist_public_url'] ?? '')
          .toString();
      _openlistUserCtrl.text = (data['openlist_username'] ?? '').toString();
      _openlistPasswordCtrl.text = (data['openlist_password'] ?? '').toString();
      _openlistPasswordMasked = data['openlist_password_set'] == true;
      _openlistPathCtrl.text =
          (data['openlist_backup_path'] ?? '/duoyi-backups').toString();
      _backupEmailEnabled = data['backup_email_enabled'] == true;
      _emailToCtrl.text = (data['backup_email_to'] ?? '').toString();
      _emailFromCtrl.text = (data['backup_email_from'] ?? '').toString();
      _smtpHostCtrl.text = (data['backup_email_smtp_host'] ?? '').toString();
      _smtpPortCtrl.text =
          (((data['backup_email_smtp_port'] as num?) ?? 465).toInt())
              .toString();
      _smtpUserCtrl.text = (data['backup_email_smtp_username'] ?? '')
          .toString();
      _smtpPasswordCtrl.text = (data['backup_email_smtp_password'] ?? '')
          .toString();
      _smtpPasswordMasked = data['backup_email_smtp_password_set'] == true;
      _reminderEmailEnabled = data['reminder_email_enabled'] == true;
      _reminderEmailToCtrl.text = (data['reminder_email_to'] ?? '').toString();
      _reminderEmailFromCtrl.text = (data['reminder_email_from'] ?? '')
          .toString();
      _reminderSmtpHostCtrl.text = (data['reminder_email_smtp_host'] ?? '')
          .toString();
      _reminderSmtpPortCtrl.text =
          (((data['reminder_email_smtp_port'] as num?) ?? 465).toInt())
              .toString();
      _reminderSmtpUserCtrl.text = (data['reminder_email_smtp_username'] ?? '')
          .toString();
      _reminderSmtpPasswordCtrl.text =
          (data['reminder_email_smtp_password'] ?? '').toString();
      _reminderSmtpPasswordMasked =
          data['reminder_email_smtp_password_set'] == true;
      _accountEmailEnabled = data['email_service_enabled'] != false;
      _emailAutoSwitchEnabled = data['email_auto_switch_enabled'] == true;
      _emailPrimaryProvider = _mailProviderValue(
        data['email_code_primary_provider'],
        fallback: 'claw163',
      );
      _emailBackupProvider = _mailProviderValue(
        data['email_code_backup_provider'],
        fallback: 'resend',
      );
      _emailActiveSlot = data['email_code_active_slot'] == 'backup'
          ? 'backup'
          : 'primary';
      _emailSenderNameCtrl.text = (data['email_sender_name'] ?? '多仪')
          .toString();
      _openclawMailUserCtrl.text = (data['openclaw_mail_user'] ?? '')
          .toString();
      _openclawMailKeyCtrl.text = (data['openclaw_mail_api_key'] ?? '')
          .toString();
      _openclawMailKeyMasked = data['openclaw_mail_api_key_set'] == true;
      _resendBaseUrlCtrl.text =
          (data['resend_base_url'] ?? 'https://api.resend.com').toString();
      _resendApiKeyCtrl.text = (data['resend_api_key'] ?? '').toString();
      _resendApiKeyMasked = data['resend_api_key_set'] == true;
      _resendFromCtrl.text =
          (data['resend_from'] ?? '多仪 <noreply@mail.6688667.xyz>').toString();
      _systemNoticeEmailCtrl.text = (data['system_notice_email_to'] ?? '')
          .toString();
      _accountSmtpHostCtrl.text = (data['email_smtp_host'] ?? '').toString();
      _accountSmtpPortCtrl.text =
          (((data['email_smtp_port'] as num?) ?? 465).toInt()).toString();
      _accountSmtpUserCtrl.text = (data['email_smtp_username'] ?? '')
          .toString();
      _accountSmtpPasswordCtrl.text = (data['email_smtp_password'] ?? '')
          .toString();
      _accountSmtpPasswordMasked = data['email_smtp_password_set'] == true;
      _accountSmtpUseSsl = data['email_smtp_use_ssl'] != false;
      final backupPage = await widget.api.listBackupsPage(
        query: nextBackupQuery.isEmpty ? null : nextBackupQuery,
        status: nextBackupStatus.isEmpty ? null : nextBackupStatus,
        sort: nextBackupSort,
        limit: nextBackupPageSize,
        offset: nextBackupOffset,
      );
      final serverBackupPage = await widget.api.listServerBackupsPage(
        query: nextServerBackupQuery.isEmpty ? null : nextServerBackupQuery,
        status: nextServerBackupStatus.isEmpty ? null : nextServerBackupStatus,
        sort: nextServerBackupSort,
        limit: nextServerBackupPageSize,
        offset: nextServerBackupOffset,
      );
      _backupPage = backupPage;
      _serverBackupPage = serverBackupPage;
      _backups = backupPage.items;
      _serverBackups = serverBackupPage.items;
    } catch (e) {
      _error = _adminErrorMessage(e, '备份配置与备份记录');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final openlistPassword = _openlistPasswordCtrl.text.trim();
      final smtpPassword = _smtpPasswordCtrl.text.trim();
      final reminderSmtpPassword = _reminderSmtpPasswordCtrl.text.trim();
      final openclawMailKey = _openclawMailKeyCtrl.text.trim();
      final resendApiKey = _resendApiKeyCtrl.text.trim();
      final accountSmtpPassword = _accountSmtpPasswordCtrl.text.trim();
      final payload = <String, Object?>{
        'backup_enabled': _backupEnabled,
        'backup_max_size_kb': int.tryParse(_maxSizeCtrl.text.trim()) ?? 2048,
        'backup_interval_minutes':
            int.tryParse(_intervalCtrl.text.trim()) ?? 30,
        'backup_retain_days': int.tryParse(_retainCtrl.text.trim()) ?? 0,
        'server_backup_enabled': _serverBackupEnabled,
        'server_backup_interval_minutes':
            int.tryParse(_serverIntervalCtrl.text.trim()) ?? 720,
        'server_backup_retain_days':
            int.tryParse(_serverRetainCtrl.text.trim()) ?? 14,
        'openlist_backup_enabled': _openlistEnabled,
        'openlist_webdav_url': _openlistUrlCtrl.text.trim(),
        'openlist_public_url': _openlistPublicUrlCtrl.text.trim(),
        'openlist_username': _openlistUserCtrl.text.trim(),
        'openlist_backup_path': _openlistPathCtrl.text.trim(),
        'backup_email_enabled': _backupEmailEnabled,
        'backup_email_to': _emailToCtrl.text.trim(),
        'backup_email_from': _emailFromCtrl.text.trim(),
        'backup_email_smtp_host': _smtpHostCtrl.text.trim(),
        'backup_email_smtp_port':
            int.tryParse(_smtpPortCtrl.text.trim()) ?? 465,
        'backup_email_smtp_username': _smtpUserCtrl.text.trim(),
        'reminder_email_enabled': _reminderEmailEnabled,
        'reminder_email_to': _reminderEmailToCtrl.text.trim(),
        'reminder_email_from': _reminderEmailFromCtrl.text.trim(),
        'reminder_email_smtp_host': _reminderSmtpHostCtrl.text.trim(),
        'reminder_email_smtp_port':
            int.tryParse(_reminderSmtpPortCtrl.text.trim()) ?? 465,
        'reminder_email_smtp_username': _reminderSmtpUserCtrl.text.trim(),
        'email_service_enabled': _accountEmailEnabled,
        'email_sender_name': _emailSenderNameCtrl.text.trim(),
        'email_code_primary_provider': _emailPrimaryProvider,
        'email_code_backup_provider': _emailBackupProvider,
        'email_code_active_slot': _emailActiveSlot,
        'email_auto_switch_enabled': _emailAutoSwitchEnabled,
        'openclaw_mail_enabled':
            _emailPrimaryProvider == 'claw163' ||
            _emailBackupProvider == 'claw163',
        'openclaw_mail_user': _openclawMailUserCtrl.text.trim(),
        'resend_base_url': _resendBaseUrlCtrl.text.trim(),
        'resend_from': _resendFromCtrl.text.trim(),
        'system_notice_email_to': _systemNoticeEmailCtrl.text.trim(),
        'email_smtp_host': _accountSmtpHostCtrl.text.trim(),
        'email_smtp_port':
            int.tryParse(_accountSmtpPortCtrl.text.trim()) ?? 465,
        'email_smtp_username': _accountSmtpUserCtrl.text.trim(),
        'email_smtp_use_ssl': _accountSmtpUseSsl,
      };
      if (!(_openlistPasswordMasked && openlistPassword.contains('***'))) {
        payload['openlist_password'] = openlistPassword;
      }
      if (!(_smtpPasswordMasked && smtpPassword.contains('***'))) {
        payload['backup_email_smtp_password'] = smtpPassword;
      }
      if (!(_reminderSmtpPasswordMasked &&
          reminderSmtpPassword.contains('***'))) {
        payload['reminder_email_smtp_password'] = reminderSmtpPassword;
      }
      if (!(_openclawMailKeyMasked && openclawMailKey.contains('***'))) {
        payload['openclaw_mail_api_key'] = openclawMailKey;
      }
      if (!(_resendApiKeyMasked && resendApiKey.contains('***'))) {
        payload['resend_api_key'] = resendApiKey;
      }
      if (!(_accountSmtpPasswordMasked &&
          accountSmtpPassword.contains('***'))) {
        payload['email_smtp_password'] = accountSmtpPassword;
      }
      await widget.api.client.patch('/api/admin/settings', payload);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('云端备份配置已保存')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _runServerBackup() async {
    setState(() => _runningServerBackup = true);
    try {
      await widget.api.runServerBackup();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('服务器备份已执行')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _runningServerBackup = false);
    }
  }

  Future<void> _testReminderEmail() async {
    setState(() => _testingReminderEmail = true);
    try {
      final res = await widget.api.testReminderEmail();
      if (mounted) {
        final recipient = (res['recipient'] ?? '').toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              recipient.isEmpty ? '测试邮件已发送' : '测试邮件已发送到 $recipient',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _testingReminderEmail = false);
    }
  }

  Future<void> _testAccountEmail() async {
    setState(() => _testingAccountEmail = true);
    try {
      final res = await widget.api.testAccountEmail();
      if (mounted) {
        final recipient = (res['recipient'] ?? '').toString();
        final provider = (res['provider'] ?? '').toString();
        final channel = provider.isEmpty ? '' : ' · $provider';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              recipient.isEmpty
                  ? '账号测试邮件已发送$channel'
                  : '账号测试邮件已发送到 $recipient$channel',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _testingAccountEmail = false);
    }
  }

  String _mailProviderValue(Object? value, {required String fallback}) {
    final raw = (value ?? fallback).toString().trim().toLowerCase();
    final normalized = switch (raw) {
      'openclaw' || 'openclaw_mail' => 'claw163',
      _ => raw,
    };
    return {'claw163', 'resend', 'smtp', 'none'}.contains(normalized)
        ? normalized
        : fallback;
  }

  List<DropdownMenuItem<String>> _mailProviderItems() => const [
    DropdownMenuItem(value: 'claw163', child: Text('Claw163')),
    DropdownMenuItem(value: 'resend', child: Text('Resend')),
    DropdownMenuItem(value: 'smtp', child: Text('SMTP')),
    DropdownMenuItem(value: 'none', child: Text('关闭')),
  ];

  Future<void> _wipe(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text('清空 ${row['username']} 的云端备份?'),
        icon: const Icon(Icons.cloud_off_outlined),
        content: const Text('账号保留，但服务器上的同步数据会清零，用户下次同步后本地数据将被覆盖。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.wipeBackup(row['user_id'].toString());
      final nextOffset = _backups.length == 1 && _backupOffset > 0
          ? (_backupOffset - _backupPageSize).clamp(0, _backupOffset)
          : _backupOffset;
      await _load(backupOffset: nextOffset);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _exportBackupsCsv() async {
    setState(() => _exportingBackups = true);
    try {
      final csv = await widget.api.exportBackupsCsv(
        query: _backupQuery.isEmpty ? null : _backupQuery,
        status: _backupStatus.isEmpty ? null : _backupStatus,
        sort: _backupSort,
      );
      await _shareAdminCsv(
        csv,
        prefix: 'duoyi_backups',
        text: '多仪用户备份导出',
        subject: '多仪用户备份 CSV',
        successLabel: '用户备份 CSV 已导出',
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _exportingBackups = false);
    }
  }

  Future<void> _exportServerBackupsCsv() async {
    setState(() => _exportingServerBackups = true);
    try {
      final csv = await widget.api.exportServerBackupsCsv(
        query: _serverBackupQuery.isEmpty ? null : _serverBackupQuery,
        status: _serverBackupStatus.isEmpty ? null : _serverBackupStatus,
        sort: _serverBackupSort,
      );
      await _shareAdminCsv(
        csv,
        prefix: 'duoyi_server_backups',
        text: '多仪服务器备份导出',
        subject: '多仪服务器备份 CSV',
        successLabel: '服务器备份 CSV 已导出',
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _exportingServerBackups = false);
    }
  }

  Future<void> _shareAdminCsv(
    String csv, {
    required String prefix,
    required String text,
    required String subject,
    required String successLabel,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    await file.writeAsString(csv, flush: true);
    await Clipboard.setData(ClipboardData(text: file.path));
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: text, subject: subject),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$successLabel，路径已复制：${file.path}')));
  }

  Widget _backupStatusChip(String label, String value) {
    final selected = _backupStatus == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _load(backupStatus: value, backupOffset: 0),
      ),
    );
  }

  Widget _serverBackupStatusChip(String label, String value) {
    final selected = _serverBackupStatus == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) =>
            _load(serverBackupStatus: value, serverBackupOffset: 0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _AdminErrorState(message: _error!, onRetry: () => _load());
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final totalKb = _backups.fold<int>(
      0,
      (s, e) => s + ((e['size_kb'] as int?) ?? 0),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppSettingsSection(
          title: '云端备份',
          subtitle: '限制同步体积、频率与服务开关',
          children: [
            AppSwitchTile(
              icon: Icons.cloud_sync_outlined,
              color: cs.primary,
              value: _backupEnabled,
              title: '启用云端备份',
              subtitle: '关闭后所有 /api/sync 请求会被拒绝',
              onChanged: (v) => setState(() => _backupEnabled = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _maxSizeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '单用户同步大小上限 (KB)',
                helperText: '0 = 不限，默认 2048',
                prefixIcon: Icon(Icons.storage_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _intervalCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '客户端最小自动同步间隔 (分钟)',
                helperText: '用于客户端回退策略参考',
                prefixIcon: Icon(Icons.update_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _retainCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '备份历史保留天数',
                helperText: '0 = 永久保留 (当前后端仅保留最新快照)',
                prefixIcon: Icon(Icons.history_outlined),
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? '保存中…' : '保存'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppSettingsSection(
          title: '服务器备份',
          subtitle: '定期打包后台数据库，上传到 OpenList，并可邮件通知',
          children: [
            AppSwitchTile(
              icon: Icons.dns_outlined,
              color: Colors.indigo,
              value: _serverBackupEnabled,
              title: '启用服务器定期备份',
              subtitle: '后台进程按间隔生成数据库 ZIP 快照',
              onChanged: (v) => setState(() => _serverBackupEnabled = v),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _serverIntervalCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '服务器备份间隔 (分钟)',
                      prefixIcon: Icon(Icons.schedule_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _serverRetainCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '本地保留天数',
                      prefixIcon: Icon(Icons.history_toggle_off_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppSwitchTile(
              icon: Icons.cloud_upload_outlined,
              color: Colors.blue,
              value: _openlistEnabled,
              title: '上传到 OpenList',
              subtitle: '使用 OpenList WebDAV 保存服务器备份包',
              onChanged: (v) => setState(() => _openlistEnabled = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _openlistUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'OpenList WebDAV URL',
                hintText: 'http://127.0.0.1:5244/dav',
                prefixIcon: Icon(Icons.link_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _openlistPublicUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'OpenList 公开 URL (可选)',
                prefixIcon: Icon(Icons.public_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _openlistUserCtrl,
                    decoration: const InputDecoration(
                      labelText: 'OpenList 用户名',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _openlistPasswordCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'OpenList 密码',
                      helperText: _openlistPasswordMasked
                          ? '已配置，保持不动即不修改'
                          : null,
                      prefixIcon: const Icon(Icons.password_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _openlistPathCtrl,
              decoration: const InputDecoration(
                labelText: 'OpenList 备份目录',
                hintText: '/duoyi-backups',
                prefixIcon: Icon(Icons.folder_outlined),
              ),
            ),
            const SizedBox(height: 12),
            AppSwitchTile(
              icon: Icons.mark_email_read_outlined,
              color: Colors.teal,
              value: _backupEmailEnabled,
              title: '备份完成后发送邮件',
              subtitle: '支持 SMTP，失败会写入备份记录',
              onChanged: (v) => setState(() => _backupEmailEnabled = v),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailToCtrl,
                    decoration: const InputDecoration(
                      labelText: '通知收件人',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _emailFromCtrl,
                    decoration: const InputDecoration(
                      labelText: '发件人',
                      prefixIcon: Icon(Icons.outgoing_mail),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _smtpHostCtrl,
              decoration: const InputDecoration(
                labelText: 'SMTP Host',
                prefixIcon: Icon(Icons.dns_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _smtpPortCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'SMTP 端口',
                      prefixIcon: Icon(Icons.numbers_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _smtpUserCtrl,
                    decoration: const InputDecoration(
                      labelText: 'SMTP 用户名',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _smtpPasswordCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'SMTP 密码',
                helperText: _smtpPasswordMasked ? '已配置，保持不动即不修改' : null,
                prefixIcon: const Icon(Icons.key_outlined),
              ),
            ),
            const SizedBox(height: 16),
            AppSwitchTile(
              icon: Icons.mark_email_read_outlined,
              color: Colors.indigo,
              value: _accountEmailEnabled,
              title: '账号验证码邮件',
              subtitle: '注册验证、邮箱登录和找回密码共用主备通道',
              onChanged: (v) => setState(() => _accountEmailEnabled = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emailSenderNameCtrl,
              decoration: const InputDecoration(
                labelText: '账号邮件发件人显示名',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _emailPrimaryProvider,
                    decoration: const InputDecoration(
                      labelText: '主通道',
                      prefixIcon: Icon(Icons.route_outlined),
                    ),
                    items: _mailProviderItems(),
                    onChanged: (v) =>
                        setState(() => _emailPrimaryProvider = v ?? 'claw163'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _emailBackupProvider,
                    decoration: const InputDecoration(
                      labelText: '备用通道',
                      prefixIcon: Icon(Icons.alt_route_outlined),
                    ),
                    items: _mailProviderItems(),
                    onChanged: (v) =>
                        setState(() => _emailBackupProvider = v ?? 'resend'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _emailActiveSlot,
                    decoration: const InputDecoration(
                      labelText: '当前优先线路',
                      prefixIcon: Icon(Icons.swap_horiz_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'primary', child: Text('主通道')),
                      DropdownMenuItem(value: 'backup', child: Text('备用通道')),
                    ],
                    onChanged: (v) =>
                        setState(() => _emailActiveSlot = v ?? 'primary'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('备用成功后自动切换'),
                    value: _emailAutoSwitchEnabled,
                    onChanged: (v) =>
                        setState(() => _emailAutoSwitchEnabled = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _openclawMailUserCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Claw163 发件邮箱',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _openclawMailKeyCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Claw163 API Key',
                      helperText: _openclawMailKeyMasked
                          ? '已配置，保持不动即不修改'
                          : null,
                      prefixIcon: const Icon(Icons.key_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _resendBaseUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'Resend Base URL',
                hintText: 'https://api.resend.com',
                prefixIcon: Icon(Icons.link_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _resendApiKeyCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Resend API Key',
                      helperText: _resendApiKeyMasked ? '已配置，保持不动即不修改' : null,
                      prefixIcon: const Icon(Icons.key_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _resendFromCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Resend 发件人',
                      prefixIcon: Icon(Icons.outgoing_mail),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _systemNoticeEmailCtrl,
              decoration: const InputDecoration(
                labelText: '系统通知收件人',
                helperText: '多个邮箱用逗号分隔',
                prefixIcon: Icon(Icons.notifications_active_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _accountSmtpHostCtrl,
              decoration: const InputDecoration(
                labelText: '账号 SMTP Host',
                prefixIcon: Icon(Icons.dns_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _accountSmtpPortCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '账号 SMTP 端口',
                      prefixIcon: Icon(Icons.numbers_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _accountSmtpUserCtrl,
                    decoration: const InputDecoration(
                      labelText: '账号 SMTP 用户名',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _accountSmtpPasswordCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: '账号 SMTP 密码',
                helperText: _accountSmtpPasswordMasked ? '已配置，保持不动即不修改' : null,
                prefixIcon: const Icon(Icons.key_outlined),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('账号 SMTP 使用 SSL'),
              value: _accountSmtpUseSsl,
              onChanged: (v) => setState(() => _accountSmtpUseSsl = v),
            ),
            const SizedBox(height: 16),
            AppSwitchTile(
              icon: Icons.alternate_email_outlined,
              color: Colors.deepPurple,
              value: _reminderEmailEnabled,
              title: '邮件提醒投递',
              subtitle: '待办/目标的“邮件”提醒会按计划写入后端 SMTP 队列',
              onChanged: (v) => setState(() => _reminderEmailEnabled = v),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _reminderEmailToCtrl,
                    decoration: const InputDecoration(
                      labelText: '默认提醒收件人',
                      helperText: '用户登录名是邮箱时优先投递给该用户',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _reminderEmailFromCtrl,
                    decoration: const InputDecoration(
                      labelText: '提醒发件人',
                      prefixIcon: Icon(Icons.outgoing_mail),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reminderSmtpHostCtrl,
              decoration: const InputDecoration(
                labelText: '提醒 SMTP Host',
                prefixIcon: Icon(Icons.dns_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _reminderSmtpPortCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '提醒 SMTP 端口',
                      prefixIcon: Icon(Icons.numbers_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _reminderSmtpUserCtrl,
                    decoration: const InputDecoration(
                      labelText: '提醒 SMTP 用户名',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reminderSmtpPasswordCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: '提醒 SMTP 密码',
                helperText: _reminderSmtpPasswordMasked ? '已配置，保持不动即不修改' : null,
                prefixIcon: const Icon(Icons.key_outlined),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? '保存中…' : '保存配置'),
                ),
                OutlinedButton.icon(
                  onPressed: _runningServerBackup ? null : _runServerBackup,
                  icon: _runningServerBackup
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.backup_outlined),
                  label: Text(_runningServerBackup ? '备份中…' : '立即备份'),
                ),
                OutlinedButton.icon(
                  onPressed: _testingReminderEmail ? null : _testReminderEmail,
                  icon: _testingReminderEmail
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.mark_email_read_outlined),
                  label: Text(_testingReminderEmail ? '发送中…' : '测试提醒邮件'),
                ),
                OutlinedButton.icon(
                  onPressed: _testingAccountEmail ? null : _testAccountEmail,
                  icon: _testingAccountEmail
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.alternate_email_outlined),
                  label: Text(_testingAccountEmail ? '发送中…' : '测试账号邮件'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppSectionHeader(
          title: '服务器备份记录',
          subtitle: _adminPageSummary(_serverBackupPage),
          actionLabel: _exportingServerBackups ? '导出中…' : '导出筛选结果',
          actionIcon: Icons.ios_share_outlined,
          onAction: _exportingServerBackups ? null : _exportServerBackupsCsv,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _loading
                ? null
                : () => _load(serverBackupOffset: _serverBackupOffset),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('刷新'),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _serverBackupSearchCtrl,
          decoration: InputDecoration(
            hintText: '搜索文件名、状态、路径或详情',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _serverBackupQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: '清空服务器备份搜索',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _serverBackupSearchCtrl.clear();
                      _load(serverBackupQuery: '', serverBackupOffset: 0);
                    },
                  ),
            isDense: true,
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _load(
            serverBackupQuery: _serverBackupSearchCtrl.text.trim(),
            serverBackupOffset: 0,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _serverBackupStatusChip('全部备份', ''),
              _serverBackupStatusChip('已上传', 'uploaded'),
              _serverBackupStatusChip('仅本地', 'local_only'),
              _serverBackupStatusChip('远端失败', 'local_created_remote_failed'),
              _serverBackupStatusChip('已创建', 'created'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        AppDropdownField<String>(
          initialValue: _serverBackupSort,
          labelText: '服务器备份排序',
          items: const [
            DropdownMenuItem(value: 'created_desc', child: Text('最新生成优先')),
            DropdownMenuItem(value: 'size_desc', child: Text('文件从大到小')),
            DropdownMenuItem(value: 'size_asc', child: Text('文件从小到大')),
            DropdownMenuItem(value: 'status_asc', child: Text('状态 A-Z')),
            DropdownMenuItem(value: 'filename_asc', child: Text('文件名 A-Z')),
          ],
          onChanged: (value) => _load(
            serverBackupSort: value ?? 'created_desc',
            serverBackupOffset: 0,
          ),
        ),
        const SizedBox(height: 6),
        if (_serverBackups.isEmpty)
          Text(
            '当前筛选下没有服务器备份记录。可搜索文件名、状态、路径或详情，也可以切换状态后再看。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.58),
            ),
          ),
        ..._serverBackups.map((b) {
          final status = (b['status'] ?? '-').toString();
          return AppListTileCard(
            margin: const EdgeInsets.only(bottom: 8),
            dense: true,
            leading: Icon(Icons.backup_outlined, color: cs.primary),
            title: Text((b['filename'] ?? '-').toString()),
            subtitle: Text(
              '${b['created_at'] ?? '-'} · ${_adminStatusLabel(status)} · ${b['size_bytes'] ?? 0} bytes · 排序: ${_adminServerBackupSortLabel(_serverBackupSort)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.62),
              ),
            ),
          );
        }),
        _AdminPaginationBar(
          page: _serverBackupPage,
          loading: _loading,
          pageSize: _serverBackupPageSize,
          onPageSizeChanged: (value) =>
              _load(serverBackupPageSize: value, serverBackupOffset: 0),
          onPrevious: () => _load(
            serverBackupOffset: (_serverBackupOffset - _serverBackupPageSize)
                .clamp(0, _serverBackupOffset),
          ),
          onNext: () => _load(
            serverBackupOffset: _serverBackupOffset + _serverBackupPageSize,
          ),
          onJumpToPage: (page) =>
              _load(serverBackupOffset: (page - 1) * _serverBackupPageSize),
        ),
        const SizedBox(height: 12),
        AppSectionHeader(
          title: '所有用户备份',
          subtitle:
              '${_adminPageSummary(_backupPage)} · 本页 ${(totalKb / 1024).toStringAsFixed(1)} MB',
          actionLabel: _exportingBackups ? '导出中…' : '导出筛选结果',
          actionIcon: Icons.ios_share_outlined,
          onAction: _exportingBackups ? null : _exportBackupsCsv,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _loading
                ? null
                : () => _load(backupOffset: _backupOffset),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('刷新'),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _backupSearchCtrl,
          decoration: InputDecoration(
            hintText: '搜索用户名、邮箱、昵称或用户 ID',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _backupQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: '清空用户备份搜索',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _backupSearchCtrl.clear();
                      _load(backupQuery: '', backupOffset: 0);
                    },
                  ),
            isDense: true,
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _load(
            backupQuery: _backupSearchCtrl.text.trim(),
            backupOffset: 0,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _backupStatusChip('全部用户', ''),
              _backupStatusChip('已有快照', 'synced'),
              _backupStatusChip('无快照', 'empty'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        AppDropdownField<String>(
          initialValue: _backupSort,
          labelText: '用户备份排序',
          items: const [
            DropdownMenuItem(value: 'updated_desc', child: Text('最近同步优先')),
            DropdownMenuItem(value: 'username_asc', child: Text('用户名 A-Z')),
            DropdownMenuItem(value: 'size_desc', child: Text('备份体积从大到小')),
            DropdownMenuItem(value: 'size_asc', child: Text('备份体积从小到大')),
            DropdownMenuItem(value: 'version_desc', child: Text('同步版本较高优先')),
          ],
          onChanged: (value) =>
              _load(backupSort: value ?? 'updated_desc', backupOffset: 0),
        ),
        const SizedBox(height: 6),
        if (_backups.isEmpty)
          Text(
            '当前筛选下没有用户备份。可搜索用户名、邮箱、昵称或用户 ID，也可以切换“已有快照/无快照”。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.58),
            ),
          ),
        ..._backups.map((b) {
          final email = (b['email'] ?? '').toString();
          final displayName = (b['display_name'] ?? '').toString();
          final hasSnapshot = b['has_snapshot'] == true;
          final updated = hasSnapshot
              ? (b['updated_at'] ?? '尚无同步时间').toString()
              : '尚无同步快照';
          return AppListTileCard(
            margin: const EdgeInsets.only(bottom: 8),
            dense: true,
            leading: Icon(Icons.cloud_done_outlined, color: cs.primary),
            title: Text(b['username'].toString()),
            subtitle: Text(
              [
                if (displayName.isNotEmpty) '昵称: $displayName',
                if (email.isNotEmpty) '邮箱: $email',
                updated,
                '版本 ${b['sync_version'] ?? 0}',
                '${b['size_kb']} KB',
                '排序: ${_adminBackupSortLabel(_backupSort)}',
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.62),
              ),
            ),
            trailing: IconButton(
              tooltip: '清空备份',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _wipe(b),
            ),
          );
        }),
        _AdminPaginationBar(
          page: _backupPage,
          loading: _loading,
          pageSize: _backupPageSize,
          onPageSizeChanged: (value) =>
              _load(backupPageSize: value, backupOffset: 0),
          onPrevious: () => _load(
            backupOffset: (_backupOffset - _backupPageSize).clamp(
              0,
              _backupOffset,
            ),
          ),
          onNext: () => _load(backupOffset: _backupOffset + _backupPageSize),
          onJumpToPage: (page) =>
              _load(backupOffset: (page - 1) * _backupPageSize),
        ),
      ],
    );
  }
}

// ====================================================================
// 用户
// ====================================================================

class _UsersTab extends StatefulWidget {
  final AdminApi api;
  final String? selfId;
  const _UsersTab({required this.api, required this.selfId});
  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  static const _onlineRefreshInterval = Duration(seconds: 60);

  List<Map<String, dynamic>> _users = [];
  AdminPage? _page;
  bool _loading = true;
  String? _error;
  String _query = '';
  String _status = '';
  String _sort = 'created_desc';
  int _pageSize = _adminPageSize;
  int _offset = 0;
  final Set<String> _selectedUserIds = <String>{};
  Timer? _onlineRefreshTimer;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _onlineRefreshTimer = Timer.periodic(_onlineRefreshInterval, (_) {
      if (!mounted || _loading) return;
      _load(quiet: true);
    });
  }

  @override
  void dispose() {
    _onlineRefreshTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({
    String? query,
    String? status,
    String? sort,
    int? pageSize,
    int? offset,
    bool quiet = false,
  }) async {
    final nextQuery = query ?? _query;
    final nextStatus = status ?? _status;
    final nextSort = sort ?? _sort;
    final nextPageSize = pageSize ?? _pageSize;
    final nextOffset = offset ?? _offset;
    _query = nextQuery;
    _status = nextStatus;
    _sort = nextSort;
    _pageSize = nextPageSize;
    _offset = nextOffset;
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await widget.api.listUsersPage(
        query: nextQuery.isEmpty ? null : nextQuery,
        status: _backendStatusFilter(nextStatus),
        online: _onlineFilter(nextStatus),
        sort: nextSort,
        limit: nextPageSize,
        offset: nextOffset,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _users = page.items;
        _selectedUserIds.removeWhere(
          (id) => !_users.any((u) => u['user_id'].toString() == id),
        );
        _error = null;
      });
    } catch (e) {
      if (!quiet) {
        _error = _adminErrorMessage(e, '用户列表');
      }
    } finally {
      if (mounted && !quiet) setState(() => _loading = false);
    }
  }

  void _applySearch() {
    _load(query: _searchCtrl.text.trim(), offset: 0);
  }

  void _applyStatus(String status) {
    setState(() => _status = status);
    _load(status: status, offset: 0);
  }

  void _applySort(String sort) {
    _load(sort: sort, offset: 0);
  }

  void _jumpToPage(int pageNumber) {
    final page = pageNumber < 1 ? 1 : pageNumber;
    _load(offset: (page - 1) * _pageSize);
  }

  bool? _onlineFilter(String status) {
    if (status == 'online') return true;
    if (status == 'offline') return false;
    return null;
  }

  String? _backendStatusFilter(String status) {
    if (status.isEmpty || status == 'online' || status == 'offline') {
      return null;
    }
    return status;
  }

  Future<void> _toggleAdmin(Map<String, dynamic> u) async {
    final becomeAdmin = !(u['is_admin'] == true);
    try {
      await widget.api.updateUser(u['user_id'], isAdmin: becomeAdmin);
      u['is_admin'] = becomeAdmin;
      await _load(quiet: true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _toggleDisable(Map<String, dynamic> u) async {
    final disable = !(u['is_disabled'] == true);
    try {
      await widget.api.updateUser(u['user_id'], isDisabled: disable);
      u['is_disabled'] = disable;
      await _load(quiet: true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _exportUsersCsv() async {
    try {
      final csv = await widget.api.exportUsersCsv(
        query: _query.isEmpty ? null : _query,
        status: _backendStatusFilter(_status),
        online: _onlineFilter(_status),
        sort: _sort,
      );
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/duoyi_users_${DateTime.now().millisecondsSinceEpoch}.csv',
      );
      await file.writeAsString(csv, flush: true);
      await Clipboard.setData(ClipboardData(text: file.path));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: '多仪管理员用户导出',
          subject: '多仪用户 CSV',
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('用户 CSV 已导出，路径已复制：${file.path}')));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  List<String> get _selectableCurrentPageUserIds => _users
      .map((u) => u['user_id'].toString())
      .where((id) => id.isNotEmpty && id != widget.selfId)
      .toList();

  List<String> get _selectedCurrentPageUserIds =>
      _selectableCurrentPageUserIds.where(_selectedUserIds.contains).toList();

  void _toggleUserSelection(String userId, bool selected) {
    setState(() {
      if (selected) {
        _selectedUserIds.add(userId);
      } else {
        _selectedUserIds.remove(userId);
      }
    });
  }

  void _toggleCurrentPageSelection(bool selected) {
    setState(() {
      final ids = _selectableCurrentPageUserIds;
      if (selected) {
        _selectedUserIds.addAll(ids);
      } else {
        _selectedUserIds.removeAll(ids);
      }
    });
  }

  Future<void> _bulkSetDisabled(bool disabled) async {
    final ids = _selectedCurrentPageUserIds;
    if (ids.isEmpty) return;
    final ok = await _confirmAdminDangerAction(
      context: context,
      title: disabled ? '批量禁用账号？' : '批量恢复账号？',
      message: disabled
          ? '将禁用当前页已选的 ${ids.length} 个账号，并使这些账号需要重新登录。'
          : '将恢复当前页已选的 ${ids.length} 个账号登录权限。',
      confirmLabel: disabled ? '禁用' : '恢复',
    );
    if (!ok) return;
    try {
      await widget.api.bulkUpdateUserStatus(userIds: ids, isDisabled: disabled);
      _selectedUserIds.removeAll(ids);
      await _load(offset: _offset);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            disabled ? '已批量禁用 ${ids.length} 个账号' : '已批量恢复 ${ids.length} 个账号',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _resetPassword(Map<String, dynamic> u) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text('重置 ${u['username']} 的密码'),
        icon: const Icon(Icons.lock_reset_outlined),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: '新密码'),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('提交'),
          ),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      await widget.api.updateUser(u['user_id'], newPassword: ctrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('密码已重置，该用户需重新登录')));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text('删除 ${u['username']} ?'),
        icon: const Icon(Icons.delete_outline),
        content: const Text('会同时删除其所有同步数据与反馈，不可恢复'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteUser(u['user_id']);
      await _load(
        offset: _offsetAfterAdminDelete(
          offset: _offset,
          itemCount: _users.length,
          pageSize: _pageSize,
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  String _formatServerTime(dynamic raw) {
    final text = raw?.toString() ?? '';
    if (text.isEmpty || text == 'null') return '-';
    var normalized = text.contains('T') ? text : text.replaceFirst(' ', 'T');
    final hasTimezone = RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(normalized);
    if (!hasTimezone) normalized = '${normalized}Z';
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) return text;
    final local = parsed.toLocal();
    return I18nDateFormat.fullDateTime(local);
  }

  String _formatLastLogin(dynamic raw) {
    final formatted = _formatServerTime(raw);
    return formatted == '-' ? '从未登录' : formatted;
  }

  String _formatLastActive(dynamic raw) {
    final formatted = _formatServerTime(raw);
    return formatted == '-' ? '从未活跃' : formatted;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loadingFirstPage = _loading && _page == null;
    final selectableIds = _selectableCurrentPageUserIds;
    final selectedIds = _selectedCurrentPageUserIds;
    final allCurrentPageSelected =
        selectableIds.isNotEmpty && selectedIds.length == selectableIds.length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: '搜索用户名、邮箱、昵称或用户 ID',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '清空搜索',
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _load(query: '', offset: 0);
                                },
                              ),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _applySearch(),
                    ),
                  ),
                  IconButton(
                    tooltip: '搜索用户',
                    onPressed: _applySearch,
                    icon: const Icon(Icons.manage_search),
                  ),
                  IconButton(
                    tooltip: '导出用户筛选结果',
                    onPressed: _loading ? null : _exportUsersCsv,
                    icon: const Icon(Icons.download_outlined),
                  ),
                  IconButton(
                    tooltip: '刷新用户列表',
                    onPressed: _loading ? null : () => _load(offset: _offset),
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _userFilterChip('全部账号', ''),
                    _userFilterChip('可登录', 'active'),
                    _userFilterChip('在线', 'online'),
                    _userFilterChip('离线', 'offline'),
                    _userFilterChip('管理员', 'admin'),
                    _userFilterChip('已禁用', 'disabled'),
                    _userFilterChip('普通用户', 'normal'),
                    _userFilterChip('有反馈', 'has_feedback'),
                    _userFilterChip('邮箱未验证', 'unverified_email'),
                    _userFilterChip('邮箱已验证', 'verified_email'),
                    _userFilterChip('未绑定邮箱', 'no_email'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              AppDropdownField<String>(
                initialValue: _sort,
                labelText: '排序',
                items: const [
                  DropdownMenuItem(
                    value: 'created_desc',
                    child: Text('最新注册优先'),
                  ),
                  DropdownMenuItem(
                    value: 'last_active_desc',
                    child: Text('最近活跃优先'),
                  ),
                  DropdownMenuItem(
                    value: 'last_login_desc',
                    child: Text('最近登录优先'),
                  ),
                  DropdownMenuItem(
                    value: 'feedback_desc',
                    child: Text('反馈较多优先'),
                  ),
                  DropdownMenuItem(
                    value: 'username_asc',
                    child: Text('用户名 A-Z'),
                  ),
                  DropdownMenuItem(value: 'email_asc', child: Text('邮箱 A-Z')),
                ],
                onChanged: (value) => _applySort(value ?? 'created_desc'),
              ),
              if (!loadingFirstPage && _error == null && _users.isNotEmpty) ...[
                const SizedBox(height: 8),
                AppSurfaceCard(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  color: cs.secondaryContainer.withValues(alpha: 0.26),
                  border: Border.all(
                    color: cs.secondary.withValues(alpha: 0.16),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final summary = Text(
                        selectedIds.isEmpty
                            ? '本页 ${_users.length} 个账号 · 可勾选后批量禁用或恢复'
                            : '已选 ${selectedIds.length} 个账号 · 批量操作仅作用于当前页勾选项',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.68),
                        ),
                      );
                      final actions = Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilterChip(
                            label: Text(
                              allCurrentPageSelected ? '取消全选本页' : '全选本页',
                            ),
                            selected: allCurrentPageSelected,
                            onSelected: selectableIds.isEmpty
                                ? null
                                : (_) => _toggleCurrentPageSelection(
                                    !allCurrentPageSelected,
                                  ),
                          ),
                          TextButton.icon(
                            onPressed: selectedIds.isEmpty || _loading
                                ? null
                                : () => _bulkSetDisabled(true),
                            icon: const Icon(Icons.block_outlined),
                            label: const Text('批量禁用'),
                          ),
                          TextButton.icon(
                            onPressed: selectedIds.isEmpty || _loading
                                ? null
                                : () => _bulkSetDisabled(false),
                            icon: const Icon(Icons.lock_open_outlined),
                            label: const Text('批量恢复'),
                          ),
                        ],
                      );
                      if (constraints.maxWidth < 560) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            summary,
                            const SizedBox(height: 6),
                            actions,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: summary),
                          actions,
                        ],
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        if (loadingFirstPage)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('正在加载用户列表…'),
                ],
              ),
            ),
          )
        else if (_error != null)
          Expanded(
            child: _AdminErrorState(
              message: _error!,
              onRetry: () => _load(offset: _offset),
            ),
          )
        else if (_users.isEmpty)
          Expanded(
            child: EmptyState(
              icon: Icons.people_outline,
              message: _query.isEmpty && _status.isEmpty
                  ? '暂无用户记录'
                  : '没有匹配的用户。请调整搜索关键词或账号状态筛选。',
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(offset: _offset),
              child: ListView.separated(
                padding: const EdgeInsets.all(8),
                itemCount: _users.length,
                separatorBuilder: (context, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final u = _users[i];
                  final userId = u['user_id'].toString();
                  final isSelf = userId == widget.selfId;
                  final disabled = u['is_disabled'] == true;
                  final admin = u['is_admin'] == true;
                  final online = u['online'] == true;
                  final selected = _selectedUserIds.contains(userId);
                  final registeredAt = _formatServerTime(u['created_at']);
                  final lastLoginAt = _formatLastLogin(u['last_login_at']);
                  final lastActiveAt = _formatLastActive(u['last_active_at']);
                  final email = (u['email'] ?? '').toString();
                  final emailVerified = u['email_verified'] == true;
                  final displayName = (u['display_name'] ?? '').toString();
                  final identityParts = [
                    if (displayName.isNotEmpty) '昵称: $displayName',
                    if (email.isNotEmpty)
                      '邮箱: $email${emailVerified ? ' (已验证)' : ' (未验证)'}'
                    else
                      '未绑定邮箱',
                    '排序: ${_adminUserSortLabel(_sort)}',
                  ];
                  return AppListTileCard(
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: selected,
                          onChanged: isSelf
                              ? null
                              : (value) =>
                                    _toggleUserSelection(userId, value == true),
                        ),
                        CircleAvatar(
                          backgroundColor: admin
                              ? Colors.deepOrange.withValues(alpha: 0.2)
                              : cs.primary.withValues(alpha: 0.12),
                          foregroundColor: admin
                              ? Colors.deepOrange
                              : cs.primary,
                          child: Text(
                            (u['username'] as String? ?? '?').isEmpty
                                ? '?'
                                : u['username'].toString().substring(0, 1),
                          ),
                        ),
                      ],
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            u['username'].toString(),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w400,
                              decoration: disabled
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        AppStatusBadge(
                          label: online ? '在线' : '离线',
                          color: online ? Colors.green : Colors.grey,
                          icon: online
                              ? Icons.circle
                              : Icons.radio_button_unchecked,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                        ),
                        if (admin) ...[
                          const SizedBox(width: 6),
                          const AppStatusBadge(
                            label: '管理员',
                            color: Colors.deepOrange,
                          ),
                        ],
                        if (disabled) ...[
                          const SizedBox(width: 6),
                          const AppStatusBadge(label: '已禁用', color: Colors.red),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      '${identityParts.join(' · ')}\n注册: $registeredAt · 最近登录: $lastLoginAt · 最近活跃: $lastActiveAt · 反馈: ${u['feedback_count'] ?? 0}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) async {
                        switch (action) {
                          case 'admin':
                            await _toggleAdmin(u);
                            break;
                          case 'disable':
                            await _toggleDisable(u);
                            break;
                          case 'reset':
                            await _resetPassword(u);
                            break;
                          case 'delete':
                            await _delete(u);
                            break;
                          case 'copy_id':
                            await Clipboard.setData(
                              ClipboardData(text: u['user_id'].toString()),
                            );
                            if (!context.mounted) return;
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('用户 ID 已复制')),
                              );
                            }
                            break;
                        }
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'admin',
                          child: Text(admin ? '撤销管理员权限' : '授予管理员权限'),
                        ),
                        PopupMenuItem(
                          value: 'disable',
                          child: Text(disabled ? '恢复账号登录' : '禁用账号登录'),
                        ),
                        const PopupMenuItem(
                          value: 'reset',
                          child: Text('重置登录密码'),
                        ),
                        const PopupMenuItem(
                          value: 'copy_id',
                          child: Text('复制用户 ID'),
                        ),
                        if (!isSelf)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text(
                              '删除账号与数据',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        _AdminPaginationBar(
          page: _page,
          loading: _loading,
          pageSize: _pageSize,
          onPageSizeChanged: (value) => _load(pageSize: value, offset: 0),
          onPrevious: () =>
              _load(offset: _previousAdminOffset(_offset, _pageSize)),
          onNext: () => _load(offset: _offset + _pageSize),
          onJumpToPage: _jumpToPage,
        ),
      ],
    );
  }

  Widget _userFilterChip(String label, String value) {
    final selected = _status == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _applyStatus(value),
      ),
    );
  }
}

// ====================================================================
// 公告
// ====================================================================

class _AnnouncementsTab extends StatefulWidget {
  final AdminApi api;
  const _AnnouncementsTab({required this.api});
  @override
  State<_AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends State<_AnnouncementsTab> {
  List<Map<String, dynamic>> _items = [];
  AdminPage? _page;
  bool _loading = true;
  String? _error;
  String _query = '';
  String _status = '';
  String _level = '';
  String _sort = 'created_desc';
  int _pageSize = _adminPageSize;
  int _offset = 0;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({
    int? offset,
    String? query,
    String? status,
    String? level,
    String? sort,
    int? pageSize,
  }) async {
    final nextOffset = offset ?? _offset;
    final nextQuery = query ?? _query;
    final nextStatus = status ?? _status;
    final nextLevel = level ?? _level;
    final nextSort = sort ?? _sort;
    final nextPageSize = pageSize ?? _pageSize;
    _offset = nextOffset;
    _query = nextQuery;
    _status = nextStatus;
    _level = nextLevel;
    _sort = nextSort;
    _pageSize = nextPageSize;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.listAnnouncementsPage(
        query: nextQuery.isEmpty ? null : nextQuery,
        status: nextStatus.isEmpty ? null : nextStatus,
        level: nextLevel.isEmpty ? null : nextLevel,
        sort: nextSort,
        limit: nextPageSize,
        offset: nextOffset,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _items = page.items;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = _adminErrorMessage(e, '公告列表'));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _applySearch() {
    _load(query: _searchCtrl.text.trim(), offset: 0);
  }

  Future<void> _openEdit({Map<String, dynamic>? item}) async {
    final titleCtrl = TextEditingController(
      text: (item?['title'] ?? '').toString(),
    );
    final bodyCtrl = TextEditingController(
      text: (item?['body'] ?? '').toString(),
    );
    String level = (item?['level'] ?? 'info').toString();
    bool published =
        (item?['published'] ?? 1) == 1 || item?['published'] == true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AppDialog(
          title: Text(item == null ? '新增公告' : '编辑公告'),
          icon: const Icon(Icons.campaign_outlined),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: '标题'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: bodyCtrl,
                  maxLines: 6,
                  decoration: const InputDecoration(labelText: '内容'),
                ),
                const SizedBox(height: 8),
                AppDropdownField<String>(
                  initialValue: level,
                  labelText: '级别',
                  items: const [
                    DropdownMenuItem(value: 'info', child: Text('普通')),
                    DropdownMenuItem(value: 'warning', child: Text('警告')),
                    DropdownMenuItem(value: 'critical', child: Text('紧急')),
                  ],
                  onChanged: (v) => setSt(() => level = v ?? 'info'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: published,
                  title: const Text('立即发布'),
                  onChanged: (v) => setSt(() => published = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      if (item == null) {
        await widget.api.createAnnouncement(
          title: titleCtrl.text.trim(),
          body: bodyCtrl.text.trim(),
          level: level,
          published: published,
        );
      } else {
        await widget.api.updateAnnouncement(
          (item['id'] as num).toInt(),
          title: titleCtrl.text.trim(),
          body: bodyCtrl.text.trim(),
          level: level,
          published: published,
        );
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loadingFirstPage = _loading && _page == null;
    return Scaffold(
      body: Column(
        children: [
          AppSectionHeader(
            title: '公告列表',
            subtitle: _adminPageSummary(_page),
            actionLabel: '刷新',
            actionIcon: Icons.refresh,
            onAction: _loading ? null : () => _load(offset: _offset),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '搜索公告标题或正文',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空公告搜索',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchCtrl.clear();
                          _load(query: '', offset: 0);
                        },
                      ),
                isDense: true,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _applySearch(),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Row(
              children: [
                _announcementStatusChip('全部状态', ''),
                _announcementStatusChip('已发布', 'published'),
                _announcementStatusChip('草稿', 'draft'),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                _announcementLevelChip('全部级别', ''),
                _announcementLevelChip('普通', 'info'),
                _announcementLevelChip('重要', 'warning'),
                _announcementLevelChip('紧急', 'critical'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: AppDropdownField<String>(
              initialValue: _sort,
              labelText: '公告排序',
              items: const [
                DropdownMenuItem(value: 'created_desc', child: Text('最新创建优先')),
                DropdownMenuItem(value: 'updated_desc', child: Text('最近更新优先')),
                DropdownMenuItem(value: 'level_desc', child: Text('紧急程度优先')),
                DropdownMenuItem(value: 'title_asc', child: Text('标题 A-Z')),
              ],
              onChanged: (value) =>
                  _load(sort: value ?? 'created_desc', offset: 0),
            ),
          ),
          if (loadingFirstPage)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('正在加载公告列表…'),
                  ],
                ),
              ),
            )
          else if (_error != null)
            Expanded(
              child: _AdminErrorState(
                message: _error!,
                onRetry: () => _load(offset: _offset),
              ),
            )
          else if (_items.isEmpty)
            const Expanded(
              child: EmptyState(
                icon: Icons.campaign_outlined,
                message: '当前筛选下没有公告。可调整关键词、发布状态或级别筛选，公告较多时使用底部分页查看。',
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(offset: _offset),
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final a = _items[i];
                    final published =
                        a['published'] == 1 || a['published'] == true;
                    final level = (a['level'] ?? 'info').toString();
                    final levelColor = switch (level) {
                      'critical' => Colors.red,
                      'warning' => Colors.orange,
                      _ => cs.primary,
                    };
                    return AppListTileCard(
                      margin: const EdgeInsets.only(bottom: 8),
                      isThreeLine: true,
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              (a['title'] ?? '').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w400,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          AppStatusBadge(
                            label: _adminStatusLabel(level),
                            color: levelColor,
                          ),
                          if (!published) ...[
                            const SizedBox(width: 6),
                            AppStatusBadge(
                              label: '草稿',
                              color: cs.onSurface.withValues(alpha: 0.58),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        '创建: ${a['created_at']} · 更新: ${a['updated_at'] ?? '-'} · 排序: ${_adminAnnouncementSortLabel(_sort)}\n${(a['body'] ?? '').toString()}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.64),
                        ),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) async {
                          switch (action) {
                            case 'edit':
                              await _openEdit(item: a);
                              return;
                            case 'toggle':
                              await widget.api.updateAnnouncement(
                                (a['id'] as num).toInt(),
                                published: !published,
                              );
                              await _load(offset: _offset);
                              return;
                            case 'delete':
                              final confirmed = await _confirmAdminDangerAction(
                                context: context,
                                title: '删除公告？',
                                message:
                                    '将删除“${(a['title'] ?? '').toString()}”，已发布用户也将不再看到这条公告。',
                              );
                              if (!confirmed) return;
                              await widget.api.deleteAnnouncement(
                                (a['id'] as num).toInt(),
                              );
                              await _load(
                                offset: _offsetAfterAdminDelete(
                                  offset: _offset,
                                  itemCount: _items.length,
                                  pageSize: _pageSize,
                                ),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('公告已删除')),
                              );
                              return;
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Text('编辑')),
                          PopupMenuItem(
                            value: 'toggle',
                            child: Text(published ? '下架' : '发布'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text(
                              '删除',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          _AdminPaginationBar(
            page: _page,
            loading: _loading,
            pageSize: _pageSize,
            onPageSizeChanged: (value) => _load(pageSize: value, offset: 0),
            onPrevious: () =>
                _load(offset: _previousAdminOffset(_offset, _pageSize)),
            onNext: () => _load(offset: _offset + _pageSize),
            onJumpToPage: (page) => _load(offset: (page - 1) * _pageSize),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(),
        icon: const Icon(Icons.add),
        label: const Text('发布'),
      ),
    );
  }

  Widget _announcementStatusChip(String label, String value) {
    final selected = _status == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _load(status: value, offset: 0),
      ),
    );
  }

  Widget _announcementLevelChip(String label, String value) {
    final selected = _level == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _load(level: value, offset: 0),
      ),
    );
  }
}

// ====================================================================
// 反馈
// ====================================================================

class _FeedbackTab extends StatefulWidget {
  final AdminApi api;
  const _FeedbackTab({required this.api});
  @override
  State<_FeedbackTab> createState() => _FeedbackTabState();
}

class _FeedbackTabState extends State<_FeedbackTab> {
  List<Map<String, dynamic>> _items = [];
  AdminPage? _page;
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  String _filter = '';
  String _categoryFilter = '';
  String _query = '';
  String _sort = 'created_desc';
  int _pageSize = _adminPageSize;
  int _offset = 0;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({
    int? offset,
    String? query,
    String? sort,
    int? pageSize,
  }) async {
    final nextOffset = offset ?? _offset;
    final nextQuery = query ?? _query;
    final nextSort = sort ?? _sort;
    final nextPageSize = pageSize ?? _pageSize;
    _offset = nextOffset;
    _query = nextQuery;
    _sort = nextSort;
    _pageSize = nextPageSize;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.listFeedbackPage(
        status: _filter.isEmpty ? null : _filter,
        query: nextQuery.isEmpty ? null : nextQuery,
        category: _categoryFilter.isEmpty ? null : _categoryFilter,
        sort: nextSort,
        limit: nextPageSize,
        offset: nextOffset,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _items = page.items;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = _adminErrorMessage(e, '反馈列表'));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _applySearch() {
    _load(query: _searchCtrl.text.trim(), offset: 0);
  }

  List<int> get _currentPageOpenIds => _items
      .where((f) => (f['status'] ?? 'open').toString() == 'open')
      .map((f) => (f['id'] as num).toInt())
      .toList();

  List<int> _currentPageIdsWithStatus(String status) => _items
      .where((f) => (f['status'] ?? 'open').toString() == status)
      .map((f) => (f['id'] as num).toInt())
      .toList();

  Map<String, int> get _currentPageStatusCounts {
    final counts = <String, int>{
      'open': 0,
      'in_progress': 0,
      'resolved': 0,
      'closed': 0,
    };
    for (final f in _items) {
      final status = (f['status'] ?? 'open').toString();
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> _markCurrentPageOpenInProgress() async {
    await _bulkUpdateCurrentPageStatus(
      fromStatus: 'open',
      toStatus: 'in_progress',
      reply: '已收到，进入处理中。',
      successMessage: '已将当前页 {count} 条待处理反馈标记为处理中',
    );
  }

  Future<void> _bulkUpdateCurrentPageStatus({
    required String fromStatus,
    required String toStatus,
    required String reply,
    required String successMessage,
  }) async {
    final ids = _currentPageIdsWithStatus(fromStatus);
    if (ids.isEmpty) return;
    try {
      await widget.api.bulkUpdateFeedbackStatus(
        feedbackIds: ids,
        reply: reply,
        status: toStatus,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage.replaceAll('{count}', '${ids.length}')),
        ),
      );
      _load(offset: _offset);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _exportFilteredCsv() async {
    setState(() => _exporting = true);
    try {
      final csv = await widget.api.exportFeedbackCsv(
        status: _filter.isEmpty ? null : _filter,
        query: _query.isEmpty ? null : _query,
        category: _categoryFilter.isEmpty ? null : _categoryFilter,
        sort: _sort,
      );
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/duoyi_feedback_${DateTime.now().millisecondsSinceEpoch}.csv',
      );
      await file.writeAsString(csv, flush: true);
      await Clipboard.setData(ClipboardData(text: file.path));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: '多仪管理员反馈导出',
          subject: '多仪反馈 CSV',
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('反馈 CSV 已导出，路径已复制：${file.path}')));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _reply(Map<String, dynamic> f) async {
    final ctrl = TextEditingController(
      text: (f['admin_reply'] ?? '').toString(),
    );
    String status = (f['status'] ?? 'resolved').toString();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AppDialog(
          title: const Text('回复反馈'),
          icon: const Icon(Icons.reply_outlined),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text((f['content'] ?? '').toString()),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '回复内容'),
              ),
              const SizedBox(height: 8),
              AppDropdownField<String>(
                initialValue: status,
                labelText: '处理状态',
                items: const [
                  DropdownMenuItem(value: 'open', child: Text('待处理')),
                  DropdownMenuItem(value: 'in_progress', child: Text('处理中')),
                  DropdownMenuItem(value: 'resolved', child: Text('已解决')),
                  DropdownMenuItem(value: 'closed', child: Text('已关闭')),
                ],
                onChanged: (v) => setSt(() => status = v ?? status),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('提交'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      await widget.api.replyFeedback(
        feedbackId: (f['id'] as num).toInt(),
        reply: ctrl.text.trim(),
        status: status,
      );
      _load(offset: _offset);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loadingFirstPage = _loading && _page == null;
    final statusCounts = _currentPageStatusCounts;
    final openIds = _currentPageOpenIds;
    final inProgressIds = _currentPageIdsWithStatus('in_progress');
    final resolvedIds = _currentPageIdsWithStatus('resolved');
    return Scaffold(
      body: Column(
        children: [
          AppSectionHeader(
            title: '反馈列表',
            subtitle: _adminPageSummary(_page),
            actionLabel: '刷新',
            actionIcon: Icons.refresh,
            onAction: _loading ? null : () => _load(offset: _offset),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '搜索反馈内容、回复或用户名',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空反馈搜索',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchCtrl.clear();
                          _load(query: '', offset: 0);
                        },
                      ),
                isDense: true,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _applySearch(),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Row(
              children: [
                _filterChip('全部', ''),
                _filterChip('待处理', 'open'),
                _filterChip('处理中', 'in_progress'),
                _filterChip('已解决', 'resolved'),
                _filterChip('已关闭', 'closed'),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                _categoryChip(_feedbackCategoryLabel(''), ''),
                _categoryChip(_feedbackCategoryLabel('feature'), 'feature'),
                _categoryChip(_feedbackCategoryLabel('bug'), 'bug'),
                _categoryChip(_feedbackCategoryLabel('wish'), 'wish'),
                _categoryChip(_feedbackCategoryLabel('other'), 'other'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: AppDropdownField<String>(
              initialValue: _sort,
              labelText: '反馈排序',
              items: const [
                DropdownMenuItem(value: 'created_desc', child: Text('最新反馈优先')),
                DropdownMenuItem(value: 'updated_desc', child: Text('最近处理优先')),
                DropdownMenuItem(value: 'status_asc', child: Text('待处理优先')),
                DropdownMenuItem(value: 'user_asc', child: Text('用户 A-Z')),
              ],
              onChanged: (value) =>
                  _load(sort: value ?? 'created_desc', offset: 0),
            ),
          ),
          if (!loadingFirstPage && _error == null && _items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: AppSurfaceCard(
                padding: const EdgeInsets.all(12),
                color: cs.primary.withValues(alpha: 0.08),
                border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.dashboard_customize_outlined,
                          color: cs.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '本页 ${_items.length} 条 · 待处理 ${statusCounts['open'] ?? 0} · 处理中 ${statusCounts['in_progress'] ?? 0} · 已解决 ${statusCounts['resolved'] ?? 0}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w400,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '共 ${_page?.total ?? _items.length} 条反馈，当前按${_adminFeedbackSortLabel(_sort)}排列。大量反馈按状态、分类、搜索和分页拆开处理，也可导出当前筛选结果。',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.64),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '导出筛选结果',
                          onPressed: _loading || _exporting
                              ? null
                              : _exportFilteredCsv,
                          icon: _exporting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.download_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (openIds.isNotEmpty)
                          TextButton.icon(
                            onPressed: _loading
                                ? null
                                : _markCurrentPageOpenInProgress,
                            icon: const Icon(Icons.playlist_add_check_outlined),
                            label: const Text('本页待处理转处理中'),
                          ),
                        if (inProgressIds.isNotEmpty)
                          TextButton.icon(
                            onPressed: _loading
                                ? null
                                : () => _bulkUpdateCurrentPageStatus(
                                    fromStatus: 'in_progress',
                                    toStatus: 'resolved',
                                    reply: '已处理完成。',
                                    successMessage:
                                        '已将当前页 {count} 条处理中反馈标记为已解决',
                                  ),
                            icon: const Icon(Icons.task_alt_outlined),
                            label: const Text('本页处理中转已解决'),
                          ),
                        if (resolvedIds.isNotEmpty)
                          TextButton.icon(
                            onPressed: _loading
                                ? null
                                : () => _bulkUpdateCurrentPageStatus(
                                    fromStatus: 'resolved',
                                    toStatus: 'closed',
                                    reply: '已归档关闭。',
                                    successMessage: '已将当前页 {count} 条已解决反馈关闭归档',
                                  ),
                            icon: const Icon(Icons.inventory_2_outlined),
                            label: const Text('本页已解决转关闭'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (loadingFirstPage)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('正在加载反馈列表…'),
                  ],
                ),
              ),
            )
          else if (_error != null)
            Expanded(
              child: _AdminErrorState(
                message: _error!,
                onRetry: () => _load(offset: _offset),
              ),
            )
          else if (_items.isEmpty)
            const Expanded(
              child: EmptyState(
                icon: Icons.inbox_outlined,
                message: '当前筛选下没有反馈。反馈较多时请用底部分页查看其他页面，或切换处理状态和分类。',
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(offset: _offset),
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final f = _items[i];
                    final status = (f['status'] ?? 'open').toString();
                    final category = (f['category'] ?? '').toString();
                    final statusColor = switch (status) {
                      'resolved' => Colors.green,
                      'closed' => Colors.grey,
                      'in_progress' => Colors.orange,
                      _ => cs.primary,
                    };
                    final reply = (f['admin_reply'] ?? '').toString();
                    final createdAt = (f['created_at'] ?? '').toString();
                    return AppListTileCard(
                      margin: const EdgeInsets.only(bottom: 8),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${f['username']} · ${_feedbackCategoryLabel(category)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          AppStatusBadge(
                            label: _adminStatusLabel(status),
                            color: statusColor,
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (createdAt.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                createdAt,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.52),
                                ),
                              ),
                            ),
                          Text(
                            (f['content'] ?? '').toString(),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                          if (reply.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.teal.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.teal.withValues(alpha: 0.16),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.subdirectory_arrow_right,
                                      size: 16,
                                      color: Colors.teal,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '回复: $reply',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: cs.onSurface.withValues(
                                                alpha: 0.68,
                                              ),
                                              fontWeight: FontWeight.w400,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '回复',
                            icon: const Icon(Icons.reply),
                            onPressed: () => _reply(f),
                          ),
                          IconButton(
                            tooltip: '删除',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final confirmed = await _confirmAdminDangerAction(
                                context: context,
                                title: '删除反馈？',
                                message: '将删除 ${f['username']} 的这条反馈，删除后无法恢复。',
                              );
                              if (!confirmed) return;
                              try {
                                await widget.api.deleteFeedback(
                                  (f['id'] as num).toInt(),
                                );
                                await _load(
                                  offset: _offsetAfterAdminDelete(
                                    offset: _offset,
                                    itemCount: _items.length,
                                    pageSize: _pageSize,
                                  ),
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('反馈已删除')),
                                );
                              } on ApiException catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.message)),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          _AdminPaginationBar(
            barKey: const ValueKey('admin_feedback_pagination'),
            page: _page,
            loading: _loading,
            pageSize: _pageSize,
            onPageSizeChanged: (value) => _load(pageSize: value, offset: 0),
            onPrevious: () =>
                _load(offset: _previousAdminOffset(_offset, _pageSize)),
            onNext: () => _load(offset: _offset + _pageSize),
            onJumpToPage: (page) => _load(offset: (page - 1) * _pageSize),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _filter = value);
          _load(offset: 0);
        },
      ),
    );
  }

  Widget _categoryChip(String label, String value) {
    final selected = _categoryFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _categoryFilter = value);
          _load(offset: 0);
        },
      ),
    );
  }
}

// ====================================================================
// 邀请码
// ====================================================================

class _InvitesTab extends StatefulWidget {
  final AdminApi api;
  const _InvitesTab({required this.api});
  @override
  State<_InvitesTab> createState() => _InvitesTabState();
}

class _InvitesTabState extends State<_InvitesTab> {
  List<Map<String, dynamic>> _codes = [];
  AdminPage? _page;
  bool _loading = true;
  String? _error;
  String _status = '';
  String _query = '';
  String _sort = 'created_desc';
  int _pageSize = _adminPageSize;
  int _offset = 0;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({
    int? offset,
    String? status,
    String? query,
    String? sort,
    int? pageSize,
  }) async {
    final nextOffset = offset ?? _offset;
    final nextStatus = status ?? _status;
    final nextQuery = query ?? _query;
    final nextSort = sort ?? _sort;
    final nextPageSize = pageSize ?? _pageSize;
    _offset = nextOffset;
    _status = nextStatus;
    _query = nextQuery;
    _sort = nextSort;
    _pageSize = nextPageSize;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.listInviteCodesPage(
        query: nextQuery.isEmpty ? null : nextQuery,
        status: nextStatus.isEmpty ? null : nextStatus,
        sort: nextSort,
        limit: nextPageSize,
        offset: nextOffset,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _codes = page.items;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = _adminErrorMessage(e, '邀请码列表'));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _applySearch() {
    _load(query: _searchCtrl.text.trim(), offset: 0);
  }

  Future<void> _generate() async {
    int count = 5;
    String note = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AppDialog(
          title: const Text('生成邀请码'),
          icon: const Icon(Icons.vpn_key_outlined),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text('数量:'),
                  Expanded(
                    child: Slider(
                      value: count.toDouble(),
                      min: 1,
                      max: 50,
                      divisions: 49,
                      label: '$count',
                      onChanged: (v) => setSt(() => count = v.toInt()),
                    ),
                  ),
                  Text('$count'),
                ],
              ),
              TextField(
                decoration: const InputDecoration(labelText: '备注 (可选)'),
                onChanged: (v) => note = v,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('生成'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final codes = await widget.api.createInviteCodes(
        count: count,
        note: note,
      );
      await _load(offset: 0);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AppDialog(
          title: Text('已生成 ${codes.length} 个邀请码'),
          icon: const Icon(Icons.check_circle_outline),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: SelectableText(codes.join('\n')),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: codes.join('\n')));
                Navigator.pop(ctx);
              },
              child: const Text('复制并关闭'),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loadingFirstPage = _loading && _page == null;
    return Scaffold(
      body: Column(
        children: [
          AppSectionHeader(
            title: '邀请码列表',
            subtitle: _adminPageSummary(_page),
            actionLabel: '刷新',
            actionIcon: Icons.refresh,
            onAction: _loading ? null : () => _load(offset: _offset),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '搜索邀请码、备注或使用者',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空邀请码搜索',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchCtrl.clear();
                          _load(query: '', offset: 0);
                        },
                      ),
                isDense: true,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _applySearch(),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                _inviteStatusChip('全部邀请码', ''),
                _inviteStatusChip('未使用', 'unused'),
                _inviteStatusChip('已使用', 'used'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: AppDropdownField<String>(
              initialValue: _sort,
              labelText: '邀请码排序',
              items: const [
                DropdownMenuItem(value: 'created_desc', child: Text('最新生成优先')),
                DropdownMenuItem(value: 'used_desc', child: Text('最近使用优先')),
                DropdownMenuItem(value: 'code_asc', child: Text('邀请码 A-Z')),
                DropdownMenuItem(value: 'note_asc', child: Text('备注 A-Z')),
              ],
              onChanged: (value) =>
                  _load(sort: value ?? 'created_desc', offset: 0),
            ),
          ),
          if (loadingFirstPage)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('正在加载邀请码列表…'),
                  ],
                ),
              ),
            )
          else if (_error != null)
            Expanded(
              child: _AdminErrorState(
                message: _error!,
                onRetry: () => _load(offset: _offset),
              ),
            )
          else if (_codes.isEmpty)
            const Expanded(
              child: EmptyState(
                icon: Icons.vpn_key_outlined,
                message: '当前筛选下没有邀请码。可搜索邀请码、备注或使用者；邀请码较多时请用底部分页查看其他页面。',
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(offset: _offset),
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _codes.length,
                  itemBuilder: (_, i) {
                    final c = _codes[i];
                    final used = (c['used_by'] ?? '').toString().isNotEmpty;
                    return AppListTileCard(
                      margin: const EdgeInsets.only(bottom: 8),
                      leading: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: (used ? Colors.grey : Colors.blue).withValues(
                            alpha: 0.12,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          used ? Icons.check_circle : Icons.key,
                          color: used ? Colors.grey : Colors.blue,
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              c['code'].toString(),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w400,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          AppStatusBadge(
                            label: used ? '已使用' : '未使用',
                            color: used ? Colors.grey : Colors.blue,
                          ),
                        ],
                      ),
                      subtitle: Text(
                        used
                            ? '已被 ${c['used_by_name'] ?? '?'} 使用 · ${c['used_at']} · 排序: ${_adminInviteSortLabel(_sort)}'
                            : '创建 ${c['created_at']} · 排序: ${_adminInviteSortLabel(_sort)}${(c['note'] ?? '').toString().isNotEmpty ? ' · ${c['note']}' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                      trailing: used
                          ? null
                          : IconButton(
                              tooltip: '删除',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final code = c['code'].toString();
                                final confirmed =
                                    await _confirmAdminDangerAction(
                                      context: context,
                                      title: '删除邀请码？',
                                      message: '将删除未使用的邀请码 $code，删除后无法恢复。',
                                    );
                                if (!confirmed) return;
                                await widget.api.deleteInviteCode(code);
                                await _load(
                                  offset: _offsetAfterAdminDelete(
                                    offset: _offset,
                                    itemCount: _codes.length,
                                    pageSize: _pageSize,
                                  ),
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('邀请码已删除')),
                                );
                              },
                            ),
                    );
                  },
                ),
              ),
            ),
          _AdminPaginationBar(
            page: _page,
            loading: _loading,
            pageSize: _pageSize,
            onPageSizeChanged: (value) => _load(pageSize: value, offset: 0),
            onPrevious: () =>
                _load(offset: _previousAdminOffset(_offset, _pageSize)),
            onNext: () => _load(offset: _offset + _pageSize),
            onJumpToPage: (page) => _load(offset: (page - 1) * _pageSize),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _generate,
        icon: const Icon(Icons.add),
        label: const Text('生成'),
      ),
    );
  }

  Widget _inviteStatusChip(String label, String value) {
    final selected = _status == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _load(status: value, offset: 0),
      ),
    );
  }
}

// ====================================================================
// 审计日志
// ====================================================================

class _AuditLogTab extends StatefulWidget {
  final AdminApi api;
  const _AuditLogTab({required this.api});
  @override
  State<_AuditLogTab> createState() => _AuditLogTabState();
}

class _AuditLogTabState extends State<_AuditLogTab> {
  List<Map<String, dynamic>> _items = [];
  AdminPage? _page;
  bool _loading = true;
  String? _error;
  String _action = '';
  String _query = '';
  String _sort = 'created_desc';
  int _pageSize = _adminPageSize;
  int _offset = 0;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({
    int? offset,
    String? action,
    String? query,
    String? sort,
    int? pageSize,
  }) async {
    final nextOffset = offset ?? _offset;
    final nextAction = action ?? _action;
    final nextQuery = query ?? _query;
    final nextSort = sort ?? _sort;
    final nextPageSize = pageSize ?? _pageSize;
    _offset = nextOffset;
    _action = nextAction;
    _query = nextQuery;
    _sort = nextSort;
    _pageSize = nextPageSize;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.auditLogPage(
        action: nextAction.isEmpty ? null : nextAction,
        query: nextQuery.isEmpty ? null : nextQuery,
        sort: nextSort,
        limit: nextPageSize,
        offset: nextOffset,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _items = page.items;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = _adminErrorMessage(e, '审计日志'));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _applySearch() {
    _load(query: _searchCtrl.text.trim(), offset: 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loadingFirstPage = _loading && _page == null;
    return Column(
      children: [
        AppSectionHeader(
          title: '审计日志',
          subtitle: _adminPageSummary(_page),
          actionLabel: '刷新',
          actionIcon: Icons.refresh,
          onAction: _loading ? null : () => _load(offset: _offset),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '搜索管理员、操作、对象或详情',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空日志搜索',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchCtrl.clear();
                        _load(query: '', offset: 0);
                      },
                    ),
              isDense: true,
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _applySearch(),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              _actionChip('全部操作', ''),
              _actionChip('更新用户', 'user.update'),
              _actionChip('公告', 'announcement.update'),
              _actionChip('回复反馈', 'feedback.reply'),
              _actionChip('邀请码', 'invite.create'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: AppDropdownField<String>(
            initialValue: _sort,
            labelText: '日志排序',
            items: const [
              DropdownMenuItem(value: 'created_desc', child: Text('最新操作优先')),
              DropdownMenuItem(value: 'actor_asc', child: Text('管理员 A-Z')),
              DropdownMenuItem(value: 'action_asc', child: Text('操作类型 A-Z')),
              DropdownMenuItem(value: 'target_asc', child: Text('对象 A-Z')),
            ],
            onChanged: (value) =>
                _load(sort: value ?? 'created_desc', offset: 0),
          ),
        ),
        if (loadingFirstPage)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('正在加载审计日志…'),
                ],
              ),
            ),
          )
        else if (_error != null)
          Expanded(
            child: _AdminErrorState(
              message: _error!,
              onRetry: () => _load(offset: _offset),
            ),
          )
        else if (_items.isEmpty)
          const Expanded(
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              message: '当前筛选下没有审计日志。管理员操作较多时可搜索管理员、操作或对象，并使用底部分页查看。',
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(offset: _offset),
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final item = _items[i];
                  final action = (item['action'] ?? '').toString();
                  final actor = (item['actor_name'] ?? item['actor'] ?? '-')
                      .toString();
                  final target = (item['target'] ?? '').toString();
                  final detail = (item['detail'] ?? '').toString();
                  final createdAt = (item['created_at'] ?? '').toString();
                  return AppListTileCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    leading: Icon(
                      Icons.receipt_long_outlined,
                      color: cs.primary,
                    ),
                    title: Text(
                      '${_auditActionLabel(action)} · $actor',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    subtitle: Text(
                      [
                        if (createdAt.isNotEmpty) createdAt,
                        '排序: ${_adminAuditSortLabel(_sort)}',
                        if (target.isNotEmpty) '对象: $target',
                        if (detail.isNotEmpty) '详情: $detail',
                      ].join('\n'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.64),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        _AdminPaginationBar(
          page: _page,
          loading: _loading,
          pageSize: _pageSize,
          onPageSizeChanged: (value) => _load(pageSize: value, offset: 0),
          onPrevious: () =>
              _load(offset: _previousAdminOffset(_offset, _pageSize)),
          onNext: () => _load(offset: _offset + _pageSize),
          onJumpToPage: (page) => _load(offset: (page - 1) * _pageSize),
        ),
      ],
    );
  }

  Widget _actionChip(String label, String value) {
    final selected = _action == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _load(action: value, offset: 0),
      ),
    );
  }
}
