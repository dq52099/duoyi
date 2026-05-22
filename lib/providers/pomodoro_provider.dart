import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/domain_event_bus.dart';
import '../models/pomodoro.dart';
import '../services/focus_distraction_service.dart';
import '../services/focus_dnd_service.dart';
import '../services/focus_sound_service.dart';
import 'cloud_sync_provider.dart';
import 'notification_service.dart';
import 'time_audit_provider.dart';

class PomodoroProvider extends ChangeNotifier with WidgetsBindingObserver {
  PomodoroState _state = PomodoroState(
    remainingSeconds: 1500,
    totalSeconds: 1500,
    isRunning: false,
    isCountUp: false,
    type: PomodoroType.focus,
    completedSessions: 0,
  );

  PomodoroConfig _config = PomodoroConfig();
  Timer? _timer;
  List<PomodoroSession> _sessions = [];
  List<PomodoroFocusPenalty> _penalties = [];
  int _sessionCountToday = 0;
  String? _lastDate;
  NotificationService? _notifier;
  TimeAuditProvider? _timeAudit;

  /// 真实白噪音服务。Task 16 接入：番茄钟状态 ↔ 音频播放。
  final FocusSoundService _sound = FocusSoundService.instance;
  final FocusDndService _dnd = FocusDndService.instance;
  final FocusDistractionService _distraction = FocusDistractionService.instance;

  /// 是否监听了 WidgetsBinding 生命周期（保证 `dispose` 时对称移除）。
  bool _lifecycleAttached = false;
  FocusDndStatus _dndStatus = const FocusDndStatus.unavailable();
  int? _dndPreviousFilter;
  bool _dndActive = false;
  bool _dndEnableInFlight = false;
  bool _dndRestoreInFlight = false;
  Timer? _distractionTimer;
  FocusDistractionStatus _distractionStatus =
      const FocusDistractionStatus.unavailable();
  String? _lastDistractingPackage;

