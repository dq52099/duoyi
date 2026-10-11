import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Buffered native widget launches, distinct from ordinary external links.
/// A delivery ID identifies a received tap, not its URI or account binding.
class WidgetLaunchService {
  WidgetLaunchService({
    MethodChannel channel = const MethodChannel('duoyi/widget_launch'),
  }) : _channel = channel {
    _controller = StreamController<Uri>.broadcast(
      onListen: _subscribe,
      onCancel: _unsubscribe,
    );
  }

  static final instance = WidgetLaunchService();

  final MethodChannel _channel;
  late final StreamController<Uri> _controller;
  final Set<String> _receivedIds = {};
  final Set<String> _terminalIds = {};
  final Set<String> _acknowledgedIds = {};
  final Queue<String> _acknowledgedOrder = Queue<String>();
  int _generation = 0;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  final Queue<Object?> _bufferedHotDeliveries = Queue<Object?>();
  bool _draining = false;
  bool _backlogReady = false;
  bool _redrainRequested = false;

  Stream<Uri> get links => _controller.stream;

  bool ownsDelivery(Uri uri) {
    try {
      return _receivedIds.contains(uri.queryParameters['widget_delivery']);
    } on FormatException {
      return false;
    }
  }

  void _subscribe() {
    final generation = ++_generation;
    _bufferedHotDeliveries.clear();
    _backlogReady = false;
    _draining = false;
    _redrainRequested = false;
    // Install the handler before requesting the ordered native backlog.
    // Buffer newer hot taps until that snapshot is emitted, deduplicating IDs.
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLaunch') {
        if (generation != _generation) return null;
        if (!_backlogReady || _draining) {
          // The native snapshot has receipt order. Emit it before newer hot
          // taps even if its method-channel result arrives after onLaunch.
          _bufferedHotDeliveries.add(call.arguments);
        } else {
          await _receive(call.arguments, generation);
        }
      }
      return null;
    });
    unawaited(_drain(generation));
  }

  Future<void> _drain(int generation) async {
    if (generation != _generation || !_controller.hasListener || _draining) {
      return;
    }
    _draining = true;
    _backlogReady = false;
    try {
      final pending = await _channel.invokeListMethod<Object?>('subscribe');
      if (generation != _generation) return;
      _retryAttempt = 0;
      for (final delivery in pending ?? const <Object?>[]) {
        await _receive(delivery, generation);
      }
      while (generation == _generation && _bufferedHotDeliveries.isNotEmpty) {
        await _receive(_bufferedHotDeliveries.removeFirst(), generation);
      }
      if (generation == _generation) _backlogReady = true;
    } catch (error, stack) {
      debugPrint('[WidgetLaunch] subscription failed: $error\n$stack');
      _scheduleRetry(generation);
    } finally {
      if (generation == _generation) {
        _draining = false;
        if (_redrainRequested && _controller.hasListener) {
          _redrainRequested = false;
          _retryTimer?.cancel();
          _retryTimer = null;
          unawaited(_drain(generation));
        }
      }
    }
  }

  void _scheduleRetry(int generation) {
    if (generation != _generation ||
        !_controller.hasListener ||
        _retryTimer?.isActive == true) {
      return;
    }
    const delays = [1, 2, 4, 8, 16];
    final seconds = delays[_retryAttempt < 4 ? _retryAttempt++ : 4];
    _retryTimer = Timer(Duration(seconds: seconds), () {
      _retryTimer = null;
      if (generation != _generation || !_controller.hasListener) return;
      if (_draining) {
        // A slow ACK must not consume the only scheduled retry wakeup.
        _redrainRequested = true;
      } else {
        unawaited(_drain(generation));
      }
    });
  }

  Future<void> _receive(Object? raw, int generation) async {
    if (generation != _generation || !_controller.hasListener) return;
    if (raw is! Map) return;
    final id = raw['id'];
    final link = raw['uri'];
    if (id is! String || id.trim().isEmpty) return;
    final uri = _uriFromEnvelope(link, id);
    if (uri == null) {
      // Reject corrupt native envelopes terminally instead of retaining them
      // forever. No URI from this branch is emitted to the application.
      _receivedIds.add(id);
      await _acknowledgeId(id);
      return;
    }
    if (_receivedIds.add(id)) {
      _controller.add(uri);
    } else if (_terminalIds.contains(id)) {
      await acknowledge(uri);
    }
  }

  static Uri? _uriFromEnvelope(Object? link, String id) {
    if (link is! String) return null;
    try {
      final uri = Uri.tryParse(link);
      if (uri == null || uri.scheme != 'duoyi' || !uri.hasAuthority) {
        return null;
      }
      final parameters = uri.queryParametersAll;
      final sources = parameters['source'];
      final deliveries = parameters['widget_delivery'];
      if (sources?.length != 1 ||
          sources!.single != 'widget' ||
          deliveries?.length != 1 ||
          deliveries!.single != id) {
        return null;
      }
      return uri;
    } on FormatException {
      return null;
    }
  }

  Future<void> acknowledge(Uri uri) async {
    if (!ownsDelivery(uri)) return;
    final id = uri.queryParameters['widget_delivery'];
    if (id == null || !_receivedIds.contains(id)) return;
    await _acknowledgeId(id);
  }

  Future<void> _acknowledgeId(String id) async {
    _terminalIds.add(id);
    try {
      // The caller has accepted or rejected dispatch. ACK is not a claim that
      // a provider's asynchronous data mutation has finished successfully.
      await _channel.invokeMethod<void>('ack', id);
      if (_acknowledgedIds.add(id)) _acknowledgedOrder.add(id);
      // Native cannot replay an ACKed entry. Retain a generous overlap window
      // for already returned drain snapshots; unacknowledged IDs stay tracked.
      while (_acknowledgedOrder.length > 4096) {
        final expired = _acknowledgedOrder.removeFirst();
        _acknowledgedIds.remove(expired);
        _receivedIds.remove(expired);
        _terminalIds.remove(expired);
      }
    } catch (error, stack) {
      // Native retains it for reconnect. A repeated delivery is ACKed again
      // without being added to the Dart stream for a second time.
      debugPrint('[WidgetLaunch] acknowledgement failed: $error\n$stack');
      _scheduleRetry(_generation);
    }
  }

  void _unsubscribe() {
    ++_generation;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
    _bufferedHotDeliveries.clear();
    _backlogReady = false;
    _draining = false;
    _redrainRequested = false;
    _receivedIds.removeWhere((id) => !_terminalIds.contains(id));
    unawaited(() async {
      try {
        await _channel.invokeMethod<void>('unsubscribe');
      } catch (error, stack) {
        debugPrint('[WidgetLaunch] unsubscribe failed: $error\n$stack');
      }
    }());
  }
}
