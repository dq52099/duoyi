import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/location_reminder.dart';

class LocationGeofenceService {
  LocationGeofenceService._();

  static const MethodChannel _channel = MethodChannel(
    'duoyi/location_geofence',
  );

  static Future<LocationGeofenceSyncResult> syncReminders(
    List<LocationReminder> reminders,
  ) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'syncReminders',
        <String, Object?>{'reminders': reminders.map(_encodeReminder).toList()},
      );
      return LocationGeofenceSyncResult.fromMap(raw);
    } on PlatformException catch (e, st) {
      debugPrint('[LocationGeofenceService] sync failed: $e\n$st');
      return LocationGeofenceSyncResult(
        available: false,
        scheduledCount: 0,
        status: e.code,
        message: e.message,
      );
    }
  }

  static Future<LocationGeofenceSyncResult> clearReminders() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'clearReminders',
      );
      return LocationGeofenceSyncResult.fromMap(raw);
    } on PlatformException catch (e, st) {
      debugPrint('[LocationGeofenceService] clear failed: $e\n$st');
      return LocationGeofenceSyncResult(
        available: false,
        scheduledCount: 0,
        status: e.code,
        message: e.message,
      );
    }
  }

  static Future<LocationGeofencePermissionResult> requestPermissions() async {
    var foreground = await Permission.locationWhenInUse.status;
    if (!foreground.isGranted) {
      foreground = await Permission.locationWhenInUse.request();
    }

    var background = await Permission.locationAlways.status;
    if (foreground.isGranted && !background.isGranted) {
      background = await Permission.locationAlways.request();
    }

    return LocationGeofencePermissionResult(
      foregroundGranted: foreground.isGranted,
      backgroundGranted: background.isGranted,
      foregroundPermanentlyDenied: foreground.isPermanentlyDenied,
      backgroundPermanentlyDenied: background.isPermanentlyDenied,
      shouldOpenSettings:
          foreground.isPermanentlyDenied ||
          background.isPermanentlyDenied ||
          (foreground.isGranted && !background.isGranted),
    );
  }

  static Future<LocationGeofencePermissionResult> permissionStatus() async {
    final foreground = await Permission.locationWhenInUse.status;
    final background = await Permission.locationAlways.status;
    return LocationGeofencePermissionResult(
      foregroundGranted: foreground.isGranted,
      backgroundGranted: background.isGranted,
      foregroundPermanentlyDenied: foreground.isPermanentlyDenied,
      backgroundPermanentlyDenied: background.isPermanentlyDenied,
      shouldOpenSettings:
          foreground.isPermanentlyDenied ||
          background.isPermanentlyDenied ||
          (foreground.isGranted && !background.isGranted),
    );
  }

  static Future<LocationGeofenceSyncResult> requestPermissionsAndSync(
    List<LocationReminder> reminders,
  ) async {
    final permission = await requestPermissions();
    if (permission.canScheduleGeofence) {
      return syncReminders(reminders);
    }
    return LocationGeofenceSyncResult(
      available: false,
      scheduledCount: 0,
      status: 'permission_missing',
      message: permission.message,
    );
  }

  static Future<bool> openLocationSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openLocationSettings') ?? false;
    } on PlatformException catch (e, st) {
      debugPrint('[LocationGeofenceService] open settings failed: $e\n$st');
      return false;
    }
  }

  static Map<String, Object?> _encodeReminder(LocationReminder reminder) => {
    'id': reminder.id,
    'title': reminder.title,
    'note': reminder.note,
    'latitude': reminder.latitude,
    'longitude': reminder.longitude,
    'radiusMeters': reminder.radiusMeters,
    'trigger': reminder.trigger.name,
    'oneShot': reminder.oneShot,
    'linkedType': reminder.linkedType,
    'linkedId': reminder.linkedId,
  };
}

@immutable
class LocationGeofencePermissionResult {
  final bool foregroundGranted;
  final bool backgroundGranted;
  final bool foregroundPermanentlyDenied;
  final bool backgroundPermanentlyDenied;
  final bool shouldOpenSettings;

  const LocationGeofencePermissionResult({
    required this.foregroundGranted,
    required this.backgroundGranted,
    required this.foregroundPermanentlyDenied,
    required this.backgroundPermanentlyDenied,
    required this.shouldOpenSettings,
  });

  bool get canScheduleGeofence => foregroundGranted && backgroundGranted;

  String get message {
    if (canScheduleGeofence) return '位置权限已授权';
    if (!foregroundGranted) return '需要先授予使用期间位置权限';
    return '需要在系统设置中允许始终访问位置，后台地理围栏才能触发';
  }
}

@immutable
class LocationGeofenceSyncResult {
  final bool available;
  final int scheduledCount;
  final String status;
  final String? message;

  const LocationGeofenceSyncResult({
    required this.available,
    required this.scheduledCount,
    required this.status,
    this.message,
  });

  factory LocationGeofenceSyncResult.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const LocationGeofenceSyncResult(
        available: false,
        scheduledCount: 0,
        status: 'unavailable',
      );
    }
    return LocationGeofenceSyncResult(
      available: map['available'] == true,
      scheduledCount: (map['scheduledCount'] as num?)?.toInt() ?? 0,
      status: map['status']?.toString() ?? 'unknown',
      message: map['message']?.toString(),
    );
  }
}
