/// Web 无桌面通知占位。
class DesktopNotification {
  bool get isAvailable => false;
  Future<void> init() async {}
  Future<void> notify({required String summary, required String body,
      String icon = 'dialog-information'}) async {}
  void dispose() {}
}
