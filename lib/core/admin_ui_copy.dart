/// Typed bilingual copy and localization getters for admin console,
/// module switchers, access-denied states, dashboard tab, and tabs 1-3
/// (Site Settings, AI Config, Cloud Backup).
library;

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import 'i18n.dart';

class AdminUiCopy {
  AdminUiCopy._();

  static bool get isZh => I18n.current == AppLocale.zh;
  static bool get isEn => I18n.current == AppLocale.en;

  // ---------------------------------------------------------------------------
  // Root Shell & Entry
  // ---------------------------------------------------------------------------
  static String adminScreenTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '管理员后台' : 'Admin Console';
  }

  static String get adminScreenTitle => adminScreenTitleFor(I18n.current);

  static String adminAccessOnlyFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '仅管理员可访问' : 'Admin access only';
  }

  static String get adminAccessOnly => adminAccessOnlyFor(I18n.current);

  static String noModulePermissionFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '暂无此模块的管理权限' : 'No permission to manage this module';
  }

  static String get noModulePermission => noModulePermissionFor(I18n.current);

  static String get selectModuleTooltip => isZh ? '选择管理模块' : 'Select module';
  static String get refreshCurrentPageTooltip =>
      isZh ? '刷新当前页' : 'Refresh current page';

  // ---------------------------------------------------------------------------
  // Module Tabs (10 modules: 0-9)
  // ---------------------------------------------------------------------------
  static const List<String> moduleKeys = [
    'dashboard',
    'settings',
    'ai',
    'backup',
    'users',
    'groups',
    'announcements',
    'feedback',
    'invites',
    'audit',
  ];

  static String tabTitleForIndex(int index, [AppLocale? locale]) {
    final effectiveLocale = locale ?? I18n.current;
    final zh = effectiveLocale == AppLocale.zh;
    return switch (index) {
      0 => zh ? '概览' : 'Dashboard',
      1 => zh ? '全站设置' : 'Settings',
      2 => zh ? 'AI 配置' : 'AI Config',
      3 => zh ? '云端备份' : 'Cloud Backup',
      4 => zh ? '用户' : 'Users',
      5 => zh ? '用户组' : 'Groups',
      6 => zh ? '公告' : 'Announcements',
      7 => zh ? '许愿与反馈' : 'Feedback',
      8 => zh ? '邀请码' : 'Invites',
      9 => zh ? '日志' : 'Logs',
      _ => '',
    };
  }

  static String tabTitle(String zhTitle, [AppLocale? locale]) {
    final effectiveLocale = locale ?? I18n.current;
    if (effectiveLocale == AppLocale.zh) return zhTitle;
    return switch (zhTitle) {
      '概览' => 'Dashboard',
      '全站设置' => 'Settings',
      'AI 配置' => 'AI Config',
      '云端备份' => 'Cloud Backup',
      '用户' => 'Users',
      '用户组' => 'Groups',
      '公告' => 'Announcements',
      '许愿与反馈' => 'Feedback',
      '邀请码' => 'Invites',
      '日志' => 'Logs',
      _ => zhTitle,
    };
  }

  static List<(IconData, String)> get moduleTabsMeta => [
    (Icons.dashboard_outlined, tabTitleForIndex(0)),
    (Icons.tune, tabTitleForIndex(1)),
    (Icons.auto_awesome, tabTitleForIndex(2)),
    (Icons.cloud_outlined, tabTitleForIndex(3)),
    (Icons.people_outline, tabTitleForIndex(4)),
    (Icons.groups_2_outlined, tabTitleForIndex(5)),
    (Icons.campaign_outlined, tabTitleForIndex(6)),
    (Icons.feedback_outlined, tabTitleForIndex(7)),
    (Icons.vpn_key_outlined, tabTitleForIndex(8)),
    (Icons.receipt_long_outlined, tabTitleForIndex(9)),
  ];

  // ---------------------------------------------------------------------------
  // Common Actions
  // ---------------------------------------------------------------------------
  static String reloadFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '重新加载' : 'Reload';
  }

  static String get reload => reloadFor(I18n.current);

  static String retryFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '重试' : 'Retry';
  }

  static String get retry => retryFor(I18n.current);

  static String cancelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '取消' : 'Cancel';
  }

  static String get cancel => cancelFor(I18n.current);

  static String cancelBtnFor([AppLocale? locale]) => cancelFor(locale);

  static String get cancelBtn => cancel;

  static String saveFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '保存' : 'Save';
  }

  static String get save => saveFor(I18n.current);

  static String saveBtnFor([AppLocale? locale]) => saveFor(locale);

  static String get saveBtn => save;

  static String deleteFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '删除' : 'Delete';
  }

  static String get delete => deleteFor(I18n.current);

  static String wipeFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '清空' : 'Clear';
  }

  static String get wipe => wipeFor(I18n.current);

  static String refreshFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '刷新' : 'Refresh';
  }

  static String get refresh => refreshFor(I18n.current);

  static String refreshBtnFor([AppLocale? locale]) => refreshFor(locale);

  static String get refreshBtn => refresh;

  static String closeFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '关闭' : 'Close';
  }

  static String get close => closeFor(I18n.current);

  static String enabledFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '启用' : 'Active';
  }

  static String get enabled => enabledFor(I18n.current);

  static String disabledFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '停用' : 'Inactive';
  }

  static String get disabled => disabledFor(I18n.current);

  static String unnamedGroupFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '未命名用户组' : 'Unnamed Group';
  }

  static String get unnamedGroup => unnamedGroupFor(I18n.current);

  static String unnamedRoleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '未命名角色' : 'Unnamed Role';
  }

  static String get unnamedRole => unnamedRoleFor(I18n.current);

  static String userCountLabel(int count, [AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '$count 人' : (count == 1 ? '1 user' : '$count users');
  }

  static String groupCardCoinsLabel(int coins, [AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '默认时光币\n$coins' : 'Default Time Coins\n$coins';
  }

  static String editGroupTooltipFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '编辑用户组' : 'Edit group';
  }

  static String get editGroupTooltip => editGroupTooltipFor(I18n.current);

  static String deleteGroupTooltipFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '删除用户组' : 'Delete group';
  }

  static String get deleteGroupTooltip => deleteGroupTooltipFor(I18n.current);

  static String editRoleTooltipFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '编辑角色' : 'Edit role';
  }

  static String get editRoleTooltip => editRoleTooltipFor(I18n.current);

  static String configuredLeaveUnchanged([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '已配置，保持不动即不修改' : 'Configured (leave unchanged to keep)';
  }

  static String savingEllipsis([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '保存中…' : 'Saving...';
  }

  static String backingUpEllipsis([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '备份中…' : 'Backing up...';
  }

  static String sendingEllipsis([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '发送中…' : 'Sending...';
  }

  static String exportingEllipsis([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '导出中…' : 'Exporting...';
  }

  // ---------------------------------------------------------------------------
  // Pagination & List Helpers
  // ---------------------------------------------------------------------------
  static String perPageFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '每页' : 'Per page';
  }

  static String get perPage => perPageFor(I18n.current);

  static String pageNumberFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '页码' : 'Page';
  }

  static String get pageNumber => pageNumberFor(I18n.current);

  static String jumpToFirstPageFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '跳到第一页' : 'Jump to first page';
  }

  static String get jumpToFirstPage => jumpToFirstPageFor(I18n.current);

  static String previousPageFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '上一页' : 'Previous page';
  }

  static String get previousPage => previousPageFor(I18n.current);

  static String nextPageFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '下一页' : 'Next page';
  }

  static String get nextPage => nextPageFor(I18n.current);

  static String jumpToLastPageFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '跳到最后一页' : 'Jump to last page';
  }

  static String get jumpToLastPage => jumpToLastPageFor(I18n.current);

  static String paginationNavigationFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '分页导航' : 'Page navigation';
  }

  static String get paginationNavigation =>
      paginationNavigationFor(I18n.current);

  // ---------------------------------------------------------------------------
  // Permissions & Roles
  // ---------------------------------------------------------------------------
  static String allPermissionsFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '全部权限' : 'All Permissions';
  }

  static String get allPermissions => allPermissionsFor(I18n.current);

  static String noAdminPermissionsFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '无管理权限' : 'No admin permissions';
  }

  static String get noAdminPermissions => noAdminPermissionsFor(I18n.current);

  static String permissionGroupTitle(String zhTitle, [AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    if (zh) return zhTitle;
    return switch (zhTitle) {
      '基础功能' => 'Core Features',
      '个人数据' => 'Personal Data',
      '管理功能' => 'Management',
      '系统功能' => 'System Features',
      _ => zhTitle,
    };
  }

  static String permissionLabel(String key, [AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return switch (key) {
      'settings' => zh ? '全站设置' : 'Settings',
      'users' => zh ? '用户' : 'Users',
      'coins' => zh ? '时光币' : 'Time Coins',
      'backup' => zh ? '备份' : 'Backup',
      'ai' => 'AI',
      'announcements' => zh ? '公告' : 'Announcements',
      'feedback' => zh ? '反馈' : 'Feedback',
      'invites' => zh ? '邀请码' : 'Invites',
      'audit' => zh ? '日志' : 'Logs',
      'groups' => zh ? '用户组' : 'Groups',
      'roles' => zh ? '角色' : 'Roles',
      'permissions' => zh ? '权限字典' : 'Permissions Dict',
      '*' => zh ? '全部权限' : 'All Permissions',
      _ => key,
    };
  }

  static String statusLabel(String value, [AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return switch (value) {
      'open' => zh ? '待处理' : 'Open',
      'in_progress' => zh ? '处理中' : 'In Progress',
      'resolved' => zh ? '已解决' : 'Resolved',
      'closed' => zh ? '已关闭' : 'Closed',
      'published' => zh ? '已发布' : 'Published',
      'draft' => zh ? '草稿' : 'Draft',
      'used' => zh ? '已使用' : 'Used',
      'unused' => zh ? '未使用' : 'Unused',
      'admin' => zh ? '管理员' : 'Admin',
      'disabled' => zh ? '已禁用' : 'Disabled',
      'active' => zh ? '可登录' : 'Active',
      'normal' => zh ? '普通用户' : 'Standard User',
      'online' => zh ? '在线' : 'Online',
      'offline' => zh ? '离线' : 'Offline',
      'unverified_email' => zh ? '邮箱未验证' : 'Unverified Email',
      'verified_email' => zh ? '邮箱已验证' : 'Email Verified',
      'no_email' => zh ? '未绑定邮箱' : 'No Email',
      'has_feedback' => zh ? '有反馈' : 'Has Feedback',
      'info' => zh ? '普通' : 'Info',
      'warning' => zh ? '重要' : 'Warning',
      'critical' => zh ? '紧急' : 'Critical',
      'uploaded' => zh ? '已上传' : 'Uploaded',
      'local_only' => zh ? '仅本地' : 'Local Only',
      'local_created_remote_failed' => zh ? '远端失败' : 'Remote Failed',
      'created' => zh ? '已创建' : 'Created',
      _ => value.isEmpty ? (zh ? '全部' : 'All') : value,
    };
  }

  static String backupSortLabel(String value, [AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return switch (value) {
      'username_asc' => zh ? '用户名 A-Z' : 'Username A-Z',
      'size_desc' => zh ? '备份体积从大到小' : 'Size (Largest first)',
      'size_asc' => zh ? '备份体积从小到大' : 'Size (Smallest first)',
      'version_desc' => zh ? '同步版本较高优先' : 'Sync version (Highest)',
      _ => zh ? '最近同步优先' : 'Recently synced first',
    };
  }

  static String serverBackupSortOptionLabel(String value, [AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return switch (value) {
      'size_desc' => zh ? '文件从大到小' : 'Size (Largest first)',
      'size_asc' => zh ? '文件从小到大' : 'Size (Smallest first)',
      'status_asc' => zh ? '状态 A-Z' : 'Status A-Z',
      'filename_asc' => zh ? '文件名 A-Z' : 'Filename A-Z',
      _ => zh ? '最新生成优先' : 'Newest first',
    };
  }

  static String backupSortOptionLabel(String value, [AppLocale? locale]) =>
      backupSortLabel(value, locale);

  // ---------------------------------------------------------------------------
  // Action Error Formatting
  // ---------------------------------------------------------------------------
  static String formatActionError(
    Object error,
    String action, {
    AppLocale? locale,
  }) {
    final effectiveLocale = locale ?? I18n.current;
    final zh = effectiveLocale == AppLocale.zh;
    final text = userVisibleApiError(error, locale: effectiveLocale);
    return zh ? '$action失败：$text' : '$action failed: $text';
  }

  // ---------------------------------------------------------------------------
  // Dashboard Tab
  // ---------------------------------------------------------------------------
  static String get dashboardData => isZh ? '概览数据' : 'dashboard data';
  static String get dashboardLoadFailed =>
      isZh ? '概览加载失败，请重试' : 'Failed to load dashboard. Please try again.';
  static String get dashboardRefreshFailed =>
      isZh ? '概览刷新失败' : 'Dashboard refresh failed';

  static String dashboardRefreshFailedWith(String error, [AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '概览刷新失败：$error' : 'Dashboard refresh failed: $error';
  }

  static String get updatingDashboardData =>
      isZh ? '正在更新概览数据' : 'Updating dashboard data...';

  static String get clientConnection => isZh ? '客户端连接' : 'Client Connection';
  static String get relativeSameOriginProxy =>
      isZh ? '相对路径 (同域反代)' : 'Relative path (same-origin proxy)';

  // KPI Metrics
  static String get kpiTotalUsers => isZh ? '总用户' : 'Total Users';
  static String get kpiAdmins => isZh ? '管理员' : 'Admins';
  static String get kpiDisabled => isZh ? '已禁用' : 'Disabled';
  static String get kpiNewToday => isZh ? '今日新增' : 'New Today';
  static String get kpiActive7d => isZh ? '7 日活跃' : '7d Active';
  static String get kpiOnline => isZh ? '在线' : 'Online';
  static String get kpiUnverifiedEmail => isZh ? '邮箱未验证' : 'Unverified Email';
  static String get kpiOpenFeedback => isZh ? '待处理反馈' : 'Open Feedback';
  static String get kpiInProgressFeedback => isZh ? '处理中反馈' : 'In Progress';
  static String get kpiTotalFeedback => isZh ? '反馈总数' : 'Total Feedback';
  static String get kpiPublishedAnnouncements =>
      isZh ? '公告(已发)' : 'Announcements (Sent)';
  static String get kpiInvitesUsed => isZh ? '邀请码已用' : 'Invites Used';

  // Registration Series
  static String get recentRegistrations7d =>
      isZh ? '近 7 天注册' : 'Registrations (Last 7 Days)';
  static String get noRegistrations => isZh ? '暂无注册' : 'No registrations';

  // ---------------------------------------------------------------------------
  // Module 1: Site Settings Tab
  // ---------------------------------------------------------------------------
  static String settingsTabTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '全站设置' : 'Site Settings';
  }

  static String get settingsTabTitle => settingsTabTitleFor(I18n.current);

  static String settingsTargetFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '全站设置' : 'site settings';
  }

  static String get settingsTarget => settingsTargetFor(I18n.current);

  static String groupsTargetFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '用户组' : 'user groups';
  }

  static String get groupsTarget => groupsTargetFor(I18n.current);

  static String rolesTargetFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '角色' : 'roles';
  }

  static String get rolesTarget => rolesTargetFor(I18n.current);

  static String settingsUpdatedFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '设置已更新' : 'Settings updated';
  }

  static String get settingsUpdated => settingsUpdatedFor(I18n.current);

  static String missingGroupsPermissionFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '缺少用户组管理权限' : 'Missing permission to manage user groups';
  }

  static String get missingGroupsPermission =>
      missingGroupsPermissionFor(I18n.current);

  static String missingRolesPermissionFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '缺少角色管理权限' : 'Missing permission to manage roles';
  }

  static String get missingRolesPermission =>
      missingRolesPermissionFor(I18n.current);

  static String addGroupTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '新增用户组' : 'Add User Group';
  }

  static String get addGroupTitle => addGroupTitleFor(I18n.current);

  static String editGroupTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '编辑用户组' : 'Edit User Group';
  }

  static String get editGroupTitle => editGroupTitleFor(I18n.current);

  static String groupNameLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '用户组名称' : 'Group Name';
  }

  static String get groupNameLabel => groupNameLabelFor(I18n.current);

  static String groupDescriptionLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '说明' : 'Description';
  }

  static String get groupDescriptionLabel =>
      groupDescriptionLabelFor(I18n.current);

  static String groupDescriptionHelperFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '用于管理员识别该组适用的人群或规则'
        : 'Helps admins identify the intended audience or rules for this group';
  }

  static String get groupDescriptionHelper =>
      groupDescriptionHelperFor(I18n.current);

  static String groupDefaultCoinsLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '默认时光币' : 'Default Time Coins';
  }

  static String get groupDefaultCoinsLabel =>
      groupDefaultCoinsLabelFor(I18n.current);

  static String groupDefaultCoinsHelperFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '新注册或分配到该组时使用的默认额度'
        : 'Default quota allocated upon registration or group assignment';
  }

  static String get groupDefaultCoinsHelper =>
      groupDefaultCoinsHelperFor(I18n.current);

  static String groupEnableLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '启用用户组' : 'Enable User Group';
  }

  static String get groupEnableLabel => groupEnableLabelFor(I18n.current);

  static String groupEnableSubtitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '停用后不再作为可分配用户组' : 'Disabled groups cannot be assigned to users';
  }

  static String get groupEnableSubtitle => groupEnableSubtitleFor(I18n.current);

  static String pleaseEnterGroupNameFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '请填写用户组名称' : 'Please enter a group name';
  }

  static String get pleaseEnterGroupName =>
      pleaseEnterGroupNameFor(I18n.current);

  static String groupSavedFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '用户组已保存' : 'User group saved';
  }

  static String get groupSaved => groupSavedFor(I18n.current);

  static String get groupManagementTitle =>
      I18n.current == AppLocale.zh ? '用户组管理' : 'User Groups';
  static String get groupManagementSubtitle => I18n.current == AppLocale.zh
      ? '设置各组的默认时光币额度和启用状态'
      : 'Set default time coins and availability for each group';
  static String get groupDefaultQuotaTitle =>
      I18n.current == AppLocale.zh ? '默认额度' : 'Default Quota';
  static String get groupDefaultQuotaMessage => I18n.current == AppLocale.zh
      ? '新用户注册后按所属用户组设置的默认额度发放时光币。'
      : 'New users receive the default time coins set for their assigned group.';
  static String get noGroups =>
      I18n.current == AppLocale.zh ? '暂无用户组' : 'No user groups yet';

  static String defaultGroupCannotDeleteFor([AppLocale? locale]) =>
      (locale ?? I18n.current) == AppLocale.zh
      ? '默认用户组不能删除'
      : 'The default user group cannot be deleted';
  static String deleteGroupTitle(String name, [AppLocale? locale]) =>
      (locale ?? I18n.current) == AppLocale.zh
      ? '删除用户组 $name'
      : 'Delete User Group $name';
  static String deleteGroupBody(int count, [AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    if (count <= 0) {
      return zh ? '删除后不会影响已有用户数据。' : 'Existing user data will be kept.';
    }
    return zh
        ? '该组内 $count 个用户会回退到默认用户组，已有时光币记录保留。'
        : '$count ${count == 1 ? 'user will' : 'users will'} move to the default group. Existing time coin records will be kept.';
  }

  static String groupDeleted(int count, [AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    if (count <= 0) return zh ? '用户组已删除' : 'User group deleted';
    return zh
        ? '用户组已删除，$count 个用户已回退到默认组'
        : 'User group deleted. $count ${count == 1 ? 'user moved' : 'users moved'} to the default group';
  }

  static String actionDeleteGroupFor([AppLocale? locale]) =>
      (locale ?? I18n.current) == AppLocale.zh ? '删除用户组' : 'delete user group';
  static String groupSavedRefreshFailedFor([AppLocale? locale]) =>
      (locale ?? I18n.current) == AppLocale.zh
      ? '用户组已保存，列表刷新失败，请重试'
      : 'User group saved. Refresh failed; please retry';
  static String groupDeletedRefreshFailedFor([AppLocale? locale]) =>
      (locale ?? I18n.current) == AppLocale.zh
      ? '用户组已删除，列表刷新失败，请重试'
      : 'User group deleted. Refresh failed; please retry';

  static String addRoleTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '新增角色' : 'Add Role';
  }

  static String get addRoleTitle => addRoleTitleFor(I18n.current);

  static String editRoleTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '编辑角色' : 'Edit Role';
  }

  static String get editRoleTitle => editRoleTitleFor(I18n.current);

  static String roleNameLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '角色名称' : 'Role Name';
  }

  static String get roleNameLabel => roleNameLabelFor(I18n.current);

  static String roleDescriptionLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '说明' : 'Description';
  }

  static String get roleDescriptionLabel =>
      roleDescriptionLabelFor(I18n.current);

  static String roleDescriptionHelperFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '说明该角色的适用对象或权限边界'
        : 'Describes the intended role holders and permission boundaries';
  }

  static String get roleDescriptionHelper =>
      roleDescriptionHelperFor(I18n.current);

  static String roleEnableLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '启用角色' : 'Enable Role';
  }

  static String get roleEnableLabel => roleEnableLabelFor(I18n.current);

  static String roleEnableSubtitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '停用后不再作为可分配角色' : 'Disabled roles cannot be assigned';
  }

  static String get roleEnableSubtitle => roleEnableSubtitleFor(I18n.current);

  static String pleaseEnterRoleNameFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '请填写角色名称' : 'Please enter a role name';
  }

  static String get pleaseEnterRoleName => pleaseEnterRoleNameFor(I18n.current);

  static String roleSavedFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '角色已保存' : 'Role saved';
  }

  static String get roleSaved => roleSavedFor(I18n.current);

  static String updateConfigSavedFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '更新配置已保存' : 'Update configuration saved';
  }

  static String get updateConfigSaved => updateConfigSavedFor(I18n.current);

  static String versionPresetCurrentFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '当前版本' : 'Current Version';
  }

  static String get versionPresetCurrent =>
      versionPresetCurrentFor(I18n.current);

  static String versionPresetNextPatchFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '下一补丁' : 'Next Patch';
  }

  static String get versionPresetNextPatch =>
      versionPresetNextPatchFor(I18n.current);

  static String versionPresetNextMinorFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '下一小版本' : 'Next Minor';
  }

  static String get versionPresetNextMinor =>
      versionPresetNextMinorFor(I18n.current);

  static String versionPresetMinimumNextPatchFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '强制低于下一补丁' : 'Force Below Next Patch';
  }

  static String get versionPresetMinimumNextPatch =>
      versionPresetMinimumNextPatchFor(I18n.current);

  static String minimumVersionPrefixFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '最低' : 'Min';
  }

  static String get minimumVersionPrefix =>
      minimumVersionPrefixFor(I18n.current);

  static String versionOptionLabel(
    String key, {
    String? fallback,
    AppLocale? locale,
  }) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return switch (key) {
      'current' => zh ? '当前版本' : 'Current Version',
      'next_patch' => zh ? '下一补丁' : 'Next Patch',
      'next_minor' => zh ? '下一小版本' : 'Next Minor',
      'minimum_next_patch' => zh ? '强制低于下一补丁' : 'Force Below Next Patch',
      _ => fallback ?? key,
    };
  }

  static String defaultUpdateNotes(String version, {AppLocale? locale}) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    if (zh) {
      return [
        '本次更新摘要：',
        '- 版本 $version 包含近期问题修复与稳定性优化。',
        '- 安装包与完整发布说明由后端发布通道自动读取。',
        '- 若管理员开启强制更新，客户端会遮挡当前页面直到完成更新。',
      ].join('\n');
    }
    return [
      'Update summary:',
      '- Version $version includes recent bug fixes and stability improvements.',
      '- Installation packages and full release notes are automatically resolved by the backend release channel.',
      '- If force update is enabled, the client locks the current screen until the update is completed.',
    ].join('\n');
  }

  static String groupsAndRolesTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '用户组与角色' : 'Groups & Roles';
  }

  static String get groupsAndRolesTitle => groupsAndRolesTitleFor(I18n.current);

  static String groupsAndRolesSubtitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '管理默认时光币、成员分组和管理员权限模板'
        : 'Manage default time coins, user grouping, and admin permission templates';
  }

  static String get groupsAndRolesSubtitle =>
      groupsAndRolesSubtitleFor(I18n.current);

  static String groupsRolesSummary(int groups, int roles, [AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '用户组 $groups 个 · 角色 $roles 个' : '$groups groups · $roles roles';
  }

  static String addGroupBtnFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '用户组' : 'Group';
  }

  static String get addGroupBtn => addGroupBtnFor(I18n.current);

  static String addRoleBtnFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '角色' : 'Role';
  }

  static String get addRoleBtn => addRoleBtnFor(I18n.current);

  static String groupsRolesLoadFailedFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '用户组或角色加载失败' : 'Failed to load user groups or roles';
  }

  static String get groupsRolesLoadFailed =>
      groupsRolesLoadFailedFor(I18n.current);

  static String noManageableGroupsFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '暂无可管理用户组' : 'No manageable user groups';
  }

  static String get noManageableGroups => noManageableGroupsFor(I18n.current);

  static String noManageableRolesFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '暂无可管理角色' : 'No manageable roles';
  }

  static String get noManageableRoles => noManageableRolesFor(I18n.current);

  static String emptyBackendReturnFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '后端返回为空。' : 'Backend returned empty.';
  }

  static String get emptyBackendReturn => emptyBackendReturnFor(I18n.current);

  static String errorAboveExplainsWhyFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '上方错误说明了未能加载的原因。'
        : 'The error message above explains why loading failed.';
  }

  static String get errorAboveExplainsWhy =>
      errorAboveExplainsWhyFor(I18n.current);

  static String accountsRegistrationSectionTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '账户、注册与用户组' : 'Accounts, Registration & Groups';
  }

  static String get accountsRegistrationSectionTitle =>
      accountsRegistrationSectionTitleFor(I18n.current);

  static String accountsRegistrationSectionSubtitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '控制新用户入口、邀请码、邮箱验证和默认用户组额度'
        : 'Manage registration entry, invite codes, email verification, and default group quota';
  }

  static String get accountsRegistrationSectionSubtitle =>
      accountsRegistrationSectionSubtitleFor(I18n.current);

  static String registrationEnabledTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '允许注册' : 'Allow Registration';
  }

  static String get registrationEnabledTitle =>
      registrationEnabledTitleFor(I18n.current);

  static String registrationEnabledSubtitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '关闭后仅允许已有账号登录'
        : 'When disabled, only existing accounts can log in';
  }

  static String get registrationEnabledSubtitle =>
      registrationEnabledSubtitleFor(I18n.current);

  static String inviteCodeRequiredTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '注册需要邀请码' : 'Require Invite Code';
  }

  static String get inviteCodeRequiredTitle =>
      inviteCodeRequiredTitleFor(I18n.current);

  static String inviteCodeRequiredSubtitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '只有带邀请码才能注册' : 'Registration requires an invite code';
  }

  static String get inviteCodeRequiredSubtitle =>
      inviteCodeRequiredSubtitleFor(I18n.current);

  static String registrationEmailRequiredTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '注册邮箱验证' : 'Email Verification for Registration';
  }

  static String get registrationEmailRequiredTitle =>
      registrationEmailRequiredTitleFor(I18n.current);

  static String registrationEmailRequiredSubtitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '新账号必须填写邮箱并通过验证码后才能创建'
        : 'New accounts must verify their email before sign-up';
  }

  static String get registrationEmailRequiredSubtitle =>
      registrationEmailRequiredSubtitleFor(I18n.current);

  static String defaultCoinsLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '默认用户组时光币' : 'Default Group Time Coins';
  }

  static String get defaultCoinsLabel => defaultCoinsLabelFor(I18n.current);

  static String defaultCoinsHelperFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '新注册普通用户默认获得的额度，管理员可继续在用户列表单独调整'
        : 'Default quota allocated to new users; admins can adjust per user';
  }

  static String get defaultCoinsHelper => defaultCoinsHelperFor(I18n.current);

  static String maintenanceSectionTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '维护模式' : 'Maintenance Mode';
  }

  static String get maintenanceSectionTitle =>
      maintenanceSectionTitleFor(I18n.current);

  static String maintenanceSectionSubtitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '控制同步服务与客户端提示'
        : 'Control cloud sync availability and client notice';
  }

  static String get maintenanceSectionSubtitle =>
      maintenanceSectionSubtitleFor(I18n.current);

  static String maintenanceModeTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '启用维护模式' : 'Enable Maintenance Mode';
  }

  static String get maintenanceModeTitle =>
      maintenanceModeTitleFor(I18n.current);

  static String maintenanceModeSubtitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '开启后暂停云同步，并在登录页展示维护公告'
        : 'Pauses cloud sync and displays maintenance banner on login screen';
  }

  static String get maintenanceModeSubtitle =>
      maintenanceModeSubtitleFor(I18n.current);

  static String maintenanceMessageLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '维护公告文字' : 'Maintenance Message';
  }

  static String get maintenanceMessageLabel =>
      maintenanceMessageLabelFor(I18n.current);

  static String maintenanceMessageHintFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '将在客户端登录/同步报错时展示'
        : 'Shown on client login and sync error dialogues';
  }

  static String get maintenanceMessageHint =>
      maintenanceMessageHintFor(I18n.current);

  static String appUpdateSectionTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '应用更新' : 'App Updates';
  }

  static String get appUpdateSectionTitle =>
      appUpdateSectionTitleFor(I18n.current);

  static String appUpdateSectionSubtitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '设置更新提示、最低支持版本与强制更新策略'
        : 'Configure update prompt, minimum supported version, and force update policy';
  }

  static String get appUpdateSectionSubtitle =>
      appUpdateSectionSubtitleFor(I18n.current);

  static String forceUpdateTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '强制更新' : 'Force Update';
  }

  static String get forceUpdateTitle => forceUpdateTitleFor(I18n.current);

  static String forceUpdateSubtitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '有可安装的新版本时，用户需完成更新后继续使用'
        : 'When a new installable version is available, users must update before continuing';
  }

  static String get forceUpdateSubtitle => forceUpdateSubtitleFor(I18n.current);

  static String currentClientVersionTitle(String name, [AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '当前客户端版本 $name' : 'Current Client Version $name';
  }

  static String currentClientVersionMessageFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '普通更新会在“检查更新”和底部“我的”入口显示红点；强制更新会锁定客户端，直到用户安装新版本。安装包与发布说明由后端发布通道自动读取。'
        : 'Standard updates show an update badge in Check for Updates and the Mine tab; force updates lock the client until the update is installed. Installation packages and notes are automatically resolved by the backend.';
  }

  static String get currentClientVersionMessage =>
      currentClientVersionMessageFor(I18n.current);

  static String versionPolicyLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '版本策略' : 'Version Policy';
  }

  static String get versionPolicyLabel => versionPolicyLabelFor(I18n.current);

  static String versionSelectionTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '版本选择' : 'Version Selection';
  }

  static String get versionSelectionTitle =>
      versionSelectionTitleFor(I18n.current);

  static String versionSelectionMessage(
    String latest,
    String min, [
    AppLocale? locale,
  ]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '最新版本：$latest；最低支持版本：$min。管理员只需选择上方策略，无需手动输入版本、安装包地址或更新内容。'
        : 'Latest version: $latest; Minimum supported: $min. Admins only need to select a policy above without typing raw version numbers or download URLs.';
  }

  static String updateNotesPreviewTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '更新内容预览' : 'Release Notes Preview';
  }

  static String get updateNotesPreviewTitle =>
      updateNotesPreviewTitleFor(I18n.current);

  static String updateNotesSaveHintFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '保存时会自动写入以上摘要；安装包地址和完整发布说明由后端发布通道自动读取。'
        : 'Saving automatically records the summary above; download URLs and full changelogs are resolved by the backend release channel.';
  }

  static String get updateNotesSaveHint => updateNotesSaveHintFor(I18n.current);

  static String saveUpdateConfigBtnFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '保存更新配置' : 'Save Update Policy';
  }

  static String get saveUpdateConfigBtn => saveUpdateConfigBtnFor(I18n.current);

  static String serverAddressTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '服务器地址' : 'Server Address';
  }

  static String get serverAddressTitle => serverAddressTitleFor(I18n.current);

  static String serverAddressMessageFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '服务器地址在 APK / Web 构建时就已锁定，运行期不可修改。如需切换后端，请重新构建并分发新版本。'
        : 'The server address is hardcoded at APK / Web build time and cannot be modified at runtime. Rebuild the application to switch backends.';
  }

  static String get serverAddressMessage =>
      serverAddressMessageFor(I18n.current);

  // ---------------------------------------------------------------------------
  // Module 2: AI Settings Tab
  // ---------------------------------------------------------------------------
  static String aiSettingsTabTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? 'AI 配置' : 'AI Config';
  }

  static String get aiSettingsTabTitle => aiSettingsTabTitleFor(I18n.current);

  static String aiConfigSavedFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? 'AI 配置已保存' : 'AI configuration saved';
  }

  static String get aiConfigSaved => aiConfigSavedFor(I18n.current);

  static String aiSectionTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? 'AI 功能' : 'AI Service';
  }

  static String get aiSectionTitle => aiSectionTitleFor(I18n.current);

  static String aiSectionSubtitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '所有请求经后端代理，前端不暴露密钥'
        : 'All AI requests are proxied via backend; frontend never exposes secrets';
  }

  static String get aiSectionSubtitle => aiSectionSubtitleFor(I18n.current);

  static String aiEnableTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '启用 AI 功能' : 'Enable AI Service';
  }

  static String get aiEnableTitle => aiEnableTitleFor(I18n.current);

  static String aiEnableSubtitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '关闭后所有用户都无法使用 AI 拆解/回顾'
        : 'When disabled, AI decomposition and review become unavailable to all users';
  }

  static String get aiEnableSubtitle => aiEnableSubtitleFor(I18n.current);

  static String aiBaseUrlLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '服务地址 (Base URL)' : 'Base URL';
  }

  static String get aiBaseUrlLabel => aiBaseUrlLabelFor(I18n.current);

  static String aiBaseUrlHelperFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '路径后自动加 /v1/chat/completions'
        : 'Automatically appends /v1/chat/completions';
  }

  static String get aiBaseUrlHelper => aiBaseUrlHelperFor(I18n.current);

  static String aiApiKeyConfiguredHelperFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '已配置（显示为掩码，保持不动即不修改）'
        : 'Configured (masked; leave unchanged to keep)';
  }

  static String get aiApiKeyConfiguredHelper =>
      aiApiKeyConfiguredHelperFor(I18n.current);

  static String aiApiKeyNotConfiguredHelperFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '尚未配置' : 'Not configured';
  }

  static String get aiApiKeyNotConfiguredHelper =>
      aiApiKeyNotConfiguredHelperFor(I18n.current);

  static String aiModelLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '模型名称' : 'Model Name';
  }

  static String get aiModelLabel => aiModelLabelFor(I18n.current);

  static String aiDailyQuotaLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '每用户每日调用上限' : 'Daily Quota per User';
  }

  static String get aiDailyQuotaLabel => aiDailyQuotaLabelFor(I18n.current);

  static String aiDailyQuotaHelperFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '0 = 不限' : '0 = unlimited';
  }

  static String get aiDailyQuotaHelper => aiDailyQuotaHelperFor(I18n.current);

  static String aiTestCurrentFormFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '测试当前表单' : 'Test Current Settings';
  }

  static String get aiTestCurrentForm => aiTestCurrentFormFor(I18n.current);

  static String aiSecurityProxyTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '安全代理' : 'Secure Proxy';
  }

  static String get aiSecurityProxyTitle =>
      aiSecurityProxyTitleFor(I18n.current);

  static String aiSecurityProxyMessageFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '所有用户的 AI 请求都通过后端 /api/ai/chat 代理，前端永远拿不到 API Key。'
        : 'All AI requests are proxied via /api/ai/chat; API keys are never leaked to the client.';
  }

  static String get aiSecurityProxyMessage =>
      aiSecurityProxyMessageFor(I18n.current);

  static String unnamedModelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '未命名模型' : 'Unnamed Model';
  }

  static String get unnamedModel => unnamedModelFor(I18n.current);

  static String emptyReplyFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '空回复' : 'Empty response';
  }

  static String get emptyReply => emptyReplyFor(I18n.current);

  static String aiTestSkippedMessage(String model, {AppLocale? locale}) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    final modelLabel = model.isEmpty ? unnamedModelFor(locale) : model;
    return zh
        ? 'AI 功能开关未启用，未测试上游连接。模型：$modelLabel'
        : 'AI service is disabled, upstream connection was not tested. Model: $modelLabel';
  }

  static String aiTestSuccessMessage(
    String model,
    String sample, {
    AppLocale? locale,
  }) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    final modelLabel = model.isEmpty ? unnamedModelFor(locale) : model;
    final sampleText = sample.isEmpty ? emptyReplyFor(locale) : sample;
    return zh
        ? '当前表单配置可达，模型 $modelLabel 回复: $sampleText'
        : 'Form configuration is reachable, model $modelLabel reply: $sampleText';
  }

  static String aiTestDisabledMessage(String model, {AppLocale? locale}) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    final modelLabel = model.isEmpty ? unnamedModelFor(locale) : model;
    return zh
        ? '当前表单配置完整，AI 功能开关未启用，未发起上游请求。模型：$modelLabel'
        : 'Form configuration complete, AI service disabled, no upstream request sent. Model: $modelLabel';
  }

  static String aiFailureReason(Object raw, [AppLocale? locale]) {
    final effectiveLocale = locale ?? I18n.current;
    final zh = effectiveLocale == AppLocale.zh;
    final text = raw is ApiException
        ? userVisibleApiError(raw, locale: effectiveLocale)
        : raw.toString().trim();
    final prefix = zh ? '测试失败：' : 'Test failed: ';
    if (text.isEmpty) {
      return prefix +
          (zh ? 'AI 服务没有返回错误详情' : 'AI service returned no error details');
    }
    if (text.contains('AI 功能未启用')) {
      return prefix +
          (zh
              ? 'AI 功能未启用，请先保存并开启 AI 功能'
              : 'AI service is disabled. Please save and enable AI first');
    }
    if (text.contains('API Key')) {
      return prefix +
          (zh ? '管理员尚未配置 AI API Key' : 'AI API Key is not configured by admin');
    }
    if (text.contains('401') || text.contains('403')) {
      return prefix +
          (zh
              ? 'AI 密钥无效或没有模型权限'
              : 'Invalid AI API Key or insufficient model permissions');
    }
    if (text.contains('429') || text.contains('额度')) {
      return prefix +
          (zh ? '今日 AI 额度已用尽' : "Today's AI quota has been exhausted");
    }
    if (text.contains('404') || text.toLowerCase().contains('not found')) {
      return prefix +
          (zh
              ? 'AI 代理或上游模型不可用，请检查 Base URL、模型名称和后端 /api/admin/ai/test 路由'
              : 'AI proxy or upstream model unavailable. Check Base URL, model name, and backend route');
    }
    if (text.contains('上游不可达') ||
        text.contains('不可达') ||
        text.contains('502')) {
      return prefix +
          (zh
              ? 'AI 上游服务不可达，请检查 Base URL、网络或模型配置'
              : 'AI upstream unreachable. Check Base URL, network, and model config');
    }
    if (text.contains('超时')) {
      return prefix +
          (zh
              ? 'AI 服务响应超时，请稍后重试'
              : 'AI response timed out. Please try again later');
    }
    return '$prefix$text';
  }

  // ---------------------------------------------------------------------------
  // Module 3: Cloud Backup & Server Backup Tab
  // ---------------------------------------------------------------------------
  static String backupSettingsTabTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '备份配置与备份记录' : 'Backup Config & Records';
  }

  static String get backupSettingsTabTitle =>
      backupSettingsTabTitleFor(I18n.current);

  static String backupConfigSavedFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '云端备份配置已保存' : 'Cloud backup settings saved';
  }

  static String get backupConfigSaved => backupConfigSavedFor(I18n.current);

  static String serverBackupExecutedFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '服务器备份已执行' : 'Server backup completed';
  }

  static String get serverBackupExecuted =>
      serverBackupExecutedFor(I18n.current);

  static String testEmailSentFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '测试邮件已发送' : 'Test email sent';
  }

  static String get testEmailSent => testEmailSentFor(I18n.current);

  static String testEmailSentTo(String recipient, [AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '测试邮件已发送到 $recipient' : 'Test email sent to $recipient';
  }

  static String accountTestEmailSent(String channel, [AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '账号测试邮件已发送$channel' : 'Account test email sent$channel';
  }

  static String accountTestEmailSentTo(
    String recipient,
    String channel, [
    AppLocale? locale,
  ]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '账号测试邮件已发送到 $recipient$channel'
        : 'Account test email sent to $recipient$channel';
  }

  static String mailProviderDisabledFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '关闭' : 'Disabled';
  }

  static String get mailProviderDisabled =>
      mailProviderDisabledFor(I18n.current);

  static String wipeBackupDialogTitle(String username, [AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '清空 $username 的云端备份?' : 'Clear cloud backup for $username?';
  }

  static String wipeBackupDialogContentFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '账号保留，但服务器上的同步数据会清零，用户下次同步后本地数据将被覆盖。'
        : 'The account will be retained, but server sync data will be wiped and will overwrite client data upon next sync.';
  }

  static String get wipeBackupDialogContent =>
      wipeBackupDialogContentFor(I18n.current);

  static String exportUserBackupsTextFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '多仪用户备份导出' : 'Duoyi User Backups Export';
  }

  static String get exportUserBackupsText =>
      exportUserBackupsTextFor(I18n.current);

  static String exportUserBackupsSubjectFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '多仪用户备份 CSV' : 'Duoyi User Backups CSV';
  }

  static String get exportUserBackupsSubject =>
      exportUserBackupsSubjectFor(I18n.current);

  static String exportUserBackupsSuccessFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '用户备份 CSV 已导出' : 'User backups CSV exported';
  }

  static String get exportUserBackupsSuccess =>
      exportUserBackupsSuccessFor(I18n.current);

  static String exportServerBackupsTextFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '多仪服务器备份导出' : 'Duoyi Server Backups Export';
  }

  static String get exportServerBackupsText =>
      exportServerBackupsTextFor(I18n.current);

  static String exportServerBackupsSubjectFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '多仪服务器备份 CSV' : 'Duoyi Server Backups CSV';
  }

  static String get exportServerBackupsSubject =>
      exportServerBackupsSubjectFor(I18n.current);

  static String exportServerBackupsSuccessFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '服务器备份 CSV 已导出' : 'Server backups CSV exported';
  }

  static String get exportServerBackupsSuccess =>
      exportServerBackupsSuccessFor(I18n.current);

  static String shareAdminCsvSuccess(
    String label,
    String path, [
    AppLocale? locale,
  ]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '$label，路径已复制：$path' : '$label, path copied: $path';
  }

  static String serverBackupRecordsTabFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '服务器备份记录' : 'Server Backup Records';
  }

  static String get serverBackupRecordsTab =>
      serverBackupRecordsTabFor(I18n.current);

  static String allUserBackupsTabFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '所有用户备份' : 'User Backups';
  }

  static String get allUserBackupsTab => allUserBackupsTabFor(I18n.current);

  static String exportFilteredResultsFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '导出筛选结果' : 'Export Filtered';
  }

  static String get exportFilteredResults =>
      exportFilteredResultsFor(I18n.current);

  static String searchServerBackupsHintFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '搜索文件名、状态、路径或详情' : 'Search filename, status, path, or details';
  }

  static String get searchServerBackupsHint =>
      searchServerBackupsHintFor(I18n.current);

  static String clearServerBackupSearchTooltipFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '清空服务器备份搜索' : 'Clear search';
  }

  static String get clearServerBackupSearchTooltip =>
      clearServerBackupSearchTooltipFor(I18n.current);

  static String allBackupsChipFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '全部备份' : 'All Backups';
  }

  static String get allBackupsChip => allBackupsChipFor(I18n.current);

  static String uploadedChipFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '已上传' : 'Uploaded';
  }

  static String get uploadedChip => uploadedChipFor(I18n.current);

  static String localOnlyChipFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '仅本地' : 'Local Only';
  }

  static String get localOnlyChip => localOnlyChipFor(I18n.current);

  static String remoteFailedChipFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '远端失败' : 'Remote Failed';
  }

  static String get remoteFailedChip => remoteFailedChipFor(I18n.current);

  static String createdChipFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '已创建' : 'Created';
  }

  static String get createdChip => createdChipFor(I18n.current);

  static String serverBackupSortLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '服务器备份排序' : 'Sort Server Backups';
  }

  static String get serverBackupSortLabel =>
      serverBackupSortLabelFor(I18n.current);

  static String emptyServerBackupsMessageFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '当前筛选下没有服务器备份记录。可搜索文件名、状态、路径或详情，也可以切换状态后再看。'
        : 'No server backup records found under current filter. Try searching filename, status, or path, or change filters.';
  }

  static String get emptyServerBackupsMessage =>
      emptyServerBackupsMessageFor(I18n.current);

  static String bytesUnit([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '字节' : 'bytes';
  }

  static String pageTotalMbLabel(String mb, [AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '本页 $mb MB' : 'This page $mb MB';
  }

  static String searchUserBackupsHintFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '搜索用户名、邮箱、昵称或用户 ID'
        : 'Search username, email, nickname, or user ID';
  }

  static String get searchUserBackupsHint =>
      searchUserBackupsHintFor(I18n.current);

  static String clearUserBackupSearchTooltipFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '清空用户备份搜索' : 'Clear search';
  }

  static String get clearUserBackupSearchTooltip =>
      clearUserBackupSearchTooltipFor(I18n.current);

  static String allUsersChipFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '全部用户' : 'All Users';
  }

  static String get allUsersChip => allUsersChipFor(I18n.current);

  static String hasSnapshotChipFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '已有快照' : 'Has Snapshot';
  }

  static String get hasSnapshotChip => hasSnapshotChipFor(I18n.current);

  static String noSnapshotChipFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '无快照' : 'No Snapshot';
  }

  static String get noSnapshotChip => noSnapshotChipFor(I18n.current);

  static String userBackupSortLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '用户备份排序' : 'Sort User Backups';
  }

  static String get userBackupSortLabel => userBackupSortLabelFor(I18n.current);

  static String emptyUserBackupsMessageFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '当前筛选下没有用户备份。可搜索用户名、邮箱、昵称或用户 ID，也可以切换“已有快照/无快照”。'
        : 'No user backups found under current filter. Try searching username, email, nickname, or switch snapshot filter.';
  }

  static String get emptyUserBackupsMessage =>
      emptyUserBackupsMessageFor(I18n.current);

  static String noSyncTime([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '尚无同步时间' : 'No sync time';
  }

  static String noSyncSnapshot([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '尚无同步快照' : 'No snapshot';
  }

  static String nicknamePrefix([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '昵称' : 'Nickname';
  }

  static String emailPrefix([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '邮箱' : 'Email';
  }

  static String syncVersionPrefix([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '版本' : 'Version';
  }

  static String wipeBackupTooltipFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '清空备份' : 'Clear backup';
  }

  static String get wipeBackupTooltip => wipeBackupTooltipFor(I18n.current);

  static String cloudBackupSectionTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '云端备份' : 'Cloud Backup';
  }

  static String get cloudBackupSectionTitle =>
      cloudBackupSectionTitleFor(I18n.current);

  static String cloudBackupSectionSubtitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '限制同步体积、频率与服务开关'
        : 'Configure sync payload limit, frequency, and service availability';
  }

  static String get cloudBackupSectionSubtitle =>
      cloudBackupSectionSubtitleFor(I18n.current);

  static String cloudBackupEnableTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '启用云端备份' : 'Enable Cloud Backup';
  }

  static String get cloudBackupEnableTitle =>
      cloudBackupEnableTitleFor(I18n.current);

  static String cloudBackupEnableSubtitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '关闭后暂停所有账号的云同步'
        : 'When disabled, cloud sync is paused for all accounts';
  }

  static String get cloudBackupEnableSubtitle =>
      cloudBackupEnableSubtitleFor(I18n.current);

  static String backupMaxSizeLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '单用户同步大小上限 (KB)' : 'Max Sync Payload per User (KB)';
  }

  static String get backupMaxSizeLabel => backupMaxSizeLabelFor(I18n.current);

  static String backupMaxSizeHelperFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '0 = 不限，默认 2048' : '0 = unlimited, default 2048';
  }

  static String get backupMaxSizeHelper => backupMaxSizeHelperFor(I18n.current);

  static String backupIntervalLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '客户端最小自动同步间隔 (分钟)' : 'Min Auto-Sync Interval (minutes)';
  }

  static String get backupIntervalLabel => backupIntervalLabelFor(I18n.current);

  static String backupIntervalHelperFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '用于客户端回退策略参考' : 'Reference for client fallback frequency';
  }

  static String get backupIntervalHelper =>
      backupIntervalHelperFor(I18n.current);

  static String backupRetainLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '备份历史保留天数' : 'Retention Period (days)';
  }

  static String get backupRetainLabel => backupRetainLabelFor(I18n.current);

  static String backupRetainHelperFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '0 = 永久保留 (当前后端仅保留最新快照)'
        : '0 = forever (backend currently stores latest snapshot only)';
  }

  static String get backupRetainHelper => backupRetainHelperFor(I18n.current);

  static String serverBackupSectionTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '服务器备份' : 'Server Backup';
  }

  static String get serverBackupSectionTitle =>
      serverBackupSectionTitleFor(I18n.current);

  static String serverBackupSectionSubtitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '定期打包后台数据库，上传到 OpenList，并可邮件通知'
        : 'Periodically archive server database, upload to OpenList, and dispatch email notices';
  }

  static String get serverBackupSectionSubtitle =>
      serverBackupSectionSubtitleFor(I18n.current);

  static String serverBackupEnableTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '启用服务器定期备份' : 'Enable Scheduled Server Backup';
  }

  static String get serverBackupEnableTitle =>
      serverBackupEnableTitleFor(I18n.current);

  static String serverBackupEnableSubtitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '后台进程按间隔生成数据库 ZIP 快照'
        : 'Background task generates database ZIP snapshot';
  }

  static String get serverBackupEnableSubtitle =>
      serverBackupEnableSubtitleFor(I18n.current);

  static String serverBackupIntervalLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '服务器备份间隔 (分钟)' : 'Backup Interval (minutes)';
  }

  static String get serverBackupIntervalLabel =>
      serverBackupIntervalLabelFor(I18n.current);

  static String serverBackupRetainLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '本地保留天数' : 'Local Retention (days)';
  }

  static String get serverBackupRetainLabel =>
      serverBackupRetainLabelFor(I18n.current);

  static String openlistEnableTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '上传到 OpenList' : 'Upload to OpenList';
  }

  static String get openlistEnableTitle => openlistEnableTitleFor(I18n.current);

  static String openlistEnableSubtitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '使用 OpenList WebDAV 保存服务器备份包'
        : 'Archive backups to OpenList WebDAV storage';
  }

  static String get openlistEnableSubtitle =>
      openlistEnableSubtitleFor(I18n.current);

  static String openlistPublicUrlLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? 'OpenList 公开 URL (可选)' : 'OpenList Public URL (Optional)';
  }

  static String get openlistPublicUrlLabel =>
      openlistPublicUrlLabelFor(I18n.current);

  static String openlistUserLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? 'OpenList 用户名' : 'OpenList Username';
  }

  static String get openlistUserLabel => openlistUserLabelFor(I18n.current);

  static String openlistPasswordLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? 'OpenList 密码' : 'OpenList Password';
  }

  static String get openlistPasswordLabel =>
      openlistPasswordLabelFor(I18n.current);

  static String openlistPathLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? 'OpenList 备份目录' : 'OpenList Backup Path';
  }

  static String get openlistPathLabel => openlistPathLabelFor(I18n.current);

  static String backupEmailEnableTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '备份完成后发送邮件' : 'Send Email on Completion';
  }

  static String get backupEmailEnableTitle =>
      backupEmailEnableTitleFor(I18n.current);

  static String backupEmailEnableSubtitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '支持 SMTP，失败会写入备份记录'
        : 'Sends email via SMTP; logged to backup records on failure';
  }

  static String get backupEmailEnableSubtitle =>
      backupEmailEnableSubtitleFor(I18n.current);

  static String noticeRecipientLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '通知收件人' : 'Notification Recipient';
  }

  static String get noticeRecipientLabel =>
      noticeRecipientLabelFor(I18n.current);

  static String senderLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '发件人' : 'Sender';
  }

  static String get senderLabel => senderLabelFor(I18n.current);

  static String smtpPortLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? 'SMTP 端口' : 'SMTP Port';
  }

  static String get smtpPortLabel => smtpPortLabelFor(I18n.current);

  static String smtpUsernameLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? 'SMTP 用户名' : 'SMTP Username';
  }

  static String get smtpUsernameLabel => smtpUsernameLabelFor(I18n.current);

  static String smtpPasswordLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? 'SMTP 密码' : 'SMTP Password';
  }

  static String get smtpPasswordLabel => smtpPasswordLabelFor(I18n.current);

  static String accountEmailEnableTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '账号验证码邮件' : 'Account Verification Emails';
  }

  static String get accountEmailEnableTitle =>
      accountEmailEnableTitleFor(I18n.current);

  static String accountEmailEnableSubtitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '注册验证、邮箱登录和找回密码共用主备通道'
        : 'Sign-up verification, magic links, and password resets use dual routing';
  }

  static String get accountEmailEnableSubtitle =>
      accountEmailEnableSubtitleFor(I18n.current);

  static String emailTitleLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '账号邮件标题' : 'Email Subject Prefix';
  }

  static String get emailTitleLabel => emailTitleLabelFor(I18n.current);

  static String emailTitleHelperFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '兼容 RE0 的 TITLE，默认使用多仪'
        : 'Compatible with RE0 TITLE; defaults to Duoyi';
  }

  static String get emailTitleHelper => emailTitleHelperFor(I18n.current);

  static String emailSenderNameLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '账号邮件发件人显示名' : 'Sender Display Name';
  }

  static String get emailSenderNameLabel =>
      emailSenderNameLabelFor(I18n.current);

  static String primaryChannelLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '主通道' : 'Primary Channel';
  }

  static String get primaryChannelLabel => primaryChannelLabelFor(I18n.current);

  static String backupChannelLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '备用通道' : 'Backup Channel';
  }

  static String get backupChannelLabel => backupChannelLabelFor(I18n.current);

  static String activePriorityChannelLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '当前优先线路' : 'Active Priority Route';
  }

  static String get activePriorityChannelLabel =>
      activePriorityChannelLabelFor(I18n.current);

  static String primaryChannelItemFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '主通道' : 'Primary Channel';
  }

  static String get primaryChannelItem => primaryChannelItemFor(I18n.current);

  static String backupChannelItemFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '备用通道' : 'Backup Channel';
  }

  static String get backupChannelItem => backupChannelItemFor(I18n.current);

  static String autoSwitchOnSuccessTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '备用成功后自动切换' : 'Auto-switch after backup success';
  }

  static String get autoSwitchOnSuccessTitle =>
      autoSwitchOnSuccessTitleFor(I18n.current);

  static String claw163EmailLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? 'Claw163 发件邮箱' : 'Claw163 Sender Email';
  }

  static String get claw163EmailLabel => claw163EmailLabelFor(I18n.current);

  static String resendBaseUrlLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? 'Resend 服务地址' : 'Resend Base URL';
  }

  static String get resendBaseUrlLabel => resendBaseUrlLabelFor(I18n.current);

  static String resendSenderLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? 'Resend 发件人' : 'Resend Sender';
  }

  static String get resendSenderLabel => resendSenderLabelFor(I18n.current);

  static String systemNoticeRecipientLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '系统通知收件人' : 'System Notice Recipient';
  }

  static String get systemNoticeRecipientLabel =>
      systemNoticeRecipientLabelFor(I18n.current);

  static String systemNoticeRecipientHelperFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '多个邮箱用逗号分隔' : 'Separate multiple emails with commas';
  }

  static String get systemNoticeRecipientHelper =>
      systemNoticeRecipientHelperFor(I18n.current);

  static String accountSmtpHostLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '账号 SMTP Host' : 'Account SMTP Host';
  }

  static String get accountSmtpHostLabel =>
      accountSmtpHostLabelFor(I18n.current);

  static String accountSmtpPortLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '账号 SMTP 端口' : 'Account SMTP Port';
  }

  static String get accountSmtpPortLabel =>
      accountSmtpPortLabelFor(I18n.current);

  static String accountSmtpUserLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '账号 SMTP 用户名' : 'Account SMTP Username';
  }

  static String get accountSmtpUserLabel =>
      accountSmtpUserLabelFor(I18n.current);

  static String accountSmtpFromLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '账号 SMTP 发件地址' : 'Account SMTP From Address';
  }

  static String get accountSmtpFromLabel =>
      accountSmtpFromLabelFor(I18n.current);

  static String accountSmtpFromHelperFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '留空时使用账号 SMTP 用户名'
        : 'When left empty, uses Account SMTP Username';
  }

  static String get accountSmtpFromHelper =>
      accountSmtpFromHelperFor(I18n.current);

  static String accountSmtpPasswordLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '账号 SMTP 密码' : 'Account SMTP Password';
  }

  static String get accountSmtpPasswordLabel =>
      accountSmtpPasswordLabelFor(I18n.current);

  static String accountSmtpUseSslTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '账号 SMTP 使用 SSL' : 'Account SMTP Use SSL';
  }

  static String get accountSmtpUseSslTitle =>
      accountSmtpUseSslTitleFor(I18n.current);

  static String reminderEmailEnableTitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '邮件提醒投递' : 'Email Reminder Delivery';
  }

  static String get reminderEmailEnableTitle =>
      reminderEmailEnableTitleFor(I18n.current);

  static String reminderEmailEnableSubtitleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '待办/目标的“邮件”提醒会按计划写入后端 SMTP 队列'
        : 'Scheduled Todo/Goal email reminders are queued into backend SMTP';
  }

  static String get reminderEmailEnableSubtitle =>
      reminderEmailEnableSubtitleFor(I18n.current);

  static String reminderDefaultRecipientLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '默认提醒收件人' : 'Default Reminder Recipient';
  }

  static String get reminderDefaultRecipientLabel =>
      reminderDefaultRecipientLabelFor(I18n.current);

  static String reminderDefaultRecipientHelperFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh
        ? '用户登录名是邮箱时优先投递给该用户'
        : 'If username is a valid email, delivered to that user primarily';
  }

  static String get reminderDefaultRecipientHelper =>
      reminderDefaultRecipientHelperFor(I18n.current);

  static String reminderSenderLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '提醒发件人' : 'Reminder Sender';
  }

  static String get reminderSenderLabel => reminderSenderLabelFor(I18n.current);

  static String reminderSmtpHostLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '提醒 SMTP Host' : 'Reminder SMTP Host';
  }

  static String get reminderSmtpHostLabel =>
      reminderSmtpHostLabelFor(I18n.current);

  static String reminderSmtpPortLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '提醒 SMTP 端口' : 'Reminder SMTP Port';
  }

  static String get reminderSmtpPortLabel =>
      reminderSmtpPortLabelFor(I18n.current);

  static String reminderSmtpUserLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '提醒 SMTP 用户名' : 'Reminder SMTP Username';
  }

  static String get reminderSmtpUserLabel =>
      reminderSmtpUserLabelFor(I18n.current);

  static String reminderSmtpPasswordLabelFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '提醒 SMTP 密码' : 'Reminder SMTP Password';
  }

  static String get reminderSmtpPasswordLabel =>
      reminderSmtpPasswordLabelFor(I18n.current);

  static String saveConfigBtnFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '保存配置' : 'Save Config';
  }

  static String get saveConfigBtn => saveConfigBtnFor(I18n.current);

  static String runBackupNowBtnFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '立即备份' : 'Backup Now';
  }

  static String get runBackupNowBtn => runBackupNowBtnFor(I18n.current);

  static String testReminderEmailBtnFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '测试提醒邮件' : 'Test Reminder Email';
  }

  static String get testReminderEmailBtn =>
      testReminderEmailBtnFor(I18n.current);

  static String testAccountEmailBtnFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '测试账号邮件' : 'Test Account Email';
  }

  static String get testAccountEmailBtn => testAccountEmailBtnFor(I18n.current);

  // ---------------------------------------------------------------------------
  // Action Names (for formatActionError)
  // ---------------------------------------------------------------------------
  static String actionUpdateSettingsFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '更新设置' : 'update settings';
  }

  static String get actionUpdateSettings =>
      actionUpdateSettingsFor(I18n.current);

  static String actionSaveGroupFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '保存用户组' : 'save user group';
  }

  static String get actionSaveGroup => actionSaveGroupFor(I18n.current);

  static String actionSaveRoleFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '保存角色' : 'save role';
  }

  static String get actionSaveRole => actionSaveRoleFor(I18n.current);

  static String actionSaveUpdateConfigFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '保存更新配置' : 'save update configuration';
  }

  static String get actionSaveUpdateConfig =>
      actionSaveUpdateConfigFor(I18n.current);

  static String actionUpdateForceUpdateFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '更新强制升级设置' : 'update force update settings';
  }

  static String get actionUpdateForceUpdate =>
      actionUpdateForceUpdateFor(I18n.current);

  static String actionSaveAiConfigFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '保存 AI 配置' : 'save AI configuration';
  }

  static String get actionSaveAiConfig => actionSaveAiConfigFor(I18n.current);

  static String actionSaveBackupConfigFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '保存备份配置' : 'save backup configuration';
  }

  static String get actionSaveBackupConfig =>
      actionSaveBackupConfigFor(I18n.current);

  static String actionRunServerBackupFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '执行服务器备份' : 'run server backup';
  }

  static String get actionRunServerBackup =>
      actionRunServerBackupFor(I18n.current);

  static String actionSendReminderTestEmailFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '发送提醒测试邮件' : 'send reminder test email';
  }

  static String get actionSendReminderTestEmail =>
      actionSendReminderTestEmailFor(I18n.current);

  static String actionSendAccountTestEmailFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '发送账号测试邮件' : 'send account test email';
  }

  static String get actionSendAccountTestEmail =>
      actionSendAccountTestEmailFor(I18n.current);

  static String actionWipeBackupFor([AppLocale? locale]) {
    final zh = (locale ?? I18n.current) == AppLocale.zh;
    return zh ? '清空云端备份' : 'clear cloud backup';
  }

  static String get actionWipeBackup => actionWipeBackupFor(I18n.current);

  // ---------------------------------------------------------------------------
  // Error Formatting
  // ---------------------------------------------------------------------------
  static String formatLoadError(
    Object error,
    String target, {
    AppLocale? locale,
  }) {
    final effectiveLocale = locale ?? I18n.current;
    final zh = effectiveLocale == AppLocale.zh;
    final text = userVisibleApiError(error, locale: effectiveLocale);
    return zh ? '无法加载$target：$text' : 'Could not load $target: $text';
  }
}
