import '../core/calendar_event_display_text.dart';
import '../core/i18n.dart';
import '../core/lunar_calendar.dart';
import '../models/calendar_event.dart';
import 'holiday_calendar.dart';

/// Uses the source object's identity for each published schedule destination.
String homeWidgetScheduleEventDeepLink(CalendarEvent event) {
  final sourceId = event.type == CalendarEventType.event
      ? event.id
      : event.sourceId;
  if (sourceId == null || sourceId.trim().isEmpty) return '';
  final id = Uri.encodeComponent(sourceId);
  return switch (event.type) {
    CalendarEventType.todo => 'duoyi://todo/$id',
    CalendarEventType.habit => 'duoyi://habit/$id',
    CalendarEventType.anniversary => 'duoyi://anniversary/$id',
    CalendarEventType.course => 'duoyi://course/$id',
    CalendarEventType.diary => 'duoyi://diary/$id',
    CalendarEventType.goal => 'duoyi://goal/$id',
    CalendarEventType.countdown => 'duoyi://countdown/$id',
    CalendarEventType.event => 'duoyi://event/$id',
    CalendarEventType.pomodoro => 'duoyi://pomodoro/$id',
    CalendarEventType.timeEntry => 'duoyi://time-entry/$id',
  };
}

/// Projects the calendar feed into the order used by the launcher schedule.
/// A timed todo can keep its date at midnight and its clock in [CalendarEvent.time].
List<CalendarEvent> homeWidgetScheduleEvents(Iterable<CalendarEvent> events) {
  final visible = events.where((event) {
    if (event.type == CalendarEventType.todo && event.isCompleted) return false;
    if (event.type == CalendarEventType.event) {
      return event.id.trim().isNotEmpty;
    }
    return event.sourceId?.trim().isNotEmpty == true;
  }).toList();
  visible.sort((a, b) {
    final startOrder = _startOf(a).compareTo(_startOf(b));
    if (startOrder != 0) return startOrder;
    final titleOrder = a.title.compareTo(b.title);
    if (titleOrder != 0) return titleOrder;
    return a.id.compareTo(b.id);
  });
  return visible;
}

DateTime _startOf(CalendarEvent event) {
  final time = event.time;
  if (time == null) return event.date;
  return DateTime(
    event.date.year,
    event.date.month,
    event.date.day,
    time.hour,
    time.minute,
  );
}

/// Uses calendar display metadata to translate generated copy, preserving titles.
String homeWidgetScheduleEventLabel(CalendarEvent event) {
  final time = event.time == null
      ? ''
      : '${event.time!.hour.toString().padLeft(2, '0')}:'
            '${event.time!.minute.toString().padLeft(2, '0')} ';
  final title = CalendarEventDisplayText.resolveTitle(event);
  return '$time${event.type.label} · $title';
}

/// Returns compact statutory rest/work makeup badge for calendar widget cells/headers.
String? homeWidgetCalendarDayBadge(
  DateTime date, {
  AppLocale locale = AppLocale.zh,
}) {
  if (HolidayCalendar.isHoliday(date)) {
    return switch (locale) {
      AppLocale.zh => '休',
      AppLocale.en => 'Off',
    };
  }
  if (HolidayCalendar.isWorkMakeupDay(date)) {
    return switch (locale) {
      AppLocale.zh => '班',
      AppLocale.en => 'Work',
    };
  }
  return null;
}

/// Formats a concise lunar date + holiday name summary for calendar widgets.
String homeWidgetCalendarSummary(
  DateTime date, {
  AppLocale locale = AppLocale.zh,
}) {
  final lunar = LunarCalendar.fromSolar(date);
  final holiday = HolidayCalendar.holidayName(date, locale: locale);
  if (locale == AppLocale.en) {
    final lunarLabel = 'Lunar ${lunar.month}/${lunar.day}';
    return holiday == null || holiday.isEmpty
        ? lunarLabel
        : '$lunarLabel · $holiday';
  }
  final base = '农历${lunar.chineseText}';
  return holiday == null || holiday.isEmpty ? base : '$base · $holiday';
}
