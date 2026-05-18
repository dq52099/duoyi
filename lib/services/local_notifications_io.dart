import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

import '../core/local_timezone_resolver.dart';
import 'notification_permission_exception.dart';

/// 本地通知 / 每日闹钟(Android + iOS + Linux 实现)。
class LocalNotifications {
  static final LocalNotifications instance = LocalNotifications._();
  LocalNotifications._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _granted = false;
  String? _launchPayload;
  bool get permissionGranted => _granted;
  static const RawResourceAndroidNotificationSound _alarmSound =
      RawResourceAndroidNotificationSound('duoyi_alarm');
  static const RawResourceAndroidNotificationSound _defaultSound =
      RawResourceAndroidNotificationSound('duoyi_alarm');
  static const String _defaultChannelId = 'duoyi_general_alerts_v7';
  static const String _alarmChannelId = 'duoyi_alarm_fullscreen_v6';
  static const Set<String> _legacyChannelIds = <String>{
    'duoyi_general_alerts_v2',
    'duoyi_general_alerts_v3',
    'duoyi_general_alerts_v4',
    'duoyi_general_alerts_v5',
    'duoyi_general_alerts_v6',
    'duoyi_alarm',
    'duoyi_alarm_fullscreen_v3',
    'duoyi_alarm_fullscreen_v4',
    'duoyi_alarm_fullscreen_v5',
  };

