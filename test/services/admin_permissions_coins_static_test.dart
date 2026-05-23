import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('admin api exposes permissions and coin adjustment contracts', () {
    final adminApi = File('lib/services/admin_api.dart').readAsStringSync();

    expect(adminApi, contains('Future<void> setUserAdminPermissions'));
    expect(adminApi, contains("'admin_permissions': permissions"));
    expect(adminApi, contains(r"'/api/admin/users/$userId'"));
    expect(adminApi, contains('Future<Map<String, dynamic>> adjustUserCoins'));
    expect(adminApi, contains("'delta': delta"));
    expect(adminApi, contains("body['reason'] = reason.trim();"));
    expect(adminApi, contains(r"'/api/admin/users/$userId/coins'"));

    final backend = File('backend/main.py').readAsStringSync();
    expect(backend, contains('@app.post("/api/admin/users/{user_id}/coins")'));
    expect(backend, contains('_ensure_admin_permission(db, actor, "coins")'));
    expect(backend, contains('SET virtual_rewards=?, sync_version=?, updated_at=?'));
    expect(backend, contains('"user.coins_adjust"'));
    expect(backend, contains('if req.admin_permissions is not None:'));
    expect(backend, contains('UPDATE users SET admin_permissions=? WHERE id=?'));
  });

  test('backend gates granular admin feature permissions', () {
    final backend = File('backend/main.py').readAsStringSync();

    expect(backend, contains('_ensure_admin_permission(db, actor, "settings")'));
    expect(backend, contains('_ensure_admin_permission(db, actor, "feedback")'));
    expect(
      backend,
      contains('_ensure_admin_permission(db, actor, "announcements")'),
    );
    expect(backend, contains('_ensure_admin_permission(db, actor, "invites")'));
    expect(backend, contains('_ensure_admin_permission(db, actor, "audit")'));
    expect(backend, contains('_ensure_admin_permission(db, actor, "backup")'));
    expect(backend, contains('_ensure_admin_permission(db, actor, "ai")'));
    expect(backend, contains('AI_SETTING_KEYS'));
    expect(backend, contains('BACKUP_SETTING_KEYS'));
    expect(backend, contains('BACKUP_ADMIN_SETTING_KEYS'));
    expect(backend, contains('ADMIN_SETTINGS_SCOPES'));
  });

  test('backend feedback history exposes optional pagination', () {
    final backend = File('backend/main.py').readAsStringSync();

    expect(backend, contains('@app.get("/api/feedback/me")'));
    expect(backend, contains('page: Optional[int] = None'));
    expect(backend, contains('page_size: Optional[int] = None'));
    expect(backend, contains('"total_pages"'));
    expect(backend, contains('"page_size"'));
    expect(
      backend,
      contains('if page is None and page_size is None:'),
    );
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
    expect(adminScreen, contains('List<String> _adminUserPermissions'));
    expect(adminScreen, contains('String _adminPermissionsLabel'));
    expect(adminScreen, contains("u['admin_permissions']"));
    expect(adminScreen, contains("u['coin_balance']"));
    expect(adminScreen, contains("u['lifetime_coins']"));
    expect(adminScreen, contains(r"'权限: $permissionsText'"));
    expect(
      adminScreen,
      contains(r"'时光币: $coinBalance / 累计 $lifetimeCoins'"),
    );
    expect(adminScreen, contains("label: '细分权限'"));
    expect(adminScreen, contains(r"'排序: ${_adminUserSortLabel(_sort)}'"));
    expect(adminScreen, contains('ListView.separated'));
    expect(adminScreen, contains('_AdminPaginationBar('));
  });

  test('admin user menu can set permissions and adjust coins', () {
    final adminScreen = File(
      'lib/screens/admin_screen.dart',
    ).readAsStringSync();

    expect(adminScreen, contains('Future<void> _editAdminPermissions'));
    expect(adminScreen, contains('Future<void> _adjustCoins'));
    expect(adminScreen, contains("case 'permissions':"));
    expect(adminScreen, contains("case 'coins':"));
    expect(adminScreen, contains("value: 'permissions'"));
    expect(adminScreen, contains("child: Text('设置管理权限')"));
    expect(adminScreen, contains("value: 'coins'"));
    expect(adminScreen, contains("child: Text('调整时光币')"));
    expect(adminScreen, contains('widget.api.setUserAdminPermissions('));
    expect(adminScreen, contains('widget.api.adjustUserCoins('));
    expect(adminScreen, contains("u['coin_balance'] = adjusted['balance'];"));
    expect(adminScreen, contains("u['lifetime_coins'] = adjusted['lifetime'];"));
    expect(adminScreen, contains("helperText: '正数增加，负数扣减'"));
    expect(adminScreen, contains("SnackBar(content: Text('管理权限已更新'))"));
    expect(adminScreen, contains("SnackBar(content: Text('时光币已调整'))"));
  });
}
