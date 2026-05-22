import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/countdown.dart';
import 'cloud_sync_provider.dart';

class CountdownProvider extends ChangeNotifier {
  static const _key = 'duoyi_countdowns';
  List<CountdownItem> _items = [];

  List<CountdownItem> get items => List.unmodifiable(
    _items..sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return a.targetDate.compareTo(b.targetDate);
    }),
  );

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_key) ?? [];
    _items = data.map((e) => CountdownItem.fromJson(jsonDecode(e))).toList();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _items.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_key, data);
    notifyListeners();
  }

  void addItem(CountdownItem item) {
    _items.add(item);
    _save();
  }

  Future<CountdownImportSummary> importCountdowns(
    Iterable<CountdownItem> items,
  ) async {
    var inserted = 0;
    var skippedDuplicates = 0;
    final seen = _items.map(_importDuplicateKey).toSet();
    for (final item in items) {
      if (item.title.trim().isEmpty) continue;
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
    }
    return CountdownImportSummary(
      inserted: inserted,
      skippedDuplicates: skippedDuplicates,
    );
  }

  void updateItem(CountdownItem item) {
    final idx = _items.indexWhere((e) => e.id == item.id);
    if (idx == -1) return;
    _items[idx] = item;
    _save();
  }

  Future<void> deleteItem(String id) async {
    await CloudSyncProvider.recordDeletedItem('countdowns', id);
    _items.removeWhere((e) => e.id == id);
    await _save();
  }

  void togglePin(String id) {
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx != -1) {
      final old = _items[idx];
      _items[idx] = old.copyWith(isPinned: !old.isPinned);
      _save();
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
