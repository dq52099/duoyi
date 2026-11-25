import 'dart:async';

import 'package:flutter/foundation.dart';

/// A storage phase becomes ready only after every required load acknowledges
/// success in its captured context. Failed phases can be retried explicitly.
class RequiredStorageStartup extends ChangeNotifier {
  int _revision = 0;
  bool _ready = false;
  bool _busy = false;
  bool _failed = false;
  Future<void>? _pending;
  bool Function()? _contextCurrent;

  bool get ready => _ready && _contextCurrent?.call() == true;
  bool get busy => _busy;
  bool get failed => _failed;

  void invalidate() {
    _revision++;
    _ready = false;
    _busy = false;
    _failed = false;
    _pending = null;
    _contextCurrent = null;
    notifyListeners();
  }

  Future<void> ensure({
    required Future<void> Function(
      Future<void> Function(Future<void> Function()) load,
    )
    run,
    required bool Function() isCurrent,
    Duration loadTimeout = const Duration(seconds: 12),
  }) {
    if (!isCurrent()) {
      if (_pending == null) {
        _failed = true;
        notifyListeners();
      }
      return Future<void>.error(StateError('Storage startup context changed'));
    }
    if (_contextCurrent != null && !_contextCurrent!()) invalidate();
    final existing = _pending;
    if (existing != null) return existing;
    final revision = _revision;
    _contextCurrent = isCurrent;
    _busy = true;
    _failed = false;
    bool current() => _revision == revision && isCurrent();
    void requireCurrent() {
      if (!current()) throw StateError('Storage startup context changed');
    }

    late final Future<void> pending;
    pending =
        Future<void>.sync(() async {
          await run((task) async {
            requireCurrent();
            await Future<void>.sync(task).timeout(loadTimeout);
            requireCurrent();
          });
          requireCurrent();
          _ready = true;
          _busy = false;
          notifyListeners();
        }).catchError((Object error, StackTrace stack) {
          // An obsolete attempt cannot reset a newer phase or authorize readiness.
          if (_revision == revision && identical(_pending, pending)) {
            _ready = false;
            _busy = false;
            _failed = true;
            _pending = null;
            notifyListeners();
          }
          Error.throwWithStackTrace(error, stack);
        });
    _pending = pending;
    notifyListeners();
    return pending;
  }
}
