import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../providers/app_lock_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/note_provider.dart';
import 'account_local_data_cleaner.dart';
import 'app_access_route_gate.dart';
import 'app_update_service.dart';

/// The account and storage identity that opened a note editor.
class NoteEditorOrigin {
  NoteEditorOrigin.capture(this.context)
    : provider = context.read<NoteProvider>(),
      auth = context.read<AuthProvider?>(),
      lock = context.read<AppLockProvider?>(),
      update = context.read<AppUpdateService?>(),
      route = ModalRoute.of(context),
      accountGeneration = AccountLocalDataCleaner.accountDataGeneration {
    storageGeneration = provider.storageGeneration;
    sessionGeneration = auth?.sessionGeneration;
    wasLoggedIn = auth?.state.isLoggedIn ?? false;
    final userId = auth?.state.userId?.trim();
    _userId = userId == null || userId.isEmpty ? null : userId;
    _client = _clientSnapshot();
    if (wasLoggedIn) {
      try {
        _lease = auth!.captureSessionLease();
      } catch (_) {
        _leaseFailed = true;
      }
    }
  }

  final BuildContext context;
  final NoteProvider provider;
  final AuthProvider? auth;
  final AppLockProvider? lock;
  final AppUpdateService? update;
  final ModalRoute<dynamic>? route;
  final int accountGeneration;
  late final int storageGeneration;
  late final int? sessionGeneration;
  late final bool wasLoggedIn;
  late final Object _client;
  String? _userId;
  AuthSessionLease? _lease;
  bool _leaseFailed = false;

  Iterable<ChangeNotifier> get notifiers => [provider, ?auth, ?lock, ?update];

  Object _clientSnapshot() => (
    auth?.client,
    auth?.client.token,
    auth?.client.baseUrl,
    auth?.state.token,
  );

  bool isCurrent({bool checkRoute = true, bool checkAccess = true}) {
    if (!context.mounted ||
        _leaseFailed ||
        provider.storageGeneration != storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        ) ||
        (route != null &&
            (!route!.isActive || (checkRoute && !route!.isCurrent)))) {
      return false;
    }
    try {
      if (!identical(context.read<NoteProvider>(), provider) ||
          !identical(context.read<AuthProvider?>(), auth) ||
          !identical(context.read<AppLockProvider?>(), lock) ||
          !identical(context.read<AppUpdateService?>(), update) ||
          _clientSnapshot() != _client) {
        return false;
      }
      if (checkAccess &&
          (lock?.isLocked == true || update?.mustUpdate == true)) {
        return false;
      }
      final currentAuth = auth;
      if (currentAuth != null) {
        if (currentAuth.sessionGeneration != sessionGeneration ||
            currentAuth.state.isLoggedIn != wasLoggedIn ||
            currentAuth.isAccountTransitionInProgress ||
            currentAuth.isLocalAccountDataBlocked ||
            (_lease != null && !currentAuth.isSessionLeaseCurrent(_lease!))) {
          return false;
        }
        final userId = currentAuth.state.userId?.trim();
        if ((_userId?.isNotEmpty ?? false) && _userId != userId) return false;
        if (userId?.isNotEmpty ?? false) _userId ??= userId;
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// A save or attachment flow is permanently canceled when its authority leaves.
/// Only the exact modal owned by this flow may be removed during cancellation.
class NoteEditorOperation {
  NoteEditorOperation(this.origin) {
    for (final notifier in origin.notifiers) {
      notifier.addListener(_observeAuthority);
    }
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _observeAuthority,
    );
    origin.route?.secondaryAnimation?.addListener(_observeSourceCover);
    for (final observer in Navigator.of(origin.context).widget.observers) {
      if (observer is AppAccessRouteGate) {
        _gates.add(observer);
        observer.routeRevision.addListener(_observeRoute);
      }
    }
  }

  final NoteEditorOrigin origin;
  final _gates = <AppAccessRouteGate>[];
  ModalRoute<dynamic>? ownedRoute;
  bool _expired = false;
  bool _disposed = false;

  void _observeAuthority() {
    if (_disposed || _expired) return;
    if (!origin.isCurrent(checkRoute: false)) _invalidate();
  }

  void _observeRoute() {
    if (_disposed || _expired) return;
    if (_gates.any(
      (gate) =>
          !identical(gate.currentRoute, origin.route) &&
          !identical(gate.currentRoute, ownedRoute),
    )) {
      _invalidate();
    }
  }

  void _observeSourceCover() {
    if (ownedRoute == null &&
        (origin.route?.secondaryAnimation?.value ?? 0) > 0) {
      _invalidate();
    }
  }

  void _observeOwnedCover() {
    if ((ownedRoute?.secondaryAnimation?.value ?? 0) > 0) _invalidate();
  }

  void _invalidate() {
    if (_expired || _disposed) return;
    _expired = true;
    _closeOwnedRoute();
  }

  void _closeOwnedRoute() {
    final route = ownedRoute;
    if (route == null) return;
    void close() {
      final navigator = route.navigator;
      if (route.isActive && navigator?.mounted == true) {
        navigator!.removeRoute(route);
      }
    }

    scheduleMicrotask(() {
      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        WidgetsBinding.instance.addPostFrameCallback((_) => close());
      } else {
        close();
      }
    });
  }

  void own(ModalRoute<dynamic> route) => ownedRoute = route;

  void listenForCover() =>
      ownedRoute?.secondaryAnimation?.addListener(_observeOwnedCover);

  void release(ModalRoute<dynamic> route) {
    route.secondaryAnimation?.removeListener(_observeOwnedCover);
    if (identical(ownedRoute, route)) ownedRoute = null;
  }

  bool isCurrent() {
    if (_disposed || _expired) return false;
    _observeAuthority();
    _observeRoute();
    if (_expired) return false;
    final route = ownedRoute ?? origin.route;
    return route == null || (route.isActive && route.isCurrent);
  }

  void dispose() {
    if (_disposed) return;
    _closeOwnedRoute();
    _disposed = true;
    for (final notifier in origin.notifiers) {
      notifier.removeListener(_observeAuthority);
    }
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _observeAuthority,
    );
    origin.route?.secondaryAnimation?.removeListener(_observeSourceCover);
    ownedRoute?.secondaryAnimation?.removeListener(_observeOwnedCover);
    for (final gate in _gates) {
      gate.routeRevision.removeListener(_observeRoute);
    }
  }
}
