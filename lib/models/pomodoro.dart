enum PomodoroType { focus, shortBreak, longBreak }

class PomodoroConfig {
  int focusDuration;        // seconds, default 1500 (25min)
  int shortBreakDuration;   // seconds, default 300 (5min)
  int longBreakDuration;    // seconds, default 900 (15min)
  int sessionsPerLongBreak; // default 4
  bool whiteNoiseEnabled;
  bool autoStartBreaks;
  bool autoStartFocus;

  PomodoroConfig({
    this.focusDuration = 1500,
    this.shortBreakDuration = 300,
    this.longBreakDuration = 900,
    this.sessionsPerLongBreak = 4,
    this.whiteNoiseEnabled = false,
    this.autoStartBreaks = false,
    this.autoStartFocus = false,
  });

  Map<String, dynamic> toJson() => {
        'focusDuration': focusDuration,
        'shortBreakDuration': shortBreakDuration,
        'longBreakDuration': longBreakDuration,
        'sessionsPerLongBreak': sessionsPerLongBreak,
        'whiteNoiseEnabled': whiteNoiseEnabled,
        'autoStartBreaks': autoStartBreaks,
        'autoStartFocus': autoStartFocus,
      };

  factory PomodoroConfig.fromJson(Map<String, dynamic> json) => PomodoroConfig(
        focusDuration: json['focusDuration'] ?? 1500,
        shortBreakDuration: json['shortBreakDuration'] ?? 300,
        longBreakDuration: json['longBreakDuration'] ?? 900,
        sessionsPerLongBreak: json['sessionsPerLongBreak'] ?? 4,
        whiteNoiseEnabled: json['whiteNoiseEnabled'] ?? false,
        autoStartBreaks: json['autoStartBreaks'] ?? false,
        autoStartFocus: json['autoStartFocus'] ?? false,
      );
}

class PomodoroSession {
  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final int durationSeconds;
  final PomodoroType type;
  final String? taskName;
  final bool whiteNoiseEnabled;

  PomodoroSession({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
    required this.type,
    this.taskName,
    this.whiteNoiseEnabled = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'durationSeconds': durationSeconds,
        'type': type.index,
        'taskName': taskName,
        'whiteNoiseEnabled': whiteNoiseEnabled,
      };

  factory PomodoroSession.fromJson(Map<String, dynamic> json) => PomodoroSession(
        id: json['id'],
        startTime: DateTime.parse(json['startTime']),
        endTime: DateTime.parse(json['endTime']),
        durationSeconds: json['durationSeconds'],
        type: PomodoroType.values[json['type']],
        taskName: json['taskName'],
        whiteNoiseEnabled: json['whiteNoiseEnabled'] ?? false,
      );
}

class PomodoroState {
  final int remainingSeconds;
  final int totalSeconds;
  final bool isRunning;
  final PomodoroType type;
  final int completedSessions;
  final String? taskName;
  final bool whiteNoiseEnabled;

  const PomodoroState({
    required this.remainingSeconds,
    required this.totalSeconds,
    required this.isRunning,
    required this.type,
    required this.completedSessions,
    this.taskName,
    this.whiteNoiseEnabled = false,
  });

  double get progress => totalSeconds > 0 ? remainingSeconds / totalSeconds : 1.0;

  PomodoroState copyWith({
    int? remainingSeconds,
    int? totalSeconds,
    bool? isRunning,
    PomodoroType? type,
    int? completedSessions,
    String? taskName,
    bool? whiteNoiseEnabled,
    bool clearTaskName = false,
  }) =>
      PomodoroState(
        remainingSeconds: remainingSeconds ?? this.remainingSeconds,
        totalSeconds: totalSeconds ?? this.totalSeconds,
        isRunning: isRunning ?? this.isRunning,
        type: type ?? this.type,
        completedSessions: completedSessions ?? this.completedSessions,
        taskName: clearTaskName ? null : (taskName ?? this.taskName),
        whiteNoiseEnabled: whiteNoiseEnabled ?? this.whiteNoiseEnabled,
      );
}