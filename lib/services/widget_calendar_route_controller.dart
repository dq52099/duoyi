import 'dart:async';

import 'package:flutter/widgets.dart';

/// Owns date routes without removing another screen's dialog or draft.
class WidgetCalendarRouteController {
  final List<({NavigatorState navigator, Route<void> route})> _owned = [];

  Route<void>? _currentOwnedRoute(NavigatorState navigator) {
    for (final entry in _owned.reversed) {
      if (identical(entry.navigator, navigator) && entry.route.isCurrent) {
        return entry.route;
      }
    }
    return null;
  }

  void open(NavigatorState navigator, Route<void> route) {
    if (!navigator.mounted) return;
    final previous = _currentOwnedRoute(navigator);
    final completion = previous == null
        ? navigator.push<void>(route)
        : navigator.pushReplacement<void, void>(route);
    _owned.add((navigator: navigator, route: route));
    unawaited(
      completion.then((_) {
        _owned.removeWhere((entry) => identical(entry.route, route));
      }),
    );
  }

  bool showSection(NavigatorState navigator) {
    if (!navigator.mounted || _currentOwnedRoute(navigator) == null) {
      return false;
    }
    navigator.pop<void>();
    return true;
  }
}
