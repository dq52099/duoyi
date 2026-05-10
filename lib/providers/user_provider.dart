import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';

class UserProvider extends ChangeNotifier {
  UserProfile _profile = UserProfile();

  UserProfile get profile => _profile;

  /// Rebuild stats from data providers (called by MainShell periodically)
  void recalc({
    int completedTodos = 0,
    int totalFocusMinutes = 0,
    int currentStreak = 0,
    int bestStreak = 0,
  }) {
    final unchanged =
        _profile.totalTodosCompleted == completedTodos &&
        _profile.totalFocusMinutes == totalFocusMinutes &&
        _profile.currentStreak == currentStreak &&
        _profile.bestStreak == bestStreak;
    if (unchanged) return;

    _profile.totalTodosCompleted = completedTodos;
    _profile.totalFocusMinutes = totalFocusMinutes;
    _profile.currentStreak = currentStreak;
    _profile.bestStreak = bestStreak;
    _notifyListenersSafely();
  }

  void _notifyListenersSafely() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (hasListeners) notifyListeners();
      });
      return;
    }
    notifyListeners();
  }

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('user_profile');
    if (data != null) {
      _profile = UserProfile.fromJson(json.decode(data));
      notifyListeners();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_profile', json.encode(_profile.toJson()));
  }

  Future<void> setUsername(String name) async {
    _profile.username = name;
    _profile.avatarInitials = name.isNotEmpty ? name[0] : '我';
    notifyListeners();
    await _save();
  }

  void updateLastSyncTime(DateTime time) {
    _profile.lastSyncTime = time;
    notifyListeners();
  }
}
