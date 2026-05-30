import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Android location reminders sync to native geofences', () {
    final dartService = File(
      'lib/services/location_geofence_service.dart',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
    ).readAsStringSync();
    final scheduler = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/LocationGeofenceScheduler.kt',
    ).readAsStringSync();
    final receiver = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/LocationGeofenceReceiver.kt',
    ).readAsStringSync();
    final integrations = File(
      'lib/screens/integrations_screen.dart',
    ).readAsStringSync();
    final model = File('lib/models/location_reminder.dart').readAsStringSync();

    expect(dartService, contains("'duoyi/location_geofence'"));
    expect(
      dartService,
      contains("import 'package:permission_handler/permission_handler.dart';"),
    );
    expect(dartService, contains('syncReminders'));
    expect(dartService, contains('clearReminders'));
    expect(dartService, contains('requestPermissions'));
    expect(dartService, contains('requestPermissionsAndSync'));
    expect(dartService, contains('Permission.locationWhenInUse.request()'));
    expect(dartService, contains('Permission.locationAlways.request()'));
    expect(dartService, contains('openLocationSettings'));
    expect(dartService, contains("'trigger': reminder.trigger.name"));
    expect(dartService, contains("'oneShot': reminder.oneShot"));
    expect(main, contains("import 'services/location_geofence_service.dart';"));
    expect(main, contains('LocationGeofenceService.syncReminders'));
    expect(main, contains('locationReminderProvider.addListener'));

    expect(manifest, contains('android.permission.ACCESS_FINE_LOCATION'));
    expect(manifest, contains('android.permission.ACCESS_COARSE_LOCATION'));
    expect(manifest, contains('android.permission.ACCESS_BACKGROUND_LOCATION'));
    expect(manifest, contains('android:name=".LocationGeofenceReceiver"'));
    expect(gradle, contains('com.google.android.gms:play-services-location'));

    expect(mainActivity, contains('duoyi/location_geofence'));
    expect(mainActivity, contains('"syncReminders"'));
    expect(mainActivity, contains('LocationGeofenceScheduler.syncReminders'));
    expect(mainActivity, contains('"openLocationSettings"'));

    expect(scheduler, contains('LocationServices.getGeofencingClient'));
    expect(scheduler, contains('Geofence.Builder()'));
    expect(scheduler, contains('GEOFENCE_TRANSITION_ENTER'));
    expect(scheduler, contains('GEOFENCE_TRANSITION_EXIT'));
    expect(scheduler, contains('ACCESS_BACKGROUND_LOCATION'));
    expect(scheduler, contains('permission_missing'));
    expect(scheduler, contains('PendingIntent.FLAG_MUTABLE'));
    expect(scheduler, contains('remember(context, reminders)'));
    expect(scheduler, contains('removeGeofences(pendingIntent(context))'));

    expect(receiver, contains('GeofencingEvent.fromIntent'));
    expect(receiver, contains('duoyi://location/'));
    expect(receiver, contains('duoyi://todo/'));
    expect(receiver, contains('duoyi://goal/'));
    expect(receiver, contains('位置提醒：'));
    expect(receiver, contains('removeOneShot'));
    expect(receiver, contains('POST_NOTIFICATIONS'));

    expect(integrations, contains('Android 已接入系统 geofence 调度'));
    expect(model, contains('Android 通过原生 geofence 调度接入系统后台触发'));
    expect(model, isNot(contains('本期先做模型 + 前台触发能力，后续接入')));
    expect(integrations, contains('授权后台位置'));
    expect(
      integrations,
      contains('LocationGeofenceService.requestPermissions'),
    );
    expect(
      integrations,
      contains('LocationGeofenceService.openLocationSettings'),
    );
  });
}
