import 'dart:io' as io;

import 'package:flutter/services.dart';

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

  bool get isXiaomiLike {
    final haystack = [
      manufacturer,
      brand,
      model,
    ].whereType<String>().join(' ').toLowerCase();
    return haystack.contains('xiaomi') ||
        haystack.contains('redmi') ||
        haystack.contains('poco');
  }

  String get displayName {
    final parts = [
      manufacturer,
      brand,
      model,
    ].whereType<String>().where((e) => e.trim().isNotEmpty).toList();
    if (parts.isEmpty) return 'Android';
    return parts.toSet().join(' ');
  }
}

/// 原生(Android/iOS/Linux/Win/Mac)下的真实 Platform 判断。
class PlatformInfo {
  static const MethodChannel _channel = MethodChannel('duoyi/platform_info');

  static bool get isAndroid => io.Platform.isAndroid;
  static bool get isIOS => io.Platform.isIOS;
  static bool get isLinux => io.Platform.isLinux;
  static bool get isMacOS => io.Platform.isMacOS;
  static bool get isWindows => io.Platform.isWindows;
  static bool get isFuchsia => io.Platform.isFuchsia;

  static Future<AndroidDeviceInfoLite?> getAndroidDeviceInfo() async {
    if (!isAndroid) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getAndroidDeviceInfo',
      );
      if (raw == null) return null;
      return AndroidDeviceInfoLite(
        manufacturer: raw['manufacturer']?.toString(),
        brand: raw['brand']?.toString(),
        model: raw['model']?.toString(),
        sdkInt: (raw['sdkInt'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}
