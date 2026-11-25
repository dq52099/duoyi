import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_lock_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/preferences_provider.dart';
import 'account_local_data_cleaner.dart';
import 'app_update_service.dart';

/// Authority retained by the setting control that rendered an interaction.
class SettingsActionOrigin {
  SettingsActionOrigin(this._context)
    : preferences = _context.read<PreferencesProvider?>(),
      _auth = _context.read<AuthProvider?>(),
      _lock = _context.read<AppLockProvider?>(),
      _update = _context.read<AppUpdateService?>(),
      _route = ModalRoute.of(_context),
      _accountGeneration = AccountLocalDataCleaner.accountDataGeneration {
    _preferenceGeneration = preferences?.storageGeneration;
    _sessionGeneration = _auth?.sessionGeneration;
    _wasLoggedIn = _auth?.state.isLoggedIn ?? false;
    _userId = _normalize(_auth?.state.userId);
    if (_wasLoggedIn) {
      try {
        _lease = _auth!.captureSessionLease();
      } catch (_) {
        _leaseFailed = true;
      }
    }
  }

  final BuildContext _context;
  final PreferencesProvider? preferences;
  final AuthProvider? _auth;
  final AppLockProvider? _lock;
  final AppUpdateService? _update;
  final ModalRoute<dynamic>? _route;
  final int _accountGeneration;
  late final int? _preferenceGeneration;
  late final int? _sessionGeneration;
  late final bool _wasLoggedIn;
  String? _userId;
  AuthSessionLease? _lease;
  bool _leaseFailed = false;

  static String? _normalize(String? raw) {
    final value = raw?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  bool isCurrent({bool checkRoute = true}) {
    if (!_context.mounted ||
        _leaseFailed ||
        preferences?.storageGeneration != _preferenceGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _accountGeneration,
        ) ||
        (_route != null &&
            (!_route.isActive || (checkRoute && !_route.isCurrent)))) {
      return false;
    }
    try {
      if (!identical(_context.read<PreferencesProvider?>(), preferences) ||
          !identical(_context.read<AuthProvider?>(), _auth) ||
          !identical(_context.read<AppLockProvider?>(), _lock) ||
          !identical(_context.read<AppUpdateService?>(), _update) ||
          _lock?.isLocked == true ||
          _update?.mustUpdate == true) {
        return false;
      }
      final auth = _auth;
      if (auth != null) {
        if (auth.sessionGeneration != _sessionGeneration ||
            auth.state.isLoggedIn != _wasLoggedIn ||
            auth.isAccountTransitionInProgress ||
            auth.isLocalAccountDataBlocked ||
            (_lease != null && !auth.isSessionLeaseCurrent(_lease!))) {
          return false;
        }
        final id = _normalize(auth.state.userId);
        if (_userId != null && id != _userId) return false;
        _userId ??= id;
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