  /// Tap 回调(payload)——由主入口注册处理 deep link。
  void Function(String payload)? onTap;

  Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    if (!LocalTimezoneResolver.isInitialized) {
      await LocalTimezoneResolver.init();
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
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
        final actionId = resp.actionId;
        // 把 todo 的 action 按钮映射成深链 payload
        if (actionId != null && actionId.isNotEmpty) {
          if (actionId.startsWith('todo_complete_')) {
            final id = actionId.substring('todo_complete_'.length);
            if (onTap != null) onTap!('duoyi://action/complete_todo?id=$id');
            return;
          }
          if (actionId.startsWith('todo_snooze_')) {
            final id = actionId.substring('todo_snooze_'.length);
            if (onTap != null) {
              onTap!(
                'duoyi://snooze/${resp.id ?? 0}'
                '?delay=5&payload=duoyi://todo/$id',
              );
            }
            return;
          }
        }
        final payload = resp.payload;
        if (payload != null && onTap != null) onTap!(payload);
      },
    );

    try {
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      final launchPayload = launchDetails?.notificationResponse?.payload;
      if (launchDetails?.didNotificationLaunchApp == true &&
          launchPayload != null &&
          launchPayload.isNotEmpty) {
        _launchPayload = launchPayload;
      }
    } catch (e, st) {
      debugPrint('[LocalNotifications] launch payload probe failed: $e\n$st');
    }

    // 建立默认渠道
    if (_isAndroid) {
      try {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await android?.createNotificationChannel(
          const AndroidNotificationChannel(
            _defaultChannelId,
            '多仪 · 通知提醒',
            description: '日常提醒会发声、震动并尽量弹出横幅',
            importance: Importance.max,
            playSound: true,
            sound: _defaultSound,
            enableVibration: true,
            audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
          ),
        );
        await android?.createNotificationChannel(
          AndroidNotificationChannel(
            _alarmChannelId,
            '多仪 · 强提醒',
            description: '重要提醒会响铃、震动并弹出确认界面',
            importance: Importance.max,
            playSound: true,
            sound: _alarmSound,
            enableVibration: true,
            audioAttributesUsage: AudioAttributesUsage.alarm,
          ),
        );
        for (final channelId in _legacyChannelIds) {
          await android?.deleteNotificationChannel(channelId);
        }
      } catch (e, st) {
        debugPrint('[LocalNotifications] channel setup failed: $e\n$st');
      }
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
    try {
      if (!_initialized) await init();
    } catch (e, st) {
      debugPrint('[LocalNotifications] init before permission failed: $e\n$st');
      return false;
    }
    if (_isAndroid) {
      try {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        _granted =
            await android?.requestNotificationsPermission() ??
            await Permission.notification.request().isGranted;
      } catch (_) {
        final status = await Permission.notification.request();
        _granted = status.isGranted;
      }
      return _granted;
    }
    if (_isIOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final granted =
          await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
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
    if (_isAndroid || _isIOS) {
      try {
        _granted = await Permission.notification.status.isGranted;
      } catch (_) {
        _granted = true;
      }
    } else {
      _granted = true;
    }
  }

  /// 重新探测当前通知权限状态，不弹系统对话框。
  Future<bool> refreshPermission() async {
    if (!_initialized) await init();
    await _probePermission();
    return _granted;
  }

  Future<bool> ensurePermission() async {
    if (!_initialized) await init();
    await _probePermission();
    if (_granted) return true;
    return requestPermission();
  }

  Future<void> _ensureDeliveryPermission(String operation) async {
    final granted = await ensurePermission();
    if (granted) return;
    debugPrint(
      '[LocalNotifications] $operation skipped: notification permission denied',
    );
    throw const NotificationPermissionDeniedException();
  }

  NotificationDetails _details({
    String channelId = _defaultChannelId,
    List<AndroidNotificationAction>? androidActions,
  }) {
    final isAlarm = channelId == _alarmChannelId;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        isAlarm ? '多仪 · 强提醒' : '多仪 · 通知提醒',
        channelDescription: isAlarm ? '重要提醒会响铃、震动并弹出确认界面' : '日常提醒会发声、震动并尽量弹出横幅',
        importance: Importance.max,
        priority: Priority.max,
        category: isAlarm
            ? AndroidNotificationCategory.alarm
            : AndroidNotificationCategory.reminder,
        playSound: true,
        sound: isAlarm ? _alarmSound : _defaultSound,
        enableVibration: true,
        audioAttributesUsage: isAlarm
            ? AudioAttributesUsage.alarm
            : AudioAttributesUsage.notificationRingtone,
        visibility: NotificationVisibility.public,
        icon: '@mipmap/ic_launcher',
        ticker: '多仪提醒',
        actions: androidActions,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      ),
      macOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      ),
      linux: const LinuxNotificationDetails(),
    );
  }

  /// 为待办提醒构建 "完成 / 稍后" 两个 action 按钮。
  ///
  /// payload 形如 `duoyi://todo/{id}`。每个 action 用 input ID 绑定深链方案。
  List<AndroidNotificationAction>? _todoActionsFor(String? payload) {
    if (payload == null) return null;
    if (!payload.startsWith('duoyi://todo/')) return null;
    final id = payload.substring('duoyi://todo/'.length).split('?').first;
    if (id.isEmpty) return null;
    return [
      AndroidNotificationAction(
        'todo_complete_$id',
        '完成',
        showsUserInterface: true,
        cancelNotification: true,
      ),
      AndroidNotificationAction(
        'todo_snooze_$id',
        '5 分钟后',
        showsUserInterface: true,
        cancelNotification: true,
      ),
    ];
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
    String? channelId,
  }) async {
    if (!_initialized) await init();
    await _ensureDeliveryPermission('show');
    await _plugin.show(
      id,
      title,
      body,
      _details(
        channelId: channelId ?? _defaultChannelId,
        androidActions: _todoActionsFor(payload),
      ),
      payload: payload,
    );
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
    await _ensureDeliveryPermission('scheduleOnce');
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      _details(
        channelId: channelId ?? _defaultChannelId,
        androidActions: _todoActionsFor(payload),
      ),
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
    await _ensureDeliveryPermission('scheduleDaily');
    final details = _details(channelId: channelId ?? _defaultChannelId);

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
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  tz.TZDateTime _nextInstanceOfWeekdayTime(int weekday, int hour, int minute) {
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

  String? takeLaunchPayload() {
    final payload = _launchPayload;
    _launchPayload = null;
    return payload;
  }

  Future<Set<String>?> notificationChannelIds() async {
    if (!_isAndroid) return const <String>{};
    if (!_initialized) await init();
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final channels = await android?.getNotificationChannels();
      if (channels == null) return null;
      return channels.map((c) => c.id).toSet();
    } catch (_) {
      return null;
    }
  }
}
