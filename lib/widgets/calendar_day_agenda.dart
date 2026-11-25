import '../core/almanac_locale_format.dart';
import '../core/almanac_ui_copy.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/anniversary_provider.dart';
import '../providers/course_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/time_audit_provider.dart';
import '../providers/todo_provider.dart';
import '../core/completion_visibility_policy.dart';
import '../core/design_tokens.dart';
import '../core/todo_templates.dart';
import '../models/calendar_event.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/main_ui_copy.dart';
import '../models/diary_entry.dart';
import '../models/todo.dart';
import '../core/calendar_agenda_ui_copy.dart';
import '../core/lunar_calendar.dart';
import '../screens/almanac_screen.dart';
import '../screens/diary_screen.dart';
import '../services/holiday_calendar.dart';
import '../core/calendar_event_display_text.dart';
import 'brand_background.dart' show BrandRouteSurface;
import 'calendar_event_sheet.dart';
import 'surface_components.dart';

class CalendarDayAgenda extends StatelessWidget {
  final DateTime date;
  final CalendarProvider calendarProvider;
  final Set<CalendarEventType>? activeTypes;
  final String? projectKey;
  final String? workspaceId;
  final double horizontalPadding;
  final bool scrollable;
  final int? previewLimit;
  final bool? hasActiveFilters;

