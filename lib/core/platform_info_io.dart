import 'dart:io' as io;

/// 原生(Android/iOS/Linux/Win/Mac)下的真实 Platform 判断。
class PlatformInfo {
  static bool get isAndroid => io.Platform.isAndroid;
  static bool get isIOS => io.Platform.isIOS;
  static bool get isLinux => io.Platform.isLinux;
  static bool get isMacOS => io.Platform.isMacOS;
  static bool get isWindows => io.Platform.isWindows;
  static bool get isFuchsia => io.Platform.isFuchsia;
}
