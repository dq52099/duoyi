import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../core/domain_event_bus.dart';
import '../core/account_preference_writes.dart';
import '../core/focus_sound_catalog.dart';
import '../models/pomodoro.dart';
import '../services/focus_distraction_service.dart';
import '../services/focus_dnd_service.dart';
import '../services/focus_sound_service.dart';
import '../services/account_local_data_cleaner.dart';
import 'cloud_sync_provider.dart';
import 'auth_provider.dart';
import 'preferences_provider.dart';
import 'notification_service.dart';
import 'time_audit_provider.dart';

class PomodoroProvider extends ChangeNotifier with WidgetsBindingObserver {
  /// 运行态快照的持久化键：进程被杀重启后据此恢复进行中的专注。
  /// Android 小组件的 `focus_timer_ends_at_millis` 与 `endsAtMs` 同源。
  static const String runningSnapshotKey = 'pomodoro_running_snapshot';
  static const String dailyFocusGoalPrefsKey = 'pomodoro_daily_goal_minutes';
  static const int defaultDailyFocusGoalMinutes = 120;
  static const String ambientMixerPrefsKey = 'pomodoro_ambient_mixer_v1';
  static const int maxAmbientMixerTracks = 4;

  PomodoroState _state = PomodoroState(
    remainingSeconds: 1500,
    totalSeconds: 1500,
    isRunning: false,
    isCountUp: false,
    type: PomodoroType.focus,
    completedSessions: 0,
  );

  PomodoroConfig _config = PomodoroConfig();
  Future<void>? _configWriteTail;
  PreferencesProvider? _preferences;
  AuthProvider? _preferencesAuth;
  int _defaultFocusMinutes = 25;
  int _dailyFocusGoalMinutes = defaultDailyFocusGoalMinutes;
  Map<String, double> _ambientMixerTracks = <String, double>{};
  final Map<String, AudioPlayer> _extraMixerPlayers = <String, AudioPlayer>{};
  bool _mixerAuditionActive = false;
  bool _focusDraftPrepared = true;
  Timer? _timer;
  final ValueNotifier<int> _timerTicks = ValueNotifier<int>(0);
  List<PomodoroSession> _sessions = [];
  List<PomodoroFocusPenalty> _penalties = [];
  int _persistedRevision = 0;
  int _storageGeneration = 0;
  int _runtimeRevision = 0;
  bool _runningSnapshotHydrated = false;
  int? _runningAccountGeneration;
  int _sessionCountToday = 0;
  int _mineWeeklyFocusMinutes = 0;
  DateTime? _mineWeeklyFocusComputedAt;
  String? _lastDate;
  NotificationService? _notifier;
  TimeAuditProvider? _timeAudit;

  /// 运行态时间锚点（epoch ms）：倒计时 = 预计结束时刻 `endsAt`，
  /// 正计时 = 本次累计的开始时刻。暂停/停止/完成/重置后置空。
  int? _activeAnchorMs;
  String? _activeSessionId;
  Timer? _snapshotClearRetryTimer;

  /// 上次写入的快照 payload（去重：锚点不变时 tick 重复调用零成本跳过）。
  String? _lastSnapshotPayload;
  String? _pendingSnapshotPayload;
  int _snapshotRevision = 0;

  /// 快照落盘串行队列：完成旧相位（删）与续跑新相位（写）在同一帧发生，
  /// 按入队顺序 drain 保证 remove 先于新 setString 落盘。不用 Future 链——
  /// 链首 future 的回调会固定在其创建 zone 调度，fakeAsync 测试驱动不到。
  final List<Future<void> Function()> _snapshotOps = [];
  bool _snapshotDraining = false;
  Completer<void>? _snapshotDrainCompleter;
  bool _snapshotWritesSucceeded = true;
  bool _disposed = false;

  /// 真实白噪音服务。Task 16 接入：番茄钟状态 ↔ 音频播放。
  final FocusSoundService _sound = FocusSoundService.instance;
  final FocusDndService _dnd = FocusDndService.instance;
  final FocusDistractionService _distraction = FocusDistractionService.instance;

  /// 是否监听了 WidgetsBinding 生命周期（保证 `dispose` 时对称移除）。
  bool _lifecycleAttached = false;
  FocusDndStatus _dndStatus = const FocusDndStatus.unavailable();
  int? _dndPreviousFilter;
  int? _dndPendingRestoreFilter;
  bool _dndActive = false;
  bool _dndEnableInFlight = false;
  bool _dndRestoreInFlight = false;
  Future<void>? _dndOperationTail;
  Timer? _distractionTimer;
  FocusDistractionStatus _distractionStatus =
      const FocusDistractionStatus.unavailable();
  String? _lastDistractingPackage;

