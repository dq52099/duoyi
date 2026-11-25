import 'dart:math' as math;

import 'app_date_format.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/almanac_locale_format.dart';
import '../core/calendar_date_navigation.dart';
import '../core/calendar_ui_copy.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/lunar_calendar.dart';
import '../providers/preferences_provider.dart';
import 'surface_components.dart';

enum AppDatePickerMode { solar, lunar }

String _formatLunarYear(int year, {int? solarYear}) =>
    AlmanacLocaleFormat.formatLunarYear(year, solarYear: solarYear);

class AppDatePickerResult {
  final DateTime date;
  final AppDatePickerMode mode;
  final bool ignoreYear;

  const AppDatePickerResult({
    required this.date,
    required this.mode,
    this.ignoreYear = false,
  });

  String get solarText => I18nDateFormat.date(date);

  String get lunarText {
    if (!LunarCalendar.isWithinDocumentedSolarRange(date)) {
      return CalendarUiCopy.unavailable;
    }
    final lunar = LunarCalendar.tryFromSolar(date);
    if (lunar == null) {
      return CalendarUiCopy.unavailable;
    }
    if (I18n.current == AppLocale.zh) {
      return '${_formatLunarYear(lunar.year, solarYear: date.year)}'
          '${LunarCalendar.monthName(lunar.month, isLeap: lunar.isLeapMonth)} '
          '${LunarCalendar.dayName(lunar.day)}';
    }
    final monthStr = lunar.isLeapMonth
        ? '${I18n.tr('picker.lunar.leap_month')} ${lunar.month}'
        : '${I18n.tr('picker.lunar.month')} ${lunar.month}';
    final dayStr = '${I18n.tr('picker.lunar.day')} ${lunar.day}';
    return '${I18n.tr('calendar.lunar')} ${_formatLunarYear(lunar.year)} $monthStr, $dayStr';
  }
}

class AppDatePicker {
  AppDatePicker._();

  static Future<DateTime?> pickSolar(
    BuildContext context, {
    required DateTime initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
    String? title,
    String? subtitle,
    String? titleKey,
    String? subtitleKey,
    String Function()? titleBuilder,
    String Function()? subtitleBuilder,
  }) async {
    final result = await show(
      context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      title: title,
      subtitle: subtitle,
      titleKey: titleKey,
      subtitleKey: subtitleKey,
      titleBuilder: titleBuilder,
      subtitleBuilder: subtitleBuilder,
      initialMode: AppDatePickerMode.solar,
    );
    return result?.date;
  }

  static ModalBottomSheetRoute<AppDatePickerResult> buildRoute(
    BuildContext context, {
    required DateTime initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
    String? title,
    String? subtitle,
    String? titleKey,
    String? subtitleKey,
    String Function()? titleBuilder,
    String Function()? subtitleBuilder,
    AppDatePickerMode initialMode = AppDatePickerMode.solar,
    bool allowIgnoreYear = false,
    bool initialIgnoreYear = false,
    bool useRootNavigator = false,
  }) {
    final preferences = context.read<PreferencesProvider?>();
    return createAppModalSheetRoute<AppDatePickerResult>(
      context: context,
      useRootNavigator: useRootNavigator,
      builder: (_) {
        final sheet = _AppDatePickerSheet(
          initialDate: initialDate,
          firstDate: firstDate ?? DateTime(1900),
          lastDate: lastDate ?? DateTime(2099, 12, 31),
          title: title,
          subtitle: subtitle,
          titleKey: titleKey,
          subtitleKey: subtitleKey,
          titleBuilder: titleBuilder,
          subtitleBuilder: subtitleBuilder,
          initialMode: initialMode,
          allowIgnoreYear: allowIgnoreYear,
          initialIgnoreYear: initialIgnoreYear,
        );
        return preferences == null
            ? sheet
            : ChangeNotifierProvider<PreferencesProvider>.value(
                value: preferences,
                child: sheet,
              );
      },
    );
  }

