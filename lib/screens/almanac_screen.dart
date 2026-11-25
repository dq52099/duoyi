import 'dart:collection';

import '../widgets/app_date_format.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/almanac_locale_format.dart';
import '../core/almanac_ui_copy.dart';
import '../core/calendar_date_navigation.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/lunar_calendar.dart';
import '../models/anniversary.dart';
import '../models/countdown.dart';
import '../providers/anniversary_provider.dart';
import '../providers/countdown_provider.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/almanac_tools_service.dart';
import '../services/holiday_calendar.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/surface_components.dart';
import '../widgets/brand_background.dart' show LocaleStatePreservingRoute;
import '../widgets/controller_dialog.dart' show showControllerDialog;
import 'almanac_tools_screen.dart';

enum AlmanacEntryMode { calendar, almanac }

/// 统一万年历与万年历工具共用的明/暗色语义调色板。
abstract final class AlmanacPalette {
  static const Color paperGold = Color(0xFFB39162);
  static const Color lightScaffoldBackground = Color(0xFFFFFEFC);

  static Color goldInk({required bool isDark}) =>
      isDark ? const Color(0xFFDEBE8F) : const Color(0xFF745A34);

  static Color huangDaoInk({required bool isDark}) =>
      isDark ? const Color(0xFFDEBE8F) : const Color(0xFF8B6520);

  static Color auspiciousGreen({required bool isDark}) =>
      isDark ? const Color(0xFF81C784) : const Color(0xFF1B5E20);

  static Color inauspiciousRed({required bool isDark}) =>
      isDark ? const Color(0xFFE57373) : const Color(0xFFB71C1C);

  static Color termGreen({required bool isDark}) =>
      isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);

  static Color highlightTermGreen({required bool isDark}) =>
      isDark ? const Color(0xFF81C784) : const Color(0xFF43A047);

  static Color solarFestivalAmber({required bool isDark}) =>
      isDark ? const Color(0xFFFFB74D) : const Color(0xFFEF6C00);

  static Color lunarFestivalRose({required bool isDark}) =>
      isDark ? const Color(0xFFF48FB1) : const Color(0xFFC2185B);

  static Color holidayTeal({required bool isDark}) =>
      isDark ? const Color(0xFF4DB6AC) : const Color(0xFF00897B);

  static Color makeupIndigo({required bool isDark}) =>
      isDark ? const Color(0xFFB39DDB) : const Color(0xFF5E35B1);

  static Color huangDaoAmber({required bool isDark}) =>
      isDark ? const Color(0xFFFFCC80) : const Color(0xFF9E6B24);

  static Color workdayBlue({required bool isDark}) =>
      isDark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0);

  static Color sanFuOrange({required bool isDark}) =>
      isDark ? const Color(0xFFFFAB91) : const Color(0xFFD84315);

  static Color restRed({required bool isDark}) =>
      isDark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828);

  static Color birthdayPink({required bool isDark}) =>
      isDark ? const Color(0xFFF48FB1) : const Color(0xFFD81B60);

  static Color memorialRed({required bool isDark}) =>
      isDark ? const Color(0xFFE57373) : const Color(0xFFE53935);

  static Color customIndigo({required bool isDark}) =>
      isDark ? const Color(0xFF9FA8DA) : const Color(0xFF3949AB);

  static Color adapt(Color base, {required bool isDark}) {
    if (!isDark) return base;
    return switch (base.toARGB32()) {
      0xFF2E7D32 || 0xFF1B5E20 || 0xFF43A047 => const Color(0xFF81C784),
      0xFFEF6C00 => const Color(0xFFFFB74D),
      0xFFC2185B || 0xFFE91E63 || 0xFFD81B60 => const Color(0xFFF48FB1),
      0xFF00897B => const Color(0xFF4DB6AC),
      0xFF5E35B1 => const Color(0xFFB39DDB),
      0xFF9E6B24 => const Color(0xFFFFCC80),
      0xFF1565C0 => const Color(0xFF90CAF9),
      0xFFD84315 || 0xFFBF360C => const Color(0xFFFFAB91),
      0xFFC62828 => const Color(0xFFEF9A9A),
      0xFFE53935 => const Color(0xFFE57373),
      0xFF3949AB => const Color(0xFF9FA8DA),
      _ => base,
    };
  }
}

/// 万年历页面。保留 `almanac` 枚举用于兼容旧深链/测试，入口统一展示万年历。
class AlmanacScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  final DateTime? initialDate;
  final AlmanacEntryMode initialMode;
  final int? accountGeneration;

  const AlmanacScreen({
    super.key,
    this.initialDate,
    this.initialMode = AlmanacEntryMode.calendar,
    this.accountGeneration,
  });

  @override
  State<AlmanacScreen> createState() => _AlmanacScreenState();
}

class _AlmanacScreenState extends State<AlmanacScreen> {
  static final DateTime _firstSupportedDate = DateTime(1900);
  static final DateTime _lastSupportedDate = DateTime(2099, 12, 31);

  late DateTime _date;
  late int _accountGeneration;
  final Map<String, _MonthCalendarData> _monthDataCache =
      <String, _MonthCalendarData>{};
  final Map<String, List<_MonthHighlight>> _fixedMonthHighlightCache =
      <String, List<_MonthHighlight>>{};

