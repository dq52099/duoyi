import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/almanac_locale_format.dart';
import '../../core/almanac_ui_copy.dart';
import '../../core/calendar_agenda_ui_copy.dart';
import '../../core/calendar_date_navigation.dart';
import '../../core/calendar_event_display_text.dart';
import '../../core/calendar_ui_copy.dart';
import '../../core/i18n.dart';
import '../../core/i18n_date_format.dart';
import '../../core/lunar_calendar.dart';
import '../../models/anniversary.dart';
import '../../models/calendar_event.dart';
import '../../models/countdown.dart';
import '../../models/course_schedule.dart';
import '../../models/diary_entry.dart';
import '../../models/goal.dart';
import '../../models/habit.dart';
import '../../models/pomodoro.dart';
import '../../models/time_entry.dart';
import '../../models/todo.dart';
import '../../providers/anniversary_provider.dart';
import '../../providers/calendar_provider.dart';
import '../../providers/countdown_provider.dart';
import '../../providers/course_provider.dart';
import '../../providers/diary_provider.dart';
import '../../providers/goal_provider.dart';
import '../../providers/habit_provider.dart';
import '../../providers/pomodoro_provider.dart';
import '../../providers/preferences_provider.dart';
import '../../providers/share_provider.dart';
import '../../providers/time_audit_provider.dart';
import '../../providers/todo_provider.dart';
import '../../screens/diary_screen.dart';
import '../../services/almanac_tools_service.dart';
import '../../services/holiday_calendar.dart';
import '../../widgets/app_date_picker.dart';
import '../../widgets/calendar_event_sheet.dart';
import '../desktop_web_nav.dart';
import '../desktop_web_tokens.dart';

enum _CalendarWorkspaceMode { month, week, day, year }

T? _maybeWatch<T extends Object>(BuildContext context) {
  try {
    return Provider.of<T>(context);
  } on ProviderNotFoundException {
    return null;
  }
}

