/// 跨端本地通知/闹钟服务。
/// web: 空实现(浏览器的 Notifications API 较鸡肋，本版不做)
/// io(Android/iOS/Linux/macOS/Windows): 使用 flutter_local_notifications
export 'local_notifications_stub.dart'
    if (dart.library.io) 'local_notifications_io.dart';
