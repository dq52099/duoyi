import 'package:flutter/material.dart';
import '../core/i18n.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../models/time_entry.dart';
import '../providers/time_audit_provider.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/app_time_picker.dart';
import '../widgets/surface_components.dart';

enum _AuditRange { today, week, month, all }

class TimeAuditScreen extends StatefulWidget {
  const TimeAuditScreen({super.key});

  @override
  State<TimeAuditScreen> createState() => _TimeAuditScreenState();
}

class _TimeAuditScreenState extends State<TimeAuditScreen> {
  _AuditRange _range = _AuditRange.today;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TimeAuditProvider>();
    final entries = _entriesFor(provider);
    final totalSeconds = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.durationSeconds,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('时间足迹')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('补记'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _SummaryCard(
            rangeLabel: _rangeLabel(_range),
            totalSeconds: totalSeconds,
            entries: entries,
          ),
          const SizedBox(height: 10),
          SegmentedButton<_AuditRange>(
            segments: const [
              ButtonSegment(value: _AuditRange.today, label: Text('今天')),
              ButtonSegment(value: _AuditRange.week, label: Text('本周')),
              ButtonSegment(value: _AuditRange.month, label: Text('本月')),
              ButtonSegment(value: _AuditRange.all, label: Text('全部')),
            ],
            selected: {_range},
            onSelectionChanged: (value) => setState(() => _range = value.first),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            AppSurfaceCard(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
              child: Column(
                children: [
                  Icon(
                    Icons.timeline_outlined,
                    size: 42,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.32),
                  ),
                  const SizedBox(height: 10),
                  Text('${_rangeLabel(_range)}暂无时间记录'),
                ],
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
              child: Text(
                '${_rangeLabel(_range)}时间线',
                style: const TextStyle(
                  fontWeight: FontWeight.w400,
                  fontSize: 13,
                ),
              ),
            ),
            for (final entry in entries) ...[
              _TimeEntryCard(
                entry: entry,
                onTap: () => _showEditor(context, entry: entry),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }

  void _showEditor(BuildContext context, {TimeEntry? entry}) {
    showAppModalSheet(
      context: context,
      builder: (_) => _TimeEntrySheet(entry: entry),
    );
  }

  List<TimeEntry> _entriesFor(TimeAuditProvider provider) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);
    return switch (_range) {
      _AuditRange.today => provider.entriesInRange(
        todayStart,
        todayStart.add(const Duration(days: 1)),
      ),
      _AuditRange.week => provider.entriesInRange(
        weekStart,
        weekStart.add(const Duration(days: 7)),
      ),
      _AuditRange.month => provider.entriesInRange(
        monthStart,
        DateTime(now.year, now.month + 1, 1),
      ),
      _AuditRange.all => provider.entries,
    };
  }

  String _rangeLabel(_AuditRange range) => switch (range) {
    _AuditRange.today => '今日',
    _AuditRange.week => '本周',
    _AuditRange.month => '本月',
    _AuditRange.all => '全部',
  };
}

class _SummaryCard extends StatelessWidget {
  final String rangeLabel;
  final int totalSeconds;
  final List<TimeEntry> entries;

  const _SummaryCard({
    required this.rangeLabel,
    required this.totalSeconds,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final byCategory = <TimeEntryCategory, int>{};
    for (final entry in entries) {
      byCategory[entry.category] =
          (byCategory[entry.category] ?? 0) + entry.durationSeconds;
    }
    final categories = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return AppSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _MetricBlock(
                  title: '$rangeLabel投入',
                  value: _formatDuration(totalSeconds),
                  icon: Icons.timelapse_outlined,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricBlock(
                  title: '记录数',
                  value: '${entries.length} 条',
                  icon: Icons.list_alt_outlined,
                  color: const Color(0xFF26A69A),
                ),
              ),
            ],
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final entry in categories.take(4))
              _CategoryShareRow(
                category: entry.key,
                seconds: entry.value,
                totalSeconds: totalSeconds,
              ),
          ],
        ],
      ),
    );
  }
}

