import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/app_lock_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/share_provider.dart';
import 'account_local_data_cleaner.dart';
import 'app_update_service.dart';

/// Retains the authority that opened a Goal form across rebuilds and awaits.
class GoalEditorOrigin {
  GoalEditorOrigin._({
    required this.provider,
    required this.storageGeneration,
    required this.accountGeneration,
    required this.auth,
    required this.share,
    required this.route,
    required this.sessionLease,
    required this.leaseFailed,
  }) : sessionGeneration = auth?.sessionGeneration,
       wasLoggedIn = auth?.state.isLoggedIn ?? false,
       _userId = _normalize(auth?.state.userId);

  final GoalProvider provider;
  final int storageGeneration;
  final int accountGeneration;
  final AuthProvider? auth;
  final ShareProvider? share;
  final ModalRoute<dynamic>? route;
  final AuthSessionLease? sessionLease;
  final bool leaseFailed;
  final int? sessionGeneration;
  final bool wasLoggedIn;
  String? _userId;

  static String? _normalize(String? raw) {
    final value = raw?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static GoalEditorOrigin capture(BuildContext context) {
    final provider = context.read<GoalProvider>();
    final auth = context.read<AuthProvider?>();
    AuthSessionLease? lease;
    var failed = false;
    if (auth?.state.isLoggedIn == true) {
      try {
        lease = auth!.captureSessionLease();
      } catch (_) {
        failed = true;
      }
    }
    return GoalEditorOrigin._(
      provider: provider,
      storageGeneration: provider.storageGeneration,
      accountGeneration: AccountLocalDataCleaner.accountDataGeneration,
      auth: auth,
      share: context.read<ShareProvider?>(),
      route: ModalRoute.of(context),
      sessionLease: lease,
      leaseFailed: failed,
    );
  }

  bool isCurrent(
    BuildContext context, {
    bool checkRoute = true,
    bool checkAccess = true,
  }) {
    if (!context.mounted ||
        leaseFailed ||
        provider.storageGeneration != storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return false;
    }
    if (route != null &&
        (!route!.isActive || (checkRoute && !route!.isCurrent))) {
      return false;
    }
    try {
      if (!identical(context.read<GoalProvider>(), provider) ||
          !identical(context.read<AuthProvider?>(), auth) ||
          !identical(context.read<ShareProvider?>(), share)) {
        return false;
      }
      final currentAuth = auth;
      if (currentAuth != null) {
        if (currentAuth.sessionGeneration != sessionGeneration ||
            currentAuth.state.isLoggedIn != wasLoggedIn ||
            currentAuth.isAccountTransitionInProgress ||
            currentAuth.isLocalAccountDataBlocked ||
            (sessionLease != null &&
                !currentAuth.isSessionLeaseCurrent(sessionLease!))) {
          return false;
        }
        final id = _normalize(currentAuth.state.userId);
        if (_userId != null && id != _userId) return false;
        _userId ??= id;
      }
      if (checkAccess &&
          (context.read<AppLockProvider?>()?.isLocked == true ||
              context.read<AppUpdateService?>()?.mustUpdate == true)) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  bool canEdit(String workspaceId) => share?.canEdit(workspaceId) ?? true;
}
