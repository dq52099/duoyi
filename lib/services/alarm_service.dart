import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/local_timezone_resolver.dart';
import '../core/platform_info.dart';
import 'reminder_sinks.dart';

/// 精准闹钟权限缺失异常。
///
/// Android 12+ 要求应用持有 `SCHEDULE_EXACT_ALARM` 权限才能用精准闹钟
/// 模式（`AndroidScheduleMode.exactAllowWhileIdle`）调度通知。若权限未
/// 被授予，`flutter_local_notifications` 会在 `zonedSchedule` 调用时抛出
/// `PlatformException(code: 'exact_alarms_not_permitted')`。
///
/// `AlarmService.scheduleFullScreen` 会捕获该异常并**尽力而为**降级到
/// 非精准模式重试一次（让提醒仍能发出，只是可能偏移几分钟），然后再
/// 抛出本异常；调用方捕获后可弹出"前往系统设置开启精准闹钟"的引导。
class AlarmPermissionDeniedException implements Exception {
  final String message;
  const AlarmPermissionDeniedException([this.message = '需要精准闹钟权限才能准时提醒']);

  @override
  String toString() => 'AlarmPermissionDeniedException: $message';
}

/// 闹钟通道服务（与 [LocalNotifications] 平行）。
///
/// 用于"到点必须处理"的强提醒场景：
/// - Android：`duoyi_alarm` 渠道，`Importance.max`，可按提醒配置启用
///   `fullScreenIntent`，`category=alarm`，震动模式 `[0, 500, 500, 500]`。
/// - iOS：`interruptionLevel=.timeSensitive`（避免使用 `.critical`，
///   后者需要 Apple 单独批准的 entitlement）。
/// - Linux / macOS / Windows：退化为普通通知（无全屏效果）。
///
/// 所有调度走 [FlutterLocalNotificationsPlugin.zonedSchedule]，时间统一使用
/// `tz.TZDateTime.from(when, tz.local)` 以获得"壁钟时间"语义。
class AlarmService implements ReminderAlarmSink {
  static final AlarmService instance = AlarmService._();
  AlarmService._();

  /// 独立的插件实例，与 [LocalNotifications] 互不干扰：
  /// - 各自维护自己的 `pendingNotificationRequests`；
  /// - 避免一端 `cancelAll` 误杀另一端的调度。
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  String? _launchPayload;
  bool get isInitialized => _initialized;

  /// Tap 回调（payload）——由主入口注册处理 deep link。
  void Function(String payload)? onTap;

  /// Android 闹钟通道标识。
  ///
  /// Android 通知渠道一旦在用户手机上创建，声音/弹窗等级无法通过代码修改。
  /// 使用新的 channel id 强制创建强提醒渠道，避免旧包遗留的静音/低优先级渠道
  /// 继续吞掉习惯提醒。
  static const String channelId = 'duoyi_alarm_fullscreen_v2';
  static const String legacyChannelId = 'duoyi_alarm';
  static const String _channelName = '多仪 · 强提醒';
  static const String _channelDesc = '到点响铃、震动并弹出确认界面的提醒';

  /// 震动模式：静 0 → 震 500 → 静 500 → 震 500（毫秒）。
  /// `Int64List` 无法 const 化，使用 late final 缓存。
  static final Int64List _vibrationPattern = Int64List.fromList(<int>[
    0,
    500,
    500,
    500,
  ]);
  static const List<AndroidNotificationAction> _habitActions =
      <AndroidNotificationAction>[
        AndroidNotificationAction(
          'habit_checkin',
          '完成打卡',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'habit_open',
          '打开',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ];

  /// 初始化插件与通道；幂等。
  Future<void> init() async {
    if (_initialized) return;

    // 若主入口已调用 LocalTimezoneResolver.init()，tz.local 已就绪，直接沿用；
    // 否则按宽松回退策略初始化 tz 数据库并尝试设置本地时区，
    // 等待主入口下次刷新覆盖。
    if (!LocalTimezoneResolver.isInitialized) {
      tzdata.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation(DateTime.now().timeZoneName));
      } catch (_) {
        tz.setLocalLocation(tz.UTC);
      }
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    // 不在 AlarmService 初始化时弹权限，权限由 LocalNotifications 或显式调用
    // [requestExactAlarmPermission] / 系统设置流程负责，避免重复弹窗。
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
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

    try {
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      final launchPayload = launchDetails?.notificationResponse?.payload;
      if (launchDetails?.didNotificationLaunchApp == true &&
          launchPayload != null &&
          launchPayload.isNotEmpty) {
        _launchPayload = launchPayload;
      }
    } catch (e, st) {
      debugPrint('[AlarmService] launch payload probe failed: $e\n$st');
    }

    if (_isAndroid) {
      try {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await android?.createNotificationChannel(
          AndroidNotificationChannel(
            channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.max,
            enableVibration: true,
            vibrationPattern: _vibrationPattern,
            playSound: true,
            audioAttributesUsage: AudioAttributesUsage.alarm,
          ),
        );
      } catch (e, st) {
        debugPrint('[AlarmService] channel setup failed: $e\n$st');
      }
    }

    _initialized = true;
  }

