/// 位置提醒引擎与 Provider。
///
/// 不依赖 geolocator 插件以避免引入新依赖；调用方将当前位置喂入
/// [LocationReminderEngine.evaluate]，引擎判定哪些 reminder 命中
/// （并基于 `trigger.enter` / `trigger.leave` 与上次状态做边界检测）。
///
/// 真实定位订阅由上层接入：例如 `geolocator` 后续插件。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/location_reminder.dart';
import 'cloud_sync_provider.dart';

class LocationFix {
  final double latitude;
  final double longitude;
  final DateTime at;

  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.at,
  });
}

class LocationReminderHit {
  final LocationReminder reminder;
  final LocationTrigger triggeredBy;
  final LocationFix fix;

  const LocationReminderHit({
    required this.reminder,
    required this.triggeredBy,
    required this.fix,
  });
}

class LocationReminderEngine {
  LocationReminderEngine._();

  /// Haversine 距离（米）。
  static double distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180.0;
    final dLat = rad(lat2 - lat1);
    final dLon = rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  /// 给定当前位置与上一轮"是否在范围内"的状态，判定哪些提醒命中。
  ///
  /// [previousInRange] 维护 reminderId → bool 表示上一轮判定。
  /// 返回 (hits, updatedInRange)。
  static (List<LocationReminderHit>, Map<String, bool>) evaluate({
    required List<LocationReminder> reminders,
    required LocationFix fix,
    required Map<String, bool> previousInRange,
    Duration cooldown = const Duration(minutes: 10),
  }) {
    final hits = <LocationReminderHit>[];
    final next = Map<String, bool>.from(previousInRange);
    for (final r in reminders) {
      final d = distanceMeters(
        fix.latitude,
        fix.longitude,
        r.latitude,
        r.longitude,
      );
      final nowInRange = d <= r.radiusMeters;
      final prev = previousInRange[r.id] ?? false;
      next[r.id] = nowInRange;

      final lastFired = r.lastFiredAt;
      if (lastFired != null && fix.at.difference(lastFired).abs() < cooldown) {
        continue;
      }

      final triggered = r.trigger == LocationTrigger.enter
          ? !prev && nowInRange
          : prev && !nowInRange;
      if (triggered) {
        hits.add(
          LocationReminderHit(reminder: r, triggeredBy: r.trigger, fix: fix),
        );
      }
    }
    return (hits, next);
  }
}

class LocationReminderProvider extends ChangeNotifier {
  static const _key = 'duoyi_location_reminders_v1';

  final List<LocationReminder> _reminders = [];
  final Map<String, bool> _inRange = {};
  bool _loaded = false;

  List<LocationReminder> get reminders =>
      List<LocationReminder>.unmodifiable(_reminders);
  bool get isLoaded => _loaded;

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      _loaded = true;
      return;
    }
    try {
      final list = jsonDecode(raw) as List;
      _reminders
        ..clear()
        ..addAll(
          list.whereType<Map>().map(
            (m) => LocationReminder.fromJson(Map<String, dynamic>.from(m)),
          ),
        );
    } catch (e) {
      debugPrint('[LocationReminder] load failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> add(LocationReminder reminder) async {
    _reminders.add(reminder);
    await _save();
    notifyListeners();
  }

  Future<void> update(LocationReminder reminder) async {
    final i = _reminders.indexWhere((r) => r.id == reminder.id);
    if (i < 0) return;
    _reminders[i] = reminder.copyWith(updatedAt: DateTime.now());
    await _save();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    await CloudSyncProvider.recordDeletedItem('location_reminders', id);
    _reminders.removeWhere((r) => r.id == id);
    _inRange.remove(id);
    await _save();
    notifyListeners();
  }

  /// 注入一次位置更新；返回命中的提醒。
  List<LocationReminderHit> ingestFix(LocationFix fix) {
    final (hits, nextRange) = LocationReminderEngine.evaluate(
      reminders: _reminders,
      fix: fix,
      previousInRange: _inRange,
    );
    _inRange
      ..clear()
      ..addAll(nextRange);
    if (hits.isNotEmpty) {
      // 更新 lastFiredAt + oneShot 删除
      final removedIds = <String>[];
      for (final hit in hits) {
        final i = _reminders.indexWhere((r) => r.id == hit.reminder.id);
        if (i < 0) continue;
        if (_reminders[i].oneShot) {
          removedIds.add(_reminders[i].id);
          _reminders.removeAt(i);
        } else {
          _reminders[i] = _reminders[i].copyWith(lastFiredAt: fix.at);
        }
      }
      // ignore: discarded_futures
      _saveTriggeredHits(removedIds);
    }
    return hits;
  }

  Future<void> _saveTriggeredHits(List<String> removedIds) async {
    if (removedIds.isNotEmpty) {
      await CloudSyncProvider.recordDeletedItems(
        'location_reminders',
        removedIds,
      );
    }
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_reminders.map((r) => r.toJson()).toList()),
    );
  }
}