  @override
  void initState() {
    super.initState();
    _date = _clampDate(widget.initialDate ?? DateTime.now());
    _accountGeneration =
        widget.accountGeneration ??
        AccountLocalDataCleaner.accountDataGeneration;
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _onAccountDataGenerationChanged,
    );
    I18n.localeListenable.addListener(_onLocaleChanged);
  }

  void _onAccountDataGenerationChanged() {
    if (!mounted) return;
    _accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    _fixedMonthHighlightCache.clear();
    setState(() {});
  }

  void _onLocaleChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _onAccountDataGenerationChanged,
    );
    super.dispose();
  }

  DateTime _clampDate(DateTime value) {
    final day = DateTime(value.year, value.month, value.day);
    if (day.isBefore(_firstSupportedDate)) return _firstSupportedDate;
    if (day.isAfter(_lastSupportedDate)) return _lastSupportedDate;
    return day;
  }

  Future<void> _pickDate() async {
    final originGeneration = _accountGeneration;
    final picked = await AppDatePicker.pickSolar(
      context,
      initialDate: _clampDate(_date),
      firstDate: _firstSupportedDate,
      lastDate: _lastSupportedDate,
      titleKey: 'today.almanac.title',
    );
    if (!mounted ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          originGeneration,
        ) ||
        originGeneration != _accountGeneration) {
      return;
    }
    if (picked != null) setState(() => _date = _clampDate(picked));
  }

  void _goToday() {
    final today = _clampDate(DateTime.now());
    final alreadyToday =
        _date.year == today.year &&
        _date.month == today.month &&
        _date.day == today.day;
    if (!alreadyToday) {
      setState(() => _date = today);
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, locale, _) => Text(
            AlmanacUiCopy.goTodayFeedback(
              alreadyToday: alreadyToday,
              locale: locale,
            ),
          ),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _shiftMonth(int months) {
    final target = CalendarDateNavigation.tryShiftMonths(_date, months);
    if (target != null) {
      setState(() => _date = _clampDate(target));
    }
  }

  void _shiftDay(int days) {
    final target = CalendarDateNavigation.tryShiftDays(_date, days);
    if (target != null) {
      setState(() => _date = _clampDate(target));
    }
  }

  void _showSelectedDateDetail() {
    _openAlmanacDetail(_date);
  }

  void _onDatePicked(DateTime date) {
    final selectedDate = _clampDate(date);
    setState(() => _date = selectedDate);
  }

  Future<void> _openAlmanacDetail(DateTime selectedDate) async {
    final originGeneration = _accountGeneration;
    final returnedDate = await Navigator.of(context).push<DateTime?>(
      MaterialPageRoute<DateTime?>(
        builder: (_) => _AlmanacDetailPage(
          date: selectedDate,
          originAccountGeneration: originGeneration,
        ),
      ),
    );
    if (!mounted ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          originGeneration,
        ) ||
        originGeneration != _accountGeneration ||
        returnedDate == null) {
      return;
    }
    setState(() => _date = _clampDate(returnedDate));
  }

  void _openToolsTab(int tabIndex, {String? activity}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlmanacToolsScreen(
          initialTab: tabIndex,
          initialDate: _date,
          initialActivity: activity,
        ),
      ),
    );
  }

  _MonthCalendarData _monthDataFor(DateTime month) {
    final key = '${month.year}-${month.month}';
    return _monthDataCache.putIfAbsent(
      key,
      () => _MonthCalendarData.fromMonth(month),
    );
  }

  List<_MonthHighlight> _monthHighlightsFor({
    required DateTime month,
    required Iterable<CountdownItem> countdowns,
    required Iterable<Anniversary> anniversaries,
  }) {
    final key = '${I18n.current.name}-${month.year}-${month.month}';
    final fixed = _fixedMonthHighlightCache.putIfAbsent(
      key,
      () => _buildFixedMonthHighlights(monthData: _monthDataFor(month)),
    );
    return _mergeMonthHighlights([
      ...fixed,
      ..._buildUserMonthHighlights(
        month: month,
        countdowns: countdowns,
        anniversaries: anniversaries,
      ),
    ]);
  }

  static String? _safeSolarTerm(DateTime date) {
    try {
      return LunarCalendar.solarTerm(date);
    } catch (_) {
      return null;
    }
  }

  List<(String, Color)> _dateBadges({
    required bool isDark,
    required String? term,
    required String? solarFestival,
    required String? lunarFestival,
    required bool isHoliday,
    required bool isWorkMakeupDay,
  }) {
    return <(String, Color)>[
      if (term != null)
        (AlmanacUiCopy.termBadge(term), AlmanacPalette.termGreen(isDark: isDark)),
      if (solarFestival != null)
        (
          AlmanacUiCopy.solarFestivalBadge(solarFestival),
          AlmanacPalette.solarFestivalAmber(isDark: isDark),
        ),
      if (lunarFestival != null)
        (
          AlmanacUiCopy.lunarFestivalBadge(lunarFestival),
          AlmanacPalette.lunarFestivalRose(isDark: isDark),
        ),
      if (isHoliday)
        (AlmanacUiCopy.holidayBadge, AlmanacPalette.holidayTeal(isDark: isDark)),
      if (isWorkMakeupDay)
        (
          AlmanacUiCopy.makeupWorkdayBadge,
          AlmanacPalette.makeupIndigo(isDark: isDark),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageTitle = AlmanacUiCopy.pageTitle;
    final selectedDate = _date;
    final almanacDetail = LunarCalendar.tryAlmanacDetail(selectedDate);
    final lunar =
        almanacDetail?.lunarDate ?? LunarCalendar.tryFromSolar(selectedDate);
    final term = _safeSolarTerm(selectedDate);
    final solarFes = LunarCalendar.solarFestival(selectedDate);
    final lunarFes = lunar != null ? LunarCalendar.lunarFestival(lunar) : null;
    final isHoliday = HolidayCalendar.isHoliday(selectedDate);
    final isWorkMakeupDay = HolidayCalendar.isWorkMakeupDay(selectedDate);
    final dateBadges = _dateBadges(
      isDark: isDark,
      term: term,
      solarFestival: solarFes,
      lunarFestival: lunarFes,
      isHoliday: isHoliday,
      isWorkMakeupDay: isWorkMakeupDay,
    );
    final countdownProvider = context.watch<CountdownProvider?>();
    final anniversaryProvider = context.watch<AnniversaryProvider?>();
    final monthData = _monthDataFor(selectedDate);
    final monthHighlights = _monthHighlightsFor(
      month: selectedDate,
      countdowns: countdownProvider?.items ?? const <CountdownItem>[],
      anniversaries: anniversaryProvider?.items ?? const <Anniversary>[],
    );
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final routeBackground = theme.brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;

    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: Text(pageTitle),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        centerTitle: false,
        titleSpacing: 4,
        leadingWidth: 44,
        toolbarHeight:
            (MediaQuery.textScalerOf(context).scale(20.0) + 36.0) > 56.0
            ? (MediaQuery.textScalerOf(context).scale(20.0) + 36.0)
            : 56.0,
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: AlmanacUiCopy.previousDayTooltip,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
            onPressed: _date == _firstSupportedDate
                ? null
                : () => _shiftDay(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: AlmanacUiCopy.nextDayTooltip,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
            onPressed: _date == _lastSupportedDate ? null : () => _shiftDay(1),
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: AlmanacUiCopy.todayTooltip,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
            onPressed: _goToday,
            icon: const Icon(Icons.today_outlined),
          ),
        ],
      ),
      body: ColoredBox(
        color: routeBackground.withValues(alpha: 0.92),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 940;
            final monthCalendar = _MonthCalendar(
              date: selectedDate,
              monthData: monthData,
              highlights: monthHighlights,
              onPick: _onDatePicked,
              onPreviousMonth: () => _shiftMonth(-1),
              onNextMonth: () => _shiftMonth(1),
              onTitleTap: _pickDate,
            );
            final quickToolsBar = _AlmanacQuickToolsBar(
              onSelectTab: _openToolsTab,
            );
            final summary = _SelectedDateSummaryCard(
              detail: almanacDetail,
              selectedDate: selectedDate,
              badges: dateBadges,
              onOpenAlmanac: _showSelectedDateDetail,
            );
            final highlights = _MonthHighlightsCard(
              selectedDate: selectedDate,
              highlights: monthHighlights,
              onSelectDate: _onDatePicked,
            );
            return Scrollbar(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  wide ? 24 : 14,
                  6,
                  wide ? 24 : 14,
                  22 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        monthCalendar,
                        SizedBox(height: wide ? 14 : 10),
                        summary,
                        SizedBox(height: wide ? 12 : 10),
                        quickToolsBar,
                        SizedBox(height: wide ? 18 : 14),
                        highlights,
                      ],
                    ),
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

class _MonthCalendarData {
  final int year;
  final int month;
  final int daysInMonth;
  final int firstWeekdayOffset;
  final int rowCount;
  final List<_MonthDayData> days;

  const _MonthCalendarData({
    required this.year,
    required this.month,
    required this.daysInMonth,
    required this.firstWeekdayOffset,
    required this.rowCount,
    required this.days,
  });

  factory _MonthCalendarData.fromMonth(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    final offset = (first.weekday - 1) % 7; // 周一为 0
    final totalDays = last.day;
    final civilDays = CalendarDateNavigation.daysFrom(first, totalDays);
    final days = <_MonthDayData>[];

    for (var i = 0; i < totalDays; i++) {
      final dayNumber = i + 1;
      final day = civilDays.length > i ? civilDays[i] : null;
      if (day == null) {
        days.add(
          _MonthDayData(
            date: null,
            day: dayNumber,
            lunar: null,
            term: null,
            solarFestival: null,
            lunarFestival: null,
            isWeekend: false,
            isHoliday: false,
            isWorkMakeupDay: false,
          ),
        );
        continue;
      }
      final lunar = LunarCalendar.tryFromSolar(day);
      final term = _AlmanacScreenState._safeSolarTerm(day);
      final solarFestival = LunarCalendar.solarFestival(day);
      final lunarFestival = lunar != null
          ? LunarCalendar.lunarFestival(lunar)
          : null;
      days.add(
        _MonthDayData(
          date: day,
          day: day.day,
          lunar: lunar,
          term: term,
          solarFestival: solarFestival,
          lunarFestival: lunarFestival,
          isWeekend: day.weekday >= DateTime.saturday,
          isHoliday: HolidayCalendar.isHoliday(day),
          isWorkMakeupDay: HolidayCalendar.isWorkMakeupDay(day),
        ),
      );
    }
    return _MonthCalendarData(
      year: month.year,
      month: month.month,
      daysInMonth: last.day,
      firstWeekdayOffset: offset,
      rowCount: ((last.day + offset) / 7).ceil(),
      days: List.unmodifiable(days),
    );
  }

  _MonthDayData? dayAt(int day) {
    if (day < 1 || day > daysInMonth) return null;
    return days[day - 1];
  }
}

class _MonthDayData {
  final DateTime? date;
  final int day;
  final String? explicitLabel;
  final LunarDate? lunar;
  final String? term;
  final String? solarFestival;
  final String? lunarFestival;
  final bool isWeekend;
  final bool isHoliday;
  final bool isWorkMakeupDay;

  const _MonthDayData({
    required this.date,
    required this.day,
    String? label,
    this.lunar,
    required this.term,
    required this.solarFestival,
    required this.lunarFestival,
    required this.isWeekend,
    required this.isHoliday,
    required this.isWorkMakeupDay,
  }) : explicitLabel = label;

  bool get isAvailable => date != null;

  String get label {
    if (explicitLabel != null) return explicitLabel!;
    if (term != null) {
      return AlmanacLocaleFormat.formatSolarTerm(term) ?? term!;
    }
    if (solarFestival != null) {
      return AlmanacLocaleFormat.formatFestival(solarFestival) ??
          solarFestival!;
    }
    if (lunarFestival != null) {
      return AlmanacLocaleFormat.formatFestival(lunarFestival) ??
          lunarFestival!;
    }
    if (I18n.current == AppLocale.zh && lunar != null) {
      return lunar!.shortDayOrMonth;
    }
    return '';
  }
}

List<_MonthHighlight> _buildFixedMonthHighlights({
  required _MonthCalendarData monthData,
}) {
  final labelsByDay = <int, List<_HighlightLabel>>{};

  void add(_MonthDayData day, String label, IconData icon, Color color) {
    labelsByDay
        .putIfAbsent(day.day, () => <_HighlightLabel>[])
        .add(_HighlightLabel(label: label, icon: icon, color: color));
  }

  for (final day in monthData.days) {
    if (day.date == null) continue;
    final term = day.term;
    final solarFestival = day.solarFestival;
    final lunarFestival = day.lunarFestival;
    if (term != null) {
      add(
        day,
        AlmanacUiCopy.termHighlight(term),
        Icons.eco_outlined,
        AlmanacPalette.highlightTermGreen(isDark: false),
      );
    }
    if (solarFestival != null) {
      add(
        day,
        AlmanacUiCopy.solarFestivalHighlight(solarFestival),
        Icons.celebration_outlined,
        AlmanacPalette.solarFestivalAmber(isDark: false),
      );
    }
    if (lunarFestival != null) {
      add(
        day,
        AlmanacUiCopy.lunarFestivalHighlight(lunarFestival),
        Icons.local_florist_outlined,
        const Color(0xFFE91E63),
      );
    }
    if (day.isHoliday) {
      add(
        day,
        AlmanacUiCopy.holidayBadge,
        Icons.beach_access_outlined,
        AlmanacPalette.holidayTeal(isDark: false),
      );
    }
    if (day.isWorkMakeupDay) {
      add(
        day,
        AlmanacUiCopy.makeupWorkdayBadge,
        Icons.work_outline,
        AlmanacPalette.makeupIndigo(isDark: false),
      );
    }
  }

  return _highlightsFromLabels(
    year: monthData.year,
    month: monthData.month,
    labelsByDay: labelsByDay,
  );
}

List<_MonthHighlight> _buildUserMonthHighlights({
  required DateTime month,
  required Iterable<CountdownItem> countdowns,
  required Iterable<Anniversary> anniversaries,
}) {
  final first = DateTime(month.year, month.month, 1);
  final labelsByDay = <int, List<_HighlightLabel>>{};

  void add(DateTime date, String label, IconData icon, Color color) {
    if (date.year != month.year || date.month != month.month) return;
    labelsByDay
        .putIfAbsent(date.day, () => <_HighlightLabel>[])
        .add(_HighlightLabel(label: label, icon: icon, color: color));
  }

  for (final item in countdowns) {
    add(
      item.targetDate,
      AlmanacUiCopy.countdownHighlight(item.title),
      Icons.hourglass_bottom_outlined,
      AlmanacPalette.makeupIndigo(isDark: false),
    );
  }

  for (final item in anniversaries) {
    final occurrence = _anniversaryOccurrenceInMonth(
      item,
      month.year,
      month.month,
    );
    if (occurrence == null) continue;
    final (label, icon, color) = switch (item.type) {
      AnniversaryType.birthday => (
        AlmanacUiCopy.birthdayHighlight(item.title),
        Icons.cake_outlined,
        AlmanacPalette.birthdayPink(isDark: false),
      ),
      AnniversaryType.memorial => (
        AlmanacUiCopy.memorialHighlight(item.title),
        Icons.favorite_border,
        AlmanacPalette.memorialRed(isDark: false),
      ),
      AnniversaryType.custom => (
        AlmanacUiCopy.memorialHighlight(item.title),
        Icons.event_available_outlined,
        AlmanacPalette.customIndigo(isDark: false),
      ),
      AnniversaryType.normal => (
        AlmanacUiCopy.countdownHighlight(item.title),
        Icons.hourglass_bottom_outlined,
        AlmanacPalette.makeupIndigo(isDark: false),
      ),
    };
    add(occurrence, label, icon, color);
  }

  return _highlightsFromLabels(
    year: first.year,
    month: first.month,
    labelsByDay: labelsByDay,
  );
}

List<_MonthHighlight> _mergeMonthHighlights(List<_MonthHighlight> highlights) {
  final labelsByDay = <int, List<_HighlightLabel>>{};
  for (final highlight in highlights) {
    labelsByDay
        .putIfAbsent(highlight.date.day, () => <_HighlightLabel>[])
        .addAll(highlight.labels);
  }
  if (highlights.isEmpty) return const <_MonthHighlight>[];
  final sample = highlights.first.date;
  return _highlightsFromLabels(
    year: sample.year,
    month: sample.month,
    labelsByDay: labelsByDay,
  );
}

List<_MonthHighlight> _highlightsFromLabels({
  required int year,
  required int month,
  required Map<int, List<_HighlightLabel>> labelsByDay,
}) {
  final highlights = labelsByDay.entries.map((entry) {
    return _MonthHighlight(
      date: DateTime(year, month, entry.key),
      labels: entry.value,
    );
  }).toList();
  highlights.sort((a, b) => a.date.compareTo(b.date));
  return highlights;
}

DateTime? _anniversaryOccurrenceInMonth(Anniversary item, int year, int month) {
  if (item.type == AnniversaryType.normal) {
    return _isSameMonth(item.originDate, year, month) ? item.originDate : null;
  }
  if (item.calendarType == AnniversaryCalendarType.lunar) {
    final lunarMonth = item.lunarMonth;
    final lunarDay = item.lunarDay;
    if (lunarMonth == null || lunarDay == null) return null;
    try {
      final solar = LunarCalendar.toSolar(
        year,
        lunarMonth,
        lunarDay,
        isLeap: item.lunarIsLeap,
      );
      return _isSameMonth(solar, year, month) ? solar : null;
    } catch (_) {
      return null;
    }
  }
  final solar = DateTime(year, item.originDate.month, item.originDate.day);
  if (solar.month != item.originDate.month ||
      solar.day != item.originDate.day) {
    return null;
  }
  return _isSameMonth(solar, year, month) ? solar : null;
}

bool _isSameMonth(DateTime date, int year, int month) =>
    date.year == year && date.month == month;

class _HighlightLabel {
  final String label;
  final IconData icon;
  final Color color;

  const _HighlightLabel({
    required this.label,
    required this.icon,
    required this.color,
  });
}

class _MonthHighlight {
  final DateTime date;
  final List<_HighlightLabel> labels;

  const _MonthHighlight({required this.date, required this.labels});
}

class _AlmanacQuickToolsBar extends StatelessWidget {
  final ValueChanged<int> onSelectTab;

  const _AlmanacQuickToolsBar({required this.onSelectTab});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = <(int tab, IconData icon, String label)>[
      (0, Icons.auto_awesome_outlined, AlmanacUiCopy.tabAuspiciousPicker),
      (1, Icons.beach_access_outlined, AlmanacUiCopy.tabHolidaySchedule),
      (2, Icons.calculate_outlined, AlmanacUiCopy.tabDateTools),
      (3, Icons.timeline_rounded, AlmanacUiCopy.tabSolarTermsBazi),
    ];
    return SingleChildScrollView(
      key: const ValueKey('almanac_quick_tools_bar'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            ActionChip(
              key: ValueKey('almanac_quick_tool_chip_${items[i].$1}'),
              avatar: Icon(items[i].$2, size: 15, color: cs.primary),
              label: Text(
                items[i].$3,
                style: appSecondaryControlLabelStyle(context).copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.normal,
                ),
              ),
              backgroundColor: Color.alphaBlend(
                cs.primary.withValues(alpha: 0.05),
                cs.surface,
              ),
              side: BorderSide(
                color: cs.primary.withValues(alpha: 0.18),
                width: 0.45,
              ),
              onPressed: () => onSelectTab(items[i].$1),
            ),
          ],
        ],
      ),
    );
  }
}

class _MonthHighlightsCard extends StatefulWidget {
  final DateTime selectedDate;
  final List<_MonthHighlight> highlights;
  final ValueChanged<DateTime>? onSelectDate;

  const _MonthHighlightsCard({
    required this.selectedDate,
    required this.highlights,
    this.onSelectDate,
  });

  @override
  State<_MonthHighlightsCard> createState() => _MonthHighlightsCardState();
}

