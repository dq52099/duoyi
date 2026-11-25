import '../core/focus_sound_catalog.dart';
import '../core/i18n.dart';

enum PomodoroType { focus, shortBreak, longBreak }

class PomodoroConfig {
  static const int defaultFocusDuration = 1500;
  static const int defaultShortBreakDuration = 300;
  static const int defaultLongBreakDuration = 900;
  static const double defaultFocusSoundVolume = 0.6;
  static const int _minStoredDurationSeconds = 60;
  static const int _maxStoredDurationSeconds = 12 * 60 * 60;

  int focusDuration; // seconds, default 1500 (25min)
  bool focusDurationUsesDefault;
  int shortBreakDuration; // seconds, default 300 (5min)
  int longBreakDuration; // seconds, default 900 (15min)
  int sessionsPerLongBreak; // default 4
  String whiteNoiseSound;
  bool autoStartBreaks;
  bool autoStartFocus;
  bool autoEnableDnd;
  bool strictFocusMode;
  bool monitorDistractingApps;
  List<String> distractingAppPackages;
  String? focusRoomId;
  double focusSoundVolume;
  DateTime updatedAt;

  /// 休息阶段是否继续播放白噪音。默认 `false`，与 `design.md §3.7` 对齐
  /// （focus 播、break 可配置）。
  bool playSoundInBreak;

  PomodoroConfig({
    int? focusDuration,
    bool? focusDurationUsesDefault,
    this.shortBreakDuration = defaultShortBreakDuration,
    this.longBreakDuration = defaultLongBreakDuration,
    this.sessionsPerLongBreak = 4,
    this.whiteNoiseSound = 'none',
    this.autoStartBreaks = false,
    this.autoStartFocus = false,
    this.autoEnableDnd = false,
    this.strictFocusMode = false,
    this.monitorDistractingApps = false,
    List<String>? distractingAppPackages,
    this.focusRoomId,
    this.focusSoundVolume = defaultFocusSoundVolume,
    this.playSoundInBreak = false,
    DateTime? updatedAt,
  }) : focusDuration = focusDuration ?? defaultFocusDuration,
       focusDurationUsesDefault =
           focusDurationUsesDefault ?? focusDuration == null,
       distractingAppPackages = distractingAppPackages ?? const <String>[],
       updatedAt = updatedAt ?? DateTime.now();

  PomodoroConfig copyWith({
    int? focusDuration,
    bool? focusDurationUsesDefault,
  }) => PomodoroConfig(
    focusDuration: focusDuration ?? this.focusDuration,
    focusDurationUsesDefault:
        focusDurationUsesDefault ?? this.focusDurationUsesDefault,
    shortBreakDuration: shortBreakDuration,
    longBreakDuration: longBreakDuration,
    sessionsPerLongBreak: sessionsPerLongBreak,
    whiteNoiseSound: whiteNoiseSound,
    autoStartBreaks: autoStartBreaks,
    autoStartFocus: autoStartFocus,
    autoEnableDnd: autoEnableDnd,
    strictFocusMode: strictFocusMode,
    monitorDistractingApps: monitorDistractingApps,
    distractingAppPackages: List.of(distractingAppPackages),
    focusRoomId: focusRoomId,
    focusSoundVolume: focusSoundVolume,
    playSoundInBreak: playSoundInBreak,
    updatedAt: updatedAt,
  );

  void touch() {
    updatedAt = DateTime.now();
  }

