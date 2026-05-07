enum PomodoroType { focus, shortBreak, longBreak }

class PomodoroConfig {
  int focusDuration; // seconds, default 1500 (25min)
  int shortBreakDuration; // seconds, default 300 (5min)
  int longBreakDuration; // seconds, default 900 (15min)
  int sessionsPerLongBreak; // default 4
  String whiteNoiseSound;
  bool autoStartBreaks;
  bool autoStartFocus;

  PomodoroConfig({
    this.focusDuration = 1500,
    this.shortBreakDuration = 300,
    this.longBreakDuration = 900,
    this.sessionsPerLongBreak = 4,
    this.whiteNoiseSound = 'none',
    this.autoStartBreaks = false,
    this.autoStartFocus = false,
  });

  Map<String, dynamic> toJson() => {
    'focusDuration': focusDuration,
    'shortBreakDuration': shortBreakDuration,
    'longBreakDuration': longBreakDuration,
    'sessionsPerLongBreak': sessionsPerLongBreak,
    'whiteNoiseSound': whiteNoiseSound,
    'autoStartBreaks': autoStartBreaks,
    'autoStartFocus': autoStartFocus,
  };

  factory PomodoroConfig.fromJson(Map<String, dynamic> json) {
    String sound = 'none';
    if (json.containsKey('whiteNoiseSound')) {
      sound = json['whiteNoiseSound'];
    } else if (json['whiteNoiseEnabled'] == true) {
      sound = 'rain'; // Fallback for old data
    }

    return PomodoroConfig(
      focusDuration: json['focusDuration'] ?? 1500,
      shortBreakDuration: json['shortBreakDuration'] ?? 300,
      longBreakDuration: json['longBreakDuration'] ?? 900,
      sessionsPerLongBreak: json['sessionsPerLongBreak'] ?? 4,
      whiteNoiseSound: sound,
      autoStartBreaks: json['autoStartBreaks'] ?? false,
      autoStartFocus: json['autoStartFocus'] ?? false,
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

  PomodoroSession({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
    required this.type,
    this.taskName,
    this.whiteNoiseSound = 'none',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime.toIso8601String(),
    'durationSeconds': durationSeconds,
    'type': type.index,
    'taskName': taskName,
    'whiteNoiseSound': whiteNoiseSound,
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
      whiteNoiseSound: sound,
    );
  }
}

class PomodoroState {
  final int remainingSeconds;
  final int totalSeconds;
  final bool isRunning;
  final PomodoroType type;
  final int completedSessions;
  final String? taskName;
  final String whiteNoiseSound;

  const PomodoroState({
    required this.remainingSeconds,
    required this.totalSeconds,
    required this.isRunning,
    required this.type,
    required this.completedSessions,
    this.taskName,
    this.whiteNoiseSound = 'none',
  });

  double get progress =>
      totalSeconds > 0 ? remainingSeconds / totalSeconds : 1.0;

  PomodoroState copyWith({
    int? remainingSeconds,
    int? totalSeconds,
    bool? isRunning,
    PomodoroType? type,
    int? completedSessions,
    String? taskName,
    String? whiteNoiseSound,
    bool clearTaskName = false,
  }) => PomodoroState(
    remainingSeconds: remainingSeconds ?? this.remainingSeconds,
    totalSeconds: totalSeconds ?? this.totalSeconds,
    isRunning: isRunning ?? this.isRunning,
    type: type ?? this.type,
    completedSessions: completedSessions ?? this.completedSessions,
    taskName: clearTaskName ? null : (taskName ?? this.taskName),
    whiteNoiseSound: whiteNoiseSound ?? this.whiteNoiseSound,
  );
}
