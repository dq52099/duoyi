import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/anniversary.dart';
import '../services/reminder_scheduler.dart';
import 'cloud_sync_provider.dart';

class AnniversaryProvider extends ChangeNotifier {
  static const _key = 'duoyi_anniversaries_v2';
  static const Duration _reminderSyncTimeout = Duration(seconds: 5);
  List<Anniversary> _items = [];
  ReminderScheduler? _scheduler;

  List<Anniversary> get items {
    final sorted = [..._items];
    sorted.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return a.daysRemaining.compareTo(b.daysRemaining);
    });
    return List.unmodifiable(sorted);
  }

  /// 纯倒数(单次)
  List<Anniversary> get countdowns =>
      _items.where((e) => e.type == AnniversaryType.normal).toList();

  /// 生日
  List<Anniversary> get birthdays =>
      _items.where((e) => e.type == AnniversaryType.birthday).toList();

  /// 纪念日
  List<Anniversary> get memorials =>
      _items.where((e) => e.type == AnniversaryType.memorial).toList();

  /// 最近 30 天内要发生的
  List<Anniversary> get upcoming {
    return items.where((e) {
      final d = e.daysRemaining;
      return d >= 0 && d <= 30;
    }).toList();
  }

  // ignore: use_setters_to_change_properties
  set scheduler(ReminderScheduler? scheduler) {
    _scheduler = scheduler;
  }

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_key) ?? [];
    _items = data.map((e) => Anniversary.fromJson(jsonDecode(e))).toList();

    notifyListeners();
  }

  void resetLocalState() {
    _items = [];
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      _items.map((e) => jsonEncode(e.toJson())).toList(),
    );
    notifyListeners();
  }

  Future<void> _syncRemindersNow() async {
    final scheduler = _scheduler;
    if (scheduler == null) return;
    try {
      await scheduler
          .syncAnniversaries(List.of(_items))
          .timeout(_reminderSyncTimeout);
    } catch (error, stackTrace) {
      debugPrint(
        '[AnniversaryProvider] reminder sync failed: $error\n$stackTrace',
      );
    }
  }

  Future<void> add(Anniversary item) async {
    item.updatedAt = DateTime.now();
    final index = _items.indexWhere((existing) => existing.id == item.id);
    if (index == -1) {
      _items.add(item);
    } else {
      _items[index] = item;
    }
    await _save();
    await _syncRemindersNow();
  }

  Future<AnniversaryImportSummary> importAnniversaries(
    Iterable<Anniversary> items,
  ) async {
    var inserted = 0;
    var skippedDuplicates = 0;
    final seen = _items.map(_importDuplicateKey).toSet();
    for (final item in items) {
      if (item.title.trim().isEmpty) continue;
      if (item.type == AnniversaryType.normal) {
        skippedDuplicates++;
        continue;
      }
      final key = _importDuplicateKey(item);
      if (seen.contains(key)) {
        skippedDuplicates++;
        continue;
      }
      seen.add(key);
      _items.add(item);
      inserted++;
    }
    if (inserted > 0) {
      await _save();
      await _syncRemindersNow();
    }
    return AnniversaryImportSummary(
      inserted: inserted,
      skippedDuplicates: skippedDuplicates,
    );
  }

  Future<void> update(Anniversary item) async {
    final idx = _items.indexWhere((e) => e.id == item.id);
    if (idx != -1) {
      item.updatedAt = DateTime.now();
      _items[idx] = item;
      await _save();
      await _syncRemindersNow();
    }
  }

  Future<void> delete(String id) async {
    await CloudSyncProvider.recordDeletedItem('anniversaries', id);
    _items.removeWhere((e) => e.id == id);
    await _save();
    await _syncRemindersNow();
  }

  Future<void> togglePin(String id) async {
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx != -1) {
      _items[idx].isPinned = !_items[idx].isPinned;
      _items[idx].updatedAt = DateTime.now();
      await _save();
    }
  }
}

class AnniversaryImportSummary {
  final int inserted;
  final int skippedDuplicates;

  const AnniversaryImportSummary({
    required this.inserted,
    required this.skippedDuplicates,
  });
}

String _importDuplicateKey(Anniversary item) {
  return [
    item.title.trim().toLowerCase(),
    item.originDate.toIso8601String(),
    item.type.index,
    item.calendarType.index,
  ].join('|');
}
