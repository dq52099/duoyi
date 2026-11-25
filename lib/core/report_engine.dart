/// 周报 / 月报生成引擎（Task T-43）。
///
/// 离线汇总本地数据，输出可在"我的"页面查看的报告。不依赖 AI 服务。
library;

import 'dart:collection';

import '../models/habit.dart';
import '../models/pomodoro.dart';
import '../models/time_entry.dart';
import '../models/todo.dart';
import 'period_report.dart';

export 'period_report.dart';

class ReportEngine {
  ReportEngine._();

  static const int _maxReportCacheEntries = 16;
  static final LinkedHashMap<Object, PeriodReport> _reportCache =
      LinkedHashMap<Object, PeriodReport>();
  static final Map<String, DateTime?> _dateKeyCache = <String, DateTime?>{};

  static ReportComparison compare({
    required PeriodReport current,
    required PeriodReport previous,
  }) {
    return ReportComparison.compare(current: current, previous: previous);
  }

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
    final todosFp = _todosFingerprint(todos);
    final habitsFp = _habitsFingerprint(habits);
    final sessionsFp = _sessionsFingerprint(sessions);
    final entriesFp = _timeEntriesFingerprint(timeEntries);
    final cacheKey = (
      start.millisecondsSinceEpoch,
      end.year,
      end.month,
      end.day,
      todosFp,
      habitsFp,
      sessionsFp,
      entriesFp,
    );
    final cached = _reportCache.remove(cacheKey);
    if (cached != null) {
      _reportCache[cacheKey] = cached;
      return cached;
    }

    bool inRange(DateTime d) => !d.isBefore(start) && d.isBefore(endExclusive);

    var created = 0;
    var completed = 0;
    for (final t in todos) {
      if (inRange(t.createdAt)) created++;
      final c = t.completedAt;
      if (t.isCompleted && c != null && inRange(c)) completed++;
    }

    var habitCheckIns = 0;
    var longestStreak = 0;
    for (final h in habits) {
      for (final entry in h.completions.entries) {
        final d = _parseDateKey(entry.key);
        if (d != null && inRange(d) && h.activeForDate(d)) {
          habitCheckIns += entry.value;
        }
      }
      if (h.currentStreak > longestStreak) {
        longestStreak = h.currentStreak;
      }
    }

    var focusSessionsCount = 0;
    var focusSeconds = 0;
    for (final s in sessions) {
      if (s.type == PomodoroType.focus && inRange(s.endTime)) {
        focusSessionsCount++;
        focusSeconds += s.durationSeconds;
      }
    }

    var timeEntrySeconds = 0;
    final byCategory = <TimeEntryCategory, int>{};
    for (final e in timeEntries) {
      if (inRange(e.startAt)) {
        final dur = e.durationSeconds;
        timeEntrySeconds += dur;
        byCategory[e.category] = (byCategory[e.category] ?? 0) + dur;
      }
    }

    final report = PeriodReport(
      start: start,
      end: end,
      todosCreated: created,
      todosCompleted: completed,
      habitCheckIns: habitCheckIns,
      longestHabitStreak: longestStreak,
      focusSessions: focusSessionsCount,
      focusSeconds: focusSeconds,
      timeEntrySeconds: timeEntrySeconds,
      timeEntryByCategory: Map<Object, int>.unmodifiable(byCategory),
    );
    if (_reportCache.length >= _maxReportCacheEntries) {
      _reportCache.remove(_reportCache.keys.first);
    }
    _reportCache[cacheKey] = report;
    return report;
  }

  static (int, int, int) _todosFingerprint(List<TodoItem> todos) {
    var maxUpdatedMs = 0;
    var hash = 0;
    for (final t in todos) {
      final u = t.updatedAt.millisecondsSinceEpoch;
      if (u > maxUpdatedMs) maxUpdatedMs = u;
      hash = Object.hash(
        hash,
        t.id,
        t.isCompleted,
        t.createdAt.millisecondsSinceEpoch,
        t.completedAt?.millisecondsSinceEpoch ?? -1,
        u,
      );
    }
    return (todos.length, maxUpdatedMs, hash);
  }

  static (int, int, int) _habitsFingerprint(List<Habit> habits) {
    var maxUpdatedMs = 0;
    var hash = 0;
    for (final h in habits) {
      final u = h.updatedAt.millisecondsSinceEpoch;
      if (u > maxUpdatedMs) maxUpdatedMs = u;
      var compHash = 0;
      for (final entry in h.completions.entries) {
        compHash ^= Object.hash(entry.key, entry.value);
      }
      hash = Object.hash(
        hash,
        h.id,
        h.currentStreak,
        h.completions.length,
        compHash,
        h.startDate?.millisecondsSinceEpoch ?? -1,
        h.endDate?.millisecondsSinceEpoch ?? -1,
        h.createdAt.millisecondsSinceEpoch,
        u,
      );
    }
    return (habits.length, maxUpdatedMs, hash);
  }

  static (int, int) _sessionsFingerprint(List<PomodoroSession> sessions) {
    var hash = 0;
    for (final s in sessions) {
      hash = Object.hash(
        hash,
        s.id,
        s.type.index,
        s.endTime.millisecondsSinceEpoch,
        s.durationSeconds,
      );
    }
    return (sessions.length, hash);
  }

  static (int, int, int) _timeEntriesFingerprint(List<TimeEntry> entries) {
    var maxUpdatedMs = 0;
    var hash = 0;
    for (final e in entries) {
      final u = e.updatedAt.millisecondsSinceEpoch;
      if (u > maxUpdatedMs) maxUpdatedMs = u;
      hash = Object.hash(
        hash,
        e.id,
        e.startAt.millisecondsSinceEpoch,
        e.endAt.millisecondsSinceEpoch,
        e.category.index,
        u,
      );
    }
    return (entries.length, maxUpdatedMs, hash);
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
    if (_dateKeyCache.containsKey(key)) {
      return _dateKeyCache[key];
    }
    final parts = key.split('-');
    DateTime? parsed;
    if (parts.length == 3) {
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y != null && m != null && d != null) {
        parsed = DateTime(y, m, d);
      }
    }
    if (_dateKeyCache.length >= 2048) {
      _dateKeyCache.clear();
    }
    _dateKeyCache[key] = parsed;
    return parsed;
  }
}