T? _maybeRead<T extends Object>(BuildContext context) {
  try {
    return Provider.of<T>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
}

R _maybeSelect<T extends Object, R>(
  BuildContext context,
  R Function(T? provider) selector,
  R fallback,
) {
  try {
    return context.select<T?, R>(selector);
  } on ProviderNotFoundException {
    return fallback;
  }
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

bool _isSameCivilDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _weekdayName(int weekday, AppLocale locale) {
  if (locale == AppLocale.en) {
    return switch (weekday) {
      DateTime.monday => 'Mon',
      DateTime.tuesday => 'Tue',
      DateTime.wednesday => 'Wed',
      DateTime.thursday => 'Thu',
      DateTime.friday => 'Fri',
      DateTime.saturday => 'Sat',
      DateTime.sunday => 'Sun',
      _ => '',
    };
  }
  return switch (weekday) {
    DateTime.monday => '周一',
    DateTime.tuesday => '周二',
    DateTime.wednesday => '周三',
    DateTime.thursday => '周四',
    DateTime.friday => '周五',
    DateTime.saturday => '周六',
    DateTime.sunday => '周日',
    _ => '',
  };
}

String _formatEventTime(CalendarEvent event) {
  final t = event.time;
  if (t == null) return '';
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

IconData _eventTypeIcon(CalendarEventType type) => switch (type) {
  CalendarEventType.event => Icons.event_outlined,
  CalendarEventType.todo => Icons.check_circle_outline,
  CalendarEventType.habit => Icons.repeat_rounded,
  CalendarEventType.pomodoro => Icons.timer_outlined,
  CalendarEventType.anniversary => Icons.cake_outlined,
  CalendarEventType.course => Icons.school_outlined,
  CalendarEventType.diary => Icons.menu_book_outlined,
  CalendarEventType.countdown => Icons.hourglass_bottom_outlined,
  CalendarEventType.goal => Icons.flag_outlined,
  CalendarEventType.timeEntry => Icons.timelapse_outlined,
};

String _eventTypeLabel(CalendarEventType type, AppLocale locale) {
  final isEn = locale == AppLocale.en;
  return switch (type) {
    CalendarEventType.event => isEn ? 'Events' : '日程',
    CalendarEventType.todo => isEn ? 'Tasks' : '待办',
    CalendarEventType.habit => isEn ? 'Habits' : '习惯',
    CalendarEventType.pomodoro => isEn ? 'Focus' : '专注',
    CalendarEventType.anniversary => isEn ? 'Milestones' : '纪念日',
    CalendarEventType.course => isEn ? 'Courses' : '课程',
    CalendarEventType.diary => isEn ? 'Diary' : '日记',
    CalendarEventType.countdown => isEn ? 'Countdowns' : '倒数日',
    CalendarEventType.goal => isEn ? 'Goals' : '目标',
    CalendarEventType.timeEntry => isEn ? 'Time Log' : '时间足迹',
  };
}

/// Refactored Desktop Web Calendar Workspace with a single 48px toolbar,
/// full-height calendar canvas (Month / Week / Day / Year), and 340px Day
/// Inspector with lunar/almanac info, inline quick diary, and chronological agenda.
class DesktopCalendarView extends StatefulWidget {
  final DesktopWebNavController? controller;
  final DateTime? initialDate;
  final void Function(DesktopWebDestination destination)? onNavigate;
  final void Function(String todoId)? onOpenTodo;

  const DesktopCalendarView({
    super.key,
    this.controller,
    this.initialDate,
    this.onNavigate,
    this.onOpenTodo,
  });

  @override
  State<DesktopCalendarView> createState() => _DesktopCalendarViewState();
}

class _DesktopCalendarViewState extends State<DesktopCalendarView> {
  static const double _hourRowHeight = 52.0;

  late DateTime _selectedDate;
  late DateTime _focusedMonth;
  _CalendarWorkspaceMode _mode = _CalendarWorkspaceMode.month;
  final Set<CalendarEventType> _activeTypes = Set<CalendarEventType>.from(
    CalendarEventType.values,
  );
  bool _showInspector = true;
  bool _showQuickTodoInput = false;

  DesktopWebNavController? _attachedController;
  DateTime? _lastSyncedControllerDate;
  String? _lastRebuildSignature;
  bool _rebuildScheduled = false;
  String? _lastTopBarSignature;
  CalendarProvider? _observedCalendar;
  int _calendarEventsRevision = 0;
  _YearOverviewCache? _yearOverviewCache;

  final ScrollController _timelineScrollCtrl = ScrollController(
    initialScrollOffset: 7.5 * _hourRowHeight,
  );
  final ScrollController _inspectorScrollCtrl = ScrollController();
  final TextEditingController _diaryCtrl = TextEditingController();
  final FocusNode _diaryFocus = FocusNode();
  final TextEditingController _quickTodoCtrl = TextEditingController();
  final FocusNode _quickTodoFocus = FocusNode();

  Mood? _draftMood;
  DateTime? _diaryBoundDate;
  String _diarySavedSnapshot = '';
  bool _diaryDirty = false;
  bool _savingDiary = false;

  @override
  void initState() {
    super.initState();
    final seed = _dateOnly(widget.initialDate ?? DateTime.now());
    _selectedDate = seed;
    _focusedMonth = DateTime(seed.year, seed.month);
    _diaryCtrl.addListener(_onDiaryTextChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextController = widget.controller ?? DesktopWebScope.maybeOf(context);
    if (!identical(_attachedController, nextController)) {
      _attachedController?.removeListener(_onNavControllerChanged);
      _attachedController = nextController;
      _attachedController?.addListener(_onNavControllerChanged);
      _syncFromController(nextController?.focusedCalendarDate);
    }
  }

  @override
  void didUpdateWidget(covariant DesktopCalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final seed = widget.initialDate;
    if (seed != null &&
        (oldWidget.initialDate == null ||
            !_isSameCivilDay(oldWidget.initialDate!, seed))) {
      _selectDay(_dateOnly(seed));
    }
    if (!identical(oldWidget.controller, widget.controller)) {
      final resolved = widget.controller ?? DesktopWebScope.maybeOf(context);
      if (!identical(_attachedController, resolved)) {
        _attachedController?.removeListener(_onNavControllerChanged);
        _attachedController = resolved;
        _attachedController?.addListener(_onNavControllerChanged);
        _syncFromController(resolved?.focusedCalendarDate);
      }
    }
  }

  @override
  void dispose() {
    _observedCalendar?.removeListener(_onCalendarProviderChanged);
    _observedCalendar = null;
    _attachedController?.removeListener(_onNavControllerChanged);
    _diaryCtrl.removeListener(_onDiaryTextChanged);
    _diaryCtrl.dispose();
    _diaryFocus.dispose();
    _quickTodoCtrl.dispose();
    _quickTodoFocus.dispose();
    _timelineScrollCtrl.dispose();
    _inspectorScrollCtrl.dispose();
    super.dispose();
  }

  void _onCalendarProviderChanged() {
    _calendarEventsRevision++;
    _yearOverviewCache = null;
  }

  void _observeCalendarProvider(CalendarProvider? calendar) {
    if (identical(_observedCalendar, calendar)) return;
    _observedCalendar?.removeListener(_onCalendarProviderChanged);
    _observedCalendar = calendar;
    _observedCalendar?.addListener(_onCalendarProviderChanged);
    _calendarEventsRevision++;
    _yearOverviewCache = null;
  }

  void _onNavControllerChanged() {
    _syncFromController(_attachedController?.focusedCalendarDate);
  }

  void _syncFromController(DateTime? target) {
    if (target == null) return;
    final clean = _dateOnly(target);
    if (_lastSyncedControllerDate != null &&
        _isSameCivilDay(_lastSyncedControllerDate!, clean)) {
      return;
    }
    _lastSyncedControllerDate = clean;
    if (!mounted) return;
    setState(() {
      _selectedDate = clean;
      _focusedMonth = DateTime(clean.year, clean.month);
    });
  }

  void _onDiaryTextChanged() {
    final dirty = _diaryCtrl.text != _diarySavedSnapshot;
    if (dirty != _diaryDirty && mounted) {
      setState(() => _diaryDirty = dirty);
    }
  }

  void _syncDiaryDraftIfNeeded(DiaryProvider? diaries) {
    final entry = diaries?.entryForDate(_selectedDate);
    final serverContent = entry?.content ?? '';
    final dateChanged =
        _diaryBoundDate == null ||
        !_isSameCivilDay(_diaryBoundDate!, _selectedDate);

    if (dateChanged) {
      _diaryBoundDate = _selectedDate;
      _diarySavedSnapshot = serverContent;
      _draftMood = entry?.mood;
      _diaryDirty = false;
      if (_diaryCtrl.text != serverContent) {
        _diaryCtrl.text = serverContent;
      }
      return;
    }

    if (!_diaryFocus.hasFocus && !_diaryDirty) {
      if (_diarySavedSnapshot != serverContent) {
        _diarySavedSnapshot = serverContent;
        _diaryCtrl.text = serverContent;
      }
      if (_draftMood != entry?.mood) {
        _draftMood = entry?.mood;
      }
    }
  }

  void _selectDay(DateTime day) {
    final normalized = _dateOnly(day);
    setState(() {
      _selectedDate = normalized;
      _focusedMonth = DateTime(normalized.year, normalized.month);
    });
    _lastSyncedControllerDate = normalized;
    _attachedController?.focusCalendarDate(normalized);
  }

  void _jumpToday() {
    _selectDay(DateTime.now());
  }

  void _stepPeriod(int delta) {
    DateTime? target;
    switch (_mode) {
      case _CalendarWorkspaceMode.month:
        target = CalendarDateNavigation.tryShiftMonths(_focusedMonth, delta);
        if (target != null) {
          final daysInTarget = DateTime(target.year, target.month + 1, 0).day;
          final day = _selectedDate.day.clamp(1, daysInTarget);
          setState(() {
            _focusedMonth = DateTime(target!.year, target.month);
            _selectedDate = DateTime(target.year, target.month, day);
          });
          _lastSyncedControllerDate = _selectedDate;
          _attachedController?.focusCalendarDate(_selectedDate);
        }
      case _CalendarWorkspaceMode.week:
        target = CalendarDateNavigation.tryShiftDays(_selectedDate, delta * 7);
        if (target != null) _selectDay(target);
      case _CalendarWorkspaceMode.day:
        target = CalendarDateNavigation.tryShiftDays(_selectedDate, delta);
        if (target != null) _selectDay(target);
      case _CalendarWorkspaceMode.year:
        target = CalendarDateNavigation.tryShiftYears(_selectedDate, delta);
        if (target != null) _selectDay(target);
    }
  }

  Future<void> _pickToolbarDate() async {
    final picked = await AppDatePicker.pickSolar(
      context,
      initialDate: _selectedDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2099, 12, 31),
      titleKey: 'picker.date.title',
    );
    if (picked == null || !mounted) return;
    _selectDay(picked);
  }

  void _scheduleCalendarRebuildIfNeeded({
    required CalendarProvider? calendar,
    required TodoProvider? todos,
    required HabitProvider? habits,
    required PomodoroProvider? pomodoros,
    required int pomodoroPersistedRev,
    required AnniversaryProvider? anniversaries,
    required CourseProvider? courses,
    required DiaryProvider? diaries,
    required CountdownProvider? countdowns,
    required GoalProvider? goals,
    required TimeAuditProvider? timeAudit,
    required ColorScheme colorScheme,
  }) {
    if (calendar == null) return;
    final todoList = todos?.todos ?? const <TodoItem>[];
    final habitList = habits?.habits ?? const <Habit>[];
    final sessionList = pomodoros?.sessions ?? const <PomodoroSession>[];
    final anniversaryList = anniversaries?.items ?? const <Anniversary>[];
    final courseList = courses?.courses ?? const <CourseItem>[];
    final courseSettings = courses?.settings ?? ScheduleSettings();
    final diaryList = diaries?.entries ?? const <DiaryEntry>[];
    final countdownList = countdowns?.items ?? const <CountdownItem>[];
    final goalList = goals?.goals ?? const <GoalItem>[];
    final timeEntryList = timeAudit?.entries ?? const <TimeEntry>[];

    final habitSignature = Object.hashAll(
      habitList.map(
        (h) => Object.hash(h.id, h.name, h.completions.length, h.updatedAt),
      ),
    );

    final signature = [
      todos?.revision ?? todoList.length,
      habitList.length,
      habitSignature,
      pomodoroPersistedRev >= 0 ? pomodoroPersistedRev : sessionList.length,
      anniversaryList.length,
      Object.hashAll(anniversaryList.map((a) => a.updatedAt)),
      courseList.length,
      courseSettings.termStart.toIso8601String(),
      courseSettings.totalWeeks,
      diaryList.length,
      Object.hashAll(diaryList.map((d) => d.updatedAt)),
      countdownList.length,
      Object.hashAll(countdownList.map((c) => c.updatedAt)),
      goalList.length,
      Object.hashAll(goalList.map((g) => g.updatedAt)),
      timeEntryList.length,
      Object.hashAll(timeEntryList.map((t) => t.updatedAt)),
      calendar.localEvents.length,
      Object.hashAll(calendar.localEvents.map((e) => e.updatedAt ?? e.date)),
      colorScheme.brightness.index,
      colorScheme.primary.toARGB32(),
    ].join('|');

    if (signature == _lastRebuildSignature || _rebuildScheduled) return;
    _rebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildScheduled = false;
      if (!mounted) return;
      _lastRebuildSignature = signature;
      calendar.rebuild(
        todoList,
        habitList,
        sessionList,
        Theme.of(context).colorScheme,
        anniversaries: anniversaryList,
        courses: courseList,
        courseSettings: courseSettings,
        diaries: diaryList,
        countdowns: countdownList,
        goals: goalList,
        timeEntries: timeEntryList,
      );
    });
  }

  void _publishTopBarSpec(AppLocale locale, int dayEventCount) {
    final controller = _attachedController;
    if (controller == null) return;
    final isEn = locale == AppLocale.en;
    final dateText = _formatDateSummary(_selectedDate, locale);
    final subtitle = isEn
        ? '$dateText · $dayEventCount items'
        : '$dateText · $dayEventCount 项安排';
    final sig = '${locale.name}|$subtitle';
    if (sig == _lastTopBarSignature) return;
    _lastTopBarSignature = sig;
    controller.setTopBarSpec(
      DesktopWebDestination.calendar,
      DesktopTopBarSpec(
        title: isEn ? 'Calendar' : '日历',
        subtitle: subtitle,
        showQuickSearch: true,
        showQuickCreate: true,
      ),
    );
  }

  String _toolbarPeriodTitle(AppLocale locale) {
    final isEn = locale == AppLocale.en;
    return switch (_mode) {
      _CalendarWorkspaceMode.month =>
        isEn
            ? I18nDateFormat.yearMonth(_focusedMonth)
            : '${_focusedMonth.year}年${_focusedMonth.month}月',
      _CalendarWorkspaceMode.week => _weekRangeTitle(_selectedDate, locale),
      _CalendarWorkspaceMode.day =>
        isEn
            ? '${I18nDateFormat.monthDay(_selectedDate)}, ${_selectedDate.year}'
            : '${_selectedDate.year}年${_selectedDate.month}月${_selectedDate.day}日',
      _CalendarWorkspaceMode.year =>
        isEn ? '${_selectedDate.year}' : '${_selectedDate.year}年',
    };
  }

  String _weekRangeTitle(DateTime anchor, AppLocale locale) {
    final prefs = _maybeRead<PreferencesProvider>(context);
    final firstDay = CalendarDateNavigation.normalizeFirstDayOfWeek(
      prefs?.firstDayOfWeek ?? DateTime.monday,
    );
    final days = CalendarDateNavigation.weekDays(
      anchor,
      firstDayOfWeek: firstDay,
    );
    final valid = days.whereType<DateTime>().toList(growable: false);
    if (valid.isEmpty) return _formatDateSummary(anchor, locale);
    final start = valid.first;
    final end = valid.last;
    if (locale == AppLocale.en) {
      if (start.month == end.month) {
        return '${I18nDateFormat.yearMonth(start)} ${start.day}–${end.day}';
      }
      return '${I18nDateFormat.monthDay(start)} – ${I18nDateFormat.monthDay(end)}';
    }
    if (start.year == end.year && start.month == end.month) {
      return '${start.year}年${start.month}月 ${start.day}–${end.day}日';
    }
    return '${start.month}月${start.day}日 – ${end.month}月${end.day}日';
  }

  String _formatDateSummary(DateTime date, AppLocale locale) {
    final wd = _weekdayName(date.weekday, locale);
    if (locale == AppLocale.en) {
      return '$wd, ${I18nDateFormat.monthDay(date)}, ${date.year}';
    }
    return '${date.month}月${date.day}日 · $wd';
  }

  String? _cellLunarBadge(DateTime day, AppLocale locale, bool showLunar) {
    if (!showLunar || !LunarCalendar.isWithinDocumentedSolarRange(day)) {
      return null;
    }
    final lunar = LunarCalendar.tryFromSolar(day);
    if (lunar == null) return null;
    final term = LunarCalendar.solarTerm(day);
    final sFest = LunarCalendar.solarFestival(day);
    final lFest = LunarCalendar.lunarFestival(lunar);

    if (sFest != null) {
      return AlmanacLocaleFormat.formatFestival(sFest, locale) ?? sFest;
    }
    if (lFest != null) {
      return AlmanacLocaleFormat.formatFestival(lFest, locale) ?? lFest;
    }
    if (term != null) {
      return AlmanacLocaleFormat.formatSolarTerm(term, locale) ?? term;
    }
    return AlmanacLocaleFormat.formatLunarDay(lunar, locale);
  }

  bool _isHighlightedLunarTag(DateTime day) {
    if (!LunarCalendar.isWithinDocumentedSolarRange(day)) return false;
    final lunar = LunarCalendar.tryFromSolar(day);
    if (lunar == null) return false;
    return LunarCalendar.solarTerm(day) != null ||
        LunarCalendar.solarFestival(day) != null ||
        LunarCalendar.lunarFestival(lunar) != null;
  }

  Future<void> _saveInlineDiary({Mood? overrideMood}) async {
    final diaries = _maybeRead<DiaryProvider>(context);
    if (diaries == null || _savingDiary) return;
    final nextMood = overrideMood ?? _draftMood;
    final content = _diaryCtrl.text.trim();
    final existing = diaries.entryForDate(_selectedDate);
    if (existing == null && content.isEmpty && nextMood == null) {
      return;
    }
    setState(() => _savingDiary = true);
    try {
      final next = DiaryEntry(
        id: existing?.id,
        date: _selectedDate,
        content: _diaryCtrl.text.trimRight(),
        mood: nextMood,
        weather: existing?.weather,
        tags: existing?.tags,
        imagePaths: existing?.imagePaths,
        location: existing?.location,
        createdAt: existing?.createdAt,
        updatedAt: DateTime.now(),
      );
      await diaries.addOrUpdate(next);
      if (!mounted) return;
      setState(() {
        _draftMood = nextMood;
        _diarySavedSnapshot = next.content;
        _diaryDirty = false;
      });
    } finally {
      if (mounted) {
        setState(() => _savingDiary = false);
      }
    }
  }

  Future<void> _submitQuickTodo() async {
    final title = _quickTodoCtrl.text.trim();
    if (title.isEmpty) return;
    final todoProvider = _maybeRead<TodoProvider>(context);
    if (todoProvider == null) return;
    await todoProvider.addTodo(
      TodoItem(
        title: title,
        date: _selectedDate,
        workspaceId: 'private',
      ),
      waitForReminderSync: false,
    );
    if (!mounted) return;
    _quickTodoCtrl.clear();
    setState(() => _showQuickTodoInput = false);
  }

  Future<void> _createEvent({DateTime? date}) async {
    final calendar = _maybeRead<CalendarProvider>(context);
    if (calendar == null) return;
    await showLocalCalendarEventEditor(
      context,
      initialDate: date ?? _selectedDate,
    );
  }

  Future<void> _openEventSheet(CalendarEvent event) async {
    await showCalendarEventSheet(context, event);
  }

  void _openFullAlmanac() {
    final nav = _attachedController;
    if (nav != null) {
      nav.navigateTo(
        DesktopWebDestination.almanac,
        focusedDate: _selectedDate,
        almanacTab: 0,
      );
      return;
    }
    widget.onNavigate?.call(DesktopWebDestination.almanac);
  }

  Future<void> _showTermExplanationDialog(
    String rawTerm, {
    required bool isSuitable,
    required AppLocale locale,
    required DesktopWebTokens tokens,
  }) async {
    final isEn = locale == AppLocale.en;
    final info = AlmanacToolsService.explainAlmanacTerm(rawTerm, english: isEn);
    final accentColor = isSuitable ? tokens.success : tokens.warning;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: tokens.elevatedSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesktopWebTokens.radiusLg),
          side: BorderSide(
            color: tokens.hairlineBorder,
            width: DesktopWebTokens.hairlineWidth,
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXs),
              ),
              child: Text(
                isSuitable
                    ? AlmanacUiCopy.auspiciousLabel
                    : AlmanacUiCopy.inauspiciousLabel,
                style: tokens.captionStyle.copyWith(color: accentColor),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                info.localizedTitle(locale),
                style: tokens.cardTitleStyle,
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: tokens.mutedSurface,
                  borderRadius: BorderRadius.circular(
                    DesktopWebTokens.radiusPill,
                  ),
                ),
                child: Text(info.category, style: tokens.captionStyle),
              ),
              const SizedBox(height: 10),
              Text(
                AlmanacUiCopy.plainExplanationTitle,
                style: tokens.captionStyle.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: 4),
              Text(
                info.localizedExplanation(locale),
                style: tokens.bodyStyle,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(AlmanacUiCopy.dialogConfirm(locale: locale)),
          ),
        ],
      ),
    );
  }

  void _openTodoDetailOrSheet(CalendarEvent event) {
    final sourceId = event.sourceId;
    if (sourceId != null &&
        sourceId.isNotEmpty &&
        widget.onOpenTodo != null) {
      widget.onOpenTodo!(sourceId);
      return;
    }
    final nav = _attachedController;
    if (sourceId != null && sourceId.isNotEmpty && nav != null) {
      nav.navigateTo(DesktopWebDestination.todo, selectedTodoId: sourceId);
      return;
    }
    _openEventSheet(event);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final tokens = DesktopWebTokens.of(context);
        final calendar = _maybeWatch<CalendarProvider>(context);
        _observeCalendarProvider(calendar);
        final todos = _maybeWatch<TodoProvider>(context);
        final habits = _maybeWatch<HabitProvider>(context);
        final diaries = _maybeWatch<DiaryProvider>(context);
        final pomodoroPersistedRev = _maybeSelect<PomodoroProvider, int>(
          context,
          (p) => p?.persistedRevision ?? -1,
          -1,
        );
        final pomodoros = _maybeRead<PomodoroProvider>(context);
        final anniversaries = _maybeWatch<AnniversaryProvider>(context);
        final courses = _maybeWatch<CourseProvider>(context);
        final countdowns = _maybeWatch<CountdownProvider>(context);
        final goals = _maybeWatch<GoalProvider>(context);
        final timeAudit = _maybeWatch<TimeAuditProvider>(context);
        final (rawFirstDayOfWeek, showLunar) =
            _maybeSelect<PreferencesProvider, (int, bool)>(
              context,
              (p) => (p?.firstDayOfWeek ?? DateTime.monday, p?.showLunar ?? true),
              (DateTime.monday, true),
            );
        _maybeSelect<ShareProvider, int>(
          context,
          (p) => p == null
              ? -1
              : Object.hashAll(
                  p.workspaces.map(
                    (w) => Object.hash(w.id, p.roleFor(w.id), w.members.length),
                  ),
                ),
          -1,
        );

        _scheduleCalendarRebuildIfNeeded(
          calendar: calendar,
          todos: todos,
          habits: habits,
          pomodoros: pomodoros,
          pomodoroPersistedRev: pomodoroPersistedRev,
          anniversaries: anniversaries,
          courses: courses,
          diaries: diaries,
          countdowns: countdowns,
          goals: goals,
          timeAudit: timeAudit,
          colorScheme: Theme.of(context).colorScheme,
        );

        _syncDiaryDraftIfNeeded(diaries);

        final firstDayOfWeek = CalendarDateNavigation.normalizeFirstDayOfWeek(
          rawFirstDayOfWeek,
        );
        final selectedDayEvents =
            calendar?.getEventsForDate(
              _selectedDate,
              activeTypes: _activeTypes,
            ) ??
            const <CalendarEvent>[];

        _publishTopBarSpec(locale, selectedDayEvents.length);

        return Column(
          children: [
            _buildToolbar(
              context: context,
              tokens: tokens,
              locale: locale,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final canShowSideBySide =
                      constraints.maxWidth >= 880 && _showInspector;
                  if (constraints.maxWidth < 880 && _showInspector) {
                    return Column(
                      children: [
                        Expanded(
                          flex: 6,
                          child: _buildMainCalendarCanvas(
                            tokens: tokens,
                            locale: locale,
                            calendar: calendar,
                            firstDayOfWeek: firstDayOfWeek,
                            showLunar: showLunar,
                          ),
                        ),
                        Divider(
                          height: DesktopWebTokens.hairlineWidth,
                          thickness: DesktopWebTokens.hairlineWidth,
                          color: tokens.hairlineBorder,
                        ),
                        Expanded(
                          flex: 5,
                          child: _buildDayInspector(
                            tokens: tokens,
                            locale: locale,
                            showLunar: showLunar,
                            events: selectedDayEvents,
                            todos: todos,
                            habits: habits,
                            diaries: diaries,
                          ),
                        ),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _buildMainCalendarCanvas(
                          tokens: tokens,
                          locale: locale,
                          calendar: calendar,
                          firstDayOfWeek: firstDayOfWeek,
                          showLunar: showLunar,
                        ),
                      ),
                      if (canShowSideBySide) ...[
                        VerticalDivider(
                          width: DesktopWebTokens.hairlineWidth,
                          thickness: DesktopWebTokens.hairlineWidth,
                          color: tokens.hairlineBorder,
                        ),
                        SizedBox(
                          width: DesktopWebTokens.calendarInspectorWidth,
                          child: _buildDayInspector(
                            tokens: tokens,
                            locale: locale,
                            showLunar: showLunar,
                            events: selectedDayEvents,
                            todos: todos,
                            habits: habits,
                            diaries: diaries,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildToolbar({
    required BuildContext context,
    required DesktopWebTokens tokens,
    required AppLocale locale,
  }) {
    final isEn = locale == AppLocale.en;
    final activeCount = _activeTypes.length;
    final totalCount = CalendarEventType.values.length;
    final filtered = activeCount < totalCount;
    final filterLabel = filtered
        ? (isEn ? 'Filter ($activeCount)' : '筛选 ($activeCount)')
        : (isEn ? 'Filter' : '筛选');

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: tokens.topbarBackground,
        border: Border(
          bottom: BorderSide(
            color: tokens.hairlineBorder,
            width: DesktopWebTokens.hairlineWidth,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 780;
          final leftControls = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: _pickToolbarDate,
                borderRadius: BorderRadius.circular(
                  DesktopWebTokens.radiusSm,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _toolbarPeriodTitle(locale),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens.pageTitleStyle.copyWith(
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: tokens.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                height: 28,
                decoration: BoxDecoration(
                  color: tokens.mutedSurface,
                  borderRadius: BorderRadius.circular(
                    DesktopWebTokens.radiusSm,
                  ),
                  border: Border.all(
                    color: tokens.hairlineBorder,
                    width: DesktopWebTokens.hairlineWidth,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ToolbarIconBtn(
                      icon: Icons.chevron_left_rounded,
                      tooltip: isEn ? 'Previous' : '上一个',
                      tokens: tokens,
                      onTap: () => _stepPeriod(-1),
                    ),
                    Container(
                      width: DesktopWebTokens.hairlineWidth,
                      height: 16,
                      color: tokens.hairlineBorder,
                    ),
                    InkWell(
                      onTap: _jumpToday,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        child: Text(
                          isEn ? 'Today' : '今天',
                          style: tokens.captionStyle.copyWith(
                            color: _isSameCivilDay(
                                    _selectedDate,
                                    DateTime.now(),
                                  )
                                ? tokens.accent
                                : tokens.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: DesktopWebTokens.hairlineWidth,
                      height: 16,
                      color: tokens.hairlineBorder,
                    ),
                    _ToolbarIconBtn(
                      icon: Icons.chevron_right_rounded,
                      tooltip: isEn ? 'Next' : '下一个',
                      tokens: tokens,
                      onTap: () => _stepPeriod(1),
                    ),
                  ],
                ),
              ),
            ],
          );

          final centerModeSwitcher = Container(
            height: 30,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: tokens.mutedSurface,
              borderRadius: BorderRadius.circular(
                DesktopWebTokens.radiusSm,
              ),
              border: Border.all(
                color: tokens.hairlineBorder,
                width: DesktopWebTokens.hairlineWidth,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in _CalendarWorkspaceMode.values)
                  _ModeSegmentButton(
                    label: switch (m) {
                      _CalendarWorkspaceMode.month => isEn ? 'Month' : '月',
                      _CalendarWorkspaceMode.week => isEn ? 'Week' : '周',
                      _CalendarWorkspaceMode.day => isEn ? 'Day' : '日',
                      _CalendarWorkspaceMode.year => isEn ? 'Year' : '年',
                    },
                    selected: _mode == m,
                    tokens: tokens,
                    onTap: () => setState(() => _mode = m),
                  ),
              ],
            ),
          );

          final rightControls = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Right: Compact category filter popover + Inspector toggle + Primary + New Event
              MenuAnchor(
                builder: (context, menuController, child) {
                  return InkWell(
                    onTap: () {
                      if (menuController.isOpen) {
                        menuController.close();
                      } else {
                        menuController.open();
                      }
                    },
                    borderRadius: BorderRadius.circular(
                      DesktopWebTokens.radiusSm,
                    ),
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: filtered
                            ? tokens.accentSoft
                            : tokens.mutedSurface,
                        borderRadius: BorderRadius.circular(
                          DesktopWebTokens.radiusSm,
                        ),
                        border: Border.all(
                          color: filtered
                              ? tokens.accentBorder
                              : tokens.hairlineBorder,
                          width: DesktopWebTokens.hairlineWidth,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.filter_list_rounded,
                            size: 15,
                            color: filtered
                                ? tokens.accent
                                : tokens.textSecondary,
                          ),
                          if (!compact) ...[
                            const SizedBox(width: 5),
                            Text(
                              filterLabel,
                              style: tokens.captionStyle.copyWith(
                                color: filtered
                                    ? tokens.accent
                                    : tokens.textPrimary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
                menuChildren: [
                  StatefulBuilder(
                    builder: (menuCtx, menuSetState) => Padding(
                      padding: const EdgeInsets.all(10),
                      child: SizedBox(
                        width: 240,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  isEn ? 'Calendar Categories' : '日程分类筛选',
                                  style: tokens.cardTitleStyle.copyWith(
                                    fontSize: 13.5,
                                  ),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _activeTypes
                                        ..clear()
                                        ..addAll(CalendarEventType.values);
                                    });
                                    menuSetState(() {});
                                  },
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    CalendarUiCopy.filterAll,
                                    style: tokens.captionStyle.copyWith(
                                      color: tokens.accent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final type in CalendarEventType.values)
                                  FilterChip(
                                    selected: _activeTypes.contains(type),
                                    showCheckmark: false,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                    avatar: Icon(
                                      _eventTypeIcon(type),
                                      size: 14,
                                      color: _activeTypes.contains(type)
                                          ? tokens.accent
                                          : tokens.textMuted,
                                    ),
                                    label: Text(
                                      _eventTypeLabel(type, locale),
                                      style: tokens.captionStyle.copyWith(
                                        color: _activeTypes.contains(type)
                                            ? tokens.accent
                                            : tokens.textSecondary,
                                      ),
                                    ),
                                    onSelected: (checked) {
                                      setState(() {
                                        if (checked) {
                                          _activeTypes.add(type);
                                        } else if (_activeTypes.length > 1) {
                                          _activeTypes.remove(type);
                                        }
                                      });
                                      menuSetState(() {});
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: isEn ? 'Toggle Day Inspector' : '展开/收起右侧日详情',
                child: InkWell(
                  onTap: () => setState(() => _showInspector = !_showInspector),
                  borderRadius: BorderRadius.circular(
                    DesktopWebTokens.radiusSm,
                  ),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: _showInspector
                          ? tokens.selectedSurface
                          : tokens.mutedSurface,
                      borderRadius: BorderRadius.circular(
                        DesktopWebTokens.radiusSm,
                      ),
                      border: Border.all(
                        color: _showInspector
                            ? tokens.accentBorder
                            : tokens.hairlineBorder,
                        width: DesktopWebTokens.hairlineWidth,
                      ),
                    ),
                    child: Icon(
                      Icons.view_sidebar_outlined,
                      size: 15,
                      color: _showInspector
                          ? tokens.accent
                          : tokens.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          );

          return Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: leftControls,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              centerModeSwitcher,
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: rightControls,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMainCalendarCanvas({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required CalendarProvider? calendar,
    required int firstDayOfWeek,
    required bool showLunar,
  }) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: switch (_mode) {
        _CalendarWorkspaceMode.month => _buildMonthGrid(
          tokens: tokens,
          locale: locale,
          calendar: calendar,
          firstDayOfWeek: firstDayOfWeek,
          showLunar: showLunar,
        ),
        _CalendarWorkspaceMode.week => _buildWeekGrid(
          tokens: tokens,
          locale: locale,
          calendar: calendar,
          firstDayOfWeek: firstDayOfWeek,
        ),
        _CalendarWorkspaceMode.day => _buildDayTimeline(
          tokens: tokens,
          locale: locale,
          calendar: calendar,
          showLunar: showLunar,
        ),
        _CalendarWorkspaceMode.year => _buildYearOverview(
          tokens: tokens,
          locale: locale,
          calendar: calendar,
          firstDayOfWeek: firstDayOfWeek,
        ),
      },
    );
  }

  Widget _buildMonthGrid({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required CalendarProvider? calendar,
    required int firstDayOfWeek,
    required bool showLunar,
  }) {
    final weekdays = CalendarDateNavigation.orderedWeekdays(firstDayOfWeek);
    final monthStart = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final offset = (monthStart.weekday - firstDayOfWeek) % 7;
    final gridStart = CalendarDateNavigation.tryShiftDays(monthStart, -offset);
    final days = gridStart == null
        ? List<DateTime?>.filled(42, null)
        : List<DateTime?>.generate(
            42,
            (index) => CalendarDateNavigation.tryShiftDays(gridStart, index),
          );
    final today = _dateOnly(DateTime.now());

    return Container(
      decoration: BoxDecoration(
        color: tokens.panelSurface,
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusLg),
        border: Border.all(
          color: tokens.hairlineBorder,
          width: DesktopWebTokens.hairlineWidth,
        ),
        boxShadow: tokens.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusLg),
        child: Column(
          children: [
            Container(
              height: 34,
              decoration: BoxDecoration(
                color: tokens.mutedSurface,
                border: Border(
                  bottom: BorderSide(
                    color: tokens.hairlineBorder,
                    width: DesktopWebTokens.hairlineWidth,
                  ),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    child: Center(
                      child: Text(
                        locale == AppLocale.en ? 'Wk' : '周',
                        style: tokens.captionStyle.copyWith(
                          fontSize: 10.5,
                          color: tokens.textMuted,
                        ),
                      ),
                    ),
                  ),
                  for (var i = 0; i < weekdays.length; i++)
                    Expanded(
                      child: Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: tokens.hairlineBorder,
                              width: DesktopWebTokens.hairlineWidth,
                            ),
                          ),
                        ),
                        child: Text(
                          _weekdayName(weekdays[i], locale),
                          style: tokens.captionStyle.copyWith(
                            color:
                                (weekdays[i] == DateTime.saturday ||
                                    weekdays[i] == DateTime.sunday)
                                ? tokens.accent.withValues(alpha: 0.85)
                                : tokens.textSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  for (var week = 0; week < 6; week++)
                    Expanded(
                      child: Container(
                        decoration: week > 0
                            ? BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: tokens.hairlineBorder,
                                    width: DesktopWebTokens.hairlineWidth,
                                  ),
                                ),
                              )
                            : null,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Builder(
                              builder: (context) {
                                DateTime? anchorDay;
                                for (var c = 0; c < 7; c++) {
                                  final candidate = days[week * 7 + c];
                                  if (candidate != null) {
                                    anchorDay = candidate;
                                    break;
                                  }
                                }
                                final isoWeek = anchorDay == null
                                    ? null
                                    : LunarCalendar.isoWeekNumber(anchorDay);
                                return Container(
                                  width: 34,
                                  alignment: Alignment.topCenter,
                                  padding: const EdgeInsets.only(top: 7),
                                  color: tokens.mutedSurface,
                                  child: Text(
                                    isoWeek == null
                                        ? ''
                                        : 'W${isoWeek.toString().padLeft(2, '0')}',
                                    style: tokens.captionStyle.copyWith(
                                      fontSize: 10,
                                      color: tokens.textMuted,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            for (var col = 0; col < 7; col++)
                              Expanded(
                                child: _MonthDayCell(
                                  day: days[week * 7 + col],
                                  isFirstCol: false,
                                  isInCurrentMonth:
                                      days[week * 7 + col]?.month ==
                                          _focusedMonth.month &&
                                      days[week * 7 + col]?.year ==
                                          _focusedMonth.year,
                                  isToday:
                                      days[week * 7 + col] != null &&
                                      _isSameCivilDay(
                                        days[week * 7 + col]!,
                                        today,
                                      ),
                                  isSelected:
                                      days[week * 7 + col] != null &&
                                      _isSameCivilDay(
                                        days[week * 7 + col]!,
                                        _selectedDate,
                                      ),
                                  isHoliday:
                                      days[week * 7 + col] != null &&
                                      HolidayCalendar.isHoliday(
                                        days[week * 7 + col]!,
                                      ),
                                  isWorkMakeupDay:
                                      days[week * 7 + col] != null &&
                                      HolidayCalendar.isWorkMakeupDay(
                                        days[week * 7 + col]!,
                                      ),
                                  lunarTag: days[week * 7 + col] == null
                                      ? null
                                      : _cellLunarBadge(
                                          days[week * 7 + col]!,
                                          locale,
                                          showLunar,
                                        ),
                                  isLunarHighlighted:
                                      days[week * 7 + col] != null &&
                                      _isHighlightedLunarTag(
                                        days[week * 7 + col]!,
                                      ),
                                  events: days[week * 7 + col] == null
                                      ? const <CalendarEvent>[]
                                      : (calendar?.getEventsForDate(
                                              days[week * 7 + col]!,
                                              activeTypes: _activeTypes,
                                            ) ??
                                            const <CalendarEvent>[]),
                                  locale: locale,
                                  tokens: tokens,
                                  onSelectDay: (d) => _selectDay(d),
                                  onCreateForDay: (d) => _createEvent(date: d),
                                  onTapEvent: _openEventSheet,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekGrid({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required CalendarProvider? calendar,
    required int firstDayOfWeek,
  }) {
    final days = CalendarDateNavigation.weekDays(
      _selectedDate,
      firstDayOfWeek: firstDayOfWeek,
    );
    final today = _dateOnly(DateTime.now());
    final now = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: tokens.panelSurface,
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusLg),
        border: Border.all(
          color: tokens.hairlineBorder,
          width: DesktopWebTokens.hairlineWidth,
        ),
        boxShadow: tokens.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusLg),
        child: Column(
          children: [
            // Header + All-day strip
            Container(
              decoration: BoxDecoration(
                color: tokens.mutedSurface,
                border: Border(
                  bottom: BorderSide(
                    color: tokens.hairlineBorder,
                    width: DesktopWebTokens.hairlineWidth,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 44,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 54,
                          child: Center(
                            child: Text(
                              locale == AppLocale.en ? 'All' : '全天',
                              style: tokens.captionStyle,
                            ),
                          ),
                        ),
                        for (final day in days)
                          Expanded(
                            child: InkWell(
                              onTap: day == null ? null : () => _selectDay(day),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: day != null &&
                                          _isSameCivilDay(day, _selectedDate)
                                      ? tokens.accentSoft
                                      : null,
                                  border: Border(
                                    left: BorderSide(
                                      color: tokens.hairlineBorder,
                                      width: DesktopWebTokens.hairlineWidth,
                                    ),
                                  ),
                                ),
                                child: day == null
                                    ? const SizedBox.shrink()
                                    : FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                _weekdayName(
                                                  day.weekday,
                                                  locale,
                                                ),
                                                style: tokens.captionStyle
                                                    .copyWith(
                                                      color:
                                                          _isSameCivilDay(
                                                            day,
                                                            today,
                                                          )
                                                          ? tokens.accent
                                                          : tokens
                                                                .textSecondary,
                                                    ),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                width: 24,
                                                height: 24,
                                                alignment: Alignment.center,
                                                decoration:
                                                    _isSameCivilDay(day, today)
                                                    ? BoxDecoration(
                                                        color: tokens.accent,
                                                        shape: BoxShape.circle,
                                                      )
                                                    : null,
                                                child: Text(
                                                  '${day.day}',
                                                  style: tokens.bodyStyle
                                                      .copyWith(
                                                        fontSize: 13,
                                                        fontFeatures: const [
                                                          FontFeature
                                                              .tabularFigures(),
                                                        ],
                                                        color:
                                                            _isSameCivilDay(
                                                              day,
                                                              today,
                                                            )
                                                            ? tokens
                                                                  .accentForeground
                                                            : tokens
                                                                  .textPrimary,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 52,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 54,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: tokens.hairlineBorder,
                                  width: DesktopWebTokens.hairlineWidth,
                                ),
                              ),
                            ),
                          ),
                        ),
                        for (final day in days)
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: tokens.hairlineBorder,
                                    width: DesktopWebTokens.hairlineWidth,
                                  ),
                                  top: BorderSide(
                                    color: tokens.hairlineBorder,
                                    width: DesktopWebTokens.hairlineWidth,
                                  ),
                                ),
                              ),
                              child: day == null
                                  ? const SizedBox.shrink()
                                  : _AllDayMiniColumn(
                                      events:
                                          (calendar?.getEventsForDate(
                                                    day,
                                                    activeTypes: _activeTypes,
                                                  ) ??
                                                  const <CalendarEvent>[])
                                              .where((e) => e.time == null)
                                              .toList(growable: false),
                                      tokens: tokens,
                                      onTapEvent: _openEventSheet,
                                    ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 24-Hour Scrollable Grid
            Expanded(
              child: SingleChildScrollView(
                controller: _timelineScrollCtrl,
                child: SizedBox(
                  height: 24 * _hourRowHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Hour axis
                      SizedBox(
                        width: 54,
                        child: Column(
                          children: [
                            for (var h = 0; h < 24; h++)
                              SizedBox(
                                height: _hourRowHeight,
                                child: Align(
                                  alignment: Alignment.topRight,
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      right: 8,
                                      top: 2,
                                    ),
                                    child: Text(
                                      '${h.toString().padLeft(2, '0')}:00',
                                      style: tokens.captionStyle.copyWith(
                                        fontSize: 10.5,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      for (final day in days)
                        Expanded(
                          child: _HourlyEventColumn(
                            day: day,
                            isSelected:
                                day != null &&
                                _isSameCivilDay(day, _selectedDate),
                            isToday:
                                day != null && _isSameCivilDay(day, today),
                            now: now,
                            hourHeight: _hourRowHeight,
                            timedEvents: day == null
                                ? const <CalendarEvent>[]
                                : (calendar?.getEventsForDate(
                                            day,
                                            activeTypes: _activeTypes,
                                          ) ??
                                          const <CalendarEvent>[])
                                      .where((e) => e.time != null)
                                      .toList(growable: false),
                            tokens: tokens,
                            onSelectDay: (d) => _selectDay(d),
                            onTapEvent: _openEventSheet,
                            onDoubleTapEmpty: (d) => _createEvent(date: d),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayTimeline({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required CalendarProvider? calendar,
    required bool showLunar,
  }) {
    final dayEvents =
        calendar?.getEventsForDate(_selectedDate, activeTypes: _activeTypes) ??
        const <CalendarEvent>[];
    final allDayEvents = dayEvents
        .where((e) => e.time == null)
        .toList(growable: false);
    final timedEvents = dayEvents
        .where((e) => e.time != null)
        .toList(growable: false);
    final lunarText = _cellLunarBadge(_selectedDate, locale, showLunar);
    final today = _dateOnly(DateTime.now());
    final now = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: tokens.panelSurface,
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusLg),
        border: Border.all(
          color: tokens.hairlineBorder,
          width: DesktopWebTokens.hairlineWidth,
        ),
        boxShadow: tokens.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: tokens.mutedSurface,
                border: Border(
                  bottom: BorderSide(
                    color: tokens.hairlineBorder,
                    width: DesktopWebTokens.hairlineWidth,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              _formatDateSummary(_selectedDate, locale),
                              style: tokens.pageTitleStyle.copyWith(
                                fontSize: 16,
                              ),
                            ),
                            if (lunarText != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: tokens.accentSoft,
                                  borderRadius: BorderRadius.circular(
                                    DesktopWebTokens.radiusPill,
                                  ),
                                ),
                                child: Text(
                                  lunarText,
                                  style: tokens.captionStyle.copyWith(
                                    color: tokens.accent,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        locale == AppLocale.en
                            ? '${timedEvents.length} scheduled · ${allDayEvents.length} all-day'
                            : '${timedEvents.length} 项定时 · ${allDayEvents.length} 项全天',
                        style: tokens.captionStyle,
                      ),
                    ],
                  ),
                  if (allDayEvents.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final e in allDayEvents)
                          InkWell(
                            onTap: () => _openEventSheet(e),
                            borderRadius: BorderRadius.circular(
                              DesktopWebTokens.radiusXs,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: e.color.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(
                                  DesktopWebTokens.radiusXs,
                                ),
                                border: Border(
                                  left: BorderSide(color: e.color, width: 3),
                                ),
                              ),
                              child: Text(
                                CalendarEventDisplayText.resolveTitle(e),
                                style: tokens.captionStyle.copyWith(
                                  color: tokens.textPrimary,
                                  decoration: e.isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _timelineScrollCtrl,
                child: SizedBox(
                  height: 24 * _hourRowHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 62,
                        child: Column(
                          children: [
                            for (var h = 0; h < 24; h++)
                              SizedBox(
                                height: _hourRowHeight,
                                child: Align(
                                  alignment: Alignment.topRight,
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      right: 10,
                                      top: 2,
                                    ),
                                    child: Text(
                                      '${h.toString().padLeft(2, '0')}:00',
                                      style: tokens.captionStyle.copyWith(
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _HourlyEventColumn(
                          day: _selectedDate,
                          isSelected: false,
                          isToday: _isSameCivilDay(_selectedDate, today),
                          now: now,
                          hourHeight: _hourRowHeight,
                          timedEvents: timedEvents,
                          tokens: tokens,
                          showExtendedDetails: true,
                          onSelectDay: (_) {},
                          onTapEvent: _openEventSheet,
                          onDoubleTapEmpty: (d) => _createEvent(date: d),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _YearOverviewCache _yearOverviewDataFor({
    required int year,
    required int firstDayOfWeek,
    required AppLocale locale,
    required CalendarProvider? calendar,
  }) {
    var activeTypesMask = 0;
    for (final t in _activeTypes) {
      activeTypesMask |= 1 << t.index;
    }
    final calendarRevision = Object.hash(
      _calendarEventsRevision,
      calendar?.sourceRevision ?? 0,
      calendar?.events.length ?? 0,
    );
    final cached = _yearOverviewCache;
    if (cached != null &&
        identical(cached.calendar, calendar) &&
        cached.year == year &&
        cached.firstDayOfWeek == firstDayOfWeek &&
        cached.locale == locale &&
        cached.calendarRevision == calendarRevision &&
        cached.activeTypesMask == activeTypesMask) {
      return cached;
    }

    final dateCounts =
        calendar?.filteredDateEventCounts(_activeTypes) ?? const <String, int>{};
    final weekdays = CalendarDateNavigation.orderedWeekdays(firstDayOfWeek);
    final months = List<_YearMonthCache>.generate(12, (idx) {
      final month = idx + 1;
      final monthDate = DateTime(year, month, 1);
      final daysInMonth = DateTime(year, month + 1, 0).day;
      final leading = (monthDate.weekday - firstDayOfWeek) % 7;
      var monthEventCount = 0;
      final cells = List<_YearDayCellMeta?>.filled(42, null, growable: false);
      final monthPrefix = '$year-${month.toString().padLeft(2, '0')}-';

      for (var dayNum = 1; dayNum <= daysInMonth; dayNum++) {
        final d = DateTime(year, month, dayNum);
        final key = '$monthPrefix${dayNum.toString().padLeft(2, '0')}';
        final count = dateCounts[key] ?? 0;
        monthEventCount += count;
        final isHoliday = HolidayCalendar.isHoliday(d);
        final isMakeup = !isHoliday && HolidayCalendar.isWorkMakeupDay(d);
        final holidayTitle = isHoliday
            ? HolidayCalendar.holidayName(d, locale: locale)
            : (isMakeup ? AlmanacUiCopy.makeupWorkdayBadge : null);
        final tagText = isHoliday
            ? AlmanacUiCopy.holidayTag
            : (isMakeup ? AlmanacUiCopy.makeupWorkdayTag : null);
        final cellIndex = leading + dayNum - 1;
        if (cellIndex >= 0 && cellIndex < 42) {
          cells[cellIndex] = _YearDayCellMeta(
            dayNum: dayNum,
            date: d,
            count: count,
            isHoliday: isHoliday,
            isMakeup: isMakeup,
            holidayTitle: holidayTitle,
            tagText: tagText,
          );
        }
      }

      return _YearMonthCache(
        month: month,
        daysInMonth: daysInMonth,
        monthEventCount: monthEventCount,
        cells: cells,
      );
    }, growable: false);

    final built = _YearOverviewCache(
      calendar: calendar,
      year: year,
      firstDayOfWeek: firstDayOfWeek,
      locale: locale,
      calendarRevision: calendarRevision,
      activeTypesMask: activeTypesMask,
      weekdays: weekdays,
      months: months,
    );
    _yearOverviewCache = built;
    return built;
  }

  Widget _buildYearOverview({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required CalendarProvider? calendar,
    required int firstDayOfWeek,
  }) {
    final year = _selectedDate.year;
    final yearData = _yearOverviewDataFor(
      year: year,
      firstDayOfWeek: firstDayOfWeek,
      locale: locale,
      calendar: calendar,
    );
    final today = _dateOnly(DateTime.now());

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 820 ? 4 : 3;
        return GridView.builder(
          itemCount: 12,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.15,
          ),
          itemBuilder: (context, idx) {
            final monthMeta = yearData.months[idx];
            final month = monthMeta.month;
            final daysInMonth = monthMeta.daysInMonth;
            final monthEventCount = monthMeta.monthEventCount;
            final isFocusedMonth =
                _focusedMonth.year == year && _focusedMonth.month == month;

            return RepaintBoundary(
              child: DesktopPanelCard(
                padding: const EdgeInsets.all(10),
                border: Border.all(
                  color: isFocusedMonth
                      ? tokens.accentBorder
                      : tokens.hairlineBorder,
                  width: DesktopWebTokens.hairlineWidth,
                ),
                onTap: () {
                  setState(() {
                    _focusedMonth = DateTime(year, month);
                    _selectedDate = DateTime(
                      year,
                      month,
                      _selectedDate.day.clamp(1, daysInMonth),
                    );
                    _mode = _CalendarWorkspaceMode.month;
                  });
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            CalendarUiCopy.yearMonthTitle(month),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tokens.cardTitleStyle.copyWith(
                              fontSize: 13.5,
                              color: isFocusedMonth
                                  ? tokens.accent
                                  : tokens.textPrimary,
                            ),
                          ),
                        ),
                        if (monthEventCount > 0) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.accentSoft,
                              borderRadius: BorderRadius.circular(
                                DesktopWebTokens.radiusPill,
                              ),
                            ),
                            child: Text(
                              '$monthEventCount',
                              style: tokens.captionStyle.copyWith(
                                fontSize: 10.5,
                                color: tokens.accent,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (final wd in yearData.weekdays)
                          Expanded(
                            child: Center(
                              child: Text(
                                locale == AppLocale.en
                                    ? _weekdayName(wd, locale).substring(0, 1)
                                    : _weekdayName(wd, locale).substring(1),
                                style: tokens.captionStyle.copyWith(
                                  fontSize: 10,
                                  color: tokens.textMuted,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 42,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 7,
                              mainAxisSpacing: 1,
                              crossAxisSpacing: 1,
                            ),
                        itemBuilder: (context, cellIdx) {
                          final cell = monthMeta.cells[cellIdx];
                          if (cell == null) {
                            return const SizedBox.shrink();
                          }
                          final d = cell.date;
                          final isToday = _isSameCivilDay(d, today);
                          final isSelected = _isSameCivilDay(d, _selectedDate);
                          final isHoliday = cell.isHoliday;
                          final isMakeup = cell.isMakeup;
                          final count = cell.count;

                          Widget cellBody = Container(
                            decoration: BoxDecoration(
                              color: isToday
                                  ? tokens.accent
                                  : isSelected
                                  ? tokens.selectedSurface
                                  : isHoliday
                                  ? tokens.success.withValues(
                                      alpha: tokens.isDark ? 0.18 : 0.12,
                                    )
                                  : isMakeup
                                  ? tokens.warning.withValues(
                                      alpha: tokens.isDark ? 0.18 : 0.12,
                                    )
                                  : count > 0
                                  ? tokens.accent.withValues(
                                      alpha: (0.08 + count * 0.05).clamp(
                                        0.08,
                                        0.28,
                                      ),
                                    )
                                  : null,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Center(
                                  child: Text(
                                    '${cell.dayNum}',
                                    style: tokens.captionStyle.copyWith(
                                      fontSize: 10.5,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                      color: isToday
                                          ? tokens.accentForeground
                                          : isSelected
                                          ? tokens.accent
                                          : isHoliday
                                          ? tokens.success
                                          : isMakeup
                                          ? tokens.warning
                                          : tokens.textPrimary,
                                    ),
                                  ),
                                ),
                                if (cell.tagText != null)
                                  Positioned(
                                    top: 1,
                                    right: 1,
                                    child: Text(
                                      cell.tagText!,
                                      style: tokens.captionStyle.copyWith(
                                        fontSize: 6.5,
                                        height: 1.0,
                                        color: isToday
                                            ? tokens.accentForeground
                                            : (isHoliday
                                                  ? tokens.success
                                                  : tokens.warning),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                          if (cell.holidayTitle != null) {
                            cellBody = Tooltip(
                              message: cell.holidayTitle!,
                              child: cellBody,
                            );
                          }

                          return InkWell(
                            onTap: () {
                              _selectDay(d);
                              setState(() => _mode = _CalendarWorkspaceMode.month);
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: cellBody,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDayInspector({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required bool showLunar,
    required List<CalendarEvent> events,
    required TodoProvider? todos,
    required HabitProvider? habits,
    required DiaryProvider? diaries,
  }) {
    final isEn = locale == AppLocale.en;
    final today = _dateOnly(DateTime.now());
    final diffDays = _selectedDate.difference(today).inDays;
    final relativeLabel = switch (diffDays) {
      0 => isEn ? 'Today' : '今天',
      1 => isEn ? 'Tomorrow' : '明天',
      -1 => isEn ? 'Yesterday' : '昨天',
      > 1 => isEn ? 'In $diffDays d' : '$diffDays天后',
      _ => isEn ? '${-diffDays} d ago' : '${-diffDays}天前',
    };

    final withinLunarRange = LunarCalendar.isWithinDocumentedSolarRange(
      _selectedDate,
    );
    final lunar = withinLunarRange
        ? LunarCalendar.tryFromSolar(_selectedDate)
        : null;
    final solarTerm = withinLunarRange
        ? LunarCalendar.solarTerm(_selectedDate)
        : null;
    final festival = withinLunarRange
        ? (LunarCalendar.solarFestival(_selectedDate) ??
              (lunar == null ? null : LunarCalendar.lunarFestival(lunar)))
        : null;
    final almanac = withinLunarRange
        ? LunarCalendar.tryAlmanacDetail(_selectedDate)
        : null;

    final lunarDisplayParts = <String>[
      if (lunar != null) AlmanacLocaleFormat.formatLunarDate(lunar, locale),
      if (solarTerm != null)
        AlmanacLocaleFormat.formatSolarTerm(solarTerm, locale) ?? solarTerm,
      if (festival != null)
        AlmanacLocaleFormat.formatFestival(festival, locale) ?? festival,
    ];

    final timed = events
        .where((e) => e.time != null)
        .toList(growable: false)
      ..sort((a, b) {
        final am = a.time!.hour * 60 + a.time!.minute;
        final bm = b.time!.hour * 60 + b.time!.minute;
        return am.compareTo(bm);
      });
    final allDay = events
        .where((e) => e.time == null)
        .toList(growable: false);

    return Container(
      color: tokens.isLiquidGlass
          ? tokens.sidebarBackground
          : tokens.sidebarBackground.withValues(alpha: 0.72),
      child: ListView(
        controller: _inspectorScrollCtrl,
        padding: const EdgeInsets.all(14),
        children: [
          // 1. Selected Date Hero Header
          DesktopPanelCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: diffDays == 0
                            ? tokens.accentSoft
                            : tokens.mutedSurface,
                        borderRadius: BorderRadius.circular(
                          DesktopWebTokens.radiusPill,
                        ),
                      ),
                      child: Text(
                        relativeLabel,
                        style: tokens.captionStyle.copyWith(
                          color: diffDays == 0
                              ? tokens.accent
                              : tokens.textSecondary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    _ToolbarIconBtn(
                      icon: Icons.chevron_left_rounded,
                      tooltip: isEn ? 'Previous day' : '前一天',
                      tokens: tokens,
                      onTap: () {
                        final prev = CalendarDateNavigation.tryShiftDays(
                          _selectedDate,
                          -1,
                        );
                        if (prev != null) _selectDay(prev);
                      },
                    ),
                    const SizedBox(width: 2),
                    _ToolbarIconBtn(
                      icon: Icons.chevron_right_rounded,
                      tooltip: isEn ? 'Next day' : '后一天',
                      tokens: tokens,
                      onTap: () {
                        final next = CalendarDateNavigation.tryShiftDays(
                          _selectedDate,
                          1,
                        );
                        if (next != null) _selectDay(next);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  isEn
                      ? '${_weekdayName(_selectedDate.weekday, locale)}, ${I18nDateFormat.monthDay(_selectedDate)}'
                      : '${_selectedDate.month}月${_selectedDate.day}日 · ${_weekdayName(_selectedDate.weekday, locale)}',
                  style: tokens.heroTitleStyle.copyWith(fontSize: 20),
                ),
                if (showLunar && lunarDisplayParts.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    lunarDisplayParts.join(' · '),
                    style: tokens.bodyMutedStyle.copyWith(
                      color: (solarTerm != null || festival != null)
                          ? tokens.accent
                          : tokens.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _InspectorMetaBadge(
                      label: AlmanacUiCopy.isoWeekBadge(
                        LunarCalendar.isoWeekNumber(_selectedDate),
                        locale,
                      ),
                      color: tokens.textSecondary,
                      tokens: tokens,
                    ),
                    if (HolidayCalendar.isHoliday(_selectedDate))
                      _InspectorMetaBadge(
                        label:
                            '${AlmanacUiCopy.holidayTag} · ${HolidayCalendar.holidayName(_selectedDate, locale: locale) ?? AlmanacUiCopy.holidayBadge}',
                        color: tokens.success,
                        tokens: tokens,
                      )
                    else if (HolidayCalendar.isWorkMakeupDay(_selectedDate))
                      _InspectorMetaBadge(
                        label:
                            '${AlmanacUiCopy.makeupWorkdayTag} · ${AlmanacUiCopy.makeupWorkdayBadge}',
                        color: tokens.warning,
                        tokens: tokens,
                      ),
                    _InspectorMetaBadge(
                      label: AlmanacLocaleFormat.formatXingZuo(
                        almanac?.xingZuo ?? LunarCalendar.xingZuo(_selectedDate),
                        locale,
                      ),
                      color: tokens.info,
                      tokens: tokens,
                    ),
                    if (showLunar && almanac != null && almanac.tianShen.isNotEmpty)
                      _InspectorMetaBadge(
                        label:
                            '${AlmanacLocaleFormat.formatTianShenType(almanac.tianShenType, locale)} · ${AlmanacLocaleFormat.formatTianShen(almanac.tianShen, locale)}',
                        color: almanac.isHuangDao
                            ? tokens.success
                            : tokens.textSecondary,
                        tokens: tokens,
                      ),
                  ],
                ),
                if (almanac?.nextSolarTerm != null) ...[
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Icon(
                        Icons.eco_outlined,
                        size: 13,
                        color: tokens.success,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          AlmanacUiCopy.solarTermCountdownText(
                            almanac!.nextSolarTerm!,
                            locale,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tokens.captionStyle.copyWith(
                            color: tokens.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (showLunar && almanac != null) ...[
                  const SizedBox(height: 10),
                  Divider(
                    height: 1,
                    thickness: DesktopWebTokens.hairlineWidth,
                    color: tokens.hairlineBorder,
                  ),
                  const SizedBox(height: 10),
                  _AlmanacClickableChipsRow(
                    badge: isEn ? 'Fit' : '宜',
                    badgeColor: tokens.success,
                    rawTerms: almanac.suitable,
                    locale: locale,
                    tokens: tokens,
                    onTapTerm: (term) => _showTermExplanationDialog(
                      term,
                      isSuitable: true,
                      locale: locale,
                      tokens: tokens,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _AlmanacClickableChipsRow(
                    badge: isEn ? 'Avoid' : '忌',
                    badgeColor: tokens.warning,
                    rawTerms: almanac.avoid,
                    locale: locale,
                    tokens: tokens,
                    onTapTerm: (term) => _showTermExplanationDialog(
                      term,
                      isSuitable: false,
                      locale: locale,
                      tokens: tokens,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                InkWell(
                  key: const ValueKey('desktop_calendar_open_almanac'),
                  onTap: _openFullAlmanac,
                  borderRadius: BorderRadius.circular(
                    DesktopWebTokens.radiusSm,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.accentSoft,
                      borderRadius: BorderRadius.circular(
                        DesktopWebTokens.radiusSm,
                      ),
                      border: Border.all(
                        color: tokens.accentBorder,
                        width: DesktopWebTokens.hairlineWidth,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.wb_twilight_rounded,
                          size: 15,
                          color: tokens.accent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            AlmanacUiCopy.fullAlmanacAndAuspiciousAction,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tokens.captionStyle.copyWith(
                              color: tokens.accent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: tokens.accent,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 2. Inline Quick Diary Card
          DesktopPanelCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.menu_book_outlined,
                      size: 16,
                      color: tokens.accent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isEn ? 'Daily Journal' : '这一天的日记',
                      style: tokens.cardTitleStyle.copyWith(fontSize: 14),
                    ),
                    const Spacer(),
                    if (diaries != null)
                      Tooltip(
                        message: isEn ? 'Open full diary editor' : '打开完整日记编辑',
                        child: InkWell(
                          onTap: () => showDiaryEditor(
                            context,
                            entry: diaries.entryForDate(_selectedDate),
                            initialDate: _selectedDate,
                          ),
                          borderRadius: BorderRadius.circular(
                            DesktopWebTokens.radiusXs,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.open_in_new_rounded,
                              size: 14,
                              color: tokens.textMuted,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // Mood selector pills
                Row(
                  children: [
                    for (final mood in Mood.values)
                      Expanded(
                        child: Tooltip(
                          message: mood.labelFor(locale),
                          child: InkWell(
                            onTap: diaries == null
                                ? null
                                : () => _saveInlineDiary(overrideMood: mood),
                            borderRadius: BorderRadius.circular(
                              DesktopWebTokens.radiusSm,
                            ),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              decoration: BoxDecoration(
                                color: _draftMood == mood
                                    ? tokens.accentSoft
                                    : tokens.mutedSurface,
                                borderRadius: BorderRadius.circular(
                                  DesktopWebTokens.radiusSm,
                                ),
                                border: Border.all(
                                  color: _draftMood == mood
                                      ? tokens.accentBorder
                                      : Colors.transparent,
                                  width: DesktopWebTokens.hairlineWidth,
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  switch (mood) {
                                    Mood.awesome =>
                                      Icons.sentiment_very_satisfied_outlined,
                                    Mood.good =>
                                      Icons.sentiment_satisfied_outlined,
                                    Mood.okay =>
                                      Icons.sentiment_neutral_outlined,
                                    Mood.bad =>
                                      Icons.sentiment_dissatisfied_outlined,
                                    Mood.terrible =>
                                      Icons.sentiment_very_dissatisfied_outlined,
                                  },
                                  size: 17,
                                  color: _draftMood == mood
                                      ? tokens.accent
                                      : tokens.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _diaryCtrl,
                  focusNode: _diaryFocus,
                  minLines: 2,
                  maxLines: 5,
                  style: tokens.bodyStyle.copyWith(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: isEn
                        ? 'Write a quick note for this day...'
                        : '写下这一天的日记...',
                    hintStyle: tokens.bodyMutedStyle.copyWith(
                      color: tokens.textMuted,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _diaryDirty
                            ? (isEn ? 'Unsaved changes' : '有未保存内容')
                            : (_diarySavedSnapshot.isNotEmpty
                                  ? (isEn ? 'Saved' : '已记录')
                                  : (isEn
                                        ? 'Pick mood or jot a line'
                                        : '随时记下想法与心情')),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens.captionStyle.copyWith(
                          color: _diaryDirty
                              ? tokens.warning
                              : tokens.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_diaryDirty || _diaryCtrl.text.trim().isNotEmpty)
                      FilledButton.tonal(
                        onPressed: _savingDiary ? null : () => _saveInlineDiary(),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          minimumSize: const Size(0, 26),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          _savingDiary
                              ? (isEn ? 'Saving...' : '保存中...')
                              : (isEn ? 'Save' : '保存日记'),
                          style: tokens.captionStyle.copyWith(
                            color: tokens.accent,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 3. Full Chronological Day Agenda + Quick Add
          DesktopPanelCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isEn ? 'Day Agenda' : '当日议程',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens.cardTitleStyle.copyWith(fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.mutedSurface,
                        borderRadius: BorderRadius.circular(
                          DesktopWebTokens.radiusPill,
                        ),
                      ),
                      child: Text(
                        '${events.length}',
                        style: tokens.captionStyle,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => setState(() {
                        _showQuickTodoInput = !_showQuickTodoInput;
                        if (_showQuickTodoInput) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _quickTodoFocus.requestFocus();
                          });
                        }
                      }),
                      borderRadius: BorderRadius.circular(
                        DesktopWebTokens.radiusXs,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.mutedSurface,
                          borderRadius: BorderRadius.circular(
                            DesktopWebTokens.radiusXs,
                          ),
                        ),
                        child: Text(
                          isEn ? '+ Task' : '+ 待办',
                          style: tokens.captionStyle.copyWith(
                            color: tokens.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => _createEvent(date: _selectedDate),
                      borderRadius: BorderRadius.circular(
                        DesktopWebTokens.radiusXs,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.accentSoft,
                          borderRadius: BorderRadius.circular(
                            DesktopWebTokens.radiusXs,
                          ),
                        ),
                        child: Text(
                          isEn ? '+ Event' : '+ 日程',
                          style: tokens.captionStyle.copyWith(
                            color: tokens.accent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                if (_showQuickTodoInput) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _quickTodoCtrl,
                          focusNode: _quickTodoFocus,
                          onSubmitted: (_) => _submitQuickTodo(),
                          style: tokens.bodyStyle.copyWith(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: isEn
                                ? 'Add task for this day, press Enter...'
                                : '添加这一天的待办，回车保存...',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        onPressed: _submitQuickTodo,
                        icon: Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: tokens.accent,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 10),
                if (events.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.event_available_outlined,
                            size: 26,
                            color: tokens.textMuted,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isEn
                                ? 'Nothing scheduled for this day'
                                : '这一天暂无安排，可随时添加日程或待办',
                            style: tokens.bodyMutedStyle.copyWith(
                              color: tokens.textMuted,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  if (timed.isNotEmpty) ...[
                    Text(
                      isEn ? 'TIMED SCHEDULE' : '按时间安排',
                      style: tokens.sectionHeaderStyle,
                    ),
                    const SizedBox(height: 6),
                    for (final event in timed)
                      _InspectorAgendaRow(
                        event: event,
                        selectedDate: _selectedDate,
                        locale: locale,
                        tokens: tokens,
                        todos: todos,
                        habits: habits,
                        onOpenEvent: _openEventSheet,
                        onOpenTodo: _openTodoDetailOrSheet,
                      ),
                  ],
                  if (allDay.isNotEmpty) ...[
                    if (timed.isNotEmpty) const SizedBox(height: 10),
                    Text(
                      isEn ? 'ALL-DAY & MILESTONES' : '全天 · 待办与习惯',
                      style: tokens.sectionHeaderStyle,
                    ),
                    const SizedBox(height: 6),
                    for (final event in allDay)
                      _InspectorAgendaRow(
                        event: event,
                        selectedDate: _selectedDate,
                        locale: locale,
                        tokens: tokens,
                        todos: todos,
                        habits: habits,
                        onOpenEvent: _openEventSheet,
                        onOpenTodo: _openTodoDetailOrSheet,
                      ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final DesktopWebTokens tokens;
  final VoidCallback onTap;

  const _ToolbarIconBtn({
    required this.icon,
    required this.tooltip,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(icon, size: 17, color: tokens.textSecondary),
        ),
      ),
    );
  }
}

class _ModeSegmentButton extends StatelessWidget {
  final String label;
  final bool selected;
  final DesktopWebTokens tokens;
  final VoidCallback onTap;

  const _ModeSegmentButton({
    required this.label,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXs),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? tokens.elevatedSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXs),
          boxShadow: selected ? tokens.cardShadow : null,
        ),
        child: Text(
          label,
          style: tokens.captionStyle.copyWith(
            fontSize: 12,
            color: selected ? tokens.accent : tokens.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _MonthDayCell extends StatefulWidget {
  final DateTime? day;
  final bool isFirstCol;
  final bool isInCurrentMonth;
  final bool isToday;
  final bool isSelected;
  final bool isHoliday;
  final bool isWorkMakeupDay;
  final String? lunarTag;
  final bool isLunarHighlighted;
  final List<CalendarEvent> events;
  final AppLocale locale;
  final DesktopWebTokens tokens;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<DateTime> onCreateForDay;
  final ValueChanged<CalendarEvent> onTapEvent;

  const _MonthDayCell({
    required this.day,
    required this.isFirstCol,
    required this.isInCurrentMonth,
    required this.isToday,
    required this.isSelected,
    this.isHoliday = false,
    this.isWorkMakeupDay = false,
    required this.lunarTag,
    required this.isLunarHighlighted,
    required this.events,
    required this.locale,
    required this.tokens,
    required this.onSelectDay,
    required this.onCreateForDay,
    required this.onTapEvent,
  });

  @override
  State<_MonthDayCell> createState() => _MonthDayCellState();
}

class _MonthDayCellState extends State<_MonthDayCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final tokens = widget.tokens;
    final baseBorder = Border(
      left: widget.isFirstCol
          ? BorderSide.none
          : BorderSide(
              color: tokens.hairlineBorder,
              width: DesktopWebTokens.hairlineWidth,
            ),
    );

    if (day == null) {
      return Container(decoration: BoxDecoration(border: baseBorder));
    }

    final bgColor = widget.isSelected
        ? tokens.accentSoft
        : _hovered
        ? tokens.hoverSurface
        : (widget.isHoliday && widget.isInCurrentMonth)
        ? tokens.success.withValues(alpha: tokens.isDark ? 0.08 : 0.045)
        : (!widget.isInCurrentMonth
              ? tokens.mutedSurface
              : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSelectDay(day),
        onDoubleTap: () => widget.onCreateForDay(day),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: bgColor,
            border: widget.isSelected
                ? Border.all(color: tokens.accent, width: 1.0)
                : baseBorder,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Day number + holiday badge + lunar/festival tag + hover '+'
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: widget.isToday
                        ? BoxDecoration(
                            color: tokens.accent,
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Text(
                      '${day.day}',
                      style: tokens.bodyStyle.copyWith(
                        fontSize: 12.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: widget.isToday
                            ? tokens.accentForeground
                            : widget.isInCurrentMonth
                            ? (widget.isSelected
                                  ? tokens.accent
                                  : tokens.textPrimary)
                            : tokens.textMuted,
                      ),
                    ),
                  ),
                  if (widget.isHoliday || widget.isWorkMakeupDay) ...[
                    const SizedBox(width: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 0.5,
                      ),
                      decoration: BoxDecoration(
                        color: (widget.isHoliday
                                ? tokens.success
                                : tokens.warning)
                            .withValues(
                              alpha: widget.isInCurrentMonth
                                  ? (tokens.isDark ? 0.22 : 0.14)
                                  : 0.08,
                            ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.isHoliday
                            ? AlmanacUiCopy.holidayTag
                            : AlmanacUiCopy.makeupWorkdayTag,
                        style: tokens.captionStyle.copyWith(
                          fontSize: 9.0,
                          height: 1.1,
                          color: (widget.isHoliday
                                  ? tokens.success
                                  : tokens.warning)
                              .withValues(
                                alpha: widget.isInCurrentMonth ? 1.0 : 0.65,
                              ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 3),
                  if (widget.lunarTag != null)
                    Expanded(
                      child: Text(
                        widget.lunarTag!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: tokens.captionStyle.copyWith(
                          fontSize: 10.5,
                          color: widget.isLunarHighlighted
                              ? tokens.accent
                              : (widget.isInCurrentMonth
                                    ? tokens.textMuted
                                    : tokens.textMuted.withValues(alpha: 0.55)),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  if (_hovered)
                    InkWell(
                      onTap: () => widget.onCreateForDay(day),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Icon(
                          Icons.add_rounded,
                          size: 14,
                          color: tokens.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxHeight < 18 ||
                        widget.events.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    const pillHeight = 17.0;
                    const gap = 2.0;
                    final maxSlots =
                        ((constraints.maxHeight + gap) / (pillHeight + gap))
                            .floor()
                            .clamp(0, 4);
                    if (maxSlots == 0) return const SizedBox.shrink();

                    final hasOverflow = widget.events.length > maxSlots;
                    final visibleCount = hasOverflow
                        ? (maxSlots - 1).clamp(0, widget.events.length)
                        : widget.events.length.clamp(0, maxSlots);
                    final remaining = widget.events.length - visibleCount;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < visibleCount; i++) ...[
                          if (i > 0) const SizedBox(height: gap),
                          _MonthEventPill(
                            event: widget.events[i],
                            tokens: tokens,
                            dimmed: !widget.isInCurrentMonth,
                            onTap: () {
                              widget.onSelectDay(day);
                              widget.onTapEvent(widget.events[i]);
                            },
                          ),
                        ],
                        if (hasOverflow && remaining > 0) ...[
                          const SizedBox(height: gap),
                          Text(
                            widget.locale == AppLocale.en
                                ? '+$remaining more'
                                : '+$remaining 项',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tokens.captionStyle.copyWith(
                              fontSize: 10,
                              color: tokens.textMuted,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthEventPill extends StatelessWidget {
  final CalendarEvent event;
  final DesktopWebTokens tokens;
  final bool dimmed;
  final VoidCallback onTap;

  const _MonthEventPill({
    required this.event,
    required this.tokens,
    required this.dimmed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = _formatEventTime(event);
    final title = CalendarEventDisplayText.resolveTitle(event);
    final display = timeStr.isEmpty ? title : '$timeStr $title';
    final alphaFactor = dimmed ? 0.55 : 1.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 17,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: event.color.withValues(
            alpha: (tokens.isDark ? 0.22 : 0.13) * alphaFactor,
          ),
          borderRadius: BorderRadius.circular(4),
          border: Border(
            left: BorderSide(
              color: event.color.withValues(alpha: alphaFactor),
              width: 2.5,
            ),
          ),
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          display,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.captionStyle.copyWith(
            fontSize: 10.5,
            height: 1.15,
            color: tokens.textPrimary.withValues(
              alpha: event.isCompleted ? 0.55 : alphaFactor,
            ),
            decoration: event.isCompleted ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }
}

class _AllDayMiniColumn extends StatelessWidget {
  final List<CalendarEvent> events;
  final DesktopWebTokens tokens;
  final ValueChanged<CalendarEvent> onTapEvent;

  const _AllDayMiniColumn({
    required this.events,
    required this.tokens,
    required this.onTapEvent,
  });

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    return ListView.separated(
      itemCount: events.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, idx) {
        final e = events[idx];
        return InkWell(
          onTap: () => onTapEvent(e),
          borderRadius: BorderRadius.circular(3),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: e.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
              border: Border(left: BorderSide(color: e.color, width: 2.5)),
            ),
            child: Text(
              CalendarEventDisplayText.resolveTitle(e),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.captionStyle.copyWith(
                fontSize: 10,
                color: tokens.textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HourlyEventColumn extends StatelessWidget {
  final DateTime? day;
  final bool isSelected;
  final bool isToday;
  final DateTime now;
  final double hourHeight;
  final List<CalendarEvent> timedEvents;
  final DesktopWebTokens tokens;
  final bool showExtendedDetails;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<CalendarEvent> onTapEvent;
  final ValueChanged<DateTime> onDoubleTapEmpty;

  const _HourlyEventColumn({
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.now,
    required this.hourHeight,
    required this.timedEvents,
    required this.tokens,
    this.showExtendedDetails = false,
    required this.onSelectDay,
    required this.onTapEvent,
    required this.onDoubleTapEmpty,
  });

  double _durationHours(CalendarEvent event) {
    if (event.endDate != null) {
      final diffMin = event.endDate!.difference(event.date).inMinutes;
      if (diffMin >= 20 && diffMin <= 12 * 60) {
        return diffMin / 60.0;
      }
    }
    return 0.9;
  }

  @override
  Widget build(BuildContext context) {
    final sorted = List<CalendarEvent>.of(timedEvents)
      ..sort((a, b) {
        final am = a.time!.hour * 60 + a.time!.minute;
        final bm = b.time!.hour * 60 + b.time!.minute;
        return am.compareTo(bm);
      });

    final nowMinutes = now.hour * 60 + now.minute;
    final nowTop = (nowMinutes / 60.0) * hourHeight;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: day == null ? null : () => onSelectDay(day!),
      onDoubleTap: day == null ? null : () => onDoubleTapEmpty(day!),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? tokens.accentSoft.withValues(alpha: tokens.accentSoft.a * 0.45)
              : null,
          border: Border(
            left: BorderSide(
              color: tokens.hairlineBorder,
              width: DesktopWebTokens.hairlineWidth,
            ),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final colWidth = constraints.maxWidth;
            return Stack(
              children: [
                // Hour divider lines
                Column(
                  children: [
                    for (var h = 0; h < 24; h++)
                      Container(
                        height: hourHeight,
                        decoration: h > 0
                            ? BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: tokens.hairlineBorder.withValues(
                                      alpha: tokens.hairlineBorder.a * 0.7,
                                    ),
                                    width: DesktopWebTokens.hairlineWidth,
                                  ),
                                ),
                              )
                            : null,
                      ),
                  ],
                ),

                // Timed event blocks
                for (var i = 0; i < sorted.length; i++)
                  _buildPositionedEvent(
                    sorted[i],
                    index: i,
                    all: sorted,
                    colWidth: colWidth,
                  ),

                // Current-time red indicator line
                if (isToday)
                  Positioned(
                    top: nowTop,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: tokens.danger,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Container(
                              height: 1.2,
                              color: tokens.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPositionedEvent(
    CalendarEvent event, {
    required int index,
    required List<CalendarEvent> all,
    required double colWidth,
  }) {
    final t = event.time!;
    final startMin = t.hour * 60 + t.minute;
    final top = (startMin / 60.0) * hourHeight;
    final height = (_durationHours(event) * hourHeight).clamp(24.0, 240.0);

    // Lightweight overlap lane offset
    var lane = 0;
    for (var prev = index - 1; prev >= 0; prev--) {
      final pTime = all[prev].time!;
      final pStart = pTime.hour * 60 + pTime.minute;
      if ((startMin - pStart).abs() < 45) {
        lane++;
      } else {
        break;
      }
    }
    final clampedLane = lane.clamp(0, 2);
    final leftInset = 3.0 + clampedLane * (colWidth * 0.22);

    final title = CalendarEventDisplayText.resolveTitle(event);
    final sub = CalendarEventDisplayText.resolveSubtitle(event);
    final timeStr = _formatEventTime(event);

    return Positioned(
      top: top + 1,
      left: leftInset,
      right: 3,
      height: height - 2,
      child: InkWell(
        onTap: () => onTapEvent(event),
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXs),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: event.color.withValues(alpha: tokens.isDark ? 0.28 : 0.16),
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXs),
            border: Border(left: BorderSide(color: event.color, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$timeStr $title',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.captionStyle.copyWith(
                        fontSize: 11,
                        color: tokens.textPrimary,
                        decoration: event.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  if (event.hasConflict)
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 12,
                      color: tokens.warning,
                    ),
                ],
              ),
              if (showExtendedDetails && height >= 40 && sub != null)
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.captionStyle.copyWith(
                    fontSize: 10.5,
                    color: tokens.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InspectorMetaBadge extends StatelessWidget {
  final String label;
  final Color color;
  final DesktopWebTokens tokens;

  const _InspectorMetaBadge({
    required this.label,
    required this.color,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: tokens.isDark ? 0.18 : 0.11),
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
      ),
      child: Text(
        label,
        style: tokens.captionStyle.copyWith(fontSize: 11, color: color),
      ),
    );
  }
}

class _AlmanacClickableChipsRow extends StatelessWidget {
  final String badge;
  final Color badgeColor;
  final String rawTerms;
  final AppLocale locale;
  final DesktopWebTokens tokens;
  final ValueChanged<String> onTapTerm;

  const _AlmanacClickableChipsRow({
    required this.badge,
    required this.badgeColor,
    required this.rawTerms,
    required this.locale,
    required this.tokens,
    required this.onTapTerm,
  });

  @override
  Widget build(BuildContext context) {
    final terms = rawTerms
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .take(5)
        .toList(growable: false);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: locale == AppLocale.en ? 44 : 24,
          ),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              badge,
              maxLines: 1,
              softWrap: false,
              style: tokens.captionStyle.copyWith(
                fontSize: 10.5,
                color: badgeColor,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: terms.isEmpty
              ? Text(
                  '—',
                  style: tokens.captionStyle.copyWith(
                    fontSize: 11.5,
                    color: tokens.textSecondary,
                  ),
                )
              : Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    for (final term in terms)
                      InkWell(
                        onTap: () => onTapTerm(term),
                        borderRadius: BorderRadius.circular(5),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.mutedSurface,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: tokens.hairlineBorder,
                              width: DesktopWebTokens.hairlineWidth,
                            ),
                          ),
                          child: Text(
                            AlmanacLocaleFormat.formatActivityTerm(
                              term,
                              locale,
                            ),
                            style: tokens.captionStyle.copyWith(
                              fontSize: 11,
                              color: tokens.textPrimary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _InspectorAgendaRow extends StatelessWidget {
  final CalendarEvent event;
  final DateTime selectedDate;
  final AppLocale locale;
  final DesktopWebTokens tokens;
  final TodoProvider? todos;
  final HabitProvider? habits;
  final ValueChanged<CalendarEvent> onOpenEvent;
  final ValueChanged<CalendarEvent> onOpenTodo;

  const _InspectorAgendaRow({
    required this.event,
    required this.selectedDate,
    required this.locale,
    required this.tokens,
    required this.todos,
    required this.habits,
    required this.onOpenEvent,
    required this.onOpenTodo,
  });

  @override
  Widget build(BuildContext context) {
    final title = CalendarEventDisplayText.resolveTitle(event);
    final subtitle = CalendarEventDisplayText.resolveSubtitle(event);
    final timeStr = _formatEventTime(event);
    final isTodo = event.type == CalendarEventType.todo;
    final isHabit = event.type == CalendarEventType.habit;
    final sourceId = event.sourceId;

    Habit? matchedHabit;
    if (isHabit && habits != null && sourceId != null) {
      for (final h in habits!.habits) {
        if (h.id == sourceId) {
          matchedHabit = h;
          break;
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DesktopHoverTile(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        onTap: () => isTodo ? onOpenTodo(event) : onOpenEvent(event),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 3,
              height: 26,
              decoration: BoxDecoration(
                color: event.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            if (isTodo && todos != null && sourceId != null)
              InkWell(
                onTap: () => todos!.toggleTodo(sourceId),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    event.isCompleted
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 17,
                    color: event.isCompleted
                        ? tokens.success
                        : tokens.textSecondary,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  _eventTypeIcon(event.type),
                  size: 15,
                  color: event.color,
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (timeStr.isNotEmpty) ...[
                        Text(
                          timeStr,
                          style: tokens.captionStyle.copyWith(
                            color: event.color,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tokens.bodyStyle.copyWith(
                            fontSize: 13,
                            color: event.isCompleted
                                ? tokens.textMuted
                                : tokens.textPrimary,
                            decoration: event.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (subtitle != null && subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.captionStyle.copyWith(
                        fontSize: 11,
                        color: tokens.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            if (event.hasConflict)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Tooltip(
                  message: CalendarAgendaUiCopy.timeConflictTooltip,
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 15,
                    color: tokens.warning,
                  ),
                ),
              ),
            if (isHabit && habits != null && matchedHabit != null) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: matchedHabit.countForDate(selectedDate) > 0
                    ? () => habits!.decrementHabitForDate(
                        matchedHabit!.id,
                        selectedDate,
                      )
                    : null,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.remove_rounded,
                    size: 15,
                    color: matchedHabit.countForDate(selectedDate) > 0
                        ? tokens.textSecondary
                        : tokens.textMuted.withValues(alpha: 0.4),
                  ),
                ),
              ),
              Text(
                '${matchedHabit.countForDate(selectedDate)}/${matchedHabit.targetCount}',
                style: tokens.captionStyle.copyWith(
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              InkWell(
                onTap: () => habits!.incrementHabitForDate(
                  matchedHabit!.id,
                  selectedDate,
                ),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.add_rounded,
                    size: 15,
                    color: tokens.accent,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _YearOverviewCache {
  final CalendarProvider? calendar;
  final int year;
  final int firstDayOfWeek;
  final AppLocale locale;
  final int calendarRevision;
  final int activeTypesMask;
  final List<int> weekdays;
  final List<_YearMonthCache> months;

  const _YearOverviewCache({
    required this.calendar,
    required this.year,
    required this.firstDayOfWeek,
    required this.locale,
    required this.calendarRevision,
    required this.activeTypesMask,
    required this.weekdays,
    required this.months,
  });
}

class _YearMonthCache {
  final int month;
  final int daysInMonth;
  final int monthEventCount;
  final List<_YearDayCellMeta?> cells;

  const _YearMonthCache({
    required this.month,
    required this.daysInMonth,
    required this.monthEventCount,
    required this.cells,
  });
}

class _YearDayCellMeta {
  final int dayNum;
  final DateTime date;
  final int count;
  final bool isHoliday;
  final bool isMakeup;
  final String? holidayTitle;
  final String? tagText;

  const _YearDayCellMeta({
    required this.dayNum,
    required this.date,
    required this.count,
    required this.isHoliday,
    required this.isMakeup,
    required this.holidayTitle,
    required this.tagText,
  });
}
