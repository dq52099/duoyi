import 'package:flutter/material.dart';
import '../../core/i18n.dart';
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
    final selectedDotColor = cs.onSurface.withValues(alpha: 0.72);
    final totalCells = startOffset + lastDay.day;
    final rows = (totalCells / 7).ceil();
    final preferredRowHeight = showLunar ? 48.0 : 34.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        const verticalPadding = 8.0;
        const weekdayHeight = 16.0;
        const weekdayGap = 2.0;
        final bounded = constraints.hasBoundedHeight;
        final availableRowHeight = bounded
            ? (constraints.maxHeight -
                      verticalPadding -
                      weekdayHeight -
                      weekdayGap) /
                  rows
            : preferredRowHeight;
        final rowSlotHeight = bounded
            ? availableRowHeight.clamp(10.0, preferredRowHeight)
            : preferredRowHeight;
        final cellHeight = (rowSlotHeight - 2).clamp(8.0, preferredRowHeight);
        final showSubText = showLunar && cellHeight >= 42;
        final showDots = cellHeight >= 29;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Column(
            children: [
              SizedBox(
                height: weekdayHeight,
                child: Row(
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
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: weekdayGap),
              ...List.generate(rows, (row) {
                return SizedBox(
                  height: rowSlotHeight,
                  child: Row(
                    children: List.generate(7, (col) {
                      final dayNum = row * 7 + col - startOffset + 1;
                      if (dayNum < 1 || dayNum > lastDay.day) {
                        return const Expanded(child: SizedBox.expand());
                      }
                      final date = DateTime(
                        focusedMonth.year,
                        focusedMonth.month,
                        dayNum,
                      );
                      final key =
                          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                      final types = dateEventTypes[key] ?? [];
                      final isSelected =
                          date.year == selectedDay.year &&
                          date.month == selectedDay.month &&
                          date.day == selectedDay.day;
                      final isToday =
                          date.year == DateTime.now().year &&
                          date.month == DateTime.now().month &&
                          date.day == DateTime.now().day;
                      final selectedBackground = Color.alphaBlend(
                        cs.primary.withValues(
                          alpha: Theme.of(context).brightness == Brightness.dark
                              ? 0.20
                              : 0.13,
                        ),
                        cs.surface,
                      );
                      final selectedForeground = cs.onSurface;
                      final dayFontSize = cellHeight < 14
                          ? (cellHeight * 0.72).clamp(6.0, 9.0).toDouble()
                          : cellHeight < 28
                          ? 11.0
                          : cellHeight < 36
                          ? 12.0
                          : 13.0;

                      // 农历/节气/节日 小字
                      String? subText;
                      Color? subColor;
                      if (showSubText && I18n.current == AppLocale.zh) {
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
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? selectedBackground
                                  : (isToday
                                        ? cs.primary.withValues(alpha: 0.1)
                                        : Colors.transparent),
                              borderRadius: BorderRadius.circular(9),
                              border: isSelected
                                  ? Border.all(
                                      color: cs.primary.withValues(alpha: 0.26),
                                      width: 0.45,
                                    )
                                  : null,
                            ),
                            child: ClipRect(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '$dayNum',
                                    style: TextStyle(
                                      fontSize: dayFontSize,
                                      height: cellHeight < 14 ? 0.95 : 1.05,
                                      fontWeight: FontWeight.w400,
                                      color: isSelected
                                          ? selectedForeground
                                          : (isToday
                                                ? cs.primary
                                                : cs.onSurface),
                                    ),
                                  ),
                                  if (subText != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 1),
                                      child: Text(
                                        subText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 9,
                                          height: 1,
                                          color: isSelected
                                              ? selectedForeground.withValues(
                                                  alpha: 0.64,
                                                )
                                              : subColor,
                                        ),
                                      ),
                                    ),
                                  if (showDots && types.isNotEmpty)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        top: subText == null ? 3 : 2,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (types.contains(
                                            CalendarEventType.event,
                                          ))
                                            _dot(
                                              isSelected
                                                  ? selectedDotColor
                                                  : const Color(0xFF5B6EE1),
                                            ),
                                          if (types.contains(
                                            CalendarEventType.todo,
                                          ))
                                            _dot(
                                              isSelected
                                                  ? selectedDotColor
                                                  : cs.primary,
                                            ),
                                          if (types.contains(
                                            CalendarEventType.habit,
                                          ))
                                            _dot(
                                              isSelected
                                                  ? selectedDotColor
                                                  : cs.tertiary,
                                            ),
                                          if (types.contains(
                                            CalendarEventType.pomodoro,
                                          ))
                                            _dot(
                                              isSelected
                                                  ? selectedDotColor
                                                  : Colors.red.shade400,
                                            ),
                                          if (types.contains(
                                            CalendarEventType.anniversary,
                                          ))
                                            _dot(
                                              isSelected
                                                  ? selectedDotColor
                                                  : const Color(0xFFE91E63),
                                            ),
                                          if (types.contains(
                                            CalendarEventType.countdown,
                                          ))
                                            _dot(
                                              isSelected
                                                  ? selectedDotColor
                                                  : const Color(0xFFFF8A65),
                                            ),
                                          if (types.contains(
                                            CalendarEventType.course,
                                          ))
                                            _dot(
                                              isSelected
                                                  ? selectedDotColor
                                                  : const Color(0xFF42A5F5),
                                            ),
                                          if (types.contains(
                                            CalendarEventType.diary,
                                          ))
                                            _dot(
                                              isSelected
                                                  ? selectedDotColor
                                                  : const Color(0xFF26A69A),
                                            ),
                                          if (types.contains(
                                            CalendarEventType.timeEntry,
                                          ))
                                            _dot(
                                              isSelected
                                                  ? selectedDotColor
                                                  : const Color(0xFF78909C),
                                            ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _dot(Color color) => Container(
    width: 4,
    height: 4,
    margin: const EdgeInsets.only(left: 1),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
