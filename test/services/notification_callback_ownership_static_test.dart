import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('notification callback ownership is shared by local and alarm paths', () {
    final local = File(
      'lib/services/local_notifications_io.dart',
    ).readAsStringSync();
    final alarm = File('lib/services/alarm_service.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(local, contains('void dispatchNotificationResponse('));
    expect(local, contains("actionId == 'todo_complete'"));
    expect(local, contains("actionId == 'habit_checkin'"));
    expect(
      alarm,
      contains('LocalNotifications.instance.dispatchNotificationResponse('),
    );
    expect(
      main,
      contains(
        'if (localLaunchPayload != null && localLaunchPayload.isNotEmpty)',
      ),
    );
    expect(
      main,
      contains('await ensureReminderProvidersStartup();'),
      reason:
          'native cold-start deep links must wait for reminder provider hydration',
    );
  });
}
