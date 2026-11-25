import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('管理员用户列表显示真实最近活跃和在线离线状态', () {
    final backend = File('backend/main.py').readAsStringSync();
    final adminScreen = File(
      'lib/screens/admin_screen.dart',
    ).readAsStringSync();

    expect(backend, contains('SESSION_ONLINE_SECONDS'));
    expect(backend, contains('last_active_at TEXT'));
    expect(backend, contains('def _utc_now_text()'));
    expect(backend, contains('UPDATE users SET last_active_at=?'));
    expect(backend, contains('VALUES(?,?,?,?)'));
    expect(
      backend,
      contains('UPDATE users SET last_login_at=?, last_active_at=? WHERE id=?'),
    );
    expect(backend, contains('def _has_recent_user_activity'));
    expect(
      backend,
      isNot(contains("last_login_at >= datetime('now','-7 days')")),
    );
    expect(backend, contains('u.last_login_at, u.last_active_at'));
    expect(backend, contains('"last_active_at": r["last_active_at"]'));
    expect(backend, contains('"online": r["id"] in online_user_ids'));

    expect(adminScreen, contains("u['last_login_at']"));
    expect(adminScreen, contains("u['last_active_at']"));
    expect(adminScreen, contains('text.replaceFirst'));
    expect(adminScreen, contains('hasTimezone'));
    expect(adminScreen, contains('_formatLastLogin'));
    expect(adminScreen, contains("_userText('在线', 'Online')"));
    expect(adminScreen, contains(r'最近登录: $lastLoginAt'));
    expect(adminScreen, contains(r'最近活跃: $lastActiveAt'));
    expect(adminScreen, contains('从未登录'));
    expect(adminScreen, contains('从未活跃'));
    expect(adminScreen, contains('Timer.periodic(_onlineRefreshInterval'));
    expect(adminScreen, contains('Duration(seconds: 60)'));
    expect(adminScreen, contains('isActive: _activeTabIndex == 4'));
    expect(adminScreen, contains('void _handleTabChanged()'));
    expect(adminScreen, contains('void _startOnlineRefreshTimer()'));
    expect(adminScreen, contains('void _stopOnlineRefreshTimer()'));
    expect(adminScreen, contains('!widget.isActive ||'));
    expect(adminScreen, contains('_backgroundRefreshInFlight'));
    expect(adminScreen, contains('background: !deferred'));
    expect(
      adminScreen,
      contains('(background && (_backgroundRefreshInFlight || _loading))'),
    );
    expect(
      adminScreen,
      contains('if (background) _backgroundOperation = marker;'),
    );
    expect(adminScreen, contains('identical(_backgroundOperation, marker)'));
  });

  test('管理员后台大数据列表使用分页 API 和分页文案', () {
    final adminScreen = File(
      'lib/screens/admin_screen.dart',
    ).readAsStringSync();
    final adminApi = File('lib/services/admin_api.dart').readAsStringSync();
    final announcementCopy = File(
      'lib/core/admin_announcement_ui_copy.dart',
    ).readAsStringSync();
    final inviteCopy = File(
      'lib/core/admin_invite_ui_copy.dart',
    ).readAsStringSync();
    final auditCopy = File(
      'lib/core/admin_audit_ui_copy.dart',
    ).readAsStringSync();
    final feedbackCopy = File(
      'lib/core/admin_feedback_ui_copy.dart',
    ).readAsStringSync();
    final feedbackExport = File(
      'lib/services/admin_feedback_export.dart',
    ).readAsStringSync();

    expect(adminApi, contains('class AdminPage'));
    expect(adminApi, contains('Future<AdminPage> listUsersPage'));
    expect(adminApi, contains('Future<AdminPage> listBackupsPage'));
    expect(adminApi, contains('Future<AdminPage> listServerBackupsPage'));
    expect(adminApi, contains('Future<String> exportBackupsCsv'));
    expect(adminApi, contains('Future<String> exportServerBackupsCsv'));
    expect(adminApi, contains("'/api/admin/backups/export.csv'"));
    expect(adminApi, contains("'/api/admin/server-backups/export.csv'"));
    expect(adminApi, contains('Future<AdminPage> listAnnouncementsPage'));
    expect(adminApi, contains('Future<AdminPage> listFeedbackPage'));
    expect(adminApi, contains('Future<AdminPage> listInviteCodesPage'));
    expect(adminApi, contains('Future<String> exportFeedbackCsv'));
    expect(adminApi, contains("'/api/admin/feedback/export.csv'"));
    expect(adminApi, contains('client.getText('));
    expect(adminApi, contains("'limit': limit"));
    expect(adminApi, contains("'offset': offset"));
    expect(
      adminApi,
      contains("params: {'q': query, 'status': status, 'sort': sort}"),
    );

    expect(adminScreen, contains('const int _adminPageSize = 20'));
    expect(adminScreen, contains('_AdminPaginationBar'));
    expect(adminScreen, contains(r'第 $start-$end 条 / 共 ${page.total} 条'));
    expect(
      adminScreen,
      contains('String _adminPageNumber(AdminPage? page, [AppLocale? locale])'),
    );
    expect(adminScreen, contains(r'第 $current/$totalPages 页'));
    expect(adminScreen, contains('AdminAnnouncementUiCopy.loadingFor()'));
    expect(announcementCopy, contains('Loading announcements…'));
    expect(adminScreen, contains('AdminFeedbackUiCopy.loadingFor()'));
    expect(feedbackCopy, contains('正在加载反馈列表…'));
    expect(adminScreen, contains('AdminInviteUiCopy.loadingFor()'));
    expect(inviteCopy, contains('Loading invite codes…'));
    expect(adminScreen, contains('AdminAuditUiCopy.loadingFor()'));
    expect(auditCopy, contains('Loading audit log…'));
    expect(adminScreen, contains("'Search username, email, name or user ID'"));
    expect(
      adminScreen,
      contains('hintText: AdminUiCopy.searchServerBackupsHintFor(locale)'),
    );
    expect(
      adminScreen,
      contains('hintText: AdminUiCopy.searchUserBackupsHintFor(locale)'),
    );
    expect(
      RegExp(
        r'tooltip:\s*AdminUiCopy\.clearServerBackupSearchTooltipFor\(\s*locale\s*,?\s*\)',
      ).hasMatch(adminScreen),
      isTrue,
    );
    expect(
      RegExp(
        r'tooltip:\s*AdminUiCopy\.clearUserBackupSearchTooltipFor\(\s*locale\s*,?\s*\)',
      ).hasMatch(adminScreen),
      isTrue,
    );
    expect(adminScreen, contains('Future<void> _exportBackupsCsv()'));
    expect(adminScreen, contains('Future<void> _exportServerBackupsCsv()'));
    expect(adminScreen, contains('widget.api.exportBackupsCsv('));
    expect(adminScreen, contains('widget.api.exportServerBackupsCsv('));
    expect(adminScreen, contains("prefix: 'duoyi_backups'"));
    expect(adminScreen, contains("prefix: 'duoyi_server_backups'"));
    expect(
      RegExp(
        r'actionLabel: _exportingBackups\s*\?\s*AdminUiCopy\.exportingEllipsis\(locale\)\s*:\s*AdminUiCopy\.exportFilteredResultsFor\(locale\)',
      ).hasMatch(adminScreen),
      isTrue,
    );
    expect(
      RegExp(
        r'actionLabel: _exportingServerBackups\s*\?\s*AdminUiCopy\.exportingEllipsis\(locale\)\s*:\s*AdminUiCopy\.exportFilteredResultsFor\(locale\)',
      ).hasMatch(adminScreen),
      isTrue,
    );
    expect(
      adminScreen,
      contains('labelText: AdminUiCopy.serverBackupSortLabelFor(locale)'),
    );
    expect(
      adminScreen,
      contains('labelText: AdminUiCopy.userBackupSortLabelFor(locale)'),
    );
    expect(
      RegExp(
        r"_serverBackupStatusChip\(\s*AdminUiCopy\.uploadedChipFor\(locale\),\s*'uploaded',?\s*\)",
      ).hasMatch(adminScreen),
      isTrue,
    );
    expect(
      RegExp(
        r"_backupStatusChip\(\s*AdminUiCopy\.hasSnapshotChipFor\(locale\),\s*'synced',?\s*\)",
      ).hasMatch(adminScreen),
      isTrue,
    );
    expect(adminScreen, contains("_userText('在线', 'Online'), 'online'"));
    expect(adminScreen, contains("'unverified_email'"));
    expect(adminScreen, contains("'has_feedback'"));
    expect(adminScreen, contains("online: _onlineFilter(nextStatus)"));
    expect(adminScreen, contains("status: _backendStatusFilter(nextStatus)"));
    expect(adminScreen, contains("value: 'email_asc'"));
    expect(adminScreen, contains("value: 'version_desc'"));
    expect(adminScreen, contains('serverBackupPageSize: value'));
    expect(adminScreen, contains('backupPageSize: value'));
    expect(adminScreen, contains('_adminServerBackupSortLabel'));
    expect(adminScreen, contains('_adminBackupSortLabel'));
    expect(adminScreen, contains('AdminAnnouncementUiCopy.noMatchesFor()'));
    expect(announcementCopy, contains('No matching announcements.'));
    expect(feedbackCopy, contains('暂无反馈'));
    expect(adminScreen, contains('AdminFeedbackUiCopy.emptyFor()'));
    expect(feedbackCopy, contains('没有匹配的反馈，请调整筛选条件'));
    expect(adminScreen, contains('AdminFeedbackUiCopy.noMatchesFor()'));
    expect(adminScreen, contains('_categoryFilter.isEmpty'));
    expect(
      adminScreen,
      contains('Future<void> _exportFilteredCsv(_FeedbackAction origin)'),
    );
    expect(adminScreen, contains('AdminApi(origin.client).exportFeedbackCsv('));
    expect(adminScreen, contains('tooltip: AdminFeedbackUiCopy.exportFor()'));
    expect(adminScreen, contains('SharePlus.instance.share'));
    expect(feedbackExport, contains('duoyi_feedback_'));
    expect(adminScreen, contains('exportAdminFeedbackCsv('));
    expect(feedbackCopy, contains('导出当前筛选结果的前 5000 条'));
    expect(feedbackExport, contains('handedOff = true'));
    expect(adminScreen, contains('AdminInviteUiCopy.noMatchesFor()'));
    expect(inviteCopy, contains('No matching invite codes.'));
    expect(adminScreen, contains('AdminInviteUiCopy.searchHintFor()'));
    expect(inviteCopy, contains('Search codes, notes or users'));
    expect(adminScreen, contains('AdminAuditUiCopy.searchHintFor()'));
    expect(
      auditCopy,
      contains('Search administrators, actions, targets or details'),
    );
    expect(
      adminScreen,
      contains('tooltip: AdminInviteUiCopy.clearSearchFor()'),
    );
    expect(inviteCopy, contains('Clear invite code search'));
    expect(adminScreen, contains('tooltip: AdminAuditUiCopy.clearSearchFor()'));
    expect(auditCopy, contains('Clear audit search'));
    expect(
      adminScreen,
      contains('query: nextQuery.isEmpty ? null : nextQuery'),
    );
    expect(
      adminScreen,
      contains('AdminAnnouncementUiCopy.deleteTitleFor(locale)'),
    );
    expect(announcementCopy, contains('Delete announcement?'));
    expect(feedbackCopy, contains('删除反馈？'));
    expect(adminScreen, contains('AdminFeedbackUiCopy.deleteTitleFor'));
    expect(adminScreen, contains('AdminInviteUiCopy.deleteTitleFor(locale)'));
    expect(inviteCopy, contains('Delete invite code?'));
    expect(
      adminScreen,
      contains('label: Text(AdminAnnouncementUiCopy.newTitleFor())'),
    );
    expect(announcementCopy, contains('New announcement'));
    expect(
      adminScreen,
      contains('label: Text(AdminInviteUiCopy.generateTitleFor())'),
    );
    expect(inviteCopy, contains('Generate invite codes'));
    expect(adminScreen, isNot(contains('floatingActionButton:')));
    expect(adminScreen, isNot(contains('FloatingActionButton.extended')));
    expect(adminScreen, contains('AdminUiCopy.perPageFor(locale)'));
    expect(adminScreen, contains('label: AdminUiCopy.perPageFor(locale)'));
    expect(adminScreen, contains('label: AdminUiCopy.pageNumberFor(locale)'));
    expect(adminScreen, contains('class _AdminPaginationLabeledControl'));
    expect(adminScreen, contains('constraints.maxWidth < 720'));
    expect(adminScreen, isNot(contains('constraints.maxWidth < 520')));
    expect(
      adminScreen,
      contains("key: const ValueKey('admin_compact_pagination_full_width')"),
    );
    expect(
      adminScreen,
      contains('crossAxisAlignment: CrossAxisAlignment.stretch'),
    );
    expect(adminScreen, contains('Wrap('));
    expect(adminScreen, contains('WrapAlignment.spaceBetween'));
    expect(adminScreen, contains('width: 76'));
    expect(adminScreen, contains('width: 54'));
    expect(adminScreen, contains('maxWidth: 300'));
    expect(adminScreen, contains('maxWidth: 300'));
    expect(adminScreen, contains('fromLTRB(10, 4, 10, 4)'));
    expect(
      adminScreen,
      contains(
        "'\${_adminPageSummary(page, locale)} · \${_adminPageNumber(page, locale)}'",
      ),
    );
    expect(adminScreen, contains('class _AdminChipWrap'));
    // Complete, stable tab labels are verified by the rendered cases in
    // admin_navigation_selection_labels_test.dart, independent of width math.
    expect(adminScreen, isNot(contains('width: 92')));
    expect(
      RegExp(
        r'_AdminChipWrap\(|Wrap\(\s*spacing:\s*6',
      ).allMatches(adminScreen).length,
      greaterThanOrEqualTo(8),
    );
    expect(
      RegExp(
        r'content:\s+SingleChildScrollView\(',
      ).allMatches(adminScreen).length,
      greaterThanOrEqualTo(2),
    );
    final sharedForm = adminScreen.substring(
      adminScreen.indexOf('Widget _adminDialogForm({'),
      adminScreen.indexOf('class _AdminPaginationBar'),
    );
    expect(sharedForm, contains('SingleChildScrollView('));
    final announcements = adminScreen.substring(
      adminScreen.indexOf('class _AnnouncementsTabState'),
      adminScreen.indexOf('class _FeedbackTab'),
    );
    expect(announcements, contains('content: _adminDialogForm('));
    final invites = adminScreen.substring(
      adminScreen.indexOf('class _InvitesTabState'),
      adminScreen.indexOf('class _AuditLogTab'),
    );
    expect(
      RegExp(r'content:\s+_adminDialogForm\(').allMatches(invites),
      hasLength(2),
    );
    expect(invites, contains('await dialogRoute.completed'));
    expect(invites, contains('noteCtrl.dispose()'));
    expect(invites, contains('isCurrent: current'));
    expect(invites, contains('identical(operation, _pendingMutation)'));
    expect(adminScreen, contains("allowed: canAccess('invites')"));
    expect(adminScreen, contains('Widget navButton({'));
    expect(adminScreen, contains('iconSize: 16'));
    expect(adminScreen, isNot(contains('admin_compact_pagination_inline')));
    expect(adminScreen, isNot(contains('compactHasPageShortcuts')));
    expect(adminScreen, isNot(contains('Expanded(child: previousButton)')));
    expect(adminScreen, isNot(contains('Expanded(child: nextButton)')));
    final paginationStart = adminScreen.indexOf('class _AdminPaginationBar ');
    expect(paginationStart, greaterThanOrEqualTo(0));
    final paginationEnd = adminScreen.indexOf(
      'class _AdminPaginationLabeledControl ',
      paginationStart,
    );
    expect(paginationEnd, greaterThan(paginationStart));
    final pagination = adminScreen.substring(paginationStart, paginationEnd);
    expect(
      pagination,
      isNot(contains('minimumSize: const WidgetStatePropertyAll')),
    );
    expect(adminScreen, contains('dimension: 32'));
    expect(adminScreen, isNot(contains('dimension: 26')));
    expect(adminScreen, isNot(contains('height: 22')));
    expect(adminScreen, isNot(contains('dimension: 22')));
    expect(adminScreen, isNot(contains('width: 124')));
    expect(adminScreen, contains('minHeight: 32'));
    expect(adminScreen, isNot(contains('minHeight: 26')));
    expect(adminScreen, contains('class _AdminGlassControlTheme'));
    expect(adminScreen, contains('selectedFill'));
    expect(adminScreen, contains('glassControlFill'));
    expect(
      adminScreen,
      contains('message: AdminUiCopy.paginationNavigationFor(locale)'),
    );
    expect(
      adminScreen,
      contains('message: AdminUiCopy.jumpToFirstPageFor(locale)'),
    );
    expect(
      adminScreen,
      contains('message: AdminUiCopy.previousPageFor(locale)'),
    );
    expect(adminScreen, contains('message: AdminUiCopy.nextPageFor(locale)'));
    expect(
      adminScreen,
      contains('message: AdminUiCopy.jumpToLastPageFor(locale)'),
    );
    expect(adminScreen, contains('onJumpToPage'));
    expect(adminScreen, isNot(contains("label: const Text('上一页')")));
    expect(adminScreen, isNot(contains("label: const Text('下一页')")));
    expect(adminScreen, contains('tooltip: AdminFeedbackUiCopy.replyFor()'));
    expect(adminScreen, contains('tooltip: AdminUiCopy.deleteFor()'));
    expect(
      adminScreen,
      contains('tooltip: AdminFeedbackUiCopy.detailTooltipFor()'),
    );
    expect(adminScreen, contains('if (_open)'));
    expect(adminScreen, isNot(contains('Matrix4.translationValues')));
    expect(adminScreen, contains('static const double _actionRailWidth'));
    expect(
      adminScreen,
      contains('const List<int> _adminPageSizeOptions = [20, 50, 100, 200]'),
    );
    expect(adminScreen, contains('items: _adminPageSizeOptions'));
    expect(adminScreen, contains('DropdownMenuItem(value: v'));
    expect(
      adminScreen,
      contains('AdminApi(origin.client).listAnnouncementsPage'),
    );
    expect(adminScreen, contains("anyOfPermissions: const {'announcements'}"));
    expect(adminScreen, contains('isCurrent: current'));
    expect(adminScreen, contains('AdminApi(origin.client).listFeedbackPage'));
    expect(
      adminScreen,
      contains('AdminApi(origin.client).listInviteCodesPage'),
    );
    expect(adminScreen, contains("anyOfPermissions: const {'invites'}"));
    expect(adminScreen, contains('AdminApi(origin.client).auditLogPage'));
    expect(adminScreen, contains("anyOfPermissions: const {'audit'}"));
    expect(
      adminScreen,
      contains('labelText: AdminAnnouncementUiCopy.sortTitleFor()'),
    );
    expect(announcementCopy, contains('Sort announcements'));
    expect(feedbackCopy, contains('反馈排序'));
    expect(adminScreen, contains('AdminFeedbackUiCopy.sortTitleFor'));
    expect(
      adminScreen,
      contains('labelText: AdminInviteUiCopy.sortTitleFor()'),
    );
    expect(inviteCopy, contains('Sort invite codes'));
    expect(adminScreen, contains('labelText: AdminAuditUiCopy.sortTitleFor()'));
    expect(auditCopy, contains("_text('日志排序', 'Sort audit log', locale)"));
    expect(announcementCopy, contains('最近更新优先'));
    expect(announcementCopy, contains('Recently updated'));
    expect(feedbackCopy, contains('最近处理优先'));
    expect(inviteCopy, contains('最近使用优先'));
    expect(inviteCopy, contains('Recently used'));
    expect(auditCopy, contains("_text('操作类型 A-Z', 'Action A–Z', locale)"));
    expect(adminScreen, contains('AdminAuditUiCopy.sortLabel(value, locale)'));
    expect(adminScreen, contains('AdminFeedbackUiCopy.bulkLabel(t.'));
    expect(adminScreen, contains("('in_progress', 'resolved', '已处理完成。')"));
    expect(adminScreen, contains("('resolved', 'closed', '已归档关闭。')"));
    expect(feedbackCopy, contains('每次最多处理 100 条'));
    expect(adminScreen, contains('_adminAnnouncementSortLabel'));
    expect(adminScreen, contains('_adminFeedbackSortLabel'));
    expect(adminScreen, contains('_adminInviteSortLabel'));
    expect(adminScreen, contains('_adminAuditSortLabel'));
    expect(adminScreen, contains('_feedbackCategoryLabel(category)'));
    expect(adminScreen, contains('label: Text(_feedbackCategoryLabel(value))'));
    expect(adminScreen, contains("ValueKey('admin_feedback_category_"));
    expect(adminScreen, contains('_inviteStatusChip'));
    expect(adminScreen, contains('_offsetAfterAdminDelete'));
  });

  test('管理员反馈 CSV 导出使用当前筛选并做表格公式防护', () {
    final backend = File('backend/main.py').readAsStringSync();

    expect(backend, contains('@app.get("/api/admin/feedback/export.csv")'));
    expect(backend, contains('def export_feedback_csv'));
    expect(backend, contains('_feedback_admin_filters('));
    expect(backend, contains('_feedback_admin_order_by(sort)'));
    expect(backend, contains('email_verified'));
    expect(backend, contains('sync_version'));
    expect(backend, contains('has_snapshot'));
    expect(backend, contains('status == "has_feedback"'));
    expect(backend, contains('status == "unverified_email"'));
    expect(backend, contains('"email_asc"'));
    expect(backend, contains('"version_desc"'));
    expect(backend, contains('limit: int = Query(5000, ge=1, le=20000)'));
    expect(backend, contains('"Content-Disposition"'));
    expect(backend, contains('"X-Total-Count"'));
    expect(backend, contains('"X-Exported-Count"'));
    expect(backend, contains('"feedback.export"'));
    expect(backend, contains('def _csv_safe(value)'));
    expect(
      backend,
      contains('text[0] in ("=", "+", "-", "@", "\\t", "\\r", "\\n")'),
    );
    expect(backend, contains('writer.writerow('));
    expect(backend, contains('text/csv; charset=utf-8'));
  });
}
