const int minimumPlatformNotificationId = -0x80000000;
const int maximumPlatformNotificationId = 0x7fffffff;

bool isValidPlatformNotificationId(int id) {
  return id >= minimumPlatformNotificationId &&
      id <= maximumPlatformNotificationId;
}

int normalizePlatformNotificationId(int id) {
  if (isValidPlatformNotificationId(id)) return id;
  var normalized = id & 0xffffffff;
  if (normalized > maximumPlatformNotificationId) {
    normalized -= 0x100000000;
  }
  return normalized;
}

int legacyWeekdayNotificationId(int base, int weekday) {
  return normalizePlatformNotificationId(base * 10 + weekday);
}
