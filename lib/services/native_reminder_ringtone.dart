import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/local_timezone_resolver.dart';

class NativeReminderRingtone {
  NativeReminderRingtone._();

  static const MethodChannel _channel = MethodChannel(
    'duoyi/reminder_ringtone',
  );

  static Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
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
      'vibrate': vibrate,
      'snoozeMinutes': snoozeMinutes,
      'repeatCount': repeatCount,
    });
  }

  static Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
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
      'vibrate': vibrate,
      'snoozeMinutes': snoozeMinutes,
      'repeatCount': repeatCount,
    });
  }

  static Future<void> cancel(int id) async {
    if (!_isAndroid) return;
    await _invoke('cancel', <String, Object?>{'id': id});
  }

  static Future<void> cancelAll() async {
    if (!_isAndroid) return;
    await _invoke('cancelAll');
  }

  static Future<void> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } catch (e, st) {
      debugPrint('[NativeReminderRingtone] $method failed: $e\n$st');
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
