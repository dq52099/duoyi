import 'package:crypto/crypto.dart' show sha256;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/account_preference_writes.dart';

/// 应用锁：本地 PIN(4-8 位数字) + 可选自动锁定超时。
/// 使用 SHA-256 + 固定 salt 的单向哈希存储；无法重置需清应用数据。
class AppLockProvider extends ChangeNotifier {
  static const _kHash = 'app_lock_pin_hash';
  static const _kEnabled = 'app_lock_enabled';
  static const _kAutoLockMinutes = 'app_lock_auto_minutes';
  static const _kLastActive = 'app_lock_last_active';
  static const _salt = 'duoyi_lock_v1';

  bool _enabled = false;
  int _autoLockMinutes = 5;
  bool _isLocked = false;
  DateTime _lastActive = DateTime.now();
  int _accessGeneration = 0;
  bool _disposed = false;
  int _settingsGeneration = 0;
  Future<void> _settingsWrites = Future<void>.value();

  bool get enabled => _enabled;
  bool get isLocked => _enabled && _isLocked;
  int get accessGeneration => _accessGeneration;
  int get autoLockMinutes => _autoLockMinutes;

  bool _validPin(String pin) => RegExp(r'^\d{4,8}$').hasMatch(pin);

  Future<void> loadFromStorage() {
    _accessGeneration++;
    final generation = ++_settingsGeneration;
    return _enqueueSettings(() async {
      final p = await SharedPreferences.getInstance();
      if (_disposed || generation != _settingsGeneration) return;
      _enabled = p.getBool(_kEnabled) ?? false;
      _autoLockMinutes = (p.getInt(_kAutoLockMinutes) ?? 5).clamp(0, 240);
      final lastStr = p.getString(_kLastActive);
      _lastActive = lastStr != null
          ? (DateTime.tryParse(lastStr) ?? DateTime.now())
          : DateTime.now();
      // 启动时如果启用了锁，就立即处于锁定态
      _isLocked = _enabled;
      notifyListeners();
    });
  }

  String _hash(String pin) {
    final bytes = utf8.encode(_salt + pin);
    return sha256.convert(bytes).toString();
  }

  Future<bool> setPin(String pin) async {
    if (!_validPin(pin)) return false;
    _accessGeneration++;
    return _writeSettings<bool>(
      (transaction, _) async {
        await transaction.setString(_kHash, _hash(pin));
        await transaction.setBool(_kEnabled, true);
        return true;
      },
      onCommitted: (_) {
        // Updating a credential must not unlock a lock raised during saving.
        _enabled = true;
        notifyListeners();
      },
    );
  }

  Future<bool> disable(String currentPin) async {
    _accessGeneration++;
    return _writeSettings<bool>(
      (transaction, preferences) async {
        if (!_matchesPin(currentPin, preferences)) return false;
        // Disable first. A failed second write is restored by the transaction.
        await transaction.setBool(_kEnabled, false);
        await transaction.remove(_kHash);
        return true;
      },
      onCommitted: (changed) {
        if (!changed) return;
        _enabled = false;
        _isLocked = false;
        notifyListeners();
      },
    );
  }

  Future<bool> verify(String pin) async {
    if (!_validPin(pin)) return false;
    // Never read a partially written credential pair.
    await _settingsWrites;
    final p = await SharedPreferences.getInstance();
    return !_disposed && _matchesPin(pin, p);
  }

  bool _matchesPin(String pin, SharedPreferences preferences) =>
      _validPin(pin) && preferences.getString(_kHash) == _hash(pin);

  Future<T> _enqueueSettings<T>(Future<T> Function() operation) {
    final result = _settingsWrites.then((_) => operation());
    _settingsWrites = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<T> _writeSettings<T>(
    Future<T> Function(AccountPreferenceTransaction, SharedPreferences)
    operation, {
    required void Function(T) onCommitted,
  }) {
    final generation = _settingsGeneration;
    bool isCurrent() => !_disposed && generation == _settingsGeneration;
    return _enqueueSettings(() async {
      if (!isCurrent()) throw const AccountPreferenceWriteCanceled();
      final preferences = await SharedPreferences.getInstance();
      final transaction = AccountPreferenceTransaction(preferences, isCurrent);
      try {
        final result = await operation(transaction, preferences);
        transaction.commit();
        onCommitted(result);
        return result;
      } catch (_) {
        // This device setting queue serializes reloads and other saves too, so
        // a canceled operation can restore its snapshot before the next one.
        await transaction.rollback(canceledBeforeCleanup: true);
        rethrow;
      }
    });
  }

  /// The initiating screen and lock state must still be current after checking
  /// the PIN. A late result must not unlock a new lock or a dismissed screen.
  Future<void> unlockWith(String pin, {bool Function()? isCurrent}) async {
    if (_disposed || !(isCurrent?.call() ?? true)) return;
    final generation = _accessGeneration;
    final verified = await verify(pin);
    if (_disposed ||
        generation != _accessGeneration ||
        !verified ||
        !(isCurrent?.call() ?? true)) {
      return;
    }
    _isLocked = false;
    _lastActive = DateTime.now();
    notifyListeners();
  }

  void lock() {
    if (!_enabled) return;
    _accessGeneration++;
    _isLocked = true;
    notifyListeners();
  }

  Future<void> setAutoLockMinutes(int m) {
    final minutes = m.clamp(0, 240);
    return _writeSettings<void>(
      (transaction, _) async {
        await transaction.setInt(_kAutoLockMinutes, minutes);
      },
      onCommitted: (_) {
        _autoLockMinutes = minutes;
        notifyListeners();
      },
    );
  }

  /// 应用退到后台/恢复前台时由外部调用以决定是否锁。
  Future<void> onAppLifecycleInactive() async {
    _lastActive = DateTime.now();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLastActive, _lastActive.toIso8601String());
  }

  Future<void> onAppLifecycleResume() async {
    if (!_enabled) return;
    if (_autoLockMinutes == 0) {
      // 0 = 每次切回立刻锁
      lock();
      return;
    }
    final diff = DateTime.now().difference(_lastActive);
    if (diff.inMinutes >= _autoLockMinutes) {
      lock();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _accessGeneration++;
    _settingsGeneration++;
    super.dispose();
  }
}
