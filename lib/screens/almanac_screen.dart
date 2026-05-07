import 'package:flutter/material.dart';
import '../core/lunar_calendar.dart';

/// 黄历 / 万年历
class AlmanacScreen extends StatefulWidget {
  final DateTime? initialDate;
  const AlmanacScreen({super.key, this.initialDate});

  @override
  State<AlmanacScreen> createState() => _AlmanacScreenState();
}

class _AlmanacScreenState extends State<AlmanacScreen> {
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate ?? DateTime.now();
  }

  void _shift(int days) {
    setState(() => _date = _date.add(Duration(days: days)));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2099, 12, 31),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
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
        title: const Text('黄历 · 万年历'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: '回到今天',
            onPressed: () => setState(() => _date = DateTime.now()),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 主卡：大字公历 + 农历
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
                      icon: const Icon(Icons.chevron_left,
                          color: Colors.white),
                      onPressed: () => _shift(-1),
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
                                fontWeight: FontWeight.w800,
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
                      icon: const Icon(Icons.chevron_right,
                          color: Colors.white),
                      onPressed: () => _shift(1),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    _chip('农历${lunar.chineseText}'),
                    _chip('$ganzhi · 属$zodiac'),
                    if (term != null) _chip('🌿 $term'),
                    if (solarFes != null) _chip('🎉 $solarFes'),
                    if (lunarFes != null) _chip('🏮 $lunarFes'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 宜忌
          Row(
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
          ),
          const SizedBox(height: 16),
          // 小月历
          _MiniMonth(
            date: _date,
            onPick: (d) => setState(() => _date = d),
          ),
          const SizedBox(height: 16),
          // 说明
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 16, color: Colors.orange),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '农历/节气基于通用压缩算法，覆盖 1900-2099 年；宜忌仅供娱乐参考。',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade700),
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

  Widget _yijiCard(
      {required String title, required String body, required Color color}) {
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
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
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
                          fontWeight: FontWeight.w600,
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
                final day =
                    DateTime(date.year, date.month, d);
                final lunar = LunarCalendar.fromSolar(day);
                final isSelected = day.year == date.year &&
                    day.month == date.month &&
                    day.day == date.day;
                final today = DateTime.now();
                final isToday = day.year == today.year &&
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
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? cs.onPrimary
                                  : (isToday ? cs.primary : null),
                            ),
                          ),
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
