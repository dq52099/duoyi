/// 位置服务 - 适配层。
///
/// 不直接依赖 `geolocator` 插件（保持依赖表干净）。
/// `LocationProbe` 是接口：调用方可以注入插件实现，也可以走"用户手动输入"
/// 的回退实现。本期通过 [ManualLocationProbe] 提供回退能力，
/// 后续如需后台 geofence 监听，可在 `lib/services/location_probe_geolocator.dart`
/// 里实现 `LocationProbe` 接口并注入到 main.dart。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../providers/location_reminder_provider.dart';

abstract class LocationProbe {
  /// 启动后台位置追踪。命中 [LocationReminder] 时回调 [onFix]。
  Future<void> start({required void Function(LocationFix) onFix});

  /// 暂停后台追踪。
  Future<void> stop();

  /// 当前是否在追踪。
  bool get isTracking;
}

/// 手动注入位置的回退实现（不需要权限）。
///
/// 调用方可以通过 [setCurrentLocation] 主动报告坐标。
class ManualLocationProbe implements LocationProbe {
  bool _running = false;
  void Function(LocationFix)? _onFix;

  @override
  bool get isTracking => _running;

  @override
  Future<void> start({required void Function(LocationFix) onFix}) async {
    _running = true;
    _onFix = onFix;
  }

  @override
  Future<void> stop() async {
    _running = false;
    _onFix = null;
  }

  void setCurrentLocation(double latitude, double longitude) {
    if (!_running) return;
    final fix = LocationFix(
      latitude: latitude,
      longitude: longitude,
      at: DateTime.now(),
    );
    _onFix?.call(fix);
  }
}

/// 把 [LocationProbe] 的位置流接入 [LocationReminderProvider]。
///
/// 命中的 reminder 由调用方决定如何展示（通常用 [NotificationService]
/// 弹一条本地通知）。
class LocationReminderController {
  final LocationProbe probe;
  final LocationReminderProvider provider;
  final void Function(LocationReminderHit hit)? onHit;
  StreamSubscription<void>? _hbSub;

  LocationReminderController({
    required this.probe,
    required this.provider,
    this.onHit,
  });

  Future<void> start() async {
    await probe.start(onFix: _handleFix);
  }

  Future<void> stop() async {
    await _hbSub?.cancel();
    await probe.stop();
  }

  void _handleFix(LocationFix fix) {
    try {
      final hits = provider.ingestFix(fix);
      for (final hit in hits) {
        onHit?.call(hit);
      }
    } catch (e, st) {
      debugPrint('[LocationReminderController] ingest failed: $e\n$st');
    }
  }
}
