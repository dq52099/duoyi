import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/anniversary_provider.dart';
import '../providers/course_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/time_audit_provider.dart';
import '../providers/todo_provider.dart';
import '../models/calendar_event.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../models/diary_entry.dart';
import '../core/lunar_calendar.dart';
import '../screens/diary_screen.dart';
import 'calendar_event_sheet.dart';

class CalendarDayAgenda extends StatelessWidget {
  final DateTime date;
  final CalendarProvider calendarProvider;
  final Set<CalendarEventType>? activeTypes;
  final String? projectKey;
  final String? workspaceId;

  const CalendarDayAgenda({
    super.key,
    required this.date,
    required this.calendarProvider,
    this.activeTypes,
    this.projectKey,
    this.workspaceId,
  });

  IconData _icon(CalendarEventType t) {
    switch (t) {
      case CalendarEventType.event:
        return Icons.event_note_outlined;
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
    final events = calendarProvider.getEventsForDate(
      date,
      activeTypes: activeTypes,
      projectKey: projectKey,
      workspaceId: workspaceId,
    );
    final timedEvents = events.where((e) => e.time != null).toList()
      ..sort(
        (a, b) =>
            _eventStartOnDay(a, date).compareTo(_eventStartOnDay(b, date)),
      );
    final untimedEvents = events.where((e) => e.time == null).toList();

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

        if (timedEvents.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionTitle('🕘 时间线'),
          _CalendarDayTimeGrid(date: date, events: timedEvents),
        ],

        if (untimedEvents.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionTitle('📝 全天/无时间'),
          ..._buildTimeline(context, untimedEvents),
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
            '${I18n.tr('calendar.chinese_lunar_calendar')} ${lunar.chineseText}',
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
                child: _DraggableEventCard(event: e),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _CalendarDayTimeGrid extends StatelessWidget {
  static const double _hourHeight = 54;
  static const double _timeColumnWidth = 48;

  final DateTime date;
  final List<CalendarEvent> events;

  const _CalendarDayTimeGrid({required this.date, required this.events});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: _hourHeight * 24,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          for (var hour = 0; hour < 24; hour++)
            Positioned(
              top: hour * _hourHeight,
              left: 0,
              right: 0,
              height: _hourHeight,
              child: _TimelineHourRow(hour: hour),
            ),
          for (var i = 0; i < events.length; i++)
            _positionedEvent(context, events[i], i),
        ],
      ),
    );
  }

  Widget _positionedEvent(
    BuildContext context,
    CalendarEvent event,
    int index,
  ) {
    final start = _eventStartOnDay(event, date);
    final end = _eventEndOnDay(event, date);
    final top = _minutesFromDayStart(start) / 60 * _hourHeight;
    final durationMinutes = math.max(30, end.difference(start).inMinutes);
    final height = math.max(44.0, durationMinutes / 60 * _hourHeight);
    final overlapLane = _overlapLane(event, index);
    final left = _timeColumnWidth + 8 + overlapLane * 10.0;
    final clampedTop = top.clamp(0.0, _hourHeight * 24 - 44).toDouble();
    final clampedHeight = height
        .clamp(44.0, _hourHeight * 24 - clampedTop)
        .toDouble();
    return Positioned(
      top: clampedTop,
      left: left,
      right: 8,
      height: clampedHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: _DraggableEventCard(event: event, compact: clampedHeight < 88),
      ),
    );
  }

  int _overlapLane(CalendarEvent event, int index) {
    final start = _eventStartOnDay(event, date);
    final end = _eventEndOnDay(event, date);
    var overlaps = 0;
    for (var i = 0; i < index; i++) {
      final other = events[i];
      final otherStart = _eventStartOnDay(other, date);
      final otherEnd = _eventEndOnDay(other, date);
      if (start.isBefore(otherEnd) && end.isAfter(otherStart)) overlaps++;
    }
    return overlaps.clamp(0, 2);
  }
}

class _TimelineHourRow extends StatelessWidget {
  final int hour;

  const _TimelineHourRow({required this.hour});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = '${hour.toString().padLeft(2, '0')}:00';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _CalendarDayTimeGrid._timeColumnWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
            ),
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(top: 10, right: 8),
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ],
    );
  }
}

class _DraggableEventCard extends StatefulWidget {
  final CalendarEvent event;
  final bool compact;

  const _DraggableEventCard({required this.event, this.compact = false});

  @override
  State<_DraggableEventCard> createState() => _DraggableEventCardState();
}

class _DraggableEventCardState extends State<_DraggableEventCard> {
  double _dragDy = 0;

