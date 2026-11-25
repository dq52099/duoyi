import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

import '../core/i18n.dart';
import '../core/local_timezone_resolver.dart';
import 'native_reminder_ringtone.dart';
import 'notification_permission_exception.dart';
import 'reminder_ringtone_settings.dart';
import 'reminder_notification_id.dart';
import 'account_local_data_cleaner.dart';
import 'notification_action_envelope.dart';

const String _kNotificationMetaPrefsKey = 'duoyi_notif_meta_v1';
const int _kMaxPersistedNotificationMetaEntries = 400;

@pragma('vm:entry-point')
Future<void> duoyiBackgroundNotificationResponse(
  NotificationResponse response,
) async {
  try {
    final verified = await NotificationActionEnvelope.verifyResponse(response);
    if (verified == null) return;
    await LocalNotifications.instance.handleBackgroundNotificationResponse(
      verified,
    );
  } catch (error, stack) {
    debugPrint('[LocalNotifications] background action failed: $error\n$stack');
  }
}

/// 本地通知 / 每日闹钟(Android + iOS + Linux 实现)。
class LocalNotifications {
  static final LocalNotifications instance = LocalNotifications._();
  LocalNotifications._()
    : _plugin = FlutterLocalNotificationsPlugin(),
      _androidOverride = null;

  @visibleForTesting
  LocalNotifications.forTesting({
    required FlutterLocalNotificationsPlugin plugin,
    required bool isAndroid,
    bool initialized = true,
  }) : _plugin = plugin,
       _androidOverride = isAndroid {
    _initialized = initialized;
  }

  final FlutterLocalNotificationsPlugin _plugin;
  final bool? _androidOverride;
  bool _pluginInitialized = false;
  bool _launchPayloadProbed = false;
  bool _initialized = false;
  Future<void>? _pluginInitFuture;
  Future<void>? _initFuture;
  bool _granted = false;
  String? _launchPayload;
  int? _launchPayloadGeneration;
  String? _lastQuickAddOngoingSignature;
  static const Duration _visibleNotificationDuplicateWindow = Duration(
    seconds: 3,
  );
  final Map<String, DateTime> _recentVisibleNotificationSignatures =
      <String, DateTime>{};
  final Map<String, DateTime> _recentVisibleNotificationContentSignatures =
      <String, DateTime>{};
  final Map<int, DateTime> _recentVisibleNotificationIds = <int, DateTime>{};
  final Map<int, ({String title, String body, String? originalPayload})>
  _notificationContentCache =
      <int, ({String title, String body, String? originalPayload})>{};
  static const List<String> _iosTodoActions = <String>[
    'todo_complete',
    'todo_snooze_10m',
  ];
  static const List<String> _iosHabitActions = <String>[
    'habit_checkin',
    'habit_snooze_10m',
  ];
  static const List<String> _iosAlarmActions = <String>[
    'alarm_snooze_10m',
    'alarm_dismiss',
  ];
  bool get permissionGranted => _granted;
  String _androidSoundResourceName =
      ReminderRingtoneSettings.androidRawResourceNameFor(
        ReminderRingtoneSettings.defaultSound,
      );
  RawResourceAndroidNotificationSound get _alarmSound =>
      RawResourceAndroidNotificationSound(_androidSoundResourceName);
  RawResourceAndroidNotificationSound get _defaultSound =>
      RawResourceAndroidNotificationSound(_androidSoundResourceName);
  static const String _defaultChannelId = 'duoyi_general_alerts_v18';
  static const String _alarmChannelId = 'duoyi_alarm_fullscreen_v18';
  static const String quickAddChannelId = 'duoyi_quick_add_ongoing_v2';
  static const int quickAddNotificationId = 880016;
  static const int diagnosticNotificationId = 919003;
  static const int scheduledDiagnosticNotificationId = 919004;
  static const Set<int> reservedNotificationIds = <int>{
    quickAddNotificationId,
    880017,
    880018,
    880019,
    880020,
    880021,
    880022,
    880023,
    919001,
    NativeReminderRingtone.previewNotificationId,
    diagnosticNotificationId,
    scheduledDiagnosticNotificationId,
  };
  static const Set<String> _quickAddLegacyChannelIds = <String>{
    'duoyi_quick_add_ongoing_v1',
  };
  static const Set<String> _legacyChannelIds = <String>{
    'duoyi_general_alerts_v2',
    'duoyi_general_alerts_v3',
    'duoyi_general_alerts_v4',
    'duoyi_general_alerts_v5',
    'duoyi_general_alerts_v6',
    'duoyi_general_alerts_v7',
    'duoyi_general_alerts_v8',
    'duoyi_general_alerts_v9',
    'duoyi_general_alerts_v10',
    'duoyi_general_alerts_v11',
    'duoyi_general_alerts_v12',
    'duoyi_general_alerts_v13',
    'duoyi_general_alerts_v14',
    'duoyi_general_alerts_v15',
    'duoyi_general_alerts_v16',
    'duoyi_general_alerts_v17',
  };
  static const Set<String> _alarmLegacyChannelIds = <String>{
    'duoyi_alarm',
    'duoyi_alarm_fullscreen_v3',
    'duoyi_alarm_fullscreen_v4',
    'duoyi_alarm_fullscreen_v5',
    'duoyi_alarm_fullscreen_v6',
    'duoyi_alarm_fullscreen_v7',
    'duoyi_alarm_fullscreen_v8',
    'duoyi_alarm_fullscreen_v9',
    'duoyi_alarm_fullscreen_v10',
    'duoyi_alarm_fullscreen_v11',
    'duoyi_alarm_fullscreen_v12',
    'duoyi_alarm_fullscreen_v13',
    'duoyi_alarm_fullscreen_v14',
    'duoyi_alarm_fullscreen_v15',
    'duoyi_alarm_fullscreen_v16',
    'duoyi_alarm_fullscreen_v17',
  };

  Set<int> _queueIdsFor(int id) {
    return <int>{
      id,
      for (var weekday = 1; weekday <= 7; weekday++) _subId(id, weekday),
      for (var weekday = 1; weekday <= 7; weekday++) _legacySubId(id, weekday),
    };
  }

  Future<void> _cancelNativeRingtoneQueue(
    int id, {
    required String operation,
  }) async {
    if (!_isAndroid) return;
    final failures = <Object>[];
    for (final nativeId in _queueIdsFor(id)) {
      try {
        await NativeReminderRingtone.cancelOrThrow(nativeId);
      } catch (e, st) {
        failures.add(e);
        debugPrint(
          '[LocalNotifications] $operation native owner cleanup failed: '
          '$e\n$st',
        );
      }
    }
    if (failures.isEmpty) return;
    debugPrint(
      '[LocalNotifications] $operation continues after native owner cleanup '
      'failure count=${failures.length}; ordinary notification registration '
      'must not be blocked by stale strong-reminder cleanup.',
    );
  }

  /// Tap 回调(payload)——由主入口注册处理 deep link。
  void Function(String payload)? onTap;

  Future<void> init() async {
    if (_initialized) return;
    final inFlight = _initFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final future = _initLocked();
    _initFuture = future;
    try {
      await future;
    } finally {
      _initFuture = null;
    }
  }

