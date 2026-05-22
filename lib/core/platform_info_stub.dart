/// Web 环境下的 Platform 占位符。dart:io 在 web 不可用，用常量返回 false。
class AndroidDeviceInfoLite {
  final String? manufacturer;
  final String? brand;
  final String? model;
  final int? sdkInt;

  const AndroidDeviceInfoLite({
    this.manufacturer,
    this.brand,
    this.model,
    this.sdkInt,
  });

  bool get isXiaomiLike => false;
  String get displayName => 'Android';
}

class PlatformInfo {
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isLinux => false;
  static bool get isMacOS => false;
  static bool get isWindows => false;
  static bool get isFuchsia => false;

  static Future<AndroidDeviceInfoLite?> getAndroidDeviceInfo() async => null;
  static Future<bool> canUseFullScreenIntent() async => true;
  static Future<String?> getSystemTimeZoneId() async => null;
}
