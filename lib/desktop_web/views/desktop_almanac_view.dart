import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/almanac_locale_format.dart';
import '../../core/almanac_ui_copy.dart';
import '../../core/calendar_date_navigation.dart';
import '../../core/i18n.dart';
import '../../core/i18n_date_format.dart';
import '../../core/lunar_calendar.dart';
import '../../models/anniversary.dart';
import '../../models/countdown.dart';
import '../../providers/anniversary_provider.dart';
import '../../providers/calendar_provider.dart';
import '../../providers/countdown_provider.dart';
import '../../providers/preferences_provider.dart';
import '../../services/almanac_tools_service.dart';
import '../../services/holiday_calendar.dart';
import '../../widgets/app_date_picker.dart';
import '../desktop_web_nav.dart';
import '../desktop_web_tokens.dart';

T? _maybeWatch<T extends Object>(BuildContext context) {
  try {
    return Provider.of<T>(context);
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

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _clampSupportedDate(DateTime d) {
  final clean = _dateOnly(d);
  if (clean.year < 1900) return DateTime(1900, 1, 1);
  if (clean.year > 2099) return DateTime(2099, 12, 31);
  return clean;
}

class _MonthHighlightEntry {
  final DateTime date;
  final List<_HighlightTag> tags;

  const _MonthHighlightEntry({required this.date, required this.tags});
}

class _HighlightTag {
  final String label;
  final IconData icon;
  final Color color;

  const _HighlightTag({
    required this.label,
    required this.icon,
    required this.color,
  });
}

/// Native widescreen Desktop Web Perpetual Calendar & Almanac Workbench.
class DesktopAlmanacView extends StatefulWidget {
  final DesktopWebNavController? controller;
  final DateTime? initialDate;
  final int initialTab;
  final void Function(DesktopWebDestination destination)? onNavigate;

  const DesktopAlmanacView({
    super.key,
    this.controller,
    this.initialDate,
    this.initialTab = 0,
    this.onNavigate,
  });

  @override
  State<DesktopAlmanacView> createState() => _DesktopAlmanacViewState();
}

class _DesktopAlmanacViewState extends State<DesktopAlmanacView> {
  static const int _minYear = 1900;
  static const int _maxYear = 2099;

  late DateTime _selectedDate;
  late DateTime _focusedMonth;
  int _activeTab = 0;

  // Left panel state
  bool _highlightsExpanded = false;

  // Tab 0 (Classical Almanac) state
  bool _yiExpanded = false;
  bool _jiExpanded = false;
  late int _selectedShichenIndex;

  // Tab 1 (Auspicious Picker) state
  final TextEditingController _activitySearchCtrl = TextEditingController();
  String _selectedActivity = '嫁娶';
  late DateTime _auspiciousStartDate;
  int _auspiciousRangeDays = 90;
  bool _auspiciousWeekendsOnly = false;
  String? _auspiciousAvoidZodiac;
  int _auspiciousVisibleLimit = 40;

  // Tab 2 (Holidays) state
  late int _holidayYear;

  // Tab 3 (Date Tools & Solar Terms & BaZi) state
  late DateTime _intervalStart;
  late DateTime _intervalEnd;
  bool _intervalInclusive = false;

  late DateTime _offsetBaseDate;
  final TextEditingController _offsetDeltaCtrl = TextEditingController(
    text: '30',
  );
  int _offsetDelta = 30;
  bool _offsetWorkdaysOnly = false;

  bool _converterSolarToLunar = true;
  late DateTime _convSolarInput;
  int _convLunarYear = 2025;
  int _convLunarMonth = 6;
  int _convLunarDay = 1;
  bool _convLunarIsLeap = false;

  late int _solarTermsYear;
  late DateTime _baziBirthDate;
  int _baziHourIndex = 4; // 09:00-10:59 辰时

  DesktopWebNavController? _attachedController;
  DateTime? _lastSyncedControllerDate;
  int? _lastSyncedControllerTab;
  String? _lastTopBarSignature;

  static const List<({String branch, int hour, String labelZh, String labelEn})>
  _shichenHours = [
    (branch: '子', hour: 0, labelZh: '子时 (23:00-00:59)', labelEn: 'Zi (23-01)'),
    (branch: '丑', hour: 2, labelZh: '丑时 (01:00-02:59)', labelEn: 'Chou (01-03)'),
    (branch: '寅', hour: 4, labelZh: '寅时 (03:00-04:59)', labelEn: 'Yin (03-05)'),
    (branch: '卯', hour: 6, labelZh: '卯时 (05:00-06:59)', labelEn: 'Mao (05-07)'),
    (branch: '辰', hour: 8, labelZh: '辰时 (07:00-08:59)', labelEn: 'Chen (07-09)'),
    (branch: '巳', hour: 10, labelZh: '巳时 (09:00-10:59)', labelEn: 'Si (09-11)'),
    (branch: '午', hour: 12, labelZh: '午时 (11:00-12:59)', labelEn: 'Wu (11-13)'),
    (branch: '未', hour: 14, labelZh: '未时 (13:00-14:59)', labelEn: 'Wei (13-15)'),
    (branch: '申', hour: 16, labelZh: '申时 (15:00-16:59)', labelEn: 'Shen (15-17)'),
    (branch: '酉', hour: 18, labelZh: '酉时 (17:00-18:59)', labelEn: 'You (17-19)'),
    (branch: '戌', hour: 20, labelZh: '戌时 (19:00-20:59)', labelEn: 'Xu (19-21)'),
    (branch: '亥', hour: 22, labelZh: '亥时 (21:00-22:59)', labelEn: 'Hai (21-23)'),
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final seed = _clampSupportedDate(widget.initialDate ?? now);
    _selectedDate = seed;
    _focusedMonth = DateTime(seed.year, seed.month);
    _activeTab = widget.initialTab.clamp(0, 3);
    _selectedShichenIndex = _shichenIndexForHour(now.hour);

    final today = _clampSupportedDate(now);
    _auspiciousStartDate = today;
    _holidayYear = HolidayCalendar.supportedYears.contains(seed.year)
        ? seed.year
        : (HolidayCalendar.supportedYears.contains(today.year)
              ? today.year
              : HolidayCalendar.supportedYears.last);

    _intervalStart = today;
    _intervalEnd = _clampSupportedDate(today.add(const Duration(days: 30)));
    _offsetBaseDate = today;
    _convSolarInput = seed;
    final initialLunar =
        LunarCalendar.tryFromSolar(seed) ?? const LunarDate(2025, 6, 1);
    _convLunarYear = initialLunar.year.clamp(_minYear, _maxYear);
    _convLunarMonth = initialLunar.month;
    _convLunarDay = initialLunar.day;
    _convLunarIsLeap = initialLunar.isLeapMonth;

    _solarTermsYear = seed.year;
    _baziBirthDate = DateTime(1995, 5, 18);
    _baziHourIndex = 5;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = widget.controller ?? DesktopWebScope.maybeOf(context);
    if (!identical(_attachedController, next)) {
      _attachedController?.removeListener(_onNavControllerChanged);
      _attachedController = next;
      _attachedController?.addListener(_onNavControllerChanged);
      _syncFromController();
    }
  }

  @override
  void didUpdateWidget(covariant DesktopAlmanacView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDate != null &&
        (oldWidget.initialDate == null ||
            !_isSameDay(oldWidget.initialDate!, widget.initialDate!))) {
      _selectDate(widget.initialDate!, syncController: false);
    }
    if (widget.initialTab != oldWidget.initialTab) {
      setState(() => _activeTab = widget.initialTab.clamp(0, 3));
    }
  }

  @override
  void dispose() {
    _attachedController?.removeListener(_onNavControllerChanged);
    _activitySearchCtrl.dispose();
    _offsetDeltaCtrl.dispose();
    super.dispose();
  }

  int _shichenIndexForHour(int hour) {
    if (hour == 23 || hour == 0) return 0;
    return ((hour + 1) ~/ 2).clamp(0, 11);
  }

  void _onNavControllerChanged() {
    _syncFromController();
  }

  void _syncFromController() {
    final c = _attachedController;
    if (c == null || !mounted) return;
    var changed = false;
    final targetDate = c.focusedCalendarDate;
    if (targetDate != null) {
      final clean = _clampSupportedDate(targetDate);
      if (_lastSyncedControllerDate == null ||
          !_isSameDay(_lastSyncedControllerDate!, clean)) {
        _lastSyncedControllerDate = clean;
        if (!_isSameDay(_selectedDate, clean)) {
          _selectedDate = clean;
          _focusedMonth = DateTime(clean.year, clean.month);
          changed = true;
        }
      }
    }
    final targetTab = c.almanacTabIndex.clamp(0, 3);
    if (_lastSyncedControllerTab != targetTab) {
      _lastSyncedControllerTab = targetTab;
      if (_activeTab != targetTab) {
        _activeTab = targetTab;
        changed = true;
      }
    }
    if (changed) {
      setState(() {});
    }
  }

  void _selectDate(DateTime date, {bool syncController = true}) {
    final clean = _clampSupportedDate(date);
    setState(() {
      _selectedDate = clean;
      _focusedMonth = DateTime(clean.year, clean.month);
      _yiExpanded = false;
      _jiExpanded = false;
    });
    if (syncController) {
      _lastSyncedControllerDate = clean;
      _attachedController?.focusCalendarDate(clean);
    }
  }

  void _selectTab(int index) {
    final normalized = index.clamp(0, 3);
    if (_activeTab == normalized) return;
    setState(() => _activeTab = normalized);
    _lastSyncedControllerTab = normalized;
    _attachedController?.setAlmanacTab(normalized);
  }

  void _shiftMonth(int delta) {
    final shifted = CalendarDateNavigation.tryShiftMonths(_focusedMonth, delta);
    if (shifted == null || shifted.year < _minYear || shifted.year > _maxYear) {
      return;
    }
    final daysInTarget = DateTime(shifted.year, shifted.month + 1, 0).day;
    _selectDate(
      DateTime(shifted.year, shifted.month, _selectedDate.day.clamp(1, daysInTarget)),
    );
  }

  void _jumpToday() {
    _selectDate(DateTime.now());
  }

  void _publishTopBarSpec(AppLocale locale, LunarAlmanacDetail? detail) {
    final nav = _attachedController;
    if (nav == null) return;
    final isEn = locale == AppLocale.en;
    final dateText = I18nDateFormat.date(_selectedDate, locale: locale);
    final lunarText = detail != null
        ? AlmanacLocaleFormat.formatLunarDate(detail.lunarDate, locale)
        : '';
    final subtitle = lunarText.isEmpty ? dateText : '$dateText · $lunarText';
    final sig = '${locale.storageValue}|$subtitle';
    if (sig == _lastTopBarSignature) return;
    _lastTopBarSignature = sig;
    nav.setTopBarSpec(
      DesktopWebDestination.almanac,
      DesktopTopBarSpec(
        title: AlmanacUiCopy.pageTitle,
        breadcrumb: DesktopWebDestination.almanac.sectionLabel(locale),
        subtitle: subtitle,
        showQuickSearch: true,
        showQuickCreate: false,
        actions: [
          _TopBarActionPill(
            icon: Icons.today_outlined,
            label: isEn ? 'Today' : '回到今天',
            onTap: _jumpToday,
          ),
          _TopBarActionPill(
            icon: Icons.calendar_month_outlined,
            label: isEn ? 'Calendar' : '日程视图',
            onTap: () {
              nav.navigateTo(
                DesktopWebDestination.calendar,
                focusedDate: _selectedDate,
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final tokens = DesktopWebTokens.of(context);
        final isEn = locale == AppLocale.en;
        final (showLunar, rawFirstDayOfWeek) =
            _maybeSelect<PreferencesProvider, (bool, int)>(
              context,
              (p) => (p?.showLunar ?? true, p?.firstDayOfWeek ?? DateTime.monday),
              (true, DateTime.monday),
            );
        final calendar = _maybeWatch<CalendarProvider>(context);
        final countdowns = _maybeWatch<CountdownProvider>(context);
        final anniversaries = _maybeWatch<AnniversaryProvider>(context);

        final firstDayOfWeek = CalendarDateNavigation.normalizeFirstDayOfWeek(
          rawFirstDayOfWeek,
        );
        final detail = LunarCalendar.tryAlmanacDetail(_selectedDate);
        _publishTopBarSpec(locale, detail);

        return ColoredBox(
          key: const ValueKey('desktop_almanac_view'),
          color: Colors.transparent,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final twoColumn = width >= 820;
              final leftWidth = width >= 1120 ? 440.0 : 396.0;
              final paddingH = width >= 1120 ? 24.0 : 16.0;

              final leftColumn = _buildLeftColumn(
                tokens: tokens,
                locale: locale,
                isEn: isEn,
                showLunar: showLunar,
                firstDayOfWeek: firstDayOfWeek,
                calendar: calendar,
                countdowns: countdowns?.items ?? const <CountdownItem>[],
                anniversaries: anniversaries?.items ?? const <Anniversary>[],
              );

              final rightWorkspace = _buildRightWorkspace(
                tokens: tokens,
                locale: locale,
                isEn: isEn,
                showLunar: showLunar,
                detail: detail,
              );

              if (!twoColumn) {
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(paddingH, 16, paddingH, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      leftColumn,
                      const SizedBox(height: 16),
                      _buildTabBar(
                        tokens: tokens,
                        locale: locale,
                        isEn: isEn,
                      ),
                      const SizedBox(height: 12),
                      rightWorkspace,
                    ],
                  ),
                );
              }

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: DesktopWebTokens.contentMaxWidth,
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(paddingH, 16, paddingH, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: leftWidth,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: leftColumn,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildTabBar(
                                tokens: tokens,
                                locale: locale,
                                isEn: isEn,
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: rightWorkspace,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Left Column: Next Holiday Banner + Perpetual Month Calendar + Month Highlights
  // ---------------------------------------------------------------------------

  Widget _buildLeftColumn({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required bool isEn,
    required bool showLunar,
    required int firstDayOfWeek,
    required CalendarProvider? calendar,
    required List<CountdownItem> countdowns,
    required List<Anniversary> anniversaries,
  }) {
    final today = _dateOnly(DateTime.now());
    final nextHoliday = HolidayCalendar.nextHoliday(today);
    final highlights = _buildMonthHighlights(
      month: _focusedMonth,
      locale: locale,
      tokens: tokens,
      countdowns: countdowns,
      anniversaries: anniversaries,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (nextHoliday != null) ...[
          _buildNextHolidayBanner(
            tokens: tokens,
            locale: locale,
            isEn: isEn,
            today: today,
            nextHoliday: nextHoliday,
          ),
          const SizedBox(height: 12),
        ],
        _buildPerpetualCalendarCard(
          tokens: tokens,
          locale: locale,
          isEn: isEn,
          showLunar: showLunar,
          firstDayOfWeek: firstDayOfWeek,
          today: today,
          calendar: calendar,
        ),
        const SizedBox(height: 12),
        _buildMonthHighlightsCard(
          tokens: tokens,
          locale: locale,
          isEn: isEn,
          highlights: highlights,
        ),
      ],
    );
  }

  Widget _buildNextHolidayBanner({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required bool isEn,
    required DateTime today,
    required HolidayScheduleItem nextHoliday,
  }) {
    final daysLeft = nextHoliday.daysUntil(today);
    final name = nextHoliday.localizedName(locale);
    final rangeStr =
        '${I18nDateFormat.monthDay(nextHoliday.startDate)} – ${I18nDateFormat.monthDay(nextHoliday.endDate)}';

    return DesktopPanelCard(
      key: const ValueKey('almanac_next_holiday_banner'),
      frosted: tokens.isLiquidGlass,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      color: tokens.accentSoft,
      border: Border.all(
        color: tokens.accentBorder,
        width: DesktopWebTokens.hairlineWidth,
      ),
      onTap: () {
        setState(() => _holidayYear = nextHoliday.year);
        _selectTab(2);
      },
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tokens.accent,
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.beach_access_outlined,
              size: 18,
              color: tokens.accentForeground,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  daysLeft <= 0
                      ? (isEn ? '$name holiday ongoing' : '$name · 放假进行中')
                      : (isEn ? 'Next: $name' : '距下一法定假期 · $name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.bodyStyle.copyWith(
                    fontSize: 13,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '$rangeStr · ${AlmanacUiCopy.holidayDaysBadge(nextHoliday.totalDays, locale)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.captionStyle.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: tokens.panelSurface,
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
              border: Border.all(
                color: tokens.accentBorder,
                width: DesktopWebTokens.hairlineWidth,
              ),
            ),
            child: Text(
              daysLeft <= 0
                  ? (isEn ? 'Now' : '放假中')
                  : (isEn ? '${daysLeft}d' : '还有 $daysLeft 天'),
              style: tokens.captionStyle.copyWith(
                color: tokens.accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerpetualCalendarCard({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required bool isEn,
    required bool showLunar,
    required int firstDayOfWeek,
    required DateTime today,
    required CalendarProvider? calendar,
  }) {
    final weekdays = CalendarDateNavigation.orderedWeekdays(firstDayOfWeek);
    final monthFirst = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final offset = (monthFirst.weekday - firstDayOfWeek) % 7;
    final daysInMonth = DateTime(
      _focusedMonth.year,
      _focusedMonth.month + 1,
      0,
    ).day;
    final rowCount = ((offset + daysInMonth + 6) ~/ 7).clamp(5, 6);
    final gridStart = CalendarDateNavigation.tryShiftDays(monthFirst, -offset);

    return DesktopPanelCard(
      frosted: tokens.isLiquidGlass,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Quick year / month / today bar
          Row(
            children: [
              _PickerPillButton(
                key: const ValueKey('almanac_year_picker_button'),
                label: AlmanacUiCopy.yearHeader(_focusedMonth.year, locale),
                tokens: tokens,
                onTap: () => _pickYearDialog(tokens, locale),
              ),
              const SizedBox(width: 6),
              _PickerPillButton(
                key: const ValueKey('almanac_month_picker_button'),
                label: AlmanacUiCopy.monthHeader(_focusedMonth.month, locale),
                tokens: tokens,
                onTap: () => _pickMonthDialog(tokens, locale),
              ),
              const Spacer(),
              _SquareIconButton(
                icon: Icons.chevron_left_rounded,
                tooltip: AlmanacUiCopy.previousMonthTooltip,
                tokens: tokens,
                onTap: () => _shiftMonth(-1),
              ),
              const SizedBox(width: 4),
              InkWell(
                key: const ValueKey('almanac_today_button'),
                onTap: _jumpToday,
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXs),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _isSameDay(_selectedDate, today)
                        ? tokens.accentSoft
                        : tokens.mutedSurface,
                    borderRadius: BorderRadius.circular(
                      DesktopWebTokens.radiusXs,
                    ),
                    border: Border.all(
                      color: _isSameDay(_selectedDate, today)
                          ? tokens.accentBorder
                          : tokens.hairlineBorder,
                      width: DesktopWebTokens.hairlineWidth,
                    ),
                  ),
                  child: Text(
                    isEn ? 'Today' : '今',
                    style: tokens.captionStyle.copyWith(
                      color: _isSameDay(_selectedDate, today)
                          ? tokens.accent
                          : tokens.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _SquareIconButton(
                icon: Icons.chevron_right_rounded,
                tooltip: AlmanacUiCopy.nextMonthTooltip,
                tokens: tokens,
                onTap: () => _shiftMonth(1),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Weekday header + ISO week column
          Row(
            children: [
              SizedBox(
                width: 30,
                child: Center(
                  child: Text(
                    isEn ? 'Wk' : '周',
                    style: tokens.captionStyle.copyWith(
                      fontSize: 10.5,
                      color: tokens.textMuted,
                    ),
                  ),
                ),
              ),
              for (final wd in weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      _shortWeekday(wd, isEn),
                      style: tokens.captionStyle.copyWith(
                        fontSize: 11,
                        color: (wd == DateTime.saturday || wd == DateTime.sunday)
                            ? tokens.accent
                            : tokens.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),

          // Perpetual calendar rows
          for (var row = 0; row < rowCount; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Builder(
                    builder: (context) {
                      DateTime? rowAnchor;
                      for (var c = 0; c < 7; c++) {
                        final candidate = gridStart == null
                            ? null
                            : CalendarDateNavigation.tryShiftDays(
                                gridStart,
                                row * 7 + c,
                              );
                        if (candidate != null) {
                          rowAnchor = candidate;
                          break;
                        }
                      }
                      final isoWk = rowAnchor == null
                          ? null
                          : LunarCalendar.isoWeekNumber(rowAnchor);
                      return SizedBox(
                        width: 30,
                        height: 48,
                        child: Center(
                          child: Text(
                            isoWk == null
                                ? ''
                                : 'W${isoWk.toString().padLeft(2, '0')}',
                            style: tokens.captionStyle.copyWith(
                              fontSize: 9.5,
                              color: tokens.textMuted,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  for (var col = 0; col < 7; col++)
                    Expanded(
                      child: _buildCalendarCell(
                        day: gridStart == null
                            ? null
                            : CalendarDateNavigation.tryShiftDays(
                                gridStart,
                                row * 7 + col,
                              ),
                        today: today,
                        tokens: tokens,
                        locale: locale,
                        showLunar: showLunar,
                        calendar: calendar,
                      ),
                    ),
                ],
              ),
            ),

          const SizedBox(height: 6),
          Divider(
            height: 1,
            thickness: DesktopWebTokens.hairlineWidth,
            color: tokens.hairlineBorder,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _LegendItem(
                color: tokens.success,
                badgeText: AlmanacUiCopy.holidayTag,
                label: AlmanacUiCopy.holidayBadge,
                tokens: tokens,
              ),
              _LegendItem(
                color: tokens.warning,
                badgeText: AlmanacUiCopy.makeupWorkdayTag,
                label: AlmanacUiCopy.makeupWorkdayBadge,
                tokens: tokens,
              ),
              _LegendItem(
                color: tokens.accent,
                badgeText: isEn ? 'Term' : '节',
                label: isEn ? 'Term / Festival' : '节气 / 节日',
                tokens: tokens,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarCell({
    required DateTime? day,
    required DateTime today,
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required bool showLunar,
    required CalendarProvider? calendar,
  }) {
    if (day == null || day.year < _minYear || day.year > _maxYear) {
      return const SizedBox(height: 48);
    }
    final inCurrentMonth =
        day.year == _focusedMonth.year && day.month == _focusedMonth.month;
    final isToday = _isSameDay(day, today);
    final isSelected = _isSameDay(day, _selectedDate);
    final isHoliday = HolidayCalendar.isHoliday(day);
    final isMakeup = !isHoliday && HolidayCalendar.isWorkMakeupDay(day);
    final isWeekend =
        day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

    final lunar = showLunar ? LunarCalendar.tryFromSolar(day) : null;
    final term = showLunar ? LunarCalendar.solarTerm(day) : null;
    final solarFes = showLunar ? LunarCalendar.solarFestival(day) : null;
    final lunarFes = (showLunar && lunar != null)
        ? LunarCalendar.lunarFestival(lunar)
        : null;

    String? subText;
    var subHighlighted = false;
    if (showLunar) {
      if (solarFes != null) {
        subText = AlmanacLocaleFormat.formatFestival(solarFes, locale) ?? solarFes;
        subHighlighted = true;
      } else if (lunarFes != null) {
        subText = AlmanacLocaleFormat.formatFestival(lunarFes, locale) ?? lunarFes;
        subHighlighted = true;
      } else if (term != null) {
        subText = AlmanacLocaleFormat.formatSolarTerm(term, locale) ?? term;
        subHighlighted = true;
      } else if (lunar != null) {
        subText = locale == AppLocale.zh
            ? lunar.shortDayOrMonth
            : 'D${lunar.day}';
      }
    }

    final hasEvents = (calendar?.getEventsForDate(day).isNotEmpty ?? false);

    final Color bgColor;
    if (isToday) {
      bgColor = tokens.accent;
    } else if (isSelected) {
      bgColor = tokens.accentSoft;
    } else if (isHoliday && inCurrentMonth) {
      bgColor = tokens.success.withValues(alpha: tokens.isDark ? 0.10 : 0.06);
    } else {
      bgColor = Colors.transparent;
    }

    final Color dayColor;
    if (isToday) {
      dayColor = tokens.accentForeground;
    } else if (!inCurrentMonth) {
      dayColor = tokens.textMuted.withValues(alpha: 0.55);
    } else if (isSelected) {
      dayColor = tokens.accent;
    } else if (isHoliday) {
      dayColor = tokens.success;
    } else if (isWeekend && !isMakeup) {
      dayColor = tokens.accent;
    } else {
      dayColor = tokens.textPrimary;
    }

    final holidayLabel = isHoliday
        ? (HolidayCalendar.holidayName(day, locale: locale) ??
              AlmanacUiCopy.holidayBadge)
        : (isMakeup ? AlmanacUiCopy.makeupWorkdayBadge : null);
    final tooltipParts = <String>[
      I18nDateFormat.date(day, locale: locale),
      if (showLunar && lunar != null)
        AlmanacLocaleFormat.formatLunarDate(lunar, locale),
      if (term != null)
        AlmanacLocaleFormat.formatSolarTerm(term, locale) ?? term,
      if (solarFes != null)
        AlmanacLocaleFormat.formatFestival(solarFes, locale) ?? solarFes,
      if (lunarFes != null)
        AlmanacLocaleFormat.formatFestival(lunarFes, locale) ?? lunarFes,
      ?holidayLabel,
    ];
    final tooltipMessage = tooltipParts.toSet().join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.5),
      child: Tooltip(
        message: tooltipMessage,
        waitDuration: const Duration(milliseconds: 350),
        child: InkWell(
          onTap: () => _selectDate(day),
          borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
              border: isSelected && !isToday
                  ? Border.all(color: tokens.accent, width: 1.0)
                  : null,
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${day.day}',
                        maxLines: 1,
                        style: tokens.bodyStyle.copyWith(
                          fontSize: 13.5,
                          height: 1.1,
                          color: dayColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (subText != null) ...[
                        const SizedBox(height: 1.5),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Text(
                            subText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: tokens.captionStyle.copyWith(
                              fontSize: 9.5,
                              height: 1.1,
                              color: isToday
                                  ? tokens.accentForeground.withValues(
                                      alpha: 0.9,
                                    )
                                  : subHighlighted
                                  ? (inCurrentMonth
                                        ? tokens.accent
                                        : tokens.accent.withValues(alpha: 0.55))
                                  : (inCurrentMonth
                                        ? tokens.textMuted
                                        : tokens.textMuted.withValues(
                                            alpha: 0.45,
                                          )),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isHoliday || isMakeup)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 2.5),
                      decoration: BoxDecoration(
                        color: isToday
                            ? Colors.white.withValues(alpha: 0.22)
                            : (isHoliday ? tokens.success : tokens.warning)
                                  .withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        isHoliday
                            ? AlmanacUiCopy.holidayTag
                            : AlmanacUiCopy.makeupWorkdayTag,
                        style: tokens.captionStyle.copyWith(
                          fontSize: 8.0,
                          height: 1.15,
                          color: isToday
                              ? tokens.accentForeground
                              : (isHoliday ? tokens.success : tokens.warning),
                        ),
                      ),
                    ),
                  ),
                if (hasEvents)
                  Positioned(
                    bottom: 2,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        width: 3.5,
                        height: 3.5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isToday
                              ? tokens.accentForeground
                              : tokens.accent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_MonthHighlightEntry> _buildMonthHighlights({
    required DateTime month,
    required AppLocale locale,
    required DesktopWebTokens tokens,
    required List<CountdownItem> countdowns,
    required List<Anniversary> anniversaries,
  }) {
    final byDay = <int, List<_HighlightTag>>{};
    void add(int day, String label, IconData icon, Color color) {
      byDay
          .putIfAbsent(day, () => <_HighlightTag>[])
          .add(_HighlightTag(label: label, icon: icon, color: color));
    }

    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    for (var d = 1; d <= daysInMonth; d++) {
      final date = DateTime(month.year, month.month, d);
      final term = LunarCalendar.solarTerm(date);
      if (term != null) {
        add(
          d,
          AlmanacUiCopy.termHighlight(term),
          Icons.eco_outlined,
          tokens.success,
        );
      }
      final festivals = LunarCalendar.allFestivals(date);
      for (final f in festivals) {
        add(
          d,
          AlmanacLocaleFormat.formatFestival(f, locale) ?? f,
          Icons.celebration_outlined,
          tokens.warning,
        );
      }
      if (HolidayCalendar.isHoliday(date)) {
        final hName = HolidayCalendar.holidayName(date, locale: locale);
        add(
          d,
          hName == null
              ? AlmanacUiCopy.holidayBadge
              : '${AlmanacUiCopy.holidayTag} · $hName',
          Icons.beach_access_outlined,
          tokens.success,
        );
      } else if (HolidayCalendar.isWorkMakeupDay(date)) {
        add(
          d,
          AlmanacUiCopy.makeupWorkdayBadge,
          Icons.work_outline,
          tokens.warning,
        );
      }
    }

    for (final c in countdowns) {
      if (c.targetDate.year == month.year &&
          c.targetDate.month == month.month) {
        add(
          c.targetDate.day,
          AlmanacUiCopy.countdownHighlight(c.title),
          Icons.hourglass_bottom_outlined,
          tokens.info,
        );
      }
    }

    for (final a in anniversaries) {
      final occ = _anniversaryOccurrenceInMonth(a, month.year, month.month);
      if (occ != null) {
        add(
          occ.day,
          a.type == AnniversaryType.birthday
              ? AlmanacUiCopy.birthdayHighlight(a.title)
              : AlmanacUiCopy.memorialHighlight(a.title),
          a.type == AnniversaryType.birthday
              ? Icons.cake_outlined
              : Icons.favorite_border,
          tokens.danger,
        );
      }
    }

    final result = byDay.entries
        .map(
          (e) => _MonthHighlightEntry(
            date: DateTime(month.year, month.month, e.key),
            tags: e.value,
          ),
        )
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  DateTime? _anniversaryOccurrenceInMonth(
    Anniversary item,
    int year,
    int month,
  ) {
    if (item.type == AnniversaryType.normal) {
      return item.originDate.year == year && item.originDate.month == month
          ? item.originDate
          : null;
    }
    if (item.calendarType == AnniversaryCalendarType.lunar) {
      final lm = item.lunarMonth;
      final ld = item.lunarDay;
      if (lm == null || ld == null) return null;
      final solar = LunarCalendar.tryToSolar(
        year,
        lm,
        ld,
        isLeap: item.lunarIsLeap,
      );
      if (solar != null && solar.year == year && solar.month == month) {
        return solar;
      }
      return null;
    }
    final solar = DateTime(year, item.originDate.month, item.originDate.day);
    if (solar.month != item.originDate.month ||
        solar.day != item.originDate.day) {
      return null;
    }
    return solar.month == month ? solar : null;
  }

  Widget _buildMonthHighlightsCard({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required bool isEn,
    required List<_MonthHighlightEntry> highlights,
  }) {
    const collapsedLimit = 6;
    final hasOverflow = highlights.length > collapsedLimit;
    final visible = _highlightsExpanded
        ? highlights
        : highlights.take(collapsedLimit).toList(growable: false);

    return DesktopPanelCard(
      frosted: tokens.isLiquidGlass,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AlmanacUiCopy.monthHighlightsTitle,
                  style: tokens.cardTitleStyle.copyWith(fontSize: 14),
                ),
              ),
              Text(
                AlmanacUiCopy.monthBadge(_focusedMonth.month),
                style: tokens.captionStyle.copyWith(color: tokens.accent),
              ),
              if (hasOverflow) ...[
                const SizedBox(width: 8),
                InkWell(
                  key: const ValueKey('almanac_highlights_expand_toggle'),
                  onTap: () => setState(
                    () => _highlightsExpanded = !_highlightsExpanded,
                  ),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    child: Text(
                      _highlightsExpanded
                          ? AlmanacUiCopy.collapseTerms
                          : '${AlmanacUiCopy.expandAllTerms} (${highlights.length})',
                      style: tokens.captionStyle.copyWith(color: tokens.accent),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (highlights.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                AlmanacUiCopy.monthHighlightsEmpty,
                style: tokens.bodyMutedStyle,
              ),
            )
          else
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 8,
                  thickness: DesktopWebTokens.hairlineWidth,
                  color: tokens.hairlineBorder,
                ),
              DesktopHoverTile(
                key: ValueKey('almanac_highlight_${visible[i].date.day}'),
                selected: _isSameDay(visible[i].date, _selectedDate),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                onTap: () => _selectDate(visible[i].date),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 38,
                      child: Text(
                        '${visible[i].date.month}/${visible[i].date.day}',
                        style: tokens.captionStyle.copyWith(
                          color: _isSameDay(visible[i].date, _selectedDate)
                              ? tokens.accent
                              : tokens.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          for (final tag in visible[i].tags)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: tag.color.withValues(
                                  alpha: tokens.isDark ? 0.18 : 0.11,
                                ),
                                borderRadius: BorderRadius.circular(
                                  DesktopWebTokens.radiusPill,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(tag.icon, size: 11, color: tag.color),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      tag.label,
                                      style: tokens.captionStyle.copyWith(
                                        fontSize: 11,
                                        color: tokens.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Right Workspace Segmented Tab Bar + Tabs 0..3
  // ---------------------------------------------------------------------------

  Widget _buildTabBar({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required bool isEn,
  }) {
    final tabs = <(int, IconData, String)>[
      (0, Icons.wb_twilight_rounded, AlmanacUiCopy.tabClassicalAlmanac),
      (1, Icons.auto_awesome_outlined, AlmanacUiCopy.tabAuspiciousPicker),
      (2, Icons.beach_access_outlined, AlmanacUiCopy.tabHolidaySchedule),
      (3, Icons.swap_horiz_rounded, isEn ? 'Tools & BaZi' : '日期工具 & 节气八字'),
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: tokens.panelSurface,
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
        border: Border.all(
          color: tokens.hairlineBorder,
          width: DesktopWebTokens.hairlineWidth,
        ),
        boxShadow: tokens.cardShadow,
      ),
      child: Row(
        children: [
          for (final (idx, icon, label) in tabs)
            Expanded(
              child: InkWell(
                key: ValueKey('almanac_tab_$idx'),
                onTap: () => _selectTab(idx),
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _activeTab == idx
                        ? tokens.accentSoft
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(
                      DesktopWebTokens.radiusSm,
                    ),
                    border: _activeTab == idx
                        ? Border.all(
                            color: tokens.accentBorder,
                            width: DesktopWebTokens.hairlineWidth,
                          )
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 15,
                        color: _activeTab == idx
                            ? tokens.accent
                            : tokens.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tokens.captionStyle.copyWith(
                            fontSize: 12.5,
                            color: _activeTab == idx
                                ? tokens.accent
                                : tokens.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRightWorkspace({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required bool isEn,
    required bool showLunar,
    required LunarAlmanacDetail? detail,
  }) {
    return switch (_activeTab) {
      0 => _buildClassicalAlmanacTab(
        tokens: tokens,
        locale: locale,
        isEn: isEn,
        showLunar: showLunar,
        detail: detail,
      ),
      1 => _buildAuspiciousPickerTab(
        tokens: tokens,
        locale: locale,
        isEn: isEn,
      ),
      2 => _buildHolidayScheduleTab(
        tokens: tokens,
        locale: locale,
        isEn: isEn,
      ),
      _ => _buildDateToolsAndBaziTab(
        tokens: tokens,
        locale: locale,
        isEn: isEn,
      ),
    };
  }

  // ---------------------------------------------------------------------------
  // Tab 0: 老黄历详版 (Classical Almanac Detail)
  // ---------------------------------------------------------------------------

  Widget _buildClassicalAlmanacTab({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required bool isEn,
    required bool showLunar,
    required LunarAlmanacDetail? detail,
  }) {
    if (detail == null) {
      return DesktopPanelCard(
        padding: const EdgeInsets.all(24),
        child: Text(
          AlmanacUiCopy.almanacUnavailable,
          style: tokens.bodyMutedStyle,
        ),
      );
    }

    final today = _dateOnly(DateTime.now());
    final diffDays = _selectedDate.difference(today).inDays;
    final relativeLabel = switch (diffDays) {
      0 => isEn ? 'Today' : '今天',
      1 => isEn ? 'Tomorrow' : '明天',
      -1 => isEn ? 'Yesterday' : '昨天',
      > 1 => isEn ? 'In $diffDays d' : '$diffDays天后',
      _ => isEn ? '${-diffDays} d ago' : '${-diffDays}天前',
    };

    final isHoliday = HolidayCalendar.isHoliday(_selectedDate);
    final isMakeup = !isHoliday && HolidayCalendar.isWorkMakeupDay(_selectedDate);
    final holidayTitle = HolidayCalendar.holidayName(_selectedDate, locale: locale);
    final festivals = LunarCalendar.allFestivals(_selectedDate);

    final yiTerms = _splitTerms(detail.suitable);
    final jiTerms = _splitTerms(detail.avoid);
    final selectedHourIndex = _selectedShichenIndex
        .clamp(
          0,
          math.max(0, detail.hourFortuneItems.length - 1),
        )
        .toInt();
    final selectedHour = detail.hourFortuneItems.isEmpty
        ? null
        : detail.hourFortuneItems[selectedHourIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Hero Date + Lunar + Ganzhi + Zodiac + XingZuo + HuangDao Badge
        DesktopPanelCard(
          frosted: tokens.isLiquidGlass,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _BadgePill(
                          label: relativeLabel,
                          color: diffDays == 0
                              ? tokens.accent
                              : tokens.textSecondary,
                          tokens: tokens,
                        ),
                        _BadgePill(
                          label: AlmanacUiCopy.isoWeekBadge(
                            detail.isoWeekNumber,
                            locale,
                          ),
                          color: tokens.textSecondary,
                          tokens: tokens,
                        ),
                        _BadgePill(
                          label: AlmanacUiCopy.dayOfYearBadge(
                            detail.dayOfYear,
                            locale,
                          ),
                          color: tokens.textSecondary,
                          tokens: tokens,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SquareIconButton(
                    icon: Icons.chevron_left_rounded,
                    tooltip: AlmanacUiCopy.previousDayTooltip,
                    tokens: tokens,
                    onTap: () {
                      final prev = CalendarDateNavigation.tryShiftDays(
                        _selectedDate,
                        -1,
                      );
                      if (prev != null && prev.year >= _minYear) {
                        _selectDate(prev);
                      }
                    },
                  ),
                  const SizedBox(width: 4),
                  _SquareIconButton(
                    icon: Icons.chevron_right_rounded,
                    tooltip: AlmanacUiCopy.nextDayTooltip,
                    tokens: tokens,
                    onTap: () {
                      final next = CalendarDateNavigation.tryShiftDays(
                        _selectedDate,
                        1,
                      );
                      if (next != null && next.year <= _maxYear) {
                        _selectDate(next);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    AlmanacUiCopy.fullDateTitle(
                      _selectedDate,
                      locale,
                      null,
                    ),
                    style: tokens.heroTitleStyle.copyWith(fontSize: 22),
                  ),
                  if (showLunar)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
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
                      child: Text(
                        AlmanacLocaleFormat.formatFullLunarDate(
                          detail.lunarDate,
                          locale: locale,
                        ),
                        style: tokens.bodyStyle.copyWith(color: tokens.accent),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                AlmanacLocaleFormat.formatGanzhiLine(detail, locale),
                style: tokens.bodyMutedStyle,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _BadgePill(
                    label:
                        '${isEn ? 'Zodiac' : '生肖'} · ${AlmanacLocaleFormat.formatZodiac(detail.yearZodiac, locale)}',
                    color: tokens.info,
                    tokens: tokens,
                  ),
                  _BadgePill(
                    label: AlmanacLocaleFormat.formatXingZuo(
                      detail.xingZuo,
                      locale,
                    ),
                    color: tokens.info,
                    tokens: tokens,
                  ),
                  _BadgePill(
                    label:
                        '${detail.isHuangDao ? AlmanacUiCopy.huangDaoLabel : AlmanacUiCopy.heiDaoLabel} · ${AlmanacLocaleFormat.formatTianShen(detail.tianShen, locale)} (${AlmanacLocaleFormat.formatTianShenLuck(detail.tianShenLuck, locale)})',
                    color: detail.isHuangDao ? tokens.success : tokens.warning,
                    tokens: tokens,
                  ),
                  if (isHoliday)
                    _BadgePill(
                      label:
                          '${AlmanacUiCopy.holidayTag} · ${holidayTitle ?? AlmanacUiCopy.holidayBadge}',
                      color: tokens.success,
                      tokens: tokens,
                    ),
                  if (isMakeup)
                    _BadgePill(
                      label: AlmanacUiCopy.makeupWorkdayBadge,
                      color: tokens.warning,
                      tokens: tokens,
                    ),
                  if (detail.currentSolarTerm != null)
                    _BadgePill(
                      label: _formatCurrentTermBadge(detail, locale),
                      color: tokens.success,
                      tokens: tokens,
                    ),
                  for (final f in festivals)
                    _BadgePill(
                      label: AlmanacLocaleFormat.formatFestival(f, locale) ?? f,
                      color: tokens.warning,
                      tokens: tokens,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2. Full 宜 / 忌 Card (expandable + clickable plain-language explanation)
        DesktopPanelCard(
          frosted: tokens.isLiquidGlass,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 16,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isEn ? 'Daily Suitable & Avoid' : '每日宜忌（点击词条查白话释义）',
                      style: tokens.cardTitleStyle.copyWith(fontSize: 14.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildYiJiSection(
                title: AlmanacUiCopy.auspiciousLabel,
                badgeColor: tokens.success,
                terms: yiTerms,
                expanded: _yiExpanded,
                onToggleExpand: () => setState(() => _yiExpanded = !_yiExpanded),
                tokens: tokens,
                locale: locale,
                isEn: isEn,
              ),
              const SizedBox(height: 12),
              Divider(
                height: 1,
                thickness: DesktopWebTokens.hairlineWidth,
                color: tokens.hairlineBorder,
              ),
              const SizedBox(height: 12),
              _buildYiJiSection(
                title: AlmanacUiCopy.inauspiciousLabel,
                badgeColor: tokens.danger,
                terms: jiTerms,
                expanded: _jiExpanded,
                onToggleExpand: () => setState(() => _jiExpanded = !_jiExpanded),
                tokens: tokens,
                locale: locale,
                isEn: isEn,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 3. 神煞方位卡 (Deities & Compass Positions)
        DesktopPanelCard(
          frosted: tokens.isLiquidGlass,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AlmanacUiCopy.deitiesAndDirectionsTitle,
                style: tokens.cardTitleStyle.copyWith(fontSize: 14.5),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final directionTiles = [
                    _DirectionTile(
                      label: AlmanacUiCopy.caiShenLabel,
                      value: AlmanacLocaleFormat.formatDirection(
                        detail.caiShenPosition,
                        locale,
                      ),
                      color: tokens.warning,
                      tokens: tokens,
                    ),
                    _DirectionTile(
                      label: AlmanacUiCopy.xiShenLabel,
                      value: AlmanacLocaleFormat.formatDirection(
                        detail.xiShenPosition,
                        locale,
                      ),
                      color: tokens.danger,
                      tokens: tokens,
                    ),
                    _DirectionTile(
                      label: AlmanacUiCopy.fuShenLabel,
                      value: AlmanacLocaleFormat.formatDirection(
                        detail.fuShenPosition,
                        locale,
                      ),
                      color: tokens.success,
                      tokens: tokens,
                    ),
                    _DirectionTile(
                      label: AlmanacUiCopy.yangGuiLabel,
                      value: AlmanacLocaleFormat.formatDirection(
                        detail.yangGuiPosition,
                        locale,
                      ),
                      color: tokens.accent,
                      tokens: tokens,
                    ),
                    _DirectionTile(
                      label: AlmanacUiCopy.yinGuiLabel,
                      value: AlmanacLocaleFormat.formatDirection(
                        detail.yinGuiPosition,
                        locale,
                      ),
                      color: tokens.info,
                      tokens: tokens,
                    ),
                  ];
                  if (constraints.maxWidth >= 520) {
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < directionTiles.length; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(child: directionTiles[i]),
                          ],
                        ],
                      ),
                    );
                  }
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: directionTiles,
                  );
                },
              ),
              const SizedBox(height: 12),
              _ShenShaRow(
                label: AlmanacUiCopy.jiShenLabel,
                color: tokens.success,
                items: AlmanacLocaleFormat.formatShenShaList(
                  detail.jiShen,
                  locale,
                ),
                tokens: tokens,
                emptyLabel: isEn ? 'None' : '无',
              ),
              const SizedBox(height: 8),
              _ShenShaRow(
                label: AlmanacUiCopy.xiongShaLabel,
                color: tokens.warning,
                items: AlmanacLocaleFormat.formatShenShaList(
                  detail.xiongSha,
                  locale,
                ),
                tokens: tokens,
                emptyLabel: isEn ? 'None' : '无',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 4. Classical 6-field Almanac Matrix + Phenology
        LayoutBuilder(
          builder: (context, constraints) {
            final sideBySide = constraints.maxWidth >= 560;
            final classicalCard = _buildClassicalGridCard(
              detail: detail,
              tokens: tokens,
              locale: locale,
              isEn: isEn,
            );
            final phenologyCard = _buildPhenologyCard(
              detail: detail,
              tokens: tokens,
              locale: locale,
              isEn: isEn,
            );
            if (!sideBySide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  classicalCard,
                  const SizedBox(height: 12),
                  phenologyCard,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 12, child: classicalCard),
                const SizedBox(width: 12),
                Expanded(flex: 10, child: phenologyCard),
              ],
            );
          },
        ),
        const SizedBox(height: 12),

        // 5. 十二时辰吉凶条 + Inline Shichen Inspector
        DesktopPanelCard(
          frosted: tokens.isLiquidGlass,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.schedule_outlined,
                    size: 16,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      AlmanacUiCopy.shichenTitle,
                      style: tokens.cardTitleStyle.copyWith(fontSize: 14.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      isEn ? 'Click an hour for details' : '点击时辰查看宜忌与方位',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: tokens.captionStyle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cols = constraints.maxWidth >= 520 ? 6 : 4;
                  const gap = 6.0;
                  final tileWidth =
                      (constraints.maxWidth - gap * (cols - 1)) / cols;
                  final nowHourIdx = _isSameDay(_selectedDate, today)
                      ? _shichenIndexForHour(DateTime.now().hour)
                      : -1;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (var i = 0; i < detail.hourFortuneItems.length; i++)
                        SizedBox(
                          width: tileWidth,
                          child: _ShichenTile(
                            key: ValueKey('almanac_shichen_$i'),
                            item: detail.hourFortuneItems[i],
                            selected: i == selectedHourIndex,
                            isCurrentHour: i == nowHourIdx,
                            locale: locale,
                            tokens: tokens,
                            onTap: () =>
                                setState(() => _selectedShichenIndex = i),
                          ),
                        ),
                    ],
                  );
                },
              ),
              if (selectedHour != null) ...[
                const SizedBox(height: 12),
                _buildSelectedShichenInspector(
                  item: selectedHour,
                  tokens: tokens,
                  locale: locale,
                  isEn: isEn,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildYiJiSection({
    required String title,
    required Color badgeColor,
    required List<String> terms,
    required bool expanded,
    required VoidCallback onToggleExpand,
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required bool isEn,
  }) {
    const limit = 8;
    final hasMore = terms.length > limit;
    final visible = expanded ? terms : terms.take(limit).toList(growable: false);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: isEn ? 48 : 28,
            minHeight: 28,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: tokens.isDark ? 0.22 : 0.14),
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
            ),
            child: Text(
              title,
              maxLines: 1,
              softWrap: false,
              style: tokens.bodyStyle.copyWith(
                fontSize: 12.5,
                color: badgeColor,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final term in visible)
                    InkWell(
                      key: ValueKey('almanac_term_${title}_$term'),
                      onTap: () => _showTermDialog(
                        term,
                        badgeLabel: title,
                        badgeColor: badgeColor,
                        tokens: tokens,
                        locale: locale,
                        isEn: isEn,
                      ),
                      borderRadius: BorderRadius.circular(
                        DesktopWebTokens.radiusXs,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.mutedSurface,
                          borderRadius: BorderRadius.circular(
                            DesktopWebTokens.radiusXs,
                          ),
                          border: Border.all(
                            color: tokens.hairlineBorder,
                            width: DesktopWebTokens.hairlineWidth,
                          ),
                        ),
                        child: Text(
                          AlmanacLocaleFormat.formatActivityTerm(term, locale),
                          style: tokens.captionStyle.copyWith(
                            fontSize: 12,
                            color: tokens.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  if (hasMore)
                    InkWell(
                      onTap: onToggleExpand,
                      borderRadius: BorderRadius.circular(
                        DesktopWebTokens.radiusXs,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.accentSoft,
                          borderRadius: BorderRadius.circular(
                            DesktopWebTokens.radiusXs,
                          ),
                        ),
                        child: Text(
                          expanded
                              ? AlmanacUiCopy.collapseTerms
                              : '${AlmanacUiCopy.expandAllTerms} (${terms.length})',
                          style: tokens.captionStyle.copyWith(
                            fontSize: 12,
                            color: tokens.accent,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildClassicalGridCard({
    required LunarAlmanacDetail detail,
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required bool isEn,
  }) {
    final rows = <(String, String)>[
      (
        AlmanacUiCopy.fetalGodLabel,
        AlmanacLocaleFormat.formatFetalGod(detail.fetalGod, locale),
      ),
      (
        AlmanacUiCopy.pengZuLabel,
        AlmanacLocaleFormat.formatPengZu(detail.pengZu, locale),
      ),
      (
        AlmanacUiCopy.fiveElementsLabel,
        AlmanacLocaleFormat.formatFiveElements(
          detail.fiveElements,
          dayNaYin: detail.dayNaYin,
          zhiXing: detail.zhiXing,
          locale: locale,
        ),
      ),
      (
        AlmanacUiCopy.zhiXingLabel,
        AlmanacLocaleFormat.formatZhiXing(detail.zhiXing, locale),
      ),
      (
        AlmanacUiCopy.mansionLabel,
        AlmanacLocaleFormat.formatMansion(detail.mansion, locale),
      ),
      (
        AlmanacUiCopy.clashLabel,
        AlmanacLocaleFormat.formatClash(detail, locale),
      ),
    ];

    return DesktopPanelCard(
      frosted: tokens.isLiquidGlass,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isEn ? 'Classical Almanac Details' : '传统黄历明细',
            style: tokens.cardTitleStyle.copyWith(fontSize: 14.5),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 12,
                thickness: DesktopWebTokens.hairlineWidth,
                color: tokens.hairlineBorder,
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: isEn ? 104 : 76,
                  child: Text(
                    rows[i].$1,
                    style: tokens.captionStyle.copyWith(color: tokens.textMuted),
                  ),
                ),
                Expanded(
                  child: Text(
                    rows[i].$2.isEmpty ? '—' : rows[i].$2,
                    style: tokens.bodyStyle.copyWith(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhenologyCard({
    required LunarAlmanacDetail detail,
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required bool isEn,
  }) {
    final nextTerm = detail.nextSolarTerm;
    final shuJiu = AlmanacLocaleFormat.formatShuJiu(detail.shuJiu, locale);
    final sanFu = AlmanacLocaleFormat.formatSanFu(detail.sanFu, locale);
    final hou = AlmanacLocaleFormat.formatHou(detail.hou, locale);
    final wuHou = AlmanacLocaleFormat.formatWuHou(detail.wuHou, locale);
    final yueXiang = AlmanacLocaleFormat.formatYueXiang(detail.yueXiang, locale);

    return DesktopPanelCard(
      frosted: tokens.isLiquidGlass,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AlmanacUiCopy.phenologyAndSeasonTitle,
            style: tokens.cardTitleStyle.copyWith(fontSize: 14.5),
          ),
          if (nextTerm != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: tokens.accentSoft,
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
                border: Border.all(
                  color: tokens.accentBorder,
                  width: DesktopWebTokens.hairlineWidth,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AlmanacUiCopy.solarTermCountdownText(nextTerm, locale),
                    style: tokens.bodyStyle.copyWith(
                      fontSize: 12.5,
                      color: tokens.accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${isEn ? 'Exact time' : '交节时刻'}: ${I18nDateFormat.fullDateTime(nextTerm.exactDateTime, locale: locale)}',
                    style: tokens.captionStyle,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          _PhenologyRow(
            label: AlmanacUiCopy.houLabel,
            value: hou,
            isEn: isEn,
            tokens: tokens,
          ),
          _PhenologyRow(
            label: AlmanacUiCopy.wuHouLabel,
            value: wuHou,
            isEn: isEn,
            tokens: tokens,
          ),
          _PhenologyRow(
            label: AlmanacUiCopy.yueXiangLabel,
            value: yueXiang,
            isEn: isEn,
            tokens: tokens,
          ),
          if (shuJiu != null && shuJiu.isNotEmpty)
            _PhenologyRow(
              label: AlmanacUiCopy.shuJiuLabel,
              value: shuJiu,
              isEn: isEn,
              tokens: tokens,
            ),
          if (sanFu != null && sanFu.isNotEmpty)
            _PhenologyRow(
              label: AlmanacUiCopy.sanFuLabel,
              value: sanFu,
              isEn: isEn,
              tokens: tokens,
            ),
        ],
      ),
    );
  }

  Widget _buildSelectedShichenInspector({
    required AlmanacHourFortune item,
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required bool isEn,
  }) {
    final yi = item.yi;
    final ji = item.ji;
    return Container(
      key: const ValueKey('almanac_shichen_detail'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.mutedSurface,
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
        border: Border.all(
          color: tokens.hairlineBorder,
          width: DesktopWebTokens.hairlineWidth,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                AlmanacUiCopy.hourFortuneDialogTitle(
                  item.branch,
                  item.isAuspicious,
                  locale: locale,
                ),
                style: tokens.cardTitleStyle.copyWith(fontSize: 14),
              ),
              _BadgePill(
                label: item.range,
                color: tokens.textSecondary,
                tokens: tokens,
              ),
              _BadgePill(
                label:
                    '${AlmanacLocaleFormat.formatGanZhi(item.ganzhi, locale)} · ${AlmanacLocaleFormat.formatTianShen(item.deity, locale)} (${AlmanacLocaleFormat.formatTianShenType(item.tianShenType, locale)})',
                color: item.isAuspicious ? tokens.success : tokens.warning,
                tokens: tokens,
              ),
              if (item.naYin.isNotEmpty)
                _BadgePill(
                  label:
                      '${AlmanacUiCopy.hourNaYinLabel}: ${AlmanacLocaleFormat.formatNaYin(item.naYin, locale)}',
                  color: tokens.info,
                  tokens: tokens,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              if (item.caiPosition.isNotEmpty)
                Text(
                  '${AlmanacUiCopy.caiShenLabel}: ${AlmanacLocaleFormat.formatDirection(item.caiPosition, locale)}',
                  style: tokens.captionStyle,
                ),
              if (item.xiPosition.isNotEmpty)
                Text(
                  '${AlmanacUiCopy.xiShenLabel}: ${AlmanacLocaleFormat.formatDirection(item.xiPosition, locale)}',
                  style: tokens.captionStyle,
                ),
              if (item.fuPosition.isNotEmpty)
                Text(
                  '${AlmanacUiCopy.fuShenLabel}: ${AlmanacLocaleFormat.formatDirection(item.fuPosition, locale)}',
                  style: tokens.captionStyle,
                ),
              if (item.chongSha.isNotEmpty)
                Text(
                  '${AlmanacUiCopy.hourChongShaLabel}: ${AlmanacLocaleFormat.formatHourChongSha(item.chongSha, locale)}',
                  style: tokens.captionStyle,
                ),
            ],
          ),
          if (yi.isNotEmpty) ...[
            const SizedBox(height: 8),
            _InlineHourTermRow(
              badge: AlmanacUiCopy.hourYiLabel,
              badgeColor: tokens.success,
              terms: yi,
              locale: locale,
              tokens: tokens,
              onTapTerm: (term) => _showTermDialog(
                term,
                badgeLabel: AlmanacUiCopy.auspiciousLabel,
                badgeColor: tokens.success,
                tokens: tokens,
                locale: locale,
                isEn: isEn,
              ),
            ),
          ],
          if (ji.isNotEmpty) ...[
            const SizedBox(height: 6),
            _InlineHourTermRow(
              badge: AlmanacUiCopy.hourJiLabel,
              badgeColor: tokens.danger,
              terms: ji,
              locale: locale,
              tokens: tokens,
              onTapTerm: (term) => _showTermDialog(
                term,
                badgeLabel: AlmanacUiCopy.inauspiciousLabel,
                badgeColor: tokens.danger,
                tokens: tokens,
                locale: locale,
                isEn: isEn,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: 择吉日查询 (Auspicious Day Finder)
  // ---------------------------------------------------------------------------

  Widget _buildAuspiciousPickerTab({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required bool isEn,
  }) {
    final query = _activitySearchCtrl.text.trim().isNotEmpty
        ? _activitySearchCtrl.text.trim()
        : _selectedActivity;
    final matches = AlmanacToolsService.findAuspiciousDays(
      activity: query,
      startDate: _auspiciousStartDate,
      rangeDays: _auspiciousRangeDays,
      weekendsOrHolidaysOnly: _auspiciousWeekendsOnly,
      avoidZodiac: _auspiciousAvoidZodiac,
    );
    final visibleMatches = matches
        .take(_auspiciousVisibleLimit)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPanelCard(
          frosted: tokens.isLiquidGlass,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      AlmanacUiCopy.selectActivityLabel,
                      style: tokens.cardTitleStyle.copyWith(fontSize: 14.5),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: TextField(
                      key: const ValueKey('almanac_auspicious_search_field'),
                      controller: _activitySearchCtrl,
                      style: tokens.bodyStyle.copyWith(fontSize: 12.5),
                      onChanged: (_) => setState(() {
                        _auspiciousVisibleLimit = 40;
                      }),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: AlmanacUiCopy.searchActivityHint,
                        prefixIcon: const Icon(Icons.search_rounded, size: 16),
                        suffixIcon: _activitySearchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded, size: 15),
                                onPressed: () => setState(() {
                                  _activitySearchCtrl.clear();
                                  _auspiciousVisibleLimit = 40;
                                }),
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final preset in AlmanacToolsService.presetActivities)
                    _FilterChoicePill(
                      key: ValueKey('almanac_preset_${preset.key}'),
                      label: preset.localizedLabel(locale),
                      selected:
                          _activitySearchCtrl.text.trim().isEmpty &&
                          _selectedActivity == preset.key,
                      tokens: tokens,
                      onTap: () => setState(() {
                        _activitySearchCtrl.clear();
                        _selectedActivity = preset.key;
                        _auspiciousVisibleLimit = 40;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(
                height: 1,
                thickness: DesktopWebTokens.hairlineWidth,
                color: tokens.hairlineBorder,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _DatePickChip(
                    label:
                        '${AlmanacUiCopy.startDateLabel}: ${I18nDateFormat.date(_auspiciousStartDate, locale: locale)}',
                    tokens: tokens,
                    onTap: () async {
                      final picked = await _pickSolarDate(
                        _auspiciousStartDate,
                        title: AlmanacUiCopy.startDateLabel,
                      );
                      if (picked != null && mounted) {
                        setState(() {
                          _auspiciousStartDate = _clampSupportedDate(picked);
                          _auspiciousVisibleLimit = 40;
                        });
                      }
                    },
                  ),
                  for (final days in const [30, 90, 180, 365])
                    _FilterChoicePill(
                      key: ValueKey('almanac_range_$days'),
                      label: AlmanacUiCopy.rangeDaysOption(days, locale),
                      selected: _auspiciousRangeDays == days,
                      tokens: tokens,
                      onTap: () => setState(() {
                        _auspiciousRangeDays = days;
                        _auspiciousVisibleLimit = 40;
                      }),
                    ),
                  _FilterChoicePill(
                    key: const ValueKey('almanac_auspicious_weekend_toggle'),
                    label: AlmanacUiCopy.weekendsOrHolidaysOnlyLabel,
                    selected: _auspiciousWeekendsOnly,
                    tokens: tokens,
                    onTap: () => setState(() {
                      _auspiciousWeekendsOnly = !_auspiciousWeekendsOnly;
                      _auspiciousVisibleLimit = 40;
                    }),
                  ),
                  _ZodiacAvoidMenu(
                    selectedZodiac: _auspiciousAvoidZodiac,
                    locale: locale,
                    tokens: tokens,
                    onChanged: (z) => setState(() {
                      _auspiciousAvoidZodiac = z;
                      _auspiciousVisibleLimit = 40;
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                AlmanacUiCopy.auspiciousMatchesSummary(matches.length, locale),
                style: tokens.captionStyle.copyWith(color: tokens.textSecondary),
              ),
              if (matches.isNotEmpty)
                Text(
                  isEn
                      ? 'Click a row to focus on calendar'
                      : '点击任意日期行即可在左侧日历定位查看',
                  style: tokens.captionStyle,
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (matches.isEmpty)
          DesktopPanelCard(
            padding: const EdgeInsets.all(24),
            child: Text(
              AlmanacUiCopy.noAuspiciousDaysFound,
              style: tokens.bodyMutedStyle,
              textAlign: TextAlign.center,
            ),
          )
        else ...[
          for (var i = 0; i < visibleMatches.length; i++) ...[
            _AuspiciousResultCard(
              key: ValueKey(
                'almanac_auspicious_result_${visibleMatches[i].date.year}-${visibleMatches[i].date.month}-${visibleMatches[i].date.day}',
              ),
              match: visibleMatches[i],
              selected: _isSameDay(visibleMatches[i].date, _selectedDate),
              locale: locale,
              isEn: isEn,
              tokens: tokens,
              onJumpCalendar: () => _selectDate(visibleMatches[i].date),
              onOpenDetail: () {
                _selectDate(visibleMatches[i].date);
                _selectTab(0);
              },
            ),
            const SizedBox(height: 8),
          ],
          if (matches.length > visibleMatches.length)
            Center(
              child: OutlinedButton(
                onPressed: () => setState(() => _auspiciousVisibleLimit += 40),
                child: Text(
                  isEn
                      ? 'Show more (${matches.length - visibleMatches.length} remaining)'
                      : '显示更多（还有 ${matches.length - visibleMatches.length} 天）',
                ),
              ),
            ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: 法定放假安排 (Holiday Schedule & Bridge Leave Tips)
  // ---------------------------------------------------------------------------

  Widget _buildHolidayScheduleTab({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required bool isEn,
  }) {
    final today = _dateOnly(DateTime.now());
    final next = HolidayCalendar.nextHoliday(today);
    final years = HolidayCalendar.supportedYears;
    final items = HolidayCalendar.schedulesForYear(_holidayYear);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (next != null) ...[
          DesktopPanelCard(
            frosted: tokens.isLiquidGlass,
            padding: const EdgeInsets.all(18),
            color: tokens.accentSoft,
            border: Border.all(
              color: tokens.accentBorder,
              width: DesktopWebTokens.hairlineWidth,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AlmanacUiCopy.nextHolidayHeroTitle(next, today, locale),
                        style: tokens.pageTitleStyle.copyWith(
                          color: tokens.accent,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${I18nDateFormat.date(next.startDate, locale: locale)} – ${I18nDateFormat.date(next.endDate, locale: locale)} · ${AlmanacUiCopy.holidayDaysBadge(next.totalDays, locale)}',
                        style: tokens.bodyStyle.copyWith(
                          fontSize: 13,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (next.localizedBridgeLeaveTip(locale).isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${AlmanacUiCopy.bridgeLeaveTipLabel}: ${next.localizedBridgeLeaveTip(locale)}',
                          style: tokens.bodyMutedStyle.copyWith(fontSize: 12.5),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  children: [
                    Text(
                      '${next.daysUntil(today)}',
                      style: tokens.metricValueStyle.copyWith(
                        fontSize: 32,
                        color: tokens.accent,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      isEn ? 'DAYS' : '天',
                      style: tokens.captionStyle.copyWith(color: tokens.accent),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Year Selector
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              isEn ? 'Select Year' : '选择年份',
              style: tokens.bodyMutedStyle,
            ),
            for (final y in years)
              _FilterChoicePill(
                key: ValueKey('almanac_holiday_year_$y'),
                label: AlmanacUiCopy.yearHeader(y, locale),
                selected: _holidayYear == y,
                tokens: tokens,
                onTap: () => setState(() => _holidayYear = y),
              ),
          ],
        ),
        const SizedBox(height: 12),

        for (final item in items) ...[
          _HolidayScheduleCard(
            item: item,
            today: today,
            locale: locale,
            isEn: isEn,
            tokens: tokens,
            onJumpDate: _selectDate,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: 日期工具 & 节气八字
  // ---------------------------------------------------------------------------

  Widget _buildDateToolsAndBaziTab({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required bool isEn,
  }) {
    final intervalCard = _buildIntervalCard(
      tokens: tokens,
      locale: locale,
      isEn: isEn,
    );
    final offsetCard = _buildOffsetCard(
      tokens: tokens,
      locale: locale,
      isEn: isEn,
    );
    final converterCard = _buildConverterCard(
      tokens: tokens,
      locale: locale,
      isEn: isEn,
    );
    final solarTermsCard = _buildSolarTermsCard(
      tokens: tokens,
      locale: locale,
      isEn: isEn,
    );
    final baziCard = _buildBaziCard(
      tokens: tokens,
      locale: locale,
      isEn: isEn,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= 540;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sideBySide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: intervalCard),
                  const SizedBox(width: 12),
                  Expanded(child: offsetCard),
                ],
              )
            else ...[
              intervalCard,
              const SizedBox(height: 12),
              offsetCard,
            ],
            const SizedBox(height: 12),
            converterCard,
            const SizedBox(height: 12),
            baziCard,
            const SizedBox(height: 12),
            solarTermsCard,
          ],
        );
      },
    );
  }

  Widget _buildIntervalCard({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required bool isEn,
  }) {
    final result = AlmanacToolsService.calculateDateInterval(
      _intervalStart,
      _intervalEnd,
      inclusive: _intervalInclusive,
    );
    return DesktopPanelCard(
      frosted: tokens.isLiquidGlass,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AlmanacUiCopy.intervalCalcTitle,
            style: tokens.cardTitleStyle.copyWith(fontSize: 14.5),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DatePickChip(
                label:
                    '${AlmanacUiCopy.startDateLabel}: ${I18nDateFormat.date(_intervalStart, locale: locale)}',
                tokens: tokens,
                onTap: () async {
                  final picked = await _pickSolarDate(
                    _intervalStart,
                    title: AlmanacUiCopy.startDateLabel,
                  );
                  if (picked != null && mounted) {
                    setState(() => _intervalStart = _clampSupportedDate(picked));
                  }
                },
              ),
              _DatePickChip(
                label:
                    '${AlmanacUiCopy.endDateLabel}: ${I18nDateFormat.date(_intervalEnd, locale: locale)}',
                tokens: tokens,
                onTap: () async {
                  final picked = await _pickSolarDate(
                    _intervalEnd,
                    title: AlmanacUiCopy.endDateLabel,
                  );
                  if (picked != null && mounted) {
                    setState(() => _intervalEnd = _clampSupportedDate(picked));
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  AlmanacUiCopy.includeEndDateLabel,
                  style: tokens.captionStyle,
                ),
              ),
              Switch.adaptive(
                key: const ValueKey('almanac_interval_inclusive_toggle'),
                value: _intervalInclusive,
                onChanged: (v) => setState(() => _intervalInclusive = v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens.mutedSurface,
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${AlmanacUiCopy.calendarDaysLabel}: ${result.calendarDays} ${isEn ? 'days' : '天'}'
                  '  (${result.exactYears}${isEn ? 'y ' : '年'}${result.exactMonths}${isEn ? 'm ' : '月'}${result.exactDays}${isEn ? 'd' : '天'})',
                  style: tokens.bodyStyle.copyWith(
                    fontSize: 13.5,
                    color: tokens.accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _StatChip(
                      label: AlmanacUiCopy.workdaysLabel,
                      value: '${result.workdays}',
                      color: tokens.info,
                      tokens: tokens,
                    ),
                    _StatChip(
                      label: AlmanacUiCopy.restDaysLabel,
                      value: '${result.restDays}',
                      color: tokens.success,
                      tokens: tokens,
                    ),
                    _StatChip(
                      label: AlmanacUiCopy.weekendDaysLabel,
                      value: '${result.weekendDays}',
                      color: tokens.textSecondary,
                      tokens: tokens,
                    ),
                    _StatChip(
                      label: AlmanacUiCopy.holidayDaysLabel,
                      value: '${result.holidayDays}',
                      color: tokens.success,
                      tokens: tokens,
                    ),
                    _StatChip(
                      label: AlmanacUiCopy.makeupDaysLabel,
                      value: '${result.makeupWorkdays}',
                      color: tokens.warning,
                      tokens: tokens,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOffsetCard({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required bool isEn,
  }) {
    final result = AlmanacToolsService.offsetDate(
      _offsetBaseDate,
      _offsetDelta,
      workdaysOnly: _offsetWorkdaysOnly,
    );

    return DesktopPanelCard(
      frosted: tokens.isLiquidGlass,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AlmanacUiCopy.offsetCalcTitle,
            style: tokens.cardTitleStyle.copyWith(fontSize: 14.5),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _DatePickChip(
                label:
                    '${AlmanacUiCopy.baseDateLabel}: ${I18nDateFormat.date(_offsetBaseDate, locale: locale)}',
                tokens: tokens,
                onTap: () async {
                  final picked = await _pickSolarDate(
                    _offsetBaseDate,
                    title: AlmanacUiCopy.baseDateLabel,
                  );
                  if (picked != null && mounted) {
                    setState(
                      () => _offsetBaseDate = _clampSupportedDate(picked),
                    );
                  }
                },
              ),
              SizedBox(
                width: 96,
                child: TextField(
                  key: const ValueKey('almanac_offset_delta_field'),
                  controller: _offsetDeltaCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                  ),
                  style: tokens.bodyStyle.copyWith(
                    fontSize: 13,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  onChanged: (raw) {
                    final parsed = int.tryParse(raw.trim());
                    if (parsed != null) {
                      setState(() => _offsetDelta = parsed.clamp(-36500, 36500));
                    }
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: isEn ? 'Days' : '天数',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final preset in const [-30, -7, 7, 14, 30, 90, 100])
                _FilterChoicePill(
                  label: preset > 0 ? '+$preset' : '$preset',
                  selected: _offsetDelta == preset,
                  tokens: tokens,
                  onTap: () => setState(() {
                    _offsetDelta = preset;
                    _offsetDeltaCtrl.text = '$preset';
                  }),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  AlmanacUiCopy.workdaysOnlyLabel,
                  style: tokens.captionStyle,
                ),
              ),
              Switch.adaptive(
                key: const ValueKey('almanac_offset_workdays_toggle'),
                value: _offsetWorkdaysOnly,
                onChanged: (v) => setState(() => _offsetWorkdaysOnly = v),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens.mutedSurface,
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${AlmanacUiCopy.targetDateLabel}: ${AlmanacUiCopy.fullDateTitle(result.targetDate, locale, null)}',
                        style: tokens.bodyStyle.copyWith(
                          fontSize: 13.5,
                          color: tokens.accent,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${result.lunarLabel} · ${AlmanacUiCopy.isoWeekBadge(result.isoWeekNumber, locale)} · '
                        '${result.isHoliday ? AlmanacUiCopy.holidayBadge : (result.isWorkMakeupDay ? AlmanacUiCopy.makeupWorkdayBadge : (result.isWorkday ? (isEn ? 'Workday' : '工作日') : (isEn ? 'Rest day' : '休息日')))}',
                        style: tokens.captionStyle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _selectDate(result.targetDate),
                  child: Text(isEn ? 'View' : '定位'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConverterCard({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required bool isEn,
  }) {
    final leapMonthInYear = LunarCalendar.leapMonthOfLunarYear(_convLunarYear);
    final maxDaysInLunarMonth = LunarCalendar.daysInLunarMonth(
      _convLunarYear,
      _convLunarMonth,
      isLeap: _convLunarIsLeap && leapMonthInYear == _convLunarMonth,
    );
    final safeLunarDay = _convLunarDay
        .clamp(
          1,
          math.max(1, maxDaysInLunarMonth),
        )
        .toInt();

    final DateConversionDetail? conversion = _converterSolarToLunar
        ? AlmanacToolsService.solarToLunarDetail(_convSolarInput)
        : AlmanacToolsService.lunarToSolarDetail(
            _convLunarYear,
            _convLunarMonth,
            safeLunarDay,
            isLeap: _convLunarIsLeap && leapMonthInYear == _convLunarMonth,
          );

    return DesktopPanelCard(
      frosted: tokens.isLiquidGlass,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                AlmanacUiCopy.solarLunarConverterTitle,
                style: tokens.cardTitleStyle.copyWith(fontSize: 14.5),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _FilterChoicePill(
                    key: const ValueKey('almanac_conv_solar_to_lunar'),
                    label: AlmanacUiCopy.solarToLunarTab,
                    selected: _converterSolarToLunar,
                    tokens: tokens,
                    onTap: () => setState(() => _converterSolarToLunar = true),
                  ),
                  _FilterChoicePill(
                    key: const ValueKey('almanac_conv_lunar_to_solar'),
                    label: AlmanacUiCopy.lunarToSolarTab,
                    selected: !_converterSolarToLunar,
                    tokens: tokens,
                    onTap: () => setState(() => _converterSolarToLunar = false),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_converterSolarToLunar)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _DatePickChip(
                  label:
                      '${isEn ? 'Solar Date' : '公历日期'}: ${I18nDateFormat.date(_convSolarInput, locale: locale)}',
                  tokens: tokens,
                  onTap: () async {
                    final picked = await _pickSolarDate(
                      _convSolarInput,
                      title: isEn ? 'Select Solar Date' : '选择公历日期',
                    );
                    if (picked != null && mounted) {
                      setState(() => _convSolarInput = _clampSupportedDate(picked));
                    }
                  },
                ),
                OutlinedButton(
                  onPressed: () => setState(() => _convSolarInput = _selectedDate),
                  child: Text(isEn ? 'Use Selected Day' : '使用当前选中日'),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StepperPill(
                      label:
                          '$_convLunarYear${isEn ? '' : '年'} (${AlmanacLocaleFormat.formatGanZhi(LunarCalendar.ganzhiOf(_convLunarYear), locale)})',
                      tokens: tokens,
                      onMinus: _convLunarYear > _minYear
                          ? () => setState(() {
                              _convLunarYear--;
                              if (LunarCalendar.leapMonthOfLunarYear(
                                    _convLunarYear,
                                  ) !=
                                  _convLunarMonth) {
                                _convLunarIsLeap = false;
                              }
                            })
                          : null,
                      onPlus: _convLunarYear < _maxYear
                          ? () => setState(() {
                              _convLunarYear++;
                              if (LunarCalendar.leapMonthOfLunarYear(
                                    _convLunarYear,
                                  ) !=
                                  _convLunarMonth) {
                                _convLunarIsLeap = false;
                              }
                            })
                          : null,
                      onTapCenter: () async {
                        final picked = await _showNumberGridDialog(
                          title: isEn ? 'Lunar Year' : '选择农历年份',
                          values: [
                            for (var y = _minYear; y <= _maxYear; y++) y,
                          ],
                          selected: _convLunarYear,
                          labelBuilder: (y) => '$y',
                          tokens: tokens,
                        );
                        if (picked != null && mounted) {
                          setState(() {
                            _convLunarYear = picked;
                            if (LunarCalendar.leapMonthOfLunarYear(picked) !=
                                _convLunarMonth) {
                              _convLunarIsLeap = false;
                            }
                          });
                        }
                      },
                    ),
                    _StepperPill(
                      label: LunarCalendar.monthName(
                        _convLunarMonth,
                        isLeap:
                            _convLunarIsLeap &&
                            leapMonthInYear == _convLunarMonth,
                      ),
                      tokens: tokens,
                      onMinus: () => setState(() {
                        _convLunarMonth = _convLunarMonth > 1
                            ? _convLunarMonth - 1
                            : 12;
                        if (leapMonthInYear != _convLunarMonth) {
                          _convLunarIsLeap = false;
                        }
                      }),
                      onPlus: () => setState(() {
                        _convLunarMonth = _convLunarMonth < 12
                            ? _convLunarMonth + 1
                            : 1;
                        if (leapMonthInYear != _convLunarMonth) {
                          _convLunarIsLeap = false;
                        }
                      }),
                      onTapCenter: () async {
                        final picked = await _showNumberGridDialog(
                          title: isEn ? 'Lunar Month' : '选择农历月份',
                          values: [for (var m = 1; m <= 12; m++) m],
                          selected: _convLunarMonth,
                          labelBuilder: (m) =>
                              LunarCalendar.monthName(m, isLeap: false),
                          tokens: tokens,
                        );
                        if (picked != null && mounted) {
                          setState(() {
                            _convLunarMonth = picked;
                            if (leapMonthInYear != picked) {
                              _convLunarIsLeap = false;
                            }
                          });
                        }
                      },
                    ),
                    _StepperPill(
                      label: LunarCalendar.dayName(safeLunarDay),
                      tokens: tokens,
                      onMinus: () => setState(() {
                        _convLunarDay = safeLunarDay > 1
                            ? safeLunarDay - 1
                            : maxDaysInLunarMonth;
                      }),
                      onPlus: () => setState(() {
                        _convLunarDay = safeLunarDay < maxDaysInLunarMonth
                            ? safeLunarDay + 1
                            : 1;
                      }),
                      onTapCenter: () async {
                        final picked = await _showNumberGridDialog(
                          title: isEn ? 'Lunar Day' : '选择农历日期',
                          values: [
                            for (var d = 1; d <= maxDaysInLunarMonth; d++) d,
                          ],
                          selected: safeLunarDay,
                          labelBuilder: LunarCalendar.dayName,
                          tokens: tokens,
                        );
                        if (picked != null && mounted) {
                          setState(() => _convLunarDay = picked);
                        }
                      },
                    ),
                    if (leapMonthInYear == _convLunarMonth)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              '${AlmanacUiCopy.isLeapMonthLabel} (${LunarCalendar.monthName(leapMonthInYear, isLeap: true)})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tokens.captionStyle.copyWith(
                                color: tokens.accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Switch.adaptive(
                            key: const ValueKey('almanac_conv_leap_switch'),
                            value: _convLunarIsLeap,
                            onChanged: (v) =>
                                setState(() => _convLunarIsLeap = v),
                          ),
                        ],
                      )
                    else if (leapMonthInYear > 0)
                      _FilterChoicePill(
                        key: const ValueKey('almanac_conv_jump_leap_month'),
                        label: isEn
                            ? 'Switch to Leap Month $leapMonthInYear'
                            : '切至该年${LunarCalendar.monthName(leapMonthInYear, isLeap: true)}',
                        selected: false,
                        tokens: tokens,
                        onTap: () => setState(() {
                          _convLunarMonth = leapMonthInYear;
                          _convLunarIsLeap = true;
                        }),
                      )
                    else
                      Text(
                        AlmanacUiCopy.yearHasNoLeapMonth,
                        style: tokens.captionStyle,
                      ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 12),
          if (conversion == null)
            Text(
              AlmanacUiCopy.unavailable,
              style: tokens.bodyMutedStyle,
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tokens.mutedSurface,
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _converterSolarToLunar
                              ? AlmanacLocaleFormat.formatFullLunarDate(
                                  conversion.lunarDate,
                                  includeGanzhi: true,
                                  locale: locale,
                                )
                              : AlmanacUiCopy.fullDateTitle(
                                  conversion.solarDate,
                                  locale,
                                  null,
                                ),
                          style: tokens.bodyStyle.copyWith(
                            fontSize: 14.5,
                            color: tokens.accent,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${isEn ? 'Solar' : '公历'}: ${I18nDateFormat.date(conversion.solarDate, locale: locale)} · '
                          '${isEn ? 'Lunar' : '农历'}: ${AlmanacLocaleFormat.formatLunarDate(conversion.lunarDate, locale)}',
                          style: tokens.captionStyle.copyWith(
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _BadgePill(
                              label: AlmanacLocaleFormat.formatZodiac(
                                conversion.zodiac,
                                locale,
                              ),
                              color: tokens.info,
                              tokens: tokens,
                            ),
                            _BadgePill(
                              label: AlmanacLocaleFormat.formatXingZuo(
                                conversion.xingZuo,
                                locale,
                              ),
                              color: tokens.info,
                              tokens: tokens,
                            ),
                            _BadgePill(
                              label: AlmanacUiCopy.isoWeekBadge(
                                conversion.isoWeekNumber,
                                locale,
                              ),
                              color: tokens.textSecondary,
                              tokens: tokens,
                            ),
                            if (conversion.tianShen.isNotEmpty)
                              _BadgePill(
                                label:
                                    '${AlmanacLocaleFormat.formatTianShenType(conversion.tianShenType, locale)} · ${AlmanacLocaleFormat.formatTianShen(conversion.tianShen, locale)}',
                                color: conversion.tianShenType == '黄道'
                                    ? tokens.success
                                    : tokens.warning,
                                tokens: tokens,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () => _selectDate(conversion.solarDate),
                    child: Text(isEn ? 'Jump to Date' : '跳到此日'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBaziCard({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required bool isEn,
  }) {
    final selectedHourSpec = _shichenHours[_baziHourIndex.clamp(0, 11)];
    final birthDateTime = DateTime(
      _baziBirthDate.year,
      _baziBirthDate.month,
      _baziBirthDate.day,
      selectedHourSpec.hour,
      0,
    );
    final info = LunarCalendar.tryEightChar(birthDateTime);

    return DesktopPanelCard(
      frosted: tokens.isLiquidGlass,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                AlmanacUiCopy.baziTitle,
                style: tokens.cardTitleStyle.copyWith(fontSize: 14.5),
              ),
              _DatePickChip(
                label:
                    '${AlmanacUiCopy.birthDateTimeLabel}: ${I18nDateFormat.date(_baziBirthDate, locale: locale)}',
                tokens: tokens,
                onTap: () async {
                  final picked = await _pickSolarDate(
                    _baziBirthDate,
                    title: AlmanacUiCopy.birthDateTimeLabel,
                  );
                  if (picked != null && mounted) {
                    setState(
                      () => _baziBirthDate = _clampSupportedDate(picked),
                    );
                  }
                },
              ),
              _ShichenDropdownButton(
                selectedIndex: _baziHourIndex,
                hours: _shichenHours,
                isEn: isEn,
                tokens: tokens,
                onChanged: (idx) => setState(() => _baziHourIndex = idx),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (info == null)
            Text(AlmanacUiCopy.unavailable, style: tokens.bodyMutedStyle)
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final cols = constraints.maxWidth >= 460 ? 4 : 2;
                const gap = 8.0;
                final width = (constraints.maxWidth - gap * (cols - 1)) / cols;
                final pillars = [
                  (
                    AlmanacUiCopy.yearPillarLabel,
                    info.yearGanZhi,
                    info.yearWuXing,
                    info.yearNaYin,
                  ),
                  (
                    AlmanacUiCopy.monthPillarLabel,
                    info.monthGanZhi,
                    info.monthWuXing,
                    info.monthNaYin,
                  ),
                  (
                    AlmanacUiCopy.dayPillarLabel,
                    info.dayGanZhi,
                    info.dayWuXing,
                    info.dayNaYin,
                  ),
                  (
                    AlmanacUiCopy.timePillarLabel,
                    info.timeGanZhi,
                    info.timeWuXing,
                    info.timeNaYin,
                  ),
                ];
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final (title, gz, wx, ny) in pillars)
                      SizedBox(
                        width: width,
                        child: Container(
                          padding: const EdgeInsets.all(10),
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
                          child: Column(
                            children: [
                              Text(title, style: tokens.captionStyle),
                              const SizedBox(height: 4),
                              Text(
                                AlmanacLocaleFormat.formatGanZhi(gz, locale),
                                style: tokens.pageTitleStyle.copyWith(
                                  fontSize: 18,
                                  color: tokens.accent,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                AlmanacLocaleFormat.formatWuXing(wx, locale),
                                style: tokens.captionStyle.copyWith(
                                  color: tokens.textPrimary,
                                ),
                              ),
                              Text(
                                AlmanacLocaleFormat.formatNaYin(ny, locale),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tokens.captionStyle.copyWith(
                                  fontSize: 10.5,
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
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _BadgePill(
                  label:
                      '${AlmanacUiCopy.dayMasterLabel}: ${info.dayMaster} (${AlmanacLocaleFormat.formatWuXing(info.dayMasterWuXing, locale)})',
                  color: tokens.accent,
                  tokens: tokens,
                ),
                _BadgePill(
                  label:
                      '${isEn ? 'Zodiac' : '生肖'}: ${AlmanacLocaleFormat.formatZodiac(info.zodiac, locale)}',
                  color: tokens.info,
                  tokens: tokens,
                ),
                _BadgePill(
                  label:
                      '${AlmanacUiCopy.wuXingSummaryLabel}: ${info.wuXingCounts.entries.map((e) => '${AlmanacLocaleFormat.formatWuXing(e.key, locale)} ${e.value}').join(' · ')}',
                  color: tokens.textSecondary,
                  tokens: tokens,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSolarTermsCard({
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required bool isEn,
  }) {
    final terms = LunarCalendar.yearSolarTerms(_solarTermsYear);
    final nextTerm = LunarCalendar.nextSolarTerm(DateTime.now());

    return DesktopPanelCard(
      frosted: tokens.isLiquidGlass,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${AlmanacUiCopy.yearHeader(_solarTermsYear, locale)} · ${AlmanacUiCopy.yearSolarTermsTitle}',
                  style: tokens.cardTitleStyle.copyWith(fontSize: 14.5),
                ),
              ),
              _SquareIconButton(
                icon: Icons.chevron_left_rounded,
                tooltip: isEn ? 'Previous year' : '上一年',
                tokens: tokens,
                onTap: _solarTermsYear > _minYear
                    ? () => setState(() => _solarTermsYear--)
                    : null,
              ),
              const SizedBox(width: 4),
              _SquareIconButton(
                icon: Icons.chevron_right_rounded,
                tooltip: isEn ? 'Next year' : '下一年',
                tokens: tokens,
                onTap: _solarTermsYear < _maxYear
                    ? () => setState(() => _solarTermsYear++)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth >= 600
                  ? 3
                  : (constraints.maxWidth >= 380 ? 2 : 1);
              const gap = 8.0;
              final tileWidth =
                  (constraints.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final term in terms)
                    SizedBox(
                      width: tileWidth,
                      child: InkWell(
                        onTap: () => _selectDate(term.exactDateTime),
                        borderRadius: BorderRadius.circular(
                          DesktopWebTokens.radiusSm,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: (nextTerm != null &&
                                    nextTerm.name == term.name &&
                                    nextTerm.exactDateTime.year ==
                                        term.exactDateTime.year)
                                ? tokens.accentSoft
                                : tokens.mutedSurface,
                            borderRadius: BorderRadius.circular(
                              DesktopWebTokens.radiusSm,
                            ),
                            border: Border.all(
                              color: (nextTerm != null &&
                                      nextTerm.name == term.name &&
                                      nextTerm.exactDateTime.year ==
                                          term.exactDateTime.year)
                                  ? tokens.accentBorder
                                  : tokens.hairlineBorder,
                              width: DesktopWebTokens.hairlineWidth,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  AlmanacLocaleFormat.formatSolarTerm(
                                        term.name,
                                        locale,
                                      ) ??
                                      term.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tokens.bodyStyle.copyWith(
                                    fontSize: 12.5,
                                    color: (nextTerm != null &&
                                            nextTerm.name == term.name &&
                                            nextTerm.exactDateTime.year ==
                                                term.exactDateTime.year)
                                        ? tokens.accent
                                        : tokens.textPrimary,
                                  ),
                                ),
                              ),
                              Text(
                                _formatTermTimestamp(term.exactDateTime),
                                style: tokens.captionStyle.copyWith(
                                  fontSize: 11,
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
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers & Dialogs
  // ---------------------------------------------------------------------------

  Future<DateTime?> _pickSolarDate(DateTime initial, {String? title}) {
    return AppDatePicker.pickSolar(
      context,
      initialDate: _clampSupportedDate(initial),
      firstDate: DateTime(_minYear),
      lastDate: DateTime(_maxYear, 12, 31),
      title: title,
    );
  }

  Future<void> _pickYearDialog(DesktopWebTokens tokens, AppLocale locale) async {
    final picked = await _showNumberGridDialog(
      title: locale == AppLocale.en ? 'Select Year' : '选择年份 (1900–2099)',
      values: [for (var y = _minYear; y <= _maxYear; y++) y],
      selected: _focusedMonth.year,
      labelBuilder: (y) => '$y',
      tokens: tokens,
    );
    if (picked != null && mounted) {
      final daysInTarget = DateTime(picked, _focusedMonth.month + 1, 0).day;
      _selectDate(
        DateTime(
          picked,
          _focusedMonth.month,
          _selectedDate.day.clamp(1, daysInTarget),
        ),
      );
    }
  }

  Future<void> _pickMonthDialog(
    DesktopWebTokens tokens,
    AppLocale locale,
  ) async {
    final picked = await _showNumberGridDialog(
      title: locale == AppLocale.en ? 'Select Month' : '选择月份',
      values: [for (var m = 1; m <= 12; m++) m],
      selected: _focusedMonth.month,
      labelBuilder: (m) => AlmanacUiCopy.monthHeader(m, locale),
      tokens: tokens,
    );
    if (picked != null && mounted) {
      final daysInTarget = DateTime(_focusedMonth.year, picked + 1, 0).day;
      _selectDate(
        DateTime(
          _focusedMonth.year,
          picked,
          _selectedDate.day.clamp(1, daysInTarget),
        ),
      );
    }
  }

  Future<int?> _showNumberGridDialog({
    required String title,
    required List<int> values,
    required int selected,
    required String Function(int) labelBuilder,
    required DesktopWebTokens tokens,
  }) {
    return showDialog<int>(
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
        title: Text(title, style: tokens.cardTitleStyle),
        content: SizedBox(
          width: 360,
          height: math.min(340.0, (values.length / 4).ceil() * 44.0 + 16),
          child: GridView.builder(
            itemCount: values.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 2.2,
            ),
            itemBuilder: (context, idx) {
              final val = values[idx];
              final isSel = val == selected;
              return InkWell(
                onTap: () => Navigator.of(dialogCtx).pop(val),
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXs),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSel ? tokens.accent : tokens.mutedSurface,
                    borderRadius: BorderRadius.circular(
                      DesktopWebTokens.radiusXs,
                    ),
                    border: Border.all(
                      color: isSel ? tokens.accent : tokens.hairlineBorder,
                      width: DesktopWebTokens.hairlineWidth,
                    ),
                  ),
                  child: Text(
                    labelBuilder(val),
                    style: tokens.captionStyle.copyWith(
                      color: isSel
                          ? tokens.accentForeground
                          : tokens.textPrimary,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showTermDialog(
    String rawTerm, {
    required String badgeLabel,
    required Color badgeColor,
    required DesktopWebTokens tokens,
    required AppLocale locale,
    required bool isEn,
  }) {
    final info = AlmanacToolsService.explainAlmanacTerm(rawTerm, english: isEn);
    return showDialog<void>(
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
                color: badgeColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXs),
              ),
              child: Text(
                badgeLabel,
                style: tokens.captionStyle.copyWith(color: badgeColor),
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

  static List<String> _splitTerms(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];
    return trimmed
        .split(RegExp(r'\s+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
  }

  static String _shortWeekday(int isoWeekday, bool isEn) {
    if (isEn) {
      return const [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ][isoWeekday - 1];
    }
    return const ['一', '二', '三', '四', '五', '六', '日'][isoWeekday - 1];
  }

  static String _formatCurrentTermBadge(
    LunarAlmanacDetail detail,
    AppLocale locale,
  ) {
    final name =
        AlmanacLocaleFormat.formatSolarTerm(detail.currentSolarTerm, locale) ??
        detail.currentSolarTerm ??
        '';
    final exact = detail.currentSolarTermExactTime;
    if (exact == null) return name;
    final hh = exact.hour.toString().padLeft(2, '0');
    final mm = exact.minute.toString().padLeft(2, '0');
    return '$name $hh:$mm';
  }

  static String _formatTermTimestamp(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$m-$d $hh:$mm';
  }
}

// -----------------------------------------------------------------------------
// Compact Reusable Desktop Almanac Sub-Widgets
// -----------------------------------------------------------------------------

class _TopBarActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _TopBarActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWebTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: tokens.mutedSurface,
          borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
          border: Border.all(
            color: tokens.hairlineBorder,
            width: DesktopWebTokens.hairlineWidth,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: tokens.accent),
            const SizedBox(width: 5),
            Text(
              label,
              style: tokens.captionStyle.copyWith(
                fontSize: 12.5,
                color: tokens.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerPillButton extends StatelessWidget {
  final String label;
  final DesktopWebTokens tokens;
  final VoidCallback onTap;

  const _PickerPillButton({
    super.key,
    required this.label,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: tokens.mutedSurface,
          borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
          border: Border.all(
            color: tokens.hairlineBorder,
            width: DesktopWebTokens.hairlineWidth,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: tokens.cardTitleStyle.copyWith(fontSize: 14)),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: tokens.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final DesktopWebTokens tokens;
  final VoidCallback? onTap;

  const _SquareIconButton({
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
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXs),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: tokens.mutedSurface,
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXs),
            border: Border.all(
              color: tokens.hairlineBorder,
              width: DesktopWebTokens.hairlineWidth,
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: onTap != null
                ? tokens.textSecondary
                : tokens.textMuted.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String badgeText;
  final String label;
  final DesktopWebTokens tokens;

  const _LegendItem({
    required this.color,
    required this.badgeText,
    required this.label,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            badgeText,
            style: tokens.captionStyle.copyWith(fontSize: 9.5, color: color),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: tokens.captionStyle.copyWith(fontSize: 11)),
      ],
    );
  }
}

class _BadgePill extends StatelessWidget {
  final String label;
  final Color color;
  final DesktopWebTokens tokens;

  const _BadgePill({
    required this.label,
    required this.color,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: tokens.isDark ? 0.18 : 0.11),
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
      ),
      child: Text(
        label,
        style: tokens.captionStyle.copyWith(fontSize: 11.5, color: color),
      ),
    );
  }
}

class _DirectionTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final DesktopWebTokens tokens;

  const _DirectionTile({
    required this.label,
    required this.value,
    required this.color,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: tokens.mutedSurface,
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
        border: Border.all(
          color: tokens.hairlineBorder,
          width: DesktopWebTokens.hairlineWidth,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: tokens.captionStyle.copyWith(color: color)),
          const SizedBox(height: 2),
          Text(
            value.isEmpty ? '—' : value,
            style: tokens.bodyStyle.copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ShenShaRow extends StatelessWidget {
  final String label;
  final Color color;
  final List<String> items;
  final DesktopWebTokens tokens;
  final String emptyLabel;

  const _ShenShaRow({
    required this.label,
    required this.color,
    required this.items,
    required this.tokens,
    required this.emptyLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: tokens.isDark ? 0.18 : 0.12),
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXs),
          ),
          child: Text(
            label,
            style: tokens.captionStyle.copyWith(color: color),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            items.isEmpty ? emptyLabel : items.join(' · '),
            style: tokens.bodyMutedStyle.copyWith(fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}

class _PhenologyRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isEn;
  final DesktopWebTokens tokens;

  const _PhenologyRow({
    required this.label,
    required this.value,
    required this.isEn,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: isEn ? 96 : 82,
            child: Text(
              label,
              style: tokens.captionStyle.copyWith(color: tokens.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: tokens.bodyStyle.copyWith(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShichenTile extends StatelessWidget {
  final AlmanacHourFortune item;
  final bool selected;
  final bool isCurrentHour;
  final AppLocale locale;
  final DesktopWebTokens tokens;
  final VoidCallback onTap;

  const _ShichenTile({
    super.key,
    required this.item,
    required this.selected,
    required this.isCurrentHour,
    required this.locale,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final luckColor = item.isAuspicious ? tokens.success : tokens.textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? tokens.accentSoft : tokens.mutedSurface,
          borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
          border: Border.all(
            color: selected ? tokens.accent : tokens.hairlineBorder,
            width: selected ? 1.0 : DesktopWebTokens.hairlineWidth,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    locale == AppLocale.en ? item.branch : '${item.branch}时',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.bodyStyle.copyWith(
                      fontSize: 12.5,
                      color: selected ? tokens.accent : tokens.textPrimary,
                    ),
                  ),
                ),
                if (isCurrentHour) ...[
                  const SizedBox(width: 3),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: tokens.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              item.range.substring(0, 5),
              style: tokens.captionStyle.copyWith(
                fontSize: 9.5,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              AlmanacLocaleFormat.formatTianShenLuck(
                item.isAuspicious ? '吉' : '凶',
                locale,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.captionStyle.copyWith(
                fontSize: 10.5,
                color: luckColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineHourTermRow extends StatelessWidget {
  final String badge;
  final Color badgeColor;
  final List<String> terms;
  final AppLocale locale;
  final DesktopWebTokens tokens;
  final ValueChanged<String> onTapTerm;

  const _InlineHourTermRow({
    required this.badge,
    required this.badgeColor,
    required this.terms,
    required this.locale,
    required this.tokens,
    required this.onTapTerm,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            badge,
            style: tokens.captionStyle.copyWith(
              fontSize: 10.5,
              color: badgeColor,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final t in terms)
                InkWell(
                  onTap: () => onTapTerm(t),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.panelSurface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: tokens.hairlineBorder,
                        width: DesktopWebTokens.hairlineWidth,
                      ),
                    ),
                    child: Text(
                      AlmanacLocaleFormat.formatActivityTerm(t, locale),
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

class _FilterChoicePill extends StatelessWidget {
  final String label;
  final bool selected;
  final DesktopWebTokens tokens;
  final VoidCallback onTap;

  const _FilterChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? tokens.accentSoft : tokens.mutedSurface,
          borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
          border: Border.all(
            color: selected ? tokens.accentBorder : tokens.hairlineBorder,
            width: DesktopWebTokens.hairlineWidth,
          ),
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

class _DatePickChip extends StatelessWidget {
  final String label;
  final DesktopWebTokens tokens;
  final VoidCallback onTap;

  const _DatePickChip({
    required this.label,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: tokens.mutedSurface,
          borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
          border: Border.all(
            color: tokens.hairlineBorder,
            width: DesktopWebTokens.hairlineWidth,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.date_range_outlined, size: 15, color: tokens.accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.captionStyle.copyWith(
                  fontSize: 12,
                  color: tokens.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZodiacAvoidMenu extends StatelessWidget {
  final String? selectedZodiac;
  final AppLocale locale;
  final DesktopWebTokens tokens;
  final ValueChanged<String?> onChanged;

  const _ZodiacAvoidMenu({
    required this.selectedZodiac,
    required this.locale,
    required this.tokens,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final label = selectedZodiac == null
        ? '${AlmanacUiCopy.avoidZodiacLabel}: ${AlmanacUiCopy.noZodiacFilterLabel}'
        : '${AlmanacUiCopy.avoidZodiacLabel}: ${AlmanacLocaleFormat.formatZodiac(selectedZodiac!, locale)}';

    return PopupMenuButton<String>(
      onSelected: (value) => onChanged(value == '__none__' ? null : value),
      color: tokens.elevatedSurface,
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: '__none__',
          child: Text(
            AlmanacUiCopy.noZodiacFilterLabel,
            style: tokens.bodyStyle.copyWith(fontSize: 13),
          ),
        ),
        for (final z in AlmanacToolsService.zodiacOptions)
          PopupMenuItem<String>(
            value: z,
            child: Text(
              AlmanacLocaleFormat.formatZodiac(z, locale),
              style: tokens.bodyStyle.copyWith(fontSize: 13),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selectedZodiac != null
              ? tokens.accentSoft
              : tokens.mutedSurface,
          borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
          border: Border.all(
            color: selectedZodiac != null
                ? tokens.accentBorder
                : tokens.hairlineBorder,
            width: DesktopWebTokens.hairlineWidth,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.captionStyle.copyWith(
                  fontSize: 12,
                  color: selectedZodiac != null
                      ? tokens.accent
                      : tokens.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: selectedZodiac != null
                  ? tokens.accent
                  : tokens.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _AuspiciousResultCard extends StatelessWidget {
  final AuspiciousDayMatch match;
  final bool selected;
  final AppLocale locale;
  final bool isEn;
  final DesktopWebTokens tokens;
  final VoidCallback onJumpCalendar;
  final VoidCallback onOpenDetail;

  const _AuspiciousResultCard({
    super.key,
    required this.match,
    required this.selected,
    required this.locale,
    required this.isEn,
    required this.tokens,
    required this.onJumpCalendar,
    required this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    final suitablePreview = AlmanacLocaleFormat.formatActivitiesPreview(
      match.detail.suitable,
      maxTerms: 6,
      locale: locale,
    );
    return DesktopPanelCard(
      frosted: tokens.isLiquidGlass,
      padding: const EdgeInsets.all(13),
      border: Border.all(
        color: selected ? tokens.accent : tokens.hairlineBorder,
        width: selected ? 1.0 : DesktopWebTokens.hairlineWidth,
      ),
      onTap: onJumpCalendar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      AlmanacUiCopy.fullDateTitle(match.date, locale, null),
                      style: tokens.bodyStyle.copyWith(
                        fontSize: 14,
                        color: selected ? tokens.accent : tokens.textPrimary,
                      ),
                    ),
                    Text(
                      AlmanacLocaleFormat.formatLunarDate(
                        match.lunarDate,
                        locale,
                      ),
                      style: tokens.captionStyle.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                    _BadgePill(
                      label:
                          '${AlmanacLocaleFormat.formatTianShenType(match.tianShenType, locale)} · ${AlmanacLocaleFormat.formatTianShen(match.tianShen, locale)}',
                      color: match.isHuangDao ? tokens.success : tokens.warning,
                      tokens: tokens,
                    ),
                    _BadgePill(
                      label: AlmanacLocaleFormat.formatZhiXing(
                        match.zhiXing,
                        locale,
                      ),
                      color: tokens.info,
                      tokens: tokens,
                    ),
                    if (match.isHoliday)
                      _BadgePill(
                        label: match.holidayName ?? AlmanacUiCopy.holidayTag,
                        color: tokens.success,
                        tokens: tokens,
                      )
                    else if (match.isWorkMakeupDay)
                      _BadgePill(
                        label: AlmanacUiCopy.makeupWorkdayBadge,
                        color: tokens.warning,
                        tokens: tokens,
                      )
                    else if (match.isWeekend)
                      _BadgePill(
                        label: AlmanacUiCopy.weekendTag,
                        color: tokens.accent,
                        tokens: tokens,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onOpenDetail,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(isEn ? 'Details' : '详版'),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right_rounded, size: 16),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${AlmanacUiCopy.auspiciousLabel}: $suitablePreview',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tokens.captionStyle.copyWith(color: tokens.textPrimary),
          ),
          const SizedBox(height: 3),
          Text(
            AlmanacLocaleFormat.formatClash(match.detail, locale),
            style: tokens.captionStyle,
          ),
        ],
      ),
    );
  }
}

class _HolidayScheduleCard extends StatelessWidget {
  final HolidayScheduleItem item;
  final DateTime today;
  final AppLocale locale;
  final bool isEn;
  final DesktopWebTokens tokens;
  final ValueChanged<DateTime> onJumpDate;

  const _HolidayScheduleCard({
    required this.item,
    required this.today,
    required this.locale,
    required this.isEn,
    required this.tokens,
    required this.onJumpDate,
  });

  @override
  Widget build(BuildContext context) {
    final days = item.daysUntil(today);
    final isPast =
        DateTime(item.endDate.year, item.endDate.month, item.endDate.day)
            .isBefore(today);
    final String statusLabel;
    final Color statusColor;
    if (item.isOngoingOn(today)) {
      statusLabel = isEn ? 'Ongoing' : '放假中';
      statusColor = tokens.success;
    } else if (isPast) {
      statusLabel = isEn ? 'Ended' : '已结束';
      statusColor = tokens.textMuted;
    } else {
      statusLabel = isEn ? 'In ${days}d' : '还有 $days 天';
      statusColor = tokens.accent;
    }

    final tip = item.localizedBridgeLeaveTip(locale);

    return DesktopPanelCard(
      frosted: tokens.isLiquidGlass,
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      item.localizedName(locale),
                      style: tokens.cardTitleStyle.copyWith(fontSize: 15),
                    ),
                    _BadgePill(
                      label: AlmanacUiCopy.holidayDaysBadge(
                        item.totalDays,
                        locale,
                      ),
                      color: tokens.success,
                      tokens: tokens,
                    ),
                    Text(
                      '${I18nDateFormat.monthDay(item.startDate)} – ${I18nDateFormat.monthDay(item.endDate)}',
                      style: tokens.captionStyle.copyWith(
                        color: tokens.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              _BadgePill(
                label: statusLabel,
                color: statusColor,
                tokens: tokens,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final d in item.holidayDates)
                InkWell(
                  onTap: () => onJumpDate(d),
                  borderRadius: BorderRadius.circular(
                    DesktopWebTokens.radiusXs,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.success.withValues(
                        alpha: tokens.isDark ? 0.18 : 0.11,
                      ),
                      borderRadius: BorderRadius.circular(
                        DesktopWebTokens.radiusXs,
                      ),
                    ),
                    child: Text(
                      '${d.month}/${d.day}',
                      style: tokens.captionStyle.copyWith(
                        color: tokens.success,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              if (item.makeupDates.isEmpty)
                _BadgePill(
                  label: AlmanacUiCopy.noMakeupWorkdaysLabel,
                  color: tokens.success,
                  tokens: tokens,
                )
              else
                for (final m in item.makeupDates)
                  InkWell(
                    onTap: () => onJumpDate(m),
                    borderRadius: BorderRadius.circular(
                      DesktopWebTokens.radiusXs,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.warning.withValues(
                          alpha: tokens.isDark ? 0.18 : 0.12,
                        ),
                        borderRadius: BorderRadius.circular(
                          DesktopWebTokens.radiusXs,
                        ),
                      ),
                      child: Text(
                        '${AlmanacUiCopy.makeupWorkdayTag} ${m.month}/${m.day}',
                        style: tokens.captionStyle.copyWith(
                          color: tokens.warning,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
            ],
          ),
          if (tip.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: tokens.mutedSurface,
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXs),
              ),
              child: Text(
                '${AlmanacUiCopy.bridgeLeaveTipLabel}: $tip',
                style: tokens.captionStyle.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final DesktopWebTokens tokens;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.panelSurface,
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXs),
        border: Border.all(
          color: tokens.hairlineBorder,
          width: DesktopWebTokens.hairlineWidth,
        ),
      ),
      child: Text(
        '$label $value',
        style: tokens.captionStyle.copyWith(
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _StepperPill extends StatelessWidget {
  final String label;
  final DesktopWebTokens tokens;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final VoidCallback onTapCenter;

  const _StepperPill({
    required this.label,
    required this.tokens,
    this.onMinus,
    this.onPlus,
    required this.onTapCenter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: tokens.mutedSurface,
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
        border: Border.all(
          color: tokens.hairlineBorder,
          width: DesktopWebTokens.hairlineWidth,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onMinus,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Icon(
                Icons.remove_rounded,
                size: 14,
                color: onMinus != null
                    ? tokens.textSecondary
                    : tokens.textMuted.withValues(alpha: 0.4),
              ),
            ),
          ),
          Flexible(
            child: InkWell(
              onTap: onTapCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.captionStyle.copyWith(
                    fontSize: 12,
                    color: tokens.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          InkWell(
            onTap: onPlus,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Icon(
                Icons.add_rounded,
                size: 14,
                color: onPlus != null
                    ? tokens.textSecondary
                    : tokens.textMuted.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShichenDropdownButton extends StatelessWidget {
  final int selectedIndex;
  final List<({String branch, int hour, String labelZh, String labelEn})> hours;
  final bool isEn;
  final DesktopWebTokens tokens;
  final ValueChanged<int> onChanged;

  const _ShichenDropdownButton({
    required this.selectedIndex,
    required this.hours,
    required this.isEn,
    required this.tokens,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final current = hours[selectedIndex.clamp(0, hours.length - 1)];
    return PopupMenuButton<int>(
      onSelected: onChanged,
      color: tokens.elevatedSurface,
      itemBuilder: (_) => [
        for (var i = 0; i < hours.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Text(
              isEn ? hours[i].labelEn : hours[i].labelZh,
              style: tokens.bodyStyle.copyWith(fontSize: 13),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: tokens.mutedSurface,
          borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
          border: Border.all(
            color: tokens.hairlineBorder,
            width: DesktopWebTokens.hairlineWidth,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_outlined, size: 15, color: tokens.accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                isEn ? current.labelEn : current.labelZh,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.captionStyle.copyWith(
                  fontSize: 12,
                  color: tokens.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: tokens.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
