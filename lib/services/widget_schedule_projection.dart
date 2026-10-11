import '../core/calendar_event_display_text.dart';
import '../models/calendar_event.dart';

/// Projects the calendar feed into the order used by the launcher schedule.
/// A timed todo can keep its date at midnight and its clock in [CalendarEvent.time].
List<CalendarEvent> homeWidgetScheduleEvents(Iterable<CalendarEvent> events) {
  final visible = events.where((event) {
    if (event.type == CalendarEventType.todo && event.isCompleted) return false;
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
