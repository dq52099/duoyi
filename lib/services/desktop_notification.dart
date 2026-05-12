// 跨端桌面通知。web 下空实现。
export 'desktop_notification_stub.dart'
    if (dart.library.io) 'desktop_notification_io.dart';