  PomodoroState get state => _state;
  PomodoroConfig get config => _config;
  List<PomodoroSession> get sessions => _sessions;
  List<PomodoroFocusPenalty> get penalties => List.unmodifiable(_penalties);
  int get sessionCountToday => _sessionCountToday;
  FocusDndStatus get focusDndStatus => _dndStatus;
  bool get focusDndActive => _dndActive;
  FocusDistractionStatus get focusDistractionStatus => _distractionStatus;

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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _recordStrictFocusPenalty(FocusPenaltyReason.leaveApp);
    }
    if (state == AppLifecycleState.resumed) {
      // 回到前台：若番茄钟正在跑 + 已选择白噪音，但服务静音了，补上。
      final expected = _state.whiteNoiseSound;
      if (_state.isRunning && expected != 'none' && !_sound.isPlaying) {
        _sound.play(expected);
      }
      if (_config.autoEnableDnd) {
        // ignore: discarded_futures
        refreshFocusDndStatus();
        _syncDndToState();
      }
      if (_config.monitorDistractingApps) {
        // ignore: discarded_futures
        refreshFocusDistractionStatus();
        _syncDistractionMonitorToState();
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

    final penaltiesData = prefs.getString('pomodoro_focus_penalties');
    if (penaltiesData != null) {
      _penalties = (json.decode(penaltiesData) as List)
          .whereType<Map>()
          .map((e) => PomodoroFocusPenalty.fromJson(Map.from(e)))
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
      isCountUp: false,
      type: PomodoroType.focus,
      completedSessions: 0,
      whiteNoiseSound: _config.whiteNoiseSound,
      focusRoomId: _config.focusRoomId,
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

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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

  Future<void> _savePenalties() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'pomodoro_focus_penalties',
      json.encode(_penalties.map((e) => e.toJson()).toList()),
    );
  }

  Future<bool> deleteSession(String id) async {
    final idx = _sessions.indexWhere((s) => s.id == id);
    if (idx < 0) return false;

    final removed = _sessions.removeAt(idx);
    await CloudSyncProvider.recordDeletedItem('pomodoro_sessions', removed.id);
    if (removed.type == PomodoroType.focus &&
        _isSameDay(removed.startTime, DateTime.now())) {
      await _refreshTodayFocusMeta();
    }

    await _timeAudit?.deleteByDedupeKey(
      TimeAuditProvider.pomodoroDedupeKey(id),
    );
    await _saveSessions();
    notifyListeners();
    return true;
  }

  Future<bool> updateSession(PomodoroSession updated) async {
    final idx = _sessions.indexWhere((s) => s.id == updated.id);
    if (idx < 0) return false;

    final previous = _sessions[idx];
    _sessions[idx] = updated;
    if (_affectsTodayFocusCount(previous) || _affectsTodayFocusCount(updated)) {
      await _refreshTodayFocusMeta();
    }

    final dedupeKey = TimeAuditProvider.pomodoroDedupeKey(updated.id);
    if (updated.type == PomodoroType.focus) {
      await _timeAudit?.recordPomodoroSession(
        sessionId: updated.id,
        title: updated.taskName?.isNotEmpty == true
            ? updated.taskName!
            : '番茄专注',
        startAt: updated.startTime,
        endAt: updated.endTime,
        note: updated.whiteNoiseSound == 'none'
            ? ''
            : '白噪音：${updated.whiteNoiseSound}',
      );
    } else {
      await _timeAudit?.deleteByDedupeKey(dedupeKey);
    }

    await _saveSessions();
    notifyListeners();
    return true;
  }

  bool _affectsTodayFocusCount(PomodoroSession session) {
    return session.type == PomodoroType.focus &&
        _isSameDay(session.startTime, DateTime.now());
  }

  Future<void> _refreshTodayFocusMeta() async {
    final now = DateTime.now();
    _sessionCountToday = _sessions
        .where(
          (s) => s.type == PomodoroType.focus && _isSameDay(s.startTime, now),
        )
        .length;
    _lastDate = _todayKey();
    await _saveMeta();
  }

  // --- Timer controls ---

  void toggleTimer() {
    if (_state.isRunning) {
      _recordStrictFocusPenalty(FocusPenaltyReason.pause);
      _pauseTimer();
    } else {
      _startTimer();
    }
  }

  void _startTimer() {
    _state = _state.copyWith(isRunning: true);
    notifyListeners();
    _syncSoundToState();
    _syncDndToState();
    _syncDistractionMonitorToState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state.isCountUp) {
        _state = _state.copyWith(remainingSeconds: _state.remainingSeconds + 1);
        notifyListeners();
        return;
      }
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
    _syncDndToState();
    _syncDistractionMonitorToState();
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
    final durationSeconds = _state.isCountUp
        ? _state.remainingSeconds.clamp(1, 24 * 60 * 60)
        : _state.totalSeconds;
    final session = PomodoroSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      startTime: DateTime.now().subtract(Duration(seconds: durationSeconds)),
      endTime: DateTime.now(),
      durationSeconds: durationSeconds,
      type: _state.type,
      taskName: _state.taskName,
      whiteNoiseSound: _state.whiteNoiseSound,
      tag: _state.tag,
      focusRoomId: _state.focusRoomId,
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

    if (_state.isCountUp) {
      _state = _state.copyWith(
        remainingSeconds: 0,
        totalSeconds: 0,
        isRunning: false,
        isCountUp: true,
        type: PomodoroType.focus,
        completedSessions: newCount,
      );
    } else {
      _state = _state.copyWith(
        remainingSeconds: nextDuration,
        totalSeconds: nextDuration,
        isRunning: _config.autoStartBreaks || _config.autoStartFocus,
        type: nextType,
        completedSessions: newCount,
      );
    }

    if (_state.isRunning) {
      _startTimer();
    } else {
      // 本相位不自动续跑：立刻把声音停掉（focus→break 过渡，或已到末尾）。
      // ignore: discarded_futures
      _sound.stop();
      _syncDndToState();
      _syncDistractionMonitorToState();
    }
    notifyListeners();
  }

  void skipSession() {
    _timer?.cancel();
    _recordStrictFocusPenalty(FocusPenaltyReason.skip);
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
    _syncDndToState();
    _syncDistractionMonitorToState();
    notifyListeners();
  }

  void resetTimer() {
    _timer?.cancel();
    _recordStrictFocusPenalty(FocusPenaltyReason.reset);
    _state = _state.copyWith(
      remainingSeconds: _state.isCountUp ? 0 : _config.focusDuration,
      totalSeconds: _state.isCountUp ? 0 : _config.focusDuration,
      isRunning: false,
      type: PomodoroType.focus,
      completedSessions: 0,
    );
    // ignore: discarded_futures
    _sound.stop();
    _syncDndToState();
    _syncDistractionMonitorToState();
    notifyListeners();
  }

  void finishCurrentSession() {
    if (_state.type != PomodoroType.focus) return;
    if (_state.isCountUp && !_state.isRunning && _state.remainingSeconds <= 0) {
      return;
    }
    _completeSession();
  }

  void setCountUpMode(bool enabled) {
    if (_state.isRunning) return;
    _timer?.cancel();
    _state = _state.copyWith(
      remainingSeconds: enabled ? 0 : _config.focusDuration,
      totalSeconds: enabled ? 0 : _config.focusDuration,
      isRunning: false,
      isCountUp: enabled,
      type: PomodoroType.focus,
    );
    // ignore: discarded_futures
    _sound.stop();
    _syncDndToState();
    _syncDistractionMonitorToState();
    notifyListeners();
  }

  // --- Config ---

  Future<void> setConfig(PomodoroConfig cfg) async {
    _config = cfg;
    await _saveConfig();
    if (!_state.isRunning) {
      _state = _state.copyWith(
        remainingSeconds: _state.isCountUp ? 0 : cfg.focusDuration,
        totalSeconds: _state.isCountUp ? 0 : cfg.focusDuration,
        whiteNoiseSound: cfg.whiteNoiseSound,
        focusRoomId: cfg.focusRoomId,
      );
    }
    notifyListeners();
    _syncDndToState();
    _syncDistractionMonitorToState();
  }

  Future<void> setAutoEnableDnd(bool enabled) async {
    if (_config.autoEnableDnd == enabled) return;
    _config.autoEnableDnd = enabled;
    await _saveConfig();
    if (enabled) {
      await refreshFocusDndStatus();
    } else {
      await _restoreFocusDndIfNeeded();
    }
    notifyListeners();
    _syncDndToState();
  }

  Future<void> setStrictFocusMode(bool enabled) async {
    if (_config.strictFocusMode == enabled) return;
    _config.strictFocusMode = enabled;
    await _saveConfig();
    notifyListeners();
    _syncDistractionMonitorToState();
  }

  Future<FocusDndStatus> refreshFocusDndStatus() async {
    _dndStatus = await _dnd.getStatus();
    notifyListeners();
    return _dndStatus;
  }

  Future<bool> openFocusDndSettings() => _dnd.openPolicyAccessSettings();

  bool get _shouldEnableDnd =>
      _config.autoEnableDnd &&
      _state.isRunning &&
      _state.type == PomodoroType.focus;

  void _syncDndToState() {
    if (_shouldEnableDnd) {
      if (!_dndActive && !_dndEnableInFlight) {
        // ignore: discarded_futures
        _enableFocusDndIfPossible();
      }
      return;
    }
    if ((_dndActive || _dndPreviousFilter != null) && !_dndRestoreInFlight) {
      // ignore: discarded_futures
      _restoreFocusDndIfNeeded();
    }
  }

  Future<void> _enableFocusDndIfPossible() async {
    _dndEnableInFlight = true;
    try {
      final status = await _dnd.getStatus();
      _dndStatus = status;
      if (!_shouldEnableDnd || !status.supported || !status.accessGranted) {
        notifyListeners();
        return;
      }

      final result = await _dnd.enable();
      if (result.enabled) {
        _dndPreviousFilter ??= result.previousFilter;
        _dndActive = true;
        _dndStatus = FocusDndStatus(
          supported: true,
          accessGranted: true,
          currentFilter: result.currentFilter,
        );
      }
      if (!_shouldEnableDnd) {
        await _restoreFocusDndIfNeeded();
      }
      notifyListeners();
    } finally {
      _dndEnableInFlight = false;
    }
  }

  Future<void> _restoreFocusDndIfNeeded({bool notify = true}) async {
    if (_dndRestoreInFlight) return;
    final previous = _dndPreviousFilter;
    if (previous == null) {
      _dndActive = false;
      return;
    }
    _dndRestoreInFlight = true;
    _dndPreviousFilter = null;
    _dndActive = false;
    try {
      await _dnd.restore(previous);
      _dndStatus = await _dnd.getStatus();
      if (notify) notifyListeners();
    } finally {
      _dndRestoreInFlight = false;
    }
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

  void setFocusRoomId(String? roomId) {
    final clean = roomId?.trim();
    _config.focusRoomId = clean?.isEmpty == true ? null : clean;
    _state = _state.copyWith(
      focusRoomId: _config.focusRoomId,
      clearFocusRoom: _config.focusRoomId == null,
    );
    _saveConfig();
    notifyListeners();
  }

  Future<void> refreshFocusDistractionStatus() async {
    _distractionStatus = await _distraction.getStatus();
    notifyListeners();
  }

  Future<bool> openFocusUsageAccessSettings() {
    return _distraction.openUsageAccessSettings();
  }

  Future<bool> openFocusAccessibilitySettings() {
    return _distraction.openAccessibilitySettings();
  }

  void setMonitorDistractingApps(bool enabled) {
    if (_config.monitorDistractingApps == enabled) return;
    _config.monitorDistractingApps = enabled;
    _saveConfig();
    notifyListeners();
    // ignore: discarded_futures
    refreshFocusDistractionStatus();
    _syncDistractionMonitorToState();
  }

  void setDistractingAppPackages(List<String> packages) {
    final normalized =
        packages
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    _config.distractingAppPackages = normalized;
    _saveConfig();
    notifyListeners();
    _syncDistractionMonitorToState();
  }

  void setWhiteNoiseSound(String sound) {
    _state = _state.copyWith(whiteNoiseSound: sound);
    _config.whiteNoiseSound = sound;
    _saveConfig();
    notifyListeners();
    _syncSoundToState();
  }

  void recordFocusLeaveAppPenalty() {
    _recordStrictFocusPenalty(FocusPenaltyReason.leaveApp);
  }

  void _recordStrictFocusPenalty(
    FocusPenaltyReason reason, {
    String? appPackage,
  }) {
    if (!_config.strictFocusMode ||
        !_state.isRunning ||
        _state.type != PomodoroType.focus) {
      return;
    }
    final now = DateTime.now();
    final affectedSeconds =
        (_state.isCountUp
                ? _state.remainingSeconds.clamp(1, 24 * 60 * 60)
                : (_state.totalSeconds - _state.remainingSeconds).clamp(
                    1,
                    _state.totalSeconds,
                  ))
            .toInt();
    final penalty = PomodoroFocusPenalty(
      id: '${now.microsecondsSinceEpoch}_${reason.key}',
      occurredAt: now,
      reason: reason,
      affectedSeconds: affectedSeconds,
      taskName: _state.taskName,
      tag: _state.tag,
      focusRoomId: _state.focusRoomId,
      appPackage: appPackage,
    );
    _penalties = [penalty, ..._penalties].take(100).toList();
    _savePenalties();
    notifyListeners();
  }

  void _syncDistractionMonitorToState() {
    final shouldMonitor =
        _config.strictFocusMode &&
        _config.monitorDistractingApps &&
        _state.isRunning &&
        _state.type == PomodoroType.focus &&
        _config.distractingAppPackages.isNotEmpty;
    if (!shouldMonitor) {
      _distractionTimer?.cancel();
      _distractionTimer = null;
      _lastDistractingPackage = null;
      // ignore: discarded_futures
      _distraction.setFocusBlocker(enabled: false, packages: const []);
      return;
    }
    // ignore: discarded_futures
    _distraction.setFocusBlocker(
      enabled: true,
      packages: _config.distractingAppPackages,
    );
    _distractionTimer ??= Timer.periodic(
      const Duration(seconds: 20),
      (_) => _checkDistractingForegroundApp(),
    );
    // ignore: discarded_futures
    _checkDistractingForegroundApp();
  }

  Future<void> _checkDistractingForegroundApp() async {
    if (!_config.strictFocusMode ||
        !_config.monitorDistractingApps ||
        !_state.isRunning ||
        _state.type != PomodoroType.focus) {
      return;
    }
    final packageName = await _distraction.getForegroundApp();
    if (packageName == null || packageName.isEmpty) return;
    _distractionStatus = FocusDistractionStatus(
      supported: true,
      accessGranted: true,
      foregroundPackage: packageName,
    );
    if (!_config.distractingAppPackages.contains(packageName)) {
      _lastDistractingPackage = null;
      notifyListeners();
      return;
    }
    if (_lastDistractingPackage == packageName) return;
    _lastDistractingPackage = packageName;
    _recordStrictFocusPenalty(
      FocusPenaltyReason.distractingApp,
      appPackage: packageName,
    );
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

  List<PomodoroFocusPenalty> get todayPenalties {
    final now = DateTime.now();
    return _penalties
        .where((p) => _isSameDay(p.occurredAt, now))
        .toList(growable: false);
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
    // ignore: discarded_futures
    _restoreFocusDndIfNeeded(notify: false);
    _distractionTimer?.cancel();
    super.dispose();
  }
}
