import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/calendar_provider.dart';
import '../../providers/theme_provider.dart';
import '../../models/calendar_event.dart';

class CalendarDayAgenda extends StatelessWidget {
  final DateTime date;
  final CalendarProvider calendarProvider;

  const CalendarDayAgenda({
    super.key,
    required this.date,
    required this.calendarProvider,
  });

  IconData _icon(CalendarEventType t) {
    switch (t) {
      case CalendarEventType.todo:
        return Icons.check_circle_outline;
      case CalendarEventType.habit:
        return Icons.repeat;
      case CalendarEventType.pomodoro:
        return Icons.timer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ThemeProvider>().brand.strings;
    final events = calendarProvider.getEventsForDate(date);
    events.sort((a, b) => (a.time?.hour ?? 0).compareTo(b.time?.hour ?? 0));

    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_busy, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(
                s.calendarEmpty,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Text(
            '${date.month}月${date.day}日 议程',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: events.length,
            itemBuilder: (context, index) {
              final e = events[index];
              final isLast = index == events.length - 1;
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Timeline indicator
                    SizedBox(
                      width: 24,
                      child: Column(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: e.color.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _icon(e.type),
                              color: e.color,
                              size: 14,
                            ),
                          ),
                          if (!isLast)
                            Expanded(
                              child: Container(
                                width: 2,
                                color: Colors.grey.shade200,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Event card
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.grey.withValues(alpha: 0.1),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.title,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: e.isCompleted ? Colors.grey : null,
                                  decoration: e.isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              if (e.time != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.access_time,
                                        size: 12,
                                        color: Colors.grey.shade500,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${e.time!.hour.toString().padLeft(2, '0')}:${e.time!.minute.toString().padLeft(2, '0')}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