  Future<void> _initLocked() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    if (!LocalTimezoneResolver.isInitialized) {
      await LocalTimezoneResolver.init();
    }
    await _ensurePluginInitialized();
    await _probeLaunchPayload();

    // 建立默认渠道
    if (_isAndroid) {
      try {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await _ensureAndroidFallbackChannelSound(
          _defaultChannelId,
          I18n.tr('notification.channel.general.name'),
          I18n.tr('notification.channel.general.description'),
          Importance.high,
          AudioAttributesUsage.notificationRingtone,
        );
        await _ensureAndroidFallbackChannelSound(
          _alarmChannelId,
          I18n.tr('notification.channel.alarm.name'),
          I18n.tr('notification.channel.alarm.description'),
          Importance.max,
          AudioAttributesUsage.alarm,
        );
        await android?.createNotificationChannel(
          AndroidNotificationChannel(
            quickAddChannelId,
            I18n.tr('notification.channel.quick_add.name'),
            description: I18n.tr('notification.channel.quick_add.description'),
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
            showBadge: false,
          ),
        );
        for (final channelId in _quickAddLegacyChannelIds) {
          await android?.deleteNotificationChannel(channelId);
        }
        for (final channelId in _legacyChannelIds) {
          await android?.deleteNotificationChannel(channelId);
        }
        for (final channelId in _alarmLegacyChannelIds) {
          await android?.deleteNotificationChannel(channelId);
        }
        for (final channelId in NativeReminderRingtone.legacyChannelIds) {
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

  Future<void> initForLaunchPayload() async {
    if (_initialized || (_pluginInitialized && _launchPayloadProbed)) return;
    await _ensurePluginInitialized();
    await _probeLaunchPayload();
  }

  Future<void> _ensurePluginInitialized() async {
    if (_pluginInitialized) return;
    final inFlight = _pluginInitFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final future = _initializePlugin();
    _pluginInitFuture = future;
    try {
      await future;
    } finally {
      _pluginInitFuture = null;
    }
  }

  Future<void> _initializePlugin() async {
    if (_pluginInitialized) return;

    const androidInit = AndroidInitializationSettings(
      '@drawable/ic_stat_duoyi',
    );
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
        dispatchNotificationResponse(resp);
      },
      onDidReceiveBackgroundNotificationResponse:
          duoyiBackgroundNotificationResponse,
    );
    _pluginInitialized = true;
  }

  /// Stores title/body/payload metadata keyed by notification ID so snooze and
  /// headless background action handlers retain the original alert copy.
  Future<void> recordScheduledMetadata({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    _notificationContentCache[id] = (
      title: title,
      body: body,
      originalPayload: payload,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      final owner = prefs.getString(AccountLocalDataCleaner.accountDataOwnerKey);
      final raw = prefs.getString(_kNotificationMetaPrefsKey);
      Map<String, dynamic> entries = <String, dynamic>{};
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic> && decoded['owner'] == owner) {
          final map = decoded['items'];
          if (map is Map) {
            entries = Map<String, dynamic>.from(map);
          }
        }
      }
      entries[id.toString()] = <String, dynamic>{
        't': title,
        'b': body,
        'p': ?payload,
        'ts': DateTime.now().millisecondsSinceEpoch,
      };
      if (entries.length > _kMaxPersistedNotificationMetaEntries) {
        final sortedKeys = entries.keys.toList()
          ..sort((a, b) {
            final ta = (entries[a] as Map?)?['ts'] as int? ?? 0;
            final tb = (entries[b] as Map?)?['ts'] as int? ?? 0;
            return ta.compareTo(tb);
          });
        final overflow = entries.length - _kMaxPersistedNotificationMetaEntries;
        for (var i = 0; i < overflow; i++) {
          entries.remove(sortedKeys[i]);
        }
      }
      await prefs.setString(
        _kNotificationMetaPrefsKey,
        jsonEncode(<String, dynamic>{'owner': owner, 'items': entries}),
      );
    } catch (_) {
      // Metadata persistence failure must never block reminder delivery.
    }
  }

  Future<({String title, String body, String? originalPayload})?>
  metadataForNotification(int id) async {
    final mem = _notificationContentCache[id];
    if (mem != null) return mem;
    try {
      final prefs = await SharedPreferences.getInstance();
      final owner = prefs.getString(AccountLocalDataCleaner.accountDataOwnerKey);
      final raw = prefs.getString(_kNotificationMetaPrefsKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['owner'] != owner) {
        return null;
      }
      final items = decoded['items'];
      if (items is! Map) return null;
      final entry = items[id.toString()];
      if (entry is! Map) return null;
      final title = entry['t']?.toString() ?? '';
      final body = entry['b']?.toString() ?? '';
      final payload = entry['p']?.toString();
      if (title.isEmpty && body.isEmpty) return null;
      final value = (title: title, body: body, originalPayload: payload);
      _notificationContentCache[id] = value;
      return value;
    } catch (_) {
      return null;
    }
  }

  Future<void> handleBackgroundNotificationResponse(
    NotificationResponse rawResp,
  ) async {
    final resp = await NotificationActionEnvelope.verifyResponse(rawResp);
    if (resp == null) return;
    final actionId = resp.actionId;
    if (actionId == null || actionId.isEmpty) return;

    if (actionId == 'alarm_dismiss') {
      if (_isAndroid) {
        unawaited(NativeReminderRingtone.stopActive());
      }
      if (resp.id != null) {
        try {
          await _plugin.cancel(resp.id!);
        } catch (_) {}
      }
      return;
    }

    if (actionId == 'todo_complete' ||
        actionId == 'action_complete' ||
        actionId.startsWith('todo_complete_')) {
      final id = actionId.startsWith('todo_complete_')
          ? Uri.decodeComponent(actionId.substring('todo_complete_'.length))
          : (resp.payload == null ? null : _idFromPayload(resp.payload!, 'todo'));
      if (id != null && id.isNotEmpty) {
        await _completeTodoInBackgroundStorage(id);
      }
      if (resp.id != null) {
        try {
          await _plugin.cancel(resp.id!);
        } catch (_) {}
      }
      return;
    }

    if (actionId == 'habit_checkin' ||
        actionId == 'action_habit_checkin' ||
        actionId.startsWith('habit_checkin_')) {
      final id = actionId.startsWith('habit_checkin_')
          ? Uri.decodeComponent(actionId.substring('habit_checkin_'.length))
          : (resp.payload == null
                ? null
                : _idFromPayload(resp.payload!, 'habit'));
      if (id != null && id.isNotEmpty) {
        await _checkInHabitInBackgroundStorage(id);
      }
      if (resp.id != null) {
        try {
          await _plugin.cancel(resp.id!);
        } catch (_) {}
      }
      return;
    }

    final snooze = _parseSnoozeAction(actionId, resp.payload);
    if (snooze != null) {
      final notifId = resp.id ?? 0;
      if (_isAndroid) {
        unawaited(NativeReminderRingtone.stopActive());
      }
      final meta = await metadataForNotification(notifId);
      final title = (meta?.title.trim().isNotEmpty == true)
          ? meta!.title
          : I18n.tr('action.snooze');
      final body = meta?.body ?? '';
      final originalPayload = meta?.originalPayload ?? snooze.originalPayload;
      try {
        tzdata.initializeTimeZones();
        if (!LocalTimezoneResolver.isInitialized) {
          await LocalTimezoneResolver.init();
        }
        final when = DateTime.now().add(Duration(minutes: snooze.delayMinutes));
        final scheduledAt = tz.TZDateTime.from(when, tz.local);
        final generation = AccountLocalDataCleaner.accountDataGeneration;
        await _plugin.cancel(notifId);
        if (_isAndroid) {
          await NativeReminderRingtone.cancel(notifId);
        }
        await _plugin.zonedSchedule(
          notifId,
          title,
          body,
          scheduledAt,
          _details(
            channelId: _defaultChannelId,
            groupKey: _androidGroupKeyFor(originalPayload),
            iosCategoryIdentifier: _iosCategoryIdentifierFor(originalPayload),
            androidActions: _todoActionsFor(originalPayload),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: await NotificationActionEnvelope.signPayload(
            notifId,
            originalPayload,
            actions: _actionsToSignFor(originalPayload),
            expectedAccountGeneration: generation,
          ),
        );
      } catch (e, st) {
        debugPrint('[LocalNotifications] background snooze failed: $e\n$st');
      }
    }
  }

  Future<void> _completeTodoInBackgroundStorage(String todoId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('todos');
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final nowIso = DateTime.now().toIso8601String();
      var changed = false;
      final updated = <dynamic>[];
      for (final item in decoded) {
        if (item is Map && item['id']?.toString() == todoId) {
          final next = Map<String, dynamic>.from(item);
          if (next['isCompleted'] != true) {
            next['isCompleted'] = true;
            next['completedAt'] ??= nowIso;
            next['updatedAt'] = nowIso;
            changed = true;
          }
          updated.add(next);
        } else {
          updated.add(item);
        }
      }
      if (changed) {
        await prefs.setString('todos', jsonEncode(updated));
      }
    } catch (_) {}
  }

