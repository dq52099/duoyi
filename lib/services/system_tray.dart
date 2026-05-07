/// 跨端托盘。web 下空实现，io 下可选 linux dbus。
export 'system_tray_stub.dart' if (dart.library.io) 'system_tray_io.dart';
