import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 统一的本地时区解析器。
///
/// 调用顺序：
/// 1. 默认跟随手机系统 IANA 时区（例：`America/Mexico_City`）
/// 2. 用户显式固定应用内时区时使用该 IANA 名
/// 3. 系统只返回 `UTC` 或不可解析值时回退 `Asia/Shanghai`
///
/// 任何"什么时候响"的调度代码必须使用 `tz.TZDateTime.from(dateTime, tz.local)`，
/// 禁止直接 `DateTime.utc(...)` 传入 `zonedSchedule`。
class LocalTimezoneResolver {
  LocalTimezoneResolver._();

  static const String preferenceKey = 'pref_app_timezone_iana';
  static const String modePreferenceKey = 'pref_app_timezone_mode';
  static const String defaultIana = 'Asia/Shanghai';
  static const String followSystemValue = 'system';
  static const String fixedValue = 'fixed';

  @visibleForTesting
  static Future<String?> Function()? debugSystemTimeZoneReader;

  /// 非理想路径的日志（`flutter_timezone` 失败 / 回退次数等），便于 QA 排查。
  static final List<String> diagnostics = [];

  static bool _initialized = false;
  static String _currentIana = defaultIana;

  /// 解析出的 IANA 名，例如 `Asia/Shanghai`。
  static String get currentIana => _currentIana;

  /// 是否已初始化（`init()` 是否被调用过）。
  static bool get isInitialized => _initialized;

  /// 初始化时区数据库并设置 `tz.local`。幂等调用。
  ///
  /// 应在 `runApp` 之前、`main()` 初始化阶段调用一次。
  static Future<void> init() async {
    // tz 数据库是进程级全局的，允许多次调用，但只有第一次生效。
    tzdata.initializeTimeZones();

    final name = await _resolveIanaName();
    _setLocation(name);
    _initialized = true;
  }

  /// 重新探测并应用当前系统时区。返回新的 IANA 名。
  ///
  /// 用于 `AppLifecycleState.resumed` 时对比缓存值，若变化则触发
  /// `ReminderScheduler.resyncAll`。
  static Future<String> refresh() async {
    final name = await _resolveIanaName();
    _setLocation(name);
    return _currentIana;
  }

  static Future<void> setApplicationTimeZone(String name) async {
    tzdata.initializeTimeZones();
    final p = await SharedPreferences.getInstance();
    if (name == followSystemValue) {
      await p.setString(modePreferenceKey, followSystemValue);
      await p.remove(preferenceKey);
      final resolved = await _resolveIanaName();
      _setLocation(resolved);
      _initialized = true;
      return;
    }
    final next = _canResolve(name) && name != 'UTC' ? name : defaultIana;
    await p.setString(modePreferenceKey, fixedValue);
    await p.setString(preferenceKey, next);
    _setLocation(next);
    _initialized = true;
  }

  static Future<String> _resolveIanaName() async {
    try {
      final p = await SharedPreferences.getInstance();
      final mode = p.getString(modePreferenceKey) ?? followSystemValue;
      final saved = p.getString(preferenceKey);
      if (mode == fixedValue &&
          saved != null &&
          saved.isNotEmpty &&
          _canResolve(saved)) {
        if (saved == 'UTC') {
          _log('固定应用时区为 UTC，改用 $defaultIana');
          await p.setString(preferenceKey, defaultIana);
          return defaultIana;
        }
        return saved;
      }

      final systemName = await _readSystemIanaName();
      if (systemName != null) return systemName;

      _log('系统时区不可用，回退到 $defaultIana');
      return defaultIana;
    } catch (e) {
      _log('解析应用时区失败: $e，回退到 $defaultIana');
      return defaultIana;
    }
  }

  static Future<String?> _readSystemIanaName() async {
    try {
      final debugName = await debugSystemTimeZoneReader?.call();
      if (_isUsableIana(debugName)) return debugName;
    } catch (_) {
      // 测试注入失败时继续走真实平台。
    }

    try {
      final name = await FlutterTimezone.getLocalTimezone();
      if (_isUsableIana(name)) return name;
      _log('flutter_timezone 返回不可用时区: "$name"');
    } catch (e) {
      _log('flutter_timezone.getLocalTimezone 异常: $e');
    }

    final dartName = DateTime.now().timeZoneName;
    if (_isUsableIana(dartName)) return dartName;
    _log('DateTime.timeZoneName 不可用: "$dartName"');
    return null;
  }

  static bool _isUsableIana(String? name) {
    if (name == null || name.isEmpty || name == 'UTC') return false;
    return _canResolve(name);
  }

  static bool _canResolve(String name) {
    try {
      tz.getLocation(name);
      return true;
    } catch (_) {
      return false;
    }
  }

  static void _setLocation(String name) {
    try {
      tz.setLocalLocation(tz.getLocation(name));
      _currentIana = name;
    } catch (e) {
      _log('setLocalLocation 失败(name=$name): $e，强制使用 $defaultIana');
      final fallback = tz.getLocation(defaultIana);
      tz.setLocalLocation(fallback);
      _currentIana = defaultIana;
    }
  }

  static void _log(String msg) {
    diagnostics.add(msg);
    if (kDebugMode) {
      debugPrint('[LocalTimezoneResolver] $msg');
    }
  }
}
