import 'dart:async';

import 'package:flutter/widgets.dart';

import 'widget_navigation_request.dart';

/// Retains one original delivery until its deferred app interaction runs.
class WidgetLaunchAccess {
  WidgetLaunchAccess({
    required this.uri,
    required this.request,
    required this.isBlocked,
    required this.requeue,
    required this.acknowledge,
    this.requiresLatest = false,
    this.isCallerAvailable,
  });

  final Uri uri;
  final WidgetNavigationRequest request;
  final bool Function() isBlocked;
  final void Function(Uri, WidgetNavigationRequest) requeue;
  final Future<void> Function(Uri) acknowledge;
  final bool requiresLatest;
  final bool Function()? isCallerAvailable;
  int _pending = 0;
  bool _dispatchFinished = false;
  bool _queued = false;
  bool _acknowledged = false;
  bool _actionStarted = false;
  bool _interactionPresented = false;

  /// An open form is retained under the access overlay. Replaying its receipt
  /// would open a second form and lose ownership of the existing draft.
  void markInteractionPresented() => _interactionPresented = true;

  /// Once a write has started, locking may suppress feedback but cannot replay
  /// that write as a new interaction.
  void markActionStarted() => _actionStarted = true;

  /// Feedback can arrive on a later frame after the native receipt was consumed.
  /// Keep checking access and identity without allowing another action dispatch.
  bool get canDeliverFeedback =>
      !_queued &&
      request.isCurrentAccount &&
      (!requiresLatest || request.isLatest) &&
      (isCallerAvailable?.call() ?? true) &&
      !isBlocked();

  bool get canProceed {
    if (_queued ||
        _acknowledged ||
        !request.isCurrentAccount ||
        (requiresLatest && !request.isLatest) ||
        !(isCallerAvailable?.call() ?? true)) {
      return false;
    }
    if (isBlocked()) {
      if (!_actionStarted && !_interactionPresented) {
        _queued = true;
        requeue(uri, request);
      }
      return false;
    }
    return true;
  }

  void afterFrame(VoidCallback action) {
    _pending++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (canProceed) action();
      } finally {
        _pending--;
        _finishIfIdle();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> run(Future<void> Function() action) async {
    _pending++;
    try {
      if (canProceed) await action();
    } finally {
      _pending--;
      _finishIfIdle();
    }
  }

  void finishDispatch() {
    _dispatchFinished = true;
    _finishIfIdle();
  }

  void _finishIfIdle() {
    if (!_dispatchFinished || _pending != 0 || _queued || _acknowledged) return;
    _acknowledged = true;
    unawaited(acknowledge(uri));
  }
}
