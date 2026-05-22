import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FocusDndStatus {
  final bool supported;
  final bool accessGranted;
  final int? currentFilter;

  const FocusDndStatus({
    required this.supported,
    required this.accessGranted,
    this.currentFilter,
  });

  factory FocusDndStatus.fromMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) return const FocusDndStatus.unavailable();
    return FocusDndStatus(
      supported: raw['supported'] == true,
      accessGranted: raw['accessGranted'] == true,
      currentFilter: (raw['currentFilter'] as num?)?.toInt(),
    );
  }

  const FocusDndStatus.unavailable()
    : supported = false,
      accessGranted = false,
      currentFilter = null;
}

class FocusDndEnableResult {
  final bool enabled;
  final int? previousFilter;
  final int? currentFilter;

  const FocusDndEnableResult({
    required this.enabled,
    this.previousFilter,
    this.currentFilter,
  });

  factory FocusDndEnableResult.fromMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) return const FocusDndEnableResult(enabled: false);
    return FocusDndEnableResult(
      enabled: raw['enabled'] == true,
      previousFilter: (raw['previousFilter'] as num?)?.toInt(),
      currentFilter: (raw['currentFilter'] as num?)?.toInt(),
    );
  }
}

class FocusDndService {
  FocusDndService._();

  static final FocusDndService instance = FocusDndService._();
  static const MethodChannel _channel = MethodChannel('duoyi/focus_dnd');

  static const int interruptionFilterAll = 1;
  static const int interruptionFilterPriority = 2;
  static const int interruptionFilterNone = 3;
  static const int interruptionFilterAlarms = 4;

  Future<FocusDndStatus> getStatus() async {
    if (!_isAndroid) return const FocusDndStatus.unavailable();
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('getStatus');
      return FocusDndStatus.fromMap(raw);
    } catch (e, st) {
      debugPrint('[FocusDndService] getStatus failed: $e\n$st');
      return const FocusDndStatus.unavailable();
    }
  }

  Future<bool> openPolicyAccessSettings() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openPolicyAccessSettings') ??
          false;
    } catch (e, st) {
      debugPrint('[FocusDndService] open settings failed: $e\n$st');
      return false;
    }
  }

  Future<FocusDndEnableResult> enable({
    int filter = interruptionFilterPriority,
  }) async {
    if (!_isAndroid) return const FocusDndEnableResult(enabled: false);
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'enableDnd',
        <String, Object?>{'filter': filter},
      );
      return FocusDndEnableResult.fromMap(raw);
    } catch (e, st) {
      debugPrint('[FocusDndService] enable failed: $e\n$st');
      return const FocusDndEnableResult(enabled: false);
    }
  }

  Future<bool> restore(int? previousFilter) async {
    if (!_isAndroid || previousFilter == null) return false;
    try {
      return await _channel.invokeMethod<bool>('restoreDnd', <String, Object?>{
            'previousFilter': previousFilter,
          }) ??
          false;
    } catch (e, st) {
      debugPrint('[FocusDndService] restore failed: $e\n$st');
      return false;
    }
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
