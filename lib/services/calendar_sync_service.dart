/// 第三方日历 ICS 订阅服务。
///
/// 支持只读订阅符合 RFC 5545 的 .ics URL。覆盖 Google Calendar Public iCal、
/// Outlook Public Subscribe、CalDAV 服务器 export 端点、企业 iCal feeds。
///
/// 设计：
/// - 后台 HTTP GET → 解析 VEVENT → 转换为本地 CalendarEvent 视图模型。
/// - 不写入 Todo/Goal 等原始模块；只把订阅事件并入日历聚合。
/// - 失败优雅降级；保留上次缓存。
/// - 不做双向同步；写操作（创建/编辑日程）仍在多仪本地。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/calendar_event.dart';

class IcsSubscription {
  final String id;
  final String name;
  final String url;
  final int colorValue;
  final bool enabled;
  final DateTime? lastSyncedAt;

  const IcsSubscription({
    required this.id,
    required this.name,
    required this.url,
    this.colorValue = 0xFF42A5F5,
    this.enabled = true,
    this.lastSyncedAt,
  });

  IcsSubscription copyWith({
    String? name,
    String? url,
    int? colorValue,
    bool? enabled,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
  }) => IcsSubscription(
    id: id,
    name: name ?? this.name,
    url: url ?? this.url,
    colorValue: colorValue ?? this.colorValue,
    enabled: enabled ?? this.enabled,
    lastSyncedAt: clearLastSyncedAt ? null : (lastSyncedAt ?? this.lastSyncedAt),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'colorValue': colorValue,
    'enabled': enabled,
    'lastSyncedAt': lastSyncedAt?.toIso8601String(),
  };

  factory IcsSubscription.fromJson(Map<String, dynamic> json) =>
      IcsSubscription(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '订阅',
        url: json['url']?.toString() ?? '',
        colorValue:
            (json['colorValue'] as num?)?.toInt() ?? 0xFF42A5F5,
        enabled: json['enabled'] != false,
        lastSyncedAt: DateTime.tryParse(
          json['lastSyncedAt']?.toString() ?? '',
        ),
      );
}

class CalendarSyncProvider extends ChangeNotifier {
  static const _subscriptionsKey = 'duoyi_ics_subscriptions_v1';
  static const _eventsKeyPrefix = 'duoyi_ics_events_';

  final List<IcsSubscription> _subscriptions = [];
  final Map<String, List<CalendarEvent>> _eventsBySubscription = {};
  bool _syncing = false;
  String? _lastError;

  List<IcsSubscription> get subscriptions =>
      List<IcsSubscription>.unmodifiable(_subscriptions);

  bool get isSyncing => _syncing;

  String? get lastError => _lastError;