  static Future<AppDatePickerResult?> show(
    BuildContext context, {
    required DateTime initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
    String? title,
    String? subtitle,
    String? titleKey,
    String? subtitleKey,
    String Function()? titleBuilder,
    String Function()? subtitleBuilder,
    AppDatePickerMode initialMode = AppDatePickerMode.solar,
    bool allowIgnoreYear = false,
    bool initialIgnoreYear = false,
    bool useRootNavigator = false,
  }) {
    final route = buildRoute(
      context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      title: title,
      subtitle: subtitle,
      titleKey: titleKey,
      subtitleKey: subtitleKey,
      titleBuilder: titleBuilder,
      subtitleBuilder: subtitleBuilder,
      initialMode: initialMode,
      allowIgnoreYear: allowIgnoreYear,
      initialIgnoreYear: initialIgnoreYear,
      useRootNavigator: useRootNavigator,
    );
    return Navigator.of(context, rootNavigator: useRootNavigator).push(route);
  }
}

class _AppDatePickerSheet extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String? title;
  final String? subtitle;
  final String? titleKey;
  final String? subtitleKey;
  final String Function()? titleBuilder;
  final String Function()? subtitleBuilder;
  final AppDatePickerMode initialMode;
  final bool allowIgnoreYear;
  final bool initialIgnoreYear;

  const _AppDatePickerSheet({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    this.title,
    this.subtitle,
    this.titleKey,
    this.subtitleKey,
    this.titleBuilder,
    this.subtitleBuilder,
    required this.initialMode,
    required this.allowIgnoreYear,
    required this.initialIgnoreYear,
  });

  @override
  State<_AppDatePickerSheet> createState() => _AppDatePickerSheetState();
}

