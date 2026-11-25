import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_lock_provider.dart';
import '../providers/auth_provider.dart';
import 'account_local_data_cleaner.dart';
import 'api_client.dart';
import 'app_update_service.dart';

/// Records authority changes for a mounted Admin tab, including revoke/regrant.
/// A receipt has no listeners of its own; language and profile edits preserve it.
class AdminActionHost {
  BuildContext? _context;
  ModalRoute<dynamic>? _route;
  AuthProvider? _auth;
  AppLockProvider? _lock;
  AppUpdateService? _update;
  Object? _authority;
  int _epoch = 0;
  bool _disposed = false;

  int get revision {
    _observe();
    return _epoch;
  }

  void bind(BuildContext context) {
    if (_disposed) return;
    _context = context;
    _route = ModalRoute.of(context);
    final auth = context.watch<AuthProvider?>();
    final lock = context.watch<AppLockProvider?>();
    final update = context.watch<AppUpdateService?>();
    if (!identical(auth, _auth) ||
        !identical(lock, _lock) ||
        !identical(update, _update)) {
      _unlisten();
      _auth = auth;
      _lock = lock;
      _update = update;
      _auth?.addListener(_observe);
      _lock?.addListener(_observe);
      _update?.addListener(_observe);
    }
    _observe();
  }

  Object _snapshot() {
    final auth = _auth;
    final state = auth?.state;
    final permissions = state?.adminPermissions;
    // Null is the legacy full-admin contract. Explicit none always denies.
    final permissionKey =
        permissions == null ||
            (permissions.contains('*') && !permissions.contains('__none__'))
        ? 'all'
        : ((permissions.toSet().toList()..sort()).join(','));
    return (
      auth,
      auth?.client,
      state?.userId,
      state?.token,
      auth?.client.token,
      auth?.client.baseUrl,
      auth?.sessionGeneration,
      auth?.successfulAccountTransitionRevision,
      auth?.isAccountTransitionInProgress,
      auth?.isLocalAccountDataBlocked,
      state?.isAdmin,
      permissionKey,
      _lock,
      _lock?.isLocked,
      _update,
      _update?.mustUpdate,
      AccountLocalDataCleaner.accountDataGeneration,
    );
  }

  void _observe() {
    if (_disposed) return;
    final next = _snapshot();
    if (next != _authority) {
      _authority = next;
      _epoch++;
    }
  }

  AdminActionOrigin capture({
    required ApiClient client,
    Set<String> anyOfPermissions = const {'groups'},
  }) {
    _observe();
    return AdminActionOrigin._(
      this,
      _epoch,
      client,
      Set<String>.unmodifiable(anyOfPermissions),
    );
  }

  bool _isCurrent(AdminActionOrigin origin, {required bool checkRoute}) {
    final context = _context;
    if (_disposed || context == null || !context.mounted) return false;
    try {
      if (!identical(context.read<AuthProvider?>(), _auth) ||
          !identical(context.read<AppLockProvider?>(), _lock) ||
          !identical(context.read<AppUpdateService?>(), _update)) {
        _epoch++;
        return false;
      }
      _observe();
      final auth = _auth;
      if (origin._epoch != _epoch ||
          auth == null ||
          !auth.state.isLoggedIn ||
          !auth.state.isAdmin ||
          auth.isAccountTransitionInProgress ||
          auth.isLocalAccountDataBlocked ||
          _lock?.isLocked == true ||
          _update?.mustUpdate == true ||
          !identical(origin.client, auth.client) ||
          origin.client.token != auth.state.token ||
          origin.client.token != origin._token ||
          origin.client.baseUrl != origin._baseUrl ||
          (_route != null &&
              (!_route!.isActive || (checkRoute && !_route!.isCurrent)))) {
        return false;
      }
      final permissions = auth.state.adminPermissions;
      return permissions == null ||
          (!permissions.contains('__none__') &&
              (permissions.contains('*') ||
                  origin._permissions.any(permissions.contains)));
    } catch (_) {
      return false;
    }
  }

  void _unlisten() {
    _auth?.removeListener(_observe);
    _lock?.removeListener(_observe);
    _update?.removeListener(_observe);
  }

  void dispose() {
    if (_disposed) return;
    _unlisten();
    _disposed = true;
    _epoch++;
    _context = null;
  }
}

/// Authority of a rendered control, latched invalid after any failed check.
class AdminActionOrigin {
  AdminActionOrigin._(this._host, this._epoch, this.client, this._permissions)
    : _token = client.token,
      _baseUrl = client.baseUrl;

  final AdminActionHost _host;
  final int _epoch;
  final ApiClient client;
  final Set<String> _permissions;
  final String? _token;
  final String _baseUrl;
  bool _invalid = false;

  bool isCurrent({bool checkRoute = true}) {
    if (_invalid) return false;
    if (!_host._isCurrent(this, checkRoute: checkRoute)) {
      _invalid = true;
      return false;
    }
    return true;
  }
}
