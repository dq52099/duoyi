import 'package:flutter/material.dart';
import '../core/i18n.dart';
import '../core/lunar_calendar.dart';
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
            );
            final miniMonth = _MiniMonth(
              date: _date,
              onPick: (d) => setState(() => _date = _clampDate(d)),
            );
            final yiji = _yijiRow(suitable: suitable, avoid: avoid);
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
                          fontWeight: FontWeight.w400,
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
                fontWeight: FontWeight.w400,
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
    return Column(
      children: [
        _yijiCard(title: '宜', body: suitable, color: const Color(0xFF66BB6A)),
        const SizedBox(height: 10),
        _yijiCard(title: '忌', body: avoid, color: const Color(0xFFEF5350)),
      ],
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

  const _DateDetailCard({
    required this.date,
    required this.lunarText,
    required this.ganzhi,
    required this.zodiac,
    required this.solarTerm,
    required this.solarFestival,
    required this.lunarFestival,
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
                  fontWeight: FontWeight.w400,
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
  final ValueChanged<DateTime> onPick;
  const _MiniMonth({required this.date, required this.onPick});

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
                          fontWeight: FontWeight.w400,
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
                              fontWeight: FontWeight.w400,
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
