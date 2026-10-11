import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Tracks writes before their first await so account cleanup can drain them.
class AccountPreferenceWrites {
  AccountPreferenceWrites._();

  static int _generation = 0;
  static int _boundaryDepth = 0;
  static Completer<void>? _boundaryFinished;
  static final Set<Future<void>> _pending = {};

  static int get generation => _generation;
  static bool get isBoundaryActive => _boundaryDepth > 0;

  static void invalidate() => _generation++;

  static Future<void> run(
    Future<void> Function(AccountPreferenceWriteToken token) operation,
  ) {
    if (_boundaryDepth > 0) return Future<void>.value();
    final token = AccountPreferenceWriteToken._(_generation);
    final pending = Future<void>.sync(() => operation(token));
    _pending.add(pending);
    pending.then(
      (_) => _pending.remove(pending),
      onError: (Object error, StackTrace stack) => _pending.remove(pending),
    );
    return pending;
  }

  static Future<T> runResult<T>(
    Future<T> Function(AccountPreferenceWriteToken token) operation, {
    required T Function() canceledResult,
  }) {
    if (_boundaryDepth > 0) return Future<T>.value(canceledResult());
    final token = AccountPreferenceWriteToken._(_generation);
    final result = Future<T>.sync(() => operation(token));
    final pending = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pending.add(pending);
    pending.then((_) => _pending.remove(pending));
    return result;
  }

  static Future<void> drain() async {
    while (_pending.isNotEmpty) {
      await Future.wait(
        _pending.toList().map(
          (pending) =>
              pending.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        ),
      );
    }
  }

  /// Lets untracked UI reads wait until account cleanup has settled.
  /// Do not call this from a tracked write: cleanup is draining that write.
  static Future<void> waitForBoundary() async {
    while (_boundaryDepth > 0) {
      await _boundaryFinished!.future;
    }
  }

  static Future<T> boundary<T>(Future<T> Function() operation) async {
    _boundaryDepth++;
    _boundaryFinished ??= Completer<void>();
    invalidate();
    try {
      await drain();
      return await operation();
    } finally {
      _boundaryDepth--;
      if (_boundaryDepth == 0) {
        final finished = _boundaryFinished;
        _boundaryFinished = null;
        finished?.complete();
      }
    }
  }
}

class AccountPreferenceWriteToken {
  final int _generation;
  AccountPreferenceWriteToken._(this._generation);

  bool get isCurrent =>
      _generation == AccountPreferenceWrites._generation &&
      AccountPreferenceWrites._boundaryDepth == 0;

  void ensureCurrent() {
    if (!isCurrent) throw const AccountPreferenceWriteCanceled();
  }
}

class AccountPreferenceWriteCanceled implements Exception {
  const AccountPreferenceWriteCanceled();
}

/// Validates legacy SharedPreferences results and restores multi-key changes
/// on failure. Account cleanup waits for every issued platform write.
class AccountPreferenceTransaction {
  final SharedPreferences _preferences;
  final bool Function() _isCurrent;
  final Map<String, Object?> _previous = {};
  bool _committed = false;

  AccountPreferenceTransaction(this._preferences, this._isCurrent);

  bool get isCommitted => _committed;
  Iterable<String> get changedKeys => _previous.keys;

  void commit() {
    ensureCurrent();
    _committed = true;
    _previous.clear();
  }

  void ensureCurrent() {
    if (!_isCurrent()) throw const AccountPreferenceWriteCanceled();
  }

  Future<AccountPreferenceTransaction> getPreferences() async {
    ensureCurrent();
    return this;
  }

  Future<bool> _write(String key, Future<bool> Function() write) async {
    ensureCurrent();
    _previous.putIfAbsent(key, () => _preferences.get(key));
    final saved = await write();
    ensureCurrent();
    if (!saved) throw StateError('Preference persistence failed');
    return true;
  }

  Future<bool> setBool(String key, bool value) =>
      _write(key, () => _preferences.setBool(key, value));
  Future<bool> setInt(String key, int value) =>
      _write(key, () => _preferences.setInt(key, value));
  Future<bool> setDouble(String key, double value) =>
      _write(key, () => _preferences.setDouble(key, value));
  Future<bool> setString(String key, String value) =>
      _write(key, () => _preferences.setString(key, value));
  Future<bool> setStringList(String key, List<String> value) =>
      _write(key, () => _preferences.setStringList(key, value));
  Future<bool> remove(String key) =>
      _write(key, () => _preferences.remove(key));

  Future<void> reload() async {
    ensureCurrent();
    await _preferences.reload();
    ensureCurrent();
  }

  Future<void> rollback({bool canceledBeforeCleanup = false}) async {
    for (final entry in _previous.entries.toList().reversed) {
      if (!canceledBeforeCleanup && !_isCurrent()) return;
      final value = entry.value;
      try {
        switch (value) {
          case bool():
            await _preferences.setBool(entry.key, value);
          case int():
            await _preferences.setInt(entry.key, value);
          case double():
            await _preferences.setDouble(entry.key, value);
          case String():
            await _preferences.setString(entry.key, value);
          case List<String>():
            await _preferences.setStringList(entry.key, value);
          case null:
            await _preferences.remove(entry.key);
          default:
            throw StateError('Unsupported preference value');
        }
      } catch (_) {
        // Reload below reflects disk even if a failed device cannot restore it.
      }
    }
    if (canceledBeforeCleanup || _isCurrent()) await _preferences.reload();
  }
}
