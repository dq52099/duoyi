import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/domain_event_bus.dart';
import '../models/pomodoro.dart';
import '../services/focus_sound_service.dart';
import 'notification_service.dart';
import 'time_audit_provider.dart';

class PomodoroProvider extends ChangeNotifier with WidgetsBindingObserver {
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
  TimeAuditProvider? _timeAudit;

  /// 真实白噪音服务。Task 16 接入：番茄钟状态 ↔ 音频播放。
  final FocusSoundService _sound = FocusSoundService.instance;

  /// 是否监听了 WidgetsBinding 生命周期（保证 `dispose` 时对称移除）。
  bool _lifecycleAttached = false;

  PomodoroState get state => _state;
  PomodoroConfig get config => _config;
  List<PomodoroSession> get sessions => _sessions;
  int get sessionCountToday => _sessionCountToday;

  void attachNotifier(NotificationService n) {
    _notifier = n;
  }

  void attachTimeAudit(TimeAuditProvider provider) {
    _timeAudit = provider;
  }

  /// 由 `main.dart` 在 runApp 之前调用。幂等。
  ///
  /// - 绑定 `WidgetsBindingObserver`，在 `resumed` 时按 `state.isRunning` 恢复
  ///   白噪音播放；在 `paused / inactive` 时按策略保持（Android 前台服务
  ///   由 audioplayers 与 manifest 的 `foregroundServiceType=mediaPlayback`
  ///   保证锁屏不被 kill）。
  void attachLifecycle() {
    if (_lifecycleAttached) return;
    WidgetsBinding.instance.addObserver(this);
    _sound.bindLifecycle(WidgetsBinding.instance);
    _lifecycleAttached = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 回到前台：若番茄钟正在跑 + 已选择白噪音，但服务静音了，补上。
      final expected = _state.whiteNoiseSound;
      if (_state.isRunning && expected != 'none' && !_sound.isPlaying) {
        _sound.play(expected);
      }
    }
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
    _syncSoundToState();
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
    // 300ms 淡出；FocusSoundService.fadeOut 结束后会把 isPlaying 置为 false，
    // 满足 Requirement 5.6（500ms 内静音）。
    // ignore: discarded_futures
    _sound.fadeOut(const Duration(milliseconds: 300));
  }

  /// 依据当前 [_state]（`isRunning`、`type`、`whiteNoiseSound`）与
  /// [_config.playSoundInBreak] 决定播放 / 停止白噪音。
  ///
  /// 调用点：`_startTimer` 与 `_completeSession` 的相位切换后。
  void _syncSoundToState() {
    final sound = _state.whiteNoiseSound;
    final shouldPlay =
        _state.isRunning &&
        sound != 'none' &&
        (_state.type == PomodoroType.focus || _config.playSoundInBreak);
    if (shouldPlay) {
      if (!_sound.isPlaying || _sound.currentSound != sound) {
        // ignore: discarded_futures
        _sound.play(sound);
      }
    } else {
      if (_sound.isPlaying) {
        // ignore: discarded_futures
        _sound.stop();
      }
    }
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
      tag: _state.tag,
    );
    _sessions.add(session);
    _saveSessions();

    if (_state.type == PomodoroType.focus) {
      DomainEventBus.instance.publish(
        DomainEvent(
          type: DomainEventType.pomodoroCompleted,
          objectId: session.id,
          metadata: {'durationSeconds': session.durationSeconds},
        ),
      );
      // ignore: discarded_futures
      _timeAudit?.recordPomodoroSession(
        sessionId: session.id,
        title: session.taskName?.isNotEmpty == true
            ? session.taskName!
            : '番茄专注',
        startAt: session.startTime,
        endAt: session.endTime,
        note: session.whiteNoiseSound == 'none'
            ? ''
            : '白噪音：${session.whiteNoiseSound}',
      );
    }

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
    } else {
      // 本相位不自动续跑：立刻把声音停掉（focus→break 过渡，或已到末尾）。
      // ignore: discarded_futures
      _sound.stop();
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
    // ignore: discarded_futures
    _sound.stop();
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
    // ignore: discarded_futures
    _sound.stop();
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

  void setTag(String? tag) {
    final clean = tag?.trim();
    _state = _state.copyWith(
      tag: clean,
      clearTag: clean == null || clean.isEmpty,
    );
    notifyListeners();
  }

  void setWhiteNoiseSound(String sound) {
    _state = _state.copyWith(whiteNoiseSound: sound);
    _config.whiteNoiseSound = sound;
    _saveConfig();
    notifyListeners();
    _syncSoundToState();
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
    if (_lifecycleAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _lifecycleAttached = false;
    }
    // 不 dispose FocusSoundService（它是进程级单例），只停播。
    // ignore: discarded_futures
    _sound.stop();
    super.dispose();
  }
}
