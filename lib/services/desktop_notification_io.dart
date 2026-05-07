import 'dart:io' show Platform;
import 'package:dbus/dbus.dart';

/// Linux desktop notifications via DBus org.freedesktop.Notifications.
/// 其他 native 平台下为空实现(Android 用系统通知通道，见 NotificationService)。
class DesktopNotification {
  DBusClient? _client;
  bool _available = false;

  Future<void> init() async {
    if (!Platform.isLinux) return;
    try {
      _client = DBusClient.session();
      final obj = DBusRemoteObject(
        _client!,
        name: 'org.freedesktop.Notifications',
        path: DBusObjectPath('/org/freedesktop/Notifications'),
      );
      await obj.callMethod(
        'org.freedesktop.Notifications',
        'GetCapabilities',
        [],
        replySignature: DBusSignature('as'),
      );
      _available = true;
    } catch (_) {
      _available = false;
    }
  }

  bool get isAvailable => _available;

  Future<void> notify({
    required String summary,
    required String body,
    String icon = 'dialog-information',
  }) async {
    if (!_available || _client == null) return;
    try {
      final obj = DBusRemoteObject(
        _client!,
        name: 'org.freedesktop.Notifications',
        path: DBusObjectPath('/org/freedesktop/Notifications'),
      );
      await obj.callMethod(
        'org.freedesktop.Notifications',
        'Notify',
        [
          const DBusString('duoyi'),
          const DBusUint32(0),
          DBusString(icon),
          DBusString(summary),
          DBusString(body),
          DBusArray(DBusSignature('s'), const []),
          DBusDict(DBusSignature('s'), DBusSignature('v'), const {}),
          const DBusInt32(5000),
        ],
        replySignature: DBusSignature('u'),
      );
    } catch (_) {}
  }

  void dispose() {
    _client?.close();
    _client = null;
    _available = false;
  }
}
