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

  void _shiftMonth(int months) {
    final targetMonth = DateTime(_date.year, _date.month + months, 1);
    final lastDay = DateTime(targetMonth.year, targetMonth.month + 1, 0).day;
    final nextDay = _date.day <= lastDay ? _date.day : lastDay;
    setState(() {
      _date = _clampDate(
        DateTime(targetMonth.year, targetMonth.month, nextDay),
      );
    });
  }

  void _shiftDay(int days) {
    setState(() => _date = _clampDate(_date.add(Duration(days: days))));
  }

  void _showSelectedDateDetail() {
    final detail = LunarCalendar.almanacDetail(_date);
    final term = LunarCalendar.solarTerm(_date);
    final solarFestival = LunarCalendar.solarFestival(_date);
    final lunarFestival = LunarCalendar.lunarFestival(detail.lunarDate);
    final badges = _dateBadges(
      term: term,
      solarFestival: solarFestival,
      lunarFestival: lunarFestival,
      isHoliday: HolidayCalendar.isHoliday(_date),
      isWorkMakeupDay: HolidayCalendar.isWorkMakeupDay(_date),
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => _AlmanacDetailSheet(
        detail: detail,
        badges: badges,
        weekNames: const ['一', '二', '三', '四', '五', '六', '日'],
        yijiRow: _yijiRow,
        detailRows: _detailRows,
      ),
    );
  }

  List<(String, Color)> _dateBadges({
    required String? term,
    required String? solarFestival,
    required String? lunarFestival,
    required bool isHoliday,
    required bool isWorkMakeupDay,
  }) {
    return <(String, Color)>[
      if (term != null) ('节气 $term', const Color(0xFF2E7D32)),
      if (solarFestival != null) ('公历 $solarFestival', const Color(0xFFEF6C00)),
      if (lunarFestival != null && I18n.current == AppLocale.zh)
        ('农历 $lunarFestival', const Color(0xFFC2185B)),
      if (isHoliday) ('法定假日', const Color(0xFF00897B)),
      if (isWorkMakeupDay) ('调休上班', const Color(0xFF5E35B1)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    const pageTitle = '万年历';
    final selectedDate = _date;
    final almanacDetail = LunarCalendar.almanacDetail(selectedDate);
    final lunar = almanacDetail.lunarDate;
    final term = LunarCalendar.solarTerm(selectedDate);
    final solarFes = LunarCalendar.solarFestival(selectedDate);
    final lunarFes = LunarCalendar.lunarFestival(lunar);
    final isHoliday = HolidayCalendar.isHoliday(selectedDate);
    final isWorkMakeupDay = HolidayCalendar.isWorkMakeupDay(selectedDate);
    final dateBadges = _dateBadges(
      term: term,
      solarFestival: solarFes,
      lunarFestival: lunarFes,
      isHoliday: isHoliday,
      isWorkMakeupDay: isWorkMakeupDay,
    );
    final countdownProvider = context.watch<CountdownProvider?>();
    final anniversaryProvider = context.watch<AnniversaryProvider?>();
    final monthHighlights = _buildMonthHighlights(
      month: selectedDate,
      countdowns: countdownProvider?.items ?? const <CountdownItem>[],
      anniversaries: anniversaryProvider?.items ?? const <Anniversary>[],
    );
    final monthHighlightDays = {
      for (final highlight in monthHighlights) highlight.date.day,
    };
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
            tooltip: '前一天',
            onPressed: _date == _firstSupportedDate
                ? null
                : () => _shiftDay(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: '后一天',
            onPressed: _date == _lastSupportedDate ? null : () => _shiftDay(1),
            icon: const Icon(Icons.chevron_right),
          ),
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
            final monthCalendar = _MonthCalendar(
              date: selectedDate,
              highlightDays: monthHighlightDays,
              highlights: monthHighlights,
              onPick: (d) => setState(() => _date = _clampDate(d)),
              onPreviousMonth: () => _shiftMonth(-1),
              onNextMonth: () => _shiftMonth(1),
              onTitleTap: _pickDate,
            );
            final summary = _SelectedDateSummaryCard(
              detail: almanacDetail,
              badges: dateBadges,
              onTap: _showSelectedDateDetail,
            );
            final highlights = _MonthHighlightsCard(
              selectedDate: selectedDate,
              highlights: monthHighlights,
            );
            return Scrollbar(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  wide ? 24 : 14,
                  6,
                  wide ? 24 : 14,
                  22,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        monthCalendar,
                        SizedBox(height: wide ? 16 : 12),
                        summary,
                        SizedBox(height: wide ? 22 : 18),
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

  Widget _detailRows(BuildContext context, LunarAlmanacDetail detail) {
    final rows = <(String, String)>[
      ('胎神', detail.fetalGod),
      ('彭祖', detail.pengZu),
      ('五行', detail.fiveElements),
      ('星宿', detail.mansion),
      ('冲煞', detail.clash),
    ];

    return Column(
      children: [
        _detailInfoGrid(context, rows),
        const SizedBox(height: 12),
        _hourFortuneRow(context, detail.hourFortuneItems, isLast: true),
      ],
    );
  }

  Widget _detailInfoGrid(BuildContext context, List<(String, String)> rows) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final columns = constraints.maxWidth >= 560 ? 2 : 1;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: rows
              .map(
                (row) => SizedBox(
                  width: itemWidth,
                  child: _detailInfoTile(context, label: row.$1, value: row.$2),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _detailInfoTile(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.42,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.54),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: cs.onSurface.withValues(alpha: 0.82),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hourFortuneRow(
    BuildContext context,
    List<AlmanacHourFortune> fortunes, {
    required bool isLast,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.16 : 0.34,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '时辰吉凶',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.54),
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 6.0;
              final columns = constraints.maxWidth >= 520
                  ? 4
                  : constraints.maxWidth >= 330
                  ? 3
                  : 2;
              final itemWidth =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: fortunes
                    .map(
                      (fortune) =>
                          _hourFortuneBlock(context, fortune, width: itemWidth),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _hourFortuneBlock(
    BuildContext context,
    AlmanacHourFortune fortune, {
    required double width,
  }) {
    final cs = Theme.of(context).colorScheme;
    final color = fortune.isAuspicious
        ? const Color(0xFF2E7D32)
        : const Color(0xFFC62828);
    return SizedBox(
      width: width,
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.16), width: 0.45),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${fortune.branch}时',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.86),
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ),
                Text(
                  fortune.isAuspicious ? '吉' : '凶',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              fortune.range,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.58),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${fortune.ganzhi} ${fortune.deity}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.72),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _yijiCard({
    required String title,
    required String body,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 0.45),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              body,
              style: TextStyle(
                fontSize: 13,
                color: color.withValues(alpha: 0.86),
                height: 1.45,
              ),
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
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                '本月重点日期',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.normal,
                  color: cs.onSurface.withValues(alpha: 0.78),
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
                '本月暂无重点日期',
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
                children: highlights
                    .take(12)
                    .map(
                      (highlight) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 34,
                              child: Text(
                                '${highlight.date.day}',
                                style: appSecondaryControlTextStyle(context)
                                    .copyWith(
                                      fontSize: 13,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.64,
                                      ),
                                    ),
                              ),
                            ),
                            Expanded(
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: highlight.labels.take(3).map((label) {
                                  return _SoftAlmanacTag(label: label);
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          if (highlights.length > 12)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '还有 ${highlights.length - 12} 个重点日期',
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

class _SoftAlmanacTag extends StatelessWidget {
  final _HighlightLabel label;

  const _SoftAlmanacTag({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = Color.lerp(label.color, cs.onSurface, 0.28) ?? label.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(label.icon, size: 12, color: color.withValues(alpha: 0.82)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: appSecondaryControlLabelStyle(
                context,
              ).copyWith(color: cs.onSurface.withValues(alpha: 0.70)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedDateSummaryCard extends StatelessWidget {
  final LunarAlmanacDetail detail;
  final List<(String, Color)> badges;
  final VoidCallback onTap;

  const _SelectedDateSummaryCard({
    required this.detail,
    required this.badges,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = Color.alphaBlend(
      cs.primary.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.08 : 0.045,
      ),
      cs.surface,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 13),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
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
                          detail.lunarDate.chineseText,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontSize: 17,
                                fontWeight: FontWeight.normal,
                                color: cs.onSurface,
                              ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _spacedGanzhiLine(detail.ganzhiLine),
                          style: appSecondaryControlTextStyle(context).copyWith(
                            color: cs.onSurface.withValues(alpha: 0.62),
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: cs.surface.withValues(alpha: 0.76),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: cs.onSurface.withValues(alpha: 0.46),
                    ),
                  ),
                ],
              ),
              if (badges.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: badges
                      .map(
                        (badge) =>
                            _AlmanacBadge(text: badge.$1, color: badge.$2),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.32
                        : 0.62,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    _SummaryYijiLine(
                      label: '宜',
                      text: _summaryTerms(detail.suitable),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Divider(
                        height: 1,
                        thickness: 0.45,
                        color: cs.outlineVariant.withValues(alpha: 0.20),
                      ),
                    ),
                    _SummaryYijiLine(
                      label: '忌',
                      text: _summaryTerms(detail.avoid),
                    ),
                  ],
                ),
              ),
            ],
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
    final color = label == '宜'
        ? const Color(0xFF2E7D32)
        : const Color(0xFFC62828);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
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
              color: cs.onSurface.withValues(alpha: 0.76),
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _AlmanacDetailSheet extends StatelessWidget {
  final LunarAlmanacDetail detail;
  final List<(String, Color)> badges;
  final List<String> weekNames;
  final Widget Function({required String suitable, required String avoid})
  yijiRow;
  final Widget Function(BuildContext context, LunarAlmanacDetail detail)
  detailRows;

  const _AlmanacDetailSheet({
    required this.detail,
    required this.badges,
    required this.weekNames,
    required this.yijiRow,
    required this.detailRows,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayDate = detail.solarDate;
    final fullDate =
        '${displayDate.year}年${displayDate.month}月${displayDate.day}日 星期${weekNames[displayDate.weekday - 1]}';
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
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
                          fullDate,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.normal,
                                color: cs.onSurface,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${detail.lunarDate.chineseText}  ${_spacedGanzhiLine(detail.ganzhiLine)}',
                          style: appSecondaryControlTextStyle(context).copyWith(
                            color: cs.onSurface.withValues(alpha: 0.64),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (badges.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: badges
                      .map(
                        (badge) =>
                            _AlmanacBadge(text: badge.$1, color: badge.$2),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 14),
              yijiRow(suitable: detail.suitable, avoid: detail.avoid),
              const SizedBox(height: 12),
              detailRows(context, detail),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlmanacBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _AlmanacBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.normal,
        ),
      ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  final DateTime date;
  final Set<int> highlightDays;
  final List<_MonthHighlight> highlights;
  final ValueChanged<DateTime> onPick;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onTitleTap;

  const _MonthCalendar({
    required this.date,
    required this.highlightDays,
    required this.highlights,
    required this.onPick,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onTitleTap,
  });

  @override
  Widget build(BuildContext context) {
    final first = DateTime(date.year, date.month, 1);
    final last = DateTime(date.year, date.month + 1, 0);
    final offset = first.weekday - 1; // 周一为 0
    final cs = Theme.of(context).colorScheme;

    final highlightByDay = {for (final item in highlights) item.date.day: item};
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 4),
          child: Row(
            children: [
              _MonthNavButton(
                tooltip: '上个月',
                icon: Icons.chevron_left,
                onPressed: onPreviousMonth,
              ),
              Expanded(
                child: GestureDetector(
                  onTap: onTitleTap,
                  child: Column(
                    children: [
                      Text(
                        '${date.month}月',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 24,
                          fontWeight: FontWeight.normal,
                          letterSpacing: 0,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${date.year}年',
                        style: appSecondaryControlLabelStyle(
                          context,
                        ).copyWith(color: cs.onSurface.withValues(alpha: 0.48)),
                      ),
                    ],
                  ),
                ),
              ),
              _MonthNavButton(
                tooltip: '下个月',
                icon: Icons.chevron_right,
                onPressed: onNextMonth,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: const ['一', '二', '三', '四', '五', '六', '日']
              .map(
                (d) => Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: TextStyle(
                        fontSize: 11,
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
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: List.generate(7, (col) {
                final d = row * 7 + col - offset + 1;
                if (d < 1 || d > last.day) {
                  return const Expanded(child: SizedBox(height: 48));
                }
                final day = DateTime(date.year, date.month, d);
                final lunar = I18n.current == AppLocale.zh
                    ? LunarCalendar.fromSolar(day)
                    : null;
                final term = LunarCalendar.solarTerm(day);
                final solarFestival = LunarCalendar.solarFestival(day);
                final lunarFestival = lunar == null
                    ? null
                    : LunarCalendar.lunarFestival(lunar);
                final dayLabel =
                    term ??
                    solarFestival ??
                    lunarFestival ??
                    lunar?.shortDayOrMonth ??
                    '';
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
                final highlight = highlightByDay[d];
                final isWeekend = day.weekday >= DateTime.saturday;
                final isHoliday = HolidayCalendar.isHoliday(day);
                final isWorkMakeupDay = HolidayCalendar.isWorkMakeupDay(day);
                final selectedFill = Color.alphaBlend(
                  cs.primary.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.18
                        : 0.11,
                  ),
                  cs.surface,
                );
                final selectedText = cs.onSurface;
                final festivalColor = Color.lerp(
                  const Color(0xFFEF6C00),
                  cs.onSurface,
                  Theme.of(context).brightness == Brightness.dark ? 0.20 : 0.30,
                )!;
                final termColor = Color.lerp(
                  const Color(0xFF2E7D32),
                  cs.onSurface,
                  Theme.of(context).brightness == Brightness.dark ? 0.20 : 0.24,
                )!;
                final restColor = Color.lerp(
                  const Color(0xFFC62828),
                  cs.onSurface,
                  0.28,
                )!;
                final workColor = Color.lerp(
                  const Color(0xFF5E35B1),
                  cs.onSurface,
                  0.30,
                )!;

                return Expanded(
                  child: GestureDetector(
                    onTap: () => onPick(day),
                    child: Container(
                      height: 48,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? selectedFill
                            : isToday
                            ? cs.primary.withValues(alpha: 0.055)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: isSelected
                            ? Border.all(
                                color: cs.primary.withValues(alpha: 0.20),
                                width: 0.45,
                              )
                            : null,
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$d',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.normal,
                                    color: isSelected
                                        ? selectedText
                                        : isWorkMakeupDay
                                        ? workColor
                                        : isHoliday || isWeekend
                                        ? restColor
                                        : (isToday
                                              ? cs.primary
                                              : cs.onSurface.withValues(
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
                                    fontSize: 9,
                                    color: isSelected
                                        ? selectedText.withValues(alpha: 0.60)
                                        : term != null
                                        ? termColor
                                        : solarFestival != null ||
                                              lunarFestival != null
                                        ? festivalColor
                                        : cs.onSurface.withValues(alpha: 0.42),
                                  ),
                                ),
                                if (hasHighlight)
                                  Container(
                                    width: 3.5,
                                    height: 3.5,
                                    margin: const EdgeInsets.only(top: 3),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? selectedText.withValues(alpha: 0.70)
                                          : cs.primary.withValues(alpha: 0.58),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (isHoliday || isWorkMakeupDay)
                            Positioned(
                              top: 3,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      (isWorkMakeupDay ? workColor : restColor)
                                          .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  isWorkMakeupDay ? '班' : '休',
                                  style: TextStyle(
                                    color:
                                        (isWorkMakeupDay
                                                ? workColor
                                                : restColor)
                                            .withValues(alpha: 0.82),
                                    fontSize: 8,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                          if (highlight != null && highlight.labels.length > 1)
                            Positioned(
                              bottom: 4,
                              right: 5,
                              child: Text(
                                '+${highlight.labels.length - 1}',
                                style: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.34),
                                  fontSize: 8,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        }),
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
        minimumSize: const Size(34, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: cs.onSurface.withValues(alpha: 0.62),
        backgroundColor: cs.surface.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.20 : 0.58,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
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
