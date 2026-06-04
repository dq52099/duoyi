typedef NotificationStatusBarSync =
    Future<bool> Function({bool force, bool requestIfNeeded});

class NotificationStatusBarSyncBridge {
  NotificationStatusBarSyncBridge._();

  static NotificationStatusBarSync? _sync;

  static void attach(NotificationStatusBarSync? sync) {
    _sync = sync;
  }

  static Future<bool> sync({
    bool force = false,
    bool requestIfNeeded = false,
  }) async {
    final current = _sync;
    if (current == null) return false;
    return current(force: force, requestIfNeeded: requestIfNeeded);
  }
}
