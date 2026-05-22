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

  static Future<bool> requestPinWidget(DuoyiWidgetKind kind) async {
    if (!_isAndroid) return false;
    try {
      return await _channel
              .invokeMethod<bool>('requestPinWidget', <String, Object?>{
                'kind': switch (kind) {
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
                },
              }) ??
          false;
    } catch (e, st) {
      debugPrint('[AndroidWidgetManager] requestPinWidget failed: $e\n$st');
      return false;
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
