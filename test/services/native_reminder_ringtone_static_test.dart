import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Android 内置铃声链路具备服务、资源和停止动作', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneService.kt',
    ).readAsStringSync();
    final receiver = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneReceiver.kt',
    ).readAsStringSync();
    final bootReceiver = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneBootReceiver.kt',
    ).readAsStringSync();
    final scheduler = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneScheduler.kt',
    ).readAsStringSync();
    final alarmService = File(
      'lib/services/alarm_service.dart',
    ).readAsStringSync();

    expect(manifest, contains('android:name=".ReminderRingtoneService"'));
    expect(manifest, contains('android:name=".ReminderRingtoneReceiver"'));
    expect(manifest, contains('android:name=".ReminderRingtoneBootReceiver"'));
    expect(manifest, contains('android.permission.FOREGROUND_SERVICE'));
    expect(manifest, contains('android.permission.VIBRATE'));
    expect(receiver, contains('context.startForegroundService(serviceIntent)'));
    expect(bootReceiver, contains('ReminderRingtoneScheduler.restoreAll'));
    expect(scheduler, contains('startRingtoneService(context, intent)'));
    expect(scheduler, contains('context.startForegroundService(intent)'));
    expect(scheduler, contains('rememberSchedule'));
    expect(scheduler, contains('encodeEntry'));
    expect(scheduler, contains('fun restoreAll'));
    expect(bootReceiver, contains('Intent.ACTION_BOOT_COMPLETED'));
    expect(service, contains('AudioAttributes.USAGE_ALARM'));
    expect(service, contains('setSound(null, null)'));
    expect(service, contains('NotificationManager.IMPORTANCE_HIGH'));
    expect(service, contains('if (shouldVibrate) vibrate()'));
    expect(service, contains('putExtra("vibrate", vibrate)'));
    expect(receiver, contains('getBooleanExtra("vibrate", true)'));
    expect(scheduler, contains('.put("vibrate"'));
    expect(service, contains('setFullScreenIntent(fullScreenIntent, false)'));
    expect(service, contains('NotificationCompat.VISIBILITY_PUBLIC'));
    expect(service, contains('NotificationCompat.PRIORITY_HIGH'));
    expect(service, contains('setOnlyAlertOnce(true)'));
    expect(service, contains('longArrayOf(0, 220, 420, 220)'));
    expect(service, contains('addAction(0, "停止响铃"'));
    expect(service, contains('.setAction(actionStop)'));
    expect(service, contains('.putExtra("id", id)'));
    expect(service, contains('cancelStatusNotification'));
    expect(service, contains(r'addAction(0, "稍后 $snoozeMinutes 分钟"'));
    expect(service, contains('REMINDER_RING_SNOOZE'));
    expect(service, contains('ReminderRingtoneScheduler.scheduleOnce'));
    expect(service, contains('delayMinutes * 60_000L'));
    expect(service, contains('snoozeMinutes > 0'));
    expect(service, contains('putExtra("vibrate", shouldVibrate)'));
    expect(service, contains('putExtra("delayMinutes", snoozeMinutes)'));
    expect(service, contains('putExtra("repeatRemaining", repeatRemaining)'));
    expect(service, contains('scheduleAutoRepeat'));
    expect(service, contains('repeatRemaining - 1'));
    expect(service, contains('putExtra("repeatRemaining"'));
    expect(receiver, contains('getIntExtra("snoozeMinutes", 0)'));
    expect(receiver, contains('getIntExtra("repeatRemaining", 0)'));
    expect(scheduler, contains('.put("snoozeMinutes"'));
    expect(scheduler, contains('.put("repeatCount"'));
    expect(service, contains('stopSelf()'));
    expect(alarmService, contains('NativeReminderRingtone.showNow'));
    expect(alarmService, contains('NativeReminderRingtone.scheduleOnce'));
    expect(alarmService, contains('NativeReminderRingtone.scheduleDaily'));
    expect(service, contains('setDeleteIntent(stopIntent)'));
    expect(service, contains('setOngoing(false)'));
    expect(service, contains('setAutoCancel(true)'));
    expect(alarmService, contains("channelId = 'duoyi_alarm_fullscreen_v8'"));
    expect(
      alarmService,
      contains("RawResourceAndroidNotificationSound('duoyi_classic')"),
    );
    expect(alarmService, contains("'duoyi_alarm_fullscreen_v7'"));
    expect(alarmService, contains('ongoing: false'));
    expect(alarmService, contains('autoCancel: true'));
    expect(alarmService, contains('onlyAlertOnce: true'));
    expect(alarmService, contains('int snoozeMinutes = 5'));
    expect(alarmService, contains('fullScreen: false'));
    expect(scheduler, contains('ReminderRingtoneService.stopIfActive'));
    expect(scheduler, contains('ReminderRingtoneService.stopActive'));
    expect(service, contains('.getInt(volumeKey, 60)'));
    expect(service, contains('.coerceIn(40, 80)'));

    for (final name in ['alarm', 'chime', 'bell', 'beep', 'classic']) {
      expect(
        File('android/app/src/main/res/raw/duoyi_$name.wav').existsSync(),
        isTrue,
      );
      expect(service, contains('R.raw.duoyi_$name'));
    }
  });

  test('原生每日铃声调度跟随手机时区，不把 UTC 兜底到上海', () {
    final scheduler = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneScheduler.kt',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
    ).readAsStringSync();

    expect(scheduler, contains('TimeZone.getDefault().id'));
    expect(mainActivity, contains('TimeZone.getDefault().id'));
    expect(mainActivity, contains('"getSystemTimeZoneId"'));
    expect(mainActivity, contains('result.success(TimeZone.getDefault().id)'));
    expect(scheduler, contains('normalized == "UTC"'));
    expect(scheduler, isNot(contains('return "Asia/Shanghai"')));
    expect(mainActivity, isNot(contains('?: "Asia/Shanghai"')));
    expect(scheduler, contains('return systemDefault'));
  });

  test('点击内置铃声通知进入应用会停止响铃服务', () {
    final service = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneService.kt',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
    ).readAsStringSync();

    expect(service, contains('setContentIntent(contentIntent)'));
    expect(mainActivity, contains('override fun onCreate'));
    expect(mainActivity, contains('override fun onNewIntent'));
    expect(service, contains('openAppIntent(payload, stopRingtone = true)'));
    expect(
      service,
      isNot(contains('openAppIntent(payload, stopRingtone = false)')),
    );
    expect(service, contains('extraStopRingtone'));
    expect(mainActivity, contains('stopReminderRingtoneIfRequested(intent)'));
    expect(mainActivity, contains('ReminderRingtoneService.extraStopRingtone'));
    expect(mainActivity, contains('opensDuoyiReminderTarget'));
    expect(mainActivity, isNot(contains('override fun onResume')));
    expect(
      mainActivity,
      contains(
        'stopService(Intent(this, ReminderRingtoneService::class.java))',
      ),
    );
  });

  test('Android 内置铃声不被通知权限检查阻断', () {
    final alarmService = File(
      'lib/services/alarm_service.dart',
    ).readAsStringSync();

    final scheduleOnceIndex = alarmService.indexOf(
      'NativeReminderRingtone.scheduleOnce',
    );
    final schedulePermissionIndex = alarmService.indexOf(
      "_ensureNotificationPermission('scheduleFullScreen')",
    );
    expect(scheduleOnceIndex, greaterThanOrEqualTo(0));
    expect(schedulePermissionIndex, greaterThan(scheduleOnceIndex));

    final showNowIndex = alarmService.indexOf('NativeReminderRingtone.showNow');
    final testPermissionIndex = alarmService.indexOf(
      "_ensureNotificationPermission('showFullScreenTest')",
    );
    expect(showNowIndex, greaterThanOrEqualTo(0));
    expect(testPermissionIndex, greaterThan(showNowIndex));

    final scheduleDailyIndex = alarmService.indexOf(
      'NativeReminderRingtone.scheduleDaily',
    );
    final dailyPermissionIndex = alarmService.indexOf(
      "_ensureNotificationPermission('scheduleDailyFullScreen')",
    );
    expect(scheduleDailyIndex, greaterThanOrEqualTo(0));
    expect(dailyPermissionIndex, greaterThan(scheduleDailyIndex));
    expect(alarmService, contains('on NotificationPermissionDeniedException'));
    expect(alarmService, contains('if (_isAndroid) return;'));
  });
}
