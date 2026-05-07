import 'package:dbus/dbus.dart';

/// Linux desktop notifications via DBus org.freedesktop.Notifications.
class DesktopNotification {
  DBusClient? _client;
  bool _available = false;

  Future<void> init() async {
    try {
      _client = DBusClient.session();
      // Probe the notification service exists
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

  Future<int?> notify({
    required String summary,
    String body = '',
    String appName = '指尖时光',
    String iconName = 'appointment-soon',
    int timeoutMs = 5000,
  }) async {
    if (_client == null || !_available) return null;
    try {
      final obj = DBusRemoteObject(
        _client!,
        name: 'org.freedesktop.Notifications',
        path: DBusObjectPath('/org/freedesktop/Notifications'),
      );
      final result = await obj.callMethod(
        'org.freedesktop.Notifications',
        'Notify',
        [
          DBusString(appName),
          const DBusUint32(0),
          DBusString(iconName),
          DBusString(summary),
          DBusString(body),
          DBusArray(DBusSignature('s'), const []),
          DBusDict(DBusSignature('s'), DBusSignature('v'), const {}),
          DBusInt32(timeoutMs),
        ],
        replySignature: DBusSignature('u'),
      );
      final id = result.values.first;
      if (id is DBusUint32) return id.value;
      return null;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _client?.close();
    _client = null;
    _available = false;
  }
}
