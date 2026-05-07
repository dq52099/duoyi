import 'package:flutter/material.dart';
import '../models/recurrence.dart';

/// 重复规则编辑弹出层。
class RecurrencePicker extends StatefulWidget {
  final RecurrenceRule initial;
  const RecurrencePicker({super.key, required this.initial});

  static Future<RecurrenceRule?> show(
    BuildContext context, {
    required RecurrenceRule initial,
  }) {
    return showModalBottomSheet<RecurrenceRule>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RecurrencePicker(initial: initial),
    );
  }

  @override
  State<RecurrencePicker> createState() => _RecurrencePickerState();
}

class _RecurrencePickerState extends State<RecurrencePicker> {
  late RecurrenceFrequency _freq;
  late int _interval;
  late List<int> _weekdays;
  int? _byMonthDay;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _freq = widget.initial.frequency;
    _interval = widget.initial.interval;
    _weekdays = [...?widget.initial.byWeekdays];
    _byMonthDay = widget.initial.byMonthDay;
    _endDate = widget.initial.endDate;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('重复',
              style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            children: [
              for (final f in RecurrenceFrequency.values)
                ChoiceChip(
                  label: Text(_freqLabel(f)),
                  selected: _freq == f,
                  onSelected: (_) => setState(() => _freq = f),
                ),
            ],
          ),
          if (_freq != RecurrenceFrequency.none) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('每'),
                SizedBox(
                  width: 72,
                  child: TextField(
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(text: '$_interval'),
                    decoration: const InputDecoration(isDense: true),
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      if (n != null && n > 0) _interval = n;
                    },
                  ),
                ),
                Text(' ${_unitLabel(_freq)}'),
              ],
            ),
          ],
          if (_freq == RecurrenceFrequency.weekly) ...[
            const SizedBox(height: 12),
            const Text('每周哪几天',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: List.generate(7, (i) {
                const names = ['一', '二', '三', '四', '五', '六', '日'];
                final selected = _weekdays.contains(i);
                return FilterChip(
                  label: Text(names[i]),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: (_) => setState(() {
                    if (selected) {
                      _weekdays.remove(i);
                    } else {
                      _weekdays.add(i);
                    }
                  }),
                );
              }),
            ),
          ],
          if (_freq == RecurrenceFrequency.monthly) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('每月第几天 '),
                SizedBox(
                  width: 72,
                  child: TextField(
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(
                        text: _byMonthDay?.toString() ?? ''),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '留空=同日',
                    ),
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      if (n != null && n >= 1 && n <= 31) _byMonthDay = n;
                      if (v.isEmpty) _byMonthDay = null;
                    },
                  ),
                ),
                const Text(' 日'),
              ],
            ),
          ],
          if (_freq != RecurrenceFrequency.none) ...[
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.event_busy, size: 18),
              title: const Text('结束日期 (可选)'),
              subtitle: Text(
                _endDate == null
                    ? '永不结束'
                    : '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}',
              ),
              trailing: _endDate == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _endDate = null),
                    ),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _endDate ??
                      DateTime.now().add(const Duration(days: 90)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime(2099, 12, 31),
                );
                if (picked != null) setState(() => _endDate = picked);
              },
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, const RecurrenceRule()),
                child: const Text('清除'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  RecurrenceRule(
                    frequency: _freq,
                    interval: _interval < 1 ? 1 : _interval,
                    byWeekdays:
                        _freq == RecurrenceFrequency.weekly && _weekdays.isNotEmpty
                            ? [..._weekdays]
                            : null,
                    byMonthDay: _freq == RecurrenceFrequency.monthly
                        ? _byMonthDay
                        : null,
                    endDate: _endDate,
                  ),
                ),
                child: const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _freqLabel(RecurrenceFrequency f) => switch (f) {
        RecurrenceFrequency.none => '不重复',
        RecurrenceFrequency.daily => '每天',
        RecurrenceFrequency.weekly => '每周',
        RecurrenceFrequency.monthly => '每月',
        RecurrenceFrequency.yearly => '每年',
      };

  String _unitLabel(RecurrenceFrequency f) => switch (f) {
        RecurrenceFrequency.daily => '天',
        RecurrenceFrequency.weekly => '周',
        RecurrenceFrequency.monthly => '月',
        RecurrenceFrequency.yearly => '年',
        RecurrenceFrequency.none => '',
      };
}
