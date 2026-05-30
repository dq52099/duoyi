import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('admin api exposes permissions and coin adjustment contracts', () {
    final adminApi = File('lib/services/admin_api.dart').readAsStringSync();

    expect(adminApi, contains('Future<void> setUserAdminPermissions'));
    expect(adminApi, contains("'admin_permissions': permissions"));
    expect(adminApi, contains('String? groupId'));
    expect(adminApi, contains('String? roleId'));
    expect(adminApi, contains("body['group_id'] = groupId"));
    expect(adminApi, contains("body['role_id'] = roleId"));
    expect(adminApi, contains(r"'/api/admin/users/$userId'"));
    expect(adminApi, contains('Future<Map<String, dynamic>> adjustUserCoins'));
    expect(adminApi, contains("'delta': delta"));
    expect(adminApi, contains("body['reason'] = reason.trim();"));
    expect(adminApi, contains('_validateCoinAdjustmentResponse'));
    expect(adminApi, contains("response['balance']"));
    expect(adminApi, contains("response['lifetime']"));
    expect(adminApi, contains("response['server_version']"));
    expect(adminApi, contains('时光币调整缺少余额字段'));
    expect(
      adminApi,
      contains('return _validateCoinAdjustmentResponse(response);'),
    );
    expect(
      adminApi,
      contains("throw const ApiException('接口返回结构错误：时光币调整缺少余额字段')"),
    );
    expect(adminApi, contains(r"'/api/admin/users/$userId/coins'"));
    expect(
      adminApi,
      contains(r"client.post('/api/admin/users/$userId/coins', body)"),
      reason: '时光币调整应直连当前主路由，避免连续探测兼容别名导致 404 噪声。',
    );
    for (final noisyFallback in [
      r"'/api/admin/users/$userId/quota/adjust'",
      r"'/api/admin/users/$userId/time-coins/adjust'",
      r"'/api/admin/users/$userId/time_coin_balance/adjust'",
      r"'/api/admin/users/$userId/coin-adjustment'",
    ]) {
      expect(
        adminApi,
        isNot(contains(noisyFallback)),
        reason: '$noisyFallback 应只作为后端兼容别名，不再由前端主动试探。',
      );
    }
    expect(adminApi, contains('Future<AdminPage> listGroupsPage'));
    expect(adminApi, contains('Future<List<Map<String, dynamic>>> listGroups'));
    expect(adminApi, contains("'/api/admin/groups',"));
    expect(adminApi, contains('return await _getPage(path'));
    expect(
      adminApi,
      contains("client.getRaw('/api/admin/groups?limit=500&offset=0')"),
    );
    expect(adminApi, contains('Future<Map<String, dynamic>> saveGroup'));
    expect(adminApi, contains('int? defaultGenerateQuota'));
    expect(adminApi, contains('int? defaultEditQuota'));
    expect(
      adminApi,
      contains("'default_generate_quota': ?defaultGenerateQuota"),
      reason: '保存用户组时不能把隐藏额度字段用 UI 默认值覆盖掉。',
    );
    expect(
      adminApi,
      contains("'default_edit_quota': ?defaultEditQuota"),
      reason: '保存用户组时不能把隐藏额度字段用 UI 默认值覆盖掉。',
    );
    expect(adminApi, contains('_sendFirstAvailable('));
    expect(adminApi, contains("'/api/admin/groups'"));
    expect(adminApi, contains("'/api/admin/user-groups'"));
    expect(adminApi, contains("'/api/admin/user_groups'"));
    expect(adminApi, contains(r"'/api/admin/groups/$groupId'"));
    expect(adminApi, contains('Future<List<Map<String, dynamic>>> listRoles'));
    expect(adminApi, contains("client.getRaw('/api/admin/roles')"));
    expect(adminApi, contains('Future<Map<String, dynamic>> saveRole'));
    expect(adminApi, contains("client.post('/api/admin/roles', body)"));
    expect(
      adminApi,
      contains(r"client.patch('/api/admin/roles/$roleId', body)"),
    );

    final backend = File('backend/main.py').readAsStringSync();
    final statsSource = backend.substring(
      backend.indexOf('@app.get("/api/admin/stats")'),
      backend.indexOf('@app.get("/api/admin/users")'),
    );
    expect(statsSource, isNot(contains('virtual_rewards')));
    expect(statsSource, isNot(contains('coin_balance')));
    expect(statsSource, isNot(contains('lifetime_coins')));
    expect(
      backend,
      contains('"coin_balance": coin_balance'),
      reason: '用户分页列表仍需展示每个账号的时光币余额。',
    );
    expect(
      backend,
      contains('"lifetime_coins": lifetime_coins'),
      reason: '用户分页列表仍需展示每个账号的累计时光币。',
    );
    expect(backend, contains('@app.post("/api/admin/users/{user_id}/coins")'));
    expect(backend, contains('_ensure_admin_permission(db, actor, "coins")'));
    expect(
      backend,
      contains('SET virtual_rewards=?, sync_version=?, updated_at=?'),
    );
    expect(backend, contains('"user.coins_adjust"'));
    expect(backend, contains('if req.admin_permissions is not None:'));
    expect(
      backend,
      contains('UPDATE users SET admin_permissions=? WHERE id=?'),
    );
    expect(
      backend,
      contains('def _ensure_admin_management_permission'),
      reason: '只有 users 权限不能修改管理员身份、角色或权限。',
    );
    expect(
      backend,
      contains('touches_admin_management'),
      reason: '修改管理员身份、角色或权限时需要额外门禁，避免 users 权限自提权。',
    );
    expect(
      backend,
      contains('return _user_response(fresh, db=db)'),
      reason: '管理员保存用户组/角色后需要返回最新用户对象，避免前端拿不到 group_id/role_id。',
    );
    expect(
      backend,
      contains(
        'def group_int(field: str, fallback: int, *aliases: str) -> int:',
      ),
      reason: '后端更新用户组时需要保留前端未提交的隐藏额度字段，并兼容驼峰别名。',
    );
    expect(
      backend,
      contains(
        '_setting_set(db, "default_registration_coins", default_time_coins)',
      ),
      reason: '默认用户组额度需要同步默认注册时光币。',
    );
    expect(backend, contains('"default_registration_coins": 100'));
    expect(adminApi, contains("detail == 'not found'"));
    expect(
      adminApi,
      isNot(contains("if (message.startsWith('404:')) return true;")),
      reason: '业务 404 不能被当成路由不存在继续 fallback。',
    );
  });

  test('backend gates granular admin feature permissions', () {
    final backend = File('backend/main.py').readAsStringSync();

    expect(
      backend,
      contains('_ensure_admin_permission(db, actor, "settings")'),
    );
    expect(
      backend,
      contains('_ensure_admin_permission(db, actor, "feedback")'),
    );
    expect(
      backend,
      contains('_ensure_admin_permission(db, actor, "announcements")'),
    );
    expect(backend, contains('_ensure_admin_permission(db, actor, "invites")'));
    expect(backend, contains('_ensure_admin_permission(db, actor, "audit")'));
    expect(backend, contains('_ensure_admin_permission(db, actor, "backup")'));
    expect(backend, contains('_ensure_admin_permission(db, actor, "ai")'));
    expect(backend, contains('@app.get("/api/admin/permissions")'));
    expect(backend, contains('@app.get("/api/admin/groups")'));
    expect(backend, contains('@app.post("/api/admin/groups")'));
    expect(backend, contains('@app.put("/api/admin/groups/{group_id}")'));
    expect(backend, contains('@app.patch("/api/admin/groups/{group_id}")'));
    expect(backend, contains('@app.get("/api/admin/roles")'));
    expect(backend, contains('@app.post("/api/admin/roles")'));
    expect(backend, contains('@app.put("/api/admin/roles/{role_id}")'));
    expect(backend, contains('@app.patch("/api/admin/roles/{role_id}")'));
    expect(backend, contains('_ensure_admin_permission(db, actor, "groups")'));
    expect(backend, contains('_ensure_admin_permission(db, actor, "roles")'));
    expect(
      backend,
      contains('_ensure_admin_permission(db, actor, "permissions")'),
    );
    expect(
      backend,
      contains(
        '_ensure_admin_any_permission(db, user_id, ("roles", "permissions"))',
      ),
    );
    expect(backend, contains('AI_SETTING_KEYS'));
    expect(backend, contains('BACKUP_SETTING_KEYS'));
    expect(backend, contains('BACKUP_ADMIN_SETTING_KEYS'));
    expect(backend, contains('ADMIN_SETTINGS_SCOPES'));
  });

  test('admin group editor preserves explicit zero defaults', () {
    final adminScreen = File(
      'lib/screens/admin_screen.dart',
    ).readAsStringSync();

    expect(
      adminScreen,
      contains('int _adminIntValueOrDefault(dynamic raw, int fallback)'),
    );
    for (final entry in {
      'default_time_coins': 100,
      'default_generate_quota': 100,
      'default_edit_quota': 100,
      'default_generate_history_retention': 50,
      'default_edit_history_retention': 20,
    }.entries) {
      final zeroFallbackPattern = "_adminIntValue(group?['${entry.key}']) == 0";
      expect(
        adminScreen,
        isNot(contains(zeroFallbackPattern)),
        reason: '${entry.key} 为 0 是有效配置，编辑时不能回填默认值。',
      );
      final safeDefaultPattern = RegExp(
        "_adminIntValueOrDefault\\(\\s*group\\?\\['${entry.key}'\\],\\s*"
        '${entry.value},\\s*\\)',
      );
      expect(
        safeDefaultPattern.allMatches(adminScreen).length,
        greaterThanOrEqualTo(2),
        reason: '两个用户组编辑入口都需要只在缺失/空值时使用默认值。',
      );
    }
  });

  test('backend feedback history exposes optional pagination', () {
    final backend = File('backend/main.py').readAsStringSync();

    expect(backend, contains('@app.get("/api/feedback/me")'));
    expect(backend, contains('page: Optional[int] = None'));
    expect(backend, contains('page_size: Optional[int] = None'));
    expect(backend, contains('"total_pages"'));
    expect(backend, contains('"page_size"'));
    expect(backend, contains('if page is None and page_size is None:'));
  });

  test('admin user list shows compact permissions and time coins', () {
    final adminScreen = File(
      'lib/screens/admin_screen.dart',
    ).readAsStringSync();

    expect(adminScreen, contains('const String _adminAllPermission'));
    expect(adminScreen, contains('const String _adminNoPermission'));
    expect(
      adminScreen,
      contains('const Map<String, String> _adminPermissionLabels'),
    );
    expect(adminScreen, contains("'coins': '时光币'"));
    expect(adminScreen, contains("'groups': '用户组'"));
    expect(adminScreen, contains("'roles': '角色'"));
    expect(adminScreen, contains("'permissions': '权限字典'"));
    expect(adminScreen, contains('List<String> _adminUserPermissions'));
    expect(adminScreen, contains('String _adminPermissionsLabel'));
    expect(adminScreen, contains('List<Map<String, dynamic>> _groups = [];'));
    expect(adminScreen, contains('List<Map<String, dynamic>> _roles = [];'));
    expect(adminScreen, contains('widget.api.listGroups()'));
    expect(adminScreen, contains('widget.api.listRoles()'));
    expect(adminScreen, contains('String? _groupsRolesError;'));
    expect(
      adminScreen,
      contains('Future<List<Map<String, dynamic>>> _loadUserGroupsForUsers'),
    );
    expect(
      adminScreen,
      contains('Future<List<Map<String, dynamic>>> _loadUserRolesForUsers'),
    );
    expect(
      adminScreen,
      contains("errors.add(_adminErrorMessage(error, '用户组'))"),
    );
    expect(
      adminScreen,
      contains("errors.add(_adminErrorMessage(error, '角色'))"),
    );
    expect(adminScreen, contains('用户组或角色加载失败'));
    expect(
      adminScreen,
      isNot(
        contains('listGroups().catchError((_) => <Map<String, dynamic>>[])'),
      ),
    );
    expect(
      adminScreen,
      isNot(
        contains('listRoles().catchError((_) => <Map<String, dynamic>>[])'),
      ),
    );
    expect(adminScreen, contains('Future<void> _editGroup'));
    expect(adminScreen, contains('Future<void> _editRole'));
    expect(adminScreen, contains('用户组与角色'));
    expect(adminScreen, contains('widget.api.saveGroup('));
    expect(adminScreen, contains('widget.api.saveRole('));
    expect(adminScreen, contains('默认时光币'));
    expect(adminScreen, contains('图片额度模式'));
    expect(adminScreen, contains("u['admin_permissions']"));
    expect(adminScreen, contains("u['group_id']"));
    expect(adminScreen, contains("u['role_id']"));
    expect(adminScreen, contains("u['coin_balance']"));
    expect(adminScreen, contains("u['lifetime_coins']"));
    expect(adminScreen, contains('final pageCoinBalance = _users.fold<int>'));
    expect(adminScreen, contains('final pageLifetimeCoins = _users.fold<int>'));
    expect(
      adminScreen,
      contains(r'本页时光币 $pageCoinBalance / 累计 $pageLifetimeCoins'),
    );
    final dashboardBody = adminScreen.substring(
      adminScreen.indexOf('class _DashboardTab'),
      adminScreen.indexOf('class _GridCards'),
    );
    expect(dashboardBody, isNot(contains("'时光币余额'")));
    expect(dashboardBody, isNot(contains("'累计时光币'")));
    expect(adminScreen, contains(r"'权限: $permissionsText'"));
    expect(adminScreen, contains(r"'用户组: $groupName'"));
    expect(adminScreen, contains(r"'角色: $roleName'"));
    expect(adminScreen, contains(r"'时光币: $coinBalance / 累计 $lifetimeCoins'"));
    expect(adminScreen, contains("label: '细分权限'"));
    expect(adminScreen, contains(r"'排序: ${_adminUserSortLabel(_sort)}'"));
    expect(adminScreen, contains('ListView.separated'));
    expect(adminScreen, contains('_AdminPaginationBar('));
    expect(
      adminScreen,
      contains(
        'return Border.all(\n'
        '    color: theme.colorScheme.outline.withValues(alpha: alpha),\n'
        '    width: 0.45,\n'
        '  );',
      ),
    );
    expect(
      adminScreen,
      isNot(contains('Border.all(color: theme.colorScheme.outline')),
    );
  });

  test('admin user menu can set permissions and adjust coins', () {
    final adminScreen = File(
      'lib/screens/admin_screen.dart',
    ).readAsStringSync();

    expect(adminScreen, contains('Future<void> _editAdminPermissions'));
    expect(adminScreen, contains('Future<void> _editUserGroupRole'));
    expect(adminScreen, contains('Future<void> _adjustCoins'));
    expect(
      adminScreen,
      contains('selfAdminPermissions: auth.state.adminPermissions'),
    );
    expect(adminScreen, contains('final List<String>? selfAdminPermissions;'));
    expect(adminScreen, contains("bool get _canManageCoins"));
    expect(adminScreen, contains("_canUseAdminPermission('coins')"));
    expect(adminScreen, contains("bool get _canManageGroups"));
    expect(adminScreen, contains("bool get _canManageRoles"));
    expect(adminScreen, contains("bool get _canManagePermissions"));
    expect(adminScreen, contains("_canUseAdminPermission('groups')"));
    expect(adminScreen, contains("_canUseAdminPermission('roles')"));
    expect(adminScreen, contains("_canUseAdminPermission('permissions')"));
    expect(adminScreen, contains("case 'permissions':"));
    expect(adminScreen, contains("case 'group_role':"));
    expect(adminScreen, contains("case 'coins':"));
    expect(adminScreen, contains("value: 'permissions'"));
    expect(adminScreen, contains("? '设置管理权限' : '设置管理权限（无权限）'"));
    expect(adminScreen, contains('设置管理权限（无权限）'));
    expect(adminScreen, contains('缺少权限管理权限'));
    expect(adminScreen, contains("value: 'group_role'"));
    expect(adminScreen, contains('设置用户组/角色'));
    expect(adminScreen, contains('缺少用户组或角色管理权限'));
    expect(adminScreen, contains('widget.api.updateUser('));
    expect(adminScreen, contains('activeOnly: true'));
    expect(adminScreen, contains("item['is_active'] == false"));
    expect(adminScreen, contains("isInactive ? ' · 停用' : ''"));
    expect(
      adminScreen,
      contains('groupId: _canManageGroups ? selectedGroupId : null'),
    );
    expect(
      adminScreen,
      contains('roleId: _canManageRoles ? selectedRoleId : null'),
    );
    expect(adminScreen, contains("value: 'coins'"));
    expect(adminScreen, contains('enabled: _canManageCoins'));
    expect(adminScreen, contains("调整时光币（无权限）"));
    expect(adminScreen, contains("缺少时光币管理权限"));
    expect(adminScreen, contains('widget.api.setUserAdminPermissions('));
    expect(adminScreen, contains('widget.api.adjustUserCoins('));
    expect(adminScreen, contains("u['coin_balance'] = adjusted['balance'];"));
    expect(
      adminScreen,
      contains("u['lifetime_coins'] = adjusted['lifetime'];"),
    );
    expect(adminScreen, contains("helperText: '正数增加，负数扣减'"));
    expect(adminScreen, contains("SnackBar(content: Text('管理权限已更新'))"));
    expect(adminScreen, contains("SnackBar(content: Text('时光币已调整'))"));
  });
}
