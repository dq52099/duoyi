import '../models/anniversary.dart';
import '../models/calendar_event.dart';

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
