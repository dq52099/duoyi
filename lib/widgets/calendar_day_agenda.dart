import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/anniversary_provider.dart';
import '../providers/course_provider.dart';
import '../providers/diary_provider.dart';
import '../models/calendar_event.dart';
import '../models/diary_entry.dart';
import '../core/lunar_calendar.dart';
import '../screens/diary_screen.dart';
import 'calendar_event_sheet.dart';

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
      case CalendarEventType.anniversary:
        return Icons.celebration_outlined;
      case CalendarEventType.course:
        return Icons.class_outlined;
      case CalendarEventType.diary:
        return Icons.book_outlined;
      case CalendarEventType.countdown:
        return Icons.hourglass_bottom;
      case CalendarEventType.goal:
        return Icons.flag_circle_outlined;
      case CalendarEventType.timeEntry:
        return Icons.timelapse_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ThemeProvider>().brand.strings;
    final anniversaries = context.watch<AnniversaryProvider>();
    final courses = context.watch<CourseProvider>();
    final diary = context.watch<DiaryProvider>();
    final events = calendarProvider.getEventsForDate(date);
    events.sort((a, b) => (a.time?.hour ?? 0).compareTo(b.time?.hour ?? 0));

    final lunar = LunarCalendar.fromSolar(date);
    final term = LunarCalendar.solarTerm(date);
    final solarFes = LunarCalendar.solarFestival(date);
    final lunarFes = LunarCalendar.lunarFestival(lunar);

    // 纪念日命中
    final hitAnniversaries = anniversaries.items.where((a) {
      final n = a.nextOccurrence;
      return n.year == date.year && n.month == date.month && n.day == date.day;
    }).toList();

    // 课表
    final todayCourses = courses.coursesOfDate(date);

    final todayDiary = diary.entryForDate(date);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // 农历 / 节日 / 节气头
        _dayHeader(context, lunar, term, solarFes, lunarFes),

        // 日记按钮
        _DiaryQuickEntry(date: date, entry: todayDiary),

        if (hitAnniversaries.isNotEmpty) ...[
          const SizedBox(height: 8),
          _sectionTitle('🎉 今日纪念'),
          ...hitAnniversaries.map(
            (a) => _AnniversaryTile(
              title: a.title,
              color: Color(a.colorValue),
              subtitle: a.yearsPassed != null
                  ? '第 ${a.yearsPassed! + 1} 次'
                  : null,
            ),
          ),
        ],

        if (todayCourses.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionTitle('📚 今日课程'),
          ...todayCourses.map(
            (c) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Color(c.colorValue).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Color(c.colorValue).withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.class_outlined,
                    color: Color(c.colorValue),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w400,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '第${c.startSection}-${c.endSection}节${c.location.isNotEmpty ? ' · ${c.location}' : ''}${c.teacher.isNotEmpty ? ' · ${c.teacher}' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        if (events.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionTitle('📝 日程'),
          ..._buildTimeline(context, events),
        ],

        if (events.isEmpty && hitAnniversaries.isEmpty && todayCourses.isEmpty)
          Padding(
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
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _dayHeader(
    BuildContext context,
    LunarDate lunar,
    String? term,
    String? solarFes,
    String? lunarFes,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.wb_sunny_outlined, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            '农历 ${lunar.chineseText}',
            style: TextStyle(
              fontSize: 13,
              color: cs.primary,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(width: 8),
          if (term != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                term,
                style: const TextStyle(fontSize: 11, color: Colors.green),
              ),
            ),
          if (solarFes != null) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                solarFes,
                style: const TextStyle(fontSize: 11, color: Colors.red),
              ),
            ),
          ],
          if (lunarFes != null) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.deepOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                lunarFes,
                style: const TextStyle(fontSize: 11, color: Colors.deepOrange),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: Colors.grey.shade600,
        fontWeight: FontWeight.w400,
      ),
    ),
  );

  List<Widget> _buildTimeline(
    BuildContext context,
    List<CalendarEvent> events,
  ) {
    return List.generate(events.length, (index) {
      final e = events[index];
      final isLast = index == events.length - 1;
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                    child: Icon(_icon(e.type), color: e.color, size: 14),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(width: 2, color: Colors.grey.shade200),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => showCalendarEventSheet(context, e),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: e.hasConflict
                            ? Theme.of(
                                context,
                              ).colorScheme.error.withValues(alpha: 0.36)
                            : Colors.grey.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.title,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: e.isCompleted ? Colors.grey : null,
                                  decoration: e.isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                            if (e.hasConflict)
                              Tooltip(
                                message: '时间冲突',
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                          ],
                        ),
                        if (e.subtitle != null && e.subtitle!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              e.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        if (e.time != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              '${e.time!.hour.toString().padLeft(2, '0')}:${e.time!.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _DiaryQuickEntry extends StatelessWidget {
  final DateTime date;
  final DiaryEntry? entry;
  const _DiaryQuickEntry({required this.date, required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasEntry = entry != null;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DiaryEditScreen(entry: entry, initialDate: date),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: hasEntry
              ? cs.primary.withValues(alpha: 0.08)
              : Colors.grey.shade50,
          border: Border.all(
            color: hasEntry
                ? cs.primary.withValues(alpha: 0.2)
                : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Icon(
              hasEntry ? Icons.book : Icons.edit_note,
              size: 18,
              color: hasEntry ? cs.primary : Colors.grey.shade600,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasEntry ? entry!.title : '写下这一天的日记',
                style: TextStyle(
                  fontSize: 13,
                  color: hasEntry ? cs.primary : Colors.grey.shade600,
                  fontWeight: hasEntry ? FontWeight.w400 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasEntry && entry!.mood != null)
              Text(entry!.mood!.emoji, style: const TextStyle(fontSize: 16)),
            Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

class _AnniversaryTile extends StatelessWidget {
  final String title;
  final Color color;
  final String? subtitle;

  const _AnniversaryTile({
    required this.title,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.celebration_outlined, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w400,
                    fontSize: 13,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
