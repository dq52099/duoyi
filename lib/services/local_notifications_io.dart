import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

import '../core/local_timezone_resolver.dart';

/// 本地通知 / 每日闹钟(Android + iOS + Linux 实现)。
class LocalNotifications {
  static final LocalNotifications instance = LocalNotifications._();
  LocalNotifications._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _granted = false;
  bool get permissionGranted => _granted;

  /// Tap 回调(payload)——由主入口注册处理 deep link。
  void Function(String payload)? onTap;

  Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    // 若主入口已经通过 LocalTimezoneResolver.init() 设置过 tz.local，则直接沿用；
    // 否则按原有回退策略（系统 timeZoneName → UTC）临时设置，等主入口
    // 下次 resolver 刷新时再覆盖。
    if (!LocalTimezoneResolver.isInitialized) {
      try {
        tz.setLocalLocation(tz.getLocation(DateTime.now().timeZoneName));
      } catch (_) {
        // 某些设备 timeZoneName 不是 IANA；回退到 UTC，仍可工作。
        tz.setLocalLocation(tz.UTC);
      }
    }

    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const linuxInit = LinuxInitializationSettings(defaultActionName: 'Open');
    await _plugin.initialize(
      const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
        macOS: iosInit,
        linux: linuxInit,
      ),
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload != null && onTap != null) onTap!(payload);
      },
    );

    // 建立默认渠道
    if (_isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        'duoyi_general',
        '多仪 · 常规',
        description: '日常提醒(到期/打卡/番茄)',
        importance: Importance.high,
      ));
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        'duoyi_alarm',
        '多仪 · 闹钟',
        description: '重要提醒会发声',
        importance: Importance.max,
      ));
    }

    _initialized = true;
    // 默认先探测权限状态
    await _probePermission();
  }

  bool get _isAndroid {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  bool get _isIOS {
    if (kIsWeb) return false;
    try {
      return Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestPermission() async {
    if (!_initialized) await init();
    if (_isAndroid) {
      final status = await Permission.notification.request();
      _granted = status.isGranted;
      // 精准闹钟 (Android 12+) 需另外申请
      try {
        await Permission.scheduleExactAlarm.request();
      } catch (_) {}
      return _granted;
    }
    if (_isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await ios?.requestPermissions(
            alert: true, badge: true, sound: true,
          ) ??
          false;
      _granted = granted;
      return granted;
    }
    // Linux / macOS: 假设可用
    _granted = true;
    return true;
  }

  Future<void> _probePermission() async {
    if (_isAndroid) {
      _granted = await Permission.notification.isGranted;
    } else {
      _granted = true;
    }
  }

  NotificationDetails _details({String channelId = 'duoyi_general'}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelId == 'duoyi_alarm' ? '多仪 · 闹钟' : '多仪 · 常规',
        channelDescription:
            channelId == 'duoyi_alarm' ? '重要提醒会发声' : '日常提醒(到期/打卡/番茄)',
        importance: channelId == 'duoyi_alarm' ? Importance.max : Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(),
      macOS: const DarwinNotificationDetails(),
      linux: const LinuxNotificationDetails(),
    );
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
    String? channelId,
  }) async {
    if (!_initialized) await init();
    await _plugin.show(id, title, body,
        _details(channelId: channelId ?? 'duoyi_general'),
        payload: payload);
  }

  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
    String? channelId,
  }) async {
    if (!_initialized) await init();
    if (when.isBefore(DateTime.now())) return;
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      _details(channelId: channelId ?? 'duoyi_general'),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  /// 每日固定时间；可选 weekdays (1=Mon..7=Sun) 限定某几天。
  /// 当传入 weekdays 时会内部生成多条 matchDateTimeComponents 调度。
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? payload,
    String? channelId,
    List<int>? weekdays,
  }) async {
    if (!_initialized) await init();
    final details = _details(channelId: channelId ?? 'duoyi_general');

    if (weekdays == null || weekdays.isEmpty) {
      // 每天
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        _nextInstanceOfTime(hour, minute),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } else {
      // 每个 weekday 一条，ID 用基础 id + 偏移保证唯一
      for (final w in weekdays) {
        final subId = _subId(id, w);
        await _plugin.zonedSchedule(
          subId,
          title,
          body,
          _nextInstanceOfWeekdayTime(w, hour, minute),
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
        );
      }
    }
  }

  int _subId(int base, int weekday) => base * 10 + weekday;

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  tz.TZDateTime _nextInstanceOfWeekdayTime(
      int weekday, int hour, int minute) {
    var scheduled = _nextInstanceOfTime(hour, minute);
    while (scheduled.weekday != weekday) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  Future<void> cancel(int id) async {
    if (!_initialized) return;
    await _plugin.cancel(id);
    // 也清理按 weekday 展开的副本
    for (int w = 1; w <= 7; w++) {
      await _plugin.cancel(_subId(id, w));
    }
  }

  Future<void> cancelAll() async {
    if (!_initialized) return;
    await _plugin.cancelAll();
  }

  Future<List<int>> pendingIds() async {
    if (!_initialized) return const [];
    final pending = await _plugin.pendingNotificationRequests();
    return pending.map((e) => e.id).toList();
  }
}
