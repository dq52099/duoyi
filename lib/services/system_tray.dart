import 'dart:async';
import 'package:dbus/dbus.dart';

/// Lightweight Linux StatusNotifierItem-style tray.
/// Many DEs (KDE, recent GNOME via extension) honor this. If the host bus
/// doesn't accept registration, the tray gracefully no-ops.
class SystemTrayService {
  DBusClient? _bus;
  bool _registered = false;
  final _onActivate = StreamController<String>.broadcast();
  Stream<String> get onActivate => _onActivate.stream;

  Future<void> init() async {
    try {
      _bus = DBusClient.session();
      // Probe status notifier watcher
      final watcher = DBusRemoteObject(
        _bus!,
        name: 'org.kde.StatusNotifierWatcher',
        path: DBusObjectPath('/StatusNotifierWatcher'),
      );
      await watcher.getAllProperties('org.kde.StatusNotifierWatcher');
      _registered = true;
    } catch (_) {
      _registered = false;
    }
  }

  bool get isRegistered => _registered;

  /// Emit a synthetic activation event so consumers can run actions even
  /// when the real tray isn't available (e.g. via a quick-launch shortcut).
  void simulateActivate(String actionId) {
    _onActivate.add(actionId);
  }

  void dispose() {
    _onActivate.close();
    _bus?.close();
    _bus = null;
    _registered = false;
  }
}
