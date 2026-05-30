import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NotificationSettings {
  NotificationSettings._();

  static const MethodChannel _channel = MethodChannel(
    'duoyi/notification_settings',
  );

  static Future<bool> openAppNotificationSettings() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openAppNotificationSettings') ??
          false;
    } catch (e, st) {
      debugPrint('[NotificationSettings] open app settings failed: $e\n$st');
      return false;
    }
  }

  static Future<bool> openNotificationChannelSettings(String channelId) async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'openNotificationChannelSettings',
            <String, Object?>{'channelId': channelId},
          ) ??
          false;
    } catch (e, st) {
      debugPrint(
        '[NotificationSettings] open channel settings failed: $e\n$st',
      );
      return openAppNotificationSettings();
    }
  }

  static Future<Map<String, NotificationChannelStatus>?>
  notificationChannelStatuses(Iterable<String> channelIds) async {
    if (!_isAndroid) return const <String, NotificationChannelStatus>{};
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'notificationChannelStatuses',
        <String, Object?>{'channelIds': channelIds.toList(growable: false)},
      );
      if (raw == null) return null;
      return raw.map((id, value) {
        final data = value is Map
            ? value.cast<String, Object?>()
            : const <String, Object?>{};
        return MapEntry(id, NotificationChannelStatus.fromMap(data));
      });
    } catch (e, st) {
      debugPrint(
        '[NotificationSettings] read channel statuses failed: $e\n$st',
      );
      return null;
    }
  }

  static Future<SystemNotificationAudioStatus?> systemAudioStatus() async {
    if (!_isAndroid) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'systemAudioStatus',
      );
      if (raw == null) return null;
      return SystemNotificationAudioStatus.fromMap(raw);
    } catch (e, st) {
      debugPrint('[NotificationSettings] read audio status failed: $e\n$st');
      return null;
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

class NotificationChannelStatus {
  final int? importance;
  final bool? hasSound;
  final bool? canBypassDnd;
  final bool exists;

  const NotificationChannelStatus({
    required this.exists,
    this.importance,
    this.hasSound,
    this.canBypassDnd,
  });

  factory NotificationChannelStatus.fromMap(Map<String, Object?> map) {
    return NotificationChannelStatus(
      exists: map['exists'] == true,
      importance: map['importance'] is int ? map['importance'] as int : null,
      hasSound: map['hasSound'] is bool ? map['hasSound'] as bool : null,
      canBypassDnd: map['canBypassDnd'] is bool
          ? map['canBypassDnd'] as bool
          : null,
    );
  }

  bool get isBlocked => exists && importance == 0;

  bool get isLowImportance =>
      exists && importance != null && importance! > 0 && importance! <= 2;

  bool get isSilent => exists && hasSound == false;
}

class SystemNotificationAudioStatus {
  final int alarmVolume;
  final int alarmMaxVolume;
  final int notificationVolume;
  final int notificationMaxVolume;
  final int ringVolume;
  final int ringMaxVolume;
  final bool dndSupported;
  final int? interruptionFilter;
  final bool notificationPolicyAccessGranted;

  const SystemNotificationAudioStatus({
    required this.alarmVolume,
    required this.alarmMaxVolume,
    required this.notificationVolume,
    required this.notificationMaxVolume,
    required this.ringVolume,
    required this.ringMaxVolume,
    required this.dndSupported,
    required this.interruptionFilter,
    required this.notificationPolicyAccessGranted,
  });

  factory SystemNotificationAudioStatus.fromMap(Map<String, Object?> map) {
    return SystemNotificationAudioStatus(
      alarmVolume: _asInt(map['alarmVolume']),
      alarmMaxVolume: _asInt(map['alarmMaxVolume']),
      notificationVolume: _asInt(map['notificationVolume']),
      notificationMaxVolume: _asInt(map['notificationMaxVolume']),
      ringVolume: _asInt(map['ringVolume']),
      ringMaxVolume: _asInt(map['ringMaxVolume']),
      dndSupported: map['dndSupported'] == true,
      interruptionFilter: map['interruptionFilter'] is int
          ? map['interruptionFilter'] as int
          : null,
      notificationPolicyAccessGranted:
          map['notificationPolicyAccessGranted'] == true,
    );
  }

  bool get alarmMuted => alarmMaxVolume > 0 && alarmVolume <= 0;

  bool get notificationMuted =>
      notificationMaxVolume > 0 && notificationVolume <= 0;

  bool get ringMuted => ringMaxVolume > 0 && ringVolume <= 0;

  bool get dndActive =>
      dndSupported && interruptionFilter != null && interruptionFilter != 1;

  int get alarmPercent => _percent(alarmVolume, alarmMaxVolume);

  int get notificationPercent =>
      _percent(notificationVolume, notificationMaxVolume);

  int get ringPercent => _percent(ringVolume, ringMaxVolume);

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _percent(int value, int max) {
    if (max <= 0) return 0;
    return ((value / max) * 100).round().clamp(0, 100);
  }
}
