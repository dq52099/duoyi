/// Web 环境下的 Platform 占位符。dart:io 在 web 不可用，用常量返回 false。
class PlatformInfo {
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isLinux => false;
  static bool get isMacOS => false;
  static bool get isWindows => false;
  static bool get isFuchsia => false;
}
