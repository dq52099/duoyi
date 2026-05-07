import 'package:flutter/material.dart';
import '../../models/calendar_event.dart';
import '../../core/lunar_calendar.dart';

class CalendarMonthGrid extends StatelessWidget {
  final DateTime focusedMonth;
  final DateTime selectedDay;
  final Map<String, List<CalendarEventType>> dateEventTypes;
  final void Function(DateTime) onDaySelected;

  /// 是否显示农历/节气/节日
  final bool showLunar;

  const CalendarMonthGrid({
    super.key,
    required this.focusedMonth,
    required this.selectedDay,
    required this.dateEventTypes,
    required this.onDaySelected,
    this.showLunar = true,
  });

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final lastDay = DateTime(focusedMonth.year, focusedMonth.month + 1, 0);
    final startOffset = (firstDay.weekday - 1) % 7; // 周一起
    final cs = Theme.of(context).colorScheme;
    final totalCells = startOffset + lastDay.day;
    final rows = (totalCells / 7).ceil();
    final cellHeight = showLunar ? 56.0 : 44.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['一', '二', '三', '四', '五', '六', '日']
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 6),
          ...List.generate(rows, (row) {
            return Row(
              children: List.generate(7, (col) {
                final dayNum = row * 7 + col - startOffset + 1;
                if (dayNum < 1 || dayNum > lastDay.day) {
                  return Expanded(child: SizedBox(height: cellHeight));
                }
                final date = DateTime(
                  focusedMonth.year,
                  focusedMonth.month,
                  dayNum,
                );
                final key =
                    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                final types = dateEventTypes[key] ?? [];
                final isSelected = date.year == selectedDay.year &&
                    date.month == selectedDay.month &&
                    date.day == selectedDay.day;
                final isToday = date.year == DateTime.now().year &&
                    date.month == DateTime.now().month &&
                    date.day == DateTime.now().day;

                // 农历/节气/节日 小字
                String? subText;
                Color? subColor;
                if (showLunar) {
                  final lunar = LunarCalendar.fromSolar(date);
                  final term = LunarCalendar.solarTerm(date);
                  final solarFes = LunarCalendar.solarFestival(date);
                  final lunarFes = LunarCalendar.lunarFestival(lunar);
                  if (solarFes != null) {
                    subText = solarFes;
                    subColor = Colors.red.shade400;
                  } else if (lunarFes != null) {
                    subText = lunarFes;
                    subColor = Colors.red.shade400;
                  } else if (term != null) {
                    subText = term;
                    subColor = Colors.green.shade600;
                  } else {
                    subText = lunar.shortDayOrMonth;
                    subColor = Colors.grey.shade500;
                  }
                }

                return Expanded(
                  child: GestureDetector(
                    onTap: () => onDaySelected(date),
                    child: Container(
                      height: cellHeight,
                      margin: const EdgeInsets.symmetric(
                          horizontal: 2, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? cs.primary
                            : (isToday
                                ? cs.primary.withValues(alpha: 0.1)
                                : Colors.transparent),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$dayNum',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isToday || isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? cs.onPrimary
                                  : (isToday ? cs.primary : cs.onSurface),
                            ),
                          ),
                          if (subText != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Text(
                                subText,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: isSelected
                                      ? cs.onPrimary.withValues(alpha: 0.85)
                                      : subColor,
                                ),
                              ),
                            ),
                          if (types.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (types.contains(CalendarEventType.todo))
                                    _dot(
                                        isSelected
                                            ? Colors.white
                                            : cs.primary),
                                  if (types.contains(CalendarEventType.habit))
                                    _dot(isSelected
                                        ? Colors.white70
                                        : cs.tertiary),
                                  if (types.contains(
                                      CalendarEventType.pomodoro))
                                    _dot(isSelected
                                        ? Colors.white54
                                        : Colors.red.shade400),
                                  if (types.contains(
                                      CalendarEventType.anniversary))
                                    _dot(isSelected
                                        ? Colors.white70
                                        : const Color(0xFFE91E63)),
                                  if (types
                                      .contains(CalendarEventType.course))
                                    _dot(isSelected
                                        ? Colors.white60
                                        : const Color(0xFF42A5F5)),
                                  if (types.contains(CalendarEventType.diary))
                                    _dot(isSelected
                                        ? Colors.white60
                                        : const Color(0xFF26A69A)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
        ],
      ),
    );
  }

  Widget _dot(Color color) => Container(
        width: 4,
        height: 4,
        margin: const EdgeInsets.only(left: 1),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
