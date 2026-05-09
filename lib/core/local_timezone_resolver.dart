import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 统一的本地时区解析器。
///
/// 调用顺序：
/// 1. `flutter_timezone.FlutterTimezone.getLocalTimezone()` 返回 IANA 名（例：`Asia/Shanghai`）
/// 2. 失败回退到 `DateTime.now().timeZoneName`
/// 3. 再失败固定回退 `Asia/Shanghai`（对中文用户更安全，比 UTC 合理）
///
/// 任何"什么时候响"的调度代码必须使用 `tz.TZDateTime.from(dateTime, tz.local)`，
/// 禁止直接 `DateTime.utc(...)` 传入 `zonedSchedule`。
class LocalTimezoneResolver {
  LocalTimezoneResolver._();

  /// 非理想路径的日志（`flutter_timezone` 失败 / 回退次数等），便于 QA 排查。
  static final List<String> diagnostics = [];

  static bool _initialized = false;
  static String _currentIana = 'Asia/Shanghai';

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

  static Future<String> _resolveIanaName() async {
    // 1. 插件优先
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      if (name.isNotEmpty && _canResolve(name)) {
        return name;
      }
      _log('flutter_timezone 返回不可解析的名字: "$name"，继续回退');
    } catch (e) {
      _log('flutter_timezone.getLocalTimezone 异常: $e');
    }

    // 2. 系统 DateTime.timeZoneName（部分平台是 IANA，部分是缩写如 CST）
    final dartName = DateTime.now().timeZoneName;
    if (dartName.isNotEmpty && _canResolve(dartName)) {
      _log('使用 DateTime.timeZoneName 回退: "$dartName"');
      return dartName;
    }
    _log('DateTime.timeZoneName 不可解析: "$dartName"');

    // 3. 固定回退：中国大陆用户兜底
    _log('回退到 Asia/Shanghai');
    return 'Asia/Shanghai';
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
      _log('setLocalLocation 失败(name=$name): $e，强制使用 Asia/Shanghai');
      final fallback = tz.getLocation('Asia/Shanghai');
      tz.setLocalLocation(fallback);
      _currentIana = 'Asia/Shanghai';
    }
  }

  static void _log(String msg) {
    diagnostics.add(msg);
    if (kDebugMode) {
      debugPrint('[LocalTimezoneResolver] $msg');
    }
  }
}
