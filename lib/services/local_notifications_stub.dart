/// Web 环境占位。所有调用都是空操作。
class LocalNotifications {
  static final LocalNotifications instance = LocalNotifications._();
  LocalNotifications._();

  static const int quickAddNotificationId = 880016;

  final bool _granted = false;
  bool get permissionGranted => _granted;

  Future<void> init() async {}

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
    String title = '多仪快捷记录',
    String body = '下拉通知栏添加待办，或一键开始专注',
  }) async {}

  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
    String? channelId,
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
  }) async {}

  Future<void> cancel(int id) async {}
  Future<void> cancelAll() async {}
  Future<List<int>> pendingIds() async => const [];
  Future<Set<String>?> notificationChannelIds() async => const <String>{};
  String? takeLaunchPayload() => null;

  void Function(String payload)? onTap;
}