  bool get _canDrag =>
      widget.event.sourceId != null &&
      (widget.event.type == CalendarEventType.todo ||
          widget.event.type == CalendarEventType.timeEntry);

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final compact = widget.compact;
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(compact ? 8 : 10);
    final card = InkWell(
      borderRadius: radius,
      onTap: () => showCalendarEventSheet(context, e),
      child: Container(
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
            : const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: radius,
          border: Border.all(
            color: e.hasConflict
                ? cs.error.withValues(alpha: 0.36)
                : Colors.grey.withValues(alpha: 0.1),
          ),
        ),
        child: compact
            ? _buildCompactContent(context, e)
            : _buildRegularContent(context, e),
      ),
    );

    if (!_canDrag) return card;
    return GestureDetector(
      onVerticalDragStart: (_) => _dragDy = 0,
      onVerticalDragUpdate: (details) => _dragDy += details.delta.dy,
      onVerticalDragEnd: (_) => _applyDrag(context),
      child: card,
    );
  }

  Widget _buildCompactContent(BuildContext context, CalendarEvent e) {
    return Row(
      children: [
        if (_canDrag) ...[
          Icon(Icons.drag_indicator, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 3),
        ],
        Expanded(
          child: Text(
            e.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: e.isCompleted ? Colors.grey : null,
              decoration: e.isCompleted ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        if (e.time != null) ...[
          const SizedBox(width: 6),
          Text(
            I18nDateFormat.timeOfDay(
              hour: e.time!.hour,
              minute: e.time!.minute,
            ),
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
        ],
        if (e.hasConflict) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: '时间冲突',
            child: Icon(
              Icons.warning_amber_rounded,
              size: 14,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRegularContent(BuildContext context, CalendarEvent e) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (_canDrag) ...[
              Icon(Icons.drag_indicator, size: 16, color: Colors.grey.shade500),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                e.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: e.isCompleted ? Colors.grey : null,
                  decoration: e.isCompleted ? TextDecoration.lineThrough : null,
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
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
        if (e.time != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              I18nDateFormat.timeOfDay(
                hour: e.time!.hour,
                minute: e.time!.minute,
              ),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
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
    );
  }

  Future<void> _applyDrag(BuildContext context) async {
    if (_dragDy.abs() < 18) return;
    final steps = (_dragDy / 24).round().clamp(-8, 8);
    if (steps == 0) return;
    final delta = Duration(minutes: steps * 15);
    final event = widget.event;
    switch (event.type) {
      case CalendarEventType.todo:
        await _adjustTodo(context, event, delta);
      case CalendarEventType.timeEntry:
        await _adjustTimeEntry(context, event, delta);
      default:
        break;
    }
  }

  Future<void> _adjustTodo(
    BuildContext context,
    CalendarEvent event,
    Duration delta,
  ) async {
    final id = event.sourceId;
    if (id == null) return;
    final provider = context.read<TodoProvider>();
    final matches = provider.todos.where((todo) => todo.id == id);
    if (matches.isEmpty) return;
    final todo = matches.first;
    final base = todo.dueDate ?? todo.date;
    final next = _clampToDay(base.add(delta), event.date);
    await provider.updateTodo(todo.id, todo.copyWith(dueDate: next));
    if (!context.mounted) return;
    _showDragResult(context, next);
  }

  Future<void> _adjustTimeEntry(
    BuildContext context,
    CalendarEvent event,
    Duration delta,
  ) async {
    final id = event.sourceId;
    if (id == null) return;
    final provider = context.read<TimeAuditProvider>();
    final matches = provider.entries.where((entry) => entry.id == id);
    if (matches.isEmpty) return;
    final entry = matches.first;
    final duration = entry.endAt.difference(entry.startAt);
    final next = _clampToDay(entry.startAt.add(delta), event.date);
    await provider.update(
      entry.copyWith(startAt: next, endAt: next.add(duration)),
    );
    if (!context.mounted) return;
    _showDragResult(context, next);
  }

  DateTime _clampToDay(DateTime value, DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day, 23, 45);
    if (value.isBefore(start)) return start;
    if (value.isAfter(end)) return end;
    return DateTime(day.year, day.month, day.day, value.hour, value.minute);
  }

  void _showDragResult(BuildContext context, DateTime value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已调整到 ${I18nDateFormat.time(value)}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }
}

DateTime _eventStartOnDay(CalendarEvent event, DateTime day) {
  final dayStart = _dateOnly(day);
  final eventDay = _dateOnly(event.date);
  if (dayStart.isAfter(eventDay)) return dayStart;
  final time = event.time;
  if (time == null) return dayStart;
  return DateTime(day.year, day.month, day.day, time.hour, time.minute);
}

DateTime _eventEndOnDay(CalendarEvent event, DateTime day) {
  final start = _eventStartOnDay(event, day);
  final dayEnd = _dateOnly(day).add(const Duration(days: 1));
  final endDate = event.endDate;
  if (endDate == null || !endDate.isAfter(start)) {
    final fallback = start.add(const Duration(hours: 1));
    return fallback.isAfter(dayEnd) ? dayEnd : fallback;
  }
  final end = DateTime(
    endDate.year,
    endDate.month,
    endDate.day,
    endDate.hour,
    endDate.minute,
  );
  if (end.isAfter(dayEnd)) return dayEnd;
  if (end.isBefore(start)) {
    final fallback = start.add(const Duration(hours: 1));
    return fallback.isAfter(dayEnd) ? dayEnd : fallback;
  }
  return end;
}

int _minutesFromDayStart(DateTime value) => value.hour * 60 + value.minute;

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

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