class _AppDatePickerSheetState extends State<_AppDatePickerSheet> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  late AppDatePickerMode _mode;
  LunarDate? _lunar;
  LunarDate? _wheelLunar;
  bool _lunarCandidateUnavailable = false;
  bool _ignoreYear = false;
  ModalRoute<dynamic>? _owningRoute;

  bool _isLunarRepresentable(DateTime solarDate, LunarDate? lunar) {
    if (!LunarCalendar.isWithinDocumentedSolarRange(solarDate)) return false;
    if (lunar == null) return false;
    return lunar.year >= 1900 && lunar.year <= 2099;
  }

  LunarDate? _tryRepresentableLunar(DateTime solarDate) {
    if (!LunarCalendar.isWithinDocumentedSolarRange(solarDate)) return null;
    final lunar = LunarCalendar.tryFromSolar(solarDate);
    if (lunar == null || lunar.year < 1900 || lunar.year > 2099) return null;
    return lunar;
  }

  @override
  void initState() {
    super.initState();
    _selectedDay = _clamp(widget.initialDate);
    _focusedDay = _selectedDay;
    _mode = widget.initialMode;
    _lunar = _tryRepresentableLunar(_selectedDay);
    _wheelLunar = _lunar ?? const LunarDate(1900, 1, 1);
    if (_mode == AppDatePickerMode.lunar &&
        !_isLunarRepresentable(_selectedDay, _lunar)) {
      _mode = AppDatePickerMode.solar;
    }
    _ignoreYear = widget.initialIgnoreYear && widget.allowIgnoreYear;
    I18n.localeListenable.addListener(_onLocaleChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _owningRoute ??= ModalRoute.of(context);
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _handleCancel() {
    if (!mounted) return;
    final route = _owningRoute ?? ModalRoute.of(context);
    if (route == null || !route.isActive || !route.isCurrent) return;
    route.navigator?.pop();
  }

  void _handleConfirm() {
    if (!mounted) return;
    final route = _owningRoute ?? ModalRoute.of(context);
    if (route == null || !route.isActive || !route.isCurrent) return;
    final result = AppDatePickerResult(
      date: _selectedDay,
      mode: _mode,
      ignoreYear: _ignoreYear,
    );
    route.navigator?.pop(result);
  }

  DateTime _clamp(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    if (d.isBefore(widget.firstDate)) return widget.firstDate;
    if (d.isAfter(widget.lastDate)) return widget.lastDate;
    return d;
  }

  void _setSolar(DateTime day) {
    setState(() {
      _selectedDay = _clamp(day);
      _focusedDay = DateTime(_selectedDay.year, _selectedDay.month);
      _lunar = _tryRepresentableLunar(_selectedDay);
      if (_lunar != null) {
        _wheelLunar = _lunar;
      }
      _lunarCandidateUnavailable = false;
    });
  }

  void _setLunar({int? year, int? month, int? day, bool? isLeapMonth}) {
    final currentLunar = _wheelLunar ?? _lunar ?? const LunarDate(1900, 1, 1);
    final nextYear = year ?? currentLunar.year;
    final nextMonth = month ?? currentLunar.month;
    final leapOfYear = LunarCalendar.leapMonthOfLunarYear(nextYear);
    final requestedLeap = isLeapMonth ?? currentLunar.isLeapMonth;
    final nextIsLeap = requestedLeap && leapOfYear == nextMonth;
    final computedDays = LunarCalendar.daysInLunarMonth(
      nextYear,
      nextMonth,
      isLeap: nextIsLeap,
    );
    final maxDay = computedDays > 0
        ? computedDays
        : LunarCalendar.daysInMonth(nextYear, nextMonth, isLeap: nextIsLeap);
    final nextDay = (day ?? currentLunar.day).clamp(1, maxDay).toInt();
    final candidateLunar = LunarDate(
      nextYear,
      nextMonth,
      nextDay,
      isLeapMonth: nextIsLeap,
    );

    final solar = LunarCalendar.tryToSolar(
      nextYear,
      nextMonth,
      nextDay,
      isLeap: nextIsLeap,
    );

    LunarDate? roundtripLunar;
    if (solar != null &&
        LunarCalendar.isWithinDocumentedSolarRange(solar) &&
        !solar.isBefore(widget.firstDate) &&
        !solar.isAfter(widget.lastDate)) {
      try {
        roundtripLunar = LunarCalendar.tryFromSolar(solar);
      } catch (_) {
        roundtripLunar = null;
      }
    }

    final isValidCandidate =
        roundtripLunar != null &&
        roundtripLunar.year == candidateLunar.year &&
        roundtripLunar.month == candidateLunar.month &&
        roundtripLunar.day == candidateLunar.day &&
        roundtripLunar.isLeapMonth == candidateLunar.isLeapMonth;

    setState(() {
      _wheelLunar = candidateLunar;
      if (isValidCandidate) {
        _selectedDay = solar!;
        _focusedDay = DateTime(_selectedDay.year, _selectedDay.month);
        _lunar = roundtripLunar;
        _lunarCandidateUnavailable = false;
      } else {
        _lunarCandidateUnavailable = true;
      }
    });
  }

  String _resolveTitle() {
    if (widget.titleBuilder != null) return widget.titleBuilder!();
    if (widget.titleKey != null) return I18n.tr(widget.titleKey!);
    if (widget.title != null) return widget.title!;
    return I18n.tr('picker.date.title');
  }

  String? _resolveSubtitle() {
    if (widget.subtitleBuilder != null) return widget.subtitleBuilder!();
    if (widget.subtitleKey != null) return I18n.tr(widget.subtitleKey!);
    return widget.subtitle;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final result = AppDatePickerResult(
      date: _selectedDay,
      mode: _mode,
      ignoreYear: _ignoreYear,
    );
    return AppModalSheet(
      title: _resolveTitle(),
      subtitle: _resolveSubtitle(),
      actions: [
        TextButton.icon(
          onPressed: () => _setSolar(DateTime.now()),
          icon: const Icon(Icons.today_outlined, size: 18),
          label: Text(I18n.tr('picker.action.today')),
        ),
        TextButton(
          onPressed: _handleCancel,
          child: Text(I18n.tr('action.cancel')),
        ),
        FilledButton(
          onPressed: _handleConfirm,
          child: Text(I18n.tr('action.confirm')),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<AppDatePickerMode>(
            segments: [
              ButtonSegment(
                value: AppDatePickerMode.solar,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(I18n.tr('calendar.solar')),
              ),
              ButtonSegment(
                value: AppDatePickerMode.lunar,
                icon: const Icon(Icons.brightness_2_outlined),
                label: Text(I18n.tr('calendar.lunar')),
                enabled: _isLunarRepresentable(_selectedDay, _lunar),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() {
              if (s.first == AppDatePickerMode.lunar &&
                  !_isLunarRepresentable(_selectedDay, _lunar)) {
                return;
              }
              _mode = s.first;
            }),
          ),
          const SizedBox(height: 12),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                cs.primary.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.12 : 0.06,
                ),
                cs.surface,
              ),
              borderRadius: DesignTokens.borderRadiusLg,
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.16),
                width: 0.45,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: DesignTokens.borderRadiusMd,
                  ),
                  child: Icon(
                    _mode == AppDatePickerMode.solar
                        ? Icons.calendar_month_outlined
                        : Icons.brightness_2_outlined,
                    color: cs.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppDateFormat.date(context, result.date),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _lunarCandidateUnavailable
                            ? CalendarUiCopy.unavailable
                            : result.lunarText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (widget.allowIgnoreYear) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _ignoreYear,
              title: Text(I18n.tr('picker.date.ignore_year')),
              subtitle: Text(I18n.tr('picker.date.ignore_year_desc')),
              onChanged: (v) => setState(() => _ignoreYear = v),
            ),
          ],
          const SizedBox(height: 12),
          if (_mode == AppDatePickerMode.solar)
            _SolarCalendar(
              focusedDay: _focusedDay,
              selectedDay: _selectedDay,
              firstDay: widget.firstDate,
              lastDay: widget.lastDate,
              onDaySelected: _setSolar,
              onPageChanged: (day) => setState(() => _focusedDay = day),
            )
          else if (_isLunarRepresentable(_selectedDay, _lunar) &&
              _wheelLunar != null)
            _LunarPicker(lunar: _wheelLunar!, onChanged: _setLunar)
          else
            Container(
              height: 190,
              alignment: Alignment.center,
              child: Text(
                CalendarUiCopy.unavailable,
                style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _SolarCalendar extends StatelessWidget {
  final DateTime focusedDay;
  final DateTime selectedDay;
  final DateTime firstDay;
  final DateTime lastDay;
  final ValueChanged<DateTime> onDaySelected;
  final ValueChanged<DateTime> onPageChanged;

  const _SolarCalendar({
    required this.focusedDay,
    required this.selectedDay,
    required this.firstDay,
    required this.lastDay,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  static const _weekdayKeys = <String>[
    'picker.weekday.mon',
    'picker.weekday.tue',
    'picker.weekday.wed',
    'picker.weekday.thu',
    'picker.weekday.fri',
    'picker.weekday.sat',
    'picker.weekday.sun',
  ];

  static const _weekdayFullKeys = <String>[
    'weekday.mon',
    'weekday.tue',
    'weekday.wed',
    'weekday.thu',
    'weekday.fri',
    'weekday.sat',
    'weekday.sun',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final month = DateTime(focusedDay.year, focusedDay.month);
    final firstMonth = DateTime(firstDay.year, firstDay.month);
    final lastMonth = DateTime(lastDay.year, lastDay.month);
    final canGoPrevious = month.isAfter(firstMonth);
    final canGoNext = month.isBefore(lastMonth);
    final firstOfMonth = DateTime.utc(month.year, month.month, 1);
    final firstDayOfWeek = context.select<PreferencesProvider?, int>(
      (p) => CalendarDateNavigation.normalizeFirstDayOfWeek(
        p?.firstDayOfWeek ?? 1,
      ),
    );
    final weekdayOrder = CalendarDateNavigation.orderedWeekdays(firstDayOfWeek);
    final leadingBlankCount = (firstOfMonth.weekday - firstDayOfWeek) % 7;
    final calendarFill = Color.alphaBlend(
      cs.primary.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.06 : 0.025,
      ),
      cs.surface,
    );
    const rows = 6;
    final inheritedStyle = DefaultTextStyle.of(context).style;
    final weekdayStyle = inheritedStyle
        .merge(theme.textTheme.labelMedium)
        .copyWith(fontWeight: FontWeight.normal);
    final dayStyle = inheritedStyle
        .merge(theme.textTheme.bodyMedium)
        .copyWith(fontWeight: FontWeight.normal);
    final textScaler = MediaQuery.textScalerOf(context);
    var minimumColumnWidth = 0.0;
    var dayHeight = 38.0;
    void measure(
      String label,
      TextStyle style,
      double horizontalPadding, {
      bool day = false,
    }) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: textScaler,
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 1,
      )..layout();
      try {
        minimumColumnWidth = math.max(
          minimumColumnWidth,
          painter.width + horizontalPadding,
        );
        if (day) dayHeight = math.max(dayHeight, painter.height + 4);
      } finally {
        painter.dispose();
      }
    }

    // Budget the actual scaled labels once for the whole seven-column grid.
    // Weekday gutters and day-cell padding must survive enlarged fonts.
    for (final key in _weekdayKeys) {
      measure(I18n.tr(key), weekdayStyle, 4);
    }
    for (var day = 1; day <= 31; day++) {
      measure('$day', dayStyle, 6, day: true);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: calendarFill,
        borderRadius: DesignTokens.borderRadiusLg,
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.16),
          width: 0.45,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: I18n.tr('picker.date.prev_month'),
                  visualDensity: VisualDensity.compact,
                  onPressed: canGoPrevious
                      ? () {
                          final prev = CalendarDateNavigation.tryShiftMonths(
                            month,
                            -1,
                          );
                          if (prev != null) {
                            onPageChanged(DateTime(prev.year, prev.month));
                          }
                        }
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      I18nDateFormat.yearMonth(month),
                      style:
                          theme.textTheme.titleMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.normal,
                          ) ??
                          TextStyle(
                            color: cs.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.normal,
                          ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: I18n.tr('picker.date.next_month'),
                  visualDensity: VisualDensity.compact,
                  onPressed: canGoNext
                      ? () {
                          final next = CalendarDateNavigation.tryShiftMonths(
                            month,
                            1,
                          );
                          if (next != null) {
                            onPageChanged(DateTime(next.year, next.month));
                          }
                        }
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 2),
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: math.max(constraints.maxWidth, minimumColumnWidth * 7),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          for (var i = 0; i < 7; i++)
                            Expanded(
                              child: Center(
                                child: _WeekdayLabel(
                                  label: I18n.tr(
                                    _weekdayKeys[weekdayOrder[i] - 1],
                                  ),
                                  semanticsLabel: I18n.tr(
                                    _weekdayFullKeys[weekdayOrder[i] - 1],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      for (var row = 0; row < rows; row++)
                        Row(
                          children: [
                            for (var col = 0; col < 7; col++)
                              Expanded(
                                child: _SolarDayCell(
                                  cell: _dateForCell(
                                    month: month,
                                    index: row * 7 + col,
                                    leadingBlankCount: leadingBlankCount,
                                  ),
                                  selectedDay: selectedDay,
                                  firstDay: firstDay,
                                  lastDay: lastDay,
                                  onSelected: onDaySelected,
                                  height: dayHeight,
                                ),
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
      ),
    );
  }

  static _SolarCalendarCell _dateForCell({
    required DateTime month,
    required int index,
    required int leadingBlankCount,
  }) {
    final firstOfMonth = DateTime.utc(month.year, month.month, 1);
    final dayOffset = index - leadingBlankCount;
    final date = CalendarDateNavigation.tryShiftDays(firstOfMonth, dayOffset);
    return _SolarCalendarCell(
      date: date,
      inCurrentMonth:
          date != null && date.year == month.year && date.month == month.month,
    );
  }
}

class _SolarCalendarCell {
  final DateTime? date;
  final bool inCurrentMonth;

  const _SolarCalendarCell({required this.date, required this.inCurrentMonth});
}

class _WeekdayLabel extends StatelessWidget {
  final String label;
  final String? semanticsLabel;

  const _WeekdayLabel({required this.label, this.semanticsLabel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      label: semanticsLabel,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: cs.primary.withValues(alpha: 0.82),
            fontWeight: FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _SolarDayCell extends StatelessWidget {
  final _SolarCalendarCell cell;
  final DateTime selectedDay;
  final DateTime firstDay;
  final DateTime lastDay;
  final ValueChanged<DateTime> onSelected;
  final double height;

  const _SolarDayCell({
    required this.cell,
    required this.selectedDay,
    required this.firstDay,
    required this.lastDay,
    required this.onSelected,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final cellDate = cell.date;
    if (cellDate == null) {
      return Padding(
        padding: const EdgeInsets.all(3),
        child: Semantics(
          label: CalendarUiCopy.unavailable,
          enabled: false,
          button: false,
          child: Container(height: height, alignment: Alignment.center),
        ),
      );
    }

    final day = DateTime(cellDate.year, cellDate.month, cellDate.day);
    final today = DateTime.now();
    final isToday = _sameDate(day, today);
    final isSelected = _sameDate(day, selectedDay);
    final disabled =
        day.isBefore(_dateOnly(firstDay)) || day.isAfter(_dateOnly(lastDay));
    final isEnabledCurrentMonth = !disabled && cell.inCurrentMonth;
    final currentMonthFill = Color.alphaBlend(
      cs.primary.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.10 : 0.07,
      ),
      cs.surface,
    );
    final todayFill = Color.alphaBlend(
      cs.primary.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.18 : 0.13,
      ),
      cs.surface,
    );
    final selectedFill = Color.alphaBlend(
      cs.primary.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.20 : 0.13,
      ),
      cs.surface,
    );
    final background = isSelected
        ? selectedFill
        : isToday
        ? todayFill
        : isEnabledCurrentMonth
        ? currentMonthFill
        : Colors.transparent;
    final foreground = disabled
        ? cs.onSurface.withValues(alpha: 0.30)
        : isSelected
        ? cs.onSurface
        : isToday
        ? cs.primary
        : cell.inCurrentMonth
        ? cs.onSurface
        : cs.onSurfaceVariant.withValues(alpha: 0.36);
    final border = isSelected
        ? Border.all(color: cs.primary.withValues(alpha: 0.26), width: 0.45)
        : isToday
        ? Border.all(color: cs.primary.withValues(alpha: 0.26), width: 0.45)
        : isEnabledCurrentMonth
        ? Border.all(color: cs.primary.withValues(alpha: 0.14), width: 0.45)
        : null;

    return Padding(
      padding: const EdgeInsets.all(3),
      child: Semantics(
        label: AppDateFormat.date(context, day),
        selected: isSelected,
        enabled: !disabled,
        button: true,
        child: Material(
          key: ValueKey(
            'solar-day-${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
          ),
          color: background,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: disabled ? null : () => onSelected(day),
            child: Container(
              height: height,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: border,
              ),
              child: Text(
                '${day.day}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _LunarPicker extends StatelessWidget {
  final LunarDate lunar;
  final void Function({int? year, int? month, int? day, bool? isLeapMonth})
  onChanged;

  const _LunarPicker({required this.lunar, required this.onChanged});

  static String _yearLabel(int year) => _formatLunarYear(year);

  static String _formatMonth(int month, {bool isLeap = false}) {
    if (I18n.current == AppLocale.zh) {
      return LunarCalendar.monthName(month, isLeap: isLeap);
    }
    final prefix = isLeap
        ? I18n.tr('picker.lunar.leap_month')
        : I18n.tr('picker.lunar.month');
    return '$prefix $month';
  }

  static String _formatDay(int day) {
    if (I18n.current == AppLocale.zh) {
      return LunarCalendar.dayName(day);
    }
    return '${I18n.tr('picker.lunar.day')} $day';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final leapMonth = LunarCalendar.leapMonthOfLunarYear(lunar.year);
    final rawDays = LunarCalendar.daysInLunarMonth(
      lunar.year,
      lunar.month,
      isLeap: lunar.isLeapMonth,
    );
    final maxDays = rawDays > 0
        ? rawDays
        : LunarCalendar.daysInMonth(
            lunar.year,
            lunar.month,
            isLeap: lunar.isLeapMonth,
          );
    final isLeapSelected = lunar.isLeapMonth && leapMonth == lunar.month;
    final leapLabel = I18n.current == AppLocale.zh
        ? '闰月 · ${LunarCalendar.monthName(leapMonth, isLeap: true)}'
        : '${I18n.tr('picker.lunar.leap_month')} $leapMonth';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (leapMonth > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                key: const ValueKey('app_date_picker_leap_month_chip'),
                selected: isLeapSelected,
                label: Text(
                  leapLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: isLeapSelected ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: FontWeight.normal,
                  ),
                ),
                backgroundColor: cs.surface,
                selectedColor: cs.primary.withValues(alpha: 0.12),
                side: BorderSide(
                  color: isLeapSelected
                      ? cs.primary.withValues(alpha: 0.55)
                      : cs.outlineVariant.withValues(alpha: 0.45),
                  width: 0.45,
                ),
                onSelected: (selected) {
                  onChanged(month: leapMonth, isLeapMonth: selected);
                },
              ),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: _NumberWheel(
                value: lunar.year,
                min: 1900,
                max: 2099,
                labelBuilder: _yearLabel,
                onChanged: (v) => onChanged(year: v),
              ),
            ),
            Expanded(
              child: _NumberWheel(
                value: lunar.month,
                min: 1,
                max: 12,
                labelBuilder: (v) =>
                    _formatMonth(v, isLeap: lunar.isLeapMonth && v == lunar.month),
                onChanged: (v) => onChanged(
                  month: v,
                  isLeapMonth: v == leapMonth ? lunar.isLeapMonth : false,
                ),
              ),
            ),
            Expanded(
              child: _NumberWheel(
                value: lunar.day,
                min: 1,
                max: maxDays,
                labelBuilder: _formatDay,
                onChanged: (v) => onChanged(day: v),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NumberWheel extends StatefulWidget {
  final int value;
  final int min;
  final int max;
  final String Function(int value) labelBuilder;
  final ValueChanged<int> onChanged;

  const _NumberWheel({
    required this.value,
    required this.min,
    required this.max,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  State<_NumberWheel> createState() => _NumberWheelState();
}

class _NumberWheelState extends State<_NumberWheel> {
  late FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(
      initialItem: (widget.value - widget.min)
          .clamp(0, widget.max - widget.min)
          .toInt(),
    );
  }

  @override
  void didUpdateWidget(covariant _NumberWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.min != widget.min ||
        oldWidget.max != widget.max) {
      _controller.jumpToItem(
        (widget.value - widget.min).clamp(0, widget.max - widget.min).toInt(),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 190,
      child: ListWheelScrollView.useDelegate(
        controller: _controller,
        itemExtent: 42,
        physics: const FixedExtentScrollPhysics(),
        overAndUnderCenterOpacity: 0.45,
        onSelectedItemChanged: (i) => widget.onChanged(widget.min + i),
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: widget.max - widget.min + 1,
          builder: (context, index) {
            final value = widget.min + index;
            final label = widget.labelBuilder(value);
            return Semantics(
              label: label,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurface),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
