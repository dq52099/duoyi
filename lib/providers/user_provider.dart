import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';

class UserProvider extends ChangeNotifier {
  UserProfile _profile = UserProfile();
  int _storageGeneration = 0;

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
    _profile.updatedAt = DateTime.now();
    // ignore: discarded_futures
    _saveThenNotifySafely();
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
    final generation = _storageGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration) return;
    final data = prefs.getString('user_profile');
    if (data != null) {
      _profile = UserProfile.fromJson(json.decode(data));
    } else {
      _profile = UserProfile();
    }
    notifyListeners();
  }

  void resetLocalState() {
    _storageGeneration++;
    _profile = UserProfile();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_profile', json.encode(_profile.toJson()));
  }

  Future<void> _saveThenNotifySafely() async {
    await _save();
    _notifyListenersSafely();
  }

  Future<void> updateProfile({
    required String username,
    String? avatarInitials,
    String? displayName,
    String? email,
    bool? emailVerified,
    String? avatarUrl,
    String? bio,
  }) async {
    await _writeProfile(
      username: username,
      avatarInitials: avatarInitials,
      displayName: displayName,
      email: email,
      emailVerified: emailVerified,
      avatarUrl: avatarUrl,
      bio: bio,
      touchUpdatedAt: true,
    );
  }

  Future<void> applyAccountSnapshot({
    required String username,
    String? avatarInitials,
    String? displayName,
    String? email,
    bool? emailVerified,
    String? avatarUrl,
    String? bio,
  }) async {
    await _writeProfile(
      username: username,
      avatarInitials: avatarInitials,
      displayName: displayName,
      email: email,
      emailVerified: emailVerified,
      avatarUrl: avatarUrl,
      bio: bio,
      touchUpdatedAt: false,
    );
  }

  Future<void> _writeProfile({
    required String username,
    String? avatarInitials,
    String? displayName,
    String? email,
    bool? emailVerified,
    String? avatarUrl,
    String? bio,
    required bool touchUpdatedAt,
  }) async {
    final cleanName = username.trim().isEmpty ? '用户' : username.trim();
    final cleanInitials = (avatarInitials ?? '').trim();
    _profile.username = cleanName;
    _profile.avatarInitials = cleanInitials.isNotEmpty
        ? _firstCodePoint(cleanInitials)
        : _firstCodePoint(cleanName);
    if (displayName != null) {
      _profile.displayName = displayName.trim();
    }
    if (email != null) {
      _profile.email = email.trim();
    }
    if (emailVerified != null) {
      _profile.emailVerified = emailVerified;
    }
    if (avatarUrl != null) {
      _profile.avatarUrl = avatarUrl.trim();
    }
    if (bio != null) {
      _profile.bio = bio.trim();
    }
    if (touchUpdatedAt || _profile.updatedAt == null) {
      _profile.updatedAt = DateTime.now();
    }
    await _save();
    notifyListeners();
  }

  Future<void> clearAccountProfileCache() async {
    _profile.username = '用户';
    _profile.avatarInitials = _firstCodePoint(_profile.username);
    _profile.displayName = '';
    _profile.email = '';
    _profile.emailVerified = false;
    _profile.avatarUrl = '';
    _profile.bio = '';
    _profile.updatedAt = DateTime.now();
    await _save();
    notifyListeners();
  }

  Future<void> setUsername(String name) async {
    await updateProfile(username: name);
  }

  void updateLastSyncTime(DateTime time) {
    _profile.lastSyncTime = time;
    // ignore: discarded_futures
    _saveThenNotifySafely();
  }

  String _firstCodePoint(String value) {
    return String.fromCharCode(value.runes.first);
  }
}
