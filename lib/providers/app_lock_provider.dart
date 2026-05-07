import 'package:crypto/crypto.dart' show sha256;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  bool get enabled => _enabled;
  bool get isLocked => _enabled && _isLocked;
  int get autoLockMinutes => _autoLockMinutes;

  Future<void> loadFromStorage() async {
    final p = await SharedPreferences.getInstance();
    _enabled = p.getBool(_kEnabled) ?? false;
    _autoLockMinutes = p.getInt(_kAutoLockMinutes) ?? 5;
    final lastStr = p.getString(_kLastActive);
    _lastActive = lastStr != null
        ? (DateTime.tryParse(lastStr) ?? DateTime.now())
        : DateTime.now();
    // 启动时如果启用了锁，就立即处于锁定态
    _isLocked = _enabled;
    notifyListeners();
  }

  String _hash(String pin) {
    final bytes = utf8.encode(_salt + pin);
    return sha256.convert(bytes).toString();
  }

  Future<bool> setPin(String pin) async {
    if (pin.length < 4 || pin.length > 8) return false;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kHash, _hash(pin));
    await p.setBool(_kEnabled, true);
    _enabled = true;
    _isLocked = false;
    notifyListeners();
    return true;
  }

  Future<void> disable(String currentPin) async {
    if (!await verify(currentPin)) return;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kHash);
    await p.setBool(_kEnabled, false);
    _enabled = false;
    _isLocked = false;
    notifyListeners();
  }

  Future<bool> verify(String pin) async {
    final p = await SharedPreferences.getInstance();
    final stored = p.getString(_kHash);
    if (stored == null) return false;
    return stored == _hash(pin);
  }

  Future<void> unlockWith(String pin) async {
    if (await verify(pin)) {
      _isLocked = false;
      _lastActive = DateTime.now();
      notifyListeners();
    }
  }

  void lock() {
    if (!_enabled) return;
    _isLocked = true;
    notifyListeners();
  }

  Future<void> setAutoLockMinutes(int m) async {
    _autoLockMinutes = m.clamp(0, 240);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kAutoLockMinutes, _autoLockMinutes);
    notifyListeners();
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
      _isLocked = true;
      notifyListeners();
      return;
    }
    final diff = DateTime.now().difference(_lastActive);
    if (diff.inMinutes >= _autoLockMinutes) {
      _isLocked = true;
      notifyListeners();
    }
  }
}
