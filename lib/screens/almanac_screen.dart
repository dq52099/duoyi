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
            onPressed: _date == _firstSupportedDate ? null : () => _shiftDay(-1),
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
                padding: EdgeInsets.all(wide ? 20 : 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1160),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        monthCalendar,
                        SizedBox(height: wide ? 18 : 14),
                        summary,
                        SizedBox(height: wide ? 18 : 14),
                        highlights,
                        const SizedBox(height: 14),
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
        for (var i = 0; i < rows.length; i++)
          _detailRow(
            context,
            label: rows[i].$1,
            value: rows[i].$2,
            isLast: false,
          ),
        _hourFortuneRow(context, detail.hourFortuneItems, isLast: true),
      ],
    );
  }

  Widget _detailRow(
    BuildContext context, {
    required String label,
    required String value,
    required bool isLast,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast
                ? Colors.transparent
                : cs.outlineVariant.withValues(alpha: 0.18),
            width: 0.45,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.54),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: cs.onSurface.withValues(alpha: 0.82),
              ),
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast
                ? Colors.transparent
                : cs.outlineVariant.withValues(alpha: 0.18),
            width: 0.45,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 68,
            child: Text(
              '时辰吉凶',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.54),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 6.0;
                final columns = constraints.maxWidth >= 480
                    ? 4
                    : constraints.maxWidth >= 320
                    ? 3
                    : 2;
                final itemWidth =
                    (constraints.maxWidth - spacing * (columns - 1)) / columns;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: fortunes
                      .map(
                        (fortune) => _hourFortuneBlock(
                          context,
                          fortune,
                          width: itemWidth,
                        ),
                      )
                      .toList(),
                );
              },
            ),
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
              '万年历覆盖 1900-2099 年，使用本地农历表与黄历规则生成日期详情。',
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
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      onTap: onTap,
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.normal,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _spacedGanzhiLine(detail.ganzhiLine),
                      style: appSecondaryControlTextStyle(
                        context,
                      ).copyWith(color: cs.onSurface.withValues(alpha: 0.64)),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: cs.onSurface.withValues(alpha: 0.42),
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
                    (badge) => _AlmanacBadge(text: badge.$1, color: badge.$2),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          _SummaryYijiLine(label: '宜', text: _summaryTerms(detail.suitable)),
          const SizedBox(height: 6),
          _SummaryYijiLine(label: '忌', text: _summaryTerms(detail.avoid)),
        ],
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
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
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
            style: appSecondaryControlTextStyle(
              context,
            ).copyWith(color: cs.onSurface.withValues(alpha: 0.78)),
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
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '上个月',
                onPressed: onPreviousMonth,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: onTitleTap,
                  child: Column(
                    children: [
                      Text(
                        '${date.month}月',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.normal,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        '${date.year}年',
                        style: appSecondaryControlLabelStyle(
                          context,
                        ).copyWith(color: cs.onSurface.withValues(alpha: 0.50)),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: '下个月',
                onPressed: onNextMonth,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 6),
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
                        ? 0.20
                        : 0.13,
                  ),
                  cs.surface,
                );
                final selectedText = cs.onSurface;

                return Expanded(
                  child: GestureDetector(
                    onTap: () => onPick(day),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          height: 52,
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? selectedFill
                                : (isToday
                                      ? cs.primary.withValues(alpha: 0.1)
                                      : isHoliday
                                      ? const Color(
                                          0xFFEF5350,
                                        ).withValues(alpha: 0.06)
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
                                      : isWorkMakeupDay
                                      ? const Color(0xFF5E35B1)
                                      : isHoliday || isWeekend
                                      ? const Color(0xFFC62828)
                                      : (isToday ? cs.primary : null),
                                ),
                              ),
                              Text(
                                dayLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: isSelected
                                      ? selectedText.withValues(alpha: 0.64)
                                      : term != null
                                      ? const Color(0xFF2E7D32)
                                      : solarFestival != null ||
                                            lunarFestival != null
                                      ? const Color(0xFFEF6C00)
                                      : cs.onSurface.withValues(alpha: 0.48),
                                ),
                              ),
                              if (hasHighlight)
                                Container(
                                  width: 4,
                                  height: 4,
                                  margin: const EdgeInsets.only(top: 2),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? selectedText
                                        : cs.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (isHoliday || isWorkMakeupDay)
                          Positioned(
                            top: 2,
                            right: 3,
                            child: Text(
                              isWorkMakeupDay ? '班' : '休',
                              style: TextStyle(
                                color: isWorkMakeupDay
                                    ? const Color(0xFF5E35B1)
                                    : const Color(0xFFC62828),
                                fontSize: 9,
                              ),
                            ),
                          ),
                        if (highlight != null && highlight.labels.length > 1)
                          Positioned(
                            bottom: 3,
                            right: 4,
                            child: Text(
                              '+${highlight.labels.length - 1}',
                              style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.42),
                                fontSize: 8,
                              ),
                            ),
                          ),
                      ],
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
