/// Web 环境占位。所有调用都是空操作。
class LocalNotifications {
  static final LocalNotifications instance = LocalNotifications._();
  LocalNotifications._();

  static const int quickAddNotificationId = 880016;
  static const int diagnosticNotificationId = 919003;
  static const int scheduledDiagnosticNotificationId = 919004;
  static const String quickAddChannelId = 'duoyi_quick_add_ongoing_v2';
  static const Set<int> reservedNotificationIds = <int>{
    quickAddNotificationId,
    880017,
    880018,
    880019,
    880020,
    880021,
    880022,
    880023,
    919001,
    919002,
    diagnosticNotificationId,
    scheduledDiagnosticNotificationId,
  };

  final bool _granted = false;
  bool get permissionGranted => _granted;

  Future<void> init() async {}
  Future<void> initForLaunchPayload() async {}

  Future<bool> requestPermission() async => false;
  Future<bool> refreshPermission() async => _granted;
  Future<bool> ensurePermission() async => _granted;

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
    String? channelId,
  }) async {}

  Future<void> showQuickAddOngoing({
    String? title,
    String? body,
    bool enableQuickActions = true,
    bool requestIfNeeded = false,
    bool force = false,
  }) async {}
  Future<void> cancelQuickAddOngoing() async {}

  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
    String? channelId,
    bool requestIfNeeded = false,
  }) async {}

  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? payload,
    String? channelId,
    List<int>? weekdays,
    bool requestIfNeeded = false,
  }) async {}

  Future<void> cancel(int id) async {}
  Future<void> cancelAll() async {}
  Future<List<int>> pendingIds() async => const [];
  Future<Set<String>?> notificationChannelIds() async => const <String>{};
  Future<void> refreshAndroidRingtoneChannels() async {}
  String? takeLaunchPayload() => null;

  void Function(String payload)? onTap;
}
