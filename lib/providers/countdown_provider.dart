import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/countdown.dart';
import '../models/goal.dart' show ReminderKind;
import '../services/account_local_data_cleaner.dart';
import '../services/reminder_scheduler.dart';
import 'cloud_sync_provider.dart';

class CountdownProvider extends ChangeNotifier {
  static const _key = 'duoyi_countdowns';
  static const Duration _reminderSyncTimeout = Duration(seconds: 5);
  List<CountdownItem> _items = [];
  ReminderScheduler? _scheduler;
  int _storageGeneration = 0;
  String? _lastReminderSyncIssue;
  VoidCallback? onLocalMutationPersisted;

  List<CountdownItem> get items => List.unmodifiable(
    [..._items]..sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return a.targetDate.compareTo(b.targetDate);
    }),
  );

  String? get lastReminderSyncIssue => _lastReminderSyncIssue;

  // ignore: use_setters_to_change_properties
  set scheduler(ReminderScheduler? scheduler) {
    _scheduler = scheduler;
  }

  bool _isCurrentStorageGeneration(
    int storageGeneration,
    int accountGeneration,
  ) {
    return storageGeneration == _storageGeneration &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        );
  }

  Future<void> loadFromStorage() async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
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
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
    _items = loaded;
    notifyListeners();
  }

  void resetLocalState() {
    _storageGeneration++;
    _items = [];
    _lastReminderSyncIssue = null;
    notifyListeners();
  }

  Future<bool> _save() async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final data = _items.map((e) => jsonEncode(e.toJson())).toList();
    final prefs = await SharedPreferences.getInstance();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) {
      return false;
    }
    await prefs.setStringList(_key, data);
    _notifyLocalMutationPersisted();
    notifyListeners();
    return true;
  }

  void _notifyLocalMutationPersisted() {
    try {
      onLocalMutationPersisted?.call();
    } catch (e, st) {
      debugPrint('[CountdownProvider] local mutation callback failed: $e\n$st');
    }
  }

  Future<String?> _syncRemindersNow() async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final scheduler = _scheduler;
    if (scheduler == null) {
      if (!_hasEnabledReminders()) {
        _lastReminderSyncIssue = null;
        return null;
      }
      final issue = '提醒服务未初始化，未能注册倒数日提醒。请重启应用或重新打开提醒设置后再保存。';
      _lastReminderSyncIssue = issue;
      return issue;
    }
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) {
      return null;
    }
    final items = List.of(_items);
    try {
      await scheduler.syncCountdowns(items).timeout(_reminderSyncTimeout);
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) {
        return null;
      }
      _lastReminderSyncIssue = null;
      return null;
    } on ReminderScheduleSyncException catch (error, stackTrace) {
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) {
        return null;
      }
      final issue = error.failures.isEmpty
          ? '提醒未注册，请检查通知权限、提醒方式和提醒时间后重新保存。'
          : error.failures.first;
      _lastReminderSyncIssue = issue;
      debugPrint(
        '[CountdownProvider] reminder sync failed: $error\n$stackTrace',
      );
      return issue;
    } catch (error, stackTrace) {
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) {
        return null;
      }
      final issue = '提醒未注册，请检查通知权限、提醒方式和提醒时间后重新保存。';
      _lastReminderSyncIssue = issue;
      debugPrint(
        '[CountdownProvider] reminder sync failed: $error\n$stackTrace',
      );
      return issue;
    }
  }

  bool _hasEnabledReminders() {
    return _items.any(
      (item) => item.remind && item.reminderKind != ReminderKind.off,
    );
  }

  Future<String?> addItem(CountdownItem item) async {
    final idx = _items.indexWhere((e) => e.id == item.id);
    if (idx == -1) {
      _items.add(item);
    } else {
      _items[idx] = item;
    }
    final saved = await _save();
    if (!saved) return null;
    return _syncRemindersNow();
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
    String? reminderSyncIssue;
    if (inserted > 0) {
      final saved = await _save();
      if (saved) reminderSyncIssue = await _syncRemindersNow();
    }
    return CountdownImportSummary(
      inserted: inserted,
      skippedDuplicates: skippedDuplicates,
      reminderSyncIssue: reminderSyncIssue,
    );
  }

  Future<String?> updateItem(CountdownItem item) async {
    final idx = _items.indexWhere((e) => e.id == item.id);
    if (idx == -1) {
      _items.add(item);
    } else {
      _items[idx] = item;
    }
    final saved = await _save();
    if (!saved) return null;
    return _syncRemindersNow();
  }

  Future<void> deleteItem(String id) async {
    await CloudSyncProvider.recordDeletedItem('countdowns', id);
    _items.removeWhere((e) => e.id == id);
    final saved = await _save();
    if (saved) await _syncRemindersNow();
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
  final String? reminderSyncIssue;

  const CountdownImportSummary({
    required this.inserted,
    required this.skippedDuplicates,
    this.reminderSyncIssue,
  });
}

String _importDuplicateKey(CountdownItem item) {
  return [
    item.title.trim().toLowerCase(),
    item.targetDate.toIso8601String(),
    item.category.trim().toLowerCase(),
  ].join('|');
}
