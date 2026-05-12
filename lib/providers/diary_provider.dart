import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/domain_event_bus.dart';
import '../models/diary_entry.dart';

class DiaryProvider extends ChangeNotifier {
  static const _key = 'duoyi_diary';
  List<DiaryEntry> _entries = [];

  List<DiaryEntry> get entries =>
      List.unmodifiable(_entries..sort((a, b) => b.date.compareTo(a.date)));

  int get totalCount => _entries.length;

  int get thisMonthCount {
    final now = DateTime.now();
    return _entries
        .where((e) => e.date.year == now.year && e.date.month == now.month)
        .length;
  }

  /// 连续写日记天数
  int get currentStreak {
    if (_entries.isEmpty) return 0;
    final sorted = [..._entries]..sort((a, b) => b.date.compareTo(a.date));
    final dates = sorted.map((e) => _normalize(e.date)).toSet().toList()
      ..sort((a, b) => b.compareTo(a));

    final today = _normalize(DateTime.now());
    int streak = 0;
    DateTime cursor = today;
    if (!dates.contains(today)) {
      cursor = today.subtract(const Duration(days: 1));
      if (!dates.contains(cursor)) return 0;
    }
    while (dates.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  DateTime _normalize(DateTime d) => DateTime(d.year, d.month, d.day);

  DiaryEntry? entryForDate(DateTime date) {
    final key =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    for (final e in _entries) {
      if (e.dateKey == key) return e;
    }
    return null;
  }

  Map<String, DiaryEntry> get entriesByDate {
    final map = <String, DiaryEntry>{};
    for (final e in _entries) {
      map[e.dateKey] = e;
    }
    return map;
  }

  /// 心情统计(过去 N 天)
  Map<Mood, int> moodDistribution({int days = 30}) {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: days));
    final map = <Mood, int>{};
    for (final e in _entries) {
      if (e.mood == null) continue;
      if (e.date.isBefore(cutoff)) continue;
      map[e.mood!] = (map[e.mood!] ?? 0) + 1;
    }
    return map;
  }

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_key) ?? [];
    _entries = data.map((e) => DiaryEntry.fromJson(jsonDecode(e))).toList();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      _entries.map((e) => jsonEncode(e.toJson())).toList(),
    );
    notifyListeners();
  }

  Future<void> addOrUpdate(DiaryEntry entry) async {
    final idx = _entries.indexWhere((e) => e.id == entry.id);
    // 同一天只保留一条，更新的情况下比对日期
    final sameDayIdx = _entries.indexWhere(
      (e) => e.dateKey == entry.dateKey && e.id != entry.id,
    );
    if (idx != -1) {
      entry.updatedAt = DateTime.now();
      _entries[idx] = entry;
    } else if (sameDayIdx != -1) {
      // 存在同一天的日记，合并
      final existing = _entries[sameDayIdx];
      existing.content = entry.content;
      existing.mood = entry.mood;
      existing.weather = entry.weather;
      existing.tags = entry.tags;
      existing.imagePaths = entry.imagePaths;
      existing.location = entry.location;
      existing.updatedAt = DateTime.now();
    } else {
      _entries.add(entry);
      DomainEventBus.instance.publish(
        DomainEvent(type: DomainEventType.diaryWritten, objectId: entry.id),
      );
    }
    await _save();
  }

  Future<void> delete(String id) async {
    _entries.removeWhere((e) => e.id == id);
    await _save();
  }
}
