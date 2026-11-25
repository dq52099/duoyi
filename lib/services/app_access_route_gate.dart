import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

/// Keeps the app's access decision attached to each real Navigator route.
///
/// Use the same observer for the Navigator's lifetime. The caller supplies
/// `locked || mustUpdate` and separately gates pointers, focus and semantics.
/// This blocks pop-disposition based navigation; it does not intercept direct
/// `Navigator.pop`, route removal or business callbacks.
class AppAccessRouteGate extends NavigatorObserver {
  AppAccessRouteGate({bool blocked = false}) : _blocked = blocked;

  final Map<ModalRoute<dynamic>, _AccessPopEntry> _entries = Map.identity();
  final List<Route<dynamic>> _routes = [];
  bool _blocked;
  bool _disposed = false;
  final _routeRevision = ValueNotifier<int>(0);

  bool get isBlocked => _blocked;
  Route<dynamic>? get currentRoute => _routes.isEmpty ? null : _routes.last;

  /// Synchronous Navigator events, including push/pop within one frame.
  /// Consumers must still check their own account and operation authority.
  ValueListenable<int> get routeRevision => _routeRevision;

  @visibleForTesting
  int get registeredRouteCount => _entries.length;

  /// Updates existing routes immediately, including dialogs and modal sheets.
  void setBlocked(bool blocked) {
    if (_disposed || blocked == _blocked) return;
    _blocked = blocked;
    for (final entry in List<_AccessPopEntry>.of(_entries.values)) {
      entry.setCanPop(!blocked);
    }
  }

  void _register(Route<dynamic>? route) {
    if (_disposed || route is! ModalRoute<dynamic>) return;
    if (_entries.containsKey(route)) return;
    final entry = _AccessPopEntry(canPop: !_blocked);
    _entries[route] = entry;
    route.registerPopEntry(entry);
  }

  void _unregister(Route<dynamic>? route) {
    if (route is! ModalRoute<dynamic>) return;
    final entry = _entries.remove(route);
    if (entry == null) return;
    route.unregisterPopEntry(entry);
    entry.dispose();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _register(route);
    if (!_disposed) _routeRevision.value++;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _unregister(route);
    if (!_disposed) _routeRevision.value++;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _unregister(route);
    if (!_disposed) _routeRevision.value++;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    } else if (newRoute != null) {
      _routes.add(newRoute);
    }
    _unregister(oldRoute);
    _register(newRoute);
    if (!_disposed) _routeRevision.value++;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final route in List<ModalRoute<dynamic>>.of(_entries.keys)) {
      _unregister(route);
    }
    _routes.clear();
    _routeRevision.dispose();
  }
}

class _AccessPopEntry extends PopEntry<Object?> {
  _AccessPopEntry({required bool canPop})
    : canPopNotifier = ValueNotifier<bool>(canPop);

  @override
  final ValueNotifier<bool> canPopNotifier;
  bool _disposed = false;

  void setCanPop(bool canPop) {
    if (!_disposed) canPopNotifier.value = canPop;
  }

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {}

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    canPopNotifier.dispose();
  }
}
