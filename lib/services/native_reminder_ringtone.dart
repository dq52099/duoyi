import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/local_timezone_resolver.dart';

class NativeReminderRingtone {
  NativeReminderRingtone._();

  static const String statusChannelId = 'duoyi_builtin_ringtone_status_v4';
  static const String fallbackChannelId = 'duoyi_alarm_fallback_v9';
  static const Set<String> legacyChannelIds = <String>{
    'duoyi_builtin_ringtone_status_v1',
    'duoyi_builtin_ringtone_status_v2',
    'duoyi_builtin_ringtone_status_v3',
    'duoyi_alarm_fallback_v1',
    'duoyi_alarm_fallback_v2',
    'duoyi_alarm_fallback_v3',
    'duoyi_alarm_fallback_v4',
    'duoyi_alarm_fallback_v5',
    'duoyi_alarm_fallback_v6',
    'duoyi_alarm_fallback_v7',
    'duoyi_alarm_fallback_v8',
  };
  static const int previewNotificationId = 919002;
  static const Duration previewDuration = Duration(seconds: 3);
  static const MethodChannel _channel = MethodChannel(
    'duoyi/reminder_ringtone',
  );
  static int _previewGeneration = 0;

  static Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
    bool fullScreen = false,
    bool vibrate = true,
    int snoozeMinutes = 0,
    int repeatCount = 0,
  }) async {
    if (!_isAndroid) return;
    await _invoke('showNow', <String, Object?>{
      'id': id,
      'title': title,
      'body': body,
      'payload': payload,
      'fullScreen': fullScreen,
      'vibrate': vibrate,
      'snoozeMinutes': snoozeMinutes,
      'repeatCount': repeatCount,
    });
  }

  static Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
    bool fullScreen = false,
    bool vibrate = true,
    int snoozeMinutes = 0,
    int repeatCount = 0,
  }) async {
    if (!_isAndroid) return;
    await _invoke('scheduleOnce', <String, Object?>{
      'id': id,
      'title': title,
      'body': body,
      'triggerAtMillis': when.millisecondsSinceEpoch,
      'payload': payload,
      'fullScreen': fullScreen,
      'vibrate': vibrate,
      'snoozeMinutes': snoozeMinutes,
      'repeatCount': repeatCount,
    });
    await _verifyPending(id, 'scheduleOnce');
  }

  static Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
    bool fullScreen = false,
    bool vibrate = true,
    int snoozeMinutes = 0,
    int repeatCount = 0,
  }) async {
    if (!_isAndroid) return;
    await _invoke('scheduleDaily', <String, Object?>{
      'id': id,
      'title': title,
      'body': body,
      'hour': hour,
      'minute': minute,
      'weekdays': weekdays ?? const <int>[],
      'timezoneId': LocalTimezoneResolver.currentIana,
      'payload': payload,
      'fullScreen': fullScreen,
      'vibrate': vibrate,
      'snoozeMinutes': snoozeMinutes,
      'repeatCount': repeatCount,
    });
    await _verifyPending(id, 'scheduleDaily');
  }

  static Future<void> cancel(int id) async {
    if (!_isAndroid) return;
    await _tryInvoke('cancel', <String, Object?>{'id': id});
  }

  static Future<void> cancelOrThrow(int id) async {
    if (!_isAndroid) return;
    await _invoke('cancel', <String, Object?>{'id': id});
  }

  static Future<void> cancelAll() async {
    if (!_isAndroid) return;
    await _tryInvoke('cancelAll');
  }

  static Future<void> stopActive() async {
    if (!_isAndroid) return;
    await _tryInvoke('stopActive');
  }

  static Future<List<int>> pendingIds() async {
    if (!_isAndroid) return const <int>[];
    try {
      return await pendingIdsOrThrow();
    } catch (e, st) {
      debugPrint('[NativeReminderRingtone] pendingIds failed: $e\n$st');
      return const <int>[];
    }
  }

  static Future<List<int>> pendingIdsOrThrow() async {
    if (!_isAndroid) return const <int>[];
    final raw = await _channel.invokeMethod<List<dynamic>>('pendingIds');
    if (raw == null) return const <int>[];
    return raw
        .map((value) {
          if (value is int) return value;
          return int.tryParse(value.toString());
        })
        .whereType<int>()
        .toList(growable: false);
  }

  static Future<NativeReminderDeliveryIssue?> lastDeliveryIssue() async {
    if (!_isAndroid) return null;
    try {
      final raw = await _channel.invokeMethod<Object?>('lastDeliveryIssue');
      if (raw is! Map) return null;
      return NativeReminderDeliveryIssue.fromMap(raw);
    } catch (e, st) {
      debugPrint('[NativeReminderRingtone] lastDeliveryIssue failed: $e\n$st');
      return null;
    }
  }

  static Future<void> clearLastDeliveryIssue() async {
    if (!_isAndroid) return;
    await _tryInvoke('clearLastDeliveryIssue');
  }

  static Future<NativeReminderPlaybackStatus?> lastPlaybackStatus() async {
    if (!_isAndroid) return null;
    try {
      final raw = await _channel.invokeMethod<Object?>('lastPlaybackStatus');
      if (raw is! Map) return null;
      return NativeReminderPlaybackStatus.fromMap(raw);
    } catch (e, st) {
      debugPrint('[NativeReminderRingtone] lastPlaybackStatus failed: $e\n$st');
      return null;
    }
  }

  static Future<void> clearLastPlaybackStatus() async {
    if (!_isAndroid) return;
    await _tryInvoke('clearLastPlaybackStatus');
  }

  static Future<bool> preview({
    String title = '铃声试听',
    String body = '正在播放当前提醒铃声',
    Duration duration = previewDuration,
  }) async {
    if (!_isAndroid) return true;
    final generation = ++_previewGeneration;
    await _tryInvoke('cancel', <String, Object?>{'id': previewNotificationId});
    await clearLastDeliveryIssue();
    await clearLastPlaybackStatus();
    final started = await _tryInvoke('showNow', <String, Object?>{
      'id': previewNotificationId,
      'title': title,
      'body': body,
      'payload': null,
      'fullScreen': false,
      'vibrate': false,
      'snoozeMinutes': 0,
      'repeatCount': 0,
    });
    if (!started) return false;
    final playbackStarted = await _waitForPreviewPlaybackStart();
    if (!playbackStarted) {
      await _tryInvoke('cancel', <String, Object?>{
        'id': previewNotificationId,
      });
      return false;
    }
    if (duration <= Duration.zero) {
      await _tryInvoke('cancel', <String, Object?>{
        'id': previewNotificationId,
      });
      return true;
    }
    unawaited(
      Future<void>.delayed(duration).then((_) async {
        if (generation == _previewGeneration) {
          await _tryInvoke('cancel', <String, Object?>{
            'id': previewNotificationId,
          });
        }
      }),
    );
    return true;
  }

  static Future<NativeReminderPreviewResult> previewCurrentSound({
    Duration duration = previewDuration,
  }) async {
    if (!_isAndroid) return const NativeReminderPreviewResult.started();
    try {
      final raw = await _channel.invokeMethod<Object?>(
        'previewCurrentSound',
        <String, Object?>{'durationMillis': duration.inMilliseconds},
      );
      if (raw is Map) return NativeReminderPreviewResult.fromMap(raw);
      return const NativeReminderPreviewResult.started();
    } catch (e, st) {
      debugPrint(
        '[NativeReminderRingtone] previewCurrentSound failed: $e\n$st',
      );
      return NativeReminderPreviewResult.failed(
        reason: 'platform_channel_failed',
        message: '铃声试听启动失败，请重试。',
      );
    }
  }

  static Future<void> stopPreview() async {
    if (!_isAndroid) return;
    await _tryInvoke('stopPreview');
  }

  static Future<bool> _waitForPreviewPlaybackStart({
    Duration timeout = const Duration(milliseconds: 1600),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final issue = await lastDeliveryIssue();
      if (issue?.id == previewNotificationId) return false;
      final status = await lastPlaybackStatus();
      if (status?.id == previewNotificationId && status?.status == 'started') {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  static Future<void> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final ok = await _tryInvoke(method, arguments);
    if (!ok) throw NativeReminderRingtoneException(method);
  }

  static Future<void> _verifyPending(int id, String method) async {
    try {
      final pending = await pendingIdsOrThrow();
      if (pending.contains(id)) return;
      debugPrint(
        '[NativeReminderRingtone] $method pending verification missing id: $id; '
        'keeping schedule because AlarmManager/launcher pending queries can lag '
        'after platform registration succeeds.',
      );
    } catch (e, st) {
      debugPrint(
        '[NativeReminderRingtone] $method pending verification skipped: $e\n$st',
      );
    }
  }

  static Future<bool> _tryInvoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      final result = await _channel.invokeMethod<Object?>(method, arguments);
      if (result is bool) return result;
      return true;
    } catch (e, st) {
      debugPrint('[NativeReminderRingtone] $method failed: $e\n$st');
      return false;
    }
  }

  static bool get _isAndroid {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }
}