  /// 所有订阅汇总后的只读事件。
  List<CalendarEvent> allEvents() {
    final out = <CalendarEvent>[];
    for (final list in _eventsBySubscription.values) {
      out.addAll(list);
    }
    return out;
  }

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_subscriptionsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _subscriptions
          ..clear()
          ..addAll(
            list
                .whereType<Map>()
                .map(
                  (m) => IcsSubscription.fromJson(
                    Map<String, dynamic>.from(m),
                  ),
                ),
          );
      } catch (e) {
        debugPrint('[CalendarSync] load subscriptions failed: $e');
      }
    }
    for (final sub in _subscriptions) {
      final cached = prefs.getString('$_eventsKeyPrefix${sub.id}');
      if (cached == null) continue;
      try {
        final list = jsonDecode(cached) as List;
        _eventsBySubscription[sub.id] = list
            .whereType<Map>()
            .map((m) => _calendarEventFromJson(
                  Map<String, dynamic>.from(m),
                  Color(sub.colorValue),
                ))
            .whereType<CalendarEvent>()
            .toList();
      } catch (e) {
        debugPrint('[CalendarSync] load cached events failed: $e');
      }
    }
    notifyListeners();
  }

  Future<void> addSubscription(IcsSubscription sub) async {
    _subscriptions.add(sub);
    await _save();
    notifyListeners();
  }

  Future<void> updateSubscription(IcsSubscription sub) async {
    final i = _subscriptions.indexWhere((s) => s.id == sub.id);
    if (i < 0) return;
    _subscriptions[i] = sub;
    await _save();
    notifyListeners();
  }

  Future<void> removeSubscription(String id) async {
    _subscriptions.removeWhere((s) => s.id == id);
    _eventsBySubscription.remove(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_eventsKeyPrefix$id');
    await _save();
    notifyListeners();
  }

  /// 拉取所有启用的订阅，更新缓存。
  Future<void> syncAll() async {
    if (_syncing) return;
    _syncing = true;
    _lastError = null;
    notifyListeners();
    try {
      for (final sub in _subscriptions.where((s) => s.enabled)) {
        await _syncOne(sub);
      }
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> _syncOne(IcsSubscription sub) async {
    try {
      final resp = await http.get(Uri.parse(sub.url)).timeout(
        const Duration(seconds: 20),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        debugPrint('[CalendarSync] ${sub.url} returned ${resp.statusCode}');
        return;
      }
      final events = IcsParser.parse(
        resp.body,
        subscriptionId: sub.id,
        color: Color(sub.colorValue),
      );
      _eventsBySubscription[sub.id] = events;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_eventsKeyPrefix${sub.id}',
        jsonEncode(events.map(_calendarEventToJson).toList()),
      );
      final idx = _subscriptions.indexWhere((s) => s.id == sub.id);
      if (idx >= 0) {
        _subscriptions[idx] =
            _subscriptions[idx].copyWith(lastSyncedAt: DateTime.now());
        await _save();
      }
    } catch (e, st) {
      debugPrint('[CalendarSync] sync ${sub.url} failed: $e\n$st');
      _lastError = e.toString();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _subscriptionsKey,
      jsonEncode(_subscriptions.map((s) => s.toJson()).toList()),
    );
  }
}

// ---------------------------------------------------------------------------
// JSON helpers
// ---------------------------------------------------------------------------

Map<String, Object?> _calendarEventToJson(CalendarEvent e) => {
  'id': e.id,
  'title': e.title,
  'date': e.date.toIso8601String(),
  'endDate': e.endDate?.toIso8601String(),
  'subtitle': e.subtitle,
  'colorValue': e.color.toARGB32(),
  'sourceId': e.sourceId,
  'timeHour': e.time?.hour,
  'timeMinute': e.time?.minute,
};

CalendarEvent? _calendarEventFromJson(Map<String, dynamic> json, Color color) {
  try {
    return CalendarEvent(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      date: DateTime.parse(json['date'] as String),
      endDate: json['endDate'] != null
          ? DateTime.parse(json['endDate'] as String)
          : null,
      subtitle: json['subtitle']?.toString(),
      type: CalendarEventType.timeEntry,
      color: color,
      sourceId: json['sourceId']?.toString(),
      time: (json['timeHour'] != null && json['timeMinute'] != null)
          ? TimeOfDay(
              hour: (json['timeHour'] as num).toInt(),
              minute: (json['timeMinute'] as num).toInt(),
            )
          : null,
    );
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// ICS parser (RFC 5545 subset)
// ---------------------------------------------------------------------------

class IcsParser {
  IcsParser._();

  static List<CalendarEvent> parse(
    String body, {
    required String subscriptionId,
    required Color color,
  }) {
    // 折行处理：以空格/Tab 开头的下一行属于上一行
    final lines = _unfold(body.split(RegExp(r'\r?\n')));
    final events = <CalendarEvent>[];
    int i = 0;
    while (i < lines.length) {
      if (lines[i].trim().toUpperCase() == 'BEGIN:VEVENT') {
        final endIdx = lines.indexWhere(
          (l) => l.trim().toUpperCase() == 'END:VEVENT',
          i,
        );
        if (endIdx < 0) break;
        final ev = _parseEvent(
          lines.sublist(i + 1, endIdx),
          subscriptionId: subscriptionId,
          color: color,
        );
        if (ev != null) events.add(ev);
        i = endIdx + 1;
      } else {
        i++;
      }
    }
    return events;
  }

  static List<String> _unfold(List<String> raw) {
    final out = <String>[];
    for (final line in raw) {
      if (line.isEmpty) continue;
      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (out.isNotEmpty) {
          out[out.length - 1] = out.last + line.substring(1);
        }
      } else {
        out.add(line);
      }
    }
    return out;
  }

  static CalendarEvent? _parseEvent(
    List<String> body, {
    required String subscriptionId,
    required Color color,
  }) {
    String? uid;
    String? summary;
    String? location;
    DateTime? dtStart;
    DateTime? dtEnd;
    bool allDay = false;
    for (final line in body) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final key = line.substring(0, colon).toUpperCase();
      final value = line.substring(colon + 1);
      if (key == 'UID') {
        uid = value;
      } else if (key == 'SUMMARY') {
        summary = _unescape(value);
      } else if (key == 'LOCATION') {
        location = _unescape(value);
      } else if (key.startsWith('DTSTART')) {
        final pair = _parseDate(key, value);
        dtStart = pair?.value;
        allDay = pair?.allDay ?? false;
      } else if (key.startsWith('DTEND')) {
        final pair = _parseDate(key, value);
        dtEnd = pair?.value;
      }
    }
    if (uid == null || summary == null || dtStart == null) return null;
    return CalendarEvent(
      id: 'ics_${subscriptionId}_$uid',
      title: summary,
      subtitle: location,
      date: dtStart,
      endDate: dtEnd,
      type: CalendarEventType.timeEntry,
      color: color,
      sourceId: uid,
      time: allDay ? null : TimeOfDay.fromDateTime(dtStart),
    );
  }

  static String _unescape(String s) {
    return s
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\,', ',')
        .replaceAll(r'\;', ';')
        .replaceAll(r'\\', r'\');
  }

  /// 解析 DTSTART / DTEND；支持：
  /// - `YYYYMMDDTHHMMSSZ`（UTC）
  /// - `YYYYMMDDTHHMMSS`（本地）
  /// - `YYYYMMDD`（全天）
  static _DateParse? _parseDate(String key, String value) {
    final raw = value.trim();
    if (raw.length == 8) {
      final y = int.tryParse(raw.substring(0, 4));
      final m = int.tryParse(raw.substring(4, 6));
      final d = int.tryParse(raw.substring(6, 8));
      if (y == null || m == null || d == null) return null;
      return _DateParse(DateTime(y, m, d), true);
    }
    if (raw.length >= 15) {
      final y = int.tryParse(raw.substring(0, 4));
      final mo = int.tryParse(raw.substring(4, 6));
      final d = int.tryParse(raw.substring(6, 8));
      final h = int.tryParse(raw.substring(9, 11));
      final mi = int.tryParse(raw.substring(11, 13));
      final s = int.tryParse(raw.substring(13, 15));
      if (y == null ||
          mo == null ||
          d == null ||
          h == null ||
          mi == null ||
          s == null) {
        return null;
      }
      final isUtc = raw.endsWith('Z');
      final dt = isUtc
          ? DateTime.utc(y, mo, d, h, mi, s).toLocal()
          : DateTime(y, mo, d, h, mi, s);
      return _DateParse(dt, false);
    }
    return null;
  }
}

class _DateParse {
  final DateTime value;
  final bool allDay;
  const _DateParse(this.value, this.allDay);
}