  Map<String, dynamic> toJson() => {
    'focusDuration': focusDuration,
    'focusDurationUsesDefault': focusDurationUsesDefault,
    'shortBreakDuration': shortBreakDuration,
    'longBreakDuration': longBreakDuration,
    'sessionsPerLongBreak': sessionsPerLongBreak,
    'whiteNoiseSound': whiteNoiseSound,
    'autoStartBreaks': autoStartBreaks,
    'autoStartFocus': autoStartFocus,
    'autoEnableDnd': autoEnableDnd,
    'strictFocusMode': strictFocusMode,
    'monitorDistractingApps': monitorDistractingApps,
    'distractingAppPackages': distractingAppPackages,
    'focusRoomId': focusRoomId,
    'focusSoundVolume': focusSoundVolume,
    'playSoundInBreak': playSoundInBreak,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory PomodoroConfig.fromJson(Map<String, dynamic> json) {
    String sound = 'none';
    if (json.containsKey('whiteNoiseSound')) {
      sound = json['whiteNoiseSound'];
    } else if (json['whiteNoiseEnabled'] == true) {
      sound = 'rain'; // Fallback for old data
    }

    return PomodoroConfig(
      // Older valid values have no provenance; preserve explicit 25 minutes.
      focusDurationUsesDefault: json['focusDurationUsesDefault'] is bool
          ? json['focusDurationUsesDefault'] as bool
          : _storedDuration(json['focusDuration'], 0) == 0,
      focusDuration: _storedDuration(
        json['focusDuration'],
        defaultFocusDuration,
      ),
      shortBreakDuration: _storedDuration(
        json['shortBreakDuration'],
        defaultShortBreakDuration,
      ),
      longBreakDuration: _storedDuration(
        json['longBreakDuration'],
        defaultLongBreakDuration,
      ),
      sessionsPerLongBreak: _intInRange(json['sessionsPerLongBreak'], 4, 1, 20),
      whiteNoiseSound: _normalizeStoredFocusSound(sound),
      autoStartBreaks: json['autoStartBreaks'] ?? false,
      autoStartFocus: json['autoStartFocus'] ?? false,
      autoEnableDnd: json['autoEnableDnd'] ?? false,
      strictFocusMode: json['strictFocusMode'] ?? false,
      monitorDistractingApps: json['monitorDistractingApps'] ?? false,
      distractingAppPackages:
          (json['distractingAppPackages'] as List?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList() ??
          const <String>[],
      focusRoomId: json['focusRoomId']?.toString(),
      focusSoundVolume: _doubleInRange(
        json['focusSoundVolume'],
        defaultFocusSoundVolume,
        0.4,
        1.0,
      ),
      playSoundInBreak: json['playSoundInBreak'] ?? false,
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static int _storedDuration(Object? raw, int fallback) {
    final value = switch (raw) {
      final num n => n.toInt(),
      final String s => int.tryParse(s.trim()),
      _ => null,
    };
    if (value == null ||
        value < _minStoredDurationSeconds ||
        value > _maxStoredDurationSeconds) {
      return fallback;
    }
    return value;
  }

  static int _intInRange(Object? raw, int fallback, int min, int max) {
    final value = switch (raw) {
      final num n => n.toInt(),
      final String s => int.tryParse(s.trim()),
      _ => null,
    };
    if (value == null || value < min || value > max) return fallback;
    return value;
  }

  static double _doubleInRange(
    Object? raw,
    double fallback,
    double min,
    double max,
  ) {
    final value = switch (raw) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s.trim()),
      _ => null,
    };
    if (value == null || value < min || value > max) return fallback;
    return value;
  }
}

enum FocusPenaltyReason { pause, skip, reset, leaveApp, distractingApp }

extension FocusPenaltyReasonX on FocusPenaltyReason {
  String get key {
    switch (this) {
      case FocusPenaltyReason.pause:
        return 'pause';
      case FocusPenaltyReason.skip:
        return 'skip';
      case FocusPenaltyReason.reset:
        return 'reset';
      case FocusPenaltyReason.leaveApp:
        return 'leaveApp';
      case FocusPenaltyReason.distractingApp:
        return 'distractingApp';
    }
  }

  String get label => labelFor(I18n.current);

  String labelFor(AppLocale locale) {
    final isEn = locale == AppLocale.en;
    switch (this) {
      case FocusPenaltyReason.pause:
        return isEn ? 'Paused focus' : '暂停专注';
      case FocusPenaltyReason.skip:
        return isEn ? 'Skipped focus' : '跳过专注';
      case FocusPenaltyReason.reset:
        return isEn ? 'Reset focus' : '重置专注';
      case FocusPenaltyReason.leaveApp:
        return isEn ? 'Left the app' : '离开应用';
      case FocusPenaltyReason.distractingApp:
        return isEn ? 'Opened a distracting app' : '打开分心应用';
    }
  }

  static FocusPenaltyReason fromKey(String? key) {
    for (final reason in FocusPenaltyReason.values) {
      if (reason.key == key) return reason;
    }
    return FocusPenaltyReason.pause;
  }
}

class PomodoroFocusPenalty {
  final String id;
  final DateTime occurredAt;
  final FocusPenaltyReason reason;
  final int affectedSeconds;
  final String? taskName;
  final String? tag;
  final String? focusRoomId;
  final String? appPackage;

  const PomodoroFocusPenalty({
    required this.id,
    required this.occurredAt,
    required this.reason,
    required this.affectedSeconds,
    this.taskName,
    this.tag,
    this.focusRoomId,
    this.appPackage,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'occurredAt': occurredAt.toIso8601String(),
    'updatedAt': occurredAt.toIso8601String(),
    'reason': reason.key,
    // Keep the legacy payload stable while its UI label follows the locale.
    'reasonLabel': reason.labelFor(AppLocale.zh),
    'affectedSeconds': affectedSeconds,
    'taskName': taskName,
    'tag': tag,
    'focusRoomId': focusRoomId,
    'appPackage': appPackage,
  };

  factory PomodoroFocusPenalty.fromJson(Map<String, dynamic> json) {
    final occurredAt =
        DateTime.tryParse(json['occurredAt']?.toString() ?? '') ??
        DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return PomodoroFocusPenalty(
      id:
          json['id']?.toString() ??
          occurredAt.microsecondsSinceEpoch.toString(),
      occurredAt: occurredAt,
      reason: FocusPenaltyReasonX.fromKey(json['reason']?.toString()),
      affectedSeconds: (json['affectedSeconds'] as num?)?.round() ?? 0,
      taskName: json['taskName']?.toString(),
      tag: json['tag']?.toString(),
      focusRoomId: json['focusRoomId']?.toString(),
      appPackage: json['appPackage']?.toString(),
    );
  }
}

class PomodoroSession {
  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final int durationSeconds;
  final PomodoroType type;
  final String? taskName;
  final String whiteNoiseSound;
  final String? tag;
  final String? focusRoomId;
  final DateTime updatedAt;

  PomodoroSession({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
    required this.type,
    this.taskName,
    this.whiteNoiseSound = 'none',
    this.tag,
    this.focusRoomId,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? endTime;

  PomodoroSession copyWith({
    DateTime? startTime,
    DateTime? endTime,
    int? durationSeconds,
    PomodoroType? type,
    String? taskName,
    bool clearTaskName = false,
    String? whiteNoiseSound,
    String? tag,
    bool clearTag = false,
    String? focusRoomId,
    bool clearFocusRoomId = false,
    DateTime? updatedAt,
  }) {
    return PomodoroSession(
      id: id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      type: type ?? this.type,
      taskName: clearTaskName ? null : (taskName ?? this.taskName),
      whiteNoiseSound: whiteNoiseSound ?? this.whiteNoiseSound,
      tag: clearTag ? null : (tag ?? this.tag),
      focusRoomId: clearFocusRoomId ? null : (focusRoomId ?? this.focusRoomId),
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime.toIso8601String(),
    'durationSeconds': durationSeconds,
    'type': type.index,
    'taskName': taskName,
    'whiteNoiseSound': whiteNoiseSound,
    'tag': tag,
    'focusRoomId': focusRoomId,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory PomodoroSession.fromJson(Map<String, dynamic> json) {
    String sound = 'none';
    if (json.containsKey('whiteNoiseSound')) {
      sound = json['whiteNoiseSound'];
    } else if (json['whiteNoiseEnabled'] == true) {
      sound = 'rain'; // Fallback
    }

    return PomodoroSession(
      id: json['id'],
      startTime: DateTime.parse(json['startTime']),
      endTime: DateTime.parse(json['endTime']),
      durationSeconds: json['durationSeconds'],
      type: PomodoroType.values[json['type']],
      taskName: json['taskName'],
      whiteNoiseSound: _normalizeStoredFocusSound(sound),
      tag: json['tag']?.toString(),
      focusRoomId: json['focusRoomId']?.toString(),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.tryParse(json['endTime']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class PomodoroState {
  final int remainingSeconds;
  final int totalSeconds;
  final bool isRunning;
  final bool isCountUp;
  final PomodoroType type;
  final int completedSessions;
  final String? taskName;
  final String whiteNoiseSound;
  final String? tag;
  final String? focusRoomId;

  const PomodoroState({
    required this.remainingSeconds,
    required this.totalSeconds,
    required this.isRunning,
    this.isCountUp = false,
    required this.type,
    required this.completedSessions,
    this.taskName,
    this.whiteNoiseSound = 'none',
    this.tag,
    this.focusRoomId,
  });

  double get progress => isCountUp
      ? 1.0
      : (totalSeconds > 0 ? remainingSeconds / totalSeconds : 1.0);

  PomodoroState copyWith({
    int? remainingSeconds,
    int? totalSeconds,
    bool? isRunning,
    bool? isCountUp,
    PomodoroType? type,
    int? completedSessions,
    String? taskName,
    String? whiteNoiseSound,
    String? tag,
    String? focusRoomId,
    bool clearTaskName = false,
    bool clearTag = false,
    bool clearFocusRoom = false,
  }) => PomodoroState(
    remainingSeconds: remainingSeconds ?? this.remainingSeconds,
    totalSeconds: totalSeconds ?? this.totalSeconds,
    isRunning: isRunning ?? this.isRunning,
    isCountUp: isCountUp ?? this.isCountUp,
    type: type ?? this.type,
    completedSessions: completedSessions ?? this.completedSessions,
    taskName: clearTaskName ? null : (taskName ?? this.taskName),
    whiteNoiseSound: whiteNoiseSound ?? this.whiteNoiseSound,
    tag: clearTag ? null : (tag ?? this.tag),
    focusRoomId: clearFocusRoom ? null : (focusRoomId ?? this.focusRoomId),
  );
}

String _normalizeStoredFocusSound(String sound) {
  final clean = sound.trim();
  if (clean.startsWith('custom:')) return clean;
  return FocusSoundCatalog.normalizeForPlayback(clean);
}