  Future<void> _checkInHabitInBackgroundStorage(String habitId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('habits');
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final now = DateTime.now();
      final todayKey =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final nowIso = now.toIso8601String();
      var changed = false;
      final updated = <dynamic>[];
      for (final item in decoded) {
        if (item is Map && item['id']?.toString() == habitId) {
          final next = Map<String, dynamic>.from(item);
          final completions = next['completions'] is Map
              ? Map<String, dynamic>.from(next['completions'] as Map)
              : <String, dynamic>{};
          final currentCount = (completions[todayKey] as num?)?.toInt() ?? 0;
          final targetCount = (next['targetCount'] as num?)?.toInt() ?? 1;
          if (currentCount < targetCount) {
            completions[todayKey] = currentCount + 1;
            next['completions'] = completions;
            final updatedAtMap = next['completionUpdatedAt'] is Map
                ? Map<String, dynamic>.from(next['completionUpdatedAt'] as Map)
                : <String, dynamic>{};
            updatedAtMap[todayKey] = nowIso;
            next['completionUpdatedAt'] = updatedAtMap;
            next['updatedAt'] = nowIso;
            changed = true;
          }
          updated.add(next);
        } else {
          updated.add(item);
        }
      }
      if (changed) {
        await prefs.setString('habits', jsonEncode(updated));
      }
    } catch (_) {}
  }

  ({int delayMinutes, String originalPayload})? _parseSnoozeAction(
    String actionId,
    String? respPayload,
  ) {
    if (actionId == 'todo_snooze_10m' ||
        actionId == 'habit_snooze_10m' ||
        actionId == 'alarm_snooze_10m') {
      return (delayMinutes: 10, originalPayload: respPayload ?? '');
    }
    if (actionId == 'action_snooze') {
      return (delayMinutes: 5, originalPayload: respPayload ?? '');
    }
    if (actionId.startsWith('todo_snooze_')) {
      final rest = actionId.substring('todo_snooze_'.length);
      for (final minutes in const [10, 15, 60]) {
        final exact = '${minutes}m';
        final prefix = '${minutes}m_';
        if (rest == exact) {
          return (delayMinutes: minutes, originalPayload: respPayload ?? '');
        }
        if (rest.startsWith(prefix)) {
          final id = rest.substring(prefix.length);
          final originalPayload =
              respPayload ?? 'duoyi://todo/${Uri.decodeComponent(id)}';
          return (delayMinutes: minutes, originalPayload: originalPayload);
        }
      }
      final originalPayload =
          respPayload ?? 'duoyi://todo/${Uri.decodeComponent(rest)}';
      return (delayMinutes: 5, originalPayload: originalPayload);
    }
    if (actionId.startsWith('habit_snooze_')) {
      final rest = actionId.substring('habit_snooze_'.length);
      for (final minutes in const [10, 15, 60]) {
        final exact = '${minutes}m';
        final prefix = '${minutes}m_';
        if (rest == exact) {
          return (delayMinutes: minutes, originalPayload: respPayload ?? '');
        }
        if (rest.startsWith(prefix)) {
          final id = rest.substring(prefix.length);
          final originalPayload =
              respPayload ?? 'duoyi://habit/${Uri.decodeComponent(id)}';
          return (delayMinutes: minutes, originalPayload: originalPayload);
        }
      }
      final originalPayload =
          respPayload ?? 'duoyi://habit/${Uri.decodeComponent(rest)}';
      return (delayMinutes: 10, originalPayload: originalPayload);
    }
    return null;
  }

  /// Routes every plugin callback through the ordinary notification owner.
  ///
  /// `FlutterLocalNotificationsPlugin` is a process-wide singleton even when
  /// callers construct it through separate factory expressions. AlarmService
  /// therefore delegates to this method instead of replacing the callback.
  void dispatchNotificationResponse(
    NotificationResponse response, {
    void Function(String payload)? fallback,
  }) {
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    unawaited(() async {
      try {
        final payload = await payloadForNotificationResponse(response);
        if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          generation,
        )) {
          return;
        }
        if (payload == null || payload.isEmpty) return;
        final handler = onTap;
        if (handler != null) {
          handler(payload);
        } else {
          fallback?.call(payload);
        }
      } catch (error, stack) {
        debugPrint('[LocalNotifications] response rejected: $error\n$stack');
      }
    }());
  }

  /// Shared by local/alarm live callbacks and both cold-start probes.
  Future<String?> payloadForNotificationResponse(
    NotificationResponse response,
  ) async {
    final verified = await NotificationActionEnvelope.verifyResponse(response);
    return verified == null ? null : _payloadForResponse(verified);
  }

  Future<void> _probeLaunchPayload() async {
    if (_launchPayloadProbed) return;
    _launchPayloadProbed = true;
    final generation = AccountLocalDataCleaner.accountDataGeneration;

    try {
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      final response = launchDetails?.notificationResponse;
      final launchPayload = response == null
          ? null
          : await payloadForNotificationResponse(response);
      if (AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation) &&
          launchDetails?.didNotificationLaunchApp == true &&
          launchPayload != null &&
          launchPayload.isNotEmpty) {
        _launchPayload = launchPayload;
        _launchPayloadGeneration = generation;
      }
    } catch (e, st) {
      debugPrint('[LocalNotifications] launch payload probe failed: $e\n$st');
    }
  }

  String _buildSnoozeDeepLink({
    required int? notificationId,
    required int delayMinutes,
    required String originalPayload,
  }) {
    final query = delayMinutes == 5
        ? '?delay=5&payload=${Uri.encodeComponent(originalPayload)}'
        : '?delay=$delayMinutes&payload=${Uri.encodeComponent(originalPayload)}';
    final base = 'duoyi://snooze/${notificationId ?? 0}$query';
    final cached = notificationId == null
        ? null
        : _notificationContentCache[notificationId];
    if (cached == null || cached.title.trim().isEmpty) {
      return base;
    }
    return '$base&title=${Uri.encodeComponent(cached.title)}'
        '&body=${Uri.encodeComponent(cached.body)}';
  }

  String? _payloadForResponse(NotificationResponse resp) {
    final actionId = resp.actionId;
    // 把通知 action 映射成与应用内 deep link 相同的入口；冷启动和前台点击共用。
    if (actionId != null && actionId.isNotEmpty) {
      if (actionId == 'quick_todo' || actionId == 'quick_todo_open') {
        final text = resp.input?.trim();
        if (text != null && text.isNotEmpty) {
          return 'duoyi://action/quick_todo'
              '?text=${Uri.encodeComponent(text)}';
        }
        return 'duoyi://action/quick_todo';
      }
      if (actionId == 'quick_focus') {
        return 'duoyi://action/start_pomodoro';
      }
      if (actionId == 'alarm_dismiss') {
        if (_isAndroid) {
          unawaited(NativeReminderRingtone.stopActive());
        }
        return null;
      }
      if ((actionId == 'todo_complete' || actionId == 'action_complete') &&
          resp.payload != null) {
        final id = _idFromPayload(resp.payload!, 'todo');
        if (id != null && id.isNotEmpty) {
          return 'duoyi://action/complete_todo?id=${Uri.encodeComponent(id)}';
        }
      }
      if ((actionId == 'habit_checkin' || actionId == 'action_habit_checkin') &&
          resp.payload != null) {
        final id = _idFromPayload(resp.payload!, 'habit');
        if (id != null && id.isNotEmpty) {
          return 'duoyi://action/checkin_habit?id=${Uri.encodeComponent(id)}';
        }
      }
      if (actionId.startsWith('todo_complete_')) {
        final id = actionId.substring('todo_complete_'.length);
        return 'duoyi://action/complete_todo?id=${Uri.encodeComponent(id)}';
      }
      if (actionId.startsWith('habit_checkin_')) {
        final id = actionId.substring('habit_checkin_'.length);
        return 'duoyi://action/checkin_habit?id=${Uri.encodeComponent(id)}';
      }
      if (actionId.startsWith('todo_snooze_')) {
        final rest = actionId.substring('todo_snooze_'.length);
        for (final minutes in const [10, 15, 60]) {
          if (rest == '${minutes}m') {
            final parsed = _parseSnoozeAction(actionId, resp.payload);
            if (parsed != null) {
              return _buildSnoozeDeepLink(
                notificationId: resp.id,
                delayMinutes: parsed.delayMinutes,
                originalPayload: parsed.originalPayload,
              );
            }
          }
          final prefix = '${minutes}m_';
          if (rest.startsWith(prefix)) {
            final id = rest.substring(prefix.length);
            final originalPayload =
                resp.payload ?? 'duoyi://todo/${Uri.decodeComponent(id)}';
            return _buildSnoozeDeepLink(
              notificationId: resp.id,
              delayMinutes: minutes,
              originalPayload: originalPayload,
            );
          }
        }
        final originalPayload =
            resp.payload ?? 'duoyi://todo/${Uri.decodeComponent(rest)}';
        final base =
            'duoyi://snooze/${resp.id ?? 0}'
            '?delay=5&payload=${Uri.encodeComponent(originalPayload)}';
        final cached = resp.id == null
            ? null
            : _notificationContentCache[resp.id!];
        if (cached != null && cached.title.trim().isNotEmpty) {
          return '$base&title=${Uri.encodeComponent(cached.title)}'
              '&body=${Uri.encodeComponent(cached.body)}';
        }
        return base;
      }
      if (actionId.startsWith('habit_snooze_') ||
          actionId == 'todo_snooze_10m' ||
          actionId == 'habit_snooze_10m' ||
          actionId == 'alarm_snooze_10m' ||
          actionId == 'action_snooze') {
        final parsed = _parseSnoozeAction(actionId, resp.payload);
        if (parsed != null) {
          return _buildSnoozeDeepLink(
            notificationId: resp.id,
            delayMinutes: parsed.delayMinutes,
            originalPayload: parsed.originalPayload,
          );
        }
      }
    }
    return resp.payload;
  }

  String? _idFromPayload(String payload, String host) {
    final uri = Uri.tryParse(payload);
    if (uri == null || uri.host != host || uri.pathSegments.isEmpty) {
      return null;
    }
    return uri.pathSegments.first;
  }

  bool get _isAndroid {
    if (kIsWeb) return false;
    final override = _androidOverride;
    if (override != null) return override;
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
      final pluginGranted = await _requestAndroidNotificationPermission();
      final handlerGranted = await _permissionHandlerNotificationGranted(
        request: true,
      );
      final appEnabled = await _androidNotificationsEnabled();
      _granted = _combineKnownPermissionSignals(
        pluginGranted,
        handlerGranted,
        appEnabled,
      );
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
    if (_isAndroid) {
      final handlerGranted = await _permissionHandlerNotificationGranted();
      final appEnabled = await _androidNotificationsEnabled();
      _granted = _combineKnownPermissionSignals(handlerGranted, appEnabled);
      return;
    }
    if (_isIOS) {
      _granted = await _permissionHandlerNotificationGranted() ?? false;
      return;
    }
    _granted = true;
  }

  Future<bool?> _requestAndroidNotificationPermission() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.requestNotificationsPermission();
    } catch (e, st) {
      debugPrint(
        '[LocalNotifications] Android notification permission request failed: '
        '$e\n$st',
      );
      return null;
    }
  }

  Future<bool?> _androidNotificationsEnabled() async {
    if (!_isAndroid) return null;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.areNotificationsEnabled();
    } catch (e, st) {
      debugPrint(
        '[LocalNotifications] Android notification enabled probe failed: '
        '$e\n$st',
      );
      return null;
    }
  }

  Future<bool?> _permissionHandlerNotificationGranted({
    bool request = false,
  }) async {
    try {
      final status = request
          ? await Permission.notification.request()
          : await Permission.notification.status;
      return status.isGranted;
    } catch (e, st) {
      debugPrint(
        '[LocalNotifications] permission_handler notification probe failed: '
        '$e\n$st',
      );
      return null;
    }
  }

  bool _combineKnownPermissionSignals(
    bool? first, [
    bool? second,
    bool? third,
  ]) {
    final signals = <bool>[?first, ?second, ?third];
    if (signals.isEmpty) return false;
    return signals.every((granted) => granted);
  }

  /// 重新探测当前通知权限状态，不弹系统对话框。
  Future<bool> refreshPermission() async {
    try {
      if (!_initialized) await init();
      await _probePermission();
    } catch (e, st) {
      debugPrint('[LocalNotifications] refreshPermission failed: $e\n$st');
      _granted = false;
    }
    return _granted;
  }

  Future<bool> ensurePermission() async {
    try {
      if (!_initialized) await init();
      await _probePermission();
    } catch (e, st) {
      debugPrint('[LocalNotifications] ensurePermission probe failed: $e\n$st');
      _granted = false;
    }
    if (_granted) return true;
    return requestPermission();
  }

  Future<void> _ensureDeliveryPermission(
    String operation, {
    bool requestIfNeeded = true,
  }) async {
    final granted = requestIfNeeded
        ? await ensurePermission()
        : await refreshPermission();
    if (granted) return;
    debugPrint(
      '[LocalNotifications] $operation skipped: notification permission denied',
    );
    throw const NotificationPermissionDeniedException();
  }

  String? _androidGroupKeyFor(String? payload, {String? channelId}) {
    final uri = payload == null ? null : Uri.tryParse(payload);
    return switch (uri?.host) {
      'todo' => 'com.duoyi.duoyi.GROUP_TODO',
      'habit' => 'com.duoyi.duoyi.GROUP_HABIT',
      'focus' || 'pomodoro' => 'com.duoyi.duoyi.GROUP_FOCUS',
      'report' => 'com.duoyi.duoyi.GROUP_DIGEST',
      'tab' when uri?.pathSegments.firstOrNull == 'today' =>
        'com.duoyi.duoyi.GROUP_DIGEST',
      'calendar' ||
      'course' ||
      'goal' ||
      'anniversary' ||
      'countdown' ||
      'event' => 'com.duoyi.duoyi.GROUP_SCHEDULE',
      _ =>
        channelId == _alarmChannelId
            ? 'com.duoyi.duoyi.GROUP_SCHEDULE'
            : null,
    };
  }

  String? _iosCategoryIdentifierFor(String? payload, {bool isAlarm = false}) {
    if (isAlarm) return 'DUOYI_ALARM_REMINDER';
    final uri = payload == null ? null : Uri.tryParse(payload);
    return switch (uri?.host) {
      'todo' => 'DUOYI_TODO_REMINDER',
      'habit' => 'DUOYI_HABIT_REMINDER',
      _ => null,
    };
  }

  List<String> _actionsToSignFor(String? payload, {String? channelId}) {
    final ids = <String>{
      ...?_todoActionsFor(payload)?.map((action) => action.id),
    };
    if (payload != null) {
      if (payload.startsWith('duoyi://todo/')) {
        final rawId = payload.substring('duoyi://todo/'.length).split('?').first;
        final id = Uri.encodeComponent(rawId);
        ids.addAll(_iosTodoActions);
        ids.add('action_complete');
        ids.add('action_snooze');
        if (id.isNotEmpty) {
          ids.addAll(<String>[
            'todo_complete_$id',
            'todo_snooze_$id',
            'todo_snooze_10m_$id',
            'todo_snooze_15m_$id',
            'todo_snooze_60m_$id',
          ]);
        }
      } else if (payload.startsWith('duoyi://habit/')) {
        final rawId = payload
            .substring('duoyi://habit/'.length)
            .split('?')
            .first;
        final id = Uri.encodeComponent(rawId);
        ids.addAll(_iosHabitActions);
        ids.add('action_habit_checkin');
        ids.add('action_snooze');
        if (id.isNotEmpty) {
          ids.addAll(<String>[
            'habit_checkin_$id',
            'habit_snooze_10m_$id',
            'habit_snooze_15m_$id',
            'habit_snooze_60m_$id',
          ]);
        }
      }
    }
    if (channelId == _alarmChannelId) {
      ids.addAll(_iosAlarmActions);
    }
    return ids.toList(growable: false);
  }

  NotificationDetails _details({
    String channelId = _defaultChannelId,
    List<AndroidNotificationAction>? androidActions,
    String? groupKey,
    String? iosCategoryIdentifier,
    bool silent = false,
  }) {
    final isAlarm = channelId == _alarmChannelId;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        isAlarm
            ? I18n.tr('notification.channel.alarm.name')
            : I18n.tr('notification.channel.general.name'),
        channelDescription: isAlarm
            ? I18n.tr('notification.channel.alarm.description')
            : I18n.tr('notification.channel.general.description'),
        importance: isAlarm
            ? Importance.max
            : (silent ? Importance.low : Importance.high),
        priority: isAlarm
            ? Priority.max
            : (silent ? Priority.low : Priority.high),
        category: isAlarm
            ? AndroidNotificationCategory.alarm
            : AndroidNotificationCategory.reminder,
        playSound: !silent,
        sound: silent ? null : (isAlarm ? _alarmSound : _defaultSound),
        enableVibration: !silent,
        silent: silent,
        audioAttributesUsage: isAlarm
            ? AudioAttributesUsage.alarm
            : AudioAttributesUsage.notificationRingtone,
        visibility: NotificationVisibility.public,
        icon: '@drawable/ic_stat_duoyi',
        ticker: I18n.tr('notification.ticker.reminder'),
        groupKey: groupKey,
        autoCancel: true,
        ongoing: false,
        actions: androidActions,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: !silent,
        presentBadge: true,
        categoryIdentifier: iosCategoryIdentifier,
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: !silent,
        presentBadge: true,
        categoryIdentifier: iosCategoryIdentifier,
      ),
      linux: const LinuxNotificationDetails(),
    );
  }

  NotificationDetails _quickAddDetails({
    required String title,
    required String body,
    required bool enableQuickActions,
  }) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        quickAddChannelId,
        I18n.tr('notification.channel.quick_add.name'),
        channelDescription: I18n.tr(
          'notification.channel.quick_add.description',
        ),
        importance: Importance.low,
        priority: Priority.low,
        category: AndroidNotificationCategory.status,
        playSound: false,
        enableVibration: false,
        silent: true,
        visibility: NotificationVisibility.public,
        icon: '@drawable/ic_stat_duoyi',
        ticker: I18n.tr('notification.ticker.quick_add'),
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        showWhen: false,
        channelShowBadge: false,
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          htmlFormatBigText: false,
          htmlFormatContentTitle: false,
        ),
        actions: enableQuickActions
            ? <AndroidNotificationAction>[
                AndroidNotificationAction(
                  'quick_todo',
                  I18n.tr('notification.quick_add.action.add_todo'),
                  showsUserInterface: true,
                  cancelNotification: false,
                  inputs: <AndroidNotificationActionInput>[
                    AndroidNotificationActionInput(
                      label: I18n.tr('notification.quick_add.input_label'),
                    ),
                  ],
                ),
                AndroidNotificationAction(
                  'quick_todo_open',
                  I18n.tr('notification.quick_add.action.open_input'),
                  showsUserInterface: true,
                  cancelNotification: false,
                ),
                AndroidNotificationAction(
                  'quick_focus',
                  I18n.tr('notification.quick_add.action.start_focus'),
                  showsUserInterface: true,
                  cancelNotification: false,
                ),
              ]
            : null,
      ),
    );
  }

  /// 为待办和习惯推送构建通知 action 按钮（支持后台静默完成/打卡与多档稍后提醒）。
  ///
  /// payload 形如 `duoyi://todo/{id}` 或 `duoyi://habit/{id}`。
  List<AndroidNotificationAction>? _todoActionsFor(String? payload) {
    if (payload == null) return null;
    if (payload.startsWith('duoyi://habit/')) {
      final id = Uri.encodeComponent(
        payload.substring('duoyi://habit/'.length).split('?').first,
      );
      if (id.isEmpty) return null;
      final isEn = I18n.current == AppLocale.en;
      return [
        AndroidNotificationAction(
          'habit_checkin_$id',
          isEn ? 'Check in' : '完成打卡',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'habit_snooze_10m_$id',
          isEn ? 'In 10 min' : '10 分钟后',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'habit_snooze_60m_$id',
          isEn ? 'In 1 hour' : '1 小时后',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ];
    }
    if (!payload.startsWith('duoyi://todo/')) return null;
    final id = Uri.encodeComponent(
      payload.substring('duoyi://todo/'.length).split('?').first,
    );
    if (id.isEmpty) return null;
    final isEn = I18n.current == AppLocale.en;
    return [
      AndroidNotificationAction(
        'todo_complete_$id',
        I18n.tr('action.complete'),
        showsUserInterface: false,
        cancelNotification: true,
      ),
      AndroidNotificationAction(
        'todo_snooze_$id',
        I18n.tr('reminder.snooze_5min'),
        showsUserInterface: false,
        cancelNotification: true,
      ),
      AndroidNotificationAction(
        'todo_snooze_10m_$id',
        isEn ? 'In 10 min' : '10 分钟后',
        showsUserInterface: false,
        cancelNotification: true,
      ),
      AndroidNotificationAction(
        'todo_snooze_60m_$id',
        isEn ? 'In 1 hour' : '1 小时后',
        showsUserInterface: false,
        cancelNotification: true,
      ),
    ];
  }

  String _visibleNotificationSignature({
    required String title,
    required String body,
    String? payload,
    String? channelId,
  }) {
    return '$title\n$body\n${payload ?? ''}\n${channelId ?? _defaultChannelId}';
  }

  String _visibleNotificationContentSignature({
    required String title,
    required String body,
    String? channelId,
  }) {
    return '$title\n$body\n${channelId ?? _defaultChannelId}';
  }

  bool _reserveVisibleNotificationSlot({
    required int id,
    required String title,
    required String body,
    String? payload,
    String? channelId,
  }) {
    final now = DateTime.now();
    _recentVisibleNotificationSignatures.removeWhere(
      (_, at) => now.difference(at) > _visibleNotificationDuplicateWindow,
    );
    _recentVisibleNotificationContentSignatures.removeWhere(
      (_, at) => now.difference(at) > _visibleNotificationDuplicateWindow,
    );
    _recentVisibleNotificationIds.removeWhere(
      (_, at) => now.difference(at) > _visibleNotificationDuplicateWindow,
    );
    final lastShownById = _recentVisibleNotificationIds[id];
    if (lastShownById != null &&
        now.difference(lastShownById) <= _visibleNotificationDuplicateWindow) {
      debugPrint('[LocalNotifications] duplicate visible notification skipped');
      return false;
    }
    final signature = _visibleNotificationSignature(
      title: title,
      body: body,
      payload: payload,
      channelId: channelId,
    );
    final contentSignature = _visibleNotificationContentSignature(
      title: title,
      body: body,
      channelId: channelId,
    );
    final lastShownAt = _recentVisibleNotificationSignatures[signature];
    if (lastShownAt != null &&
        now.difference(lastShownAt) <= _visibleNotificationDuplicateWindow) {
      debugPrint('[LocalNotifications] duplicate visible notification skipped');
      return false;
    }
    final lastShownWithSameContent =
        _recentVisibleNotificationContentSignatures[contentSignature];
    if (lastShownWithSameContent != null &&
        now.difference(lastShownWithSameContent) <=
            _visibleNotificationDuplicateWindow) {
      debugPrint('[LocalNotifications] duplicate visible notification skipped');
      return false;
    }
    _recentVisibleNotificationIds[id] = now;
    _recentVisibleNotificationSignatures[signature] = now;
    _recentVisibleNotificationContentSignatures[contentSignature] = now;
    return true;
  }

  void _releaseVisibleNotificationSlot({
    required int id,
    required String title,
    required String body,
    String? payload,
    String? channelId,
  }) {
    _recentVisibleNotificationIds.remove(id);
    _recentVisibleNotificationSignatures.remove(
      _visibleNotificationSignature(
        title: title,
        body: body,
        payload: payload,
        channelId: channelId,
      ),
    );
    _recentVisibleNotificationContentSignatures.remove(
      _visibleNotificationContentSignature(
        title: title,
        body: body,
        channelId: channelId,
      ),
    );
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
    String? channelId,
    bool silent = false,
  }) async {
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    if (!_initialized) await init();
    await _ensureAndroidFallbackChannelsForOperation('show');
    await _ensureDeliveryPermission('show');
    final effectiveChannelId = channelId ?? _defaultChannelId;
    if (!_reserveVisibleNotificationSlot(
      id: id,
      title: title,
      body: body,
      payload: payload,
      channelId: effectiveChannelId,
    )) {
      return;
    }
    try {
      await _cancelPluginNotificationOnly(id, operation: 'show replace');
      await _cancelNativeRingtoneQueue(id, operation: 'show handoff');
      await _plugin.show(
        id,
        title,
        body,
        _details(
          channelId: effectiveChannelId,
          androidActions: _todoActionsFor(payload),
          groupKey: _androidGroupKeyFor(
            payload,
            channelId: effectiveChannelId,
          ),
          iosCategoryIdentifier: _iosCategoryIdentifierFor(
            payload,
            isAlarm: effectiveChannelId == _alarmChannelId,
          ),
          silent: silent,
        ),
        payload: await NotificationActionEnvelope.signPayload(
          id,
          payload,
          actions: _actionsToSignFor(
            payload,
            channelId: effectiveChannelId,
          ),
          expectedAccountGeneration: generation,
        ),
      );
      await recordScheduledMetadata(
        id: id,
        title: title,
        body: body,
        payload: payload,
      );
    } catch (_) {
      _releaseVisibleNotificationSlot(
        id: id,
        title: title,
        body: body,
        payload: payload,
        channelId: effectiveChannelId,
      );
      rethrow;
    }
  }

  Future<void> _cancelPluginNotificationOnly(
    int id, {
    required String operation,
  }) async {
    var failureCount = 0;
    var skipPluginCleanup = false;
    for (final queueId in _queueIdsFor(id)) {
      if (!skipPluginCleanup) {
        try {
          await _plugin.cancel(queueId);
          continue;
        } catch (e, st) {
          failureCount++;
          debugPrint('[LocalNotifications] $operation cancel failed: $e\n$st');
          if (_isAndroid && _isPendingIntentLimitExceeded(e)) {
            skipPluginCleanup = true;
          } else {
            continue;
          }
        }
      }
      if (_isAndroid) {
        await NativeReminderRingtone.cancel(queueId);
      }
    }
    if (failureCount > 0) {
      debugPrint(
        '[LocalNotifications] $operation continues after plugin cancel '
        'failure count=$failureCount; replacement notification should not be '
        'blocked by stale cleanup.',
      );
    }
  }

  Future<void> showQuickAddOngoing({
    String? title,
    String? body,
    bool enableQuickActions = true,
    bool requestIfNeeded = false,
    bool force = false,
  }) async {
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    if (!_isAndroid) return;
    if (!_initialized) await init();
    await _ensureDeliveryPermission(
      'showQuickAddOngoing',
      requestIfNeeded: requestIfNeeded,
    );
    final effectiveTitle = title ?? I18n.tr('notification.quick_add.title');
    final effectiveBody = body ?? I18n.tr('notification.quick_add.body');
    final signature = '$effectiveTitle\n$effectiveBody\n$enableQuickActions';
    if (!force && _lastQuickAddOngoingSignature == signature) return;
    await _plugin.show(
      quickAddNotificationId,
      effectiveTitle,
      effectiveBody,
      _quickAddDetails(
        title: effectiveTitle,
        body: effectiveBody,
        enableQuickActions: enableQuickActions,
      ),
      payload: await NotificationActionEnvelope.signPayload(
        quickAddNotificationId,
        enableQuickActions ? 'duoyi://action/quick_todo' : 'duoyi://tab/todo',
        expectedAccountGeneration: generation,
        actions: enableQuickActions
            ? const ['quick_todo', 'quick_todo_open', 'quick_focus']
            : const [],
      ),
    );
    _lastQuickAddOngoingSignature = signature;
  }

  Future<void> cancelQuickAddOngoing() async {
    if (!_initialized) await init();
    _lastQuickAddOngoingSignature = null;
    await _plugin.cancel(quickAddNotificationId);
  }

  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
    String? channelId,
    bool requestIfNeeded = false,
    bool silent = false,
  }) async {
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    if (!_initialized) await init();
    if (!when.isAfter(DateTime.now())) {
      throw StateError('提醒时间已过去，未注册到系统通知');
    }
    await _ensureAndroidFallbackChannelsForOperation('scheduleOnce');
    await _ensureDeliveryPermission(
      'scheduleOnce',
      requestIfNeeded: requestIfNeeded,
    );
    await _cancelNativeRingtoneQueue(id, operation: 'scheduleOnce handoff');
    await _cancelPluginNotificationOnly(id, operation: 'scheduleOnce replace');
    final scheduledAt = tz.TZDateTime.from(when, tz.local);
    final effectiveChannelId = channelId ?? _defaultChannelId;
    final details = _details(
      channelId: effectiveChannelId,
      androidActions: _todoActionsFor(payload),
      groupKey: _androidGroupKeyFor(payload, channelId: effectiveChannelId),
      iosCategoryIdentifier: _iosCategoryIdentifierFor(
        payload,
        isAlarm: effectiveChannelId == _alarmChannelId,
      ),
      silent: silent,
    );
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduledAt,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: await NotificationActionEnvelope.signPayload(
          id,
          payload,
          actions: _actionsToSignFor(payload, channelId: effectiveChannelId),
          expectedAccountGeneration: generation,
        ),
      );
    } on PlatformException catch (e) {
      if (!_isExactAlarmDenied(e)) rethrow;
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduledAt,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: await NotificationActionEnvelope.signPayload(
          id,
          payload,
          actions: _actionsToSignFor(payload, channelId: effectiveChannelId),
          expectedAccountGeneration: generation,
        ),
      );
    }
    await recordScheduledMetadata(
      id: id,
      title: title,
      body: body,
      payload: payload,
    );
    await _logPendingVerification(<int>{id}, operation: 'scheduleOnce');
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
    bool requestIfNeeded = false,
    bool silent = false,
  }) async {
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    if (!_initialized) await init();
    await _ensureAndroidFallbackChannelsForOperation('scheduleDaily');
    await _ensureDeliveryPermission(
      'scheduleDaily',
      requestIfNeeded: requestIfNeeded,
    );
    await _cancelNativeRingtoneQueue(id, operation: 'scheduleDaily handoff');
    await _cancelPluginNotificationOnly(id, operation: 'scheduleDaily replace');
    final effectiveChannelId = channelId ?? _defaultChannelId;
    final details = _details(
      channelId: effectiveChannelId,
      androidActions: _todoActionsFor(payload),
      groupKey: _androidGroupKeyFor(payload, channelId: effectiveChannelId),
      iosCategoryIdentifier: _iosCategoryIdentifierFor(
        payload,
        isAlarm: effectiveChannelId == _alarmChannelId,
      ),
      silent: silent,
    );

    final expectedIds = <int>{};
    try {
      if (weekdays == null || weekdays.isEmpty) {
        // 每天
        expectedIds.add(id);
        await _scheduleRepeating(
          generation: generation,
          id: id,
          title: title,
          body: body,
          when: _nextInstanceOfTime(hour, minute),
          details: details,
          components: DateTimeComponents.time,
          payload: payload,
          channelId: effectiveChannelId,
        );
        await recordScheduledMetadata(
          id: id,
          title: title,
          body: body,
          payload: payload,
        );
      } else {
        // 每个 weekday 一条，ID 用稳定小整数，避免 base * 10 在 Android int
        // 通知 id 上溢出导致系统拒绝注册。
        for (final w in weekdays) {
          final subId = _subId(id, w);
          expectedIds.add(subId);
          await _scheduleRepeating(
            generation: generation,
            id: subId,
            title: title,
            body: body,
            when: _nextInstanceOfWeekdayTime(w, hour, minute),
            details: details,
            components: DateTimeComponents.dayOfWeekAndTime,
            payload: payload,
            channelId: effectiveChannelId,
          );
          await recordScheduledMetadata(
            id: subId,
            title: title,
            body: body,
            payload: payload,
          );
        }
      }
      await _logPendingVerification(expectedIds, operation: 'scheduleDaily');
    } catch (_) {
      await _cancelScheduledIds(expectedIds);
      rethrow;
    }
  }

  Future<void> _scheduleRepeating({
    required int generation,
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required NotificationDetails details,
    required DateTimeComponents components,
    String? payload,
    String? channelId,
  }) async {
    final effectiveChannelId = channelId ?? _defaultChannelId;
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: components,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: await NotificationActionEnvelope.signPayload(
          id,
          payload,
          actions: _actionsToSignFor(payload, channelId: effectiveChannelId),
          expectedAccountGeneration: generation,
        ),
      );
    } on PlatformException catch (e) {
      if (!_isExactAlarmDenied(e)) rethrow;
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: components,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: await NotificationActionEnvelope.signPayload(
          id,
          payload,
          actions: _actionsToSignFor(payload, channelId: effectiveChannelId),
          expectedAccountGeneration: generation,
        ),
      );
    }
  }

  Future<void> _logPendingVerification(
    Iterable<int> ids, {
    required String operation,
  }) async {
    final expected = ids.toSet();
    if (expected.isEmpty) return;
    Set<int> missing;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      final actual = pending.map((request) => request.id).toSet();
      missing = expected.difference(actual);
    } catch (e, st) {
      debugPrint(
        '[LocalNotifications] $operation pending verification skipped: $e\n$st',
      );
      return;
    }
    if (missing.isEmpty) return;
    debugPrint(
      '[LocalNotifications] $operation pending verification missing ids: '
      '${missing.join(',')}; keeping schedule because the platform accepted '
      'zonedSchedule and pendingNotificationRequests can be incomplete on '
      'some launchers/plugin versions.',
    );
  }

  Future<void> _cancelScheduledIds(Iterable<int> ids) async {
    var skipPluginCleanup = false;
    for (final id in ids.toSet()) {
      if (!skipPluginCleanup) {
        try {
          await _plugin.cancel(id);
          continue;
        } catch (e, st) {
          debugPrint(
            '[LocalNotifications] partial schedule cleanup failed: $e\n$st',
          );
          if (_isAndroid && _isPendingIntentLimitExceeded(e)) {
            skipPluginCleanup = true;
          } else {
            continue;
          }
        }
      }
      if (_isAndroid) {
        await NativeReminderRingtone.cancel(id);
      }
    }
  }

  static bool _isExactAlarmDenied(PlatformException e) {
    if (e.code == 'exact_alarms_not_permitted') return true;
    final msg = '${e.message ?? ''} ${e.details ?? ''}';
    return msg.contains('SCHEDULE_EXACT_ALARM') ||
        msg.contains('exact_alarms_not_permitted');
  }

  static bool _isPendingIntentLimitExceeded(Object e) {
    final msg = e.toString();
    return msg.contains('Too many PendingIntent created') ||
        msg.contains('10000 PendingIntents');
  }

  int _subId(int base, int weekday) {
    var h = 0x811c9dc5;
    final key = '$base:$weekday';
    for (final unit in key.codeUnits) {
      h ^= unit;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return h == 0 ? weekday : h;
  }

  int _legacySubId(int base, int weekday) =>
      legacyWeekdayNotificationId(base, weekday);

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
    if (!_initialized) await init();
    if (id == quickAddNotificationId) {
      _lastQuickAddOngoingSignature = null;
    }
    Object? firstError;
    StackTrace? firstStack;
    var skipPluginCancel = false;
    for (final queueId in _queueIdsFor(id)) {
      if (!skipPluginCancel) {
        try {
          await _plugin.cancel(queueId);
        } catch (e, st) {
          debugPrint('[LocalNotifications] cancel failed: $e\n$st');
          if (_isAndroid && _isPendingIntentLimitExceeded(e)) {
            skipPluginCancel = true;
          } else {
            firstError ??= e;
            firstStack ??= st;
          }
        }
      }
      if (_isAndroid) {
        await NativeReminderRingtone.cancel(queueId);
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack ?? StackTrace.current);
    }
  }

  Future<void> cancelAll() async {
    Object? firstError;
    StackTrace? firstStack;
    try {
      if (!_initialized) await init();
    } catch (e, st) {
      firstError = e;
      firstStack = st;
      debugPrint(
        '[LocalNotifications] cancelAll initialization failed: $e\n$st',
      );
    }
    _lastQuickAddOngoingSignature = null;
    _recentVisibleNotificationIds.clear();
    _recentVisibleNotificationSignatures.clear();
    _recentVisibleNotificationContentSignatures.clear();
    try {
      await _plugin.cancelAll();
    } catch (e, st) {
      firstError ??= e;
      firstStack ??= st;
      debugPrint('[LocalNotifications] cancelAll plugin failed: $e\n$st');
    }
    if (_isAndroid) {
      try {
        await NativeReminderRingtone.cancelAllOrThrow();
      } catch (e, st) {
        firstError ??= e;
        firstStack ??= st;
        debugPrint('[LocalNotifications] cancelAll native failed: $e\n$st');
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack ?? StackTrace.current);
    }
  }

  Future<List<int>> pendingIds() async {
    try {
      return await pendingIdsOrThrow();
    } catch (e, st) {
      debugPrint('[LocalNotifications] pendingIds failed: $e\n$st');
      return <int>[];
    }
  }

  Future<List<int>> pendingIdsOrThrow() async {
    if (!_initialized) await init();
    final pending = await _plugin.pendingNotificationRequests();
    return pending.map((e) => e.id).toList();
  }

  String? takeLaunchPayload() {
    final payload = _launchPayload;
    final generation = _launchPayloadGeneration;
    _launchPayload = null;
    _launchPayloadGeneration = null;
    return generation != null &&
            AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)
        ? payload
        : null;
  }

  Future<Set<String>?> notificationChannelIds() async {
    if (!_isAndroid) return const <String>{};
    try {
      if (!_initialized) await init();
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

  Future<void> refreshAndroidRingtoneChannels() async {
    if (!_isAndroid) return;
    if (!_initialized) await init();
    await _ensureAndroidFallbackChannels();
  }

  Future<void> _refreshFallbackRingtoneSound() async {
    if (!_isAndroid) return;
    _androidSoundResourceName =
        await ReminderRingtoneSettings.loadAndroidRawResourceName();
  }

  Future<void> _ensureAndroidFallbackChannels() async {
    if (!_isAndroid) return;
    await _ensureAndroidFallbackChannelSound(
      _defaultChannelId,
      I18n.tr('notification.channel.general.name'),
      I18n.tr('notification.channel.general.description'),
      Importance.high,
      AudioAttributesUsage.notificationRingtone,
    );
    await _ensureAndroidFallbackChannelSound(
      _alarmChannelId,
      I18n.tr('notification.channel.alarm.name'),
      I18n.tr('notification.channel.alarm.description'),
      Importance.max,
      AudioAttributesUsage.alarm,
    );
  }

  Future<void> _ensureAndroidFallbackChannelsForOperation(
    String operation,
  ) async {
    if (!_isAndroid) return;
    try {
      await _ensureAndroidFallbackChannels();
    } catch (e, st) {
      debugPrint(
        '[LocalNotifications] $operation channel setup failed; continuing '
        'notification registration: $e\n$st',
      );
    }
  }

  Future<void> _ensureAndroidFallbackChannelSound(
    String channelId,
    String channelName,
    String channelDescription,
    Importance importance,
    AudioAttributesUsage audioUsage,
  ) async {
    if (!_isAndroid) return;
    await _refreshFallbackRingtoneSound();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final shouldRecreateChannel =
        await ReminderRingtoneSettings.androidFallbackChannelSoundNeedsRefresh(
          channelId,
          _androidSoundResourceName,
        );
    if (shouldRecreateChannel) {
      await android?.deleteNotificationChannel(channelId);
    }
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDescription,
        importance: importance,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(_androidSoundResourceName),
        enableVibration: true,
        audioAttributesUsage: audioUsage,
      ),
    );
    await ReminderRingtoneSettings.markAndroidFallbackChannelSoundApplied(
      channelId,
      _androidSoundResourceName,
    );
  }
}
