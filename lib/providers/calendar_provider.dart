import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import '../services/account_local_data_cleaner.dart';
import '../services/reminder_scheduler.dart';
import '../core/account_preference_writes.dart';
import 'cloud_sync_provider.dart';

const int _calendarIsolateEncodeMinItems = 500;

List<String> _encodeCalendarEventsPayload(List<CalendarEvent> events) =>
    events.map((event) => jsonEncode(event.toJson())).toList(growable: false);

class CalendarProvider extends ChangeNotifier {
  static const _localEventsKey = 'duoyi_local_calendar_events_v1';

  final List<CalendarEvent> _events = [];
  final List<CalendarEvent> _localEvents = [];
  List<CalendarEvent> _externalEvents = const <CalendarEvent>[];
  Object? _lastRebuildSignature;
  int _sourceRevision = 0;
  int _storageGeneration = 0;
  int _cacheEpoch = 0;
  Set<DateTime>? _cachedDatesWithEvents;
  int? _cachedDatesEpoch;
  Map<String, List<CalendarEventType>>? _cachedDateEventTypes;
  int? _cachedDateEventTypesEpoch;
  final Map<String, Map<String, List<CalendarEventType>>>
  _cachedFilteredDateEventTypes = {};
  int? _cachedFilteredTypesEpoch;
  final Map<String, Map<String, int>> _cachedFilteredDateEventCounts = {};
  int? _cachedFilteredCountsEpoch;
  Future<void> _localWriteTail = Future<void>.value();
  ReminderScheduler? _scheduler;
  VoidCallback? onLocalEventsChanged;
  Future<void> Function(String id)? localEventReminderCanceller;

  set scheduler(ReminderScheduler? value) {
    _scheduler = value;
  }

  List<CalendarEvent> get events => _events;
  List<CalendarEvent> get localEvents => List.unmodifiable(_localEvents);
  int get sourceRevision => _sourceRevision;

  void _invalidateDerivedCaches() {
    _cacheEpoch++;
    _cachedDatesWithEvents = null;
    _cachedDateEventTypes = null;
    _cachedFilteredDateEventTypes.clear();
    _cachedFilteredDateEventCounts.clear();
  }

  Future<void> _syncLocalEventReminders(
    int generation,
    int accountGeneration,
  ) async {
    final scheduler = _scheduler;
    if (scheduler == null ||
        !_isCurrentStorageGeneration(generation, accountGeneration)) {
      return;
    }
    final snapshot = List<CalendarEvent>.of(_localEvents);
    try {
      await scheduler.syncCalendarEvents(snapshot);
    } catch (e, st) {
      debugPrint('[CalendarProvider] local event reminder sync failed: $e\n$st');
    }
  }

