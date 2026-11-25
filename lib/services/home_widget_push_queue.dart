import 'dart:async';

/// Coalesces foreground changes and opportunistically drains before suspension.
/// Publication identity and account-generation checks remain in [publish].
class HomeWidgetPushQueue {
  HomeWidgetPushQueue({
    required bool Function() canPublish,
    required String Function() readSignature,
    required Future<bool> Function() publish,
    DateTime Function()? now,
    void Function(Object error, StackTrace? stack)? onFailure,
  }) : _canPublish = canPublish,
       _readSignature = readSignature,
       _publish = publish,
       _now = now ?? DateTime.now,
       _onFailure = onFailure;

  static const debounceDelay = Duration(milliseconds: 2200);
  static const minimumInterval = Duration(seconds: 8);
  static const _maxForegroundRetries = 3;
  static const _maxBackgroundPasses = 2;

  final bool Function() _canPublish;
  final String Function() _readSignature;
  final Future<bool> Function() _publish;
  final DateTime Function() _now;
  final void Function(Object error, StackTrace? stack)? _onFailure;
  Timer? _timer;
  Future<void>? _running;
  DateTime? _lastStartedAt;
  String _lastSignature = '';
  bool _pending = false;
  bool _background = false;
  bool _disposed = false;
  int _retries = 0;

  void invalidateSignature() => _lastSignature = '';

  void queue() {
    if (_disposed || !_canPublish()) return;
    _pending = true;
    _retries = 0;
    if (_background) {
      _cancelTimer();
      unawaited(flush());
    } else {
      _schedule();
    }
  }

  /// Repeated inactive/paused signals share one background transition. Changes
  /// arriving between those signals still go through [queue] immediately.
  void setBackground(bool value) {
    if (_disposed || _background == value) return;
    _background = value;
    _cancelTimer();
    if (value) {
      if (_pending) unawaited(flush());
    } else {
      _retries = 0;
      if (_pending) _schedule();
    }
  }

  /// Waits for this drain, including at most one immediate background followup.
  /// Completion does not promise OS refresh or successful publication.
  Future<void> flush() {
    if (_disposed) return Future<void>.value();
    final running = _running;
    if (running != null) return running;
    _cancelTimer();
    final completion = Completer<void>();
    _running = completion.future;
    unawaited(() async {
      try {
        await _drain();
      } finally {
        _running = null;
        completion.complete();
        if (!_disposed &&
            !_background &&
            _pending &&
            _retries <= _maxForegroundRetries) {
          _schedule();
        }
      }
    }());
    return completion.future;
  }

  Future<void> _drain() async {
    var passes = 0;
    while (!_disposed && _pending && _canPublish()) {
      _pending = false;
      var succeeded = true;
      try {
        final signature = _readSignature();
        if (signature != _lastSignature) {
          _lastSignature = signature;
          _lastStartedAt = _now();
          succeeded = await _publish();
          if (!succeeded) {
            _onFailure?.call(
              StateError('queued widget publication failed'),
              null,
            );
          }
        }
      } catch (error, stack) {
        succeeded = false;
        _onFailure?.call(error, stack);
      }
      passes++;
      if (!succeeded) {
        _lastSignature = '';
        _pending = true;
        _retries++;
        // Keep dirty work for resume; never spin or start a background timer.
        break;
      }
      _retries = 0;
      if (!_background || passes >= _maxBackgroundPasses) break;
    }
  }

  void _schedule() {
    _cancelTimer();
    if (_disposed || !_canPublish()) return;
    final last = _lastStartedAt;
    final remaining = last == null
        ? debounceDelay
        : minimumInterval - _now().difference(last);
    final delay = remaining > debounceDelay ? remaining : debounceDelay;
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(flush());
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _disposed = true;
    _cancelTimer();
  }
}
