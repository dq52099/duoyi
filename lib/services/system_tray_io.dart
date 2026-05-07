import 'dart:async';
import 'dart:io' show Platform;
import 'package:dbus/dbus.dart';

/// 原生平台下的托盘(Linux StatusNotifier 占位)。
class SystemTrayService {
  DBusClient? _bus;
  bool _registered = false;
  final _onActivate = StreamController<String>.broadcast();
  Stream<String> get onActivate => _onActivate.stream;
  bool get isRegistered => _registered;

  Future<void> init() async {
    if (!Platform.isLinux) return;
    try {
      _bus = DBusClient.session();
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

  void simulateActivate(String actionId) => _onActivate.add(actionId);

  void dispose() {
    _onActivate.close();
    _bus?.close();
    _bus = null;
    _registered = false;
  }
}
