import 'package:flutter/material.dart';
import '../models/calendar_event.dart';
import '../models/todo.dart';
import '../models/habit.dart';
import '../models/pomodoro.dart';

class CalendarProvider extends ChangeNotifier {
  final List<CalendarEvent> _events = [];

  List<CalendarEvent> get events => _events;

  void rebuild(
    List<TodoItem> todos,
    List<Habit> habits,
    List<PomodoroSession> pomodoroSessions,
    ColorScheme colorScheme,
  ) {
    _events.clear();

    for (final t in todos) {
      _events.add(
        CalendarEvent(
          id: t.id,
          title: t.title,
          date: t.date,
          type: CalendarEventType.todo,
          color: colorScheme.primary,
          isCompleted: t.isCompleted,
          sourceId: t.id,
        ),
      );
    }

    for (final h in habits) {
      for (final entry in h.completions.entries) {
        final parts = entry.key.split('-');
        if (parts.length == 3) {
          _events.add(
            CalendarEvent(
              id: '${h.id}_${entry.key}',
              title: '${h.name} (${entry.value}/${h.targetCount})',
              date: DateTime(
                int.parse(parts[0]),
                int.parse(parts[1]),
                int.parse(parts[2]),
              ),
              type: CalendarEventType.habit,
              color: Color(h.colorValue),
              isCompleted: entry.value >= h.targetCount,
              sourceId: h.id,
            ),
          );
        }
      }
    }

    for (final s in pomodoroSessions) {
      if (s.type == PomodoroType.focus) {
        _events.add(
          CalendarEvent(
            id: s.id,
            title: s.taskName ?? '专注 ${s.durationSeconds ~/ 60} 分钟',
            date: s.startTime,
            type: CalendarEventType.pomodoro,
            color: const Color(0xFFE53935),
            isCompleted: true,
            sourceId: s.id,
            time: TimeOfDay.fromDateTime(s.startTime),
          ),
        );
      }
    }

    notifyListeners();
  }

  List<CalendarEvent> getEventsForDate(DateTime date) {
    final key =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return _events.where((e) => e.dateKey == key).toList();
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
}