  Future<void> loadFromStorage() async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return;
    }
    final data = prefs.getStringList(_localEventsKey) ?? const <String>[];
    _localEvents
      ..clear()
      ..addAll(
        data
            .map((raw) {
              final json = jsonDecode(raw) as Map<String, dynamic>;
              return CalendarEvent.fromJson(json);
            })
            .where((event) => event.type == CalendarEventType.event),
      );
    _lastRebuildSignature = null;
    _sourceRevision++;
    _invalidateDerivedCaches();
    notifyListeners();
    unawaited(_syncLocalEventReminders(generation, accountGeneration));
  }

  void resetLocalState() {
    _storageGeneration++;
    _events.clear();
    _localEvents.clear();
    _externalEvents = const <CalendarEvent>[];
    _lastRebuildSignature = null;
    _sourceRevision++;
    _invalidateDerivedCaches();
    notifyListeners();
  }

  Future<void> addLocalEvent(
    CalendarEvent event, {
    bool Function()? canWrite,
  }) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    bool isCurrent() =>
        _isCurrentStorageGeneration(generation, accountGeneration) &&
        canWrite?.call() != false;
    await _enqueueLocalWrite(() async {
      if (!isCurrent()) return;
      final next = List<CalendarEvent>.of(_localEvents)
        ..add(_asLocalEvent(event));
      await _saveLocalEvents(
        next,
        generation,
        accountGeneration,
        canWrite: isCurrent,
      );
      if (!isCurrent()) return;
      _publishLocalSnapshot(next);
      await _syncLocalEventReminders(generation, accountGeneration);
    });
  }

  Future<CalendarEventImportSummary> importLocalEvents(
    Iterable<CalendarEvent> events,
  ) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    var inserted = 0;
    var skippedDuplicates = 0;
    await _enqueueLocalWrite(() async {
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
      final next = List<CalendarEvent>.of(_localEvents);
      final seen = next.map(_importDuplicateKey).toSet();
      for (final event in events) {
        if (event.title.trim().isEmpty) continue;
        final key = _importDuplicateKey(event);
        if (seen.contains(key)) {
          skippedDuplicates++;
          continue;
        }
        seen.add(key);
        next.add(_asLocalEvent(event));
        inserted++;
      }
      if (inserted == 0) return;
      await _saveLocalEvents(next, generation, accountGeneration);
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
      _publishLocalSnapshot(next);
      await _syncLocalEventReminders(generation, accountGeneration);
    });
    return CalendarEventImportSummary(
      inserted: inserted,
      skippedDuplicates: skippedDuplicates,
    );
  }

  Future<void> updateLocalEvent(CalendarEvent event) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    await _enqueueLocalWrite(() async {
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
      final index = _localEvents.indexWhere((e) => e.id == event.id);
      if (index == -1) return;
      await _cancelLocalEventReminder(event.id);
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
      final next = List<CalendarEvent>.of(_localEvents);
      next[index] = _asLocalEvent(event);
      await _saveLocalEvents(next, generation, accountGeneration);
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
      _publishLocalSnapshot(next);
      await _syncLocalEventReminders(generation, accountGeneration);
    });
  }

  Future<void> deleteLocalEvent(String id) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    await _enqueueLocalWrite(() async {
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
      final existing = _localEvents
          .where((event) => event.id == id)
          .toList(growable: false);
      await _cancelLocalEventReminder(id);
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
      for (final event in existing) {
        if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
        await CloudSyncProvider.recordDeletedItem(
          'calendar_events',
          event.id,
          workspaceId: event.workspaceId,
        );
        if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
      }
      if (existing.isEmpty) return;
      final next = _localEvents.where((event) => event.id != id).toList();
      await _saveLocalEvents(next, generation, accountGeneration);
      if (!_isCurrentStorageGeneration(generation, accountGeneration)) return;
      _publishLocalSnapshot(next);
      await _syncLocalEventReminders(generation, accountGeneration);
    });
  }

  Future<void> _cancelLocalEventReminder(String id) async {
    try {
      await localEventReminderCanceller?.call(id);
    } catch (e, st) {
      debugPrint(
        '[CalendarProvider] local event reminder cancel failed: $e\n$st',
      );
    }
  }

  Future<void> _saveLocalEvents(
    List<CalendarEvent> snapshot,
    int generation,
    int accountGeneration, {
    bool Function()? canWrite,
  }) => AccountPreferenceWrites.runResult<void>((token) async {
    bool isCurrent() =>
        token.isCurrent &&
        _isCurrentStorageGeneration(generation, accountGeneration) &&
        canWrite?.call() != false;
    if (!isCurrent()) throw const AccountPreferenceWriteCanceled();
    final prefs = await SharedPreferences.getInstance();
    final data = snapshot.length >= _calendarIsolateEncodeMinItems
        ? await compute(_encodeCalendarEventsPayload, snapshot)
        : _encodeCalendarEventsPayload(snapshot);
    final transaction = AccountPreferenceTransaction(prefs, isCurrent);
    try {
      await transaction.setStringList(_localEventsKey, data);
      transaction.commit();
    } catch (_) {
      // Cleanup drains this tracked write before removing account keys.
      await transaction.rollback(canceledBeforeCleanup: true);
      rethrow;
    }
  }, canceledResult: () => throw const AccountPreferenceWriteCanceled());

  Future<void> _enqueueLocalWrite(Future<void> Function() operation) {
    final run = _localWriteTail.then((_) => operation());
    _localWriteTail = run.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return run;
  }

  void _publishLocalSnapshot(List<CalendarEvent> snapshot) {
    _localEvents
      ..clear()
      ..addAll(snapshot);
    _lastRebuildSignature = null;
    _sourceRevision++;
    _invalidateDerivedCaches();
    onLocalEventsChanged?.call();
    _notifyListenersSafely();
  }

  bool _isCurrentStorageGeneration(
    int storageGeneration,
    int accountGeneration,
  ) {
    return storageGeneration == _storageGeneration &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        );
  }

  CalendarEvent _asLocalEvent(CalendarEvent event) {
    final id = event.id.isEmpty
        ? 'local_${DateTime.now().microsecondsSinceEpoch}'
        : event.id;
    return event.copyWith(
      id: id,
      type: CalendarEventType.event,
      sourceId: event.sourceId?.isNotEmpty == true ? event.sourceId : id,
      updatedAt: event.updatedAt ?? DateTime.now(),
    );
  }

  /// 设置外部订阅事件（来自 ICS 订阅）。会触发下次 rebuild 时合并。
  // ignore: use_setters_to_change_properties
  void setExternalEvents(List<CalendarEvent> events) {
    final next = List<CalendarEvent>.unmodifiable(events);
    if (_eventsEqual(_externalEvents, next)) return;
    _externalEvents = next;
    _lastRebuildSignature = null;
    _sourceRevision++;
    _invalidateDerivedCaches();
    _notifyListenersSafely();
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
      ..addAll(_localEvents)
      ..addAll(_externalEvents);

    if (!_eventsEqual(previousEvents, _events)) {
      _lastRebuildSignature = signature;
      _invalidateDerivedCaches();
      _notifyListenersSafely();
      return;
    }
    _lastRebuildSignature = signature;
  }

  List<CalendarEvent> buildEventsForDateSnapshot(
    DateTime date,
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
    DateTime? now,
  }) {
    final civilQuery = _tryCivilQuery(date);
    if (civilQuery == null) return List<CalendarEvent>.empty(growable: false);
    final events = CalendarAggregator.buildEvents(
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
      now: now,
    );
    return [...events, ..._localEvents, ..._externalEvents]
        .where((event) => _eventOccursOnDate(event, civilQuery))
        .toList(growable: false);
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
      _hashCalendarEvents(_localEvents),
    ]);
  }

  int _hashTodos(List<TodoItem> todos) {
    return Object.hashAll(
      todos.map((t) {
        final rule = t.reminderPlan.primaryRule;
        return Object.hashAll([
          t.id,
          t.title,
          t.date.millisecondsSinceEpoch,
          t.dueDate?.millisecondsSinceEpoch,
          t.reminderAt?.millisecondsSinceEpoch,
          // ignore: deprecated_member_use_from_same_package
          t.hasReminder,
          t.reminder.enabled,
          t.reminder.kind.index,
          t.reminder.hour,
          t.reminder.minute,
          t.reminder.daysBefore,
          t.reminderPlan.enabled,
          rule?.enabled,
          rule?.type.index,
          rule?.kind.index,
          rule?.hour,
          rule?.minute,
          rule?.offsetMinutes,
          Object.hashAll(rule?.weekdays ?? const <int>[]),
          t.isCompleted,
          t.listGroupId,
          t.listGroupName,
          t.workspaceId,
        ]);
      }),
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
          h.unit,
          h.generatedUnitKey,
          Object.hashAll(h.activeWeekdays),
          h.weeklyTarget,
          h.flexTarget,
          h.flexPeriod,
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
          a.ignoreYear,
          a.updatedAt.millisecondsSinceEpoch,
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
          g.workspaceId,
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

  int _hashCalendarEvents(List<CalendarEvent> events) {
    return Object.hashAll(
      events.map(
        (event) => Object.hashAll([
          event.id,
          event.title,
          event.date.millisecondsSinceEpoch,
          event.endDate?.millisecondsSinceEpoch,
          event.type.index,
          event.color,
          event.subtitle,
          event.workspaceId,
          event.note,
          event.updatedAt?.millisecondsSinceEpoch,
          event.reminderMinutes,
          event.time == null
              ? null
              : Object.hash(event.time!.hour, event.time!.minute),
        ]),
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
        a.projectId == b.projectId &&
        a.projectName == b.projectName &&
        a.workspaceId == b.workspaceId &&
        a.endDate == b.endDate &&
        a.hasConflict == b.hasConflict &&
        a.conflictCount == b.conflictCount &&
        a.note == b.note &&
        a.updatedAt == b.updatedAt &&
        a.reminderMinutes == b.reminderMinutes &&
        _timeEqual(a.time, b.time) &&
        _habitDisplayEqual(a, b);
  }

  bool _habitDisplayEqual(CalendarEvent a, CalendarEvent b) {
    if (a.type != CalendarEventType.habit) return true;
    final left = a.displayMetadata;
    final right = b.displayMetadata;
    if (identical(left, right)) return true;
    if (left is! HabitDisplayMetadata || right is! HabitDisplayMetadata) {
      return false;
    }
    final leftProgress = left.flexProgress;
    final rightProgress = right.flexProgress;
    return left.kind == right.kind &&
        left.count == right.count &&
        left.targetCount == right.targetCount &&
        left.unit == right.unit &&
        left.generatedUnitKey == right.generatedUnitKey &&
        left.hasFlexRule == right.hasFlexRule &&
        (identical(leftProgress, rightProgress) ||
            (leftProgress != null &&
                rightProgress != null &&
                leftProgress.period == rightProgress.period &&
                leftProgress.start == rightProgress.start &&
                leftProgress.end == rightProgress.end &&
                leftProgress.completed == rightProgress.completed &&
                leftProgress.target == rightProgress.target));
  }

  bool _timeEqual(TimeOfDay? a, TimeOfDay? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return a.hour == b.hour && a.minute == b.minute;
  }

  List<CalendarEvent> getEventsForDate(
    DateTime date, {
    Set<CalendarEventType>? activeTypes,
    String? projectKey,
    String? workspaceId,
  }) {
    final civilQuery = _tryCivilQuery(date);
    if (civilQuery == null) return <CalendarEvent>[];
    return _events.where((e) {
      if (!_eventOccursOnDate(e, civilQuery)) return false;
      if (activeTypes != null && !activeTypes.contains(e.type)) return false;
      if (!_matchesProject(e, projectKey)) return false;
      if (!_matchesWorkspace(e, workspaceId)) return false;
      return true;
    }).toList();
  }

  String _filterCacheKey(
    Set<CalendarEventType>? activeTypes, {
    String? projectKey,
    String? workspaceId,
  }) {
    final typesKey = activeTypes == null
        ? '*'
        : (activeTypes.map((t) => t.name).toList()..sort()).join(',');
    return '$typesKey|${projectKey ?? ''}|${workspaceId ?? ''}';
  }

  Set<DateTime> get datesWithEvents {
    if (_cachedDatesWithEvents != null && _cachedDatesEpoch == _cacheEpoch) {
      return Set<DateTime>.of(_cachedDatesWithEvents!);
    }
    final dates = <DateTime>{};
    for (final e in _events) {
      dates.addAll(_eventDates(e));
    }
    _cachedDatesWithEvents = Set<DateTime>.unmodifiable(dates);
    _cachedDatesEpoch = _cacheEpoch;
    return Set<DateTime>.of(_cachedDatesWithEvents!);
  }

  Map<String, List<CalendarEventType>> get dateEventTypes {
    if (_cachedDateEventTypes != null &&
        _cachedDateEventTypesEpoch == _cacheEpoch) {
      return {
        for (final entry in _cachedDateEventTypes!.entries)
          entry.key: List<CalendarEventType>.of(entry.value),
      };
    }
    final map = <String, Set<CalendarEventType>>{};
    for (final e in _events) {
      for (final key in _eventDateKeys(e)) {
        map.putIfAbsent(key, () => {}).add(e.type);
      }
    }
    _cachedDateEventTypes = {
      for (final entry in map.entries)
        entry.key: List<CalendarEventType>.unmodifiable(entry.value),
    };
    _cachedDateEventTypesEpoch = _cacheEpoch;
    return {
      for (final entry in _cachedDateEventTypes!.entries)
        entry.key: List<CalendarEventType>.of(entry.value),
    };
  }

  /// Filtered variant: only include event types in [activeTypes].
  Map<String, List<CalendarEventType>> filteredDateEventTypes(
    Set<CalendarEventType>? activeTypes, {
    String? projectKey,
    String? workspaceId,
  }) {
    if (activeTypes == null && projectKey == null && workspaceId == null) {
      return dateEventTypes;
    }
    if (_cachedFilteredTypesEpoch != _cacheEpoch) {
      _cachedFilteredDateEventTypes.clear();
      _cachedFilteredTypesEpoch = _cacheEpoch;
    }
    final filterKey = _filterCacheKey(
      activeTypes,
      projectKey: projectKey,
      workspaceId: workspaceId,
    );
    final cached = _cachedFilteredDateEventTypes[filterKey];
    if (cached != null) {
      return {
        for (final entry in cached.entries)
          entry.key: List<CalendarEventType>.of(entry.value),
      };
    }
    final map = <String, Set<CalendarEventType>>{};
    for (final e in _events) {
      if (activeTypes != null && !activeTypes.contains(e.type)) continue;
      if (!_matchesProject(e, projectKey)) continue;
      if (!_matchesWorkspace(e, workspaceId)) continue;
      for (final key in _eventDateKeys(e)) {
        map.putIfAbsent(key, () => {}).add(e.type);
      }
    }
    final frozen = <String, List<CalendarEventType>>{
      for (final entry in map.entries)
        entry.key: List<CalendarEventType>.unmodifiable(entry.value),
    };
    _cachedFilteredDateEventTypes[filterKey] = frozen;
    return {
      for (final entry in frozen.entries)
        entry.key: List<CalendarEventType>.of(entry.value),
    };
  }

  Map<String, int> filteredDateEventCounts(
    Set<CalendarEventType>? activeTypes, {
    String? projectKey,
    String? workspaceId,
  }) {
    if (_cachedFilteredCountsEpoch != _cacheEpoch) {
      _cachedFilteredDateEventCounts.clear();
      _cachedFilteredCountsEpoch = _cacheEpoch;
    }
    final filterKey = _filterCacheKey(
      activeTypes,
      projectKey: projectKey,
      workspaceId: workspaceId,
    );
    final cached = _cachedFilteredDateEventCounts[filterKey];
    if (cached != null) {
      return Map<String, int>.of(cached);
    }
    final map = <String, int>{};
    for (final e in _events) {
      if (activeTypes != null && !activeTypes.contains(e.type)) continue;
      if (!_matchesProject(e, projectKey)) continue;
      if (!_matchesWorkspace(e, workspaceId)) continue;
      for (final key in _eventDateKeys(e)) {
        map[key] = (map[key] ?? 0) + 1;
      }
    }
    _cachedFilteredDateEventCounts[filterKey] = Map<String, int>.unmodifiable(
      map,
    );
    return Map<String, int>.of(map);
  }

  bool _matchesProject(CalendarEvent event, String? projectKey) {
    if (projectKey == null) return true;
    if (event.type != CalendarEventType.todo) return false;
    return (event.projectKey ?? '') == projectKey;
  }

  bool _matchesWorkspace(CalendarEvent event, String? workspaceId) {
    if (workspaceId == null) return true;
    final eventWorkspaceId = event.workspaceId;
    if (workspaceId == 'private') {
      return eventWorkspaceId == null ||
          eventWorkspaceId.isEmpty ||
          eventWorkspaceId == 'private';
    }
    return eventWorkspaceId == workspaceId;
  }

  DateTime? _tryCivilQuery(DateTime date) {
    try {
      final civil = _utcCivilDay(date);
      final local = DateTime(civil.year, civil.month, civil.day);
      // A skipped local day must not match events on its normalized neighbor.
      if (local.year != civil.year ||
          local.month != civil.month ||
          local.day != civil.day) {
        return null;
      }
      return civil;
    } on ArgumentError {
      // A representable instant can have an unrepresentable civil midnight.
      return null;
    }
  }

  bool _eventOccursOnDate(CalendarEvent event, DateTime civilQuery) {
    final start = _utcCivilDay(event.date);
    final end = _eventVisibleEndDate(event, start);
    final visibleEnd = end.isBefore(start) ? start : end;
    return !civilQuery.isBefore(start) && !civilQuery.isAfter(visibleEnd);
  }

  List<DateTime> _eventDates(CalendarEvent event) {
    final start = _utcCivilDay(event.date);
    final end = _eventVisibleEndDate(event, start);
    final dayCount = end.isBefore(start) ? 1 : end.difference(start).inDays + 1;
    final dates = <DateTime>[];
    for (var index = 0; index < dayCount; index++) {
      // UTC contains civil fields here, not the event's converted instant.
      // Its consecutive days remain stable across local DST transitions.
      final civil = start.add(Duration(days: index));
      final local = DateTime(civil.year, civil.month, civil.day);
      if (local.year == civil.year &&
          local.month == civil.month &&
          local.day == civil.day) {
        dates.add(local);
      }
    }
    return dates;
  }

  List<String> _eventDateKeys(CalendarEvent event) {
    return _eventDates(event).map(_dateKey).toList(growable: false);
  }

  DateTime _eventVisibleEndDate(CalendarEvent event, DateTime start) {
    final endDate = event.endDate;
    if (endDate == null || !endDate.isAfter(event.date)) return start;

    var end = _utcCivilDay(endDate);
    final endsAtMidnight =
        endDate.hour == 0 &&
        endDate.minute == 0 &&
        endDate.second == 0 &&
        endDate.millisecond == 0 &&
        endDate.microsecond == 0;
    if (endsAtMidnight && end.isAfter(start)) {
      // Exclude the civil end day before constructing any local dates. A
      // skipped local day must not shift this endpoint to its neighbor.
      end = end.subtract(const Duration(days: 1));
    }
    return end;
  }

  DateTime _utcCivilDay(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class CalendarEventImportSummary {
  final int inserted;
  final int skippedDuplicates;

  const CalendarEventImportSummary({
    required this.inserted,
    required this.skippedDuplicates,
  });
}

String _importDuplicateKey(CalendarEvent event) {
  final end = event.endDate;
  final time = event.time;
  return [
    event.title.trim().toLowerCase(),
    event.date.toIso8601String(),
    end?.toIso8601String() ?? '',
    time == null ? '' : '${time.hour}:${time.minute}',
    event.projectName?.trim().toLowerCase() ?? '',
  ].join('|');
}