  const CalendarDayAgenda({
    super.key,
    required this.date,
    required this.calendarProvider,
    this.activeTypes,
    this.projectKey,
    this.workspaceId,
    this.horizontalPadding = 16,
    this.scrollable = true,
    this.previewLimit,
    this.hasActiveFilters,
  });

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLocale>(
    valueListenable: I18n.localeListenable,
    builder: (context, locale, child) => _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final s = context.watch<ThemeProvider>().brand.strings;
    final showLunar = context.select<PreferencesProvider?, bool>(
      (p) => p?.showLunar ?? true,
    );
    final anniversaries = context.watch<AnniversaryProvider>();
    final courses = context.watch<CourseProvider>();
    final diary = context.watch<DiaryProvider>();
    final events = calendarProvider.getEventsForDate(
      date,
      activeTypes: activeTypes,
      projectKey: projectKey,
      workspaceId: workspaceId,
    );
    final todoById = {
      for (final todo in context.read<TodoProvider>().todos) todo.id: todo,
    };
    final visibleEvents = previewLimit == null
        ? events
        : events.take(previewLimit!.clamp(0, events.length)).toList();
    final hiddenEventCount = events.length - visibleEvents.length;
    final timedEvents = visibleEvents.where((e) => e.time != null).toList()
      ..sort(
        (a, b) =>
            _eventStartOnDay(a, date).compareTo(_eventStartOnDay(b, date)),
      );
    final untimedEvents = visibleEvents.where((e) => e.time == null).toList();

    final lunar = LunarCalendar.fromSolar(date);
    final term = LunarCalendar.solarTerm(date);
    final solarFes = LunarCalendar.solarFestival(date);
    final lunarFes = LunarCalendar.lunarFestival(lunar);

    // 纪念日命中
    final hitAnniversaries = anniversaries.itemsAt(date).where((a) {
      final n = a.nextOccurrenceForDate(date);
      return n.year == date.year && n.month == date.month && n.day == date.day;
    }).toList();

    // 课表
    final todayCourses = courses.coursesOfDate(date);

    final todayDiary = diary.entryForDate(date);

    final isFilterActive =
        hasActiveFilters ?? (activeTypes != null || projectKey != null);

    final children = [
      // 农历 / 节日 / 节气 / 放假 / 周数星座头
      _dayHeader(
        context,
        lunar,
        term,
        solarFes,
        lunarFes,
        showLunar: showLunar,
      ),

      // 日记按钮
      _DiaryQuickEntry(date: date, entry: todayDiary),

      if (hitAnniversaries.isNotEmpty) ...[
        const SizedBox(height: 8),
        _sectionTitle(CalendarAgendaUiCopy.anniversarySectionTitleForDate(date)),
        ...hitAnniversaries.map(
          (a) => _AnniversaryTile(
            title: a.title,
            color: Color(a.colorValue),
            subtitle: a.yearsPassedForDate(date) != null
                ? CalendarAgendaUiCopy.anniversaryCount(
                    a.yearsPassedForDate(date)! + 1,
                  )
                : null,
          ),
        ),
      ],

      if (todayCourses.isNotEmpty) ...[
        const SizedBox(height: 12),
        _sectionTitle(CalendarAgendaUiCopy.courseSectionTitleForDate(date)),
        ...todayCourses.map(
          (c) => AppSurfaceCard(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
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
                          fontWeight: FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${CalendarAgendaUiCopy.coursePeriod(c.startSection, c.endSection)}${c.location.isNotEmpty ? ' · ${c.location}' : ''}${c.teacher.isNotEmpty ? ' · ${c.teacher}' : ''}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        _sectionTitle(CalendarAgendaUiCopy.timelineSectionTitle),
        _CalendarDayTimeGrid(
          date: date,
          events: timedEvents,
          todoById: todoById,
        ),
      ],

      if (untimedEvents.isNotEmpty) ...[
        const SizedBox(height: 12),
        _sectionTitle(CalendarAgendaUiCopy.allDaySectionTitle),
        ..._buildTimeline(context, untimedEvents, todoById),
      ],

      if (hiddenEventCount > 0)
        _AgendaOverflowNotice(hiddenCount: hiddenEventCount),

      if (events.isEmpty && hitAnniversaries.isEmpty && todayCourses.isEmpty)
        Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isFilterActive
                      ? Icons.filter_alt_off_outlined
                      : Icons.event_available_outlined,
                  size: 44,
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 14),
                Text(
                  isFilterActive
                      ? MainUiCopy.calendarNoEventsDayFilter
                      : (events.isEmpty
                            ? MainUiCopy.calendarNoEventsDay
                            : s.calendarEmpty),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isFilterActive
                      ? MainUiCopy.calendarEmptyFilterHint
                      : MainUiCopy.calendarEmptyDayHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 24),
    ];

    if (!scrollable) {
      return Padding(
        key: const ValueKey('calendar_day_agenda_inline_content'),
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
    }

    return Scrollbar(
      child: ListView(
        key: const ValueKey('calendar_day_agenda_scroll_view'),
        primary: false,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        children: children,
      ),
    );
  }

  Widget _dayHeader(
    BuildContext context,
    LunarDate lunar,
    String? term,
    String? solarFes,
    String? lunarFes, {
    bool showLunar = true,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    final headerSurface = Color.alphaBlend(
      cs.primary.withValues(alpha: 0.06),
      Color.alphaBlend(
        surfaceStyle?.cardFillColor ?? cs.surface,
        theme.scaffoldBackgroundColor,
      ),
    );
    final headerForeground = surfaceStyle == null
        ? cs.primary
        : appReadableForeground(headerSurface, cs.primary);
    final isHoliday = HolidayCalendar.isHoliday(date);
    final isMakeup = HolidayCalendar.isWorkMakeupDay(date);
    final holidayName = isHoliday ? HolidayCalendar.holidayName(date) : null;
    final isoWeek = LunarCalendar.isoWeekNumber(date);
    var xingZuo = '';
    try {
      xingZuo = AlmanacLocaleFormat.formatXingZuo(LunarCalendar.xingZuo(date));
    } catch (_) {}
    final weekConstellationText = xingZuo.isEmpty
        ? AlmanacUiCopy.isoWeekBadge(isoWeek)
        : '${AlmanacUiCopy.isoWeekBadge(isoWeek)} · $xingZuo';
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.wb_sunny_outlined, size: 16, color: cs.primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (showLunar)
                  Text(
                    '${I18n.tr('calendar.chinese_lunar_calendar')} ${AlmanacLocaleFormat.formatLunarDate(lunar)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: headerForeground,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                if (isHoliday)
                  _dayBadge(
                    holidayName != null && holidayName.isNotEmpty
                        ? '${AlmanacUiCopy.holidayTag} · $holidayName'
                        : AlmanacUiCopy.holidayBadge,
                    cs.brightness == Brightness.dark
                        ? const Color(0xFF4DB6AC)
                        : const Color(0xFF00796B),
                    (cs.brightness == Brightness.dark
                            ? const Color(0xFF4DB6AC)
                            : const Color(0xFF00796B))
                        .withValues(alpha: 0.12),
                    surface: surfaceStyle == null ? null : headerSurface,
                  ),
                if (isMakeup)
                  _dayBadge(
                    AlmanacUiCopy.makeupWorkdayBadge,
                    cs.brightness == Brightness.dark
                        ? const Color(0xFFB39DDB)
                        : const Color(0xFF5E35B1),
                    (cs.brightness == Brightness.dark
                            ? const Color(0xFFB39DDB)
                            : const Color(0xFF5E35B1))
                        .withValues(alpha: 0.12),
                    surface: surfaceStyle == null ? null : headerSurface,
                  ),
                if (term != null)
                  _dayBadge(
                    AlmanacLocaleFormat.formatSolarTerm(term)!,
                    cs.brightness == Brightness.dark
                        ? DesignTokens.todoCompletedDark
                        : DesignTokens.defaultSuccess,
                    (cs.brightness == Brightness.dark
                            ? DesignTokens.todoCompletedDark
                            : DesignTokens.defaultSuccess)
                        .withValues(alpha: 0.12),
                    surface: surfaceStyle == null ? null : headerSurface,
                  ),
                if (solarFes != null)
                  _dayBadge(
                    AlmanacLocaleFormat.formatFestival(solarFes)!,
                    cs.brightness == Brightness.dark
                        ? DesignTokens.todoOverdueDark
                        : DesignTokens.defaultError,
                    (cs.brightness == Brightness.dark
                            ? DesignTokens.todoOverdueDark
                            : DesignTokens.defaultError)
                        .withValues(alpha: 0.12),
                    surface: surfaceStyle == null ? null : headerSurface,
                  ),
                if (lunarFes != null)
                  _dayBadge(
                    AlmanacLocaleFormat.formatFestival(lunarFes)!,
                    cs.brightness == Brightness.dark
                        ? DesignTokens.todoDueSoonDark
                        : DesignTokens.todoDueSoon,
                    (cs.brightness == Brightness.dark
                            ? DesignTokens.todoDueSoonDark
                            : DesignTokens.todoDueSoon)
                        .withValues(alpha: 0.12),
                    surface: surfaceStyle == null ? null : headerSurface,
                  ),
                _dayBadge(
                  weekConstellationText,
                  cs.primary,
                  cs.primary.withValues(alpha: 0.09),
                  surface: surfaceStyle == null ? null : headerSurface,
                ),
                Semantics(
                  button: true,
                  label: AlmanacUiCopy.openAlmanacLabel,
                  child: InkWell(
                    key: const ValueKey('agenda_open_almanac_chip'),
                    borderRadius: BorderRadius.circular(999),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BrandRouteSurface(
                            child: AlmanacScreen(initialDate: date),
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: cs.primary.withValues(alpha: 0.25),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              AlmanacUiCopy.openAlmanacLabel,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: headerForeground,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 13,
                            color: headerForeground,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayBadge(
    String text,
    Color color,
    Color backgroundColor, {
    Color? surface,
  }) {
    final foreground = surface == null
        ? color
        : appReadableForeground(Color.alphaBlend(backgroundColor, surface), color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: foreground)),
    );
  }

  Widget _sectionTitle(String text) => Builder(
    builder: (context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.normal,
        ),
      ),
    ),
  );

  List<Widget> _buildTimeline(
    BuildContext context,
    List<CalendarEvent> events,
    Map<String, TodoItem> todoById,
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
                    child: Builder(
                      builder: (context) {
                        final visual = _calendarEventVisual(e, todoById);
                        return Icon(visual.icon, color: visual.color, size: 14);
                      },
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: Theme.of(context).colorScheme.outlineVariant
                            .withValues(
                              alpha:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? 0.28
                                  : 0.45,
                            ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DraggableEventCard(event: e, todoById: todoById),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _CalendarEventPlacement {
  final double top;
  final double height;
  final double left;
  final double width;

  const _CalendarEventPlacement({
    required this.top,
    required this.height,
    required this.left,
    required this.width,
  });
}

class _CalendarDayTimeGrid extends StatefulWidget {
  static const double _hourHeight = 54;
  static const double _timeColumnWidth = 48;

  final DateTime date;
  final List<CalendarEvent> events;
  final Map<String, TodoItem> todoById;

  const _CalendarDayTimeGrid({
    required this.date,
    required this.events,
    required this.todoById,
  });

  static double _resolveTimeColumnWidth(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final defaultTextStyle = DefaultTextStyle.of(context);
    var labelStyle = TextStyle(
      fontSize: 10,
      color: cs.onSurfaceVariant.withValues(alpha: 0.72),
    );
    if (labelStyle.inherit) {
      labelStyle = defaultTextStyle.style.merge(labelStyle);
    }
    if (MediaQuery.boldTextOf(context)) {
      labelStyle = labelStyle.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final locale = Localizations.maybeLocaleOf(context);

    var maxLabelWidth = 0.0;
    final painter = TextPainter(
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
    );
    try {
      for (var hour = 0; hour < 24; hour++) {
        final label = '${hour.toString().padLeft(2, '0')}:00';
        painter.text = TextSpan(text: label, style: labelStyle);
        painter.layout();
        final width = math.max(painter.width, painter.maxIntrinsicWidth);
        if (width > maxLabelWidth) {
          maxLabelWidth = width;
        }
      }
    } finally {
      painter.dispose();
    }
    return math.max(_timeColumnWidth, maxLabelWidth);
  }

  @override
  State<_CalendarDayTimeGrid> createState() => _CalendarDayTimeGridState();
}

class _CalendarDayTimeGridState extends State<_CalendarDayTimeGrid> {
  final ScrollController _horizontalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  static double _measureCompactEventWidth(
    BuildContext context,
    CalendarEvent event,
  ) {
    final defaultStyle = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final locale = Localizations.maybeLocaleOf(context);

    final title = CalendarEventDisplayText.resolveTitle(event);
    var titleStyle = const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.normal,
    );
    if (titleStyle.inherit) {
      titleStyle = defaultStyle.merge(titleStyle);
    }
    if (MediaQuery.boldTextOf(context)) {
      titleStyle = titleStyle.merge(const TextStyle(fontWeight: FontWeight.bold));
    }

    final titlePainter = TextPainter(
      text: TextSpan(text: title, style: titleStyle),
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
      maxLines: 1,
    )..layout();
    final rawTitleWidth = titlePainter.width;
    titlePainter.dispose();

    // Cap measured title contribution at 12em of the scaled 12px font for one-line preview.
    final maxTitlePreviewBudget = scaler.scale(12.0) * 12.0;
    final titleWidth = math.min(rawTitleWidth, maxTitlePreviewBudget);

    double timeWidth = 0.0;
    if (event.time != null) {
      final timeText = I18nDateFormat.timeOfDay(
        hour: event.time!.hour,
        minute: event.time!.minute,
      );
      var timeStyle = const TextStyle(fontSize: 10);
      if (timeStyle.inherit) {
        timeStyle = defaultStyle.merge(timeStyle);
      }
      if (MediaQuery.boldTextOf(context)) {
        timeStyle = timeStyle.merge(const TextStyle(fontWeight: FontWeight.bold));
      }
      final timePainter = TextPainter(
        text: TextSpan(text: timeText, style: timeStyle),
        textDirection: direction,
        textScaler: scaler,
        locale: locale,
        maxLines: 1,
      )..layout();
      timeWidth = timePainter.width;
      timePainter.dispose();
    }

    double badgeWidth = 0.0;
    final visual = _eventVisualState(event);
    final isCompleted = visual == TodoVisualState.completed;
    final isOverdue = visual == TodoVisualState.overdue;
    if (isCompleted || isOverdue) {
      final badgeLabel = isCompleted
          ? MainUiCopy.calendarStatusCompleted
          : MainUiCopy.calendarStatusOverdue;
      var badgeStyle = const TextStyle(fontSize: 10);
      if (badgeStyle.inherit) {
        badgeStyle = defaultStyle.merge(badgeStyle);
      }
      if (MediaQuery.boldTextOf(context)) {
        badgeStyle = badgeStyle.merge(const TextStyle(fontWeight: FontWeight.bold));
      }
      final badgePainter = TextPainter(
        text: TextSpan(text: badgeLabel, style: badgeStyle),
        textDirection: direction,
        textScaler: scaler,
        locale: locale,
        maxLines: 1,
      )..layout();
      badgeWidth = 6.0 + badgePainter.width + 12.0;
      badgePainter.dispose();
    }

    final baseWidth = 16.0 +
        19.0 +
        (event.time != null ? (6.0 + timeWidth) : 0.0) +
        (event.hasConflict ? 18.0 : 0.0) +
        badgeWidth +
        4.0;
    return baseWidth + titleWidth;
  }

  (List<_CalendarEventPlacement>, double) _computeEventPlacements(
    BuildContext context,
    double availableWidth,
  ) {
    final events = widget.events;
    final date = widget.date;
    const hourHeight = _CalendarDayTimeGrid._hourHeight;

    if (events.isEmpty) {
      return (<_CalendarEventPlacement>[], availableWidth);
    }

    final rawTops = List<double>.filled(events.length, 0);
    final rawHeights = List<double>.filled(events.length, 0);
    final rawBottoms = List<double>.filled(events.length, 0);

    for (var i = 0; i < events.length; i++) {
      final event = events[i];
      final start = _eventStartOnDay(event, date);
      final end = _eventEndOnDay(event, date);
      final top = _minutesFromDayStart(start) / 60 * hourHeight;
      final durationMinutes = math.max(30, end.difference(start).inMinutes);
      final height = math.max(44.0, durationMinutes / 60 * hourHeight);
      final clampedTop = top.clamp(0.0, hourHeight * 24 - 44).toDouble();
      final clampedHeight = height
          .clamp(44.0, hourHeight * 24 - clampedTop)
          .toDouble();
      rawTops[i] = clampedTop;
      rawHeights[i] = clampedHeight;
      rawBottoms[i] = clampedTop + clampedHeight;
    }

    final parent = List<int>.generate(events.length, (i) => i);
    int find(int i) {
      var root = i;
      while (root != parent[root]) {
        root = parent[root];
      }
      var curr = i;
      while (curr != root) {
        final next = parent[curr];
        parent[curr] = root;
        curr = next;
      }
      return root;
    }

    void union(int i, int j) {
      final rootI = find(i);
      final rootJ = find(j);
      if (rootI != rootJ) {
        parent[rootI] = rootJ;
      }
    }

    for (var i = 0; i < events.length; i++) {
      for (var j = i + 1; j < events.length; j++) {
        final overlap = math.min(rawBottoms[i], rawBottoms[j]) -
            math.max(rawTops[i], rawTops[j]);
        if (overlap > 0.1) {
          union(i, j);
        }
      }
    }

    final groups = <int, List<int>>{};
    for (var i = 0; i < events.length; i++) {
      groups.putIfAbsent(find(i), () => []).add(i);
    }

    final laneAssignments = List<int>.filled(events.length, 0);
    final groupLaneCounts = <int, int>{};

    for (final entry in groups.entries) {
      final groupIndices = entry.value;
      groupIndices.sort((a, b) {
        final cmp = rawTops[a].compareTo(rawTops[b]);
        return cmp != 0 ? cmp : a.compareTo(b);
      });
      final laneEndTimes = <double>[];
      for (final idx in groupIndices) {
        final top = rawTops[idx];
        final bottom = rawBottoms[idx];
        int assigned = -1;
        for (var l = 0; l < laneEndTimes.length; l++) {
          if (laneEndTimes[l] <= top + 0.1) {
            assigned = l;
            laneEndTimes[l] = bottom;
            break;
          }
        }
        if (assigned == -1) {
          assigned = laneEndTimes.length;
          laneEndTimes.add(bottom);
        }
        laneAssignments[idx] = assigned;
      }
      groupLaneCounts[entry.key] = laneEndTimes.length;
    }

    const double laneGap = 4.0;
    final placements = List<_CalendarEventPlacement?>.filled(events.length, null);
    double maxTotalGroupWidth = availableWidth;

    for (final entry in groups.entries) {
      final groupRoot = entry.key;
      final groupIndices = entry.value;
      final k = groupLaneCounts[groupRoot] ?? 1;

      double maxRequiredWidth = 0.0;
      for (final idx in groupIndices) {
        final required = _measureCompactEventWidth(context, events[idx]);
        if (required > maxRequiredWidth) {
          maxRequiredWidth = required;
        }
      }
      final minLaneWidth = math.max(120.0, maxRequiredWidth);

      if (k <= 1) {
        final cardWidth = math.max(availableWidth, minLaneWidth);
        for (final idx in groupIndices) {
          placements[idx] = _CalendarEventPlacement(
            top: rawTops[idx],
            height: rawHeights[idx],
            left: 0.0,
            width: cardWidth,
          );
        }
        if (cardWidth > maxTotalGroupWidth) {
          maxTotalGroupWidth = cardWidth;
        }
      } else {
        final totalMinGroupWidth = k * minLaneWidth + (k - 1) * laneGap;
        final double laneWidth;
        if (totalMinGroupWidth <= availableWidth) {
          laneWidth = (availableWidth - (k - 1) * laneGap) / k;
        } else {
          laneWidth = minLaneWidth;
        }
        final groupWidth = k * laneWidth + (k - 1) * laneGap;
        if (groupWidth > maxTotalGroupWidth) {
          maxTotalGroupWidth = groupWidth;
        }
        for (final idx in groupIndices) {
          final lane = laneAssignments[idx];
          final left = lane * (laneWidth + laneGap);
          placements[idx] = _CalendarEventPlacement(
            top: rawTops[idx],
            height: rawHeights[idx],
            left: left,
            width: laneWidth,
          );
        }
      }
    }

    return (
      placements.map((p) => p!).toList(growable: false),
      maxTotalGroupWidth,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final timeColumnWidth = _CalendarDayTimeGrid._resolveTimeColumnWidth(context);
    return Container(
      height: _CalendarDayTimeGrid._hourHeight * 24,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.10),
          width: 0.45,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final availableEventsWidth = math.max(
            0.0,
            totalWidth - (timeColumnWidth + 8) - 8,
          );
          final (placements, contentWidth) = _computeEventPlacements(
            context,
            availableEventsWidth,
          );

          return Stack(
            children: [
              for (var hour = 0; hour < 24; hour++)
                Positioned(
                  top: hour * _CalendarDayTimeGrid._hourHeight,
                  left: 0,
                  right: 0,
                  height: _CalendarDayTimeGrid._hourHeight,
                  child: _TimelineHourRow(
                    hour: hour,
                    timeColumnWidth: timeColumnWidth,
                  ),
                ),
              Positioned(
                top: 0,
                bottom: 0,
                left: timeColumnWidth + 8,
                right: 8,
                child: Scrollbar(
                  controller: _horizontalController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _horizontalController,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: SizedBox(
                      width: contentWidth,
                      height: _CalendarDayTimeGrid._hourHeight * 24,
                      child: Stack(
                        children: [
                          for (var i = 0; i < widget.events.length; i++)
                            _buildPositionedEvent(
                              context,
                              widget.events[i],
                              placements[i],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPositionedEvent(
    BuildContext context,
    CalendarEvent event,
    _CalendarEventPlacement placement,
  ) {
    return Positioned(
      top: placement.top,
      left: placement.left,
      width: placement.width,
      height: placement.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: _DraggableEventCard(
          event: event,
          compact: placement.height < 88,
          timelineHeight: placement.height,
          todoById: widget.todoById,
        ),
      ),
    );
  }
}

class _AgendaOverflowNotice extends StatelessWidget {
  final int hiddenCount;

  const _AgendaOverflowNotice({required this.hiddenCount});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        CalendarAgendaUiCopy.overflowNotice(hiddenCount),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          color: cs.onSurfaceVariant.withValues(alpha: 0.72),
        ),
      ),
    );
  }
}

class _TimelineHourRow extends StatelessWidget {
  final int hour;
  final double timeColumnWidth;

  const _TimelineHourRow({
    required this.hour,
    this.timeColumnWidth = _CalendarDayTimeGrid._timeColumnWidth,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = '${hour.toString().padLeft(2, '0')}:00';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: timeColumnWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurfaceVariant.withValues(alpha: 0.72),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(top: 10, right: 8),
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.08),
          ),
        ),
      ],
    );
  }
}

class _DraggableEventCard extends StatefulWidget {
  final CalendarEvent event;
  final bool compact;
  final double? timelineHeight;
  final Map<String, TodoItem> todoById;

  const _DraggableEventCard({
    required this.event,
    required this.todoById,
    this.compact = false,
    this.timelineHeight,
  });

  @override
  State<_DraggableEventCard> createState() => _DraggableEventCardState();
}

class _DraggableEventCardState extends State<_DraggableEventCard> {
  double _dragDy = 0;

  bool get _canDrag =>
      widget.timelineHeight != null &&
      widget.event.time != null &&
      widget.event.sourceId != null &&
      (widget.event.type == CalendarEventType.todo ||
          widget.event.type == CalendarEventType.timeEntry);

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final title = CalendarEventDisplayText.resolveTitle(e);
    final subtitle = CalendarEventDisplayText.resolveSubtitle(e);
    final scaler = MediaQuery.textScalerOf(context);
    final regularHeight =
        scaler.scale(13) * 1.2 * 2 +
        (subtitle?.isNotEmpty == true ? 3 + scaler.scale(11) * 1.2 : 0) +
        (e.time != null ? 3 + scaler.scale(11) * 1.2 : 0) +
        16;
    final compact =
        widget.compact ||
        (widget.timelineHeight != null &&
            widget.timelineHeight! - 20.9 < regularHeight);
    final cs = Theme.of(context).colorScheme;
    final visual = _eventVisualState(e);
    final isCompleted = visual == TodoVisualState.completed;
    final isOverdue = visual == TodoVisualState.overdue;
    final statusColor = isCompleted
        ? cs.tertiary
        : isOverdue
        ? cs.error
        : null;
    final radius = BorderRadius.circular(compact ? 8 : 10);
    if (widget.timelineHeight == null && appSurfaceStyleOf(context) != null) {
      return AppSurfaceCard(
        padding: EdgeInsets.zero,
        borderRadius: radius,
        onTap: () => showCalendarEventSheet(context, e),
        border: e.hasConflict || statusColor != null
            ? Border.all(
                color: e.hasConflict
                    ? cs.error.withValues(alpha: 0.36)
                    : statusColor!.withValues(alpha: 0.24),
                width: 0.45,
              )
            : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: statusColor?.withValues(alpha: 0.07),
            borderRadius: radius,
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: _buildRegularContent(
              context,
              e,
              title: title,
              subtitle: subtitle,
              limitedHeight: false,
            ),
          ),
        ),
      );
    }
    final card = InkWell(
      borderRadius: radius,
      onTap: () => showCalendarEventSheet(context, e),
      child: Container(
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
            : const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: statusColor == null
              ? cs.surface
              : Color.alphaBlend(
                  statusColor.withValues(alpha: 0.07),
                  cs.surface,
                ),
          borderRadius: radius,
          border: Border.all(
            color: e.hasConflict
                ? cs.error.withValues(alpha: 0.36)
                : statusColor != null
                ? statusColor.withValues(alpha: 0.24)
                : cs.outlineVariant.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.22
                        : 0.14,
                  ),
            width: 0.45,
          ),
        ),
        child: compact
            ? _buildCompactContent(context, e, title: title)
            : _buildRegularContent(
                context,
                e,
                title: title,
                subtitle: subtitle,
                limitedHeight: widget.timelineHeight != null,
              ),
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

  Widget _buildCompactContent(
    BuildContext context,
    CalendarEvent e, {
    required String title,
  }) {
    final visual = _eventVisualState(e);
    final eventVisual = _calendarEventVisual(e, widget.todoById);
    final cs = Theme.of(context).colorScheme;
    final isCompleted = visual == TodoVisualState.completed;
    final isOverdue = visual == TodoVisualState.overdue;
    final statusColor = isCompleted
        ? cs.tertiary
        : isOverdue
        ? cs.error
        : null;
    return Row(
      children: [
        Tooltip(
          message: isCompleted
              ? MainUiCopy.calendarStatusCompleted
              : isOverdue
              ? MainUiCopy.calendarStatusOverdue
              : e.type.label,
          child: Icon(
            isCompleted
                ? Icons.check_circle_outline
                : isOverdue
                ? Icons.schedule
                : eventVisual.icon,
            size: 14,
            color: statusColor ?? eventVisual.color,
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            title,
            key: ValueKey('calendar-compact-title-${e.id}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.normal,
              color: isCompleted
                  ? cs.onSurfaceVariant
                  : isOverdue
                  ? _readableStateForeground(
                      cs.error,
                      isDark: cs.brightness == Brightness.dark,
                    )
                  : null,
              decoration: isCompleted ? TextDecoration.lineThrough : null,
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
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
        if (e.hasConflict) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: CalendarAgendaUiCopy.timeConflictTooltip,
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

  Widget _buildRegularContent(
    BuildContext context,
    CalendarEvent e, {
    required String title,
    required String? subtitle,
    required bool limitedHeight,
  }) {
    final visual = _eventVisualState(e);
    final eventVisual = _calendarEventVisual(e, widget.todoById);
    final cs = Theme.of(context).colorScheme;
    final isCompleted = visual == TodoVisualState.completed;
    final isOverdue = visual == TodoVisualState.overdue;
    final statusColor = isCompleted
        ? cs.tertiary
        : isOverdue
        ? cs.error
        : null;
    final stackStatus = !limitedHeight && appSurfaceStyleOf(context) != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (_canDrag) ...[
              Icon(Icons.drag_indicator, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
            ],
            Icon(eventVisual.icon, size: 16, color: eventVisual.color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                maxLines: limitedHeight ? 2 : null,
                overflow: limitedHeight ? TextOverflow.ellipsis : null,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.2,
                  fontWeight: FontWeight.normal,
                  color: isCompleted
                      ? cs.onSurfaceVariant
                      : isOverdue
                      ? _readableStateForeground(
                          cs.error,
                          isDark: cs.brightness == Brightness.dark,
                        )
                      : null,
                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (statusColor != null && !stackStatus) ...[
              const SizedBox(width: 6),
              _CalendarAgendaStatusBadge(
                label: isCompleted
                    ? MainUiCopy.calendarStatusCompleted
                    : MainUiCopy.calendarStatusOverdue,
                color: statusColor,
              ),
            ],
            if (e.hasConflict && !stackStatus)
              Tooltip(
                message: CalendarAgendaUiCopy.timeConflictTooltip,
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
          ],
        ),
        if (stackStatus && (statusColor != null || e.hasConflict))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (statusColor != null)
                  _CalendarAgendaStatusBadge(
                    label: isCompleted
                        ? MainUiCopy.calendarStatusCompleted
                        : MainUiCopy.calendarStatusOverdue,
                    color: statusColor,
                    useSurfaceForeground: true,
                  ),
                if (e.hasConflict)
                  Tooltip(
                    message: CalendarAgendaUiCopy.timeConflictTooltip,
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: cs.error,
                    ),
                  ),
              ],
            ),
          ),
        if (subtitle != null && subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              subtitle,
              maxLines: limitedHeight ? 1 : null,
              overflow: limitedHeight ? TextOverflow.ellipsis : null,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                color: cs.onSurfaceVariant,
              ),
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
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                color: cs.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: Icon(
            Icons.chevron_right,
            size: 16,
            color: cs.onSurfaceVariant,
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
    final waitForReminderSync = _todoNeedsReminderSync(todo);
    try {
      final saveResult = await provider.updateTodoWithResult(
        todo.id,
        todo.copyWith(dueDate: next),
        waitForReminderSync: waitForReminderSync,
      );
      if (!context.mounted) return;
      if (!saveResult.saved) {
        _showDragFailure(context, CalendarAgendaUiCopy.dragTaskSavingBusy);
        return;
      }
      final reminderIssue = waitForReminderSync
          ? saveResult.reminderSync?.issue
          : null;
      if (reminderIssue != null) {
        _showDragFailure(
          context,
          CalendarAgendaUiCopy.dragReminderWarning(
            I18nDateFormat.time(next),
            reminderIssue,
          ),
        );
        return;
      }
      _showDragResult(context, next);
    } catch (e) {
      if (!context.mounted) return;
      _showDragFailure(context, CalendarAgendaUiCopy.dragTaskSaveFailed(e));
    }
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
        content: Text(
          CalendarAgendaUiCopy.dragAdjustSuccess(I18nDateFormat.time(value)),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showDragFailure(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  bool _todoNeedsReminderSync(TodoItem todo) {
    return todo.hasReminder ||
        todo.reminder.enabled ||
        todo.reminderPlan.enabled;
  }
}

TodoVisualState _eventVisualState(CalendarEvent event) {
  if (event.type != CalendarEventType.todo) return TodoVisualState.normal;
  if (event.isCompleted) return TodoVisualState.completed;
  final dueAt = event.endDate;
  if (dueAt != null && dueAt.isBefore(DateTime.now())) {
    return TodoVisualState.overdue;
  }
  return TodoVisualState.normal;
}

class _CalendarTodoVisual {
  final IconData icon;
  final Color color;

  const _CalendarTodoVisual({required this.icon, required this.color});
}

_CalendarTodoVisual _calendarEventVisual(
  CalendarEvent event,
  Map<String, TodoItem> todoById,
) {
  if (event.type != CalendarEventType.todo || event.sourceId == null) {
    return _CalendarTodoVisual(
      icon: _fallbackEventIcon(event.type),
      color: event.color,
    );
  }
  final todo = todoById[event.sourceId];
  if (todo != null) return _calendarTodoVisual(todo);
  return _CalendarTodoVisual(
    icon: _fallbackEventIcon(event.type),
    color: event.color,
  );
}

_CalendarTodoVisual _calendarTodoVisual(TodoItem todo) {
  final target = todo.listGroupName?.trim();
  if (target != null && target.isNotEmpty) {
    for (final template in TodoListTemplates.all) {
      if (template.name == target) {
        return _CalendarTodoVisual(icon: template.icon, color: template.color);
      }
    }
  }
  return _CalendarTodoVisual(
    icon: switch (todo.quadrant) {
      EisenhowerQuadrant.urgentImportant => Icons.priority_high_outlined,
      EisenhowerQuadrant.notUrgentImportant => Icons.flag_outlined,
      EisenhowerQuadrant.urgentNotImportant => Icons.bolt_outlined,
      EisenhowerQuadrant.notUrgentNotImportant => Icons.checklist_rounded,
    },
    color: switch (todo.quadrant) {
      EisenhowerQuadrant.urgentImportant => DesignTokens.defaultError,
      EisenhowerQuadrant.notUrgentImportant => DesignTokens.todoDueSoon,
      EisenhowerQuadrant.urgentNotImportant => DesignTokens.defaultInfo,
      EisenhowerQuadrant.notUrgentNotImportant => DesignTokens.defaultTextMuted,
    },
  );
}

IconData _fallbackEventIcon(CalendarEventType t) {
  return switch (t) {
    CalendarEventType.event => Icons.event_note_outlined,
    CalendarEventType.todo => Icons.check_circle_outline,
    CalendarEventType.habit => Icons.repeat,
    CalendarEventType.pomodoro => Icons.timer,
    CalendarEventType.anniversary => Icons.celebration_outlined,
    CalendarEventType.course => Icons.class_outlined,
    CalendarEventType.diary => Icons.book_outlined,
    CalendarEventType.countdown => Icons.hourglass_bottom,
    CalendarEventType.goal => Icons.flag_circle_outlined,
    CalendarEventType.timeEntry => Icons.timelapse_outlined,
  };
}

Color _readableStateForeground(Color color, {bool isDark = false}) {
  var resolved = color;
  var iterations = 0;
  if (isDark) {
    while (resolved.computeLuminance() < 0.40 && iterations < 20) {
      resolved = Color.alphaBlend(Colors.white.withValues(alpha: 0.08), resolved);
      iterations++;
    }
  } else {
    while (resolved.computeLuminance() > 0.12 && iterations < 20) {
      resolved = Color.alphaBlend(Colors.black.withValues(alpha: 0.08), resolved);
      iterations++;
    }
  }
  return resolved;
}

class _CalendarAgendaStatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool useSurfaceForeground;

  const _CalendarAgendaStatusBadge({
    required this.label,
    required this.color,
    this.useSurfaceForeground = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24), width: 0.55),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: useSurfaceForeground
                ? Theme.of(context).colorScheme.onSurface
                : _readableStateForeground(color, isDark: isDark),
          ),
        ),
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
    return Semantics(
      button: true,
      child: AppSurfaceCard(
        padding: const EdgeInsets.all(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DiaryEditScreen(entry: entry, initialDate: date),
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 24),
          child: Row(
            children: [
              Icon(
                hasEntry ? Icons.book : Icons.edit_note,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasEntry
                      ? entry!.title
                      : CalendarAgendaUiCopy.emptyDiaryPrompt,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 13,
                    color: hasEntry ? cs.onSurface : cs.onSurfaceVariant,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              if (hasEntry && entry!.mood != null)
                Text(entry!.mood!.emoji, style: const TextStyle(fontSize: 16)),
              Icon(Icons.chevron_right, size: 16, color: cs.onSurfaceVariant),
            ],
          ),
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
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
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
                    fontWeight: FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
