/// 周报 / 月报生成引擎（Task T-43）。
///
/// 离线汇总本地数据，输出可在"我的"页面查看的报告。不依赖 AI 服务。
library;

import '../models/habit.dart';
import '../models/pomodoro.dart';
import '../models/time_entry.dart';
import '../models/todo.dart';

class PeriodReport {
  /// 报告覆盖范围起点（含）。
  final DateTime start;

  /// 报告覆盖范围终点（含）。
  final DateTime end;

  /// 周期内创建的待办数。
  final int todosCreated;

  /// 周期内完成的待办数。
  final int todosCompleted;

  /// 周期内打卡的习惯次数总和。
  final int habitCheckIns;

  /// 周期内已坚持的最长习惯连续天数。
  final int longestHabitStreak;

  /// 周期内完成的番茄数。
  final int focusSessions;

  /// 周期内累计专注秒数。
  final int focusSeconds;

  /// 周期内累计时间足迹秒数。
  final int timeEntrySeconds;

  /// 各类别时间足迹秒数。
  final Map<TimeEntryCategory, int> timeEntryByCategory;

  /// 完成率（完成 / 创建）。
  double get todoCompletionRate {
    if (todosCreated == 0) return 0;
    return (todosCompleted / todosCreated).clamp(0.0, 1.0);
  }

  /// 专注分钟。
  int get focusMinutes => focusSeconds ~/ 60;

  /// 时间足迹分钟。
  int get timeEntryMinutes => timeEntrySeconds ~/ 60;

  const PeriodReport({
    required this.start,
    required this.end,
    required this.todosCreated,
    required this.todosCompleted,
    required this.habitCheckIns,
    required this.longestHabitStreak,
    required this.focusSessions,
    required this.focusSeconds,
    required this.timeEntrySeconds,
    required this.timeEntryByCategory,
  });
}

class ReportEngine {
  ReportEngine._();

  /// 生成 [start, end] 区间的报告。
  ///
  /// [start]/[end] 应为日期对齐（hour=0），end 含当日。
  static PeriodReport buildReport({
    required DateTime start,
    required DateTime end,
    required List<TodoItem> todos,
    required List<Habit> habits,
    required List<PomodoroSession> sessions,
    required List<TimeEntry> timeEntries,
  }) {
    final endExclusive = DateTime(end.year, end.month, end.day + 1);

    bool inRange(DateTime d) =>
        !d.isBefore(start) && d.isBefore(endExclusive);

    final created = todos.where((t) => inRange(t.createdAt)).length;
    final completed = todos.where((t) {
      final c = t.completedAt;
      return t.isCompleted && c != null && inRange(c);
    }).length;

    var habitCheckIns = 0;
    var longestStreak = 0;
    for (final h in habits) {
      for (final entry in h.completions.entries) {
        final d = _parseDateKey(entry.key);
        if (d != null && inRange(d)) habitCheckIns += entry.value;
      }
      longestStreak = longestStreak > h.currentStreak
          ? longestStreak
          : h.currentStreak;
    }

    final focusSessions = sessions
        .where(
          (s) => s.type == PomodoroType.focus && inRange(s.endTime),
        )
        .toList();
    final focusSeconds = focusSessions.fold<int>(
      0,
      (a, s) => a + s.durationSeconds,
    );

    final periodEntries = timeEntries.where((e) => inRange(e.startAt)).toList();
    final timeEntrySeconds = periodEntries.fold<int>(
      0,
      (a, e) => a + e.durationSeconds,
    );
    final byCategory = <TimeEntryCategory, int>{};
    for (final e in periodEntries) {
      byCategory[e.category] =
          (byCategory[e.category] ?? 0) + e.durationSeconds;
    }

    return PeriodReport(
      start: start,
      end: end,
      todosCreated: created,
      todosCompleted: completed,
      habitCheckIns: habitCheckIns,
      longestHabitStreak: longestStreak,
      focusSessions: focusSessions.length,
      focusSeconds: focusSeconds,
      timeEntrySeconds: timeEntrySeconds,
      timeEntryByCategory: byCategory,
    );
  }

  /// 本周（周一—周日）。
  static PeriodReport thisWeek({
    required List<TodoItem> todos,
    required List<Habit> habits,
    required List<PomodoroSession> sessions,
    required List<TimeEntry> timeEntries,
    DateTime? now,
  }) {
    final base = now ?? DateTime.now();
    final today = DateTime(base.year, base.month, base.day);
    final start = today.subtract(Duration(days: today.weekday - 1));
    final end = start.add(const Duration(days: 6));
    return buildReport(
      start: start,
      end: end,
      todos: todos,
      habits: habits,
      sessions: sessions,
      timeEntries: timeEntries,
    );
  }

  /// 本月（自然月）。
  static PeriodReport thisMonth({
    required List<TodoItem> todos,
    required List<Habit> habits,
    required List<PomodoroSession> sessions,
    required List<TimeEntry> timeEntries,
    DateTime? now,
  }) {
    final base = now ?? DateTime.now();
    final start = DateTime(base.year, base.month, 1);
    final end = DateTime(base.year, base.month + 1, 0);
    return buildReport(
      start: start,
      end: end,
      todos: todos,
      habits: habits,
      sessions: sessions,
      timeEntries: timeEntries,
    );
  }

  static DateTime? _parseDateKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }
}
