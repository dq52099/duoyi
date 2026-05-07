import 'package:flutter/material.dart';
import '../models/calendar_event.dart';
import '../models/todo.dart';
import '../models/habit.dart';
import '../models/pomodoro.dart';
import '../models/anniversary.dart';
import '../models/course_schedule.dart';
import '../models/diary_entry.dart';
import '../models/countdown.dart';
import '../models/goal.dart';

class CalendarProvider extends ChangeNotifier {
  final List<CalendarEvent> _events = [];

  List<CalendarEvent> get events => _events;

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
  }) {
    _events.clear();

    // Todo
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

    // Habit completions
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

    // Pomodoro
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

    // 纪念日 / 生日 / 循环类倒数(取当年的下一次发生日)
    if (anniversaries != null) {
      for (final a in anniversaries) {
        final d = a.nextOccurrence;
        _events.add(
          CalendarEvent(
            id: 'anni_${a.id}',
            title: a.title,
            date: d,
            type: CalendarEventType.anniversary,
            color: Color(a.colorValue),
            isCompleted: false,
            sourceId: a.id,
          ),
        );
      }
    }

    // 纯倒数日(单次)
    if (countdowns != null) {
      for (final c in countdowns) {
        _events.add(
          CalendarEvent(
            id: 'cd_${c.id}',
            title: c.title,
            date: c.targetDate,
            type: CalendarEventType.countdown,
            color: const Color(0xFFE91E63),
            isCompleted: c.daysRemaining < 0,
            sourceId: c.id,
          ),
        );
      }
    }

    // 课程：把当前学期内所有周次 × 当天课 × 计算公历日期
    if (courses != null && courseSettings != null) {
      for (final course in courses) {
        for (final week in course.weeks) {
          final dayOffset = (week - 1) * 7 + (course.weekday - 1);
          final date = courseSettings.termStart.add(Duration(days: dayOffset));
          _events.add(
            CalendarEvent(
              id: 'course_${course.id}_${week}_${course.weekday}',
              title: course.name,
              date: date,
              type: CalendarEventType.course,
              color: Color(course.colorValue),
              isCompleted: false,
              sourceId: course.id,
            ),
          );
        }
      }
    }

    // 日记
    if (diaries != null) {
      for (final d in diaries) {
        _events.add(
          CalendarEvent(
            id: 'diary_${d.id}',
            title: d.title,
            date: d.date,
            type: CalendarEventType.diary,
            color: const Color(0xFF26A69A),
            isCompleted: false,
            sourceId: d.id,
          ),
        );
      }
    }

    // 目标(以目标截止日展示)
    if (goals != null) {
      for (final g in goals) {
        if (g.targetDate == null) continue;
        _events.add(
          CalendarEvent(
            id: 'goal_${g.id}',
            title: '🎯 ${g.title}',
            date: g.targetDate!,
            type: CalendarEventType.goal,
            color: Color(g.colorValue),
            isCompleted: g.status == GoalStatus.achieved,
            sourceId: g.id,
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
