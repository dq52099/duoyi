import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum DuoyiWidgetKind {
  todo,
  focus,
  habit,
  calendar,
  schedule,
  goal,
  course,
  note,
  anniversary,
  diary,
}

enum AndroidWidgetPinResult {
  requested,
  unsupported,
  permissionDenied,
  invalidKind,
  unavailable;

  static AndroidWidgetPinResult fromId(String? id) {
    return switch (id) {
      'requested' => AndroidWidgetPinResult.requested,
      'unsupported' => AndroidWidgetPinResult.unsupported,
      'permission_denied' => AndroidWidgetPinResult.permissionDenied,
      'invalid_kind' => AndroidWidgetPinResult.invalidKind,
      _ => AndroidWidgetPinResult.unavailable,
    };
  }
}

class AndroidWidgetManager {
  AndroidWidgetManager._();

  static const MethodChannel _channel = MethodChannel('duoyi/widgets');

  static Future<bool> canRequestPinWidget() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canRequestPinWidget') ?? false;
    } catch (e, st) {
      debugPrint('[AndroidWidgetManager] canRequestPinWidget failed: $e\n$st');
      return false;
    }
  }

  static Future<AndroidWidgetPinResult> requestPinWidget(
    DuoyiWidgetKind kind,
  ) async {
    if (!_isAndroid) return AndroidWidgetPinResult.unsupported;
    try {
      final status = await _channel.invokeMethod<String>(
        'requestPinWidget',
        <String, Object?>{'kind': kind.id},
      );
      return AndroidWidgetPinResult.fromId(status);
    } catch (e, st) {
      debugPrint('[AndroidWidgetManager] requestPinWidget failed: $e\n$st');
      return AndroidWidgetPinResult.unavailable;
    }
  }

  static Future<bool> openWidgetSettings() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openWidgetSettings') ?? false;
    } catch (e, st) {
      debugPrint('[AndroidWidgetManager] openWidgetSettings failed: $e\n$st');
      return false;
    }
  }

  static bool get _isAndroid {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }
}

extension DuoyiWidgetKindId on DuoyiWidgetKind {
  String get id {
    return switch (this) {
      DuoyiWidgetKind.todo => 'todo',
      DuoyiWidgetKind.focus => 'focus',
      DuoyiWidgetKind.habit => 'habit',
      DuoyiWidgetKind.calendar => 'calendar',
      DuoyiWidgetKind.schedule => 'schedule',
      DuoyiWidgetKind.goal => 'goal',
      DuoyiWidgetKind.course => 'course',
      DuoyiWidgetKind.note => 'note',
      DuoyiWidgetKind.anniversary => 'anniversary',
      DuoyiWidgetKind.diary => 'diary',
    };
  }
}
