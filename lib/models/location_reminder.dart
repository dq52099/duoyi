/// 位置提醒（Location-based reminders）模型。
///
/// 设计：
/// - 用户绑定经纬度 + 半径 + 触发方向（进入/离开）；
/// - `LocationReminderEngine` 在 App 在前台 / 收到位置更新时检查匹配，
///   命中后 publish DomainEvent + 发本地通知；
/// - 真正的后台 geofence 监听需要平台插件（geolocator / flutter_background_geofence），
///   本期先做模型 + 前台触发能力，后续接入。
library;

import 'package:uuid/uuid.dart';

const _locationUuid = Uuid();

enum LocationTrigger { enter, leave }

class LocationReminder {
  final String id;
  final String title;
  final String? note;

  /// 纬度（WGS-84）。
  final double latitude;

  /// 经度（WGS-84）。
  final double longitude;

  /// 触发半径（米）。
  final double radiusMeters;

  /// 触发方向。
  final LocationTrigger trigger;

  /// 是否在触发一次后自动失效。
  final bool oneShot;

  /// 关联的原始模块（todo/goal/none）。
  final String? linkedType;

  /// 关联对象 ID。
  final String? linkedId;

  /// 创建时间。
  final DateTime createdAt;

  /// 最近一次编辑时间，用于云同步冲突判断。
  final DateTime updatedAt;

  /// 上次触发时间（用于 oneShot + 节流）。
  final DateTime? lastFiredAt;

  LocationReminder({
    String? id,
    required this.title,
    this.note,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 100,
    this.trigger = LocationTrigger.enter,
    this.oneShot = false,
    this.linkedType,
    this.linkedId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.lastFiredAt,
  })  : id = id ?? _locationUuid.v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  LocationReminder copyWith({
    String? title,
    String? note,
    double? latitude,
    double? longitude,
    double? radiusMeters,
    LocationTrigger? trigger,
    bool? oneShot,
    String? linkedType,
    String? linkedId,
    DateTime? updatedAt,
    DateTime? lastFiredAt,
    bool clearLastFiredAt = false,
  }) =>
      LocationReminder(
        id: id,
        title: title ?? this.title,
        note: note ?? this.note,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        radiusMeters: radiusMeters ?? this.radiusMeters,
        trigger: trigger ?? this.trigger,
        oneShot: oneShot ?? this.oneShot,
        linkedType: linkedType ?? this.linkedType,
        linkedId: linkedId ?? this.linkedId,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
        lastFiredAt:
            clearLastFiredAt ? null : (lastFiredAt ?? this.lastFiredAt),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
        'trigger': trigger.name,
        'oneShot': oneShot,
        'linkedType': linkedType,
        'linkedId': linkedId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'lastFiredAt': lastFiredAt?.toIso8601String(),
      };

  factory LocationReminder.fromJson(Map<String, dynamic> json) {
    return LocationReminder(
      id: json['id']?.toString(),
      title: json['title']?.toString() ?? '位置提醒',
      note: json['note']?.toString(),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 100,
      trigger: LocationTrigger.values.firstWhere(
        (t) => t.name == json['trigger'],
        orElse: () => LocationTrigger.enter,
      ),
      oneShot: json['oneShot'] == true,
      linkedType: json['linkedType']?.toString(),
      linkedId: json['linkedId']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      lastFiredAt: DateTime.tryParse(json['lastFiredAt']?.toString() ?? ''),
    );
  }
}
