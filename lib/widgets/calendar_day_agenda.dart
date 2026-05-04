import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/calendar_provider.dart';
import '../../providers/theme_provider.dart';
import '../../models/calendar_event.dart';

class CalendarDayAgenda extends StatelessWidget {
  final DateTime date;
  final CalendarProvider calendarProvider;

  const CalendarDayAgenda({super.key, required this.date, required this.calendarProvider});

  IconData _icon(CalendarEventType t) {
    switch (t) {
      case CalendarEventType.todo: return Icons.check_circle_outline;
      case CalendarEventType.habit: return Icons.repeat;
      case CalendarEventType.pomodoro: return Icons.timer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ThemeProvider>().brand.strings;
    final events = calendarProvider.getEventsForDate(date);
    events.sort((a, b) => (a.time?.hour ?? 0).compareTo(b.time?.hour ?? 0));

    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(s.calendarEmpty, style: TextStyle(color: Colors.grey.shade500)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('${date.month}月${date.day}日 议程',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        ...events.map((e) => ListTile(
              dense: true,
              leading: Icon(_icon(e.type), color: e.color, size: 20),
              title: Text(e.title, style: TextStyle(
                fontSize: 14,
                decoration: e.isCompleted ? TextDecoration.lineThrough : null,
              )),
              subtitle: e.time != null
                  ? Text('${e.time!.hour.toString().padLeft(2, '0')}:${e.time!.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 11))
                  : null,
            )),
      ],
    );
  }
}