import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../core/design_tokens.dart';
import '../core/lunar_calendar.dart';
import 'surface_components.dart';

enum AppDatePickerMode { solar, lunar }

class AppDatePickerResult {
  final DateTime date;
  final AppDatePickerMode mode;
  final bool ignoreYear;

  const AppDatePickerResult({
    required this.date,
    required this.mode,
    this.ignoreYear = false,
  });

  String get solarText =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String get lunarText {
    final lunar = LunarCalendar.fromSolar(date);
    return '${LunarCalendar.ganzhiOf(lunar.year)}年（${date.year}）${lunar.chineseText}';
  }
}

class AppDatePicker {
  AppDatePicker._();

  static Future<DateTime?> pickSolar(
    BuildContext context, {
    required DateTime initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
    String title = '选择日期',
    String? subtitle,
  }) async {
    final result = await show(
      context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      title: title,
      subtitle: subtitle,
      initialMode: AppDatePickerMode.solar,
    );
    return result?.date;
  }

  static Future<AppDatePickerResult?> show(
    BuildContext context, {
    required DateTime initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
    String title = '选择日期',
    String? subtitle,
    AppDatePickerMode initialMode = AppDatePickerMode.solar,
    bool allowIgnoreYear = false,
  }) {
    return showAppModalSheet<AppDatePickerResult>(
      context: context,
      builder: (_) => _AppDatePickerSheet(
        initialDate: initialDate,
        firstDate: firstDate ?? DateTime(1900),
        lastDate: lastDate ?? DateTime(2099, 12, 31),
        title: title,
        subtitle: subtitle,
        initialMode: initialMode,
        allowIgnoreYear: allowIgnoreYear,
      ),
    );
  }
}

class _AppDatePickerSheet extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;
  final String? subtitle;
  final AppDatePickerMode initialMode;
  final bool allowIgnoreYear;

  const _AppDatePickerSheet({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.title,
    required this.subtitle,
    required this.initialMode,
    required this.allowIgnoreYear,
  });

  @override
  State<_AppDatePickerSheet> createState() => _AppDatePickerSheetState();
}

class _AppDatePickerSheetState extends State<_AppDatePickerSheet> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  late AppDatePickerMode _mode;
  late LunarDate _lunar;
  bool _ignoreYear = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = _clamp(widget.initialDate);
    _focusedDay = _selectedDay;
    _mode = widget.initialMode;
    _lunar = LunarCalendar.fromSolar(_selectedDay);
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
      _lunar = LunarCalendar.fromSolar(_selectedDay);
    });
  }

  void _setLunar({int? year, int? month, int? day}) {
    final nextYear = year ?? _lunar.year;
    final nextMonth = month ?? _lunar.month;
    final maxDay = LunarCalendar.daysInMonth(
      nextYear,
      nextMonth,
      isLeap: _lunar.isLeapMonth,
    );
    final nextDay = (day ?? _lunar.day).clamp(1, maxDay).toInt();
    final solar = LunarCalendar.toSolar(nextYear, nextMonth, nextDay);
    setState(() {
      _selectedDay = _clamp(solar);
      _focusedDay = DateTime(_selectedDay.year, _selectedDay.month);
      _lunar = LunarCalendar.fromSolar(_selectedDay);
    });
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
      title: widget.title,
      subtitle: widget.subtitle,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, result),
          child: const Text('确定'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<AppDatePickerMode>(
            segments: const [
              ButtonSegment(
                value: AppDatePickerMode.solar,
                icon: Icon(Icons.calendar_month_outlined),
                label: Text('公历'),
              ),
              ButtonSegment(
                value: AppDatePickerMode.lunar,
                icon: Icon(Icons.brightness_2_outlined),
                label: Text('农历'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.32),
              borderRadius: DesignTokens.borderRadiusLg,
              border: Border.all(color: cs.primary.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                Icon(Icons.event_available_outlined, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${result.solarText}  ·  ${result.lunarText}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface,
                    ),
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
              title: const Text('忽略年份'),
              subtitle: const Text('适合生日、纪念日每年重复'),
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
          else
            _LunarPicker(lunar: _lunar, onChanged: _setLunar),
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TableCalendar<void>(
      locale: 'zh_CN',
      firstDay: firstDay,
      lastDay: lastDay,
      focusedDay: focusedDay,
      selectedDayPredicate: (day) => isSameDay(day, selectedDay),
      rowHeight: 42,
      daysOfWeekHeight: 26,
      calendarFormat: CalendarFormat.month,
      availableCalendarFormats: const {CalendarFormat.month: '月'},
      headerStyle: HeaderStyle(
        titleCentered: true,
        formatButtonVisible: false,
        leftChevronIcon: const Icon(Icons.chevron_left_rounded),
        rightChevronIcon: const Icon(Icons.chevron_right_rounded),
        titleTextStyle:
            Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w400) ??
            const TextStyle(fontSize: 16),
      ),
      calendarStyle: CalendarStyle(
        todayDecoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        todayTextStyle: TextStyle(color: cs.primary),
        selectedDecoration: BoxDecoration(
          color: cs.primary,
          shape: BoxShape.circle,
        ),
      ),
      onDaySelected: (selected, _) => onDaySelected(selected),
      onPageChanged: onPageChanged,
    );
  }
}

class _LunarPicker extends StatelessWidget {
  final LunarDate lunar;
  final void Function({int? year, int? month, int? day}) onChanged;

  const _LunarPicker({required this.lunar, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _NumberWheel(
            value: lunar.year,
            min: 1900,
            max: 2099,
            labelBuilder: (v) => '${LunarCalendar.ganzhiOf(v)}年（$v）',
            onChanged: (v) => onChanged(year: v),
          ),
        ),
        Expanded(
          child: _NumberWheel(
            value: lunar.month,
            min: 1,
            max: 12,
            labelBuilder: (v) => LunarCalendar.monthName(v),
            onChanged: (v) => onChanged(month: v),
          ),
        ),
        Expanded(
          child: _NumberWheel(
            value: lunar.day,
            min: 1,
            max: LunarCalendar.daysInMonth(lunar.year, lunar.month),
            labelBuilder: (v) => LunarCalendar.dayName(v),
            onChanged: (v) => onChanged(day: v),
          ),
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
            return Center(
              child: Text(
                widget.labelBuilder(value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurface),
              ),
            );
          },
        ),
      ),
    );
  }
}
