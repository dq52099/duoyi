import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/countdown.dart';

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

  void updateItem(CountdownItem item) {
    final idx = _items.indexWhere((e) => e.id == item.id);
    if (idx == -1) return;
    _items[idx] = item;
    _save();
  }

  void deleteItem(String id) {
    _items.removeWhere((e) => e.id == id);
    _save();
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
