import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../core/calendar_aggregator.dart';
import '../models/calendar_event.dart';
import '../models/todo.dart';
import '../models/habit.dart';
import '../models/pomodoro.dart';
import '../models/anniversary.dart';
import '../models/course_schedule.dart';
import '../models/diary_entry.dart';
import '../models/countdown.dart';
import '../models/goal.dart';
import '../models/time_entry.dart';

class CalendarProvider extends ChangeNotifier {
  final List<CalendarEvent> _events = [];
  List<CalendarEvent> _externalEvents = const <CalendarEvent>[];
  Object? _lastRebuildSignature;

  List<CalendarEvent> get events => _events;

  /// 设置外部订阅事件（来自 ICS 订阅）。会触发下次 rebuild 时合并。
  // ignore: use_setters_to_change_properties
  void setExternalEvents(List<CalendarEvent> events) {
    _externalEvents = List<CalendarEvent>.unmodifiable(events);
    _lastRebuildSignature = null;
  }

  /// 重建所有事件索引。
  /// 新增的 anniversaries/courses/diaries/countdowns/goals 均以可选参数传入，保证调用方兼容。
  void rebuild(
    List<TodoItem> todos,
    List<Habit> habits,
    List<PomodoroSession> pomodoroSessions,
    ColorScheme colorScheme, {
    List<Anniversary>? anniversaries,
    List<CourseItem>? courses,
    ScheduleSettings? courseSettings,
    List<DiaryEntry>? diaries,
    List<CountdownItem>? countdowns,
    List<GoalItem>? goals,
    List<TimeEntry>? timeEntries,
  }) {
    final signature = _buildSignature(
      todos,
      habits,
      pomodoroSessions,
      colorScheme,
      anniversaries: anniversaries,
      courses: courses,
      courseSettings: courseSettings,
      diaries: diaries,
      countdowns: countdowns,
      goals: goals,
      timeEntries: timeEntries,
    );
    if (_lastRebuildSignature == signature) return;

    final previousEvents = List<CalendarEvent>.of(_events);
    final nextEvents = CalendarAggregator.buildEvents(
      todos: todos,
      habits: habits,
      pomodoroSessions: pomodoroSessions,
      colorScheme: colorScheme,
      anniversaries: anniversaries,
      courses: courses,
      courseSettings: courseSettings,
      diaries: diaries,
      countdowns: countdowns,
      goals: goals,
      timeEntries: timeEntries,
    );
    _events
      ..clear()
      ..addAll(nextEvents)
      ..addAll(_externalEvents);

    if (!_eventsEqual(previousEvents, _events)) {
      _lastRebuildSignature = signature;
      _notifyListenersSafely();
      return;
    }
    _lastRebuildSignature = signature;
  }

  int _buildSignature(
    List<TodoItem> todos,
    List<Habit> habits,
    List<PomodoroSession> pomodoroSessions,
    ColorScheme colorScheme, {
    List<Anniversary>? anniversaries,
    List<CourseItem>? courses,
    ScheduleSettings? courseSettings,
    List<DiaryEntry>? diaries,
    List<CountdownItem>? countdowns,
    List<GoalItem>? goals,
    List<TimeEntry>? timeEntries,
  }) {
    final now = DateTime.now();
    final todayKey = DateTime(
      now.year,
      now.month,
      now.day,
    ).millisecondsSinceEpoch;
    return Object.hashAll([
      todayKey,
      colorScheme.primary,
      _hashTodos(todos),
      _hashHabits(habits),
      _hashPomodoroSessions(pomodoroSessions),
      _hashAnniversaries(anniversaries),
      _hashCourses(courses, courseSettings),
      _hashDiaries(diaries),
      _hashCountdowns(countdowns),
      _hashGoals(goals),
      _hashTimeEntries(timeEntries),
    ]);
  }

  int _hashTodos(List<TodoItem> todos) {
    return Object.hashAll(
      todos.map(
        (t) => Object.hash(
          t.id,
          t.title,
          t.date.millisecondsSinceEpoch,
          t.dueDate?.millisecondsSinceEpoch,
          t.isCompleted,
        ),
      ),
    );
  }

  int _hashHabits(List<Habit> habits) {
    return Object.hashAll(
      habits.map((h) {
        final completions = h.completions.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        return Object.hashAll([
          h.id,
          h.name,
          h.colorValue,
          h.kind.index,
          h.targetCount,
          Object.hashAll(h.activeWeekdays),
          h.weeklyTarget,
          h.startDate?.millisecondsSinceEpoch,
          h.endDate?.millisecondsSinceEpoch,
          Object.hashAll(completions.map((e) => Object.hash(e.key, e.value))),
        ]);
      }),
    );
  }

  int _hashPomodoroSessions(List<PomodoroSession> sessions) {
    return Object.hashAll(
      sessions.map(
        (s) => Object.hash(
          s.id,
          s.startTime.millisecondsSinceEpoch,
          s.endTime.millisecondsSinceEpoch,
          s.durationSeconds,
          s.type.index,
          s.taskName,
          s.whiteNoiseSound,
        ),
      ),
    );
  }

