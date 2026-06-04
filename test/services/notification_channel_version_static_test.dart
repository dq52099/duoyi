import 'dart:io';

import 'package:test/test.dart';

void main() {
  const notificationChannelId = 'duoyi_general_alerts_v18';
  const alarmChannelId = 'duoyi_alarm_fullscreen_v18';
  const nativeStatusChannelId = 'duoyi_builtin_ringtone_status_v4';
  const nativeFallbackChannelId = 'duoyi_alarm_fallback_v9';

  group('Android 通知 channel 版本护栏', () {
    test('普通提醒、强提醒和内置铃声 channel id 在服务与底层实现中保持一致', () {
      final local = File(
        'lib/services/local_notifications_io.dart',
      ).readAsStringSync();
      final alarm = File('lib/services/alarm_service.dart').readAsStringSync();
      final native = File(
        'lib/services/native_reminder_ringtone.dart',
      ).readAsStringSync();
      final receiver = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneReceiver.kt',
      ).readAsStringSync();
      final nativeService = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneService.kt',
      ).readAsStringSync();

      expect(
        local,
        contains(
          "static const String _defaultChannelId = '$notificationChannelId'",
        ),
      );
      expect(
        local,
        contains("static const String _alarmChannelId = '$alarmChannelId'"),
      );
      expect(
        alarm,
        contains("static const String channelId = '$alarmChannelId'"),
      );
      expect(native, contains("statusChannelId = '$nativeStatusChannelId'"));
      expect(
        native,
        contains("fallbackChannelId = '$nativeFallbackChannelId'"),
      );
      expect(
        receiver,
        contains(
          'private const val fallbackChannelId = "$nativeFallbackChannelId"',
        ),
      );
      expect(
        nativeService,
        contains('private const val channelId = "$nativeStatusChannelId"'),
      );
    });

    test('旧 channel 会被列入清理和通知健康诊断，避免继续命中静音渠道', () {
      final local = File(
        'lib/services/local_notifications_io.dart',
      ).readAsStringSync();
      final alarm = File('lib/services/alarm_service.dart').readAsStringSync();
      final health = File(
        'lib/services/permission_health_service.dart',
      ).readAsStringSync();
      final native = File(
        'lib/services/native_reminder_ringtone.dart',
      ).readAsStringSync();
      final receiver = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneReceiver.kt',
      ).readAsStringSync();

      for (var version = 2; version <= 17; version++) {
        final id = 'duoyi_general_alerts_v$version';
        expect(
          File('lib/providers/notification_service.dart').readAsStringSync(),
          contains("'$id'"),
        );
        expect(local, contains("'$id'"));
      }
      for (final id in const [
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
      ]) {
        expect(alarm, contains("'$id'"));
        expect(local, contains("'$id'"));
      }
      for (final id in const [
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
      ]) {
        expect(native, contains("'$id'"));
      }
      for (final id in const [
        'duoyi_alarm_fallback_v1',
        'duoyi_alarm_fallback_v2',
        'duoyi_alarm_fallback_v3',
        'duoyi_alarm_fallback_v4',
        'duoyi_alarm_fallback_v5',
        'duoyi_alarm_fallback_v6',
        'duoyi_alarm_fallback_v7',
        'duoyi_alarm_fallback_v8',
      ]) {
        expect(receiver, contains('"$id"'));
      }
      expect(
        local,
        contains(
          'for (final channelId in NativeReminderRingtone.legacyChannelIds)',
        ),
      );
      expect(
        alarm,
        contains(
          'for (final legacyId in NativeReminderRingtone.legacyChannelIds)',
        ),
      );

      expect(local, contains('deleteNotificationChannel(channelId)'));
      expect(alarm, contains('deleteNotificationChannel(legacyId)'));
      expect(local, contains('Future<bool> _androidChannelNeedsSoundRepair'));
      expect(alarm, contains('Future<bool> _androidChannelNeedsSoundRepair'));
      expect(local, contains('status.isSilent || status.isLowImportance'));
      expect(alarm, contains('status.isSilent || status.isLowImportance'));
      expect(local, contains('Future<void> refreshAndroidRingtoneChannels()'));
      expect(alarm, contains('Future<void> refreshAndroidRingtoneChannel()'));
      expect(receiver, contains('legacyFallbackChannelIds.forEach'));
      expect(receiver, contains('deleteNotificationChannel(it)'));
      expect(health, contains('NotificationService.channelId'));
      expect(health, contains('AlarmService.channelId'));
      expect(health, contains('NativeReminderRingtone.statusChannelId'));
      expect(health, contains('...NotificationService.legacyChannelIds'));
      expect(health, contains('...AlarmService.legacyChannelIds'));
      expect(health, contains('...NativeReminderRingtone.legacyChannelIds'));
    });

    test('通知设置页打开的是当前 channel，且不暴露旧 channel 入口', () {
      final screen = File(
        'lib/screens/notification_history_screen.dart',
      ).readAsStringSync();

      expect(
        screen,
        matches(
          RegExp(
            r'_openSystemSettings\(\s*NotificationService\.channelId,?\s*\)',
            multiLine: true,
          ),
        ),
      );
      expect(
        screen,
        matches(
          RegExp(
            r'_openSystemSettings\(\s*AlarmService\.channelId,?\s*\)',
            multiLine: true,
          ),
        ),
      );
      expect(screen, contains('NativeReminderRingtone.statusChannelId'));
      expect(screen, contains('NativeReminderRingtone.fallbackChannelId'));
      expect(
        screen,
        contains('channelId != NativeReminderRingtone.statusChannelId'),
      );
      expect(screen, contains('status.isLowImportance'));
      expect(screen, isNot(contains('duoyi_general_alerts_v14')));
      expect(screen, isNot(contains('duoyi_alarm_fullscreen_v14')));
      expect(screen, isNot(contains('duoyi_alarm_fallback_v4')));
    });

    test('Android 系统通知使用单色 small icon，不使用 launcher 彩色图标', () {
      final icon = File(
        'android/app/src/main/res/drawable/ic_stat_duoyi.xml',
      ).readAsStringSync();
      final local = File(
        'lib/services/local_notifications_io.dart',
      ).readAsStringSync();
      final alarm = File('lib/services/alarm_service.dart').readAsStringSync();
      final nativeService = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneService.kt',
      ).readAsStringSync();
      final receiver = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneReceiver.kt',
      ).readAsStringSync();
      final geofenceReceiver = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/LocationGeofenceReceiver.kt',
      ).readAsStringSync();
      final focusService = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/services/FocusSoundForegroundService.kt',
      ).readAsStringSync();

      expect(icon, contains('android:fillColor="#FFFFFFFF"'));
      expect(local, contains('AndroidInitializationSettings('));
      expect(alarm, contains('AndroidInitializationSettings('));
      expect(local, contains("'@drawable/ic_stat_duoyi'"));
      expect(alarm, contains("'@drawable/ic_stat_duoyi'"));
      expect(local, isNot(contains('@mipmap/ic_launcher')));
      expect(alarm, isNot(contains('@mipmap/ic_launcher')));
      for (final source in [
        nativeService,
        receiver,
        geofenceReceiver,
        focusService,
      ]) {
        expect(source, contains('R.drawable.ic_stat_duoyi'));
        expect(source, isNot(contains('R.mipmap.ic_launcher')));
      }
    });

    test('铃声设置变化会立即刷新普通提醒和强提醒渠道', () {
      final main = File('lib/main.dart').readAsStringSync();
      final local = File(
        'lib/services/local_notifications_io.dart',
      ).readAsStringSync();
      final localStub = File(
        'lib/services/local_notifications_stub.dart',
      ).readAsStringSync();
      final alarm = File('lib/services/alarm_service.dart').readAsStringSync();

      expect(main, contains('Future<void> _refreshReminderRingtoneChannels()'));
      expect(main, contains('ReminderRingtoneSettings.onChanged = (keys)'));
      expect(
        main,
        contains('keys.contains(ReminderRingtoneSettings.soundPreferenceKey)'),
      );
      expect(
        main,
        contains('keys.contains(ReminderRingtoneSettings.volumePreferenceKey)'),
      );
      expect(
        main,
        contains(
          'LocalNotifications.instance.refreshAndroidRingtoneChannels()',
        ),
      );
      expect(
        main,
        contains('AlarmService.instance.refreshAndroidRingtoneChannel()'),
      );
      expect(
        main,
        contains('ReminderRingtoneSettings.applyPersistedSettingsToNative()'),
      );
      expect(main, contains('await _refreshReminderRingtoneChannels();'));
      expect(main, contains('await queueFullReminderResync('));
      expect(main, contains("reason: 'ringtone settings changed'"));
      expect(local, contains('Future<void> refreshAndroidRingtoneChannels()'));
      expect(local, contains('await _ensureAndroidFallbackChannels();'));
      expect(
        localStub,
        contains('Future<void> refreshAndroidRingtoneChannels() async {}'),
      );
      expect(alarm, contains('Future<void> refreshAndroidRingtoneChannel()'));
      expect(alarm, contains('await _ensureAndroidFallbackChannelSound();'));
    });
  });
}
