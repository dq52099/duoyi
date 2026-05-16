import 'package:flutter/material.dart';
import '../../models/calendar_event.dart';

class CalendarWeekStrip extends StatelessWidget {
  final DateTime selectedDay;
  final Map<String, List<CalendarEventType>> dateEventTypes;
  final void Function(DateTime) onDaySelected;
  final Set<CalendarEventType>? activeTypes;

  const CalendarWeekStrip({
    super.key,
    required this.selectedDay,
    required this.dateEventTypes,
    required this.onDaySelected,
    this.activeTypes,
  });

  static Color _colorFor(CalendarEventType t, ColorScheme cs) {
    switch (t) {
      case CalendarEventType.todo:
        return cs.primary;
      case CalendarEventType.habit:
        return cs.tertiary;
      case CalendarEventType.pomodoro:
        return Colors.red;
      case CalendarEventType.anniversary:
        return const Color(0xFFE91E63);
      case CalendarEventType.course:
        return const Color(0xFF42A5F5);
      case CalendarEventType.diary:
        return const Color(0xFF26A69A);
      case CalendarEventType.countdown:
        return Colors.orange;
      case CalendarEventType.goal:
        return const Color(0xFFFFA726);
      case CalendarEventType.timeEntry:
        return const Color(0xFF78909C);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final monday = selectedDay.subtract(
      Duration(days: selectedDay.weekday - 1),
    );
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));
    final today = DateTime.now();

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: days.map((d) {
              final key =
                  '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
              final types = dateEventTypes[key] ?? [];
              final isSelected =
                  d.day == selectedDay.day && d.month == selectedDay.month;
              final isToday = d.day == today.day && d.month == today.month;
              final labels = ['一', '二', '三', '四', '五', '六', '日'];

              return GestureDetector(
                onTap: () => onDaySelected(d),
                child: Container(
                  width: 48,
                  height: 64,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? cs.primary
                        : (isToday ? cs.primary.withValues(alpha: 0.12) : null),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        labels[d.weekday - 1],
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected
                              ? cs.onPrimary
                              : Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        '${d.day}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                          color: isSelected ? cs.onPrimary : null,
                        ),
                      ),
                      if (types.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: types
                              .take(3)
                              .map(
                                (t) => Container(
                                  width: 5,
                                  height: 5,
                                  margin: const EdgeInsets.only(right: 1),
                                  decoration: BoxDecoration(
                                    color: _colorFor(t, cs),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: days
                .where((d) {
                  final key =
                      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                  return dateEventTypes.containsKey(key);
                })
                .expand((d) {
                  final label = [
                    '周一',
                    '周二',
                    '周三',
                    '周四',
                    '周五',
                    '周六',
                    '周日',
                  ][d.weekday - 1];
                  return [
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(
                        '$label ${d.month}/${d.day}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    Text(
                      '${dateEventTypes.length} 个活动',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ];
                })
                .toList(),
          ),
        ),
      ],
    );
  }
}