  int _hashAnniversaries(List<Anniversary>? anniversaries) {
    if (anniversaries == null) return 0;
    return Object.hashAll(
      anniversaries.map(
        (a) => Object.hash(
          a.id,
          a.title,
          a.originDate.millisecondsSinceEpoch,
          a.type.index,
          a.calendarType.index,
          a.colorValue,
          a.lunarYear,
          a.lunarMonth,
          a.lunarDay,
          a.lunarIsLeap,
        ),
      ),
    );
  }

  int _hashCourses(List<CourseItem>? courses, ScheduleSettings? settings) {
    if (courses == null || settings == null) return 0;
    return Object.hashAll([
      settings.termStart.millisecondsSinceEpoch,
      settings.totalWeeks,
      settings.sessionsPerDay,
      settings.sessionMinutes,
      Object.hashAll(
        courses.map(
          (c) => Object.hash(
            c.id,
            c.name,
            c.weekday,
            c.startSection,
            c.sectionCount,
            c.colorValue,
            Object.hashAll(c.weeks),
          ),
        ),
      ),
    ]);
  }

  int _hashDiaries(List<DiaryEntry>? diaries) {
    if (diaries == null) return 0;
    return Object.hashAll(
      diaries.map(
        (d) => Object.hash(
          d.id,
          d.title,
          d.date.millisecondsSinceEpoch,
          d.updatedAt.millisecondsSinceEpoch,
        ),
      ),
    );
  }

  int _hashCountdowns(List<CountdownItem>? countdowns) {
    if (countdowns == null) return 0;
    return Object.hashAll(
      countdowns.map(
        (c) => Object.hash(
          c.id,
          c.title,
          c.targetDate.millisecondsSinceEpoch,
          c.isPinned,
        ),
      ),
    );
  }

  int _hashGoals(List<GoalItem>? goals) {
    if (goals == null) return 0;
    return Object.hashAll(
      goals.map(
        (g) => Object.hash(
          g.id,
          g.title,
          g.targetDate?.millisecondsSinceEpoch,
          g.status.index,
          g.colorValue,
          g.autoProgress,
          g.computedProgress,
        ),
      ),
    );
  }

  int _hashTimeEntries(List<TimeEntry>? entries) {
    if (entries == null) return 0;
    return Object.hashAll(
      entries.map(
        (e) => Object.hash(
          e.id,
          e.title,
          e.startAt.millisecondsSinceEpoch,
          e.endAt.millisecondsSinceEpoch,
          e.category.index,
          e.source.index,
          e.sourceId,
        ),
      ),
    );
  }

  void _notifyListenersSafely() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (hasListeners) notifyListeners();
      });
      return;
    }
    notifyListeners();
  }

  bool _eventsEqual(List<CalendarEvent> a, List<CalendarEvent> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_eventEqual(a[i], b[i])) return false;
    }
    return true;
  }

  bool _eventEqual(CalendarEvent a, CalendarEvent b) {
    return a.id == b.id &&
        a.title == b.title &&
        a.date == b.date &&
        a.type == b.type &&
        a.color == b.color &&
        a.isCompleted == b.isCompleted &&
        a.sourceId == b.sourceId &&
        a.subtitle == b.subtitle &&
        a.endDate == b.endDate &&
        a.hasConflict == b.hasConflict &&
        a.conflictCount == b.conflictCount &&
        _timeEqual(a.time, b.time);
  }

  bool _timeEqual(TimeOfDay? a, TimeOfDay? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return a.hour == b.hour && a.minute == b.minute;
  }

  List<CalendarEvent> getEventsForDate(
    DateTime date, {
    Set<CalendarEventType>? activeTypes,
  }) {
    final key =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return _events.where((e) {
      if (e.dateKey != key) return false;
      if (activeTypes != null && !activeTypes.contains(e.type)) return false;
      return true;
    }).toList();
  }

  Set<DateTime> get datesWithEvents {
    final dates = <DateTime>{};
    for (final e in _events) {
      dates.add(DateTime(e.date.year, e.date.month, e.date.day));
    }
    return dates;
  }

  Map<String, List<CalendarEventType>> get dateEventTypes {
    final map = <String, Set<CalendarEventType>>{};
    for (final e in _events) {
      map.putIfAbsent(e.dateKey, () => {}).add(e.type);
    }
    return map.map((k, v) => MapEntry(k, v.toList()));
  }

  /// Filtered variant: only include event types in [activeTypes].
  Map<String, List<CalendarEventType>> filteredDateEventTypes(
    Set<CalendarEventType>? activeTypes,
  ) {
    if (activeTypes == null) return dateEventTypes;
    final map = <String, Set<CalendarEventType>>{};
    for (final e in _events) {
      if (!activeTypes.contains(e.type)) continue;
      map.putIfAbsent(e.dateKey, () => {}).add(e.type);
    }
    return map.map((k, v) => MapEntry(k, v.toList()));
  }
}
