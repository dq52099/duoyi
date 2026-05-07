import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/goal.dart';

class GoalProvider extends ChangeNotifier {
  static const _key = 'duoyi_goals';
  List<GoalItem> _goals = [];

  List<GoalItem> get goals {
    final sorted = [..._goals];
    sorted.sort((a, b) {
      // 进行中 > 已完成 > 暂停 > 放弃
      int statusRank(g) => switch (g.status) {
            GoalStatus.active => 0,
            GoalStatus.paused => 2,
            GoalStatus.achieved => 1,
            GoalStatus.abandoned => 3,
          };
      final s = statusRank(a).compareTo(statusRank(b));
      if (s != 0) return s;
      return a.sortOrder.compareTo(b.sortOrder);
    });
    return List.unmodifiable(sorted);
  }

  List<GoalItem> get activeGoals =>
      _goals.where((g) => g.status == GoalStatus.active).toList();

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    _goals = raw.map((e) => GoalItem.fromJson(jsonDecode(e))).toList();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _key, _goals.map((e) => jsonEncode(e.toJson())).toList());
    notifyListeners();
  }

  Future<void> add(GoalItem goal) async {
    _goals.add(goal);
    await _save();
  }

  Future<void> update(GoalItem goal) async {
    final idx = _goals.indexWhere((g) => g.id == goal.id);
    if (idx != -1) {
      goal.updatedAt = DateTime.now();
      _goals[idx] = goal;
      await _save();
    }
  }

  Future<void> delete(String id) async {
    _goals.removeWhere((g) => g.id == id);
    await _save();
  }

  Future<void> setStatus(String id, GoalStatus status) async {
    final idx = _goals.indexWhere((g) => g.id == id);
    if (idx != -1) {
      _goals[idx].status = status;
      if (status == GoalStatus.achieved) _goals[idx].progress = 1.0;
      _goals[idx].updatedAt = DateTime.now();
      await _save();
    }
  }

  Future<void> toggleMilestone(String goalId, String milestoneId) async {
    final idx = _goals.indexWhere((g) => g.id == goalId);
    if (idx != -1) {
      final m = _goals[idx].milestones.firstWhere(
            (x) => x.id == milestoneId,
            orElse: () => _goals[idx].milestones.first,
          );
      m.isCompleted = !m.isCompleted;
      m.completedAt = m.isCompleted ? DateTime.now() : null;
      _goals[idx].updatedAt = DateTime.now();

      // 自动完成目标
      if (_goals[idx].autoProgress &&
          _goals[idx].milestones.isNotEmpty &&
          _goals[idx].milestones.every((x) => x.isCompleted) &&
          _goals[idx].status == GoalStatus.active) {
        _goals[idx].status = GoalStatus.achieved;
        _goals[idx].progress = 1.0;
      } else if (_goals[idx].status == GoalStatus.achieved &&
          !m.isCompleted &&
          _goals[idx].autoProgress) {
        _goals[idx].status = GoalStatus.active;
      }
      await _save();
    }
  }

  Future<void> addMilestone(String goalId, String title) async {
    final idx = _goals.indexWhere((g) => g.id == goalId);
    if (idx != -1) {
      _goals[idx].milestones.add(GoalMilestone(title: title));
      _goals[idx].updatedAt = DateTime.now();
      await _save();
    }
  }

  Future<void> removeMilestone(String goalId, String milestoneId) async {
    final idx = _goals.indexWhere((g) => g.id == goalId);
    if (idx != -1) {
      _goals[idx].milestones.removeWhere((m) => m.id == milestoneId);
      _goals[idx].updatedAt = DateTime.now();
      await _save();
    }
  }

  Future<void> setManualProgress(String goalId, double progress) async {
    final idx = _goals.indexWhere((g) => g.id == goalId);
    if (idx != -1) {
      _goals[idx].autoProgress = false;
      _goals[idx].progress = progress.clamp(0.0, 1.0);
      _goals[idx].updatedAt = DateTime.now();
      if (_goals[idx].progress >= 1.0) {
        _goals[idx].status = GoalStatus.achieved;
      }
      await _save();
    }
  }
}
