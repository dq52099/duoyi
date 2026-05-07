import '../models/anniversary.dart';
import '../models/calendar_event.dart';
import '../models/diary_entry.dart';
import '../models/goal.dart';
import '../models/habit.dart';
import '../models/note.dart';
import '../models/todo.dart';

/// 把日历事件导出为 RFC 5545 iCalendar 文本，供用户下载或复制到他处订阅。
class IcsExporter {
  /// 生成 .ics 文本。
  static String fromEvents(
    Iterable<CalendarEvent> events, {
    String calendarName = '多仪 · 日程',
  }) {
    final sb = StringBuffer()
      ..writeln('BEGIN:VCALENDAR')
      ..writeln('VERSION:2.0')
      ..writeln('PRODID:-//Duoyi//ZH//CN')
      ..writeln('X-WR-CALNAME:$calendarName');
    for (final e in events) {
      sb
        ..writeln('BEGIN:VEVENT')
        ..writeln('UID:${e.id}@duoyi')
        ..writeln('DTSTAMP:${_fmtUtc(DateTime.now())}')
        ..writeln('DTSTART;VALUE=DATE:${_fmtDate(e.date)}')
        ..writeln(
            'DTEND;VALUE=DATE:${_fmtDate(e.date.add(const Duration(days: 1)))}')
        ..writeln('SUMMARY:${_escape(e.title)}')
        ..writeln('CATEGORIES:${e.type.name}')
        ..writeln('END:VEVENT');
    }
    sb.writeln('END:VCALENDAR');
    return sb.toString();
  }

  /// 纪念日(带每年循环 RRULE)。
  static String fromAnniversaries(Iterable<Anniversary> items,
      {String calendarName = '多仪 · 纪念日'}) {
    final sb = StringBuffer()
      ..writeln('BEGIN:VCALENDAR')
      ..writeln('VERSION:2.0')
      ..writeln('PRODID:-//Duoyi//ZH//CN')
      ..writeln('X-WR-CALNAME:$calendarName');
    for (final a in items) {
      final date = a.nextOccurrence;
      final recurring = a.type != AnniversaryType.normal;
      sb
        ..writeln('BEGIN:VEVENT')
        ..writeln('UID:anni_${a.id}@duoyi')
        ..writeln('DTSTAMP:${_fmtUtc(DateTime.now())}')
        ..writeln('DTSTART;VALUE=DATE:${_fmtDate(date)}')
        ..writeln(
            'DTEND;VALUE=DATE:${_fmtDate(date.add(const Duration(days: 1)))}')
        ..writeln('SUMMARY:${_escape(a.title)}');
      if ((a.description ?? '').isNotEmpty) {
        sb.writeln('DESCRIPTION:${_escape(a.description!)}');
      }
      if (recurring) sb.writeln('RRULE:FREQ=YEARLY');
      sb.writeln('END:VEVENT');
    }
    sb.writeln('END:VCALENDAR');
    return sb.toString();
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  static String _fmtUtc(DateTime d) {
    final u = d.toUtc();
    return '${_fmtDate(u)}T${u.hour.toString().padLeft(2, '0')}${u.minute.toString().padLeft(2, '0')}${u.second.toString().padLeft(2, '0')}Z';
  }

  static String _escape(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll(',', '\\,')
        .replaceAll(';', '\\;')
        .replaceAll('\n', '\\n');
  }
}

/// 单模块文本导出 (CSV / Markdown)。
class ModuleExporter {
  static String todosCsv(Iterable<TodoItem> todos) {
    final sb = StringBuffer('title,completed,priority,quadrant,list,due,tags\n');
    for (final t in todos) {
      final row = [
        _csv(t.title),
        t.isCompleted ? '1' : '0',
        t.priority.label,
        _quadLabel(t.quadrant),
        _csv(t.listGroupName ?? ''),
        t.dueDate?.toIso8601String() ?? '',
        _csv(t.tags.join('|')),
      ].join(',');
      sb.writeln(row);
    }
    return sb.toString();
  }

