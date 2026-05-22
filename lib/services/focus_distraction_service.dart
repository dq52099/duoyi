import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FocusDistractionStatus {
  final bool supported;
  final bool accessGranted;
  final bool accessibilityGranted;
  final bool blockerConfigured;
  final String? foregroundPackage;

  const FocusDistractionStatus({
    required this.supported,
    required this.accessGranted,
    this.accessibilityGranted = false,
    this.blockerConfigured = false,
    this.foregroundPackage,
  });

  const FocusDistractionStatus.unavailable()
    : supported = false,
      accessGranted = false,
      accessibilityGranted = false,
      blockerConfigured = false,
      foregroundPackage = null;

  factory FocusDistractionStatus.fromMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) return const FocusDistractionStatus.unavailable();
    return FocusDistractionStatus(
      supported: raw['supported'] == true,
      accessGranted: raw['accessGranted'] == true,
      accessibilityGranted: raw['accessibilityGranted'] == true,
      blockerConfigured: raw['blockerConfigured'] == true,
      foregroundPackage: raw['foregroundPackage']?.toString(),
    );
  }
}

class FocusDistractionService {
  FocusDistractionService._();

  static final FocusDistractionService instance = FocusDistractionService._();
  static const MethodChannel _channel = MethodChannel(
    'duoyi/focus_distraction',
  );

  Future<FocusDistractionStatus> getStatus() async {
    if (!_isAndroid) return const FocusDistractionStatus.unavailable();
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('getStatus');
      return FocusDistractionStatus.fromMap(raw);
    } catch (e, st) {
      debugPrint('[FocusDistractionService] getStatus failed: $e\n$st');
      return const FocusDistractionStatus.unavailable();
    }
  }

  Future<String?> getForegroundApp() async {
    if (!_isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('getForegroundApp');
    } catch (e, st) {
      debugPrint('[FocusDistractionService] foreground app failed: $e\n$st');
      return null;
    }
  }

  Future<bool> openUsageAccessSettings() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openUsageAccessSettings') ??
          false;
    } catch (e, st) {
      debugPrint('[FocusDistractionService] open settings failed: $e\n$st');
      return false;
    }
  }

  Future<bool> openAccessibilitySettings() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openAccessibilitySettings') ??
          false;
    } catch (e, st) {
      debugPrint(
        '[FocusDistractionService] open accessibility failed: $e\n$st',
      );
      return false;
    }
  }

  Future<bool> setFocusBlocker({
    required bool enabled,
    required List<String> packages,
  }) async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('setFocusBlocker', {
            'enabled': enabled,
            'packages': packages,
          }) ??
          false;
    } catch (e, st) {
      debugPrint('[FocusDistractionService] set blocker failed: $e\n$st');
      return false;
    }
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
