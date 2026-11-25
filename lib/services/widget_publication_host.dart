import 'dart:async';

import 'account_local_data_cleaner.dart';
import 'widget_publication.dart';
import 'widget_publication_controller.dart';

/// Host ordering shared by publication and the pre-deletion cleanup barrier.
/// Auth/hydration and presentation validity are supplied by the current host;
/// native storage can never authenticate that context.
class WidgetPublicationHost {
  WidgetPublicationHost({required this.controller, this.onStatus});

  final WidgetPublicationController controller;
  final void Function(String message)? onStatus;

  Future<bool> publish({
    required ValidatedWidgetWorkspace workspace,
    required WidgetDevicePresentation presentation,
    required Map<String, Object> completeValues,
    required DateTime capturedAt,
    required Future<bool> Function() refreshWidgets,
    required Future<bool> Function() requestFreshCapture,
    required void Function() invalidatePushSignature,
  }) async {
    bool current() =>
        _current(workspace.accountGeneration, workspace.isCurrent);
    if (!current()) return false;
    final values = Map<String, Object>.unmodifiable({
      for (final key in WidgetPublication.valueKeys) key: completeValues[key]!,
    });
    controller.selectPresentation(presentation);
    if (!controller.ready) await controller.advancePresentation();
    if (!current()) return false;
    if (!controller.ready) {
      var opened = await controller.openWorkspace(workspace, forceReset: false);
      if (opened.status == 'barrierRequired') {
        final sealed = await controller.invalidate();
        if (!current()) return false;
        if (sealed.barrierConfirmed) {
          opened = await controller.openWorkspace(workspace, forceReset: false);
        } else if (!controller.requiresDurabilityRecovery) {
          return false;
        }
      }
      if (!current()) return false;
      if (controller.requiresDurabilityRecovery) {
        final recovered = await controller.recoverWorkspace(workspace);
        if (recovered.storeCommitted && current()) {
          invalidatePushSignature();
          // Never await a nested push inside HomeWidgetService's payload FIFO.
          // This pass's payload predates the seal and must be discarded.
          scheduleMicrotask(() {
            if (!current()) return;
            unawaited(
              Future<bool>.sync(requestFreshCapture).catchError((Object error) {
                onStatus?.call('post-recovery push failed: $error');
                return false;
              }),
            );
          });
        }
        return false;
      }
      if (!opened.storeCommitted || !controller.ready) {
        onStatus?.call('native workspace open: ${opened.status}');
        return false;
      }
    }
    if (!current()) return false;
    final capture = controller.capture(values, capturedAt: capturedAt);
    if (capture == null) return false;
    final published = await controller.publish(capture);
    if (!published.storeCommitted || !current()) {
      onStatus?.call('native publication: ${published.status}');
      return false;
    }
    final refreshed = await refreshWidgets();
    return refreshed && current();
  }

  /// Call before clearing account models or ownership. Legacy cache work is
  /// allowed only after a still-current native sealed/absent barrier.
  Future<WidgetPublicationOutcome> clearForCleanup({
    required ValidatedWidgetCleanup cleanup,
    required WidgetDevicePresentation presentation,
    required Future<bool> Function() clearCachedWidgetData,
  }) async {
    bool current() => _current(cleanup.accountGeneration, cleanup.isCurrent);
    if (!current()) return _superseded;
    controller.revoke();
    controller.selectPresentation(presentation);
    var barrier = await controller.invalidate();
    if (!current()) return _superseded;
    if (!barrier.barrierConfirmed && controller.requiresDurabilityRecovery) {
      barrier = await controller.recoverCleanup(cleanup);
      if (!current()) return _superseded;
    }
    if (!barrier.barrierConfirmed) return barrier;
    final cleared = await clearCachedWidgetData();
    if (!current()) return _superseded;
    if (!cleared) return const WidgetPublicationOutcome('legacyClearFailed');
    return WidgetPublicationOutcome(
      barrier.status,
      storeCommitted: barrier.storeCommitted,
      barrierConfirmed: true,
    );
  }

  static bool _current(int generation, bool Function() predicate) {
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
      return false;
    }
    try {
      return predicate();
    } catch (_) {
      return false;
    }
  }

  static const _superseded = WidgetPublicationOutcome('supersededContext');
}