class _MetricBlock extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricBlock({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w400,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withValues(alpha: 0.62),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryShareRow extends StatelessWidget {
  final TimeEntryCategory category;
  final int seconds;
  final int totalSeconds;

  const _CategoryShareRow({
    required this.category,
    required this.seconds,
    required this.totalSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(category);
    final ratio = totalSeconds <= 0 ? 0.0 : seconds / totalSeconds;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            child: Text(
              category.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 7,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 54,
            child: Text(
              _formatDuration(seconds),
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeEntryCard extends StatelessWidget {
  final TimeEntry entry;
  final VoidCallback onTap;

  const _TimeEntryCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(entry.category);
    return AppSurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_iconFor(entry.category), color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w400,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatDateTime(entry.startAt)} - ${_formatDateTime(entry.endAt)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.62),
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _Chip(text: entry.category.label),
                    _Chip(text: entry.source.label),
                    _Chip(text: _formatDuration(entry.durationSeconds)),
                    if (entry.note.isNotEmpty) _Chip(text: entry.note),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => context.read<TimeAuditProvider>().delete(entry.id),
          ),
        ],
      ),
    );
  }
}

class _TimeEntrySheet extends StatefulWidget {
  final TimeEntry? entry;

  const _TimeEntrySheet({this.entry});

  @override
  State<_TimeEntrySheet> createState() => _TimeEntrySheetState();
}

class _TimeEntrySheetState extends State<_TimeEntrySheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _noteCtrl;
  late final TextEditingController _minutesCtrl;
  late TimeEntryCategory _category;
  late DateTime _startAt;
  late DateTime _endAt;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _titleCtrl = TextEditingController(text: entry?.title ?? '时间记录');
    _noteCtrl = TextEditingController(text: entry?.note ?? '');
    _minutesCtrl = TextEditingController(
      text: entry == null
          ? '25'
          : (entry.durationSeconds ~/ 60).clamp(1, 1440).toString(),
    );
    _category = entry?.category ?? TimeEntryCategory.focus;
    _startAt = entry?.startAt ?? DateTime.now();
    _endAt = entry?.endAt ?? DateTime.now().add(const Duration(minutes: 25));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    _minutesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppModalSheet(
      title: widget.entry == null ? '补记时间' : '编辑时间',
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(I18n.tr('action.cancel')),
        ),
        FilledButton(onPressed: _save, child: Text(I18n.tr('action.save'))),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: '标题',
              prefixIcon: Icon(Icons.title, size: 20),
            ),
          ),
          const SizedBox(height: DesignTokens.spaceMd),
          AppDropdownField<TimeEntryCategory>(
            initialValue: _category,
            labelText: '分类',
            prefixIcon: const Icon(Icons.label_outline, size: 20),
            items: [
              for (final c in TimeEntryCategory.values)
                DropdownMenuItem(value: c, child: Text(c.label)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _category = v);
            },
          ),
          const SizedBox(height: DesignTokens.spaceMd),
          Row(
            children: [
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.play_arrow),
                  title: const Text('开始'),
                  subtitle: Text(_formatDateTime(_startAt)),
                  onTap: _pickStart,
                ),
              ),
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.stop),
                  title: const Text('结束'),
                  subtitle: Text(_formatDateTime(_endAt)),
                  onTap: _pickEnd,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spaceSm),
          TextField(
            controller: _minutesCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: '分钟数'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: DesignTokens.spaceSm),
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(labelText: '备注'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickStart() async {
    final date = await AppDatePicker.pickSolar(
      context,
      initialDate: _startAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      title: '开始日期',
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await AppTimePicker.show(
      context,
      initialTime: TimeOfDay.fromDateTime(_startAt),
      title: '开始时间',
      minuteStep: 5,
    );
    if (time == null) return;
    if (!mounted) return;
    setState(() {
      _startAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      final minutes = int.tryParse(_minutesCtrl.text.trim()) ?? 25;
      _endAt = _startAt.add(Duration(minutes: minutes));
    });
  }

  Future<void> _pickEnd() async {
    final date = await AppDatePicker.pickSolar(
      context,
      initialDate: _endAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      title: '结束日期',
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await AppTimePicker.show(
      context,
      initialTime: TimeOfDay.fromDateTime(_endAt),
      title: '结束时间',
      minuteStep: 5,
    );
    if (time == null) return;
    if (!mounted) return;
    setState(
      () => _endAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _save() async {
    final provider = context.read<TimeAuditProvider>();
    final minutes = int.tryParse(_minutesCtrl.text.trim()) ?? 0;
    final endAt = _endAt.isAfter(_startAt)
        ? _endAt
        : _startAt.add(Duration(minutes: minutes <= 0 ? 1 : minutes));
    final entry = TimeEntry(
      id: widget.entry?.id,
      title: _titleCtrl.text.trim().isEmpty ? '时间记录' : _titleCtrl.text.trim(),
      startAt: _startAt,
      endAt: endAt,
      category: _category,
      source: TimeEntrySource.manual,
      note: _noteCtrl.text.trim(),
      createdAt: widget.entry?.createdAt,
    );
    if (widget.entry == null) {
      await provider.add(entry);
    } else {
      await provider.update(entry);
    }
    if (!mounted) return;
    Navigator.pop(context);
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }
}

String _formatDateTime(DateTime d) =>
    '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _formatDuration(int seconds) {
  if (seconds >= 3600) {
    return '${(seconds / 3600).toStringAsFixed(seconds % 3600 == 0 ? 0 : 1)} 小时';
  }
  return '${(seconds / 60).toStringAsFixed(seconds % 60 == 0 ? 0 : 1)} 分钟';
}

Color _colorFor(TimeEntryCategory category) => switch (category) {
  TimeEntryCategory.focus => const Color(0xFFE53935),
  TimeEntryCategory.todo => const Color(0xFF42A5F5),
  TimeEntryCategory.habit => const Color(0xFF66BB6A),
  TimeEntryCategory.goal => const Color(0xFFAB47BC),
  TimeEntryCategory.study => const Color(0xFF26A69A),
  TimeEntryCategory.work => const Color(0xFFFF9800),
  TimeEntryCategory.life => const Color(0xFF8D6E63),
  TimeEntryCategory.other => const Color(0xFF78909C),
};

IconData _iconFor(TimeEntryCategory category) => switch (category) {
  TimeEntryCategory.focus => Icons.timer_outlined,
  TimeEntryCategory.todo => Icons.check_circle_outline,
  TimeEntryCategory.habit => Icons.repeat,
  TimeEntryCategory.goal => Icons.flag_outlined,
  TimeEntryCategory.study => Icons.menu_book_outlined,
  TimeEntryCategory.work => Icons.work_outline,
  TimeEntryCategory.life => Icons.favorite_outline,
  TimeEntryCategory.other => Icons.more_horiz,
};