class NativeReminderRingtoneException implements Exception {
  final String method;

  const NativeReminderRingtoneException(this.method);

  @override
  String toString() => 'NativeReminderRingtoneException: $method failed';
}

class NativeReminderPreviewResult {
  final bool started;
  final String reason;
  final String message;

  const NativeReminderPreviewResult({
    required this.started,
    required this.reason,
    required this.message,
  });

  const NativeReminderPreviewResult.started()
    : started = true,
      reason = 'started',
      message = '正在试听当前提醒铃声。';

  const NativeReminderPreviewResult.failed({
    required this.reason,
    required this.message,
  }) : started = false;

  factory NativeReminderPreviewResult.fromMap(Map<dynamic, dynamic> raw) {
    final started = raw['started'] == true;
    return NativeReminderPreviewResult(
      started: started,
      reason: raw['reason']?.toString() ?? (started ? 'started' : 'unknown'),
      message:
          raw['message']?.toString() ?? (started ? '正在试听当前提醒铃声。' : '铃声试听启动失败。'),
    );
  }
}

class NativeReminderDeliveryIssue {
  final int id;
  final String reason;
  final String message;
  final DateTime timestamp;

  const NativeReminderDeliveryIssue({
    required this.id,
    required this.reason,
    required this.message,
    required this.timestamp,
  });

  factory NativeReminderDeliveryIssue.fromMap(Map<dynamic, dynamic> raw) {
    final timestampMillis = _asInt(raw['timestamp']);
    return NativeReminderDeliveryIssue(
      id: _asInt(raw['id']),
      reason: raw['reason']?.toString() ?? '',
      message: raw['message']?.toString() ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMillis),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class NativeReminderPlaybackStatus {
  final int id;
  final String status;
  final String source;
  final DateTime timestamp;

  const NativeReminderPlaybackStatus({
    required this.id,
    required this.status,
    required this.source,
    required this.timestamp,
  });

  factory NativeReminderPlaybackStatus.fromMap(Map<dynamic, dynamic> raw) {
    final timestampMillis = _asInt(raw['timestamp']);
    return NativeReminderPlaybackStatus(
      id: _asInt(raw['id']),
      status: raw['status']?.toString() ?? '',
      source: raw['source']?.toString() ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMillis),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