  static String todosMarkdown(Iterable<TodoItem> todos) {
    final sb = StringBuffer('# 待办清单\n\n');
    final groups = <String, List<TodoItem>>{};
    for (final t in todos) {
      groups.putIfAbsent(t.listGroupName ?? '未分组', () => []).add(t);
    }
    for (final g in groups.entries) {
      sb.writeln('## ${g.key}\n');
      for (final t in g.value) {
        final mark = t.isCompleted ? '[x]' : '[ ]';
        final due = t.dueDate == null
            ? ''
            : ' — ⏰ ${t.dueDate!.toIso8601String().substring(0, 10)}';
        sb.writeln('- $mark ${t.title}$due');
        for (final s in t.subtasks) {
          sb.writeln('  - ${s.isCompleted ? '[x]' : '[ ]'} ${s.title}');
        }
      }
      sb.writeln();
    }
    return sb.toString();
  }

  static String habitsCsv(Iterable<Habit> habits) {
    final sb = StringBuffer(
        'name,kind,target,current_streak,best_streak,category,tags\n');
    for (final h in habits) {
      sb.writeln([
        _csv(h.name),
        h.kind.name,
        h.targetCount,
        h.currentStreak,
        h.bestStreak,
        _csv(h.category ?? ''),
        _csv(h.tags.join('|')),
      ].join(','));
    }
    return sb.toString();
  }

  static String notesMarkdown(Iterable<NoteItem> notes) {
    final sb = StringBuffer('# 笔记\n\n');
    for (final n in notes) {
      sb.writeln('## ${n.title}');
      sb.writeln(
          '*${n.updatedAt.toIso8601String().substring(0, 16).replaceAll("T", " ")}*\n');
      sb.writeln(n.content);
      sb.writeln('\n---\n');
    }
    return sb.toString();
  }

  static String diaryMarkdown(Iterable<DiaryEntry> entries) {
    final sb = StringBuffer('# 日记\n\n');
    for (final d in entries) {
      final date = '${d.date.year}-${d.date.month.toString().padLeft(2, '0')}-${d.date.day.toString().padLeft(2, '0')}';
      sb.writeln('## $date ${d.mood?.emoji ?? ''} ${d.weather?.emoji ?? ''}');
      if (d.tags.isNotEmpty) {
        sb.writeln('Tags: ${d.tags.map((t) => '#$t').join(' ')}\n');
      }
      sb.writeln(d.content);
      sb.writeln('\n---\n');
    }
    return sb.toString();
  }

  static String anniversariesMarkdown(Iterable<Anniversary> items) {
    final sb = StringBuffer('# 纪念日\n\n');
    for (final a in items) {
      sb.writeln(
          '- **${a.title}** — ${_annType(a.type)} · ${a.calendarType == AnniversaryCalendarType.lunar ? "农历" : "公历"}');
      sb.writeln('  下一次: ${a.nextOccurrence.toIso8601String().substring(0, 10)}');
      if ((a.description ?? '').isNotEmpty) sb.writeln('  ${a.description!}');
      sb.writeln();
    }
    return sb.toString();
  }

  static String goalsMarkdown(Iterable<GoalItem> goals) {
    final sb = StringBuffer('# 目标\n\n');
    for (final g in goals) {
      sb.writeln(
          '## ${g.title} — ${(g.computedProgress * 100).toStringAsFixed(0)}%');
      if (g.description.isNotEmpty) sb.writeln(g.description);
      sb.writeln();
      for (final m in g.milestones) {
        sb.writeln(
            '- ${m.isCompleted ? '[x]' : '[ ]'} ${m.title}');
      }
      sb.writeln();
    }
    return sb.toString();
  }

  static String _csv(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String _quadLabel(EisenhowerQuadrant q) => switch (q) {
        EisenhowerQuadrant.urgentImportant => 'Q1',
        EisenhowerQuadrant.notUrgentImportant => 'Q2',
        EisenhowerQuadrant.urgentNotImportant => 'Q3',
        EisenhowerQuadrant.notUrgentNotImportant => 'Q4',
      };

  static String _annType(AnniversaryType t) => switch (t) {
        AnniversaryType.birthday => '生日',
        AnniversaryType.memorial => '纪念日',
        AnniversaryType.normal => '倒数',
        AnniversaryType.custom => '自定义',
      };
}
