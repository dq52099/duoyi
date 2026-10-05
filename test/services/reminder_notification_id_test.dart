import 'package:test/test.dart';

import 'package:duoyi/services/reminder_notification_id.dart';

void main() {
  test('platform notification IDs normalize to signed 32-bit values', () {
    expect(normalizePlatformNotificationId(0x7fffffff), 0x7fffffff);
    expect(normalizePlatformNotificationId(0x80000000), -0x80000000);
    expect(normalizePlatformNotificationId(2939613521), -1355353775);
    expect(isValidPlatformNotificationId(-0x80000000), isTrue);
    expect(isValidPlatformNotificationId(0x7fffffff), isTrue);
    expect(isValidPlatformNotificationId(0x80000000), isFalse);
  });

  test('legacy weekday IDs match Android signed Int overflow semantics', () {
    for (var weekday = 1; weekday <= 7; weekday++) {
      final id = legacyWeekdayNotificationId(293961352, weekday);
      expect(isValidPlatformNotificationId(id), isTrue);
      expect(id, 293961352 * 10 + weekday - 0x100000000);
    }
    expect(legacyWeekdayNotificationId(100, 1), 1001);
    expect(legacyWeekdayNotificationId(293961352, 1), -1355353775);
    expect(normalizePlatformNotificationId(2939613521), -1355353775);
    expect(
      isValidPlatformNotificationId(minimumPlatformNotificationId),
      isTrue,
    );
  });
}
