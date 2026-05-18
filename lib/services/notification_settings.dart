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

  static bool get _isAndroid {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }
}
