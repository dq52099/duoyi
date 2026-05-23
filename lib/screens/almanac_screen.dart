import 'package:flutter/material.dart';
import '../core/i18n.dart';
import '../core/lunar_calendar.dart';
import '../widgets/app_date_picker.dart';

enum AlmanacEntryMode { calendar, almanac }

/// 黄历与万年历共用日期算法，但入口默认侧重点不同。
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

  void _toggleMode() {
    final nextMode = widget.initialMode == AlmanacEntryMode.almanac
        ? AlmanacEntryMode.calendar
        : AlmanacEntryMode.almanac;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AlmanacScreen(initialDate: _date, initialMode: nextMode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAlmanac = widget.initialMode == AlmanacEntryMode.almanac;
    final pageTitle = isAlmanac ? '黄历' : '万年历';
    final lunar = LunarCalendar.fromSolar(_date);
    final zodiac = LunarCalendar.zodiacOf(lunar.year);
    final ganzhi = LunarCalendar.ganzhiOf(lunar.year);
    final term = LunarCalendar.solarTerm(_date);
    final solarFes = LunarCalendar.solarFestival(_date);
    final lunarFes = LunarCalendar.lunarFestival(lunar);
    final suitable = LunarCalendar.suitable(_date);
    final avoid = LunarCalendar.avoid(_date);
    final weekNames = ['一', '二', '三', '四', '五', '六', '日'];
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(pageTitle),
        actions: [
          IconButton(
            icon: Icon(
              isAlmanac
                  ? Icons.calendar_month_outlined
                  : Icons.wb_sunny_outlined,
            ),
            tooltip: isAlmanac ? '切换到万年历' : '切换到黄历',
            onPressed: _toggleMode,
          ),
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: '回到今天',
            onPressed: () => setState(() => _date = _clampDate(DateTime.now())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
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
                      icon: const Icon(
                        Icons.chevron_right,
                        color: Colors.white,
                      ),
                      onPressed: _date == _lastSupportedDate
                          ? null
                          : () => _shift(1),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    _chip(
                      '${I18n.tr('calendar.chinese_lunar_calendar')} ${lunar.chineseText}',
                    ),
                    if (I18n.current == AppLocale.zh)
                      _chip('$ganzhi · 属$zodiac'),
                    if (term != null) _chip('🌿 $term'),
                    if (solarFes != null) _chip('🎉 $solarFes'),
                    if (lunarFes != null && I18n.current == AppLocale.zh)
                      _chip('🏮 $lunarFes'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (isAlmanac) ...[
            _yijiRow(suitable: suitable, avoid: avoid),
            const SizedBox(height: 16),
            _MiniMonth(
              date: _date,
              onPick: (d) => setState(() => _date = _clampDate(d)),
            ),
          ] else ...[
            _MiniMonth(
              date: _date,
              onPick: (d) => setState(() => _date = _clampDate(d)),
            ),
            const SizedBox(height: 16),
            _yijiRow(suitable: suitable, avoid: avoid),
          ],
          const SizedBox(height: 16),
          Container(
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
                    isAlmanac
                        ? '宜忌仅供娱乐参考，农历与节气覆盖 1900-2099 年。'
                        : '万年历覆盖 1900-2099 年，支持公历、农历与节气查看。',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ),
        ],
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
        border: Border.all(color: color.withValues(alpha: 0.15)),
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
    return Row(
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
        border: Border.all(color: Colors.grey.shade200),
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

                return Expanded(
                  child: GestureDetector(
                    onTap: () => onPick(day),
                    child: Container(
                      height: 42,
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? cs.primary
                            : (isToday
                                  ? cs.primary.withValues(alpha: 0.1)
                                  : null),
                        borderRadius: BorderRadius.circular(8),
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
                                  ? cs.onPrimary
                                  : (isToday ? cs.primary : null),
                            ),
                          ),
                          if (lunar != null)
                            Text(
                              lunar.shortDayOrMonth,
                              style: TextStyle(
                                fontSize: 9,
                                color: isSelected
                                    ? cs.onPrimary.withValues(alpha: 0.8)
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
