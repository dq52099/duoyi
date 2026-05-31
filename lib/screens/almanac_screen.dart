import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/lunar_calendar.dart';
import '../models/anniversary.dart';
import '../models/countdown.dart';
import '../providers/anniversary_provider.dart';
import '../providers/countdown_provider.dart';
import '../services/holiday_calendar.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/surface_components.dart';

enum AlmanacEntryMode { calendar, almanac }

/// 万年历页面。保留 `almanac` 枚举用于兼容旧深链/测试，入口统一展示万年历。
class AlmanacScreen extends StatefulWidget {
  final DateTime? initialDate;
  final AlmanacEntryMode initialMode;

  const AlmanacScreen({
    super.key,
    this.initialDate,
    this.initialMode = AlmanacEntryMode.calendar,
  });

  @override
  State<AlmanacScreen> createState() => _AlmanacScreenState();
}

class _AlmanacScreenState extends State<AlmanacScreen> {
  static final DateTime _firstSupportedDate = DateTime(1900);
  static final DateTime _lastSupportedDate = DateTime(2099, 12, 31);

  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _date = _clampDate(widget.initialDate ?? DateTime.now());
  }

  void _shift(int days) {
    setState(() => _date = _clampDate(_date.add(Duration(days: days))));
  }

  DateTime _clampDate(DateTime value) {
    final day = DateTime(value.year, value.month, value.day);
    if (day.isBefore(_firstSupportedDate)) return _firstSupportedDate;
    if (day.isAfter(_lastSupportedDate)) return _lastSupportedDate;
    return day;
  }

  Future<void> _pickDate() async {
    final picked = await AppDatePicker.pickSolar(
      context,
      initialDate: _clampDate(_date),
      firstDate: _firstSupportedDate,
      lastDate: _lastSupportedDate,
      title: '万年历',
    );
    if (!mounted) return;
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
        content: Text(alreadyToday ? '已经是今天' : '已回到今天'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const pageTitle = '万年历';
    final lunar = LunarCalendar.fromSolar(_date);
    final zodiac = LunarCalendar.zodiacOf(lunar.year);
    final ganzhi = LunarCalendar.ganzhiOf(lunar.year);
    final term = LunarCalendar.solarTerm(_date);
    final solarFes = LunarCalendar.solarFestival(_date);
    final lunarFes = LunarCalendar.lunarFestival(lunar);
    final suitable = LunarCalendar.suitable(_date);
    final avoid = LunarCalendar.avoid(_date);
    final isHoliday = HolidayCalendar.isHoliday(_date);
    final isWorkMakeupDay = HolidayCalendar.isWorkMakeupDay(_date);
    final countdownProvider = context.watch<CountdownProvider?>();
    final anniversaryProvider = context.watch<AnniversaryProvider?>();
    final monthHighlights = _buildMonthHighlights(
      month: _date,
      countdowns: countdownProvider?.items ?? const <CountdownItem>[],
      anniversaries: anniversaryProvider?.items ?? const <Anniversary>[],
    );
    final monthHighlightDays = {
      for (final highlight in monthHighlights) highlight.date.day,
    };
    final weekNames = ['一', '二', '三', '四', '五', '六', '日'];
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
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: '回到今天',
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
            final summary = _summaryHeroCard(
              cs: cs,
              weekNames: weekNames,
              lunarText: lunar.chineseText,
              ganzhi: ganzhi,
              zodiac: zodiac,
              term: term,
              solarFestival: solarFes,
              lunarFestival: lunarFes,
            );
            final detail = _DateDetailCard(
              date: _date,
              lunarText: lunar.chineseText,
              ganzhi: ganzhi,
              zodiac: zodiac,
              solarTerm: term,
              solarFestival: solarFes,
              lunarFestival: lunarFes,
              isHoliday: isHoliday,
              isWorkMakeupDay: isWorkMakeupDay,
            );
            final miniMonth = _MiniMonth(
              date: _date,
              highlightDays: monthHighlightDays,
              onPick: (d) => setState(() => _date = _clampDate(d)),
            );
            final yiji = _yijiRow(suitable: suitable, avoid: avoid);
            final highlights = _MonthHighlightsCard(
              selectedDate: _date,
              highlights: monthHighlights,
            );
            return Scrollbar(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(wide ? 20 : 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1160),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    summary,
                                    const SizedBox(height: 16),
                                    miniMonth,
                                    const SizedBox(height: 16),
                                    highlights,
                                  ],
                                ),
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                flex: 6,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    detail,
                                    const SizedBox(height: 16),
                                    yiji,
                                    const SizedBox(height: 16),
                                    _aboutCard(),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              summary,
                              const SizedBox(height: 16),
                              detail,
                              const SizedBox(height: 16),
                              miniMonth,
                              const SizedBox(height: 16),
                              highlights,
                              const SizedBox(height: 16),
                              yiji,
                              const SizedBox(height: 16),
                              _aboutCard(),
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

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  Widget _summaryHeroCard({
    required ColorScheme cs,
    required List<String> weekNames,
    required String lunarText,
    required String ganzhi,
    required String zodiac,
    required String? term,
    required String? solarFestival,
    required String? lunarFestival,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primary.withValues(alpha: 0.85),
            cs.primary.withValues(alpha: 0.6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white),
                onPressed: _date == _firstSupportedDate
                    ? null
                    : () => _shift(-1),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: _pickDate,
                  child: Column(
                    children: [
                      Text(
                        '${_date.year} 年 ${_date.month} 月',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_date.day}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 56,
                          fontWeight: FontWeight.normal,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '星期${weekNames[_date.weekday - 1]}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.white),
                onPressed: _date == _lastSupportedDate ? null : () => _shift(1),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 4,
            children: [
              _chip('${I18n.tr('calendar.chinese_lunar_calendar')} $lunarText'),
              if (I18n.current == AppLocale.zh) _chip('$ganzhi · 属$zodiac'),
              if (term != null) _chip('🌿 $term'),
              if (solarFestival != null) _chip('🎉 $solarFestival'),
              if (lunarFestival != null && I18n.current == AppLocale.zh)
                _chip('🏮 $lunarFestival'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _aboutCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Colors.orange),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '万年历覆盖 1900-2099 年，支持公历、农历、节气与宜忌查看。',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _yijiCard({
    required String title,
    required String body,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 0.45),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: TextStyle(
              fontSize: 13,
              color: color.withValues(alpha: 0.85),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _yijiRow({required String suitable, required String avoid}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _yijiCard(
            title: '宜',
            body: suitable,
            color: const Color(0xFF66BB6A),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _yijiCard(
            title: '忌',
            body: avoid,
            color: const Color(0xFFEF5350),
          ),
        ),
      ],
    );
  }
}

List<_MonthHighlight> _buildMonthHighlights({
  required DateTime month,
  required Iterable<CountdownItem> countdowns,
  required Iterable<Anniversary> anniversaries,
}) {
  final first = DateTime(month.year, month.month, 1);
  final last = DateTime(month.year, month.month + 1, 0);
  final labelsByDay = <int, List<_HighlightLabel>>{};

  void add(DateTime date, String label, IconData icon, Color color) {
    if (date.year != month.year || date.month != month.month) return;
    labelsByDay
        .putIfAbsent(date.day, () => <_HighlightLabel>[])
        .add(_HighlightLabel(label: label, icon: icon, color: color));
  }

  for (
    var day = first;
    !day.isAfter(last);
    day = day.add(const Duration(days: 1))
  ) {
    final lunar = LunarCalendar.fromSolar(day);
    final term = LunarCalendar.solarTerm(day);
    final solarFestival = LunarCalendar.solarFestival(day);
    final lunarFestival = LunarCalendar.lunarFestival(lunar);
    if (term != null) {
      add(day, '节气 · $term', Icons.eco_outlined, const Color(0xFF43A047));
    }
    if (solarFestival != null) {
      add(
        day,
        '节日 · $solarFestival',
        Icons.celebration_outlined,
        const Color(0xFFEF6C00),
      );
    }
    if (lunarFestival != null) {
      add(
        day,
        '农历 · $lunarFestival',
        Icons.local_florist_outlined,
        const Color(0xFFE91E63),
      );
    }
    if (HolidayCalendar.isHoliday(day)) {
      add(day, '法定假日', Icons.beach_access_outlined, const Color(0xFF00897B));
    }
    if (HolidayCalendar.isWorkMakeupDay(day)) {
      add(day, '调休上班', Icons.work_outline, const Color(0xFF5E35B1));
    }
  }

  for (final item in countdowns) {
    add(
      item.targetDate,
      '倒数日 · ${item.title}',
      Icons.hourglass_bottom_outlined,
      const Color(0xFF5E35B1),
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
        '生日 · ${item.title}',
        Icons.cake_outlined,
        const Color(0xFFD81B60),
      ),
      AnniversaryType.memorial => (
        '纪念日 · ${item.title}',
        Icons.favorite_border,
        const Color(0xFFE53935),
      ),
      AnniversaryType.custom => (
        '纪念日 · ${item.title}',
        Icons.event_available_outlined,
        const Color(0xFF3949AB),
      ),
      AnniversaryType.normal => (
        '倒数日 · ${item.title}',
        Icons.hourglass_bottom_outlined,
        const Color(0xFF5E35B1),
      ),
    };
    add(occurrence, label, icon, color);
  }

  final highlights = labelsByDay.entries.map((entry) {
    return _MonthHighlight(
      date: DateTime(month.year, month.month, entry.key),
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

class _MonthHighlightsCard extends StatelessWidget {
  final DateTime selectedDate;
  final List<_MonthHighlight> highlights;

  const _MonthHighlightsCard({
    required this.selectedDate,
    required this.highlights,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_note_outlined, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                '本月重点日期',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                ),
              ),
              const Spacer(),
              Text(
                '${selectedDate.month} 月',
                style: appSecondaryControlLabelStyle(
                  context,
                ).copyWith(color: cs.onSurface.withValues(alpha: 0.54)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (highlights.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.34),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '本月暂无重点日期',
                style: appSecondaryControlTextStyle(
                  context,
                ).copyWith(color: cs.onSurface.withValues(alpha: 0.62)),
              ),
            )
          else
            ...highlights
                .take(14)
                .map(
                  (highlight) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 38,
                          child: Text(
                            '${highlight.date.month}/${highlight.date.day}',
                            style: appSecondaryControlTextStyle(context)
                                .copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.70),
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: highlight.labels.take(4).map((label) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: label.color.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: label.color.withValues(alpha: 0.16),
                                    width: 0.45,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      label.icon,
                                      size: 13,
                                      color: label.color,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        label.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            appSecondaryControlTextStyle(
                                              context,
                                            ).copyWith(
                                              color: cs.onSurface.withValues(
                                                alpha: 0.78,
                                              ),
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          if (highlights.length > 14)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '还有 ${highlights.length - 14} 个重点日期',
                style: appSecondaryControlLabelStyle(
                  context,
                ).copyWith(color: cs.onSurface.withValues(alpha: 0.52)),
              ),
            ),
        ],
      ),
    );
  }
}

class _DateDetailCard extends StatelessWidget {
  final DateTime date;
  final String lunarText;
  final String ganzhi;
  final String zodiac;
  final String? solarTerm;
  final String? solarFestival;
  final String? lunarFestival;
  final bool isHoliday;
  final bool isWorkMakeupDay;

  const _DateDetailCard({
    required this.date,
    required this.lunarText,
    required this.ganzhi,
    required this.zodiac,
    required this.solarTerm,
    required this.solarFestival,
    required this.lunarFestival,
    required this.isHoliday,
    required this.isWorkMakeupDay,
  });

  @override
  Widget build(BuildContext context) {
    final dayOfYear = date.difference(DateTime(date.year)).inDays + 1;
    final remainingDays = DateTime(date.year + 1).difference(date).inDays;
    final items = <(IconData, String, String)>[
      (
        Icons.calendar_month_outlined,
        '公历',
        '${date.year}-${_two(date.month)}-${_two(date.day)}',
      ),
      (Icons.nights_stay_outlined, '农历', lunarText),
      (Icons.auto_awesome_outlined, '干支生肖', '$ganzhi年 · 属$zodiac'),
      (Icons.timelapse_outlined, '年进度', '第 $dayOfYear 天 · 还剩 $remainingDays 天'),
      if (solarTerm != null) (Icons.eco_outlined, '节气', solarTerm!),
      if (solarFestival != null)
        (Icons.celebration_outlined, '公历节日', solarFestival!),
      if (lunarFestival != null)
        (Icons.local_florist_outlined, '农历节日', lunarFestival!),
      if (isHoliday) (Icons.beach_access_outlined, '节假日', '法定假日'),
      if (isWorkMakeupDay) (Icons.work_outline, '调休', '调休上班日'),
    ];
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.16),
              width: 0.45,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '日期信息',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                ),
              ),
              const SizedBox(height: 10),
              ...items.map((item) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(item.$1, size: 16, color: cs.primary),
                                const SizedBox(width: 8),
                                Text(
                                  item.$2,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurface.withValues(alpha: 0.58),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.only(left: 24),
                              child: Text(
                                item.$3,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Icon(item.$1, size: 16, color: cs.primary),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 68,
                              child: Text(
                                item.$2,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface.withValues(alpha: 0.58),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                item.$3,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                        ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _MiniMonth extends StatelessWidget {
  final DateTime date;
  final Set<int> highlightDays;
  final ValueChanged<DateTime> onPick;
  const _MiniMonth({
    required this.date,
    required this.highlightDays,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final first = DateTime(date.year, date.month, 1);
    final last = DateTime(date.year, date.month + 1, 0);
    final offset = first.weekday - 1; // 周一为 0
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200, width: 0.45),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: const ['一', '二', '三', '四', '五', '六', '日']
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          ...List.generate(((last.day + offset) / 7).ceil(), (row) {
            return Row(
              children: List.generate(7, (col) {
                final d = row * 7 + col - offset + 1;
                if (d < 1 || d > last.day) {
                  return const Expanded(child: SizedBox(height: 42));
                }
                final day = DateTime(date.year, date.month, d);
                final lunar = I18n.current == AppLocale.zh
                    ? LunarCalendar.fromSolar(day)
                    : null;
                final isSelected =
                    day.year == date.year &&
                    day.month == date.month &&
                    day.day == date.day;
                final today = DateTime.now();
                final isToday =
                    day.year == today.year &&
                    day.month == today.month &&
                    day.day == today.day;
                final hasHighlight = highlightDays.contains(d);
                final selectedFill = Color.alphaBlend(
                  cs.primary.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.20
                        : 0.13,
                  ),
                  cs.surface,
                );
                final selectedText = cs.onSurface;

                return Expanded(
                  child: GestureDetector(
                    onTap: () => onPick(day),
                    child: Container(
                      height: 42,
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? selectedFill
                            : (isToday
                                  ? cs.primary.withValues(alpha: 0.1)
                                  : null),
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected
                            ? Border.all(
                                color: cs.primary.withValues(alpha: 0.26),
                                width: 0.45,
                              )
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$d',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.normal,
                              color: isSelected
                                  ? selectedText
                                  : (isToday ? cs.primary : null),
                            ),
                          ),
                          if (lunar != null)
                            Text(
                              lunar.shortDayOrMonth,
                              style: TextStyle(
                                fontSize: 9,
                                color: isSelected
                                    ? selectedText.withValues(alpha: 0.64)
                                    : Colors.grey.shade500,
                              ),
                            ),
                          if (hasHighlight)
                            Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.only(top: 2),
                              decoration: BoxDecoration(
                                color: isSelected ? selectedText : cs.primary,
                                shape: BoxShape.circle,
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
}
