import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pomodoro.dart';
import 'notification_service.dart';

class PomodoroProvider extends ChangeNotifier {
  PomodoroState _state = PomodoroState(
    remainingSeconds: 1500,
    totalSeconds: 1500,
    isRunning: false,
    type: PomodoroType.focus,
    completedSessions: 0,
  );

  PomodoroConfig _config = PomodoroConfig();
  Timer? _timer;
  List<PomodoroSession> _sessions = [];
  int _sessionCountToday = 0;
  String? _lastDate;
  NotificationService? _notifier;

  PomodoroState get state => _state;
  PomodoroConfig get config => _config;
  List<PomodoroSession> get sessions => _sessions;
  int get sessionCountToday => _sessionCountToday;

  void attachNotifier(NotificationService n) {
    _notifier = n;
  }

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();

    final configData = prefs.getString('pomodoro_config');
    if (configData != null) {
      _config = PomodoroConfig.fromJson(json.decode(configData));
    }

    final sessionsData = prefs.getString('pomodoro_sessions');
    if (sessionsData != null) {
      _sessions = (json.decode(sessionsData) as List)
          .map((e) => PomodoroSession.fromJson(e))
          .toList();
    }

    _sessionCountToday = prefs.getInt('pomodoro_count_today') ?? 0;
    _lastDate = prefs.getString('pomodoro_last_date');
    _checkDayReset();
    _initState();
    notifyListeners();
  }

  void _initState() {
    _state = PomodoroState(
      remainingSeconds: _config.focusDuration,
      totalSeconds: _config.focusDuration,
      isRunning: false,
      type: PomodoroType.focus,
      completedSessions: 0,
      whiteNoiseSound: _config.whiteNoiseSound,
    );
  }

  void _checkDayReset() {
    final today = _todayKey();
    if (_lastDate != today) {
      _sessionCountToday = 0;
      _lastDate = today;
      _saveMeta();
    }
  }

  String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  Future<void> _saveMeta() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pomodoro_count_today', _sessionCountToday);
    await prefs.setString('pomodoro_last_date', _lastDate!);
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pomodoro_config', json.encode(_config.toJson()));
  }

  Future<void> _saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'pomodoro_sessions',
      json.encode(_sessions.map((e) => e.toJson()).toList()),
    );
  }

  // --- Timer controls ---

  void toggleTimer() {
    if (_state.isRunning) {
      _pauseTimer();
    } else {
      _startTimer();
    }
  }

  void _startTimer() {
    _state = _state.copyWith(isRunning: true);
    notifyListeners();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state.remainingSeconds <= 1) {
        _completeSession();
        return;
      }
      _state = _state.copyWith(remainingSeconds: _state.remainingSeconds - 1);
      notifyListeners();
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
    _state = _state.copyWith(isRunning: false);
    notifyListeners();
  }

  void _completeSession() {
    _timer?.cancel();
    final session = PomodoroSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      startTime: DateTime.now().subtract(
        Duration(seconds: _state.totalSeconds),
      ),
      endTime: DateTime.now(),
      durationSeconds: _state.totalSeconds,
      type: _state.type,
      taskName: _state.taskName,
      whiteNoiseSound: _state.whiteNoiseSound,
    );
    _sessions.add(session);
    _saveSessions();

    // Fire desktop notification
    if (_state.type == PomodoroType.focus) {
      _notifier?.notifyPomodoroComplete(taskName: _state.taskName);
    } else {
      _notifier?.notifyBreakComplete();
    }

    int newCount = _state.completedSessions;
    if (_state.type == PomodoroType.focus) {
      newCount++;
      _sessionCountToday++;
      _saveMeta();
    }

    PomodoroType nextType;
    int nextDuration;
    if (_state.type == PomodoroType.focus) {
      if (newCount % _config.sessionsPerLongBreak == 0) {
        nextType = PomodoroType.longBreak;
        nextDuration = _config.longBreakDuration;
      } else {
        nextType = PomodoroType.shortBreak;
        nextDuration = _config.shortBreakDuration;
      }
    } else {
      nextType = PomodoroType.focus;
      nextDuration = _config.focusDuration;
    }

    _state = _state.copyWith(
      remainingSeconds: nextDuration,
      totalSeconds: nextDuration,
      isRunning: _config.autoStartBreaks || _config.autoStartFocus,
      type: nextType,
      completedSessions: newCount,
    );

    if (_state.isRunning) {
      _startTimer();
    }
    notifyListeners();
  }

  void skipSession() {
    _timer?.cancel();
    if (_state.type == PomodoroType.focus) {
      _state = _state.copyWith(
        remainingSeconds: _config.shortBreakDuration,
        totalSeconds: _config.shortBreakDuration,
        isRunning: false,
        type: PomodoroType.shortBreak,
      );
    } else {
      _state = _state.copyWith(
        remainingSeconds: _config.focusDuration,
        totalSeconds: _config.focusDuration,
        isRunning: false,
        type: PomodoroType.focus,
      );
    }
    notifyListeners();
  }

  void resetTimer() {
    _timer?.cancel();
    _state = _state.copyWith(
      remainingSeconds: _config.focusDuration,
      totalSeconds: _config.focusDuration,
      isRunning: false,
      type: PomodoroType.focus,
      completedSessions: 0,
    );
    notifyListeners();
  }

  // --- Config ---

  Future<void> setConfig(PomodoroConfig cfg) async {
    _config = cfg;
    await _saveConfig();
    if (!_state.isRunning) {
      _state = _state.copyWith(
        remainingSeconds: cfg.focusDuration,
        totalSeconds: cfg.focusDuration,
        whiteNoiseSound: cfg.whiteNoiseSound,
      );
    }
    notifyListeners();
  }

  void setTaskName(String? name) {
    _state = _state.copyWith(taskName: name, clearTaskName: name == null);
    notifyListeners();
  }

  void setWhiteNoiseSound(String sound) {
    _state = _state.copyWith(whiteNoiseSound: sound);
    _config.whiteNoiseSound = sound;
    _saveConfig();
    notifyListeners();
  }

  // --- Queries ---

  List<PomodoroSession> getSessionsForDateRange(DateTime start, DateTime end) {
    return _sessions
        .where(
          (s) =>
              s.type == PomodoroType.focus &&
              s.startTime.isAfter(start) &&
              s.startTime.isBefore(end),
        )
        .toList();
  }

  List<PomodoroSession> get todayFocusSessions {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return getSessionsForDateRange(start, now.add(const Duration(days: 1)));
  }

  int get totalFocusMinutes {
    return _sessions
            .where((s) => s.type == PomodoroType.focus)
            .fold(0, (sum, s) => sum + s.durationSeconds) ~/
        60;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