class _MonthHighlightsCardState extends State<_MonthHighlightsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final highlights = widget.highlights;
    final selectedDate = widget.selectedDate;
    final visibleHighlights =
        _expanded ? highlights : highlights.take(12).toList(growable: false);

    final surfaceStyle = appSurfaceStyleOf(context);
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      borderRadius: BorderRadius.circular(
        surfaceStyle?.cardRadius ?? DesignTokens.radiusCard,
      ),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(
            cs.primary.withValues(alpha: isDark ? 0.050 : 0.026),
            cs.surface,
          ),
          cs.surface,
        ],
      ),
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: isDark ? 0.14 : 0.18),
        width: 0.55,
      ),
      elevation: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 3,
                    height: 14,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusPill,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      AlmanacUiCopy.monthHighlightsTitle,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.normal,
                        color: cs.onSurface.withValues(
                          alpha: isDark ? 0.88 : 0.80,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                AlmanacUiCopy.monthBadge(selectedDate.month),
                style: appSecondaryControlLabelStyle(context).copyWith(
                  color: cs.onSurface.withValues(alpha: isDark ? 0.88 : 0.80),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (highlights.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.16),
                    width: 0.45,
                  ),
                ),
              ),
              child: Text(
                AlmanacUiCopy.monthHighlightsEmpty,
                style: appSecondaryControlTextStyle(
                  context,
                ).copyWith(color: cs.onSurface.withValues(alpha: 0.62)),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.14),
                    width: 0.45,
                  ),
                ),
              ),
              child: Column(
                children: visibleHighlights
                    .map(
                      (highlight) => InkWell(
                        key: ValueKey(
                          'month_highlight_row_${highlight.date.year}_${highlight.date.month}_${highlight.date.day}',
                        ),
                        borderRadius: BorderRadius.circular(8),
                        onTap: widget.onSelectDate == null
                            ? null
                            : () => widget.onSelectDate!(highlight.date),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 7,
                            horizontal: 2,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width:
                                    (MediaQuery.textScalerOf(
                                              context,
                                            ).scale(13.0) *
                                            2.4) >
                                        34.0
                                    ? (MediaQuery.textScalerOf(
                                            context,
                                          ).scale(13.0) *
                                          2.4)
                                    : 34.0,
                                child: Text(
                                  '${highlight.date.day}',
                                  style: appSecondaryControlTextStyle(context)
                                      .copyWith(
                                        fontSize: 13,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                        color:
                                            highlight.date.day ==
                                                selectedDate.day
                                            ? cs.primary
                                            : cs.onSurface.withValues(
                                                alpha: isDark ? 0.88 : 0.78,
                                              ),
                                      ),
                                ),
                              ),
                              Expanded(
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: highlight.labels
                                      .take(3)
                                      .map(
                                        (label) =>
                                            _SoftAlmanacTag(label: label),
                                      )
                                      .toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          if (highlights.length > 12)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (!_expanded)
                    Text(
                      AlmanacUiCopy.moreHighlights(highlights.length - 12),
                      style: appSecondaryControlLabelStyle(
                        context,
                      ).copyWith(color: cs.onSurface.withValues(alpha: 0.52)),
                    ),
                  InkWell(
                    key: const ValueKey('month_highlights_expand_toggle'),
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        _expanded
                            ? AlmanacUiCopy.collapseTerms
                            : AlmanacUiCopy.expandAllTerms,
                        style: appSecondaryControlLabelStyle(
                          context,
                        ).copyWith(color: cs.primary),
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
}

class _SoftAlmanacTag extends StatelessWidget {
  final _HighlightLabel label;

  const _SoftAlmanacTag({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final adapted = AlmanacPalette.adapt(label.color, isDark: isDark);
    final color = Color.lerp(adapted, cs.onSurface, 0.28) ?? adapted;
    final pillBg = Color.alphaBlend(color.withValues(alpha: 0.08), cs.surface);
    final iconColor = appReadableForeground(
      pillBg,
      color.withValues(alpha: isDark ? 0.92 : 0.82),
    );
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxTagWidth = (screenWidth - 86.0) > 160.0
        ? (screenWidth - 86.0)
        : 160.0;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxTagWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.12), width: 0.45),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(label.icon, size: 12, color: iconColor),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label.label,
                softWrap: true,
                style: appSecondaryControlLabelStyle(context).copyWith(
                  color: cs.onSurface.withValues(alpha: isDark ? 0.88 : 0.78),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedDateSummaryCard extends StatelessWidget {
  final LunarAlmanacDetail? detail;
  final DateTime selectedDate;
  final List<(String, Color)> badges;
  final VoidCallback onOpenAlmanac;

  const _SelectedDateSummaryCard({
    required this.detail,
    required this.selectedDate,
    required this.badges,
    required this.onOpenAlmanac,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = Color.alphaBlend(
      cs.primary.withValues(alpha: isDark ? 0.08 : 0.045),
      cs.surface,
    );
    final lunar = detail?.lunarDate ?? LunarCalendar.tryFromSolar(selectedDate);
    final lunarTitle = lunar != null
        ? AlmanacLocaleFormat.formatLunarDate(lunar)
        : AlmanacUiCopy.lunarUnavailable;
    final ganzhiSubtitle = detail != null
        ? _spacedGanzhiLine(detail!.ganzhiLine)
        : AlmanacUiCopy.almanacUnavailable;
    final suitableText = detail != null
        ? (AlmanacLocaleFormat.isEn
              ? AlmanacLocaleFormat.formatActivitiesPreview(
                  detail!.suitable,
                  maxTerms: 6,
                )
              : _summaryTerms(detail!.suitable))
        : AlmanacUiCopy.unavailable;
    final avoidText = detail != null
        ? (AlmanacLocaleFormat.isEn
              ? AlmanacLocaleFormat.formatActivitiesPreview(
                  detail!.avoid,
                  maxTerms: 6,
                )
              : _summaryTerms(detail!.avoid))
        : AlmanacUiCopy.unavailable;

    final surfaceStyle = appSurfaceStyleOf(context);
    return Material(
      key: const ValueKey('selected_date_almanac_summary_card'),
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          surfaceStyle?.cardRadius ?? DesignTokens.radiusCard,
        ),
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: isDark ? 0.14 : 0.18),
          width: 0.55,
        ),
      ),
      elevation: isDark ? 0 : 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: AlmanacUiCopy.viewAlmanacDetail,
        child: Tooltip(
          message: AlmanacUiCopy.viewAlmanacDetail,
          child: InkWell(
            onTap: onOpenAlmanac,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lunarTitle,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontSize: 16,
                                    fontWeight: FontWeight.normal,
                                    color: cs.onSurface,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              ganzhiSubtitle,
                              style: appSecondaryControlTextStyle(context)
                                  .copyWith(
                                    color: cs.onSurface.withValues(
                                      alpha: isDark ? 0.88 : 0.76,
                                    ),
                                    height: 1.25,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: cs.onSurface.withValues(alpha: 0.42),
                      ),
                    ],
                  ),
                  if (detail != null || badges.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (detail != null) ...[
                          _AlmanacBadge(
                            text: AlmanacUiCopy.isoWeekBadge(
                              detail!.isoWeekNumber,
                            ),
                            color: cs.primary,
                            surfaceColor: bg,
                          ),
                          if (detail!.xingZuo.isNotEmpty)
                            _AlmanacBadge(
                              text: AlmanacLocaleFormat.formatXingZuo(
                                detail!.xingZuo,
                              ),
                              color: cs.secondary,
                              surfaceColor: bg,
                            ),
                          if (detail!.tianShen.isNotEmpty)
                            _AlmanacBadge(
                              text:
                                  '${AlmanacLocaleFormat.formatTianShen(detail!.tianShen)} · ${detail!.isHuangDao ? AlmanacUiCopy.huangDaoLabel : AlmanacUiCopy.heiDaoLabel}',
                              color: detail!.isHuangDao
                                  ? AlmanacPalette.huangDaoAmber(isDark: isDark)
                                  : cs.onSurfaceVariant,
                              surfaceColor: bg,
                            ),
                        ],
                        for (final badge in badges)
                          _AlmanacBadge(
                            text: badge.$1,
                            color: badge.$2,
                            surfaceColor: bg,
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surface.withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark
                            ? 0.32
                            : 0.62,
                      ),
                      borderRadius: BorderRadius.circular(
                        surfaceStyle?.smallTileRadius ??
                            DesignTokens.radiusControl,
                      ),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.14),
                        width: 0.45,
                      ),
                    ),
                    child: Column(
                      children: [
                        _SummaryYijiLine(
                          label: AlmanacUiCopy.auspiciousLabel,
                          text: suitableText,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Divider(
                            height: 1,
                            thickness: 0.45,
                            color: cs.outlineVariant.withValues(alpha: 0.20),
                          ),
                        ),
                        _SummaryYijiLine(
                          label: AlmanacUiCopy.inauspiciousLabel,
                          text: avoidText,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryYijiLine extends StatelessWidget {
  final String label;
  final String text;

  const _SummaryYijiLine({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAuspicious = label == '宜' || label == 'Fit';
    final badgeColor = isAuspicious
        ? AlmanacPalette.auspiciousGreen(isDark: isDark)
        : AlmanacPalette.inauspiciousRed(isDark: isDark);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 26, minHeight: 20),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: badgeColor,
              fontSize: 12,
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: appSecondaryControlTextStyle(context).copyWith(
              color: cs.onSurface.withValues(alpha: isDark ? 0.88 : 0.80),
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _AlmanacDetailPage extends StatefulWidget {
  final DateTime date;
  final int? originAccountGeneration;

  const _AlmanacDetailPage({required this.date, this.originAccountGeneration});

  @override
  State<_AlmanacDetailPage> createState() => _AlmanacDetailPageState();
}

class _AlmanacDetailPageState extends State<_AlmanacDetailPage> {
  static final DateTime _firstSupportedDate = DateTime(1900);
  static final DateTime _lastSupportedDate = DateTime(2099, 12, 31);
  late final PageController _pageController;
  late int _currentPage;
  DateTime? _selectedDate;
  late final int _originAccountGeneration;
  final Map<int, LunarAlmanacDetail?> _detailCache =
      <int, LunarAlmanacDetail?>{};
  bool _allowPopWithResult = false;

  @override
  void initState() {
    super.initState();
    _originAccountGeneration =
        widget.originAccountGeneration ??
        AccountLocalDataCleaner.accountDataGeneration;
    _selectedDate = _clampDate(widget.date);
    _currentPage = _pageForDate(_selectedDate!);
    _pageController = PageController(initialPage: _currentPage);
    I18n.localeListenable.addListener(_onLocaleChanged);
  }

  void _onLocaleChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    _pageController.dispose();
    super.dispose();
  }

  DateTime _clampDate(DateTime value) {
    final day = _dateOnly(value);
    if (day.isBefore(_firstSupportedDate)) return _firstSupportedDate;
    if (day.isAfter(_lastSupportedDate)) return _lastSupportedDate;
    return day;
  }

  int get _pageCount =>
      DateTime.utc(2099, 12, 31).difference(DateTime.utc(1900, 1, 1)).inDays +
      1;

  int _pageForDate(DateTime date) {
    final clamped = _clampDate(date);
    return DateTime.utc(
      clamped.year,
      clamped.month,
      clamped.day,
    ).difference(DateTime.utc(1900, 1, 1)).inDays;
  }

  DateTime? _dateForPage(int page) {
    return CalendarDateNavigation.tryShiftDays(_firstSupportedDate, page);
  }

  DateTime _gregorianDateForPage(int page) {
    return DateTime.utc(1900, 1, 1).add(Duration(days: page));
  }

  LunarAlmanacDetail? _detailFor(DateTime date) {
    final day = _dateOnly(date);
    final key = day.year * 10000 + day.month * 100 + day.day;
    return _detailCache.putIfAbsent(
      key,
      () => LunarCalendar.tryAlmanacDetail(day),
    );
  }

  void _popWithCurrentDate() {
    if (_allowPopWithResult) return;
    final ownedRoute = ModalRoute.of(context);
    setState(() => _allowPopWithResult = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ownedRoute != null && !ownedRoute.isCurrent) {
        // A covering route (e.g. dialog, picker, sheet) is currently top-most.
        // Do not pop the covering route; leave detail route open and reset flag.
        setState(() => _allowPopWithResult = false);
        return;
      }
      if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
        _originAccountGeneration,
      )) {
        Navigator.of(context).pop();
        return;
      }
      Navigator.of(context).pop(_selectedDate);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final pageBackground = isDark
        ? Color.alphaBlend(
            AlmanacPalette.paperGold.withValues(alpha: 0.05),
            cs.surface,
          )
        : AlmanacPalette.lightScaffoldBackground;
    final title = _selectedDate != null
        ? AlmanacUiCopy.fullDateTitle(
            _selectedDate!,
            null,
            AppDateFormat.patternOf(context),
          )
        : AlmanacUiCopy.skippedDateFullTitle(
            _gregorianDateForPage(_currentPage),
            null,
            AppDateFormat.patternOf(context),
          );

    return PopScope<DateTime?>(
      canPop: _allowPopWithResult,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _popWithCurrentDate();
      },
      child: Scaffold(
        backgroundColor: pageBackground,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(() {
            final textScaler = MediaQuery.textScalerOf(context);
            if (textScaler.scale(1.0) <= 1.05) {
              return 56.0;
            }
            final width = MediaQuery.sizeOf(context).width;
            final availableWidth = (width - 120.0).clamp(40.0, double.infinity);
            final titleStyle =
                Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.normal,
                  letterSpacing: 0,
                ) ??
                const TextStyle(fontSize: 18, fontWeight: FontWeight.normal);
            final size = _measureAlmanacTextSize(
              context: context,
              text: title,
              style: titleStyle,
              textScaler: textScaler,
              textDirection: Directionality.of(context),
              maxWidth: availableWidth,
            );
            final h = size.height + 24.0;
            return h > 56.0 ? h : 56.0;
          }()),
          child: _AlmanacDetailNavBar(
            title: title,
            backgroundColor: pageBackground,
            onBack: _popWithCurrentDate,
          ),
        ),
        body: ColoredBox(
          color: pageBackground,
          child: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontal = constraints.maxWidth <= 420 ? 20.0 : 24.0;
                return PageView.builder(
                  controller: _pageController,
                  itemCount: _pageCount,
                  onPageChanged: (page) {
                    final pageDate = _dateForPage(page);
                    setState(() {
                      _currentPage = page;
                      _selectedDate = pageDate;
                    });
                  },
                  itemBuilder: (context, page) {
                    final pageDate = _dateForPage(page);
                    if (pageDate == null) {
                      final utcCivil = _gregorianDateForPage(page);
                      return Scrollbar(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            horizontal,
                            12,
                            horizontal,
                            28,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 620),
                              child: _SkippedCivilDayCard(
                                year: utcCivil.year,
                                month: utcCivil.month,
                                day: utcCivil.day,
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    final pageDetail = _detailFor(pageDate);
                    return Scrollbar(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          horizontal,
                          12,
                          horizontal,
                          28,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 620),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _ClassicalAlmanacCard(
                                  detail: pageDetail,
                                  date: pageDate,
                                  originAccountGeneration:
                                      _originAccountGeneration,
                                ),
                                if (pageDetail != null) ...[
                                  const SizedBox(height: 14),
                                  _AlmanacExtendedDetailsSection(
                                    detail: pageDetail,
                                    date: pageDate,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _AlmanacDetailNavBar extends StatelessWidget {
  final String title;
  final Color backgroundColor;
  final VoidCallback onBack;

  const _AlmanacDetailNavBar({
    required this.title,
    required this.backgroundColor,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Container(
        color: backgroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: IconButton(
                tooltip: AlmanacUiCopy.backTooltip,
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_ios_new),
                iconSize: 20,
                color: cs.onSurface.withValues(alpha: 0.86),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  softWrap: true,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.normal,
                    letterSpacing: 0,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }
}

class _SkippedCivilDayCard extends StatelessWidget {
  final int year;
  final int month;
  final int day;

  const _SkippedCivilDayCard({
    required this.year,
    required this.month,
    required this.day,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    const gold = AlmanacPalette.paperGold;
    final lineColor = gold.withValues(alpha: isDark ? 0.62 : 0.55);
    final cardColor = isDark
        ? Color.alphaBlend(gold.withValues(alpha: 0.04), cs.surface)
        : Colors.white;
    final paperTint = Color.alphaBlend(
      gold.withValues(alpha: isDark ? 0.030 : 0.018),
      cardColor,
    );

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 380),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [paperTint, cardColor],
        ),
        borderRadius: BorderRadius.circular(
          appSurfaceStyleOf(context)?.cardRadius ?? DesignTokens.radiusCard,
        ),
        border: Border.all(color: lineColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.075),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AlmanacUiCopy.skippedCivilDayTitle(
                year,
                month,
                day,
                null,
                AppDateFormat.patternOf(context),
              ),
              style: TextStyle(
                fontSize: 20,
                color: cs.onSurface,
                fontWeight: FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
              ),
              child: Text(
                AlmanacUiCopy.skippedCivilDayNotice(),
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.68),
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                AlmanacUiCopy.skippedCivilDayExplanation(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: cs.onSurface.withValues(alpha: 0.54),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlmanacTextKey {
  final String text;
  final TextStyle style;
  final TextScaler textScaler;
  final double scaledProbe;
  final TextDirection textDirection;
  final double maxWidth;
  final int? maxLines;
  final Locale? locale;
  final StrutStyle? strutStyle;

  const _AlmanacTextKey({
    required this.text,
    required this.style,
    required this.textScaler,
    required this.scaledProbe,
    required this.textDirection,
    required this.maxWidth,
    required this.maxLines,
    required this.locale,
    required this.strutStyle,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _AlmanacTextKey &&
          other.text == text &&
          other.style == style &&
          other.textScaler == textScaler &&
          other.scaledProbe == scaledProbe &&
          other.textDirection == textDirection &&
          other.maxWidth == maxWidth &&
          other.maxLines == maxLines &&
          other.locale == locale &&
          other.strutStyle == strutStyle;

  @override
  int get hashCode => Object.hash(
    text,
    style,
    textScaler,
    scaledProbe,
    textDirection,
    maxWidth,
    maxLines,
    locale,
    strutStyle,
  );
}

const int _maxAlmanacTextCacheEntries = 256;
final LinkedHashMap<_AlmanacTextKey, Size> _almanacTextSizeCache =
    LinkedHashMap<_AlmanacTextKey, Size>();

Size _measureAlmanacTextSize({
  BuildContext? context,
  required String text,
  required TextStyle style,
  required TextScaler textScaler,
  TextDirection textDirection = TextDirection.ltr,
  double maxWidth = double.infinity,
  int? maxLines,
  StrutStyle? strutStyle,
}) {
  final effectiveStyle = context != null
      ? DefaultTextStyle.of(context).style.merge(style)
      : style;
  final locale = context != null ? Localizations.maybeLocaleOf(context) : null;
  final key = _AlmanacTextKey(
    text: text,
    style: effectiveStyle,
    textScaler: textScaler,
    scaledProbe: textScaler.scale(effectiveStyle.fontSize ?? 14.0),
    textDirection: textDirection,
    maxWidth: maxWidth,
    maxLines: maxLines,
    locale: locale,
    strutStyle: strutStyle,
  );
  final existing = _almanacTextSizeCache.remove(key);
  if (existing != null) {
    _almanacTextSizeCache[key] = existing;
    return existing;
  }
  final painter = TextPainter(
    text: TextSpan(text: text, style: effectiveStyle),
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: maxLines,
    locale: locale,
    strutStyle: strutStyle,
  )..layout(maxWidth: maxWidth);
  final size = painter.size;
  painter.dispose();
  if (_almanacTextSizeCache.length >= _maxAlmanacTextCacheEntries) {
    _almanacTextSizeCache.remove(_almanacTextSizeCache.keys.first);
  }
  _almanacTextSizeCache[key] = size;
  return size;
}

double _measureHeroPanelHeight({
  required BuildContext context,
  required DateTime date,
  required LunarAlmanacDetail? detail,
  required double availableWidth,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  final lunar = detail?.lunarDate ?? LunarCalendar.tryFromSolar(date);
  final lunarText = lunar != null
      ? (AlmanacLocaleFormat.isEn
            ? AlmanacLocaleFormat.formatLunarDate(lunar)
            : lunar.chineseText)
      : AlmanacUiCopy.lunarUnavailable;
  final ganzhiText = detail != null
      ? _spacedGanzhiLine(detail.ganzhiLine)
      : AlmanacUiCopy.almanacUnavailable;

  final innerWidth = (availableWidth - 28.0).clamp(20.0, double.infinity);

  final dayCandidate = _clampDouble(availableWidth * 0.36, 76, 106);
  final dayWidthEstimate = dayCandidate * textScaler.scale(1.0) * 1.15;
  final daySize = (dayWidthEstimate > innerWidth || availableWidth <= 320)
      ? 76.0
      : dayCandidate;
  final lunarSize = _clampDouble(availableWidth * 0.13, 26, 36);
  final ganzhiSize = _clampDouble(availableWidth * 0.052, 13.5, 16);

  final dayHeight = _measureAlmanacTextSize(
    context: context,
    text: '${date.day}',
    style: TextStyle(
      fontSize: daySize,
      height: 0.92,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    textScaler: textScaler,
    textDirection: textDirection,
    maxWidth: innerWidth,
    maxLines: 1,
  ).height;

  final lunarHeight = _measureAlmanacTextSize(
    context: context,
    text: lunarText,
    style: TextStyle(
      fontSize: lunarSize,
      height: 1.1,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    textScaler: textScaler,
    textDirection: textDirection,
    maxWidth: innerWidth,
  ).height;

  final ganzhiHeight = _measureAlmanacTextSize(
    context: context,
    text: ganzhiText,
    style: TextStyle(fontSize: ganzhiSize, height: 1.35, letterSpacing: 0),
    textScaler: textScaler,
    textDirection: textDirection,
    maxWidth: innerWidth,
  ).height;

  return dayHeight + 10.0 + lunarHeight + 9.0 + ganzhiHeight + 28.0 + 12.0;
}

double _measureVerticalYijiHeight({
  required BuildContext context,
  required LunarAlmanacDetail? detail,
  required double availableWidth,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  final isEn = AlmanacLocaleFormat.isEn;
  final suitableTerms = detail?.suitable != null
      ? _splitAlmanacTerms(detail!.suitable).take(5).toList(growable: false)
      : <String>[AlmanacUiCopy.unavailable];
  final avoidTerms = detail?.avoid != null
      ? _splitAlmanacTerms(detail!.avoid).take(5).toList(growable: false)
      : <String>[AlmanacUiCopy.unavailable];

  final colWidth = (availableWidth - 1.0).clamp(0.0, double.infinity) / 2;
  final textSize = isEn
      ? (colWidth < 80 ? 11.5 : 12.5)
      : (colWidth < 66 ? 13.0 : 14.0);
  final scaledTitleSize = textScaler.scale(13.0);
  final circleSize = (scaledTitleSize + 10.0) > 24.0
      ? (scaledTitleSize + 10.0)
      : 24.0;
  final horizontalColWidth = (colWidth - 18.0).clamp(24.0, double.infinity);

  final fitTitle = isEn ? AlmanacUiCopy.auspiciousLabel : '宜';
  final avoidTitle = isEn ? AlmanacUiCopy.inauspiciousLabel : '忌';
  var headerHeight = circleSize;
  for (final header in [fitTitle, avoidTitle]) {
    final badgeMaxW = header.length > 1
        ? (horizontalColWidth - 18.0).clamp(16.0, double.infinity)
        : double.infinity;
    final h =
        _measureAlmanacTextSize(
          context: context,
          text: header,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.normal,
            height: 1.0,
          ),
          textScaler: textScaler,
          textDirection: textDirection,
          maxWidth: badgeMaxW,
        ).height +
        8.0;
    if (h > headerHeight) headerHeight = h;
  }

  double measureTermsHeight(List<String> terms) {
    double total = 0;
    final style = TextStyle(fontSize: textSize, height: isEn ? 1.25 : 1.18);
    final strut = isEn
        ? null
        : StrutStyle(fontSize: textSize, height: 1.18, forceStrutHeight: true);
    final maxTermWidth = isEn
        ? horizontalColWidth
        : textScaler.scale(textSize) + 8.0;
    for (final term in terms) {
      final termText = isEn
          ? AlmanacLocaleFormat.formatActivityTerm(term)
          : _verticalAlmanacTerm(term);
      final termSize = _measureAlmanacTextSize(
        context: context,
        text: termText,
        style: style,
        textScaler: textScaler,
        textDirection: textDirection,
        maxWidth: maxTermWidth,
        strutStyle: strut,
      );
      total += termSize.height + 5.0;
    }
    return total;
  }

  final suitableHeight = measureTermsHeight(suitableTerms);
  final avoidHeight = measureTermsHeight(avoidTerms);
  final maxTermsHeight = suitableHeight > avoidHeight
      ? suitableHeight
      : avoidHeight;

  return headerHeight + 8.0 + maxTermsHeight + 23.0 + 12.0;
}

double _measureClassicalCellHeight({
  required BuildContext context,
  required String title,
  required List<String> valueLines,
  required double availableWidth,
  required bool isPengZu,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  final boundedWidth = availableWidth.clamp(20.0, double.infinity);
  final titleHeight = _measureAlmanacTextSize(
    context: context,
    text: title,
    style: const TextStyle(
      fontSize: 16.0,
      height: 1.1,
      fontWeight: FontWeight.normal,
    ),
    textScaler: textScaler,
    textDirection: textDirection,
    maxWidth: boundedWidth,
  ).height;

  const valueSize = 12.4;
  final valueHeight = isPengZu ? 1.48 : 1.36;
  final lineStyle = TextStyle(
    fontSize: valueSize,
    height: valueHeight,
    fontWeight: FontWeight.normal,
  );
  double linesTotalHeight = 0;
  for (final line in valueLines) {
    if (line.isEmpty) {
      linesTotalHeight += textScaler.scale(valueSize * 0.62);
    } else {
      linesTotalHeight += _measureAlmanacTextSize(
        context: context,
        text: line,
        style: lineStyle,
        textScaler: textScaler,
        textDirection: textDirection,
        maxWidth: boundedWidth,
      ).height;
    }
  }

  final gap = isPengZu ? 8.0 : 6.0;
  final verticalPadding = isPengZu ? 24.0 : 20.0;
  return verticalPadding + titleHeight + gap + linesTotalHeight;
}

class _ClassicalAlmanacCard extends StatelessWidget {
  final LunarAlmanacDetail? detail;
  final DateTime? date;
  final int? originAccountGeneration;

  const _ClassicalAlmanacCard({
    this.detail,
    this.date,
    this.originAccountGeneration,
  });

  DateTime get _effectiveDate => date ?? detail?.solarDate ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const gold = AlmanacPalette.paperGold;
    final lineColor = gold.withValues(alpha: isDark ? 0.62 : 0.55);
    final cardColor = isDark
        ? Color.alphaBlend(
            gold.withValues(alpha: 0.04),
            theme.colorScheme.surface,
          )
        : Colors.white;
    final paperTint = Color.alphaBlend(
      gold.withValues(alpha: isDark ? 0.030 : 0.018),
      cardColor,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cardInnerWidth = (width - 2.0).clamp(0.0, double.infinity);
        final textDirection =
            Directionality.maybeOf(context) ?? TextDirection.ltr;
        final textScaler = MediaQuery.textScalerOf(context);
        final textScale = textScaler.scale(1.0);
        final isEn = AlmanacLocaleFormat.isEn;

        final dayMeasuredWidth = _measureAlmanacTextSize(
          context: context,
          text: '${_effectiveDate.day}',
          style: const TextStyle(
            fontSize: 76.0,
            height: 0.92,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          textScaler: textScaler,
          textDirection: textDirection,
        ).width;

        final sideBySideHeroWidth =
            ((cardInnerWidth - 0.7).clamp(0.0, double.infinity)) * 0.68;
        final sideBySideYijiWidth =
            ((cardInnerWidth - 0.7).clamp(0.0, double.infinity)) * 0.32;
        final sideBySideDayWidth = sideBySideHeroWidth - 34.0;
        final sideBySideYijiColWidth =
            ((sideBySideYijiWidth - 0.7).clamp(0.0, double.infinity)) / 2.0;
        final sideBySideYijiColInner =
            (sideBySideYijiColWidth - 18.0).clamp(0.0, double.infinity);

        final scaledYijiBadgeSize = textScaler.scale(13.0);
        final yijiCircleSize = (scaledYijiBadgeSize + 10.0) > 24.0
            ? (scaledYijiBadgeSize + 10.0)
            : 24.0;
        var requiredYijiColInner = isEn
            ? 0.0
            : (yijiCircleSize > (textScaler.scale(14.0) + 8.0)
                  ? yijiCircleSize
                  : (textScaler.scale(14.0) + 8.0));
        if (isEn) {
          for (final header in [
            AlmanacUiCopy.auspiciousLabel,
            AlmanacUiCopy.inauspiciousLabel,
          ]) {
            final headerWidth =
                _measureAlmanacTextSize(
                  context: context,
                  text: header,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.normal,
                    height: 1.0,
                  ),
                  textScaler: textScaler,
                  textDirection: textDirection,
                ).width +
                18.0;
            if (headerWidth > requiredYijiColInner) {
              requiredYijiColInner = headerWidth;
            }
          }
        }

        final reflowTopVisual =
            dayMeasuredWidth > sideBySideDayWidth ||
            sideBySideYijiColInner < requiredYijiColInner;

        final heroWidth = reflowTopVisual ? cardInnerWidth : sideBySideHeroWidth;
        final yijiWidth = reflowTopVisual ? cardInnerWidth : sideBySideYijiWidth;

        final heroHeight = _measureHeroPanelHeight(
          context: context,
          date: _effectiveDate,
          detail: detail,
          availableWidth: heroWidth,
          textScaler: textScaler,
          textDirection: textDirection,
        );

        final yijiHeight = _measureVerticalYijiHeight(
          context: context,
          detail: detail,
          availableWidth: yijiWidth,
          textScaler: textScaler,
          textDirection: textDirection,
        );

        final baseTop = width * 0.66 * (textScale <= 1.05 ? 1.0 : textScale);
        final topCandidates = [baseTop, heroHeight, yijiHeight, 246.0];
        final topMinHeight = reflowTopVisual
            ? (heroHeight + 1.0 + yijiHeight)
            : topCandidates.reduce((a, b) => a > b ? a : b);

        final tableContentWidth =
            (cardInnerWidth - 1.4).clamp(0.0, double.infinity);
        final sideColWidth = tableContentWidth * 0.32;
        final sideInnerWidth = (sideColWidth - 16.0).clamp(
          20.0,
          double.infinity,
        );
        final centerColWidth = tableContentWidth * 0.36;
        final centerInnerWidth = (centerColWidth - 16.0).clamp(
          20.0,
          double.infinity,
        );

        final fetalGodLines = detail != null
            ? [
                isEn
                    ? AlmanacLocaleFormat.formatFetalGod(detail!.fetalGod)
                    : detail!.fetalGod,
              ]
            : [AlmanacUiCopy.unavailable];
        final mansionLines = detail != null
            ? [
                isEn
                    ? AlmanacLocaleFormat.formatMansion(detail!.mansion)
                    : detail!.mansion,
              ]
            : [AlmanacUiCopy.unavailable];
        final fiveElementLines = detail != null
            ? (isEn
                  ? [AlmanacLocaleFormat.formatFiveElements(detail!.fiveElements)]
                  : _splitFiveElementLines(detail!.fiveElements))
            : [AlmanacUiCopy.unavailable];
        final clashLines = detail != null
            ? (isEn
                  ? [AlmanacLocaleFormat.formatClash(detail!)]
                  : _splitClashLines(detail!.clash))
            : [AlmanacUiCopy.unavailable];
        final pengZuLines = detail != null
            ? (isEn
                  ? [AlmanacLocaleFormat.formatPengZu(detail!.pengZu)]
                  : _splitPengZuLines(detail!.pengZu))
            : [AlmanacUiCopy.unavailable];

        final fetalTitle = isEn ? AlmanacUiCopy.fetalGodLabel : '胎神';
        final mansionTitle = isEn ? AlmanacUiCopy.mansionLabel : '星宿';
        final fiveElementsTitle = isEn ? AlmanacUiCopy.fiveElementsLabel : '五行';
        final clashTitle = isEn ? AlmanacUiCopy.clashLabel : '冲煞';
        final pengZuTitle = isEn ? AlmanacUiCopy.pengZuLabel : '彭祖';

        var reflowInfoTable = false;
        const infoTitleStyle = TextStyle(
          fontSize: 16.0,
          height: 1.1,
          fontWeight: FontWeight.normal,
        );
        const infoValueStyle = TextStyle(
          fontSize: 12.4,
          height: 1.36,
          fontWeight: FontWeight.normal,
        );
        for (final entry in <(String, double, List<String>)>[
          (fetalTitle, sideInnerWidth, fetalGodLines),
          (mansionTitle, sideInnerWidth, mansionLines),
          (fiveElementsTitle, sideInnerWidth, fiveElementLines),
          (clashTitle, sideInnerWidth, clashLines),
          (pengZuTitle, centerInnerWidth, pengZuLines),
        ]) {
          final titleWidth = _measureAlmanacTextSize(
            context: context,
            text: entry.$1,
            style: infoTitleStyle,
            textScaler: textScaler,
            textDirection: textDirection,
          ).width;
          if (titleWidth > entry.$2 + 0.5) {
            reflowInfoTable = true;
            break;
          }
          if (isEn) {
            for (final line in entry.$3) {
              for (final word in line.split(RegExp(r'\s+'))) {
                if (word.isEmpty) continue;
                final wordWidth = _measureAlmanacTextSize(
                  context: context,
                  text: word,
                  style: infoValueStyle,
                  textScaler: textScaler,
                  textDirection: textDirection,
                ).width;
                if (wordWidth > entry.$2) {
                  reflowInfoTable = true;
                  break;
                }
              }
              if (reflowInfoTable) break;
            }
            if (reflowInfoTable) break;
          }
        }

        final hFetalGod = _measureClassicalCellHeight(
          context: context,
          title: fetalTitle,
          valueLines: fetalGodLines,
          availableWidth: sideInnerWidth,
          isPengZu: false,
          textScaler: textScaler,
          textDirection: textDirection,
        );
        final hMansion = _measureClassicalCellHeight(
          context: context,
          title: mansionTitle,
          valueLines: mansionLines,
          availableWidth: sideInnerWidth,
          isPengZu: false,
          textScaler: textScaler,
          textDirection: textDirection,
        );
        final hFiveElements = _measureClassicalCellHeight(
          context: context,
          title: fiveElementsTitle,
          valueLines: fiveElementLines,
          availableWidth: sideInnerWidth,
          isPengZu: false,
          textScaler: textScaler,
          textDirection: textDirection,
        );
        final hClash = _measureClassicalCellHeight(
          context: context,
          title: clashTitle,
          valueLines: clashLines,
          availableWidth: sideInnerWidth,
          isPengZu: false,
          textScaler: textScaler,
          textDirection: textDirection,
        );
        final hPengZu = _measureClassicalCellHeight(
          context: context,
          title: pengZuTitle,
          valueLines: pengZuLines,
          availableWidth: centerInnerWidth,
          isPengZu: true,
          textScaler: textScaler,
          textDirection: textDirection,
        );

        final maxSideCell = [
          hFetalGod,
          hMansion,
          hFiveElements,
          hClash,
        ].reduce((a, b) => a > b ? a : b);
        final sideNeeded = (maxSideCell + 10.0) * 2.0 + 1.0;
        final pengZuNeeded = hPengZu + 12.0;

        final baseTable = width * 0.62 * (textScale <= 1.05 ? 1.0 : textScale);
        final tableCandidates = [baseTable, pengZuNeeded, sideNeeded, 236.0];
        final tableHeight = tableCandidates.reduce((a, b) => a > b ? a : b);

        final fortunesCount = detail?.hourFortuneItems.length ?? 0;
        final singleCellWidth =
            cardInnerWidth / (fortunesCount > 0 ? fortunesCount : 12);
        final scaledBranch = textScaler.scale(12.5);
        final hourNeedsTwoRows =
            singleCellWidth < (scaledBranch + 12.0) && fortunesCount == 12;

        final baseHourHeight = _clampDouble(
          width * 0.17 * (textScale <= 1.05 ? textScale : 1.0),
          58,
          76,
        );
        double measuredHourHeight;
        if (fortunesCount == 0) {
          final emptyH = _measureAlmanacTextSize(
            context: context,
            text: AlmanacUiCopy.hourFortuneUnavailable,
            style: appSecondaryControlTextStyle(context).copyWith(fontSize: 12),
            textScaler: textScaler,
            textDirection: textDirection,
            maxWidth: (cardInnerWidth - 16.0).clamp(20.0, double.infinity),
          ).height;
          measuredHourHeight = emptyH + 24.0;
        } else {
          final perCellWidth = hourNeedsTwoRows
              ? (cardInnerWidth / 6.0)
              : singleCellWidth;
          final branchSize = perCellWidth < 28 ? 11.0 : 12.5;
          final luckSize = perCellWidth < 28 ? 10.5 : 12.0;
          final branchH = _measureAlmanacTextSize(
            context: context,
            text: '子',
            style: TextStyle(fontSize: branchSize, height: 1.05),
            textScaler: textScaler,
            textDirection: textDirection,
            maxLines: 1,
          ).height;
          final luckH = _measureAlmanacTextSize(
            context: context,
            text: '吉',
            style: TextStyle(
              fontSize: luckSize,
              height: 1.05,
              fontWeight: FontWeight.normal,
            ),
            textScaler: textScaler,
            textDirection: textDirection,
            maxLines: 1,
          ).height;
          final rowH = branchH + 5.0 + luckH + 8.0;
          measuredHourHeight = hourNeedsTwoRows ? (rowH * 2.0 + 1.0) : rowH;
        }
        final formulaHourHeight = hourNeedsTwoRows
            ? (baseHourHeight * 2.0 + 8.0)
            : (textScale > 1.05
                  ? (baseHourHeight * textScale)
                  : baseHourHeight);
        final hourHeight = formulaHourHeight > measuredHourHeight
            ? formulaHourHeight
            : measuredHourHeight;

        final topVisual = _AlmanacTopVisual(
          detail: detail,
          date: _effectiveDate,
          lineColor: lineColor,
          gold: gold,
          reflow: reflowTopVisual,
          heroHeight: heroHeight,
          yijiHeight: yijiHeight,
        );
        final infoTable = _ClassicalInfoTable(
          detail: detail,
          lineColor: lineColor,
          reflow: reflowInfoTable,
        );

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [paperTint, cardColor],
            ),
            borderRadius: BorderRadius.circular(
              appSurfaceStyleOf(context)?.cardRadius ?? DesignTokens.radiusCard,
            ),
            border: Border.all(color: lineColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.075),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              appSurfaceStyleOf(context)?.cardRadius ?? DesignTokens.radiusCard,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (reflowTopVisual)
                  topVisual
                else
                  SizedBox(height: topMinHeight, child: topVisual),
                _ClassicalDivider(color: lineColor),
                if (reflowInfoTable)
                  infoTable
                else
                  SizedBox(height: tableHeight, child: infoTable),
                _ClassicalDivider(color: lineColor),
                SizedBox(
                  height: hourHeight,
                  child: _ClassicalHourRow(
                    fortunes:
                        detail?.hourFortuneItems ??
                        const <AlmanacHourFortune>[],
                    lineColor: lineColor,
                    gold: gold,
                    originAccountGeneration: originAccountGeneration,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AlmanacTopVisual extends StatelessWidget {
  final LunarAlmanacDetail? detail;
  final DateTime date;
  final Color lineColor;
  final Color gold;
  final bool reflow;
  final double? heroHeight;
  final double? yijiHeight;

  const _AlmanacTopVisual({
    this.detail,
    required this.date,
    required this.lineColor,
    required this.gold,
    this.reflow = false,
    this.heroHeight,
    this.yijiHeight,
  });

  @override
  Widget build(BuildContext context) {
    if (reflow) {
      final yiji = _VerticalYijiPanel(
        suitable: detail?.suitable,
        avoid: detail?.avoid,
        date: date,
        gold: gold,
        lineColor: lineColor,
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: heroHeight ?? 0),
            child: _DateHeroPanel(detail: detail, date: date, gold: gold),
          ),
          _ClassicalDivider(color: lineColor),
          if (yijiHeight != null)
            SizedBox(height: yijiHeight, child: yiji)
          else
            yiji,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 32,
          child: _VerticalYijiPanel(
            suitable: detail?.suitable,
            avoid: detail?.avoid,
            date: date,
            gold: gold,
            lineColor: lineColor,
          ),
        ),
        _ClassicalVerticalDivider(color: lineColor),
        Expanded(
          flex: 68,
          child: _DateHeroPanel(detail: detail, date: date, gold: gold),
        ),
      ],
    );
  }
}

class _VerticalYijiPanel extends StatelessWidget {
  static const int _visibleTermLimit = 5;

  final String? suitable;
  final String? avoid;
  final DateTime date;
  final Color gold;
  final Color lineColor;

  const _VerticalYijiPanel({
    this.suitable,
    this.avoid,
    required this.date,
    required this.gold,
    required this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final goldText = AlmanacPalette.goldInk(isDark: isDark);
    final darkText = cs.onSurface.withValues(alpha: isDark ? 0.88 : 0.86);
    final suitableTerms = suitable != null
        ? _splitAlmanacTerms(
            suitable!,
          ).take(_visibleTermLimit).toList(growable: false)
        : <String>[AlmanacUiCopy.unavailable];
    final avoidTerms = avoid != null
        ? _splitAlmanacTerms(
            avoid!,
          ).take(_visibleTermLimit).toList(growable: false)
        : <String>[AlmanacUiCopy.unavailable];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth =
            (constraints.maxWidth - 1).clamp(0, double.infinity) / 2;
        final textSize = AlmanacLocaleFormat.isEn
            ? (columnWidth < 80 ? 11.5 : 12.5)
            : (columnWidth < 66 ? 13.0 : 14.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 13, 8, 10),
                child: _VerticalYijiColumn(
                  key: const ValueKey('almanac_vertical_suitable_column'),
                  keyName: 'suitable',
                  title: '宜',
                  terms: suitableTerms,
                  date: date,
                  color: goldText,
                  fontSize: textSize,
                ),
              ),
            ),
            _ClassicalVerticalDivider(color: lineColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 13, 10, 10),
                child: _VerticalYijiColumn(
                  key: const ValueKey('almanac_vertical_avoid_column'),
                  keyName: 'avoid',
                  title: '忌',
                  terms: avoidTerms,
                  date: date,
                  color: darkText,
                  fontSize: textSize,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VerticalYijiColumn extends StatelessWidget {
  final String keyName;
  final String title;
  final List<String> terms;
  final DateTime date;
  final Color color;
  final double fontSize;

  const _VerticalYijiColumn({
    super.key,
    required this.keyName,
    required this.title,
    required this.terms,
    required this.date,
    required this.color,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final isEn = AlmanacLocaleFormat.isEn;
    final displayTitle = !isEn
        ? title
        : (title == '宜'
              ? AlmanacUiCopy.auspiciousLabel
              : (title == '忌' ? AlmanacUiCopy.inauspiciousLabel : title));
    final textScaler = MediaQuery.textScalerOf(context);
    final scaledTitleSize = textScaler.scale(13.0);
    final circleSize = (scaledTitleSize + 10.0) > 24.0
        ? (scaledTitleSize + 10.0)
        : 24.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          constraints: BoxConstraints(
            minWidth: displayTitle.length > 1 ? 0 : circleSize,
            minHeight: circleSize,
          ),
          padding: displayTitle.length > 1
              ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
              : const EdgeInsets.all(2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: displayTitle.length > 1
                ? BoxShape.rectangle
                : BoxShape.circle,
            borderRadius: displayTitle.length > 1
                ? BorderRadius.circular(999)
                : null,
            border: Border.all(
              color: color.withValues(alpha: 0.62),
              width: 0.7,
            ),
          ),
          child: Text(
            displayTitle,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.normal,
              height: 1.0,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Align(
            key: ValueKey('almanac_vertical_${keyName}_terms_box'),
            alignment: Alignment.topCenter,
            child: Column(
              key: ValueKey('almanac_vertical_${keyName}_terms'),
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final term in terms)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: _VerticalTerm(
                      term: term,
                      date: date,
                      color: color,
                      fontSize: fontSize,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _VerticalTerm extends StatelessWidget {
  final String term;
  final DateTime date;
  final Color color;
  final double fontSize;

  const _VerticalTerm({
    required this.term,
    required this.date,
    required this.color,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final isEn = AlmanacLocaleFormat.isEn;
    final textScaler = MediaQuery.textScalerOf(context);
    final scaledWidth = textScaler.scale(fontSize) + 8.0;
    final displayText = isEn
        ? AlmanacLocaleFormat.formatActivityTerm(term)
        : _verticalAlmanacTerm(term);
    final label = Text(
      displayText,
      textAlign: TextAlign.center,
      softWrap: true,
      style: TextStyle(
        color: color.withValues(alpha: 0.94),
        fontSize: fontSize,
        height: isEn ? 1.25 : 1.18,
      ),
      strutStyle: isEn
          ? null
          : StrutStyle(
              fontSize: fontSize,
              height: 1.18,
              forceStrutHeight: true,
            ),
    );
    final wrapped = isEn ? label : SizedBox(width: scaledWidth, child: label);
    if (term == AlmanacUiCopy.unavailable) return wrapped;
    return InkWell(
      borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      onTap: () => _showAlmanacTermDictionarySheet(context, term, date),
      child: wrapped,
    );
  }
}

class _DateHeroPanel extends StatelessWidget {
  final LunarAlmanacDetail? detail;
  final DateTime date;
  final Color gold;

  const _DateHeroPanel({this.detail, required this.date, required this.gold});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lunar = detail?.lunarDate ?? LunarCalendar.tryFromSolar(date);
    final lunarText = lunar != null
        ? (AlmanacLocaleFormat.isEn
              ? AlmanacLocaleFormat.formatLunarDate(lunar)
              : lunar.chineseText)
        : AlmanacUiCopy.lunarUnavailable;
    final ganzhiText = detail != null
        ? _spacedGanzhiLine(detail!.ganzhiLine)
        : AlmanacUiCopy.almanacUnavailable;

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final dayCandidate = _clampDouble(constraints.maxWidth * 0.36, 76, 106);
        final dayWidthEstimate = dayCandidate * textScaler.scale(1.0) * 1.15;
        final daySize =
            (dayWidthEstimate > (constraints.maxWidth - 28.0) ||
                constraints.maxWidth <= 320)
            ? 76.0
            : dayCandidate;
        final lunarSize = _clampDouble(constraints.maxWidth * 0.13, 26, 36);
        final ganzhiSize = _clampDouble(constraints.maxWidth * 0.052, 13.5, 16);
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${date.day}',
                maxLines: 1,
                style: TextStyle(
                  fontSize: daySize,
                  height: 0.92,
                  color: cs.onSurface,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w400,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                lunarText,
                softWrap: true,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: lunarSize,
                  height: 1.1,
                  color: cs.onSurface,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                ganzhiText,
                softWrap: true,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: ganzhiSize,
                  height: 1.35,
                  color: cs.onSurface.withValues(alpha: isDark ? 0.88 : 0.78),
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ClassicalInfoTable extends StatelessWidget {
  final LunarAlmanacDetail? detail;
  final Color lineColor;
  final bool reflow;

  const _ClassicalInfoTable({
    this.detail,
    required this.lineColor,
    this.reflow = false,
  });

  @override
  Widget build(BuildContext context) {
    final fetalGod = detail?.fetalGod ?? AlmanacUiCopy.unavailable;
    final mansion = detail?.mansion ?? AlmanacUiCopy.unavailable;
    final pengZu = detail?.pengZu ?? AlmanacUiCopy.unavailable;
    final fiveElements = detail?.fiveElements ?? AlmanacUiCopy.unavailable;
    final clash = detail?.clash ?? AlmanacUiCopy.unavailable;

    final fetalCell = _ClassicalInfoCell(title: '胎神', value: fetalGod);
    final mansionCell = _ClassicalInfoCell(title: '星宿', value: mansion);
    final pengZuCell = _ClassicalInfoCell(title: '彭祖', value: pengZu);
    final fiveElementsCell = _ClassicalInfoCell(title: '五行', value: fiveElements);
    final clashCell = _ClassicalInfoCell(title: '冲煞', value: clash);

    if (reflow) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          fetalCell,
          _ClassicalDivider(color: lineColor),
          mansionCell,
          _ClassicalDivider(color: lineColor),
          pengZuCell,
          _ClassicalDivider(color: lineColor),
          fiveElementsCell,
          _ClassicalDivider(color: lineColor),
          clashCell,
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 32,
          child: Column(
            children: [
              Expanded(child: fetalCell),
              _ClassicalDivider(color: lineColor),
              Expanded(child: mansionCell),
            ],
          ),
        ),
        _ClassicalVerticalDivider(color: lineColor),
        Expanded(flex: 36, child: pengZuCell),
        _ClassicalVerticalDivider(color: lineColor),
        Expanded(
          flex: 32,
          child: Column(
            children: [
              Expanded(child: fiveElementsCell),
              _ClassicalDivider(color: lineColor),
              Expanded(child: clashCell),
            ],
          ),
        ),
      ],
    );
  }
}

class _ClassicalInfoCell extends StatelessWidget {
  final String title;
  final String value;

  const _ClassicalInfoCell({required this.title, required this.value});

  static String _formatClassicalClashEn(String clash) {
    final match = RegExp(r'^(.)日冲(.)（(.{2})）煞(.)$').firstMatch(clash.trim());
    if (match != null) {
      final dayZ = AlmanacLocaleFormat.formatZodiac(
        match.group(1)!,
        AppLocale.en,
      );
      final clashZ = AlmanacLocaleFormat.formatZodiac(
        match.group(2)!,
        AppLocale.en,
      );
      final gz = AlmanacLocaleFormat.formatGanZhi(
        match.group(3)!,
        AppLocale.en,
      );
      final dir = AlmanacLocaleFormat.formatDirection(
        match.group(4)!,
        AppLocale.en,
      );
      return '$dayZ Day clashes $clashZ ($gz) · Sha $dir';
    }
    return clash.trim();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isEn = AlmanacLocaleFormat.isEn;
    final isFetalGod = title == '胎神';
    final isMansion = title == '星宿';
    final isPengZu = title == '彭祖';
    final isFiveElement = title == '五行';
    final isClash = title == '冲煞';
    final displayTitle = !isEn
        ? title
        : (isFetalGod
              ? AlmanacUiCopy.fetalGodLabel
              : isMansion
              ? AlmanacUiCopy.mansionLabel
              : isPengZu
              ? AlmanacUiCopy.pengZuLabel
              : isFiveElement
              ? AlmanacUiCopy.fiveElementsLabel
              : isClash
              ? AlmanacUiCopy.clashLabel
              : title);
    final isUnavailable =
        value.trim() == AlmanacUiCopy.unavailable || value.trim().isEmpty;
    final List<String> valueLines;
    if (isUnavailable) {
      valueLines = [AlmanacUiCopy.unavailable];
    } else if (isEn) {
      if (isFetalGod) {
        valueLines = [AlmanacLocaleFormat.formatFetalGod(value)];
      } else if (isMansion) {
        valueLines = [AlmanacLocaleFormat.formatMansion(value)];
      } else if (isPengZu) {
        valueLines = [AlmanacLocaleFormat.formatPengZu(value)];
      } else if (isFiveElement) {
        valueLines = [AlmanacLocaleFormat.formatFiveElements(value)];
      } else if (isClash) {
        valueLines = [_formatClassicalClashEn(value)];
      } else {
        valueLines = [value.trim()];
      }
    } else {
      valueLines = isPengZu
          ? _splitPengZuLines(value)
          : isFiveElement
          ? _splitFiveElementLines(value)
          : isClash
          ? _splitClashLines(value)
          : [value.trim()];
    }
    const titleSize = 16.0;
    const valueSize = 12.4;
    final valueHeight = isPengZu ? 1.48 : 1.36;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 8,
        vertical: isPengZu ? 12 : 10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            displayTitle,
            softWrap: true,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: titleSize,
              height: 1.1,
              fontWeight: FontWeight.normal,
              color: cs.onSurface,
            ),
          ),
          SizedBox(height: isPengZu ? 8 : 6),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final line in valueLines)
                if (line.isEmpty)
                  const SizedBox(height: valueSize * 0.62)
                else
                  Text(
                    line,
                    textAlign: TextAlign.center,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: valueSize,
                      height: valueHeight,
                      fontWeight: FontWeight.normal,
                      color: cs.onSurface.withValues(
                        alpha: isDark ? 0.88 : 0.78,
                      ),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClassicalHourRow extends StatelessWidget {
  final List<AlmanacHourFortune> fortunes;
  final Color lineColor;
  final Color gold;
  final int? originAccountGeneration;

  const _ClassicalHourRow({
    required this.fortunes,
    required this.lineColor,
    required this.gold,
    this.originAccountGeneration,
  });

  @override
  Widget build(BuildContext context) {
    if (fortunes.isEmpty) {
      return Center(
        child: Text(
          AlmanacUiCopy.hourFortuneUnavailable,
          style: appSecondaryControlTextStyle(context).copyWith(
            fontSize: 12,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.52),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final scaledBranch = textScaler.scale(12.5);
        final singleCellWidth = constraints.maxWidth / fortunes.length;
        final needsTwoRows =
            singleCellWidth < (scaledBranch + 12.0) && fortunes.length == 12;

        if (needsTwoRows) {
          final row1 = fortunes.sublist(0, 6);
          final row2 = fortunes.sublist(6, 12);
          return Column(
            children: [
              Expanded(
                child: Row(
                  children: row1.asMap().entries.map((entry) {
                    return Expanded(
                      child: _ClassicalHourCell(
                        fortune: entry.value,
                        lineColor: lineColor,
                        gold: gold,
                        showRightBorder: entry.key != 5,
                        originAccountGeneration: originAccountGeneration,
                      ),
                    );
                  }).toList(),
                ),
              ),
              _ClassicalDivider(color: lineColor),
              Expanded(
                child: Row(
                  children: row2.asMap().entries.map((entry) {
                    return Expanded(
                      child: _ClassicalHourCell(
                        fortune: entry.value,
                        lineColor: lineColor,
                        gold: gold,
                        showRightBorder: entry.key != 5,
                        originAccountGeneration: originAccountGeneration,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          );
        }

        return Row(
          children: fortunes.asMap().entries.map((entry) {
            final index = entry.key;
            final fortune = entry.value;
            return Expanded(
              child: _ClassicalHourCell(
                fortune: fortune,
                lineColor: lineColor,
                gold: gold,
                showRightBorder: index != fortunes.length - 1,
                originAccountGeneration: originAccountGeneration,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _ClassicalHourCell extends StatelessWidget {
  final AlmanacHourFortune fortune;
  final Color lineColor;
  final Color gold;
  final bool showRightBorder;
  final int? originAccountGeneration;

  const _ClassicalHourCell({
    required this.fortune,
    required this.lineColor,
    required this.gold,
    required this.showRightBorder,
    this.originAccountGeneration,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final goldText = AlmanacPalette.goldInk(isDark: isDark);
    final luckColor = fortune.isAuspicious
        ? goldText
        : cs.onSurface.withValues(alpha: isDark ? 0.88 : 0.78);
    final cellFill = fortune.isAuspicious
        ? gold.withValues(alpha: isDark ? 0.055 : 0.040)
        : Colors.transparent;
    return InkWell(
      onTap: () => _showHourFortuneDialog(
        context,
        fortune,
        originAccountGeneration: originAccountGeneration,
      ),
      child: Container(
        height: double.infinity,
        decoration: BoxDecoration(
          color: cellFill,
          border: Border(
            right: showRightBorder
                ? BorderSide(color: lineColor, width: 0.55)
                : BorderSide.none,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final branchSize = constraints.maxWidth < 28 ? 11.0 : 12.5;
            final luckSize = constraints.maxWidth < 28 ? 10.5 : 12.0;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  fortune.branch,
                  maxLines: 1,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: isDark ? 0.88 : 0.86),
                    fontSize: branchSize,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  fortune.isAuspicious ? '吉' : '凶',
                  maxLines: 1,
                  style: TextStyle(
                    color: luckColor,
                    fontSize: luckSize,
                    height: 1.05,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ClassicalDivider extends StatelessWidget {
  final Color color;

  const _ClassicalDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(height: 0.7, color: color);
  }
}

class _ClassicalVerticalDivider extends StatelessWidget {
  final Color color;

  const _ClassicalVerticalDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(width: 0.7, color: color);
  }
}

void _showHourFortuneDialog(
  BuildContext context,
  AlmanacHourFortune fortune, {
  int? originAccountGeneration,
}) {
  final originGen =
      originAccountGeneration ?? AccountLocalDataCleaner.accountDataGeneration;
  showControllerDialog<void>(
    context: context,
    controllers: const <TextEditingController>[],
    builder: (dialogContext) {
      return ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (context, locale, _) {
          final theme = Theme.of(context);
          final cs = theme.colorScheme;
          final isDark = theme.brightness == Brightness.dark;
          const gold = AlmanacPalette.paperGold;
          final lineColor = gold.withValues(
            alpha: isDark ? 0.62 : 0.45,
          );
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                appSurfaceStyleOf(context)?.cardRadius ??
                    DesignTokens.radiusCard,
              ),
              side: BorderSide(color: lineColor, width: 1),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      AlmanacUiCopy.hourFortuneDialogTitle(
                        fortune.branch,
                        fortune.isAuspicious,
                        locale: locale,
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.normal,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _HourDetailLine(
                      label: AlmanacUiCopy.hourDetailTime(locale: locale),
                      value: fortune.range,
                    ),
                    _HourDetailLine(
                      label: AlmanacUiCopy.hourDetailGanzhi(locale: locale),
                      value: fortune.ganzhi,
                    ),
                    _HourDetailLine(
                      label: AlmanacUiCopy.hourDetailDeity(locale: locale),
                      value: fortune.deity,
                    ),
                    if (fortune.chongSha.isNotEmpty)
                      _HourDetailLine(
                        label: AlmanacUiCopy.hourChongShaLabel,
                        value: AlmanacLocaleFormat.formatHourChongSha(
                          fortune.chongSha,
                          locale,
                        ),
                      ),
                    if (fortune.naYin.isNotEmpty)
                      _HourDetailLine(
                        label: AlmanacUiCopy.hourNaYinLabel,
                        value: AlmanacLocaleFormat.formatNaYin(
                          fortune.naYin,
                          locale,
                        ),
                      ),
                    if (fortune.caiPosition.isNotEmpty ||
                        fortune.xiPosition.isNotEmpty ||
                        fortune.fuPosition.isNotEmpty)
                      _HourDetailLine(
                        label: AlmanacUiCopy.hourPositionsLabel,
                        value: [
                          if (fortune.caiPosition.isNotEmpty)
                            '${AlmanacUiCopy.caiShenLabel}: ${AlmanacLocaleFormat.formatDirection(fortune.caiPosition, locale)}',
                          if (fortune.xiPosition.isNotEmpty)
                            '${AlmanacUiCopy.xiShenLabel}: ${AlmanacLocaleFormat.formatDirection(fortune.xiPosition, locale)}',
                          if (fortune.fuPosition.isNotEmpty)
                            '${AlmanacUiCopy.fuShenLabel}: ${AlmanacLocaleFormat.formatDirection(fortune.fuPosition, locale)}',
                        ].join(' · '),
                      ),
                    if (fortune.yi.isNotEmpty)
                      _HourDetailLine(
                        label: AlmanacUiCopy.hourYiLabel,
                        value: fortune.yi
                            .take(6)
                            .map(
                              (t) => AlmanacLocaleFormat.formatActivityTerm(
                                t,
                                locale,
                              ),
                            )
                            .join(locale == AppLocale.en ? ', ' : ' '),
                      ),
                    if (fortune.ji.isNotEmpty)
                      _HourDetailLine(
                        label: AlmanacUiCopy.hourJiLabel,
                        value: fortune.ji
                            .take(6)
                            .map(
                              (t) => AlmanacLocaleFormat.formatActivityTerm(
                                t,
                                locale,
                              ),
                            )
                            .join(locale == AppLocale.en ? ', ' : ' '),
                      ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.center,
                      child: TextButton(
                        onPressed: () {
                          if (!AccountLocalDataCleaner
                              .isCurrentAccountDataGeneration(originGen)) {
                            Navigator.of(dialogContext).pop();
                            return;
                          }
                          Navigator.of(dialogContext).pop();
                        },
                        child: Text(
                          AlmanacUiCopy.dialogConfirm(locale: locale),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _HourDetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _HourDetailLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: isDark ? 0.75 : 0.70),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: cs.onSurface.withValues(alpha: isDark ? 0.90 : 0.86),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _resolveAlmanacBadgeForeground(
  List<Color> candidateCardSurfaces,
  Color accent, {
  required bool isDark,
}) {
  final badgeSurfaces = [
    for (final surface in candidateCardSurfaces)
      Color.alphaBlend(accent.withValues(alpha: 0.10), surface),
  ];

  bool passesAll(Color candidate) {
    for (final bg in badgeSurfaces) {
      final composited = Color.alphaBlend(candidate, bg);
      if (appContrastRatio(bg, composited) < 4.7) return false;
    }
    return true;
  }

  if (passesAll(accent)) return accent;

  final target = isDark ? Colors.white : Colors.black;
  for (final amount in const <double>[0.14, 0.26, 0.38, 0.50, 0.62, 0.74]) {
    final candidate = Color.lerp(accent, target, amount) ?? accent;
    if (passesAll(candidate)) return candidate;
  }

  var worstBg = badgeSurfaces.first;
  var worstRatio = double.infinity;
  for (final bg in badgeSurfaces) {
    final ratio = appContrastRatio(bg, Color.alphaBlend(accent, bg));
    if (ratio < worstRatio) {
      worstRatio = ratio;
      worstBg = bg;
    }
  }
  return appReadableForeground(worstBg, accent);
}

class _AlmanacBadge extends StatelessWidget {
  final String text;
  final Color color;
  final Color? surfaceColor;

  const _AlmanacBadge({
    required this.text,
    required this.color,
    this.surfaceColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final baseAccent = !isDark && color.toARGB32() == 0xFF2E7D32
        ? AlmanacPalette.auspiciousGreen(isDark: false)
        : !isDark && color.toARGB32() == 0xFFD84315
        ? const Color(0xFFBF360C)
        : AlmanacPalette.adapt(color, isDark: isDark);
    final surfaceStyle = appSurfaceStyleOf(context);
    final candidateSurfaces = surfaceColor != null
        ? <Color>[surfaceColor!]
        : <Color>[
            cs.surface,
            Color.alphaBlend(
              cs.primary.withValues(alpha: isDark ? 0.045 : 0.025),
              cs.surface,
            ),
            if (surfaceStyle?.cardFillColor != null)
              Color.alphaBlend(
                surfaceStyle!.cardFillColor!,
                theme.scaffoldBackgroundColor,
              ),
          ];
    final fgColor = _resolveAlmanacBadgeForeground(
      candidateSurfaces,
      baseAccent,
      isDark: isDark,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.14), width: 0.45),
      ),
      child: Text(
        text,
        softWrap: true,
        style: TextStyle(
          color: fgColor,
          fontSize: 12,
          fontWeight: FontWeight.normal,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  final DateTime date;
  final _MonthCalendarData monthData;
  final List<_MonthHighlight> highlights;
  final ValueChanged<DateTime> onPick;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onTitleTap;

  const _MonthCalendar({
    required this.date,
    required this.monthData,
    required this.highlights,
    required this.onPick,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onTitleTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final compact = MediaQuery.sizeOf(context).width < 380;
    final dayFontSize = compact ? 13.0 : 14.0;
    final labelFontSize = compact ? 8.5 : 9.0;
    final textScaler = MediaQuery.textScalerOf(context);
    final scaledDayHeight = textScaler.scale(dayFontSize) * 1.35;
    final scaledLabelHeight = textScaler.scale(labelFontSize) * 1.35;
    final baseCellHeight = compact ? 46.0 : 48.0;
    final badgeHeight = textScaler.scale(8) * 1.35 + 4;
    final counterHeight = textScaler.scale(8) * 1.35 + 4;
    final neededCellHeight = scaledDayHeight + scaledLabelHeight + 16.0;
    final cellHeight = neededCellHeight > baseCellHeight
        ? neededCellHeight
        : baseCellHeight;
    final cellRadius = compact ? 10.0 : 12.0;
    final cellMargin = compact ? 0.0 : 1.5;
    final highlightByDay = {for (final item in highlights) item.date.day: item};
    return Column(
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(
            compact ? 0 : 12,
            8,
            compact ? 0 : 12,
            10,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              appSurfaceStyleOf(context)?.cardRadius ?? DesignTokens.radiusCard,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  cs.primary.withValues(alpha: isDark ? 0.10 : 0.045),
                  cs.surface,
                ),
                Color.alphaBlend(
                  AlmanacPalette.paperGold.withValues(
                    alpha: isDark ? 0.08 : 0.035,
                  ),
                  cs.surface,
                ),
              ],
            ),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: isDark ? 0.18 : 0.22),
              width: 0.6,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.10 : 0.045),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 2),
                child: Row(
                  children: [
                    _MonthNavButton(
                      tooltip: AlmanacUiCopy.previousMonthTooltip,
                      icon: Icons.chevron_left,
                      onPressed: onPreviousMonth,
                    ),
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: AlmanacUiCopy.selectDateTooltip,
                        child: Tooltip(
                          message: AlmanacUiCopy.selectDateTooltip,
                          child: GestureDetector(
                            onTap: onTitleTap,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.calendar_today_outlined,
                                  size: 14,
                                  color: cs.onSurface.withValues(alpha: 0.46),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  AlmanacUiCopy.monthHeader(date.month),
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(
                                        fontSize: 24,
                                        fontWeight: FontWeight.normal,
                                        letterSpacing: 0,
                                        color: cs.onSurface,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  AlmanacUiCopy.yearHeader(date.year),
                                  style: appSecondaryControlLabelStyle(context)
                                      .copyWith(
                                        color: cs.onSurfaceVariant,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    _MonthNavButton(
                      tooltip: AlmanacUiCopy.nextMonthTooltip,
                      icon: Icons.chevron_right,
                      onPressed: onNextMonth,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: AlmanacUiCopy.weekdayInitials
                    .map(
                      (d) => Expanded(
                        child: Center(
                          child: Text(
                            d,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 6),
              ...List.generate(monthData.rowCount, (row) {
                final firstDay = row * 7 - monthData.firstWeekdayOffset + 1;
                final rowDays = List.generate(
                  7,
                  (col) => monthData.dayAt(firstDay + col),
                );
                final rowBadgeHeight =
                    rowDays.any(
                      (day) =>
                          day != null && (day.isHoliday || day.isWorkMakeupDay),
                    )
                    ? badgeHeight
                    : 0.0;
                final rowCounterHeight =
                    List.generate(
                      7,
                      (col) => highlightByDay[firstDay + col],
                    ).any((item) => item != null && item.labels.length > 1)
                    ? counterHeight
                    : 0.0;
                final rowCellHeight =
                    cellHeight + rowBadgeHeight + rowCounterHeight;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    children: List.generate(7, (col) {
                      final d =
                          row * 7 + col - monthData.firstWeekdayOffset + 1;
                      final dayData = monthData.dayAt(d);
                      if (dayData == null) {
                        return Expanded(child: SizedBox(height: rowCellHeight));
                      }
                      final day = dayData.date;
                      final dayLabel = dayData.label;
                      final isSelected =
                          day != null &&
                          day.year == date.year &&
                          day.month == date.month &&
                          day.day == date.day;
                      final highlight = highlightByDay[d];
                      final hasHighlight = highlight != null;
                      final isToday = day != null && day == today;
                      final isWeekend = dayData.isWeekend;
                      final isHoliday = dayData.isHoliday;
                      final isWorkMakeupDay = dayData.isWorkMakeupDay;
                      final selectedFill = Color.alphaBlend(
                        cs.primary.withValues(alpha: isDark ? 0.20 : 0.12),
                        cs.surface,
                      );
                      final selectedText = cs.onSurface;
                      final cellBg = isToday
                          ? Color.alphaBlend(
                              cs.primary.withValues(
                                alpha: isDark ? 0.10 : 0.06,
                              ),
                              cs.surface,
                            )
                          : hasHighlight
                          ? Color.alphaBlend(
                              cs.surfaceContainerHighest.withValues(
                                alpha: isDark ? 0.12 : 0.22,
                              ),
                              cs.surface,
                            )
                          : cs.surface;
                      final restColor = appReadableForeground(
                        cellBg,
                        Color.lerp(
                          AlmanacPalette.restRed(isDark: isDark),
                          cs.onSurface,
                          isDark ? 0.12 : 0.28,
                        )!,
                      );
                      final workColor = appReadableForeground(
                        cellBg,
                        Color.lerp(
                          AlmanacPalette.makeupIndigo(isDark: isDark),
                          cs.onSurface,
                          isDark ? 0.12 : 0.30,
                        )!,
                      );

                      return Expanded(
                        child: Semantics(
                          button: day != null,
                          selected: isSelected,
                          label: AlmanacUiCopy.dayCellSemanticLabel(
                            day,
                            d,
                            dayLabel,
                            isSelected: isSelected,
                            isToday: isToday,
                            pattern: AppDateFormat.patternOf(context),
                          ),
                          child: Container(
                            height: rowCellHeight,
                            margin: EdgeInsets.symmetric(
                              horizontal: cellMargin,
                            ),
                            foregroundDecoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(cellRadius),
                              border: Border.all(
                                color: isSelected
                                    ? cs.primary.withValues(alpha: 0.24)
                                    : isToday
                                    ? cs.primary.withValues(alpha: 0.16)
                                    : hasHighlight
                                    ? cs.outlineVariant.withValues(
                                        alpha: isDark ? 0.14 : 0.18,
                                      )
                                    : Colors.transparent,
                                width: isSelected ? 0.7 : 0.45,
                              ),
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? selectedFill
                                  : isToday
                                  ? cs.primary.withValues(
                                      alpha: isDark ? 0.10 : 0.06,
                                    )
                                  : hasHighlight
                                  ? cs.surfaceContainerHighest.withValues(
                                      alpha: isDark ? 0.12 : 0.22,
                                    )
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(cellRadius),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: cs.primary.withValues(
                                          alpha: isDark ? 0.16 : 0.10,
                                        ),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Material(
                              type: MaterialType.transparency,
                              child: InkWell(
                                onTap: day == null ? null : () => onPick(day),
                                borderRadius: BorderRadius.circular(cellRadius),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Center(
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          top: rowBadgeHeight,
                                          bottom: rowCounterHeight,
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              '$d',
                                              style: TextStyle(
                                                fontSize: dayFontSize,
                                                fontWeight: FontWeight.normal,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                                color: isSelected
                                                    ? selectedText
                                                    : isWorkMakeupDay
                                                    ? workColor
                                                    : isHoliday || isWeekend
                                                    ? restColor
                                                    : (isToday
                                                          ? cs.primary
                                                          : cs.onSurface
                                                                .withValues(
                                                                  alpha: 0.88,
                                                                )),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              dayLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: labelFontSize,
                                                color: isSelected
                                                    ? selectedText
                                                    : cs.onSurfaceVariant,
                                              ),
                                            ),
                                            if (hasHighlight)
                                              Container(
                                                width: 3.5,
                                                height: 3.5,
                                                margin: const EdgeInsets.only(
                                                  top: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isSelected
                                                      ? selectedText.withValues(
                                                          alpha: 0.70,
                                                        )
                                                      : cs.primary.withValues(
                                                          alpha: 0.58,
                                                        ),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (isHoliday || isWorkMakeupDay)
                                      Positioned(
                                        top: 3,
                                        left: 0,
                                        right: 0,
                                        child: Center(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 0,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  (isWorkMakeupDay
                                                          ? workColor
                                                          : restColor)
                                                      .withValues(alpha: 0.08),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    DesignTokens.radiusXs,
                                                  ),
                                            ),
                                            child: Text(
                                              isWorkMakeupDay
                                                  ? AlmanacUiCopy
                                                        .makeupWorkdayTag
                                                  : AlmanacUiCopy.holidayTag,
                                              style: TextStyle(
                                                color: cs.onSurface,
                                                fontSize: 8,
                                                letterSpacing: 0,
                                                height: 1,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (highlight != null &&
                                        highlight.labels.length > 1)
                                      Positioned(
                                        bottom: 4,
                                        right: 5,
                                        child: Text(
                                          '+${highlight.labels.length - 1}',
                                          style: TextStyle(
                                            color: cs.onSurfaceVariant,
                                            fontSize: 8,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
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
        ),
      ],
    );
  }
}

class _MonthNavButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _MonthNavButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        tapTargetSize: MaterialTapTargetSize.padded,
        foregroundColor: cs.onSurface.withValues(alpha: 0.62),
        backgroundColor: cs.surface.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.20 : 0.58,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
        ),
      ),
    );
  }
}

String _summaryTerms(String value) {
  final terms = value
      .split(RegExp(r'\s+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .take(6)
      .toList(growable: false);
  return terms.isEmpty ? value : terms.join(' ');
}

String _spacedGanzhiLine(String value) {
  return value.replaceFirst('年', '年 ').replaceFirst('月', '月 ').trim();
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

List<String> _splitAlmanacTerms(String value) {
  final terms = value
      .split(RegExp(r'[\s、，,；;。]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  return terms.isEmpty ? [value] : terms;
}

String _verticalAlmanacTerm(String value) {
  return value.runes.map((rune) => String.fromCharCodes([rune])).join('\n');
}

List<String> _splitPengZuLines(String value) {
  final seed = value
      .trim()
      .split(RegExp(r'[；;，,。]+'))
      .map((item) => item.replaceAll(RegExp(r'\s+'), '').trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  final lines = <String>[];
  for (final item in seed) {
    if (item.runes.length <= 4) {
      lines.add(item);
      continue;
    }
    final parts = RegExp(r'.{1,4}', unicode: true)
        .allMatches(item)
        .map((match) => match.group(0) ?? '')
        .where((part) => part.isNotEmpty);
    lines.addAll(parts);
  }
  if (lines.length >= 4) {
    return <String>[...lines.take(2), '', ...lines.skip(2)];
  }
  return lines.isEmpty ? [value.trim()] : lines;
}

List<String> _splitFiveElementLines(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return const <String>[];
  final tokens = normalized
      .split(' ')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  final lines = <String>[];
  if (tokens.length >= 2) {
    _addFiveElementPart(lines, tokens.join(''));
    return lines.isEmpty ? [tokens.join('  ')] : lines;
  }

  for (final token in tokens.isEmpty ? [normalized] : tokens) {
    _addFiveElementPart(lines, token);
  }
  return lines.isEmpty ? [normalized] : lines;
}

List<String> _splitClashLines(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), '');
  if (normalized.isEmpty) return const <String>[];
  final lines = <String>[];
  final directionMatch = RegExp(r'^(.*?)(煞[东南西北中]+方?)$').firstMatch(normalized);
  if (directionMatch != null) {
    final prefix = directionMatch.group(1) ?? '';
    final direction = directionMatch.group(2) ?? '';
    if (prefix.isNotEmpty) lines.add(prefix);
    if (direction.isNotEmpty) lines.add(direction);
    return lines;
  }
  return [normalized];
}

void _addFiveElementPart(List<String> lines, String value) {
  final text = value.trim();
  if (text.isEmpty) return;

  final zhiXingMatch = RegExp(r'^(.+?)([建除满平定执破危成收开闭]执位)$').firstMatch(text);
  if (zhiXingMatch != null) {
    final prefix = zhiXingMatch.group(1) ?? '';
    final zhiXing = zhiXingMatch.group(2) ?? '';
    final parts = [prefix, zhiXing].where((part) => part.isNotEmpty);
    if (parts.isNotEmpty) lines.add(parts.join('  '));
    return;
  }

  lines.add(text);
}

double _clampDouble(double value, double min, double max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

void _showAlmanacTermDictionarySheet(
  BuildContext context,
  String rawTerm,
  DateTime date,
) {
  showAppModalSheet<void>(
    context: context,
    builder: (sheetContext) {
      return ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (context, locale, _) {
          final isEn = locale == AppLocale.en;
          final cs = Theme.of(context).colorScheme;
          final explanation = AlmanacToolsService.explainAlmanacTerm(
            rawTerm,
            english: isEn,
          );
          final cat = explanation.category;
          return AppModalSheet(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      explanation.localizedTitle(locale),
                      style: TextStyle(
                        fontSize: 18,
                        color: cs.onSurface,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isEn ? 'Almanac Term' : cat,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  isEn ? 'Plain Meaning' : AlmanacUiCopy.plainExplanationTitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  explanation.localizedExplanation(locale),
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.45,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      key: const ValueKey('term_sheet_find_auspicious_btn'),
                      onPressed: () {
                        final navigator = Navigator.of(context);
                        Navigator.of(sheetContext).pop();
                        navigator.push(
                          MaterialPageRoute(
                            builder: (_) => AlmanacToolsScreen(
                              initialTab: 0,
                              initialDate: date,
                              initialActivity: rawTerm,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.auto_awesome_outlined,
                        size: 16,
                      ),
                      label: Text(
                        isEn ? 'Find Auspicious Days' : '查找该事项吉日',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _AlmanacExtendedDetailsSection extends StatelessWidget {
  final LunarAlmanacDetail detail;
  final DateTime date;

  const _AlmanacExtendedDetailsSection({
    required this.detail,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ExpandableYijiDictionaryCard(detail: detail, date: date),
        const SizedBox(height: 12),
        _DeitiesAndDirectionsCard(detail: detail),
        const SizedBox(height: 12),
        _PhenologyAndSeasonCard(detail: detail, date: date),
      ],
    );
  }
}

class _ExpandableYijiDictionaryCard extends StatefulWidget {
  final LunarAlmanacDetail detail;
  final DateTime date;

  const _ExpandableYijiDictionaryCard({
    required this.detail,
    required this.date,
  });

  @override
  State<_ExpandableYijiDictionaryCard> createState() =>
      _ExpandableYijiDictionaryCardState();
}

class _ExpandableYijiDictionaryCardState
    extends State<_ExpandableYijiDictionaryCard> {
  static const int _collapsedCount = 8;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEn = AlmanacLocaleFormat.isEn;
    final suitableAll = _splitAlmanacTerms(widget.detail.suitable);
    final avoidAll = _splitAlmanacTerms(widget.detail.avoid);
    final hasOverflow =
        suitableAll.length > _collapsedCount ||
        avoidAll.length > _collapsedCount;
    final suitableShown = _expanded
        ? suitableAll
        : suitableAll.take(_collapsedCount).toList(growable: false);
    final avoidShown = _expanded
        ? avoidAll
        : avoidAll.take(_collapsedCount).toList(growable: false);

    return AppSurfaceCard(
      key: const ValueKey('almanac_yiji_dictionary_card'),
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(
        appSurfaceStyleOf(context)?.cardRadius ?? DesignTokens.radiusCard,
      ),
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: isDark ? 0.16 : 0.22),
        width: 0.5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book_outlined, size: 17, color: cs.primary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  AlmanacUiCopy.tapTermForExplanationHint,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              if (hasOverflow)
                InkWell(
                  key: const ValueKey('almanac_yiji_expand_toggle'),
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    child: Text(
                      _expanded
                          ? AlmanacUiCopy.collapseTerms
                          : AlmanacUiCopy.expandAllTerms,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.primary,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isEn
                ? 'Suitable Activities (${suitableAll.length})'
                : '今日宜 · 全项 (${suitableAll.length})',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final term in suitableShown)
                _InteractiveTermChip(
                  rawTerm: term,
                  isAuspicious: true,
                  onTap: () => _showAlmanacTermDictionarySheet(
                    context,
                    term,
                    widget.date,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isEn
                ? 'Matters to Avoid (${avoidAll.length})'
                : '今日忌 · 全项 (${avoidAll.length})',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final term in avoidShown)
                _InteractiveTermChip(
                  rawTerm: term,
                  isAuspicious: false,
                  onTap: () => _showAlmanacTermDictionarySheet(
                    context,
                    term,
                    widget.date,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InteractiveTermChip extends StatelessWidget {
  final String rawTerm;
  final bool isAuspicious;
  final VoidCallback onTap;

  const _InteractiveTermChip({
    required this.rawTerm,
    required this.isAuspicious,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tint = isAuspicious
        ? AlmanacPalette.goldInk(isDark: isDark)
        : AlmanacPalette.inauspiciousRed(isDark: isDark);
    final display = AlmanacLocaleFormat.isEn
        ? AlmanacLocaleFormat.formatActivityTerm(rawTerm)
        : rawTerm;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tint.withValues(alpha: 0.24), width: 0.45),
        ),
        child: Text(
          display,
          style: TextStyle(
            fontSize: 12,
            color: tint,
            fontWeight: FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _DeitiesAndDirectionsCard extends StatelessWidget {
  final LunarAlmanacDetail detail;

  const _DeitiesAndDirectionsCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final huangColor = detail.isHuangDao
        ? AlmanacPalette.huangDaoInk(isDark: isDark)
        : cs.onSurfaceVariant;
    final directions = <(String label, String rawDir)>[
      (AlmanacUiCopy.caiShenLabel, detail.caiShenPosition),
      (AlmanacUiCopy.xiShenLabel, detail.xiShenPosition),
      (AlmanacUiCopy.fuShenLabel, detail.fuShenPosition),
      (AlmanacUiCopy.yangGuiLabel, detail.yangGuiPosition),
      (AlmanacUiCopy.yinGuiLabel, detail.yinGuiPosition),
    ].where((e) => e.$2.trim().isNotEmpty).toList(growable: false);
    final jiShenList = AlmanacLocaleFormat.formatShenShaList(detail.jiShen);
    final xiongShaList = AlmanacLocaleFormat.formatShenShaList(detail.xiongSha);

    return AppSurfaceCard(
      key: const ValueKey('almanac_deities_directions_card'),
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(
        appSurfaceStyleOf(context)?.cardRadius ?? DesignTokens.radiusCard,
      ),
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: isDark ? 0.16 : 0.22),
        width: 0.5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.explore_outlined, size: 17, color: cs.primary),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      AlmanacUiCopy.deitiesAndDirectionsTitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurface,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
              if (detail.tianShen.isNotEmpty)
                _AlmanacBadge(
                  text:
                      '${AlmanacUiCopy.tianShenLabel} ${AlmanacLocaleFormat.formatTianShen(detail.tianShen)} · ${detail.isHuangDao ? AlmanacUiCopy.huangDaoLabel : AlmanacUiCopy.heiDaoLabel}',
                  color: huangColor,
                ),
              if (detail.zhiXing.isNotEmpty)
                _AlmanacBadge(
                  text:
                      '${AlmanacUiCopy.zhiXingLabel}: ${AlmanacLocaleFormat.formatZhiXing(detail.zhiXing)}',
                  color: cs.primary,
                ),
            ],
          ),
          if (directions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in directions)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.20),
                        width: 0.45,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.$1,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          AlmanacLocaleFormat.formatDirection(item.$2),
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          if (jiShenList.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '${AlmanacUiCopy.jiShenLabel}: ${jiShenList.join(AlmanacLocaleFormat.isEn ? ', ' : ' ')}',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: cs.onSurface.withValues(alpha: 0.86),
              ),
            ),
          ],
          if (xiongShaList.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${AlmanacUiCopy.xiongShaLabel}: ${xiongShaList.join(AlmanacLocaleFormat.isEn ? ', ' : ' ')}',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PhenologyAndSeasonCard extends StatelessWidget {
  final LunarAlmanacDetail detail;
  final DateTime date;

  const _PhenologyAndSeasonCard({
    required this.detail,
    required this.date,
  });

  String _formatMoment(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$m-$d $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shuJiu = AlmanacLocaleFormat.formatShuJiu(detail.shuJiu);
    final sanFu = AlmanacLocaleFormat.formatSanFu(detail.sanFu);

    return AppSurfaceCard(
      key: const ValueKey('almanac_phenology_season_card'),
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(
        appSurfaceStyleOf(context)?.cardRadius ?? DesignTokens.radiusCard,
      ),
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: isDark ? 0.16 : 0.22),
        width: 0.5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.spa_outlined, size: 17, color: cs.primary),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      AlmanacUiCopy.phenologyAndSeasonTitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurface,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
              _AlmanacBadge(
                text: AlmanacUiCopy.isoWeekBadge(detail.isoWeekNumber),
                color: cs.primary,
              ),
              _AlmanacBadge(
                text: AlmanacUiCopy.dayOfYearBadge(detail.dayOfYear),
                color: cs.secondary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (detail.xingZuo.isNotEmpty)
                _AlmanacBadge(
                  text:
                      '${AlmanacUiCopy.xingZuoLabel}: ${AlmanacLocaleFormat.formatXingZuo(detail.xingZuo)}',
                  color: cs.primary,
                ),
              if (detail.yueXiang.isNotEmpty)
                _AlmanacBadge(
                  text:
                      '${AlmanacUiCopy.yueXiangLabel}: ${AlmanacLocaleFormat.formatYueXiang(detail.yueXiang)}',
                  color: AlmanacPalette.makeupIndigo(isDark: isDark),
                ),
              if (detail.hou.isNotEmpty)
                _AlmanacBadge(
                  text:
                      '${AlmanacUiCopy.houLabel}: ${AlmanacLocaleFormat.formatHou(detail.hou)}',
                  color: AlmanacPalette.termGreen(isDark: isDark),
                ),
              if (detail.wuHou.isNotEmpty)
                _AlmanacBadge(
                  text:
                      '${AlmanacUiCopy.wuHouLabel}: ${AlmanacLocaleFormat.formatWuHou(detail.wuHou)}',
                  color: AlmanacPalette.holidayTeal(isDark: isDark),
                ),
              if (shuJiu != null && shuJiu.isNotEmpty)
                _AlmanacBadge(
                  text: '${AlmanacUiCopy.shuJiuLabel}: $shuJiu',
                  color: AlmanacPalette.workdayBlue(isDark: isDark),
                ),
              if (sanFu != null && sanFu.isNotEmpty)
                _AlmanacBadge(
                  text: '${AlmanacUiCopy.sanFuLabel}: $sanFu',
                  color: AlmanacPalette.sanFuOrange(isDark: isDark),
                ),
            ],
          ),
          if (detail.currentSolarTerm != null &&
              detail.currentSolarTermExactTime != null) ...[
            const SizedBox(height: 10),
            Text(
              '${AlmanacLocaleFormat.formatSolarTerm(detail.currentSolarTerm!) ?? detail.currentSolarTerm!} · ${_formatMoment(detail.currentSolarTermExactTime!)}',
              style: TextStyle(
                fontSize: 12.5,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: appReadableForeground(
                  cs.surface,
                  AlmanacPalette.termGreen(isDark: isDark),
                ),
              ),
            ),
          ],
          if (detail.nextSolarTerm != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    '${AlmanacUiCopy.nextSolarTermLabel}: ${AlmanacUiCopy.solarTermCountdownText(detail.nextSolarTerm!)} (${_formatMoment(detail.nextSolarTerm!.exactDateTime)})',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: cs.onSurface.withValues(alpha: 0.88),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('almanac_open_solar_terms_tool_btn'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AlmanacToolsScreen(
                            initialTab: 3,
                            initialDate: date,
                          ),
                        ),
                      );
                    },
                    child: Text(AlmanacUiCopy.yearSolarTermsTitle),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
