import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/countdown.dart';
import '../services/reminder_scheduler.dart';
import 'cloud_sync_provider.dart';

class CountdownProvider extends ChangeNotifier {
  static const _key = 'duoyi_countdowns';
  static const Duration _reminderSyncTimeout = Duration(seconds: 5);
  List<CountdownItem> _items = [];
  ReminderScheduler? _scheduler;

  List<CountdownItem> get items => List.unmodifiable(
    [..._items]..sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return a.targetDate.compareTo(b.targetDate);
    }),
  );

  // ignore: use_setters_to_change_properties
  set scheduler(ReminderScheduler? scheduler) {
    _scheduler = scheduler;
  }

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_key) ?? [];
    final loaded = <CountdownItem>[];
    for (final entry in data) {
      try {
        final decoded = jsonDecode(entry);
        if (decoded is Map<String, dynamic>) {
          loaded.add(CountdownItem.fromJson(decoded));
        } else if (decoded is Map) {
          loaded.add(
            CountdownItem.fromJson(Map<String, dynamic>.from(decoded)),
          );
        }
      } catch (error, stackTrace) {
        debugPrint(
          '[CountdownProvider] skipped invalid countdown record: $error\n$stackTrace',
        );
      }
    }
    _items = loaded;
    notifyListeners();
  }

  void resetLocalState() {
    _items = [];
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _items.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_key, data);
    notifyListeners();
  }

  Future<void> _syncRemindersNow() async {
    final scheduler = _scheduler;
    if (scheduler == null) return;
    try {
      await scheduler
          .syncCountdowns(List.of(_items))
          .timeout(_reminderSyncTimeout);
    } catch (error, stackTrace) {
      debugPrint(
        '[CountdownProvider] reminder sync failed: $error\n$stackTrace',
      );
    }
  }

  Future<void> addItem(CountdownItem item) async {
    final idx = _items.indexWhere((e) => e.id == item.id);
    if (idx == -1) {
      _items.add(item);
    } else {
      _items[idx] = item;
    }
    await _save();
    await _syncRemindersNow();
  }

  Future<CountdownImportSummary> importCountdowns(
    Iterable<CountdownItem> items,
  ) async {
    var inserted = 0;
    var skippedDuplicates = 0;
    final seen = _items.map(_importDuplicateKey).toSet();
    for (final item in items) {
      if (item.title.trim().isEmpty) {
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
    return CountdownImportSummary(
      inserted: inserted,
      skippedDuplicates: skippedDuplicates,
    );
  }

  Future<void> updateItem(CountdownItem item) async {
    final idx = _items.indexWhere((e) => e.id == item.id);
    if (idx == -1) {
      _items.add(item);
    } else {
      _items[idx] = item;
    }
    await _save();
    await _syncRemindersNow();
  }

  Future<void> deleteItem(String id) async {
    await CloudSyncProvider.recordDeletedItem('countdowns', id);
    _items.removeWhere((e) => e.id == id);
    await _save();
    await _syncRemindersNow();
  }

  Future<void> togglePin(String id) async {
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx != -1) {
      final old = _items[idx];
      _items[idx] = old.copyWith(isPinned: !old.isPinned);
      await _save();
    }
  }
}

class CountdownImportSummary {
  final int inserted;
  final int skippedDuplicates;

  const CountdownImportSummary({
    required this.inserted,
    required this.skippedDuplicates,
  });
}

String _importDuplicateKey(CountdownItem item) {
  return [
    item.title.trim().toLowerCase(),
    item.targetDate.toIso8601String(),
    item.category.trim().toLowerCase(),
  ].join('|');
}
