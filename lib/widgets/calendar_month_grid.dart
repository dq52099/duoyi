import 'package:flutter/material.dart';
import '../../models/calendar_event.dart';

class CalendarMonthGrid extends StatelessWidget {
  final DateTime focusedMonth;
  final DateTime selectedDay;
  final Map<String, List<CalendarEventType>> dateEventTypes;
  final void Function(DateTime) onDaySelected;

  const CalendarMonthGrid({
    super.key,
    required this.focusedMonth,
    required this.selectedDay,
    required this.dateEventTypes,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final lastDay = DateTime(focusedMonth.year, focusedMonth.month + 1, 0);
    final startOffset = firstDay.weekday % 7;
    final cs = Theme.of(context).colorScheme;
    final totalCells = startOffset + lastDay.day;
    final rows = (totalCells / 7).ceil();

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: ['一', '二', '三', '四', '五', '六', '日']
              .map((d) => SizedBox(
                    width: 40,
                    child: Center(child: Text(d, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500))),
                  ))
              .toList(),
        ),
        const SizedBox(height: 4),
        ...List.generate(rows, (row) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(7, (col) {
                final dayNum = row * 7 + col - startOffset + 1;
                if (dayNum < 1 || dayNum > lastDay.day) {
                  return const SizedBox(width: 40, height: 44);
                }
                final date = DateTime(focusedMonth.year, focusedMonth.month, dayNum);
                final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                final types = dateEventTypes[key] ?? [];
                final isSelected = date.year == selectedDay.year && date.month == selectedDay.month && date.day == selectedDay.day;
                final isToday = date.year == DateTime.now().year && date.month == DateTime.now().month && date.day == DateTime.now().day;

                return GestureDetector(
                  onTap: () => onDaySelected(date),
                  child: Container(
                    width: 40, height: 44,
                    decoration: BoxDecoration(
                      color: isSelected ? cs.primary : (isToday ? cs.primary.withValues(alpha: 0.12) : null),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$dayNum',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isToday ? FontWeight.bold : FontWeight.w400,
                              color: isSelected ? cs.onPrimary : (isToday ? cs.primary : null),
                            )),
                        if (types.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (types.contains(CalendarEventType.todo))
                                  Container(width: 5, height: 5, decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle)),
                                if (types.contains(CalendarEventType.habit))
                                  Container(width: 5, height: 5, margin: const EdgeInsets.only(left: 2), decoration: BoxDecoration(color: cs.tertiary, shape: BoxShape.circle)),
                                if (types.contains(CalendarEventType.pomodoro))
                                  Container(width: 5, height: 5, margin: const EdgeInsets.only(left: 2), decoration: BoxDecoration(color: Colors.red.shade400, shape: BoxShape.circle)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          );
        }),
      ],
    );
  }
}