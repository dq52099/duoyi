import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'web_lifecycle_recovery_stub.dart'
    if (dart.library.js_interop) 'web_lifecycle_recovery_web.dart'
    if (dart.library.html) 'web_lifecycle_recovery_web.dart'
    as impl;

/// Coordinates Web foreground-resume frame repainting so Mobile Chrome
/// background/foreground transitions recover cleanly instead of leaving a stale
/// or blank CanvasKit compositor surface.
class WebLifecycleRecovery {
  WebLifecycleRecovery._();

  static void Function()? _unsubscribeJs;
  static Timer? _settleTimer;
  static int _installCount = 0;
  static int _repaintRequests = 0;

  @visibleForTesting
  static int get debugRepaintRequestCount => _repaintRequests;

  @visibleForTesting
  static bool get debugHasPendingSettleTimer => _settleTimer?.isActive ?? false;

  /// Installs the Web `duoyi:web-resume` event bridge once for the app root.
  static void install() {
    _installCount++;
    if (_unsubscribeJs != null || !kIsWeb) return;
    _unsubscribeJs = impl.installWebResumeListener(() {
      requestVisualRecovery();
    });
  }

  /// Detaches the Web event listener and cancels any pending follow-up timer.
  static void uninstall() {
    if (_installCount > 0) _installCount--;
    if (_installCount > 0) return;
    _settleTimer?.cancel();
    _settleTimer = null;
    _unsubscribeJs?.call();
    _unsubscribeJs = null;
  }

  /// Triggers a forced frame repaint on Web when the app returns to foreground.
  static void onAppResumed() {
    if (!kIsWeb) return;
    requestVisualRecovery();
  }

  /// Marks attached render trees needing paint and schedules forced frames.
  ///
  /// When [scheduleFollowUp] is true, a single coalesced 120ms follow-up pump
  /// is scheduled so Chromium surfaces restored slightly after `visibilitychange`
  /// receive a fresh bitmap upload.
  static void requestVisualRecovery({bool scheduleFollowUp = true}) {
    _repaintRequests++;
    _pumpFrameSafely();
    if (!scheduleFollowUp) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 120), () {
      _settleTimer = null;
      _pumpFrameSafely();
    });
  }

  static void _pumpFrameSafely() {
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      scheduler.addPostFrameCallback((_) => _markRenderTreesAndScheduleFrame());
      return;
    }
    _markRenderTreesAndScheduleFrame();
  }

  static void _markRenderTreesAndScheduleFrame() {
    final renderer = RendererBinding.instance;
    for (final renderView in renderer.renderViews) {
      renderView.markNeedsPaint();
      late RenderObjectVisitor markAttached;
      markAttached = (RenderObject child) {
        if (child.attached) {
          child.markNeedsPaint();
        }
        child.visitChildren(markAttached);
      };
      renderView.visitChildren(markAttached);
    }
    WidgetsBinding.instance
      ..scheduleForcedFrame()
      ..ensureVisualUpdate();
  }

  @visibleForTesting
  static void resetForTesting() {
    _installCount = 0;
    _repaintRequests = 0;
    _settleTimer?.cancel();
    _settleTimer = null;
    _unsubscribeJs?.call();
    _unsubscribeJs = null;
  }
}
