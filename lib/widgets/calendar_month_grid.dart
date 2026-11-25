import 'dart:collection';

import 'app_date_format.dart';
import 'package:flutter/material.dart';
import '../core/almanac_ui_copy.dart';
import '../core/calendar_agenda_ui_copy.dart';
import '../core/calendar_date_navigation.dart';
import '../core/calendar_ui_copy.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/lunar_calendar.dart';
import '../models/calendar_event.dart';
import '../services/holiday_calendar.dart';

enum _MonthLunarTone { none, festival, solarTerm, regular }

class _MonthDayStaticMeta {
  final int dayNum;
  final DateTime? date;
  final String dateKey;
  final bool isHoliday;
  final bool isWorkMakeupDay;
  final String? lunarText;
  final _MonthLunarTone lunarTone;

  const _MonthDayStaticMeta({
    required this.dayNum,
    required this.date,
    required this.dateKey,
    required this.isHoliday,
    required this.isWorkMakeupDay,
    required this.lunarText,
    required this.lunarTone,
  });
}

class _MonthGridCacheKey {
  final int year;
  final int month;
  final int holidayVersion;
  final bool showLunar;
  final AppLocale locale;

  const _MonthGridCacheKey({
    required this.year,
    required this.month,
    required this.holidayVersion,
    required this.showLunar,
    required this.locale,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _MonthGridCacheKey &&
          other.year == year &&
          other.month == month &&
          other.holidayVersion == holidayVersion &&
          other.showLunar == showLunar &&
          other.locale == locale;

  @override
  int get hashCode =>
      Object.hash(year, month, holidayVersion, showLunar, locale);
}

class _LabelWidthCacheKey {
  final String samplesKey;
  final double? fontSize;
  final double? height;
  final FontWeight? fontWeight;
  final double textScale;
  final TextDirection textDirection;
  final Locale? locale;

  const _LabelWidthCacheKey({
    required this.samplesKey,
    required this.fontSize,
    required this.height,
    required this.fontWeight,
    required this.textScale,
    required this.textDirection,
    required this.locale,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _LabelWidthCacheKey &&
          other.samplesKey == samplesKey &&
          other.fontSize == fontSize &&
          other.height == height &&
          other.fontWeight == fontWeight &&
          other.textScale == textScale &&
          other.textDirection == textDirection &&
          other.locale == locale;

  @override
  int get hashCode => Object.hash(
    samplesKey,
    fontSize,
    height,
    fontWeight,
    textScale,
    textDirection,
    locale,
  );
}

class CalendarMonthGrid extends StatelessWidget {
  static const int _maxMonthCacheEntries = 24;
  static const int _maxLabelWidthCacheEntries = 64;
  static final LinkedHashMap<_MonthGridCacheKey, List<_MonthDayStaticMeta>>
  _monthMetaCache =
      LinkedHashMap<_MonthGridCacheKey, List<_MonthDayStaticMeta>>();
  static final LinkedHashMap<_LabelWidthCacheKey, double>
  _labelWidthCache = LinkedHashMap<_LabelWidthCacheKey, double>();

  static List<_MonthDayStaticMeta> _resolveMonthMeta({
    required int year,
    required int month,
    required int daysInMonth,
    required DateTime civilFirstDay,
    required bool showLunar,
    required AppLocale locale,
  }) {
    final key = _MonthGridCacheKey(
      year: year,
      month: month,
      holidayVersion: HolidayCalendar.cacheVersion,
      showLunar: showLunar,
      locale: locale,
    );
    final cached = _monthMetaCache.remove(key);
    if (cached != null) {
      _monthMetaCache[key] = cached;
      return cached;
    }

    final includeLunarText = showLunar && locale == AppLocale.zh;
    final list = List<_MonthDayStaticMeta>.generate(daysInMonth, (index) {
      final dayNum = index + 1;
      final date = CalendarDateNavigation.tryShiftDays(civilFirstDay, index);
      if (date == null) {
        return _MonthDayStaticMeta(
          dayNum: dayNum,
          date: null,
          dateKey: '',
          isHoliday: false,
          isWorkMakeupDay: false,
          lunarText: null,
          lunarTone: _MonthLunarTone.none,
        );
      }
      final dateKey =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final isHoliday = HolidayCalendar.isHoliday(date);
      final isWorkMakeupDay = HolidayCalendar.isWorkMakeupDay(date);

      String? lunarText;
      var lunarTone = _MonthLunarTone.none;
      if (includeLunarText) {
        final solarFes = LunarCalendar.solarFestival(date);
        final isSolarRange = LunarCalendar.isWithinDocumentedSolarRange(date);
        final lunar = isSolarRange ? LunarCalendar.tryFromSolar(date) : null;
        if (solarFes != null) {
          lunarText = solarFes;
          lunarTone = _MonthLunarTone.festival;
        } else if (lunar != null) {
          final lunarFes = LunarCalendar.lunarFestival(lunar);
          String? term;
          try {
            term = LunarCalendar.solarTerm(date);
          } catch (_) {
            term = null;
          }
          if (lunarFes != null) {
            lunarText = lunarFes;
            lunarTone = _MonthLunarTone.festival;
          } else if (term != null) {
            lunarText = term;
            lunarTone = _MonthLunarTone.solarTerm;
          } else {
            lunarText = lunar.shortDayOrMonth;
            lunarTone = _MonthLunarTone.regular;
          }
        }
      }

      return _MonthDayStaticMeta(
        dayNum: dayNum,
        date: date,
        dateKey: dateKey,
        isHoliday: isHoliday,
        isWorkMakeupDay: isWorkMakeupDay,
        lunarText: lunarText,
        lunarTone: lunarTone,
      );
    }, growable: false);

    final immutable = List<_MonthDayStaticMeta>.unmodifiable(list);
    if (_monthMetaCache.length >= _maxMonthCacheEntries) {
      _monthMetaCache.remove(_monthMetaCache.keys.first);
    }
    _monthMetaCache[key] = immutable;
    return immutable;
  }

  static double _measureMaxLabelWidthCached(
    List<String> samples,
    TextStyle style, {
    required TextDirection textDirection,
    required TextScaler textScaler,
    required Locale? locale,
  }) {
    final key = _LabelWidthCacheKey(
      samplesKey: samples.join('\u0000'),
      fontSize: style.fontSize,
      height: style.height,
      fontWeight: style.fontWeight,
      textScale: textScaler.scale(1.0),
      textDirection: textDirection,
      locale: locale,
    );
    final cached = _labelWidthCache.remove(key);
    if (cached != null) {
      _labelWidthCache[key] = cached;
      return cached;
    }

    var maxW = 0.0;
    for (final sample in samples) {
      final painter = TextPainter(
        text: TextSpan(text: sample, style: style),
        textDirection: textDirection,
        textScaler: textScaler,
        locale: locale,
        maxLines: 1,
      )..layout();
      if (painter.width > maxW) {
        maxW = painter.width;
      }
      painter.dispose();
    }
    if (_labelWidthCache.length >= _maxLabelWidthCacheEntries) {
      _labelWidthCache.remove(_labelWidthCache.keys.first);
    }
    _labelWidthCache[key] = maxW;
    return maxW;
  }

  final DateTime focusedMonth;
  final DateTime selectedDay;
  final Map<String, List<CalendarEventType>> dateEventTypes;
  final Map<String, int> dateEventCounts;
  final void Function(DateTime) onDaySelected;

  /// 是否显示农历/节气/节日
  final bool showLunar;
  final int firstDayOfWeek;

  const CalendarMonthGrid({
    super.key,
    required this.focusedMonth,
    required this.selectedDay,
    required this.dateEventTypes,
    this.dateEventCounts = const {},
    required this.onDaySelected,
    this.showLunar = true,
    this.firstDayOfWeek = DateTime.monday,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayYear = now.year;
    final todayMonth = now.month;
    final todayDay = now.day;
    final civilFirstDay = DateTime.utc(
      focusedMonth.year,
      focusedMonth.month,
      1,
    );
    final civilLastDay = DateTime.utc(
      focusedMonth.year,
      focusedMonth.month + 1,
      0,
    );
    final daysInMonth = civilLastDay.day;
    final first = CalendarDateNavigation.normalizeFirstDayOfWeek(
      firstDayOfWeek,
    );
    final startOffset = (civilFirstDay.weekday - first) % 7;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final selectedDotColor = cs.onSurface.withValues(alpha: 0.72);
    final selectedBackground = Color.alphaBlend(
      cs.primary.withValues(alpha: isDark ? 0.20 : 0.13),
      cs.surface,
    );
    final selectedForeground = cs.onSurface;
    final currentLocale = I18n.current;
    final monthMeta = _resolveMonthMeta(
      year: focusedMonth.year,
      month: focusedMonth.month,
      daysInMonth: daysInMonth,
      civilFirstDay: civilFirstDay,
      showLunar: showLunar,
      locale: currentLocale,
    );
    final totalCells = startOffset + daysInMonth;
    final rows = (totalCells / 7).ceil();
    final preferredRowHeight = showLunar ? 58.0 : 48.0;
    final maxRowHeight = showLunar ? 72.0 : 62.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        const verticalPadding = 12.0;
        final textScaler = MediaQuery.textScalerOf(context);
        final textDirection =
            Directionality.maybeOf(context) ?? TextDirection.ltr;
        final appLocale = Localizations.maybeLocaleOf(context);
        final datePattern = AppDateFormat.patternOf(context);
        final scale = textScaler.scale(14) / 14;
        final weekdayHeight = (textScaler.scale(12) * 1.3).clamp(20.0, 48.0);
        const weekdayGap = 4.0;
        final scaledMaxRowHeight = (maxRowHeight * scale).clamp(
          maxRowHeight,
          140.0,
        );
        final scaledPreferredRowHeight = (preferredRowHeight * scale).clamp(
          preferredRowHeight,
          120.0,
        );
        final bounded = constraints.hasBoundedHeight;

        // Baseline minimum row slot height needed to comfortably display day number
        const minCivicDateFontSize = 13.0;
        final estimatedDayNumHeight =
            (textScaler.scale(minCivicDateFontSize) * 1.15).ceilToDouble();
        final minComfortableRowHeight = (estimatedDayNumHeight + 10.0).clamp(
          28.0,
          scaledMaxRowHeight,
        );

        final minTotalHeight =
            verticalPadding +
            weekdayHeight +
            weekdayGap +
            (rows * minComfortableRowHeight);
        final needsScroll = bounded && constraints.maxHeight < minTotalHeight;

        final availableRowHeight = bounded && !needsScroll
            ? (constraints.maxHeight -
                      verticalPadding -
                      weekdayHeight -
                      weekdayGap) /
                  rows
            : scaledPreferredRowHeight;
        final rowSlotHeight = needsScroll
            ? scaledPreferredRowHeight
            : (bounded
                  ? availableRowHeight.clamp(
                      minComfortableRowHeight,
                      scaledMaxRowHeight,
                    )
                  : scaledPreferredRowHeight);
        final cellHeight = (rowSlotHeight - 4).clamp(24.0, scaledMaxRowHeight);

        final horizontalPadding = constraints.maxWidth < 360 ? 6.0 : 12.0;

        final dayFontSize = cellHeight < 14
            ? (cellHeight * 0.72).clamp(6.0, 9.0).toDouble()
            : cellHeight < 28
            ? 11.0
            : cellHeight < 36
            ? 12.0
            : 13.0;

        final dayNumHeight =
            (textScaler.scale(dayFontSize) * (cellHeight < 14 ? 0.95 : 1.15))
                .ceilToDouble();
        final subTextHeight = (1.0 + textScaler.scale(10.0) * 1.25)
            .ceilToDouble();
        const dotsHeight = 6.0;
        final badgeHeight = (6.0 + textScaler.scale(10.0) * 1.25)
            .ceilToDouble();

        final cellWidth =
            ((constraints.maxWidth - horizontalPadding * 2) / 7 - 4.0)
                .clamp(1.0, double.infinity);
        final holidayColor = isDark
            ? const Color(0xFF6EE7B7)
            : const Color(0xFF0F766E);
        final makeupColor = isDark
            ? const Color(0xFFC4B5FD)
            : const Color(0xFF5B21B6);

        double measureMaxLabelWidth(List<String> samples, TextStyle style) {
          return _measureMaxLabelWidthCached(
            samples,
            style,
            textDirection: textDirection,
            textScaler: textScaler,
            locale: appLocale,
          );
        }

        final maxDayWidth = measureMaxLabelWidth(
          const ['28', '30'],
          TextStyle(
            fontSize: dayFontSize,
            height: cellHeight < 14 ? 0.95 : 1.05,
            fontWeight: FontWeight.normal,
          ),
        );
        final holidayTagWidth =
            measureMaxLabelWidth(
              [AlmanacUiCopy.holidayTag, AlmanacUiCopy.makeupWorkdayTag],
              const TextStyle(fontSize: 8.5, height: 1.0),
            ) +
            4.0;
        final holidayTagHeight = (textScaler.scale(8.5) * 1.1 + 2.0)
            .ceilToDouble();
        final canShowHolidayTagText =
            (cellWidth - maxDayWidth) / 2 >= (holidayTagWidth + 2.0) &&
            cellHeight >= (holidayTagHeight + 8.0);

        // Usable inner height inside the cell Container (margin is vertical 2.0 each side = 4.0, plus safety margin for border)
        final usableCellHeight = cellHeight - 5.0;

        final canShowDots = usableCellHeight >= dayNumHeight + dotsHeight;
        final canShowSubText =
            showLunar && (usableCellHeight >= dayNumHeight + subTextHeight);
        final canShowSubTextAndDots =
            showLunar &&
            (usableCellHeight >= dayNumHeight + subTextHeight + dotsHeight);
        final canShowSubTextAndBadge =
            showLunar &&
            (usableCellHeight >= dayNumHeight + subTextHeight + badgeHeight);
        final canShowBadgeWithoutSubText =
            usableCellHeight >= dayNumHeight + badgeHeight;

        final weekdayHeader = SizedBox(
          height: weekdayHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: CalendarAgendaUiCopy.weekdayInitialsFor(first)
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        );

        final monthRows = Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(rows, (row) {
            return SizedBox(
              height: rowSlotHeight,
              child: Row(
                children: List.generate(7, (col) {
                  final dayNum = row * 7 + col - startOffset + 1;
                  if (dayNum < 1 || dayNum > daysInMonth) {
                    return const Expanded(child: SizedBox.expand());
                  }
                  final meta = monthMeta[dayNum - 1];
                  final date = meta.date;
                  if (date == null) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        child: Semantics(
                          label: CalendarUiCopy.unavailable,
                          enabled: false,
                          button: false,
                          child: SizedBox(
                            width: double.infinity,
                            height: cellHeight,
                          ),
                        ),
                      ),
                    );
                  }
                  final key = meta.dateKey;
                  final types = dateEventTypes[key] ?? [];
                  final eventCount = dateEventCounts[key] ?? types.length;
                  final hasTodo = types.contains(CalendarEventType.todo);
                  final isSelected =
                      date.year == selectedDay.year &&
                      date.month == selectedDay.month &&
                      date.day == selectedDay.day;
                  final isToday =
                      date.year == todayYear &&
                      date.month == todayMonth &&
                      date.day == todayDay;
                  final isHoliday = meta.isHoliday;
                  final isWorkMakeupDay = meta.isWorkMakeupDay;

                  final lunarText = meta.lunarText;
                  final Color? lunarColor = switch (meta.lunarTone) {
                    _MonthLunarTone.festival =>
                      cs.brightness == Brightness.dark
                          ? DesignTokens.todoOverdueDark
                          : DesignTokens.defaultError,
                    _MonthLunarTone.solarTerm =>
                      cs.brightness == Brightness.dark
                          ? DesignTokens.todoCompletedDark
                          : DesignTokens.defaultSuccess,
                    _MonthLunarTone.regular => cs.onSurfaceVariant,
                    _MonthLunarTone.none => null,
                  };

                  final hasEvents = types.isNotEmpty || eventCount > 0;
                  // Event-before-lunar priority monotonicity:
                  // If day has scheduled events, lunar subtext is only displayed when
                  // there is sufficient vertical space for BOTH lunar text AND event indicators,
                  // preventing lunar text from displacing or suppressing scheduled events.
                  final canDisplaySubText = hasEvents
                      ? canShowSubTextAndDots
                      : canShowSubText;
                  final subText = canDisplaySubText ? lunarText : null;
                  final subColor = canDisplaySubText ? lunarColor : null;

                  final hasSubText = subText != null;
                  final countIsVisible = canShowDots && eventCount > 0;
                  final showEventCountBadge =
                      countIsVisible &&
                      eventCount > 1 &&
                      (hasSubText
                          ? canShowSubTextAndBadge
                          : canShowBadgeWithoutSubText);
                  final showDots =
                      canShowDots && types.isNotEmpty && !showEventCountBadge;

                  final semanticLabel = _daySemanticLabel(
                    date,
                    pattern: datePattern,
                    isToday: isToday,
                    isSelected: isSelected,
                    eventCount: eventCount,
                    subText: lunarText,
                    isHoliday: isHoliday,
                    isWorkMakeupDay: isWorkMakeupDay,
                  );

                  return Expanded(
                    child: Semantics(
                      button: true,
                      selected: isSelected,
                      label: semanticLabel,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(
                            DesignTokens.radiusControl,
                          ),
                          onTap: () => onDaySelected(date),
                          child: Center(
                            child: Container(
                              width: double.infinity,
                              height: cellHeight,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 2,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? selectedBackground
                                    : (isToday
                                          ? cs.primary.withValues(alpha: 0.1)
                                          : Colors.transparent),
                                borderRadius: BorderRadius.circular(
                                  DesignTokens.radiusControl,
                                ),
                                border: isSelected
                                    ? Border.all(
                                        color: cs.primary.withValues(
                                          alpha: 0.26,
                                        ),
                                        width: 0.45,
                                      )
                                    : null,
                              ),
                              child: Stack(
                                children: [
                                  Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          '$dayNum',
                                          style: TextStyle(
                                            fontSize: dayFontSize,
                                            height: cellHeight < 14
                                                ? 0.95
                                                : 1.05,
                                            fontWeight: FontWeight.normal,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                            color: isSelected
                                                ? selectedForeground
                                                : (isToday
                                                      ? cs.primary
                                                      : cs.onSurface),
                                          ),
                                        ),
                                        if (subText != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 1,
                                            ),
                                            child: Text(
                                              subText,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 10,
                                                height: 1,
                                                color: isSelected
                                                    ? selectedForeground
                                                          .withValues(
                                                            alpha: 0.64,
                                                          )
                                                    : subColor,
                                              ),
                                            ),
                                          ),
                                        if (showDots)
                                          Padding(
                                            padding: EdgeInsets.only(
                                              top: subText == null ? 3 : 2,
                                            ),
                                            child: _eventDots(
                                              context,
                                              types: types,
                                              isSelected: isSelected,
                                              selectedColor: selectedDotColor,
                                            ),
                                          ),
                                        if (showEventCountBadge)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 1,
                                            ),
                                            child: _eventCountBadge(
                                              context,
                                              count: eventCount,
                                              color: hasTodo
                                                  ? cs.primary
                                                  : cs.tertiary,
                                              foreground: isSelected
                                                  ? selectedForeground
                                                  : null,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (isHoliday || isWorkMakeupDay)
                                    Positioned(
                                      top: 2,
                                      right: 2,
                                      child: canShowHolidayTagText
                                          ? DecoratedBox(
                                              decoration: BoxDecoration(
                                                color:
                                                    (isWorkMakeupDay
                                                            ? makeupColor
                                                            : holidayColor)
                                                        .withValues(
                                                          alpha: isDark
                                                              ? 0.18
                                                              : 0.10,
                                                        ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 2,
                                                      vertical: 0.5,
                                                    ),
                                                child: Text(
                                                  isWorkMakeupDay
                                                      ? AlmanacUiCopy
                                                            .makeupWorkdayTag
                                                      : AlmanacUiCopy
                                                            .holidayTag,
                                                  style: TextStyle(
                                                    fontSize: 8.5,
                                                    height: 1.0,
                                                    color: isSelected
                                                        ? selectedForeground
                                                        : (isWorkMakeupDay
                                                              ? makeupColor
                                                              : holidayColor),
                                                    fontWeight:
                                                        FontWeight.normal,
                                                  ),
                                                ),
                                              ),
                                            )
                                          : (cellHeight >= 16
                                                ? SizedBox(
                                                    width: 5,
                                                    height: 5,
                                                    child: DecoratedBox(
                                                      decoration: BoxDecoration(
                                                        color: isWorkMakeupDay
                                                            ? makeupColor
                                                            : holidayColor,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                  )
                                                : const SizedBox.shrink()),
                                    ),
                                ],
                              ),
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
        );

        if (needsScroll) {
          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 6.0,
            ),
            child: Column(
              children: [
                weekdayHeader,
                const SizedBox(height: weekdayGap),
                Expanded(child: SingleChildScrollView(child: monthRows)),
              ],
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 6.0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              weekdayHeader,
              const SizedBox(height: weekdayGap),
              monthRows,
            ],
          ),
        );
      },
    );
  }

  Widget _eventCountBadge(
    BuildContext context, {
    required int count,
    required Color color,
    Color? foreground,
  }) {
    final textColor = foreground ?? color;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.20), width: 0.45),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: CalendarAgendaUiCopy.isEn ? 4 : 6,
          vertical: 2,
        ),
        child: Text(
          CalendarAgendaUiCopy.monthEventBadge(count),
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: 10,
            height: 1,
            color: textColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  Widget _eventDots(
    BuildContext context, {
    required List<CalendarEventType> types,
    required bool isSelected,
    required Color selectedColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: types
          .take(3)
          .map(
            (type) =>
                _dot(isSelected ? selectedColor : _colorForType(type, cs)),
          )
          .toList(),
    );
  }

  Color _colorForType(CalendarEventType type, ColorScheme cs) => switch (type) {
    CalendarEventType.event => const Color(0xFF5B6EE1),
    CalendarEventType.todo => cs.primary,
    CalendarEventType.habit => cs.tertiary,
    CalendarEventType.pomodoro =>
      cs.brightness == Brightness.dark
          ? DesignTokens.todoOverdueDark
          : DesignTokens.defaultError,
    CalendarEventType.anniversary => const Color(0xFFE91E63),
    CalendarEventType.countdown => const Color(0xFFFF8A65),
    CalendarEventType.course => const Color(0xFF42A5F5),
    CalendarEventType.diary => const Color(0xFF26A69A),
    CalendarEventType.goal => const Color(0xFFFFA726),
    CalendarEventType.timeEntry => const Color(0xFF78909C),
  };

  Widget _dot(Color color) => Container(
    width: 4,
    height: 4,
    margin: const EdgeInsets.only(left: 1),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  String _daySemanticLabel(
    DateTime date, {
    required bool isToday,
    required bool isSelected,
    required int eventCount,
    required String? subText,
    bool isHoliday = false,
    bool isWorkMakeupDay = false,
    String? pattern,
  }) {
    final base = CalendarAgendaUiCopy.daySemanticLabel(
      date,
      isToday: isToday,
      isSelected: isSelected,
      eventCount: eventCount,
      subText: subText,
      pattern: pattern,
    );
    if (!isHoliday && !isWorkMakeupDay) return base;
    final status = isWorkMakeupDay
        ? AlmanacUiCopy.makeupWorkdayBadge
        : AlmanacUiCopy.holidayBadge;
    return I18n.current == AppLocale.en ? '$base, $status' : '$base，$status';
  }
}
