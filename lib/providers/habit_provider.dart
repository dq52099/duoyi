import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/domain_event_bus.dart';
import '../models/habit.dart';
import '../models/time_entry.dart';
import 'time_audit_provider.dart';

class HabitProvider extends ChangeNotifier {
  List<Habit> _habits = [];
  TimeAuditProvider? _timeAudit;

  List<Habit> get habits => _habits;

  double get todayOverallProgress {
    final active = _habits.where((h) => h.isActiveToday()).toList();
    if (active.isEmpty) return 0;
    return active.fold(0.0, (sum, h) => sum + h.todayProgress()) /
        active.length;
  }

  int get todayTotalCompletions =>
      _habits.fold(0, (sum, h) => sum + h.todayCount());

  double get todayCompletionRate {
    final active = _habits.where((h) => h.isActiveToday()).toList();
    if (active.isEmpty) return 0;
    return active.where((h) => h.isCompletedToday()).length / active.length;
  }

  int get longestCurrentStreak => _habits.fold(
    0,
    (max, h) => h.currentStreak > max ? h.currentStreak : max,
  );

  int get longestBestStreak =>
      _habits.fold(0, (max, h) => h.bestStreak > max ? h.bestStreak : max);

  // --- Persistence ---

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('habits');
    if (data != null) {
      final list = json.decode(data) as List;
      _habits = list.map((e) => Habit.fromJson(e)).toList();
    }
    notifyListeners();
  }

  // ignore: use_setters_to_change_properties
  set timeAudit(TimeAuditProvider? provider) {
    _timeAudit = provider;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'habits',
      json.encode(_habits.map((e) => e.toJson()).toList()),
    );
  }

  // --- CRUD ---

  Future<void> addHabit(Habit habit) async {
    _habits.add(habit);
    DomainEventBus.instance.publish(
      DomainEvent(type: DomainEventType.habitCreated, objectId: habit.id),
    );
    notifyListeners();
    await _save();
  }

  Future<void> incrementHabit(String id) async {
    final idx = _habits.indexWhere((h) => h.id == id);
    if (idx != -1) {
      _habits[idx].completions[_habits[idx].todayKey()] =
          (_habits[idx].completions[_habits[idx].todayKey()] ?? 0) + 1;
      _recalcStreak(idx);
      DomainEventBus.instance.publish(
        DomainEvent(
          type: DomainEventType.habitCheckedIn,
          objectId: _habits[idx].id,
          metadata: {'count': _habits[idx].todayCount()},
        ),
      );
      notifyListeners();
      await _save();
      await _timeAudit?.recordHabitCheckIn(
        _habits[idx],
        cumulativeCount: _habits[idx].todayCount(),
      );
    }
  }

  Future<void> decrementHabit(String id) async {
    final idx = _habits.indexWhere((h) => h.id == id);
    if (idx != -1) {
      final key = _habits[idx].todayKey();
      final v = _habits[idx].completions[key] ?? 0;
      if (v > 0) {
        _habits[idx].completions[key] = v - 1;
        _recalcStreak(idx);
        notifyListeners();
        await _save();
        await _timeAudit?.removeHabitCheckIn(_habits[idx], count: v);
      }
    }
  }

  void _recalcStreak(int idx) {
    final h = _habits[idx];
    int streak = 0;
    final now = DateTime.now();
    for (int i = 0; i < 365; i++) {
      final d = now.subtract(Duration(days: i));
      if (h.isCompletedForDate(d)) {
        streak++;
      } else if (i > 0) {
        break;
      }
    }
    h.currentStreak = streak;
    if (streak > h.bestStreak) h.bestStreak = streak;
  }

  Future<void> deleteHabit(String id) async {
    final idx = _habits.indexWhere((h) => h.id == id);
    if (idx != -1) {
      await _timeAudit?.deleteBySource(TimeEntrySource.habit, id);
    }
    _habits.removeWhere((h) => h.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> updateHabit(String id, Habit updated) async {
    final idx = _habits.indexWhere((h) => h.id == id);
    if (idx != -1) {
      _habits[idx] = updated;
      notifyListeners();
      await _save();
    }
  }

  // --- Heatmap ---

  Map<String, int> combinedHeatmap(int weeks) {
    final data = <String, int>{};
    final now = DateTime.now();
    for (int w = 0; w < weeks; w++) {
      for (int d = 0; d < 7; d++) {
        final date = now.subtract(Duration(days: w * 7 + (6 - d)));
        final key =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        int total = 0;
        int max = 0;
        for (final h in _habits) {
          total += h.completions[key] ?? 0;
          max += h.targetCount;
        }
        data[key] = max > 0 ? ((total / max) * 5).ceil().clamp(1, 5) : 0;
      }
    }
    return data;
  }

  // --- Weekly stats ---

  List<double> last7DaysCompletion() {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      final active = _habits
          .where((h) => h.activeWeekdays.contains(d.weekday - 1))
          .toList();
      if (active.isEmpty) return 0;
      return active.where((h) => h.isCompletedForDate(d)).length /
          active.length;
    });
  }

  // --- Reorder ---

  Future<void> reorder(List<String> orderedIds) async {
    final map = {for (final h in _habits) h.id: h};
    final newList = <Habit>[];
    for (int i = 0; i < orderedIds.length; i++) {
      final h = map[orderedIds[i]];
      if (h != null) {
        h.sortOrder = i;
        newList.add(h);
        map.remove(orderedIds[i]);
      }
    }
    newList.addAll(map.values);
    _habits = newList;
    notifyListeners();
    await _save();
  }
}