  PomodoroProvider() {
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _syncPreferenceDefault,
    );
  }

  PomodoroState get state => _state;
  int get focusTimerEndsAtMillis =>
      _state.isRunning && !_state.isCountUp ? _activeAnchorMs ?? 0 : 0;
  int get focusTimerStartedAtMillis =>
      _state.isRunning && _state.isCountUp ? _activeAnchorMs ?? 0 : 0;
  PomodoroConfig get config => _config;
  int get defaultFocusMinutes => _defaultFocusMinutes;
  int get effectiveFocusDuration => _config.focusDurationUsesDefault
      ? _defaultFocusMinutes * 60
      : _config.focusDuration;

  /// Preference observation is read-only; mode changes are explicit writes.
  void attachPreferences(
    PreferencesProvider preferences, {
    AuthProvider? auth,
  }) {
    _preferences?.removeListener(_syncPreferenceDefault);
    _preferencesAuth?.removeListener(_syncPreferenceDefault);
    _preferences = preferences;
    _preferencesAuth = auth;
    preferences.addListener(_syncPreferenceDefault);
    auth?.addListener(_syncPreferenceDefault);
    _syncPreferenceDefault();
  }

  void _syncPreferenceDefault() {
    final preferences = _preferences;
    if (_disposed || preferences == null) return;
    // An unhydrated or invalidated source cannot own a previous account's
    // default. Only an untouched draft is refreshed; active phases keep time.
    if (!preferences.isStorageLoaded) {
      if (_defaultFocusMinutes != 25) {
        _defaultFocusMinutes = 25;
        _refreshPreparedFocus();
        notifyListeners();
      }
      return;
    }
    if (AccountPreferenceWrites.isBoundaryActive ||
        _preferencesAuth?.isAccountTransitionInProgress == true ||
        _preferencesAuth?.isLocalAccountDataBlocked == true) {
      return;
    }
    final minutes = preferences.defaultPomodoroMinutes.clamp(5, 180);
    if (minutes == _defaultFocusMinutes) return;
    _defaultFocusMinutes = minutes;
    _refreshPreparedFocus();
    notifyListeners();
  }

  bool _refreshPreparedFocus() {
    if (!_focusDraftPrepared ||
        _state.isRunning ||
        _state.isCountUp ||
        _state.type != PomodoroType.focus) {
      return false;
    }
    final duration = effectiveFocusDuration;
    if (_state.totalSeconds == duration &&
        _state.remainingSeconds == duration) {
      return false;
    }
    _state = _state.copyWith(
      totalSeconds: duration,
      remainingSeconds: duration,
    );
    return true;
  }

  List<PomodoroSession> get sessions => _sessions;
  List<PomodoroFocusPenalty> get penalties => List.unmodifiable(_penalties);
  int get persistedRevision => _persistedRevision;
  int get storageGeneration => _storageGeneration;
  int get sessionCountToday => _sessionCountToday;
  int get mineWeeklyFocusMinutes {
    final computedAt = _mineWeeklyFocusComputedAt;
    if (computedAt == null ||
        clock.now().difference(computedAt) >= const Duration(minutes: 15)) {
      _recomputeMineWeeklyFocus();
    }
    return _mineWeeklyFocusMinutes;
  }

  FocusDndStatus get focusDndStatus => _dndStatus;
  bool get focusDndActive => _dndActive;
  FocusDistractionStatus get focusDistractionStatus => _distractionStatus;
  ValueListenable<int> get timerTicks => _timerTicks;

  void attachNotifier(NotificationService n) {
    _notifier = n;
    _syncBackgroundEndReminder();
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
    _sound.onForegroundStopRequested = handleFocusForegroundStopRequested;
    _lifecycleAttached = true;
  }

  Future<void> handleFocusForegroundStopRequested() async {
    final ownsEffect = _captureEffectOwner(runtime: true, config: true);
    final receipt = await _changeConfig(
      (next) => next.whiteNoiseSound = FocusSoundCatalog.none,
      guard: ownsEffect,
    );
    if (!_isCurrentConfigReceipt(receipt)) return;
    await _syncSoundToState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(_recordStrictFocusPenalty(FocusPenaltyReason.leaveApp));
    }
    if (state == AppLifecycleState.resumed) {
      _synchronizeTimerToAnchor();
      // 回到前台：若番茄钟正在跑 + 已选择白噪音，但服务静音了，补上。
      final expected = _state.whiteNoiseSound;
      if (_state.isRunning && expected != 'none' && !_sound.isPlaying) {
        unawaited(_syncSoundToState());
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
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final runtimeRevision = _runtimeRevision;
    final pendingConfig = _configWriteTail;
    if (pendingConfig != null) await pendingConfig;
    final prefs = await SharedPreferences.getInstance();
    if (!_isCurrentStorageGeneration(generation, accountGeneration) ||
        runtimeRevision != _runtimeRevision) {
      return;
    }

    final configData = prefs.getString('pomodoro_config');
    _config = configData == null
        ? PomodoroConfig()
        : PomodoroConfig.fromJson(json.decode(configData));

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
    final storedGoal = prefs.getInt(dailyFocusGoalPrefsKey);
    _dailyFocusGoalMinutes =
        (storedGoal != null && storedGoal >= 10 && storedGoal <= 720)
        ? storedGoal
        : defaultDailyFocusGoalMinutes;
    final rawMixer = prefs.getString(ambientMixerPrefsKey);
    if (rawMixer != null && rawMixer.isNotEmpty) {
      try {
        final decoded = json.decode(rawMixer);
        if (decoded is Map) {
          final parsed = <String, double>{};
          for (final entry in decoded.entries) {
            final key = entry.key.toString().trim();
            final val = entry.value is num ? (entry.value as num).toDouble() : null;
            if (key.isNotEmpty &&
                key != FocusSoundCatalog.none &&
                val != null &&
                parsed.length < maxAmbientMixerTracks) {
              parsed[key] = val.clamp(0.1, 1.0).toDouble();
            }
          }
          _ambientMixerTracks = parsed;
        }
      } catch (_) {
        _ambientMixerTracks = <String, double>{};
      }
    } else if (_config.whiteNoiseSound != FocusSoundCatalog.none) {
      _ambientMixerTracks = <String, double>{
        _config.whiteNoiseSound: _config.focusSoundVolume,
      };
    } else {
      _ambientMixerTracks = <String, double>{};
    }
    // 先过跨天重置再恢复/结算，保证逾期补结算的当日计数归属恢复当天。
    _checkDayReset();
    var snapshotHandled = false;
    final hydrateRuntime = !_runningSnapshotHydrated;
    if (hydrateRuntime) {
      _runningSnapshotHydrated = true;
      snapshotHandled = await _restoreRunningFromSnapshot(
        prefs,
        generation,
        accountGeneration,
        runtimeRevision,
      );
    }
    if (!_isCurrentStorageGeneration(generation, accountGeneration) ||
        (!snapshotHandled && runtimeRevision != _runtimeRevision)) {
      return;
    }
    if (_state.isRunning) {
      _state = _state.copyWith(
        whiteNoiseSound: _config.whiteNoiseSound,
        focusRoomId: _config.focusRoomId,
        clearFocusRoom: _config.focusRoomId == null,
      );
      unawaited(_syncSoundToState());
      _syncDndToState();
      _syncDistractionMonitorToState();
    } else if (hydrateRuntime && !snapshotHandled) {
      // 无快照且不在运行：重置为完整 focusDuration。
      // 有快照但逾期且未续跑时，保留结算后的 break 相位，不重置。
      _initState();
    } else {
      _refreshPreparedFocus();
    }
    _recomputeMineWeeklyFocus();
    _persistedRevision++;
    notifyListeners();
  }

  void resetLocalState() {
    _storageGeneration++;
    _runtimeRevision++;
    _cancelTimer();
    _clearRunningSnapshot();
    _cancelBackgroundEndReminder();
    _runningSnapshotHydrated = false;
    _runningAccountGeneration = null;
    _timerTicks.value = 0;
    _config = PomodoroConfig();
    _defaultFocusMinutes = 25;
    _dailyFocusGoalMinutes = defaultDailyFocusGoalMinutes;
    _ambientMixerTracks = <String, double>{};
    _mixerAuditionActive = false;
    unawaited(_stopExtraMixerPlayers());
    _sessions = [];
    _penalties = [];
    _sessionCountToday = 0;
    _recomputeMineWeeklyFocus();
    _lastDate = null;
    _persistedRevision++;
    _initState();
    // ignore: discarded_futures
    _sound.stop();
    // ignore: discarded_futures
    _restoreFocusDndIfNeeded(notify: false);
    _dndStatus = const FocusDndStatus.unavailable();
    _dndActive = false;
    _distractionTimer?.cancel();
    _distractionTimer = null;
    _distractionStatus = const FocusDistractionStatus.unavailable();
    _lastDistractingPackage = null;
    // ignore: discarded_futures
    _distraction.setFocusBlocker(enabled: false, packages: const []);
    notifyListeners();
  }

  void _initState() {
    _focusDraftPrepared = true;
    _state = PomodoroState(
      remainingSeconds: effectiveFocusDuration,
      totalSeconds: effectiveFocusDuration,
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
    final n = clock.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isCurrentStorageGeneration(int generation, int accountGeneration) =>
      generation == _storageGeneration &&
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(accountGeneration);

  Future<void> _saveMeta() async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final count = _sessionCountToday;
    final lastDate = _lastDate ??= _todayKey();
    final prefs = await SharedPreferences.getInstance();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
    await prefs.setInt('pomodoro_count_today', count);
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
    await prefs.setString('pomodoro_last_date', lastDate);
  }

  Future<_PomodoroConfigReceipt?> _changeConfig(
    void Function(PomodoroConfig) change, {
    bool resetIdleFocus = false,
    bool prepareIdleFocus = false,
    bool Function()? guard,
  }) {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final runtimeRevision = _runtimeRevision;
    final auth = _preferencesAuth;
    final session = auth?.sessionGeneration;
    return AccountPreferenceWrites.runResult((token) {
      final previous = _configWriteTail;
      final write = () async {
        bool isCurrent() =>
            !_disposed &&
            token.isCurrent &&
            identical(auth, _preferencesAuth) &&
            auth?.sessionGeneration == session &&
            auth?.isAccountTransitionInProgress != true &&
            auth?.isLocalAccountDataBlocked != true &&
            _isCurrentStorageGeneration(generation, accountGeneration) &&
            (guard?.call() ?? true);
        if (previous != null) await previous;
        if (!isCurrent()) return null;
        final next = _config.copyWith();
        change(next);
        final changed =
            json.encode(next.toJson()) != json.encode(_config.toJson());
        if (changed) {
          next.touch();
          final payload = json.encode(next.toJson());
          final prefs = await SharedPreferences.getInstance();
          if (!isCurrent()) return null;
          final transaction = AccountPreferenceTransaction(prefs, isCurrent);
          try {
            await transaction.setString('pomodoro_config', payload);
            transaction.commit();
          } on AccountPreferenceWriteCanceled {
            await transaction.rollback(canceledBeforeCleanup: true);
            return null;
          } catch (_) {
            await transaction.rollback();
            rethrow;
          }
          if (!isCurrent()) return null;
          _config = next;
          _persistedRevision++;
        }
        final priorState = _state;
        _state = _state.copyWith(
          whiteNoiseSound: next.whiteNoiseSound,
          focusRoomId: next.focusRoomId,
          clearFocusRoom: next.focusRoomId == null,
        );
        if (prepareIdleFocus &&
            (runtimeRevision == _runtimeRevision || _focusDraftPrepared) &&
            !_state.isRunning) {
          _runtimeRevision++;
          _cancelTimer();
          _clearRunningSnapshot();
          _cancelBackgroundEndReminder();
          _focusDraftPrepared = true;
          _state = _state.copyWith(
            isCountUp: false,
            type: PomodoroType.focus,
            remainingSeconds: effectiveFocusDuration,
            totalSeconds: effectiveFocusDuration,
          );
        } else if (resetIdleFocus &&
            runtimeRevision == _runtimeRevision &&
            !_state.isRunning &&
            !_state.isCountUp &&
            _state.type == PomodoroType.focus) {
          _focusDraftPrepared = true;
          _refreshPreparedFocus();
        }
        final receipt = _PomodoroConfigReceipt(
          _config,
          generation,
          accountGeneration,
          token,
          auth,
          session,
          changed,
        );
        if (changed ||
            priorState.totalSeconds != _state.totalSeconds ||
            priorState.remainingSeconds != _state.remainingSeconds ||
            priorState.type != _state.type ||
            priorState.isCountUp != _state.isCountUp) {
          notifyListeners();
        }
        return receipt;
      }();
      final settled = write.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      _configWriteTail = settled;
      settled.then((_) {
        if (identical(_configWriteTail, settled)) _configWriteTail = null;
      });
      return write;
    }, canceledResult: () => null);
  }

  bool _isCurrentConfigReceipt(_PomodoroConfigReceipt? receipt) =>
      receipt != null &&
      !_disposed &&
      receipt.token.isCurrent &&
      identical(receipt.auth, _preferencesAuth) &&
      receipt.auth?.sessionGeneration == receipt.session &&
      receipt.auth?.isAccountTransitionInProgress != true &&
      receipt.auth?.isLocalAccountDataBlocked != true &&
      identical(receipt.config, _config) &&
      _isCurrentStorageGeneration(
        receipt.generation,
        receipt.accountGeneration,
      );

  bool Function() _captureEffectOwner({
    bool runtime = false,
    bool config = false,
  }) {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final writeGeneration = AccountPreferenceWrites.generation;
    final auth = _preferencesAuth;
    final session = auth?.sessionGeneration;
    final runtimeRevision = _runtimeRevision;
    final configuration = _config;
    return () =>
        !_disposed &&
        !AccountPreferenceWrites.isBoundaryActive &&
        AccountPreferenceWrites.generation == writeGeneration &&
        _isCurrentStorageGeneration(generation, accountGeneration) &&
        identical(auth, _preferencesAuth) &&
        auth?.sessionGeneration == session &&
        auth?.isAccountTransitionInProgress != true &&
        auth?.isLocalAccountDataBlocked != true &&
        (!runtime || runtimeRevision == _runtimeRevision) &&
        (!config || identical(configuration, _config));
  }

  Future<void> _saveSessions() async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final sessions = List<PomodoroSession>.of(_sessions);
    final prefs = await SharedPreferences.getInstance();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
    // 大列表的 JSON 编码会阻塞主 isolate，挪到后台 isolate 执行（对齐
    // todo_provider 的做法）；小列表直接同步编码，省去 isolate 往返。
    final data = sessions.length >= _isolateEncodeMinItems
        ? await compute(_encodePomodoroSessionsPayload, sessions)
        : json.encode(sessions.map((e) => e.toJson()).toList());
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
    await prefs.setString('pomodoro_sessions', data);
  }

  /// 会话记录有界增长：超出上限时丢弃最旧的记录（机制对齐 penalties
  /// 的 take(100)；上限放宽到 500 以保留统计页/日历/报告的近月历史）。
  void _trimSessions() {
    if (_sessions.length > _maxPomodoroSessions) {
      _sessions.removeRange(0, _sessions.length - _maxPomodoroSessions);
    }
  }

  /// 测试专用：批量注入历史会话（触发上限裁剪与持久化）。
  @visibleForTesting
  Future<void> debugAddSessionsForTest(List<PomodoroSession> sessions) async {
    _sessions.addAll(sessions);
    _trimSessions();
    await _saveSessions();
    notifyListeners();
  }

  Future<void> _savePenaltyList(List<PomodoroFocusPenalty> penalties) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'pomodoro_focus_penalties',
      json.encode(penalties.map((e) => e.toJson()).toList()),
    );
  }

  // --- 运行态快照（进程被杀重启后的恢复路径） ---

  /// 串行执行快照落盘操作；失败静默降级，不影响计时主流程。
  Future<bool> _queueSnapshotOp(
    Future<bool> Function(SharedPreferences) op, {
    void Function(bool)? onSettled,
  }) {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final result = Completer<bool>();
    _snapshotOps.add(() async {
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) {
        result.complete(false);
        return;
      }
      var succeeded = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
        succeeded = await op(prefs);
      } catch (_) {
        // Retry running writes on the next tick; expose cleanup failure below.
      } finally {
        if (_isCurrentStorageGeneration(generation, accountGeneration)) {
          _snapshotWritesSucceeded = succeeded;
          onSettled?.call(succeeded);
        }
        result.complete(
          succeeded &&
              _isCurrentStorageGeneration(generation, accountGeneration),
        );
      }
    });
    if (_snapshotDraining) return result.future;
    _snapshotDraining = true;
    _snapshotDrainCompleter = Completer<void>();
    unawaited(_drainSnapshotOps());
    return result.future;
  }

  /// Includes the operation already removed from the queue and sent to storage.
  Future<bool> waitForSnapshotWrites() async {
    while (_snapshotDraining) {
      await _snapshotDrainCompleter!.future;
    }
    return _snapshotWritesSucceeded;
  }

  Future<void> _drainSnapshotOps() async {
    try {
      while (_snapshotOps.isNotEmpty) {
        final op = _snapshotOps.removeAt(0);
        try {
          await op();
        } catch (_) {
          // 快照持久化失败可容忍：下次 tick / 退出运行态会重新同步。
        }
      }
    } finally {
      _snapshotDraining = false;
      _snapshotDrainCompleter!.complete();
    }
  }

  Object _runningSnapshotKey() => (
    _activeSessionId,
    _state.type.index,
    _state.isCountUp,
    _state.totalSeconds,
    _activeAnchorMs,
    _state.completedSessions,
    _state.taskName,
    _state.tag,
  );

  Object? _lastEncodedSnapshotKey;
  bool _runningSnapshotDirty = true;

  Map<String, dynamic> _runningSnapshot() => <String, dynamic>{
    'isRunning': true,
    'sessionId': _activeSessionId,
    'type': _state.type.index,
    'isCountUp': _state.isCountUp,
    'totalSeconds': _state.totalSeconds,
    'endsAtMs': _activeAnchorMs,
    'completedSessions': _state.completedSessions,
    'taskName': _state.taskName,
    'tag': _state.tag,
  };

  /// 把当前运行态写入快照。在启动与每个计时 tick 调用；锚点及元信息不变且上次
  /// 写入已成功时跳过 JSON 编码与落盘，避免每秒 1s tick 触发序列化开销。
  void _persistRunningSnapshot() {
    if (!_state.isRunning || _activeAnchorMs == null) return;
    final snapshotKey = _runningSnapshotKey();
    if (!_runningSnapshotDirty && snapshotKey == _lastEncodedSnapshotKey) {
      return;
    }
    final payload = json.encode(_runningSnapshot());
    if (payload == _lastSnapshotPayload || payload == _pendingSnapshotPayload) {
      _lastEncodedSnapshotKey = snapshotKey;
      _runningSnapshotDirty = false;
      return;
    }
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final revision = ++_snapshotRevision;
    _lastEncodedSnapshotKey = snapshotKey;
    _runningSnapshotDirty = false;
    _pendingSnapshotPayload = payload;
    unawaited(
      _queueSnapshotOp(
        (prefs) => prefs.setString(runningSnapshotKey, payload),
        onSettled: (succeeded) {
          if (_isCurrentStorageGeneration(generation, accountGeneration) &&
              revision == _snapshotRevision) {
            _pendingSnapshotPayload = null;
            _lastSnapshotPayload = succeeded ? payload : null;
            if (!succeeded) {
              _runningSnapshotDirty = true;
            }
          }
        },
      ),
    );
  }

  /// 离开运行态（暂停 / 手动停止 / 完成 / 重置 / 重置本地数据）时清快照。
  void _clearRunningSnapshot() {
    _activeAnchorMs = null;
    _activeSessionId = null;
    _lastEncodedSnapshotKey = null;
    _runningSnapshotDirty = true;
    _snapshotClearRetryTimer?.cancel();
    _snapshotRevision++;
    _lastSnapshotPayload = null;
    _pendingSnapshotPayload = null;
    _queueSnapshotClear();
  }

  Future<bool> _removeRunningSnapshot(
    SharedPreferences prefs,
    int generation,
    int accountGeneration,
  ) async {
    try {
      if (await prefs.remove(runningSnapshotKey)) return true;
    } catch (_) {
      // A stopped marker prevents recovery if deletion is temporarily refused.
    }
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) {
      return false;
    }
    return prefs.setString(runningSnapshotKey, '{"isRunning":false}');
  }

  void _queueSnapshotClear({int attempt = 0}) {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final revision = _snapshotRevision;
    unawaited(
      _queueSnapshotOp(
        (prefs) => _removeRunningSnapshot(prefs, generation, accountGeneration),
        onSettled: (succeeded) {
          if (!succeeded &&
              !_disposed &&
              attempt < 3 &&
              revision == _snapshotRevision) {
            _snapshotClearRetryTimer = Timer(const Duration(seconds: 1), () {
              if (_isCurrentStorageGeneration(generation, accountGeneration) &&
                  revision == _snapshotRevision) {
                _queueSnapshotClear(attempt: attempt + 1);
              }
            });
          }
        },
      ),
    );
  }

  /// 启动时重建：进程被杀后唯一恢复路径（不做后台计时）。
  ///
  /// - 未逾期 → 按 `endsAt - now` 恢复 remainingSeconds 并重启 Timer；
  ///   正计时按累计时长恢复。
  /// - 逾期（elapsed ≥ total）→ 删除快照后走既有自然完成结算
  ///   （写一条 session、当日计数 +1、autoStartBreaks），保证只结算一次。
  ///
  /// 返回是否处理过快照（恢复运行或完成结算）；调用方据此决定是否回退
  /// 到 [_initState]（逾期结算后不续跑时，应保留 break 相位而非重置）。
  Future<bool> _restoreRunningFromSnapshot(
    SharedPreferences prefs,
    int generation,
    int accountGeneration,
    int runtimeRevision,
  ) async {
    bool canRestore() =>
        _isCurrentStorageGeneration(generation, accountGeneration) &&
        runtimeRevision == _runtimeRevision;
    if (!canRestore()) return false;
    final raw = prefs.getString(runningSnapshotKey);
    if (raw == null) return false;

    Map<String, dynamic>? data;
    try {
      final decoded = json.decode(raw);
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    } on FormatException {
      data = null;
    }
    int? integerField(String key) {
      final value = data?[key];
      return value is num && value.isFinite ? value.toInt() : null;
    }

    final anchorMs = integerField('endsAtMs');
    final totalSeconds = integerField('totalSeconds');
    final isCountUp = data?['isCountUp'] == true;
    if (data == null ||
        data['isRunning'] != true ||
        anchorMs == null ||
        totalSeconds == null ||
        // 正计时运行态 totalSeconds 恒为 0（累计时长用 remainingSeconds 表达），
        // 不能按损坏快照清除；只有倒计时才要求 totalSeconds > 0。
        (!isCountUp && totalSeconds <= 0)) {
      // 快照损坏 / 非运行态：清理后按无快照处理。
      await _queueSnapshotOp(
        (prefs) => _removeRunningSnapshot(prefs, generation, accountGeneration),
      );
      return false;
    }

    final typeIndex = integerField('type') ?? 0;
    final type = typeIndex >= 0 && typeIndex < PomodoroType.values.length
        ? PomodoroType.values[typeIndex]
        : PomodoroType.focus;
    final completedSessions = integerField('completedSessions') ?? 0;
    final taskName = data['taskName']?.toString();
    final tag = data['tag']?.toString();
    final nowMs = clock.now().millisecondsSinceEpoch;
    final storedSessionId = data['sessionId'];
    final sessionId = storedSessionId is String && storedSessionId.isNotEmpty
        ? storedSessionId
        : 'legacy-$anchorMs-${type.index}-$isCountUp';
    if (_sessions.any((session) => session.id == sessionId)) {
      await _queueSnapshotOp(
        (prefs) => _removeRunningSnapshot(prefs, generation, accountGeneration),
      );
      return false;
    }

    if (!isCountUp) {
      // 倒计时：快照锚点即结束时刻，向上取整避免恢复瞬间吞掉不足 1 秒。
      final remainingSeconds = ((anchorMs - nowMs) / 1000).ceil();
      if (remainingSeconds <= 0) {
        // 逾期：先删快照（结算只此一次），再走既有自然完成结算。
        _activeAnchorMs = null;
        _lastSnapshotPayload = null;
        final removed = await _queueSnapshotOp(
          (prefs) =>
              _removeRunningSnapshot(prefs, generation, accountGeneration),
        );
        if (!canRestore() || !removed) return false;
        _activeSessionId = sessionId;
        _state = PomodoroState(
          // 结算时长取 totalSeconds，与 remainingSeconds 无关；
          // 置 1 表达「倒计时走完」的完成语义。
          remainingSeconds: 1,
          totalSeconds: totalSeconds,
          isRunning: true,
          type: type,
          completedSessions: completedSessions,
          taskName: taskName,
          whiteNoiseSound: _config.whiteNoiseSound,
          tag: tag,
          focusRoomId: _config.focusRoomId,
        );
        _completeSession();
        return true;
      }
      // 快照锚点异常超前（时钟回拨 / 写入异常值）：真实运行态剩余永远
      // ≤ totalSeconds，remaining > total 只能是损坏，按损坏清键回退，
      // 避免恢复出远超配置时长的倒计时（与正计时的 clamp 对称）。
      if (remainingSeconds > totalSeconds) {
        _activeAnchorMs = null;
        _lastSnapshotPayload = null;
        await _queueSnapshotOp(
          (prefs) =>
              _removeRunningSnapshot(prefs, generation, accountGeneration),
        );
        return false;
      }
      _state = PomodoroState(
        remainingSeconds: remainingSeconds,
        totalSeconds: totalSeconds,
        isRunning: true,
        type: type,
        completedSessions: completedSessions,
        taskName: taskName,
        whiteNoiseSound: _config.whiteNoiseSound,
        tag: tag,
        focusRoomId: _config.focusRoomId,
      );
      // 保留原锚点续跑：完成时刻仍对齐快照里的 endsAt，不白送时间。
      _activeAnchorMs = anchorMs;
      _activeSessionId = sessionId;
      _lastSnapshotPayload = null;
      _startTimer();
      return true;
    }

    // 正计时：快照锚点为开始时刻，按累计时长恢复（上限对齐完成时的
    // clamp(1, 24h) 语义）。
    final elapsed = ((nowMs - anchorMs) / 1000).floor().clamp(
      0,
      _maxCountUpSnapshotSeconds,
    );
    _state = PomodoroState(
      remainingSeconds: elapsed,
      totalSeconds: totalSeconds,
      isRunning: true,
      isCountUp: true,
      type: type,
      completedSessions: completedSessions,
      taskName: taskName,
      whiteNoiseSound: _config.whiteNoiseSound,
      tag: tag,
      focusRoomId: _config.focusRoomId,
    );
    _activeAnchorMs = nowMs - elapsed * 1000;
    _activeSessionId = sessionId;
    _lastSnapshotPayload = null;
    _startTimer();
    return true;
  }

  Future<bool> deleteSession(String id) async {
    final idx = _sessions.indexWhere((s) => s.id == id);
    if (idx < 0) return false;

    final removed = _sessions.removeAt(idx);
    _recomputeMineWeeklyFocus();
    await CloudSyncProvider.recordDeletedItem('pomodoro_sessions', removed.id);
    if (removed.type == PomodoroType.focus &&
        _isSameDay(removed.startTime, clock.now())) {
      await _refreshTodayFocusMeta();
    }

    await _timeAudit?.deleteByDedupeKey(
      TimeAuditProvider.pomodoroDedupeKey(id),
    );
    await _saveSessions();
    _persistedRevision++;
    notifyListeners();
    return true;
  }

  Future<bool> updateSession(PomodoroSession updated) async {
    final idx = _sessions.indexWhere((s) => s.id == updated.id);
    if (idx < 0) return false;

    final previous = _sessions[idx];
    _sessions[idx] = updated;
    _recomputeMineWeeklyFocus();
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
    _persistedRevision++;
    notifyListeners();
    return true;
  }

  bool _affectsTodayFocusCount(PomodoroSession session) {
    return session.type == PomodoroType.focus &&
        _isSameDay(session.startTime, clock.now());
  }

  void _recomputeMineWeeklyFocus({DateTime? now}) {
    final effectiveNow = now ?? clock.now();
    final weekAgo = effectiveNow.subtract(const Duration(days: 7));
    var seconds = 0;
    for (final session in _sessions) {
      if (session.type == PomodoroType.focus &&
          session.startTime.isAfter(weekAgo)) {
        seconds += session.durationSeconds;
      }
    }
    _mineWeeklyFocusMinutes = seconds ~/ 60;
    _mineWeeklyFocusComputedAt = effectiveNow;
  }

  Future<void> _refreshTodayFocusMeta() async {
    final now = clock.now();
    _sessionCountToday = _sessions
        .where(
          (s) => s.type == PomodoroType.focus && _isSameDay(s.startTime, now),
        )
        .length;
    _lastDate = _todayKey();
    await _saveMeta();
  }

  // --- Timer controls ---

  void _syncBackgroundEndReminder() {
    final notifier = _notifier;
    if (notifier == null ||
        _disposed ||
        !_state.isRunning ||
        _state.isCountUp ||
        _activeAnchorMs == null) {
      return;
    }
    final endsAt = DateTime.fromMillisecondsSinceEpoch(_activeAnchorMs!);
    if (!endsAt.isAfter(clock.now())) return;
    unawaited(
      notifier.schedulePomodoroEndReminder(
        isFocus: _state.type == PomodoroType.focus,
        taskName: _state.taskName,
        when: endsAt,
      ),
    );
  }

  void _cancelBackgroundEndReminder() {
    final notifier = _notifier;
    if (notifier == null) return;
    unawaited(notifier.cancelPomodoroEndReminder());
  }

  void toggleTimer() {
    if (_state.isRunning) {
      unawaited(_recordStrictFocusPenalty(FocusPenaltyReason.pause));
      _pauseTimer();
    } else {
      _startTimer();
    }
  }

  void startIfIdle() {
    if (_state.isRunning) return;
    _startTimer();
  }

  void _startTimer() {
    _focusDraftPrepared = false;
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    _runningSnapshotHydrated = true;
    _runningAccountGeneration = accountGeneration;
    if (_timer?.isActive ?? false) {
      if (!_state.isRunning) {
        _state = _state.copyWith(isRunning: true);
        notifyListeners();
      }
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
      _syncBackgroundEndReminder();
      unawaited(_syncSoundToState());
      _syncDndToState();
      _syncDistractionMonitorToState();
      return;
    }
    _runtimeRevision++;
    final runtimeRevision = _runtimeRevision;
    _snapshotClearRetryTimer?.cancel();
    _activeSessionId ??= const Uuid().v4();
    if (!_state.isRunning) {
      _state = _state.copyWith(isRunning: true);
    }
    // 新启动（含暂停续跑）计算锚点；崩溃恢复路径已带原锚点，不重算。
    _activeAnchorMs ??= _state.isCountUp
        ? clock.now().millisecondsSinceEpoch - _state.remainingSeconds * 1000
        : clock.now().millisecondsSinceEpoch + _state.remainingSeconds * 1000;
    _persistRunningSnapshot();
    notifyListeners();
    if (!_isCurrentStorageGeneration(generation, accountGeneration) ||
        runtimeRevision != _runtimeRevision ||
        !_state.isRunning) {
      return;
    }
    _syncBackgroundEndReminder();
    unawaited(_syncSoundToState());
    _syncDndToState();
    _syncDistractionMonitorToState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) {
        _cancelTimer();
        return;
      }
      _synchronizeTimerToAnchor();
    });
  }

  void _synchronizeTimerToAnchor({bool completeExpired = true}) {
    final anchor = _activeAnchorMs;
    if (!_state.isRunning || anchor == null) return;
    if (_runningAccountGeneration !=
        AccountLocalDataCleaner.accountDataGeneration) {
      _cancelTimer();
      return;
    }
    final nowMs = clock.now().millisecondsSinceEpoch;
    final seconds = _state.isCountUp
        ? ((nowMs - anchor) / 1000).floor().clamp(0, _maxCountUpSnapshotSeconds)
        : ((anchor - nowMs) / 1000).ceil().clamp(0, _state.totalSeconds);
    _state = _state.copyWith(remainingSeconds: seconds);
    if (!_state.isCountUp && seconds == 0 && completeExpired) {
      _completeSession();
      return;
    }
    _notifyTimerTick();
    _persistRunningSnapshot();
  }

  void _notifyTimerTick() {
    _timerTicks.value++;
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _pauseTimer() {
    _synchronizeTimerToAnchor(completeExpired: false);
    if (_state.isRunning && !_state.isCountUp && _state.remainingSeconds == 0) {
      _completeSession();
      return;
    }
    _runtimeRevision++;
    _cancelTimer();
    _clearRunningSnapshot();
    _cancelBackgroundEndReminder();
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
  Future<bool> _syncSoundToState() async {
    final ownsEffect = _captureEffectOwner(runtime: true, config: true);
    if (!ownsEffect()) return false;
    final sound = _state.whiteNoiseSound;
    final volume = _config.focusSoundVolume;
    final shouldPlay =
        _state.isRunning &&
        sound != 'none' &&
        (_state.type == PomodoroType.focus || _config.playSoundInBreak);
    if (shouldPlay) {
      unawaited(_syncExtraMixerPlayers(play: _ambientMixerTracks.length >= 2));
      if (!_sound.isPlaying || _sound.currentSound != sound) {
        return _playFocusSound(sound, volume: volume, isCurrent: ownsEffect);
      } else {
        await _sound.setVolume(volume);
        return ownsEffect();
      }
    } else {
      if (!_mixerAuditionActive) {
        unawaited(_syncExtraMixerPlayers(play: false));
      }
      if (_sound.isPlaying && !_mixerAuditionActive) {
        await _sound.stop();
      }
      return ownsEffect();
    }
  }

  Future<bool> _playFocusSound(
    String sound, {
    required double volume,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return false;
    await _sound.setVolume(volume);
    if (!isCurrent()) return false;
    final started = await _sound.play(sound);
    return isCurrent() && started;
  }

  Future<bool> _previewWhiteNoiseSound(String sound) async {
    final ownsEffect = _captureEffectOwner(runtime: true, config: true);
    if (!ownsEffect()) return false;
    if (sound == FocusSoundCatalog.none || _state.isRunning) return true;
    final volume = _config.focusSoundVolume;
    await _sound.setVolume(volume);
    if (!ownsEffect()) return false;
    final started = await _sound.preview(sound);
    return ownsEffect() && started;
  }

  String get _focusSoundPreviewFallback {
    final current = _state.whiteNoiseSound;
    if (current != FocusSoundCatalog.none) return current;
    return FocusSoundCatalog.tracks.first.id;
  }

  void _completeSession() {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    _runtimeRevision++;
    final sessionId = _activeSessionId ?? const Uuid().v4();
    _cancelTimer();
    // 结算即清旧快照（自然完成与崩溃后的逾期补结算共用）；若按
    // autoStart 续跑，_startTimer 会以新相位锚点重新落盘。
    _clearRunningSnapshot();
    _cancelBackgroundEndReminder();
    final completedState = _state;
    final completedType = completedState.type;
    final durationSeconds = completedState.isCountUp
        ? completedState.remainingSeconds.clamp(1, 24 * 60 * 60).toInt()
        : completedState.totalSeconds;
    final completedAt = clock.now();
    final session = PomodoroSession(
      id: sessionId,
      startTime: completedAt.subtract(Duration(seconds: durationSeconds)),
      endTime: completedAt,
      durationSeconds: durationSeconds,
      type: completedType,
      taskName: completedState.taskName,
      whiteNoiseSound: completedState.whiteNoiseSound,
      tag: completedState.tag,
      focusRoomId: completedState.focusRoomId,
    );
    _trimSessions();
    _sessions.add(session);
    _recomputeMineWeeklyFocus(now: completedAt);

    int newCount = completedState.completedSessions;
    final shouldSaveMeta = completedType == PomodoroType.focus;
    if (completedType == PomodoroType.focus) {
      newCount++;
      _sessionCountToday++;
    }

    PomodoroType nextType;
    int nextDuration;
    if (completedType == PomodoroType.focus) {
      if (newCount % _config.sessionsPerLongBreak == 0) {
        nextType = PomodoroType.longBreak;
        nextDuration = _config.longBreakDuration;
      } else {
        nextType = PomodoroType.shortBreak;
        nextDuration = _config.shortBreakDuration;
      }
    } else {
      nextType = PomodoroType.focus;
      nextDuration = effectiveFocusDuration;
    }
    final shouldAutoStartNext = completedType == PomodoroType.focus
        ? _config.autoStartBreaks
        : _config.autoStartFocus;

    if (completedState.isCountUp) {
      _state = completedState.copyWith(
        remainingSeconds: 0,
        totalSeconds: 0,
        isRunning: false,
        isCountUp: true,
        type: PomodoroType.focus,
        completedSessions: newCount,
      );
    } else {
      _state = completedState.copyWith(
        remainingSeconds: nextDuration,
        totalSeconds: nextDuration,
        isRunning: shouldAutoStartNext,
        type: nextType,
        completedSessions: newCount,
      );
    }

    if (_state.isRunning) {
      _startTimer();
    } else {
      _focusDraftPrepared =
          !_state.isCountUp && _state.type == PomodoroType.focus;
      // 本相位不自动续跑：立刻把声音停掉（focus→break 过渡，或已到末尾）。
      // ignore: discarded_futures
      _sound.stop();
      _syncDndToState();
      _syncDistractionMonitorToState();
    }
    notifyListeners();
    unawaited(
      _persistCompletedSession(
        session: session,
        completedState: completedState,
        completedType: completedType,
        saveMeta: shouldSaveMeta,
        generation: generation,
        accountGeneration: accountGeneration,
      ),
    );
  }

  Future<void> _persistCompletedSession({
    required PomodoroSession session,
    required PomodoroState completedState,
    required PomodoroType completedType,
    required bool saveMeta,
    required int generation,
    required int accountGeneration,
  }) async {
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
    await _saveSessions();
    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;

    if (completedType == PomodoroType.focus && !_disposed) {
      await _timeAudit?.recordPomodoroSession(
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
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
      if (!_disposed) {
        DomainEventBus.instance.publish(
          DomainEvent(
            type: DomainEventType.pomodoroCompleted,
            objectId: session.id,
            metadata: {'durationSeconds': session.durationSeconds},
          ),
        );
      }
    }

    if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;

    // Fire desktop notification
    if (!_disposed) {
      final cancelPendingEndReminder = !_state.isRunning;
      if (completedType == PomodoroType.focus) {
        _notifier?.notifyPomodoroComplete(
          taskName: completedState.taskName,
          cancelPendingEndReminder: cancelPendingEndReminder,
        );
      } else {
        _notifier?.notifyBreakComplete(
          cancelPendingEndReminder: cancelPendingEndReminder,
        );
      }
    }

    if (saveMeta) {
      await _saveMeta();
    }

    if (!_isCurrentStorageGeneration(generation, accountGeneration) ||
        _disposed) {
      return;
    }
    _persistedRevision++;
    notifyListeners();
  }

  void skipSession() {
    _runtimeRevision++;
    _runningSnapshotHydrated = true;
    _cancelTimer();
    _clearRunningSnapshot();
    _cancelBackgroundEndReminder();
    unawaited(_recordStrictFocusPenalty(FocusPenaltyReason.skip));
    if (_state.type == PomodoroType.focus) {
      _state = _state.copyWith(
        remainingSeconds: _config.shortBreakDuration,
        totalSeconds: _config.shortBreakDuration,
        isRunning: false,
        type: PomodoroType.shortBreak,
      );
    } else {
      _state = _state.copyWith(
        remainingSeconds: effectiveFocusDuration,
        totalSeconds: effectiveFocusDuration,
        isRunning: false,
        type: PomodoroType.focus,
      );
    }
    _focusDraftPrepared =
        !_state.isCountUp && _state.type == PomodoroType.focus;
    // ignore: discarded_futures
    _sound.stop();
    _syncDndToState();
    _syncDistractionMonitorToState();
    notifyListeners();
  }

  void resetTimer() {
    _runtimeRevision++;
    _runningSnapshotHydrated = true;
    _cancelTimer();
    _clearRunningSnapshot();
    _cancelBackgroundEndReminder();
    unawaited(_recordStrictFocusPenalty(FocusPenaltyReason.reset));
    _state = _state.copyWith(
      remainingSeconds: _state.isCountUp ? 0 : effectiveFocusDuration,
      totalSeconds: _state.isCountUp ? 0 : effectiveFocusDuration,
      isRunning: false,
      type: PomodoroType.focus,
      completedSessions: 0,
    );
    _focusDraftPrepared = !_state.isCountUp;
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
    _synchronizeTimerToAnchor(completeExpired: false);
    _completeSession();
  }

  void setCountUpMode(bool enabled) {
    if (_state.isRunning) return;
    _runtimeRevision++;
    _runningSnapshotHydrated = true;
    _cancelTimer();
    _state = _state.copyWith(
      remainingSeconds: enabled ? 0 : effectiveFocusDuration,
      totalSeconds: enabled ? 0 : effectiveFocusDuration,
      isRunning: false,
      isCountUp: enabled,
      type: PomodoroType.focus,
    );
    _focusDraftPrepared = !enabled;
    // ignore: discarded_futures
    _sound.stop();
    _syncDndToState();
    _syncDistractionMonitorToState();
    notifyListeners();
  }

  // --- Config ---

  Future<void> setConfig(PomodoroConfig cfg) async {
    final snapshot = cfg.copyWith();
    final receipt = await _changeConfig((next) {
      next.focusDuration = snapshot.focusDuration;
      next.focusDurationUsesDefault = snapshot.focusDurationUsesDefault;
      next.shortBreakDuration = snapshot.shortBreakDuration;
      next.longBreakDuration = snapshot.longBreakDuration;
      next.sessionsPerLongBreak = snapshot.sessionsPerLongBreak;
      next.whiteNoiseSound = snapshot.whiteNoiseSound;
      next.autoStartBreaks = snapshot.autoStartBreaks;
      next.autoStartFocus = snapshot.autoStartFocus;
      next.autoEnableDnd = snapshot.autoEnableDnd;
      next.strictFocusMode = snapshot.strictFocusMode;
      next.monitorDistractingApps = snapshot.monitorDistractingApps;
      next.distractingAppPackages = List.of(snapshot.distractingAppPackages);
      next.focusRoomId = snapshot.focusRoomId;
      next.focusSoundVolume = snapshot.focusSoundVolume;
      next.playSoundInBreak = snapshot.playSoundInBreak;
    }, resetIdleFocus: true);
    if (!_isCurrentConfigReceipt(receipt)) return;
    _syncDndToState();
    _syncDistractionMonitorToState();
  }

  Future<void> setFocusDuration(int seconds) async {
    final receipt = await _changeConfig((next) {
      next.focusDuration = seconds.clamp(60, 12 * 60 * 60);
      next.focusDurationUsesDefault = false;
    }, prepareIdleFocus: true);
    if (!_isCurrentConfigReceipt(receipt)) return;
  }

  Future<void> useDefaultFocusDuration() async {
    await _changeConfig((next) {
      next.focusDurationUsesDefault = true;
    }, prepareIdleFocus: true);
  }

  Future<void> setAutoEnableDnd(bool enabled) async {
    final receipt = await _changeConfig((next) => next.autoEnableDnd = enabled);
    if (!_isCurrentConfigReceipt(receipt) || !receipt!.changed) return;
    if (enabled) {
      await refreshFocusDndStatus();
    } else {
      await _restoreFocusDndIfNeeded();
    }
    if (!_isCurrentConfigReceipt(receipt)) return;
    notifyListeners();
    _syncDndToState();
  }

  Future<void> setStrictFocusMode(bool enabled) async {
    final receipt = await _changeConfig(
      (next) => next.strictFocusMode = enabled,
    );
    if (!_isCurrentConfigReceipt(receipt) || !receipt!.changed) return;
    _syncDistractionMonitorToState();
  }

  Future<FocusDndStatus> refreshFocusDndStatus() async {
    final ownsEffect = _captureEffectOwner();
    if (!ownsEffect()) return _dndStatus;
    final status = await _dnd.getStatus();
    if (ownsEffect()) {
      _dndStatus = status;
      notifyListeners();
    }
    return status;
  }

  Future<bool> openFocusDndSettings() => _dnd.openPolicyAccessSettings();

  bool get _shouldEnableDnd =>
      _config.autoEnableDnd &&
      _state.isRunning &&
      _state.type == PomodoroType.focus;

  void _syncDndToState() {
    if (!_captureEffectOwner()()) return;
    if (_dndPendingRestoreFilter != null) {
      if (!_dndRestoreInFlight && !_dndEnableInFlight) {
        unawaited(_restoreFocusDndIfNeeded());
      }
      return;
    }
    if (_shouldEnableDnd) {
      if (!_dndActive && !_dndEnableInFlight && !_dndRestoreInFlight) {
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

  Future<void> _enqueueDndOperation(Future<void> Function() operation) {
    final previous = _dndOperationTail;
    final result = () async {
      if (previous != null) await previous;
      await operation();
    }();
    final settled = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _dndOperationTail = settled;
    settled.then((_) {
      if (identical(_dndOperationTail, settled)) _dndOperationTail = null;
    });
    return result;
  }

  Future<void> _enableFocusDndIfPossible() {
    if (_dndEnableInFlight) return Future<void>.value();
    _dndEnableInFlight = true;
    final ownsEffect = _captureEffectOwner(runtime: true, config: true);
    return _enqueueDndOperation(() async {
      try {
        if (!ownsEffect()) return;
        final status = await _dnd.getStatus();
        if (!ownsEffect()) return;
        _dndStatus = status;
        if (!_shouldEnableDnd || !status.supported || !status.accessGranted) {
          notifyListeners();
          return;
        }

        final result = await _dnd.enable();
        if (!ownsEffect() || !_shouldEnableDnd) {
          // This issued enable belongs to the old operation. Restore its own
          // filter before the queue lets a newer owner enable DND.
          if (result.enabled) {
            final restored = await _dnd.restore(result.previousFilter);
            if (!restored) _dndPendingRestoreFilter = result.previousFilter;
          }
          return;
        }
        if (result.enabled) {
          _dndPreviousFilter ??= result.previousFilter;
          _dndActive = true;
          _dndStatus = FocusDndStatus(
            supported: true,
            accessGranted: true,
            currentFilter: result.currentFilter,
          );
        }
        notifyListeners();
      } finally {
        _dndEnableInFlight = false;
        if (!ownsEffect() && _dndPendingRestoreFilter == null) {
          _syncDndToState();
        }
      }
    });
  }

  Future<void> _restoreFocusDndIfNeeded({bool notify = true}) {
    if (_dndRestoreInFlight) return _dndOperationTail ?? Future<void>.value();
    final previous = _dndPendingRestoreFilter ?? _dndPreviousFilter;
    if (previous == null) {
      _dndActive = false;
      return Future<void>.value();
    }
    _dndRestoreInFlight = true;
    _dndPendingRestoreFilter = previous;
    _dndPreviousFilter = null;
    _dndActive = false;
    final ownsEffect = _captureEffectOwner();
    var restored = false;
    return _enqueueDndOperation(() async {
      try {
        // Restoration also runs after reset/dispose, using only the captured
        // filter. It may never publish its result into a newer owner.
        restored = await _dnd.restore(previous);
        if (!restored) return;
        _dndPendingRestoreFilter = null;
        if (!ownsEffect()) return;
        final status = await _dnd.getStatus();
        if (!ownsEffect()) return;
        _dndStatus = status;
        if (notify) notifyListeners();
      } finally {
        _dndRestoreInFlight = false;
        if (restored) _syncDndToState();
      }
    });
  }

  void setTaskName(String? name) {
    _state = _state.copyWith(taskName: name, clearTaskName: name == null);
    _syncBackgroundEndReminder();
    notifyListeners();
  }

  void setTag(String? tag) {
    final clean = tag?.trim();
    _state = _state.copyWith(
      tag: clean,
      clearTag: clean == null || clean.isEmpty,
    );
    _syncBackgroundEndReminder();
    notifyListeners();
  }

  Future<void> setFocusRoomId(String? roomId) async {
    final clean = roomId?.trim();
    final nextRoomId = clean == null || clean.isEmpty ? null : clean;
    await _changeConfig((next) => next.focusRoomId = nextRoomId);
  }

  Future<void> refreshFocusDistractionStatus() async {
    final ownsEffect = _captureEffectOwner();
    if (!ownsEffect()) return;
    final status = await _distraction.getStatus();
    if (ownsEffect()) {
      _distractionStatus = status;
      notifyListeners();
    }
  }

  Future<bool> openFocusUsageAccessSettings() {
    return _distraction.openUsageAccessSettings();
  }

  Future<bool> openFocusAccessibilitySettings() {
    return _distraction.openAccessibilitySettings();
  }

  Future<void> setMonitorDistractingApps(bool enabled) async {
    final receipt = await _changeConfig(
      (next) => next.monitorDistractingApps = enabled,
    );
    if (!_isCurrentConfigReceipt(receipt) || !receipt!.changed) return;
    // ignore: discarded_futures
    refreshFocusDistractionStatus();
    _syncDistractionMonitorToState();
  }

  Future<void> setDistractingAppPackages(List<String> packages) async {
    final normalized =
        packages
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final receipt = await _changeConfig(
      (next) => next.distractingAppPackages = normalized,
    );
    if (!_isCurrentConfigReceipt(receipt) || !receipt!.changed) return;
    _syncDistractionMonitorToState();
  }

  Future<bool> setWhiteNoiseSound(String sound, {bool preview = true}) async {
    final normalized = sound.startsWith('custom:')
        ? sound
        : FocusSoundCatalog.normalizeForPlayback(sound);
    final receipt = await _changeConfig(
      (next) => next.whiteNoiseSound = normalized,
    );
    if (!_isCurrentConfigReceipt(receipt)) return false;
    final ownsEffect = _captureEffectOwner(runtime: true, config: true);
    final playbackOk = await _syncSoundToState();
    if (!_isCurrentConfigReceipt(receipt) || !ownsEffect()) return false;
    if (!playbackOk &&
        _state.isRunning &&
        normalized != FocusSoundCatalog.none) {
      await _changeConfig(
        (next) => next.whiteNoiseSound = FocusSoundCatalog.none,
        guard: () => _isCurrentConfigReceipt(receipt) && ownsEffect(),
      );
      return false;
    }
    if (preview && normalized != FocusSoundCatalog.none && !_state.isRunning) {
      return _previewWhiteNoiseSound(normalized);
    }
    return true;
  }

  Future<bool> setFocusSoundVolume(double volume, {bool preview = true}) async {
    final normalized = volume
        .clamp(FocusSoundService.minimumAudibleVolume, 1.0)
        .toDouble();
    final receipt = await _changeConfig(
      (next) => next.focusSoundVolume = normalized,
    );
    if (!_isCurrentConfigReceipt(receipt)) return false;
    final ownsEffect = _captureEffectOwner(runtime: true, config: true);
    await _sound.setVolume(normalized);
    if (!_isCurrentConfigReceipt(receipt) || !ownsEffect()) return false;
    if (preview && !_state.isRunning) {
      return _previewWhiteNoiseSound(_focusSoundPreviewFallback);
    }
    return true;
  }

  int get dailyFocusGoalMinutes => _dailyFocusGoalMinutes;

  int get todayFocusMinutes =>
      todayFocusSessions.fold<int>(0, (sum, s) => sum + s.durationSeconds) ~/
      60;

  double get dailyFocusGoalProgress => _dailyFocusGoalMinutes <= 0
      ? 0.0
      : (todayFocusMinutes / _dailyFocusGoalMinutes).clamp(0.0, 1.0);

  Map<String, double> get ambientMixerTracks =>
      Map<String, double>.unmodifiable(_ambientMixerTracks);

  bool get hasMultiTrackMix => _ambientMixerTracks.length >= 2;

  bool get isMixerAuditioning => _mixerAuditionActive;

  List<String> get activeMixerTrackIds =>
      _ambientMixerTracks.keys.toList(growable: false);

  Future<void> setDailyFocusGoalMinutes(int minutes) async {
    final clamped = minutes.clamp(10, 720).toInt();
    if (_dailyFocusGoalMinutes == clamped) return;
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    _dailyFocusGoalMinutes = clamped;
    _persistedRevision++;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
      await prefs.setInt(dailyFocusGoalPrefsKey, clamped);
    } catch (_) {
      // Ignore storage errors in restricted environments gracefully.
    }
  }

  Future<void> prepareSingleAmbientTrack(String id) async {
    final normalized = id.startsWith('custom:')
        ? id
        : FocusSoundCatalog.normalizeForPlayback(id);
    await _stopExtraMixerPlayers();
    _mixerAuditionActive = false;
    if (normalized == FocusSoundCatalog.none) {
      _ambientMixerTracks = <String, double>{};
    } else {
      _ambientMixerTracks = <String, double>{
        normalized: _config.focusSoundVolume,
      };
    }
    await _persistAmbientMixer();
  }

  Future<bool> selectSingleAmbientTrack(
    String sound, {
    bool preview = true,
  }) async {
    final normalized = sound.startsWith('custom:')
        ? sound
        : FocusSoundCatalog.normalizeForPlayback(sound);
    await prepareSingleAmbientTrack(normalized);
    return setWhiteNoiseSound(normalized, preview: preview);
  }

  Future<void> toggleMixerTrack(
    String trackId, {
    double defaultVolume = 0.7,
  }) async {
    final clean = trackId.trim();
    if (clean.isEmpty || clean == FocusSoundCatalog.none) {
      await clearMixerTracks();
      return;
    }
    final next = Map<String, double>.from(_ambientMixerTracks);
    if (next.containsKey(clean)) {
      next.remove(clean);
    } else {
      if (next.length >= maxAmbientMixerTracks) {
        next.remove(next.keys.first);
      }
      next[clean] = defaultVolume.clamp(0.1, 1.0).toDouble();
    }
    _ambientMixerTracks = next;
    await _persistAmbientMixer();
    final primary = next.isEmpty ? FocusSoundCatalog.none : next.keys.first;
    await _changeConfig((c) => c.whiteNoiseSound = primary);
    await _syncMixerPlayback();
    notifyListeners();
  }

  Future<void> setMixerTrackVolume(String trackId, double volume) async {
    final clean = trackId.trim();
    if (!_ambientMixerTracks.containsKey(clean)) return;
    final clamped = volume.clamp(0.1, 1.0).toDouble();
    _ambientMixerTracks = <String, double>{
      ..._ambientMixerTracks,
      clean: clamped,
    };
    await _persistAmbientMixer();
    final primary = _ambientMixerTracks.isEmpty
        ? null
        : _ambientMixerTracks.keys.first;
    if (clean == primary) {
      final scaledPrimary = (clamped * _config.focusSoundVolume)
          .clamp(FocusSoundService.minimumAudibleVolume, 1.0)
          .toDouble();
      try {
        await _sound.setVolume(scaledPrimary);
      } catch (_) {}
    } else {
      final player = _extraMixerPlayers[clean];
      if (player != null) {
        try {
          await player.setVolume(
            (clamped * _config.focusSoundVolume).clamp(0.05, 1.0),
          );
        } catch (_) {}
      }
    }
    notifyListeners();
  }

  Future<void> clearMixerTracks() async {
    _ambientMixerTracks = <String, double>{};
    _mixerAuditionActive = false;
    await _persistAmbientMixer();
    await _stopExtraMixerPlayers();
    await setWhiteNoiseSound(FocusSoundCatalog.none, preview: false);
    notifyListeners();
  }

  Future<bool> toggleMixerAudition() async {
    if (_ambientMixerTracks.isEmpty) return false;
    if (_mixerAuditionActive) {
      _mixerAuditionActive = false;
      await _stopExtraMixerPlayers();
      try {
        if (!_state.isRunning) await _sound.stop();
      } catch (_) {}
      notifyListeners();
      return false;
    }
    _mixerAuditionActive = true;
    await _syncMixerPlayback(forceAudition: true);
    notifyListeners();
    return true;
  }

  Future<void> _persistAmbientMixer() async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
      if (_ambientMixerTracks.isEmpty) {
        await prefs.remove(ambientMixerPrefsKey);
      } else {
        await prefs.setString(
          ambientMixerPrefsKey,
          json.encode(_ambientMixerTracks),
        );
      }
    } catch (_) {}
  }

  Future<void> _syncMixerPlayback({bool forceAudition = false}) async {
    final shouldPlay =
        forceAudition ||
        _mixerAuditionActive ||
        (_state.isRunning &&
            (_state.type == PomodoroType.focus || _config.playSoundInBreak));
    if (!shouldPlay || _ambientMixerTracks.isEmpty) {
      await _stopExtraMixerPlayers();
      if (!_state.isRunning) {
        try {
          await _sound.stop();
        } catch (_) {}
      }
      return;
    }
    final entries = _ambientMixerTracks.entries.toList(growable: false);
    final primary = entries.first;
    final primaryVol = (primary.value * _config.focusSoundVolume)
        .clamp(FocusSoundService.minimumAudibleVolume, 1.0)
        .toDouble();
    try {
      await _sound.setVolume(primaryVol);
      await _sound.play(primary.key);
    } catch (_) {}
    await _syncExtraMixerPlayers(play: entries.length >= 2);
  }

  Future<void> _syncExtraMixerPlayers({required bool play}) async {
    if (!play || _ambientMixerTracks.length < 2) {
      await _stopExtraMixerPlayers();
      return;
    }
    final entries = _ambientMixerTracks.entries.skip(1).toList(growable: false);
    final wantedIds = entries.map((e) => e.key).toSet();
    final staleIds = _extraMixerPlayers.keys
        .where((id) => !wantedIds.contains(id))
        .toList(growable: false);
    for (final staleId in staleIds) {
      final stalePlayer = _extraMixerPlayers.remove(staleId);
      if (stalePlayer != null) {
        try {
          await stalePlayer.stop();
          await stalePlayer.dispose();
        } catch (_) {}
      }
    }
    for (final entry in entries) {
      final vol = (entry.value * _config.focusSoundVolume)
          .clamp(0.05, 1.0)
          .toDouble();
      final existing = _extraMixerPlayers[entry.key];
      if (existing != null) {
        try {
          await existing.setVolume(vol);
        } catch (_) {}
        continue;
      }
      final assetPath = FocusSoundCatalog.assetMap[entry.key];
      if (assetPath == null || assetPath.isEmpty) continue;
      try {
        final player = AudioPlayer();
        _extraMixerPlayers[entry.key] = player;
        await player.setReleaseMode(ReleaseMode.loop);
        await player.play(AssetSource(assetPath), volume: vol);
      } catch (_) {
        // Ignore platform channel failures in host widget/unit tests.
      }
    }
  }

  Future<void> _stopExtraMixerPlayers() async {
    if (_extraMixerPlayers.isEmpty) return;
    final players = _extraMixerPlayers.values.toList(growable: false);
    _extraMixerPlayers.clear();
    for (final player in players) {
      try {
        await player.stop();
        await player.dispose();
      } catch (_) {}
    }
  }

  void recordFocusLeaveAppPenalty() {
    unawaited(_recordStrictFocusPenalty(FocusPenaltyReason.leaveApp));
  }

  Future<void> _recordStrictFocusPenalty(
    FocusPenaltyReason reason, {
    String? appPackage,
  }) async {
    if (!_config.strictFocusMode ||
        !_state.isRunning ||
        _state.type != PomodoroType.focus) {
      return;
    }
    final now = clock.now();
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
    final nextPenalties = [penalty, ..._penalties].take(100).toList();
    await _savePenaltyList(nextPenalties);
    _penalties = nextPenalties;
    _persistedRevision++;
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
    final ownsEffect = _captureEffectOwner(runtime: true, config: true);
    if (!ownsEffect()) return;
    if (!_config.strictFocusMode ||
        !_config.monitorDistractingApps ||
        !_state.isRunning ||
        _state.type != PomodoroType.focus) {
      return;
    }
    final packageName = await _distraction.getForegroundApp();
    if (!ownsEffect()) return;
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
    unawaited(
      _recordStrictFocusPenalty(
        FocusPenaltyReason.distractingApp,
        appPackage: packageName,
      ),
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

  List<PomodoroSession> get todayFocusSessions =>
      focusSessionsForDate(clock.now());

  List<PomodoroSession> focusSessionsForDate(DateTime date) => _sessions
      .where(
        (session) =>
            session.type == PomodoroType.focus &&
            _isSameDay(session.startTime, date),
      )
      .toList();

  int get totalFocusMinutes {
    return _sessions
            .where((s) => s.type == PomodoroType.focus)
            .fold(0, (sum, s) => sum + s.durationSeconds) ~/
        60;
  }

  List<PomodoroFocusPenalty> get todayPenalties {
    final now = clock.now();
    return _penalties
        .where((p) => _isSameDay(p.occurredAt, now))
        .toList(growable: false);
  }

  @override
  void dispose() {
    _disposed = true;
    _preferences?.removeListener(_syncPreferenceDefault);
    _preferencesAuth?.removeListener(_syncPreferenceDefault);
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _syncPreferenceDefault,
    );
    _snapshotClearRetryTimer?.cancel();
    _cancelTimer();
    if (_lifecycleAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _lifecycleAttached = false;
    }
    // 不 dispose FocusSoundService（它是进程级单例），只停播。
    // ignore: discarded_futures
    _sound.stop();
    // ignore: discarded_futures
    _stopExtraMixerPlayers();
    // ignore: discarded_futures
    _restoreFocusDndIfNeeded(notify: false);
    _distractionTimer?.cancel();
    _timerTicks.dispose();
    super.dispose();
  }
}

class _PomodoroConfigReceipt {
  final PomodoroConfig config;
  final int generation;
  final int accountGeneration;
  final AccountPreferenceWriteToken token;
  final AuthProvider? auth;
  final int? session;
  final bool changed;
  const _PomodoroConfigReceipt(
    this.config,
    this.generation,
    this.accountGeneration,
    this.token,
    this.auth,
    this.session,
    this.changed,
  );
}

/// 单文件本地持久化的 JSON 编码条数阈值：超过后挪到后台 isolate 编码。
const int _isolateEncodeMinItems = 500;

/// 会话记录保留上限（超出裁剪最旧记录）。
const int _maxPomodoroSessions = 500;

/// 正计时崩溃恢复的累计上限（对齐 _completeSession 的 clamp(1, 24h)）。
const int _maxCountUpSnapshotSeconds = 24 * 60 * 60;

String _encodePomodoroSessionsPayload(List<PomodoroSession> sessions) =>
    json.encode(sessions.map((e) => e.toJson()).toList());
