import 'dart:async';
import 'dart:convert';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../core/domain_event_bus.dart';
import '../core/focus_sound_catalog.dart';
import '../models/pomodoro.dart';
import '../services/focus_distraction_service.dart';
import '../services/focus_dnd_service.dart';
import '../services/focus_sound_service.dart';
import '../services/account_local_data_cleaner.dart';
import 'cloud_sync_provider.dart';
import 'notification_service.dart';
import 'time_audit_provider.dart';

class PomodoroProvider extends ChangeNotifier with WidgetsBindingObserver {
  /// 运行态快照的持久化键：进程被杀重启后据此恢复进行中的专注。
  /// Android 小组件的 `focus_timer_ends_at_millis` 与 `endsAtMs` 同源。
  static const String runningSnapshotKey = 'pomodoro_running_snapshot';

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
  bool _dndActive = false;
  bool _dndEnableInFlight = false;
  bool _dndRestoreInFlight = false;
  Timer? _distractionTimer;
  FocusDistractionStatus _distractionStatus =
      const FocusDistractionStatus.unavailable();
  String? _lastDistractingPackage;

  PomodoroState get state => _state;
  int get focusTimerEndsAtMillis =>
      _state.isRunning && !_state.isCountUp ? _activeAnchorMs ?? 0 : 0;
  int get focusTimerStartedAtMillis =>
      _state.isRunning && _state.isCountUp ? _activeAnchorMs ?? 0 : 0;
  PomodoroConfig get config => _config;
  List<PomodoroSession> get sessions => _sessions;
  List<PomodoroFocusPenalty> get penalties => List.unmodifiable(_penalties);
  int get persistedRevision => _persistedRevision;
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
    await setWhiteNoiseSound(FocusSoundCatalog.none, preview: false);
    await _sound.stop();
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
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final runtimeRevision = _runtimeRevision;
    final prefs = await SharedPreferences.getInstance();
    if (!_isCurrentStorageGeneration(generation, accountGeneration) ||
        runtimeRevision != _runtimeRevision) {
      return;
    }

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
    _runningSnapshotHydrated = false;
    _runningAccountGeneration = null;
    _timerTicks.value = 0;
    _config = PomodoroConfig();
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
    _dndEnableInFlight = false;
    _distractionTimer?.cancel();
    _distractionTimer = null;
    _distractionStatus = const FocusDistractionStatus.unavailable();
    _lastDistractingPackage = null;
    // ignore: discarded_futures
    _distraction.setFocusBlocker(enabled: false, packages: const []);
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

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pomodoro_config', json.encode(_config.toJson()));
  }

  Future<void> _touchAndSaveConfig() async {
    _config.touch();
    await _saveConfig();
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

  /// 把当前运行态写入快照。在启动与每个计时 tick 调用；锚点不变时
  /// payload 相同，直接跳过落盘（快照内容与 `endsAt` 无关的秒级推进）。
  void _persistRunningSnapshot() {
    if (!_state.isRunning || _activeAnchorMs == null) return;
    final payload = json.encode(_runningSnapshot());
    if (payload == _lastSnapshotPayload || payload == _pendingSnapshotPayload) {
      return;
    }
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final revision = ++_snapshotRevision;
    _pendingSnapshotPayload = payload;
    unawaited(
      _queueSnapshotOp(
        (prefs) => prefs.setString(runningSnapshotKey, payload),
        onSettled: (succeeded) {
          if (_isCurrentStorageGeneration(generation, accountGeneration) &&
              revision == _snapshotRevision) {
            _pendingSnapshotPayload = null;
            _lastSnapshotPayload = succeeded ? payload : null;
          }
        },
      ),
    );
  }

  /// 离开运行态（暂停 / 手动停止 / 完成 / 重置 / 重置本地数据）时清快照。
  void _clearRunningSnapshot() {
    _activeAnchorMs = null;
    _activeSessionId = null;
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
    final sound = _state.whiteNoiseSound;
    final shouldPlay =
        _state.isRunning &&
        sound != 'none' &&
        (_state.type == PomodoroType.focus || _config.playSoundInBreak);
    if (shouldPlay) {
      if (!_sound.isPlaying || _sound.currentSound != sound) {
        return _playFocusSound(sound);
      } else {
        await _sound.setVolume(_config.focusSoundVolume);
        return true;
      }
    } else {
      if (_sound.isPlaying) {
        await _sound.stop();
      }
      return true;
    }
  }

  Future<bool> _playFocusSound(String sound) async {
    await _sound.setVolume(_config.focusSoundVolume);
    return _sound.play(sound);
  }

  Future<bool> _previewWhiteNoiseSound(String sound) async {
    if (sound == FocusSoundCatalog.none || _state.isRunning) return true;
    await _sound.setVolume(_config.focusSoundVolume);
    return _sound.preview(sound);
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
      nextDuration = _config.focusDuration;
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
      if (completedType == PomodoroType.focus) {
        _notifier?.notifyPomodoroComplete(taskName: completedState.taskName);
      } else {
        _notifier?.notifyBreakComplete();
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
    _runtimeRevision++;
    _runningSnapshotHydrated = true;
    _cancelTimer();
    _clearRunningSnapshot();
    unawaited(_recordStrictFocusPenalty(FocusPenaltyReason.reset));
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
    _synchronizeTimerToAnchor(completeExpired: false);
    _completeSession();
  }

  void setCountUpMode(bool enabled) {
    if (_state.isRunning) return;
    _runtimeRevision++;
    _runningSnapshotHydrated = true;
    _cancelTimer();
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
    await _touchAndSaveConfig();
    _persistedRevision++;
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
    _persistedRevision++;
    notifyListeners();
    await _touchAndSaveConfig();
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
    _persistedRevision++;
    notifyListeners();
    await _touchAndSaveConfig();
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

  Future<void> setFocusRoomId(String? roomId) async {
    final clean = roomId?.trim();
    final nextRoomId = clean == null || clean.isEmpty ? null : clean;
    if (_config.focusRoomId == nextRoomId && _state.focusRoomId == nextRoomId) {
      return;
    }
    _config.focusRoomId = nextRoomId;
    _state = _state.copyWith(
      focusRoomId: _config.focusRoomId,
      clearFocusRoom: _config.focusRoomId == null,
    );
    await _touchAndSaveConfig();
    _persistedRevision++;
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

  Future<void> setMonitorDistractingApps(bool enabled) async {
    if (_config.monitorDistractingApps == enabled) return;
    _config.monitorDistractingApps = enabled;
    _persistedRevision++;
    notifyListeners();
    await _touchAndSaveConfig();
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
    if (_config.distractingAppPackages.length == normalized.length &&
        _config.distractingAppPackages.every(normalized.contains)) {
      return;
    }
    _config.distractingAppPackages = normalized;
    await _touchAndSaveConfig();
    _persistedRevision++;
    notifyListeners();
    _syncDistractionMonitorToState();
  }

  Future<bool> setWhiteNoiseSound(String sound, {bool preview = true}) async {
    final normalized = sound.startsWith('custom:')
        ? sound
        : FocusSoundCatalog.normalizeForPlayback(sound);
    if (_config.whiteNoiseSound == normalized &&
        _state.whiteNoiseSound == normalized) {
      if (preview &&
          normalized != FocusSoundCatalog.none &&
          !_state.isRunning) {
        return _previewWhiteNoiseSound(normalized);
      }
      return true;
    }
    _state = _state.copyWith(whiteNoiseSound: normalized);
    _config.whiteNoiseSound = normalized;
    await _touchAndSaveConfig();
    _persistedRevision++;
    notifyListeners();
    final playbackOk = await _syncSoundToState();
    if (!playbackOk &&
        _state.isRunning &&
        normalized != FocusSoundCatalog.none) {
      _state = _state.copyWith(whiteNoiseSound: FocusSoundCatalog.none);
      _config.whiteNoiseSound = FocusSoundCatalog.none;
      await _touchAndSaveConfig();
      _persistedRevision++;
      notifyListeners();
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
    if (_config.focusSoundVolume == normalized) {
      if (preview && !_state.isRunning) {
        return _previewWhiteNoiseSound(_focusSoundPreviewFallback);
      }
      return true;
    }
    _config.focusSoundVolume = normalized;
    await _touchAndSaveConfig();
    _persistedRevision++;
    notifyListeners();
    await _sound.setVolume(normalized);
    if (preview && !_state.isRunning) {
      return _previewWhiteNoiseSound(_focusSoundPreviewFallback);
    }
    return true;
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

  List<PomodoroSession> get todayFocusSessions {
    final now = clock.now();
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
    final now = clock.now();
    return _penalties
        .where((p) => _isSameDay(p.occurredAt, now))
        .toList(growable: false);
  }

  @override
  void dispose() {
    _disposed = true;
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
    _restoreFocusDndIfNeeded(notify: false);
    _distractionTimer?.cancel();
    _timerTicks.dispose();
    super.dispose();
  }
}

/// 单文件本地持久化的 JSON 编码条数阈值：超过后挪到后台 isolate 编码。
const int _isolateEncodeMinItems = 500;

/// 会话记录保留上限（超出裁剪最旧记录）。
const int _maxPomodoroSessions = 500;

/// 正计时崩溃恢复的累计上限（对齐 _completeSession 的 clamp(1, 24h)）。
const int _maxCountUpSnapshotSeconds = 24 * 60 * 60;

String _encodePomodoroSessionsPayload(List<PomodoroSession> sessions) =>
    json.encode(sessions.map((e) => e.toJson()).toList());