  bool get _isAndroid {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// 调度一个闹钟。[when] 采用本地时区 `DateTime`。
  ///
  /// - `requireExactAlarm=true` 时优先使用 [AndroidScheduleMode.exactAllowWhileIdle]，
  ///   需要 Android 12+ 的 `SCHEDULE_EXACT_ALARM` 权限。缺权限时底层插件会
  ///   抛出 `PlatformException(code: 'exact_alarms_not_permitted')`，本方法
  ///   会**尽力而为**降级到 [AndroidScheduleMode.inexactAllowWhileIdle] 重试
  ///   一次（让提醒仍能发出，只是可能偏移几分钟），随后再抛出
  ///   [AlarmPermissionDeniedException]，调用方可据此展示"前往系统设置
  ///   开启精准闹钟"的引导 UI。
  /// - `requireExactAlarm=false` 时直接使用非精准模式，不触发回退逻辑。
  /// - `when` 已过去时直接丢弃，保持幂等。
  @override
  Future<void> scheduleFullScreen({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
    bool requireExactAlarm = true,
    bool fullScreen = true,
  }) async {
    if (!_initialized) await init();
    if (when.isBefore(DateTime.now())) return;

    final androidDetails = AndroidNotificationDetails(
      channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: fullScreen,
      playSound: true,
      enableVibration: true,
      vibrationPattern: _vibrationPattern,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      visibility: NotificationVisibility.public,
      actions: _actionsForPayload(payload),
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.timeSensitive,
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );
    const linuxDetails = LinuxNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
      linux: linuxDetails,
    );
    final tzWhen = tz.TZDateTime.from(when, tz.local);

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tzWhen,
        details,
        androidScheduleMode: requireExactAlarm
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } on PlatformException catch (e) {
      if (!_isExactAlarmDenied(e)) rethrow;
      // 降级重试：精准闹钟权限缺失时，退化为非精准模式，让提醒至少还能响，
      // 只是可能偏移几分钟。降级成功时视为已调度，避免上层误以为队列为空。
      if (requireExactAlarm) {
        try {
          await _plugin.zonedSchedule(
            id,
            title,
            body,
            tzWhen,
            details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: payload,
          );
          return;
        } catch (_) {
          // 回退也失败时静默吞掉，下方一并抛出业务异常让调用方处理。
        }
      }
      throw const AlarmPermissionDeniedException();
    }
  }

  Future<void> showFullScreenTest({
    int id = 919001,
    String title = '强提醒测试',
    String body = '如果你看到弹屏、听到声音并有震动，强提醒通道正常。',
    String payload = 'duoyi://alarm-test',
  }) async {
    if (!_initialized) await init();
    await _plugin.show(
      id,
      title,
      body,
      _notificationDetails(fullScreen: true, payload: payload),
      payload: payload,
    );
  }

  @override
  Future<void> scheduleDailyFullScreen({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
    bool requireExactAlarm = true,
    bool fullScreen = true,
  }) async {
    if (!_initialized) await init();

    final details = _notificationDetails(
      fullScreen: fullScreen,
      payload: payload,
    );
    final normalized = weekdays == null || weekdays.isEmpty
        ? const <int>[]
        : weekdays.where((w) => w >= 1 && w <= 7).toSet().toList();

    final targets = normalized.isEmpty ? <int?>[null] : normalized.cast<int?>();
    for (final weekday in targets) {
      final scheduleId = weekday == null ? id : _subId(id, weekday);
      final when = weekday == null
          ? _nextInstanceOfTime(hour, minute)
          : _nextInstanceOfWeekdayTime(weekday, hour, minute);

      try {
        await _plugin.zonedSchedule(
          scheduleId,
          title,
          body,
          when,
          details,
          androidScheduleMode: requireExactAlarm
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: weekday == null
              ? DateTimeComponents.time
              : DateTimeComponents.dayOfWeekAndTime,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
        );
      } on PlatformException catch (e) {
        if (!_isExactAlarmDenied(e)) rethrow;
        if (requireExactAlarm) {
          try {
            await _plugin.zonedSchedule(
              scheduleId,
              title,
              body,
              when,
              details,
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              matchDateTimeComponents: weekday == null
                  ? DateTimeComponents.time
                  : DateTimeComponents.dayOfWeekAndTime,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
              payload: payload,
            );
            continue;
          } catch (_) {
            // 回退也失败时静默吞掉，下方一并抛出业务异常让调用方处理。
          }
        }
        throw const AlarmPermissionDeniedException();
      }
    }
  }

  /// 判断一个 [PlatformException] 是否由 Android 12+ 精准闹钟权限缺失引起。
  static bool _isExactAlarmDenied(PlatformException e) {
    if (e.code == 'exact_alarms_not_permitted') return true;
    final msg = '${e.message ?? ''} ${e.details ?? ''}';
    return msg.contains('SCHEDULE_EXACT_ALARM') ||
        msg.contains('exact_alarms_not_permitted');
  }

  @override
  Future<void> cancel(int id) async {
    if (!_initialized) return;
    await _plugin.cancel(id);
    for (int w = 1; w <= 7; w++) {
      await _plugin.cancel(_subId(id, w));
    }
  }

  Future<void> cancelAll() async {
    if (!_initialized) return;
    await _plugin.cancelAll();
  }

  /// 查询当前 AlarmService 下发的 pending id 列表（便于测试与诊断）。
  Future<List<int>> pendingIds() async {
    if (!_initialized) return const [];
    final pending = await _plugin.pendingNotificationRequests();
    return pending.map((e) => e.id).toList(growable: false);
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

  /// 请求 Android 12+ 精准闹钟权限。
  ///
  /// - 非 Android 平台直接返回 `true`（视为已授权）。
  /// - Android 低于 12 的系统默认即授权，`permission_handler` 也返回 granted。
  /// - 失败时返回 `false`，调用方可据此弹出引导至系统设置的提示。
  Future<bool> requestExactAlarmPermission() async {
    if (!_isAndroid) return true;
    try {
      if (!_initialized) await init();
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final exactGranted = await android?.requestExactAlarmsPermission();
      return exactGranted ?? true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestFullScreenIntentPermission() async {
    if (!_isAndroid) return true;
    try {
      if (!_initialized) await init();
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.requestFullScreenIntentPermission() ?? true;
    } catch (e, st) {
      debugPrint(
        '[AlarmService] full screen intent permission failed: $e\n$st',
      );
      return hasFullScreenIntentPermission();
    }
  }

  Future<bool> hasFullScreenIntentPermission() async {
    if (!_isAndroid) return true;
    return PlatformInfo.canUseFullScreenIntent();
  }

  /// 查询当前是否已授予精准闹钟权限（不弹系统对话框）。
  ///
  /// - 非 Android 平台直接返回 `true`。
  /// - Android 低于 12 的系统默认即授权。
  /// - 失败时返回 `false`，调用方可据此决定是否弹引导。
  Future<bool> hasExactAlarmPermission() async {
    if (!_isAndroid) return true;
    try {
      if (!_initialized) await init();
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.canScheduleExactNotifications() ?? true;
    } catch (_) {
      return false;
    }
  }

  String? takeLaunchPayload() {
    final payload = _launchPayload;
    _launchPayload = null;
    return payload;
  }

  NotificationDetails _notificationDetails({
    required bool fullScreen,
    String? payload,
  }) {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: fullScreen,
      playSound: true,
      enableVibration: true,
      vibrationPattern: _vibrationPattern,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      visibility: NotificationVisibility.public,
      actions: _actionsForPayload(payload),
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.timeSensitive,
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );
    const linuxDetails = LinuxNotificationDetails();
    return NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
      linux: linuxDetails,
    );
  }

  int _subId(int base, int weekday) => base * 10 + weekday;

  List<AndroidNotificationAction>? _actionsForPayload(String? payload) {
    if (payload == null || !payload.startsWith('duoyi://habit/')) return null;
    return _habitActions;
  }

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
}
